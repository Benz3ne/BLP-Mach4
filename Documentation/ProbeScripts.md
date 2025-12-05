# ProbeScripts.mcs - Comprehensive Documentation

## Overview

`ProbeScripts.mcs` is a Lua module for Mach4 CNC control software that provides a complete touch probe system. It includes core probing functions, dialog management, tool change automation, and specialized probing routines for piano key measurement.

**Location:** `C:\Mach4Hobby\Profiles\BLP\Macros\ProbeScripts.mcs`

---

## Architecture

### Module Structure
```lua
ProbeScripts = {}  -- Global table containing all functions
```

All functions are accessed via `ProbeScripts.FunctionName()`.

### Cross-File Interactions

| File | Interaction |
|------|-------------|
| **PLC.lua** | Monitors `iRegs0/DialogRequest` register each cycle. When set to 1, calls `ProcessDialogRequest()` in ScreenLoad.lua to display the dialog |
| **ScreenLoad.lua** | Contains `ProcessDialogRequest()` which reads the dialog configuration files and calls `ShowDialogScreen()` to render the wxWidgets dialog |
| **Temp files** | Dialog system uses file-based IPC via `C:\Mach4Hobby\Profiles\BLP\Temp\` for passing field definitions and responses between macro and screen contexts |

---

## Pound Variables (PVs) Reference

### Probe Diameter Calibration (PV 511-515)
| PV | Description |
|----|-------------|
| 511 | +X probe diameter |
| 512 | -X probe diameter |
| 513 | +Y probe diameter |
| 514 | -Y probe diameter |
| 515 | Z probe offset (effective Z diameter) |

### Probe Configuration (PV 516-520)
| PV | Description |
|----|-------------|
| 516 | Fast feed rate for probing |
| 517 | Slow feed rate (second tap) |
| 518 | Maximum probe travel distance |
| 519 | Backoff distance between taps |
| 520 | Default final retract distance |

### Tool Change & Height Measurement (PV 523-533)
| PV | Description |
|----|-------------|
| 523 | Safe Z height for tool changes |
| 524 | Y pullout distance from tool pocket |
| 525 | Approach feed rate |
| 526 | Probe station X position (machine coords) |
| 527 | Probe station Y position (machine coords) |
| 528 | Reference surface Z (spindle rim position) |
| 529 | Max probe depth for height measurement |
| 530 | Height probe fast feed |
| 531 | Height probe slow feed |
| 532 | Height probe retract distance |
| 533 | Spindle X offset for T0 probing |

### Center Finding (PV 300-301)
| PV | Description |
|----|-------------|
| 300 | Stored X edge **machine** position for Set/Center (0 = no edge stored) |
| 301 | Stored Y edge **machine** position for Set/Center (0 = no edge stored) |

### Probe Results (PV 391-393)
| PV | Description |
|----|-------------|
| 391 | Last probe machine position |
| 392 | Last probe work position |
| 393 | Probe success flag (0 or 1) |

### System State (PV 499, 540-541, 550)
| PV | Description |
|----|-------------|
| 499 | M6 tool change in-progress flag (1 = in progress, 0 = complete) |
| 540 | Left bore X position in **machine** coordinates (keytop fixture) |
| 541 | Left bore Y position in **machine** coordinates (keytop fixture) |
| 550 | Current tool number (updated by M6_ToolChange) |

---

## Core Functions

### ProbeScripts.ProbeXYZ()

**The fundamental probing function.** All other probe functions ultimately call this.

```lua
function ProbeScripts.ProbeXYZ(inst, direction, fastFeed, backoff, slowFeed, maxTravel, finalRetract, setDatum)
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| inst | number | Mach4 instance |
| direction | number | 1=+X, 2=-X, 3=+Y, 4=-Y, 5=-Z |
| fastFeed | number | First probe feed rate (IPM) |
| backoff | number | Distance to retract after first strike |
| slowFeed | number | Second probe feed rate (0 = single tap) |
| maxTravel | number | Maximum probe travel before giving up |
| finalRetract | number | -1 = return to start, 0 = stay, >0 = retract this amount |
| setDatum | number | 1 = zero work offset at edge, 0 = don't |

**Returns:** `machineEdge, workEdge, probeSuccess`

