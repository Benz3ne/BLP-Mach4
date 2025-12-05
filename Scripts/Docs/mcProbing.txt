-----------------------------------------------------------------------------
-- Name:        Auto Tool Setting Module
-- Author:      T Lamontagne
-- Modified by: T Lamontagne/Rob Gaudette 9/17/2015
---------------------------------------------------------------------
-- Modified by: B Price 10/17/2016 Replaced #var #s with constants
--Updated function Probing.SetFixOffset
--2134	mc.SV_FEEDRATE
--4001	mc.SV_MOD_GROUP_1
--4002	mc.SV_MOD_GROUP_2
--4003	mc.SV_MOD_GROUP_3
--4102	mc.SV_ORIGIN_OFFSET_Z
--5061	mc.SV_PROBE_POS_X
--5062	mc.SV_PROBE_POS_Y
--5063	mc.SV_PROBE_POS_Z 
--5071	mc.SV_PROBE_MACH_POS_X
--5072	mc.SV_PROBE_MACH_POS_Y
--5073	mc.SV_PROBE_MACH_POS_Z
-------------------------------------------------------------------
-- Modified by: B Price 7/19/2017 Defined "inst" in several functions
-------------------------------------------------------------------
-- Created:     03/11/2015
-- Copyright:   (c) 2015 Newfangled Solutions. All rights reserved.
-- License:    
-----------------------------------------------------------------------------
local Probing = {}
local mm = {}
function mm.ReturnCode(rc)
	
