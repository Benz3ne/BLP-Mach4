pageId = 0
screenId = 0
testcount = 0
machState = 0
machStateOld = -1
MachineEnabledTime = 0
machEnabled = 0
machWasEnabled = 0
inst = mc.mcGetInstance()

if UIUpdateTimer then
    UIUpdateTimer:Stop()
    UIUpdateTimer = nil
    mc.mcCntlSetLastError(inst, "Reset UI Timer")
end

--mobdebug = require('mobdebug')
--mobdebug.onexit = mobdebug.done
--mobdebug.start() -- This line is to start the debug Process Comment out for no debuging

local machDir = mc.mcCntlGetMachDir(inst)
local profile = mc.mcProfileGetName(inst)
_G.ROOT = _G.ROOT or (machDir .. "\\Profiles\\" .. profile .. "\\Scripts")
_G.SYS = _G.SYS or (_G.ROOT .. "\\System")
local DEPS = _G.ROOT .. "\\Dependencies"
package.path = DEPS .. "\\?.txt;" .. DEPS .. "\\?.lua;" .. package.path
dofile(_G.ROOT .. "\\ButtonScripts.lua")



handles = {
    sig_mpg = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_MPG),
    sig_cont = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_CONT),
    sig_inc = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_INC),
    sig_enabled = mc.mcSignalGetHandle(inst, mc.OSIG_MACHINE_ENABLED),
    sig_running = mc.mcSignalGetHandle(inst, mc.OSIG_RUNNING_GCODE),
    sig_jogging = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_ENABLED)
}
state = {
    mach_state = -1,      -- Machine state (100-299 = running)
    mpg_mode = -1,        -- MPG jog active
    fro = -1,             -- Feed rate override
    motor_mode = nil      -- Current motor dynamics mode
}

-- Signal Library
SigLib = {
[mc.OSIG_MACHINE_ENABLED] = function(state)
    machEnabled = state

    if state == 0 then
        SafeRetractVirtual()
    else
        MachineEnabledTime = os.clock()  -- Record enable time
        ToggleSoftLimits("enable")
        KeyboardInputsToggle("enable")
        CheckAirPressure()
        SpindleToolDialog()
        InitializeJog()
    end
end,

[mc.OSIG_RUNNING_GCODE] = function(state)
    DustAutomation()
end,

[mc.ISIG_INPUT6] = function(state)
    CheckAirPressure()
end,

[mc.ISIG_INPUT8] = function(state)
    if machEnabled == 1 and (os.clock() - MachineEnabledTime) > 2 then
        SpindleToolDialog()
    end
end,

[mc.ISIG_INPUT17] = function(state)
    SpindleToolPresenceChanged(state)
end,

[mc.OSIG_JOG_CONT] = function (state)
    if( state == 1) then 
       scr.SetProperty('labJogMode', 'Label', 'Continuous');
       scr.SetProperty('txtJogInc', 'Bg Color', '#C0C0C0');
       scr.SetProperty('txtJogInc', 'Fg Color', '#808080');
    end
end,

[mc.OSIG_JOG_INC] = function (state)
    if( state == 1) then
        scr.SetProperty('labJogMode', 'Label', 'Incremental');
        scr.SetProperty('txtJogInc', 'Bg Color', '#FFFFFF'); 
        scr.SetProperty('txtJogInc', 'Fg Color', '#000000');
   end
end,

[mc.OSIG_JOG_MPG] = function (state)
    if( state == 1) then
        scr.SetProperty('labJogMode', 'Label', '');
        scr.SetProperty('txtJogInc', 'Bg Color', '#C0C0C0');
        scr.SetProperty('txtJogInc', 'Fg Color', '#808080');
    end
end
}

-- Message Library
MsgLib = {
	[mc.MSG_REG_CHANGED] = function (param1, param2)
	end
}

function DebugExecute()
    local inst = mc.mcGetInstance()
    local profile = mc.mcProfileGetName(inst)
    local path = mc.mcCntlGetMachDir(inst) .. "\\Profiles\\" .. profile .. "\\Scripts\\DebugExecute.lua"
    dofile(path)
end

-- Initialize jog parameters
function InitializeJog()
    local rate = 10
    mc.mcJogSetRate(inst, 0, rate)
    mc.mcJogSetAccel(inst, 0, 15)    
    mc.mcJogSetRate(inst, 1, rate)
    mc.mcJogSetAccel(inst, 1, 15)
    mc.mcJogSetRate(inst, 2, rate)
    mc.mcJogSetAccel(inst, 2, 10)
end

-- Remember Position function.
function RememberPosition()
    local x = mc.mcAxisGetMachinePos(inst, 0)
    local y = mc.mcAxisGetMachinePos(inst, 1) 
    local z = mc.mcAxisGetMachinePos(inst, 2)
    mc.mcProfileWriteString(inst, "SavedPositions.default", "MachineX", tostring(x))
    mc.mcProfileWriteString(inst, "SavedPositions.default", "MachineY", tostring(y))
    mc.mcProfileWriteString(inst, "SavedPositions.default", "MachineZ", tostring(z))
    mc.mcProfileWriteString(inst, "SavedPositions.default", "Timestamp", tostring(os.time()))
end

function ReturnToPosition()
    local x = tonumber(mc.mcProfileGetString(inst, "SavedPositions.default", "MachineX", ""))
    local y = tonumber(mc.mcProfileGetString(inst, "SavedPositions.default", "MachineY", ""))
    local z = tonumber(mc.mcProfileGetString(inst, "SavedPositions.default", "MachineZ", ""))
    if not x or not y or not z then
        wx.wxMessageBox("Position not found.\n\nSave a position first.", "Position Not Found", wx.wxOK + wx.wxICON_WARNING)
        return false
    end
    -- Move to safe Z first, then XY, then Z
    mc.mcCntlGcodeExecuteWait(inst, string.format("G90 G53 G0 Z-0.050"))
    mc.mcCntlGcodeExecuteWait(inst, string.format("G90 G53 G0 X%.4f Y%.4f", x, y))
    mc.mcCntlGcodeExecuteWait(inst, string.format("G90 G53 G0 Z%.4f", z))
end

-- Probe safety check function
function ProbeCrashCheck()
    local hsig = mc.mcSignalGetHandle(inst, mc.ISIG_PROBE1)
    local probeState = mc.mcSignalGetState(hsig)
    local currentTool = mc.mcToolGetCurrent(inst)

    -- Only check for probe crash if current tool is T90 (probe tool) and probe signal is high
    if probeState == 1 and currentTool == 90 then
        mc.mcCntlEStop(inst)
        mc.mcCntlSetLastError(inst, "PROBE CRASH - Emergency Stop activated")
    end
end

-- Spin CW function.
function SpinCW()
    local sigh = mc.mcSignalGetHandle(inst, mc.OSIG_SPINDLEON);
    local sigState = mc.mcSignalGetState(sigh);
    
    if (sigState == 1) then 
        mc.mcSpindleSetDirection(inst, 0);
    else 
        mc.mcSpindleSetDirection(inst, 1);
    end
end

-- Spin CCW function.
function SpinCCW()
    local sigh = mc.mcSignalGetHandle(inst, mc.OSIG_SPINDLEON);
    local sigState = mc.mcSignalGetState(sigh);
    
    if (sigState == 1) then 
        mc.mcSpindleSetDirection(inst, 0);
    else 
        mc.mcSpindleSetDirection(inst, -1);
    end
end

-- Toggle Spindle function with RPM dialog
function ToggleSpindle()
    local sigh = mc.mcSignalGetHandle(inst, mc.OSIG_SPINDLEON)
    local spindleOn = mc.mcSignalGetState(sigh)

    if spindleOn == 1 then
        mc.mcSpindleSetDirection(inst, 0)
        return
    end

    local dialog = wx.wxDialog(wx.NULL, wx.wxID_ANY, "Spindle Control", 
                               wx.wxDefaultPosition, wx.wxSize(250, 160))
    local panel = wx.wxPanel(dialog, wx.wxID_ANY)
    local sizer = wx.wxBoxSizer(wx.wxVERTICAL)

    sizer:Add(wx.wxStaticText(panel, wx.wxID_ANY, "RPM (0-24000):"), 0, wx.wxALL, 5)
    local rpmInput = wx.wxSpinCtrl(panel, wx.wxID_ANY, "1000",
                                   wx.wxDefaultPosition, wx.wxDefaultSize,
                                   wx.wxSP_ARROW_KEYS, 0, 24000, 1000)
    sizer:Add(rpmInput, 0, wx.wxEXPAND + wx.wxALL, 5)

    local reverseCheckbox = wx.wxCheckBox(panel, wx.wxID_ANY, "Reverse")
    sizer:Add(reverseCheckbox, 0, wx.wxALL, 5)

    local btnSizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
    local okButton = wx.wxButton(panel, wx.wxID_OK, "OK")
    local cancelButton = wx.wxButton(panel, wx.wxID_CANCEL, "Cancel")
    okButton:SetDefault()
    btnSizer:Add(okButton, 0, wx.wxALL, 5)
    btnSizer:Add(cancelButton, 0, wx.wxALL, 5)
    sizer:Add(btnSizer, 0, wx.wxALIGN_CENTER + wx.wxALL, 5)
    
    panel:SetSizer(sizer)
    dialog:Centre()
    
    if dialog:ShowModal() == wx.wxID_OK then
        local rpm = rpmInput:GetValue()
        local direction = reverseCheckbox:GetValue() and -1 or 1
        mc.mcSpindleSetCommandRPM(inst, rpm)
        mc.mcSpindleSetDirection(inst, direction)
    end

    dialog:Destroy()
end

-- Open Docs function.
function OpenDocs()
    local major, minor = wx.wxGetOsVersion()
    local dir = mc.mcCntlGetMachDir(inst);
    local cmd = "explorer.exe /open," .. dir .. "\\Docs\\"
    if(minor <= 5) then -- Xp we don't need the /open
        cmd = "explorer.exe ," .. dir .. "\\Docs\\"
    end
	os.execute(cmd) -- another way to execute a program.
    --wx.wxExecute(cmd);
	scr.RefreshScreen(250); -- Windows 7 and 8 seem to require the screen to be refreshed.  
end

function CheckAirPressure()
    local hAir = mc.mcSignalGetHandle(inst, mc.ISIG_INPUT6)
    local airState = mc.mcSignalGetState(hAir)
   
    if airState == 0 then
        mc.mcCntlEStop(inst)
        mc.mcCntlSetLastError(inst, "No air pressure - E-Stop")
    end
end

-- Cycle Stop function.
function CycleStop()
    mc.mcCntlCycleStop(inst);
    mc.mcSpindleSetDirection(inst, 0);

    -- Reset dangerous modal states for safety
    mc.mcCntlGcodeExecute(inst, "G20 G17 G90 G67 G80 G40 G49 G94 G97 G50 M5 M9");

    mc.mcCntlSetLastError(inst, "Cycle Stopped");
    if(wait ~= nil) then
        wait = nil;
    end
end

-- Button Jog Mode Toggle() function
function ButtonJogModeToggle()
    local cont = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_CONT)
    local inc = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_INC)
    local mpg = mc.mcSignalGetHandle(inst, mc.OSIG_JOG_MPG)
    
    local isCont = mc.mcSignalGetState(cont) == 1
    
    mc.mcSignalSetState(cont, isCont and 0 or 1)
    mc.mcSignalSetState(inc, isCont and 1 or 0)
    mc.mcSignalSetState(mpg, 0)
end

-- Helper function for PLC-resumed coroutines
function RunWithPLC(func)
    wait = coroutine.create(func)
    coroutine.resume(wait)
end

-- Ref all axes: call with RunWithPLC(RefAllHome)
function RefAllHome()
    mc.mcAxisDerefAll(inst)  
    mc.mcAxisHomeAll(inst)
    coroutine.yield()
    mc.mcCntlGcodeExecuteWait(inst, "G53 G1 X0 Y0 Z0 F50")
end

-- Go To Work Zero() function.
function GoToWorkZero()
    mc.mcCntlMdiExecute(inst, "G00 X0 Y0")--Without Z moves
    --mc.mcCntlMdiExecute(inst, "G00 G53 Z-0.050\nG00 X0 Y0 A0\nG00 Z-0.050")--With Z moves
end

-- Set Feed Rate Override
function SetFRO(value)
    mc.mcCntlSetFRO(inst, value)
    scr.SetProperty("slideFRO", "Value", tostring(value))
end

-- Set Rapid Rate Override
function SetRRO(value)
    mc.mcCntlSetRRO(inst, value)
    scr.SetProperty("slideRRO", "Value", tostring(value))
end

-- Set Spindle Rate Override
function SetSRO(value)
    mc.mcSpindleSetOverride(inst, value)
    scr.SetProperty("slideSRO", "Value", tostring(value))
end

