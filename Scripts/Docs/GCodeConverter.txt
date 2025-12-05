--Version2 Delorme 3/31/23

-- Settings that can go in posts
--[[
Settings.RunRegExOnly = false
Settings["SeparatePlunge"] = true
Settings["RapidThreshold"] = 200 -- false to disable
Settings["RapidThresholdEnabled"] = true
Settings["CommentChangeLocation"] = false
--]]
-- TODO
-- Add Comment delete if rest of line is removed
-- Easier way to replace code letters ex. Q10 to S10
-- Know what the codes do to allow sanity checks
-- Allow removing repeated comments
-- Improve interface for Post

--[[
-- Common Requirements
Replace Letter
Scale Number
Remove Invalids
Add M3/M5
Replace whole lines

--]]

local GCConverter = {}
local GCCH = {}
function deepcopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[deepcopy(orig_key, copies)] = deepcopy(orig_value, copies)
            end
            setmetatable(copy, deepcopy(getmetatable(orig), copies))
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end
function GCCH.MsgBox(msg, title, btnOK, btnCANCEL)
	--local res
	if (btnOK == nil) then
		btnOK = "OK"
	end
	if (btnCANCEL == nil) then
		btnCANCEL = "Cancel"
	end
	local btnSize = wx.wxSize(150,100)
	CT = {}
------------------------------------------------------------------
	-- create diaMain
------------------------------------------------------------------
	CT.diaMain = wx.wxDialog (wx.NULL, wx.wxID_ANY, title, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxDEFAULT_DIALOG_STYLE + wx.wxSTAY_ON_TOP )
	CT.diaMain:SetSizeHints( wx.wxSize( 300,-1 ), wx.wxDefaultSize )
	
	CT.szrMain = wx.wxBoxSizer( wx.wxVERTICAL )
	
	CT.lblText = wx.wxStaticText( CT.diaMain, wx.wxID_ANY, msg, wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	CT.lblText:Wrap( -1 )
	CT.lblText:SetFont( wx.wxFont( 25, 70, 90, 90, false, "" ) )
	CT.szrMain:Add( CT.lblText, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	CT.szrButton = wx.wxBoxSizer( wx.wxHORIZONTAL )
	
	CT.btnOK = wx.wxButton( CT.diaMain, wx.wxID_ANY, btnOK, wx.wxDefaultPosition, btnSize, 0 )
	CT.btnOK:SetFont( wx.wxFont( 20, 70, 90, 90, false, "" ) )
	CT.szrButton:Add( CT.btnOK, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )
	
	CT.btnCancel = wx.wxButton( CT.diaMain, wx.wxID_ANY, btnCANCEL, wx.wxDefaultPosition, btnSize, 0 )
	CT.btnCancel:SetFont( wx.wxFont( 20, 70, 90, 90, false, "" ) )
	CT.szrButton:Add( CT.btnCancel, 0, wx.wxALL, 5 )
	
	CT.szrMain:Add( CT.szrButton, 1, wx.wxALIGN_CENTER, 5 )
	
	CT.diaMain:SetSizer( CT.szrMain )
	CT.diaMain:Layout()
	CT.szrMain:Fit( CT.diaMain )
	
	CT.diaMain:Centre( wx.wxBOTH )
	
	-- Connect Events
	
	CT.diaMain:Connect( wx.wxEVT_CLOSE_WINDOW, function(event)
	--implements diaMainOnClose
		CT.diaMain:Destroy()
		DialogReturn = wx.wxCLOSE
	end )
	
	CT.btnOK:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements btnOKOnButtonClick
		CT.diaMain:Destroy()
		DialogReturn = wx.wxOK
	end )
	
	CT.btnCancel:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
	--implements btnCancelOnButtonClick
		CT.diaMain:Destroy()
		DialogReturn = wx.wxCANCEL
	end )
	
	CT.diaMain:ShowModal()
	return _G.DialogReturn
end
-- All the print statments are just for debugging sake. When development is nearly over they should be taken out.
function GCCH.LoadTableFromFile(file_name) -- this function stopped being recognized by lua at one point
  local function Addtotable(thefile, tableindex)
    local str = thefile:read("line");
      while (str ~= nil )do  
        if (string.find(str, "<TABLE_START>") ~= nil) then
          -- Get the name of the table
          str = string.gsub(str," <TABLE_START>", "")
		local newTable = {} 
          table.insert(tableindex, Addtotable(thefile, newTable))
        elseif (string.find(str, "<TABLE_END>") ~= nil) then
          return tableindex
        else
			-- This is normal data and needs to be placed into the table
			local length = string.len(str);
			local eqpos = string.find(str,"=");
			local varname = string.sub(str, 0,eqpos-1)
			local val = string.sub(str, eqpos+1, length)
			tableindex[varname] = val
		
        end
        str = thefile:read("line");
      end
    return tableindex
  end
  local myfile = io.open(file_name , "r")
	if myfile ~= nil then  
		local dataTable = {}; -- Blank table to put the data
		dataTable = Addtotable(myfile, dataTable)
		myfile:close();
		return dataTable;
	else
		return {}
	end
end
function GCCH.SaveTableToFile(file_name, tabletoSave)
	local function TableToString(tbl)
		local str = ""
			for var,value in pairs(tbl) do 
				if (type(value) == "table") then
					str = str .. tostring(var) .. " <TABLE_START>\n".. TableToString(value).. "<TABLE_END>\n"
				else
					if tonumber(value) ~= nil then
						str = str .. tostring(var) .. "=" .. string.format("%.4f", tonumber(value)) .. "\n" 
					else
					str = str .. tostring(var) .. "=" .. tostring(value) .. "\n" 
					end
				end
			end
		return str
	end
	local str = TableToString(tabletoSave)
	local myfile = io.open(file_name , "w")
	myfile:write(str)
	myfile:flush();
	myfile:close();
	return true
end
function GCCH.escape_magic(pattern)
  return (pattern:gsub("[^%w]", "%%%1"))
end

local State = {} -- Put any Important State changes in here.
-- Possibly user inputs from a wizard in the future
local fileIssues = ""

function GCCH.ReassembleLine(State)
	local val
	local newLine = " "
	if State.PrefixLine ~= "" and State.PrefixLine ~= nil then
		newLine = State.PrefixLine
		State.PrefixLine = ""
	end
	local first = true
	local LineFeed
	for index, block in pairs(State["Positions"]) do
		val = State["Blocks"][block][index]
		if State["SplitLineBlocks"] ~= nil and State["SplitLineBlocks"][string.upper(block .. val)] == true and State["PastLineFeeds"][string.upper(block .. val)] ~= true then
			-- This is the end of the line
			State["PastLineFeeds"][string.upper(block .. val)] = true
			LineFeed = true
			break
		end
		local skip
		local Tonumber = tostring(tonumber(val))
		if State.CheckForChange == nil then
			print("CheckForChange Is NIL")
		else
			if State.CheckForChange[block] ~= nil then
				if #State.CheckForChange[block] > 0 then
					for CheckIndex, tbl in pairs(State.CheckForChange[block]) do
						for i=1, #tbl, 1 do
							Value = tbl[i]
							if (Tonumber == Value)then
								skip = State.CheckForChange[block][CheckIndex]["Function"](block, Tonumber, State)
							end
						end
					end
				elseif State.CheckForChange[block]["Function"] ~= nil then
					skip = State.CheckForChange[block]["Function"](block, Tonumber, State)
				end
			end
		end
		if skip ~= true then
			if block ~= "Comment" then
				if first == false then
					newLine = newLine .. State.Settings["Seperator"] .. block .. val
				else
					newLine = newLine .. block .. val
					first = false 
				end
			else
				if first == false then
					newLine = newLine .. State.Settings["Seperator"] .. "(" .. val .. ")"
				else
					newLine = newLine .. "(" .. val .. ")"
					first = false 
				end
			end
		end
		-- Reset table indices for next time.
		State["Blocks"][block][index] = nil 
		State["Positions"][index] = nil
	end
	if LineFeed ~= true then
		State["PastLineFeeds"] = {}
	end
	return string.sub(newLine, 2)
