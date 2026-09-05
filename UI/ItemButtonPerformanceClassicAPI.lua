-- Guda ClassicAPI ItemButton performance layer
-- Keeps the original ItemButton behavior but removes permanent idle polling
-- and consolidates per-drop-target glow OnUpdate work into one shared driver.
-- Lua 5.0 compatible.

local addon = Guda

local ItemButtonPerformance = {}
addon.Modules.ItemButtonPerformance = ItemButtonPerformance

local cursorWatcher = nil
local originalCursorOnEvent = nil
local originalCursorOnUpdate = nil
local cursorUpdateWrapper = nil
local cursorEventWrapper = nil
-- ItemButton.lua creates the watcher with OnUpdate already active. Mirror that
-- real initial state so the first idle RefreshCursorPolling() can disable it.
local cursorPollingEnabled = true

local glowDrivers = {}
local glowDriverCount = 0
local glowScanAccum = 0
local glowPulseTime = 0
local GLOW_RESCAN_INTERVAL = 0.75

local sharedGlowDriver = CreateFrame("Frame", "Guda_SharedDropGlowDriver", UIParent)
sharedGlowDriver:Hide()

local function IsShown(frame)
    return frame and frame.IsShown and frame:IsShown()
end

local function IsRelevantFrameOpen()
    if IsShown(getglobal("Guda_BagFrame")) then return true end
    if IsShown(getglobal("Guda_BankFrame")) then return true end
    return false
end

local function CursorIsCarrying()
    return CursorHasItem and CursorHasItem() and true or false
end

local function FindCursorWatcher()
    if type(GetFramesRegisteredForEvent) ~= "function" then
        return nil
    end

    local frames = { GetFramesRegisteredForEvent("CURSOR_UPDATE") }
    for i = 1, table.getn(frames) do
        local frame = frames[i]
        if frame
           and frame._lastCarrying ~= nil
           and frame._pollAccum ~= nil
           and frame.GetScript
           and frame:GetScript("OnUpdate") then
            return frame
        end
    end

    return nil
end

local function ShouldCursorPoll()
    if IsRelevantFrameOpen() then return true end
    if CursorIsCarrying() then return true end
    if cursorWatcher and cursorWatcher.pendingCheck then return true end
    return false
end

local function ScanGlowDrivers()
    if type(EnumerateFrames) ~= "function" then return end

    local frame = EnumerateFrames()
    while frame do
        if frame._t ~= nil and frame.GetParent then
            local parent = frame:GetParent()
            if parent
               and parent.dropGlowDriver == frame
               and parent.dropGlow then
                if not glowDrivers[frame] then
                    glowDrivers[frame] = parent
                    glowDriverCount = glowDriverCount + 1
                end

                -- The original driver only computes the same sine wave for
                -- its own button. The shared driver below does that once for
                -- every active glow, so the per-button OnUpdate is redundant.
                if frame.GetScript and frame:GetScript("OnUpdate") then
                    frame:SetScript("OnUpdate", nil)
                end
            end
        end

        frame = EnumerateFrames(frame)
    end
end

local function StartSharedGlowDriver()
    if not sharedGlowDriver:IsShown() then
        -- BagFrame:SetDragging() redraws drop targets synchronously, so by the
        -- time the cursor watcher reaches here the glow drivers normally
        -- already exist. Discover them once immediately; only rare late-created
        -- drivers require the slow fallback rescan below.
        ScanGlowDrivers()
        glowScanAccum = 0
        sharedGlowDriver:Show()
    end
end

