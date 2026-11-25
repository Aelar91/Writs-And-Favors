local _, ns = ...
local D = ns.D
local Plan = {}
ns.Plan = Plan

local INF = math.huge
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local band, bor, lshift, bnot = bit.band, bit.bor, bit.lshift, bit.bnot

function Plan.Travel(start)
	local S = D.S[start] or D.S[D.home or 23]
	local function sec(a, b)
		if a == b then return 0 end
		local t = a == 0 and S.T[b] or D.T[a][b]
		return (t and t >= 0) and t or INF
	end
	local function fare(a, b)
		if a == b then return 0 end
		return (a == 0 and S.F[b] or D.F[a][b]) or 0
	end
	return sec, fare
end

function Plan.BestOrder(rows, cf, from)
	from = from or 0
	local n = #rows
	if n == 0 then return {} end
	if n <= 10 then
		local full = lshift(1, n) - 1
		local dp, par = {}, {}
		for m = 1, full do dp[m], par[m] = {}, {} end
		for k = 1, n do dp[lshift(1, k - 1)][k] = cf(from, rows[k]) end
		for m = 1, full do
			local dm = dp[m]
			for k = 1, n do
				local dk = dm[k]
				if dk and band(m, lshift(1, k - 1)) ~= 0 then
					for j = 1, n do
						local bj = lshift(1, j - 1)
						if band(m, bj) == 0 then
							local t = dk + cf(rows[k], rows[j])
							local mj = bor(m, bj)
							if not dp[mj][j] or t < dp[mj][j] then dp[mj][j], par[mj][j] = t, k end
						end
					end
				end
			end
		end
		local k = 1
		for j = 2, n do if (dp[full][j] or INF) < (dp[full][k] or INF) then k = j end end
		local out, m = {}, full
		while k do
			table.insert(out, 1, rows[k])
			local p = par[m][k]
			m = band(m, bnot(lshift(1, k - 1)))
			k = p
		end
		return out
	end
	local left, out, at = {}, {}, from
	for i = 1, n do left[i] = rows[i] end
	while #left > 0 do
		local bi = 1
		for i = 2, #left do if cf(at, left[i]) < cf(at, left[bi]) then bi = i end end
		at = table.remove(left, bi)
		out[#out + 1] = at
	end
	local pre = {}
	local function measure()
		local t, prev = 0, from
		for k = 1, n do t = t + cf(prev, out[k]); pre[k] = t; prev = out[k] end
		return t
	end
	local cur = measure()
	local better = true
	while better do
		better = false
		for i = 1, n - 1 do
			for j = i + 1, n do
				local limit = cur - 1e-6
				local t, prev = i > 1 and pre[i - 1] or 0, i > 1 and out[i - 1] or from
				local k = j
				while k >= i and t < limit do t = t + cf(prev, out[k]); prev = out[k]; k = k - 1 end
				if k < i then
					k = j + 1
					while k <= n and t < limit do t = t + cf(prev, out[k]); prev = out[k]; k = k + 1 end
					if k > n and t < limit then
						local a, b = i, j
						while a < b do out[a], out[b] = out[b], out[a]; a, b = a + 1, b - 1 end
						cur, better = measure(), true
					end
				end
			end
		end
	end
	return out
end

local costOf
function Plan.CostOf(p, n) return costOf(p, n) end
function costOf(p, n)
	if not p then return nil end
	if p.ladder and #p.ladder > 0 then
		local left, c = n, 0
		for _, l in ipairs(p.ladder) do
			local take = min(left, l[2])
			c, left = c + take * l[1], left - take
			if left <= 0 then return c end
		end
		return nil -- not enough up
	end
	return p.each and p.each * n or nil
end
Plan.CostOf = costOf

Plan.ZONE_LEVEL = {
	[1413] = 10, [1421] = 10, [1432] = 10, [1436] = 10, [1439] = 10, [1433] = 15, [1442] = 15, -- Barrens, Silverpine, Loch Modan, Westfall, Darkshore, Redridge, Stonetalon
	[1440] = 19, [1431] = 19, [1424] = 20, [1437] = 20, [1441] = 24, [1416] = 27, -- Ashenvale, Duskwood, Hillsbrad, Wetlands, Thousand Needles, Alterac
	[1417] = 30, [1443] = 30, [1434] = 30, [1445] = 36, [1435] = 36, [1418] = 36, [2548] = 36, -- Arathi, Desolace, Stranglethorn, Dustwallow, Swamp of Sorrows, Badlands, Riverglades
	[1446] = 40, [1425] = 41, [1444] = 41, [1447] = 42, [1427] = 43, [1419] = 46, [1422] = 46, -- Tanaris, Hinterlands, Feralas, Azshara, Searing Gorge, Blasted Lands, Western Plaguelands
	[1448] = 47, [1450] = 47, [1449] = 48, [1428] = 50, [1430] = 50, -- Felwood, Moonglade, Un'Goro, Burning Steppes, Deadwind Pass
	[1423] = 54, [1451] = 55, [1452] = 55, [2482] = 55, -- Eastern Plaguelands, Silithus, Winterspring, Mount Hyjal
}
Plan.GATED = { [94316] = 45, [94334] = 45, [94352] = 45 }
Plan.MIN_LEVEL = 10
Plan.LOW_LEVEL = 45
Plan.NEXT_OVER = 10
local function at(map, test) return function(p) return p[3] == map and (not test or test(p[4], p[5])) end end
Plan.LOW = {
	Horde = {
		first = { at(1440), at(1448, function(_, y) return y > 75 end), at(1442) }, -- Ashenvale, Felwood's Emerald Sanctuary, Stonetalon (Ziz Fizziks)
		next = { at(1445, function(x) return x < 42 end), at(1441), at(1445) }, -- Dustwallow by the Barrens, the Shimmering Flats, the rest of Dustwallow
	},
	Alliance = { first = { at(1431), at(1435), at(1437) }, next = { at(1434), at(1417), at(1424) } },
}
Plan.WARN_OVER = 3
function Plan.Over(place, level)
	local p = place and D.places[place]
	local zl = p and Plan.ZONE_LEVEL[p[3]]
	if zl and (level or 0) > 0 and zl > level + Plan.WARN_OVER then return zl, p[2] end
end
function Plan.Warn(places, level)
	local out, seen = {}, {}
	for _, p in ipairs(places) do
		local zl, zone = Plan.Over(p, level)
		if zl and not seen[zone] then seen[zone] = true; out[#out + 1] = { zone, zl } end
	end
	table.sort(out, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
	return out
end
function Plan.WarnText(zone, zl, level)
	return ('%s is meant for level %d and up (you are %d). You can still do it, but expect to die a few times.'):format(zone, zl, level)
end
function Plan.ForWrits(o)
	local sec = Plan.Travel(o.start)
	local level = o.level or 0
	local low = level > 0 and level < Plan.LOW_LEVEL and not o.all
	local out, later, leftOut, sum = {}, {}, 0, 0
	local near = Plan.LOW[D.side or 'Horde'] or Plan.LOW.Horde
	local function among(list, place)
		for i, f in ipairs(list) do if f(D.places[place]) then return i end end
	end
	local function worth(r) return r.cost and r.rep * max(0, (o.days or 1) - (r.done and 1 or 0)) or 0 end
	for _, r in ipairs(o.rows) do
		local map = r.place and D.places[r.place][3]
		local zl = map and Plan.ZONE_LEVEL[map] or 0
		if not r.place then
			out[#out + 1] = r
		elseif level > 0 and (Plan.GATED[r.quest] or 0) > level then
			if r.cost then leftOut = leftOut + 1 end
		elseif sec(0, r.place) == INF then
			if r.cost then leftOut = leftOut + 1 end
		elseif level <= 0 or o.all or r.ready then
			out[#out + 1] = r
			if r.ready and not r.done then sum = sum + (r.cost and worth(r) or r.rep) end
		elseif low then
			local n = zl <= level + Plan.NEXT_OVER and among(near.next, r.place)
			if among(near.first, r.place) then out[#out + 1] = r; sum = sum + worth(r)
			elseif n then later[#later + 1] = { r, n, n }
			elseif zl <= level then later[#later + 1] = { r, 100 + zl, map }
			elseif r.cost then leftOut = leftOut + 1 end
		elseif zl <= level + 3 then
			out[#out + 1] = r
		elseif r.cost then
			leftOut = leftOut + 1
		end
	end
	table.sort(later, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1].writ < b[1].writ end)
	local begun
	for _, x in ipairs(later) do
		if (o.toFriendly or 0) <= 0 or sum < (o.target or 0) or begun == x[3] then
			out[#out + 1] = x[1]
			sum, begun = sum + worth(x[1]), x[3]
		elseif x[1].cost then
			leftOut = leftOut + 1
		end
	end
	return out, leftOut
end

function Plan.Rows(prices, state, stock)
	local out = {}
	for _, w in ipairs(D.writs) do
		local writ, quest, item, n, tier, place, wname, iname, stack = unpack(w)
		local pw, pi = prices[writ], prices[item]
		local ready = (state.held[writ] or 0) > 0
		local writCost = costOf(pw, 1)
		local itemCost = costOf(pi, n)
		local inStock = (pw and (pw.up or 0) >= stock) and (pi and (pi.up or 0) >= max(stock, n))
		local cost = (writCost and itemCost and (inStock or stock <= 0)) and (writCost + itemCost - D.pouch[tier]) or nil
		out[#out + 1] = {
			writ = writ, quest = quest, item = item, n = n, tier = tier, place = place, name = wname, itemName = iname, stack = stack,
			rep = D.rep[tier], pouch = D.pouch[tier], writCost = writCost, itemCost = itemCost, cost = cost,
			thin = (writCost and itemCost and not inStock and stock > 0) and true or false,
			writUp = pw and pw.up or 0, itemUp = pi and pi.up or 0,
			ready = ready, done = state.done[quest] and true or false,
			zone = place and D.places[place][2] or nil,
		}
	end
	return out
end

function Plan.Goal(o)
	local need, days, perSec = o.need, o.days, o.perSec or 0
	local sec, fare = Plan.Travel(o.start)
	local tc = function(a, b) return perSec * sec(a, b) + fare(a, b) end
	local usable, pool = {}, {}
	for _, w in ipairs(o.rows) do
		if w.rep > 0 and w.place and (w.cost or w.ready) then usable[#usable + 1] = w; pool[w] = true end
	end
	local tour = {}
	local function has(t, r) for _, x in ipairs(t) do if x == r then return true end end return false end
	local function insert(row, t)
		t = t or tour
		if has(t, row) then return 0 end
		local best, prev = INF, 0
		for i = 1, #t + 1 do
			local nx = t[i]
			local add = tc(prev, row) + (nx and (tc(row, nx) - tc(prev, nx)) or 0)
			if add < best then best = add end
			prev = nx
		end
		return best
	end
	local function insertAt(t, row)
		if has(t, row) then return t end
		local best, at, prev = INF, #t + 1, 0
		for i = 1, #t + 1 do
			local nx = t[i]
			local add = tc(prev, row) + (nx and (tc(row, nx) - tc(prev, nx)) or 0)
			if add < best then best, at = add, i end
			prev = nx
		end
		local c = {}
		for i = 1, #t do c[#c + 1] = t[i] end
		table.insert(c, at, row)
		return c
	end
	local function reorder(rows)
		if #rows <= 10 then return Plan.BestOrder(rows, tc) end
		local t = {}
		for _, r in ipairs(rows) do t = insertAt(t, r) end
		return t
	end
	local function goldOf(w, k) if w.ready then return -w.pouch + (w.cost or 0) * (k - 1) end return w.cost * k end
	local function availOf(w) if not w.cost then return w.done and math.min(1, days - 1) or 1 end return days - (w.done and 1 or 0) end
	local picks, left = {}, need
	local force = o.force or {}
	local function take(w, k)
		pool[w] = nil
		if not has(tour, w.place) then
			if #tour >= 10 then tour = insertAt(tour, w.place)
			else local r = {}; for _, x in ipairs(tour) do r[#r + 1] = x end; r[#r + 1] = w.place; tour = reorder(r) end
		end
		local p = setmetatable({ days = k, first = w.done and 2 or 1, total = goldOf(w, k), w = w, forced = force[w.writ] and true or nil }, { __index = w })
		picks[#picks + 1] = p
	end
	for _, w in ipairs(usable) do
		if force[w.writ] and pool[w] and not w.done then take(w, 1); left = left - w.rep end
	end
	while left > 0 do
		local zones, any = {}, false
		for w in pairs(pool) do
			if availOf(w) > 0 then
				local z = w.zone or ('writ ' .. w.writ)
				zones[z] = zones[z] or {}
				table.insert(zones[z], w)
				any = true
			end
		end
		if not any then break end
		local best
		for _, ws in pairs(zones) do
			table.sort(ws, function(a, b)
				local x, y = goldOf(a, 1) / a.rep, goldOf(b, 1) / b.rep
				if x ~= y then return x < y end
				return a.writ < b.writ
			end)
			local t, gold, got, travel, tk = tour, 0, 0, 0, {}
			for _, w in ipairs(ws) do
				if got >= left then break end
				local k = min(availOf(w), ceil((left - got) / w.rep))
				travel = travel + k * insert(w.place, t)
				t = insertAt(t, w.place)
				gold, got = gold + goldOf(w, k), got + w.rep * k
				tk[#tk + 1] = { w, k }
				local score = (gold + travel) / got
				if not best or score < best.score then
					local copy = {}
					for i, x in ipairs(tk) do copy[i] = x end
					best = { score = score, take = copy }
				end
			end
		end
		if not best then break end
		for _, x in ipairs(best.take) do take(x[1], x[2]); left = left - x[1].rep * x[2] end
	end
	local function repOf() local r = 0; for _, p in ipairs(picks) do r = r + p.rep * p.days end; return r end
	local function shared(p) for _, q in ipairs(picks) do if q ~= p and q.place == p.place then return true end end return false end
	for _ = 1, 200 do
		local got, best = repOf(), nil
		for _, p in ipairs(picks) do
			if not p.ready and not p.forced then
				local sh = shared(p)
				local without = tour
				if not sh then without = {}; for _, r in ipairs(tour) do if r ~= p.place then without[#without + 1] = r end end end
				local saves = sh and 0 or insert(p.place, without)
				local rest = got - p.rep * p.days
				if rest >= need then
					local gain = p.total + p.days * saves
					if gain > 1 and (not best or gain > best.gain) then best = { gain = gain, p = p } end
				else
					for w in pairs(pool) do
						local avail = availOf(w)
						local k = ceil((need - rest) / w.rep)
						if avail > 0 and k <= avail then
							local gain = p.total + p.days * saves - goldOf(w, k) - k * insert(w.place, without)
							if gain > 1 and (not best or gain > best.gain) then best = { gain = gain, p = p, w = w, k = k } end
						end
					end
				end
			end
		end
		if not best then break end
		for i, p in ipairs(picks) do if p == best.p then table.remove(picks, i); break end end
		pool[best.p.w] = true
		local rows, seen = {}, {}
		for _, p in ipairs(picks) do if not seen[p.place] then seen[p.place] = true; rows[#rows + 1] = p.place end end
		tour = reorder(rows)
		if best.w then take(best.w, best.k) end
	end
	table.sort(picks, function(a, b) return a.writ < b.writ end)
	local out, span = {}, 0
	for _, p in ipairs(picks) do span = max(span, p.first + p.days - 1) end
	for d = 1, min(days, span) do
		local ws, gold, rep = {}, 0, 0
		for _, p in ipairs(picks) do
			if d >= p.first and d < p.first + p.days then
				ws[#ws + 1] = p
				rep = rep + p.rep
				gold = gold + ((d == 1 and p.ready) and -p.pouch or (p.cost or 0))
			end
		end
		out[#out + 1] = { day = d, writs = ws, rep = rep, gold = gold }
	end
	local gold = 0
	for _, p in ipairs(picks) do gold = gold + p.total end
	local travel, last = 0, 0
	for _, r in ipairs(tour) do travel = travel + tc(last, r); last = r end
	local perDay, room, today, doneToday = 0, 0, 0, 0
	for _, w in ipairs(usable) do
		if w.cost then
			perDay = perDay + w.rep
			room = room + w.rep * (days - (w.done and 1 or 0))
			if not w.done then today = today + w.rep end
		elseif w.ready and not w.done then room, today = room + w.rep, today + w.rep end
		if w.done then doneToday = doneToday + 1 end
	end
	local daysNeeded = need <= 0 and 0 or (need <= today and 1) or (perDay > 0 and (1 + ceil((need - today) / perDay))) or nil
	return { need = need, got = repOf(), picks = picks, days = out, gold = gold, travel = travel, usable = #usable, doneToday = doneToday,
		today = today, perDay = perDay, ok = need <= 0 or room >= need, daysNeeded = daysNeeded }
end

Plan.RECEIPT = { item = 262902, favor = 15, rep = 50, back = 100 }
Plan.CRATE_LEVEL = { apprentice = 10, journeyman = 10, expert = 20, artisan = 35 }
function Plan.CrateLevel(id, tier)
	local need = Plan.CRATE_LEVEL[tier] or 0
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if info then
		local ok, _, _, _, _, minLevel = pcall(info, id)
		if ok and type(minLevel) == 'number' and minLevel > need then need = minLevel end
	end
	return need
end
function Plan.ForLevel(level, ladder, held)
	if not level or level <= 0 then return ladder, held, 0 end
	local no, out, least = {}, 0, nil
	for _, c in ipairs(D.waylaid.crates) do
		local need = Plan.CrateLevel(c[1], c[2])
		if need > level then
			no[c[1]] = true
			local sealed = D.waylaid.sealed[c[3]] and D.waylaid.sealed[c[3]][c[2]]
			if sealed then no[sealed] = true end
			if (held[c[1]] or 0) > 0 then out = out + held[c[1]]; least = math.min(least or need, need) end
		end
	end
	if not next(no) then return ladder, held, 0 end
	local h = {}
	for id, n in pairs(held) do if not no[id] then h[id] = n end end
	return function(id) if no[id] then return nil end return ladder(id) end, h, out, least
end
function Plan.LabelCrate(ladder, held, units)
	local h, gone = {}, {}
	for id, n in pairs(held) do h[id] = n end
	for _, u in ipairs(units or {}) do
		if u.held then h[u.id] = max(0, (h[u.id] or 0) - 1) else gone[u.id] = (gone[u.id] or 0) + 1 end
	end
	local function rest(id)
		local l, g = ladder(id), gone[id]
		if not l or not g then return l end
		local out = {}
		for _, st in ipairs(l) do
			local k = min(g, st[2])
			g = g - k
			if st[2] > k then out[#out + 1] = { st[1], st[2] - k } end
		end
		return out
	end
	local ok, r = pcall(Plan.Favor, { need = 1, ladder = rest, held = h })
	if ok and r and not r.short and #r.crates > 0 then return r end
end
function Plan.FillHeld(ladder, held)
	local isCrate, n, sell = {}, 0, 0
	for _, c in ipairs(D.waylaid.crates) do
		isCrate[c[1]] = true
		local h = held[c[1]] or 0
		if h > 0 then
			n = n + h
			local l = ladder(c[1])
			if l and l[1] and l[1][1] then sell = sell + h * max(0, l[1][1] - 100) end
		end
	end
	if n == 0 then return nil end
	local ok, r = pcall(Plan.Favor, { need = 1e9, ladder = function(id) if isCrate[id] then return nil end return ladder(id) end, held = held })
	local out = { held = n, fill = 0, favor = 0, cost = 0, perFavor = 0, sell = sell }
	if ok and r then
		for _, c in ipairs(r.crates) do out.fill = out.fill + c.count end
		out.favor = (r.got or 0) - (r.sealed or 0)
		out.cost = (r.cost or 0)
		out.perFavor = out.favor > 0 and out.cost / out.favor or 0
	end
	return out
end
function Plan.ReceiptUnits(ladder, limit, skip, free)
	local steps = {}
	for _, c in ipairs(D.waylaid.crates) do
		local l = ladder(c[1])
		if l then
			local gone = skip and skip[c[1]] or 0
			for _, st in ipairs(l) do
				local n = st[2] or 0
				local take = min(gone, n)
				gone, n = gone - take, n - take
				if st[1] and st[1] > 0 and n > 0 then steps[#steps + 1] = { st[1], n, c[1] } end
			end
		end
	end
	table.sort(steps, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[3] < b[3] end)
	local out = {}
	if free then
		for _, c in ipairs(D.waylaid.crates) do
			for _ = 1, free[c[1]] or 0 do
				if #out >= limit then return out end
				out[#out + 1] = { cost = 0, id = c[1], held = true }
			end
		end
	end
	for _, st in ipairs(steps) do
		for _ = 1, st[2] do
			if #out >= limit then return out end
			out[#out + 1] = { cost = st[1], id = st[3] }
		end
	end
	return out
end
function Plan.Receipts(o)
	local R = Plan.RECEIPT
	local first = max(0, min(o.need, o.writsFirst or 0))
	local full = first > 0 and floor((o.need - first) / R.rep) or ceil(o.need / R.rep)
	local extra = max(0, o.extra or 0)
	local noReceipts = (full <= 0 and 'receipts are sold from Friendly: writs first') or (o.max == 0 and 'receipts are off') or nil
	if noReceipts and extra <= 0 then return nil, noReceipts, {}, o.goalFor(o.need) end
	local memo, tries, anyFavorFail, anyCrateFail = {}, {}, false, false
	local function at(n)
		if memo[n] ~= nil then return memo[n] or nil end
		local have = o.held or {}
		local short = max(0, max(0, n - (o.receiptsHeld or 0)) * R.favor + extra - (o.favorHeld or 0))
		local fp, favorGold = nil, 0
		if short > 0 then
			local ok, r = pcall(Plan.Favor, { need = short, ladder = o.ladder, held = have })
			if not ok or not r or r.short then memo[n] = false; anyFavorFail = true; return nil end
			fp, favorGold = r, max(0, (r.cost or 0) - (r.back or 0))
		end
		local used, bought = {}, {}
		if fp then
			for _, c in ipairs(fp.crates) do used[c.id] = (used[c.id] or 0) + c.count end
			for _, b in ipairs(fp.buy) do bought[b.item] = (bought[b.item] or 0) + (b.units or 0) end
		end
		local skip, free = {}, {}
		for _, c in ipairs(D.waylaid.crates) do
			local id = c[1]
			local b = min(bought[id] or 0, used[id] or 0)
			skip[id] = b
			local left = (have[id] or 0) - ((used[id] or 0) - b)
			if left > 0 then free[id] = left end
		end
		local units = n > 0 and Plan.ReceiptUnits(o.ladder, n, skip, free) or {}
		if #units < n then memo[n] = false; anyCrateFail = true; return nil end
		local cost = 0
		for _, u in ipairs(units) do cost = cost + u.cost end
		memo[n] = { n = n, units = units, cost = cost - n * R.back, favor = n * R.favor, favorShort = short, favorGold = favorGold, favorPlan = fp }
		return memo[n]
	end
	local goals = {}
	local function goalFor(n, soon) local k = soon and -n - 1 or n; if not goals[k] then goals[k] = o.goalFor(n, soon) end; return goals[k] end
	local function weigh(n)
		local r = at(n)
		if not r then tries[#tries + 1] = n .. ': not possible'; return nil end
		local rest = max(0, o.need - n * R.rep)
		if o.only then rest = first > 0 and min(rest, o.need - full * R.rep) or 0 end
		local g = goalFor(rest, first > 0)
		r.goal, r.total, r.ok = g, g.gold + (g.travel or 0) + r.cost + r.favorGold + (o.trip or 0), g.got + n * R.rep >= o.need
		tries[#tries + 1] = n .. ': ' .. Plan.Money(r.total)
		return r
	end
	local function zeroPlan()
		local r = weigh(0)
		if r and r.favorPlan then r.tries = tries; return r end
	end
	if noReceipts then
		local z = zeroPlan()
		if z then return z end
		return nil, noReceipts, tries, goalFor(o.need)
	end
	local function most()
		for k = 6, 1, -1 do
			local n = floor(full * k / 6 + 0.5)
			if n > 0 and at(n) then return n end
		end
	end
	if o.fixed and o.fixed > 0 and o.fixed <= full then
		local r = weigh(o.fixed)
		if r then r.tries = tries; return r end
	end
	local top = most()
	local none = not top and #Plan.ReceiptUnits(o.ladder, 1) == 0
	local why = (not top) and ((none and 'the scan found none up that you can use') or (anyFavorFail and 'not enough crates up to fill for the Favor') or (anyCrateFail and 'not enough crates up') or 'no crate prices') or nil
	if o.only then
		if top and top < full then
			local lo, hi = top, full
			while hi - lo > 1 do
				local mid = floor((lo + hi) / 2)
				if at(mid) then lo = mid else hi = mid end
			end
			top = lo
		elseif not top then
			local lo, hi = 0, max(1, floor(full / 6 + 0.5))
			while hi - lo > 1 do
				local mid = floor((lo + hi) / 2)
				if at(mid) then lo = mid else hi = mid end
			end
			if lo > 0 then top = lo end
		end
		local r = top and weigh(top)
		if r then r.tries = tries; return r end
		local z = extra > 0 and zeroPlan() or nil
		if z then return z end
		return nil, why or 'no crates to be had', tries, goalFor(o.need)
	end
	local base = goalFor(o.need)
	local zero = extra > 0 and zeroPlan() or nil
	local best, bestTotal, bestOk = nil, zero and zero.total or (base.gold + (base.travel or 0)), base.got >= o.need
	if not zero then tries[#tries + 1] = '0: ' .. Plan.Money(bestTotal) end
	local seen = {}
	for _, n in ipairs({ top or 0, floor((top or 0) / 2 + 0.5) }) do
		if n > 0 and not seen[n] then
			seen[n] = true
			local r = weigh(n)
			if r and ((r.ok and not bestOk) or (r.ok == bestOk and r.total < bestTotal)) then best, bestTotal, bestOk = r, r.total, r.ok end
		end
	end
	if best then best.tries = tries; return best end
	if zero then return zero end
	return nil, why or 'writs cost less', tries, base
end
function Plan.TripCost(start, perSec, place)
	if not place then return 0 end
	local sec, fare = Plan.Travel(start)
	return (perSec or 0) * sec(0, place) + fare(0, place)
end

local function slotsFor(ws)
	local n = 0
	for _, w in ipairs(ws) do n = n + 1 + ceil(w.n / max(1, w.stack or 1)) end
	return n
end

local HOME_PREF = 60
local function withMail(order, slots, sec, cap, home)
	local n = #order
	local mails = {}
	for _, row in pairs(D.mailAt) do mails[#mails + 1] = row end
	table.sort(mails)
	local total = 0
	for i = 1, n do total = total + slots[i] end
	local seq = {}
	if total == 0 or #mails == 0 then
		for i = 1, n do seq[i] = { row = order[i], pos = i } end
		return seq
	end
	local box, adds = {}, {}
	for i = 1, n do
		local prev = i == 1 and 0 or order[i - 1]
		local best, bt
		for _, m in ipairs(mails) do
			local t = sec(prev, m) + sec(m, order[i])
			if not bt or t < bt then best, bt = m, t end
		end
		if i == 1 and home and best ~= home then
			local t = sec(prev, home) + sec(home, order[i])
			if t < bt + HOME_PREF then best, bt = home, t end
		end
		box[i], adds[i] = best, bt - sec(prev, order[i])
	end
	local least, cut, runs = { [0] = 0 }, {}, { [0] = 0 }
	for j = 1, n do
		local load = 0
		for i = j, 1, -1 do
			load = load + slots[i]
			if load > cap and i < j then break end
			local t, r = least[i - 1] + adds[i], runs[i - 1] + 1
			if not least[j] or t < least[j] - 1e-6 or (t < least[j] + 1e-6 and r < runs[j]) then least[j], cut[j], runs[j] = t, i, r end
		end
	end
	local loads, j = {}, n
	while j >= 1 do table.insert(loads, 1, { cut[j], j }); j = cut[j] - 1 end
	for _, l in ipairs(loads) do
		local take, load = {}, 0
		for k = l[1], l[2] do take[#take + 1] = k; load = load + slots[k] end
		if load > 0 then seq[#seq + 1] = { row = box[l[1]], mail = true, take = take } end
		for k = l[1], l[2] do seq[#seq + 1] = { row = order[k], pos = k } end
	end
	return seq
end

local PORT_GAIN = 30
function Plan.Ports(o)
	local out = {}
	if o.hearth and D.S[o.hearth] then out[#out + 1] = { kind = 'hearth', node = o.hearth, name = D.nodes[o.hearth][1], sec = 40 } end
	if o.druid then out[#out + 1] = { kind = 'teleport', node = D.moonglade or 69, name = 'Moonglade', sec = 25, spell = 18960, map = 1450, many = true } end
	if o.mage then
		for _, m in ipairs(D.mage or { { 23, 'Orgrimmar', 3567, 1454 }, { 11, 'Undercity', 3563, 1458 }, { 22, 'Thunder Bluff', 3566, 1456 } }) do
			out[#out + 1] = { kind = 'teleport', node = m[1], name = m[2], sec = 25, spell = m[3], map = m[4], fare = 1000, many = true, rune = true }
		end
	end
	return out
end

function Plan.Route(o)
	local sec, fare = Plan.Travel(o.start)
	local ports = Plan.Ports(o)
	local function quick(a, b)
		local t = sec(a, b)
		if a == b then return t end
		local best = t
		for _, p in ipairs(ports) do
			if p.many then
				local S = D.S[p.node]
				local tb = S and S.T[b]
				if tb and tb >= 0 and t - (p.sec + tb) >= PORT_GAIN and p.sec + tb < best then best = p.sec + tb end
			end
		end
		return best
	end
	local byPlace, rows = {}, {}
	for _, w in ipairs(o.writs) do
		if w.place then
			if not byPlace[w.place] then byPlace[w.place] = {}; rows[#rows + 1] = w.place end
			table.insert(byPlace[w.place], w)
		end
	end
	local receipts = (o.receipts or 0) > 0 and o.receipts or nil
	if (o.label or o.crates or receipts) and D.dokimi then
		if not byPlace[D.dokimi] then byPlace[D.dokimi] = {}; rows[#rows + 1] = D.dokimi end
	end
	local order = Plan.BestOrder(rows, quick)
	if o.receiptsLast and receipts and D.dokimi then
		for i, r in ipairs(order) do if r == D.dokimi then table.remove(order, i); order[#order + 1] = r; break end end
	end
	local seq
	if (o.bags or 0) > 0 then
		local slots = {}
		for i, r in ipairs(order) do slots[i] = slotsFor(byPlace[r]) + ((o.crates and r == D.dokimi) and (o.crateSlots or 0) or 0) + ((receipts and r == D.dokimi) and ceil(receipts / 5) or 0) end
		seq = withMail(order, slots, quick, o.bags, D.mailAt[o.start])
	else
		seq = {}
		for i, r in ipairs(order) do seq[i] = { row = r, pos = i } end
	end
	local legs, prev = {}, 0
	for _, s in ipairs(seq) do
		local leg = { row = s.row, mail = s.mail, sec = sec(prev, s.row), fare = fare(prev, s.row), from = prev }
		if s.mail then
			leg.writs = {}
			for _, k in ipairs(s.take) do
				for _, w in ipairs(byPlace[order[k]]) do leg.writs[#leg.writs + 1] = w end
				if o.crates and order[k] == D.dokimi then leg.crateMail = o.crates end
				if receipts and order[k] == D.dokimi then leg.receiptMail = receipts end
			end
		else
			leg.writs = byPlace[s.row]
			leg.label = o.label and s.row == D.dokimi and o.label or nil
			leg.crates = o.crates and s.row == D.dokimi and o.crates or nil
			leg.receipts = receipts and s.row == D.dokimi and receipts or nil
			leg.receiptFill = leg.receipts and o.receiptFill and #o.receiptFill > 0 and o.receiptFill or nil
		end
		legs[#legs + 1] = leg
		prev = s.row
	end
	local tries = {}
	for _, p in ipairs(ports) do
		local S = D.S[p.node]
		for n, l in ipairs(legs) do
			local t = S and S.T[l.row]
			if t and t >= 0 and l.from ~= l.row then
				local gain = l.sec - (p.sec + t)
				if gain >= PORT_GAIN then tries[#tries + 1] = { p = p, n = n, gain = gain, sec = p.sec + t, fare = (p.fare or 0) + S.F[l.row] } end
			end
		end
	end
	table.sort(tries, function(a, b) if a.gain ~= b.gain then return a.gain > b.gain end return a.n < b.n end)
	local used = {}
	for _, t in ipairs(tries) do
		local l = legs[t.n]
		if not l.port and (t.p.many or not used[t.p]) then
			used[t.p] = true
			l.port, l.sec, l.fare = t.p, t.sec, t.fare
		end
	end
	local total, fares = 0, 0
	for _, l in ipairs(legs) do
		local path = l.port and D.S[l.port.node].P[l.row] or (l.from == 0 and D.S[o.start].P[l.row] or D.P[l.from][l.row])
		l.hops = {}
		for h in (path or ''):gmatch('%d+') do l.hops[#l.hops + 1] = tonumber(h) end
		total, fares = total + l.sec, fares + l.fare
	end
	return { start = o.start, level = o.level, total = total, fares = fares, legs = legs }
end

function Plan.Shopping(days, prices, held, items)
	held, items = held or {}, items or {}
	local by, list = {}, {}
	local function add(id, name, n, writ, rep, item)
		if not by[id] then by[id] = { id = id, name = name, need = 0, writ = writ, rep = rep, item = item }; list[#list + 1] = by[id] end
		by[id].need = by[id].need + n
	end
	local have = {}
	for id, n in pairs(held) do have[id] = n end
	for id, n in pairs(items) do have[id] = (have[id] or 0) + n end
	for _, day in ipairs(days) do
		for _, w in ipairs(day.writs) do
			if (have[w.writ] or 0) > 0 then have[w.writ] = have[w.writ] - 1
			else add(w.writ, w.name, 1, true, w.rep, w.item) end
			local got = math.min(have[w.item] or 0, w.n)
			have[w.item] = (have[w.item] or 0) - got
			if w.n - got > 0 then add(w.item, w.itemName, w.n - got, false) end
		end
	end
	for _, e in ipairs(list) do e.cost = costOf(prices[e.id], e.need); e.each = e.cost and floor(e.cost / e.need + 0.5) end
	return list
end

function Plan.Money(c)
	c = floor((c or 0) + 0.5)
	local neg = c < 0
	if neg then c = -c end
	local g, s, k = floor(c / 10000), floor(c % 10000 / 100), c % 100
	local out = g > 0 and (g .. 'g' .. (s > 0 and (' ' .. s .. 's') or '')) or (s > 0 and (s .. 's' .. (k > 0 and (' ' .. k .. 'c') or '')) or (k .. 'c'))
	return (neg and '-' or '') .. out
end

function Plan.RouteSteps(route)
	local out, t = {}, 0
	for _, l in ipairs(route.legs) do
		if l.port then out[#out + 1] = { kind = 'port', text = (l.port.kind == 'hearth' and 'Hearth to ' or 'Teleport to ') .. l.port.name } end
		for _, h in ipairs(l.hops) do
			local kind, from, to = D.hops[h][1], D.hops[h][2], D.hops[h][3]
			out[#out + 1] = { kind = kind, text = (kind == 'fly' and 'Fly ' or ('Take the ' .. kind .. ' ')) .. from .. ' to ' .. to }
		end
		t = t + l.sec
		local label, zone = D.places[l.row][1], D.places[l.row][2]
		local names = {}
		for _, w in ipairs(l.writs) do names[#names + 1] = w.itemName end
		if l.mail then
			local what = #l.writs > 0 and (#l.writs .. ' writ' .. (#l.writs == 1 and '' or 's') .. ' and their items') or ''
			if l.crateMail then what = what .. (what ~= '' and ', and ' or '') .. 'your crates and bundles (fill them)' end
			if l.receiptMail then what = what .. (what ~= '' and ', and ' or '') .. l.receiptMail .. ' empty Waylaid Crate' .. (l.receiptMail == 1 and '' or 's') end
			out[#out + 1] = { kind = 'mail', at = t, row = l.row, writs = l.writs, text = label .. ': collect what you bought (' .. what .. ')' }
		else
			if l.crates then
				local n = 0
				for _, g in ipairs(l.crates) do n = n + g.count end
				names[#names + 1] = 'hand in ' .. n .. ' Sealed crate' .. (n == 1 and '' or 's')
			end
			if l.receipts then names[#names + 1] = l.receipts .. ' crate' .. (l.receipts == 1 and '' or 's') .. ' with a Forged Delivery Receipt' end
			if l.label then names[#names + 1] = 'Shipping Label' end
			out[#out + 1] = { kind = 'stop', at = t, row = l.row, writs = l.writs, label = l.label, text = label .. (zone and (', ' .. zone) or '') .. ': ' .. table.concat(names, ', ') }
		end
	end
	return out
end

function Plan.Favor(o)
	local W = D.waylaid
	local held = o.held or {}
	local sealed, sealedCount = 0, {}
	for kind, tiers in pairs(W.sealed) do
		for tier, id in pairs(tiers) do
			local n = held[id] or 0
			if n > 0 then sealed = sealed + n * W.favor[kind][tier]; sealedCount[id] = n end
		end
	end
	local books, taken = {}, {}
	local function book(id)
		if not books[id] then
			local b = {}
			if (held[id] or 0) > 0 then b[1] = { 0, held[id] } end
			for _, l in ipairs(o.ladder(id) or {}) do b[#b + 1] = l end
			books[id] = b
		end
		return books[id]
	end
	local function nextUnits(id, n)
		local skip, left, cost, top, free = taken[id] or 0, n, 0, 0, 0
		for _, l in ipairs(book(id)) do
			local u, q = l[1], l[2]
			local here = max(0, q - skip)
			skip = max(0, skip - q)
			if here > 0 then
				local k = min(here, left)
				cost, left = cost + k * u, left - k
				if u == 0 then free = free + k else top = u end
				if left == 0 then return { cost = cost, top = top, free = free } end
			end
		end
		return nil
	end
	local plan, order, bought = {}, {}, {}
	local function take(id, n, c)
		taken[id] = (taken[id] or 0) + n
		local b = bought[id] or { item = id, units = 0, cost = 0, top = 0, free = 0 }
		b.units, b.cost, b.top, b.free = b.units + n, b.cost + c.cost, max(b.top, c.top), b.free + c.free
		bought[id] = b
	end
	local got, cost, backAll = sealed, 0, 0
	while got < o.need do
		local best
		for _, c in ipairs(W.crates) do
			local id, tier, kind = c[1], c[2], c[3]
			local favor = W.favor[kind][tier]
			local box = favor and nextUnits(id, 1)
			if box then
				for _, opt in ipairs(c[5]) do
					local fill = nextUnits(opt[1], opt[2])
					if fill then
						local per = (box.cost + fill.cost - (W.money[tier] or 0)) / favor
						if not best or per < best.per then best = { c = c, opt = opt, box = box, fill = fill, favor = favor, per = per } end
					end
				end
			end
		end
		if not best then break end
		local c, opt = best.c, best.opt
		take(c[1], 1, best.box)
		take(opt[1], opt[2], best.fill)
		local back = W.money[c[2]] or 0
		local p = plan[c[1]]
		if not p then
			p = { id = c[1], tier = c[2], kind = c[3], type = c[4], favor = best.favor, count = 0, cost = 0, crateCost = 0, back = 0, bundles = {}, byItem = {} }
			plan[c[1]] = p
			order[#order + 1] = p
		end
		p.count = p.count + 1
		p.cost = p.cost + best.box.cost + best.fill.cost - back
		p.back = p.back + back
		p.crateCost = p.crateCost + best.box.cost
		local bd = p.byItem[opt[1]]
		if not bd then bd = { item = opt[1], n = opt[2], count = 0, cost = 0 }; p.byItem[opt[1]] = bd; p.bundles[#p.bundles + 1] = bd end
		bd.count, bd.cost = bd.count + 1, bd.cost + best.fill.cost
		got = got + best.favor
		cost = cost + best.box.cost + best.fill.cost - back
		backAll = backAll + back
	end
	for _, p in ipairs(order) do p.perFavor = p.cost / (p.favor * p.count); p.byItem = nil end
	table.sort(order, function(a, b) return a.perFavor < b.perFavor end)
	local buy = {}
	for _, b in pairs(bought) do
		local units = b.units - b.free
		if units > 0 then buy[#buy + 1] = { item = b.item, units = units, cost = b.cost, top = b.top, held = b.free } end
	end
	table.sort(buy, function(a, b) return a.cost > b.cost end)
	return { need = o.need, got = got, cost = cost, back = backAll, short = got < o.need, sealed = sealed, sealedCount = sealedCount, crates = order, buy = buy }
end
