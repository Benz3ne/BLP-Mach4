-- DebugExecute.lua - Automated CycleStop bug diagnosis
-- Fully automatic - no user interaction required

local inst = mc.mcGetInstance()
local logPath = "C:\\Mach4Hobby\\Profiles\\BLP\\Logs\\CycleStopDebug.txt"
local logFile = io.open(logPath, "w")

if not logFile then
    wx.wxMessageBox("Failed to open log file", "Error", wx.wxOK)
    return
end

local function log(msg)
    local line = string.format("[%s] %s\n", os.date("%H:%M:%S"), msg)
    logFile:write(line)
    logFile:flush()
end

local function testGcodeExecution()
    -- Returns true if G-code execution works, false if blocked
    local startTime = os.clock()
    local rc = mc.mcCntlGcodeExecuteWait(inst, "G4 P100")  -- 100ms dwell
    local elapsed = (os.clock() - startTime) * 1000
    return rc == 0 and elapsed < 500, rc, elapsed  -- Should complete in < 500ms
end

log("========================================")
log("AUTOMATED CYCLESTOP BUG DIAGNOSIS")
log("========================================")
log("")
log(string.format("Initial state: %d", mc.mcCntlGetState(inst)))
log("")

-- Test 1: Baseline - does G-code work normally?
log("=== TEST 1: BASELINE ===")
local works, rc, elapsed = testGcodeExecution()
log(string.format("G-code execution: %s (rc=%d, %.0fms)", works and "WORKS" or "BLOCKED", rc, elapsed))
log("")

-- Test 2: Start G-code, call CycleStop, test again
log("=== TEST 2: INTERRUPT WITH CYCLESTOP ===")
log("Starting G4 P2000 (2 sec dwell)...")
mc.mcCntlGcodeExecute(inst, "G4 P2000")  -- Non-blocking
log(string.format("State after execute: %d", mc.mcCntlGetState(inst)))

wx.wxMilliSleep(200)  -- Let it start
log(string.format("State after 200ms: %d", mc.mcCntlGetState(inst)))

log("Calling CycleStop()...")
CycleStop()  -- Call the ScreenLoad function
log(string.format("State after CycleStop: %d", mc.mcCntlGetState(inst)))

wx.wxMilliSleep(100)
log("")
log("Testing G-code execution after CycleStop...")
works, rc, elapsed = testGcodeExecution()
log(string.format("G-code execution: %s (rc=%d, %.0fms)", works and "WORKS" or "BLOCKED", rc, elapsed))
log("")

-- Test 3: If blocked, try recovery methods one at a time
if not works then
    log("=== TEST 3: RECOVERY ATTEMPTS ===")

    local recoveryMethods = {
        {"mcCntlCycleStop", function() mc.mcCntlCycleStop(inst) end},
        {"mcCntlMachineStateClear", function() mc.mcCntlMachineStateClear(inst) end},
        {"mcCntlReset", function() mc.mcCntlReset(inst) end},
    }

    for _, method in ipairs(recoveryMethods) do
        log(string.format("Trying %s...", method[1]))
        pcall(method[2])
        wx.wxMilliSleep(100)

        works, rc, elapsed = testGcodeExecution()
        log(string.format("  Result: %s (rc=%d, %.0fms)", works and "WORKS" or "STILL BLOCKED", rc, elapsed))

        if works then
            log(string.format("  >>> %s FIXED IT <<<", method[1]))
            break
        end
        log("")
    end
else
    log("=== TEST 3: SKIPPED (not blocked) ===")
    log("Bug not reproduced with non-blocking execute + CycleStop")
    log("")
    log("The bug likely requires interrupting mcCntlGcodeExecuteWait specifically.")
    log("This happens when cycle stop is pressed during a blocking operation")
    log("like probing or running a macro with GcodeExecuteWait.")
end

log("")
log("========================================")
log("DIAGNOSIS COMPLETE")
log("========================================")
log(string.format("Final state: %d", mc.mcCntlGetState(inst)))

logFile:close()

-- Show summary
local resultFile = io.open(logPath, "r")
local results = resultFile:read("*a")
resultFile:close()

wx.wxMessageBox(results, "CycleStop Debug Results", wx.wxOK)
