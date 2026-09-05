-- Turtle WoW item category corrections for stale server-side item classifications.
-- Keep this list intentionally small and explicit to avoid affecting real quest items.
-- Lua 5.0 compatible.

local addon = Guda
if not addon or not addon.Modules or not addon.Modules.BagScanner then return end

local CATEGORY_OVERRIDES = {
    [730] = "Trade Goods", -- Murloc Eye: no longer a quest item on Turtle WoW
}

-- ItemDetection checks this table at runtime before treating API/tooltip data as
-- authoritative quest metadata. Extend the existing exclusions rather than
-- replacing them so the Juju fixes remain intact.
if addon.Constants then
    addon.Constants.QUEST_CATEGORY_EXCLUSIONS = addon.Constants.QUEST_CATEGORY_EXCLUSIONS or {}
    for itemID in pairs(CATEGORY_OVERRIDES) do
        addon.Constants.QUEST_CATEGORY_EXCLUSIONS[itemID] = true
    end
end

local BagScanner = addon.Modules.BagScanner
local OriginalScanSlot = BagScanner.ScanSlot

if OriginalScanSlot then
    function BagScanner:ScanSlot(bagID, slotID)
        local itemData = OriginalScanSlot(self, bagID, slotID)
        if not itemData then return nil end

        local itemID = tonumber(itemData.itemID)
        if not itemID and itemData.link and addon.Modules.Utils then
            itemID = addon.Modules.Utils:ExtractItemID(itemData.link)
        end

        local category = itemID and CATEGORY_OVERRIDES[itemID] or nil
        if category then
            itemData.class = category
            itemData.type = category
        end

        return itemData
    end
end

addon:Debug("Turtle WoW item category overrides enabled")
