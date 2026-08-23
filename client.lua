-- client.lua
-- Secure Chat Client for ComputerCraft: Tweaked
-- Place this on a computer with a modem attached, then run: client

local common = dofile("chat_common.lua")

math.randomseed(os.epoch("utc") + os.getComputerID())

-- ---------- Modem setup ----------
local modemSide = nil
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
        modemSide = side
        break
    end
end
if not modemSide then
    error("No modem attached! Attach a wireless modem to this computer.")
end
rednet.open(modemSide)

term.clear()
term.setCursorPos(1, 1)
print("=== Secure Chat Client ===")

-- ---------- Find server ----------
print("Searching for chat server...")
local serverId = rednet.lookup(common.PROTOCOL, "chat_server")
while not serverId do
    sleep(2)
    serverId = rednet.lookup(common.PROTOCOL, "chat_server")
end
print("Found server at computer #" .. serverId)

local function send(tbl)
    rednet.send(serverId, textutils.serialize(tbl), common.PROTOCOL)
end

-- waits for a reply from the server; times out after `timeout` seconds
local function receive(timeout)
    local timer = os.startTimer(timeout or 5)
    while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "rednet_message" and a == serverId and c == common.PROTOCOL then
            local ok, tbl = pcall(textutils.unserialize, b)
            if ok and type(tbl) == "table" then return tbl end
        elseif ev == "timer" and a == timer then
            return nil
        end
    end
end

-- ---------- Register or log in ----------
write("Do you have an account? (y/n): ")
local hasAccount = read()

local username, password

if hasAccount ~= "y" then
    write("Choose a username: ")
    username = read()
    write("Choose a password: ")
    password = read("*")
    send({ type = "register", username = username, password = password })
    local resp = receive(5)
    if resp and resp.type == "register_ok" then
        print("Registered! Logging in...")
    elseif resp and resp.type == "register_fail" then
        error("Registration failed: " .. resp.reason)
    else
        error("No response from server (registration).")
    end
else
    write("Username: ")
    username = read()
    write("Password: ")
    password = read("*")
end

-- ---------- Challenge/response login ----------
send({ type = "login", username = username })
local challenge = receive(5)
if not challenge or challenge.type ~= "challenge" then
    error("Login failed: " .. (challenge and challenge.reason or "no response from server"))
end

-- Derive the same numeric key the server derived: hash(password, salt)
local sessionKey = common.hashCombine(password, challenge.salt)

-- Prove we know the key by encrypting the server's nonce with it, without ever
-- sending the password or the key itself over the network.
local response = common.toHex(common.crypt(tostring(challenge.nonce), sessionKey, challenge.nonce, false))
send({ type = "auth_response", response = response })

local result = receive(5)
if not result or result.type ~= "auth_ok" then
    error("Authentication failed: " .. (result and result.reason or "no response from server"))
end

print("Authenticated as " .. username .. "! Type a message and press Enter.")
print("Type /quit to disconnect.")
print("")

-- ---------- Chat loop ----------
local function sender()
    while true do
        write("> ")
        local msg = read()
        if msg == "/quit" then
            send({ type = "logout" })
            return
        elseif msg ~= "" then
            local nonce = common.randomNonce()
            local enc = common.crypt(msg, sessionKey, nonce, false)
            send({ type = "chat", nonce = nonce, payload = common.toHex(enc) })
        end
    end
end

local function listener()
    while true do
        local ev, a, b, c = os.pullEvent("rednet_message")
        if a == serverId and c == common.PROTOCOL then
            local ok, tbl = pcall(textutils.unserialize, b)
            if ok and type(tbl) == "table" and tbl.type == "chat" then
                local enc = common.fromHex(tbl.payload)
                local ok2, plain = pcall(common.crypt, enc, sessionKey, tbl.nonce, true)
                if ok2 then
                    print(plain)
                end
            end
        end
    end
end

parallel.waitForAny(sender, listener)
print("Disconnected.")
