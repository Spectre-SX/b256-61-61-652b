-- mastersound.lua

local dfpwm = require("cc.audio.dfpwm")

local speaker = peripheral.find("speaker")

if not speaker then
    error("No speaker peripheral found")
end

local SOUND_DIR = "sounds"
local CHUNK_SIZE = 16 * 1024

local soundName = arg[1]
local action = arg[2]
local loop = arg[3] == "loop"

if not soundName or not action then
    print("Usage:")
    print("  mastersound <sound> play")
    print("  mastersound <sound> play loop")
    print("  mastersound <sound> stop")
    return
end

local soundPath = fs.combine(SOUND_DIR, soundName .. ".dfpwm")

if action == "stop" then
    speaker.stop()
    print("Stopped: " .. soundName)
    return
end

if action ~= "play" then
    print("Unknown function: " .. action)
    print("Use: play or stop")
    return
end

if not fs.exists(soundPath) then
    printError("Sound not found: " .. soundPath)
    return
end

local function playSound()
    local file = fs.open(soundPath, "rb")

    if not file then
        return false
    end

    local decoder = dfpwm.make_decoder()

    while true do
        local data = file.read(CHUNK_SIZE)

        if not data then
            break
        end

        local audio = decoder(data)

        while not speaker.playAudio(audio) do
            os.pullEvent("speaker_audio_empty")
        end
    end

    file.close()
    return true
end

repeat
    speaker.stop()

    if not playSound() then
        printError("Failed to play " .. soundName)
        return
    end

until not loop

print("Finished: " .. soundName)
