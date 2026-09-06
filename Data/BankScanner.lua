-- Guda Bank Scanner
-- Scans and stores bank contents with caching and event pending tracking

local addon = Guda

local BankScanner = {}
addon.Modules.BankScanner = BankScanner

local bankOpen = false

local bankCache = nil
local cacheValid = false
local eventPending = false
local dirtySlots = {}
local dirtyBags = {}

local function IsBankAccessible()
    if bankOpen then return true end
    local testSlots = GetContainerNumSlots(-1)
    return testSlots and testSlots > 0
end

local function ReleaseBankBagData(bagData)
    if addon.Modules.BagScanner and addon.Modules.BagScanner.ReleaseContainerData then
        addon.Modules.BagScanner:ReleaseContainerData(bagData)
    end
end

local function ReleaseAllBankCacheData()
    if not bankCache then return end
    for _, bagData in pairs(bankCache) do
        ReleaseBankBagData(bagData)
    end
end

function BankScanner:ClearCache()
    ReleaseAllBankCacheData()
    bankCache = nil
    cacheValid = false
    dirtySlots = {}
    dirtyBags = {}
    eventPending = false
end

function BankScanner:IsEventPending()
    return eventPending
end

function BankScanner:ClearEventPending()
    eventPending = false
end

function BankScanner:MarkSlotDirty(bagID, slotID)
    if not dirtySlots[bagID] then
        dirtySlots[bagID] = {}
    end
    dirtySlots[bagID][slotID] = true
    eventPending = true
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

-- Refresh only one affected bank container. Unlike the old cache-hit path,
-- this does not walk every bank bag just to prove that an already-valid cache
-- is valid. ClassicAPI gives us cheap per-slot identity/count state for the one
-- bag the UI/event layer marked dirty.
function BankScanner:RefreshBankBagInPlace(bagID)
    if not bankCache then return end

    local oldBag = bankCache[bagID]
    if not oldBag then
        bankCache[bagID] = self:ScanBankBag(bagID)
        return
    end

    local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
    if not addon.Modules.Utils:IsBagValid(bagID) or oldBag.numSlots ~= numSlots then
        ReleaseBankBagData(oldBag)
        bankCache[bagID] = self:ScanBankBag(bagID)
        return
    end

    local freeSlots = 0
    for slotID = 1, numSlots do
        local liveInfo = GetLiveSlotInfo(bagID, slotID)
        local oldData = oldBag.slots[slotID]

        if not liveInfo then
            if oldData then
                addon.Modules.BagScanner:ReleaseItemData(oldData)
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
                if oldData then addon.Modules.BagScanner:ReleaseItemData(oldData) end
                oldBag.slots[slotID] = addon.Modules.BagScanner:ScanSlot(bagID, slotID)
            end

            if not oldBag.slots[slotID] then
                freeSlots = freeSlots + 1
            end
        end
    end

    oldBag.numSlots = numSlots
    oldBag.freeSlots = freeSlots
end

function BankScanner:GetBankData()
    if not IsBankAccessible() then
        addon:DebugCategory("GetBankData: bank not accessible")
        return {}
    end

    if cacheValid and bankCache then
        local bagsToRefresh = dirtyBags
        dirtyBags = {}

        for bagID in pairs(bagsToRefresh) do
            self:RefreshBankBagInPlace(bagID)
        end

        for bagID, slots in pairs(dirtySlots) do
            if not bagsToRefresh[bagID]
               and bagID ~= nil and type(slots) == "table" then
                if bankCache[bagID] then
                    for slotID in pairs(slots) do
                        if type(slotID) == "number" and slotID >= 1 then
                            local oldData = bankCache[bagID].slots[slotID]
                            local newData = addon.Modules.BagScanner:ScanSlot(bagID, slotID)
                            local wasEmpty = oldData == nil
                            local isEmpty = newData == nil

                            if oldData then addon.Modules.BagScanner:ReleaseItemData(oldData) end
                            bankCache[bagID].slots[slotID] = newData

                            if wasEmpty and not isEmpty then
                                bankCache[bagID].freeSlots = bankCache[bagID].freeSlots - 1
                            elseif not wasEmpty and isEmpty then
                                bankCache[bagID].freeSlots = bankCache[bagID].freeSlots + 1
                            end
                        end
                    end
                else
                    bankCache[bagID] = self:ScanBankBag(bagID)
                end
            end
        end

        dirtySlots = {}
        eventPending = false
        return bankCache
    end

    -- Full rescan is now reserved for first open / explicit full invalidation.
    ReleaseAllBankCacheData()
    bankCache = self:ScanBank()
    cacheValid = true
    dirtySlots = {}
    dirtyBags = {}
    eventPending = false
    return bankCache
end

function BankScanner:UpdateSlot(bagID, slotID)
    if not bankOpen then return end
    self:MarkSlotDirty(bagID, slotID)
end

function BankScanner:InvalidateCache()
    cacheValid = false
    eventPending = true
end

