-----------------------------------------------------------------------------
-- Name:        mcRegister (Formally: Master Module)
-- Author:      T Lamontagne
-- Modified by: B Price 12/16/19 Moved mcRegAddDel and doRegTable to master module from THC module
-- Modified by: D Delorme 3/16/23
-- Created:     03/11/2015 
-- Copyright:   (c) 2015 Newfangled Solutions. All rights reserved.
-- License:    
-----------------------------------------------------------------------------
local mcReg = {}
 
function mcReg.mcRegAddDel(inst, mode, device, path, desc, intialVal, persistent) --"mode = ADD" or "DEL", 
	local hReg
	local rc
	local cmdstring = mode .. "|" .. path
	local device = tostring(device)
	local desc = tostring(desc)
	local val = tostring(intialVal) 
	local persist = "0"
	if (type(persistent) == "boolean") then
		if (persistent ~= false) then 
			persist = "1"
		end
	elseif (type(persistent) == "number") then
		if (persistent ~= 0) then 
			persist = "1"
		end
	end
	
	--Check to see if the device is available 
	local hCmdReg 
	hCmdReg, rc = mc.mcRegGetHandle(inst, device .. "/command")
	if (rc ~= mc.MERROR_NOERROR) then --The device is not available.
		return "The command register for the instance registers is not available. Device = " .. device, mc.MERROR_NOT_IMPLEMENTED
	end
	
	--Check to see if the register exist
	hReg, rc = mc.mcRegGetHandle(inst, device .. "/" .. path)
	if (rc == mc.MERROR_NOERROR) and (mode == "ADD") then --Reg already exist so don't create it
		return "The register already exist.", mc.MERROR_NOERROR
	elseif (rc == mc.MERROR_REG_NOT_FOUND) and (mode == "DEL") then --Reg does not exist so don't try to delete it
		return "The register does not exist.", mc.MERROR_NOERROR
	elseif (rc ~= mc.MERROR_NOERROR) and (mode == "ADD") then --Reg doesn't exist so add the rest of the parameters and create it.
		if (rc == mc.MERROR_REG_NOT_FOUND) then
			cmdstring = cmdstring .. "|" .. desc .. "|" .. val  .. "|" .. persist
		else
			response = "Unexpected error"
			return response, rc
		end
	else
		--mc.mcCntlSetLastError(inst, device .. "/" .. path .. " Register does exist so delete it")
	end
	
	response, rc = mc.mcRegSendCommand(hCmdReg, cmdstring)
	return response, rc
end

-- Split up Add and delete to make calling slightly simpler
function mcReg.Add(inst, device, path, desc, intialVal, persistent)
	return mcReg.mcRegAddDel(inst, "ADD", device, path, desc, intialVal, persistent)
end
function mcReg.Delete(inst, device, path, desc, intialVal, persistent)
	return mcReg.mcRegAddDel(inst, "DEL", device, path, desc, intialVal, persistent)
end

function mcReg.doRegTable(inst, mode, t, device, group)
	local inst = inst & 0xFF
	local rc = mc.MERROR_NOERROR
	for v = 1, #t do
		local path = group .. t[v][1]
		local desc = t[v][2]
		local intialVal = t[v][3]
		local persistent = t[v][4]
		response, rc = mcReg.mcRegAddDel(inst, mode, device, path, desc, intialVal, persistent) --"ADD" or "DEL",
		if ((rc ~= mc.MERROR_NOERROR) and (rc ~= mc.MERROR_REG_NOT_FOUND)) then
			break
		end
	end
	return rc
end

function mcReg.GetRegister(regname, num)
	local hreg = mc.mcRegGetHandle(mc.mcGetInstance(), string.format("iRegs0/%s", regname))
	local val = mc.mcRegGetValueString(hreg)
	if (num == 1) then
		val = tonumber(val)
	end
	return val
end

function mcReg.SetRegister(regname, val, num)
	local inst = mc.mcGetInstance()
	local hreg = mc.mcRegGetHandle(inst, string.format("iRegs0/%s", regname))
	if (num == 1) then
		mc.mcRegSetValue(hreg, tonumber(val))
	else
		mc.mcRegSetValueString(hreg, val)
	end
end

function mcReg.SaveRegister(ini, name)
	local inst = mc.mcGetInstance()
    local hreg = mc.mcRegGetHandle(inst, string.format("iRegs0/%s", name))
    local val = mc.mcRegGetValueString(hreg)
    mc.mcProfileWriteString(0, tostring(ini), name, val)
end

function mcReg.LoadRegister(ini, name)
	local inst = mc.mcGetInstance()
	local val = mc.mcProfileGetString(inst , tostring(ini), name, "0.000")
	local hreg = mc.mcRegGetHandle(inst, string.format("iRegs0/%s", name))
	mc.mcRegSetValueString(hreg, val)
end

function mcReg.SaveRegisters()
	--Auto tool setter registers
	mcReg.SaveRegister("AutoTool", "TS_XPos")
	mcReg.SaveRegister("AutoTool", "TS_YPos")
	mcReg.SaveRegister("AutoTool", "TS_TouchPos")
	mcReg.SaveRegister("AutoTool", "TS_ProbeH")
	mcReg.SaveRegister("AutoTool", "TS_DefaultL")
	mcReg.SaveRegister("AutoTool", "TS_Retract")
	mcReg.SaveRegister("AutoTool", "TS_GCode")
end

function mcReg.LoadRegisters()
	--Auto tool setter registers
	mcReg.LoadRegister("AutoTool", "TS_XPos")
	mcReg.LoadRegister("AutoTool", "TS_YPos")
	mcReg.LoadRegister("AutoTool", "TS_TouchPos")
	mcReg.LoadRegister("AutoTool", "TS_ProbeH")
	mcReg.LoadRegister("AutoTool", "TS_DefaultL")
	mcReg.LoadRegister("AutoTool", "TS_Retract")
	mcReg.LoadRegister("AutoTool", "TS_GCode")
end

return mcReg





