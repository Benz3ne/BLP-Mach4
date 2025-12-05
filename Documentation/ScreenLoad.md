# ScreenLoad.lua - Documentation

## Overview

`ScreenLoad.lua` is the main entry point script that runs when the Mach4 screen loads. It initializes global variables, sets up the UI update timer, and loads dependent scripts.

**Location:** `C:\Users\benja\Documents\Mach4\BLP\Scripts\ScreenLoad.lua`

---

## TODO: Document the following sections

- [ ] Global variables and their purposes
- [ ] Timer setup and UI update cycle
- [ ] Script loading order and dependencies
- [ ] ShowDialogScreen() function (IPC with ProbeScripts)
- [ ] Button script integration
- [ ] Error handling patterns

---

## Quick Reference

### Globals Initialized
| Variable | Purpose |
|----------|---------|
| `pageId` | Current screen page |
| `screenId` | Current screen ID |
| `machState` | Machine state |
| `inst` | Mach4 instance handle |
| `_G.ROOT` | Scripts root path |
| `_G.SYS` | System scripts path |

### Key Functions
- `ShowDialogScreen()` - Renders wxWidgets dialogs for ProbeScripts
- UI timer callback - Periodic screen updates

---

*This document needs expansion. Add details as you work with the file.*
