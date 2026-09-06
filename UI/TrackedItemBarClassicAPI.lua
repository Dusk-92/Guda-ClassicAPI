-- Guda ClassicAPI Tracked Item Bar fast path
-- Replaces the legacy independent bag scan with BagScanner's shared snapshot.

local addon = Guda
local TrackedItemBar = addon.Modules.TrackedItemBar
if not TrackedItemBar then return end

local buttons = {}
local trackedItemsInfo = {}
local trackedByID = {}
local itemOrder = {}

local function Wipe(t)
    if not t then return end
    for k in pairs(t) do t[k] = nil end
end

local function GetItemID(itemData)
    if not itemData then return nil end
    if itemData.itemID then return tonumber(itemData.itemID) end
    if itemData.link and addon.Modules.Utils then
        return addon.Modules.Utils:ExtractItemID(itemData.link)
    end
    return nil
end

function TrackedItemBar:ScanForTrackedItems()
    Wipe(trackedItemsInfo)
    Wipe(trackedByID)
    Wipe(itemOrder)

    local trackedIDs = addon.Modules.DB:GetSetting("trackedItems") or {}
    local bagData = addon.Modules.BagScanner and addon.Modules.BagScanner:GetBagData()
    if not bagData then return end

    -- One shared BagScanner snapshot, consumed in deterministic bag/slot order.
    for bagID = 0, 4 do
        local bag = bagData[bagID]
        if bag and bag.slots then
            local numSlots = bag.numSlots or 0
            for slotID = 1, numSlots do
                local itemData = bag.slots[slotID]
                if itemData then
                    local id = GetItemID(itemData)
                    if id and trackedIDs[id] then
                        local info = trackedByID[id]
                        if not info then
                            info = {
                                itemID = id,
                                texture = itemData.texture,
                                count = 0,
                                link = itemData.link,
                                bagID = bagID,
                                slotID = slotID,
                                isQuest = false,
                                isQuestStarter = false,
                                isUnusable = false,
                                isJunk = false,
                            }
                            trackedByID[id] = info
                            table.insert(itemOrder, id)

                            -- ItemDetection is cached; evaluate once per unique
                            -- tracked item instead of once for every stack/scan.
                            if addon.Modules.ItemDetection and itemData.link then
                                local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)
                                if props then
                                    info.isQuest = props.isQuestItem and true or false
                                    info.isQuestStarter = props.isQuestStarter and true or false
                                    info.isUnusable = props.isUnusable and true or false
                                    info.isJunk = props.isJunk and true or false
                                end
                            end
                        end
                        info.count = info.count + (itemData.count or 1)
                    end
                end
            end
        end
    end

    for _, id in ipairs(itemOrder) do
        table.insert(trackedItemsInfo, trackedByID[id])
    end
end

