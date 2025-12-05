# Mach4 Library Architecture v2.0

## Core Architecture Principles

### 1. TRUST THE SYSTEM
- **Zero defensive programming**: No redundant checks, no fallback paths, no "just in case" code
- **Single logic path**: One way to do each thing, executed correctly
- **Assume lower libraries work**: They've been tested. Trust them completely.
- **Errors propagate naturally**: Let failures bubble up to where they matter

### 2. SINGLE OWNERSHIP
- Each domain belongs to exactly ONE library
- If two libraries could handle something, one is wrong
- No overlap, no ambiguity, no shared responsibilities

### 3. STRICT DEPENDENCY HIERARCHY
```
Level 4 ──calls──> Level 3 ──calls──> Level 2 ──calls──> Level 1 ──calls──> Level 0
```
- **NEVER** call upward or sideways
- **NEVER** duplicate functionality from lower levels
- **ALWAYS** delegate downward

---

## Library Hierarchy & Responsibilities

### Level 0: Foundation (COMPLETE)
Pure Lua, zero dependencies, thoroughly tested.
- **DataLib**: Data structures and manipulation
- **FileLib**: File operations and path management
- **MathLib**: Mathematical operations and conversions
- **TimeLib**: Scheduling and time operations

### Level 1: Core Systems
Direct Mach4 API wrappers with minimal logic.

#### SignalLib (COMPLETE - Consider Enhancement)
- OWNS: ALL signal operations (read/write/monitor)
- OWNS: PVs, flags, registers
- OWNS: Signal mapping and hardware I/O

**Core Functions Used:**
```lua
mcSignalGetHandle/GetState/SetState  -- Basic signal ops
mcSignalMap/Unmap                    -- Hardware mapping
mcCntlGetPoundVar/SetPoundVar        -- Pound variables
mcRegGetHandle/GetValue/SetValue      -- Registers
```

**Consider Adding:**
```lua
mcIoGetHandle/GetState/SetState      -- I/O operations
mcIoRegister/Unregister              -- Dynamic I/O
mcSignalEnable                       -- Signal enable/disable
mcSignalWait                         -- Native signal wait
```

#### MessageLib (COMPLETE)
- OWNS: ALL output to user (logging, debug, status)
- OWNS: Log formatting and levels

**Core Functions Used:**
```lua
mcCntlSetLastError                   -- User messages
```

**Consider Adding:**
```lua
mcCntlLog/mcCntlLogEx                -- Native logging
mcCntlGetLastLogMsg                  -- Log retrieval
```

#### ProfileLib (COMPLETE)
- OWNS: ALL profile persistence (read/write)
- OWNS: Profile variable namespace

**Core Functions Used:**
```lua
mcProfileGetString/WriteString        -- Profile access
mcProfileFlush                       -- Force write
mcProfileGetName                     -- Profile info
```

---

### Level 2: Machine Interface
Machine state and control abstractions.

#### SystemLib (NEW)
- OWNS: Machine state (idle/run/hold/estop)
- OWNS: Safety interlocks and conditions
- OWNS: State persistence across sessions
- OWNS: Machine runtime tracking

**Core Functions:**
```lua
-- State Management
mcCntlGetState                      -- Machine state enum
mcCntlIsInCycle                     -- Running program?
mcCntlIsStill                       -- All motion stopped?
mcCntlEnable                        -- Enable/disable
mcCntlReset                         -- Reset after errors
mcCntlEStop                         -- Emergency stop

-- Axis State
mcAxisIsHomed                       -- Per-axis home status
mcAxisIsStill                       -- Per-axis motion check
mcAxisIsEnabled                     -- Axis enabled state

-- Safety
mcCntlFeedHold                      -- Pause motion
mcCntlFeedHoldState                 -- Feedhold active?
mcSoftLimitGetState                 -- Soft limits status
mcAxisGetSoftlimitMax/Min           -- Limit values

-- Runtime
mcCntlGetRunTime                    -- Program runtime
mcCntlGetDistToGo                   -- Distance remaining
mcMotionClearPlanner                -- Clear motion buffer
mcCntlSaveParameters                -- Save parameters
```

