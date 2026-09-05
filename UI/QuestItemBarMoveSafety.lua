-- Guda Quest Item Bar movement safety
-- Prevents structural Quest Bar refreshes while the frame is being dragged.
-- Lua 5.0 compatible.

local addon = Guda
if not addon or not addon.Modules or not addon.Modules.QuestItemBar then return end

local QuestItemBar = addon.Modules.QuestItemBar
if not QuestItemBar.Update then return end

local OriginalUpdate = QuestItemBar.Update

local function FlushDeferredUpdate(barFrame)
    if not barFrame or barFrame.isMoving then return end
    if not barFrame._gudaQuestBarDeferredUpdate then return end

    barFrame._gudaQuestBarDeferredUpdate = nil
    QuestItemBar:Update()
end

local function WrapMouseUp(frame, barFrame)
    if not frame or frame._gudaQuestBarMoveSafetyWrapped then return end

    local originalMouseUp = frame:GetScript("OnMouseUp")
    frame._gudaQuestBarMoveSafetyWrapped = true

    frame:SetScript("OnMouseUp", function()
        if originalMouseUp then
            originalMouseUp()
        end

        FlushDeferredUpdate(barFrame or Guda_QuestItemBar)
    end)
end

local function EnsureMoveSafetyHooks()
    local barFrame = Guda_QuestItemBar
    if not barFrame then return end

    -- The bar itself can be dragged from its empty area.
    WrapMouseUp(barFrame, barFrame)

    -- The two visible quest item buttons also start/stop movement on behalf
    -- of their parent frame. Wrap them after they are created by Update().
    WrapMouseUp(getglobal("Guda_QuestItemBarButton1"), barFrame)
    WrapMouseUp(getglobal("Guda_QuestItemBarButton2"), barFrame)
end

function QuestItemBar:Update()
    local barFrame = Guda_QuestItemBar

    -- BAG_UPDATE and other events can arrive while StartMoving() is active.
    -- Rebuilding/hiding/resizing the frame in that state is unsafe on 1.12.
    -- Coalesce any number of refresh requests into one update after mouse-up.
    if barFrame and barFrame.isMoving then
        barFrame._gudaQuestBarDeferredUpdate = true
        return
    end

    OriginalUpdate(self)
    EnsureMoveSafetyHooks()
end

addon:Debug("QuestItemBar movement safety enabled")
