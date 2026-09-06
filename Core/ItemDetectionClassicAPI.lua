-- Guda ClassicAPI item detection fast path
-- Replaces the allocation-heavy tooltip line-table pipeline with a single-pass
-- scanner while preserving Guda's public ItemDetection API.

local addon = Guda
local ItemDetection = addon.Modules.ItemDetection
if not ItemDetection then return end

local originalGetCharges = ItemDetection.GetCharges

local detectionCache = {}
local cacheHits = 0
local cacheMisses = 0

-- Explicit charge overlays are cached per live slot. Negative results are kept
-- across ordinary BAG_UPDATE events so normal stacks do not trigger a tooltip
-- scan every time their count changes.
local chargesCache = {}
local chargeCapableLinks = {}

local EMPTY_PROPERTIES = {
    isQuestItem = false,
    isQuestStarter = false,
    isQuestUsable = false,
    isJunk = false,
    isPermanentEnchant = false,
    isUnusable = false,
}

local durabilityPattern = DURABILITY_TEMPLATE
    and string.gsub(DURABILITY_TEMPLATE, "%%d", "%%d+") or nil

local function GetCacheKey(itemLink)
    return itemLink
end

local function ExtractItemID(itemData)
    if not itemData then return nil end
    if itemData.itemID then return tonumber(itemData.itemID) end
    if not itemData.link then return nil end
    local _, _, id = string.find(itemData.link, "item:(%d+)")
    return id and tonumber(id) or nil
end

local function IsExcludedQuestItem(itemData)
    local exclusions = addon.Constants and addon.Constants.QUEST_CATEGORY_EXCLUSIONS
    if not exclusions then return false end
    local itemID = ExtractItemID(itemData)
    return itemID and exclusions[itemID] and true or false
end

local function IsRedColor(r, g, b)
    if not r or not g or not b then return false end
    local dr = math.abs(r - 1.0)
    local dg = math.abs(g - 0.125)
    local db = math.abs(b - 0.125)
    return (dr < 0.15 and dg < 0.15 and db < 0.15)
        or (r > 0.85 and g < 0.3 and b < 0.3)
end

local function IsRequirementText(text)
    if not text or text == "" then return false end
    local lower = string.lower(text)

    if string.find(lower, "requires") then return true end
    if string.find(lower, "require") then return true end
    if string.find(lower, "classes:") then return true end
    if string.find(lower, "races:") then return true end
    if string.find(lower, "level %d") then return true end
    if string.find(lower, "skill:") then return true end
    if string.find(lower, "reputation") then return true end
    if string.find(lower, "riding") then return true end
    if string.find(lower, "already known") then return true end

    if string.find(lower, "warrior") then return true end
    if string.find(lower, "paladin") then return true end
    if string.find(lower, "hunter") then return true end
    if string.find(lower, "rogue") then return true end
    if string.find(lower, "priest") then return true end
    if string.find(lower, "shaman") then return true end
    if string.find(lower, "mage") then return true end
    if string.find(lower, "warlock") then return true end
    if string.find(lower, "druid") then return true end

    if string.find(lower, "human") then return true end
    if string.find(lower, "dwarf") then return true end
    if string.find(lower, "night elf") then return true end
    if string.find(lower, "gnome") then return true end
    if string.find(lower, "orc") then return true end
    if string.find(lower, "undead") then return true end
    if string.find(lower, "tauren") then return true end
    if string.find(lower, "troll") then return true end
    if string.find(lower, "goblin") then return true end
    if string.find(lower, "high elf") then return true end

    return false
end

local function SafeSetHyperlink(tooltip, link)
    if not link then return false end
    local _, _, itemString = string.find(link, "|H(item:[^|]+)|h")
    if not itemString and string.find(link, "^item:") then
        itemString = link
    end
    if not itemString then return false end

    local ok = pcall(tooltip.SetHyperlink, tooltip, itemString)
    return ok
end

