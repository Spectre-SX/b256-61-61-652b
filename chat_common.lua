-- chat_common.lua
-- Shared code for the Secure Chat system (CC:Tweaked).
-- Implements key derivation, a nonce-based stream cipher, and hex encoding.
-- Uses only plain arithmetic (no bit32/bit library) so it works on any CC:Tweaked version.
--
-- IMPORTANT: this is a fun, self-rolled "cool encryption mechanism" for an in-game
-- chat system. It is NOT real cryptography and shouldn't be trusted for anything
-- that actually matters outside of Minecraft.

local common = {}
common.PROTOCOL = "SCHAT-V1"

local M32 = 4294967296 -- 2^32

-- One-way mixing hash (FNV-ish, additive instead of XOR-based so it needs no bit32).
-- Used to turn "password + salt" or "key + nonce" into a numeric key.
function common.hash(str)
    local h = 2166136261
    for i = 1, #str do
        h = (h + string.byte(str, i)) % M32
        h = (h * 16777619) % M32
    end
    return h
end

function common.hashCombine(a, b)
    return common.hash(tostring(a) .. "#" .. tostring(b))
end

-- Linear congruential generator step (Numerical Recipes constants).
-- state * 1664525 stays well within double-precision exactness (< 2^53).
local function lcgNext(state)
    return (state * 1664525 + 1013904223) % M32
end

-- Deterministic keystream of length n, derived from a numeric seed.
local function keystream(seed, n)
    local bytes = {}
    local state = seed % M32
    if state == 0 then state = 1 end
    for i = 1, n do
        state = lcgNext(state)
        bytes[i] = math.floor(state / 65536) % 256 -- mid-order bits mix better than low bits
    end
    return bytes
end

-- Symmetric stream cipher. Same function encrypts and decrypts a byte-for-byte
-- reversible transform via modular addition/subtraction (XOR's arithmetic cousin,
-- works without a bitwise library). `key` and `nonce` must match on both ends.
function common.crypt(str, key, nonce, decrypt)
    local seed = common.hashCombine(key, nonce)
    local ks = keystream(seed, #str)
    local out = {}
    for i = 1, #str do
        local b = string.byte(str, i)
        if decrypt then
            out[i] = string.char((b - ks[i]) % 256)
        else
            out[i] = string.char((b + ks[i]) % 256)
        end
    end
    return table.concat(out)
end

function common.toHex(str)
    local out = {}
    for i = 1, #str do
        out[i] = string.format("%02x", string.byte(str, i))
    end
    return table.concat(out)
end

function common.fromHex(hexstr)
    local out = {}
    for i = 1, #hexstr, 2 do
        out[#out + 1] = string.char(tonumber(hexstr:sub(i, i + 1), 16))
    end
    return table.concat(out)
end

function common.randomNonce()
    return math.random(1, 2000000000)
end

return common
