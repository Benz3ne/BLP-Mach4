# ScreenLoad.lua - Documentation

## Overview

`ScreenLoad.lua` is the main entry point script that runs when the Mach4 screen loads. It initializes global variables, sets up the UI update timer, loads dependent scripts, and contains all the core functions that drive the user interface and machine control operations.

**Location:** `C:\Users\benja\Documents\Mach4\BLP\Scripts\ScreenLoad.lua`

---

## Architecture

### Initialization Flow

1. Global variables initialized (`inst`, `pageId`, `screenId`, `machState`, etc.)
2. UI Timer stopped if already running (prevents duplicate timers on reload)
3. Path globals set (`_G.ROOT`, `_G.SYS`, `DEPS`)
4. Dependencies loaded via `package.path`
5. `ButtonScripts.lua` loaded via `dofile()`
6. `state` table initialized (used by `SyncMPG()` for tracking)
7. `SigLib` and `MsgLib` tables defined for signal/message handling
8. External modules loaded (`mcRegister`, `mcErrorCheck`, `mcTrace`)
9. System settings loaded from profile (`LoadSystemSettings()`)
10. Dialog system initialized (`InitDialogSystem()`)
11. Temp files cleaned up (`CleanupTemp()`)
12. UI Timer started (100ms interval)

### Cross-File Interactions

| File | Interaction |
|------|-------------|
| `ButtonScripts.lua` | Loaded at startup; contains button-triggered functions too large for ScreenLoad (e.g., `TargetMove()`, `LaserRaster()`) |
| `ProbeScripts.mcs` | Communicates via file-based IPC for dialogs |
| `PLC.lua` | Runs every PLC cycle; calls `SyncMPG()`, `ProbeCrashCheck()`, `ProcessDeferredGCode()`, `ProcessDialogRequest()`, updates cycle time display |
| `mcRegister.lua` | Used for register creation/management |
| `mcErrorCheck.lua` | Error checking utilities |
| `mcTrace.lua` | Debug tracing utilities |

---

## Global Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `inst` | number | Mach4 instance handle |
| `machState` | number | Current machine state (updated by PLC) |
| `machStateOld` | number | Previous machine state (for change detection) |
| `machEnabled` | number | Machine enabled flag (0/1) |
| `machWasEnabled` | number | Previous enabled state |
| `MachineEnabledTime` | number | `os.clock()` when machine was enabled (used for debouncing) |
| `_G.ROOT` | string | Scripts root path (`...\Profiles\BLP\Scripts`) |
| `_G.SYS` | string | System scripts path (`...\Scripts\System`) |
| `state` | table | Used by `SyncMPG()` to track `axis_rates` and `mpg0_inc` |
| `UILastStates` | table | Previous UI element states (optimization to avoid redundant updates) |
| `UIFlashCounter` | number | Counter for flashing UI elements (0-999, increments each timer tick) |
| `wait` | coroutine | Used by `RunWithPLC()` for coroutine-based operations that span PLC cycles |

---

## Signal Library (SigLib)

The `SigLib` table maps signal constants to handler functions. These are called when specific signals change state.

| Signal | Handler Purpose |
|--------|-----------------|
| `OSIG_MACHINE_ENABLED` | On enable: toggle soft limits, keyboard inputs, check air, spindle tool dialog, init jog. On disable: retract virtual tools |
| `OSIG_RUNNING_GCODE` | Trigger dust collection automation |
| `ISIG_INPUT6` | Air pressure check |
| `ISIG_INPUT8` | Spindle tool presence button (with 2s debounce) |
| `ISIG_INPUT17` | Tool present sensor - handle dialog dismissal |
| `OSIG_JOG_CONT` | Update jog mode label to "Continuous" |
| `OSIG_JOG_INC` | Update jog mode label to "Incremental" |
| `OSIG_JOG_MPG` | Clear jog mode label for MPG mode |

---