-- Helper function for Run From Here functionality
function RunFromHere()
    local selectedLine = mc.mcCntlGetGcodeLineNbr(inst)

    -- If at beginning, no need for run-from-here
    if selectedLine <= 1 then
        return false  -- Continue with normal cycle start
    end

    -- Check if we're in a canned cycle and find safe line
    local safeLine = selectedLine - 1  -- Convert to 0-indexed
    local adjustmentWarning = nil

    -- Simple scan backwards for canned cycle
    for i = selectedLine - 2, 0, -1 do
        local line = mc.mcCntlGetGcodeLine(inst, i)
        if line then
            local cleanLine = line:gsub("%(.*%)", ""):gsub(";.*", ""):upper()
            if cleanLine:match("G8[1-9]") then
                -- Found start of canned cycle, use this line
                safeLine = i
                adjustmentWarning = string.format("Starting from line %d (canned cycle start)", i + 1)
                break
            elseif cleanLine:match("G80") then
                -- Found cycle cancel before finding start, we're safe
                break
            end
        end
    end

    -- Collect machine state from gcode
    local state = {
        x = nil, y = nil, z = nil,
        tool = nil,
        spindleSpeed = nil,
        spindleDir = "M5",
        feedRate = nil,
        coolant = "M9",
        workOffset = nil
    }

    -- Scan backwards to collect state
    for i = safeLine, 0, -1 do
        local line = mc.mcCntlGetGcodeLine(inst, i)
        if line then
            local cleanLine = line:gsub("%(.*%)", ""):gsub(";.*", ""):upper()

            -- Tool change
            if not state.tool then
                local tool = cleanLine:match("T(%d+)")
                if tool then state.tool = tonumber(tool) end
            end

            -- Spindle
            if not state.spindleSpeed then
                local speed = cleanLine:match("S(%d+)")
                if speed then state.spindleSpeed = tonumber(speed) end
            end

            if cleanLine:match("M3") then
                state.spindleDir = "M3"
            elseif cleanLine:match("M4") then
                state.spindleDir = "M4"
            elseif cleanLine:match("M5") then
                state.spindleDir = "M5"
            end

            -- Coolant
            if cleanLine:match("M7") then
                state.coolant = "M7"
            elseif cleanLine:match("M8") then
                state.coolant = "M8"
            elseif cleanLine:match("M9") then
                state.coolant = "M9"
            end

            -- Feed rate
            if not state.feedRate then
                local feed = cleanLine:match("F(%d+%.?%d*)")
                if feed then state.feedRate = tonumber(feed) end
            end

            -- Work offset
            if not state.workOffset and cleanLine:match("G5[4-9]") then
                state.workOffset = cleanLine:match("(G5[4-9])")
            end

            -- Positions
            local x = cleanLine:match("X(%-?%d+%.?%d*)")
            local y = cleanLine:match("Y(%-?%d+%.?%d*)")
            local z = cleanLine:match("Z(%-?%d+%.?%d*)")

            if x and not state.x then state.x = tonumber(x) end
            if y and not state.y then state.y = tonumber(y) end
            if z and not state.z then state.z = tonumber(z) end

            -- Stop if we hit M30 or M2
            if cleanLine:match("M30") or cleanLine:match("M2%s") or cleanLine:match("M2$") then
                break
            end
        end
    end

    -- Build preview message
    local selectedContent = mc.mcCntlGetGcodeLine(inst, selectedLine) or ""
    local message = string.format("Run from line %d?\n────────────────\nSelected: %s\n",
                                 selectedLine + 1, selectedContent)

    if adjustmentWarning then
        message = message .. "\n⚠ " .. adjustmentWarning .. "\n"
    end

    message = message .. "\nMachine will be prepared with:\n"

    if state.tool then
        message = message .. string.format("• Tool: T%d\n", state.tool)
    end

    if state.spindleDir ~= "M5" and state.spindleSpeed then
        message = message .. string.format("• Spindle: S%d %s\n", state.spindleSpeed, state.spindleDir)
    end

    if state.workOffset then
        message = message .. string.format("• Work Offset: %s\n", state.workOffset)
    end

    if state.x and state.y and state.z then
        message = message .. string.format("• Position: X%.4f Y%.4f Z%.4f\n", state.x, state.y, state.z)
    else
        message = message .. "• Position: ERROR - Missing coordinate data\n"
    end

    if state.coolant ~= "M9" then
        message = message .. string.format("• Coolant: %s\n", state.coolant)
    end

    -- Show first dialog
    local dialog = wx.wxDialog(wx.NULL, wx.wxID_ANY, "Run From Here",
                              wx.wxDefaultPosition, wx.wxDefaultSize)

    local panel = wx.wxPanel(dialog, wx.wxID_ANY)
    local sizer = wx.wxBoxSizer(wx.wxVERTICAL)

    local text = wx.wxStaticText(panel, wx.wxID_ANY, message)
    sizer:Add(text, 0, wx.wxALL, 15)

    sizer:AddSpacer(10)  -- Add some space between text and buttons

    -- Button sizer
    local btnSizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
    local runBtn = wx.wxButton(panel, wx.wxID_ANY, "Run From Here")
    local beginBtn = wx.wxButton(panel, wx.wxID_ANY, "Start from Beginning")
    local cancelBtn = wx.wxButton(panel, wx.wxID_CANCEL, "Cancel")

    -- Set up button handlers
    runBtn:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        dialog:EndModal(1)  -- Return 1 for Run From Here
    end)

    beginBtn:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        dialog:EndModal(2)  -- Return 2 for Start from Beginning
    end)

    runBtn:SetDefault()
    btnSizer:Add(runBtn, 0, wx.wxALL, 5)
    btnSizer:Add(beginBtn, 0, wx.wxALL, 5)
    btnSizer:Add(cancelBtn, 0, wx.wxALL, 5)

    sizer:Add(btnSizer, 0, wx.wxALIGN_CENTER + wx.wxALL, 15)

    panel:SetSizerAndFit(sizer)
    dialog:SetClientSize(panel:GetSize())
    dialog:Centre()

    local result = dialog:ShowModal()
    dialog:Destroy()

    if result == wx.wxID_CANCEL then
        return true  -- Cancel cycle start
    elseif result == 2 then
        -- Start from beginning
        mc.mcCntlSetGcodeLineNbr(inst, 0)
        return false  -- Continue with normal cycle start
    end

    -- Check for missing critical data
    if not state.x or not state.y or not state.z then
        wx.wxMessageBox("Cannot run from here: Missing position data in gcode",
                       "Run From Here Error", wx.wxOK + wx.wxICON_ERROR)
        return true  -- Cancel
    end

    -- Execute Run From Here sequence
    mc.mcCntlSetLastError(inst, "Preparing Run From Here...")

    -- 1. Move to safe Z
    mc.mcCntlGcodeExecuteWait(inst, "G53 G0 Z0")

    -- 2. Tool change if needed
    if state.tool and state.tool ~= mc.mcToolGetCurrent(inst) then
        mc.mcCntlGcodeExecuteWait(inst, string.format("T%d M6", state.tool))
        mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%d", state.tool))
    end

    -- 3. Set work offset and modes
    local setupCmd = "G90 G94 G17"  -- Always use absolute, feed/min, XY plane
    if state.workOffset then
        setupCmd = setupCmd .. " " .. state.workOffset
    end
    mc.mcCntlGcodeExecuteWait(inst, setupCmd)

    -- 4. Start spindle
    if state.spindleSpeed and state.spindleDir ~= "M5" then
        mc.mcCntlGcodeExecuteWait(inst, string.format("S%d %s", state.spindleSpeed, state.spindleDir))
        mc.mcCntlGcodeExecuteWait(inst, "G4 P2")  -- 2 second spindle ramp
    end

    -- 5. Start coolant
    if state.coolant ~= "M9" then
        mc.mcCntlGcodeExecuteWait(inst, state.coolant)
    end

    -- 6. Move to XY position
    mc.mcCntlGcodeExecuteWait(inst, string.format("G0 X%.4f Y%.4f", state.x, state.y))

    -- 7. Show plunge confirmation with options
    local currentZ = mc.mcAxisGetPos(inst, mc.Z_AXIS)
    local plungeMsg = string.format(
        "Ready to Start Program\n────────────────────\n\n" ..
        "Machine positioned at:\n" ..
        "X%.4f Y%.4f\n" ..
        "Current Z: %.4f\n\n" ..
        "Program Z height: %.4f\n\n" ..
        "Choose how to proceed:",
        state.x, state.y, currentZ, state.z
    )

    -- Create custom dialog with three buttons
    local plungeDlg = wx.wxDialog(wx.NULL, wx.wxID_ANY, "Ready to Start",
                                  wx.wxDefaultPosition, wx.wxDefaultSize)

    local plungePanel = wx.wxPanel(plungeDlg, wx.wxID_ANY)
    local plungeSizer = wx.wxBoxSizer(wx.wxVERTICAL)

    local plungeText = wx.wxStaticText(plungePanel, wx.wxID_ANY, plungeMsg)
    plungeSizer:Add(plungeText, 0, wx.wxALL, 15)

    plungeSizer:AddSpacer(10)

    -- Button sizer
    local plungeBtnSizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
    local plungeBtn = wx.wxButton(plungePanel, wx.wxID_ANY, "Plunge and Start")
    local currentBtn = wx.wxButton(plungePanel, wx.wxID_ANY, "Start at Current Z")
    local abortBtn = wx.wxButton(plungePanel, wx.wxID_CANCEL, "Abort")

    -- Set up button handlers
    plungeBtn:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        plungeDlg:EndModal(1)  -- Plunge to Z
    end)

    currentBtn:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
        plungeDlg:EndModal(2)  -- Stay at current Z
    end)

    plungeBtn:SetDefault()
    plungeBtnSizer:Add(plungeBtn, 0, wx.wxALL, 5)
    plungeBtnSizer:Add(currentBtn, 0, wx.wxALL, 5)
    plungeBtnSizer:Add(abortBtn, 0, wx.wxALL, 5)

    plungeSizer:Add(plungeBtnSizer, 0, wx.wxALIGN_CENTER + wx.wxALL, 15)

    plungePanel:SetSizerAndFit(plungeSizer)
    plungeDlg:SetClientSize(plungePanel:GetSize())
    plungeDlg:Centre()

    local plungeResult = plungeDlg:ShowModal()
    plungeDlg:Destroy()

    if plungeResult == wx.wxID_CANCEL then
        -- User aborted - stop spindle and coolant
        mc.mcCntlGcodeExecuteWait(inst, "M5")
        mc.mcCntlGcodeExecuteWait(inst, "M9")
        mc.mcCntlSetLastError(inst, "Run From Here aborted")
        return true  -- Cancel
    end

    -- 8. Move to Z position (only if user chose to plunge)
    if plungeResult == 1 then
        mc.mcCntlSetLastError(inst, string.format("Plunging to Z%.4f", state.z))
        mc.mcCntlGcodeExecuteWait(inst, string.format("G0 Z%.4f", state.z))
    else
        mc.mcCntlSetLastError(inst, "Starting at current Z height")
    end

    -- 9. Set feed mode and feed rate
    -- CRITICAL: Switch back to G1 feed mode after all the G0 rapid positioning
    local feedCmd = "G1"
    if state.feedRate then
        feedCmd = string.format("G1 F%.1f", state.feedRate)
    end
    mc.mcCntlGcodeExecuteWait(inst, feedCmd)

    -- 10. Jump to line and start
    mc.mcCntlSetGcodeLineNbr(inst, safeLine)
    mc.mcCntlSetLastError(inst, string.format("Starting from line %d", safeLine + 1))

    return false  -- Continue with cycle start
end

