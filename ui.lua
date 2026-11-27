
local antitamper = {}

local coregui = game:GetService("CoreGui")

local function first(...)
	for _, f in ipairs({ ... }) do
		if type(f) == "function" then return f end
	end
end

local isexecclosure = first(isexecutorclosure, is_executor_closure, isourclosure, is_synapse_function)
local getinfo = first(getinfo, debug and debug.getinfo)
local getconstants = first(getconstants, debug and debug.getconstants)
local islclosure = first(islclosure, is_l_closure)

local pristine = {}

function antitamper.snapshot()
	pcall(function()
		pristine.request = (syn or http).request
		pristine.namecall = getrawmetatable(game).__namecall
		pristine.httpget = game.HttpGet
		pristine.httppost = game.HttpPost
		pristine.getobjects = game.GetObjects
		pristine.requestglobal = request
	end)
end

antitamper.snapshot()

function antitamper.ishooked(f, pristineref)
	if type(f) ~= "function" then return false, "missing" end
	if pristineref and f ~= pristineref then
		return true, "reference replaced"
	end
	if isexecclosure and isexecclosure(f) then
		return true, "executor closure where engine/c function expected"
	end
	return false
end

function antitamper.checknamecall()
	local nc = getrawmetatable(game).__namecall
	if type(nc) ~= "function" then return false end
	if pristine.namecall and nc ~= pristine.namecall then
		return true, "namecall reference changed"
	end
	local info = getinfo and getinfo(nc)
	if info and info.what == "Lua" then
		return true, "namecall is a lua closure"
	end
	if isexecclosure and isexecclosure(nc) then
		return true, "namecall is an executor closure"
	end
	return false
end

function antitamper.checkrequestglobal()
	if type(request) == "function" and type(pristine.request) == "function"
		and request == pristine.request and pristine.requestglobal ~= nil
		and pristine.requestglobal ~= request then
		return true, "global 'request' was replaceclosure'd"
	end
	return false
end

local spy_strings = {
	"httpSpy", "notdsf", "leopard-syn.lua", "eleutheri.com",
	"zezlm2hphvgjrd6op8a3aeszpnew8oxgb",
}

function antitamper.scancoregui()
	local hits = {}
	pcall(function()
		for _, inst in ipairs(coregui:GetDescendants()) do
			if inst:IsA("ScreenGui") and inst.Name == "HttpSpyGui" then
				table.insert(hits, inst:GetFullName())
			elseif inst:IsA("TextLabel") and inst.Text:find("HttpSpy", 1, true) then
				table.insert(hits, inst:GetFullName())
			end
		end
	end)
	return hits
end

function antitamper.scangc()
	local hits = {}
	if not (getgc and getconstants and islclosure) then return hits end
	for _, v in pairs(getgc(true)) do
		if type(v) == "function" and islclosure(v) then
			local ok, consts = pcall(getconstants, v)
			if ok and type(consts) == "table" then
				for _, c in ipairs(consts) do
					if type(c) == "string" then
						for _, sig in ipairs(spy_strings) do
							if c:find(sig, 1, true) then
								table.insert(hits, sig)
								break
							end
						end
					end
				end
			end
		end
	end
	return hits
end

function antitamper.scanlogs()
	local hits = {}
	if not (isfile and listfiles) then return hits end
	local pattern = tostring(game.PlaceId) .. "%-.*%-log%.txt"
	pcall(function()
		for _, path in ipairs(listfiles("")) do
			local name = path:match("[^/\\]+$")
			if name and name:find(pattern) and isfile(path) then
				table.insert(hits, path)
			end
		end
	end)
	return hits
end

function antitamper.sweep()
	local report = { tampered = false, findings = {} }

	local function add(cat, detail)
		report.tampered = true
		table.insert(report.findings, string.format("[%s] %s", cat, tostring(detail)))
	end

	local req = (syn or http) and (syn or http).request
	if req then
		local hooked, why = antitamper.ishooked(req, pristine.request)
		if hooked then add("request", why) end
	end

	for _, m in ipairs({ "HttpGet", "HttpPost", "GetObjects" }) do
		local f = game[m]
		local key = string.lower(m)
		if type(f) == "function" then
			local hooked, why = antitamper.ishooked(f, pristine[key])
			if hooked then add(m, why) end
		end
	end

	local h, d = antitamper.checknamecall()
	if h then add("namecall", d) end

	h, d = antitamper.checkrequestglobal()
	if h then add("request-global", d) end

	for _, g in ipairs(antitamper.scancoregui()) do add("gui", g) end
	for _, s in ipairs(antitamper.scangc()) do add("gc", s) end
	for _, f in ipairs(antitamper.scanlogs()) do add("logfile", f) end

	return report
end

local seen = {}

function antitamper.watch(interval, ondetect)
	task.spawn(function()
		while task.wait(interval or 5) do
			local report = antitamper.sweep()
			if report.tampered then
				for _, finding in ipairs(report.findings) do
					if not seen[finding] then
						seen[finding] = true
						pcall(ondetect, finding, report)
					end
				end
			end
		end
	end)
end

return antitamper
