local dfpwm = require("cc.audio.dfpwm")

local speaker = peripheral.find("speaker")
if not speaker then
    error("No speaker found")
end

local SONG_DIR = "songs"
local CHUNK_SIZE = 16 * 1024

-- Find songs
local songs = {}

for _, file in ipairs(fs.list(SONG_DIR)) do
    if file:lower():match("%.dfpwm$") then
        table.insert(songs, file)
    end
end

table.sort(songs)

if #songs == 0 then
    error("No .dfpwm files in /songs")
end

-- State
local song = 1
local playing = false
local quit = false

-- Screen
local w, h = term.getSize()

local function draw()
    term.setBackgroundColor(colors.black)
    term.clear()

    term.setTextColor(colors.cyan)
    term.setCursorPos(2, 2)
    term.write("DFPWM MUSIC PLAYER")

    term.setTextColor(colors.white)
    term.setCursorPos(2, 5)
    term.write("Song: " .. songs[song])

    term.setTextColor(playing and colors.lime or colors.gray)
    term.setCursorPos(2, 6)
    term.write(playing and "PLAYING" or "STOPPED")

    -- Play / Stop
    term.setBackgroundColor(playing and colors.red or colors.green)
    term.setTextColor(colors.white)

    term.setCursorPos(2, 9)
    term.write("            ")

    term.setCursorPos(5, 10)
    term.write(playing and "STOP" or "PLAY")

    -- Next
    term.setBackgroundColor(colors.blue)

    term.setCursorPos(16, 9)
    term.write("            ")

    term.setCursorPos(20, 10)
    term.write("NEXT")

    -- X
    term.setBackgroundColor(colors.red)

    term.setCursorPos(w - 5, 1)
    term.write("    ")

    term.setCursorPos(w - 4, 1)
    term.write(" X ")

    term.setBackgroundColor(colors.black)
end

local function inside(x, y, x1, y1, x2, y2)
    return x >= x1 and x <= x2 and y >= y1 and y <= y2
end

draw()

-- Playback coroutine
local player = coroutine.create(function()

    while true do

        -- Wait until we're told to play
        while not playing do
            coroutine.yield()
        end

        local file = fs.open(
            fs.combine(SONG_DIR, songs[song]),
            "rb"
        )

        if not file then
            playing = false
            draw()
            coroutine.yield()
        end

        local decoder = dfpwm.make_decoder()

        while playing do

            local data = file.read(CHUNK_SIZE)

            if not data then
                break
            end

            local audio = decoder(data)

            while not speaker.playAudio(audio) do
                if not playing then
                    break
                end

                -- Let the main event loop handle mouse events
                coroutine.yield()
            end

            coroutine.yield()
        end

        file.close()
        speaker.stop()

        if playing then
            -- Song finished
            song = song + 1

            if song > #songs then
                song = 1
            end
        end

        playing = false
        draw()
    end
end)

-- Main event loop
while not quit do

    -- Give playback some CPU time
    if coroutine.status(player) ~= "dead" then
        coroutine.resume(player)
    end

    -- Wait for ONE event
    local event, button, x, y = os.pullEvent()

    if event == "mouse_click" then

        -- PLAY / STOP
        if inside(x, y, 2, 9, 13, 11) then

            if playing then
                playing = false
                speaker.stop()
            else
                playing = true
            end

            draw()

        -- NEXT
        elseif inside(x, y, 16, 9, 27, 11) then

            playing = false
            speaker.stop()

            song = song + 1

            if song > #songs then
                song = 1
            end

            draw()

        -- X
        elseif inside(x, y, w - 5, 1, w - 2, 2) then

            quit = true
            playing = false
            speaker.stop()
        end
    end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