end
function GCCH.GetParameterFromUser(State, ParamConfig)
	for num, param in pairs(State["Params"]) do
		local GetNum = wx.wxGetTextFromUser(param, "Missing Paramerter Found")
		if GetNum ~= "" then
			ParamConfig[param] = GetNum
			State["Blocks"][State["Positions"][num]][num] = GetNum
			State["Params"][num] = nil
			addedParam = true
		end
	end
end
function GCCH.RunModFunctions(FuncTbl)
	if FuncTbl ~= nil then
		for i=1, #FuncTbl, 1 do --func in pairs(FuncTbl) do
			FuncTbl[i](State)
		end
	end
end
function GCCH.AddCommentsAheadAndBehind(State)
	if State.Settings["CommentChangeLocation"] ~= false and State["Blocks"]["Comment"] ~= nil then
		for indice, comment in pairs(State["Blocks"]["Comment"]) do
			if State.Settings["CommentAtStartOfBlock"] == false then
				State["ModifiedLine"] = State["ModifiedLine"] .. State.Settings["Seperator"] .. "(" .. comment .. ")"
			else
				State["ModifiedLine"] = "(" .. comment .. ")" .. State.Settings["Seperator"] .. State["ModifiedLine"]
			end
		end
		State["Blocks"]["Comment"] = nil
	end
end
local lineNum = 1
--File is a string of the whole file, 
--Modifiers is a table of functions in the order they should be run
function GCCH.ConvertCodes(File, ParamConfig)
	if File ~= nil and type(State.Modifiers) == "table" then
		local addedParam = false
		State["convertedFile"] = ""
		local NoIgnore = true
		local skip = false
		local totalLength = File:len()
		local currentPosition = 0
		State["Blocks"], State["Positions"], State["Params"] = {}, {}, {}
		local _, EOL = File:find("\n", 0)
		if EOL == nil then
			EOL = totalLength
		end
		State["OriginalLine"] = File:sub(0, EOL)
		if string.find(State["OriginalLine"], "(" .. State.Settings.PostIdentifier .. ")") ~= nil then
			print("File has Ignore Code")
			return -1
		end
		while State["OriginalLine"] ~= "" do
			if FileOpenedFromDialog == true then
				DI.m_gauge1:SetValue( ((currentPosition / totalLength) * 100))
				DI.MyDialog1:Update()
				--DI.MyDialog1:Refresh()
			end
			lineNum = lineNum + 1
			File = File:sub(EOL+1)
			
			--Runs functions on the whole line as a string before anything else modifies it.
			GCCH.RunModFunctions(State.Modifiers["WholeLine"])
			
			if State.Settings.RunRegExOnly ~= true then -- Allows anything not in the post file to be skipped.
				-- Break the line apart into blocks and values
				State["Blocks"], State["Positions"], State["Params"] = GCCH.SplitString(State, State["OriginalLine"]:gsub("%\n", ""), ParamConfig)
				
				-- get text input from user for each parameter
				GCCH.GetParameterFromUser(State, ParamConfig)
				
				-- Run the functions for the whole line after splitting it into blocks
				GCCH.RunModFunctions(State.Modifiers["SeparatedLine"])
				
				-- Send each block in order through the modifier functions
				for index, block in pairs(State["Positions"]) do
					if type(State["Blocks"][block]) == "table" then
						local val = State["Blocks"][block][index]
						for indice, func in pairs(State.Modifiers["Block"]) do
							func(State, index, block, val)
						end
					end
				end
				
				-- Runs the functions for after the blocks have been run through the block functions
				GCCH.RunModFunctions(State.Modifiers["SeparatedLineAfterBlocks"])
				
				-- Put the line back together
				State["ModifiedLine"] = GCCH.ReassembleLine(State)
				
				--Add Comments if they weren't put back in order
				GCCH.AddCommentsAheadAndBehind(State)
				
				-- Runs the functions for the reassembled line
				GCCH.RunModFunctions(State.Modifiers["Reassembled"])
				
				-- Add line numbers if applicable and append the line to the working file
				if State["ModifiedLine"] ~= "" then
					-- Handle line numbers based off user input interval Ex. User could input 10 and the lines would count up by 10
					if State["LineNumber"] ~= nil then
						if State["HadLineNumber"] == true then
							State["ModifiedLine"] = "N" .. State["LineNumber"] .. State["Seperator"] .. State["ModifiedLine"]
							State["HadLineNumber"] = false
						end
						State["LineNumber"] = State["LineNumber"] + State["LineNumberInterval"]
					end
					if State["BlockSkip"] ~= nil and State["BlockSkip"] > -1 and State["MoveType"] ~= nil then
						if State["BlockSkip"] == 0 then
							State["ModifiedLine"] = "/" .. State["ModifiedLine"]
						else
							State["ModifiedLine"] = "/" .. tostring(State["BlockSkip"]) .. " " .. State["ModifiedLine"]
						end
					end
					State["convertedFile"] = State["convertedFile"] .. State["ModifiedLine"] .. "\n"
				end
			end
			_, EOL = File:find("\n", 0)
			if EOL == nil then
				EOL = File:len()
			end
			currentPosition = currentPosition + EOL
			State["OriginalLine"] = File:sub(0, EOL)
		end
		return State["convertedFile"], addedParam
	end
end

function GCCH.GetValue(str,axis)
	local val  = string.match(str, tostring(axis).. "[+-.0-9]+")
	if(val == nil)then return nil end
	val = string.gsub(val,tostring(axis),"")
	return tonumber(val)
end 
function GCCH.PassesValidCheck(Code, Value) -- A place to add acceptablility checks before blocks are added to the chunk splitting table
	
	return true