end
function Probing.LengthCal(zpos)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (zpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: Z surface position no input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local ZSurf = tonumber(zpos)
	
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
    
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.Z_AXIS)
	
	local rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Move to position -------------
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G00 G80 G40 G49 G90")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%.0f", OffsetNum))
	mm.ReturnCode(rc)
	
	------------- Find Surface -------------
	local ProbeTo = ZSurf - OverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	------------- Retract -------------
	local ProbedPosAbs = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Z)
	local RetractPoint = ProbedPosAbs + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Measure Probe --------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	local ProbedMeasAbs1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Z)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	local ProbedMeasAbs2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Z)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	local ProbedMeasAbs3 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Z)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 Z%.4f", CurPosition))
	mm.ReturnCode(rc)
	
	------------- Get touch position and set offset -------------
	local ProbedMeasAbs = (ProbedMeasAbs1 + ProbedMeasAbs2 + ProbedMeasAbs3) / 3
	
    local ProbeLength = scr.GetProperty("droHeight", "Value")


    local NewOffset = ProbeLength + (ZSurf - ProbedMeasAbs)
	mc.mcToolSetData(inst, mc.MTOOL_MILL_HEIGHT, OffsetNum, NewOffset)
	mc.mcCntlSetLastError(inst, string.format("Auto tool setting complete, Offset = %.4f", NewOffset))
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.XYOffsetCal(xpos, ypos, diam, zpos, safez)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (xpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: X position not input")
		do return end
	end
	if (ypos == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: Y position not input")
		do return end
	end
	if (zpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: Z position not input")
		do return end
	end
	if (diam == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: Gage diameter not input")
		do return end
	end
	if (safez == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: Safe Z position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XPos = tonumber(xpos)
	local YPos = tonumber(ypos)
	local Diam = tonumber(diam)
	local ZMeasPos = tonumber(zpos)
	local ZSafePos = tonumber(safez)
	
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Calc Measurement End Points -------------
	local MeasDist = (Diam / 2) + OverShoot
	local XPlus = XPos + MeasDist
	local XMinus = XPos - MeasDist
	local YPlus = YPos + MeasDist
	local YMinus = YPos - MeasDist
	
	------------- Move to position ------------------------
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%.0f", OffsetNum))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 Z%.4f", ZSafePos))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 X%.4f Y%.4f", XPos, YPos))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZMeasPos, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	-------------- Measure XPlus --------------------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XPlus, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end

	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 1
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	local Meas1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end

	local Meas2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 3
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	local Meas3 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 X%.4f", XPos))
	mm.ReturnCode(rc)
	local XPlusMeas = (Meas1 + Meas2 + Meas3) / 3
	
	-------------- Measure XMinus --------------------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMinus, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 1
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	Meas1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	Meas2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 3
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	Meas3 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 X%.4f", XPos))
	mm.ReturnCode(rc)
	local XMinusMeas = (Meas1 + Meas2 + Meas3) / 3
	
	-------------- Measure YMinus --------------------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMinus, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 1
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	Meas1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	Meas2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 3
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	Meas3 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 Y%.4f", YPos))
	mm.ReturnCode(rc)
	local YMinusMeas = (Meas1 + Meas2 + Meas3) / 3
	
	-------------- Measure YPlus --------------------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YPlus, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 1
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	Meas1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	Meas2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 3
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	
	Meas3 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 Y%.4f", YPos))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 Z%.4f", ZSafePos))
	mm.ReturnCode(rc)
	local YPlusMeas = (Meas1 + Meas2 + Meas3) / 3
	
	-------------- Calculate X and Y offsets --------------
	local XCenter = (XPlusMeas + XMinusMeas) / 2
	local YCenter = (YPlusMeas + YMinusMeas) / 2
	local XOffset = XCenter - XPos
	local YOffset = YCenter - YPos
	mc.mcProfileWriteDouble(inst, "ProbingSettings", "XOffset", XOffset)
	mc.mcProfileWriteDouble(inst, "ProbingSettings", "YOffset", YOffset)
	mc.mcCntlSetLastError(inst, string.format("Probe X and Y offset set: X = %.4f, Y = %.4f", XOffset, YOffset))
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.RadiusCal(xpos, ypos, diam, zpos, safez)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (xpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: X position not input")
		do return end
	end
	if (ypos == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: Y position not input")
		do return end
	end
	if (zpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: Z position not input")
		do return end
	end
	if (diam == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: Gage diameter not input")
		do return end
	end
	if (safez == nil) then
		mc.mcCntlSetLastError(inst, "Probe Cal: Safe Z position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XPos = tonumber(xpos)
	local YPos = tonumber(ypos)
	local Diam = tonumber(diam)
	local ZMeasPos = tonumber(zpos)
	local ZSafePos = tonumber(safez)
	
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.Z_AXIS)
	
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Calc Measurement End Points -------------
	local MeasDist = (Diam / 2) + OverShoot
	local XPlus = XPos + MeasDist
	local XMinus = XPos - MeasDist
	local YPlus = YPos + MeasDist
	local YMinus = YPos - MeasDist
	
	------------- Move to position ------------------------
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%.0f", OffsetNum))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 Z%.4f", ZSafePos))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 X%.4f Y%.4f", XPos, YPos))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZMeasPos, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	-------------- Measure XPlus --------------------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XPlus, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 1
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local Meas1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local Meas2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 3
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local Meas3 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 X%.4f", XPos))
	mm.ReturnCode(rc)
	local XPlusMeas = ((Meas1 + Meas2 + Meas3) / 3) + XOffset
	
	-------------- Measure XMinus --------------------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMinus, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 1
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	Meas1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	Meas2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 3
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	Meas3 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 X%.4f", XPos))
	mm.ReturnCode(rc)
	local XMinusMeas = ((Meas1 + Meas2 + Meas3) / 3) + XOffset
	
	-------------- Measure YMinus --------------------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMinus, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 1
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	Meas1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	Meas2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 3
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMinus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	Meas3 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 Y%.4f", YPos))
	mm.ReturnCode(rc)
	local YMinusMeas = ((Meas1 + Meas2 + Meas3) / 3) + YOffset
	
	-------------- Measure YPlus --------------------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YPlus, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 1
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	Meas1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	Meas2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure 3
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YPlus, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	Meas3 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 Y%.4f", YPos))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G0 Z%.4f", ZSafePos))
	mm.ReturnCode(rc)
	local YPlusMeas = ((Meas1 + Meas2 + Meas3) / 3) + YOffset
	
	-------------- Calculate Radius --------------
	local GageRad = Diam / 2
	local Rad1 = GageRad - math.abs(XPlusMeas - XPos)
	local Rad2 = GageRad - math.abs(XPos - XMinusMeas)
	local Rad3 = GageRad - math.abs(YPlusMeas - YPos)
	local Rad4 = GageRad - math.abs(YPos - YMinusMeas)
	local Radius = (Rad1 + Rad2 + Rad3 + Rad4) / 4
	
	mc.mcProfileWriteDouble(inst, "ProbingSettings", "Radius", Radius)
	mc.mcCntlSetLastError(inst, string.format("Probe radius set: R = %.4f", Radius))
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.SingleSurfX(xpos, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (xpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XPos = tonumber(xpos)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Check direction -------------
	if (CurPosition > XPos) then
		BackOff = -BackOff
		OverShoot = -OverShoot
		ProbeRad = -ProbeRad
	end
	
	------------- Probe Surface -------------
	local ProbeTo = XPos + OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPointMACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate and set offset/vars -------------
	MeasPointABS = MeasPointABS + ProbeRad + XOffset
	MeasPointMACH = MeasPointMACH + ProbeRad + XOffset
	local PosError = MeasPointABS - XPos
	
	mc.mcCntlSetPoundVar(inst, 131, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 141, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 135, PosError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(MeasPointMACH, nil, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.SingleSurfY(ypos, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (ypos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local YPos = tonumber(ypos)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Check direction -------------
	if (CurPosition > YPos) then
		BackOff = -BackOff
		OverShoot = -OverShoot
		ProbeRad = -ProbeRad
	end
	
	------------- Probe Surface -------------
	local ProbeTo = YPos + OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPointMACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate and set offset/vars -------------
	MeasPointABS = MeasPointABS + ProbeRad + YOffset
	MeasPointMACH = MeasPointMACH + ProbeRad + YOffset
	local PosError = MeasPointABS - YPos
	
	mc.mcCntlSetPoundVar(inst, 132, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 142, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 136, PosError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(nil, MeasPointMACH, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.SingleSurfZ(zpos, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (zpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Z position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local ZPos = tonumber(zpos)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.Z_AXIS)
	
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probe Surface -------------
	local ProbeTo = ZPos - OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%.0f", OffsetNum))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Z)
	local RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Z)
	local MeasPointMACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Z)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate and set offset/vars -------------
	local PosError = MeasPointABS - ZPos
	
	mc.mcCntlSetPoundVar(inst, 133, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 143, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 137, PosError)
	
	if (SetWork == 1) then
		local HeightOffset = mc.mcToolGetData(inst, mc.MTOOL_MILL_HEIGHT, OffsetNum)
		local HeightOffsetW = mc.mcToolGetData(inst, mc.MTOOL_MILL_HEIGHT_W, OffsetNum)
		local NewWOVal = MeasPointMACH - HeightOffset - HeightOffsetW
		Probing.SetFixOffset(nil, nil, NewWOVal)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.InternalCorner(xpos, ypos, xinc, yinc, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (xpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X position not input")
		do return end
	end
	if (ypos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y position not input")
		do return end
	end
	if (yinc ~= nil) and (xinc == nil) then
		xinc = yinc
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XPos = tonumber(xpos)
	local YPos = tonumber(ypos)
	local XInc = tonumber(xinc)
	local YInc = tonumber(yinc)
	if (yinc == nil) then
		XInc = 0
		YInc = 0
	end
	
	local SetWork = tonumber(work)
	
	local MeasPointX1ABS
	local MeasPointX1MACH
	local MeasPointX2ABS
	local MeasPointX2MACH
	
	local MeasPointY1ABS
	local MeasPointY1MACH
	local MeasPointY2ABS
	local MeasPointY2MACH
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Check direction -------------
	if (CurXPosition > XPos) then
		XBackOff = -BackOff
		XOverShoot = -OverShoot
		XProbeRad = -ProbeRad
	else
		XBackOff = BackOff
		XOverShoot = OverShoot
		XProbeRad = ProbeRad
	end
	
	if (CurYPosition > YPos) then
		YBackOff = -BackOff
		YOverShoot = -OverShoot
		YProbeRad = -ProbeRad
	else
		YBackOff = BackOff
		YOverShoot = OverShoot
		YProbeRad = ProbeRad
	end
	
	------------- Probe X Surface -------------
	local ProbeTo = XPos + XOverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - XBackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointX1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X) + XProbeRad + XOffset
	MeasPointX1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X) + XProbeRad + XOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	if (YInc ~= 0) then
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CurYPosition + YInc, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
		local RetractPoint = ProbePoint - XBackOff
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
		mm.ReturnCode(rc)
		--Measure
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		MeasPointX2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X) + XProbeRad + XOffset
		MeasPointX2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X) + XProbeRad + XOffset
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
		mm.ReturnCode(rc)
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurYPosition, FastFeed))
		mm.ReturnCode(rc)
	end
	
		------------- Probe Y Surface -------------
	local ProbeTo = YPos + YOverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - YBackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointY1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + YProbeRad + YOffset
	MeasPointY1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + YProbeRad + YOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G01 Y%.4f F%.1f", CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	if (XInc ~= 0) then
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, CurXPosition + XInc, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
		local RetractPoint = ProbePoint - YBackOff
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
		mm.ReturnCode(rc)
		--Measure
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		MeasPointY2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + YProbeRad + YOffset
		MeasPointY2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + YProbeRad + YOffset
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G01 Y%.4f F%.1f", CurYPosition, FastFeed))
		mm.ReturnCode(rc)
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G01 X%.4f F%.1f", CurXPosition, FastFeed))
		mm.ReturnCode(rc)
	end
	
	------------- Calculate and set offset/vars -------------
	
	if (YInc == 0) then
		--Assume 90 degree corner
		local PosErrorX = MeasPointX1ABS - XPos
		local PosErrorY = MeasPointY1ABS - YPos
		
		mc.mcCntlSetPoundVar(inst, 131, MeasPointX1MACH)
		mc.mcCntlSetPoundVar(inst, 141, MeasPointX1ABS)
		mc.mcCntlSetPoundVar(inst, 132, MeasPointY1MACH)
		mc.mcCntlSetPoundVar(inst, 142, MeasPointY1ABS)
		mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
		mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
	else
		--Calculate angles and intercept from multi point measurement
		local XMachShift = MeasPointX1MACH - MeasPointX1ABS
		local YMachShift = MeasPointY1MACH - MeasPointY1ABS
		
        local V1X = MeasPointX1ABS
        local V1i = MeasPointX2ABS - MeasPointX1ABS
        local V1Y = CurYPosition
        local V1j = YInc

        local V2X = CurXPosition
        local V2i = XInc
        local V2Y = MeasPointY1ABS
        local V2j = MeasPointY2ABS - MeasPointY1ABS
        
        local XCornerABS, YCornerABS
        XCornerABS, YCornerABS = Probing.VectorInt2D(V1X, V1i, V1Y, V1j, V2X, V2i, V2Y, V2j)
        local XCornerMACH = XCornerABS + XMachShift
        local YCornerMACH = YCornerABS + YMachShift
        local PosErrorX = XCornerABS - XPos
        local PosErrorY = YCornerABS - YPos
        
        local CornerAngle = Probing.VectorAngle2D(V1i, V1j, V2i, V2j)
        local XAngle = Probing.VectorAngle2D(V1i, V1j, 0, V1j)
		if (V1j < 0) and (V1i < 0) and (XAngle > 0) then
			XAngle = -XAngle
		elseif (V1j > 0) and (V1i > 0) and (XAngle > 0) then
			XAngle = -XAngle
		end
        local YAngle = Probing.VectorAngle2D(V2i, V2j, V2i, 0)
		if (V2i < 0) and (V2j > 0) and (YAngle > 0) then
			YAngle = -YAngle
		elseif (V2i > 0) and (V2j < 0) and (YAngle > 0) then
			YAngle = -YAngle
		end
        local AngleError = CornerAngle - 90

		mc.mcCntlSetPoundVar(inst, 145, XAngle)
		mc.mcCntlSetPoundVar(inst, 146, YAngle)

		mc.mcCntlSetPoundVar(inst, 144, CornerAngle)
		mc.mcCntlSetPoundVar(inst, 138, AngleError)

		mc.mcCntlSetPoundVar(inst, 141, XCornerABS)
		mc.mcCntlSetPoundVar(inst, 131, XCornerMACH)
		mc.mcCntlSetPoundVar(inst, 142, YCornerABS)
		mc.mcCntlSetPoundVar(inst, 132, YCornerMACH)
		mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
		mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
	end
	
	if (SetWork == 1) then
		local XVal = mc.mcCntlGetPoundVar(inst, 131)
		local YVal = mc.mcCntlGetPoundVar(inst, 132)
		Probing.SetFixOffset(XVal, YVal, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.ExternalCorner(xpos, ypos, xinc, yinc, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (xpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X position not input")
		do return end
	end
	if (ypos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y position not input")
		do return end
	end
	if (xinc ~= nil) and (yinc == nil) then
		yinc = xinc
	elseif (yinc ~= nil) and (xinc == nil) then
		xinc = yinc
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XPos = tonumber(xpos)
	local YPos = tonumber(ypos)
	local XInc = tonumber(xinc)
	local YInc = tonumber(yinc)
	if (xinc == nil) then
		XInc = 0
		YInc = 0
	end
	
	local SetWork = tonumber(work)
	
	local MeasPointX1ABS
	local MeasPointX1MACH
	local MeasPointX2ABS
	local MeasPointX2MACH
	
	local MeasPointY1ABS
	local MeasPointY1MACH
	local MeasPointY2ABS
	local MeasPointY2MACH
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Check direction -------------
	if (CurXPosition > XPos) then
		XBackOff = -BackOff
		XOverShoot = -OverShoot
		XProbeRad = -ProbeRad
	else
		XBackOff = BackOff
		XOverShoot = OverShoot
		XProbeRad = ProbeRad
	end
	
	if (CurYPosition > YPos) then
		YBackOff = -BackOff
		YOverShoot = -OverShoot
		YProbeRad = -ProbeRad
	else
		YBackOff = BackOff
		YOverShoot = OverShoot
		YProbeRad = ProbeRad
	end
	
	------------- Calculate measurment start positions -------------
	local XMeasurePos = CurXPosition + (2 * (XPos - CurXPosition))
	local YMeasurePos = CurYPosition + (2 * (YPos - CurYPosition))
	
	------------- Probe X Surface -------------
	local ProbeTo = XPos + XOverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMeasurePos, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - XBackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointX1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X) + XProbeRad + XOffset
	MeasPointX1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X) + XProbeRad + XOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	if (YInc ~= 0) then
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMeasurePos + YInc, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
		local RetractPoint = ProbePoint - XBackOff
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
		mm.ReturnCode(rc)
		--Measure
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		MeasPointX2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X) + XProbeRad + XOffset
		MeasPointX2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X) + XProbeRad + XOffset
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
		------------- Probe Y Surface -------------
	local ProbeTo = YPos + YOverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMeasurePos, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - YBackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointY1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + YProbeRad + YOffset
	MeasPointY1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + YProbeRad + YOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	if (XInc ~= 0) then
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMeasurePos + XInc, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
		local RetractPoint = ProbePoint - YBackOff
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
		mm.ReturnCode(rc)
		--Measure
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		MeasPointY2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + YProbeRad + YOffset
		MeasPointY2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + YProbeRad + YOffset
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurYPosition, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Calculate and set offset/vars -------------
	
	if (YInc == 0) then
		--Assume 90 degree corner
		local PosErrorX = MeasPointX1ABS - XPos
		local PosErrorY = MeasPointY1ABS - YPos
		
		mc.mcCntlSetPoundVar(inst, 131, MeasPointX1MACH)
		mc.mcCntlSetPoundVar(inst, 141, MeasPointX1ABS)
		mc.mcCntlSetPoundVar(inst, 132, MeasPointY1MACH)
		mc.mcCntlSetPoundVar(inst, 142, MeasPointY1ABS)
		mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
		mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
		
	else
		--Calculate angles and intercept from multi point measurement
		local XMachShift = MeasPointX1MACH - MeasPointX1ABS
		local YMachShift = MeasPointY1MACH - MeasPointY1ABS
		
        local V1X = MeasPointX1ABS
        local V1i = MeasPointX2ABS - MeasPointX1ABS
        local V1Y = CurYPosition
        local V1j = YInc

        local V2X = CurXPosition
        local V2i = XInc
        local V2Y = MeasPointY1ABS
        local V2j = MeasPointY2ABS - MeasPointY1ABS
        
        local XCornerABS, YCornerABS
        XCornerABS, YCornerABS = Probing.VectorInt2D(V1X, V1i, V1Y, V1j, V2X, V2i, V2Y, V2j)
        local XCornerMACH = XCornerABS + XMachShift
        local YCornerMACH = YCornerABS + YMachShift
        local PosErrorX = XCornerABS - XPos
        local PosErrorY = YCornerABS - YPos
        
        local CornerAngle = Probing.VectorAngle2D(V1i, V1j, V2i, V2j)
        local XAngle = Probing.VectorAngle2D(V1i, V1j, 0, V1j)
		if (V1j < 0) and (V1i < 0) and (XAngle > 0) then
			XAngle = -XAngle
		elseif (V1j > 0) and (V1i > 0) and (XAngle > 0) then
			XAngle = -XAngle
		end
        local YAngle = Probing.VectorAngle2D(V2i, V2j, V2i, 0)
		if (V2i < 0) and (V2j > 0) and (YAngle > 0) then
			YAngle = -YAngle
		elseif (V2i > 0) and (V2j < 0) and (YAngle > 0) then
			YAngle = -YAngle
		end
        local AngleError = CornerAngle - 90

		mc.mcCntlSetPoundVar(inst, 145, XAngle)
		mc.mcCntlSetPoundVar(inst, 146, YAngle)

		mc.mcCntlSetPoundVar(inst, 144, CornerAngle)
		mc.mcCntlSetPoundVar(inst, 138, AngleError)

		mc.mcCntlSetPoundVar(inst, 141, XCornerABS)
		mc.mcCntlSetPoundVar(inst, 131, XCornerMACH)
		mc.mcCntlSetPoundVar(inst, 142, YCornerABS)
		mc.mcCntlSetPoundVar(inst, 132, YCornerMACH)
		mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
		mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
	end
	
	if (SetWork == 1) then
		local XVal = mc.mcCntlGetPoundVar(inst, 131)
		local YVal = mc.mcCntlGetPoundVar(inst, 132)
		Probing.SetFixOffset(XVal, YVal, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.InsideCenteringX(width, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (width == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X width not input")
		do return end
	end
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XWidth = tonumber(width)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probe Surface 1 -------------
	local ProbeTo = CurPosition + (XWidth / 2) + OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Probe Surface 2 -------------
	local ProbeTo = CurPosition - (XWidth / 2) - OverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate and set offset/vars -------------
	MeasPoint1ABS = MeasPoint1ABS + ProbeRad + XOffset
	MeasPoint1MACH = MeasPoint1MACH + ProbeRad + XOffset
	MeasPoint2ABS = MeasPoint2ABS - ProbeRad + XOffset
	MeasPoint2MACH = MeasPoint2MACH - ProbeRad + XOffset
	local MeasPointABS = (MeasPoint1ABS + MeasPoint2ABS) / 2
	local MeasPointMACH = (MeasPoint1MACH + MeasPoint2MACH) / 2
	local PosError = MeasPointABS - CurPosition
	local Width = MeasPoint1ABS - MeasPoint2ABS
	local WidthError = Width - XWidth
	
	mc.mcCntlSetPoundVar(inst, 131, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 141, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, Width)
	mc.mcCntlSetPoundVar(inst, 135, PosError)
	mc.mcCntlSetPoundVar(inst, 138, WidthError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(MeasPointMACH, nil, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.OutsideCenteringX(width, approach, zpos, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (width == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X width not input")
		do return end
	end
	if (approach == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Approach not input")
		do return end
	end
	if (zpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Z measure position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XWidth = tonumber(width)
	local Approach = tonumber(approach)
	local ZLevel = tonumber(zpos)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurZPosition = mc.mcAxisGetPos(inst, mc.Z_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probe Surface 1 -------------
	local ProbeTo = CurPosition + (XWidth / 2) - OverShoot
	local RetractPoint
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%.0f", OffsetNum))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo + Approach + OverShoot, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	if ((ProbeTo + Approach + OverShoot) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	if ((ProbeTo + Approach) < ProbeTo) then
		MeasPoint1ABS = MeasPoint1ABS + ProbeRad + XOffset
		MeasPoint1MACH = MeasPoint1MACH + ProbeRad + XOffset
	else
		MeasPoint1ABS = MeasPoint1ABS - ProbeRad + XOffset
		MeasPoint1MACH = MeasPoint1MACH - ProbeRad + XOffset
	end
	
	------------- Probe Surface 2 -------------
	local ProbeTo = CurPosition - (XWidth / 2) + OverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	if ((ProbeTo - Approach) > ProbeTo) then
		RetractPoint = ProbePoint + BackOff
	else
		RetractPoint = ProbePoint - BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	if ((ProbeTo - Approach) > ProbeTo) then
		MeasPoint2ABS = MeasPoint2ABS - ProbeRad + XOffset
		MeasPoint2MACH = MeasPoint2MACH - ProbeRad + XOffset
	else
		MeasPoint2ABS = MeasPoint2ABS + ProbeRad + XOffset
		MeasPoint2MACH = MeasPoint2MACH + ProbeRad + XOffset
	end
	
	------------- Calculate and set offset/vars -------------
	local MeasPointABS = (MeasPoint1ABS + MeasPoint2ABS) / 2
	local MeasPointMACH = (MeasPoint1MACH + MeasPoint2MACH) / 2
	local PosError = MeasPointABS - CurPosition
	local Width = MeasPoint1ABS - MeasPoint2ABS
	local WidthError = Width - XWidth
	
	mc.mcCntlSetPoundVar(inst, 131, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 141, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, Width)
	mc.mcCntlSetPoundVar(inst, 135, PosError)
	mc.mcCntlSetPoundVar(inst, 138, WidthError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(MeasPointMACH, nil, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.InsideCenteringY(width, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (width == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y width not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local YWidth = tonumber(width)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probe Surface 1 -------------
	local ProbeTo = CurPosition + (YWidth / 2) + OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Probe Surface 2 -------------
	local ProbeTo = CurPosition - (YWidth / 2) - OverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate and set offset/vars -------------
	MeasPoint1ABS = MeasPoint1ABS + ProbeRad + YOffset
	MeasPoint1MACH = MeasPoint1MACH + ProbeRad + YOffset
	MeasPoint2ABS = MeasPoint2ABS - ProbeRad + YOffset
	MeasPoint2MACH = MeasPoint2MACH - ProbeRad + YOffset
	local MeasPointABS = (MeasPoint1ABS + MeasPoint2ABS) / 2
	local MeasPointMACH = (MeasPoint1MACH + MeasPoint2MACH) / 2
	local PosError = MeasPointABS - CurPosition
	local Width = MeasPoint1ABS - MeasPoint2ABS
	local WidthError = Width - YWidth
	
	mc.mcCntlSetPoundVar(inst, 132, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 142, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, Width)
	mc.mcCntlSetPoundVar(inst, 136, PosError)
	mc.mcCntlSetPoundVar(inst, 138, WidthError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(nil, MeasPointMACH, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.OutsideCenteringY(width, approach, zpos, work) 
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (width == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y width not input")
		do return end
	end
	if (approach == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Approach not input")
		do return end
	end
	if (zpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Z measure position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local YWidth = tonumber(width)
	local Approach = tonumber(approach)
	local ZLevel = tonumber(zpos)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	local CurZPosition = mc.mcAxisGetPos(inst, mc.Z_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probe Surface 1 -------------
	local ProbeTo = CurPosition + (YWidth / 2) - OverShoot
	local RetractPoint
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%.0f", OffsetNum))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo + Approach + OverShoot, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo + Approach) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	if ((ProbeTo + Approach) < ProbeTo) then
		MeasPoint1ABS = MeasPoint1ABS + ProbeRad + YOffset
		MeasPoint1MACH = MeasPoint1MACH + ProbeRad + YOffset
	else
		MeasPoint1ABS = MeasPoint1ABS - ProbeRad + YOffset
		MeasPoint1MACH = MeasPoint1MACH - ProbeRad + YOffset
	end
	
	------------- Probe Surface 2 -------------
	local ProbeTo = CurPosition - (YWidth / 2) + OverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo - Approach) > ProbeTo) then
		RetractPoint = ProbePoint + BackOff
	else
		RetractPoint = ProbePoint - BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	if ((ProbeTo - Approach) > ProbeTo) then
		MeasPoint2ABS = MeasPoint2ABS - ProbeRad + YOffset
		MeasPoint2MACH = MeasPoint2MACH - ProbeRad + YOffset
	else
		MeasPoint2ABS = MeasPoint2ABS + ProbeRad + YOffset
		MeasPoint2MACH = MeasPoint2MACH + ProbeRad + YOffset
	end
	
	------------- Calculate and set offset/vars -------------
	local MeasPointABS = (MeasPoint1ABS + MeasPoint2ABS) / 2
	local MeasPointMACH = (MeasPoint1MACH + MeasPoint2MACH) / 2
	local PosError = MeasPointABS - CurPosition
	local Width = MeasPoint1ABS - MeasPoint2ABS
	local WidthError = Width - YWidth
	
	mc.mcCntlSetPoundVar(inst, 132, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 142, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, Width)
	mc.mcCntlSetPoundVar(inst, 136, PosError)
	mc.mcCntlSetPoundVar(inst, 138, WidthError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(nil, MeasPointMACH, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.Bore(diam, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (diam == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Bore diam not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local Diam = tonumber(diam)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probing positions -------------
	local ProbeToXp = CurXPosition + (Diam / 2) + OverShoot
	local ProbeToXm = CurXPosition - (Diam / 2) - OverShoot
	local ProbeToYp = CurYPosition + (Diam / 2) + OverShoot
	local ProbeToYm = CurYPosition - (Diam / 2) - OverShoot
	
	------------- Probing sequence -------------
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYp, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePointY1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYm, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePointY2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	ProbePointY1 = ProbePointY1 + ProbeRad + YOffset
	ProbePointY2 = ProbePointY2 - ProbeRad + YOffset
	local YCenter = (ProbePointY1 + ProbePointY2) / 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", YCenter, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Find X Center -------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeToXp, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeToXp, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointX1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPointX1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeToXm, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeToXm, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointX2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPointX2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	
	------------- Calculate X Center -------------
	MeasPointX1ABS = MeasPointX1ABS + ProbeRad + XOffset
	MeasPointX1MACH = MeasPointX1MACH + ProbeRad + XOffset
	MeasPointX2ABS = MeasPointX2ABS - ProbeRad + XOffset
	MeasPointX2MACH = MeasPointX2MACH - ProbeRad + XOffset
	local CenterPointXABS = (MeasPointX1ABS + MeasPointX2ABS) / 2
	local CenterPointXMACH = (MeasPointX1MACH + MeasPointX2MACH) / 2
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CenterPointXABS, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Find Y Center -------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYp, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYp, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointY1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPointY1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYm, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYm, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointY2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPointY2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	
	------------- Calculate Y Center -------------
	MeasPointY1ABS = MeasPointY1ABS + ProbeRad + YOffset
	MeasPointY1MACH = MeasPointY1MACH + ProbeRad + YOffset
	MeasPointY2ABS = MeasPointY2ABS - ProbeRad + YOffset
	MeasPointY2MACH = MeasPointY2MACH - ProbeRad + YOffset
	local CenterPointYABS = (MeasPointY1ABS + MeasPointY2ABS) / 2
	local CenterPointYMACH = (MeasPointY1MACH + MeasPointY2MACH) / 2
	
	mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CenterPointYABS, FastFeed))
	
	------------- Calculate and set offset/vars -------------
	local PosErrorX = CenterPointXABS - CurXPosition
	local PosErrorY = CenterPointYABS - CurYPosition
	local MeasDiam = ((MeasPointX1ABS - MeasPointX2ABS) + (MeasPointY1ABS - MeasPointY2ABS)) / 2
	local DiamError = MeasDiam - Diam
	
	mc.mcCntlSetPoundVar(inst, 131, CenterPointXMACH)
	mc.mcCntlSetPoundVar(inst, 132, CenterPointYMACH)
	mc.mcCntlSetPoundVar(inst, 141, CenterPointXABS)
	mc.mcCntlSetPoundVar(inst, 142, CenterPointYABS)
	mc.mcCntlSetPoundVar(inst, 144, MeasDiam)
	mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
	mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
	mc.mcCntlSetPoundVar(inst, 138, DiamError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(CenterPointXMACH, CenterPointYMACH, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.Boss(diam, approach, zpos, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (diam == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Boss diam not input")
		do return end
	end
	if (approach == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Approach not input")
		do return end
	end
	if (zpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Z measure position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local Diam = tonumber(diam)
	local Approach = tonumber(approach)
	local ZLevel = tonumber(zpos)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	local CurZPosition = mc.mcAxisGetPos(inst, mc.Z_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probing positions -------------
	local ProbeToXp = CurXPosition + (Diam / 2) - OverShoot
	local ProbeToXm = CurXPosition - (Diam / 2) + OverShoot
	local ProbeToYp = CurYPosition + (Diam / 2) - OverShoot
	local ProbeToYm = CurYPosition - (Diam / 2) + OverShoot
	
	------------- Probing sequence -------------
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%.0f", OffsetNum))
	mm.ReturnCode(rc)
	local ProbeTo = ProbeToYp
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointY1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo + Approach) < ProbeTo) then
		MeasPointY1ABS = MeasPointY1ABS + ProbeRad + YOffset
	else
		MeasPointY1ABS = MeasPointY1ABS - ProbeRad + YOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	local ProbeTo = ProbeToYm
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointY2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo - Approach) < ProbeTo) then
		MeasPointY2ABS = MeasPointY2ABS + ProbeRad + YOffset
	else
		MeasPointY2ABS = MeasPointY2ABS - ProbeRad + YOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	
	local YCenter = (MeasPointY1ABS + MeasPointY2ABS) / 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YCenter, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Find X Center -------------
	--Measure X plus
	ProbeTo = ProbeToXp
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	if ((ProbeTo + Approach) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointX1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPointX1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	if ((ProbeTo + Approach) < ProbeTo) then
		MeasPointX1ABS = MeasPointX1ABS + ProbeRad + XOffset
		MeasPointX1MACH = MeasPointX1MACH + ProbeRad + XOffset
	else
		MeasPointX1ABS = MeasPointX1ABS - ProbeRad + XOffset
		MeasPointX1MACH = MeasPointX1MACH - ProbeRad + XOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	--Measure X minus
	ProbeTo = ProbeToXm
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	if ((ProbeTo - Approach) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointX2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPointX2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	if ((ProbeTo - Approach) < ProbeTo) then
		MeasPointX2ABS = MeasPointX2ABS + ProbeRad + XOffset
		MeasPointX2MACH = MeasPointX2MACH + ProbeRad + XOffset
	else
		MeasPointX2ABS = MeasPointX2ABS - ProbeRad + XOffset
		MeasPointX2MACH = MeasPointX2MACH - ProbeRad + XOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate X Center -------------
	local CenterPointXABS = (MeasPointX1ABS + MeasPointX2ABS) / 2
	local CenterPointXMACH = (MeasPointX1MACH + MeasPointX2MACH) / 2
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, CenterPointXABS, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Find Y Center -------------
	--Measure Y plus
	ProbeTo = ProbeToYp
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo + Approach) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointY1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPointY1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	if ((ProbeTo + Approach) < ProbeTo) then
		MeasPointY1ABS = MeasPointY1ABS + ProbeRad + YOffset
		MeasPointY1MACH = MeasPointY1MACH + ProbeRad + YOffset
	else
		MeasPointY1ABS = MeasPointY1ABS - ProbeRad + YOffset
		MeasPointY1MACH = MeasPointY1MACH - ProbeRad + YOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	--Measure Y minus
	ProbeTo = ProbeToYm
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo - Approach) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointY2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPointY2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	if ((ProbeTo - Approach) < ProbeTo) then
		MeasPointY2ABS = MeasPointY2ABS + ProbeRad + YOffset
		MeasPointY2MACH = MeasPointY2MACH + ProbeRad + YOffset
	else
		MeasPointY2ABS = MeasPointY2ABS - ProbeRad + YOffset
		MeasPointY2MACH = MeasPointY2MACH - ProbeRad + YOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate Y Center -------------
	local CenterPointYABS = (MeasPointY1ABS + MeasPointY2ABS) / 2
	local CenterPointYMACH = (MeasPointY1MACH + MeasPointY2MACH) / 2
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CenterPointYABS, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Calculate and set offset/vars -------------
	local PosErrorX = CenterPointXABS - CurXPosition
	local PosErrorY = CenterPointYABS - CurYPosition
	local MeasDiam = ((MeasPointX1ABS - MeasPointX2ABS) + (MeasPointY1ABS - MeasPointY2ABS)) / 2
	local DiamError = MeasDiam - Diam
	
	mc.mcCntlSetPoundVar(inst, 131, CenterPointXMACH)
	mc.mcCntlSetPoundVar(inst, 132, CenterPointYMACH)
	mc.mcCntlSetPoundVar(inst, 141, CenterPointXABS)
	mc.mcCntlSetPoundVar(inst, 142, CenterPointYABS)
	mc.mcCntlSetPoundVar(inst, 144, MeasDiam)
	mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
	mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
	mc.mcCntlSetPoundVar(inst, 138, DiamError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(CenterPointXMACH, CenterPointYMACH, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.SingleAngleX(xpos, yinc, xcntr, ycntr, rotate)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (xpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X position not input")
		do return end
	end
	if (yinc == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y increment not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XPos = tonumber(xpos)
	local YInc = tonumber(yinc)
	
	if (xcntr == nil) then
		local XCntr = 0
	else
		local XCntr = tonumber(xcntr)
	end
	if (ycntr == nil) then
		local YCntr = 0
	else
		local YCntr = tonumber(ycntr)
	end
	
	local RotateCoord = tonumber(rotate)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPlane = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_2)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	if (CurPlane ~= 170) and (RotateCoord == 1) then
		mc.mcCntlSetLastError(inst, "Probe: Invalid plane selection for coordinate rotation")
		do return end
	end
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Check direction -------------
	if (CurXPosition > XPos) then
		BackOff = -BackOff
		OverShoot = -OverShoot
		ProbeRad = -ProbeRad
	end
	
	------------- Probe X Surface -------------
	local ProbeTo = XPos + OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X) + ProbeRad + XOffset
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X) + ProbeRad + XOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CurYPosition + YInc, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X) + ProbeRad + XOffset
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X) + ProbeRad + XOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Calculate and set offset/vars -------------
	
	--Calculate angles and intercept from multi point measurement
	local MachShift = MeasPoint1MACH - MeasPoint1ABS
	local V1X = MeasPoint1ABS
    local V1i = MeasPoint2ABS - MeasPoint1ABS
    local V1Y = CurYPosition
    local V1j = YInc
	
	local Angle = Probing.VectorAngle2D(V1i, V1j, 0, V1j)	
	if (V1j < 0) and (V1i < 0) and (Angle > 0) then
		Angle = -Angle
	elseif (V1j > 0) and (V1i > 0) and (Angle > 0) then
		Angle = -Angle
	end

	mc.mcCntlSetPoundVar(inst, 144, Angle)
	mc.mcCntlSetPoundVar(inst, 138, Angle)
	
	if (RotateCoord == 1) then
		mc.mcCntlGcodeExecuteWait(inst, string.format("G68 X%.4f Y%.4f R%.4f", XCntr, YCntr, Angle))
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.SingleAngleY(ypos, xinc, xcntr, ycntr, rotate)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (ypos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y position not input")
		do return end
	end
	if (xinc == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X increment not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local YPos = tonumber(ypos)
	local XInc = tonumber(xinc)
	
	if (xcntr == nil) then
		local XCntr = 0
	else
		local XCntr = tonumber(xcntr)
	end
	if (ycntr == nil) then
		local YCntr = 0
	else
		local YCntr = tonumber(ycntr)
	end
	
	local RotateCoord = tonumber(rotate)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPlane = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_2)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	if (CurPlane ~= 170) and (RotateCoord == 1) then
		mc.mcCntlSetLastError(inst, "Probe: Invalid plane selection for coordinate rotation")
		do return end
	end
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Check direction -------------
	if (CurYPosition > YPos) then
		BackOff = -BackOff
		OverShoot = -OverShoot
		ProbeRad = -ProbeRad
	end
	
	------------- Probe X Surface -------------
	local ProbeTo = YPos + OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + ProbeRad + YOffset
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + ProbeRad + YOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1Y%.4f F%.1f", CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, CurXPosition + XInc, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + ProbeRad + YOffset
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + ProbeRad + YOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f",  CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f",  CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	
	
	------------- Calculate and set offset/vars -------------
	
	--Calculate angles and intercept from multi point measurement
	local MachShift = MeasPoint1MACH - MeasPoint1ABS
	local V1X = CurXPosition
    local V1i = XInc
    local V1Y = MeasPoint1ABS
    local V1j = MeasPoint2ABS - MeasPoint1ABS
	
	local Angle = Probing.VectorAngle2D(V1i, V1j, V1i, 0)
	if (V1i < 0) and (V1j > 0) and (Angle > 0) then
		Angle = -Angle
	elseif (V1i > 0) and (V1j < 0) and (Angle > 0) then
		Angle = -Angle
	end

	mc.mcCntlSetPoundVar(inst, 144, Angle)
	mc.mcCntlSetPoundVar(inst, 138, Angle)
	
	if (RotateCoord == 1) then
		mc.mcCntlGcodeExecuteWait(inst, string.format("G68 X%.4f Y%.4f R%.4f", XCntr, YCntr, Angle))
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.CheckProbe(state, code)
	local inst = mc.mcGetInstance()
	local check = true
	local ProbeSigTable = {
		[31] = mc.ISIG_PROBE,
		[31.0] = mc.ISIG_PROBE,
		[31.1] = mc.ISIG_PROBE1,
		[31.2] = mc.ISIG_PROBE2,
		[31.3] = mc.ISIG_PROBE3}
	local ProbeSignal = ProbeSigTable[code]
	if (ProbeSignal == nil) then
		mc.mcCntlSetLastError(inst, "ERROR: Invalid probing G code")
		mc.mcCntlEStop(inst)
		do return end
	end
	------------- Check Probe -------------
	local hsig = mc.mcSignalGetHandle(inst, ProbeSignal)
	local ProbeState = mc.mcSignalGetState(hsig)
	local errmsg = "ERROR: No contact with probe"
	if (state == 1) then
		errmsg = "ERROR: Probe obstructed"
	end
	if (ProbeState == state) then
		mc.mcCntlSetLastError(inst, errmsg)
		mc.mcCntlEStop(inst)
		check = false
	end
	return check
end

function Probing.SetFixOffset(xval, yval, zval)
	local inst = mc.mcGetInstance()
    local FixOffset = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_14)
    local Pval = mc.mcCntlGetPoundVar(inst, mc.SV_BUFP)
    local FixNum, whole, frac

    if (FixOffset ~= 54.1) then --G54 through G59
        whole, frac = math.modf (FixOffset)
        FixNum = (whole - 53) 
        PoundVarX = ((mc.SV_FIXTURES_START - mc.SV_FIXTURES_INC) + (FixNum * mc.SV_FIXTURES_INC))
        CurrentFixture = string.format('G' .. tostring(FixOffset)) 
    else --G54.1 P1 through G54.1 P100
        FixNum = (Pval + 6)
        CurrentFixture = string.format('G54.1 P' .. tostring(Pval))
        if (Pval > 0) and (Pval < 51) then -- G54.1 P1 through G54.1 P50
            PoundVarX = ((mc.SV_FIXTURE_EXPAND - mc.SV_FIXTURES_INC) + (Pval * mc.SV_FIXTURES_INC))
        elseif (Pval > 50) and (Pval < 101) then -- G54.1 P51 through G54.1 P100
            PoundVarX = ((mc.SV_FIXTURE_EXPAND2 - mc.SV_FIXTURES_INC) + (Pval * mc.SV_FIXTURES_INC))	
        end
    end
    PoundVarY = PoundVarX + 1
    PoundVarZ = PoundVarX + 2
    if (xval ~= nil) then
        mc.mcCntlSetPoundVar(inst, PoundVarX, xval)
    end
    if (yval ~= nil) then
        mc.mcCntlSetPoundVar(inst, PoundVarY, yval)
    end
    if (zval ~= nil) then
        mc.mcCntlSetPoundVar(inst, PoundVarZ, zval)
    end
end

function Probing.NilVars(first, last)
	--Set poundvars to nil
	local inst = mc.mcGetInstance()
	local nilval = mc.mcCntlGetPoundVar(inst, 0)
	local counter = first
	while (counter <= last) do
		mc.mcCntlSetPoundVar(inst, counter, nilval)
		counter = counter + 1
	end
end

function Probing.VectorInt2D(V1X, V1i, V1Y, V1j, V2X, V2i, V2Y, V2j)
    local XInt, YInt
    if (V1i == 0) then
        XInt = V1X
        YInt = V2Y - (V2X * V2j)
    else
        local a = (V2Y * V1i) / V1j
        local b = (V1Y * V1i) / V1j
        local c = V2i - ((V2j * V1i) / V1j)
        local vconst = (a - b - V2X + V1X) / c
        XInt = V2X + (vconst * V2i)
        YInt = V2Y + (vconst * V2j)
    end
    return XInt, YInt
end

function Probing.VectorAngle2D(V1a, V1b, V2a, V2b)
    local V1abs = math.sqrt(V1a^2 + V1b^2)
    local V2abs = math.sqrt(V2a^2 + V2b^2)
    local num = (V1a * V2a) + (V1b * V2b)
    local den = V1abs * V2abs
    local angle = math.deg(math.acos(num/den))
    return angle
end

function Probing.SaveSettings()
	local inst = mc.mcGetInstance()
	local ProbeRad = scr.GetProperty("droCalProbeRad", "Value")
	mc.mcProfileWriteString(inst, "ProbingSettings", "Radius", tostring(ProbeRad))
	local XOffset = scr.GetProperty("droCalXOffset", "Value")
	mc.mcProfileWriteString(inst, "ProbingSettings", "XOffset", tostring(XOffset))
	local YOffset = scr.GetProperty("droCalYOffset", "Value")
	mc.mcProfileWriteString(inst, "ProbingSettings", "YOffset", tostring(YOffset))
	local OffsetNum = scr.GetProperty("droPrbOffNum", "Value")
	mc.mcProfileWriteString(inst , "ProbingSettings", "OffsetNum", tostring(OffsetNum))
	local SlowFeed = scr.GetProperty("droSlowFeed", "Value")
	mc.mcProfileWriteString(inst , "ProbingSettings", "SlowFeed", tostring(SlowFeed))
	local FastFeed = scr.GetProperty("droFastFeed", "Value")
	mc.mcProfileWriteString(inst , "ProbingSettings", "FastFeed", tostring(FastFeed))
	local BackOff = scr.GetProperty("droBackOff", "Value")
	mc.mcProfileWriteString(inst , "ProbingSettings", "BackOff", tostring(BackOff))
	local OverShoot = scr.GetProperty("droOverShoot", "Value")
	mc.mcProfileWriteString(inst , "ProbingSettings", "OverShoot", tostring(OverShoot))
	local InPosZone = scr.GetProperty("droPrbInPos", "Value")
	mc.mcProfileWriteString(inst , "ProbingSettings", "InPosZone", tostring(InPosZone))
	local ProbeCode = scr.GetProperty("droPrbGcode", "Value")
	mc.mcProfileWriteString(inst , "ProbingSettings", "GCode", tostring(ProbeCode))
end

function Probing.LoadSettings()
	local inst = mc.mcGetInstance()
	local ProbeRad = mc.mcProfileGetString(inst, "ProbingSettings", "Radius", "0")
	scr.SetProperty("droCalProbeRad", "Value", ProbeRad)
	local XOffset = mc.mcProfileGetString(inst, "ProbingSettings", "XOffset", "0")
	scr.SetProperty("droCalXOffset", "Value", XOffset)
	local YOffset = mc.mcProfileGetString(inst, "ProbingSettings", "YOffset", "0")
	scr.SetProperty("droCalYOffset", "Value", YOffset)
	local OffsetNum = mc.mcProfileGetString(inst , "ProbingSettings", "OffsetNum", "0")
	scr.SetProperty("droPrbOffNum", "Value", OffsetNum)
	local SlowFeed = mc.mcProfileGetString(inst , "ProbingSettings", "SlowFeed", "0")
	scr.SetProperty("droSlowFeed", "Value", SlowFeed)
	local FastFeed = mc.mcProfileGetString(inst , "ProbingSettings", "FastFeed", "0")
	scr.SetProperty("droFastFeed", "Value", FastFeed)
	local BackOff = mc.mcProfileGetString(inst , "ProbingSettings", "BackOff", "0")
	scr.SetProperty("droBackOff", "Value", BackOff)
	local OverShoot = mc.mcProfileGetString(inst , "ProbingSettings", "OverShoot", "0")
	scr.SetProperty("droOverShoot", "Value", OverShoot)
	local InPosZone = mc.mcProfileGetString(inst , "ProbingSettings", "InPosZone", "0")
	scr.SetProperty("droPrbInPos", "Value", InPosZone)
	local ProbeCode = mc.mcProfileGetString(inst , "ProbingSettings", "GCode", "0")
	scr.SetProperty("droPrbGcode", "Value", ProbeCode)
end

function Probing.SettingsHelp()
	local help = {}


	-- create ProbeSettingsHelp
	help.ProbeSettingsHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Probe Settings Help", wx.wxDefaultPosition, wx.wxSize( 500,694 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeSettingsHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeSettingsHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeSettingsHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "Offset number:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "The desired tool height offset number for the probe.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 300 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText3 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "G code:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText3:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText3, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText4 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "There are 4 possible G codes depending on the probe input being used:\nG31 - Probe\nG31.1 - Probe 1\nG31.2 - Probe 2\nG31.3 - Probe 3", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText4:Wrap( 300 )
	help.fgSizer1:Add( help.m_staticText4, 0, wx.wxALL, 5 )
	
	help.m_staticText5 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "Slow measure feedrate:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText5:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText5, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText6 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "Feedrate at which measurement moves will be executed.  Slower rates will produce more accurate measurements.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText6:Wrap( 300 )
	help.fgSizer1:Add( help.m_staticText6, 0, wx.wxALL, 5 )
	
	help.m_staticText7 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "Fast find feedrate:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText7:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText7, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText8 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "Feedrate for finding a surface before taking a measurement.  Higher rates here will reduce probe cycle time, but too fast could cause damage to the probe.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText8:Wrap( 300 )
	help.fgSizer1:Add( help.m_staticText8, 0, wx.wxALL, 5 )
	
	help.m_staticText9 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "Retract amount:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText9:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText9, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText10 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "After finding a surface at the fast find feedrate the probe will be retracted by this amount before perfoming a measurement move.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText10:Wrap( 300 )
	help.fgSizer1:Add( help.m_staticText10, 0, wx.wxALL, 5 )
	
	help.m_staticText11 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "Overshoot amount:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText11:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText11, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText12 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "Probe moves are programmed to overshoot the measurement surface by the specified amount.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText12:Wrap( 300 )
	help.fgSizer1:Add( help.m_staticText12, 0, wx.wxALL, 5 )
	
	help.m_staticText13 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "In position tolerance:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText13:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText13, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText14 = wx.wxStaticText( help.ProbeSettingsHelp, wx.wxID_ANY, "The measured point is compared to the programmed end point of the probe move.  If it is within this distance from the end point then no contact is assumed.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText14:Wrap( 300 )
	help.fgSizer1:Add( help.m_staticText14, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeSettingsHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeSettingsHelp:SetSizer( help.bSizer4 )
	help.ProbeSettingsHelp:Layout()
	
	help.ProbeSettingsHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeSettingsHelp:Destroy()
	end )
	
	help.ProbeSettingsHelp:Show()
end

function Probing.LengthCalHelp()
	local help = {}


	-- create ProbeLengthCalHelp
	help.ProbeLengthCalHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Probe Length Calibration Help", wx.wxDefaultPosition, wx.wxSize( 550,275 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeLengthCalHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeLengthCalHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeLengthCalHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeLengthCalHelp, wx.wxID_ANY, "The probe length calibration sequence will measure the probe length using the specified surface.  An approximate offset must be set for the probe prior to running this sequence.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 425 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeLengthCalHelp, wx.wxID_ANY, "Z position of calibration surface:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeLengthCalHelp, wx.wxID_ANY, "The absolute position, in the current work offset, of the surface to be used to calibrate the probe length.  The accuracy of this position will determine the accuracy of the calibration.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 300 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeLengthCalHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeLengthCalHelp:SetSizer( help.bSizer4 )
	help.ProbeLengthCalHelp:Layout()
	
	help.ProbeLengthCalHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeLengthCalHelp:Destroy()
	end )
	help.ProbeLengthCalHelp:Show()
end

function Probing.XYRadCalHelp()
	local help = {}
	
	-- create ProbeXYRadCalHelp
	help.ProbeXYRadCalHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Probe XY Offset and Radius Calibration Help", wx.wxDefaultPosition, wx.wxSize( 600,775 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeXYRadCalHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeXYRadCalHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeXYRadCalHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText18 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "XY Offset Calibration", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText18:Wrap( -1 )
	help.m_staticText18:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.bSizer4:Add( help.m_staticText18, 0, wx.wxALL, 5 )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "The probe XY offset calibration sequence will measure the inside of a known bore diameter, usually a ring gauge or precision bored hole.  The X and Y offset of the probe tip will be determined by comparing the measured center position to the actual specified center position.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 475 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.m_staticText20 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "Radius Calibration", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText20:Wrap( -1 )
	help.m_staticText20:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.bSizer4:Add( help.m_staticText20, 0, wx.wxALL, 5 )
	
	help.m_staticText21 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "The probe radius calibration sequence will measure the inside of a known bore diamter, usually a ring gauge or precision bored hole, to determine the radius of the probe tip.  The XY offset calibration should be run first for higher accuracy.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText21:Wrap( 475 )
	help.bSizer4:Add( help.m_staticText21, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "X position of gauge:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "The absolute X position, in the current work offset, of the center of the ring gauge or precision bored hole.  The accuracy of this position will determine the accuracy of the calibration.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText22 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "Y position of gauge:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText22:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText22, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText23 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "The absolute Y position, in the current work offset, of the center of the ring gauge or precision bored hole.  The accuracy of this position will determine the accuracy of the calibration.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText23:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText23, 0, wx.wxALL, 5 )
	
	help.m_staticText24 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "Z measurement position:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText24:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText24, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText25 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "The absolute Z position, in the current work offset, at which measurements should be taken.  This should be below the top surface of the ring gauge or bored hole.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText25:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText25, 0, wx.wxALL, 5 )
	
	help.m_staticText26 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "Safe Z position:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText26:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText26, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText27 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "The absolute Z position, in the current work offset, at which it is safe to rapid traverse.  This should be above the top surface of the ring gauge or bored hole.  The calibration sequence will move to this height before positioning to the specified X, Y coordinates of the center of the bore.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText27:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText27, 0, wx.wxALL, 5 )
	
	help.m_staticText28 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "Gauge diameter:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText28:Wrap( -1 )
	help.fgSizer1:Add( help.m_staticText28, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText29 = wx.wxStaticText( help.ProbeXYRadCalHelp, wx.wxID_ANY, "Diameter of the precision bore to be used for calibration.  The accuracy of this measurement will determine the accuracy of the XY offset and radius calibrations.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText29:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText29, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeXYRadCalHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeXYRadCalHelp:SetSizer( help.bSizer4 )
	help.ProbeXYRadCalHelp:Layout()
	
	help.ProbeXYRadCalHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeXYRadCalHelp:Destroy()
	end )
	help.ProbeXYRadCalHelp:Show()
end

function Probing.SingleSurfHelp()
	local help = {}

	-- create ProbeSingleSurfHelp
	help.ProbeSingleSurfHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Single Surface Probing Help", wx.wxDefaultPosition, wx.wxSize( 600,527 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeSingleSurfHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeSingleSurfHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeSingleSurfHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText18 = wx.wxStaticText( help.ProbeSingleSurfHelp, wx.wxID_ANY, "Set up and execution", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText18:Wrap( -1 )
	help.m_staticText18:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.bSizer4:Add( help.m_staticText18, 0, wx.wxALL, 5 )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeSingleSurfHelp, wx.wxID_ANY, "The single surface measure cycles measure a single surface in the X, Y or Z direction.  The probe should be positioned near the desired surface prior to running the cycle.  When the sequence starts the probe will move at the specified fast feedrate to find the surface, then retract and measure at the slow feedrate.  Measured results will be displayed and set in the appropriate # variables.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 475 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeSingleSurfHelp, wx.wxID_ANY, "X, Y or Z position:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.m_staticText1:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeSingleSurfHelp, wx.wxID_ANY, "The absolute position, in the current work offset, of the surface to be measured.  The probe will move only the specifed axis towards this position.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText22 = wx.wxStaticText( help.ProbeSingleSurfHelp, wx.wxID_ANY, "Measurement type:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText22:Wrap( -1 )
	help.m_staticText22:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText22, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText23 = wx.wxStaticText( help.ProbeSingleSurfHelp, wx.wxID_ANY, "The \"Measurement Type\" button toggles leds that specify if the work offset should be set or not.  When set to \"Measure Only\" the results will be set to the appropriate # variables but the work offset will not be set.  If \"Set Work Offset\" is selected then the current work offset will be set to the measured surface.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText23:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText23, 0, wx.wxALL, 5 )
	
	help.m_staticText24 = wx.wxStaticText( help.ProbeSingleSurfHelp, wx.wxID_ANY, "# Variables", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText24:Wrap( -1 )
	help.m_staticText24:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText24, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText25 = wx.wxStaticText( help.ProbeSingleSurfHelp, wx.wxID_ANY, "X, Y, Z machine position: #131 - 133\nX, Y, Z absolute position: #141 - 143\nX, Y, Z position error: #135 - 137", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText25:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText25, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeSingleSurfHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeSingleSurfHelp:SetSizer( help.bSizer4 )
	help.ProbeSingleSurfHelp:Layout()
	
	help.ProbeSingleSurfHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeSingleSurfHelp:Destroy()
	end )
	help.ProbeSingleSurfHelp:Show()
end

function Probing.InsideCornerHelp()
	local help = {}


	-- create ProbeInsideCornerHelp
	help.ProbeInsideCornerHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Inside Corner Probing Help", wx.wxDefaultPosition, wx.wxSize( 600,657 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeInsideCornerHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeInsideCornerHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeInsideCornerHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText18 = wx.wxStaticText( help.ProbeInsideCornerHelp, wx.wxID_ANY, "Set up and execution", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText18:Wrap( -1 )
	help.m_staticText18:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.bSizer4:Add( help.m_staticText18, 0, wx.wxALL, 5 )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeInsideCornerHelp, wx.wxID_ANY, "Inside corners can be measured two ways.  Both methods require specifying the approximate X and Y position of the corner.  The first method takes a single measurement in each axis, and assumes the corner is 90 degrees.  The second method takes two measurements in each direction, spaced as specified in the X and Y spacing dros.  This second method calculates the angle of each surface and calculates the actual corner angle and intersection point.  Measured results will be displayed and set in the appropriate # variables.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 525 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeInsideCornerHelp, wx.wxID_ANY, "X, Y position:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.m_staticText1:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeInsideCornerHelp, wx.wxID_ANY, "The absolute position, in the current work offset, of the corner point to be measured.  Probe moves will start from the initial position towards the specified point in each axis.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText22 = wx.wxStaticText( help.ProbeInsideCornerHelp, wx.wxID_ANY, "X, Y spacing:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText22:Wrap( -1 )
	help.m_staticText22:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText22, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText23 = wx.wxStaticText( help.ProbeInsideCornerHelp, wx.wxID_ANY, "When specified, the probe will measure two points for each axis.  The first measurement will be from the initial point, then the machine will shift by the value specified in the spacing DROs for the second point.  The X axis measurements will be separated by the X spacing value.  Y axis measurements by the Y spacing value.  If Y spacing is not specified it will automatically be set ot the X spacing value.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText23:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText23, 0, wx.wxALL, 5 )
	
	help.m_staticText24 = wx.wxStaticText( help.ProbeInsideCornerHelp, wx.wxID_ANY, "# Variables", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText24:Wrap( -1 )
	help.m_staticText24:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText24, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText25 = wx.wxStaticText( help.ProbeInsideCornerHelp, wx.wxID_ANY, "X, Y, Z machine position: #131 - 133\nX, Y, Z absolute position: #141 - 143\nX, Y, Z position error: #135 - 137\nCorner angle: #144\nCorner angle error: #138\nX surface angle: #145\nY surface angle: #146\n", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText25:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText25, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeInsideCornerHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeInsideCornerHelp:SetSizer( help.bSizer4 )
	help.ProbeInsideCornerHelp:Layout()
	
	help.ProbeInsideCornerHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeInsideCornerHelp:Destroy()
	end )
	help.ProbeInsideCornerHelp:Show()
end

function Probing.OutsideCornerHelp()
	local help = {}


	-- create ProbeOutsideCornerHelp
	help.ProbeOutsideCornerHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Outside Corner Probing Help", wx.wxDefaultPosition, wx.wxSize( 600,730 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeOutsideCornerHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeOutsideCornerHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeOutsideCornerHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText18 = wx.wxStaticText( help.ProbeOutsideCornerHelp, wx.wxID_ANY, "Set up and execution", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText18:Wrap( -1 )
	help.m_staticText18:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.bSizer4:Add( help.m_staticText18, 0, wx.wxALL, 5 )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeOutsideCornerHelp, wx.wxID_ANY, "Measurement points are calculated by comparing the initial point to the specified corner position.  The measurement point will be the same distance from the corner as the initial point.  Outside corners can be measured two ways.  Both methods require specifying the approximate X and Y position of the corner.  The first method takes a single measurement in each axis, and assumes the corner is 90 degrees.  The second method takes two measurements in each direction, spaced as specified in the X and Y spacing DROs.  This second method calculates the angle of each surface and calculates the actual corner angle and intersection point.  Measured results will be displayed and set in the appropriate # variables.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 525 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeOutsideCornerHelp, wx.wxID_ANY, "X, Y position:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.m_staticText1:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeOutsideCornerHelp, wx.wxID_ANY, "The absolute position, in the current work offset, of the corner point to be measured.  Probe moves will start from the initial position towards the specified point in each axis.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText22 = wx.wxStaticText( help.ProbeOutsideCornerHelp, wx.wxID_ANY, "X, Y spacing:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText22:Wrap( -1 )
	help.m_staticText22:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText22, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText23 = wx.wxStaticText( help.ProbeOutsideCornerHelp, wx.wxID_ANY, "When specified, the probe will measure two points for each axis.  The first measurement will be from a position defined by the initial point, then the machine will shift by the value specified in the spacing DROs for the second point.  The X axis measurements will be separated by the X spacing value.  Y axis measurements by the Y spacing value.  If Y spacing is not specified it will automatically be set ot the X spacing value.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText23:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText23, 0, wx.wxALL, 5 )
	
	help.m_staticText24 = wx.wxStaticText( help.ProbeOutsideCornerHelp, wx.wxID_ANY, "# Variables", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText24:Wrap( -1 )
	help.m_staticText24:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText24, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText25 = wx.wxStaticText( help.ProbeOutsideCornerHelp, wx.wxID_ANY, "X, Y, Z machine position: #131 - 133\nX, Y, Z absolute position: #141 - 143\nX, Y, Z position error: #135 - 137\nCorner angle: #144\nCorner angle error: #138\nX surface angle: #145\nY surface angle: #146\n", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText25:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText25, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeOutsideCornerHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeOutsideCornerHelp:SetSizer( help.bSizer4 )
	help.ProbeOutsideCornerHelp:Layout()
	
	help.ProbeOutsideCornerHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeOutsideCornerHelp:Destroy()
	end )
	help.ProbeOutsideCornerHelp:Show()
end

function Probing.InsideCenteringHelp()
	local help = {}


	-- create ProbeInsideCenteringHelp
	help.ProbeInsideCenteringHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Inside Centering Probing Help", wx.wxDefaultPosition, wx.wxSize( 600,402 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeInsideCenteringHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeInsideCenteringHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeInsideCenteringHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText18 = wx.wxStaticText( help.ProbeInsideCenteringHelp, wx.wxID_ANY, "Set up and execution", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText18:Wrap( -1 )
	help.m_staticText18:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.bSizer4:Add( help.m_staticText18, 0, wx.wxALL, 5 )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeInsideCenteringHelp, wx.wxID_ANY, "Inside centering finds the center point between two surfaces, such as inside a pocket or between two parts.  A nominal width is specified and measurement moves are calculated assuming the initial point is at or near the center.  Measured results will be displayed and set in the appropriate # variables.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 525 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeInsideCenteringHelp, wx.wxID_ANY, "Width:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.m_staticText1:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeInsideCenteringHelp, wx.wxID_ANY, "The nominal width of the part being measured.  The current position is assumed to be the nominal center point.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText24 = wx.wxStaticText( help.ProbeInsideCenteringHelp, wx.wxID_ANY, "# Variables", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText24:Wrap( -1 )
	help.m_staticText24:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText24, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText25 = wx.wxStaticText( help.ProbeInsideCenteringHelp, wx.wxID_ANY, "X, Y machine position: #131 - 132\nX, Y absolute position: #141 - 142\nX, Y position error: #135 - 136\nWidth: #144\nWidth error: #138\n", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText25:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText25, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeInsideCenteringHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeInsideCenteringHelp:SetSizer( help.bSizer4 )
	help.ProbeInsideCenteringHelp:Layout()
	
	help.ProbeInsideCenteringHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeInsideCenteringHelp:Destroy()
	end )
	help.ProbeInsideCenteringHelp:Show()
end

function Probing.OutsideCenteringHelp()
	local help = {}


	-- create ProbeOutsideCenteringHelp
	help.ProbeOutsideCenteringHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Outside Centering Probing Help", wx.wxDefaultPosition, wx.wxSize( 600,653 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeOutsideCenteringHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeOutsideCenteringHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeOutsideCenteringHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText18 = wx.wxStaticText( help.ProbeOutsideCenteringHelp, wx.wxID_ANY, "Set up and execution", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText18:Wrap( -1 )
	help.m_staticText18:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.bSizer4:Add( help.m_staticText18, 0, wx.wxALL, 5 )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeOutsideCenteringHelp, wx.wxID_ANY, "Outside centering finds the center point between two surfaces on the outside of a part.  A nominal width is specified and measurement moves are calculated assuming the initial point is at or near the center.  An approach value is specified that defines how far from the nominal surface the fast find probe move should start.  It is possible to measure the center of an inside pocket by specifying a negative approach value, this would be useful for pockets with islands.  The Z measurement position must be specified.  The machine will move to this Z plane for measurment, and back to the inital point to traverse.  Measured results will be displayed and set in the appropriate # variables.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 525 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeOutsideCenteringHelp, wx.wxID_ANY, "Width:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.m_staticText1:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeOutsideCenteringHelp, wx.wxID_ANY, "The nominal width of the part being measured.  The current position is assumed to be the nominal center point.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText9 = wx.wxStaticText( help.ProbeOutsideCenteringHelp, wx.wxID_ANY, "Approach:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText9:Wrap( -1 )
	help.m_staticText9:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText9, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText10 = wx.wxStaticText( help.ProbeOutsideCenteringHelp, wx.wxID_ANY, "Distance from the nominal surface, at which probing moves should start.  A negative value will force an inside measurement for measuring pockets with islands.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText10:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText10, 0, wx.wxALL, 5 )
	
	help.m_staticText11 = wx.wxStaticText( help.ProbeOutsideCenteringHelp, wx.wxID_ANY, "Z position:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText11:Wrap( -1 )
	help.m_staticText11:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText11, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText12 = wx.wxStaticText( help.ProbeOutsideCenteringHelp, wx.wxID_ANY, "Z position at which measurements should be taken.  The probe will move to a point that is the approach distance away from the surface, then move down to this Z position before making measurement moves.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText12:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText12, 0, wx.wxALL, 5 )
	
	help.m_staticText24 = wx.wxStaticText( help.ProbeOutsideCenteringHelp, wx.wxID_ANY, "# Variables", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText24:Wrap( -1 )
	help.m_staticText24:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText24, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText25 = wx.wxStaticText( help.ProbeOutsideCenteringHelp, wx.wxID_ANY, "X, Y machine position: #131 - 132\nX, Y absolute position: #141 - 142\nX, Y position error: #135 - 136\nWidth: #144\nWidth error: #138\n", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText25:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText25, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeOutsideCenteringHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeOutsideCenteringHelp:SetSizer( help.bSizer4 )
	help.ProbeOutsideCenteringHelp:Layout()
	
	help.ProbeOutsideCenteringHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeOutsideCenteringHelp:Destroy()
	end )
	help.ProbeOutsideCenteringHelp:Show()
end

function Probing.BoreHelp()
	local help = {}


	-- create ProbeBoreHelp
	help.ProbeBoreHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Bore Probing Help", wx.wxDefaultPosition, wx.wxSize( 600,402 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeBoreHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeBoreHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeBoreHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText18 = wx.wxStaticText( help.ProbeBoreHelp, wx.wxID_ANY, "Set up and execution", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText18:Wrap( -1 )
	help.m_staticText18:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.bSizer4:Add( help.m_staticText18, 0, wx.wxALL, 5 )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeBoreHelp, wx.wxID_ANY, "Probing a bore finds the center point or a bore, usually a hole, in the part.  A nominal diameter is specified and measurement moves are calculated assuming the initial point is at or near the center.  Measured results will be displayed and set in the appropriate # variables.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 525 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeBoreHelp, wx.wxID_ANY, "Diameter:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.m_staticText1:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeBoreHelp, wx.wxID_ANY, "The nominal diameter of the bore to be measured.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText24 = wx.wxStaticText( help.ProbeBoreHelp, wx.wxID_ANY, "# Variables", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText24:Wrap( -1 )
	help.m_staticText24:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText24, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText25 = wx.wxStaticText( help.ProbeBoreHelp, wx.wxID_ANY, "X, Y machine position: #131 - 132\nX, Y absolute position: #141 - 142\nX, Y position error: #135 - 136\nDiameter: #144\nDiameter error: #138\n", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText25:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText25, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeBoreHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeBoreHelp:SetSizer( help.bSizer4 )
	help.ProbeBoreHelp:Layout()
	
	help.ProbeBoreHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeBoreHelp:Destroy()
	end )
	help.ProbeBoreHelp:Show()
end

function Probing.BossHelp()
	local help = {}


	-- create ProbeBossHelp
	help.ProbeBossHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Boss Probing Help", wx.wxDefaultPosition, wx.wxSize( 600,653 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeBossHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeBossHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeBossHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText18 = wx.wxStaticText( help.ProbeBossHelp, wx.wxID_ANY, "Set up and execution", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText18:Wrap( -1 )
	help.m_staticText18:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.bSizer4:Add( help.m_staticText18, 0, wx.wxALL, 5 )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeBossHelp, wx.wxID_ANY, "Probing a boss finds the center point of a protrusion on the part.  A nominal diameter is specified and measurement moves are calculated assuming the initial point is at or near the center.  An approach value is specified that defines how far from the nominal surface the fast find probe move should start.  It is possible to measure the center of a bore by specifying a negative approach value, this would be useful for circular grooves or bores with islands.  The Z measurement position must be specified.  The machine will move to this Z plane for measurment, and back to the inital point to traverse.  Measured results will be displayed and set in the appropriate # variables.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 525 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeBossHelp, wx.wxID_ANY, "Diam:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.m_staticText1:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeBossHelp, wx.wxID_ANY, "Nominal diam of the boss being measured.  The current position is assumed to be the nominal center point.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText9 = wx.wxStaticText( help.ProbeBossHelp, wx.wxID_ANY, "Approach:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText9:Wrap( -1 )
	help.m_staticText9:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText9, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText10 = wx.wxStaticText( help.ProbeBossHelp, wx.wxID_ANY, "Distance from the nominal surface, at which probing moves should start.  A negative value will force an inside measurement for measuring bores with islands.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText10:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText10, 0, wx.wxALL, 5 )
	
	help.m_staticText11 = wx.wxStaticText( help.ProbeBossHelp, wx.wxID_ANY, "Z position:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText11:Wrap( -1 )
	help.m_staticText11:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText11, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText12 = wx.wxStaticText( help.ProbeBossHelp, wx.wxID_ANY, "Z position at which measurements should be taken.  The probe will move to a point that is the approach distance away from the surface, then move down to this Z position before making measurement moves.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText12:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText12, 0, wx.wxALL, 5 )
	
	help.m_staticText24 = wx.wxStaticText( help.ProbeBossHelp, wx.wxID_ANY, "# Variables", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText24:Wrap( -1 )
	help.m_staticText24:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText24, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText25 = wx.wxStaticText( help.ProbeBossHelp, wx.wxID_ANY, "X, Y machine position: #131 - 132\nX, Y absolute position: #141 - 142\nX, Y position error: #135 - 136\nDiameter: #144\nDiameter error: #138\n", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText25:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText25, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeBossHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeBossHelp:SetSizer( help.bSizer4 )
	help.ProbeBossHelp:Layout()
	
	help.ProbeBossHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeBossHelp:Destroy()
	end )
	help.ProbeBossHelp:Show()
end

function Probing.SingleAngleHelp()
	local help = {}


	-- create ProbeSingleAngleHelp
	help.ProbeSingleAngleHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Single Angle Probing Help", wx.wxDefaultPosition, wx.wxSize( 600,652 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeSingleAngleHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeSingleAngleHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeSingleAngleHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText18 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "Set up and execution", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText18:Wrap( -1 )
	help.m_staticText18:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.bSizer4:Add( help.m_staticText18, 0, wx.wxALL, 5 )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "The single angle measure cycles measure the angle of a surface in the XY (G17) plane.  The probe should be positioned near the desired surface prior to running the cycle.  When the sequence starts the probe will move at the specified fast feedrate to find the surface, then retract and measure at the slow feedrate.  It will then retract to the start position and move by the specified increment distance to measure a second point.  Measured results will be displayed and set in the appropriate # variables.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 525 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "X or Y position:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.m_staticText1:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "The absolute position, in the current work offset, of the surface to be measured.  The probe will move only the specifed axis towards this position.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText9 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "X or Y increment:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText9:Wrap( -1 )
	help.m_staticText9:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText9, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText10 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "The increment value specifies the space in between measurement 1 and measurement 2 parallel to the surface being measured.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText10:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText10, 0, wx.wxALL, 5 )
	
	help.m_staticText11 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "X and Y center:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText11:Wrap( -1 )
	help.m_staticText11:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText11, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText12 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "If coordinate rotation is desired, the centerpoint of rotation must be defined.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText12:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText12, 0, wx.wxALL, 5 )
	
	help.m_staticText22 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "Measurement type:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText22:Wrap( -1 )
	help.m_staticText22:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText22, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText23 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "This probing operation does not set any fixture offsets, but still uses the measurement type selection.  When set to \"Measure Only\" the results will be set to the appropriate # variables only.  If \"Set Fixture Offset\" is selected then the coordinate system will be rotated by the measure angle.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText23:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText23, 0, wx.wxALL, 5 )
	
	help.m_staticText24 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "# Variables", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText24:Wrap( -1 )
	help.m_staticText24:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText24, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText25 = wx.wxStaticText( help.ProbeSingleAngleHelp, wx.wxID_ANY, "Angle: #144\nAngle Error: #138\n", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText25:Wrap( 400 )
	help.fgSizer1:Add( help.m_staticText25, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeSingleAngleHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeSingleAngleHelp:SetSizer( help.bSizer4 )
	help.ProbeSingleAngleHelp:Layout()
	
	help.ProbeSingleAngleHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeSingleAngleHelp:Destroy()
	end )
	help.ProbeSingleAngleHelp:Show()
end

function Probing.ResultsHelp()
	help = {}
	-- create ProbeResultsHelp
	help.ProbeResultsHelp = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Probing Results Help", wx.wxDefaultPosition, wx.wxSize( 600,1009 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	help.ProbeResultsHelp:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	help.ProbeResultsHelp :SetForegroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_WINDOWTEXT ) )
	help.ProbeResultsHelp :SetBackgroundColour( wx.wxSystemSettings.GetColour( wx.wxSYS_COLOUR_3DLIGHT ) )
	
	help.bSizer4 = wx.wxBoxSizer( wx.wxVERTICAL )
	
	help.m_staticText17 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "At the conclusion of a probing cycle the measument results will be set to the pound variables listed below.  A selection of these variables will be listed on the probing tab.", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText17:Wrap( 600 )
	help.bSizer4:Add( help.m_staticText17, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	help.fgSizer1 = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	help.fgSizer1:SetFlexibleDirection( wx.wxBOTH )
	help.fgSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	help.m_staticText1 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Machine Positions:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText1:Wrap( -1 )
	help.m_staticText1:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText1, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText2 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "The machine position of the measurment point corrected for probe XY offset and radius.\n#131 - X machine position\n#132 - Y machine position\n#133 - Z machine position", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText2:Wrap( 425 )
	help.fgSizer1:Add( help.m_staticText2, 0, wx.wxALL, 5 )
	
	help.m_staticText22 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Absolute Positions*:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText22:Wrap( -1 )
	help.m_staticText22:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText22, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText23 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "The absolute position, in the currently active fixture offset, of the measurment point corrected for probe XY offset and radius.\n#141 - X absolute position\n#142 - Y absolute position\n#143 - Z absolute position", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText23:Wrap( 425 )
	help.fgSizer1:Add( help.m_staticText23, 0, wx.wxALL, 5 )
	
	help.m_staticText13 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Postion Error*:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText13:Wrap( -1 )
	help.m_staticText13:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText13, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText14 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Displays the position error between the input value and the actual measured value.\n#135 - X position error\n#136 - Y position error\n#137 - Z position error", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText14:Wrap( 425 )
	help.fgSizer1:Add( help.m_staticText14, 0, wx.wxALL, 5 )
	
	help.m_staticText24 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Size/Angle*:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText24:Wrap( -1 )
	help.m_staticText24:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText24, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText25 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "The size of the measured feature.  The value and type of measurement varies according the the cycle being run.  It could be a diameter for bore/boss measurements, angle for corners, width for centering or simply a position for single surface.\n#144 - Size of feature", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText25:Wrap( 425 )
	help.fgSizer1:Add( help.m_staticText25, 0, wx.wxALL, 5 )
	
	help.m_staticText15 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Size Error*:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText15:Wrap( -1 )
	help.m_staticText15:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText15, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText16 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Displays the error between the input or theoretical size and the actual measured size.\n#138 - Size error", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText16:Wrap( 425 )
	help.fgSizer1:Add( help.m_staticText16, 0, wx.wxALL, 5 )
	
	help.m_staticText9 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Angle X and Y*:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText9:Wrap( -1 )
	help.m_staticText9:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText9, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText10 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "X and Y angles are calculated when corners or angles are measured.\n#145 - X angle\n#146 - Y angle", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText10:Wrap( 425 )
	help.fgSizer1:Add( help.m_staticText10, 0, wx.wxALL, 5 )
	
	help.m_staticText11 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Angle Error*:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText11:Wrap( -1 )
	help.m_staticText11:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText11, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText12 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "The error between the input or theoretical and actual measured angles.\n#139 - X angle error\n#140 - Y angle error", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText12:Wrap( 425 )
	help.fgSizer1:Add( help.m_staticText12, 0, wx.wxALL, 5 )
	
	help.m_staticText19 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Measurements:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText19:Wrap( -1 )
	help.m_staticText19:SetFont( wx.wxFont( wx.wxNORMAL_FONT:GetPointSize(), 70, 90, 92, False, "" ) )
	
	help.fgSizer1:Add( help.m_staticText19, 0, wx.wxALIGN_RIGHT + wx.wxALL, 5 )
	
	help.m_staticText20 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "Raw measurement postions from the probing sequence.  These are uncorrected for probe XY offset and radius.\n#101 - #103 - X, Y, Z absolute positions\n#104 - #106 - X, Y, Z second absolute positions\n#111 - #113 - X, Y, Z machine positions\n#114 - #116 - X, Y, Z second machine positions", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText20:Wrap( 425 )
	help.fgSizer1:Add( help.m_staticText20, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( help.fgSizer1, 1, wx.wxEXPAND, 5 )
	
	help.m_staticText18 = wx.wxStaticText( help.ProbeResultsHelp, wx.wxID_ANY, "*Displayed on the screen in the results group", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	help.m_staticText18:Wrap( -1 )
	help.bSizer4:Add( help.m_staticText18, 0, wx.wxALL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	help.m_sdbSizer2 = wx.wxStdDialogButtonSizer()
	help.m_sdbSizer2OK = wx.wxButton( help.ProbeResultsHelp, wx.wxID_OK, "" )
	help.m_sdbSizer2:AddButton( help.m_sdbSizer2OK )
	help.m_sdbSizer2:Realize();
	
	help.bSizer4:Add( help.m_sdbSizer2, 1, wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	
	help.bSizer4:Add( 0, 0, 1, wx.wxEXPAND, 5 )
	
	
	help.ProbeResultsHelp:SetSizer( help.bSizer4 )
	help.ProbeResultsHelp:Layout()
	
	help.ProbeResultsHelp:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	help.m_sdbSizer2OK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements m_sdbSizer2OnOKButtonClick
	
	help.ProbeResultsHelp:Destroy()
	end )
	help.ProbeResultsHelp:Show()
end

return Probing