#### MotionLib (NEW - Split from MDILib)
- OWNS: Position management and reading
- OWNS: Jogging operations
- OWNS: Homing sequences
- OWNS: Velocity and acceleration

**Core Functions:**
```lua
-- Position
mcMotionGetPos                      -- Current position
mcMotionSetPos                      -- Override position
mcAxisGetMachinePos                 -- Machine coordinates
mcAxisGetPos                        -- Work coordinates
mcAxisSetPos                        -- Set axis position
mcMotionGetVel                      -- Current velocity

-- Homing
mcAxisHome                          -- Single axis home
mcAxisHomeAll/HomeAllEx             -- Home all axes
mcAxisHomeComplete                  -- Check completion
mcAxisSetHomeOffset                 -- Home offset

-- Jogging
mcJogVelocityStart/Stop             -- Continuous jog
mcJogIncStart/Stop                  -- Incremental jog
mcJogSetInc                         -- Jog increment
mcJogSetRate                        -- Jog speed
mcJogGetVelocity                   -- Current jog velocity
mcJogSetAccel                       -- Jog acceleration

-- Reference
mcAxisRef/RefAll                    -- Reference axes
mcAxisDeref/DerefAll                -- Dereference axes

-- Scaling
mcAxisSetScale/GetScale             -- Axis scaling
```

#### MDILib (REFOCUSED)
- OWNS: G-code execution ONLY
- OWNS: Program control (start/stop/rewind)
- OWNS: Feed rate overrides

**Core Functions:**
```lua
-- Execution
mcCntlGcodeExecuteWait              -- Synchronous G-code
mcCntlMdiExecute                    -- MDI commands
mcCntlCycleStart/Stop               -- Program control
mcCntlGcodeExecute                  -- Async G-code

-- Overrides
mcCntlGetFRO/SetFRO                 -- Feed rate override
mcCntlGetRRO/SetRRO                 -- Rapid rate override
```

#### ModalLib (NEW - Split from MDILib)
- OWNS: Modal states (G90/G91, G17/G18/G19)
- OWNS: Work coordinate systems (G54-G59)
- OWNS: Parameters and offsets

**Core Functions:**
```lua
-- Modal States
mcCntlGetModalGroup                 -- Modal groups
mcCntlGetMode                       -- G90/G91 etc

-- Parameters
mcCntlSetParameter/GetParameter     -- Parameter access
mcCntlGetParameterBit/SetParameterBit -- Bit parameters

-- Work Offsets
mcFixtureGetOffset/SetOffset        -- Work offsets
mcCntlGetOffset                     -- Active offset
mcFixtureGetCurrentIndex            -- Current fixture
mcFixtureSetCurrentIndex            -- Change fixture
```

#### DROLib (NEW)
- OWNS: ALL DRO operations
- OWNS: DRO formatting and display

**Core Functions:**
```lua
mcCntlDroRead/Write                 -- DRO access
mcCntlDroGetUseAuxPos               -- Aux position mode
mcCntlDroSetUseAuxPos               -- Set aux mode
mcCntlGetValue/SetValue             -- Generic values
```

#### UILib
- OWNS: ALL screen element updates (buttons, LEDs, labels)
- OWNS: Color/state mapping for UI elements
- Uses SignalLib for outputs, wx.* for direct UI

---

### Level 3: Operations
Complex domain-specific operations.

#### ToolLib
- OWNS: Tool table management
- OWNS: Tool change sequences (including virtual)
- OWNS: Height offset management
- OWNS: Tool life management (if enabled)

