-- GCode Conversion Base Library
mcGC = {}
mcGC.Block = {}
mcGC.Line = {}
mcGC.File = {}
mcGC.KeepState = {}

function mcGC.Line.FlipAxis(State)
	if State.AxisToFlip == nil then
		print("AxisToFlip Is NIL")
		return
	end
	local value
	local switchTo
	for axis, SwapWith in pairs(State.AxisToFlip) do
		if State["Blocks"][axis] ~= nil and State["Blocks"][SwapWith] ~= nil then
			for index, AxisCode in pairs(State["Positions"]) do
				if AxisCode == axis then
					value = State["Blocks"][axis][index]
					valIndex = index
				end
				if AxisCode == SwapWith then
					switchTo = State["Blocks"][SwapWith][index]
					swapIndex = index
				end
				if value ~= nil and switchTo ~= nil then
					State["Blocks"][axis][valIndex] = switchTo
					State["Blocks"][SwapWith][swapIndex] = value
					value = nil
					switchTo = nil
				end
			end
		end
	end
end
function mcGC.Line.ScaleAxis(State, index, block, val)
	local axisVals
	local axisVal
	if State.Axis == nil then
		print("Axis Is NIL")
		return
	end
	for MachAxis, axis in pairs(State.Axis) do
		if State["scale"][MachAxis] ~= 1 then
			axisVals = State["Blocks"][axis]
			if axisVals ~= nil and type(axisVals) == "table" then
				for index, value in pairs(axisVals) do
					axisVal = tonumber(value) * State["scale"][MachAxis]
					if State["Blocks"][MachAxis] == nil then
						State["Blocks"][MachAxis] = {}
					end
					if State["Incremental"] == true then
						State["Blocks"][MachAxis][index] = string.format("%.4f", (axisVal + State["Blocks"][axis]))
					else
						State["Blocks"][MachAxis][index] = string.format("%.4f", axisVal)
					end
					if axis ~= MachAxis then
						State["Position"][index] = MachAxis
						State["Blocks"][axis] = nil
					end
				end
			end
		end
	end
end
function mcGC.Line.ScaleLinear(State, index, block, val)
	mcGC.Line.ScaleAxis(State, index, block, val)
end
function mcGC.Line.ScaleArc(State, i, block, val)
	mcGC.Line.ScaleAxis(State, i, block, val)
	if State.AlternateAxis == nil then
		print("AlternateAxis Is NIL")
		return
	end
	for axis, ScaleAxis in pairs(State.AlternateAxis) do
		if State["scale"][ScaleAxis] ~= 1 then
			axisVals = State["Blocks"][axis]
			if axisVals ~= nil and type(axisVals) == "table" then
				for index, value in pairs(axisVals) do
					axisVal = tonumber(value) * State["scale"][ScaleAxis]
					if State["Incremental"] == true then
						State["Blocks"][axis][index] = string.format("%.4f", (axisVal + State["Blocks"][axis]))
					else
						State["Blocks"][axis][index] = string.format("%.4f", axisVal)
					end
				end
			end
		end
	end
end
function mcGC.Block.Remove(State, Index, Block)
	State["Positions"][Index] = nil
	State["Blocks"][Block][Index] = nil
end
function mcGC.Block.SwapCode(State, Index, Block, NewBlock, NewCode)
	
	--State["Positions"][Index] = newBlock
	--State["Blocks"][Block][Index] = newCode
	State["Positions"][Index] = NewBlock
	State["Blocks"][Block][Index] = nil
	if State["Blocks"][NewBlock] == nil then
		State["Blocks"][NewBlock] = {}
	end
	State["Blocks"][NewBlock][Index] = NewCode
end
function mcGC.Block.ReplaceBlocks(State, index, block, val, BlocksToReplace)
	if BlocksToReplace == nil then
		print("BlockToReplace Is NIL")
		return
	end
	function Replace(Index, Block, NewCode)
		if NewCode == false then
			State["Positions"][Index] = nil
			State["Blocks"][Block][Index] = nil 
		elseif type(NewCode) == "table" then
			if NewCode["newBlock"] ~= nil then
				--[[
				local newBlock = NewCode["newBlock"]
				local newCode = NewCode["newCode"]
				if newCode == nil then
					newCode = State["Blocks"][Block][Index]
				end
				--State["Positions"][Index] = newBlock
				--State["Blocks"][Block][Index] = newCode
				State["Positions"][Index] = newBlock
				State["Blocks"][Block][Index] = nil
				if State["Blocks"][newBlock] == nil then
					State["Blocks"][newBlock] = {}
				end
				State["Blocks"][newBlock][Index] = newCode
				--]]
				local newBlock = NewCode["newBlock"]
				local newCode = NewCode["newCode"]
				if newCode == nil then
					newCode = State["Blocks"][Block][Index]
				end
				mcGC.Block.SwapCode(State, Index, newBlock, newCode)
			else
				for oldCode, newCode in pairs(NewCode) do
					if oldCode == "Parent" then
						Replace(Index, Block, newCode)
					else
						if State["Blocks"][oldCode] ~= nil then
							for i, val in pairs(State["Blocks"][oldCode]) do
								if newCode[tostring(tonumber(val))] ~= nil then
									Replace(i, oldCode, newCode[tostring(tonumber(val))])
								else
									Replace(i, oldCode, newCode)
								end
							end
						end
					end
				end
			end
		elseif type(NewCode) == "function" then
			NewCode(State)
		else
			State["Blocks"][Block][Index] = NewCode
		end
	end
	val = tostring(tonumber(val))
	for Block, Codes in pairs(BlocksToReplace) do
		if type(Codes) == "table" then
			if block == Block then
				for SearchCode, NewCode in pairs(Codes) do
					if val == SearchCode then
						Replace(index, block, NewCode)
					end
				end
			end
		elseif Codes == false then
			if Block == block then
				State["Positions"][index] = nil
				State["Blocks"][block] = nil 
			end
		end
	end
