-- Guda ClassicAPI Inventory Count Index
-- Replaces per-mouseover full inventory scans with a cached itemID index.
-- Lua 5.0 compatible.

local addon = Guda

local InventoryIndex = {}
addon.Modules.InventoryIndex = InventoryIndex

local staticIndex = nil   -- other characters / shared characters
local currentIndex = nil  -- current character live bags + bank/mail/equipment
local staticDirty = true
local currentDirty = true
local eventFrame = nil

-- Reused presentation tables to avoid per-mouseover garbage.
local displayCharacters = {}
local breakdownParts = {}
local charParts = {}

local function GetItemID(itemData)
    if not itemData then return nil end

    if type(itemData) == "number" then
        return itemData
    end

    if type(itemData) == "table" then
        if itemData.itemID then
            return tonumber(itemData.itemID)
        end
        itemData = itemData.link
    end

    if type(itemData) ~= "string" then return nil end
    local _, _, id = string.find(itemData, "item:(%d+)")
    return id and tonumber(id) or nil
end

local function NewIndex()
    return {}
end

local function EnsureItemEntry(index, itemID)
    local entry = index[itemID]
    if not entry then
        entry = {
            totalBags = 0,
            totalBank = 0,
            totalMail = 0,
            totalEquipped = 0,
            characters = {},
            characterMap = {},
        }
        index[itemID] = entry
    end
    return entry
end

local function EnsureCharacterEntry(itemEntry, charKey, charName, charData, isCurrent, isShared)
    local entry = itemEntry.characterMap[charKey]
    if not entry then
        entry = {
            name = (charData and charData.name) or charName,
            classToken = charData and charData.classToken,
            bagCount = 0,
            bankCount = 0,
            mailCount = 0,
            equippedCount = 0,
            isCurrent = isCurrent and true or false,
            isShared = isShared and true or false,
        }
        itemEntry.characterMap[charKey] = entry
        table.insert(itemEntry.characters, entry)
    end
    return entry
end

local function AddCount(index, itemID, count, source, charKey, charName, charData, isCurrent, isShared)
    itemID = tonumber(itemID)
    count = tonumber(count) or 1
    if not itemID or count <= 0 then return end

    local itemEntry = EnsureItemEntry(index, itemID)
    local charEntry = EnsureCharacterEntry(itemEntry, charKey, charName, charData, isCurrent, isShared)

    if source == "bags" then
        itemEntry.totalBags = itemEntry.totalBags + count
        charEntry.bagCount = charEntry.bagCount + count
    elseif source == "bank" then
        itemEntry.totalBank = itemEntry.totalBank + count
        charEntry.bankCount = charEntry.bankCount + count
    elseif source == "mail" then
        itemEntry.totalMail = itemEntry.totalMail + count
        charEntry.mailCount = charEntry.mailCount + count
    elseif source == "equipped" then
        itemEntry.totalEquipped = itemEntry.totalEquipped + count
        charEntry.equippedCount = charEntry.equippedCount + count
    end
end

local function IndexContainers(index, containers, source, charKey, charName, charData, isCurrent, isShared)
    if type(containers) ~= "table" then return end

    for _, bagData in pairs(containers) do
        if type(bagData) == "table" and type(bagData.slots) == "table" then
            for _, itemData in pairs(bagData.slots) do
                if itemData then
                    local itemID = GetItemID(itemData)
                    if itemID then
                        AddCount(index, itemID, itemData.count or 1, source,
                            charKey, charName, charData, isCurrent, isShared)
                    end
                end
            end
        end
    end
end

local function IndexMailbox(index, mailboxData, charKey, charName, charData, isCurrent, isShared)
    if type(mailboxData) ~= "table" then return end

    for _, mail in ipairs(mailboxData) do
        if type(mail) == "table" then
            if type(mail.items) == "table" then
                for _, item in ipairs(mail.items) do
                    local itemID = GetItemID(item)
                    if itemID then
                        AddCount(index, itemID, item.count or 1, "mail",
                            charKey, charName, charData, isCurrent, isShared)
                    end
                end
            elseif mail.item then
                local itemID = GetItemID(mail.item)
                if itemID then
                    AddCount(index, itemID, mail.item.count or 1, "mail",
                        charKey, charName, charData, isCurrent, isShared)
                end
            end
        end
    end
