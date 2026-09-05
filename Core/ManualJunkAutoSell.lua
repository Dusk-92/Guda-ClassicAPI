-- Auto-sell items explicitly assigned by the user to the built-in Junk category.
-- Upstream Guda's vendor pass only sells poor-quality (gray) links, so a white,
-- green, etc. item manually moved to Junk is displayed as junk but never sold.
-- This module handles only those manual non-gray overrides; the original gray
-- junk seller remains unchanged.

local addon = Guda

local runner = CreateFrame("Frame")
runner:Hide()
runner.items = nil
runner.index = 0
runner.waitElapsed = 0
runner.pollElapsed = 0
runner.soldCount = 0

local function IsMerchantOpen()
    return MerchantFrame and MerchantFrame:IsShown()
end

local function GetItemID(link)
    if not link then return nil end
    local Utils = addon.Modules and addon.Modules.Utils
    if Utils and Utils.ExtractItemID then
        return Utils:ExtractItemID(link)
    end
    local _, _, id = string.find(link, "item:(%d+)")
    return id and tonumber(id) or nil
end

local function IsProtected(itemID)
    local DB = addon.Modules and addon.Modules.DB
    return DB and DB.IsItemProtected and DB:IsItemProtected(itemID)
end

local function IsManualJunk(itemID)
    if not itemID then return false end
    local CategoryManager = addon.Modules and addon.Modules.CategoryManager
    if not CategoryManager or not CategoryManager.GetCategories then return false end
    local cats = CategoryManager:GetCategories()
    return cats and cats.itemOverrides and cats.itemOverrides[itemID] == "Junk"
end

local function IsGrayLink(link)
    return link and string.find(link, "|cff9d9d9d") ~= nil
end

-- Wait for Guda's existing gray-junk seller to finish before starting this
-- pass, avoiding two vendor loops calling UseContainerItem in the same frame.
local function HasUnprotectedGrayJunk()
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if IsGrayLink(link) then
                local itemID = GetItemID(link)
                if itemID and not IsProtected(itemID) then
                    return true
                end
            end
        end
    end
    return false
end

local function StopRunner()
    runner:Hide()
    runner.items = nil
    runner.index = 0
    runner.waitElapsed = 0
    runner.pollElapsed = 0
    runner.soldCount = 0
end

local function StartManualJunkSale()
    local DB = addon.Modules and addon.Modules.DB
    if not DB then return end

    local autoVendor = DB:GetSetting("autoVendorJunk")
    if autoVendor == nil then autoVendor = true end
    if not autoVendor then return end

    local items = {}
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            -- Gray items are already handled by Guda's original vendor pass.
            if link and not IsGrayLink(link) then
                local itemID = GetItemID(link)
                if itemID and IsManualJunk(itemID) and not IsProtected(itemID) then
                    local _, _, locked = GetContainerItemInfo(bag, slot)
                    if not locked then
                        table.insert(items, { bag = bag, slot = slot, itemID = itemID })
                    end
                end
            end
        end
    end

    if table.getn(items) == 0 then return end

    runner.items = items
    runner.index = 0
    runner.waitElapsed = 0
    runner.pollElapsed = 0
    runner.soldCount = 0
    runner:Show()
end

runner:SetScript("OnUpdate", function()
    if not IsMerchantOpen() then
        StopRunner()
        return
    end

    -- Poll at 10 Hz while the original gray-item seller is active. A hard
    -- two-second ceiling prevents a stuck/locked gray item from blocking the
    -- manual-junk pass forever.
    if this.waitElapsed < 2.0 then
        this.waitElapsed = this.waitElapsed + arg1
        this.pollElapsed = this.pollElapsed + arg1
        if this.pollElapsed < 0.10 then return end
        this.pollElapsed = 0
        if HasUnprotectedGrayJunk() then return end
        this.waitElapsed = 2.0
    end

    this.index = this.index + 1
    local item = this.items and this.items[this.index]
    if not item then
        if this.soldCount > 0 then
            addon:Debug("Sold %d manually assigned junk item(s)", this.soldCount)
        end
        StopRunner()
        return
    end

    -- Revalidate the slot immediately before selling. This protects against
    -- inventory changes while the merchant window is open.
    local link = GetContainerItemLink(item.bag, item.slot)
    local itemID = GetItemID(link)
    if link and itemID == item.itemID and not IsGrayLink(link)
       and IsManualJunk(itemID) and not IsProtected(itemID) then
        local _, _, locked = GetContainerItemInfo(item.bag, item.slot)
        if not locked then
            UseContainerItem(item.bag, item.slot)
            this.soldCount = this.soldCount + 1
        end
    end
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_CLOSED")
eventFrame:SetScript("OnEvent", function()
    if event == "MERCHANT_SHOW" then
        StartManualJunkSale()
    elseif event == "MERCHANT_CLOSED" then
        StopRunner()
    end
end)

addon:Debug("Manual Junk auto-sell compatibility fix loaded")