local function PrepareTooltip(bagID, slotID, itemLink)
    local tooltip, tooltipName = addon.Modules.Utils:GetScanTooltip()
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tooltip:ClearLines()

    if bagID and slotID then
        if bagID == -1 then
            if not SafeSetHyperlink(tooltip, itemLink) then return nil, nil end
        else
            local ok = pcall(tooltip.SetBagItem, tooltip, bagID, slotID)
            if not ok then
                if not SafeSetHyperlink(tooltip, itemLink) then return nil, nil end
            end
        end
    elseif itemLink then
        if not SafeSetHyperlink(tooltip, itemLink) then return nil, nil end
    else
        return nil, nil
    end

    return tooltip, tooltipName
end

local function IsWhiteJunkCandidate(itemData)
    if not itemData then return false end

    local quality = tonumber(itemData.quality)
    local itemLink = itemData.link or ""
    if quality == nil and string.find(itemLink, "|cffffffff") then
        quality = 1
    end

    if quality ~= 1 then return false end
    if not (addon.Modules.DB and addon.Modules.DB:GetSetting("whiteItemsJunk")) then
        return false
    end

    local itemClass = itemData.class or ""
    if itemClass ~= "Weapon" and itemClass ~= "Armor" then return false end

    local subLower = string.lower(itemData.subclass or "")
    if string.find(subLower, "trinket")
        or string.find(subLower, "ring")
        or string.find(subLower, "neck")
        or string.find(subLower, "tabard")
        or string.find(subLower, "shirt")
        or string.find(subLower, "fishing pole")
        or string.find(subLower, "mining pick")
        or string.find(subLower, "skinning knife") then
        return false
    end

    local nameLower = string.lower(itemData.name or "")
    if string.find(nameLower, "mining pick")
        or string.find(nameLower, "skinning knife")
        or string.find(nameLower, "blacksmith hammer")
        or string.find(nameLower, "fishing pole")
        or string.find(nameLower, "gnomish army knife") then
        return false
    end

    return true
end