end

local function IndexSavedEquipped(index, equippedData, charKey, charName, charData, isCurrent, isShared)
    if type(equippedData) ~= "table" then return end

    for _, itemData in pairs(equippedData) do
        local itemID = GetItemID(itemData)
        if itemID then
            AddCount(index, itemID, 1, "equipped",
                charKey, charName, charData, isCurrent, isShared)
        end
    end
end

local function IndexLiveEquipped(index, charKey, charName, charData)
    for slotID = 1, 19 do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local itemID = GetItemID(link)
            if itemID then
                AddCount(index, itemID, 1, "equipped",
                    charKey, charName, charData, true, false)
            end
        end
    end
end

function InventoryIndex:InvalidateCurrent()
    currentDirty = true
end

function InventoryIndex:InvalidateAll()
    staticDirty = true
    currentDirty = true
end

local function IsIncludedCharacter(charName, charData, currentRealm)
    if type(charData) ~= "table" then return false end
    if charData.realm ~= currentRealm then return false end
    if addon.Modules.DB and addon.Modules.DB.IsGoldBlacklisted
       and addon.Modules.DB:IsGoldBlacklisted(charName) then
        return false
    end
    return true
end

function InventoryIndex:BuildStaticIndex()
    local index = NewIndex()
    local currentPlayerName = addon.Modules.DB:GetPlayerFullName()
    local currentRealm = GetRealmName()

    local function AddSource(data, isShared)
        if type(data) ~= "table" then return end

        for charName, charData in pairs(data) do
            if charName ~= currentPlayerName
               and IsIncludedCharacter(charName, charData, currentRealm) then
                local charKey = (isShared and "shared:" or "local:") .. charName
                IndexContainers(index, charData.bags, "bags", charKey, charName, charData, false, isShared)
                IndexContainers(index, charData.bank, "bank", charKey, charName, charData, false, isShared)
                IndexMailbox(index, charData.mailbox, charKey, charName, charData, false, isShared)
                IndexSavedEquipped(index, charData.equipped, charKey, charName, charData, false, isShared)
            end
        end
    end

    AddSource(Guda_DB and Guda_DB.characters, false)
    AddSource(addon.sharedCharacters, true)

    staticIndex = index
    staticDirty = false
end

function InventoryIndex:BuildCurrentIndex()
    local index = NewIndex()
    local currentPlayerName = addon.Modules.DB:GetPlayerFullName()
    local charData = Guda_DB and Guda_DB.characters and Guda_DB.characters[currentPlayerName]

    if type(charData) ~= "table" then
        currentIndex = index
        currentDirty = false
        return
    end

    local currentRealm = GetRealmName()
    if not IsIncludedCharacter(currentPlayerName, charData, currentRealm) then
        currentIndex = index
        currentDirty = false
        return
    end

    local charKey = "current:" .. currentPlayerName

    -- Bags: use BagScanner's already-refreshed runtime snapshot. This is the
    -- same state consumed by the bag UI, so tooltip counting performs no
    -- independent container scan.
    local bagData = nil
    if addon.Modules.BagScanner and addon.Modules.BagScanner.GetBagData then
        bagData = addon.Modules.BagScanner:GetBagData()
    else
        bagData = charData.bags
    end
    IndexContainers(index, bagData, "bags", charKey, currentPlayerName, charData, true, false)

    -- Bank: use live cached bank data only while the NPC bank session is open;
    -- otherwise use the last persisted snapshot.
    local bankData = charData.bank
    if addon.Modules.BankScanner and addon.Modules.BankScanner.IsBankOpen
       and addon.Modules.BankScanner:IsBankOpen()
       and addon.Modules.BankScanner.GetBankData then
        bankData = addon.Modules.BankScanner:GetBankData()
    end
    IndexContainers(index, bankData, "bank", charKey, currentPlayerName, charData, true, false)

    -- MailboxScanner persists changes with a short debounce. Reading the
    -- snapshot here avoids rescanning 100+ mails from every item tooltip.
    IndexMailbox(index, charData.mailbox, charKey, currentPlayerName, charData, true, false)

    -- Equipment is only 19 slots and is indexed once per invalidation instead
    -- of once per mouseover.
    IndexLiveEquipped(index, charKey, currentPlayerName, charData)

    currentIndex = index
    currentDirty = false