## Core Functions

### Machine Control

#### `CycleStart()`
**Purpose:** Main cycle start handler with comprehensive safety checks.

**Pre-Start Safety Checks (skipped if already running):**
1. **Work Offset Mismatch** - Scans first 30 lines for G54-G59 or G54.1 Pxx; warns if different from current offset
2. **G68/G18/G19 Incompatibility** - If G68 rotation active, scans entire file for G18/G19 plane selection (incompatible)
3. **Override Values** - If FRO/RRO/SRO not at 100%, prompts: Continue / Reset to 100% / Cancel
4. **Run From Here** - If line > 0 selected, calls `RunFromHere()` for state reconstruction

**Execution:**
- States 100-199 (already running): Direct `mcCntlCycleStart()`
- MDI tab active: Calls `scr.ExecMdi()`
- Otherwise: `mcCntlCycleStart()`

**Note:** Wrapped in `pcall()` for error handling

---

#### `RunFromHere()`
**Purpose:** Enables starting a program from a selected line with full machine state reconstruction.

**Called by:** `CycleStart()` when selected line > 1

**Behavior:**
1. **Canned Cycle Detection** - Scans backwards for G81-G89; if found, adjusts start line to cycle beginning
2. **State Collection** - Scans backwards from start line to collect:
   - Tool number (Txx)
   - Spindle speed and direction (Sxxxx, M3/M4/M5)
   - Feed rate (Fxxxx)
   - Coolant (M7/M8/M9)
   - Work offset (G54-G59)
   - Last X, Y, Z positions
3. **Preview Dialog** - Shows collected state, asks for confirmation
4. **Machine Preparation** (if confirmed):
   - Tool change if needed
   - Apply work offset
   - Start spindle
   - Rapid to XY position
   - Optional: Plunge to Z (with confirmation)
5. **Execution** - Jumps to line and starts

**Returns:** `true` if cancelled, `false` to continue with cycle start

---

#### `CycleStop()`
**Purpose:** Stop current operation and reset modal states.

**Behavior:**
1. Call `mc.mcCntlCycleStop()`
2. Stop spindle
3. Reset dangerous modals: `G20 G17 G90 G67 G80 G40 G49 G94 G97 G50 M5 M9`
4. Clear any pending coroutine (`wait = nil`)

---

#### `RefAllHome()`
**Purpose:** Home all axes, then move to machine zero. **Must be called via `RunWithPLC(RefAllHome)`.**

---

#### `MachinePark()`
**Purpose:** Rapid to park position (X min+1, Y max-1) at safe Z height.

---

#### `ReturnToMachineZero()`
**Purpose:** Rapid to machine zero via safe Z first.

---

### Position Management

#### `RememberPosition()`
**Purpose:** Save current machine position to profile for later recall.

**Saves:** Machine X, Y, Z and timestamp to `SavedPositions.default` section.

---

#### `ReturnToPosition()`
**Purpose:** Return to previously saved position.

**Behavior:** Safe Z first, then XY, then Z.

---

#### `GoToWorkZero()`
**Purpose:** Rapid to work X0 Y0 (no Z movement).

---

### Jog Control

#### `InitializeJog()`
**Purpose:** Set default jog rates and accelerations for X, Y, Z.

**Defaults:** Rate=10, Accel=15 (X/Y), Accel=10 (Z)

---

#### `SyncMPG()`
**Purpose:** Monitor for jog rate/increment changes and sync all axes. Called by PLC every cycle.

**Behavior:**
1. Tracks rate for axes 0-2 and MPG0 increment in `state` table
2. When any axis rate or increment changes, calls `SyncAllAxes()` to apply to all axes
3. Updates UI slider when rate changes

**Safety Feature:** Ignores 100% rate to prevent jog rate corruption from shift-jog bug.

---

#### `SyncAllAxes(rate, increment)`
**Purpose:** Apply rate and/or increment to all enabled axes (0-2).

