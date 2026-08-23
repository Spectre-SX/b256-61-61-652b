local dfpwm = require("cc.audio.dfpwm")

local speaker = peripheral.find("speaker")

if not speaker then
    error("No speaker peripheral found!")
end

local SONG_DIR = "songs"
local CHUNK_SIZE = 16 * 1024

-- =========================================
-- Find songs
-- =========================================

if not fs.exists(SONG_DIR) then
    fs.makeDir(SONG_DIR)
end

local songs = {}

for _, file in ipairs(fs.list(SONG_DIR)) do
    if file:lower():match("%.dfpwm$") then
        table.insert(songs, file)
    end
end

table.sort(songs)

if #songs == 0 then
    error("No .dfpwm files found in /songs")
end

-- =========================================
-- State
-- =========================================

local currentSong = 1
local playing = false
local stopRequested = false
local nextRequested = false
local exiting = false

-- =========================================
-- UI
-- =========================================

local width, height = term.getSize()

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
end

local function center(y, text, color)
    term.setTextColor(color or colors.white)

    local x = math.floor((width - #text) / 2) + 1

    term.setCursorPos(x, y)
    term.write(text)
end

local function button(x, y, w, h, text, bg, fg)
    term.setBackgroundColor(bg)
    term.setTextColor(fg or colors.white)

    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end

    local tx = x + math.floor((w - #text) / 2)
    local ty = y + math.floor(h / 2)

    term.setCursorPos(tx, ty)
    term.write(text)

    term.setBackgroundColor(colors.black)
end

local function draw()
    clear()

    center(2, "DFPWM MUSIC PLAYER", colors.cyan)

    center(
        5,
        songs[currentSong],
        colors.white
    )

    if playing then
        center(6, "PLAYING", colors.lime)
    else
        center(6, "STOPPED", colors.gray)
    end

    -- Play / Stop
    button(
        2, 9, 12, 3,
        playing and "STOP" or "PLAY",
        playing and colors.red or colors.green
    )

    -- Next
    button(
        16, 9, 12, 3,
        "NEXT",
        colors.blue
    )

    -- Exit
    button(
        width - 5, 1, 4, 2,
        "X",
        colors.red
    )

    term.setBackgroundColor(colors.black)
end

-- =========================================
-- Advance song
-- =========================================

local function nextSong()
    currentSong = currentSong + 1

    if currentSong > #songs then
        currentSong = 1
    end

    draw()
end

-- =========================================
-- Playback thread
-- =========================================

local function playback()
    while not exiting do

        -- Wait until Play is pressed
        while not playing and not exiting do
            os.pullEvent("play_song")
        end

        if exiting then
            break
        end

        local path = fs.combine(
            SONG_DIR,
            songs[currentSong]
        )

        local file = fs.open(path, "rb")

        if not file then
            playing = false
            draw()
            sleep(1)
        else
            local decoder = dfpwm.make_decoder()

            stopRequested = false
            nextRequested = false

            while playing and not stopRequested do

                local chunk = file.read(CHUNK_SIZE)

                if not chunk then
                    break
                end

                local audio = decoder(chunk)

                while not speaker.playAudio(audio) do
                    if not playing or stopRequested then
                        break
                    end

                    os.pullEvent("speaker_audio_empty")
                end
            end

            file.close()
            speaker.stop()

            -- Was the song skipped?
            if nextRequested then
                nextRequested = false
                stopRequested = false
                playing = true

                nextSong()

            -- Was the song stopped?
            elseif stopRequested then
                stopRequested = false
                playing = false
                draw()

            -- Song naturally ended
            else
                playing = false
                nextSong()
            end
        end
    end

    speaker.stop()
end

-- =========================================
-- Mouse thread
-- =========================================

local function mouse()
    while not exiting do
        local event, buttonPressed, x, y = os.pullEvent("mouse_click")

        -- PLAY / STOP
        if x >= 2 and x < 14 and y >= 9 and y < 12 then

            if playing then
                playing = false
                stopRequested = true
                speaker.stop()
                draw()
            else
                playing = true
                draw()
                os.queueEvent("play_song")
            end

        -- NEXT
        elseif x >= 16 and x < 28 and y >= 9 and y < 12 then

            if playing then
                nextRequested = true
                stopRequested = true
                speaker.stop()
            else
                nextSong()
            end

        -- X
        elseif x >= width - 5 and x < width - 1 and y >= 1 and y < 3 then

            exiting = true
            playing = false
            stopRequested = true
            speaker.stop()

            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clear()
            term.setCursorPos(1, 1)

            os.queueEvent("exit_player")
        end
    end
end

-- =========================================
-- Start
-- =========================================

draw()

parallel.waitForAny(
    playback,
    mouse
)

speaker.stop()

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
