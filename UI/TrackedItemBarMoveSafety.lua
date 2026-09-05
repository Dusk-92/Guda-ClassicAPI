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