end
function GCCH.SplitString(State, str, ParamConfig)
	State["Blocks"] = {}
	State["Positions"] = {}
	local Strings = State["Blocks"]
	local Positions = State["Positions"]
	local number = 1
	for index, code in pairs(Positions) do
		number = index + 1
	end
	local val = string.match(str, "[+-.0-9]+")
	local comment
	local ParamsTbl = State["Params"]
	local function StoreComment(CommentStart, CommentEnd, num, startSize, endSize, startComment)
		local rc = 0
		local comment = string.sub(str, CommentStart+startSize, CommentEnd-endSize)
		if Strings["Comment"] == nil then -- Makes sure "Comment" Exists in the Table
			Strings["Comment"] = {}
		end
		local subbedComment = comment
		if startComment ~= "%(" then
			subbedComment = string.gsub(subbedComment, "%(", "")
			subbedComment = string.gsub(subbedComment, "%)", "")
		end
		if startComment ~= "%\n" then
			subbedComment = string.gsub(subbedComment, "%\n", "")
		end
		--Adds the comment into the comment cache
		Strings["Comment"][num] = subbedComment 
		
		--Adds the comment in to the positions so it can go back in the order it came out in
		if State["Settings"]["CommentChangeLocation"] == false then
			Positions[num] = "Comment"
			rc = 1
		end
		--Rips the comment out the line
		local s, End = string.find(str, GCCH.escape_magic(comment))
		str = string.sub(str, End + endSize + string.len(val))
		return rc
	end
	local function CheckForComment()
		local CommentStart
		local CommentEnd
		
		local valStart, valEnd = string.find(str, GCCH.escape_magic(val))
		for indice, ignore in pairs(State.CommentIdentifiers) do
			CommentStart = string.find(str, tostring(ignore[1]))
			if CommentStart ~= nil then
				if CommentStart < valEnd+1 then
					_, CommentEnd = string.find(str, tostring(ignore[2]))
					local startlen = string.len(tostring(ignore[1]):gsub("%%", ""))
					local endlen = string.len(tostring(ignore[2]):gsub("%%", ""))
					if ignore[2] == nil then
						CommentEnd = string.len(str) + 1
						endlen = 0
					end
					if (CommentEnd) ~= nil then
						rc = StoreComment(CommentStart, CommentEnd, number, startlen, endlen, ignore[1])
						number = number + rc
						return 0
					end
				elseif CommentStart == valEnd+1 then -- This is to keep order in the case a comment is in the middle of numbers Ex. "G01 X1.25(This is a Comment)34 Y2.3"
					local Start, End = string.find(str, GCCH.escape_magic(val))
					local Code = string.sub(str, 1, Start-1)
					local Value = string.sub(str, Start, End)
					str = string.gsub(str, Code .. Value, "", 1)
					_, CommentEnd = string.find(str, tostring(ignore[2]))
					local startlen = string.len(tostring(ignore[1]):gsub("%%", ""))
					local endlen = string.len(tostring(ignore[2]):gsub("%%", ""))
					if ignore[2] == nil then
						CommentEnd = string.len(str)
						endlen = 0
					end
					--Store the comment one place ahead if comments stay in their location
					local rc = StoreComment(1, CommentEnd, number+1, startlen, endlen)
					val = string.match(str, "[+-.0-9]+")
					if val == nil then
						val = ""
					end
					Value = Value .. val
					if Strings[Code] == nil then
						Strings[Code] = {}
					end
					Strings[Code][number] = Value
					Positions[number] = Code
					if val ~= "" then
						Start, End = string.find(str, GCCH.escape_magic(val))
						str = string.sub(str, End+1)
						val = string.match(str, "[+-.0-9]+")
					end
					number = number + 2
				end
				CommentStart = string.find(str, tostring(ignore[1]))
			end
		end
	end
	local function CheckForParameters()
		local ParamStart
		local ParamEnd
		local valStart, valEnd = string.find(str, GCCH.escape_magic(val))
		for indice, ignore in pairs(State.ParameterIdentifiers) do
			ParamStart = string.find(str, GCCH.escape_magic(tostring(ignore[1])))
			if ParamStart ~= nil then
				if ParamStart < valEnd+1 then
					_, ParamEnd = string.find(str, tostring(ignore[2]))
					local endlen = string.len(string.gsub(tostring(ignore[2]), "%%", ""))
					if ignore[2] == nil then
						ParamEnd = string.len(str)
						endlen = 0
					end
					if (ParamEnd) ~= nil then
						return ParamStart, ParamEnd+endlen
					end
				end
			end
		end
	end
	while(str ~= "") do
		if val == nil then
			val = str
		end
		ParamStart, ParamEnd = CheckForParameters()
		if ParamStart == nil then
			comment = CheckForComment()
		end
		if comment ~= nil then
			comment = nil 
		elseif val ~= "" then
			local Start, End = string.find(str, GCCH.escape_magic(val))
			if ParamStart ~= nil then
				Start, End = ParamStart, ParamEnd
			end
			local Code = string.upper(string.sub(str, 1, Start-1))
			local Value = string.sub(str, Start, End)
			if Code ~= nil and Value ~= nil then
				--Remove spaces
				Code = Code:gsub("%s+", "") 
				Value = Value:gsub("%s+", "")
				if ParamStart ~= nil then -- if the values a param then check if it's defined
					if ParamConfig[Value] == nil then
						ParamsTbl[number] = Value
					else
						if ParamConfig[Value] == "False" then
							Value = ""
						else
							Value = ParamConfig[Value]
						end
					end
				end
				if GCCH.PassesValidCheck(Code, Value) then -- make sure these should be added to the table
					if State["LineBlock"] == Code then
						State["HadLineNumber"] = true
					else
						if Strings[Code] == nil then -- make sure the block exists
							Strings[Code] = {}
						end
						InsertBlock(State, "End", Code, tostring(Value))
						number = number + 1
					end
				end
				str = string.sub(str, End+1) -- Remove the block from the line
			end
		end
		if str:sub(1,1) == " " then
			str = str:sub(2)
		end
		val = string.match(str, "[+-.0-9]+")
	end
	return Strings, Positions, ParamsTbl
end


--State["OriginalLine"] is the original copy of the line being manipulated
--State["ModifiedLine"] is the modified version of the line.
--[[
ConvertFiles(Path, NewPath, Post)
Path = The path to pull from if it's a directory, every file and subdirectory will be run through the converter. If it's a file, that file will be run. Example. "C:\\PullFromHere"
NewPath = The path that converted files will be added to. If the Path is a directory this must also be a directory becuase modified clones of all the files will be put in this directory. Example. "C:\\DropHere"
--]]

