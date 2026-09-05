-- Guda ClassicAPI InventoryIndex mutation hooks
-- Ensures the O(1) tooltip index never stays stale after SavedVariables or
-- cross-character data changes that do not necessarily emit a fresh bag event.
-- Lua 5.0 compatible.

local addon = Guda
local Index = addon.Modules.InventoryIndex
local DB = addon.Modules.DB
if not Index or not DB then return end

local oldSaveBags = DB.SaveBags
local oldSaveBank = DB.SaveBank
local oldSaveEquipment = DB.SaveEquipment
local oldSaveMailbox = DB.SaveMailbox
local oldAddMailToCharacter = DB.AddMailToCharacter
local oldToggleGoldBlacklist = DB.ToggleGoldBlacklist
local oldRemoveCharacter = DB.RemoveCharacter
local oldCleanupOldCharacters = DB.CleanupOldCharacters

if oldSaveBags then
    function DB:SaveBags(bagData)
        oldSaveBags(self, bagData)
        Index:InvalidateCurrent()
    end
end

if oldSaveBank then
    function DB:SaveBank(bankData)
        oldSaveBank(self, bankData)
        Index:InvalidateCurrent()
    end
end

if oldSaveEquipment then
    function DB:SaveEquipment(equipmentData)
        oldSaveEquipment(self, equipmentData)
        Index:InvalidateCurrent()
    end
end

if oldSaveMailbox then
    function DB:SaveMailbox(mailboxData)
        oldSaveMailbox(self, mailboxData)
        -- MAIL_INBOX_UPDATE can fire before MailboxScanner's debounced save.
        -- Re-invalidating here guarantees the next tooltip sees the persisted
        -- post-update mailbox snapshot rather than the pre-save one.
        Index:InvalidateCurrent()
    end
end

if oldAddMailToCharacter then
    function DB:AddMailToCharacter(name, realm, mailRow)
        local added = oldAddMailToCharacter(self, name, realm, mailRow)
        if added then
            -- This can mutate a different local character's mailbox.
            Index:InvalidateAll()
        end
        return added
    end
end

if oldToggleGoldBlacklist then
    function DB:ToggleGoldBlacklist(fullName)
        oldToggleGoldBlacklist(self, fullName)
        Index:InvalidateAll()
    end
end

if oldRemoveCharacter then
    function DB:RemoveCharacter(fullName)
        local removed = oldRemoveCharacter(self, fullName)
        if removed then
            Index:InvalidateAll()
        end
        return removed
    end
end

if oldCleanupOldCharacters then
    function DB:CleanupOldCharacters()
        oldCleanupOldCharacters(self)
        Index:InvalidateAll()
    end
end

addon:Debug("ClassicAPI inventory index mutation safety enabled")
