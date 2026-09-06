-- Guda Bag Scanner
-- Scans and stores bag contents with caching and event pending tracking

local addon = Guda

local BagScanner = {}
addon.Modules.BagScanner = BagScanner

-- Cache for bag data to avoid re-scanning all slots on every update
local bagCache = nil
local cacheValid = false

-- Event pending tracking
local eventPending = false
local dirtySlots = {}  -- dirtySlots[bagID][slotID] = true
local dirtyBags = {}   -- BAG_UPDATE only identifies a bag, not the exact slot

--=====================================================
-- Item Data Pool
-- Reuses item data tables instead of creating new ones
--=====================================================
local itemDataPool = {}
local ITEM_DATA_POOL_MAX = 300

local function AcquireItemData()
    return table.remove(itemDataPool) or {}
end

local function ReleaseItemData(data)
    if not data then return end

    data.link = nil
    data.itemID = nil
    data.texture = nil
    data.count = nil
    data.quality = nil
    data.name = nil
    data.iLevel = nil
    data.type = nil
    data.class = nil
    data.subclass = nil
    data.equipSlot = nil
    data.locked = nil
    data.readable = nil
    data.lootable = nil
    data.isBound = nil

    if table.getn(itemDataPool) < ITEM_DATA_POOL_MAX then
        table.insert(itemDataPool, data)
    end
end

local function ReleaseBagCacheData(bagData)
    if bagData and bagData.slots then
        for _, itemData in pairs(bagData.slots) do
            if itemData then
                ReleaseItemData(itemData)
            end
        end
    end
end

local function ReleaseAllBagCacheData()
    if not bagCache then return end
    for _, bagData in pairs(bagCache) do
        ReleaseBagCacheData(bagData)
    end
end

-- Export the pool helpers so BankScanner can share the same pool instead of
-- permanently consuming tables acquired through BagScanner:ScanSlot().
function BagScanner:AcquireItemData()
    return AcquireItemData()
end

function BagScanner:ReleaseItemData(data)
    ReleaseItemData(data)
end

function BagScanner:ReleaseContainerData(containerData)
    ReleaseBagCacheData(containerData)
end

function BagScanner:GetItemDataPoolSize()
    return table.getn(itemDataPool)
end

-- Clear the bag cache (releases pooled data)
function BagScanner:ClearCache()
    ReleaseAllBagCacheData()
    bagCache = nil
    cacheValid = false
    dirtySlots = {}
    dirtyBags = {}
    eventPending = false
end

function BagScanner:IsEventPending()
    return eventPending
end

function BagScanner:ClearEventPending()
    eventPending = false
end

function BagScanner:MarkSlotDirty(bagID, slotID)
    if not dirtySlots[bagID] then
        dirtySlots[bagID] = {}
    end
    dirtySlots[bagID][slotID] = true
    eventPending = true
end

function BagScanner:GetAndClearDirtySlots()
    local dirty = dirtySlots
    dirtySlots = {}
    return dirty
end

local function GetLiveSlotInfo(bagID, slotID)
    local api = addon.Modules.ClassicAPI
    if api and api.GetContainerItemInfo then
        return api:GetContainerItemInfo(bagID, slotID)
    end

    local texture, count, locked, quality, readable, lootable =
        GetContainerItemInfo(bagID, slotID)
    local link = GetContainerItemLink(bagID, slotID)
    if not texture and not link then return nil end

    local itemID = nil
    if link then
        local _, _, idStr = string.find(link, "item:(%d+)")
        if idStr then itemID = tonumber(idStr) end
    end

    return {
        iconFileID = texture,
        stackCount = count or 1,
        isLocked = locked and true or false,
        quality = quality,
        isReadable = readable and true or false,
        hasLoot = lootable and true or false,
        hyperlink = link,
        itemID = itemID,
    }
end