-- Same UI behaviour as upstream; only the data path above is changed.
function TrackedItemBar:Update()
    local frame = Guda_TrackedItemBar
    if not frame then return end

    if addon.Modules.DB:GetSetting("showTrackedItems") == false then
        frame:Hide()
        return
    end

    self:ScanForTrackedItems()

    local buttonSize = addon.Modules.DB:GetSetting("trackedBarSize") or 36
    local spacing = 2
    local xOffset = 5
    frame:SetHeight(buttonSize + 8)

    for _, btn in ipairs(buttons) do
        btn:Hide()
        if btn.unusableOverlay then btn.unusableOverlay:Hide() end
        if btn.junkIcon then btn.junkIcon:Hide() end
        if btn.questBorder then btn.questBorder:Hide() end
        if btn.questIcon then btn.questIcon:Hide() end
    end

    for i, info in ipairs(trackedItemsInfo) do
        local button = buttons[i]
        if not button then
            button = CreateFrame("Button", "Guda_TrackedItemBarButton" .. i, frame, "Guda_ItemButtonTemplate")
            table.insert(buttons, button)

            local questBorder = CreateFrame("Frame", nil, button)
            questBorder:SetFrameLevel(button:GetFrameLevel() + 6)
            questBorder:SetBackdrop({
                bgFile = nil,
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12,
                insets = {left = 4, right = 4, top = 4, bottom = 4}
            })
            questBorder:SetBackdropBorderColor(1.0, 0.82, 0, 1)
            questBorder:Hide()
            button.questBorder = questBorder

            local questIcon = CreateFrame("Frame", nil, button)
            questIcon:SetFrameLevel(button:GetFrameLevel() + 7)
            questIcon:SetWidth(16)
            questIcon:SetHeight(16)
            local iconTex = questIcon:CreateTexture(nil, "OVERLAY")
            iconTex:SetAllPoints(questIcon)
            iconTex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
            iconTex:SetTexCoord(0, 1, 0, 1)
            questIcon:Hide()
            button.questIcon = questIcon

            button:RegisterForDrag("LeftButton")
            button:SetScript("OnDragStart", function() end)
            button:SetScript("OnReceiveDrag", function() end)
            button:SetScript("OnMouseDown", function()
                if arg1 == "LeftButton" then
                    if IsShiftKeyDown() and not (CursorHasItem and CursorHasItem()) then
                        this:GetParent():StartMoving()
                        this:GetParent().isMoving = true
                    end
                end
            end)
            button:SetScript("OnMouseUp", function()
                if arg1 == "LeftButton" then
                    local parent = this:GetParent()
                    if parent.isMoving then
                        parent:StopMovingOrSizing()
                        parent.isMoving = false
                        local point, _, relativePoint, x, y = parent:GetPoint()
                        addon.Modules.DB:SetSetting("trackedBarPosition", {
                            point = point, relativePoint = relativePoint, x = x, y = y
                        })
                    end
                end
            end)
        end

        button.hasItem = true
        button.itemData = { link = info.link, itemID = info.itemID }
        button.itemID = info.itemID
        button.bagID = info.bagID
        button.slotID = info.slotID
        button.isReadOnly = false

        local icon = getglobal(button:GetName() .. "IconTexture")
        icon:SetTexture(info.texture)
        icon:SetVertexColor(1.0, 1.0, 1.0, 1.0)

        local countText = getglobal(button:GetName() .. "Count")
        countText:SetText(info.count)
        countText:Show()

        button:SetScript("OnClick", function()
            if IsAltKeyDown() and arg1 == "LeftButton" then
                local itemID = this.itemID
                if itemID then
                    local trackedIDs = addon.Modules.DB:GetSetting("trackedItems") or {}
                    trackedIDs[itemID] = nil
                    addon.Modules.DB:SetSetting("trackedItems", trackedIDs)

                    if Guda.Modules.BagFrame and Guda.Modules.BagFrame.Update then
                        Guda.Modules.BagFrame:Update()
                    end
                    TrackedItemBar:Update()
                end
            elseif not IsShiftKeyDown() then
                if this.bagID and this.slotID then
                    UseContainerItem(this.bagID, this.slotID)
                end
            end
        end)

        button:SetScript("OnEnter", function() Guda_ItemButton_OnEnter(this) end)
        button:SetScript("OnLeave", function() Guda_ItemButton_OnLeave(this) end)

        button:ClearAllPoints()
        button:SetPoint("LEFT", frame, "LEFT", xOffset + (i - 1) * (buttonSize + spacing), 0)
        button:SetWidth(buttonSize)
        button:SetHeight(buttonSize)

        if icon then
            icon:SetWidth(buttonSize)
            icon:SetHeight(buttonSize)
        end

        local borderSize = buttonSize * 64 / 37
        local normalTex = getglobal(button:GetName() .. "NormalTexture")
        if normalTex then
            normalTex:SetWidth(borderSize)
            normalTex:SetHeight(borderSize)
        end

        local emptyBg = getglobal(button:GetName() .. "_EmptySlotBg")
        if emptyBg then
            emptyBg:SetWidth(buttonSize)
            emptyBg:SetHeight(buttonSize)
        end

        if button.questBorder then
            button.questBorder:ClearAllPoints()
            button.questBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
            button.questBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
            if info.isQuest then button.questBorder:Show() else button.questBorder:Hide() end
        end

        if button.questIcon then
            local questIconSize = math.max(12, math.min(20, buttonSize * 0.35))
            button.questIcon:SetWidth(questIconSize)
            button.questIcon:SetHeight(questIconSize)
            button.questIcon:ClearAllPoints()
            button.questIcon:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 0)

            if info.isQuest then
                local tex = button.questIcon:GetRegions()
                if tex and tex.SetTexture then
                    if info.isQuestStarter then
                        tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
                    else
                        tex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
                    end
                end
                button.questIcon:Show()
            else
                button.questIcon:Hide()
            end
        end

        if info.isUnusable then
            if not button.unusableOverlay then
                local overlay = button:CreateTexture(nil, "OVERLAY")
                overlay:SetAllPoints(icon)
                overlay:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                overlay:Hide()
                button.unusableOverlay = overlay
            end
            local r, g, b = 0.9, 0.2, 0.2
            if RED_FONT_COLOR then r, g, b = RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b end
            button.unusableOverlay:SetVertexColor(r, g, b, 0.45)
            button.unusableOverlay:Show()
        elseif button.unusableOverlay then
            button.unusableOverlay:Hide()
        end

        if info.isJunk then
            if not button.junkIcon then
                local junkFrame = CreateFrame("Frame", nil, button)
                junkFrame:SetFrameStrata("HIGH")
                local junkTex = junkFrame:CreateTexture(nil, "OVERLAY")
                junkTex:SetAllPoints(junkFrame)
                junkTex:SetTexture("Interface\\GossipFrame\\VendorGossipIcon")
                junkTex:SetTexCoord(0, 1, 0, 1)
                junkFrame.texture = junkTex
                button.junkIcon = junkFrame
            end
            local junkIconSize = math.max(10, math.min(14, buttonSize * 0.30))
            button.junkIcon:SetWidth(junkIconSize)
            button.junkIcon:SetHeight(junkIconSize)
            button.junkIcon:ClearAllPoints()
            button.junkIcon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
            button.junkIcon:Show()
        elseif button.junkIcon then
            button.junkIcon:Hide()
        end

        button:Show()
    end

    local numItems = table.getn(trackedItemsInfo)
    if numItems > 0 then
        local newWidth = xOffset * 2 + numItems * (buttonSize + spacing) - spacing
        frame:SetWidth(newWidth)
        frame:Show()
    else
        frame:Hide()
    end
