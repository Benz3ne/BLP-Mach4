	local INISection = "AutomationSetup"
	local inst = mc.mcGetInstance()
	AC = {}
	AC.Plasma = 1
	AC.Laser = 2
	AC.Oxy = 3
	AC.Propane = 4
	AC.WizardNames = 
	{
		[AC.Plasma] = "Plasma",
		[AC.Laser] = "Laser",
		[AC.Oxy] = "Oxy",
		[AC.Propane] = "Propane"
		
	}
	AC.AutomationVarKeys = {
		["Focus"] = "Focus", ["Gas Pressure"] = "Pressure", ["Gas Type"] = "Gas", ["Nozzle"] = "NozzleType", 
		["Diameter"] = "Diameter", ["Power"] = "Power", ["Air Flow"] = "Flow", ["Torch to Work Distance"] = "Height", ["Voltage"] = "Voltage"
	}
	AC.AutomationVariables = {
		[AC.Laser] = {"Focus", "Gas Pressure", "Gas Type", "Nozzle", "Diameter", "Power"},
		[AC.Plasma] = {"Voltage", "Torch to Work Distance", "Air Flow"},
		[AC.Oxy] = {}
	}
	AC.CutSettingModes = {
		[AC.Plasma] = {["Feed"] = {"Production", "Quality"}, ["Voltage"] = {"Production", "Quality"}}
	}
	AC.PierceSettingModes = {
		[AC.Oxy] = {["Preheat"] = {"Low", "High"}}
	}
	AC.ParkLocations = {"Material Load", "Consumable Change"}
	local axisCount = 3
	AC.axisLetters = {[0] = "X", [1] = "Y", [2] = "Z", [3] = "A", [4] = "B", [5] = "C"}
	AC.SetMachineTypeSpecificSettings = {
		[AC.Plasma]	= function(Settings, UI)
			local checkVal = UI["checkBoxTorchHeight"]:GetValue()
			local torchHeightDifferent = 0
			if checkVal == true then
				torchHeightDifferent = 1
			end
			rc = mc.mcProfileWriteInt(inst, INISection,"Plasma_TorchOnHeightDifferentFromPierceHeight", torchHeightDifferent)
			local CutSettings = AC.CutSettingModes[AC.Plasma]
			local SettingName = "Feed"
			
			local selection = UI["m_choice" .. SettingName]:GetSelection()
			if selection >= 0 then
				mc.mcProfileWriteString(inst, INISection,"Plasma_FeedCutSettingMode", CutSettings[SettingName][selection+1])
			end
			SettingName = "Voltage"
			selection = UI["m_choice" .. SettingName]:GetSelection()
			if selection >= 0 then
				mc.mcProfileWriteString(inst, INISection,"Plasma_VoltageCutSettingMode", CutSettings[SettingName][selection+1])
			end
		end,
		[AC.Oxy] = function(Settings, UI)
			local checkVal = UI["checkBoxTorchHeight"]:GetValue()
			local torchHeightDifferent = 0
			if checkVal == true then
				torchHeightDifferent = 1
			end
			rc = mc.mcProfileWriteInt(inst, INISection,"Oxy_TorchOnHeightDifferentFromPierceHeight", torchHeightDifferent)
			
			local PierceSettings = AC.PierceSettingModes[AC.Oxy]
			local SettingName = "Preheat"
			
			local selection = UI["m_choice" .. SettingName]:GetSelection()
			if selection >= 0 then
				mc.mcProfileWriteString(inst, INISection,"Oxy_PreheatPierceSettingMode", PierceSettings[SettingName][selection+1])
			end
		end
		
	}
	AC.GetMachineTypeSpecificSettings = {
		[AC.Plasma]	= function(Settings)
			Settings.CutFeed = mc.mcProfileGetString(inst, INISection,"Plasma_FeedCutSettingMode", "Production")
			Settings.CutVoltage = mc.mcProfileGetString(inst, INISection,"Plasma_VoltageCutSettingMode", "Production")
			Settings.TorchOnHeightDifferent = mc.mcProfileGetInt(inst, INISection,"Plasma_TorchOnHeightDifferentFromPierceHeight", 0)
		end,
		[AC.Oxy] = function(Settings)
			Settings.TorchOnHeightDifferent = mc.mcProfileGetInt(inst, INISection,"Oxy_TorchOnHeightDifferentFromPierceHeight", 0)
			Settings.PiercePreheat = mc.mcProfileGetString(inst, INISection,"Oxy_PreheatPierceSettingMode", "Production")
		end
		
	}
	function AC:SetSettings(Settings, UI)
		for name, tbl in pairs(Settings) do
			if AC.AutomationVarKeys[name] ~= nil then
				rc = mc.mcProfileWriteInt(inst, INISection,AC.AutomationVarKeys[name] .. "_PromptToChange", tbl.Prompt)
				rc = mc.mcProfileWriteInt(inst, INISection,AC.AutomationVarKeys[name] ..  "_MoveToPart", tbl.Move)
			end
		end
		if AC.SetMachineTypeSpecificSettings[self.MachineType] ~= nil then
			AC.SetMachineTypeSpecificSettings[self.MachineType](Settings, UI)
		end
	end
	function AC.GetSettings(MachineType)
		local SettingsNames = AC.AutomationVariables[MachineType]
		if SettingsNames == nil then
			mc.mcCntlSetLastError(inst, "mcAutomationConfiguration: Machine type doesn't exist")
			return
		end
		local inst = mc.mcGetInstance()
		local Settings = {}
		local SettingsKeys = wx.wxArrayString()
		for _, name in pairs(SettingsNames) do
			Settings[name] = {}
			--print(name)
			SettingsKeys:Add(name)
			Settings[name].Prompt = mc.mcProfileGetInt(inst, INISection,AC.AutomationVarKeys[name] .. "_PromptToChange", 0)
			Settings[name].Move = mc.mcProfileGetInt(inst, INISection,AC.AutomationVarKeys[name] ..  "_MoveToPart", 0)
		end
		SettingsKeys:Sort(false)
		if AC.GetMachineTypeSpecificSettings[MachineType] ~= nil then
			AC.GetMachineTypeSpecificSettings[MachineType](Settings)
		end
		return Settings, SettingsKeys
	end
	function AC.GetParkSettings(ParkLocations, AxisCount, MachineType)
		local inst = mc.mcGetInstance()
		local Settings = {}
		local SettingsKeys = wx.wxArrayString()
		for _, name in pairs(ParkLocations) do
			Settings[name] = {}
			SettingsKeys:Add(name)
			for i=0, AxisCount-1, 1 do
				local Axis = AC.axisLetters[i]
				Settings[name][Axis] = mc.mcProfileGetDouble(inst, INISection,AC.WizardNames[MachineType] .. name .. "_" .. Axis, 0)
			end
		end
		SettingsKeys:Sort(false)
		return Settings, SettingsKeys
	end
	function AC.SetParkSettings(ParkSettings, MachineType)
		local inst = mc.mcGetInstance()
		for name, tbl in pairs(ParkSettings) do
			for letter, val in pairs(tbl) do
				rc = mc.mcProfileWriteDouble(inst, INISection,AC.WizardNames[MachineType] .. name .. "_" .. letter, val)
			end
		end
	end
	function AC.GetAutomationGroups(Settings)
		local Prompt --= {}
		local Move --= {}
		for name, tbl in pairs(Settings) do
			if type(tbl) == "table" then
				if tbl.Prompt == 1 then -- prompt to change
					if Prompt == nil then
						Prompt = {}
					end
					Prompt[AC.AutomationVarKeys[name]] = 1
				elseif tbl.Move == 1 then --move to park
					if Move == nil then
						Move = {}
					end
					Move[AC.AutomationVarKeys[name]] = 1
				else -- Automated Process
					
				end
			end
		end
		return Prompt, Move
	end
	function AC.LaunchWizard(MachineType)
		local UI = {}
		local inst = mc.mcGetInstance()
		AC.MachineType = MachineType
		local Settings, SettingsKeys = AC.GetSettings(AC.MachineType)
		if SettingsKeys == nil then
			return
		end
		local ParkSettings, ParkSettingsKeys = AC.GetParkSettings(AC.ParkLocations, axisCount, MachineType)
		
		UI.MyFrame1 = wx.wxFrame (wx.NULL, wx.wxID_ANY, AC.WizardNames[MachineType] .. " Automation Configuration", wx.wxDefaultPosition, wx.wxSize( 250,100 ), wx.wxSIMPLE_BORDER+wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL + wx.wxSTAY_ON_TOP- wx.wxRESIZE_BORDER )
		UI.MyFrame1:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
		
		--UI.MyFrame1:SetIcon(wx.wxIcon(wx.wxIconLocation(mc.mcCntlGetMachDir(mc.mcGetInstance()).. "\\Mach4_Router.ico")))
		
		UI.gSizer1 =  wx.wxBoxSizer( wx.wxVERTICAL )
		
		UI.MyFrame1:SetBackgroundColour( wx.wxColour( 255, 255, 255 ) )
		
		UI.gbSizer1 = wx.wxGridBagSizer( 0, 0 )
		UI.gbSizer1:SetFlexibleDirection( wx.wxBOTH )
		UI.gbSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
		
		if SettingsKeys:GetCount() > 0 then
			
			UI.legendPanel = wx.wxPanel( UI.MyFrame1, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxSIMPLE_BORDER + wx.wxTAB_TRAVERSAL)
			UI.legendPanel:SetBackgroundColour( wx.wxColour( 255, 255, 255 ) )
			
			UI.gbSizer2 = wx.wxGridBagSizer( 0, 0 )
			UI.gbSizer2:SetFlexibleDirection( wx.wxBOTH )
			UI.gbSizer2:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
			
			--for name, tbl in pairs(Settings) do
			for index=0, SettingsKeys:GetCount()-1, 1 do
				--local index = i + 1
				local name = SettingsKeys:Item(index)
				local tbl = Settings[name]
				UI["staticText" .. index] = wx.wxStaticText(UI.legendPanel, wx.wxID_ANY, tostring(name), wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
				UI.gbSizer2:Add( UI["staticText" .. index], wx.wxGBPosition( index, 0), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxALIGN_LEFT, 5 )

				UI["checkBox" .. index] = wx.wxCheckBox( UI.legendPanel, wx.wxID_ANY, "Prompt to Change", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
				if tbl.Prompt == 1 then
					UI["checkBox" .. index]:SetValue(true)
				else
					UI["checkBox" .. index]:SetValue(false)
				end
				UI.gbSizer2:Add( UI["checkBox" .. index], wx.wxGBPosition( index, 2), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxALIGN_LEFT, 5 )
				
				UI["checkBox2" .. index] = wx.wxCheckBox( UI.legendPanel, wx.wxID_ANY, "Move to Park", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
				if tbl.Move == 1 then
					UI["checkBox2" .. index]:SetValue(true)
				else
					UI["checkBox2" .. index]:SetValue(false)
				end
				UI.gbSizer2:Add( UI["checkBox2" .. index], wx.wxGBPosition( index, 3), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxALIGN_LEFT, 5 )
				
				UI["checkBox" .. index]:Connect( wx.wxEVT_COMMAND_CHECKBOX_CLICKED, function(event)
					local checkVal = UI["checkBox" .. index]:GetValue()
					if checkVal == true then
						tbl.Prompt = 1
						tbl.Move = 0
						UI["checkBox2" .. index]:SetValue(false)
					else
						tbl.Prompt = 0
					end
				end )
				UI["checkBox2" .. index]:Connect( wx.wxEVT_COMMAND_CHECKBOX_CLICKED, function(event)
					local checkVal = UI["checkBox2" .. index]:GetValue()
					if checkVal == true then
						tbl.Move = 1
						tbl.Prompt = 0
						UI["checkBox" .. index]:SetValue(false)
					else
						tbl.Move = 0
					end
				end )
			end
			index = SettingsKeys:GetCount()
			UI.m_staticline1 = wx.wxStaticLine( UI.legendPanel, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxLI_VERTICAL )
			UI.gbSizer2:Add( UI.m_staticline1, wx.wxGBPosition( 0, 1 ), wx.wxGBSpan( index, 1 ),  wx. wxALL + wx.wxEXPAND, 5 )
			
			UI.legendPanel:SetSizer(UI.gbSizer2)
			UI.legendPanel:Layout()
			UI.gbSizer2:Fit(UI.legendPanel)

			UI.legendPanel:Fit(UI.gbSizer2)
			
			UI.gSizer1:Add(UI.legendPanel, 0, wx.wxALL, 5 )
		end
		
		UI.m_staticText1 = wx.wxStaticText( UI.MyFrame1, wx.wxID_ANY, "If no checkmark boxes are selected, we will assume the process is automated or ignored.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
		UI.m_staticText1:Wrap( -1 )
		
		UI.gbSizer1:Add(UI.m_staticText1, wx.wxGBPosition(0, 0), wx.wxGBSpan( 1, 4 ), wx.wxALL + wx.wxALIGN_LEFT, 5 )
		
		UI.StaticTextX = wx.wxStaticText(UI.MyFrame1, wx.wxID_ANY, "X", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
		UI.gbSizer1:Add( UI.StaticTextX, wx.wxGBPosition( 1, 1), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxALIGN_CENTER_HORIZONTAL, 5 )
		
		UI.StaticTextY = wx.wxStaticText(UI.MyFrame1, wx.wxID_ANY, "Y", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
		UI.gbSizer1:Add( UI.StaticTextY, wx.wxGBPosition( 1, 2), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxALIGN_CENTER_HORIZONTAL, 5 )
		
		UI.StaticTextZ = wx.wxStaticText(UI.MyFrame1, wx.wxID_ANY, "Z", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
		UI.gbSizer1:Add( UI.StaticTextZ, wx.wxGBPosition( 1, 3), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxALIGN_CENTER_HORIZONTAL, 5 )
		
		local index = 2
		--for name, tbl in pairs(ParkSettings) do
		for i=0, ParkSettingsKeys:GetCount()-1, 1 do
			local name = ParkSettingsKeys:Item(i)
			local tbl = ParkSettings[name]
			index = index + i
			UI[name .. "StaticText"] = wx.wxStaticText(UI.MyFrame1, wx.wxID_ANY, name, wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
			UI.gbSizer1:Add( UI[name .. "StaticText"], wx.wxGBPosition( index, 0), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxALIGN_LEFT, 5 )
			for ai=0, axisCount-1, 1 do
				local Axis = AC.axisLetters[ai]
				UI[name .. "SettingsCtrl" .. Axis] = wx.wxTextCtrl( UI.MyFrame1, wx.wxID_ANY,tostring(tbl[Axis]), wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
				UI.gbSizer1:Add( UI[name .. "SettingsCtrl" .. Axis], wx.wxGBPosition(index, ai+1), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxALIGN_LEFT, 5 )
				
				UI[name .. "SettingsCtrl" .. Axis]:Connect( wx.wxEVT_COMMAND_TEXT_UPDATED, function(event)
					local settingText = UI[name .. "SettingsCtrl" .. Axis]:GetValue()
					local Converted = tonumber(string.format("%.4f", settingText))
					if Converted ~= nil then
						print(Converted)
						tbl[Axis] = Converted
					end
					UI[name .. "SettingsCtrl" .. Axis]:SetValue(tostring(Converted))
				end)
			end
			UI[name .. "SetPosBtn"] = wx.wxButton( UI.MyFrame1, wx.wxID_ANY, "Set To Position", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
			UI.gbSizer1:Add( UI[name .. "SetPosBtn"] , wx.wxGBPosition( index, axisCount+1), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxALIGN_LEFT, 5 )
			
			UI[name .. "SetPosBtn"]:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
				--implements Add another spindle drowdown
				local inst = mc.mcGetInstance()
				for i=0, axisCount-1, 1 do
					local Axis = AC.axisLetters[i]
					local Val, rc = mc.mcAxisGetMachinePos(inst, i)
					if rc == 0 then
						tbl[Axis] = Val
					end
					UI[name .. "SettingsCtrl" .. Axis]:ChangeValue(tostring(Val))
				end
				event:Skip()
			end )
		end
		
		if MachineType == AC.Plasma then
			local torchOnHeightDifference = mc.mcProfileGetInt(inst, INISection,"Plasma_TorchOnHeightDifferentFromPierceHeight", 0)
			local FeedCutSettingMode = mc.mcProfileGetString(inst, INISection,"Plasma_FeedCutSettingMode", "Production")
			local VoltageCutSettingMode = mc.mcProfileGetString(inst, INISection,"Plasma_VoltageCutSettingMode", "Production")
			local CutSettings = AC.CutSettingModes[MachineType]
			UI["checkBoxTorchHeight"] = wx.wxCheckBox(UI.MyFrame1, wx.wxID_ANY, "Torch On Height Different From Pierce Height", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
			if torchOnHeightDifference == 1 then
				UI["checkBoxTorchHeight"]:SetValue(true)
			else
				UI["checkBoxTorchHeight"]:SetValue(false)
			end
			UI.gbSizer1:Add( UI["checkBoxTorchHeight"], wx.wxGBPosition( index+1, 0), wx.wxGBSpan( 1, 3 ), wx.wxALL + wx.wxALIGN_LEFT, 5 )
			index = index + 1
			
			-- New Setting
			local SettingName = "Feed"
			
			UI["bSizer1" .. SettingName] = wx.wxBoxSizer( wx.wxHORIZONTAL )
			
			UI["m_choice" .. SettingName] = wx.wxChoice( UI.MyFrame1, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, CutSettings[SettingName], 0 )
			for pos, mode in pairs(CutSettings[SettingName]) do
				if FeedCutSettingMode == mode then
					print(pos)
					UI["m_choice" .. SettingName]:SetSelection(pos-1)
					break
				end
			end
			UI["bSizer1" .. SettingName]:Add( UI["m_choice" .. SettingName], 0, wx.wxALL, 5 )
			
			UI["m_staticText" .. SettingName] = wx.wxStaticText(  UI.MyFrame1, wx.wxID_ANY, SettingName .. " Cut Setting" , wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
			UI["m_staticText" .. SettingName]:Wrap( -1 )
			UI["bSizer1" .. SettingName]:Add(UI["m_staticText" .. SettingName], 0, wx.wxALL + wx.wxALIGN_CENTER_VERTICAL, 5 )
			
			UI.gbSizer1:Add(UI["bSizer1" .. SettingName], wx.wxGBPosition( index+1, 0), wx.wxGBSpan( 1, 2 ), wx.wxALIGN_LEFT, 5 )
			index = index + 1
			
			-- New Setting
			SettingName = "Voltage"
			
			UI["bSizer1" .. SettingName] = wx.wxBoxSizer( wx.wxHORIZONTAL )
			
			UI["m_choice" .. SettingName] = wx.wxChoice( UI.MyFrame1, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, CutSettings[SettingName], 0 )
			for pos, mode in pairs(CutSettings[SettingName]) do
				if VoltageCutSettingMode == mode then
					print(pos)
					UI["m_choice" .. SettingName]:SetSelection(pos-1)
					break
				end
			end
			UI["bSizer1" .. SettingName]:Add( UI["m_choice" .. SettingName], 0, wx.wxALL, 5 )
			
			UI["m_staticText" .. SettingName] = wx.wxStaticText(  UI.MyFrame1, wx.wxID_ANY, SettingName .. " Cut Setting" , wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
			UI["m_staticText" .. SettingName]:Wrap( -1 )
			UI["bSizer1" .. SettingName]:Add( UI["m_staticText" .. SettingName], 0, wx.wxALL+ wx.wxALIGN_CENTER_VERTICAL, 5 )
			
			UI.gbSizer1:Add(UI["bSizer1" .. SettingName], wx.wxGBPosition( index+1, 0), wx.wxGBSpan( 1, 2 ),  wx.wxALIGN_LEFT, 5 )
			index = index + 1
		elseif MachineType == AC.Oxy then
			local torchOnHeightDifference = mc.mcProfileGetInt(inst, INISection,"Oxy_TorchOnHeightDifferentFromPierceHeight", 0)
			local PreheatCutSettingMode = mc.mcProfileGetString(inst, INISection,"Oxy_PreheatPierceSettingMode", "Low")
			local PierceSettings = AC.PierceSettingModes[MachineType]
			UI["checkBoxTorchHeight"] = wx.wxCheckBox(UI.MyFrame1, wx.wxID_ANY, "Torch On Height Different From Pierce Height", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
			if torchOnHeightDifference == 1 then
				UI["checkBoxTorchHeight"]:SetValue(true)
			else
				UI["checkBoxTorchHeight"]:SetValue(false)
			end
			UI.gbSizer1:Add( UI["checkBoxTorchHeight"], wx.wxGBPosition( index+1, 0), wx.wxGBSpan( 1, 3 ), wx.wxALL + wx.wxALIGN_LEFT, 5 )
			index = index + 1
			
			-- New Setting
			local SettingName = "Preheat"
			
			UI["bSizer1" .. SettingName] = wx.wxBoxSizer( wx.wxHORIZONTAL )
			
			UI["m_choice" .. SettingName] = wx.wxChoice( UI.MyFrame1, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, PierceSettings[SettingName], 0 )
			for pos, mode in pairs(PierceSettings[SettingName]) do
				if PreheatCutSettingMode == mode then
					UI["m_choice" .. SettingName]:SetSelection(pos-1)
					break
				end
			end
			UI["bSizer1" .. SettingName]:Add( UI["m_choice" .. SettingName], 0, wx.wxALL, 5 )
			
			UI["m_staticText" .. SettingName] = wx.wxStaticText(  UI.MyFrame1, wx.wxID_ANY, SettingName .. " Pierce Setting" , wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
			UI["m_staticText" .. SettingName]:Wrap( -1 )
			UI["bSizer1" .. SettingName]:Add(UI["m_staticText" .. SettingName], 0, wx.wxALL + wx.wxALIGN_CENTER_VERTICAL, 5 )
			
			UI.gbSizer1:Add(UI["bSizer1" .. SettingName], wx.wxGBPosition( index+1, 0), wx.wxGBSpan( 1, 2 ), wx.wxALIGN_LEFT, 5 )
			index = index + 1
			
		elseif MachineType == AC.Propane then
			
		end
		
		UI.m_button4 = wx.wxButton( UI.MyFrame1, wx.wxID_ANY, "Save", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
		UI.gbSizer1:Add( UI.m_button4, wx.wxGBPosition( index+1, 0), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxALIGN_LEFT, 5 )
		
		UI.m_button4:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
			--implements Add another spindle drowdown
			AC.SetParkSettings(ParkSettings, MachineType)
			AC:SetSettings(Settings, UI)
			mc.mcProfileFlush(inst)
			event:Skip()
		end )
		
		UI.gSizer1:Add(UI.gbSizer1, 1,0, 5 )
		
		UI.MyFrame1:SetSizer( UI.gSizer1 )
		UI.MyFrame1:Layout()
		UI.gSizer1:Fit( UI.MyFrame1 )
		UI.MyFrame1:Centre( wx.wxBOTH )
		 --Connect Events
		UI.MyFrame1:Connect( wx.wxEVT_CLOSE_WINDOW, function(event)
			AC.SetParkSettings(ParkSettings, MachineType)
			AC:SetSettings(Settings, UI)
			mc.mcProfileFlush(inst)
			AC.MachineType = nil
			UI.MyFrame1:Destroy()
			UI = nil
			event:Skip()
		end )  
		UI.MyFrame1:Show(true)
		wx.wxGetApp():MainLoop()
	end
	
	return AC
