-- Dalton Delorme V1 - 7/26/2023
if (mc.mcInEditor() == 1) then
	require("SetupPaths")
end
local CD = {}
function CD.AddWizardIconToWindow(window)
	local iconLoc = mc.mcCntlGetMachDir(mc.mcGetInstance()) .. "/WizardIcon.png"
	if wx.wxFileExists(iconLoc) then
		local icon = wx.wxIcon(iconLoc, wx.wxBITMAP_TYPE_PNG, 32, 32)
		window:SetIcon(icon)
	end
end
function CD.GridDialog(Name, bTblWizardHasClosed, Columns, Table)
	local AL = wx.wxArrayString()
	--for name, tbl in pairs(Table) do
	--	AL:Add(name)
	--end
	--AL:Sort(false)
	local rowValues = {}
	function SetupInputGrid()
		-- Set Variable Configuration
		local ReadOnlyAttr
		for num, tbl in pairs(Columns) do
			if type(num) ~= "number" or tbl == nil or tbl.Name == nil then
				return -1
			end
			UI.grid:SetColLabelValue(num-1, tbl.Name)
			if tbl.bIsReadOnly == true then
				if ReadOnlyAttr == nil then
					ReadOnlyAttr = wx.wxGridCellAttr()
					ReadOnlyAttr:SetReadOnly()
				end
				UI.grid:SetColAttr(num-1, ReadOnlyAttr)
			end
		end
		-- Set Default Configuration
		UI.grid:SetScrollRate(0, 8)
		UI.grid:SetMargins(0, 0)
		UI.grid:SetRowLabelAlignment(wx.wxALIGN_CENTER, wx.wxALIGN_CENTER);
		UI.grid:SetDefaultCellAlignment(wx.wxALIGN_CENTER, wx.wxALIGN_CENTER);
		UI.grid:AutoSizeColumns(true)
	end

	UI = {}
	UI.MyFrame1 = wx.wxFrame (wx.NULL, wx.wxID_ANY, Name, wx.wxDefaultPosition, wx.wxSize( 675,600 ), wx.wxDEFAULT_FRAME_STYLE - wx.wxRESIZE_BORDER + wx.wxTAB_TRAVERSAL + wx.wxSTAY_ON_TOP )
	UI.MyFrame1:SetBackgroundColour( wx.wxColour( 255, 255, 255 ) )
	UI.MyFrame1:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	
	UI.gSizer1 =  wx.wxBoxSizer( wx.wxVERTICAL )

	UI.gbSizer2 = wx.wxGridBagSizer( 0, 0 )
	UI.gbSizer2:SetFlexibleDirection( wx.wxBOTH )
	UI.gbSizer2:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )

	UI.grid = wx.wxGrid(UI.MyFrame1, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxSize( ((#Columns) * 100) + 17,504 ), wx.wxVSCROLL )

	UI.grid:EnableScrolling(false, true)
	UI.grid:SetDefaultColSize(100);
	UI.grid:SetDefaultRowSize(24);
	UI.grid:SetColLabelSize(24);
	UI.grid:SetRowLabelSize(1);
	UI.grid:SetLabelBackgroundColour(wx.wxColour(255,255,255))
	UI.grid:CreateGrid(0, #Columns, 0);
	SetupInputGrid()

	UI.gbSizer2:Add( UI.grid, wx.wxGBPosition( 0, 0 ), wx.wxGBSpan( 21, 3 ),  wx.wxALL +  wx.wxEXPAND, 5 )

	UI.gSizer1:Add( UI.gbSizer2, 1, wx.wxEXPAND, 5 )

	UI.MyFrame1:SetSizer( UI.gSizer1 )
	UI.MyFrame1:Layout()
	UI.gSizer1:Fit( UI.MyFrame1 )
	UI.MyFrame1:Centre( wx.wxBOTH )
		
	--Connect Events
	UI.MyFrame1:Connect( wx.wxEVT_CLOSE_WINDOW, function(event)
		-- Run function every time UI updates
		bTblWizardHasClosed[1] = true
		--UI.timer:Stop()
		if UI.grid ~= nil then
			UI.grid:Destroy()
		end
		if UI.MyFrame1 ~= nil then
			UI.MyFrame1:Destroy()
		end
		event:Skip()
	end )
	if UI.grid ~= nil then
		local tbl
		for col=1, #Table, 1 do
			tbl = Table[col]
			if type(tbl) == "table" then
				for row=1, #tbl, 1 do
					if col == 1 then
						UI.grid:AppendRows(1, true)
					end
					UI.grid:SetCellValue(row-1, col-1, tostring(tbl[row]))
				end
			end
		end
	end
	CD.AddWizardIconToWindow(UI.MyFrame1)
	UI.MyFrame1:Show(true)
	wx.wxGetApp():MainLoop()
end
function CD.ProgressBar(Name, bNoPulse)
	
	GAUGE = {}
	
	if Name == nil then
		Name = "Progress"
	end
	
	GAUGE.MyFrame1 = wx.wxDialog(wx.NULL, wx.wxID_ANY, Name, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxCAPTION+wx.wxSTAY_ON_TOP)
	GAUGE.MyFrame1:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )

	GAUGE.bSizer1 = wx.wxBoxSizer( wx.wxVERTICAL )

	GAUGE.m_gauge1 = wx.wxGauge( GAUGE.MyFrame1, wx.wxID_ANY, 100, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxGA_HORIZONTAL )
	GAUGE.bSizer1:Add( GAUGE.m_gauge1, 0, wx.wxALL, 5 )
	
	GAUGE.MyFrame1:SetSizer( GAUGE.bSizer1 )
	GAUGE.MyFrame1:Layout()
	GAUGE.bSizer1:Fit( GAUGE.MyFrame1 )
	
	if bNoPulse ~= true then
		PulseSW = wx.wxStopWatch()
		PulseSW:Start()
		local PulseTime = 2000
		function PulseGauge(Gauge)
			local Range = Gauge:GetRange()
			local TimeDifference = math.fmod(PulseSW:Time(), PulseTime) / PulseTime
			Gauge:SetValue(Range*TimeDifference)
			Gauge:Update()
		end
	end
	GAUGE.timer = wx.wxTimer(GAUGE.MyFrame1)
	--Connect Events
	GAUGE.MyFrame1:Connect(wx.wxEVT_TIMER, function(event)
		PulseGauge(GAUGE.m_gauge1)
		event:Skip()
	end)
	function KillFunc()
		if GAUGE.timer ~= nil then
			GAUGE.timer:Stop()
		end
		if GAUGE.MyFrame1 ~= nil then
			GAUGE.MyFrame1:Destroy()
			GAUGE.MyFrame1 = nil
		end
		GAUGE = nil
	end
	GAUGE.timer:Start(50, wx.wxTIMER_CONTINUOUS)
	GAUGE.MyFrame1:Centre( wx.wxBOTH )
	GAUGE.MyFrame1:Show()
	return KillFunc
end
return CD