local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RAW_BASE      = "https://raw.githubusercontent.com/palachpalach18-tech/roblox-live/main"
local LOCAL_DIR     = "roblox_live"
local FPS           = 10
local FRAME_BUFFER  = 60
local POLL_INTERVAL = 2  -- seconds between manifest checks
local LAYERS        = 5

local FRAME_TIME    = 1 / FPS

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
statusLabel.Size = UDim2.fromOffset(400, 24)
statusLabel.Position = UDim2.new(0.5, -200, 0, 8)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
statusLabel.TextStrokeTransparency = 0
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 16
statusLabel.Text = "Connecting..."
statusLabel.ZIndex = 100
statusLabel.Parent = screenGui

-- ===== Asset cache =====
local assets = {}   -- [slot] = rbxasset URI
local FRONT_Z = 10

local function slotFor(frame)
    return ((frame - 1) % LAYERS) + 1
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

-- ===== Frame downloader =====
local downloaded = {}  -- [slot] = true

local function downloadFrame(slot)
    if downloaded[slot] then return end
    local url  = RAW_BASE .. "/frames/f" .. slot .. ".jpg"
    local path = LOCAL_DIR .. "/f" .. slot .. ".jpg"
    local ok, body = httpGet(url)
    if ok then
        writefile(path, body)
        assets[slot] = nil  -- invalidate cache so it reloads
        downloaded[slot] = true
    end
end

-- ===== Manifest poller =====
local serverTotal  = 0
local serverSlot   = 1
local lastPoll     = 0

local function pollManifest()
    local now = os.clock()
    if now - lastPoll < POLL_INTERVAL then return end
    lastPoll = now

    local ok, body = httpGet(RAW_BASE .. "/manifest.json")
    if not ok then return end

    local ok2, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if not ok2 or not data then return end

    serverTotal = data.total or serverTotal
    serverSlot  = data.slot  or serverSlot

    -- Download next few frames ahead in parallel
    for ahead = 0, math.min(LAYERS, FRAME_BUFFER - 1) do
        local slot = ((serverSlot - 1 + ahead) % FRAME_BUFFER) + 1
        task.spawn(downloadFrame, slot)
    end

    statusLabel.Text = string.format(
        "LIVE — server frame %d | slot %d",
        serverTotal, serverSlot
    )
end

-- ===== Playback =====
local currentFrame    = 1
local nextSwitchTime  = os.clock() + FRAME_TIME
local advPerSec       = 0
local fpsWindowStart  = os.clock()

-- Preload initial slots
for slot = 1, FRAME_BUFFER do
    task.spawn(downloadFrame, slot)
end

local conn
conn = RunService.Heartbeat:Connect(function()
    if not screenGui.Parent then
        conn:Disconnect()
        return
    end

    -- Poll manifest periodically
    pollManifest()

    local now = os.clock()
    if now < nextSwitchTime then return end

    local prev = currentFrame
    while now >= nextSwitchTime do
        nextSwitchTime += FRAME_TIME
        currentFrame = (currentFrame % FRAME_BUFFER) + 1
        advPerSec   += 1
    end

    -- Prime next frame
    local nextSlot = (currentFrame % FRAME_BUFFER) + 1
    task.spawn(downloadFrame, nextSlot)

    setSlot(currentFrame)

    labels[slotFor(currentFrame)].ZIndex = FRONT_Z
    labels[slotFor(prev)].ZIndex = slotFor(prev)

    local now2 = os.clock()
    if now2 - fpsWindowStart >= 1 then
        statusLabel.Text = string.format(
            "LIVE — %d fps | server frame %d",
            advPerSec, serverTotal
        )
        advPerSec    = 0
        fpsWindowStart = now2
    end
end)
