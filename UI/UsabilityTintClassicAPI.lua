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

    local r, g, b, a = 0.9, 0.2, 0.2, 0.45
    if Guda_GetUnusableColor then
        local cr, cg, cb, ca = Guda_GetUnusableColor()
        r = cr or r
        g = cg or g
        b = cb or b
        a = ca or a
    end

    overlay:SetVertexColor(r, g, b, (a or 1.0) * 0.45)
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
