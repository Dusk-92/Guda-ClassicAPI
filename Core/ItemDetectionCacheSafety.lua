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
