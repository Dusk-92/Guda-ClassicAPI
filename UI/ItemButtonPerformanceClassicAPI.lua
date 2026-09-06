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

--=====================================================
-- Consolidated from UI/UsabilityTintClassicAPI.lua
--=====================================================
-- Guda ClassicAPI usability tint safety
-- Re-applies unusable-item tint after sorting/moves without synchronous mass scans.
-- Lua 5.0 compatible.

local addon = Guda
if not addon or not Guda_ItemButton_SetItem then return end

local OriginalSetItem = Guda_ItemButton_SetItem

local function EnsureUnusableOverlay(button)
    if button.unusableOverlay then return button.unusableOverlay end

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetAllPoints(button)
    overlay:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    overlay:Hide()
    button.unusableOverlay = overlay
    return overlay
end

-- Mirror ItemButton.lua's unusable color selection exactly. The original helper
-- is local to ItemButton.lua, so this safety layer cannot call it directly.
local function GetUnusableColor()
    if pfUI and C and C.appearance and C.appearance.bags and C.appearance.bags.unusable_color then
        local cr, cg, cb, ca = strsplit(",", C.appearance.bags.unusable_color)
        local r = tonumber(cr) or 0.9
        local g = tonumber(cg) or 0.2
        local b = tonumber(cb) or 0.2
        local a = tonumber(ca) or 1.0
        return r, g, b, a
    end

    if RED_FONT_COLOR then
        return RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, 1.0
    end

    return 0.9, 0.2, 0.2, 1.0
end

local function ApplyUnusableTint(button, unusable)
    if not button then return end

    local markUnusable = true
    if addon.Modules and addon.Modules.DB then
        local setting = addon.Modules.DB:GetSetting("markUnusableItems")
        if setting ~= nil then markUnusable = setting and true or false end
    end

    local overlay = button.unusableOverlay
    if not markUnusable or not unusable then
        if overlay then overlay:Hide() end
        return
    end

    overlay = EnsureUnusableOverlay(button)

    local r, g, b, a = GetUnusableColor()
    -- Match ItemButton.lua exactly: configured alpha is reduced once by 45%.
    local alpha = (a or 1.0) * 0.45
    overlay:SetVertexColor(r or 0.9, g or 0.2, b or 0.2, alpha)
    overlay:Show()
end

local function RefreshUsabilityAsync(button, itemData, bagID, slotID, isReadOnly, otherCharName)
    if not button or not itemData or not itemData.link then return end
    if isReadOnly or otherCharName then return end

    local detection = addon.Modules and addon.Modules.ItemDetection
    if not detection then return end

    -- Never scan tooltip state while the sort engine is actively moving/locking items.
    -- The final post-sort redraw will call SetItem again and schedule a safe refresh.
    if addon.Modules.SortEngine and addon.Modules.SortEngine.sortingInProgress then
        return
    end

    local link = itemData.link
    local cached = detection.IsUnusableCached and detection:IsUnusableCached(itemData) or nil
    if cached ~= nil then
        ApplyUnusableTint(button, cached)
        return
    end

    -- Avoid duplicate jobs when BAG_UPDATE causes several redraws for the same item.
    if button._gudaUsabilityPendingLink == link then return end
    button._gudaUsabilityPendingLink = link

    local function DoRefresh()
        if button._gudaUsabilityPendingLink ~= link then return end
        button._gudaUsabilityPendingLink = nil

        if not button.IsShown or not button:IsShown() or not button.hasItem then return end
        if button.otherChar or button.isReadOnly then return end
        if button.bagID ~= bagID or button.slotID ~= slotID then return end
        if not button.itemData or button.itemData.link ~= link then return end

        local props = detection:GetItemProperties(button.itemData, button.bagID, button.slotID)
        ApplyUnusableTint(button, props and props.isUnusable)
    end

    local Utils = addon.Modules and addon.Modules.Utils
    if Utils and Utils.QueueWork then
        Utils:QueueWork(DoRefresh)
    else
        DoRefresh()
    end
end

function Guda_ItemButton_SetItem(self, bagID, slotID, itemData, isBank, otherCharName, matchesFilter, isReadOnly)
    OriginalSetItem(self, bagID, slotID, itemData, isBank, otherCharName, matchesFilter, isReadOnly)

    if not self then return end

    local currentData = self.itemData or itemData
    local currentLink = currentData and currentData.link or nil

    -- Cancel a stale pending job if this pooled button now represents another item.
    if self._gudaUsabilityPendingLink and self._gudaUsabilityPendingLink ~= currentLink then
        self._gudaUsabilityPendingLink = nil
    end

    if self.hasItem and currentData then
        RefreshUsabilityAsync(self, currentData, tonumber(bagID), tonumber(slotID), isReadOnly, otherCharName)
    elseif self.unusableOverlay then
        self.unusableOverlay:Hide()
    end
