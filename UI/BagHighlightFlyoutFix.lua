-- Guda ClassicAPI bag hover highlight fix
-- Keep bag ownership highlights in sync with the compact bag flyout state.
-- Lua 5.0 compatible.

local addon = Guda
if not addon then return end
if type(Guda_BagFrame_HighlightBagButton) ~= "function" then return end
if type(Guda_BagFrame_ClearBagButtonHighlight) ~= "function" then return end

local OriginalHighlightBagButton = Guda_BagFrame_HighlightBagButton
local OriginalClearBagButtonHighlight = Guda_BagFrame_ClearBagButtonHighlight

local function IsBaglineHidden()
    if addon.Modules and addon.Modules.DB and addon.Modules.DB.GetSetting then
        return addon.Modules.DB:GetSetting("hideBagline") and true or false
    end
    return false
end

local function GetVisibleBagFlyout()
    local flyout = getglobal("Guda_BagFlyout")
    if flyout and flyout:IsShown() then
        return flyout
    end
end

function Guda_BagFrame_HighlightBagButton(bagID)
    -- Full bagline: preserve Guda's existing behavior exactly.
    if not IsBaglineHidden() then
        return OriginalHighlightBagButton(bagID)
    end

    local numericBagID = tonumber(bagID)

    -- Compact mode: the bag-0 toolbar button represents the flyout itself.
    -- Do not light it merely because an item belongs to the backpack while
    -- that flyout is closed.
    if numericBagID and numericBagID >= 0 and numericBagID <= 4 then
        if not GetVisibleBagFlyout() then return end

        local button
        if numericBagID == 0 then
            button = getglobal("Guda_BagFrame_Toolbar_BagSlot0")
        else
            button = getglobal("Guda_BagFlyout_Slot" .. numericBagID)
        end

        if button then button:LockHighlight() end
        return
    end

    -- Keyring/special bag buttons are not part of the compact 1-4 flyout.
    OriginalHighlightBagButton(bagID)
end

function Guda_BagFrame_ClearBagButtonHighlight()
    OriginalClearBagButtonHighlight()

    -- The original clear helper only knows about toolbar bag buttons.
    -- Also clear any compact-flyout slot we may have highlighted above.
    for bagID = 1, 4 do
        local button = getglobal("Guda_BagFlyout_Slot" .. bagID)
        if button then button:UnlockHighlight() end
    end
end
