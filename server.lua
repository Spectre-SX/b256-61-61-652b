-- server.lua
-- Secure Chat Server for ComputerCraft: Tweaked
-- Place this on a computer with a modem attached, then run: server
--
-- Features:
--  * Account registration (username + password, stored salted+hashed on disk)
--  * Challenge/response authentication over rednet (password never sent in the clear)
--  * Per-session symmetric encryption key derived from the password hash
--  * Relays chat messages between all currently-authenticated clients
--  * Logs every event (connections, auth attempts, messages) to screen + log file

local common = dofile("chat_common.lua")

math.randomseed(os.epoch("utc") + os.getComputerID())

local USERS_FILE = "users.db"
local LOG_FILE = "chat_server.log"

-- ---------- Modem setup ----------
local modemSide = nil
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
        modemSide = side
        break
    end
end
if not modemSide then
    error("No modem attached! Attach a wireless or wired modem to this computer.")
end
rednet.open(modemSide)
rednet.host(common.PROTOCOL, "chat_server")

-- ---------- User database ----------
local users = {} -- users[username] = { hash = <number>, salt = <string> }

local function loadUsers()
    if fs.exists(USERS_FILE) then
        local f = fs.open(USERS_FILE, "r")
        local data = f.readAll()
        f.close()
        local ok, decoded = pcall(textutils.unserialize, data)
        if ok and type(decoded) == "table" then users = decoded end
    end
end

local function saveUsers()
    local f = fs.open(USERS_FILE, "w")
    f.write(textutils.serialize(users))
    f.close()
end

loadUsers()

-- ---------- Logging ----------
local function log(msg)
    local stamp = ("Day %d %s"):format(os.day(), textutils.formatTime(os.time(), true))
    local line = ("[%s] %s"):format(stamp, msg)
    print(line)
    local f = fs.open(LOG_FILE, "a")
    f.write(line .. "\n")
    f.close()
end

-- ---------- Session state ----------
-- sessions[computerId] = { username, key, authenticated, pendingHash, pendingSalt, nonce }
local sessions = {}
local online = {} -- online[username] = computerId

local function send(id, tbl)
    rednet.send(id, textutils.serialize(tbl), common.PROTOCOL)
end

local function broadcastToOthers(exceptId, plainMsg)
    for id, sess in pairs(sessions) do
        if id ~= exceptId and sess.authenticated then
            local nonce = common.randomNonce()
            local enc = common.crypt(plainMsg, sess.key, nonce, false)
            send(id, { type = "chat", nonce = nonce, payload = common.toHex(enc) })
        end
    end
end

log("Server started -- protocol '" .. common.PROTOCOL .. "' on modem side '" .. modemSide .. "'")

-- ---------- Main loop ----------
while true do
    local id, message = rednet.receive(common.PROTOCOL)
    if message then
        local ok, tbl = pcall(textutils.unserialize, message)
        if ok and type(tbl) == "table" then

            -- ===== Registration =====
            if tbl.type == "register" then
                if type(tbl.username) ~= "string" or type(tbl.password) ~= "string" or tbl.username == "" then
                    send(id, { type = "register_fail", reason = "Invalid username/password" })
                elseif users[tbl.username] then
                    send(id, { type = "register_fail", reason = "Username taken" })
                    log(("Registration REJECTED (taken) from #%d: %s"):format(id, tbl.username))
                else
                    local salt = tostring(math.random(1, 1000000000))
                    users[tbl.username] = { hash = common.hashCombine(tbl.password, salt), salt = salt }
                    saveUsers()
                    send(id, { type = "register_ok" })
                    log(("New account registered from #%d: %s"):format(id, tbl.username))
                end

            -- ===== Login step 1: issue challenge =====
            elseif tbl.type == "login" then
                local u = users[tbl.username]
                if not u then
                    send(id, { type = "auth_fail", reason = "No such user" })
                    log(("Auth REJECTED (unknown user) from #%d: %s"):format(id, tostring(tbl.username)))
                else
                    local nonce = common.randomNonce()
                    sessions[id] = {
                        username = tbl.username,
                        pendingHash = u.hash,
                        salt = u.salt,
                        nonce = nonce,
                        authenticated = false,
                    }
                    send(id, { type = "challenge", nonce = nonce, salt = u.salt })
                end

            -- ===== Login step 2: verify challenge response =====
            elseif tbl.type == "auth_response" then
                local sess = sessions[id]
                if not sess or sess.authenticated then
                    send(id, { type = "auth_fail", reason = "No pending login" })
                else
                    local expected = common.toHex(
                        common.crypt(tostring(sess.nonce), sess.pendingHash, sess.nonce, false)
                    )
                    if tbl.response == expected then
                        sess.authenticated = true
                        sess.key = sess.pendingHash
                        online[sess.username] = id
                        send(id, { type = "auth_ok" })
                        log(("AUTH OK: %s connected as #%d"):format(sess.username, id))
                    else
                        log(("AUTH FAILED (bad password) for '%s' from #%d"):format(sess.username, id))
                        send(id, { type = "auth_fail", reason = "Bad credentials" })
                        sessions[id] = nil
                    end
                end

            -- ===== Chat message (must be authenticated) =====
            elseif tbl.type == "chat" then
                local sess = sessions[id]
                if sess and sess.authenticated then
                    local enc = common.fromHex(tbl.payload)
                    local ok2, plain = pcall(common.crypt, enc, sess.key, tbl.nonce, true)
                    if ok2 then
                        log(("<%s> %s"):format(sess.username, plain))
                        broadcastToOthers(id, ("<%s> %s"):format(sess.username, plain))
                    else
                        log(("Failed to decrypt message from '%s' (#%d)"):format(sess.username, id))
                    end
                else
                    send(id, { type = "auth_fail", reason = "Not authenticated" })
                end

            -- ===== Logout =====
            elseif tbl.type == "logout" then
                local sess = sessions[id]
                if sess then
                    log(("%s disconnected (#%d)"):format(sess.username, id))
                    online[sess.username] = nil
                    sessions[id] = nil
                end
            end
        end
    end
end