function CycleStart()
    -- Add error handling wrapper
    local status, err = pcall(function()
        local tab = scr.GetProperty("MainTabs", "Current Tab") or ""
        local tabG_Mdione = scr.GetProperty("nbGCodeMDI1", "Current Tab") or ""
        local tabG_Mditwo = scr.GetProperty("nbGCodeMDI2", "Current Tab") or ""
        local state = mc.mcCntlGetState(inst)

        -- Skip all checks if already running (e.g., single block mode)
        -- States 100-199 = File Run (including 113 = single block hold)
        if state >= 100 and state < 200 then
            mc.mcCntlCycleStart(inst)
            return
        end

        -- Check work offset mismatch (only for main tab, not MDI)
        local tabNum = tonumber(tab) or -1
        local tabG_MdioneNum = tonumber(tabG_Mdione) or -1
        local tabG_MditwoNum = tonumber(tabG_Mditwo) or -1

        -- Only check if we're about to run a gcode file (not MDI)
        if not (tabNum == 0 and tabG_MdioneNum == 1) and
           not (tabNum == 5 and tabG_MditwoNum == 1) then

            local filePath = mc.mcCntlGetGcodeFileName(inst)
            if filePath and filePath ~= "" then
                -- Check if G68 is active
                local g68Active = (mc.mcCntlGetPoundVar(inst, 4016) == 68)

                -- Get current machine work offset
                local currentOffset = mc.mcCntlGetPoundVar(inst, 4014)
                local currentOffsetString = ""
                if currentOffset >= 54 and currentOffset <= 59 then
                    currentOffsetString = string.format("G%.0f", currentOffset)
                elseif currentOffset == 54.1 then
                    local pval = mc.mcCntlGetPoundVar(inst, mc.SV_BUFP)
                    currentOffsetString = string.format("G54.1 P%.0f", pval)
                end

                local totalLines = mc.mcCntlGetGcodeLineCount(inst)
                local gcodeOffset = nil
                local usesG18orG19 = false

                -- Scan for work offset in first 30 lines, but scan entire file for G18/G19
                for i = 0, totalLines - 1 do
                    local line = mc.mcCntlGetGcodeLine(inst, i)
                    if line then
                        -- Remove comments and convert to uppercase for matching
                        line = line:gsub("%(.*%)", ""):gsub(";.*", ""):upper()

                        -- Check for G18 or G19 plane selection (scan entire file)
                        if g68Active and not usesG18orG19 and (line:match("G18") or line:match("G19")) then
                            usesG18orG19 = true
                            -- Don't break, need to scan entire file
                        end

                        -- Check for work offset (only first 30 lines)
                        if i < 30 and not gcodeOffset then
                            -- Check for G54-G59
                            local g5x = line:match("G5[4-9]")
                            if g5x and not line:match("G5[4-9]%.") then  -- Exclude G54.1 etc
                                gcodeOffset = g5x
                            end

                            -- Check for G54.1 Pxx
                            local g54p = line:match("G54%.1%s*P(%d+)")
                            if g54p then
                                gcodeOffset = "G54.1 P" .. g54p
                            end
                        end

                        -- Early exit if we found both
                        if usesG18orG19 and gcodeOffset then
                            break
                        end
                    end
                end

                -- Check for G68 with G18/G19 incompatibility
                if usesG18orG19 then
                    local rotation = mc.mcCntlGetPoundVar(inst, mc.SV_ROTATION)
                    local message = string.format(
                        "⚠ G68 Rotation Incompatible!\n\n" ..
                        "G68 rotation (%.2f°) is currently active,\n" ..
                        "but this program uses G18 or G19 plane selection.\n\n" ..
                        "G68 only works with G17 (XY plane).\n\n" ..
                        "Please cancel G68 rotation before running this program.",
                        rotation
                    )

                    wx.wxMessageBox(message, "G68 Plane Error",
                                   wx.wxOK + wx.wxICON_ERROR)
                    return  -- Cancel cycle start
                end

                -- Check for mismatch
                if gcodeOffset and gcodeOffset ~= currentOffsetString then
                    local message = string.format(
                        "⚠ Work Offset Mismatch Detected!\n\n" ..
                        "GCode file uses: %s\n" ..
                        "Machine is set to: %s\n\n" ..
                        "This may cause the part to be machined in the wrong location.\n\n" ..
                        "Do you want to continue anyway?",
                        gcodeOffset, currentOffsetString
                    )

                    local result = wx.wxMessageBox(message, "Work Offset Warning",
                                                  wx.wxYES_NO + wx.wxICON_WARNING + wx.wxNO_DEFAULT)

                    if result == wx.wxNO then
                        return  -- Cancel cycle start
                    end
                    -- If YES, continue with the cycle start
                end
            end
        end

        -- Check override values
        local fro = mc.mcCntlGetFRO(inst) or 100
        local rro = mc.mcCntlGetRRO(inst) or 100
        local sro = (mc.mcSpindleGetOverride(inst) or 1) * 100

        -- Ensure values are valid numbers and round them
        fro = math.floor(tonumber(fro) or 100)
        rro = math.floor(tonumber(rro) or 100)
        sro = math.floor(tonumber(sro) or 100)

        -- If any override is not at 100%, show warning dialog
        if fro ~= 100 or rro ~= 100 or sro ~= 100 then
            local message = string.format(
                "Warning: Overrides are not at 100%%\n\n" ..
                "Feed Rate Override: %d%%\n" ..
                "Rapid Rate Override: %d%%\n" ..
                "Spindle Rate Override: %d%%\n\n" ..
                "Continue with current values?\n" ..
                "YES = Continue as-is\n" ..
                "NO = Set to 100%% and continue\n" ..
                "CANCEL = Abort",
                fro, rro, sro
            )

            local result = wx.wxMessageBox(message, "Override Warning", 
                                          wx.wxYES_NO + wx.wxCANCEL + wx.wxICON_WARNING)
            
            if result == wx.wxYES then
                -- Continue with current overrides
            elseif result == wx.wxNO then
                SetFRO(100)
                SetRRO(100)
                SetSRO(100)
            else
                return  -- Cancel
            end
        end

        -- Check for Run From Here AFTER all safety checks
        -- Only for gcode files, not MDI
        if not (tabNum == 0 and tabG_MdioneNum == 1) and
           not (tabNum == 5 and tabG_MditwoNum == 1) then
            local runFromHereResult = RunFromHere()
            if runFromHereResult == true then
                return  -- User cancelled
            end
            -- If false, continue with cycle start (either from beginning or after setup)
        end

        -- Tab numbers already parsed earlier for work offset check

        if state == mc.MC_STATE_MRUN_MACROH then
            mc.mcCntlCycleStart(inst)
        elseif tabNum == 0 and tabG_MdioneNum == 1 then
            scr.ExecMdi('mdi1')
        elseif tabNum == 5 and tabG_MditwoNum == 1 then
            scr.ExecMdi('mdi2')
        else
            mc.mcCntlCycleStart(inst)
        end
    end)
    
    if not status then
        mc.mcCntlSetLastError(inst, "CycleStart error: " .. tostring(err))
    end
end

-- Cancel G68 with a confirmation modal
function CancelG68()
    if mc.mcCntlGetPoundVar(inst, 4016) ~= 68 then
        mc.mcCntlSetLastError(inst, "No active G68 rotation.")
        return false
    end

    local a  = mc.mcCntlGetPoundVar(inst, mc.SV_ROTATION)
    local cx = mc.mcCntlGetPoundVar(inst, mc.SV_ROTATION_X)
    local cy = mc.mcCntlGetPoundVar(inst, mc.SV_ROTATION_Y)
    local msg = string.format("Cancel rotation (send G69)?\n\nAngle: %.4f°\nCenter: X%.4f  Y%.4f", a, cx, cy)

    if wx.wxMessageBox(msg, "G69 Confirm", wx.wxYES_NO + wx.wxICON_QUESTION) == wx.wxYES then
        local ok = (mc.mcCntlGcodeExecuteWait(inst, "G69") == mc.MERROR_NOERROR)
        mc.mcCntlSetLastError(inst, ok and "G68 cancelled." or "Failed to send G69.")
        return ok
    end

    mc.mcCntlSetLastError(inst, "Kept current rotation.")
    return false
end

-- Recover from file hold then reset
function RecoverThenReset()
    mc.mcCntlCycleStop(inst)
	--mc.mcFileHoldRelease(inst)
	mc.mcCntlMachineStateClear(inst)
    mc.mcCntlReset(inst)
    mc.mcCntlFileRewind(inst)
end

function SecondsToTime(seconds)
    if seconds == 0 then
        return "00:00:00.00"
    else
        local hours = string.format("%02.f", math.floor(seconds/3600))
        local mins = string.format("%02.f", math.floor((seconds/60) - (hours*60)))
        local secs = string.format("%05.2f",(seconds - (hours*3600) - (mins*60)))
        return hours .. ":" .. mins .. ":" .. secs
    end
end

-- Load modules
--Master module
package.loaded.mcRegister = nil
mm = require "mcRegister"
--ErrorCheck module Added 11-4-16
package.loaded.mcErrorCheck = nil
mcErrorCheck = require "mcErrorCheck"
--Trace module
package.loaded.mcTrace = nil
mcTrace = require "mcTrace"


-- Get fixture offset pound variables
function GetFixOffsetVars()
    local fixture = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_14)
    local pval = mc.mcCntlGetPoundVar(inst, mc.SV_BUFP)
    local poundVarX, fixNum, fixString
    
    if fixture ~= 54.1 then
        fixNum = math.floor(fixture) - 53
        poundVarX = 5201 + (fixNum * 20)  -- 5221 for G54, 5241 for G55, etc.
        fixString = string.format('G%.0f', fixture)
    else
        fixNum = pval + 6
        if pval <= 50 then
            poundVarX = 6981 + (pval * 20)  -- 7001 for P1, 7021 for P2, etc.
        else
            poundVarX = 7981 + (pval * 20)  -- 8001 for P51, etc.
        end
        fixString = string.format('G54.1 P%.0f', pval)
    end
    
    return poundVarX, poundVarX + 1, poundVarX + 2, fixNum, fixString
end


-- Enable/disable buttons based on axis configuration
function ButtonEnable()
    local axes = {'X','Y','Z','A','B','C'}
    for i, axis in ipairs(axes) do
        local enabled = tostring(mc.mcAxisIsEnabled(inst, i-1))
        scr.SetProperty('btnPos' .. axis, 'Enabled', enabled)
        scr.SetProperty('btnNeg' .. axis, 'Enabled', enabled)
        scr.SetProperty('btnZero' .. axis, 'Enabled', enabled)
        scr.SetProperty('btnRef' .. axis, 'Enabled', enabled)
    end
end


-- Monitor function: runs constantly checking all axis states
function SyncMPG()
    -- Initialize tracking
    state.axis_rates = state.axis_rates or {[0] = -1, [1] = -1, [2] = -1}
    state.mpg0_inc = state.mpg0_inc or -1
    
    -- Check for rate change on any axis
    local changedRate = nil
    for axis = 0, 2 do
        if mc.mcAxisIsEnabled(inst, axis) == 1 then
            local rate = mc.mcJogGetRate(inst, axis)
            if rate ~= state.axis_rates[axis] then
                -- SAFETY FIX: Never sync 100% rate to prevent dangerous jog rate corruption
                -- This prevents the shift-jog bug from setting default rate to 100%
                if rate ~= 100 then
                    changedRate = rate
                    --mc.mcCntlSetLastError(inst, "SyncMPG: Rate change detected")
                end
                -- Always update tracking regardless of sync decision
                state.axis_rates[axis] = rate
                if changedRate then
                    break
                end
            end
        end
    end
    
    -- Check for increment change
    local changedInc = nil
    local currentInc = mc.mcMpgGetInc(inst, 0)
    if currentInc ~= state.mpg0_inc and currentInc > 0 then
        changedInc = currentInc
        --mc.mcCntlSetLastError(inst, "SyncMPG: Increment change detected")
        state.mpg0_inc = currentInc
    end
    
    -- Sync if anything changed
    if changedRate or changedInc then
        SyncAllAxes(changedRate, changedInc)
    end
end

-- Sync function: applies rate and/or increment to all enabled axes
function SyncAllAxes(rate, increment)
    for axis = 0, 2 do
        if mc.mcAxisIsEnabled(inst, axis) == 1 then
            if rate then
                mc.mcJogSetRate(inst, axis, rate)
                state.axis_rates[axis] = rate
            end
            if increment then
                mc.mcJogSetInc(inst, axis, increment)
            end
        end
    end
    -- Update the UI controls when rate changes
    if rate then
        scr.SetProperty("slJogRate", "Value", tostring(rate)) -- The DRO will auto-update since they share code 391
    end
end

-- Machine Park function. Rapids to park position (X min+1, Y max-1, Z at safe height)
function MachinePark()
    local xMin = mc.mcAxisGetSoftlimitMin(inst, mc.X_AXIS)
    local yMax = mc.mcAxisGetSoftlimitMax(inst, mc.Y_AXIS)
    local parkX = xMin + 1
    local parkY = yMax - 1
    local gcode = string.format("G00 G53 Z-0.050\nG00 G53 X%.4f Y%.4f", parkX, parkY)
    mc.mcCntlMdiExecute(inst, gcode)
end


-- Return to Machine Zero function - Rapids Z to safe height, then XY to machine zero
function ReturnToMachineZero()
    mc.mcCntlMdiExecute(inst, "G00 G53 Z-0.050\nG00 G53 X0 Y0")
end


-- Toggle Soft Limits
function ToggleSoftLimits(action)
    action = action or "toggle"
    if action == "enable" then
        scr.DoFunctionName("Soft Limits On")
    elseif action == "disable" then
        scr.DoFunctionName("Soft Limits Off")
    else  -- toggle
        scr.DoFunctionName("Soft Limits Toggle")
    end
end


-- Keyboard Inputs Toggle function
function KeyboardInputsToggle(action)
    if action == "initialize" then
        KeyboardInputsToggle()
        KeyboardInputsToggle()
        return
    end

    local iReg = mc.mcIoGetHandle(inst, "Keyboard/Enable")
    local iReg2 = mc.mcIoGetHandle(inst, "Keyboard/EnableKeyboardJog")
   
    local setState = action == "enable" and 1 or
                     action == "disable" and 0 or
                     1 - mc.mcIoGetState(iReg)
   
    mc.mcIoSetState(iReg, setState)
    mc.mcIoSetState(iReg2, setState)
end


-- Toggle Height Offset function (G43/G49)
function ToggleHeightOffset()
    local offsetMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_8)
    
    if offsetMode == 49 then
        local tool = mc.mcToolGetCurrent(inst)
        mc.mcCntlGcodeExecute(inst, string.format("G43 H%d", tool))
    elseif offsetMode ~= 49 then
        mc.mcCntlGcodeExecute(inst, "G49")
    end
end


-- Set Work Offset function (G54-G59, G54.1 P1-P100)
function SetWorkOffset(value)
    local base = math.floor(value)
    local pValue = math.floor((value - base) * 100 + 0.5)

    if pValue == 0 then
        local gcode = string.format("G%d", base)
        mc.mcCntlGcodeExecute(inst, gcode)
    else
        local gcode = string.format("G54.1 P%d", pValue)
        mc.mcCntlGcodeExecute(inst, gcode)
    end