function BankScanner:GetCachedItemCount(bagID)
    if not bankCache or not bankCache[bagID] or not bankCache[bagID].slots then
        return 0
    end
    local count = 0
    for _, item in pairs(bankCache[bagID].slots) do
        if item then count = count + 1 end
    end
    return count
end

-- Keep the existing API name used by BankFrame, but change its semantics from
-- "destroy this cache entry" to "refresh this one bank container on demand".
function BankScanner:InvalidateBag(bagID)
    if not IsBankAccessible() then return end
    dirtyBags[bagID] = true
    eventPending = true
end

function BankScanner:ScanBank()
    if not IsBankAccessible() then
        addon:Debug("Cannot scan bank - not accessible")
        return {}
    end

    local bankData = {}
    for _, bagID in ipairs(addon.Constants.BANK_BAGS) do
        bankData[bagID] = self:ScanBankBag(bagID)
    end
    return bankData
end

function BankScanner:ScanBankBag(bagID)
    local bagType = "regular"
    if addon.Modules.Utils:IsSoulBag(bagID) then
        bagType = "soul"
    elseif addon.Modules.Utils:IsHerbBag(bagID) then
        bagType = "herb"
    elseif addon.Modules.Utils:IsEnchantBag(bagID) then
        bagType = "enchant"
    elseif addon.Modules.Utils:IsAmmoQuiverBag(bagID) then
        bagType = "ammo"
    end

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
        local itemData = addon.Modules.BagScanner:ScanSlot(bagID, slot)
        bag.slots[slot] = itemData
        if not itemData then
            bag.freeSlots = bag.freeSlots + 1
        end
    end

    return bag
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

local function CloneBankDataForDatabase(runtimeData)
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

function BankScanner:SaveToDatabase()
    if not bankOpen then return end

    local bankData = self:GetBankData()
    addon.Modules.DB:SaveBank(CloneBankDataForDatabase(bankData))
    addon:Debug("Bank data saved")
end

function BankScanner:Initialize()
    addon.Modules.Events:OnBankOpen(function()
        bankOpen = true
        BankScanner:ClearCache()
        addon:Debug("Bank opened")

        Guda_ScheduleTimer(0.5, function()
            BankScanner:SaveToDatabase()
        end)
    end, "BankScanner")

    addon.Modules.Events:OnBankClose(function()
        addon:Debug("Bank closing - performing final save")
        BankScanner:SaveToDatabase()

        bankOpen = false
        BankScanner:ClearCache()
        addon:Debug("Bank closed")
    end, "BankScanner")
end

function BankScanner:IsBankOpen()
    return bankOpen
end

--=====================================================
-- Consolidated from Data/CacheLifecycleSafety.lua
--=====================================================
-- Guda ClassicAPI cache lifecycle safety
-- Whole-cache invalidation is deferred to in-place dirty refreshes while the
-- corresponding UI is visible. This prevents pooled item tables still held by
-- visible buttons from being cleared/reused before their redraw runs.
-- Lua 5.0 compatible.

local addon = Guda
local BagScanner = addon.Modules.BagScanner
local BankScanner = addon.Modules.BankScanner
if not BagScanner or not BankScanner then return end

local oldBagClearCache = BagScanner.ClearCache
local oldBagInvalidateCache = BagScanner.InvalidateCache
local oldBankClearCache = BankScanner.ClearCache
local oldBankInvalidateCache = BankScanner.InvalidateCache

local function IsShown(name)
    local frame = getglobal(name)
    return frame and frame.IsShown and frame:IsShown()
end

local function MarkAllBagsDirty()
    if addon.Constants and addon.Constants.BAGS then
        for _, bagID in ipairs(addon.Constants.BAGS) do
            BagScanner:InvalidateBag(bagID)
        end
    else
        for bagID = 0, 4 do
            BagScanner:InvalidateBag(bagID)
        end
    end
    BagScanner:InvalidateBag(-2)
end

local function MarkAllBankBagsDirty()
    if addon.Constants and addon.Constants.BANK_BAGS then
        for _, bagID in ipairs(addon.Constants.BANK_BAGS) do
            BankScanner:InvalidateBag(bagID)
        end
    end
end

function BagScanner:ClearCache()
    if IsShown("Guda_BagFrame") then
        MarkAllBagsDirty()
        return
    end
    return oldBagClearCache(self)
end

function BagScanner:InvalidateCache()
    if IsShown("Guda_BagFrame") then
        MarkAllBagsDirty()
        return
    end
    return oldBagInvalidateCache(self)
end

function BankScanner:ClearCache()
    if BankScanner:IsBankOpen() and IsShown("Guda_BankFrame") then
        MarkAllBankBagsDirty()
        return
    end
    return oldBankClearCache(self)
end

function BankScanner:InvalidateCache()
    if BankScanner:IsBankOpen() and IsShown("Guda_BankFrame") then
        MarkAllBankBagsDirty()
        return
    end
    return oldBankInvalidateCache(self)
end

addon:Debug("ClassicAPI cache lifecycle safety enabled")