-- Single pass over the tooltip font strings. No `lines = {}` table and no
-- per-line `{left=..., r=...}` allocations are created.
local function ScanProperties(itemData, bagID, slotID)
    local result = {
        isQuestItem = false,
        isQuestStarter = false,
        isQuestUsable = false,
        isJunk = false,
        isPermanentEnchant = false,
        isUnusable = false,
    }

    if not itemData then return result, false end

    local quality = tonumber(itemData.quality)
    local itemLink = itemData.link or ""
    if quality == 0 or string.find(itemLink, "|cff9d9d9d") then
        result.isJunk = true
    end

    local excludedQuest = IsExcludedQuestItem(itemData)
    if not excludedQuest and itemData.class == "Quest" then
        result.isQuestItem = true
    end

    local whiteJunkCandidate = IsWhiteJunkCandidate(itemData)
    local whiteHasSpecialText = false

    local tooltip, tooltipName = PrepareTooltip(bagID, slotID, itemData.link)
    if not tooltip then return result, false end

    local numLines = tooltip:NumLines() or 0
    local complete = numLines >= 2
    local explicitCharges = nil

    for i = 1, numLines do
        local leftLine = getglobal(tooltipName .. "TextLeft" .. i)
        local rightLine = getglobal(tooltipName .. "TextRight" .. i)
        local leftText = leftLine and leftLine:GetText() or ""
        local rightText = rightLine and rightLine:GetText() or ""
        local leftLower = leftText ~= "" and string.lower(leftText) or ""

        -- Reuse this same tooltip pass for charge detection. This avoids a
        -- second synchronous tooltip scan later when ItemButton asks for xN.
        local _, _, chargeCount = string.find(leftLower, "^(%d+) charges?$")
        if chargeCount then
            explicitCharges = tonumber(chargeCount)
        end

        local lr, lg, lb = 1, 1, 1
        if leftLine and leftLine.GetTextColor then
            lr, lg, lb = leftLine:GetTextColor()
        end

        if string.find(leftLower, "permanently") then
            result.isPermanentEnchant = true
        end

        if not excludedQuest then
            if string.find(leftLower, "quest starter")
                or string.find(leftLower, "this item begins a quest")
                or string.find(leftLower, "begins a quest")
                or string.find(leftLower, "starts a quest") then
                result.isQuestItem = true
                result.isQuestStarter = true
            elseif string.find(leftLower, "quest item") then
                result.isQuestItem = true
            end
        end

        local isYellow = lr > 0.9 and lg > 0.75 and lb < 0.2
        local isGreen = lr < 0.3 and lg > 0.9 and lb < 0.3
        if (isYellow or isGreen) and string.find(leftLower, "use:") then
            result.isQuestUsable = true
        end

        if whiteJunkCandidate then
            if (isYellow and (string.find(leftLower, "use:") or string.find(leftLower, "equip:")))
                or isGreen then
                whiteHasSpecialText = true
            end
        end

        if i >= 2 then
            if IsRedColor(lr, lg, lb) then
                if not (durabilityPattern and string.find(leftText, durabilityPattern))
                    and IsRequirementText(leftText) then
                    result.isUnusable = true
                end
            end

            if rightLine and rightLine.GetTextColor and rightText ~= "" then
                local rr, rg, rb = rightLine:GetTextColor()
                if IsRedColor(rr, rg, rb) then
                    if not (durabilityPattern and string.find(rightText, durabilityPattern))
                        and IsRequirementText(rightText) then
                        result.isUnusable = true
                    end
                end
            end
        end
    end

    if whiteJunkCandidate and not whiteHasSpecialText then
        result.isJunk = true
    end

    if result.isPermanentEnchant then
        result.isQuestItem = false
        result.isQuestStarter = false
        result.isQuestUsable = false
    end

    -- Seed the per-slot charge cache from the property scan we already paid
    -- for. Store the item link with the result so slot swaps cannot reuse stale
    -- charge data.
    if bagID and slotID and complete then
        local slotKey = bagID .. ":" .. slotID
        chargesCache[slotKey] = {
            link = itemData.link,
            charges = explicitCharges or false,
        }
        if explicitCharges and itemData.link then
            chargeCapableLinks[itemData.link] = true
        end
    end

    return result, complete
end

function ItemDetection:ClearCache()
    detectionCache = {}
    cacheHits = 0
    cacheMisses = 0
end

function ItemDetection:InvalidateItem(itemLink)
    if itemLink then detectionCache[itemLink] = nil end
end

function ItemDetection:InvalidateItems(itemLinks)
    if not itemLinks then return end
    for _, link in ipairs(itemLinks) do
        if link then detectionCache[link] = nil end
    end
end

function ItemDetection:IsCached(itemLink)
    return itemLink and detectionCache[itemLink] ~= nil
end

function ItemDetection:GetCacheStats()
    local total = cacheHits + cacheMisses
    local size = 0
    for _ in pairs(detectionCache) do size = size + 1 end
    return {
        hits = cacheHits,
        misses = cacheMisses,
        total = total,
        hitRate = total > 0 and (cacheHits / total * 100) or 0,
        size = size,
    }
end

function ItemDetection:GetItemProperties(itemData, bagID, slotID)
    if not itemData then return EMPTY_PROPERTIES end

    local cacheKey = GetCacheKey(itemData.link)
    if cacheKey and detectionCache[cacheKey] then
        cacheHits = cacheHits + 1
        return detectionCache[cacheKey]
    end

    cacheMisses = cacheMisses + 1
    local result, complete = ScanProperties(itemData, bagID, slotID)

    if cacheKey and complete then
        detectionCache[cacheKey] = result
    end

    return result
end

function ItemDetection:IsUnusableCached(itemData)
    if not itemData or not itemData.link then return nil end
    local props = detectionCache[GetCacheKey(itemData.link)]
    if not props then return nil end
    return props.isUnusable
end

addon:Debug("ClassicAPI single-pass ItemDetection enabled")