end


-- Deploy/Retract Virtual Tool (T90 probe, T91 laser)
function DeployVirtual(toolName, action)
    local toolMap = {
        probe = 90,
        laser = 91
    }
    local toolNum = toolMap[string.lower(toolName)]
    local currentTool = mc.mcToolGetCurrent(inst)
    
    -- Default to toggle if no action specified
    action = action and string.lower(action) or ((currentTool == toolNum) and "retract" or "deploy")
    
    if action == "deploy" then
        mc.mcCntlMdiExecute(inst, string.format("M6 T%d", toolNum))
    elseif action == "retract" then
        mc.mcCntlMdiExecute(inst, "M6 T0")
    end
end


-- Retract virtual tool bypass m6
function SafeRetractVirtual()
    local currentTool = mc.mcToolGetCurrent(inst)
    if currentTool >= 90 then
        mc.mcSignalSetState(mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT1), 0)  -- Laser deploy
        mc.mcSignalSetState(mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT7), 0)  -- Probe deploy
        mc.mcSignalSetState(mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT9), 0)  -- Laser fire
        mc.mcRegSetValue(mc.mcRegGetHandle(inst, "ESS/Laser/Test_Mode_Activate"), 0)
        mc.mcToolSetCurrent(inst, 0)
        mc.mcCntlSetPoundVar(inst, 550, 0)
    end
end


-- Set Laser Power (1-100%)
function SetLaserPower(power)
    power = math.max(1, math.min(100, power or 1))
    local hReg = mc.mcRegGetHandle(inst, "ESS/Laser/Vector/GCode_PWM_Percentage")
    if hReg ~= 0 then
        mc.mcRegSetValue(hReg, power)
    end
end


-- Measure Current Tool function
function MeasureCurrentTool()
    local state = mc.mcCntlGetState(inst)

    if state ~= mc.MC_STATE_IDLE then
        wx.wxMessageBox("Machine must be idle to measure tool", "Cannot Measure Tool", wx.wxOK + wx.wxICON_WARNING)
        return
    end

    mc.mcCntlMdiExecute(inst, "M310")
end


function ToggleAuxOutput(target, action)
    local outputMap = {
        -- Output mapping - add new targets here
        dustCollect = mc.OSIG_OUTPUT4,
        dustBoot = mc.OSIG_OUTPUT3,
        vacRear = mc.OSIG_OUTPUT5,
        vacFront = mc.OSIG_OUTPUT6
    }
    
    local output = outputMap[target]
    local handle = mc.mcSignalGetHandle(inst, output)
    local currentState = mc.mcSignalGetState(handle)

    local newState
    if action == "enable" then
        newState = 1
    elseif action == "disable" then
        newState = 0
    else 
        newState = 1 - currentState
    end

    mc.mcSignalSetState(handle, newState)
    local stateText = newState == 1 and "ON" or "OFF"
    --mc.mcCntlSetLastError(inst, string.format("%s: %s", target, stateText))
end


function SetCenter(axis)
    axis = string.lower(axis)
    local axisIndex = axis == "x" and 0 or (axis == "y" and 1 or nil)
    local pv = axis == "x" and 300 or (axis == "y" and 301 or nil)
    
    if not axisIndex then return end
    
    local currentPos = mc.mcAxisGetMachinePos(inst, axisIndex)
    local storedPos = mc.mcCntlGetPoundVar(inst, pv)
    
    if storedPos == 0 then
        -- First call - store current position
        mc.mcCntlSetPoundVar(inst, pv, currentPos)
        mc.mcCntlSetLastError(inst, string.format("%s: First point set at %.4f", 
                                                  string.upper(axis), currentPos))
    else
        -- Second call - calculate center and set datum
        local center = (storedPos + currentPos) / 2
        local workOffset = center - currentPos
        mc.mcAxisSetPos(inst, axisIndex, -workOffset)
        mc.mcCntlSetPoundVar(inst, pv, 0)
        mc.mcCntlSetLastError(inst, string.format("%s: Center set at machine %.4f", 
                                                  string.upper(axis), center))
    end
end


function ToggleAutomation(target, action)
    local automationMap = {
        -- Automation mapping - using output signals for immediate UI updates
        dustAuto = mc.OSIG_OUTPUT50,
        vacAuto = mc.OSIG_OUTPUT51,
        bootAuto = mc.OSIG_OUTPUT52
    }

    local output = automationMap[target]
    local handle = mc.mcSignalGetHandle(inst, output)
    local currentState = mc.mcSignalGetState(handle)

    local newState
    if action == "enable" then
        newState = 1
    elseif action == "disable" then
        newState = 0
    else  -- default to toggle
        newState = 1 - currentState
    end

    mc.mcSignalSetState(handle, newState)
    local stateText = newState == 1 and "ENABLED" or "DISABLED"
    mc.mcCntlSetLastError(inst, string.format("%s Auto: %s", target, stateText))
end


function ToggleLaserEnable(action)
    local hregActivate = mc.mcRegGetHandle(inst, "ESS/Laser/Test_Mode_Activate")
    local currentState = mc.mcRegGetValue(hregActivate)
    
    local newState = action == "enable" and 1 or
                     action == "disable" and 0 or
                     1 - currentState
    
    if newState == 0 then
        mc.mcRegSetValue(hregActivate, 0)
        mc.mcSignalSetState(mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT9), 0)
    else
        mc.mcRegSetValue(mc.mcRegGetHandle(inst, "ESS/Laser/Test_Mode_Enable"), 1)
        mc.mcSignalSetState(mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT9), 1)
        mc.mcRegSetValue(hregActivate, 1)
    end
end


function SelectToolDialog()
    local inst = mc.mcGetInstance()
    local currentTool = mc.mcToolGetCurrent(inst)
    
    -- Build list of available tools
    local tools = {}
    local toolStrings = {}
    
    -- Add T0
    table.insert(tools, 0)
    table.insert(toolStrings, "T0 - No Tool")
    
    -- Find tools with descriptions
    for t = 1, 99 do
        local desc = mc.mcToolGetDesc(inst, t)
        if desc and desc ~= "" then
            table.insert(tools, t)
            table.insert(toolStrings, string.format("T%d - %s", t, desc))
        end
    end
    
    -- Create simple selection dialog
    local choice = wx.wxGetSingleChoice(
        "Select tool to change to:",
        "Tool Selection",
        toolStrings,
        wx.NULL
    )
    
    -- If user made a selection
    if choice ~= "" then
        -- Find which tool was selected
        for i, str in ipairs(toolStrings) do
            if str == choice then
                local selectedTool = tools[i]
                
                -- Execute tool change if different from current
                if selectedTool ~= currentTool then
                    local state = mc.mcCntlGetState(inst)
                    if state == mc.MC_STATE_IDLE then
                        mc.mcCntlMdiExecute(inst, string.format("T%d M6", selectedTool))
                    else
                        wx.wxMessageBox("Machine must be idle to change tools", "Cannot Change Tool")
                    end
                end
                break
            end
        end
    end
end


-- Timer for SpindleToolDialog input settling
SpindleToolSettleTimer = wx.wxTimer()
SpindleToolSettleTimer:Connect(wx.wxEVT_TIMER, function(event)
    SpindleToolCheckAfterSettle()
end)

-- Main spindle tool dialog function - stateless design
function SpindleToolDialog()
    local buttonState = mc.mcSignalGetState(mc.mcSignalGetHandle(inst, mc.ISIG_INPUT8))
    local hClamp = mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT2)
    
    if buttonState == 0 then
        -- Button LOW - ensure clamp closed and check tool
        local clampWasOpen = mc.mcSignalGetState(hClamp) == 1
        mc.mcSignalSetState(hClamp, 0)
        
        -- Always restart the timer when button is LOW
        SpindleToolSettleTimer:Stop()  -- Cancel any pending timer
        
        -- Use longer delay if clamp was open, short delay if already closed
        local delay = clampWasOpen and 1500 or 100
        SpindleToolSettleTimer:Start(delay, wx.wxTIMER_ONE_SHOT)
        
    else
        -- Button HIGH - open clamp and cancel pending check
        mc.mcSignalSetState(hClamp, 1)
        SpindleToolSettleTimer:Stop()
        
        if SpindleDialogHandle then
            SpindleDialogHandle:EndModal(wx.wxID_CANCEL)
        end
    end
end

-- Timer callback - runs after settle delay
function SpindleToolCheckAfterSettle()
    -- Verify button is still LOW
    if mc.mcSignalGetState(mc.mcSignalGetHandle(inst, mc.ISIG_INPUT8)) ~= 0 then
        return
    end
    
    -- Check tool presence
    local toolPresent = mc.mcSignalGetState(mc.mcSignalGetHandle(inst, mc.ISIG_INPUT17))
    
    if toolPresent == 0 then
        mc.mcToolSetCurrent(inst, 0)
        mc.mcCntlGcodeExecuteWait(inst, "G49")
        return
    end
    
    -- Tool present, show dialog
    if SpindleDialogHandle then return end
    
    -- Get last tool from PV550
    local lastTool = mc.mcCntlGetPoundVar(inst, 550)
    lastTool = (lastTool < 90 and lastTool > 0) and lastTool or 0
    
    -- Build tool list
    local tools = {}
    local toolStrings = {}
    local defaultIndex = 0
    
    for t = 1, 89 do
        local desc = mc.mcToolGetDesc(inst, t)
        if desc and desc ~= "" then
            table.insert(tools, t)
            table.insert(toolStrings, string.format("T%d - %s", t, desc))
            if t == lastTool then defaultIndex = #tools - 1 end
        end
    end
    
    -- Create and show dialog
    SpindleDialogHandle = wx.wxSingleChoiceDialog(wx.NULL,
        "Select tool currently in spindle:", "Tool Selection",
        toolStrings)
    
    SpindleDialogHandle:SetSelection(defaultIndex)
    local result = SpindleDialogHandle:ShowModal()
    
    -- Get selected tool or fall back to last tool
    local selectedTool = (result == wx.wxID_OK) 
        and tools[SpindleDialogHandle:GetSelection() + 1] 
        or lastTool

    SpindleDialogHandle:Destroy()
    SpindleDialogHandle = nil
    
    -- If virtual tool active, retract it
    SafeRetractVirtual()
    
    -- Clear then reapply offset
    mc.mcCntlGcodeExecuteWait(inst, "G49")
    mc.mcToolSetCurrent(inst, selectedTool)

    if selectedTool ~= 0 then
        mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%d", selectedTool))
        mc.mcCntlSetPoundVar(inst, 550, selectedTool)
    end
end

-- Helper for Input 17 state changes
function SpindleToolPresenceChanged(state)
    if SpindleDialogHandle and state == 0 then
        -- Tool removed while dialog open - close it
        SpindleDialogHandle:EndModal(wx.wxID_CANCEL)
        mc.mcToolSetCurrent(inst, 0)
        mc.mcCntlGcodeExecuteWait(inst, "G49")
        mc.mcCntlSetLastError(inst, "Tool removed - Set to T0")
    end
end


-- Dust collection and vacuum automation function
function DustAutomation()
    local hRunning = mc.mcSignalGetHandle(inst, mc.OSIG_RUNNING_GCODE)
    local running = mc.mcSignalGetState(hRunning)
    local machState = mc.mcCntlGetState(inst)
    local wasInFile = mc.mcCntlGetPoundVar(inst, 405)
    
    -- Check if this is a file run (100-199), not MDI/script (200-299)
    local isFileRun = (machState >= 100 and machState < 200)
    
    -- Get automation modes from output signals
    local dustAuto = mc.mcSignalGetState(mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT50)) == 1
    local vacAuto = mc.mcSignalGetState(mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT51)) == 1
    local bootAuto = mc.mcSignalGetState(mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT52)) == 1
    
    -- Program file started
    if running == 1 and isFileRun and wasInFile == 0 then
        mc.mcCntlSetPoundVar(inst, 405, 1)
        if dustAuto then 
            ToggleAuxOutput("dustCollect", "enable")
        end
        
    -- Program file stopped
    elseif running == 0 and wasInFile == 1 then
        mc.mcCntlSetPoundVar(inst, 405, 0)
        if dustAuto then ToggleAuxOutput("dustCollect", "disable") end
        if bootAuto then ToggleAuxOutput("dustBoot", "disable") end
        if vacAuto then 
            ToggleAuxOutput("vacRear", "disable")
            ToggleAuxOutput("vacFront", "disable")
        end
    end
end