end

function UpdateMoveModal(State, Type)
	State["MoveType"] = Type
	if State["MoveType"] ~= 0 then
		State["LastFeedMove"] = State["MoveType"]
	end
	if State["FeedCut"] == nil and State.Settings.DefaultFeed ~= nil then
		InsertBlock(State, "End", "F", tostring(State.Settings.DefaultFeed))
		State["FeedCut"] = State.Settings.DefaultFeed
	end
end
function mcGC.KeepState.CRapid(State, index, block, val)
	UpdateMoveModal(State, 0)
	--mcGC.Line.ScaleLinear(State, index, block, val)
end
function mcGC.KeepState.CLine(State, index, block, val)
	UpdateMoveModal(State, 1)
	if type(State.Settings.RapidThreshold) == "number" and State.Settings.RapidThresholdEnabled == true then
		local loc
		for i, block in pairs(State["Blocks"]["F"]) do
			loc = i
			break
		end
		if loc ~= nil then
			if State.Settings.RapidThreshold < tonumber(State["Blocks"]["F"][loc]) then
				State["MoveType"] = 0
				State["Blocks"][block][index] = "00"
				State["Positions"][loc] = nil
				State["Blocks"]["F"] = nil 
			end
		else
			State["MoveType"] = 0
			State["Blocks"][block][index] = "00"
		end
	end
	--mcGC.Line.ScaleLinear(State, index, block, val)
end
function mcGC.KeepState.CWArc(State, index, block, val)
	UpdateMoveModal(State, 2)
	--mcGC.Line.ScaleArc(State, index, block, val)
end
function mcGC.KeepState.CCWArc(State, index, block, val)
	UpdateMoveModal(State, 3)
	--mcGC.Line.ScaleArc(State, index, block, val)
end
function mcGC.KeepState.SetAbs(State, index, block, val)
	State["Absolute"] = true
end
function mcGC.KeepState.SetInc(State, index, block, val)
	State["Absolute"] = false
end
function mcGC.KeepState.SetFeedRate(State, index, block, val)
	if type(State.Settings.RapidThreshold) == "number" then
		if tonumber(val) > State.Settings.RapidThreshold then
			State.Settings.RapidThresholdEnabled = true
			State["MoveType"] = 0
			return
		else
			State.Settings.RapidThresholdEnabled = false
		end
	end
	if State.Settings["SeparatePlunge"] == true then
		if State["Blocks"]["Z"] ~= nil and State["Blocks"]["X"] == nil and State["Blocks"]["Y"] == nil then
			State["FeedPlunge"] = val
		else
			State["FeedCut"] = val
		end
	else
		State["FeedCut"] = val
	end
end

function mcGC.KeepState.ChangeG(block, value, State)
	if State["MoveType"] ~= value then
		State["MoveType"] = tonumber(value)
	end
	if State["LastMoveType"] == State["MoveType"] then
		return true
	else
		State["LastMoveType"] = State["MoveType"]
	end
end
function InsertBlock(State, Position, Block, Value)
	local newPos
	if type(Position) == "number" then -- Insert it after the Position
		index, v = next(State["Positions"], Position)
		newPos = ((index - Position) /2) + Position
	else
		if Position == "End" then
			-- This may be far from the end of the table depending on how many new blocks have been inserted
			--This is because blocks are inserted between integers
			newPos = #State["Positions"] + 1
		elseif Position == "Start" then
			local first, v = next(State["Positions"], nil)
			newPos = (first / 2)
		end
	end
	if State["Blocks"][tostring(Block)] == nil then
		State["Blocks"][tostring(Block)] = {}
	end
	State["Blocks"][tostring(Block)][newPos] = tostring(Value)
	State["Positions"][newPos] = tostring(Block)
end
function mcGC.KeepState.UpdateModal(block, value, State)
	if State["LastAbsolute"] == State["Absolute"] then
		return true
	else
		State["LastAbsolute"] = State["Absolute"]
	end
end
function mcGC.KeepState.UpdateFeedRate(block, value, State)
	if State["Settings"]["SeparatePlunge"] == true then
		if State["FeedPlungePrev"] == State["FeedPlunge"] and State["FeedCutPrev"] == State["FeedCut"] then
			return true
		else
			if State["FeedPlungePrev"] ~= State["FeedPlunge"] then
				State["FeedPlungePrev"] = State["FeedPlunge"] 
			end
			if State["FeedCutPrev"] ~= State["FeedCut"] then
				State["FeedCutPrev"] = State["FeedCut"] 
			end
		end
	else
		if State["FeedCutPrev"] == State["FeedCut"] then
			return true
		else
			State["FeedCutPrev"] = State["FeedCut"] 
		end
	end
	return false
end

return mcGC