**Core Functions:**
```lua
-- Basic Tool Management
mcToolGetCurrent/SetCurrent         -- Active tool
mcCntlGetToolOffset                 -- Tool offset
mcToolGetData/SetData               -- Tool table
mcCntlToolChangeManual              -- Manual change

-- Tool Life Management (Optional)
mcTlmGetCurrentGroup                -- Tool groups
mcTlmAddOrChangeTool                -- Life tracking
mcTlmGetCountOverridePercent        -- Wear compensation
mcTlmResetToolData                  -- Reset counters
mcTlmLoadFile/SaveFile              -- Tool database
mcTlmToolIsManaged                  -- Check if managed
mcTlmToolSkip/SkipReset             -- Skip tools
```

#### ProbeLib
- OWNS: ALL probe cycles and patterns
- OWNS: Probe result calculations
- OWNS: Probe data logging

**Core Functions:**
```lua
mcCntlProbeGetStrikeStatus          -- Hit detection
mcAxisGetProbePos                   -- Strike position
mcMotionSetProbeComplete            -- Signal completion
mcCntlProbeFileOpen/Close           -- Data logging
mcCntlDryRunToLine                  -- Verify probe path
```

#### SpindleLib (NEW)
- OWNS: Spindle speed control
- OWNS: Spindle overrides
- OWNS: CSS calculations
- OWNS: Threading operations

**Core Functions:**
```lua
-- Speed Control
mcSpindleGetTrueRPM                 -- Actual RPM
mcSpindleSetCommandRPM              -- Set speed
mcSpindleSetDirection               -- CW/CCW
mcSpindleGetMotorRPM                -- Motor feedback

-- Overrides
mcSpindleGetOverride/SetOverride    -- Speed override

-- Advanced
mcSpindleWaitForSpeed               -- Wait for spinup
mcSpindleCalcCSSToRPM               -- CSS calculation
mcMotionGetThreadParams             -- Threading params
mcSpindleGetFeedbackRatio           -- Encoder ratio
```

#### LaserLib
- OWNS: Laser-specific operations (raster, vector)
- OWNS: Power/speed calculations for materials
- Uses SignalLib for laser control signals

#### DialogLib
- OWNS: ALL user dialog creation and management
- OWNS: Input validation and formatting
- Uses wx.* functions directly

---

### Level 4: Execution
Top-level orchestration and user-facing operations.

#### ButtonLib
- OWNS: ALL button press handlers
- OWNS: Complex multi-step operations triggered by buttons
- Orchestrates all lower libraries

#### EventLib
- OWNS: Non-button triggers (timers, signals, conditions)
- OWNS: Complex event sequences
- Uses TimeLib for scheduling, SignalLib for monitoring

#### ProgramLib (NEW)
- OWNS: G-code file management
- OWNS: Program state tracking
- OWNS: Cut recovery

**Core Functions:**
```lua
mcCntlLoadGcodeFile                 -- Load program
mcCntlGetGcodeLine                  -- Current line
mcCntlGetGcodeLineNbr               -- Line number
mcCntlGetGcodeLineCount             -- Total lines
mcCntlRewindFile                    -- Reset program
mcCntlCloseGCodeFile                -- Close file
mcCntlGetGcodeFileCount             -- Multi-file
mcCntlCutRecovery                   -- Recovery
```

#### SettingsLib
- OWNS: Initial machine configuration
- OWNS: Default value management
- RUNS: Once at startup
- Uses ProfileLib for persistence

---

## Implementation Rules

### 1. Function Design (10-50 lines typical)
- If shorter than 10 lines: consider consolidating
- If longer than 50 lines: probably doing too much
- Exception: Level 3-4 may have longer orchestration functions

### 2. Pattern Mining Before Building
Before writing ANY function:
1. Search legacy code for ALL instances of the pattern
2. List every location it appears
3. Identify the core abstraction and logic
4. Ensure it belongs at this level
5. Check if lower library should handle it

### 3. Downward Delegation Checklist
Before implementing anything, ask IN ORDER:
- Can a Level 0 library handle this? → Use it
- Can a Level 1 library handle this? → Use it
- Can a Level 2 library handle this? → Use it
- Can a Level 3 library handle this? → Use it