end

function InventoryIndex:GetItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil, nil end

    if staticDirty or not staticIndex then
        self:BuildStaticIndex()
    end
    if currentDirty or not currentIndex then
        self:BuildCurrentIndex()
    end

    return currentIndex[itemID], staticIndex[itemID]
end

function InventoryIndex:GetStats()
    local staticItems = 0
    local currentItems = 0
    if staticIndex then for _ in pairs(staticIndex) do staticItems = staticItems + 1 end end
    if currentIndex then for _ in pairs(currentIndex) do currentItems = currentItems + 1 end end
    return {
        staticItems = staticItems,
        currentItems = currentItems,
        staticDirty = staticDirty,
        currentDirty = currentDirty,
    }
end

local function GetClassColor(classToken)
    if not classToken then return 1.0, 1.0, 1.0 end
    local color = RAID_CLASS_COLORS[classToken]
    if color then return color.r, color.g, color.b end
    return 1.0, 1.0, 1.0
end

local function CollectCharacters(currentEntry, staticEntry)
    for i = 1, table.getn(displayCharacters) do
        displayCharacters[i] = nil
    end

    local index = 0
    if currentEntry and currentEntry.characters then
        for _, entry in ipairs(currentEntry.characters) do
            index = index + 1
            displayCharacters[index] = entry
        end
    end
    if staticEntry and staticEntry.characters then
        for _, entry in ipairs(staticEntry.characters) do
            index = index + 1
            displayCharacters[index] = entry
        end
    end

    table.sort(displayCharacters, function(a, b)
        if a.isShared ~= b.isShared then return not a.isShared end
        if a.isCurrent and not b.isCurrent then return true end
        if not a.isCurrent and b.isCurrent then return false end
        return (a.name or "") < (b.name or "")
    end)

    return displayCharacters
end

