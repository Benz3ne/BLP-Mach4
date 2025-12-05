# Mach4 Register Reference
## Complete findings from testing - Updated with full register list

## ✅ CONFIRMED WORKING REGISTERS

### ESS Device Registers (Device Handle: 373845696)
**Access Method: Use `ESS/` prefix OR enumerate from device handle**

#### Analog Outputs
- `ESS/Analog/Output/0_Spindle_PWM` - Type: 8.0, Writable: YES
- `ESS/Analog/Output/1_Laser_PWM` - Type: 256.0, Writable: NO

#### Timing Registers
**Working with ESS/ prefix:**
- `ESS/Timing/MainLoopCycleTime` - Main Loop Cycle Time
- `ESS/Timing/MainLoopCycleTimeHigh` - Main Loop Cycle Time High  
- `ESS/Timing/MainLoopProcTime` - Main Loop Processing Time
- `ESS/Timing/MainLoopProcTimeHigh` - Main Loop Processing Time High

**Via enumeration only:**
- `Timing/MainLoopTimerOverflowCount` - Main Loop Timer Overflow Count

#### Laser/Raster Registers
**All require ESS/ prefix to access directly:**
- `ESS/Laser/Raster/Reduce_PWM_MIN_On_Ramps_By_N_Percent`
- `ESS/Laser/Raster/Use_PWM_MIN_For_Accel_Decel_Ramps`
- `ESS/Laser/Raster/User_Override_PWM_MAX_Percentage`
- `ESS/Laser/Raster/User_Override_PWM_MIN_Percentage`
- `ESS/Laser/Raster/Show_Start_Confirmation_Window`
- `ESS/Laser/Raster/Start_Raster_On_Line_Number`
- `ESS/Laser/Raster/Final_Ramp_PWM_Percentage`
- `ESS/Laser/Raster/Ignore_Motor_X_Secondary` ✓ Confirmed
- `ESS/Laser/Raster/GCode_PWM_MAX_Percentage`
- `ESS/Laser/Raster/Final_PWM_MAX_Percentage`
- `ESS/Laser/Raster/GCode_PWM_MIN_Percentage`
- `ESS/Laser/Raster/Final_PWM_MIN_Percentage`
- `ESS/Laser/Raster/Estimated_Time_Remaining`
- `ESS/Laser/Raster/Image_Starting_Corner` ✓ Confirmed
- `ESS/Laser/Raster/Comp_For_Accel_Dist_X`
- `ESS/Laser/Raster/Show_Corner_Positions`
- `ESS/Laser/Raster/Motor_Delay_Distance`
- `ESS/Laser/Raster/Image_Color_Channel` ✓ Confirmed
- `ESS/Laser/Raster/Invert_Internsities`
- `ESS/Laser/Raster/File_Path_And_Name` ✓ Confirmed
- `ESS/Laser/Raster/Current_PWM_Output`
- `ESS/Laser/Raster/Line_Percentage`
- `ESS/Laser/Raster/Base_Frequency`
- `ESS/Laser/Raster/Line_Feed_Hold`
- `ESS/Laser/Raster/PWM_Frequency`
- `ESS/Laser/Raster/Gate_Duration`
- `ESS/Laser/Raster/Log_Bmp_Data`
- `ESS/Laser/Raster/Line_Current`
- `ESS/Laser/Raster/FIFO_Ran_Dry`
- `ESS/Laser/Raster/FeedRate_X` ✓ Confirmed
- `ESS/Laser/Raster/Gate_Delay`
- `ESS/Laser/Raster/Line_Total`
- `ESS/Laser/Raster/FIFO_Level`
- `ESS/Laser/Raster/FIFO_Empty`
- `ESS/Laser/Raster/PWM_Zero`
- `ESS/Laser/Raster/Command` ✓ Confirmed
- `ESS/Laser/Raster/Flip_X`
- `ESS/Laser/Raster/Flip_Y`
- `ESS/Laser/Raster/Error` ✓ Confirmed
- `ESS/Laser/Raster/Start` ✓ Confirmed
- `ESS/Laser/Raster/Units` ✓ Confirmed