sharedGlowDriver:SetScript("OnUpdate", function()
    glowPulseTime = glowPulseTime + arg1
    glowScanAccum = glowScanAccum + arg1

    -- Rare fallback for drivers created after the initial drag redraw. Keep
    -- this deliberately infrequent: EnumerateFrames is much more expensive
    -- than the single shared sine calculation we are trying to optimize.
    if glowScanAccum >= GLOW_RESCAN_INTERVAL then
        glowScanAccum = 0
        ScanGlowDrivers()
    end

    local phase = (math.sin(glowPulseTime * 5.24) + 1) * 0.5
    local alpha = 0.15 + phase * 0.30
    local anyActive = false

    for driver, parent in pairs(glowDrivers) do
        if driver and parent and driver.IsShown and driver:IsShown()
           and parent.dropGlow and parent.dropGlow.IsShown
           and parent.dropGlow:IsShown() then
            parent.dropGlow:SetAlpha(alpha)
            anyActive = true
        end
    end

    if not CursorIsCarrying() and not anyActive then
        this:Hide()
    end
end)

local function SetCursorPolling(enabled)
    if not cursorWatcher or not originalCursorOnUpdate then return end

    enabled = enabled and true or false
    if enabled == cursorPollingEnabled then return end
    cursorPollingEnabled = enabled

    if enabled then
        cursorWatcher:SetScript("OnUpdate", cursorUpdateWrapper)
    else
        cursorWatcher:SetScript("OnUpdate", nil)
    end
end

local function RefreshCursorPolling()
    if ShouldCursorPoll() then
        SetCursorPolling(true)
        if CursorIsCarrying() then
            StartSharedGlowDriver()
        end
    else
        SetCursorPolling(false)
    end
end

local function HookVisibilityFrame(frame)
    if not frame or frame._gudaClassicAPIPerfHooked then return end
    frame._gudaClassicAPIPerfHooked = true

    local oldOnShow = frame:GetScript("OnShow")
    local oldOnHide = frame:GetScript("OnHide")

    frame:SetScript("OnShow", function()
        if oldOnShow then oldOnShow() end
        RefreshCursorPolling()
    end)

    frame:SetScript("OnHide", function()
        if oldOnHide then oldOnHide() end

        -- The other bag/bank frame can change visibility in the same call
        -- stack, so defer the idle decision one frame.
        if Guda_ScheduleTimer then
            Guda_ScheduleTimer(0, RefreshCursorPolling)
        else
            RefreshCursorPolling()
        end
    end)
end

function ItemButtonPerformance:Initialize()
    if cursorWatcher then return true end

    cursorWatcher = FindCursorWatcher()
    if not cursorWatcher then
        addon:Debug("ClassicAPI ItemButton perf: cursor watcher not found")
        return false
    end

    originalCursorOnEvent = cursorWatcher:GetScript("OnEvent")
    originalCursorOnUpdate = cursorWatcher:GetScript("OnUpdate")

    cursorUpdateWrapper = function()
        -- Preserve the original 1.12 safety-net logic while relevant UI is
        -- open or an item is being carried.
        originalCursorOnUpdate()

        if CursorIsCarrying() then
            StartSharedGlowDriver()
        end

        if not ShouldCursorPoll() then
            SetCursorPolling(false)
        end
    end

    cursorEventWrapper = function()
        if originalCursorOnEvent then
            originalCursorOnEvent()
        end
        RefreshCursorPolling()
    end

    cursorWatcher:SetScript("OnEvent", cursorEventWrapper)

    HookVisibilityFrame(getglobal("Guda_BagFrame"))
    HookVisibilityFrame(getglobal("Guda_BankFrame"))

    -- Prime discovery once so any lazily-created glow drivers that already
    -- exist are converted to the shared driver immediately.
    ScanGlowDrivers()
    RefreshCursorPolling()

    addon:Debug("ClassicAPI ItemButton perf initialized: idle cursor polling gated, shared glow driver active")
    return true
end

function ItemButtonPerformance:GetStats()
    return {
        cursorWatcherFound = cursorWatcher ~= nil,
        cursorPollingEnabled = cursorPollingEnabled,
        sharedGlowDrivers = glowDriverCount,
        sharedGlowActive = sharedGlowDriver:IsShown(),
    }
end

-- All XML frames are guaranteed to exist by PLAYER_LOGIN. The fallback retry
-- handles unusual load orders without keeping another permanent OnUpdate alive.
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function()
    if ItemButtonPerformance:Initialize() then
        this:UnregisterEvent("PLAYER_LOGIN")
        this:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)
