-- Guda ClassicAPI integration
-- Centralizes ClassicAPI fast paths while keeping safe Vanilla fallbacks
-- during the migration. This module is intentionally small so the rest of
-- Guda does not need to know which backend supplied container data.

local addon = Guda

local ClassicAPI = {}
addon.Modules.ClassicAPI = ClassicAPI

local hasContainerInfo = type(C_Container) == "table"
    and type(C_Container.GetContainerItemInfo) == "function"
local hasContainerItemID = type(C_Container) == "table"
    and type(C_Container.GetContainerItemID) == "function"

local function ExtractItemID(link)
    if not link then return nil end
    local _, _, itemID = string.find(link, "item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

function ClassicAPI:IsAvailable()
    return hasContainerInfo and hasContainerItemID
end

function ClassicAPI:HasContainerInfo()
    return hasContainerInfo
end

function ClassicAPI:HasContainerItemID()
    return hasContainerItemID
end

-- Returns a modern-style ContainerItemInfo table.
-- ClassicAPI supplies this directly. The fallback normalizes Vanilla's flat
-- GetContainerItemInfo tuple into the same shape so callers stay branch-free.
function ClassicAPI:GetContainerItemInfo(bagID, slotID)
    if bagID == nil or slotID == nil or slotID < 1 then return nil end

    if hasContainerInfo then
        return C_Container.GetContainerItemInfo(bagID, slotID)
    end

    local texture, count, locked, quality, readable, lootable =
        GetContainerItemInfo(bagID, slotID)
    local link = GetContainerItemLink(bagID, slotID)

    if not texture and not link then return nil end

    return {
        iconFileID = texture,
        stackCount = count or 1,
        isLocked = locked and true or false,
        quality = quality,
        isReadable = readable and true or false,
        hasLoot = lootable and true or false,
        hyperlink = link,
        itemID = ExtractItemID(link),
    }
end

function ClassicAPI:GetContainerItemID(bagID, slotID, info)
    if bagID == nil or slotID == nil or slotID < 1 then return nil end

    if info and info.itemID then
        return tonumber(info.itemID)
    end

    if hasContainerItemID then
        local itemID = C_Container.GetContainerItemID(bagID, slotID)
        return itemID and tonumber(itemID) or nil
    end

    return ExtractItemID(GetContainerItemLink(bagID, slotID))
end

function ClassicAPI:GetContainerItemLink(bagID, slotID, info)
    if info and info.hyperlink then
        return info.hyperlink
    end
    return GetContainerItemLink(bagID, slotID)
end

function ClassicAPI:GetStatus()
    return {
        available = self:IsAvailable(),
        containerInfo = hasContainerInfo,
        containerItemID = hasContainerItemID,
    }
end