**Behavior:**
1. Validates probe isn't already triggered
2. Gets per-direction probe diameter from PVs 511-515
3. Clamps travel to soft limits
4. Executes G31.1 fast probe
5. If `slowFeed > 0`: retracts `backoff`, does slow G31.1
6. Handles final retract based on `finalRetract` value
7. Applies probe radius compensation to get true edge position
8. Optionally sets work offset if `setDatum == 1`
9. Updates PVs 391, 392, 393 with results

**Quirks:**
- Includes automatic "unstick" logic if probe stays triggered after retract
- Probe diameter compensation varies by direction (allows calibration for non-spherical tips)
- Travel is clamped to 0.05" inside soft limits

---

### ProbeScripts.Probe()

**Simplified wrapper around ProbeXYZ.** Maps legacy parameters to ProbeXYZ format.

```lua
function ProbeScripts.Probe(inst, direction, setDatum, returnToStart, maxTravel, fastFeed, singleTap, finalRetract)
```

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| direction | number | required | 1=+X, 2=-X, 3=+Y, 4=-Y, 5=-Z |
| setDatum | boolean | false | Zero work offset at edge |
| returnToStart | boolean | false | Return to start position after probe |
| maxTravel | number | PV 518 | Maximum probe distance |
| fastFeed | number | PV 516 | Fast probe feed rate |
| singleTap | boolean | false | Skip slow second tap |
| finalRetract | number | PV 520 | Custom retract distance |

**Returns:** `edgeValue, success` (edgeValue is work coordinate, or 0 if setDatum)

**Quirks:**
- When `returnToStart = true`, sets `finalRetract = -1` internally
- When `setDatum = true`, always returns 0 for edgeValue

---

### ProbeScripts.ProtectedMove()

**Collision-detecting move using probe signal.** Uses G31.1 for collision detection.

```lua
function ProbeScripts.ProtectedMove(inst, moveType, X, Y, Z, feedrate)
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| moveType | string | "mach" = machine coords, "work" = work coords, "inc" = incremental |
| X, Y, Z | number/nil | Target position (nil = don't move this axis) |
| feedrate | number | Feed rate (default 100) |

**Returns:** `true` on success, `false` on collision

**Behavior:**
1. Stores starting machine position
2. Builds G31.1 move command (only includes axes with significant movement > 0.0001")
3. Executes move, checking probe signal
4. If probe triggers (collision):
   - Logs to `C:\Mach4Hobby\Profiles\BLP\Logs\ProtectedMove_Failures.txt`
   - Returns to start position
   - Retries at half speed
   - If second attempt fails, returns false

**Quirks:**
- Uses ISIG_PROBE1 signal for collision detection
- Minimum retry feedrate is 10 IPM
- Logs include both work and machine coordinates

---

### ProbeScripts.ProbeOutside()

**Probes the outside edge of a feature.** Moves out, drops down, probes back in.

```lua
function ProbeScripts.ProbeOutside(inst, direction, outDistance, zDown)
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| direction | number | 1=+X, 2=-X, 3=+Y, 4=-Y (direction to move OUT) |
| outDistance | number | Distance to move out from current position |
| zDown | number | Distance to drop Z before probing |

**Returns:** Edge work coordinate, or `nil` on failure

**Behavior:**
1. Stores starting machine position (all axes)
2. Uses `ProtectedMove()` to move out (clamped to soft limits)
3. Uses `ProtectedMove()` to drop Z
4. Probes BACK toward original position (opposite direction)
5. Returns to starting position via Z up, then X/Y

**Quirks:**
- Probe direction is opposite of move direction (move +X, probe -X)
- Returns to start via machine coordinates for reliability
- Uses 0.25" retract after probe hit

---

### ProbeScripts.MoveToCenter()

**Moves to work zero handling G68 rotation.**

```lua
function ProbeScripts.MoveToCenter(inst, moveX, moveY)
```

**Behavior:**
1. Checks for active G68 rotation (PV 4016)
2. If G68 active: saves rotation parameters, cancels G68
3. Executes G90 G1 move to X0/Y0 as specified
4. Restores G68 if it was active

**Quirks:**
- Essential when G68 rotation would cause "move to 0,0" to go to wrong physical location
- Uses F200 for the move

---

### ProbeScripts.CheckG68Rotation()

**Detects and handles active G68 rotation before probing.**

```lua
function ProbeScripts.CheckG68Rotation(inst)
```

