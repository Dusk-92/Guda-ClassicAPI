-- Preserve Guda's historical charge overlay behavior while using ClassicAPI.
-- ClassicAPI reports 1 for many single-use items; Guda historically only
-- displayed charges when the tooltip explicitly contained a Charges line.

local addon = Guda
local ItemDetection = addon.Modules.ItemDetection
if not ItemDetection then return end

local fastGetCharges = ItemDetection.GetCharges

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
    if not ok then return nil end

    local numLines = tooltip:NumLines() or 0
    for i = 1, numLines do
        local line = getglobal(tooltipName .. "TextLeft" .. i)
        local text = line and line:GetText()
        if text then
            local _, _, num = string.find(string.lower(text), "^(%d+) charges?$")
            if num then return tonumber(num) end
        end
    end
    return nil
end

function ItemDetection:GetCharges(itemData, bagID, slotID)
    local charges = fastGetCharges(self, itemData, bagID, slotID)
    if charges ~= 1 then
        return charges
    end

    -- A native value of 1 is ambiguous: it can mean a true one-charge item or
    -- simply a single-use spell item. Confirm only this rare case via tooltip.
    return GetExplicitTooltipCharges(itemData, bagID, slotID)
end

addon:Debug("ClassicAPI charge compatibility filter enabled")