UILastStates = {}
UIFlashCounter = 0
UIStates = {
    btnSetCenterX = {
        check = function(inst)
            return mc.mcCntlGetPoundVar(inst, 300) == 0 and "off" or "on"
        end,
        states = {
            on = {bg = "#00FF00", fg = "#000000", label = "X Set\nFinal"},
            off = {bg = "#4B4B4B", fg = "#FFFFFF", label = "X Set\nInitial"}
        }
    },

    btnSetCenterY = {
        check = function(inst)
            return mc.mcCntlGetPoundVar(inst, 301) == 0 and "off" or "on"
        end,
        states = {
            on = {bg = "#00FF00", fg = "#000000", label = "Y Set\nFinal"},
            off = {bg = "#4B4B4B", fg = "#FFFFFF", label = "Y Set\nInitial"}
        }
    },

    btnG54 = {
        check = {pvar = mc.SV_MOD_GROUP_14, equals = 54},
        states = {on = {bg = "#00FF00", fg = "#000000"}, 
                  off = {bg = "#4B4B4B", fg = "#FFFFFF"}}
    },
    
    btnG55 = {
        check = {pvar = mc.SV_MOD_GROUP_14, equals = 55},
        states = {on = {bg = "#00FF00", fg = "#000000"}, 
                  off = {bg = "#4B4B4B", fg = "#FFFFFF"}}
    },
    
    btnG56 = {
        check = {pvar = mc.SV_MOD_GROUP_14, equals = 56},
        states = {on = {bg = "#00FF00", fg = "#000000"}, 
                  off = {bg = "#4B4B4B", fg = "#FFFFFF"}}
    },
    
    btnG57 = {
        check = {pvar = mc.SV_MOD_GROUP_14, equals = 57},
        states = {on = {bg = "#00FF00", fg = "#000000"}, 
                  off = {bg = "#4B4B4B", fg = "#FFFFFF"}}
    },
    
    btnG58 = {
        check = {pvar = mc.SV_MOD_GROUP_14, equals = 58},
        states = {on = {bg = "#00FF00", fg = "#000000"}, 
                  off = {bg = "#4B4B4B", fg = "#FFFFFF"}}
    },
    
    btnG59 = {
        check = {pvar = mc.SV_MOD_GROUP_14, equals = 59},
        states = {on = {bg = "#00FF00", fg = "#000000"}, 
                  off = {bg = "#4B4B4B", fg = "#FFFFFF"}}
    },
    
    btnG541P = {
        check = {pvar = mc.SV_MOD_GROUP_14, equals = 54.1},
        states = {on = {bg = "#00FF00", fg = "#000000"}, 
                  off = {bg = "#4B4B4B", fg = "#FFFFFF"}}
    },

    btnHeightOffset = {
        check = {pvar = mc.SV_MOD_GROUP_8, notequals = 49},
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Height Offset\nENABLED"}, 
                  off = {bg = "#FF0000", fg = "#FFFFFF", label = "Height Offset\nDISABLED"}}
    },

    btnG68Rotate = {
        check = {pvar = 4016, notequals = 69},
        states = {on = {bg = "#00FF00", fg = "#000000", label = "G68 Rotation\nACTIVE"}, 
                  off = {bg = "#4B4B4B", fg = "#FFFFFF", label = "G68 Rotation\nOFF"}}
    },
 
    btnKeyboardEnable = {
        check = {io = "Keyboard/Enable"},
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Keyboard\nENABLED"}, 
                  off = {bg = "#90EE90", fg = "#404040", label = "Keyboard\nDISABLED"}}
    },
    
    btnDustBoot = {
        check = function(inst)
            local h = mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT3)
            return mc.mcSignalGetState(h) == 1 and "on" or "off"
        end,
        disabled = function(inst)
            local state = mc.mcCntlGetState(inst)
            local inM6 = state == mc.MC_STATE_MRUN_MACROH or state == mc.MC_STATE_MRUN_MACROH_HOLD
            return inM6 or mc.mcToolGetCurrent(inst) > 89
        end,
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Dust Boot\nDOWN"},
                off = {bg = "#FF0000", fg = "#FFFFFF", label = "Dust Boot\nUP"},
                disabled = {bg = "#808080", fg = "#C0C0C0", label = "Dust Boot\nLOCKED"}}
    },

    ledHOffset = {
        check = {pvar = mc.SV_MOD_GROUP_8, notequals = 49},
        states = {on = {bg = "#00FF00"}, 
                  off = {bg = "#4B4B4B"}}
    },
    
    ledG68Active = {
        check = {pvar = 4016, notequals = 69},
        states = {on = {bg = "#00FF00"}, 
                  off = {bg = "#4B4B4B"}}
    },

    btnDustCollect = {
        check = function(inst)
            local h = mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT4)
            return mc.mcSignalGetState(h) == 1 and "on" or "off"
        end,
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Dust Collect\nON"},
                  off = {bg = "#FF0000", fg = "#FFFFFF", label = "Dust Collect\nOFF"}}
    },
    
    -- Dust Auto Mode
    btnDustAuto = {
        check = function(inst)
            local h = mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT50)
            return mc.mcSignalGetState(h) == 1 and "on" or "off"
        end,
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Dust Auto\nENABLED"},
                off = {bg = "#FF0000", fg = "#FFFFFF", label = "Dust Auto\nDISABLED"}}
    },
    
    -- Dust Boot Auto Mode
    btnBootAuto = {
        check = function(inst)
            local h = mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT52)
            return mc.mcSignalGetState(h) == 1 and "on" or "off"
        end,
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Boot Auto\nENABLED"},
                off = {bg = "#FF0000", fg = "#FFFFFF", label = "Boot Auto\nDISABLED"}}
    },
    
    -- Rear Vacuum
    btnVacRear = {
        check = function(inst)
            local h = mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT5)
            return mc.mcSignalGetState(h) == 1 and "on" or "off"
        end,
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Rear Vacuum\nON"},
                  off = {bg = "#FF0000", fg = "#FFFFFF", label = "Rear Vacuum\nOFF"}}
    },
    
    -- Front Vacuum
    btnVacFront = {
        check = function(inst)
            local h = mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT6)
            return mc.mcSignalGetState(h) == 1 and "on" or "off"
        end,
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Front Vacuum\nON"},
                  off = {bg = "#FF0000", fg = "#FFFFFF", label = "Front Vacuum\nOFF"}}
    },
    
    -- Vacuum Auto Mode
    btnVacAuto = {
        check = function(inst)
            local h = mc.mcSignalGetHandle(inst, mc.OSIG_OUTPUT51)
            return mc.mcSignalGetState(h) == 1 and "on" or "off"
        end,
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Vac Auto\nENABLED"},
                off = {bg = "#FF0000", fg = "#FFFFFF", label = "Vac Auto\nDISABLED"}}
    },
    
    -- === SYSTEM CONTROL BUTTONS ===
    
    -- Soft Limits
    btnSoftLimits = {
        check = function(inst)
            local state = mc.mcSignalGetState(mc.mcSignalGetHandle(inst, mc.OSIG_SOFTLIMITS_ON))
            return (state == 1) and "on" or "off"
        end,
        flashFreq = 9,  -- Slower flash - every 15 cycles (3.3 Hz)
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Soft Limits\nENABLED"},
                  off = {bg = "#FF0000", fg = "#FFFFFF", label = "Soft Limits\nDISABLED"},
                  off_flash = {bg = "#FFFF00", fg = "#000000", label = "Soft Limits\nDISABLED"}}
    },
    
    -- Keyboard Jog (already exists but including for completeness)
    btnKeyboardJog = {
        check = {io = "Keyboard/Enable"},
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Keyboard\nInputs ENABLED"},
                  off = {bg = "#90EE90", fg = "#808080", label = "Keyboard\nInputs DISABLED"}}
    },
    
    -- Reference All Axes / Homing Status
    btnRefAllAxes = {
        check = function(inst)
            local state = mc.mcCntlGetState(inst)
            if state == mc.MC_STATE_HOME then return "homing" end
            
            local x = mc.mcAxisIsHomed(inst, mc.X_AXIS)
            local y = mc.mcAxisIsHomed(inst, mc.Y_AXIS)
            local z = mc.mcAxisIsHomed(inst, mc.Z_AXIS)
            
            return (x == 1 and y == 1 and z == 1) and "homed" or "unhomed"
        end,
        flashFreq = 5,
        states = {homed = {bg = "#4B4B4B", fg = "#FFFFFF", label = "XYZ\nHomed"},
                  unhomed = {bg = "#FFFF00", fg = "#000000", label = "HOME\nREQUIRED"},
                  unhomed_flash = {bg = "#FF0000", fg = "#FFFFFF", label = "HOME\nREQUIRED"},
                  homing = {bg = "#FFFF00", fg = "#000000", label = "HOMING..."},
                  homing_flash = {bg = "#4B4B4B", fg = "#FFFFFF", label = "HOMING..."},
                  bypassed = {bg = "#FF8800", fg = "#000000", label = "HOMING\nBYPASSED"}}
    },
    
    -- Custom Fixture Table
    btnCustomFixtureTable = {
        check = function(inst) return "off" end,  -- Static button
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"}}
    },
    
    -- Target Move
    btnTargetMove = {
        check = function(inst) return "off" end,  -- Static button
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF", label = "Target\nMove"}}
    },
    
    -- === TOOL/PROBE BUTTONS ===
    
    -- Laser Deploy
    btnLaserDeploy = {
        check = function(inst)
            local tool = mc.mcToolGetCurrent(inst)
            return (tool == 91) and "on" or "off"
        end,
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Retract\nLaser"},
                  off = {bg = "#FF0000", fg = "#FFFFFF", label = "Deploy\nLaser"}}
    },
    
    -- Laser Activate
    btnLaserActivate = {
        check = function(inst)
            local hreg = mc.mcRegGetHandle(inst, "ESS/Laser/Test_Mode_Activate")
            if hreg ~= 0 then
                return mc.mcRegGetValue(hreg) == 1 and "on" or "off"
            end
            return "off"
        end,
        disabled = function(inst)
            return mc.mcToolGetCurrent(inst) ~= 91
        end,
        flashFreq = 5,  -- Fast flash for danger (10 Hz)
        states = {on = {bg = "#FF6600", fg = "#FFFF00", label = "Laser FIRING\nClick to DISABLE"},
                  on_flash = {bg = "#FFFF00", fg = "#FF0000", label = "Laser FIRING\nClick to DISABLE"},
                  off = {bg = "#FF0000", fg = "#FFFFFF", label = "Activate Laser\nClick to ENABLE"},
                  disabled = {bg = "#808080", fg = "#C0C0C0", label = "Laser Inactive\nDeploy First"}}
    },
    
    -- Probe Deploy
    btnProbeDeploy = {
        check = function(inst)
            local tool = mc.mcToolGetCurrent(inst)
            return (tool == 90) and "on" or "off"
        end,
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Retract Probe\nChange to T0"},
                  off = {bg = "#FF0000", fg = "#FFFFFF", label = "Deploy Probe\nChange to T90"}}
    },
    
    -- === STATUS LEDS ===
    
    -- Spindle On LED
    ledSpindleOn = {
        check = {signal = mc.OSIG_SPINDLEON},
        states = {on = {bg = "#00FF00"},
                  off = {bg = "#4B4B4B"}}
    },
    
    -- Machine Enabled LED
    ledMachineEnabled = {
        check = {signal = mc.OSIG_MACHINE_ENABLED},
        states = {on = {bg = "#00FF00"},
                  off = {bg = "#FF0000"}}
    },
    
    -- Plate Align LED (G68 status)
    ledPlateAlign = {
        check = function(inst)
            return math.abs((mc.mcCntlGetPoundVar(inst, 4016) or 0) - 69) == 0 and "off" or "on"
        end,
        states = {on = {bg = "#00FF00"},
                  off = {bg = "#4B4B4B"}}
    },

    btnToggleSpindle = {
        check = {signal = mc.OSIG_SPINDLEON},
        states = {on = {bg = "#00FF00", fg = "#000000", label = "Spindle\nON"},
                off = {bg = "#4B4B4B", fg = "#FFFFFF", label = "Spindle\nOFF"}}
    },

    -- === OVERRIDE BUTTONS (disabled during M6 using #499 flag) ===

    -- Feed Rate Override buttons
    btnFRO200 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    btnFRO150 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    btnFRO100 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    btnFRO50 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    btnFRO5 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    -- Rapid Rate Override buttons
    btnRRO100 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    btnRRO50 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    btnRRO10 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    -- Spindle RPM Override buttons
    btnSRO150 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    btnSRO125 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    btnSRO100 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    btnSRO75 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

    btnSRO50 = {
        check = function(inst) return "off" end,
        disabled = function(inst)
            return mc.mcCntlGetPoundVar(inst, 499) == 1
        end,
        states = {off = {bg = "#4B4B4B", fg = "#FFFFFF"},
                  disabled = {bg = "#808080", fg = "#C0C0C0"}}
    },

}



