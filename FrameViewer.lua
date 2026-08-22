local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================
-- CONFIG (auto-generated — do not edit manually)
-- ============================================================
local RAW_BASE      = "https://raw.githubusercontent.com/palachpalach18-tech/roblox-live/main"
local LOCAL_DIR     = "roblox_live"
local FPS           = 10
local FRAME_BUFFER  = 60
local FRAME_TIME    = 0.1
local POLL_INTERVAL = 2
local LAYERS        = 5
local SHOW_DEBUG    = true
-- ============================================================

local startClock = os.clock()
local function dbg(fmt, ...)
    if not SHOW_DEBUG then return end
    print(string.format("[%.2fs] " .. fmt, os.clock() - startClock, ...))
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
        ok, result = pcall(function()
            return { StatusCode = 200, Body = game:HttpGet(url) }
        end)
    end
    if ok and result and result.StatusCode == 200 then
        return true, result.Body
    end
    return false, nil
end

if not isfolder(LOCAL_DIR) then
    makefolder(LOCAL_DIR)
end

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LiveViewer"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local labels = table.create(LAYERS)
for L = 1, LAYERS do
    local lbl = Instance.new("ImageLabel")
    lbl.Size = UDim2.fromOffset(512, 512)
    lbl.Position = UDim2.fromScale(0.5, 0.5)
    lbl.AnchorPoint = Vector2.new(0.5, 0.5)
    lbl.BackgroundTransparency = 1
    lbl.BorderSizePixel = 0
    lbl.ScaleType = Enum.ScaleType.Fit
    lbl.Visible = true
    lbl.ZIndex = L
    lbl.Parent = screenGui
    labels[L] = lbl
end

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.fromOffset(500, 24)
statusLabel.Position = UDim2.new(0.5, -250, 0, 8)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
statusLabel.TextStrokeTransparency = 0
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 16
statusLabel.Text = "Connecting to live stream..."
statusLabel.ZIndex = 100
statusLabel.Parent = screenGui

local debugLabel = Instance.new("TextLabel")
debugLabel.Size = UDim2.fromOffset(400, 100)
debugLabel.Position = UDim2.new(0.5, -200, 1, -110)
debugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
debugLabel.BackgroundTransparency = 0.5
debugLabel.BorderSizePixel = 0
debugLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
debugLabel.Font = Enum.Font.Code
debugLabel.TextSize = 13
debugLabel.TextXAlignment = Enum.TextXAlignment.Left
debugLabel.TextYAlignment = Enum.TextYAlignment.Top
debugLabel.Text = "Debug info..."
debugLabel.ZIndex = 100
debugLabel.Visible = SHOW_DEBUG
debugLabel.Parent = screenGui

-- ===== Asset cache =====
local assets   = {}
local FRONT_Z  = 10

local function slotFor(s)
    return ((s - 1) % LAYERS) + 1
end

local function ensureAsset(slot)
    if assets[slot] then return assets[slot] end
    local path = LOCAL_DIR .. "/f" .. slot .. ".jpg"
    if isfile(path) then
        local ok, uri = pcall(getcustomasset, path)
        if ok then
            assets[slot] = uri
            return uri
        end
    end
    return nil
end

local function setSlot(slot)
    local uri = ensureAsset(slot)
    if uri then
        labels[slotFor(slot)].Image = uri
    end
end

-- ===== Downloader =====
local downloaded = {}
local downloading = {}

local function downloadFrame(slot)
    if downloaded[slot] or downloading[slot] then return end
    downloading[slot] = true
    task.spawn(function()
        local url  = RAW_BASE .. "/frames/f" .. slot .. ".jpg"
        local path = LOCAL_DIR .. "/f" .. slot .. ".jpg"
        local ok, body = httpGet(url)
        if ok and body and #body > 0 then
            writefile(path, body)
            assets[slot] = nil  -- invalidate so getcustomasset reloads
            downloaded[slot] = true
            dbg("f%d downloaded (%d bytes)", slot, #body)
        else
            downloading[slot] = false  -- allow retry
        end
    end)
end

-- ===== Manifest poller =====
local serverTotal  = 0
local serverSlot   = 0
local lastPoll     = 0
local downloadedCount = 0

local function pollManifest()
    local now = os.clock()
    if now - lastPoll < POLL_INTERVAL then return end
    lastPoll = now

    task.spawn(function()
        local ok, body = httpGet(RAW_BASE .. "/manifest.json")
        if not ok or not body then return end

        local ok2, data = pcall(HttpService.JSONDecode, HttpService, body)
        if not ok2 or not data then return end

        serverTotal = data.total or serverTotal
        serverSlot  = data.slot  or serverSlot

        -- Prefetch upcoming slots
        for ahead = 0, LAYERS do
            local slot = ((serverSlot - 1 + ahead) % FRAME_BUFFER) + 1
            downloadFrame(slot)
        end

        -- Count downloads
        downloadedCount = 0
        for _ in pairs(downloaded) do
            downloadedCount += 1
        end

        dbg("Manifest: total=%d slot=%d cached=%d", serverTotal, serverSlot, downloadedCount)
    end)
end

-- ===== Playback =====
local currentFrame   = 1
local nextSwitch     = os.clock() + FRAME_TIME
local advPerSec      = 0
local skippedTotal   = 0
local fpsWindow      = os.clock()
local playbackStart  = os.clock()

-- Download first batch
for slot = 1, math.min(LAYERS * 2, FRAME_BUFFER) do
    downloadFrame(slot)
end

local conn
conn = RunService.Heartbeat:Connect(function()
    if not screenGui.Parent then
        conn:Disconnect()
        return
    end

    pollManifest()

    local now = os.clock()
    if now < nextSwitch then return end

    local prev = currentFrame
    local advances = 0

    while now >= nextSwitch do
        nextSwitch  += FRAME_TIME
        currentFrame = (currentFrame % FRAME_BUFFER) + 1
        advances    += 1
    end

    advPerSec += advances
    if advances > 1 then
        skippedTotal += advances - 1
    end

    -- Prefetch ahead
    local nextSlot = (currentFrame % FRAME_BUFFER) + 1
    downloadFrame(nextSlot)

    setSlot(currentFrame)
    labels[slotFor(currentFrame)].ZIndex = FRONT_Z
    labels[slotFor(prev)].ZIndex = slotFor(prev)

    local now2 = os.clock()
    if now2 - fpsWindow >= 1 then
        local uptime = now2 - playbackStart
        statusLabel.Text = string.format("LIVE  %d fps  |  server frame %d", advPerSec, serverTotal)
        if SHOW_DEBUG then
            debugLabel.Text = string.format(
                "Slot: %d / %d  |  Server slot: %d\nDownloaded: %d / %d\nSkipped total: %d\nUptime: %.0fs",
                currentFrame, FRAME_BUFFER,
                serverSlot,
                downloadedCount, FRAME_BUFFER,
                skippedTotal,
                uptime
            )
        end
        advPerSec = 0
        fpsWindow = now2
    end
end)
