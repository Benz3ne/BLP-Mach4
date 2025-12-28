function PLC(inst)
    local startTime = os.clock() * 1000  -- Convert to milliseconds


    local rc = 0;
    testcount = testcount + 1
    machState, rc = mc.mcCntlGetState(inst);
    local inCycle = mc.mcCntlIsInCycle(inst);

    --  Coroutine resume
    if (wait ~= nil) and (machState == 0) then --wait exist and state == idle
        local state = coroutine.status(wait)
        if state == "suspended" then --wait is suspended
            coroutine.resume(wait)
        end
    end

    if machState == 0 or machState == 4 then
        SyncMPG()
        ProbeCrashCheck()
        ProcessDeferredGCode()

        -- This handles edge cases where M6 flag doesn't get cleared properly
        if mc.mcCntlGetPoundVar(inst, 499) == 1 then
            mc.mcCntlSetPoundVar(inst, 499, 0)
        end
    end

    -- Check for dialog request
    local hRequest = mc.mcRegGetHandle(inst, "iRegs0/DialogRequest")
    if hRequest ~= 0 and mc.mcRegGetValue(hRequest) == 1 then
        ProcessDialogRequest()
    end

    -- Check for maintenance request (from ProbeScripts macros)
    local hMaintReq = mc.mcRegGetHandle(inst, "iRegs0/MaintenanceRequest")
    if hMaintReq ~= 0 and mc.mcRegGetValue(hMaintReq) == 1 then
        MaintenanceItems()  -- This sets MaintenanceResult
        mc.mcRegSetValue(hMaintReq, 0)  -- Clear AFTER dialog is done
    end

    --  Cycle time label update
    if (machEnabled == 1) then
        local cycletime = mc.mcCntlGetRunTime(inst, time)
        scr.SetProperty("CycleTime", "Label", SecondsToTime(cycletime))
    end

    local execTime = (os.clock() * 1000) - startTime
    --GetPLCStats(execTime)  -- Comment out when not debugging
    
    --This is the last thing we do.  So keep it at the end of the script!
    machStateOld = machState;
    machWasEnabled = machEnabled;
end