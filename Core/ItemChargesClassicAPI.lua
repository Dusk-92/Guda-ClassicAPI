-- Preserve Guda's original charge overlay behavior.
-- ClassicAPI's container charge value is not reliable for distinguishing
-- ordinary stack counts from explicit item charges on the target client, so
-- only show the yellow "xN" overlay when the item tooltip actually contains a
-- Charges line (matching upstream Guda behavior).

local addon = Guda
local ItemDetection = addon.Modules.ItemDetection
if not ItemDetection then return end

local chargesCache = {}

local function SafeSetHyperlink(tooltip, link)
    if not link then return false end
    local _, _, bare = string.find(link, "|H(item:[^|]+)|h")
    if not bare and string.find(link, "^item:") then bare = link end
    if not bare then return false end
    return pcall(tooltip.SetHyperlink, tooltip, bare)
end

local function GetExplicitTooltipCharges(itemData, bagID, slotID)
    local tooltip, tooltipName = addon.Modules.Utils:GetScanTooltip()
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tooltip:ClearLines()

    local ok = false
    if bagID and slotID and bagID ~= -1 then
        ok = pcall(tooltip.SetBagItem, tooltip, bagID, slotID)
    end
    if not ok then
        ok = SafeSetHyperlink(tooltip, itemData and itemData.link)
    end
    if not ok then return nil, false end

    local numLines = tooltip:NumLines() or 0
    for i = 1, numLines do
        local line = getglobal(tooltipName .. "TextLeft" .. i)
        local text = line and line:GetText()
        if text then
            local _, _, num = string.find(string.lower(text), "^(%d+) charges?$")
            if num then return tonumber(num), numLines >= 2 end
        end
    end
    return nil, numLines >= 2
end

function ItemDetection:GetCharges(itemData, bagID, slotID)
    if not bagID or not slotID then return nil end

    local slotKey = bagID .. ":" .. slotID
    local cached = chargesCache[slotKey]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local charges, complete = GetExplicitTooltipCharges(itemData, bagID, slotID)
    if complete then
        chargesCache[slotKey] = charges or false
    end
    return charges
end

function ItemDetection:InvalidateCharges(bagID)
    if bagID then
        local prefix = bagID .. ":"
        for key in pairs(chargesCache) do
            if string.find(key, "^" .. prefix) then
                chargesCache[key] = nil
            end
        end
    else
        chargesCache = {}
    end
end

addon:Debug("Upstream-compatible charge display enabled")
