-- Semantic equivalence check: run hyprland.lua against a recording mock of the
-- `hl` API, parse hyprland.conf, normalise both into the same record strings,
-- and diff them category by category.
-- usage: lua conf-lua-equiv.lua hyprland.conf hyprland.lua  (nix flake check runs it)
local confPath, luaPath = arg[1], arg[2]

local function normnum(v)
	local n = tonumber(v)
	if n then
		return string.format("%.6g", n)
	end
	return v
end
local function normval(v)
	if type(v) == "boolean" then
		return tostring(v)
	end
	if type(v) == "number" then
		return normnum(v)
	end
	if type(v) == "table" and v.colors then
		return table.concat(v.colors, " ") .. " " .. normnum(v.angle or 0) .. "deg"
	end
	v = tostring(v):gsub("^%s+", ""):gsub("%s+$", "")
	return normnum(v)
end
local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
local function collapse(s)
	return trim(s):gsub("%s+", " ")
end
local function mods(s)
	local t = {}
	for m in s:gmatch("[^%s+]+") do
		t[#t + 1] = m:upper()
	end
	table.sort(t)
	return table.concat(t, "+")
end

---------------------------------------------------------------- Lua side
local L = {
	opt = {},
	bind = {},
	env = {},
	exec = {},
	monitor = {},
	curve = {},
	anim = {},
	gesture = {},
	wrule = {},
	lrule = {},
}
local curSubmap = ""
local function flatten(prefix, t, out)
	for k, v in pairs(t) do
		local key = prefix == "" and k or (prefix .. "." .. k)
		if type(v) == "table" and not v.colors then
			flatten(key, v, out)
		else
			out[#out + 1] = key .. " = " .. normval(v)
		end
	end
end
local function D(name, arg)
	return { __dsp = name, arg = arg }
end
local dsp = {
	exec_cmd = function(c)
		return D("exec", c)
	end,
	layout = function(m)
		return D("layoutmsg", m)
	end,
	exit = function()
		return D("exit", "")
	end,
	submap = function(n)
		return D("submap", n)
	end,
	focus = function(t)
		if t.direction then
			return D("movefocus", t.direction:sub(1, 1))
		end
		if t.workspace then
			return D("workspace", tostring(t.workspace))
		end
		error("focus: unhandled")
	end,
	window = {
		close = function()
			return D("killactive", "")
		end,
		float = function(t)
			assert(not t or t.action == nil or t.action == "toggle")
			return D("togglefloating", "")
		end,
		fullscreen = function(t)
			return D("fullscreen", (t.mode == "maximized") and "1" or "0")
		end,
		pin = function()
			return D("pin", "")
		end,
		drag = function()
			return D("movewindow", "")
		end,
		resize = function(t)
			if t == nil then
				return D("resizewindow", "")
			end
			assert(t.relative == true)
			return D("resizeactive", t.x .. " " .. t.y)
		end,
		move = function(t)
			if t.direction then
				return D("movewindow", t.direction:sub(1, 1))
			end
			if t.workspace then
				return D(t.follow == false and "movetoworkspacesilent" or "movetoworkspace", tostring(t.workspace))
			end
			error("move: unhandled")
		end,
	},
	group = {
		toggle = function()
			return D("togglegroup", "")
		end,
		next = function()
			return D("changegroupactive", "f")
		end,
		prev = function()
			return D("changegroupactive", "b")
		end,
	},
	workspace = {
		toggle_special = function(n)
			return D("togglespecialworkspace", n)
		end,
	},
}
local function rulestr(r)
	if not r then
		return ""
	end
	local t = {}
	for k, v in pairs(r) do
		t[#t + 1] = k .. "=" .. normval(v)
	end
	table.sort(t)
	return "[" .. table.concat(t, ";") .. "] "
end
hl = {
	dsp = dsp,
	config = function(t)
		flatten("", t, L.opt)
	end,
	env = function(k, v)
		L.env[#L.env + 1] = k .. "=" .. v
	end,
	monitor = function(t)
		L.monitor[#L.monitor + 1] = table.concat({ t.output, t.mode, t.position, normval(t.scale) }, "|")
	end,
	curve = function(n, t)
		assert(t.type == "bezier")
		L.curve[#L.curve + 1] = n
			.. "|"
			.. table.concat(
				{ normval(t.points[1][1]), normval(t.points[1][2]), normval(t.points[2][1]), normval(t.points[2][2]) },
				"|"
			)
	end,
	animation = function(t)
		L.anim[#L.anim + 1] =
			table.concat({ t.leaf, tostring(t.enabled), normval(t.speed), t.bezier or "", t.style or "" }, "|")
	end,
	gesture = function(t)
		L.gesture[#L.gesture + 1] = table.concat({ t.fingers, t.direction, t.action }, "|")
	end,
	on = function(ev, fn)
		assert(ev == "hyprland.start")
		local real = hl.exec_cmd
		fn()
	end,
	exec_cmd = function(c, r)
		L.exec[#L.exec + 1] = rulestr(r) .. c
	end,
	define_submap = function(name, fn)
		curSubmap = name
		fn()
		curSubmap = ""
	end,
	bind = function(keys, d, opts)
		local parts = {}
		for p in keys:gmatch("[^+]+") do
			parts[#parts + 1] = trim(p)
		end
		local key = table.remove(parts)
		local fl = {}
		opts = opts or {}
		if opts.repeating then
			fl[#fl + 1] = "e"
		end
		if opts.locked then
			fl[#fl + 1] = "l"
		end
		if opts.mouse then
			fl[#fl + 1] = "m"
		end
		local arg = d.__dsp == "exec" and trim(d.arg) or collapse(d.arg)
		L.bind[#L.bind + 1] =
			table.concat({ curSubmap, mods(table.concat(parts, " ")), key, table.concat(fl), d.__dsp, arg }, " | ")
		return {}
	end,
	window_rule = function(t)
		local out = {}
		flatten("", t, out)
		table.sort(out)
		L.wrule[#L.wrule + 1] = table.concat(out, "; ")
		return {}
	end,
	layer_rule = function(t)
		local out = {}
		flatten("", t, out)
		table.sort(out)
		L.lrule[#L.lrule + 1] = table.concat(out, "; ")
		return {}
	end,
}
dofile(luaPath)

---------------------------------------------------------------- conf side
local C = {
	opt = {},
	bind = {},
	env = {},
	exec = {},
	monitor = {},
	curve = {},
	anim = {},
	gesture = {},
	wrule = {},
	lrule = {},
}
local vars, varnames = {}, {}
local stack, rule, submap = {}, nil, ""
local function subst(s)
	table.sort(varnames, function(a, b)
		return #a > #b
	end)
	for _, n in ipairs(varnames) do
		s = s:gsub("%$" .. n:gsub("%p", "%%%0"), (vars[n]:gsub("%%", "%%%%")))
	end
	return s
end
for raw in io.lines(confPath) do
	local line = trim((raw:gsub("#.*$", "")))
	if line == "" then
		goto continue
	end
	local block = line:match("^([%w_.:-]+)%s*{$")
	if block then
		if block == "windowrule" or block == "layerrule" then
			rule = { kind = block, kv = {} }
		else
			stack[#stack + 1] = block
		end
		goto continue
	end
	if line == "}" then
		if rule then
			local out = {}
			for k, v in pairs(rule.kv) do
				out[#out + 1] = k .. " = " .. v
			end
			table.sort(out)
			local dst = rule.kind == "windowrule" and C.wrule or C.lrule
			dst[#dst + 1] = table.concat(out, "; ")
			rule = nil
		else
			table.remove(stack)
		end
		goto continue
	end
	local k, v = line:match("^([^=]-)%s*=%s*(.*)$")
	k = trim(k)
	local vn = k:match("^%$(.+)$")
	if vn then
		vars[vn] = subst(v)
		varnames[#varnames + 1] = vn
		goto continue
	end
	v = subst(v)
	if rule then
		rule.kv[(k:gsub("^match:", "match."))] = normval(v)
	elseif #stack > 0 then
		if k == "bezier" then
			local p = {}
			for x in v:gmatch("[^,]+") do
				p[#p + 1] = trim(x)
			end
			C.curve[#C.curve + 1] = p[1]
				.. "|"
				.. normnum(p[2])
				.. "|"
				.. normnum(p[3])
				.. "|"
				.. normnum(p[4])
				.. "|"
				.. normnum(p[5])
		elseif k == "animation" then
			local p = {}
			for x in v:gmatch("[^,]+") do
				p[#p + 1] = trim(x)
			end
			C.anim[#C.anim + 1] =
				table.concat({ p[1], p[2] == "1" and "true" or "false", normnum(p[3]), p[4] or "", p[5] or "" }, "|")
		else
			local val = v:match("^(rgba%b() rgba%b()) (%d+)deg$")
			if val then
				local cols, ang = v:match("^(rgba%b() rgba%b()) (%d+)deg$")
				v = cols .. " " .. normnum(ang) .. "deg"
			end
			C.opt[#C.opt + 1] = table.concat(stack, ".") .. "." .. k:gsub("-", "_") .. " = " .. normval(v)
		end
	elseif k == "monitor" then
		local p = {}
		for x in (v .. ","):gmatch("([^,]*),") do
			p[#p + 1] = trim(x)
		end
		C.monitor[#C.monitor + 1] = table.concat({ p[1], p[2], p[3], normnum(p[4]) }, "|")
	elseif k == "env" then
		local a, b = v:match("^([^,]+),(.*)$")
		C.env[#C.env + 1] = trim(a) .. "=" .. trim(b)
	elseif k == "exec-once" then
		local r, cmd = v:match("^%[(.-)%]%s*(.*)$")
		if r then
			local rk, rv = r:match("^(%S+)%s+(.*)$")
			C.exec[#C.exec + 1] = "[" .. rk .. "=" .. rv .. "] " .. cmd
		else
			C.exec[#C.exec + 1] = v
		end
	elseif k == "gesture" then
		local p = {}
		for x in v:gmatch("[^,]+") do
			p[#p + 1] = trim(x)
		end
		C.gesture[#C.gesture + 1] = table.concat(p, "|")
	elseif k == "submap" then
		submap = (v == "reset") and "" or v
	elseif k:match("^bind") then
		local fl = k:sub(5)
		local f = {}
		for _, c in ipairs({ "e", "l", "m" }) do
			if fl:find(c) then
				f[#f + 1] = c
			end
		end
		local m, key, disp, a = v:match("^([^,]*),([^,]*),([^,]*),?(.*)$")
		disp = trim(disp)
		local arg = disp == "exec" and trim(a) or collapse(a)
		C.bind[#C.bind + 1] = table.concat({ submap, mods(m), trim(key), table.concat(f), disp, arg }, " | ")
	else
		error("unhandled conf line: " .. line)
	end
	::continue::
end

---------------------------------------------------------------- diff
local total_bad = 0
local function multiset(list)
	local m = {}
	for _, x in ipairs(list) do
		m[x] = (m[x] or 0) + 1
	end
	return m
end
local order = { "monitor", "env", "exec", "opt", "curve", "anim", "gesture", "bind", "wrule", "lrule" }
for _, cat in ipairs(order) do
	local a, b = multiset(C[cat]), multiset(L[cat])
	local bad = {}
	for x, n in pairs(a) do
		if (b[x] or 0) ~= n then
			bad[#bad + 1] = "  only/more in conf: " .. x
		end
	end
	for x, n in pairs(b) do
		if (a[x] or 0) ~= n then
			bad[#bad + 1] = "  only/more in lua:  " .. x
		end
	end
	-- ordered comparison too (binds/rules: order matters for precedence)
	local sameOrder = #C[cat] == #L[cat]
	if sameOrder then
		for i = 1, #C[cat] do
			if C[cat][i] ~= L[cat][i] then
				sameOrder = false
			end
		end
	end
	print(
		string.format(
			"%-8s conf=%3d lua=%3d  %s%s",
			cat,
			#C[cat],
			#L[cat],
			#bad == 0 and "MATCH" or "MISMATCH",
			(cat == "opt") and "" or (sameOrder and " (same order)" or " (ORDER DIFFERS)")
		)
	)
	table.sort(bad)
	for _, x in ipairs(bad) do
		print(x)
	end
	total_bad = total_bad + #bad
end
if os.getenv("DUMP") then
	for _, x in ipairs(C.bind) do
		print("conf bind: " .. x)
	end
end
os.exit(total_bad == 0 and 0 or 1)
