-- Guda ClassicAPI runtime self-test
-- Read-only diagnostics for the test branch. Run /gudatest in game.
-- Lua 5.0 compatible.

local addon = Guda

local SelfTest = {}
addon.Modules.ClassicAPISelfTest = SelfTest

local function Bool(v)
    return v and "yes" or "no"
end

local function ExtractItemID(link)
    if not link then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    return id and tonumber(id) or nil
end

local function AddMismatch(state, text)
    state.mismatches = state.mismatches + 1
    if state.mismatches <= 12 then
        addon:Print("|cffff6060Mismatch:|r %s", text)
    end
end

local function CompareContainer(state, bagID, label)
    local api = addon.Modules.ClassicAPI
    local numSlots = GetContainerNumSlots(bagID) or 0

    for slotID = 1, numSlots do
        local texture, count, locked, quality, readable =
            GetContainerItemInfo(bagID, slotID)
        local link = GetContainerItemLink(bagID, slotID)
        local vanillaOccupied = texture ~= nil or link ~= nil

        local ok, info = pcall(api.GetContainerItemInfo, api, bagID, slotID)
        if not ok then
            AddMismatch(state, format("%s %d:%d ClassicAPI call errored", label, bagID, slotID))
        else
            local classicOccupied = info ~= nil
            state.checked = state.checked + 1

            if vanillaOccupied ~= classicOccupied then
                AddMismatch(state, format("%s %d:%d occupancy Vanilla=%s ClassicAPI=%s",
                    label, bagID, slotID, Bool(vanillaOccupied), Bool(classicOccupied)))
            elseif vanillaOccupied and info then
                local vanillaID = ExtractItemID(link)
                local classicID = info.itemID and tonumber(info.itemID) or nil

                if vanillaID and classicID and vanillaID ~= classicID then
                    AddMismatch(state, format("%s %d:%d itemID %s ~= %s",
                        label, bagID, slotID, tostring(vanillaID), tostring(classicID)))
                end

                if (count or 1) ~= (info.stackCount or 1) then
                    AddMismatch(state, format("%s %d:%d count %s ~= %s",
                        label, bagID, slotID, tostring(count), tostring(info.stackCount)))
                end

                if (locked and true or false) ~= (info.isLocked and true or false) then
                    AddMismatch(state, format("%s %d:%d locked state differs",
                        label, bagID, slotID))
                end

                if link and info.hyperlink and link ~= info.hyperlink then
                    AddMismatch(state, format("%s %d:%d hyperlink differs",
                        label, bagID, slotID))
                end

                -- ClassicAPI deliberately leaves cache-dependent fields nil
                -- when static item data is cold, so compare only when both exist.
                if texture and info.iconFileID and texture ~= info.iconFileID then
                    AddMismatch(state, format("%s %d:%d texture differs",
                        label, bagID, slotID))
                end
                if quality ~= nil and info.quality ~= nil and quality ~= info.quality then
                    AddMismatch(state, format("%s %d:%d quality %s ~= %s",
                        label, bagID, slotID, tostring(quality), tostring(info.quality)))
                end
                if readable ~= nil and info.isReadable ~= nil
                   and (readable and true or false) ~= (info.isReadable and true or false) then
                    AddMismatch(state, format("%s %d:%d readable state differs",
                        label, bagID, slotID))
                end
            end
        end
    end
end

function SelfTest:Run()
    local api = addon.Modules.ClassicAPI
    addon:Print("|cffffd200=== Guda ClassicAPI self-test ===|r")

    if not api then
        addon:Print("|cffff6060FAIL: ClassicAPI integration module is missing.|r")
        return false
    end

    local status = api:GetStatus()
    addon:Print("ClassicAPI fast path: %s", status.available and "|cff60ff60ACTIVE|r" or "|cffff6060MISSING|r")
    addon:Print("C_Container info=%s itemID=%s charges=%s",
        Bool(status.containerInfo), Bool(status.containerItemID), Bool(status.containerCharges))
    addon:Print("Frame helpers: EnumerateFrames=%s GetFramesRegisteredForEvent=%s",
        Bool(type(EnumerateFrames) == "function"),
        Bool(type(GetFramesRegisteredForEvent) == "function"))

    if not status.available then
        addon:Print("|cffff6060FAIL: required C_Container fast-path functions are unavailable.|r")
        return false
    end

    local state = { checked = 0, mismatches = 0 }

    for bagID = 0, 4 do
        CompareContainer(state, bagID, "bag")
    end

    -- Keyring exists on the target 1.12/Turtle client. pcall is inside the
    -- comparator, so a ClassicAPI incompatibility is reported instead of
    -- aborting the test.
    if (GetContainerNumSlots(-2) or 0) > 0 then
        CompareContainer(state, -2, "keyring")
    end

    if addon.Modules.BankScanner and addon.Modules.BankScanner.IsBankOpen
       and addon.Modules.BankScanner:IsBankOpen() then
        for _, bagID in ipairs(addon.Constants.BANK_BAGS or {}) do
            CompareContainer(state, bagID, "bank")
        end
    else
        addon:Print("Bank comparison skipped (open a bank and run /gudatest again).")
    end

    local budget = addon.Modules.Utils and addon.Modules.Utils.GetFrameBudget
        and addon.Modules.Utils:GetFrameBudget() or nil
    if budget then
        addon:Print("Queue frame budget: %.1f ms", budget * 1000)
    end

    if addon.Modules.InventoryIndex and addon.Modules.InventoryIndex.GetStats then
        local s = addon.Modules.InventoryIndex:GetStats()
        addon:Print("Inventory index: current=%d static=%d dirty(current/static)=%s/%s",
            s.currentItems or 0, s.staticItems or 0,
            Bool(s.currentDirty), Bool(s.staticDirty))
    end

    if addon.Modules.ItemButtonPerformance and addon.Modules.ItemButtonPerformance.GetStats then
        local s = addon.Modules.ItemButtonPerformance:GetStats()
        addon:Print("ItemButton perf: watcher=%s polling=%s sharedGlows=%d active=%s",
            Bool(s.cursorWatcherFound), Bool(s.cursorPollingEnabled),
            s.sharedGlowDrivers or 0, Bool(s.sharedGlowActive))
    end

    if state.mismatches == 0 then
        addon:Print("|cff60ff60PASS: %d container slots checked, no API mismatches.|r", state.checked)
        return true
    end

    if state.mismatches > 12 then
        addon:Print("... %d additional mismatch(es) hidden.", state.mismatches - 12)
    end
    addon:Print("|cffff6060FAIL: %d mismatch(es) across %d checked slots.|r",
        state.mismatches, state.checked)
    return false
end

SLASH_GUDACLASSICAPITEST1 = "/gudatest"
SlashCmdList["GUDACLASSICAPITEST"] = function()
    SelfTest:Run()
end

addon:Debug("ClassicAPI /gudatest runtime diagnostics loaded")
