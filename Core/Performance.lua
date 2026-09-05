-- Guda low-latency work queue
-- Replaces Utils' original table.remove(1) queue with an O(1) FIFO and uses
-- a much smaller frame budget suitable for WoW 1.12.1.

local addon = Guda
local Utils = addon.Modules.Utils
if not Utils then return end

local FRAME_BUDGET_SECONDS = 0.003 -- 3 ms target budget per frame
local MAX_WORK_PER_FRAME = 8

local callbacks = {}
local contexts = {}
local queueHead = 1
local queueTail = 0
local workQueueFrame = nil
local workQueuePaused = false
local lastEntryTime = 0

local performanceStats = {
    budgetExceededCount = 0,
    totalUpdates = 0,
    lastUpdateDuration = 0,
    averageUpdateDuration = 0,
}

local function QueueSize()
    if queueTail < queueHead then return 0 end
    return queueTail - queueHead + 1
end

local function ResetQueueStorage()
    callbacks = {}
    contexts = {}
    queueHead = 1
    queueTail = 0
end

function Utils:ReportEntry()
    lastEntryTime = GetTime()
end

function Utils:CheckTimeout()
    return (GetTime() - lastEntryTime) >= FRAME_BUDGET_SECONDS
end

local function EnsureWorkQueueFrame()
    if workQueueFrame then return end

    workQueueFrame = CreateFrame("Frame", "Guda_WorkQueueFrame_ClassicAPI", UIParent)
    workQueueFrame:Hide()

    workQueueFrame:SetScript("OnUpdate", function()
        Utils:ReportEntry()

        local processedCount = 0
        while queueHead <= queueTail and processedCount < MAX_WORK_PER_FRAME do
            -- Always allow at least one unit of work to make forward progress.
            if processedCount > 0 and Utils:CheckTimeout() then
                performanceStats.budgetExceededCount =
                    performanceStats.budgetExceededCount + 1
                break
            end

            local callback = callbacks[queueHead]
            local context = contexts[queueHead]
            callbacks[queueHead] = nil
            contexts[queueHead] = nil
            queueHead = queueHead + 1

            if callback then
                local success, err = pcall(callback)
                if not success then
                    addon:Error("QueueWork callback error [%s]: %s",
                        tostring(context or "unknown"), tostring(err))
                end
            end

            processedCount = processedCount + 1
        end

        local duration = GetTime() - lastEntryTime
        performanceStats.lastUpdateDuration = duration
        performanceStats.totalUpdates = performanceStats.totalUpdates + 1
        performanceStats.averageUpdateDuration =
            performanceStats.averageUpdateDuration * 0.9 + duration * 0.1

        if queueHead > queueTail then
            ResetQueueStorage()
            this:Hide()
        end
    end)
end

function Utils:QueueWork(callback, context)
    if type(callback) ~= "function" then
        addon:Error("QueueWork: callback must be a function")
        return
    end

    queueTail = queueTail + 1
    callbacks[queueTail] = callback
    contexts[queueTail] = context or "unknown"

    EnsureWorkQueueFrame()
    if not workQueuePaused then
        workQueueFrame:Show()
    end
end

function Utils:ClearWorkQueue()
    ResetQueueStorage()
    if workQueueFrame then
        workQueueFrame:Hide()
    end
end

function Utils:PauseWorkQueue()
    workQueuePaused = true
    if workQueueFrame then
        workQueueFrame:Hide()
    end
end

function Utils:ResumeWorkQueue()
    workQueuePaused = false
    if QueueSize() > 0 then
        EnsureWorkQueueFrame()
        workQueueFrame:Show()
    end
end

function Utils:GetWorkQueueSize()
    return QueueSize()
end

function Utils:GetFrameBudget()
    return FRAME_BUDGET_SECONDS
end

function Utils:SetFrameBudget(seconds)
    if type(seconds) ~= "number" then return end
    FRAME_BUDGET_SECONDS = math.max(0.001, math.min(0.05, seconds))
    addon:Debug("Frame budget set to %.3f seconds", FRAME_BUDGET_SECONDS)
end

function Utils:RecordUpdateEnd()
    local duration = GetTime() - lastEntryTime
    performanceStats.lastUpdateDuration = duration
    performanceStats.totalUpdates = performanceStats.totalUpdates + 1
    performanceStats.averageUpdateDuration =
        performanceStats.averageUpdateDuration * 0.9 + duration * 0.1

    if duration > FRAME_BUDGET_SECONDS then
        performanceStats.budgetExceededCount =
            performanceStats.budgetExceededCount + 1
    end
end

function Utils:GetPerformanceStats()
    return {
        frameBudget = FRAME_BUDGET_SECONDS,
        lastUpdateDuration = performanceStats.lastUpdateDuration,
        averageUpdateDuration = performanceStats.averageUpdateDuration,
        totalUpdates = performanceStats.totalUpdates,
        budgetExceededCount = performanceStats.budgetExceededCount,
        workQueueSize = QueueSize(),
    }
end

function Utils:ResetPerformanceStats()
    performanceStats.budgetExceededCount = 0
    performanceStats.totalUpdates = 0
    performanceStats.lastUpdateDuration = 0
    performanceStats.averageUpdateDuration = 0
end

function Utils:PrintPerformanceStats()
    local stats = self:GetPerformanceStats()
    addon:Print(Guda_L["=== Guda Performance Stats ==="])
    addon:Print(Guda_L["Frame Budget: %.0fms"], stats.frameBudget * 1000)
    addon:Print(Guda_L["Last Update: %.1fms"], stats.lastUpdateDuration * 1000)
    addon:Print("Avg Update: %.1fms", stats.averageUpdateDuration * 1000)
    addon:Print(Guda_L["Total Updates: %d"], stats.totalUpdates)
    addon:Print(Guda_L["Budget Exceeded: %d times"], stats.budgetExceededCount)
    addon:Print("Work Queue: %d items", stats.workQueueSize)
end
