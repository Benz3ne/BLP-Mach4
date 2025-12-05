-- Debug script to test gcode file reading and line selection detection
local inst = mc.mcGetInstance()

mc.mcCntlSetLastError(inst, "=== GCode File Debug Test ===")

-- Test 1: Get currently loaded file path
local filePath = mc.mcCntlGetGcodeFileName(inst)
mc.mcCntlSetLastError(inst, string.format("Loaded file: %s", filePath or "NONE"))

-- Test 2: Get selected line number
local selectedLine = mc.mcCntlGetGcodeLineNbr(inst)
mc.mcCntlSetLastError(inst, string.format("Selected line: %d", selectedLine))

-- Test 3: Get total line count
local totalLines = mc.mcCntlGetGcodeLineCount(inst)
mc.mcCntlSetLastError(inst, string.format("Total lines: %d", totalLines))

-- Test 4: Read first 20 lines to detect work offset
if filePath and filePath ~= "" then
    mc.mcCntlSetLastError(inst, "Scanning for work offset...")
    local workOffsetFound = nil

    for i = 0, math.min(19, totalLines - 1) do
        local line = mc.mcCntlGetGcodeLine(inst, i)
        if line then
            -- Check for G54-G59 or G54.1
            local g54to59 = line:match("G5[4-9]")
            local g54p = line:match("G54%.1%s*P(%d+)")

            if g54to59 then
                workOffsetFound = g54to59
                mc.mcCntlSetLastError(inst, string.format("Line %d: Found %s", i, g54to59))
                break
            elseif g54p then
                workOffsetFound = "G54.1 P" .. g54p
                mc.mcCntlSetLastError(inst, string.format("Line %d: Found G54.1 P%s", i, g54p))
                break
            end
        end
    end

    if not workOffsetFound then
        mc.mcCntlSetLastError(inst, "No work offset found in first 20 lines")
    end
end

-- Test 5: Get current machine work offset
local currentOffset = mc.mcCntlGetPoundVar(inst, 4014)  -- Modal group 14
local offsetString = ""
if currentOffset >= 54 and currentOffset <= 59 then
    offsetString = string.format("G%.0f", currentOffset)
elseif currentOffset == 54.1 then
    local pval = mc.mcCntlGetPoundVar(inst, mc.SV_BUFP)
    offsetString = string.format("G54.1 P%.0f", pval)
else
    offsetString = string.format("Unknown (%.2f)", currentOffset)
end
mc.mcCntlSetLastError(inst, string.format("Current work offset: %s", offsetString))

-- Test 6: Get specific line content (the selected line)
if selectedLine > 0 and selectedLine <= totalLines then
    local lineContent = mc.mcCntlGetGcodeLine(inst, selectedLine - 1)  -- 0-indexed
    mc.mcCntlSetLastError(inst, string.format("Selected line content: %s", lineContent or "EMPTY"))
end

mc.mcCntlSetLastError(inst, "=== Debug Test Complete ===")