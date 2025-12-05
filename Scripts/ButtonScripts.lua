local inst = mc.mcGetInstance()


-- Target Move Function
function TargetMove()
    -- Load user preferences from profile
    local lastCoordMode = mc.mcProfileGetString(inst, "TargetMove", "LastCoordMode", "work")
    local lastMoveType = mc.mcProfileGetString(inst, "TargetMove", "LastMoveType", "rapid")
    local lastFeedRate = mc.mcProfileGetString(inst, "TargetMove", "LastFeedRate", "100")
    local lastZFirst = mc.mcProfileGetString(inst, "TargetMove", "LastZFirst", "true") == "true"
    
    -- Get current positions
    local currentWorkX = mc.mcAxisGetPos(inst, mc.X_AXIS)
    local currentWorkY = mc.mcAxisGetPos(inst, mc.Y_AXIS)
    local currentWorkZ = mc.mcAxisGetPos(inst, mc.Z_AXIS)
    local currentMachineX = mc.mcAxisGetMachinePos(inst, mc.X_AXIS)
    local currentMachineY = mc.mcAxisGetMachinePos(inst, mc.Y_AXIS)
    local currentMachineZ = mc.mcAxisGetMachinePos(inst, mc.Z_AXIS)
    
    -- Get current fixture
    local currentFixture = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_14)
    local fixtureText = string.format("G%.0f", currentFixture)
    
    -- Create dialog
    local dialog = wx.wxDialog(wx.NULL, wx.wxID_ANY, "Target Move", 
                              wx.wxDefaultPosition, wx.wxSize(450, 400))
    
    -- Add keyboard shortcuts
    dialog:Connect(wx.wxEVT_CHAR_HOOK, function(event)
        local keyCode = event:GetKeyCode()
        if keyCode == wx.WXK_RETURN then
            dialog:EndModal(wx.wxID_OK)
        elseif keyCode == wx.WXK_ESCAPE then
            dialog:EndModal(wx.wxID_CANCEL)
        else
            event:Skip()
        end
    end)
    
    local panel = wx.wxPanel(dialog, wx.wxID_ANY)
    local mainSizer = wx.wxBoxSizer(wx.wxVERTICAL)
    
    -- Coordinate system selection
    local coordChoices = {"Work (" .. fixtureText .. ")", "Machine Coords"}
    local coordRadio = wx.wxRadioBox(panel, wx.wxID_ANY, "Coordinate System", 
                                     wx.wxDefaultPosition, wx.wxDefaultSize,
                                     coordChoices, 2, wx.wxRA_SPECIFY_COLS)
    
    -- Set initial coordinate mode
    if lastCoordMode == "machine" then
        coordRadio:SetSelection(1)
    else
        coordRadio:SetSelection(0)
    end
    
    mainSizer:Add(coordRadio, 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT + wx.wxTOP, 10)
    
    -- Move type selection with integrated feed rate
    local moveBox = wx.wxStaticBoxSizer(wx.wxVERTICAL, panel, "Move Type")
    
    local moveChoices = {"Rapid (G0)", "Feed Rate (G1)"}
    local moveRadio = wx.wxRadioBox(panel, wx.wxID_ANY, "",
                                    wx.wxDefaultPosition, wx.wxDefaultSize,
                                    moveChoices, 2, wx.wxRA_SPECIFY_COLS)
    
    -- Set initial move type
    if lastMoveType == "feed" then
        moveRadio:SetSelection(1)
    else
        moveRadio:SetSelection(0)
    end
    
    moveBox:Add(moveRadio, 0, wx.wxEXPAND + wx.wxALL, 5)
    
    -- Feed rate input
    local feedSizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
    feedSizer:Add(wx.wxStaticText(panel, wx.wxID_ANY, "Feed Rate:"), 0, 
                  wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 10)
    local feedInput = wx.wxTextCtrl(panel, wx.wxID_ANY, lastFeedRate,
                                    wx.wxDefaultPosition, wx.wxSize(80, -1))
    feedSizer:Add(feedInput, 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 5)
    feedSizer:Add(wx.wxStaticText(panel, wx.wxID_ANY, "IPM"), 0, 
                  wx.wxALIGN_CENTER_VERTICAL)
    
    -- Enable/disable based on initial selection
    feedInput:Enable(moveRadio:GetSelection() == 1)
    
    moveBox:Add(feedSizer, 0, wx.wxLEFT + wx.wxRIGHT + wx.wxBOTTOM, 10)
    mainSizer:Add(moveBox, 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT + wx.wxTOP, 10)
    
    -- Input fields
    -- Input fields
    local inputSizer = wx.wxFlexGridSizer(3, 3, 10, 10)
    inputSizer:AddGrowableCol(1)
    
    local xLabel = wx.wxStaticText(panel, wx.wxID_ANY, "X:")
    local xInput = wx.wxTextCtrl(panel, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize(150, -1))
    local xUnit = wx.wxStaticText(panel, wx.wxID_ANY, "in")
    
    local yLabel = wx.wxStaticText(panel, wx.wxID_ANY, "Y:")
    local yInput = wx.wxTextCtrl(panel, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize(150, -1))
    local yUnit = wx.wxStaticText(panel, wx.wxID_ANY, "in")
    
    local zLabel = wx.wxStaticText(panel, wx.wxID_ANY, "Z:")
    local zInput = wx.wxTextCtrl(panel, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize(150, -1))
    local zUnit = wx.wxStaticText(panel, wx.wxID_ANY, "in")
    
    inputSizer:Add(xLabel, 0, wx.wxALIGN_RIGHT + wx.wxALIGN_CENTER_VERTICAL)
    inputSizer:Add(xInput, 0, wx.wxEXPAND)
    inputSizer:Add(xUnit, 0, wx.wxALIGN_LEFT + wx.wxALIGN_CENTER_VERTICAL)
    inputSizer:Add(yLabel, 0, wx.wxALIGN_RIGHT + wx.wxALIGN_CENTER_VERTICAL)
    inputSizer:Add(yInput, 0, wx.wxEXPAND)
    inputSizer:Add(yUnit, 0, wx.wxALIGN_LEFT + wx.wxALIGN_CENTER_VERTICAL)
    inputSizer:Add(zLabel, 0, wx.wxALIGN_RIGHT + wx.wxALIGN_CENTER_VERTICAL)
    inputSizer:Add(zInput, 0, wx.wxEXPAND)
    inputSizer:Add(zUnit, 0, wx.wxALIGN_LEFT + wx.wxALIGN_CENTER_VERTICAL)
    
    mainSizer:Add(inputSizer, 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT + wx.wxTOP, 15)
    
    -- Update input values function
    local function updateInputs()
        local selection = coordRadio:GetSelection()
        if selection == 1 then -- Machine
            xInput:SetValue(string.format("%.4f", currentMachineX))
            yInput:SetValue(string.format("%.4f", currentMachineY))
            zInput:SetValue(string.format("%.4f", currentMachineZ))
        else -- Work (0)
            xInput:SetValue(string.format("%.4f", currentWorkX))
            yInput:SetValue(string.format("%.4f", currentWorkY))
            zInput:SetValue(string.format("%.4f", currentWorkZ))
        end
        xInput:SetFocus()
        xInput:SetSelection(-1, -1)
    end
    
    -- Connect radio events
    coordRadio:Connect(wx.wxEVT_COMMAND_RADIOBOX_SELECTED, function(event)
        updateInputs()
    end)
    
    moveRadio:Connect(wx.wxEVT_COMMAND_RADIOBOX_SELECTED, function(event)
        feedInput:Enable(moveRadio:GetSelection() == 1)
        if moveRadio:GetSelection() == 1 then
            feedInput:SetFocus()
            feedInput:SetSelection(-1, -1)
        end
    end)
    
    -- Set tab order for better keyboard navigation
    yInput:MoveAfterInTabOrder(xInput)
    zInput:MoveAfterInTabOrder(yInput)
    feedInput:MoveAfterInTabOrder(zInput)
    
    -- Z-order checkbox
    local zOrderSizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
    local zFirstCheckbox = wx.wxCheckBox(panel, wx.wxID_ANY, "Move Z first (safer for clearance)")
    zFirstCheckbox:SetValue(lastZFirst)
    zFirstCheckbox:SetToolTip(
        "When CHECKED: Z axis rises to safe height first, then XY moves to position, then Z descends to target.\n" ..
        "• Use for maximum safety when obstacles might be in the path\n" ..
        "• Prevents tool crashes when moving between parts\n" ..
        "• Recommended for most operations\n\n" ..
        "When UNCHECKED: XY moves to position first, then Z moves directly to target height.\n" ..
        "• Use when you're certain the path is clear\n" ..
        "• Faster for operations at the same Z height\n" ..
        "• Good for rapid positioning over known clear areas"
    )
    zOrderSizer:Add(zFirstCheckbox, 0, wx.wxALIGN_CENTER_VERTICAL)
    mainSizer:Add(zOrderSizer, 0, wx.wxALIGN_CENTER + wx.wxTOP + wx.wxBOTTOM, 5)
    
    -- Dialog buttons
    local buttonSizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
    local okButton = wx.wxButton(panel, wx.wxID_OK, "Execute Move")
    local cancelButton = wx.wxButton(panel, wx.wxID_CANCEL, "Cancel")
    okButton:SetMinSize(wx.wxSize(110, 35))
    cancelButton:SetMinSize(wx.wxSize(90, 35))
    buttonSizer:Add(okButton, 0, wx.wxRIGHT, 10)
    buttonSizer:Add(cancelButton, 0)
    mainSizer:Add(buttonSizer, 0, wx.wxALIGN_CENTER + wx.wxTOP + wx.wxBOTTOM, 8)
    
    panel:SetSizer(mainSizer)
    dialog:Centre()
    
    -- Initialize inputs
    updateInputs()
    
    -- Show dialog
    if dialog:ShowModal() == wx.wxID_OK then
        -- Get values
        local targetX = tonumber(xInput:GetValue())
        local targetY = tonumber(yInput:GetValue())
        local targetZ = tonumber(zInput:GetValue())
        
        -- Basic coordinate validation
        if not targetX or not targetY or not targetZ then
            wx.wxMessageBox("Invalid coordinate values!", "Input Error")
            dialog:Destroy()
            return
        end
        
        -- Get options from radio boxes
        local coordSelection = coordRadio:GetSelection()
        local moveSelection = moveRadio:GetSelection()
        
        local useRapid = (moveSelection == 0)
        local feedRate = tonumber(feedInput:GetValue())
        local useMachineCoords = (coordSelection == 1)
        local moveZFirst = zFirstCheckbox:GetValue()
        
        -- Validate feed rate if using G1
        if not useRapid then
            if not feedRate or feedRate < 1 or feedRate > 600 then
                wx.wxMessageBox("Feed rate must be between 1 and 600 IPM!", "Input Error")
                dialog:Destroy()
                return
            end
        end
        
        -- Save preferences (map radio selections to strings)
        local coordModes = {[0] = "work", [1] = "machine"}
        local moveModes = {[0] = "rapid", [1] = "feed"}
        
        mc.mcProfileWriteString(inst, "TargetMove", "LastCoordMode", coordModes[coordSelection])
        mc.mcProfileWriteString(inst, "TargetMove", "LastMoveType", moveModes[moveSelection])
        mc.mcProfileWriteString(inst, "TargetMove", "LastFeedRate", tostring(feedRate or 100))
        mc.mcProfileWriteString(inst, "TargetMove", "LastZFirst", tostring(moveZFirst))
        
        -- Build G-code
        local gcode = "G90\n" -- Ensure absolute mode

        -- For work coordinate moves, temporarily disable G68 to move to actual work position
        local g68Active = false
        if not useMachineCoords then
            local g68Mode = mc.mcCntlGetPoundVar(inst, 4016) -- Check if G68 is active (4016 = 68 if active)
            if g68Mode == 68 then
                g68Active = true
                gcode = gcode .. "G69\n" -- Temporarily cancel G68
            end
        end

        local moveCmd = useRapid and "G0" or string.format("G1 F%.1f", feedRate)

        -- Absolute mode (work or machine)
        local prefix = useMachineCoords and "G53 " or ""

        if moveZFirst then
            -- Retract Z to safe height if moving XY significantly
            local deltaX = math.abs(targetX - (useMachineCoords and currentMachineX or currentWorkX))
            local deltaY = math.abs(targetY - (useMachineCoords and currentMachineY or currentWorkY))
            if (deltaX > 0.1 or deltaY > 0.1) then
                -- Only retract if not already at safe height
                local safeZ = -0.050  -- Safe retract height in machine coords
                if currentMachineZ < safeZ then
                    gcode = gcode .. string.format("G53 G0 Z%.4f\n", safeZ)
                end
            end
            gcode = gcode .. string.format("%s%s X%.4f Y%.4f\n", prefix, moveCmd, targetX, targetY)
            gcode = gcode .. string.format("%s%s Z%.4f", prefix, moveCmd, targetZ)
        else
            -- XY first, then Z
            gcode = gcode .. string.format("%s%s X%.4f Y%.4f\n", prefix, moveCmd, targetX, targetY)
            gcode = gcode .. string.format("%s%s Z%.4f", prefix, moveCmd, targetZ)
        end

        -- Restore G68 if it was active
        if g68Active then
            -- Get the CURRENT G68 rotation parameters (not fixture offsets!)
            local rotX = mc.mcCntlGetPoundVar(inst, mc.SV_ROTATION_X) or 0  -- 2135
            local rotY = mc.mcCntlGetPoundVar(inst, mc.SV_ROTATION_Y) or 0  -- 2136
            local rotR = mc.mcCntlGetPoundVar(inst, mc.SV_ROTATION) or 0    -- 2137
            gcode = gcode .. string.format("\nG68 X%.4f Y%.4f R%.4f", rotX, rotY, rotR)
        end
        
        -- Log and execute
        local coordType = useMachineCoords and "Machine" or fixtureText
        mc.mcCntlSetLastError(inst, string.format("Target Move: %s to X%.4f Y%.4f Z%.4f", 
                              coordType, targetX, targetY, targetZ))
        
        mc.mcCntlMdiExecute(inst, gcode)
    end
    
    dialog:Destroy()