-- Main UI Update Function - Call from PLC
function UpdateUIStates()
    local inst = mc.mcGetInstance()
    
    -- Update button/LED appearances
    for elementName, config in pairs(UIStates) do
        local currentState
        
        -- Check if disabled first (overrides normal state)
        if config.disabled and config.disabled(inst) then
            currentState = "disabled"
        else
            -- Determine normal state
            if type(config.check) == "function" then
                currentState = config.check(inst)
            else
                if config.check.pvar then
                    local val = mc.mcCntlGetPoundVar(inst, config.check.pvar)
                    if config.check.equals then
                        currentState = (val == config.check.equals) and "on" or "off"
                    else -- must be notequals
                        currentState = (val ~= config.check.notequals) and "on" or "off"
                    end
                elseif config.check.signal then
                    local h = mc.mcSignalGetHandle(inst, config.check.signal)
                    currentState = mc.mcSignalGetState(h) == 1 and "on" or "off"
                elseif config.check.io then
                    local h = mc.mcIoGetHandle(inst, config.check.io)
                    currentState = mc.mcIoGetState(h) == 1 and "on" or "off"
                end
            end
        end
        
        -- Handle flashing states
        if currentState and config.states[currentState .. "_flash"] then
            -- This state has a flash alternate
            local freq = config.flashFreq or 10  -- Default 10 PLC cycles per flash
            local flashOn = (math.floor(UIFlashCounter / freq) % 2) == 0
            currentState = flashOn and currentState or (currentState .. "_flash")
        end
        
        -- Update if state changed
        if UILastStates[elementName] ~= currentState then
            UILastStates[elementName] = currentState
            local stateProps = config.states[currentState]
            
            -- Update properties - let it fail if element doesn't exist
            if stateProps.bg then 
                scr.SetProperty(elementName, 'Bg Color', stateProps.bg) 
            end
            if stateProps.fg then 
                scr.SetProperty(elementName, 'Fg Color', stateProps.fg) 
            end
            if stateProps.label then 
                scr.SetProperty(elementName, 'Label', stateProps.label) 
            end
            if config.disabled then
                scr.SetProperty(elementName, 'Enabled', currentState == "disabled" and '0' or '1')
            end
        end
    end
    
    -- Increment flash counter
    UIFlashCounter = (UIFlashCounter + 1) % 1000  -- Reset at 1000 to prevent overflow
end


function UpdateDynamicLabels()
    local inst = mc.mcGetInstance()
    scr.SetProperty('CycleTime', 'Label', SecondsToTime(mc.mcCntlGetRunTime(inst)))

    local t = mc.mcToolGetCurrent(inst) or 0
    scr.SetProperty('lblToolPreview', 'Label', t > 0 and string.format("T%d - %s", t, mc.mcToolGetDesc(inst, t) or "") or "T0 - No Tool")

    -- Machine state display
    local machState = mc.mcCntlGetState(inst)
    local stateText = "Unknown"
    if machState == 0 then stateText = "Idle"
    elseif machState == 4 then stateText = "Jogging"
    elseif machState == 100 then stateText = "Running"
    elseif machState == 101 then stateText = "Paused"
    elseif machState == 102 then stateText = "Feed Hold"
    elseif machState >= 100 and machState < 200 then stateText = "File Run"
    elseif machState >= 200 and machState < 300 then stateText = "MDI/Macro"
    elseif machState == mc.MC_STATE_MRUN_MACROH then stateText = "M6 Running"
    elseif machState == mc.MC_STATE_MRUN_MACROH_HOLD then stateText = "M6 Hold"
    elseif machState == mc.MC_STATE_HOME then stateText = "Homing"
    end
    scr.SetProperty('lblMachState', 'Label', string.format("%s (%d)", stateText, machState))

    -- G68 Rotation Display
    local g68Mode = mc.mcCntlGetPoundVar(inst, 4016)
    local rotationAngle = 0

    if g68Mode == 68 then  -- G68 is active
        rotationAngle = mc.mcCntlGetPoundVar(inst, mc.SV_ROTATION) or 0
    end

    -- Format the angle display (show 0 if G69 is active or no rotation)
    local angleText = string.format("%.3f°", rotationAngle)
    scr.SetProperty('lblG68Rot', 'Label', angleText)
    

    -- Disable override sliders and DROs during M6
    local inM6 = mc.mcCntlGetPoundVar(inst, 499) == 1
    local enabledStr = inM6 and '0' or '1'
    -- Disable sliders
    scr.SetProperty('slideFRO', 'Enabled', enabledStr)
    scr.SetProperty('slideRRO', 'Enabled', enabledStr)
    scr.SetProperty('slideSRO', 'Enabled', enabledStr)
    -- Disable DROs
    scr.SetProperty('droRapidRate', 'Enabled', enabledStr)
    scr.SetProperty('droFeedRateOver', 'Enabled', enabledStr)
    scr.SetProperty('droSpinRPMOVR', 'Enabled', enabledStr)




    -- Sync jog rate UI with actual jog rate
    local actualRate = mc.mcJogGetRate(inst, 0)  -- Use X axis as reference
    -- SAFETY FIX: Don't update UI to 100% to prevent jog rate corruption
    -- This prevents shift-jog on X-axis from corrupting the default rate
    if actualRate ~= 100 then
        local uiRateStr = scr.GetProperty("slJogRate", "Value")
        if uiRateStr ~= nil then
            local uiRate = tonumber(uiRateStr) or 0
            if math.abs(actualRate - uiRate) > 0.1 then
                scr.SetProperty("slJogRate", "Value", tostring(actualRate))
                -- droJogRate will auto-update since they share DRO code 391
            end
        end
    end

end




-- System Settings Configuration
SYSTEM_SETTINGS = {
    {
        title = "Touch Probe (T90)",
        settings = {
            {var = 511, label = "Probe Diameter +X", unit = "in",
             tooltip = "Effective diameter of the probe tip in the +X direction."},
            {var = 512, label = "Probe Diameter -X", unit = "in",
             tooltip = "Effective diameter of the probe tip in the -X direction."},
            {var = 513, label = "Probe Diameter +Y", unit = "in",
             tooltip = "Effective diameter of the probe tip in the +Y direction."},
            {var = 514, label = "Probe Diameter -Y", unit = "in",
             tooltip = "Effective diameter of the probe tip in the -Y direction."},
            {var = 515, label = "Probe Tip Z Offset", unit = "in",
             tooltip = "Effective Z probe diameter compensation for spring-loaded probes."},
            {var = 516, label = "Fast Feed", unit = "ipm",
             tooltip = "Initial fast approach speed for probing."},
            {var = 517, label = "Slow Feed", unit = "ipm",
             tooltip = "Final slow approach speed for accurate measurement."},
            {var = 518, label = "Max Travel", unit = "in",
             tooltip = "Maximum probe travel before aborting."},
            {var = 519, label = "Backoff 1", unit = "in",
             tooltip = "Distance to retract after first probe contact."},
            {var = 520, label = "Backoff 2", unit = "in",
             tooltip = "Distance to retract after final measurement."}
        }
    },
    {
        title = "Laser (T91)",
        settings = {
            {var = 521, label = "X Offset", unit = "in",
             tooltip = "X distance from spindle to laser crosshair."},
            {var = 522, label = "Y Offset", unit = "in",
             tooltip = "Y distance from spindle to laser crosshair."}
        }
    },
    {
        title = "Tool Change",
        settings = {
            {var = 523, label = "Tool Change Z", unit = "in",
             tooltip = "Z height in machine coordinates for tool changes."},
            {var = 524, label = "Pullout Distance", unit = "in",
             tooltip = "Y distance to pull tool forward after grabbing."},
            {var = 525, label = "Approach Feed", unit = "ipm",
             tooltip = "Feedrate when approaching tool holders."}
        }
    },
    {
        title = "Height Setter",
        settings = {
            {var = 526, label = "Station X", unit = "in",
             tooltip = "X machine coordinate of tool height setter."},
            {var = 527, label = "Station Y", unit = "in",
             tooltip = "Y machine coordinate of tool height setter."},
            {var = 528, label = "Spindle Rim Z", unit = "in",
             tooltip = "Z machine coordinate of spindle rim (reference for all tool heights)."},
            {var = 529, label = "Max Probe Depth", unit = "in",
             tooltip = "Maximum Z depth when searching for height setter."},
            {var = 530, label = "Fast Feed", unit = "ipm",
             tooltip = "Initial approach speed for height measurement."},
            {var = 531, label = "Slow Feed", unit = "ipm",
             tooltip = "Final approach speed for accurate measurement."},
            {var = 532, label = "Retract", unit = "in",
             tooltip = "Distance to retract between measurements."},
            {var = 533, label = "Spindle Probe X Offset", unit = "in",
             tooltip = "X offset for probing spindle rim with T0 (typically 0.85\")."}
        }
    },
    {
        title = "Keytop Replacement",
        settings = {
            {var = 540, label = "Left Bore X (Machine)", unit = "in",
             tooltip = "X machine coordinate of left calibration bore center."},
            {var = 541, label = "Left Bore Y (Machine)", unit = "in",
             tooltip = "Y machine coordinate of left calibration bore center."}
        }
    }
}

function LoadSystemSettings()
    -- Loop through sections first
    for _, section in ipairs(SYSTEM_SETTINGS) do
        -- Then loop through settings within each section
        for _, setting in ipairs(section.settings) do
            local value = mc.mcProfileGetDouble(inst, "SystemSettings", "PV" .. setting.var, 0)
            mc.mcCntlSetPoundVar(inst, setting.var, value)
        end
    end
end
LoadSystemSettings()


-- System Settings Dialog Function
function SystemSettings()
    local VALUE_FORMAT = "%.4f"
    
    -- Create dialog
    local dialog = wx.wxDialog(wx.NULL, wx.wxID_ANY, "System Settings",
                              wx.wxDefaultPosition, wx.wxSize(450, 500))
    dialog:Centre()
    local panel = wx.wxPanel(dialog, wx.wxID_ANY)
    local mainSizer = wx.wxBoxSizer(wx.wxVERTICAL)
    local scroll = wx.wxScrolledWindow(panel, wx.wxID_ANY)
    scroll:SetScrollRate(0, 20)
    local scrollSizer = wx.wxBoxSizer(wx.wxVERTICAL)
    local inputs = {}
    
    -- Calculate maximum label width for consistent alignment
    local maxLabelWidth = 0
    for _, section in ipairs(SYSTEM_SETTINGS) do
        for _, setting in ipairs(section.settings) do
            local testLabel = wx.wxStaticText(scroll, wx.wxID_ANY, setting.label .. ":")
            local width = testLabel:GetBestSize():GetWidth()
            if width > maxLabelWidth then
                maxLabelWidth = width
            end
            testLabel:Destroy()
        end
    end
    
    -- Build UI for each section
    for _, section in ipairs(SYSTEM_SETTINGS) do
        -- Section header
        local header = wx.wxStaticText(scroll, wx.wxID_ANY, section.title)
        header:SetFont(wx.wxFont(10, wx.wxFONTFAMILY_DEFAULT, 
                                wx.wxFONTSTYLE_NORMAL, wx.wxFONTWEIGHT_BOLD))
        scrollSizer:Add(header, 0, wx.wxALL, 10)
        -- Create grid for settings - FIX: Use 0 for dynamic rows
        local grid = wx.wxFlexGridSizer(0, 3, 5, 10)
        grid:AddGrowableCol(1)
        for _, setting in ipairs(section.settings) do
            -- Read current value from pound variable
            local currentValue = mc.mcCntlGetPoundVar(inst, setting.var)
            local displayValue = string.format(VALUE_FORMAT, currentValue)
            -- Create controls with fixed widths for alignment
            local label = wx.wxStaticText(scroll, wx.wxID_ANY, setting.label .. ":",
                                         wx.wxDefaultPosition, wx.wxSize(maxLabelWidth, -1),
                                         wx.wxALIGN_RIGHT)
            local input = wx.wxTextCtrl(scroll, wx.wxID_ANY, displayValue,
                                       wx.wxDefaultPosition, wx.wxSize(120, -1))
            -- Fixed width for unit labels to maintain alignment
            local unit = wx.wxStaticText(scroll, wx.wxID_ANY, setting.unit,
                                        wx.wxDefaultPosition, wx.wxSize(30, -1))
            input:SetToolTip(setting.tooltip)
            grid:Add(label, 0, wx.wxALIGN_RIGHT + wx.wxALIGN_CENTER_VERTICAL)
            grid:Add(input, 0, wx.wxEXPAND)
            grid:Add(unit, 0, wx.wxALIGN_LEFT + wx.wxALIGN_CENTER_VERTICAL)
            inputs[setting.var] = input
        end
        scrollSizer:Add(grid, 0, wx.wxALL + wx.wxEXPAND, 10)
        scrollSizer:Add(wx.wxStaticLine(scroll, wx.wxID_ANY), 0, 
                       wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT, 10)
    end
    
    scroll:SetSizer(scrollSizer)
    scroll:FitInside()
    mainSizer:Add(scroll, 1, wx.wxEXPAND + wx.wxALL, 5)
    -- Button panel
    local btnPanel = wx.wxPanel(panel, wx.wxID_ANY)
    local btnSizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
    local btnOK = wx.wxButton(btnPanel, wx.wxID_OK, "Save")
    local btnCancel = wx.wxButton(btnPanel, wx.wxID_CANCEL, "Cancel")
    btnSizer:AddStretchSpacer()
    btnSizer:Add(btnOK, 0, wx.wxALL, 5)
    btnSizer:Add(btnCancel, 0, wx.wxALL, 5)
    btnPanel:SetSizer(btnSizer)
    mainSizer:Add(btnPanel, 0, wx.wxEXPAND + wx.wxALL, 5)
    panel:SetSizer(mainSizer)
    if dialog:ShowModal() == wx.wxID_OK then
        for var, input in pairs(inputs) do
            local value = tonumber(input:GetValue())
            mc.mcCntlSetPoundVar(inst, var, value)
            mc.mcProfileWriteDouble(inst, "SystemSettings", "PV" .. var, value)
        end
        mc.mcProfileFlush(inst)
        mc.mcCntlSetLastError(inst, "Settings saved")
    end
    dialog:Destroy()
