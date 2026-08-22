-- ============================================================
-- AUTO-GENERATED FRAME VIEWER
-- ============================================================

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

local playerGui =
    player:WaitForChild("PlayerGui")


-- ============================================================
-- CONFIG
-- ============================================================

local RAW_BASE =
    "https://raw.githubusercontent.com/palachpalach18-tech/roblox-live/main"

local FRAME_BUFFER =
    10

local FPS =
    1

local POLL_INTERVAL =
    0.5

local PREFETCH =
    3

local LATENCY_FRAMES =
    2

local TMP_DIR =
    "live_tmp"

local FRAME_TIME =
    1 / FPS


-- ============================================================
-- CACHE BUST
-- ============================================================

local function cacheBust(url)

    return url
        .. "?cb="
        .. tostring(
            math.random(
                100000000,
                999999999
            )
        )

end


-- ============================================================
-- HTTP
-- ============================================================

local function httpGet(url)

    local ok
    local result

    if syn and syn.request then

        ok, result = pcall(
            syn.request,
            {
                Url = url,
                Method = "GET"
            }
        )

    elseif http_request then

        ok, result = pcall(
            http_request,
            {
                Url = url,
                Method = "GET"
            }
        )

    elseif request then

        ok, result = pcall(
            request,
            {
                Url = url,
                Method = "GET"
            }
        )

    else

        ok, result = pcall(
            function()

                return {
                    StatusCode = 200,
                    Body = game:HttpGet(url)
                }

            end
        )

    end

    if ok
        and result
        and result.StatusCode == 200 then

        return true,
            result.Body or ""

    end

    return false, ""

end


-- ============================================================
-- FILESYSTEM
-- ============================================================

if not isfolder(TMP_DIR) then

    makefolder(TMP_DIR)

end


-- ============================================================
-- GUI
-- ============================================================

local oldGui =
    playerGui:FindFirstChild(
        "LiveViewer"
    )

if oldGui then
    oldGui:Destroy()
end


local screenGui =
    Instance.new("ScreenGui")

screenGui.Name =
    "LiveViewer"

screenGui.ResetOnSpawn =
    false

screenGui.IgnoreGuiInset =
    true

screenGui.ZIndexBehavior =
    Enum.ZIndexBehavior.Sibling

screenGui.Parent =
    playerGui


local display =
    Instance.new("ImageLabel")

display.Name =
    "Display"

display.Size =
    UDim2.fromOffset(
        512,
        512
    )

display.Position =
    UDim2.fromScale(
        0.5,
        0.5
    )

display.AnchorPoint =
    Vector2.new(
        0.5,
        0.5
    )

display.BackgroundColor3 =
    Color3.fromRGB(
        0,
        0,
        0
    )

display.BorderSizePixel =
    0

display.ScaleType =
    Enum.ScaleType.Fit

display.ZIndex =
    1

display.Parent =
    screenGui


local dbg =
    Instance.new("TextLabel")

dbg.Size =
    UDim2.new(
        1,
        0,
        0,
        150
    )

dbg.Position =
    UDim2.fromOffset(
        0,
        0
    )

dbg.BackgroundColor3 =
    Color3.fromRGB(
        0,
        0,
        0
    )

dbg.BackgroundTransparency =
    0.35

dbg.TextColor3 =
    Color3.fromRGB(
        255,
        255,
        0
    )

dbg.TextStrokeTransparency =
    0

dbg.Font =
    Enum.Font.Code

dbg.TextSize =
    13

dbg.TextXAlignment =
    Enum.TextXAlignment.Left

dbg.TextYAlignment =
    Enum.TextYAlignment.Top

dbg.Text =
    "Starting..."

dbg.ZIndex =
    200

dbg.Parent =
    screenGui


-- ============================================================
-- STATE
-- ============================================================

local serverTotal = 0
local serverSlot = 1

local frameNames = {}

local downloaded = {}

local downloading = {}

local lastPoll =
    -math.huge

local manifestOk =
    false

local fetchOk = 0
local fetchFail = 0

local playSlot = 1

local nextSwitchTime =
    os.clock()
    + FRAME_TIME

local fpsCounter = 0

local fpsWindowStart =
    os.clock()


-- ============================================================
-- PATH
-- ============================================================

local function slotPath(slot)

    local filename =
        downloaded[slot]

    if not filename then
        return nil
    end

    return TMP_DIR
        .. "/"
        .. tostring(filename)

end


-- ============================================================
-- MANIFEST
-- ============================================================

local function pollManifest()

    local now =
        os.clock()

    if now - lastPoll
        < POLL_INTERVAL then

        return

    end

    lastPoll =
        now

    local url =
        RAW_BASE
        .. "/manifest.json"

    -- Manifest is mutable, so cache-bust it.
    url = cacheBust(url)

    local ok, body =
        httpGet(url)

    if not ok
        or body == "" then

        dbg.Text =
            "MANIFEST FAILED\n"
            .. RAW_BASE
            .. "/manifest.json"

        return

    end

    local decodeOk
    local data

    decodeOk, data =
        pcall(
            function()

                return HttpService:JSONDecode(
                    body
                )

            end
        )

    if not decodeOk
        or type(data) ~= "table" then

        dbg.Text =
            "MANIFEST PARSE FAILED"

        return

    end

    serverTotal =
        tonumber(data.total)
        or serverTotal

    serverSlot =
        tonumber(data.slot)
        or serverSlot

    if type(data.frames)
        == "table" then

        for slot, filename
            in pairs(data.frames) do

            local numericSlot =
                tonumber(slot)

            if numericSlot
                and type(filename)
                    == "string" then

                frameNames[numericSlot] =
                    filename

            end

        end

    end

    manifestOk =
        true