-- Refresh one cached bag in place. BAG_UPDATE does not provide the changed
-- slot on 1.12, so we cheaply compare live per-slot identity/count state and
-- only rebuild item metadata for slots that actually changed.
function BagScanner:RefreshBagInPlace(bagID)
    if not bagCache then return end

    local oldBag = bagCache[bagID]
    if not oldBag then
        bagCache[bagID] = self:ScanBag(bagID)
        return
    end

    local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
    local bagType = addon.Modules.Utils:GetSpecializedBagType(bagID) or "regular"

    if not addon.Modules.Utils:IsBagValid(bagID) or oldBag.numSlots ~= numSlots then
        ReleaseBagCacheData(oldBag)
        bagCache[bagID] = self:ScanBag(bagID)
        return
    end

    local freeSlots = 0
    for slotID = 1, numSlots do
        local liveInfo = GetLiveSlotInfo(bagID, slotID)
        local oldData = oldBag.slots[slotID]

        if not liveInfo then
            if oldData then
                ReleaseItemData(oldData)
                oldBag.slots[slotID] = nil
            end
            freeSlots = freeSlots + 1
        else
            local liveItemID = tonumber(liveInfo.itemID)
            local liveLink = liveInfo.hyperlink
            local liveCount = liveInfo.stackCount or 1
            local liveLocked = liveInfo.isLocked and true or false

            local changed = false
            if not oldData then
                changed = true
            elseif oldData.itemID ~= liveItemID then
                changed = true
            elseif oldData.link ~= liveLink then
                changed = true
            elseif oldData.count ~= liveCount then
                changed = true
            elseif (oldData.locked and true or false) ~= liveLocked then
                changed = true
            elseif liveInfo.quality ~= nil and oldData.quality ~= liveInfo.quality then
                changed = true
            elseif liveInfo.iconFileID and oldData.texture ~= liveInfo.iconFileID then
                changed = true
            end

            if changed then
                if oldData then ReleaseItemData(oldData) end
                oldBag.slots[slotID] = self:ScanSlot(bagID, slotID)
            end

            if not oldBag.slots[slotID] then
                freeSlots = freeSlots + 1
            end
        end
    end

    oldBag.numSlots = numSlots
    oldBag.freeSlots = freeSlots
    oldBag.bagType = bagType
end

-- Get cached bag data, or scan if cache is invalid
function BagScanner:GetBagData()
    if cacheValid and bagCache then
        local bagsToRefresh = dirtyBags
        dirtyBags = {}

        for bagID in pairs(bagsToRefresh) do
            self:RefreshBagInPlace(bagID)
        end

        -- Exact dirty-slot updates take precedence only when the whole bag was
        -- not already refreshed above.
        for bagID, slots in pairs(dirtySlots) do
            if not bagsToRefresh[bagID]
               and bagID ~= nil and type(slots) == "table" then
                if bagCache[bagID] then
                    for slotID in pairs(slots) do
                        if type(slotID) == "number" and slotID >= 1 then
                            local oldData = bagCache[bagID].slots[slotID]
                            local newData = self:ScanSlot(bagID, slotID)

                            local wasEmpty = oldData == nil
                            local isEmpty = newData == nil

                            if oldData then ReleaseItemData(oldData) end
                            bagCache[bagID].slots[slotID] = newData

                            if wasEmpty and not isEmpty then
                                bagCache[bagID].freeSlots = bagCache[bagID].freeSlots - 1
                            elseif not wasEmpty and isEmpty then
                                bagCache[bagID].freeSlots = bagCache[bagID].freeSlots + 1
                            end
                        end
                    end
                else
                    bagCache[bagID] = self:ScanBag(bagID)
                end
            end
        end

        dirtySlots = {}
        eventPending = false
        return bagCache
    end

    -- Cache miss - release the previous runtime cache before rebuilding it so
    -- its pooled item tables are not abandoned to the Lua GC.
    ReleaseAllBagCacheData()
    bagCache = self:ScanBags()
    cacheValid = true
    dirtySlots = {}
    dirtyBags = {}
    eventPending = false
    return bagCache
end

function BagScanner:InvalidateCache()
    cacheValid = false
    eventPending = true
end

-- Existing BagFrame code calls InvalidateBag() frequently. Keep the public API
-- but preserve the cached tables: mark only that bag dirty and refresh it in
-- place on the next GetBagData(). Bag-size changes are detected automatically.
function BagScanner:InvalidateBag(bagID)
    if bagID == nil then return end
    dirtyBags[bagID] = true
    eventPending = true
end

function BagScanner:ScanBags()
    local bagData = {}

    for _, bagID in ipairs(addon.Constants.BAGS) do
        bagData[bagID] = self:ScanBag(bagID)
    end

    bagData[-2] = self:ScanBag(-2)
    return bagData
end

function BagScanner:ScanBag(bagID)
    local bagType = addon.Modules.Utils:GetSpecializedBagType(bagID) or "regular"

    local bag = {
        slots = {},
        numSlots = addon.Modules.Utils:GetBagSlotCount(bagID),
        freeSlots = 0,
        bagType = bagType,
    }

    if not addon.Modules.Utils:IsBagValid(bagID) then
        return bag
    end

    for slot = 1, bag.numSlots do
        local itemData = self:ScanSlot(bagID, slot)
        bag.slots[slot] = itemData
        if not itemData then
            bag.freeSlots = bag.freeSlots + 1
        end
    end

    return bag
end