function GCConverter.ConvertFiles(Path, NewPath, Post)--check if the path is a file or directory. if it's a directory this is a bulk operation
	local gaugeFunctions = {}
	local function ConvertFiles()
		local inst = mc.mcGetInstance()
		local machDir = mc.mcCntlGetMachDir(inst)
		local prof = mc.mcProfileGetName(inst)
		local GCCH = GCCH
		local ConfigFileName = machDir.. "\\Profiles\\".. prof .. "\\GCodeConverterSettings\\GCodeConverterConfig.lua" 
		ConfigRC, ConfigValue = pcall(loadfile(ConfigFileName))
		if ConfigRC ~= false then
			State.Settings = ConfigValue
		else
			wx.wxMessageBox("Conversion Canceled: Can't find settings file")
			return -1
		end
		if Path == nil then
			local rc = GCCH.MsgBox("Would you like to convert a file or directory?", "File Converter", "File", "Directory")
			if rc == wx.wxOK then
				local fileTypes = "All Files(*)*.*"
				if State.Settings.DefaultExtentions ~= nil then
					fileTypes = State.Settings.DefaultExtentions
				end
				local file = wx.wxFileDialog(wx.NULL, "Choose Gcode File or Directory", "", "", fileTypes, 
									  wx.wxFD_OPEN,wx.wxDefaultPosition,wx.wxDefaultSize, "Open File to Convert" );
				if (file:ShowModal() == wx.wxID_OK) then
					Path = file:GetPath()
					FileOpenedFromDialog = true
				else
					mc.mcCntlSetLastError(inst, "Conversion Canceled: User")
					return -1
				end
			elseif rc == wx.wxCANCEL then
				local file = wx.wxDirDialog(wx.NULL, "Choose Directory To Run the Converter on", "",
								  wx.wxDD_DEFAULT_STYLE,wx.wxDefaultPosition,wx.wxDefaultSize, "Select Directory" );
				if (file:ShowModal() == wx.wxID_OK) then
					Path = file:GetPath() .. "/"
					FileOpenedFromDialog = true
				else
					mc.mcCntlSetLastError(inst, "Conversion Canceled: User")
					return -1
				end
			else
				mc.mcCntlSetLastError(inst, "Conversion Canceled: User")
				return -1
			end
		end
		gaugeFunctions.RemoveGauge = function()
			if DI ~= nil and gaugeFunctions.removegauge ~= nil then
				gaugeFunctions.removegauge()
			end
		end
		local PostName
		local PostPath
		if Post == nil then
			PostPath = mc.mcCntlGetMachDir(inst) .. "\\PostFiles\\" .. tostring(State.Settings.DefaultPOST)
			if State.Settings.DefaultPOST == nil then
				mc.mcCntlSetLastError(inst, "Default Post is missing from settings file")
				gaugeFunctions.RemoveGauge()
				return -1
			elseif wx.wxFileExists(PostPath) == false then
				mc.mcCntlSetLastError(inst, "Default Post file does not exist")
				gaugeFunctions.RemoveGauge()
				return -1
			end
			rc , Post = pcall(loadfile(PostPath))
			PostName = wx.wxFileName(PostPath):GetName()
		elseif type(Post) == "string" then
			rc, Post = pcall(loadfile(Post))
			PostName = wx.wxFileName(Post):GetName()
		end
		if Post.Name ~= nil then
			PostName = Post.Name
		end
		function AddSettingsFromPost(tbl, StateConfig)
			for name, val in pairs(tbl) do
				if type(StateConfig[name]) == "table" then
					AddSettingsFromPost(tbl[name], StateConfig[name])
				else
					StateConfig[name] = val
				end
			end
		end
		if State["Settings"] == nil then
			State["Settings"] = {}
		end
		if type(Post) ~= "table" then
			wx.wxMessageBox("Post Processor Load Error: " .. tostring(Post))
			return Post
		end
		for name, value in pairs(Post) do
			if name ~= "Settings" then
				State[name] = value
			else
				AddSettingsFromPost(value, State.Settings)
			end
		end
		local AddedParam = false
		if State.Settings.ParameterFilePath == nil then
			State.Settings.ParameterFilePath = mc.mcCntlGetMachDir(mc.mcGetInstance()) .. "\\GcodeFiles\\GcodeParameterSave.txt"
		end
		local ParamConfig = GCCH.LoadTableFromFile(State.Settings.ParameterFilePath)
		BaseState = deepcopy(State)
		local function ConvertFile(path, newpath, ParamConfig)
			if State.Settings.TestRunning == true then
				wholeFile = path
			else
				local loadedfile = mc.mcCntlGetGcodeFileName(inst)
				if loadedfile == path or newpath == loadedfile then
					if State.Settings.UnloadFilesFromMach == true then
						mc.mcCntlCloseGCodeFile(inst)
					else
						mc.mcCntlSetLastError(inst,"File: " .. path .. " is loaded into Mach4 so the conversion is being cancelled.")
						return -1
					end
				end
				opened = assert(io.open(path,"r"))
				wholeFile = opened:read("*all")
				local wxpath = wx.wxFileName(newpath)
				local dir = wxpath:GetPath()
				if wx.wxDirExists(dir) == false then
					local success = wx.wxMkdir(dir)
				end
			end
			if State.Modifiers.Before ~= nil and #State.Modifiers.Before > 0 then
				for i, func in pairs(State.Modifiers.Before) do
					wholeFile = func(wholeFile)
				end
			end
			if State.Settings.DisableDefaultRunning ~= true then
				noErr, convertedFile, addedParam = pcall(GCCH.ConvertCodes, wholeFile, ParamConfig)
				AddedParam = addedParam
				if convertedFile == nil then
					mc.mcCntlSetLastError(inst, "File Conversion Failed")
					return -1
				elseif convertedFile == 0 then
					print("File Ignored")
					mc.mcCntlSetLastError(inst, "File Already Converted")
					return -1
				elseif noErr == false then
					mc.mcCntlSetLastError(inst, "Error Converting Codes: " .. tostring(convertedFile))
				end
			end
			if State.Modifiers.After ~= nil and #State.Modifiers.After > 0 then
				for i, func in pairs(State.Modifiers.After) do
					convertedFile = func(convertedFile)
				end
			end
			if convertedFile ~= nil then
				local testfile, rc = io.open(newpath, "w")
				if rc == nil then
					convertedFile = string.format("(CONVERTED: %s %s)\n", os.date("%x"), os.date("%X")) .. convertedFile
					if PostName ~= nil then
						convertedFile = string.format("(%s)\n", PostName) .. convertedFile
					end
					if State.Settings.PostIdentifier ~= nil then
						convertedFile = "(" .. State.Settings.PostIdentifier .. ")\n" .. convertedFile
					end
					if State.Settings.TestRunning == true then
						return convertedFile
					end
					testfile:write(convertedFile);
					testfile:flush();
					testfile:close();
				else
					mc.mcCntlSetLastError(mc.mcGetInstance(), "Problem Opening Output File: " .. tostring(rc))
				end
			else
				print("Converted File is nil")
				return -1
			end
			return 0
		end
		if FileOpenedFromDialog == true then
			DI = {}
			
			-- create MyDialog1
			DI.MyDialog1 = wx.wxDialog (wx.NULL, wx.wxID_ANY, "Converting", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxCAPTION)
			DI.MyDialog1:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )

			DI.bSizer1 = wx.wxBoxSizer( wx.wxVERTICAL )

			DI.m_gauge1 = wx.wxGauge( DI.MyDialog1, wx.wxID_ANY, 100, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxGA_HORIZONTAL )
			DI.m_gauge1:SetValue( 0 )
			DI.bSizer1:Add( DI.m_gauge1, 0, wx.wxALL, 5 )
			
			DI.MyDialog1:SetSizer( DI.bSizer1 )
			DI.MyDialog1:Layout()
			DI.bSizer1:Fit( DI.MyDialog1 )
			--DI.m_gauge1:Pulse()
			DI.MyDialog1:Centre( wx.wxBOTH )
			DI.MyDialog1:Show()
			 --Connect Events
			gaugeFunctions.removegauge = function()
				DI.MyDialog1:Destroy()
				DI = nil
			end
		end
		local NewPathWasNil = false
		local FileName
		if NewPath == nil then
			NewPathWasNil = true
			--local FilePath = ""
			if State.Settings.DefaultOutputDirectory ~= nil then
				NewPath = State.Settings.DefaultOutputDirectory
			elseif wx.wxFileExists(Path) == true then
				FileName = wx.wxFileName(Path)
				NewPath = FileName:GetPathWithSep(wx.wxPATH_NATIVE)
			end
			if wx.wxDirExists(NewPath) == false then
				local file = wx.wxDirDialog(wx.NULL, "Choose Directory for GCODE output", "",
								  wx.wxDD_DEFAULT_STYLE,wx.wxDefaultPosition,wx.wxDefaultSize, "Select Directory" );
				if (file:ShowModal() == wx.wxID_OK) then
					dir = file:GetPath()
					NewPath = dir .. "/"
				else
					mc.mcCntlSetLastError(inst, "Conversion Canceled: User")
					return -1
				end
			end
			
		end
		local rc
		if wx.wxFileExists(Path) or State.Settings.TestRunning == true then
			if NewPathWasNil == true then
				FileName = wx.wxFileName(Path)
				local Ext = FileName:GetExt()
				local Name = FileName:GetName()
				NewPath = NewPath .. Name
				if State.Settings.ConvertedFilenameAddition ~= nil then
					NewPath = NewPath .. State.Settings.ConvertedFilenameAddition .. "." .. Ext
				else
					NewPath = NewPath .. "." .. Ext
				end
			end
			noErr, rc = pcall(ConvertFile, Path, NewPath, ParamConfig)
			if noErr == false then
				mc.mcCntlSetLastError(inst,"Error Converting File: " .. tostring(rc))
			end
		else
			if wx.wxDirExists(Path) == false then
				mc.mcCntlSetLastError(inst, "Directory Path does not exist")
				gaugeFunctions.RemoveGauge()
				return -1
			end
			local sc = wx.wxMessageDialog(wx.NULL, "This will convert EVERY file in this directory. Are you SURE you would like to do this?", "Confirm", wx.wxYES_NO + wx.wxCENTER, wx.wxDefaultPosition)
			local rc = sc:ShowModal()
			if rc ~= wx.wxID_YES then 
				mc.mcCntlSetLastError(inst, "User Canceled Conversion")
				return 0
			end
			if wx.wxDirExists(NewPath) == false then
				local wxpath = wx.wxFileName(NewPath)
				local dir = wxpath:GetPath()
				local success = wx.wxMkdir(dir)
			end
			local function RunAllDirs(Path, NewPath)
				local Directory = wx.wxDir(Path)
				local opened = Directory:IsOpened()
				local rc, fileOrDir = Directory:GetFirst()
				while rc ~= false do
					if wx.wxFileExists(Path .. fileOrDir) == true then
						rc = ConvertFile(Path .. fileOrDir, NewPath .. fileOrDir, ParamConfig)
						State = deepcopy(BaseState)
						if rc ~= 0 then
							return 0
						end
					elseif wx.wxDirExists(Path .. fileOrDir) == true then
						local TrueDir = fileOrDir .. "\\"
						if wx.wxDirExists(NewPath .. TrueDir) == false then
							local wxpath = wx.wxFileName(NewPath .. TrueDir)
							local dir = wxpath:GetPath()
							local success = wx.wxMkdir(dir)
						end
						RunAllDirs(Path .. TrueDir, NewPath .. TrueDir)
					end
					rc, fileOrDir = Directory:GetNext()
				end
			end
			noErr, rc = pcall(RunAllDirs, Path, NewPath)
		end
		if AddedParam == true then
			GCCH.SaveTableToFile(State.Settings.ParameterFilePath, ParamConfig)
		end
		if State.Settings.TestRunning == true then
			return rc
		elseif FileOpenedFromDialog == true and rc == 0 then
			mc.mcCntlLoadGcodeFile(inst, NewPath)
			mc.mcCntlSetLastError(inst, "GCODE File loaded: " .. tostring(NewPath))
		end
	end
	NoErr, rc = pcall(ConvertFiles)
	if gaugeFunctions.RemoveGauge ~= nil then
		gaugeFunctions.RemoveGauge()
	end
	if rc ~= -1 then
		mc.mcCntlSetLastError(mc.mcGetInstance(), "File(s) Finished Converting")
	end
	if NoErr == false then
		wx.wxMessageBox(rc)
	elseif State.Settings.TestRunning == true then
		return rc
	end