end


-- PLC Execution Time Stats
PLCStats = {times = {}, last = os.clock()}
function GetPLCStats(execTime)
    table.insert(PLCStats.times, execTime)
    -- Print every 10 seconds
    if os.clock() - PLCStats.last > 10 and #PLCStats.times > 0 then
        table.sort(PLCStats.times)
        local n = #PLCStats.times
        mc.mcCntlSetLastError(inst, string.format(
            "PLC: %.4f/%.4f/%.4fms", 
            PLCStats.times[1], 
            PLCStats.times[math.ceil(n/2)], 
            PLCStats.times[n]
        ))
        PLCStats.times = {}
        PLCStats.last = os.clock()
    end
end


-- Initialize dialog system registers
function InitDialogSystem()
    package.loaded.mcRegister = nil
    local mcReg = require "mcRegister"
    
    local registers = {
        {"DialogRequest", "Dialog request flag", "0"},
        {"DialogResponse", "Dialog response flag", "0"},
        {"DialogType", "Dialog type string", ""},
        {"DialogParam1", "Dialog parameter 1", ""},
        {"DialogParam2", "Dialog parameter 2", ""},
        {"DialogParam3", "Dialog parameter 3", ""},
        {"DialogResult", "Dialog result value", "0"},
        {"DialogResultData", "Dialog result data", ""},
        {"DialogFieldData", "Serialized field definitions", ""},
        {"DialogProfileSection", "Profile section for persistence", ""},
        {"DialogButtonLabels", "OK/Cancel button labels", ""},
        {"DialogValidation", "Validation results", ""},
        {"DialogEnableStates", "Enable/disable states", ""},
        {"DialogSequence", "Dialog sequence number", "0"},
        {"DialogError", "Dialog error flag", "0"},
        {"DialogCallback", "Callback request flag", "0"},
        {"DialogCallbackType", "Type of callback", ""},
        {"DialogCallbackData", "Callback data", ""},
        {"DialogCallbackResult", "Callback result", ""},
        -- Deferred G-code loading (for loading files after macro returns)
        {"DeferredGCodeFile", "File path for deferred loading", ""},
        {"DeferredGCodeRequest", "Request flag for deferred loading", "0"}
    }
    local created = 0
    local existing = 0
    
    for _, reg in ipairs(registers) do
        local name, desc, initial = reg[1], reg[2], reg[3]
        local handle = mc.mcRegGetHandle(inst, "iRegs0/" .. name)
        
        if handle == 0 then
            mcReg.Add(inst, "iRegs0", name, desc, initial, false)
            created = created + 1
        else
            existing = existing + 1
        end
    end
    if created > 0 then
        mc.mcCntlSetLastError(inst, string.format("Dialog registers: %d created, %d existing", created, existing))
    end
end
InitDialogSystem()

-- Clean up orphaned dialog temp files on startup
function CleanupTemp()
    local tempPath = "C:\\Mach4Hobby\\Profiles\\BLP\\Temp\\"
    
    if wx.wxDirExists(tempPath) then
        local dir = wx.wxDir(tempPath)
        if dir:IsOpened() then
            local found, filename = dir:GetFirst("dialog_*.lua")
            while found do
                os.remove(tempPath .. filename)
                found, filename = dir:GetNext()
            end

            found, filename = dir:GetFirst("dialog_*.txt")
            while found do
                os.remove(tempPath .. filename)
                found, filename = dir:GetNext()
            end
        end
    end
end
CleanupTemp()

-- Process deferred G-code loading (called from PLC when machine is idle)
-- Macros can't load G-code files directly (error -18), so they write a marker file.
-- This function checks for the marker, loads the G-code, and deletes the marker.
function ProcessDeferredGCode()
    local markerPath = "C:\\Mach4Hobby\\Profiles\\BLP\\Temp\\DeferredGCode.txt"
    local markerFile = io.open(markerPath, "r")
    if not markerFile then return end

    local filePath = markerFile:read("*all")
    markerFile:close()
    os.remove(markerPath)

    if filePath and filePath ~= "" then
        local inst = mc.mcGetInstance()
        mc.mcCntlLoadGcodeFile(inst, filePath)
        CycleStart()
    end
end

-- Process dialog requests from PLC
function ProcessDialogRequest()
    local inst = mc.mcGetInstance()
    
    local hRequest = mc.mcRegGetHandle(inst, "iRegs0/DialogRequest")
    if hRequest == 0 then return end
    
    local request = mc.mcRegGetValue(hRequest)
    if request ~= 1 then return end
    
    -- Clear request immediately
    mc.mcRegSetValue(hRequest, 0)
    
    local hType = mc.mcRegGetHandle(inst, "iRegs0/DialogType")
    local dialogType = mc.mcRegGetValueString(hType)
    
    if dialogType == "SHOW_DIALOG" then
        -- Call the new ShowDialogScreen function
        ShowDialogScreen(inst)
        
        -- Set response flag
        local hResponse = mc.mcRegGetHandle(inst, "iRegs0/DialogResponse")
        mc.mcRegSetValue(hResponse, 1)
        
    elseif dialogType == "DEBUG" then
        -- Keep debug handling for testing
        local hParam1 = mc.mcRegGetHandle(inst, "iRegs0/DialogParam1")
        local param1 = mc.mcRegGetValueString(hParam1)
        
        local result = wx.wxMessageBox(
            string.format("Debug Dialog\nParam1: %s", param1),
            "Screen Dialog Test",
            wx.wxYES_NO + wx.wxICON_QUESTION
        )
        
        local hResult = mc.mcRegGetHandle(inst, "iRegs0/DialogResult")
        mc.mcRegSetValue(hResult, result == wx.wxYES and 1 or 0)
        
        local hResponse = mc.mcRegGetHandle(inst, "iRegs0/DialogResponse")
        mc.mcRegSetValue(hResponse, 1)
    end
end

