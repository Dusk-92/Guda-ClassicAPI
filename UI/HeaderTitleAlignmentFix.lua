-- Guda header title alignment fix
-- Keeps the bag title centered in the free space between the left and right header controls.

local addon = Guda
local BagFrame = addon and addon.Modules and addon.Modules.BagFrame
if not BagFrame or not BagFrame.UpdateSearchBarVisibility then return end

local function UpdateHeaderTitleLayout()
    local title = getglobal("Guda_BagFrame_Title")
    local leftButton = getglobal("Guda_BagFrame_MailButton")
    local sortButton = getglobal("Guda_BagFrame_SortButton")
    local searchButton = getglobal("Guda_BagFrame_SearchToggleButton")

    if not title or not leftButton or not sortButton then return end

    local rightButton = sortButton
    if searchButton and searchButton:IsShown() then
        rightButton = searchButton
    end

    title:ClearAllPoints()
    title:SetPoint("LEFT", leftButton, "RIGHT", 8, 0)
    title:SetPoint("RIGHT", rightButton, "LEFT", -8, 0)
    title:SetJustifyH("CENTER")
    title:SetJustifyV("MIDDLE")
end

local OriginalUpdateSearchBarVisibility = BagFrame.UpdateSearchBarVisibility
function BagFrame:UpdateSearchBarVisibility()
    OriginalUpdateSearchBarVisibility(self)
    UpdateHeaderTitleLayout()
end
