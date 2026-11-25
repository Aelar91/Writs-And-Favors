local _, ns = ...
local D = ns.D
local Net = {}
ns.Net = Net

local INF = math.huge
local floor = math.floor
local full = { T = D.T, F = D.F, P = D.P, S = D.S }
local current = 'all'

local function round(x) return floor(x + 0.5) end

local function flights(known)
	local adj = {}
	for _, l in ipairs(D.G.legs) do
		if known[l[1]] and known[l[2]] then
			adj[l[1]] = adj[l[1]] or {}
			table.insert(adj[l[1]], l)
		end
	end
	local fly = {}
	for a in pairs(adj) do
		local d, g, done = { [a] = 0 }, { [a] = 0 }, {}
		while true do
			local u
			for k, v in pairs(d) do if not done[k] and (not u or v < d[u] or (v == d[u] and k < u)) then u = k end end
			if not u then break end
			done[u] = true
			for _, l in ipairs(adj[u] or {}) do
				local t = d[u] + l[3]
				if not d[l[2]] or t < d[l[2]] then d[l[2]], g[l[2]] = t, g[u] + l[4] end
			end
		end
		local out = {}
		for b, t in pairs(d) do if b ~= a then out[#out + 1] = { b, t, g[b] } end end
		fly[a] = out
	end
	return fly
end

local hopAt
local function flyHop(a, b)
	local na, nb = D.nodes[a], D.nodes[b]
	if not hopAt then
		hopAt = {}
		for i, h in ipairs(D.hops) do if h[1] == 'fly' then hopAt[h[2] .. '|' .. h[3]] = i end end
	end
	local k = na[1] .. '|' .. nb[1]
	if not hopAt[k] then
		D.hops[#D.hops + 1] = { 'fly', na[1], nb[1], na[2], na[3], na[4], na[5] }
		hopAt[k] = #D.hops
	end
	return hopAt[k]
end

local function edges(known)
	local G, E = D.G, {}
	for i = 1, G.n do
		local r, out = G.rides[i] or {}, {}
		for k = 1, #r, 3 do out[#out + 1] = { r[k], r[k + 1], r[k + 2], 0 } end
		E[i] = out
	end
	for _, b in ipairs(G.boats) do table.insert(E[b[1]], { b[2], b[3], b[3], 0, b[4] }) end
	for a, list in pairs(flights(known)) do
		for _, f in ipairs(list) do
			local t = f[2] + G.takeoff
			table.insert(E[G.fp[a]], { G.fp[f[1]], t, t, f[3], { a, f[1] } })
		end
	end
	return E
end

local function rowFrom(E, src, places)
	local G = D.G
	local n, d, prev, via, done = G.n, {}, {}, {}, {}
	d[src] = 0
	while true do
		local u, best = nil, INF
		for i = 1, n do local x = d[i]; if x and not done[i] and x < best then u, best = i, x end end
		if not u then break end
		done[u] = true
		for _, e in ipairs(E[u]) do
			local t = best + e[2]
			local v = e[1]
			if not d[v] or t < d[v] then d[v], prev[v], via[v] = t, u, e end
		end
	end
	local T, F, P = {}, {}, {}
	for j = 1, places do
		local v = G.place + j
		if not d[v] then
			T[j], F[j], P[j] = -1, 0, ''
		else
			local sec, fare, hops = 0, 0, {}
			while v ~= src do
				local e = via[v]
				sec, fare = sec + e[3], fare + e[4]
				local h = e[5]
				if h then table.insert(hops, 1, type(h) == 'table' and flyHop(h[1], h[2]) or h) end
				v = prev[v]
			end
			T[j], F[j], P[j] = round(sec), round(fare), table.concat(hops, '.')
		end
	end
	return T, F, P
end

local function keyOf(known)
	local ids = {}
	for id in pairs(D.nodes) do if known[id] then ids[#ids + 1] = id end end
	table.sort(ids)
	return table.concat(ids, ','), #ids
end

function Net.Use(known)
	local key, n = 'all', 0
	if known and D.G then
		key, n = keyOf(known)
		local total = 0
		for _ in pairs(D.nodes) do total = total + 1 end
		if n == total then key = 'all' end
	end
	if key == current then return false end
	current = key
	if key == 'all' then
		D.T, D.F, D.P, D.S = full.T, full.F, full.P, full.S
		return true
	end
	local E, places = edges(known), #D.places
	local rows = {}
	local function lazy(k)
		return setmetatable({}, { __index = function(t, i)
			if type(i) ~= 'number' or i < 1 or i > places then return nil end
			if not rows[i] then rows[i] = { rowFrom(E, D.G.place + i, places) } end
			rawset(t, i, rows[i][k])
			return rows[i][k]
		end })
	end
	D.T, D.F, D.P = lazy(1), lazy(2), lazy(3)
	D.S = setmetatable({}, { __index = function(t, id)
		local v = D.G.fp[id]
		if not v then return nil end
		local T, F, P = rowFrom(E, v, places)
		local r = { T = T, F = F, P = P }
		rawset(t, id, r)
		return r
	end })
	return true
end
function Net.Key() return current end
function Net.Full() return full end
function Net.Compute(known)
	local E, places, T, F, P = edges(known), #D.places, {}, {}, {}
	for i = 1, places do T[i], F[i], P[i] = rowFrom(E, D.G.place + i, places) end
	return T, F, P
end
