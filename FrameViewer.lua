-- FrameViewer.lua  (auto-generated — do not edit manually)
-- LocalScript inside StarterPlayerScripts
-- Executor required: http_request/syn.request, writefile, getcustomasset, isfolder, makefolder, isfile

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RAW_BASE      = "https://raw.githubusercontent.com/palachpalach18-tech/roblox-live/main"
local FRAME_BUFFER  = 10
local FPS           = 1
local POLL_INTERVAL = 0.5
local TMP_DIR       = "live_tmp"
local PREFETCH      = 2
local FRAME_TIME    = 1 / FPS

-- Cache-bust every request so GitHub CDN never serves stale content
local function cacheBust(url)
    return url .. "?v=" .. tostring(os.time())
end

local function httpGet(url)
    local ok, result
    if syn and syn.request then
        ok, result = pcall(syn.request, { Url = url, Method = "GET" })
    elseif http_request then
        ok, result = pcall(http_request, { Url = url, Method = "GET" })
    elseif request then
        ok, result = pcall(request, { Url = url, Method = "GET" })
    else
        ok, result = pcall(function() return { StatusCode = 200, Body = game:HttpGet(url) } end)
    end
    if ok and result and result.StatusCode == 200 then return true, result.Body end
    return false, ""
end

if not isfolder(TMP_DIR) then makefolder(TMP_DIR) end

local screenGui = Instance.new("ScreenGui")
screenGui.Name, screenGui.ResetOnSpawn, screenGui.IgnoreGuiInset = "LiveViewer", false, true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local display = Instance.new("ImageLabel")
display.Size = UDim2.fromOffset(512, 512)
display.Position = UDim2.fromScale(0.5, 0.5)
display.AnchorPoint = Vector2.new(0.5, 0.5)
display.BackgroundColor3 = Color3.fromRGB(0,0,0)
display.BackgroundTransparency = 0
display.BorderSizePixel = 0
display.ScaleType = Enum.ScaleType.Fit
display.ZIndex = 1
display.Parent = screenGui

local dbg = Instance.new("TextLabel")
dbg.Size = UDim2.new(1, 0, 0, 100)
dbg.Position = UDim2.fromOffset(0, 0)
dbg.BackgroundColor3 = Color3.fromRGB(0,0,0)
dbg.BackgroundTransparency = 0.4
dbg.TextColor3 = Color3.fromRGB(255,255,0)
dbg.TextStrokeTransparency = 0
dbg.Font = Enum.Font.Code
dbg.TextSize = 13
dbg.TextXAlignment = Enum.TextXAlignment.Left
dbg.TextYAlignment = Enum.TextYAlignment.Top
dbg.Text = "Starting..."
dbg.ZIndex = 200
dbg.Parent = screenGui

local serverTotal  = 0
local serverSlot   = 1
local lastPoll     = -math.huge
local manifestOk   = false
local slot_written = {}
for s = 1, FRAME_BUFFER do slot_written[s] = -1 end
local downloading  = {}
local fetchOk      = 0
local fetchFail    = 0

local function slotPath(slot)
    return TMP_DIR .. "/f" .. slot .. "v" .. slot_written[slot] .. ".jpg"
end

local function pollManifest()
    local now = os.clock()
    if now - lastPoll < POLL_INTERVAL then return end
    lastPoll = now
    local ok, body = httpGet(cacheBust(RAW_BASE .. "/manifest.json"))
    if not ok or body == "" then dbg.Text = "manifest FAILED\n" .. RAW_BASE return end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok2 or type(data) ~= "table" then dbg.Text = "manifest parse FAILED" return end
    serverTotal = tonumber(data.total) or serverTotal
    serverSlot  = tonumber(data.slot)  or serverSlot
    manifestOk  = true
end

local function fetchSlot(slot)
    if downloading[slot] then return end
    if slot_written[slot] >= serverTotal then return end
    local snapTotal = serverTotal
    downloading[slot] = true
    task.spawn(function()
        local url = cacheBust(RAW_BASE .. "/frames/f" .. slot .. ".jpg")
        local ok, body = httpGet(url)
        if ok and body and #body > 200 then
            local path = TMP_DIR .. "/f" .. slot .. "v" .. snapTotal .. ".jpg"
            writefile(path, body)
            slot_written[slot] = snapTotal
            fetchOk += 1
        else
            fetchFail += 1
        end
        downloading[slot] = false
    end)
end

local playSlot       = 1
local nextSwitchTime = os.clock() + FRAME_TIME
local fpsCounter     = 0
local fpsWindowStart = os.clock()

-- Wait for manifest
dbg.Text = "Fetching manifest..."
local t0 = os.clock()
repeat pollManifest() task.wait(0.3) until manifestOk or os.clock()-t0 > 10
if not manifestOk then
    dbg.Text = "TIMEOUT — manifest unreachable\n" .. RAW_BASE .. "/manifest.json"
    return
end

-- Start 2 slots behind server
playSlot = ((serverSlot - 3 + FRAME_BUFFER) % FRAME_BUFFER) + 1
dbg.Text = string.format("manifest OK slot=%d total=%d — fetching...", serverSlot, serverTotal)

for i = -2, PREFETCH do
    fetchSlot(((serverSlot - 1 + i) % FRAME_BUFFER) + 1)
end

local conn
conn = RunService.Heartbeat:Connect(function()
    if not screenGui.Parent then conn:Disconnect() return end

    pollManifest()

    for i = 0, PREFETCH do
        fetchSlot(((playSlot - 1 + i) % FRAME_BUFFER) + 1)
    end

    local now = os.clock()
    if now < nextSwitchTime then return end
    nextSwitchTime = now + FRAME_TIME

    -- Snap to server if drifted too far behind
    local drift = (serverSlot - playSlot + FRAME_BUFFER) % FRAME_BUFFER
    if drift > FRAME_BUFFER / 2 then
        playSlot = ((serverSlot - 3 + FRAME_BUFFER) % FRAME_BUFFER) + 1
    else
        playSlot = (playSlot % FRAME_BUFFER) + 1
    end

    if slot_written[playSlot] > 0 then
        local path = slotPath(playSlot)
        if isfile(path) then
            local ok, uri = pcall(getcustomasset, path)
            if ok and uri and uri ~= "" then
                display.Image = uri
                fpsCounter += 1
            end
        end
    end

    local now2 = os.clock()
    if now2 - fpsWindowStart >= 1 then
        dbg.Text = string.format(
            "LIVE | fps=%d | server slot=%d total=%d\nplay=%d | ok=%d fail=%d | img=%s",
            fpsCounter, serverSlot, serverTotal,
            playSlot, fetchOk, fetchFail,
            display.Image ~= "" and "OK" or "empty"
        )
        fpsCounter = 0
        fpsWindowStart = now2
    end
end)
