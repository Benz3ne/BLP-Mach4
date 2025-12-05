--Abstracted SET/GET functions
if mcPR == nil then
	rc, mcPR = pcall(require, "mcPRequire") -- Table with protected require function that takes the following arguments
	--(string Name, bool? Reload, string? PackageName)
	-- name is the module name, 
	--reload is a bool of whether to unload the package and 
	--PackageName is the name of the modules variable if it's different from the module name
	if rc == false then
		wx.wxMessageBox("PRequire Execution Aborted: " .. tostring(mcPR))
		return
	end
end
mcLI = mcPR.prequire("mcLinearInterpolation", false, "mcLI")

mcAB = mcPR.prequire("mcAbstraction", false, "mcAB")

LSR = {}
LSR.Functions = {}
local CutStartSettingsDRORegisters = 
{ --["DROName"] = "Abstracted Register Name"
	["amtr(LaserPower)"] = "PowerLevel",
	["amtr(Pressurebar)"] = "inPressure0",
	["droEcat(2)"] = "TargetFocus",
	["droCutHeight"] = "HeightUnitsCommanded",
	["droNozzleDiameter"] = "NozzleDiameter",
	["droCurrentHeight"] = "HeightUnitsActual",
	["droCurrentX(7)"] = "HeightVoltageActual",
	["PlateThicknessInput"] = "PlateThickness"
}
LSR.GasTypeKeys = {
	[1] = "Air",
	[2] = "O2",
	[3] = "N2"
	}
LSR.InitScr = function(LSR)
	--LSR.Funcs.WriteOnStartUp()
	
	mcAB:PopulateCutStartSettings(LSR, CutStartSettingsDRORegisters)
	local GasTypes = ""
	for i, name in pairs(LSR.GasTypeKeys) do
		GasTypes = GasTypes .. name .. "|"
	end
	-- Set the Registers for dropdowns
	local matType = scr.GetProperty("lst(MaterialType)", "Reg. Selected")
	if matType ~=  tostring(LSR.MaterialSelection.Path) then
		scr.SetProperty("lst(MaterialType)", "Reg. Selected", tostring(LSR.MaterialSelection.Path))
	end
	local gasType = scr.GetProperty("lst(gastype)", "Strings")
	if gasType ~=  GasTypes then
		scr.SetProperty("lst(gastype)", "Strings", GasTypes)
	end
	local gasTypeReg = scr.GetProperty("lst(gastype)", "Reg. Value")
	if gasType ~= LSR.GasSelection.Path then
		scr.SetProperty("lst(gastype)", "Reg. Value", tostring(LSR.GasSelection.Path))
	end
	return LSR
end
function LSR.Functions.Engage()
	local hReg = mc.mcRegGetHandle(mc.mcGetInstance(), "KsMotion0/command")
	local response, rc = mc.mcRegSendCommand(hReg, "ENGAGE")
end
function LSR.Functions.IgnoreTipTouch(val)
	local hReg = mc.mcRegGetHandle(mc.mcGetInstance(), "KsMotion0/command")
	local response, rc = mc.mcRegSendCommand(hReg, "SET TIPTOUCHDETECTION="..tostring(val))
end
function LSR.Functions.CalibrateAsync()
	local hReg = mc.mcRegGetHandle(mc.mcGetInstance(), "KsMotion0/command")
	local response, rc = mc.mcRegSendCommand(hReg, "Calibrate Async")
end
function LSR.Functions.Disengage()
	local hReg = mc.mcRegGetHandle(mc.mcGetInstance(), "KsMotion0/command")
	local response, rc = mc.mcRegSendCommand(hReg, "DISENGAGE")
end
local inst = mc.mcGetInstance()