end

addon:Debug("ClassicAPI usability tint safety enabled")

--=====================================================
-- Consolidated from UI/TooltipPositionFix.lua
--=====================================================
-- Guda item/comparison tooltip positioning fix.
-- Keeps Guda item tooltips toward the inside of the screen so comparison
-- tooltips have room to render with pfUI/DFUI and the ClassicAPI tooltip code.

local addon = Guda
if not addon or not Guda_ItemButton_OnEnter then return end

local originalOnEnter = Guda_ItemButton_OnEnter

local function IsCursorAnchored()
    if GameTooltip and GameTooltip.GetAnchorType then
        return GameTooltip:GetAnchorType() == "ANCHOR_CURSOR"
    end

    -- Compatibility with pfUI versions that expose cursor positioning only
    -- through their configuration table.
    if pfUI and pfUI.env and pfUI.env.C and pfUI.env.C.tooltip then
        return pfUI.env.C.tooltip.position == "cursor"
    end

    return false
end

local function PositionMainTooltip(button)
    if not button or not GameTooltip or not GameTooltip:IsShown() then return end
    if IsCursorAnchored() then return end

    local centerX = button.GetCenter and button:GetCenter()
    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    if not centerX or not screenWidth or screenWidth <= 0 then return end

    GameTooltip:ClearAllPoints()

    if centerX < (screenWidth / 2) then
        -- Item is on the left: grow the tooltip group toward the right.
        GameTooltip:SetPoint("BOTTOMLEFT", button, "TOPRIGHT", -10, 0)
    else
        -- Preserve Guda's historical position for items on the right.
        GameTooltip:SetPoint("BOTTOMRIGHT", button, "TOPLEFT", 10, 0)
    end
end

local function GetComparisonGap(tooltip)
    local separation = 6
    local edgeSize = 0

    if tooltip and tooltip.GetBackdrop then
        local backdrop = tooltip:GetBackdrop()
        if type(backdrop) == "table" and backdrop.edgeSize then
            edgeSize = backdrop.edgeSize
        end
    end

    return separation + edgeSize
end

local function PositionComparisonTooltips()
    if not GameTooltip or not GameTooltip:IsShown() then return end

    local first = ShoppingTooltip1
    local second = ShoppingTooltip2
    if not first or not first:IsShown() then return end

    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    local left = GameTooltip.GetLeft and GameTooltip:GetLeft()
    local right = GameTooltip.GetRight and GameTooltip:GetRight()
    if not screenWidth or not left or not right then return end

    local leftSpace = left
    local rightSpace = screenWidth - right
    local useLeft = leftSpace > rightSpace
    local gap = GetComparisonGap(first)

    first:SetOwner(GameTooltip, "ANCHOR_NONE")
    first:ClearAllPoints()
    if useLeft then
        first:SetPoint("TOPRIGHT", GameTooltip, "TOPLEFT", -gap, -10)
    else
        first:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", gap, -10)
    end

    if second and second:IsShown() then
        second:SetOwner(first, "ANCHOR_NONE")
        second:ClearAllPoints()
        if useLeft then
            second:SetPoint("TOPRIGHT", first, "TOPLEFT", -gap, 0)
        else
            second:SetPoint("TOPLEFT", first, "TOPRIGHT", gap, 0)
        end
    end
end

function Guda_ItemButton_OnEnter(self)
    originalOnEnter(self)

    -- Empty/drop-target buttons either have no item tooltip or use a small
    -- custom tooltip that does not participate in equipment comparison.
    if not self or self.isDropTarget or not self.hasItem then return end
    if not GameTooltip or not GameTooltip:IsShown() then return end
    if IsCursorAnchored() then return end

    PositionMainTooltip(self)

    -- Comparison tooltips may already have been shown synchronously by a
    -- tooltip hook. Re-anchor them now; if they are shown later, ClassicAPI's
    -- own side selection will use the corrected GameTooltip position.
    PositionComparisonTooltips()
end

addon:Debug("Guda comparison tooltip positioning fix enabled")
