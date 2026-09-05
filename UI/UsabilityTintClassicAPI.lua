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
