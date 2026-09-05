-- Guda CacheWarmer
-- Pre-warms ItemDetection and category-related tooltip caches shortly after
-- PLAYER_LOGIN so the first bag open does not pay for cold tooltip scans.
--
-- Guda ClassicAPI uses the low-latency FIFO in Core/Performance.lua. Heavy
-- tooltip operations stay as separate work items so a single callback cannot
-- accidentally bundle several expensive tooltip scans into one frame.

local addon = Guda

local CacheWarmer = {}
addon.Modules.CacheWarmer = CacheWarmer

-- Populate the real BagScanner cache once. The original implementation called
-- ScanBag() for bags 0-4 but discarded every returned table, then GetBagData()
-- immediately scanned the bags again. Returning GetBagData() here makes the
-- warmup useful and gives the later stages the exact cached snapshot.
function CacheWarmer:WarmBagScanner()
    local BagScanner = Guda.Modules.BagScanner
    if not BagScanner or not BagScanner.GetBagData then return nil end
    return BagScanner:GetBagData()
end

-- Queue tooltip/cache work using the already-cached BagScanner snapshot.
-- This avoids another round of GetContainerNumSlots/GetContainerItemLink and
-- avoids GetItemInfo calls just to discover the item class.
function CacheWarmer:WarmItemDetectionCache(bagData)
    local Utils = Guda.Modules.Utils
    local ItemDetection = Guda.Modules.ItemDetection
    local CategoryManager = Guda.Modules.CategoryManager
    local BagScanner = Guda.Modules.BagScanner

    if not (Utils and Utils.QueueWork) then return end
    if not (ItemDetection and ItemDetection.GetItemProperties) then return end

    bagData = bagData or (BagScanner and BagScanner.GetBagData
        and BagScanner:GetBagData())
    if not bagData then return end

    for bagID = 0, 4 do
        local bag = bagData[bagID]
        if bag and bag.slots then
            for slotID, slotData in pairs(bag.slots) do
                if slotData and slotData.link then
                    local b, s = bagID, slotID
                    local snapshot = {
                        link = slotData.link,
                        itemID = slotData.itemID,
                        name = slotData.name,
                        class = slotData.class,
                        type = slotData.type,
                        subclass = slotData.subclass,
                        quality = slotData.quality,
                        texture = slotData.texture,
                        equipSlot = slotData.equipSlot,
                    }

                    -- Central property scan. Keep this as its own queue item:
                    -- SetBagItem can be expensive on a cold client cache.
                    Utils:QueueWork(function()
                        ItemDetection:GetItemProperties(snapshot, b, s)
                    end, "CacheWarmer.itemDetection")

                    -- Only consumables need the restore-text tooltip cache.
                    if snapshot.class == "Consumable"
                       and Utils.GetConsumableRestoreTag then
                        Utils:QueueWork(function()
                            snapshot.restoreTag =
                                Utils:GetConsumableRestoreTag(b, s, snapshot.link)
                        end, "CacheWarmer.restoreTag")
                    end

                    -- Only equipment can be Bind on Equip.
                    if (snapshot.class == "Weapon" or snapshot.class == "Armor")
                       and Utils.IsBindOnEquip then
                        Utils:QueueWork(function()
                            Utils:IsBindOnEquip(b, s, snapshot.link)
                        end, "CacheWarmer.boe")
                    end

                    -- Runs after the relevant warmers because the queue is FIFO,
                    -- so category rules hit warm ItemDetection/tooltip caches.
                    if CategoryManager and CategoryManager.CategorizeItem then
                        Utils:QueueWork(function()
                            CategoryManager:CategorizeItem(snapshot, b, s, false)
                        end, "CacheWarmer.category")
                    end
                end
            end
        end
    end
end

function CacheWarmer:Initialize()
    -- Defer startup work so we do not compete with the login frame.
    Guda_ScheduleTimer(0.5, function()
        local bagData = CacheWarmer:WarmBagScanner()
        CacheWarmer:WarmItemDetectionCache(bagData)

        -- Completion marker runs after all prior FIFO work drains.
        local Utils = Guda.Modules.Utils
        if Utils and Utils.QueueWork then
            Utils:QueueWork(function()
                if Guda_BagFrame and Guda_BagFrame:IsShown()
                   and Guda.Modules.BagFrame and Guda.Modules.BagFrame.Update then
                    Guda.Modules.BagFrame:Update()
                end
                if Guda_BagFrame_UpdateAllUsabilityTints then
                    Guda_BagFrame_UpdateAllUsabilityTints()
                end
            end, "CacheWarmer.completionSweep")
        end
    end)
end
