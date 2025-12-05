mcCO = {}
function mcCO.AddCoroutineToTable(tbl)
	tbl.ContinueCoroutine = false -- for resuming coroutine
	tbl.DialogReturn = nil
	function tbl.CheckCoroutine()
		if tbl.CoroutineFunction ~= nil then
			tbl.Coroutine = coroutine.create(tbl.CoroutineFunction)
			tbl.CoroutineFunction = nil
			tbl.ContinueCoroutine = false
			coroutine.resume(tbl.Coroutine, tbl)
		end
		--if a button was pressed, and coroutiune is suspened
		if tbl.Coroutine ~= nil then
			if coroutine.status(tbl.Coroutine) == 'suspended' then
				if tbl.ContinueCoroutine == true then
					tbl.ContinueCoroutine = false
					coroutine.resume(tbl.Coroutine)
				end
			elseif coroutine.status(tbl.Coroutine) == "dead" then
				tbl.Coroutine = nil
			end
		end
	end
end
return mcCO