end

addon:Debug("TrackedItemBar ClassicAPI snapshot consumer loaded")

--=====================================================
-- Consolidated from UI/TrackedItemBarMoveSafety.lua
--=====================================================
-- Guda Tracked Item Bar movement safety
-- Prevents structural Tracked Item Bar refreshes while the frame is being dragged.
-- Lua 5.0 compatible.

local addon = Guda
if not addon or not addon.Modules or not addon.Modules.TrackedItemBar then return end

local TrackedItemBar = addon.Modules.TrackedItemBar
if not TrackedItemBar.Update then return end

local OriginalUpdate = TrackedItemBar.Update

local function FlushDeferredUpdate(barFrame)
    if not barFrame or barFrame.isMoving then return end
    if not barFrame._gudaTrackedBarDeferredUpdate then return end

    barFrame._gudaTrackedBarDeferredUpdate = nil
    TrackedItemBar:Update()
end

local function WrapMouseUp(frame, barFrame)
    if not frame or frame._gudaTrackedBarMoveSafetyWrapped then return end

    local originalMouseUp = frame:GetScript("OnMouseUp")
    frame._gudaTrackedBarMoveSafetyWrapped = true

    frame:SetScript("OnMouseUp", function()
        if originalMouseUp then
            originalMouseUp()
        end

        FlushDeferredUpdate(barFrame or Guda_TrackedItemBar)
    end)
end

local function EnsureMoveSafetyHooks()
    local barFrame = Guda_TrackedItemBar
    if not barFrame then return end

    -- The bar itself can be dragged from its empty area.
    WrapMouseUp(barFrame, barFrame)

    -- Tracked-item buttons can also start/stop movement on behalf of the bar.
    -- Buttons are created dynamically, so wrap every currently existing one.
    local i = 1
    while true do
        local button = getglobal("Guda_TrackedItemBarButton" .. i)
        if not button then break end
        WrapMouseUp(button, barFrame)
        i = i + 1
    end
end

function TrackedItemBar:Update()
    local barFrame = Guda_TrackedItemBar

    -- BAG_UPDATE, PLAYER_LEVEL_UP and other refreshes can arrive while
    -- StartMoving() is active. Rebuilding/hiding/resizing the frame in that
    -- state is unsafe on 1.12, so coalesce them into one post-drag refresh.
    if barFrame and barFrame.isMoving then
        barFrame._gudaTrackedBarDeferredUpdate = true
        return
    end

    OriginalUpdate(self)
    EnsureMoveSafetyHooks()
end

addon:Debug("TrackedItemBar movement safety enabled")
