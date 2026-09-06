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
end

-- Recalculate when the search control changes because it changes the free header space.
local OriginalUpdateSearchBarVisibility = BagFrame.UpdateSearchBarVisibility
function BagFrame:UpdateSearchBarVisibility()
    OriginalUpdateSearchBarVisibility(self)
    UpdateHeaderTitleLayout()
end

-- Apply once more after the complete bag OnShow path. This guarantees the XML title
-- already exists and prevents later layout work during opening from leaving the title
-- on its original frame-centered anchor.
local OriginalBagFrameOnShow = Guda_BagFrame_OnShow
if OriginalBagFrameOnShow then
    function Guda_BagFrame_OnShow(self)
        OriginalBagFrameOnShow(self)
        UpdateHeaderTitleLayout()
    end
end