-- Scan a single slot. ClassicAPI supplies itemID/link/count/lock/quality in a
-- single structured call, avoiding Vanilla link parsing and several redundant
-- container API calls on the hot path.
function BagScanner:ScanSlot(bagID, slot)
    if bagID == nil or slot == nil or slot < 1 then
        return nil
    end

    local api = addon.Modules.ClassicAPI
    local info = GetLiveSlotInfo(bagID, slot)
    if not info then return nil end

    local itemID = tonumber(info.itemID)
    if not itemID and api and api.GetContainerItemID then
        itemID = api:GetContainerItemID(bagID, slot, info)
    end

    local itemLink = info.hyperlink
    if not itemLink and api and api.GetContainerItemLink then
        itemLink = api:GetContainerItemLink(bagID, slot, info)
    end

    local texture = info.iconFileID
    local itemCount = info.stackCount or 1
    local locked = info.isLocked and true or false
    local quality = info.quality

    -- Static item fields still come through Guda's existing item-info cache.
    -- This call is cached by Utils and only occurs when the slot metadata is
    -- actually rebuilt, not on every BAG_UPDATE comparison.
    local name, link, itemQuality, iLevel, itemCategory, itemType,
        itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice

    if itemLink then
        name, link, itemQuality, iLevel, itemCategory, itemType,
            itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice =
            addon.Modules.Utils:GetItemInfo(itemLink)
    end

    -- ClassicAPI intentionally omits cache-dependent icon/name fields while
    -- static item data is cold. Preserve Vanilla behavior with a rare fallback.
    if not texture then
        local vanillaTexture, vanillaCount, vanillaLocked, vanillaQuality =
            GetContainerItemInfo(bagID, slot)
        texture = vanillaTexture or itemTexture
        if vanillaCount then itemCount = vanillaCount end
        if vanillaLocked ~= nil then locked = vanillaLocked and true or false end
        if quality == nil then quality = vanillaQuality end
    end

    local itemData = AcquireItemData()
    itemData.link = itemLink or link
    itemData.itemID = itemID
    itemData.texture = texture or itemTexture
    itemData.count = itemCount or 1
    itemData.quality = quality or itemQuality or 0
    itemData.name = name or info.itemName
    itemData.iLevel = iLevel
    itemData.type = itemType
    itemData.class = itemCategory
    itemData.subclass = itemSubType
    itemData.equipSlot = itemEquipLoc
    itemData.locked = locked
    itemData.readable = info.isReadable
    itemData.lootable = info.hasLoot
    itemData.isBound = info.isBound

    -- Override known Turtle WoW items that the API reports as Quest although
    -- they behave as consumables.
    if itemCategory == "Quest" and addon.Constants
       and addon.Constants.QUEST_CATEGORY_EXCLUSIONS then
        local exclusionID = itemID
        if not exclusionID and itemData.link then
            exclusionID = addon.Modules.Utils:ExtractItemID(itemData.link)
        end
        if exclusionID and addon.Constants.QUEST_CATEGORY_EXCLUSIONS[exclusionID] then
            itemData.class = "Consumable"
            itemData.type = "Consumable"
        end
    end

    return itemData
end

local function CloneItemData(itemData)
    if not itemData then return nil end
    return {
        link = itemData.link,
        itemID = itemData.itemID,
        texture = itemData.texture,
        count = itemData.count,
        quality = itemData.quality,
        name = itemData.name,
        iLevel = itemData.iLevel,
        type = itemData.type,
        class = itemData.class,
        subclass = itemData.subclass,
        equipSlot = itemData.equipSlot,
        locked = itemData.locked,
        readable = itemData.readable,
        lootable = itemData.lootable,
        isBound = itemData.isBound,
    }
end

local function CloneBagDataForDatabase(runtimeData)
    local snapshot = {}
    if not runtimeData then return snapshot end

    for bagID, bag in pairs(runtimeData) do
        local bagCopy = {
            slots = {},
            numSlots = bag.numSlots,
            freeSlots = bag.freeSlots,
            bagType = bag.bagType,
        }
        if bag.slots then
            for slotID, itemData in pairs(bag.slots) do
                bagCopy.slots[slotID] = CloneItemData(itemData)
            end
        end
        snapshot[bagID] = bagCopy
    end

    return snapshot
end

-- Save from the already-refreshed runtime cache instead of scanning every bag
-- a second time when the bag frame opens.
function BagScanner:SaveToDatabase()
    local runtimeData = self:GetBagData()
    addon.Modules.DB:SaveBags(CloneBagDataForDatabase(runtimeData))
    addon:Debug("Bag data saved to database")

    if addon.Modules.Tooltip and addon.Modules.Tooltip.ClearCache then
        addon.Modules.Tooltip:ClearCache()
    end
end

function BagScanner:Initialize()
    local eventFrame = CreateFrame("Frame")
    self.eventFrame = eventFrame

    eventFrame:RegisterEvent("BAG_UPDATE")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:SetScript("OnEvent", function()
        eventPending = true

        if event == "BAG_UPDATE" and arg1 ~= nil then
            -- Keep the cache structure alive. The next reader compares the
            -- affected bag in place and only rebuilds changed slots.
            dirtyBags[arg1] = true
        end
    end)

    addon:Debug("Bag scanner initialized with ClassicAPI incremental cache")
end

--=====================================================
-- Consolidated from Data/ItemCategoryOverrides.lua
--=====================================================
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