**If yes to any: DON'T REIMPLEMENT**

### 4. Upward Notification Pattern
Lower libraries don't know about higher ones:
- Use callbacks passed down
- Use status returns that higher levels poll
- Use SignalLib flags that higher levels monitor
- NEVER import or reference upward

### 5. Missing Functionality Protocol
When you discover something that belongs in a lower library:
1. STOP implementing at current level
2. Document exactly what's needed
3. Implement in the correct lower library FIRST
4. Then use it from higher level

### 6. State Management Rules
- Level 1: Reads/writes raw state (signals, profile vars)
- Level 2: Manages machine state consistency
- Level 3: Handles domain logic
- Level 4: Orchestrates final execution

### 7. Error Handling Philosophy
```lua
-- DON'T: Defensive programming
function ButtonLib.Cycle()
    local state = SystemLib.GetState()
    if state then  -- NO! Trust it returns valid state
        if state == "idle" or state == "ready" then  -- NO! One path
            -- ...
        end
    end
end

-- DO: Trust the system
function ButtonLib.Cycle()
    local state = SystemLib.GetState()  -- Trust this works
    if state == "idle" then
        MDILib.Execute("G0 X0")  -- Trust this works
    end
end
```

### 8. Exception: Mach4 API Reality
While we trust OUR libraries completely, Mach4's API may require validation:
- Probe strikes can fail mechanically
- Tool changes involve physical hardware
- Homing can fail due to switches
- For THESE cases only, check return codes

### 9. Real Usage Validation
- Level 0-2: Minimum 3 real use cases from legacy code
- Level 3-4: May handle infrequent but important operations
- No speculative "might be useful" functions

### 10. Documentation Requirements
Each library must document:
- What it OWNS (exhaustive list)
- What Mach4 functions it wraps
- What it USES (dependencies)
- What it explicitly does NOT do

---

## Migration Strategy

### Phase 1: Complete Level 1
- Enhance SignalLib with I/O functions
- Consider MessageLib logging additions
- ProfileLib is complete

### Phase 2: Implement Level 2
- SystemLib (machine state)
- MotionLib (position/jog/home)
- MDILib (execution only)
- ModalLib (modal states)
- DROLib (display values)
- UILib (screen updates)

### Phase 3: Implement Level 3
- ToolLib (tool management)
- ProbeLib (probing)
- SpindleLib (spindle control)
- LaserLib (if needed)
- DialogLib (user interaction)

### Phase 4: Implement Level 4
- ButtonLib (button handlers)
- EventLib (event sequences)
- ProgramLib (file management)
- SettingsLib (configuration)

### Phase 5: Migration
1. Update each legacy script to use new libraries
2. Remove ALL redundant code
3. Verify single ownership is maintained

---

## Functions Deliberately Ignored

These Mach4 functions are intentionally not wrapped:
- `mcPlugin*` - Plugin development only
- `mcCntl*License*` - OEM licensing
- `mcGui*`, `mcWin*` - Internal GUI framework
- `mcMotorMap*` - Low-level motor mapping
- `mcFeatureId*` - Feature management
- Most `mcDevice*` - Hardware internals

These are either too low-level, rarely used, or better accessed directly when needed.

---

## Success Metrics

A well-designed library will have:
- **Zero code duplication** with lower levels
- **Clear ownership** of its domain
- **Single execution paths** (except for Mach4 API reality)
- **Minimal line count** (leverage lower libraries)
- **Real-world justification** for every function
- **No circular or lateral dependencies**

## Remember

**TRUST YOUR LIBRARIES** - They work. Don't defend against them.

**VALIDATE MACH4** - The API can fail. Check critical operations.

**DO IT RIGHT** - One correct path, not multiple fallbacks.

**DELEGATE DOWNWARD** - Use what exists, don't recreate.

**OWN YOUR DOMAIN** - Complete ownership, no overlaps.