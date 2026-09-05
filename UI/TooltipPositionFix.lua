-- Guda item/comparison tooltip positioning fix.
-- Keeps Guda item tooltips toward the inside of the screen so comparison
-- tooltips have room to render with pfUI/DFUI and the ClassicAPI tooltip code.

local addon = Guda
if not addon or not Guda_ItemButton_OnEnter then return end

local originalOnEnter = Guda_ItemButton_OnEnter

local function IsCursorAnchored()
    if GameTooltip and GameTooltip.GetAnchorType then
        return GameTooltip:GetAnchorType() == "ANCHOR_CURSOR"
    end

    -- Compatibility with pfUI versions that expose cursor positioning only
    -- through their configuration table.
    if pfUI and pfUI.env and pfUI.env.C and pfUI.env.C.tooltip then
        return pfUI.env.C.tooltip.position == "cursor"
    end

    return false
end

local function PositionMainTooltip(button)
    if not button or not GameTooltip or not GameTooltip:IsShown() then return end
    if IsCursorAnchored() then return end

    local centerX = button.GetCenter and button:GetCenter()
    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    if not centerX or not screenWidth or screenWidth <= 0 then return end

    GameTooltip:ClearAllPoints()

    if centerX < (screenWidth / 2) then
        -- Item is on the left: grow the tooltip group toward the right.
        GameTooltip:SetPoint("BOTTOMLEFT", button, "TOPRIGHT", -10, 0)
    else
        -- Preserve Guda's historical position for items on the right.
        GameTooltip:SetPoint("BOTTOMRIGHT", button, "TOPLEFT", 10, 0)
    end
end

local function GetComparisonGap(tooltip)
    local separation = 6
    local edgeSize = 0

    if tooltip and tooltip.GetBackdrop then
        local backdrop = tooltip:GetBackdrop()
        if type(backdrop) == "table" and backdrop.edgeSize then
            edgeSize = backdrop.edgeSize
        end
    end

    return separation + edgeSize
end

local function PositionComparisonTooltips()
    if not GameTooltip or not GameTooltip:IsShown() then return end

    local first = ShoppingTooltip1
    local second = ShoppingTooltip2
    if not first or not first:IsShown() then return end

    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    local left = GameTooltip.GetLeft and GameTooltip:GetLeft()
    local right = GameTooltip.GetRight and GameTooltip:GetRight()
    if not screenWidth or not left or not right then return end

    local leftSpace = left
    local rightSpace = screenWidth - right
    local useLeft = leftSpace > rightSpace
    local gap = GetComparisonGap(first)

    first:SetOwner(GameTooltip, "ANCHOR_NONE")
    first:ClearAllPoints()
    if useLeft then
        first:SetPoint("TOPRIGHT", GameTooltip, "TOPLEFT", -gap, -10)
    else
        first:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", gap, -10)
    end

    if second and second:IsShown() then
        second:SetOwner(first, "ANCHOR_NONE")
        second:ClearAllPoints()
        if useLeft then
            second:SetPoint("TOPRIGHT", first, "TOPLEFT", -gap, 0)
        else
            second:SetPoint("TOPLEFT", first, "TOPRIGHT", gap, 0)
        end
    end
end

function Guda_ItemButton_OnEnter(self)
    originalOnEnter(self)

    -- Empty/drop-target buttons either have no item tooltip or use a small
    -- custom tooltip that does not participate in equipment comparison.
    if not self or self.isDropTarget or not self.hasItem then return end
    if not GameTooltip or not GameTooltip:IsShown() then return end
    if IsCursorAnchored() then return end

    PositionMainTooltip(self)

    -- Comparison tooltips may already have been shown synchronously by a
    -- tooltip hook. Re-anchor them now; if they are shown later, ClassicAPI's
    -- own side selection will use the corrected GameTooltip position.
    PositionComparisonTooltips()
end

addon:Debug("Guda comparison tooltip positioning fix enabled")
