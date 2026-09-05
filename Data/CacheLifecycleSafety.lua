-- Guda ClassicAPI cache lifecycle safety
-- Whole-cache invalidation is deferred to in-place dirty refreshes while the
-- corresponding UI is visible. This prevents pooled item tables still held by
-- visible buttons from being cleared/reused before their redraw runs.
-- Lua 5.0 compatible.

local addon = Guda
local BagScanner = addon.Modules.BagScanner
local BankScanner = addon.Modules.BankScanner
if not BagScanner or not BankScanner then return end

local oldBagClearCache = BagScanner.ClearCache
local oldBagInvalidateCache = BagScanner.InvalidateCache
local oldBankClearCache = BankScanner.ClearCache
local oldBankInvalidateCache = BankScanner.InvalidateCache

local function IsShown(name)
    local frame = getglobal(name)
    return frame and frame.IsShown and frame:IsShown()
end

local function MarkAllBagsDirty()
    if addon.Constants and addon.Constants.BAGS then
        for _, bagID in ipairs(addon.Constants.BAGS) do
            BagScanner:InvalidateBag(bagID)
        end
    else
        for bagID = 0, 4 do
            BagScanner:InvalidateBag(bagID)
        end
    end
    BagScanner:InvalidateBag(-2)
end

local function MarkAllBankBagsDirty()
    if addon.Constants and addon.Constants.BANK_BAGS then
        for _, bagID in ipairs(addon.Constants.BANK_BAGS) do
            BankScanner:InvalidateBag(bagID)
        end
    end
end

function BagScanner:ClearCache()
    if IsShown("Guda_BagFrame") then
        MarkAllBagsDirty()
        return
    end
    return oldBagClearCache(self)
end

function BagScanner:InvalidateCache()
    if IsShown("Guda_BagFrame") then
        MarkAllBagsDirty()
        return
    end
    return oldBagInvalidateCache(self)
end

function BankScanner:ClearCache()
    if BankScanner:IsBankOpen() and IsShown("Guda_BankFrame") then
        MarkAllBankBagsDirty()
        return
    end
    return oldBankClearCache(self)
end

function BankScanner:InvalidateCache()
    if BankScanner:IsBankOpen() and IsShown("Guda_BankFrame") then
        MarkAllBankBagsDirty()
        return
    end
    return oldBankInvalidateCache(self)
end

addon:Debug("ClassicAPI cache lifecycle safety enabled")