-- Dynamic Dialog Screen Generator 
function ShowDialogScreen(inst)
    local tempPath = "C:\\Mach4Hobby\\Profiles\\BLP\\Temp\\"
    local sequence = mc.mcRegGetValue(mc.mcRegGetHandle(inst, "iRegs0/DialogSequence"))
    local requestFile = tempPath .. string.format("dialog_request_%d.txt", sequence)
    local responseFile = tempPath .. string.format("dialog_response_%d.txt", sequence)
    local fieldsFile = tempPath .. string.format("dialog_fields_%d.lua", sequence)
    
    -- Read fields from file
    local fieldsFunc = loadfile(fieldsFile)
    if not fieldsFunc then
        mc.mcCntlSetLastError(inst, "ShowDialogScreen: No fields file found")
        return nil
    end
    
    local fields = fieldsFunc()
    
    -- Read request parameters
    local file = io.open(requestFile, "r")
    if not file then
        mc.mcCntlSetLastError(inst, "ShowDialogScreen: No request file found")
        return nil
    end
    
    local request = {}
    for line in file:lines() do
        local key, value = line:match("^([^=]+)=(.*)$")
        if key then
            request[key] = value
        end
    end
    file:close()
    
    -- Create dialog with optional width from request (nil = auto-fit)
    local dialogWidth = tonumber(request.width)
    local dialog = wx.wxDialog(wx.NULL, wx.wxID_ANY, request.title or "Dialog",
                               wx.wxDefaultPosition, dialogWidth and wx.wxSize(dialogWidth, -1) or wx.wxDefaultSize)

    local panel = wx.wxPanel(dialog, wx.wxID_ANY)
    if dialogWidth then
        panel:SetMinSize(wx.wxSize(dialogWidth - 20, -1))
    end
    local sizer = wx.wxBoxSizer(wx.wxVERTICAL)
    
    local controls = {}
    local validationLabels = {}
    local connections = {}
    
    -- Helper to track connections
    local function connectAndTrack(control, id, event, handler)
        control:Connect(id, event, handler)
        table.insert(connections, {control = control, id = id, event = event})
    end
    
    -- Helper for horizontal lines
    local function HLine(p) return wx.wxStaticLine(p, wx.wxID_ANY) end
    
    -- Trigger all field updates
    local function triggerUpdates()
        -- Handle enableIf conditions
        for _, field in ipairs(fields) do
            if field.enableIf and controls[field.key] then
                -- Request callback from macro side
                local hCallback = mc.mcRegGetHandle(inst, "iRegs0/DialogCallback")
                local hCallbackType = mc.mcRegGetHandle(inst, "iRegs0/DialogCallbackType")
                local hCallbackData = mc.mcRegGetHandle(inst, "iRegs0/DialogCallbackData")
                local hCallbackResult = mc.mcRegGetHandle(inst, "iRegs0/DialogCallbackResult")
                
                -- Serialize control values for callback
                local controlValues = {}
                for k, v in pairs(controls) do
                    if type(v.GetValue) == "function" then
                        controlValues[k] = v:GetValue()
                    elseif v.GetValue then
                        controlValues[k] = v.GetValue()
                    end
                end
                
                mc.mcRegSetValueString(hCallbackType, "enableIf")
                mc.mcRegSetValueString(hCallbackData, field.key)
                mc.mcRegSetValue(hCallback, 1)
                
                -- Wait briefly for result
                wx.wxMilliSleep(50)
                
                local enabled = mc.mcRegGetValue(hCallbackResult) == 1
                controls[field.key]:Enable(enabled)
                
                if controls[field.key .. "_label"] then
                    controls[field.key .. "_label"]:SetForegroundColour(
                        enabled and wx.wxBLACK or wx.wxColour(128, 128, 128))
                end
            end
        end
        
        panel:Layout()
    end
    
    -- Build each field
    for _, field in ipairs(fields) do
        
        if field.type == "instructions" then
            local text = wx.wxStaticText(panel, wx.wxID_ANY, field.text)
            local font = text:GetFont()
            font:SetPointSize(font:GetPointSize() - 1)
            text:SetFont(font)
            if dialogWidth then text:Wrap(dialogWidth - 40) end  -- Wrap text to fit dialog with margins
            if field.tooltip then text:SetToolTip(field.tooltip) end
            sizer:Add(text, 0, wx.wxALL + wx.wxEXPAND, 10)
            
        elseif field.type == "direction" then
            local label = wx.wxStaticText(panel, wx.wxID_ANY, field.label)
            sizer:Add(label, 0, wx.wxALIGN_CENTER + wx.wxTOP, 10)
            
            -- Direction grid with full functionality
            local gridPanel = wx.wxPanel(panel, wx.wxID_ANY)
            local dirGrid = wx.wxGridSizer(3, 3, 5, 5)
            local buttons = {}
            local selectedDirection = field.default or 0
            
            local positions = {nil, 2, nil, 1, nil, 0, nil, 3, nil}
            
            for i = 1, 9 do
                if positions[i] then
                    local idx = positions[i]
                    local labels = {[0]="+X", [1]="-X", [2]="+Y", [3]="-Y"}
                    buttons[idx] = wx.wxToggleButton(gridPanel, wx.wxID_ANY, labels[idx])
                    buttons[idx]:SetMinSize(wx.wxSize(50, 30))
                    if field.tooltip then buttons[idx]:SetToolTip(field.tooltip) end
                    dirGrid:Add(buttons[idx], 0, wx.wxEXPAND)
                    
                    if idx == selectedDirection then
                        buttons[idx]:SetValue(true)
                    end
                    
                    connectAndTrack(buttons[idx], wx.wxID_ANY, wx.wxEVT_COMMAND_TOGGLEBUTTON_CLICKED,
                        function(event)
                            for j = 0, 3 do
                                buttons[j]:SetValue(j == idx)
                            end
                            selectedDirection = idx
                            
                            -- Handle onChange callback if present
                            if field.onChange then
                                triggerUpdates()
                            end
                        end)
                else
                    dirGrid:Add(wx.wxStaticText(gridPanel, wx.wxID_ANY, ""), 0, wx.wxEXPAND)
                end
            end
            
            controls[field.key] = {
                GetValue = function() return selectedDirection end,
                SetValue = function(newDir)
                    selectedDirection = newDir
                    for i = 0, 3 do
                        buttons[i]:SetValue(i == newDir)
                    end
                end,
                Enable = function(state)
                    for i = 0, 3 do buttons[i]:Enable(state) end
                end,
                buttons = buttons,
                EnableButton = function(idx, state)
                    if buttons[idx] then buttons[idx]:Enable(state) end
                end,
                EnableAxis = function(axis, state)
                    if axis == "X" then
                        buttons[0]:Enable(state)  -- +X
                        buttons[1]:Enable(state)  -- -X
                    elseif axis == "Y" then
                        buttons[2]:Enable(state)  -- +Y
                        buttons[3]:Enable(state)  -- -Y
                    end
                end
            }
            
            -- Handle constraintHandler if present
            if field.constraintHandler then
                -- Apply constraints based on field definition
                if field.disableXIfProbeY then
                    controls[field.key].EnableAxis("X", false)
                elseif field.disableYIfProbeX then
                    controls[field.key].EnableAxis("Y", false)
                end
            end
            
            gridPanel:SetSizer(dirGrid)
            sizer:Add(gridPanel, 0, wx.wxALIGN_CENTER + wx.wxALL, 10)
            
        elseif field.type == "radio" then
            local radioBox = wx.wxRadioBox(panel, wx.wxID_ANY, field.label,
                                          wx.wxDefaultPosition, wx.wxDefaultSize,
                                          field.options, field.columns or 2,
                                          wx.wxRA_SPECIFY_COLS)
            radioBox:SetSelection(field.default or 0)
            if field.tooltip then radioBox:SetToolTip(field.tooltip) end
            controls[field.key] = radioBox
            sizer:Add(radioBox, 0, wx.wxEXPAND + wx.wxALL, 5)
            
            connectAndTrack(radioBox, wx.wxID_ANY, wx.wxEVT_COMMAND_RADIOBOX_SELECTED,
                function(event)
                    if field.onChange then
                        triggerUpdates()
                    end
                end)

        elseif field.type == "choice" then
            local row = wx.wxBoxSizer(wx.wxHORIZONTAL)

            local label = wx.wxStaticText(panel, wx.wxID_ANY, field.label)
            label:SetMinSize(wx.wxSize(140, -1))
            controls[field.key .. "_label"] = label
            row:Add(label, 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxALL, 5)

            local choice = wx.wxChoice(panel, wx.wxID_ANY, wx.wxDefaultPosition,
                                       wx.wxSize(180, -1), field.options)
            choice:SetSelection(field.default or 0)
            if field.tooltip then choice:SetToolTip(field.tooltip) end
            controls[field.key] = choice
            row:Add(choice, 1, wx.wxEXPAND + wx.wxALL, 5)

            sizer:Add(row, 0, wx.wxEXPAND)

            connectAndTrack(choice, wx.wxID_ANY, wx.wxEVT_COMMAND_CHOICE_SELECTED,
                function(event)
                    if field.onChange then
                        triggerUpdates()
                    end
                end)

        elseif field.type == "number" then
            local row = wx.wxBoxSizer(wx.wxHORIZONTAL)

            local label = wx.wxStaticText(panel, wx.wxID_ANY, field.label)
            label:SetMinSize(wx.wxSize(140, -1))
            controls[field.key .. "_label"] = label
            row:Add(label, 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxALL, 5)

            -- Format based on whether it's an integer or decimal field
            local formatStr = field.isInteger and "%d" or string.format("%%.%df", field.decimals or 4)
            local textCtrl = wx.wxTextCtrl(panel, wx.wxID_ANY,
                string.format(formatStr, field.default or 0))
            textCtrl:SetMinSize(wx.wxSize(100, -1))
            if field.tooltip then textCtrl:SetToolTip(field.tooltip) end
            controls[field.key] = textCtrl
            row:Add(textCtrl, 1, wx.wxEXPAND + wx.wxALL, 5)
            
            sizer:Add(row, 0, wx.wxEXPAND)
            
            -- Validation label if validate present
            if field.validate then
                local validLabel = wx.wxStaticText(panel, wx.wxID_ANY, "")
                local font = validLabel:GetFont()
                font:SetPointSize(font:GetPointSize() - 1)
                validLabel:SetFont(font)
                validLabel:SetForegroundColour(wx.wxColour(200, 0, 0))
                if dialogWidth then validLabel:Wrap(dialogWidth - 180) end  -- Wrap text to fit available width
                sizer:Add(validLabel, 0, wx.wxEXPAND + wx.wxLEFT, 160)
                validationLabels[field.key] = validLabel
            end
            
            connectAndTrack(textCtrl, wx.wxID_ANY, wx.wxEVT_TEXT,
                function(event)
                    local value = tonumber(textCtrl:GetValue())
                    
                    -- Handle validation
                    if field.validate and value then
                        local isValid = true
                        local errorMsg = ""
                        
                        if field.validateMin and value < field.validateMin then
                            isValid = false
                            errorMsg = field.validateMsg or string.format("Must be >= %g", field.validateMin)
                        elseif field.validateMax and value > field.validateMax then
                            isValid = false
                            errorMsg = field.validateMsg or string.format("Must be <= %g", field.validateMax)
                        end
                        
                        if validationLabels[field.key] then
                            validationLabels[field.key]:SetLabel(isValid and "" or errorMsg)
                            if dialogWidth then validationLabels[field.key]:Wrap(dialogWidth - 180) end
                        end
                        textCtrl:SetForegroundColour(isValid and wx.wxBLACK or wx.wxColour(200, 0, 0))
                        textCtrl:Refresh()
                    end
                    
                    if field.onChange then
                        triggerUpdates()
                    end
                end)
            
        elseif field.type == "text" then
            local row = wx.wxBoxSizer(wx.wxHORIZONTAL)
            
            local label = wx.wxStaticText(panel, wx.wxID_ANY, field.label)
            label:SetMinSize(wx.wxSize(140, -1))
            controls[field.key .. "_label"] = label
            row:Add(label, 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxALL, 5)
            
            local textCtrl = wx.wxTextCtrl(panel, wx.wxID_ANY, field.default or "")
            textCtrl:SetMinSize(wx.wxSize(150, -1))
            if field.tooltip then textCtrl:SetToolTip(field.tooltip) end
            controls[field.key] = textCtrl
            row:Add(textCtrl, 1, wx.wxEXPAND + wx.wxALL, 5)
            
            sizer:Add(row, 0, wx.wxEXPAND)
            
            connectAndTrack(textCtrl, wx.wxID_ANY, wx.wxEVT_TEXT,
                function(event)
                    if field.onChange then
                        triggerUpdates()
                    end
                end)
            
        elseif field.type == "checkbox" then
            local checkbox = wx.wxCheckBox(panel, wx.wxID_ANY, field.label)
            checkbox:SetValue(field.default == 1)
            if field.tooltip then checkbox:SetToolTip(field.tooltip) end
            controls[field.key] = checkbox
            sizer:Add(checkbox, 0, wx.wxALL, 5)
            
            connectAndTrack(checkbox, wx.wxID_ANY, wx.wxEVT_COMMAND_CHECKBOX_CLICKED,
                function(event)
                    if field.onChange then
                        triggerUpdates()
                    end
                end)
            
        elseif field.type == "description" then
            local text = wx.wxStaticText(panel, wx.wxID_ANY, field.text or "")
            local font = text:GetFont()
            font:SetPointSize(font:GetPointSize() - 1)
            font:SetStyle(wx.wxFONTSTYLE_ITALIC)
            text:SetFont(font)
            text:SetForegroundColour(wx.wxColour(60, 60, 60))
            controls[field.key] = text
            sizer:Add(text, 0, wx.wxEXPAND + wx.wxALL, 10)
            
        elseif field.type == "separator" then
            sizer:Add(HLine(panel), 0, wx.wxEXPAND + wx.wxALL, 10)
            
        elseif field.type == "grid" then
            local gridSizer = wx.wxFlexGridSizer(0, field.columns or 2, 5, field.spacing or 10)
            for col = 0, (field.columns or 2) - 1 do
                gridSizer:AddGrowableCol(col)
            end
            
            for _, child in ipairs(field.children) do
                local itemPanel = wx.wxPanel(panel, wx.wxID_ANY)
                local itemRow = wx.wxBoxSizer(wx.wxHORIZONTAL)
                
                local label = wx.wxStaticText(itemPanel, wx.wxID_ANY, child.label)
                label:SetMinSize(wx.wxSize(50, -1))
                controls[child.key .. "_label"] = label
                itemRow:Add(label, 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 2)
                
                local textCtrl = wx.wxTextCtrl(itemPanel, wx.wxID_ANY,
                    string.format("%.4f", child.default or 0))
                textCtrl:SetMinSize(wx.wxSize(child.width or 60, -1))
                if child.tooltip then textCtrl:SetToolTip(child.tooltip) end
                controls[child.key] = textCtrl
                itemRow:Add(textCtrl, 1, wx.wxEXPAND)
                
                connectAndTrack(textCtrl, wx.wxID_ANY, wx.wxEVT_TEXT,
                    function(event)
                        if child.onChange then
                            triggerUpdates()
                        end
                    end)
                
                itemPanel:SetSizer(itemRow)
                gridSizer:Add(itemPanel, 1, wx.wxEXPAND)
            end
            
            sizer:Add(gridSizer, 0, wx.wxEXPAND + wx.wxALL, 5)
            
        elseif field.type == "section" then
            local staticBox = wx.wxStaticBox(panel, wx.wxID_ANY, field.label)
            local boxSizer = wx.wxStaticBoxSizer(staticBox, wx.wxVERTICAL)
            
            local inner = wx.wxPanel(panel, wx.wxID_ANY)
            local innerSizer = wx.wxBoxSizer(wx.wxVERTICAL)
            
            for _, child in ipairs(field.children) do
                if child.type == "number" then
                    local row = wx.wxBoxSizer(wx.wxHORIZONTAL)
                    local label = wx.wxStaticText(inner, wx.wxID_ANY, child.label)
                    label:SetMinSize(wx.wxSize(120, -1))
                    row:Add(label, 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxALL, 5)
                    
                    local textCtrl = wx.wxTextCtrl(inner, wx.wxID_ANY,
                        string.format("%.4f", child.default or 0))
                    if child.tooltip then textCtrl:SetToolTip(child.tooltip) end
                    controls[child.key] = textCtrl
                    row:Add(textCtrl, 1, wx.wxEXPAND + wx.wxALL, 5)
                    
                    connectAndTrack(textCtrl, wx.wxID_ANY, wx.wxEVT_TEXT,
                        function(event)
                            if child.onChange then
                                triggerUpdates()
                            end
                        end)
                    
                    innerSizer:Add(row, 0, wx.wxEXPAND)
                end
            end
            
            inner:SetSizer(innerSizer)
            boxSizer:Add(inner, 0, wx.wxEXPAND)
            sizer:Add(boxSizer, 0, wx.wxEXPAND + wx.wxALL, 5)
        end
    end
    
    -- Initial update
    triggerUpdates()
    
    -- Buttons
    sizer:Add(HLine(panel), 0, wx.wxEXPAND + wx.wxALL, 10)
    local buttonSizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
    
    local okButton = wx.wxButton(panel, wx.wxID_OK, request.okLabel or "OK")
    okButton:SetDefault()
    local cancelButton = wx.wxButton(panel, wx.wxID_CANCEL, request.cancelLabel or "Cancel")
    
    buttonSizer:Add(okButton, 0, wx.wxALL, 5)
    buttonSizer:Add(cancelButton, 0, wx.wxALL, 5)
    sizer:Add(buttonSizer, 0, wx.wxALIGN_CENTER + wx.wxALL, 10)
    
    panel:SetSizer(sizer)
    
    local root = wx.wxBoxSizer(wx.wxVERTICAL)
    root:Add(panel, 1, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT, 10)
    dialog:SetSizer(root)
    dialog:Fit()
    dialog:Centre()
    
    -- Show and collect results
    local result = nil
    if dialog:ShowModal() == wx.wxID_OK then
        result = {}
        
        -- Collect all values
        for _, field in ipairs(fields) do
            if controls[field.key] and field.key then
                if field.type == "direction" then
                    result[field.key] = controls[field.key].GetValue()
                elseif field.type == "radio" then
                    result[field.key] = controls[field.key]:GetSelection()
                elseif field.type == "choice" then
                    result[field.key] = controls[field.key]:GetSelection()
                elseif field.type == "number" then
                    result[field.key] = tonumber(controls[field.key]:GetValue())
                elseif field.type == "text" then
                    result[field.key] = controls[field.key]:GetValue()
                elseif field.type == "checkbox" then
                    result[field.key] = controls[field.key]:GetValue()
                end
            end
            
            -- Collect grid children
            if field.type == "grid" and field.children then
                for _, child in ipairs(field.children) do
                    if controls[child.key] then
                        result[child.key] = tonumber(controls[child.key]:GetValue())
                    end
                end
            end
            
            -- Collect section children
            if field.type == "section" and field.children then
                for _, child in ipairs(field.children) do
                    if controls[child.key] and child.type == "number" then
                        result[child.key] = tonumber(controls[child.key]:GetValue())
                    end
                end
            end
        end
    end
    
    -- Cleanup
    for _, conn in ipairs(connections) do
        pcall(function()
            conn.control:Disconnect(conn.id, conn.event)
        end)
    end
    connections = nil
    controls = nil
    validationLabels = nil
    
    wx.wxSafeYield()
    collectgarbage("collect")
    collectgarbage("collect")
    
    dialog:Destroy()
    
    -- Write response
    local respFile = io.open(responseFile, "w")
    if respFile then
        if result then
            respFile:write("success=true\n")
            for k, v in pairs(result) do
                respFile:write(string.format("%s=%s\n", k, tostring(v)))
            end
        else
            respFile:write("success=false\n")
        end
        respFile:close()
    end
    
    -- Clean up request files
    os.remove(requestFile)
    os.remove(fieldsFile)
    
    return result
end




--Must be at the END of the script
UIUpdateTimer = wx.wxTimer()
UIUpdateTimer:Connect(wx.wxEVT_TIMER, function(event)
    UIFlashCounter = (UIFlashCounter + 1) % 1000
    UpdateUIStates()
    UpdateDynamicLabels()
    ButtonEnable()
end)
UIUpdateTimer:Start(100)