**Via enumeration (different name format):**
- `Laser/Raster_Test_or_Vector_Enabled` - Enumeration name

#### Laser/Vector Registers
**All require ESS/ prefix to access directly:**
- `ESS/Laser/Vector/User_Override_PWM_Percentage`
- `ESS/Laser/Vector/Laser_Delay_M63_OFF_Enabled`
- `ESS/Laser/Vector/Laser_Delay_M63_OFF_Time_ms`
- `ESS/Laser/Vector/GCode_PWM_Percentage`
- `ESS/Laser/Vector/Final_PWM_Percentage`
- `ESS/Laser/Vector/THC_Mode_Activate`
- `ESS/Laser/Vector/Base_Frequency`
- `ESS/Laser/Vector/PWM_Frequency`
- `ESS/Laser/Vector/Gate_Duration`
- `ESS/Laser/Vector/Gate_Delay`
- `ESS/Laser/Vector/Command`
- `ESS/Laser/Vector/Enable` ✓ Confirmed

**Via enumeration only:**
- `Laser/Current_PWM`
- `Laser/Air_Assist`
- `Laser/Test_Mode_Enable`
- `Laser/Test_Mode_Activate`
- `Laser/Test_Mode_PWM_Power`

#### Laser PWM/Special Registers
- `Laser PWM/XY Vel PWM/AOut1` - May need special access
- `Laser PWM/XY Vel PWM` - May need special access
- `Laser Gate (On/Off) Output #` - May need special access

#### Height Control (HC) Registers
**Working with ESS/ prefix:**
- `ESS/HC/ARC_OKAY` ✓ Confirmed

**Other HC registers (need ESS/ prefix):**
- `ESS/HC/PRECISION_DELAY_AFTER_ARC_OKAY_SEC`
- `ESS/HC/Z_VELOCITY_DOWN_SPEED_PERCENTAGE`
- `ESS/HC/Z_VELOCITY_UP_SPEED_PERCENTAGE`
- `ESS/HC/WORK_Z_ZEROED`
- `ESS/HC/Z_MAX_VALUE`
- `ESS/HC/Z_MIN_VALUE`
- `ESS/HC/Feedhold_Aserted_After_Losing_Arc_Okay`
- `ESS/HC/Resume_Cutting__Delay_Until_Arc_Okay`
- `ESS/HC/Limit_Switches_Inhibited_for_Pierce`
- `ESS/HC/Control_Manual_Mode_Commanding_DOWN`
- `ESS/HC/Control_Manual_Mode_Commanding_UP`
- `ESS/HC/Mode_Motion_Synced_With_Arc_Okay`
- `ESS/HC/Delay_After_Arc_Okay_Active`
- `ESS/HC/Z DRO Mach4 Commanded Steps`
- `ESS/HC/Waitng_For_Arc_Okay_Active`
- `ESS/HC/Pierce_Count_Value_Current`
- `ESS/HC/Pierce_Count_Warning_Value`
- `ESS/HC/Z_DRO_Force_Sync_With_Aux`
- `ESS/HC/Control_Mode_Status_Val`
- `ESS/HC/Z_DRO_Synced_With_Mach`
- `ESS/HC/Pierce_Count_Exceeded`
- `ESS/HC/Z DRO Real Tool Steps`
- `ESS/HC/Z DRO THC Delta Steps`
- `ESS/HC/Control_Mode_Enable`
- `ESS/HC/Pierce_Count_Reset`
- `ESS/HC/Z DRO THC Distance`
- `ESS/HC/Control_Mode_Type`
- `ESS/HC/Mode_State_String`
- `ESS/HC/FeedHoldPressed`
- `ESS/HC/Diag State Verb`
- `ESS/HC/Z_Max_Exceeded`
- `ESS/HC/Z_Min_Exceeded`
- `ESS/HC/Torch_Relay_On`
- `ESS/HC/Mode_State_Val`
- `ESS/HC/Command`

