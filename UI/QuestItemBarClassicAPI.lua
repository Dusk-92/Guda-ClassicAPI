-- Guda ClassicAPI Quest Item Bar fast path
-- Keeps the upstream UI/flyout logic but reuses BagScanner item data so the
-- quest detector does not perform a second container scan for each item.

local addon = Guda
local QuestItemBar = addon.Modules.QuestItemBar
if not QuestItemBar then return end

function QuestItemBar:CheckQuestItemUsable(bagID, slotID)
    if not bagID or not slotID then return false, false, false end

    local itemData = nil
    if addon.Modules.BagScanner and addon.Modules.BagScanner.GetBagData then
        local bagData = addon.Modules.BagScanner:GetBagData()
        local bag = bagData and bagData[bagID]
        itemData = bag and bag.slots and bag.slots[slotID]
    end

    if addon.Modules.ItemDetection and itemData then
        local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)
        if props then
            return props.isQuestItem, props.isQuestStarter, props.isQuestUsable
        end
    end

    -- Preserve the upstream fallback if the slot is not represented in the
    -- shared snapshot for any reason.
    if addon.Modules.Utils and addon.Modules.Utils.IsQuestItem then
        local isQuestItem, isQuestStarter =
            addon.Modules.Utils:IsQuestItem(bagID, slotID, itemData and itemData.link, false, false)
        return isQuestItem, isQuestStarter, isQuestItem
    end

    return false, false, false
end

addon:Debug("QuestItemBar ClassicAPI snapshot detector loaded")