**Returns:**
- `"no_rotation"` - G68 not active
- `"cancel_g68"` - User chose to cancel G68
- `"keep_g68"` - User chose to keep G68
- `nil` - User cancelled dialog

**Behavior:**
Shows 3-button dialog when G68 is active:
- "Cancel G68 and Run" → Executes G69, returns "cancel_g68"
- "Keep G68 and Run" → Returns "keep_g68"
- "Cancel" → Returns nil

---

### ProbeScripts.CheckProbeDeployed()

**Verifies T90 probe is the current tool.**

```lua
function ProbeScripts.CheckProbeDeployed(inst)
```

**Returns:**
- `true` if T90 is already active
- `false` if user declined tool change
- `nil` if user accepted tool change (tool change was performed)

**Behavior:**
1. Checks `mc.mcToolGetCurrent(inst)`
2. If T90, returns `true`
3. If not T90, prompts user with Yes/No dialog
4. If user selects Yes: executes `T90`, calls `ProbeScripts.M6_ToolChange()`, returns `nil`
5. If user selects No: returns `false`

**Note:** Callers use `if not ProbeScripts.CheckProbeDeployed(inst) then return end` which aborts on both `false` and `nil`. This is intentional - after a tool change, the machine retracts to Z-0.050, so the user must reposition before running the probe routine again.

---

## Dialog System

### ProbeScripts.ShowDialog()

**Creates and displays a modal dialog for user input.** This is a sophisticated system that communicates with ScreenLoad.lua via file-based IPC.