#### Encoder Registers
**Working with ESS/ prefix:**
- `ESS/Encoders/Encoder_0` ✓ Confirmed
- `ESS/Encoders/Encoder Spindle`
- `ESS/Encoders/Encoder_Spindle`
- `ESS/Encoders/Encoder Aux 0`
- `ESS/Encoders/Encoder_Aux_0`
- `ESS/Encoders/Encoder Aux 1`
- `ESS/Encoders/Encoder_Aux_1`
- `ESS/Encoders/Encoder Aux 2`
- `ESS/Encoders/Encoder_Aux_2`
- `ESS/Encoders/Encoder 0`
- `ESS/Encoders/Encoder 1`
- `ESS/Encoders/Encoder_1`
- `ESS/Encoders/Encoder 2`
- `ESS/Encoders/Encoder_2`
- `ESS/Encoders/Encoder 3`
- `ESS/Encoders/Encoder_3`
- `ESS/Encoders/Encoder 4`
- `ESS/Encoders/Encoder_4`
- `ESS/Encoders/Encoder 5`
- `ESS/Encoders/Encoder_5`

**Special format:**
- `Encoders and/or MPGs` - May need special access

#### Velocity (Vel) Registers
**Working with ESS/ prefix:**
- `ESS/Vel/EN_SP` ✓ Confirmed
- `ESS/Vel/CLEAR`
- `ESS/Vel/0_SP`
- `ESS/Vel/1_SP`
- `ESS/Vel/2_SP`
- `ESS/Vel/3_SP`
- `ESS/Vel/4_SP`
- `ESS/Vel/5_SP`
- `ESS/Vel/Events`
- `ESS/Vel/0_Min`
- `ESS/Vel/0_Max`
- `ESS/Vel/1_Min`
- `ESS/Vel/1_Max`
- `ESS/Vel/2_Min`
- `ESS/Vel/2_Max`
- `ESS/Vel/3_Min`
- `ESS/Vel/3_Max`
- `ESS/Vel/4_Min`
- `ESS/Vel/4_Max`
- `ESS/Vel/5_Min`
- `ESS/Vel/5_Max`

#### Expansion Port Registers
**Via enumeration (without ESS/ prefix):**
- `ExpansionPort/Ready` ✓ Confirmed
- `ExpansionPort/Plugin_Handshake_From_SS` ✓ Confirmed
- `ExpansionPort/Plugin_Handshake_To_SS` ✓ Confirmed
- `ExpansionPort/Plugin_AU` ✓ Confirmed
- `ExpansionPort/Plugin_AL` ✓ Confirmed
- `ExpansionPort/Plugin_Heartbeat` ✓ Confirmed

**Try with ESS/ prefix:**
- `ESS/ExpansionPort/Ready`
- `ESS/ExpansionPort/Plugin_Handshake_From_SS`
- `ESS/ExpansionPort/Plugin_Handshake_To_SS`
- `ESS/ExpansionPort/Plugin_AU`
- `ESS/ExpansionPort/Plugin_AL`
- `ESS/ExpansionPort/Plugin_Heartbeat`

#### Probing Registers
**Via enumeration only:**
- `Probe_Failure_Occurred`
- `Probing_Failure_Disables_Mach`
- `Probing_State`
- `Probe_0` through `Probe_3`

#### ESS Status Registers
**Via enumeration from ESS device:**
- `Connected`
- `ESS_Packets`
- `Device_Time`
- `State`
- `Mach4_GCode_Line`
- `Build_Version` - Value: "308"
- `Build_Version_Mach4` - Value: "4.2.0.5308"
- `Force_Config_Update`
- `Spindle_RPM_Index`
- `Spindle_RPM_Avg`
- `Buffer_Empty_Count`
- `Stalled_Sequence_Count`
- `Current_Buffer_Level`
- `Buffer_Data_To_Send`
- `FRB`
- `General_Command_M2010`
- `User_Comment_To_Log_M2011`
- `ESS/CC_XComp_Allowed` - May exist with ESS/ prefix