-- Fast replacement for Tooltip:AddInventoryInfo. The expensive inventory walk
-- happens only when an index is dirty; normal mouseovers are direct itemID
-- lookups plus formatting.
local Tooltip = addon.Modules.Tooltip
if Tooltip then
    function Tooltip:AddInventoryInfo(tooltip, link)
        if not addon.Modules.DB:GetSetting("showTooltipCounts") then return end
        if not Guda_DB or type(Guda_DB) ~= "table" then return end
        if not Guda_DB.characters or type(Guda_DB.characters) ~= "table" then return end

        local itemID = GetItemID(link)
        if not itemID then return end

        local currentEntry, staticEntry = InventoryIndex:GetItem(itemID)
        if not currentEntry and not staticEntry then return end

        local totalBags = (currentEntry and currentEntry.totalBags or 0)
            + (staticEntry and staticEntry.totalBags or 0)
        local totalBank = (currentEntry and currentEntry.totalBank or 0)
            + (staticEntry and staticEntry.totalBank or 0)
        local totalMail = (currentEntry and currentEntry.totalMail or 0)
            + (staticEntry and staticEntry.totalMail or 0)
        local totalEquipped = (currentEntry and currentEntry.totalEquipped or 0)
            + (staticEntry and staticEntry.totalEquipped or 0)
        local totalCount = totalBags + totalBank + totalMail + totalEquipped
        if totalCount <= 0 then return end

        tooltip:AddLine(" ")
        tooltip:AddLine("|cFFFFD200" .. Guda_L["Inventory"] .. "|r")

        local totalText = "|cFF00FFFF" .. Guda_L["Total"] .. "|r: |cFFFFFFFF" .. totalCount .. "|r"
        local bpIndex = 0
        if totalBags > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. Guda_L["Bags"] .. "|r: |cFFFFFFFF" .. totalBags .. "|r" end
        if totalBank > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. Guda_L["Bank"] .. "|r: |cFFFFFFFF" .. totalBank .. "|r" end
        if totalMail > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. Guda_L["Mail"] .. "|r: |cFFFFFFFF" .. totalMail .. "|r" end
        if totalEquipped > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. Guda_L["Equipped"] .. "|r: |cFFFFFFFF" .. totalEquipped .. "|r" end
        for i = bpIndex + 1, table.getn(breakdownParts) do breakdownParts[i] = nil end

        local breakdownText = ""
        if bpIndex > 0 then
            breakdownText = "(" .. table.concat(breakdownParts, " | ") .. ")"
        end
        tooltip:AddDoubleLine(totalText, breakdownText, 1, 1, 1, 1, 1, 1)

        local characters = CollectCharacters(currentEntry, staticEntry)
        local sharedSeparatorShown = false
        for _, charInfo in ipairs(characters) do
            if charInfo.isShared and not sharedSeparatorShown then
                tooltip:AddLine("|cFF80C0FF" .. Guda_L["Other Accounts"] .. "|r")
                sharedSeparatorShown = true
            end

            local r, g, b = GetClassColor(charInfo.classToken)
            local pIndex = 0
            if charInfo.bagCount > 0 then pIndex = pIndex + 1; charParts[pIndex] = "|cFF00FFFF" .. Guda_L["Bags"] .. "|r: |cFFFFFFFF" .. charInfo.bagCount .. "|r" end
            if charInfo.bankCount > 0 then pIndex = pIndex + 1; charParts[pIndex] = "|cFF00FFFF" .. Guda_L["Bank"] .. "|r: |cFFFFFFFF" .. charInfo.bankCount .. "|r" end
            if charInfo.mailCount > 0 then pIndex = pIndex + 1; charParts[pIndex] = "|cFF00FFFF" .. Guda_L["Mail"] .. "|r: |cFFFFFFFF" .. charInfo.mailCount .. "|r" end
            if charInfo.equippedCount > 0 then pIndex = pIndex + 1; charParts[pIndex] = "|cFF00FFFF" .. Guda_L["Equipped"] .. "|r: |cFFFFFFFF" .. charInfo.equippedCount .. "|r" end
            for i = pIndex + 1, table.getn(charParts) do charParts[i] = nil end

            local countText = pIndex > 0 and table.concat(charParts, " | ") or ""
            local displayName = charInfo.name or "?"
            if charInfo.isCurrent then
                displayName = displayName .. " |cFFFFFF00(*)|r"
            end
            tooltip:AddDoubleLine(displayName, countText, r, g, b, 1, 1, 1)
        end
    end

    -- Wrap Tooltip initialization so its legacy ClearCache definition is
    -- replaced after the original hooks are installed.
    local OriginalTooltipInitialize = Tooltip.Initialize
    function Tooltip:Initialize()
        OriginalTooltipInitialize(self)

        function Tooltip:ClearCache()
            InventoryIndex:InvalidateCurrent()
            addon:Debug("Tooltip inventory index invalidated")
        end

        InventoryIndex:Initialize()
    end
end

function InventoryIndex:Initialize()
    if eventFrame then return end

    eventFrame = CreateFrame("Frame", "Guda_InventoryIndexEvents")
    eventFrame:RegisterEvent("BAG_UPDATE")
    eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    eventFrame:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
    eventFrame:RegisterEvent("BANKFRAME_OPENED")
    eventFrame:RegisterEvent("BANKFRAME_CLOSED")
    eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")
    eventFrame:RegisterEvent("MAIL_SHOW")
    eventFrame:RegisterEvent("MAIL_CLOSED")
    eventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
    eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    eventFrame:SetScript("OnEvent", function()
        if event == "PLAYER_ENTERING_WORLD" then
            InventoryIndex:InvalidateAll()
        elseif event == "MAIL_SEND_SUCCESS" then
            -- Sending mail may update another locally stored character too.
            InventoryIndex:InvalidateAll()
        elseif event == "UNIT_INVENTORY_CHANGED" then
            if not arg1 or arg1 == "player" then
                InventoryIndex:InvalidateCurrent()
            end
        else
            InventoryIndex:InvalidateCurrent()
        end
    end)

    addon:Debug("ClassicAPI inventory count index initialized")
end

--=====================================================
-- Consolidated from Core/InventoryIndexSafety.lua
--=====================================================
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