```lua
function ProbeScripts.ShowDialog(inst, title, fields, profileSection, options)
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| title | string | Dialog window title |
| fields | table | Array of field definitions |
| profileSection | string | INI section for persistence |
| options | table | Optional settings (see below) |

**Options Table:**
- `width` - Dialog window width in pixels
- `buttonLabels.ok` - Custom OK button text
- `buttonLabels.cancel` - Custom Cancel button text

**Returns:** Table of results (key/value pairs), or `nil` if cancelled

**Field Types:**

| Type | Properties | Description |
|------|------------|-------------|
| `instructions` | text, tooltip | Read-only text (smaller font) |
| `separator` | none | Horizontal line |
| `number` | key, label, default, min, max, tooltip, isInteger, decimals, validateMsg, width, persist | Numeric input |
| `text` | key, label, default, tooltip, validate, persist | Text input (`validate` is a function returning `true` or `false, errorMsg`) |
| `checkbox` | key, label, default, tooltip, persist | Boolean toggle (default 0 or 1) |
| `radio` | key, label, options, columns, default, tooltip, persist | Single selection from options array |
| `choice` | key, label, options, default, tooltip, persist | Dropdown selection |
| `direction` | key, label, default, tooltip, persist | 4-way direction picker (0=+X, 1=-X, 2=+Y, 3=-Y) |
| `grid` | columns, spacing, children | Multi-column layout container |
| `section` | label, children | Grouped fields with border |
| `description` | key, text | Italic informational text |

**Common Field Properties:**
- `key` - Identifier for result retrieval and profile persistence
- `persist` - Set to `false` to disable automatic profile save/load (default: `true`)
- `width` - Control width in pixels (for `number` fields)

**Persistence:**
- Fields with `key` are automatically saved to/loaded from profile INI under `profileSection`
- Uses `mc.mcProfileGetDouble/Int/String` and `mc.mcProfileWriteDouble/Int/String`

**Communication Flow:**
1. `ShowDialog()` serializes fields to `dialog_fields_N.lua`
2. Writes request parameters to `dialog_request_N.txt`
3. Sets `iRegs0/DialogType = "SHOW_DIALOG"`
4. Sets `iRegs0/DialogRequest = 1`
5. PLC detects flag, calls `ProcessDialogRequest()`
6. `ProcessDialogRequest()` calls `ShowDialogScreen()` in ScreenLoad.lua
7. wxWidgets dialog is displayed
8. Results written to `dialog_response_N.txt`
9. Sets `iRegs0/DialogResponse = 1`
10. `ShowDialog()` reads response file, cleans up, returns results

**Quirks:**
- Files are in `C:\Mach4Hobby\Profiles\BLP\Temp\`
- Sequence number prevents race conditions
- `wx.wxSafeYield()` keeps UI responsive while waiting

---

### ProbeScripts.DisplayResults()

**Displays probe results with flexible formatting.**

```lua
function ProbeScripts.DisplayResults(inst, results, title, options)
```

**Options:**
- `statusFormat` - Custom format string with `{key}` placeholders
- `primaryKeys` - Array of keys to show in status bar
- `showDetails` - Show detailed wxMessageBox
- `hideKeys` - Table of keys to exclude from details
- `logFile` - Path to append results
- `profileKey` - Save to profile under "ProbeResults"

---

## Tool Change System

### ProbeScripts.M6_ToolChange()

**Complete automatic tool changer implementation.**

```lua
function ProbeScripts.M6_ToolChange(inst)
```

**Tool Categories:**
- **Physical tools (T1-T89):** Stored in pockets, picked up by spindle
- **Virtual tools (T90+):** No physical pickup, just apply G43 offsets. T90 (probe) and T91 (laser) have pneumatic deployment; others only apply offsets
- **T0:** Clear tool / bare spindle

**Tool Pocket Data (from tool table):**
- `XToolChange`, `YToolChange`, `ZToolChange` - Pocket position
- `AutoProbe` - Flag to auto-measure height after pickup

**Behavior:**
1. Sets PV 499 = 1 (M6 in-progress flag)
2. Saves FRO/RRO, sets both to 100%
3. Saves dust boot state, raises boot
4. Handles same-tool case (just sync H offset)
5. For virtual tools: deploys via OUTPUT1 (laser) or OUTPUT7 (probe)
6. For physical tools:
   - Drops current tool to pocket
   - Picks up new tool
   - Waits for tool present signal (INPUT17)
   - Calls M310 if AutoProbe flag set
7. Restores FRO/RRO, clears PV 499

**Signals Used:**
| Signal | Purpose |
|--------|---------|
| OUTPUT1 | Laser deploy |
| OUTPUT2 | Spindle clamp (0=locked, 1=open) |
| OUTPUT3 | Dust boot (0=up, 1=down) |
| OUTPUT7 | Probe deploy |
| OUTPUT9 | Laser fire |
| OUTPUT52 | Auto-boot flag |
| INPUT13 | Spindle running |
| INPUT17 | Tool present |

**Quirks:**
- Virtual tools get G43 offset automatically (includes X/Y from tool table)
- Same tool change still applies H offset (ensures sync)
- Boot auto-deploys only during file runs (machState 100-199)

---

### ProbeScripts.M310_ProbeToolHeight()

**Measures and stores tool height using fixed probe station.**

```lua
function ProbeScripts.M310_ProbeToolHeight(inst)
```

**Behavior:**
1. Gets probe station position from PV 526-527
2. Adjusts position based on tool type:
   - T0: Uses spindle X offset from PV 533
   - T90+: Applies tool table X/Y offsets
   - Others: Uses `ProbeXOffset` from tool table
3. Executes G49 (cancel H offset) before probing
4. Two-tap probe: fast (PV 530), air blast, slow (PV 531)
5. Calculates height relative to spindle rim (PV 528)
6. For T0: Sets PV 528 (establishes reference)
7. For others: Saves to tool table, applies G43

**Quirks:**
- Air blast (OUTPUT8) cleans probe between taps
- Laser (T91) state is saved/restored (ESS disables during G31)
- T0 height is always 0 (it IS the reference)

---

## User-Facing Probe Routines

### ProbeScripts.ProbeZ()

Simple Z-axis surface probe with datum setting option.

**Dialog Options:**
- Set Z Datum at Surface
- Display Probed Position

---

### ProbeScripts.ProbeXY()

Single-edge XY probe with Set/Center mode.

**Dialog Options:**
- Direction picker (+X/-X/+Y/-Y)
- Action: Set Datum / Set/Center / Show Position

**Set/Center Mode:**
Uses PV 300 (X) or PV 301 (Y) to store first edge position. Second call calculates center and sets datum.

---

### ProbeScripts.ProbeInsideCenter()

Finds center of bore/pocket by probing opposing edges.

**Dialog Options:**
- Axes: X Only / Y Only / X and Y
- Move to Center checkbox

---

### ProbeScripts.ProbeOutsideCenter()

Finds center of boss/stock by probing outside edges.

**Dialog Options:**
- Traverse height, Z drop distance
- X and Y expected widths
- Set Z Datum at Surface
- Move to Center checkbox

---

### ProbeScripts.FindAngle()

Probes two points to calculate part angle, optionally applies G68 rotation.

**Dialog Options:**
- Probe direction
- Traverse direction (must be perpendicular)
- Traverse distance

**Quirks:**
- Validates perpendicularity of directions
- Calculates angle to nearest machine axis (+X/-X/+Y/-Y)
- Offers to apply G68 rotation to align part

---

## Calibration Functions

### ProbeScripts.CalibrateProbeDiameter()

Calibrates per-direction probe diameters using a concentric bore/boss fixture.

**Process:**
1. User positions probe in bore
2. Probes bore (inside) in all 4 directions
3. Moves to center, lifts Z
4. Probes boss (outside) in all 4 directions
5. Calculates individual probe diameters for each direction
6. Saves to PVs 511-514 and profile

**Requirements:**
- Concentric bore and boss
- Known reference diameters

---

### ProbeScripts.CalibrateProbeOffset()

Calibrates T90 XY offsets using a bore centered at work 0,0.

**Process:**
1. Zeros T90 offsets in tool table
2. Probes bore center iteratively (X, Y, X again)
3. Final position = probe offset from spindle
4. Saves offsets to T90 tool table

**Prerequisites:**
- Spindle must be manually centered over bore
- Work 0,0 set at bore center

---

### ProbeScripts.SingleTapCalibrate()

Measures single-tap vs double-tap offset for high-speed probing.

**Returns:** Table of calibration offsets by direction

---

### ProbeScripts.ProbeToolPosition()

Probes a tool holder to measure and save pocket position.

**Dialog Options:**
- Tool Number (1-89, virtual tools not allowed)

**Hardcoded Parameters:**
- Pull stud width: 1.0"
- Traverse height: 0.2"
- Holder taper height: 2.8"
- Holder drop height: 0.1"

**Process:**
1. Probes pull stud top surface (-Z)
2. Uses `ProbeOutside()` to probe all 4 edges of pull stud
3. Calculates center from edge measurements
4. Moves probe to center
5. Calculates spindle position by subtracting T90 probe offsets
6. Calculates Z pickup height: `surfaceZ - probeHeight - taperHeight`
7. Saves to tool table: XToolChange, YToolChange, ZToolChange

**Prerequisites:**
- Probe must be positioned directly over pull stud
- T90 offsets must be calibrated (uses probe X/Y offsets to find spindle position)

---

## Specialized Functions

### ProbeScripts.ProbeKeys()

**Comprehensive piano key probing system.** Measures white key geometry for keytop replacement.

**Features:**
- Bore-based fixture alignment with G68 rotation
- Single-tap calibration with offset compensation
- Fixture ID detection via 10-bit binary holes
- Auto-detect lower/upper key set from shoulder geometry
- Per-key height measurement
- X edge probing at 6 Y positions with linearity analysis
- Extra probe points when linearity threshold exceeded
- Shoulder accessibility detection and probing

**Output:**
- CSV file with all probe data
- Report file with calibration info and fixture ID

---

### ProbeScripts.InitialKeytopTrim()

**Generates and queues G-code for initial keytop surface trimming.**

**Dialog Options:**
- Top Trim Depth (inches)
- Trim Operation: Full Trim / Top Only / Front Only

**Process:**
1. Performs bore alignment and G68 rotation (same as ProbeKeys)
2. Reads fixture ID from binary holes
3. Searches log files for matching fixture ID to get average Z height from previous ProbeKeys run
4. Calculates trim height: `avgZ - trimDepth`
5. Loads and modifies template G-code files, adjusting Z values
6. Writes combined G-code to piano folder
7. Creates deferred load marker for PLC to load file when idle

**Prerequisites:**
- Must run ProbeKeys first (needs average Z height from log)
- Front vacuum must be ON
- Must be on GCode tab (not MDI)

---

### ProbeScripts.Debug()

Development/testing function. Must be named .Debug to work.

---

## File Dependencies

| File | Purpose |
|------|---------|
| `ProbeScripts.mcs` | Main module |
| `ScreenLoad.lua` | Dialog rendering (ShowDialogScreen) |
| `PLC.lua` | Dialog request detection |
| `C:\...\Temp\dialog_*.txt/lua` | IPC files for dialog system |
| `C:\...\Logs\*.txt` | Error and probe data logging |