#### Homing/SoftLimits
- `Homing/SoftLimits` - Not a register, configuration setting
- `ESS/Homing/SoftLimits` - Try with prefix

#### Other Registers
- `Analog/Output/0_Spindle_PWM` - Alternative path for spindle PWM
- `Analog/Output/1_Laser_PWM` - Alternative path for laser PWM
- `Step/Dir, Quadrature or CW/CCW` - Configuration note, not a register
- `Spindle Rev - Only active when the spindle is running in reverse/CCW` - Status note
- `Spindle Fwd - Only active when the spindle is running forwards/CW` - Status note

---

## ❌ REGISTERS REQUIRING HARDWARE (Not Working Without Hardware)

### W9_HC Registers (THC Control Hardware Required)
**These exist in strings but require W9 THC hardware to be connected:**
- All 47 W9_HC registers including:
  - `W9_HC/VOLTAGE_AD_AD6_ATV_PERCENT_BELOW_CURRENT_TIP_VOLTS`
  - `W9_HC/VOLTAGE_AD_AD5_ATV_PERCENT_ABOVE_CURRENT_TIP_VOLTS`
  - `W9_HC/REPORT_MODE_ARC_OK_DELAY_BEFORE_THC_INHIBITING_THC`
  - `W9_HC/TARGET_TIP_VOLTS`
  - `W9_HC/VERSION`
  - (42+ more - see full list in original document)

---

## 📍 ACCESS METHODS

### Method 1: Direct Path
Try the register path exactly as listed:
```lua
local handle, rc = mc.mcRegGetHandle(inst, "Probe_0")
```

### Method 2: ESS Prefix
Add `ESS/` to the beginning of the path:
```lua
local handle, rc = mc.mcRegGetHandle(inst, "ESS/Laser/Vector/Enable")
```

### Method 3: Device Enumeration
Enumerate from ESS device handle (373845696):
```lua
local prev_handle = 0
local handle, rc = mc.mcRegGetNextHandle(373845696, prev_handle)
-- Returns registers with enumeration names
```

### Access Priority Order:
1. Try direct path first
2. If failed, try with `ESS/` prefix
3. If still failed, enumerate from device to find actual name
4. Fall back to alternatives (PVs, GeneralReg)

---

## 📦 ALTERNATIVE STORAGE

### Core Device Registers (Device Handle: 370956544)
- `core/global/Version` - Value: "4"
- `core/global/Build` - Value: "5308"
- `core/global/Reserved` - Value: "0"
- `core/global/GuiName` - Value: "Mach 4 - Hobby"
- `core/global/SelectedInstance` - Value: "0"

### Sim Device Registers (Device Handle: 373420640)
**All writable, access directly by name:**
- `GeneralReg0` through `GeneralReg9` - General purpose storage
- `OutputReg0` through `OutputReg3` - Output storage
- `Encoder0` through `Encoder7` - Sim encoders
- `AuxEncoder0`, `AuxEncoder1` - Auxiliary encoders
- `Panel0`, `Panel1` - Panel registers
- `utime`, `run`, `SimCommand`, `MainLoopHigh`

### Pound Variables
- Range: #1 to #19999
- All read/writable
- Access via `mc.mcCntlGetPoundVar` / `mc.mcCntlSetPoundVar`

### Profile Storage
- Persistent storage via `mc.mcProfileWriteString` / `mc.mcProfileGetString`

---

## ⚠️ IMPORTANT NOTES

1. **ESS Plugin Version Matters**: Build 278+ changed register names for Spindle/Laser PWM
2. **Register Types**: 16.0 = string, 4.0 = float, 8.0 = double, 256.0 = special/read-only
3. **Most ESS registers** need the `ESS/` prefix when accessing by path
4. **Enumeration names** often differ from the direct path format
5. **Hardware-dependent registers** only appear when hardware is connected
6. **Configuration vs Registers**: Some items like Homing/SoftLimits are plugin configuration, not registers

---