end
function GCConverter.LaunchConfigWizard()
	function AddNameAndDesc(Name, Description)
		return {["Name"] = Name, ["Description"] = Description}
	end
	local SettingsNames = {}
	-- Allows Special Display Functions to be added for each setting
	SettingsNames["DefaultOutputDirectory"] = AddNameAndDesc("Default Ouput Directory: ", "The Directory that files will be put in after conversion")
	SettingsNames["DefaultOutputDirectory"]["DisplayFunction"] = function(Parent, Sizer, tbl, name, Count)
		UI.dirpicker1 = wx.wxDirPickerCtrl (Parent, wx.wxID_ANY, tbl[name], "Browse", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxDIRP_DEFAULT_STYLE, wx.wxDefaultValidator, "")
		UI.dirpicker1:SetBackgroundColour(lightBackground)
		UI.dirpicker1:SetForegroundColour(textColor)
		if SettingsNames["DefaultOutputDirectory"].Description ~= nil then
			UI.dirpicker1:SetToolTip(SettingsNames["DefaultOutputDirectory"].Description)
		end
		Sizer:Add( UI.dirpicker1, wx.wxGBPosition( Count, 1 ), wx.wxGBSpan( 1, 2 ), wx.wxALL, 5 )
		UI.dirpicker1:Connect( wx.wxEVT_COMMAND_DIRPICKER_CHANGED, function(event)
			--implements BtnClick
			local path = event:GetPath()
			tbl[name] = path:gsub("\\", "/") .. "/"
			event:Skip()
		end )
	end
	SettingsNames["PastLineFeeds"] = {}
	SettingsNames["DefaultPOST"] = AddNameAndDesc("Default Post Processor: ", "The Post Processor that will be used to convert files")
	SettingsNames["DefaultPOST"]["DisplayFunction"] = function(Parent, Sizer, tbl, name, Count)
		-- returns table of file names in the directory
		function findFiles(machDir, RelativeToRoot) 
			local dirname = machDir .. "\\" .. RelativeToRoot
			local test = wx.wxFindFirstFile(dirname)
			local files = {}
			local fileNames = {}
			if test ~= "" then 
				local loc = string.find(test,RelativeToRoot)+#RelativeToRoot
				table.insert(fileNames, tostring(test):sub(loc, -1 ))
				table.insert(files, tostring(test))
			else
				return
			end
			repeat
				test = wx.wxFindNextFile()
				if test ~= "" then 
					local loc = string.find(test, RelativeToRoot)+#RelativeToRoot
					table.insert(fileNames, tostring(test):sub(loc, -1 ))
					table.insert(files, tostring(test))
				end 
			until(tostring(test) == "") 
			return files, fileNames
		end
		local RelativeToRoot = "PostFiles\\"
		local inst = mc.mcGetInstance()
		local fileNames, displayFileNames = findFiles(mc.mcCntlGetMachDir(inst), RelativeToRoot)
		table.insert(fileNames, 1, "Choose a .txt file to load")
		function GetPostFiles(tbl)
			local Files = wx.wxArrayString()
			for i=2, #tbl, 1 do
				Files:Add(tbl[i])
			end
			Files:Sort(false)
			Files:Insert(tbl[1], 0)
			return Files
		end
		displayFileNames = GetPostFiles(displayFileNames, tbl, Name)
		fileNames = GetPostFiles(fileNames)
		UI.m_choicePostChoices = displayFileNames
		UI.m_choicePost = wx.wxChoice( Parent, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, UI.m_choicePostChoices, 0 )
		local lookFor = tbl[name]--:gsub("/", "\\")
		local indexOfValue = displayFileNames:Index(lookFor, true, false)
		UI.m_choicePost:SetSelection(indexOfValue)
		UI.m_choicePost:SetBackgroundColour(lightBackground)
		UI.m_choicePost:SetForegroundColour(textColor)
		Sizer:Add( UI.m_choicePost, wx.wxGBPosition( Count, 1 ), wx.wxGBSpan( 1, 1 ), wx.wxALL, 5 )
		UI.m_choicePost:Connect( wx.wxEVT_COMMAND_CHOICE_SELECTED, function(event)
			local selectionNum = UI.m_choicePost:GetSelection()-- + 1
			path = fileNames:Item(selectionNum)
			if wx.wxFileExists(path) then
				tbl[name] = displayFileNames:Item(selectionNum)--path:gsub("\\", "/")
			end
		end)
	end
	SettingsNames["DefaultExtentions"] = AddNameAndDesc("Default File Extentions: ", "The Extentions that converter file dialogs will have on default")
	SettingsNames["LineBlock"] = AddNameAndDesc("Line Parameter: ", "The letter that will be used for line numbers")
	SettingsNames["DefaultMoveType"] = AddNameAndDesc("Default Move Type: ", "Move type to be set in the case a file being converted moves axis before a G move type has been run")
	SettingsNames["PostIdentifier"] = AddNameAndDesc("Converted File Identifier: ", "The comment that will be at the top of every converted file. It will also prevent files with this on the first line from being converted")
	SettingsNames["LineNumber"] = AddNameAndDesc("Start Line Number: ", "The line number that the file will start counting from")
	SettingsNames["Seperator"] = AddNameAndDesc("Parameter Separator: ", "What will go between parameters in a block%(Default is a single space%)")
	SettingsNames["CommentChangeLocation"] = AddNameAndDesc("Change Comment Location: ", "If unchecked comments will stay in the order they come out of the block. If not they will go to the start or end of the block depending on Move Comments to Start of Block")
	SettingsNames["CommentAtStartOfBlock"] = AddNameAndDesc("Move Comments to Start of Block: ", "If checked comments will be moved to start of block, otherwise they will go to the end %(Only takes effect if Change Comment Location is checked%)")
	SettingsNames["ConvertedFilenameAddition"] = AddNameAndDesc("Addition to Converted Filenames: ", "Text added right before file extention for converted files")
	SettingsNames["DefaultFeed"] = AddNameAndDesc("Default Feedrate: ", "Used when feed moves are run before feedrate has been set")
	SettingsNames["scale"] = {}
	SettingsNames["scale"]["C"] = AddNameAndDesc("Scale C: ", "What to scale axis by%(1 means numbers will not change%)")
	SettingsNames["scale"]["Z"] = AddNameAndDesc("Scale Z: ", "What to scale axis by%(1 means numbers will not change%)")
	SettingsNames["scale"]["A"] = AddNameAndDesc("Scale A: ", "What to scale axis by%(1 means numbers will not change%)")
	SettingsNames["scale"]["X"] = AddNameAndDesc("Scale X: ", "What to scale axis by%(1 means numbers will not change%)")
	SettingsNames["scale"]["B"] = AddNameAndDesc("Scale B: ", "What to scale axis by%(1 means numbers will not change%)")
	SettingsNames["scale"]["Y"] = AddNameAndDesc("Scale Y: ", "What to scale axis by%(1 means numbers will not change%)")
	SettingsNames["LineNumberInterval"] = AddNameAndDesc("Line Number Interval: ", "What number to count up by for each line")
	SettingsNames["UnloadFilesFromMach"] = AddNameAndDesc("Unload Files From Mach: ", "Close dGCode files in Mach 4 if that file is being converted")
	SettingsNames["lightBackground"] = false
	SettingsNames["darkBackground"] = false
	SettingsNames["textColor"] = false
	
	local inst = mc.mcGetInstance()
	local machDir = mc.mcCntlGetMachDir(inst)
	local prof = mc.mcProfileGetName(inst)
	local ConfigFileName = machDir.. "\\Profiles\\".. prof .. "\\GCodeConverterSettings\\GCodeConverterConfig.lua" 
	if wx.wxFileExists(ConfigFileName) == true then
		Settings = assert(dofile(ConfigFileName))
	else
		wx.wxMessageBox("Config File Missing at: " .. ConfigFileName)
	end
	if Settings == nil then
		wx.wxMessageBox("Settings load failed. Makes sure the ConverterConfig is in modules.")
	end
	local SettingsLablesSorted = wx.wxArrayString()
	local key = {}
	function labelsToList(tbl, prefix) 
		for name, val in pairs(tbl) do
			local Name = name
			
			if type(val) == "table" then
				if SettingsNames[name] ~= false then
					table.insert(prefix, Name)
					labelsToList(val, prefix)
					prefix = {}
				end
			else
				local settingsTbl = SettingsNames
				local str = ""
				for _, n in pairs(prefix) do
					if settingsTbl[n] == nil then
						str = str .. n
						Name = str
						break
					end
					settingsTbl = settingsTbl[n]
					str = str .. n .. ": "
				end
				settingsTbl = settingsTbl[name]
				if settingsTbl ~= nil and settingsTbl ~= false and settingsTbl.Name ~= nil then
					SettingsLablesSorted:Add(settingsTbl.Name)
					table.insert(prefix, name)
					key[settingsTbl.Name] = prefix 
				end
			end
		end
	end
	for name, val in pairs(Settings) do
		if type(val) == "table" then
			labelsToList(val, {name}) 
		else
			if SettingsNames[name] ~= nil and SettingsNames[name] ~= false and SettingsNames[name].Name ~= nil then
				SettingsLablesSorted:Add(SettingsNames[name].Name)
				key[SettingsNames[name].Name] = {name} 
			end
		end
	end
		
		
	--	if SettingsNames[name] ~= nil and SettingsNames[name].Name ~= nil then
	--		print(SettingsNames[name].Name)
	--		SettingsLablesSorted:Add(SettingsNames[name].Name)
	--		key[SettingsNames[name].Name] = name 
	--	else
	--		if 
	--		SettingsLablesSorted:Add(name)
	--		key[name] = name 
	--	end
	--end

	SettingsLablesSorted:Sort(false)
	local SettingsNamesSorted = wx.wxArrayString()
	for i=0, SettingsLablesSorted:GetCount()-1, 1 do
		local settingsNamesSinglepath = key[SettingsLablesSorted:Item(i)]
		local currentTable = SettingsNames
		--for _, nextKey in pairs(settingsNamesSinglepath) do
		--	currentTable = currentTable[nextKey]
		--end
		--if currentTable.Name ~= nil then
		if settingsNamesSinglepath[1] ~= nil then
			SettingsNamesSorted:Add(settingsNamesSinglepath[1])
		end
	end
	lightBackground = wx.wxColour(Settings.lightBackground)
	darkBackground = wx.wxColour(Settings.darkBackground)
	textColor = wx.wxColour(Settings.textColor)
	if lightBackground:IsOk() ~= true then
		lightBackground = wx.wxColour( 110, 110, 110 )
	end
	if darkBackground:IsOk() ~= true then
		darkBackground = wx.wxColour( 75, 75, 75 )
	end
	if textColor:IsOk() ~= true then
		textColor = wx.wxColour( 255, 255, 255 )
	end
	function SaveOnClose(SettingsTbl, file) 
		local function AddString(tbl, TblStr) 
			local str = ""
			for name, val in pairs(tbl) do
				Name = TblStr .. "[\"" .. name .."\"]"
				if type(val) == "table" then
					str = str .. Name .. " = {}\n"
					str = str .. AddString(val, Name)
				else
					if type(val) == "number" then
						str = str .. Name .. " = " .. tostring(val) .. "\n"
					elseif type(val) == "string" then
						str = str .. Name .. " = \"" .. tostring(val) .. "\"\n"
					elseif type(val) == "boolean" then
						str = str .. Name .. " = " .. tostring(val) .. "\n"
					end
				end
			end
			return str
		end
		local saveFile = "local Settings = {}\n" .. AddString(SettingsTbl, "Settings") .. "return Settings"
		local myfile = io.open(file , "w")
		
		myfile:write(saveFile)
		myfile:flush();
		myfile:close();
	end
	UI = {}
	local iconLoc = mc.mcCntlGetMachDir(inst) .. "\\Mach4_Wizard.ico"
	local icon = wx.wxIcon(iconLoc, wx.wxBITMAP_TYPE_ICO, 32, 32)
	-- create MyFrame1
	UI.MyFrame1 = wx.wxFrame (wx.NULL, wx.wxID_ANY, "GCode Converter Settings", wx.wxDefaultPosition, wx.wxSize( 500,300 ), wx.wxDEFAULT_FRAME_STYLE - wx.wxRESIZE_BORDER+wx.wxTAB_TRAVERSAL )
	UI.MyFrame1:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	UI.MyFrame1:SetFont( wx.wxFont( 12, wx.wxFONTFAMILY_SWISS, wx.wxFONTSTYLE_NORMAL, wx.wxFONTWEIGHT_NORMAL, false, "Arial" ) )
	UI.MyFrame1:SetIcon(icon)
	UI.bSizer1 = wx.wxBoxSizer( wx.wxVERTICAL )

	UI.gbSizer1 = wx.wxGridBagSizer( 0, 0 )
	UI.gbSizer1:SetFlexibleDirection( wx.wxBOTH )
	UI.gbSizer1:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )
	
	local CurrentSettingCount = 0
	function PopulateSettings()
		
		function AddSetting(name, tbl, prefix)
			local settingsTbl = SettingsNames
			local val = tbl[name]
			local tooltip
			local skip
			if settingsTbl[name] ~= nil then
				settingsTbl = settingsTbl[name]
				if settingsTbl ~= false then
					Name = settingsTbl.Name
					tooltip = settingsTbl.Description
				else 
					skip = true
				end
			elseif #prefix > 0 then
				local str = ""
				for _, n in pairs(prefix) do
					if settingsTbl[n] == nil then
						str = str .. n
						Name = str
						break
					end
					settingsTbl = settingsTbl[n]
					str = str .. n .. ": "
				end
				settingsTbl = settingsTbl[name]
				if settingsTbl ~= nil and settingsTbl ~= false then
					Name = settingsTbl.Name
					tooltip = settingsTbl.Description
				elseif settingsTbl == false then
					skip = true
				else
					print(Name)
					print(name)
				end
			end
			if skip ~= true then
				local DisplayFunction
				if settingsTbl.DisplayFunction ~= nil then
					DisplayFunction = settingsTbl["DisplayFunction"]
				end
				local Count = CurrentSettingCount
				UI["SettingsStaticText" .. Count] = wx.wxStaticText( UI.MyFrame1, wx.wxID_ANY, Name, wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
				UI["SettingsStaticText" .. Count]:SetForegroundColour(textColor)
				UI["SettingsStaticText" .. Count]:Wrap( -1 )

				UI.gbSizer1:Add( UI["SettingsStaticText" .. Count], wx.wxGBPosition( Count, 0 ), wx.wxGBSpan( 1, 1 ), wx.wxALL, 5 )
				if DisplayFunction ~= nil then
					Count = DisplayFunction(UI.MyFrame1, UI.gbSizer1, tbl, name, Count)
				elseif type(val) == "boolean" then
					UI["SettingsCheckBox" .. Count] = wx.wxCheckBox( UI.MyFrame1, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
					UI["SettingsCheckBox" .. Count]:SetValue(val)
					UI["SettingsCheckBox" .. Count]:SetBackgroundColour(lightBackground)
					if tooltip ~= nil then
						UI["SettingsCheckBox" .. Count]:SetToolTip(tooltip)
					end
					
					UI.gbSizer1:Add( UI["SettingsCheckBox" .. Count], wx.wxGBPosition( Count, 1 ), wx.wxGBSpan( 1, 1 ), wx.wxALL, 5 )
					 UI["SettingsCheckBox" .. Count]:Connect( wx.wxEVT_COMMAND_CHECKBOX_CLICKED, function(event)
						--implements Checked
						local checked = UI["SettingsCheckBox" .. Count]:GetValue()
						if checked ~= nil then
							tbl[name] = checked
						end
						event:Skip()
					end )
					
				else
					UI["SettingsTextCtrl" .. Count] = wx.wxTextCtrl( UI.MyFrame1, wx.wxID_ANY, tostring(val), wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
					UI["SettingsTextCtrl" .. Count]:SetBackgroundColour(lightBackground)
					UI["SettingsTextCtrl" .. Count]:SetForegroundColour(textColor)
					if tooltip ~= nil then
						UI["SettingsTextCtrl" .. Count]:SetToolTip(tooltip)
					end
					UI.gbSizer1:Add( UI["SettingsTextCtrl" .. Count], wx.wxGBPosition( Count, 1 ), wx.wxGBSpan( 1, 1 ), wx.wxALL + wx.wxEXPAND, 5 )
					
					UI["SettingsTextCtrl" .. Count]:Connect( wx.wxEVT_COMMAND_TEXT_UPDATED, function(event)
						local settingText = UI["SettingsTextCtrl" .. Count]:GetValue()
						if type(val) == "string" then
							if tostring(settingText) ~= nil then
								tbl[name] = tostring(settingText)
							end
						else
							if settingText ~= nil then
								tbl[name] = tonumber(settingText)
							end
						end
					end)
				end
				CurrentSettingCount = CurrentSettingCount + 1
			end
		end
		function populatesettings(tbl, prefix) 
			for name, val in pairs(tbl) do
				local Name = name
				if type(val) == "table" then
					if settingsTbl ~= false then
						table.insert(prefix, Name)
						populatesettings(val, prefix)
						prefix = {}
					else 
						skip = true
					end
				else
					AddSetting(name, tbl, prefix)
				end
			end
		end
		for i=0, SettingsNamesSorted:GetCount()-1, 1 do
			local val = Settings[SettingsNamesSorted:Item(i)]
			if type(val) == "table" then
				populatesettings(val, {SettingsNamesSorted:Item(i)}) 
			else
				AddSetting(SettingsNamesSorted:Item(i), Settings, {})
			end
		end
	end
	PopulateSettings()
	
	UI.FunctionTestBtn = wx.wxButton( UI.MyFrame1, wx.wxID_ANY, "Function Testing Button", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	UI.FunctionTestBtn:SetBackgroundColour(lightBackground)
	UI.FunctionTestBtn:SetForegroundColour(textColor)
	UI.gbSizer1:Add( UI.FunctionTestBtn, wx.wxGBPosition( CurrentSettingCount, 0 ), wx.wxGBSpan( 1, 1 ), wx.wxALL, 5 )
	
	UI.FunctionTestBtn:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
		pcall(GCodeConverter.UnitTestWizard)
		event:Skip()
	end )
	UI.bSizer1:Add( UI.gbSizer1, 1, wx.wxEXPAND, 5 )
	
	UI.MyFrame1:Connect( wx.wxEVT_CLOSE_WINDOW, function(event)
		SaveOnClose(Settings,ConfigFileName) 
		event:Skip()
	end )  
	
	UI.MyFrame1:SetSizer( UI.bSizer1 )
	UI.MyFrame1:Layout()
	UI.MyFrame1:Fit()
	UI.MyFrame1:Centre( wx.wxBOTH )

	UI.MyFrame1:Show()
	wx.wxGetApp():MainLoop()
end
function GCConverter.UnitTestWizard()
	-- returns table of file names in the directory
	function findFiles(machDir, RelativeToRoot) 
		local dirname = machDir .. "\\" .. RelativeToRoot
		local test = wx.wxFindFirstFile(dirname)
		local files = {}
		local fileNames = {}
		if test ~= "" then 
			local loc = string.find(test,RelativeToRoot)+#RelativeToRoot
			table.insert(fileNames, tostring(test):sub(loc, -1 ))
			table.insert(files, tostring(test))
		else
			return
		end
		repeat
			test = wx.wxFindNextFile()
			if test ~= "" then 
				local loc = string.find(test, RelativeToRoot)+#RelativeToRoot
				table.insert(fileNames, tostring(test):sub(loc, -1 ))
				table.insert(files, tostring(test))
			end 
		until(tostring(test) == "") 
		return files, fileNames
	end
	function GetPostFiles(tbl)
		local Files = wx.wxArrayString()
		for i=2, #tbl, 1 do
			Files:Add(tbl[i])
		end
		Files:Sort(false)
		Files:Insert(tbl[1], 0)
		return Files
	end
	function getIndexOfAction(tbl, target)
		return tbl:Index(target, true, false) + 1
	end
	function GetTableNames(path)
		PostTable = assert(dofile(path))
		UI.m_treeCtrl1:DeleteAllItems ()
		local root = UI.m_treeCtrl1:AddRoot("Modifier Functions", -1, -1)
		
		local names = {}
		for name, tbl in pairs(PostTable.Modifiers) do
			table.insert(names, name)
			local parent = UI.m_treeCtrl1:AppendItem (root, tostring(name), -1, -1)
			for branchName, val in pairs(tbl) do
				UI.m_treeCtrl1:AppendItem (parent, tostring(branchName), -1, -1)
			end
			
		end
		UI.m_treeCtrl1:Expand (root)
		return names
	end
	local PulledFuncStartLoc
	local PulledFuncEndLoc
	function getFuncFromFile(path, tableName, functionNumber)
		local luafile = assert(io.open(path, "r"))
		local file = luafile:read("*all")
		local start = 0
		--print(tableName)
		local _, Location = string.find(file, "%[\"" .. tableName .. "\"%]")
		--print(Location)
		Func = string.sub(file, Location)
		--print(file)
		start = start + Location
		PulledFuncEndLoc = string.find(Func, "},")
		--
		Func = string.sub(Func, 0, PulledFuncEndLoc)
		--print(file)
		local s, funcLocation = string.find(Func, "%[" .. tostring(functionNumber) .. "%].-end,")
		if s == nil then
			s = string.find(Func, "%[" .. tostring(functionNumber) .. "%]")
			if s == nil then
				return 
			end
			funcLocation = PulledFuncEndLoc-2
		end
		start = start + s
		news = string.sub(Func, s, funcLocation)
		beforefunc = string.find(news, "function", 0)
		start = start + beforefunc
		news = string.sub(news, beforefunc)
		return news, start-3, start + string.len(news)-2, file
	end
	local RelativeToRoot = "PostFiles\\"
	local inst = mc.mcGetInstance()
	local fileNames, displayFileNames = findFiles(mc.mcCntlGetMachDir(inst), RelativeToRoot)
	if fileNames == nil then 
		mc.mcCntlSetLastError(inst, "No files in" .. RelativeToRoot .. "directory")
		wx.wxMessageBox("No files in " .. RelativeToRoot .. " directory")
		return 
	end
	table.insert(fileNames, 1, "Choose a POST file to load")
	table.insert(displayFileNames, 1, "Choose a POST file to load")
	displayFileNames = GetPostFiles(displayFileNames)
	fileNames = GetPostFiles(fileNames)
	local path
	local iconLoc = mc.mcCntlGetMachDir(inst) .. "\\Mach4_Wizard.ico"
	local icon = wx.wxIcon(iconLoc, wx.wxBITMAP_TYPE_ICO, 32, 32)
	UI = {}

	-- create MyFrame1
	UI.MyFrame1 = wx.wxFrame (wx.NULL, wx.wxID_ANY, "Post Function Modifier", wx.wxDefaultPosition, wx.wxSize( 1000,600 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
	UI.MyFrame1:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )
	UI.MyFrame1:SetIcon(icon)

	UI.bSizer1 = wx.wxBoxSizer( wx.wxVERTICAL )

	UI.m_staticTextInput = wx.wxStaticText( UI.MyFrame1, wx.wxID_ANY, "Input GCODE to Test", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	UI.m_staticTextInput:Wrap( -1 )

	UI.bSizer1:Add( UI.m_staticTextInput, 0, wx.wxALL + wx.wxALIGN_CENTER_HORIZONTAL, 5 )

	UI.m_textCtrlInput = wx.wxTextCtrl( UI.MyFrame1, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize( 600,100 ), wx.wxTE_MULTILINE )
	UI.bSizer1:Add( UI.m_textCtrlInput, 0, wx.wxALL + wx.wxALIGN_CENTER_HORIZONTAL, 5 )

	UI.m_staticTextCode = wx.wxStaticText( UI.MyFrame1, wx.wxID_ANY, "Select the a POST file and a table to edit from the list", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	UI.m_staticTextCode:Wrap( -1 )

	UI.bSizer1:Add( UI.m_staticTextCode, 0, wx.wxALL + wx.wxALIGN_CENTER_HORIZONTAL, 5 )

	UI.m_choicePostChoices = displayFileNames
	UI.m_choicePost = wx.wxChoice( UI.MyFrame1, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, UI.m_choicePostChoices, 0 )
	UI.m_choicePost:SetSelection( 0 )
	UI.bSizer1:Add( UI.m_choicePost, 0, wx.wxALL + wx.wxALIGN_CENTER_HORIZONTAL, 5 )
	
	UI.bSizer2 = wx.wxBoxSizer( wx.wxHORIZONTAL )

	UI.m_treeCtrl1 = wx.wxTreeCtrl( UI.MyFrame1, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxTR_DEFAULT_STYLE )
	UI.bSizer2:Add( UI.m_treeCtrl1, 0, wx.wxALL+ wx.wxEXPAND, 5 )

	UI.m_textCtrlCode = wx.wxTextCtrl( UI.MyFrame1, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize( 775,-1 ), wx.wxTE_MULTILINE )
	UI.bSizer2:Add( UI.m_textCtrlCode, 0, wx.wxALL + wx.wxEXPAND, 5 )


	UI.bSizer2:Add( 0, 0, 1, wx.wxEXPAND, 5 )

	UI.GenerateButton = wx.wxButton( UI.MyFrame1, wx.wxID_ANY, "Regen", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	UI.bSizer2:Add( UI.GenerateButton, 0, wx.wxALL + wx.wxALIGN_CENTER_VERTICAL, 5 )

	UI.bSizer1:Add( UI.bSizer2, 1, wx.wxEXPAND, 5 )

	UI.m_staticTextOutput = wx.wxStaticText( UI.MyFrame1, wx.wxID_ANY, "Output", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	UI.m_staticTextOutput:Wrap( -1 )

	UI.bSizer1:Add( UI.m_staticTextOutput, 0, wx.wxALL + wx.wxALIGN_CENTER_HORIZONTAL, 5 )

	UI.m_textCtrlOutput = wx.wxTextCtrl( UI.MyFrame1, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxSize( 600,100 ), wx.wxTE_MULTILINE )
	UI.bSizer1:Add( UI.m_textCtrlOutput, 0,  wx.wxALL + wx.wxALIGN_CENTER_VERTICAL + wx.wxALIGN_CENTER_HORIZONTAL, 5 )


	UI.MyFrame1:SetSizer( UI.bSizer1 )
	UI.MyFrame1:Layout()
	--UI.MyFrame1:Fit()
	UI.MyFrame1:Centre( wx.wxBOTH )
	UI.m_choicePost:Connect( wx. wxEVT_COMMAND_CHOICE_SELECTED, function(event)
		local selectionNum = UI.m_choicePost:GetSelection()
		path = fileNames:Item(selectionNum)
		if wx.wxFileExists(path) then
			TableNames = GetTableNames(path)
		end
	end )
	local WholeFile
	UI.m_treeCtrl1:Connect( wx.wxEVT_COMMAND_TREE_SEL_CHANGED, function(event)
		--implements m_treeCtrl1OnTreeSelChanged
		local item = event:GetItem()
		currentItemNum = tonumber(UI.m_treeCtrl1:GetItemText(item))
		if currentItemNum ~= nil then
			local parent = UI.m_treeCtrl1:GetItemParent(item)
			currentItemstr = UI.m_treeCtrl1:GetItemText(parent)
			str, Start, End, WholeFile = getFuncFromFile(path, currentItemstr, currentItemNum)
			if str ~= nil then
				UI.m_textCtrlCode:SetValue(str)
			end
			--print(str)
		end
		--getTablesFromFile(path)
		event:Skip()
	end )
--wx.wxMessageBox("this is a message box")
	UI.GenerateButton:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
		--implements BtnClick
		if currentItemstr ~= nil then
			local beggining = string.sub(WholeFile, 0, Start)
			local Ending = string.sub(WholeFile, End)
			FunctionText = UI.m_textCtrlCode:GetValue()
			newStr = beggining .. FunctionText .. Ending
			local func, rc = load(newStr)
			if func == nil then
				return
			end
			PostTable = func()
		end
		--local EditedFunction = UI.m_textCtrlCode:GetValue()
		--local newfunc = load(EditedFunction)
		--PostTable.Modifiers[currentItemstr][currentItemNum] = newfunc
		if PostTable.Settings == nil then
			PostTable.Settings = {}
		end
		PostTable.Settings.TestRunning = true
		InputText = UI.m_textCtrlInput:GetValue()
		local ConvertedString = GCodeConverter.ConvertFiles(InputText, "", PostTable)
		UI.m_textCtrlOutput:SetValue(ConvertedString)

		event:Skip()
	end )

	UI.MyFrame1:Show()
	wx.wxGetApp():MainLoop()
end
return GCConverter