end



function LaserRaster()
    local PROFILE_SECTION = "LaserRaster"

    -- Load saved settings (will be overridden by image DPI if present)
    local feedStr = mc.mcProfileGetString(inst, PROFILE_SECTION, "FeedRate", "400")
    local lastFeed = tonumber(feedStr)
    if not lastFeed then lastFeed = 400 end

    -- UI
    local dlg = wx.wxDialog(wx.NULL, wx.wxID_ANY, "Laser Raster", wx.wxDefaultPosition, wx.wxSize(450, -1))
    local panel = wx.wxPanel(dlg, wx.wxID_ANY)
    local root = wx.wxBoxSizer(wx.wxVERTICAL)
    local function Label(text) return wx.wxStaticText(panel, wx.wxID_ANY, text) end
    local function HLine() return wx.wxStaticLine(panel, wx.wxID_ANY) end

    -- Controls
    local txtImage  = wx.wxTextCtrl(panel, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize(280, -1)); txtImage:Enable(false)
    local btnBrowse = wx.wxButton(panel, wx.wxID_ANY, "Browse…")

    local txtSize   = wx.wxTextCtrl(panel, wx.wxID_ANY, "--- x --- pixels", wx.wxDefaultPosition, wx.wxSize(200, -1)); txtSize:Enable(false)

    local txtFeed   = wx.wxTextCtrl(panel, wx.wxID_ANY, tostring(lastFeed))
    local txtPmin   = wx.wxTextCtrl(panel, wx.wxID_ANY, "1")
    local txtPmax   = wx.wxTextCtrl(panel, wx.wxID_ANY, "60")
    local txtTime = wx.wxTextCtrl(panel, wx.wxID_ANY, "--:-- min", wx.wxDefaultPosition, wx.wxSize(200, -1))

    -- DPI controls (will be populated from image metadata)
    local txtDpiX = wx.wxTextCtrl(panel, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize(60, -1))
    local txtDpiY = wx.wxTextCtrl(panel, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize(60, -1))

    -- Physical size controls (will be calculated from image)
    local txtPhysicalWidth = wx.wxTextCtrl(panel, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize(60, -1))
    local txtPhysicalHeight = wx.wxTextCtrl(panel, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize(60, -1))
    local chkLockAspect = wx.wxCheckBox(panel, wx.wxID_ANY, "Lock Aspect")
    chkLockAspect:SetValue(true)

    txtTime:Enable(false)

    local chkFlipX  = wx.wxCheckBox(panel, wx.wxID_ANY, "Flip X")
    local chkFlipY  = wx.wxCheckBox(panel, wx.wxID_ANY, "Flip Y")

    local rdoBL     = wx.wxRadioButton(panel, wx.wxID_ANY, "Bottom-Left", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxRB_GROUP)
    local rdoCent   = wx.wxRadioButton(panel, wx.wxID_ANY, "Center")
    rdoBL:SetValue(true)

    local rdoZCurrent  = wx.wxRadioButton(panel, wx.wxID_ANY, "Current Height", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxRB_GROUP)
    local rdoZEngrave  = wx.wxRadioButton(panel, wx.wxID_ANY, "Engraving (7mm)")
    local rdoZCut      = wx.wxRadioButton(panel, wx.wxID_ANY, "Cutting (4mm)")
    rdoZCurrent:SetValue(true)

    local btnRun    = wx.wxButton(panel, wx.wxID_OK, "Run")
    local btnCancel = wx.wxButton(panel, wx.wxID_CANCEL, "Cancel")

    -- Check for T91 (Laser tool)
    local currentTool = mc.mcToolGetCurrent(inst)
    if currentTool ~= 91 then
        -- Create tool change dialog using same style
        local toolDlg = wx.wxDialog(wx.NULL, wx.wxID_ANY, "Tool Check", 
            wx.wxDefaultPosition, wx.wxSize(350, -1))
        local toolPanel = wx.wxPanel(toolDlg, wx.wxID_ANY)
        local toolRoot = wx.wxBoxSizer(wx.wxVERTICAL)
        
        local function TLabel(text) return wx.wxStaticText(toolPanel, wx.wxID_ANY, text) end
        
        local msgText = TLabel(string.format("Current tool: T%d\n\nPlease deploy T91 (Laser) before running Laser Raster.", currentTool))
        msgText:Wrap(330)
        toolRoot:Add(msgText, 0, wx.wxALL + wx.wxALIGN_CENTER, 15)
        
        local btnSizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
        local btnChange = wx.wxButton(toolPanel, wx.wxID_OK, "Tool Change to T91")
        local btnTCancel = wx.wxButton(toolPanel, wx.wxID_CANCEL, "Cancel")
        btnSizer:Add(btnChange, 0, wx.wxRIGHT, 8)
        btnSizer:Add(btnTCancel, 0)
        toolRoot:Add(btnSizer, 0, wx.wxALIGN_CENTER + wx.wxBOTTOM, 10)
        
        toolPanel:SetSizer(toolRoot)
        toolRoot:Fit(toolDlg)
        toolDlg:Centre(wx.wxBOTH)
        
        local result = toolDlg:ShowModal()
        toolDlg:Destroy()
        
        if result == wx.wxID_OK then
            -- Change to T91
            mc.mcCntlGcodeExecuteWait(inst, "T91 M6")
            -- Verify tool change
            if mc.mcToolGetCurrent(inst) ~= 91 then
                wx.wxMessageBox("Tool change failed. Please change to T91 manually.", 
                    "Tool Error", wx.wxOK + wx.wxICON_ERROR)
                return
            end
        else
            return
        end
    end

    -- Layout
    do
        local row1 = wx.wxBoxSizer(wx.wxHORIZONTAL)
        row1:Add(Label("Image:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        row1:Add(txtImage, 1, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        row1:Add(btnBrowse, 0)
        root:Add(row1, 0, wx.wxEXPAND + wx.wxALL, 8)

        local rowPhysical = wx.wxBoxSizer(wx.wxHORIZONTAL)
        rowPhysical:Add(Label("Physical Size (in):"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        rowPhysical:Add(Label("W:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 4)
        rowPhysical:Add(txtPhysicalWidth, 0, wx.wxRIGHT, 8)
        rowPhysical:Add(Label("H:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 4)
        rowPhysical:Add(txtPhysicalHeight, 0, wx.wxRIGHT, 12)
        rowPhysical:Add(chkLockAspect, 0, wx.wxALIGN_CENTER_VERTICAL)
        root:Add(rowPhysical, 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT + wx.wxBOTTOM, 8)

        local rowDPI = wx.wxBoxSizer(wx.wxHORIZONTAL)
        rowDPI:Add(Label("DPI X:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        rowDPI:Add(txtDpiX, 0, wx.wxRIGHT, 12)
        rowDPI:Add(Label("DPI Y:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        rowDPI:Add(txtDpiY, 0)
        root:Add(rowDPI, 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT + wx.wxBOTTOM, 8)

        local row2 = wx.wxBoxSizer(wx.wxHORIZONTAL)
        row2:Add(Label("Output Resolution:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        row2:Add(txtSize, 0)
        root:Add(row2, 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT + wx.wxBOTTOM, 8)

        local rowTime = wx.wxBoxSizer(wx.wxHORIZONTAL)
        rowTime:Add(Label("Estimated time:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        rowTime:Add(txtTime, 0)
        root:Add(rowTime, 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT + wx.wxBOTTOM, 8)

        root:Add(HLine(), 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT, 8)

        local row3 = wx.wxBoxSizer(wx.wxHORIZONTAL)
        row3:Add(Label("Feedrate (IPM):"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        row3:Add(txtFeed, 0)
        root:Add(row3, 0, wx.wxEXPAND + wx.wxALL, 8)

        local row4 = wx.wxBoxSizer(wx.wxHORIZONTAL)
        row4:Add(Label("PWM Min %:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        row4:Add(txtPmin, 0, wx.wxRIGHT, 12)
        row4:Add(Label("PWM Max %:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        row4:Add(txtPmax, 0)
        root:Add(row4, 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT + wx.wxBOTTOM, 8)

        local row5 = wx.wxBoxSizer(wx.wxHORIZONTAL)
        row5:Add(chkFlipX, 0, wx.wxRIGHT, 12)
        row5:Add(chkFlipY, 0)
        root:Add(row5, 0, wx.wxLEFT + wx.wxRIGHT + wx.wxBOTTOM, 8)

        local row6 = wx.wxBoxSizer(wx.wxHORIZONTAL)
        row6:Add(Label("Start Position:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        row6:Add(rdoBL, 0, wx.wxRIGHT, 12)
        row6:Add(rdoCent, 0)
        root:Add(row6, 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT + wx.wxBOTTOM, 8)

        local rowZ = wx.wxBoxSizer(wx.wxHORIZONTAL)
        rowZ:Add(Label("Run at Z:"), 0, wx.wxALIGN_CENTER_VERTICAL + wx.wxRIGHT, 6)
        rowZ:Add(rdoZCurrent, 0, wx.wxRIGHT, 12)
        rowZ:Add(rdoZEngrave, 0, wx.wxRIGHT, 12)
        rowZ:Add(rdoZCut, 0)
        root:Add(rowZ, 0, wx.wxEXPAND + wx.wxLEFT + wx.wxRIGHT + wx.wxBOTTOM, 8)

        local row7 = wx.wxBoxSizer(wx.wxHORIZONTAL)
        row7:Add(btnRun, 0, wx.wxRIGHT, 8)
        row7:Add(btnCancel, 0)
        root:Add(row7, 0, wx.wxALIGN_RIGHT + wx.wxALL, 8)

        panel:SetSizer(root)
        root:Fit(dlg)
        dlg:Layout()
    end

    -- Image state
    local originalImage = nil  -- Store the loaded wx.wxImage
    local aspectRatio = 1.0  -- Width/Height ratio
    local updatingAspect = false  -- Flag to prevent recursive updates

    local function updateTimeEstimate()
        local feed = tonumber(txtFeed:GetValue())
        local physicalWidth = tonumber(txtPhysicalWidth:GetValue())
        local physicalHeight = tonumber(txtPhysicalHeight:GetValue())
        local targetDpiY = tonumber(txtDpiY:GetValue())

        if not (feed and physicalWidth and physicalHeight and targetDpiY) then
            txtTime:SetValue("--:-- min")
            return
        end

        -- Number of scan lines at target Y resolution
        local scan_lines = math.floor(physicalHeight * targetDpiY)

        -- Add fixed overhead for accel/decel zones (2" total)
        local row_distance = physicalWidth + 2.0
        local total_distance = row_distance * scan_lines
        local time_min = (total_distance / feed) * 1.15  -- add 15% for Y moves

        local total_seconds = time_min * 60
        local minutes = math.floor(total_seconds / 60)
        local seconds = math.floor(total_seconds % 60)
        txtTime:SetValue(string.format("%02d:%02d min", minutes, seconds))
    end

    local function updateSizeDisplay()
        local targetDpiX = tonumber(txtDpiX:GetValue())
        local targetDpiY = tonumber(txtDpiY:GetValue())
        local physicalWidth = tonumber(txtPhysicalWidth:GetValue())
        local physicalHeight = tonumber(txtPhysicalHeight:GetValue())

        if not (targetDpiX and targetDpiY and physicalWidth and physicalHeight) then
            txtSize:SetValue("--- x --- pixels")
            return
        end

        -- Calculate output resolution in pixels
        local outputPixelsX = math.floor(physicalWidth * targetDpiX + 0.5)
        local outputPixelsY = math.floor(physicalHeight * targetDpiY + 0.5)
        txtSize:SetValue(string.format("%d x %d pixels", outputPixelsX, outputPixelsY))
        updateTimeEstimate()
    end

    -- Load image from any supported format
    local function loadImage(path)
        local img = wx.wxImage()
        if not img:LoadFile(path) then
            return nil
        end

        local imgWidth = img:GetWidth()
        local imgHeight = img:GetHeight()
        aspectRatio = imgWidth / imgHeight

        -- Read DPI from image metadata
        local dpiX = img:GetOptionInt(wx.wxIMAGE_OPTION_RESOLUTIONX)
        local dpiY = img:GetOptionInt(wx.wxIMAGE_OPTION_RESOLUTIONY)
        local unit = img:GetOptionInt(wx.wxIMAGE_OPTION_RESOLUTIONUNIT)

        -- Handle combined DPI option (some formats store it differently)
        if dpiX == 0 or dpiY == 0 then
            local dpi = img:GetOptionInt(wx.wxIMAGE_OPTION_RESOLUTION)
            if dpi > 0 then
                dpiX = dpi
                dpiY = dpi
            end
        end

        -- Convert cm to inches if needed
        if unit == 2 and dpiX > 0 then
            dpiX = dpiX * 2.54
            dpiY = dpiY * 2.54
        end

        -- If image has DPI, use it. Otherwise default to 300
        if dpiX <= 0 then
            dpiX = 300
            dpiY = 300
        end

        -- Set DPI values (keep precision for accuracy)
        txtDpiX:SetValue(string.format("%.1f", dpiX))
        txtDpiY:SetValue(string.format("%.1f", dpiY))

        -- Calculate physical size from pixels and DPI
        txtPhysicalWidth:SetValue(string.format("%.3f", imgWidth / dpiX))
        txtPhysicalHeight:SetValue(string.format("%.3f", imgHeight / dpiY))

        return img
    end

    -- Convert image to grayscale BMP with specific DPI values
    local function createConvertedBMP(sourceImage, targetDpiX, targetDpiY, physicalWidth, physicalHeight)
        -- Fixed output path (always overwrites)
        local outputPath = "C:\\Mach4Hobby\\Laser_Files\\RasterBMP\\converted_temp.bmp"

        -- Ensure directory exists
        local dir = "C:\\Mach4Hobby\\Laser_Files\\RasterBMP"
        os.execute("cmd /c mkdir \"" .. dir .. "\" 2>NUL")

        -- Clone the image to avoid modifying the original
        local workingImg = sourceImage:Copy()

        -- Convert to grayscale
        workingImg = workingImg:ConvertToGreyscale()

        -- Calculate target pixel dimensions based on physical size and DPI
        -- This maintains aspect ratio while allowing different X/Y DPI
        local targetPixelsX = math.floor(physicalWidth * targetDpiX + 0.5)
        local targetPixelsY = math.floor(physicalHeight * targetDpiY + 0.5)

        -- Resample the image to the target dimensions
        workingImg:Rescale(targetPixelsX, targetPixelsY)

        -- Set DPI metadata (pass exact values - BMP format will round to nearest pixels/meter)
        workingImg:SetOption(wx.wxIMAGE_OPTION_RESOLUTIONX, targetDpiX)
        workingImg:SetOption(wx.wxIMAGE_OPTION_RESOLUTIONY, targetDpiY)
        workingImg:SetOption(wx.wxIMAGE_OPTION_RESOLUTIONUNIT, 1)  -- 1 = inches

        -- Save as BMP
        if not workingImg:SaveFile(outputPath, wx.wxBITMAP_TYPE_BMP) then
            return nil
        end

        return outputPath, targetPixelsX, targetPixelsY
    end

    -- Event handlers
    txtFeed:Connect(wx.wxEVT_TEXT, function()
        updateTimeEstimate()
    end)
    txtDpiX:Connect(wx.wxEVT_TEXT, function()
        updateSizeDisplay()
    end)
    txtDpiY:Connect(wx.wxEVT_TEXT, function()
        updateSizeDisplay()
    end)

    -- Physical dimension handlers with aspect ratio locking
    txtPhysicalWidth:Connect(wx.wxEVT_TEXT, function()
        if chkLockAspect:GetValue() and not updatingAspect then
            updatingAspect = true
            local width = tonumber(txtPhysicalWidth:GetValue())
            if width then
                txtPhysicalHeight:SetValue(string.format("%.3f", width / aspectRatio))
            end
            updatingAspect = false
        end
        updateSizeDisplay()
    end)

    txtPhysicalHeight:Connect(wx.wxEVT_TEXT, function()
        if chkLockAspect:GetValue() and not updatingAspect then
            updatingAspect = true
            local height = tonumber(txtPhysicalHeight:GetValue())
            if height then
                txtPhysicalWidth:SetValue(string.format("%.3f", height * aspectRatio))
            end
            updatingAspect = false
        end
        updateSizeDisplay()
    end)

    btnBrowse:Connect(wx.wxEVT_BUTTON, function()
        local fd = wx.wxFileDialog(dlg, "Select an image", "", "",
            "Image files (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tiff)|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tiff|" ..
            "PNG files (*.png)|*.png|" ..
            "JPEG files (*.jpg;*.jpeg)|*.jpg;*.jpeg|" ..
            "BMP files (*.bmp)|*.bmp|" ..
            "All files (*.*)|*.*",
            wx.wxFD_OPEN + wx.wxFD_FILE_MUST_EXIST)
        if fd:ShowModal() == wx.wxID_OK then
            local p = fd:GetPath()
            originalImage = loadImage(p)
            if originalImage then
                txtImage:SetValue(p)
                updateSizeDisplay()
            else
                wx.wxMessageBox("Failed to load image.", "Laser Raster", wx.wxOK + wx.wxICON_ERROR, dlg)
            end
        end
        fd:Destroy()
    end)

    -- Show
    dlg:Centre(wx.wxBOTH)
    if dlg:ShowModal() ~= wx.wxID_OK then
        dlg:Destroy()
        return
    end

    -- Extract values
    local feed_ipm  = tonumber(txtFeed:GetValue())
    local pmin      = tonumber(txtPmin:GetValue())
    local pmax      = tonumber(txtPmax:GetValue())
    local flipX     = chkFlipX:GetValue() and 1 or 0
    local flipY     = chkFlipY:GetValue() and 1 or 0
    local posBL     = rdoBL:GetValue()
    local zMode = rdoZCurrent:GetValue() and "current" or (rdoZEngrave:GetValue() and "engrave" or "cut")
    local targetDpiX = tonumber(txtDpiX:GetValue())
    local targetDpiY = tonumber(txtDpiY:GetValue())
    local physicalWidth = tonumber(txtPhysicalWidth:GetValue())
    local physicalHeight = tonumber(txtPhysicalHeight:GetValue())

    dlg:Destroy()

    -- Validate required values
    if not originalImage then
        mc.mcCntlSetLastError(inst, "Laser Raster: no image loaded.")
        return
    end

    if not (feed_ipm and targetDpiX and targetDpiY and physicalWidth and physicalHeight and pmin and pmax) then
        mc.mcCntlSetLastError(inst, "Laser Raster: missing required values.")
        return
    end

    -- Clamp PWM values to valid range
    pmin = math.max(0, math.min(100, math.floor(pmin)))
    pmax = math.max(0, math.min(100, math.floor(pmax)))

    -- Persist settings
    mc.mcProfileWriteString(inst, PROFILE_SECTION, "FeedRate", tostring(feed_ipm))
    mc.mcProfileWriteString(inst, PROFILE_SECTION, "DpiX", tostring(targetDpiX))
    mc.mcProfileWriteString(inst, PROFILE_SECTION, "DpiY", tostring(targetDpiY))

    -- Use the user-specified physical dimensions
    local w_in = physicalWidth
    local h_in = physicalHeight

    -- Current WCS position
    local x = mc.mcAxisGetPos(inst, mc.X_AXIS)
    local y = mc.mcAxisGetPos(inst, mc.Y_AXIS)
    local z = mc.mcAxisGetPos(inst, mc.Z_AXIS)

    -- Calculate target Z based on mode
    local targetZ = z  -- default to current
    if zMode == "engrave" then
        targetZ = 7/25.4 -- 7mm focus height in inches
    elseif zMode == "cut" then
        targetZ = 4/25.4 -- 4mm focus height in inches
    end

    -- Start position from BL or Center
    local startX, startY
    if posBL then
        startX, startY = x, y
    else
        startX = x - (w_in / 2.0)
        startY = y - (h_in / 2.0)
    end

    -- Emit G-code
    local g = {}
    local function line(s) g[#g+1] = s end
    line("(Laser Raster - Multi-format with DPI control)")
    line("G90 G20")
    line(string.format("G0 Z%.4f", targetZ))
    line(string.format("G0 X%.4f Y%.4f", startX, startY))

    -- Convert image to BMP with target DPI
    local convertedPath, finalPixelsX, finalPixelsY = createConvertedBMP(originalImage, targetDpiX, targetDpiY, w_in, h_in)

    if not convertedPath then
        mc.mcCntlSetLastError(inst, "Laser Raster: failed to convert image to BMP.")
        return
    end

    -- ESS raster macros
    line(string.format("M2000 (%s)", convertedPath))
    line("M2001(UNITS = IN)")
    line(string.format("M2001(FEEDRATE = %0.3f)", feed_ipm))
    line("M2001(IMAGE_STARTING_CORNER = 1)")
    line(string.format("M2001(IMAGE_FLIP_X = %d)", flipX))
    line(string.format("M2001(IMAGE_FLIP_Y = %d)", flipY))
    line(string.format("M2001(PWM_MAX = %d)", pmax))
    line(string.format("M2001(PWM_MIN = %d)", pmin))

    line("G4 P0.5")
    line("M2002")
    line("G4 P0.5")
    line("M30")

    -- Close any currently loaded G-code file
    mc.mcCntlCloseGCodeFile(inst)

    -- Write to temp and run
    local sp = wx.wxStandardPaths.Get()
    local outPath = wx.wxFileName(sp:GetTempDir(), "laser_raster.nc"):GetFullPath()
    local f = io.open(outPath, "w")
    if not f then
        mc.mcCntlSetLastError(inst, "Laser Raster: failed to open temp file for writing.")
        return
    end
    f:write(table.concat(g, "\n"), "\n")
    f:close()

    mc.mcCntlLoadGcodeFile(inst, outPath)
    mc.mcCntlCycleStart(inst)
end