--[[
-- Simple example of adding a register to the abstraction layer
mcAB:AddToAbstractionLayer(
	"NozzleDiameter", -- Table Name
	"register", -- Type of Register. Can either be "register" or "command"
	"iRegs0/LSR/NozzleDiameter", -- Path or Handle of the register
	{ -- Table that will be used to initialize the register. (Dosen't work for command registers so nil can be passed for them)
		["Description"] = "Optimal Nozzele Diameter",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number" -- Type of the value
)  
-- Complex Example of Adding a register to abstraction layer
AddToAbstractionLayer("LaserPower",--Item Name
    "register", --Type of register to be set "register" or "command"
    "ireg/LCM/Laser/Power", --Register path or handle
	{
		["Description"] = "Used in M3, Optimal position to run THC at.",
		["IntialValue"] = .1000,
		["Persist"] = 1
	},
    "number", --Register type "number" or "string"
    function(val)-- Function to run for Getting data. this can be used to scale and shift the data 
      return val + 20
    end,
    function(val)-- Function to run for Setting data. this can be used to scale and shift the data 
      return val - 20
    end,
    function(val)--Max Val check 
      if (val > 120)then
        val = 120
      end
      return val
    end,
    function(val)--Min Val check 
      if (val < 0)then
        val = 0
      end
      return val
    end
  )
  --]]
  
local ECAThdl = mc.mcRegGetHandle(mc.mcGetInstance(), "KsMotion0/command")

--[[****************************
*********Command Registers**********
]]--****************************

mcAB:AddToAbstractionLayer(
	"ZaxisIndex", -- Table Name
	"command",
    ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "ZaxisIndex",
		["DefValue"] = "3"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"ZAxisHelperIndex", -- Table Name
	"command",
    ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "ZAXISHELPERINDEX",
		["DefValue"] = "-1"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"EMAFilter", -- Table Name
	"command",
    ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "EMAFILTER",
		["DefValue"] = "0"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"KP", -- Table Name
	"command",
    ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "KP",
		["DefValue"] = "60"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"KI", -- Table Name
	"command",
	ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "KI",
		["DefValue"] = "0"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"KD", -- Table Name
	"command",
	ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "KD",
		["DefValue"] = "15"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"MaxCorrectUp", -- Table Name
	"command",
	ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "MAXCORRECTUP",
		["DefValue"] = "2"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"MaxCorrectDown", -- Table Name
	"command",
	ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "MAXCORRECTDOWN",
		["DefValue"] = "-1"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"Deadband", -- Table Name
	"command",
	ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "DEADBAND",
		["DefValue"] = ".005"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"THCECATINDEX", -- Table Name
	"command",
	ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "THCECATINDEX",
		["DefValue"] = "0"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"HeightUnitsCommanded", -- Table Name
	"command",
	ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "HeightUnitsCommanded",
		["DefValue"] = ".21"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"FocusPosition", -- Table Name
	"command",
	ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "FOCUSPOSITION",
		["DefValue"] = "0"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"MaxHeightSlope", -- Table Name
	"command",
	ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "MAXHEIGHTSLOPE",
		["DefValue"] = "25"
		
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"THCReadingDelay", -- Table Name
	"command",
	ECAThdl, -- Path or Handle
	{
		["Section"] = "Laser",
		["Type"] = "string",
		["Key"] = "THCREADINGDELAY",
		["DefValue"] = ".02"
		
	},
	"number"
)

--[[****************************
*************Registers**************
]]--****************************
-- For each machine configuration these values will vary. It is heavily advised that you find the values for you're own machine. 
-- The method to get your machines pressure values can be found in the auto gas white paper
local Presssure = {
	-- Key=TargetPsi
	-- [Key][1]=VoltageOut
	-- [Key][2]=VoltageIn
	[8] = {3.0000,6.4154},
	[17.0] = {10.8000,11.9075},
	[26.0] = {18.6000,17.3544},
	[35.0] = {26.4000,22.4939},
	[43.0] = {34.2000,27.1678},
	[51.0] = {42.0000,31.7604},
	[58.0] = {49.8000,36.2671},
	[65.0] = {57.6000,40.5478},
	[73.0] = {65.4000,44.8827},
	[80.0] = {73.2000,49.2086},
	[87.0] = {81.0000,53.3401},
	[94.0] = {88.8000,57.3631},
	[99.0] = {96.6000,60.7171},
	[100.0] = {104.4000,61.7477}
}
-- Key values to easily convert voltage out to psi
local PressureOut = {
	[3.0000] = {8},
	[42.0000] = {51.0},
	[104.4000] = {100.0}
}
-- This is where to send the voltage to the plc
mcAB:AddToAbstractionLayer(
	"AirPressure0", -- Table Name
	"register",
	"modbus0/AirPressure0", -- Path or Handle
	{
		["Description"] = "Air Pressure Sending",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number",
	nil,
	function (val) -- Set
		val = val * 14.5038 -- psi to bar
		local voltage = 1 -- The position in the table to pull the VoltageIn values from
		local below, above = LI.GetClosestNumberForSetting(val, Presssure, voltage)
		local Volt
		if below ~= nil and above ~= nil then
			-- Interpolate to find target values
			Volt = LI.LinearInterpolation(val, above, below, Presssure[above][voltage], Presssure[below][voltage])
		else
			mc.mcCntlSetLastError(mc.mcGetInstance(), "Missing values above or below for " .. "inPressure. At target of " .. val)
			Volt = 0
		end
		return Volt
	end
)
-- This is the return voltage from the plc
mcAB:AddToAbstractionLayer(
	"inPressure0", -- Table Name
	"register",
	"modbus0/inPressure0", -- Path or Handle
	{
		["Description"] = "Air Pressure Reading",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number",
	function (val) -- Get
		local voltage = 1 -- The position in the table to pull the VoltageIn values from
		local below, above = LI.GetClosestNumberForSetting(val, PressureOut, voltage)
		local psi
		if below ~= nil and above ~= nil then
			psi = LI.LinearInterpolation(val, above, below, PressureOut[above][voltage], PressureOut[below][voltage])
		else
			mc.mcCntlSetLastError(mc.mcGetInstance(), "Missing values above or below for " .. "inPressure. At target of " .. val)
			psi = -1
		end
		return psi
	end
)

mcAB:AddToAbstractionLayer(
	"Pressure", -- Table Name
	"register",
	"iRegs0/LSR/Pressure", -- Path or Handle
	{
		["Description"] = "Target Air Pressure",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"PlateThickness", -- Table Name
	"register",
	"iRegs0/LSR/PlateThickness", -- Path or Handle
	{
		["Description"] = "Currect Plate Thickness",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"NozzleDiameter", -- Table Name
	"register",
	"iRegs0/LSR/NozzleDiameter", -- Path or Handle
	{
		["Description"] = "Optimal Nozzele Diameter",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"LaserWattage", -- Table Name
	"register",
	"iRegs0/LSR/LaserWattage", -- Path or Handle
	{
		["Description"] = "Wattage of laser machine",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"Feed", -- Table Name
	"register",
	"iRegs0/LSR/Feed", -- Path or Handle
	{
		["Description"] = "Optimal Feed Rate",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number",
	nil,
	function(val)
		mc.mcCntlGcodeExecute(inst, "F".. tostring(val))
		return val
	end
)
mcAB:AddToAbstractionLayer(
	"NozzleType", -- Table Name
	"register",
	"iRegs0/LSR/NozzleType", -- Path or Handle
	{
		["Description"] = "Optimal NozzleType Rate",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number",
	nil,
	function(val)
		return "Nozzle Type: " .. val
	end
)
mcAB:AddToAbstractionLayer(
	"FocusOffset", -- Table Name
	"register",
	"iRegs0/LSR/FocusOffset", -- Path or Handle
	{
		["Description"] = "The value sent to focus when for focus to be at the tip",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"TargetFocus", -- Table Name
	"register",
	"iRegs0/LSR/TargetFocus", -- Path or Handle
	{
		["Description"] = "Optimal Focus Location",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number",
	nil,
	function(val)
		local offset = LSR.FocusOffset.Get()
		local sendVal = offset + val
		LSR.FocusPosition.Set(sendVal)
		return val
	end
)
mcAB:AddToAbstractionLayer(
	"UNITS", -- Table Name
	"register",
	"iRegs0/LSR/UNITS", -- Path or Handle
	{
		["Description"] = "The default units",
		["IntialValue"] = function()
			local units = mc.mcCntlGetUnitsCurrent(mc.mcGetInstance())
			return math.tointeger(units)
		end,
		["Persist"] = 0
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"PierceStart", -- Table Name
	"register",
	"iRegs0/LSR/Pierce/Start", -- Path or Handle
	{
		["Description"] = "The height pierce will start from",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"PierceEnd", -- Table Name
	"register",
	"iRegs0/LSR/Pierce/End", -- Path or Handle
	{
		["Description"] = "The height pierce will end at",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"PierceAuxGas", -- Table Name
	"register",
	"iRegs0/LSR/Pierce/AuxGas", -- Path or Handle
	{
		["Description"] = "Optimal auxiliary Gas pressure",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"PierceDwell", -- Table Name
	"register",
	"iRegs0/LSR/Pierce/Dwell", -- Path or Handle
	{
		["Description"] = "Pierece dwell time after fire at pierce start height",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"PierceFocusStart", -- Table Name
	"register",
	"iRegs0/LSR/Pierce/FocusStart", -- Path or Handle
	{
		["Description"] = "Focus Location at start of pierce",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"PierceFocusEnd", -- Table Name
	"register",
	"iRegs0/LSR/Pierce/FocusEnd", -- Path or Handle
	{
		["Description"] = "Focus Location at end of pierce",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"PierceIndex", -- Table Name
	"register",
	"iRegs0/LSR/Pierce/Index", -- Path or Handle
	{
		["Description"] = "Pierce Index",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)
mcAB:AddToAbstractionLayer(
	"MaterialSelection", -- Table Name
	"register",
	"iRegs0/LSR/MaterialSelection", -- Path or Handle
	{
		["Description"] = "The user selected material",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)
mcAB:AddToAbstractionLayer(
	"GasSelection", -- Table Name
	"register",
	"iRegs0/LSR/GasSelection", -- Path or Handle
	{
		["Description"] = "The currently selected gas",
		["IntialValue"] = "",
		["Persist"] = 1
	},
	"string"
)
mcAB:AddToAbstractionLayer(
	{"THCState","State"}, -- Table Name
	"register",
	"KsMotion0/thc/State", -- Path or Handle
	{
		["Description"] = "What the reported state of thc is",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)
mcAB:AddToAbstractionLayer(
	"HeightVoltageActual", -- Table Name
	"register",
	"KsMotion0/thc/HeightVoltageActual", -- Path or Handle
	{
		["Description"] = "Actual height voltage reported from kingstar",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)
mcAB:AddToAbstractionLayer(
	"HeightUnitsActual", -- Table Name
	"register",
	"KsMotion0/thc/HeightUnitsActual", -- Path or Handle
	{
		["Description"] = "Actual height units reported from kingstar",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)
mcAB:AddToAbstractionLayer(
	"PierceEnabled", -- Table Name
	"register",
	"iRegs0/LSR/PierceEnabled", -- Path or Handle
	{
		["Description"] = "Register showing whether pierce is enabled or disabled",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

--[[****************************
***************Raycus***************
]]--****************************

mcAB:AddToAbstractionLayer(
	"PowerLevel", -- Table Name
	"register",
	"Laser/PowerLevel", -- Path or Handle
	{
		["Description"] = "Commanded laser powerlevel",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"DutyCycle", -- Table Name
	"register",
	"Laser/DutyCycle", -- Path or Handle
	{
		["Description"] = "Commanded duty cycle",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"Frequency", -- Table Name
	"register",
	"Laser/Frequency", -- Path or Handle
	{
		["Description"] = "Commanded laser frequency",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddToAbstractionLayer(
	"Mode", -- Table Name
	"register",
	"Laser/Mode", -- Path or Handle
	{
		["Description"] = "Commanded laser mode",
		["IntialValue"] = 0,
		["Persist"] = 1
	},
	"number"
)

mcAB:AddAbstractionsToTable(LSR)
return LSR