end


-- ============================================================
-- FETCH FRAME
-- ============================================================

local function fetchSlot(slot)

    if downloading[slot] then
        return
    end

    local filename =
        frameNames[slot]

    if not filename then
        return
    end

    -- Already have this exact frame.
    if downloaded[slot]
        == filename then

        return

    end

    downloading[slot] =
        true

    task.spawn(
        function()

            -- UNIQUE URL.
            --
            -- Example:
            -- /frames/frame_00001234.jpg
            --
            local url =
                RAW_BASE
                .. "/frames/"
                .. filename

            -- Extra protection.
            url =
                cacheBust(url)

            local ok, body =
                httpGet(url)

            if ok
                and body
                and #body > 200 then

                local path =
                    TMP_DIR
                    .. "/"
                    .. filename

                local writeOk =
                    pcall(
                        function()

                            writefile(
                                path,
                                body
                            )

                        end
                    )

                if writeOk then

                    downloaded[slot] =
                        filename

                    fetchOk += 1

                else

                    fetchFail += 1

                end

            else

                fetchFail += 1

            end

            downloading[slot] =
                false

        end
    )

end


-- ============================================================
-- DISPLAY
-- ============================================================

local function displaySlot(slot)

    local filename =
        downloaded[slot]

    if not filename then
        return false
    end

    local path =
        slotPath(slot)

    if not path then
        return false
    end

    if not isfile(path) then
        return false
    end

    local ok, uri =
        pcall(
            getcustomasset,
            path
        )

    if not ok
        or not uri
        or uri == "" then

        return false

    end

    display.Image =
        uri

    return true

end


-- ============================================================
-- INITIAL MANIFEST
-- ============================================================

dbg.Text =
    "Fetching manifest..."

local start =
    os.clock()

repeat

    pollManifest()

    task.wait(0.3)

until manifestOk
    or os.clock() - start > 10


if not manifestOk then

    dbg.Text =
        "TIMEOUT — manifest unreachable\n"
        .. RAW_BASE
        .. "/manifest.json"

    return

end


-- ============================================================
-- INITIAL POSITION
-- ============================================================

playSlot =
    (
        (
            serverSlot
            - 1
            - LATENCY_FRAMES
        )
        % FRAME_BUFFER
    )
    + 1


dbg.Text =
    string.format(
        "MANIFEST OK\n"
        .. "server slot=%d\n"
        .. "total=%d\n"
        .. "Downloading...",
        serverSlot,
        serverTotal
    )


-- ============================================================
-- PREFETCH
-- ============================================================

for offset =
    -LATENCY_FRAMES,
    PREFETCH do

    local slot =
        (
            (
                serverSlot
                - 1
                + offset
            )
            % FRAME_BUFFER
        )
        + 1

    fetchSlot(slot)

end


-- ============================================================
-- HEARTBEAT
-- ============================================================

local connection

connection =
    RunService.Heartbeat:Connect(
        function()

            if not screenGui.Parent then

                connection:Disconnect()

                return

            end


            --========================================
            -- Poll manifest
            --========================================

            pollManifest()


            --========================================
            -- Prefetch
            --========================================

            for offset =
                0,
                PREFETCH do

                local slot =
                    (
                        (
                            playSlot
                            - 1
                            + offset
                        )
                        % FRAME_BUFFER
                    )
                    + 1

                fetchSlot(slot)

            end


            --========================================
            -- Timing
            --========================================

            local now =
                os.clock()

            if now < nextSwitchTime then
                return
            end

            nextSwitchTime =
                now
                + FRAME_TIME


            --========================================
            -- Advance
            --========================================

            local drift =
                (
                    serverSlot
                    - playSlot
                    + FRAME_BUFFER
                )
                % FRAME_BUFFER


            if drift
                > FRAME_BUFFER / 2 then

                playSlot =
                    (
                        (
                            serverSlot
                            - 1
                            - LATENCY_FRAMES
                        )
                        % FRAME_BUFFER
                    )
                    + 1

            else

                playSlot =
                    (
                        playSlot
                        % FRAME_BUFFER
                    )
                    + 1

            end


            --========================================
            -- Display
            --========================================

            if displaySlot(playSlot) then

                fpsCounter += 1

            end


            --========================================
            -- Debug
            --========================================

            local now2 =
                os.clock()

            if now2
                - fpsWindowStart
                >= 1 then

                dbg.Text =
                    string.format(
                        "LIVE\n"
                        .. "fps=%d\n"
                        .. "server=%d\n"
                        .. "total=%d\n"
                        .. "play=%d\n"
                        .. "frame=%s\n"
                        .. "ok=%d fail=%d\n"
                        .. "image=%s",

                        fpsCounter,

                        serverSlot,

                        serverTotal,

                        playSlot,

                        tostring(
                            frameNames[playSlot]
                            or "none"
                        ),

                        fetchOk,

                        fetchFail,

                        display.Image ~= ""
                            and "OK"
                            or "EMPTY"
                    )

                fpsCounter = 0

                fpsWindowStart =
                    now2

            end

        end
    )