**Parameters:**
- `rate` - New jog rate percentage (or `nil` to skip)
- `increment` - New jog increment (or `nil` to skip)

---

#### `ButtonJogModeToggle()`
**Purpose:** Toggle between continuous and incremental jog modes.

---

### Spindle Control

#### `ToggleSpindle()`
**Purpose:** Toggle spindle with RPM dialog.

**Dialog Options:**
- RPM (0-24000)
- Reverse checkbox

---

#### `SpinCW()` / `SpinCCW()`
**Purpose:** Start spindle CW/CCW or stop if running.

---

### Tool Management

#### `DeployVirtual(toolName, action)`
**Purpose:** Deploy or retract virtual tools (probe T90, laser T91).

**Parameters:**
- `toolName`: `"probe"` or `"laser"` (case-insensitive)
- `action`: `"deploy"`, `"retract"`, or `nil` for toggle

**Tool Mapping:**
| Name | Tool Number |
|------|-------------|
| `probe` | T90 |
| `laser` | T91 |

**Usage:** `DeployVirtual("probe")` toggles probe; `DeployVirtual("laser", "deploy")` deploys laser

---

#### `SafeRetractVirtual()`
**Purpose:** Emergency retract of virtual tools without M6 (used when machine disabled).

**Behavior:** Only acts if current tool >= 90. Directly sets output signals low:
- OUTPUT1 (Laser deploy)
- OUTPUT7 (Probe deploy)
- OUTPUT9 (Laser fire)
- Clears `ESS/Laser/Test_Mode_Activate`
- Sets current tool to 0

---

#### `MeasureCurrentTool()`
**Purpose:** Execute M310 to measure current tool height (requires idle state).

---

#### `SelectToolDialog()`
**Purpose:** Show tool selection dialog and execute tool change.

**Behavior:**
1. Builds list of tools with descriptions (T1-T99) plus T0
2. Shows single-choice dialog
3. If selection made and machine idle: executes `Txx M6`

---

#### `SpindleToolDialog()`
**Purpose:** Handle spindle tool detection with settle timer.

**Flow:**
1. Button LOW → close clamp, start settle timer
2. Timer fires → calls `SpindleToolCheckAfterSettle()`
3. Tool present → show selection dialog
4. Button HIGH → open clamp, cancel pending checks

---

#### `SpindleToolCheckAfterSettle()`
**Purpose:** Called by timer after spindle clamp settles. Checks tool presence and shows selection dialog.