--=====================================================
-- Explicit charge overlay cache
--=====================================================
-- ClassicAPI charge values can mirror ordinary stack counts on this client,
-- so a yellow xN overlay is still shown only after the tooltip explicitly
-- confirms a Charges line. The cache below keeps negative results across bag
-- updates and invalidates real charge items conservatively.

local function ChargeSafeSetHyperlink(tooltip, link)
    if not link then return false end
    local _, _, bare = string.find(link, "|H(item:[^|]+)|h")
    if not bare and string.find(link, "^item:") then bare = link end
    if not bare then return false end
    return pcall(tooltip.SetHyperlink, tooltip, bare)
end

local function GetExplicitTooltipCharges(itemData, bagID, slotID)
    local tooltip, tooltipName = addon.Modules.Utils:GetScanTooltip()
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tooltip:ClearLines()

    local ok = false
    if bagID and slotID and bagID ~= -1 then
        ok = pcall(tooltip.SetBagItem, tooltip, bagID, slotID)
    end
    if not ok then
        ok = ChargeSafeSetHyperlink(tooltip, itemData and itemData.link)
    end
    if not ok then return nil, false end

    local numLines = tooltip:NumLines() or 0
    for i = 1, numLines do
        local line = getglobal(tooltipName .. "TextLeft" .. i)
        local text = line and line:GetText()
        if text then
            local _, _, num = string.find(string.lower(text), "^(%d+) charges?$")
            if num then return tonumber(num), numLines >= 2 end
        end
    end
    return nil, numLines >= 2
end

function ItemDetection:GetCharges(itemData, bagID, slotID)
    if not bagID or not slotID then return nil end

    local slotKey = bagID .. ":" .. slotID
    local itemLink = itemData and itemData.link or nil
    local cached = chargesCache[slotKey]

    -- A slot cache is valid only for the exact item link currently occupying
    -- it. Normal stacks usually hit the cached `false` path here with no
    -- tooltip work at all.
    if cached and cached.link == itemLink then
        if cached.charges == false then return nil end
        return cached.charges
    end

    local charges, complete = GetExplicitTooltipCharges(itemData, bagID, slotID)
    if complete then
        chargesCache[slotKey] = {
            link = itemLink,
            charges = charges or false,
        }
        if charges and itemLink then
            chargeCapableLinks[itemLink] = true
        end
    end
    return charges
end

function ItemDetection:InvalidateCharges(bagID)
    if not bagID then
        chargesCache = {}
        chargeCapableLinks = {}
        return
    end

    local prefix = bagID .. ":"
    for key, cached in pairs(chargesCache) do
        if string.find(key, "^" .. prefix) then
            -- Keep proven negative results for ordinary items. A changed slot
            -- is still safe because GetCharges validates cached.link against
            -- the current item link. Real/known charge items are discarded so
            -- their remaining charge count is refreshed exactly from tooltip.
            if not cached or cached.charges ~= false
               or (cached.link and chargeCapableLinks[cached.link]) then
                chargesCache[key] = nil
            end
        end
    end
end

addon:Debug("Explicit charge cache optimization enabled")

--=====================================================
-- Consolidated from Core/ItemDetectionCacheSafety.lua
--=====================================================
-- Guda ClassicAPI ItemDetection cache safety
-- Keep the optimized detection cache and the legacy per-slot charge cache in
-- sync when ClassicAPI charge access is unavailable.
-- Lua 5.0 compatible.

local addon = Guda
local ItemDetection = addon.Modules.ItemDetection
if not ItemDetection then return end

local FastClearCache = ItemDetection.ClearCache

function ItemDetection:ClearCache()
    if FastClearCache then
        FastClearCache(self)
    end

    -- ItemDetectionClassicAPI keeps the original Vanilla charge-cache
    -- invalidator behind this public method. With ClassicAPI charges present
    -- it is a no-op; without them it clears the legacy bagID:slotID cache.
    if self.InvalidateCharges then
        self:InvalidateCharges(nil)
    end
end

addon:Debug("ClassicAPI ItemDetection cache safety enabled")