**Behavior:**
1. Verify button still LOW (user hasn't released)
2. Check INPUT17 (tool presence sensor)
3. If no tool: set T0, apply G49
4. If tool present: show tool selection dialog, apply G43 Hxx

**Uses:** PV 550 to remember last selected tool

---

#### `SpindleToolPresenceChanged(state)`
**Purpose:** Handle INPUT17 (tool presence sensor) state changes.

**Behavior:** If tool removed while dialog is open, closes dialog and sets T0.

---

### Override Control

#### `SetFRO(value)` / `SetRRO(value)` / `SetSRO(value)`
**Purpose:** Set feed rate / rapid rate / spindle rate override and sync UI slider.

---

### Auxiliary Control

#### `ToggleAuxOutput(target, action)`
**Purpose:** Toggle auxiliary outputs.

**Parameters:**
- `target`: `"dustCollect"`, `"dustBoot"`, `"vacRear"`, `"vacFront"`
- `action`: `"enable"`, `"disable"`, or `nil` for toggle

**Output Mapping:**
| Target | Signal |
|--------|--------|
| `dustCollect` | OUTPUT4 |
| `dustBoot` | OUTPUT3 |
| `vacRear` | OUTPUT5 |
| `vacFront` | OUTPUT6 |

---

#### `ToggleAutomation(target, action)`
**Purpose:** Toggle automation modes (auto-enable outputs when program runs).

**Parameters:**
- `target`: `"dustAuto"`, `"vacAuto"`, `"bootAuto"`
- `action`: `"enable"`, `"disable"`, or `nil` for toggle

**Output Mapping:**
| Target | Signal |
|--------|--------|
| `dustAuto` | OUTPUT50 |
| `vacAuto` | OUTPUT51 |
| `bootAuto` | OUTPUT52 |

---

#### `DustAutomation()`
**Purpose:** Automatic dust collection/vacuum/boot control based on program run state.

**Called by:** `SigLib[OSIG_RUNNING_GCODE]` when running state changes

**Behavior:**
- **Program file starts** (state 100-199, not MDI): Enable dust collector if `dustAuto` enabled
- **Program file stops**: Disable dust/boot/vacuums based on their respective auto modes

**Uses:** PV 405 to track "was in file run" state (prevents re-triggering)

**Note:** Only triggers for file runs (state 100-199), not MDI or scripts (200-299)

---

#### `ToggleSoftLimits(action)`
**Purpose:** Enable/disable/toggle soft limits.

**Parameter:** `"enable"`, `"disable"`, or `nil` for toggle

---

#### `KeyboardInputsToggle(action)`
**Purpose:** Enable/disable keyboard inputs and keyboard jog.

**Parameter:**
- `"enable"` - Enable keyboard inputs
- `"disable"` - Disable keyboard inputs
- `"initialize"` - Toggle twice (used at startup to sync state)
- `nil` - Toggle current state

**Affects:** `Keyboard/Enable` and `Keyboard/EnableKeyboardJog` I/O registers

---

#### `ToggleHeightOffset()`
**Purpose:** Toggle tool height offset (G43/G49).

**Behavior:**
- If G49 active: Apply G43 with current tool number
- If G43 active: Cancel with G49

---

#### `ToggleLaserEnable(action)`
**Purpose:** Enable/disable laser test mode.

**Parameter:** `"enable"`, `"disable"`, or `nil` for toggle

**Uses:** `ESS/Laser/Test_Mode_Activate` register

---

#### `SetLaserPower(power)`
**Purpose:** Set laser power for test mode.

**Parameter:** Power level 1-100 (clamped to range)

**Uses:** `ESS/Laser/Vector/GCode_PWM_Percentage` register

---

### Work Coordinates

#### `SetWorkOffset(value)`
**Purpose:** Set work offset (G54-G59 or G54.1 Pxx).

**Parameter Encoding:**
- `54` → G54
- `55` → G55
- `56` through `59` → G56-G59
- `54.01` → G54.1 P1
- `54.02` → G54.1 P2
- `54.50` → G54.1 P50

**Usage:** `SetWorkOffset(54.01)` sets G54.1 P1

---

#### `GetFixOffsetVars()`
**Purpose:** Get pound variables for current fixture offset.

**Returns:** `poundVarX, poundVarY, poundVarZ, fixNum, fixString`

**Variable Mapping:**
- G54-G59: PV 5221-5321 (20 apart per fixture)
- G54.1 P1-P50: PV 7001-7981 (20 apart)
- G54.1 P51+: PV 8001+ (20 apart)

**Example:** For G55, returns `5241, 5242, 5243, 2, "G55"`

---

#### `SetCenter(axis)`
**Purpose:** Two-point centering - first call stores position, second call calculates center and sets datum.

**Parameter:** `"X"` or `"Y"` (case-insensitive)

**Usage:**
1. Jog to first edge, call `SetCenter("X")` → stores position in PV 300
2. Jog to opposite edge, call `SetCenter("X")` → calculates center, sets work zero, clears PV 300

**Uses:** PV 300 (X) or PV 301 (Y) for temporary storage

---

#### `CancelG68()`
**Purpose:** Cancel G68 rotation with confirmation dialog.

---

### UI State Management

#### `UIStates` Table
**Purpose:** Declarative UI state configuration for buttons and LEDs.

**Structure:**
```lua
UIStates = {
    buttonName = {
        check = function(inst) or {pvar=, signal=, io=},
        disabled = function(inst),  -- optional
        flashFreq = number,         -- optional, cycles per flash
        states = {
            on = {bg = "#color", fg = "#color", label = "text"},
            off = {...},
            disabled = {...},
            on_flash = {...}  -- optional flash alternate
        }
    }
}
```

---

#### `UpdateUIStates()`
**Purpose:** Update all UI elements based on `UIStates` configuration.

**Called:** Every 100ms by UI timer

---

#### `UpdateDynamicLabels()`
**Purpose:** Update labels that change frequently.

**Updates:**
- Cycle time
- Tool preview
- Machine state
- G68 rotation angle
- Override slider enable states
- Jog rate sync

---

### System Settings

#### `SYSTEM_SETTINGS` Table
**Purpose:** Configuration for system settings dialog.

**Sections:**
- Touch Probe (T90): PV 511-520
- Laser (T91): PV 521-522
- Tool Change: PV 523-525
- Height Setter: PV 526-533
- Keytop Replacement: PV 540-541

---

#### `LoadSystemSettings()`
**Purpose:** Load all system settings from profile into pound variables.

**Called:** At startup

---

#### `SystemSettings()`
**Purpose:** Display system settings dialog with edit capability.

---

## Dialog System (IPC with ProbeScripts)

### Overview

The dialog system enables ProbeScripts.mcs (running in macro context) to display wxWidgets dialogs (which require screen context). This is accomplished via file-based IPC.

### Communication Flow

```
ProbeScripts.ShowDialog()
    │
    ├─► Serialize fields to dialog_fields_N.lua
    ├─► Write request to dialog_request_N.txt
    ├─► Set iRegs0/DialogType = "SHOW_DIALOG"
    ├─► Set iRegs0/DialogRequest = 1
    │
    ▼ (PLC detects flag)

PLC.lua
    │
    ├─► Calls ProcessDialogRequest()
    │
    ▼

ProcessDialogRequest()
    │
    ├─► Calls ShowDialogScreen()
    │
    ▼

ShowDialogScreen()
    │
    ├─► Read fields from dialog_fields_N.lua
    ├─► Read params from dialog_request_N.txt
    ├─► Build and display wxWidgets dialog
    ├─► Write results to dialog_response_N.txt
    ├─► Set iRegs0/DialogResponse = 1
    │
    ▼

ProbeScripts.ShowDialog() (resumes)
    │
    ├─► Read dialog_response_N.txt
    ├─► Save values to profile
    └─► Return results to caller
```

### Dialog Registers

| Register | Purpose |
|----------|---------|
| `iRegs0/DialogRequest` | Request flag (0/1) |
| `iRegs0/DialogResponse` | Response flag (0/1) |
| `iRegs0/DialogType` | Dialog type string |
| `iRegs0/DialogSequence` | Sequence number (prevents race conditions) |
| `iRegs0/DialogCallback` | Callback request flag |
| `iRegs0/DialogCallbackType` | Type of callback |
| `iRegs0/DialogCallbackData` | Callback data |
| `iRegs0/DialogCallbackResult` | Callback result |

### Temp Files

**Location:** `C:\Mach4Hobby\Profiles\BLP\Temp\`

| File Pattern | Purpose |
|--------------|---------|
| `dialog_fields_N.lua` | Serialized field definitions |
| `dialog_request_N.txt` | Request parameters |
| `dialog_response_N.txt` | Dialog results |

---

#### `InitDialogSystem()`
**Purpose:** Create dialog registers if they don't exist.

---

#### `CleanupTemp()`
**Purpose:** Remove orphaned dialog temp files on startup.

---

#### `ProcessDialogRequest()`
**Purpose:** Handle dialog requests from PLC. Called when `DialogRequest` flag is set.

---

#### `ShowDialogScreen(inst)`
**Purpose:** Build and display dynamic wxWidgets dialog from serialized field definitions.

**Supported Field Types:**
- `instructions` - Read-only text
- `separator` - Horizontal line
- `number` - Numeric input with validation
- `text` - Text input
- `checkbox` - Boolean toggle
- `radio` - Radio button group
- `choice` - Dropdown selection
- `direction` - 4-way direction picker (+X/-X/+Y/-Y)
- `grid` - Multi-column layout
- `section` - Grouped fields with border
- `description` - Italic informational text

---

### Deferred G-Code Loading

#### `ProcessDeferredGCode()`
**Purpose:** Load G-code files from macros (which can't load directly due to error -18).

**Flow:**
1. Macro writes file path to `DeferredGCode.txt`
2. PLC calls this function when idle
3. Function reads path, deletes marker, loads file, starts cycle

---

## Utility Functions

#### `SecondsToTime(seconds)`
**Purpose:** Convert seconds to HH:MM:SS.ss format.

---

#### `ProbeCrashCheck()`
**Purpose:** E-stop if probe signal high while T90 active (probe crash detection).

---

#### `OpenDocs()`
**Purpose:** Open Mach4 docs folder in Explorer.

---

#### `CheckAirPressure()`
**Purpose:** E-stop if air pressure low (INPUT6).

---

#### `ButtonEnable()`
**Purpose:** Enable/disable axis buttons based on axis configuration.

---

#### `DebugExecute()`
**Purpose:** Execute DebugExecute.lua for development testing.

---

#### `RunWithPLC(func)`
**Purpose:** Run a coroutine that can be resumed by PLC when machine becomes idle.

**How it works:**
1. Creates a coroutine from `func` and stores it in global `wait`
2. Immediately resumes the coroutine (runs until first `coroutine.yield()`)
3. PLC checks `wait` each cycle - if machine is idle and coroutine is suspended, it resumes

**Usage:**
```lua
RunWithPLC(RefAllHome)  -- RefAllHome will yield after starting homing, resume when idle
```

**Writing compatible functions:** Function must call `coroutine.yield()` at points where it should wait for idle state.

---

#### `RecoverThenReset()`
**Purpose:** Recover from file hold, then reset.

---

#### `GetPLCStats(execTime)`
**Purpose:** Collect and report PLC execution time statistics (every 10 seconds).

---

## UI Timer

The UI timer runs every 100ms and calls:
1. `UpdateUIStates()` - Update button/LED states
2. `UpdateDynamicLabels()` - Update labels
3. `ButtonEnable()` - Update button enable states

```lua
UIUpdateTimer = wx.wxTimer()
UIUpdateTimer:Connect(wx.wxEVT_TIMER, function(event)
    UIFlashCounter = (UIFlashCounter + 1) % 1000
    UpdateUIStates()
    UpdateDynamicLabels()
    ButtonEnable()
end)
UIUpdateTimer:Start(100)
```

---

## Error Handling

- `CycleStart()` wrapped in `pcall()` with error logging
- Dialog system uses sequence numbers to prevent race conditions
- Probe crash detection with immediate E-stop
- Air pressure monitoring with E-stop

---

## Dependencies

| File | Purpose |
|------|---------|
| `ButtonScripts.lua` | Button-triggered functions too large for ScreenLoad (`TargetMove()`, `LaserRaster()`) |
| `PLC.lua` | Runs every cycle; calls `SyncMPG()`, `ProbeCrashCheck()`, `ProcessDeferredGCode()`, `ProcessDialogRequest()` |
| `ProbeScripts.mcs` | Probing macro functions (IPC client for dialogs) |
| `mcRegister.lua` | Register creation/management |
| `mcErrorCheck.lua` | Error checking utilities |
| `mcTrace.lua` | Debug tracing |
