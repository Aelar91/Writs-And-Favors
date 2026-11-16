local ADDON, ns = ...
if ns.EDITION == 'favor' then return end
local D, Plan, State, S = ns.D, ns.Plan, ns.State, ns.Skin
local C = S.colors
local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local LOGO = 'Interface\\AddOns\\' .. ADDON .. '\\logo.tga'
local max, min, floor = math.max, math.min, math.floor
local M = function(c) return Plan.Money(floor(c + 0.5)) end
local function hex(c) return ('|cff%02x%02x%02x'):format(floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255)) end
local GOLD, MUTED, GREEN = hex(C.gold), hex(C.muted), hex(C.green)
local function say(msg) print('|cffffc840Writs and Favors|r: ' .. msg) end
local function now() return GetServerTime and GetServerTime() or time() end

local warned
local function wrongSide()
	local side = UnitFactionGroup and UnitFactionGroup('player')
	return (side == 'Horde' or side == 'Alliance') and side ~= (D.side or 'Horde')
end
function ns.Blocked(quiet)
	if not wrongSide() then return false end
	if not quiet or not warned then
		warned = true
		say('It loaded the ' .. (D.side or 'Horde') .. '\'s routes and hand-ins, and this character isn\'t ' .. (D.side or 'Horde') .. '. Type /reload and it loads the right ones.')
	end
	return true
end

local HOUSE = { 'prices', 'scanAt', 'fullAt', 'favorAt', 'favorFullAt' }
local function houseKey()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or 'realm'
	return realm .. '-' .. ((UnitFactionGroup and UnitFactionGroup('player')) or 'Horde')
end
function ns.House(db)
	local key = houseKey()
	db.houses = db.houses or {}
	if db.house == key then return key end
	if db.house then
		local keep = {}
		for _, f in ipairs(HOUSE) do keep[f] = db[f] end
		db.houses[db.house] = keep
		local mine = db.houses[key] or {}
		for _, f in ipairs(HOUSE) do db[f] = mine[f] end
		db.prices = db.prices or {}
		if ns.Log then ns.Log('prices: now ' .. key .. ' (was ' .. db.house .. ')') end
	end
	db.houses[key] = nil
	db.house = key
	return key
end

local W = D.waylaid
local writBy, wantedBy, crateBy, fills, sealedBy = {}, {}, {}, {}, {}
for _, w in ipairs(D.writs) do
	writBy[w[1]] = w
	wantedBy[w[3]] = wantedBy[w[3]] or {}
	table.insert(wantedBy[w[3]], w)
end
for _, c in ipairs(W.crates) do
	crateBy[c[1]] = c
	for _, o in ipairs(c[5]) do
		fills[o[1]] = fills[o[1]] or {}
		table.insert(fills[o[1]], { c, o[2] })
	end
end
for kind, tiers in pairs(W.sealed) do for tier, id in pairs(tiers) do sealedBy[id] = { kind = kind, tier = tier } end end

local snap, snapAt
local function snapshot()
	local t = GetTime and GetTime() or 0
	if snap and t - snapAt < 1 then return snap end
	local db = ns.db
	if not (db and ns.UI) then return nil end
	local ok, st = pcall(State.Read, db)
	local ok2, p = pcall(ns.UI.prices)
	if not (ok and ok2) then return nil end
	snap, snapAt = { st = st, p = p, db = db }, t
	return snap
end
function ns.Forget() snap = nil end

local function priceText(p, cost)
	if not cost then return p and ('only ' .. (p.up or 0) .. ' up') or 'no price' end
	return M(cost) .. (p and (p.source and (' (' .. p.source .. ')') or p.up and (' (' .. p.up .. ' up)')) or '')
end
local function ageLine(at)
	if not at then return 'No scan yet here: Scan at the Auction House' end
	local m = floor((now() - at) / 60)
	return 'Prices ' .. (m < 60 and (m .. ' min') or m < 1440 and (floor(m / 60) .. ' h') or (floor(m / 1440) .. ' days')) .. ' old'
end
local function crateFills(c, s, market)
	local out = {}
	for _, o in ipairs(c[5]) do
		local have = market and 0 or min(o[2], s.st.items[o[1]] or 0)
		local cost = have >= o[2] and 0 or Plan.CostOf(s.p[o[1]], o[2] - have)
		out[#out + 1] = { item = o[1], n = o[2], have = have, cost = cost }
	end
	table.sort(out, function(a, b)
		if (a.cost == nil) ~= (b.cost == nil) then return a.cost ~= nil end
		if a.cost ~= b.cost then return (a.cost or 0) < (b.cost or 0) end
		return a.item < b.item
	end)
	return out
end

function ns.TipLines(id)
	if not id or not (writBy[id] or wantedBy[id] or crateBy[id] or fills[id] or sealedBy[id]) then return nil end
	local s = snapshot()
	if not s then return nil end
	local st, p = s.st, s.p
	local out = {}
	local function add(l, r) out[#out + 1] = { l, r } end
	local w = writBy[id]
	if w then
		local writ, quest, item, n, tier, place, _, iname = unpack(w)
		local have = min(n, st.items[item] or 0)
		local held = (st.held[writ] or 0) > 0
		local writCost = held and 0 or Plan.CostOf(p[writ], 1)
		local itemCost = have >= n and 0 or Plan.CostOf(p[item], n - have)
		add('Needs', n .. ' x ' .. iname .. (have > 0 and (' (you have ' .. have .. ')') or ''))
		add('Writ', held and (GREEN .. 'held|r') or priceText(p[writ], writCost))
		add(have > 0 and have < n and ('Items, ' .. (n - have) .. ' more') or 'Items', have >= n and (GREEN .. 'all held|r') or priceText(p[item], itemCost))
		local rep, pouch = D.rep[tier] or 0, D.pouch[tier] or 0
		add('Gives', rep .. ' reputation, about ' .. M(pouch))
		if writCost and itemCost and rep > 0 then
			add('Still to pay', M(writCost + itemCost))
			local per = (writCost + itemCost - pouch) / rep
			add('A reputation', per > 0 and (GOLD .. M(per) .. '|r') or (GREEN .. 'pays for itself|r'))
		end
		if place and D.places[place] then add('Hand in', D.places[place][1] .. ', ' .. D.places[place][2]) end
		if st.done[quest] then add('Today', MUTED .. 'handed in|r') end
		add(MUTED .. ageLine(s.db.scanAt) .. '|r')
	end
	if wantedBy[id] then
		for i, x in ipairs(wantedBy[id]) do
			if i > 3 then add('', MUTED .. 'and ' .. (#wantedBy[id] - 3) .. ' more|r'); break end
			add(i == 1 and 'Wanted by' or '', x[7] .. ' (' .. x[4] .. ')')
		end
		if p[id] and p[id].each then add('Auction House', priceText(p[id], p[id].each) .. ' each') end
	end
	local c = crateBy[id]
	if c then
		local tier, kind = c[2], c[3]
		local held = (st.items[id] or 0) > 0
		local crateCost = held and 0 or Plan.CostOf(p[id], 1)
		add('Crate', held and (GREEN .. 'held|r') or priceText(p[id], crateCost))
		local opts = crateFills(c, s)
		for i, o in ipairs(opts) do
			if i > 4 then add('', MUTED .. 'and ' .. (#opts - 4) .. ' more ways|r'); break end
			local what = o.n .. ' x ' .. (W.names[o.item] or ('item ' .. o.item)) .. (o.have > 0 and (' (you have ' .. o.have .. ')') or '')
			local cost = o.have >= o.n and (GREEN .. 'held|r') or o.cost and ((i == 1 and GREEN or '') .. M(o.cost) .. (i == 1 and '|r' or '')) or (MUTED .. 'no price|r')
			add(i == 1 and 'Fill with' or 'or', what .. ': ' .. cost)
		end
		local favor, money = W.favor[kind][tier] or 0, W.money[tier] or 0
		add('Gives', favor .. ' Favor and ' .. M(money))
		local best = opts[1] and opts[1].cost
		if crateCost and best and favor > 0 then
			add('Still to pay', M(crateCost + best))
			local per = (crateCost + best - money) / favor
			add('A Favor', per > 0 and (GOLD .. M(per) .. '|r') or (GREEN .. 'pays for itself|r'))
		end
		add(MUTED .. ageLine(s.db.favorAt) .. '|r')
	end
	if fills[id] then
		for i, x in ipairs(fills[id]) do
			if i > 3 then add('', MUTED .. 'and ' .. (#fills[id] - 3) .. ' more crates|r'); break end
			add(i == 1 and 'Fills' or '', (W.names[x[1][1]] or 'a Waylaid Crate') .. ' (' .. x[2] .. ')')
		end
		if not wantedBy[id] and p[id] and p[id].each then add('Auction House', priceText(p[id], p[id].each) .. ' each') end
	end
	local sc = sealedBy[id]
	if sc then add('Hand in', W.handIn.npc .. ', ' .. W.handIn.zone .. ': ' .. (W.favor[sc.kind][sc.tier] or 0) .. ' Favor and ' .. M(W.money[sc.tier] or 0)) end
	return out
end

local function onTip(tip, id)
	local db = ns.db
	if not db or (db.settings and db.settings.tooltips == false) then return end
	local ok, lines = pcall(ns.TipLines, id)
	if not ok or not lines or #lines == 0 then return end
	tip:AddLine(' ')
	tip:AddLine('Writs and Favors', C.gold[1], C.gold[2], C.gold[3])
	for _, l in ipairs(lines) do
		if l[2] then tip:AddDoubleLine(l[1], l[2], C.muted[1], C.muted[2], C.muted[3], 1, 1, 1) else tip:AddLine(l[1], C.muted[1], C.muted[2], C.muted[3]) end
	end
	tip:Show()
end
local function hookTips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
			if (tip == GameTooltip or tip == ItemRefTooltip) and data and data.id then onTip(tip, data.id) end
		end)
		return
	end
	for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
		if tip and tip.HookScript and tip.GetItem then
			pcall(tip.HookScript, tip, 'OnTooltipSetItem', function(self)
				local _, link = self:GetItem()
				local id = link and tonumber(link:match('item:(%d+)'))
				if id then onTip(self, id) end
			end)
		end
	end
end

local TIER = { apprentice = 1, journeyman = 2, expert = 3, artisan = 4 }
local function cap(s) return (s:gsub('^%l', string.upper)) end
local COLS = {
	writs = {
		{ 'name', 'Writ', 206 }, { 'tier', 'Tier', 74 }, { 'needs', 'Needs', 170 }, { 'first', 'Writ', 70, true }, { 'second', 'Items', 76, true },
		{ 'total', 'Total', 76, true }, { 'gives', 'Rep', 48, true }, { 'per', 'Cost / rep', 98, true }, { 'where', 'Hand in', 130 },
	},
	crates = {
		{ 'name', 'Crate', 206 }, { 'tier', 'Tier', 74 }, { 'needs', 'Cheapest fill', 170 }, { 'first', 'Crate', 70, true }, { 'second', 'Fill', 76, true },
		{ 'total', 'Total', 76, true }, { 'gives', 'Favor', 48, true }, { 'per', 'Cost / Favor', 98, true },
	},
}
local SHOWN, RH = 18, 22
local B -- the window

function ns.BrowseRows(mode)
	local s = snapshot()
	if not s then return {} end
	local out = {}
	if mode == 'crates' then
		for _, c in ipairs(W.crates) do
			local id, tier, kind = c[1], c[2], c[3]
			local have = s.st.items[id] or 0
			local held = false
			local crateCost = Plan.CostOf(s.p[id], 1)
			local o = crateFills(c, s, true)[1]
			local fill = o and o.cost
			local title = (W.names[id] or ('Crate ' .. id)):gsub('^Waylaid Crate: ', '')
			local buy
			if crateCost and fill then
				buy = { { id = id, name = W.names[id] or title, need = 1, each = crateCost },
					{ id = o.item, name = W.names[o.item] or ('Item ' .. o.item), need = o.n, each = floor(fill / o.n + 0.5) } }
			end
			local favor, money = W.favor[kind][tier] or 0, W.money[tier] or 0
			local total = crateCost and fill and (crateCost + fill) or nil
			local per = total and favor > 0 and (total - money) / favor or nil
			out[#out + 1] = {
				id = id, icon = id, held = held, title = title, buy = buy, cost = total,
				v = { name = W.names[id] or '', tier = TIER[tier] or 0, needs = o and (W.names[o.item] or '') or '', first = crateCost, second = fill, total = total, gives = favor, per = per },
				t = { name = title .. (have > 0 and (MUTED .. '  have ' .. have .. '|r') or ''), tier = cap(tier), needs = o and (o.n .. ' x ' .. (W.names[o.item] or o.item)) or '-',
					first = crateCost and M(crateCost) or '-', second = fill and M(fill) or '-',
					total = total and M(total) or '-', gives = tostring(favor), per = per and M(max(0, per)) or '-' },
			}
		end
	else
		for _, r in ipairs(Plan.Rows(s.p, s.st, 0)) do
			local first = r.ready and 0 or r.writCost
			local total = first and r.itemCost and (first + r.itemCost) or nil
			local per = total and (total - r.pouch) / r.rep or nil
			local title = r.name:gsub("^Craftsman's Writ: ", '')
			local haveItems = min(r.n, s.st.items[r.item] or 0)
			local buy, cost = {}, 0
			if not r.ready then
				if r.writCost then buy[#buy + 1] = { id = r.writ, name = r.name, need = 1, each = r.writCost, writ = true, rep = r.rep, item = r.item }; cost = cost + r.writCost else buy = nil end
			end
			if buy and haveItems < r.n then
				local c = Plan.CostOf(s.p[r.item], r.n - haveItems)
				if c then buy[#buy + 1] = { id = r.item, name = r.itemName, need = r.n - haveItems, each = floor(c / (r.n - haveItems) + 0.5) }; cost = cost + c else buy = nil end
			end
			local seen = not r.zone and State.Learned(s.db, r.quest) or nil
			out[#out + 1] = {
				id = r.writ, icon = r.item, held = r.ready, dim = r.done, title = title, buy = buy, cost = cost,
				v = { name = r.name, tier = TIER[r.tier] or 0, needs = r.itemName, first = first, second = r.itemCost, total = total, gives = r.rep, per = per, where = r.zone or (seen and seen.zone) or '' },
				t = { name = r.name:gsub("^Craftsman's Writ: ", '') .. (r.done and (MUTED .. '  done today|r') or ''), tier = cap(r.tier), needs = r.n .. ' x ' .. r.itemName,
					first = r.ready and (GREEN .. 'held|r') or first and M(first) or '-', second = r.itemCost and M(r.itemCost) or '-',
					total = total and M(total) or '-', gives = tostring(r.rep), per = per and M(max(0, per)) or '-', where = r.zone or (seen and (seen.zone .. MUTED .. ' (seen)|r')) or MUTED .. 'not known yet|r' },
			}
		end
	end
	return out
end
function ns.BrowseSort(rows, key, desc)
	table.sort(rows, function(a, b)
		local x, y = a.v[key], b.v[key]
		if (x == nil) ~= (y == nil) then return x ~= nil end
		if x ~= y and x ~= nil then if desc then return x > y else return x < y end end
		if a.v.name ~= b.v.name then return a.v.name < b.v.name end
		return a.id < b.id
	end)
	return rows
end

local function consume(id, qty)
	local p = ns.db and ns.db.prices and ns.db.prices[id]
	if not p then return end
	if p.ladder and #p.ladder > 0 then
		local left = qty
		while left > 0 and p.ladder[1] do
			local l = p.ladder[1]
			local k = min(left, l[2])
			l[2], left = l[2] - k, left - k
			if l[2] <= 0 then table.remove(p.ladder, 1) end
		end
		p.each = p.ladder[1] and p.ladder[1][1] or nil
	end
	if p.up then p.up = max(0, p.up - qty) end
end
ns.Consume = consume

local drawBrowse
local function startOrder(r)
	if not (r and r.buy and #r.buy > 0) then return end
	local mode = B.state.mode
	local list = {}
	for i, e in ipairs(r.buy) do list[i] = e end
	local ok, why = ns.UI.buyOne(list, {
		title = r.title,
		done = mode == 'crates' and ('Bought ' .. r.title .. ' and its fill. Click again for another.') or ('Bought ' .. r.title .. ": it's in your mail."),
		onChange = function(msg, over)
			if over then B.order = nil end
			B.msg = msg
			snap = nil
			if B:IsShown() then pcall(drawBrowse) end
		end,
		onBought = function(e, qty) consume(e.id, qty) end,
	})
	if ok then
		if ns.UI.buying() then B.order = { mode = mode, id = r.id, title = r.title } end
	else B.msg = why end
	B.overSeen = nil
	drawBrowse()
end
local buyNow
local function buyClick() ns.UI.guard(buyNow) end
function buyNow()
	if not B.order then return startOrder(B.picked) end
	local p = ns.Buy.Pending()
	if not (p and ns.Buy.Step() == 'ready') then return end
	local anyway = IsShiftKeyDown() or (p.over and B.overSeen == p)
	if p.over and not anyway then B.overSeen = p end
	ns.Buy.Click(anyway and true or false)
	drawBrowse()
end
local function drawBuy(rows)
	local st, b = B.state, B.buy
	if B.order and not ns.UI.buying() then B.order = nil end
	B.picked = nil
	if st.sel and st.sel.mode == st.mode then for _, r in ipairs(rows) do if r.id == st.sel.id then B.picked = r end end end
	B.skip:SetShown(B.order ~= nil)
	if B.order then
		local p = ns.Buy.Pending()
		if p and ns.Buy.Step() == 'ready' then
			local label = ns.Buy.Label() or 'Buy'
			b:SetText((p.over and B.overSeen == p) and (label .. ' anyway') or label)
			b:Enable()
		else
			b:SetText(B.order.title .. '...')
			b:Disable()
		end
	else
		local r = B.picked
		local open = ns.Scan and ns.Scan.IsOpen and ns.Scan.IsOpen()
		if not r then b:SetText('Click a row to buy it'); b:Disable()
		elseif not r.buy then b:SetText('No price for ' .. r.title .. ': scan first'); b:Disable()
		elseif #r.buy == 0 then b:SetText('You hold ' .. r.title .. ' and what it needs'); b:Disable()
		elseif not open then b:SetText('Open the Auction House to buy ' .. r.title); b:Disable()
		else b:SetText(('Buy %s: %s'):format(r.title, M(r.cost or 0))); b:Enable() end
	end
	B.status:SetText(B.msg or (MUTED .. 'Click a row, then Buy. Double-click a row to start buying it.|r'))
end

function drawBrowse()
	if not (B and B:IsShown()) then return end
	local st = B.state
	local cols = COLS[st.mode]
	local rows = ns.BrowseSort(ns.BrowseRows(st.mode), st.key, st.desc)
	local best, lo, hi
	for _, r in ipairs(rows) do
		local v = r.v.per
		if v and not r.dim then
			if not lo or v < lo then lo, best = v, r end
			if not hi or v > hi then hi = v end
		end
	end
	st.offset = max(0, min(st.offset, #rows - SHOWN))
	for i, h in ipairs(B.heads) do
		local col = cols[i]
		h:SetShown(col ~= nil)
		if col then h:SetText(col[2] .. (st.key == col[1] and (st.desc and '  v' or '  ^') or '')) end
	end
	for i = 1, SHOWN do
		local line, r = B.lines[i], rows[st.offset + i]
		if not r then line:Hide() else
			line.id = r.id
			line.icon:SetTexture(GetIcon and GetIcon(r.icon) or 134400)
			line.best:SetShown(r == best)
			line.sel:SetShown(st.sel ~= nil and st.sel.mode == st.mode and st.sel.id == r.id)
			for k, cell in ipairs(line.cells) do
				local col = cols[k]
				local text = col and r.t[col[1]] or ''
				if col and col[1] == 'per' and r.v.per and lo and hi and not r.dim and ns.writColors then
					text = hex(ns.writColors.value(hi > lo and (r.v.per - lo) / (hi - lo) or 0)) .. text .. '|r'
				end
				cell:SetText(text)
				cell:SetAlpha(r.dim and 0.45 or 1)
			end
			line.icon:SetAlpha(r.dim and 0.45 or 1)
			line:Show()
		end
	end
	local db = ns.db
	local priced = 0
	for _, r in ipairs(rows) do if r.v.total then priced = priced + 1 end end
	drawBuy(rows)
	B.foot:SetText(('%d to %d of %d   %s%d priced   %s   scroll for more, click a column to sort|r'):format(
		#rows > 0 and st.offset + 1 or 0, min(#rows, st.offset + SHOWN), #rows, MUTED, priced, ageLine(st.mode == 'crates' and db.favorAt or db.scanAt)))
	B.writsBtn:SetText((st.mode == 'writs' and GOLD or '') .. 'Writs')
	B.cratesBtn:SetText((st.mode == 'crates' and GOLD or '') .. 'Crates')
	B.title:SetText(st.mode == 'crates' and 'Every Waylaid Crate' or "Every Craftsman's Writ")
end
ns.OnRefresh = function() snap = nil; if B and B:IsShown() then pcall(drawBrowse) end end

local function buildBrowse()
	local width = 16
	for _, col in ipairs(COLS.writs) do width = width + col[3] end
	width = width + 26 + 16
	local f = CreateFrame('Frame', 'WritsAndFavorsBrowse', UIParent)
	f:SetSize(width, 30 + 26 + SHOWN * RH + 34 + 34)
	f:SetPoint('CENTER')
	f:SetFrameStrata('HIGH')
	f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
	f:RegisterForDrag('LeftButton')
	f:SetScript('OnDragStart', f.StartMoving)
	f:SetScript('OnDragStop', f.StopMovingOrSizing)
	S.Box(f, C.bg, C.border)
	if UISpecialFrames then table.insert(UISpecialFrames, 'WritsAndFavorsBrowse') end
	f.state = { mode = 'writs', key = 'per', desc = false, offset = 0 }

	local head = CreateFrame('Frame', nil, f)
	head:SetPoint('TOPLEFT', 1, -1); head:SetPoint('TOPRIGHT', -1, -1); head:SetHeight(30)
	S.Box(head, C.panel, { 0, 0, 0, 0 })
	local logo = head:CreateTexture(nil, 'ARTWORK')
	logo:SetSize(20, 20); logo:SetPoint('LEFT', 8, 0); logo:SetTexture(LOGO)
	f.title = S.Text(head, 14, C.gold); f.title:SetPoint('LEFT', 34, 0)
	local close = S.Button(head, 'x', 24, 22, function() f:Hide() end); close:SetPoint('RIGHT', -4, 0)
	local function mode(m) return function() f.state.mode, f.state.offset = m, 0; drawBrowse() end end
	f.cratesBtn = S.Button(head, 'Crates', 64, 22, mode('crates')); f.cratesBtn:SetPoint('RIGHT', close, 'LEFT', -8, 0)
	f.writsBtn = S.Button(head, 'Writs', 64, 22, mode('writs')); f.writsBtn:SetPoint('RIGHT', f.cratesBtn, 'LEFT', -4, 0)

	f.heads = {}
	local x = 16 + 26
	for i, col in ipairs(COLS.writs) do
		local h = S.Button(f, col[2], col[3] - 2, 20, function()
			local key = COLS[f.state.mode][i][1]
			if f.state.key == key then f.state.desc = not f.state.desc else f.state.key, f.state.desc = key, false end
			f.state.offset = 0
			drawBrowse()
		end)
		h:SetPoint('TOPLEFT', x, -36)
		f.heads[i] = h
		x = x + col[3]
	end

	f.lines = {}
	for i = 1, SHOWN do
		local line = CreateFrame('Frame', nil, f)
		line:SetSize(width - 32, RH)
		line:SetPoint('TOPLEFT', 16, -60 - (i - 1) * RH)
		if i % 2 == 0 then local z = line:CreateTexture(nil, 'BACKGROUND'); z:SetAllPoints(); z:SetColorTexture(1, 1, 1, 0.03) end
		line.best = line:CreateTexture(nil, 'BACKGROUND', nil, 1); line.best:SetAllPoints(); line.best:SetColorTexture(1, 0.78, 0.25, 0.14)
		line.sel = line:CreateTexture(nil, 'BACKGROUND', nil, 2); line.sel:SetAllPoints(); line.sel:SetColorTexture(0.35, 0.8, 0.45, 0.22); line.sel:Hide()
		line.icon = line:CreateTexture(nil, 'ARTWORK'); line.icon:SetSize(18, 18); line.icon:SetPoint('LEFT', 2, 0); line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		line.cells = {}
		local cx = 26
		for k, col in ipairs(COLS.writs) do
			local cell = S.Text(line, 12, C.text, col[4] and 'RIGHT' or 'LEFT')
			cell:SetPoint('LEFT', cx + 4, 0); cell:SetWidth(col[3] - 10); cell:SetWordWrap(false)
			line.cells[k] = cell
			cx = cx + col[3]
		end
		line:EnableMouse(true)
		line:SetScript('OnEnter', function(self)
			if not self.id then return end
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			GameTooltip:SetItemByID(self.id)
			GameTooltip:Show()
		end)
		line:SetScript('OnLeave', function() GameTooltip:Hide() end)
		line:SetScript('OnMouseUp', function(self)
			if not self.id then return end
			local st, t = f.state, GetTime and GetTime() or 0
			local again = st.sel and st.sel.mode == st.mode and st.sel.id == self.id and f.clickAt and t - f.clickAt < 0.5
			st.sel, f.clickAt = { mode = st.mode, id = self.id }, t
			if not f.order then f.msg = nil end
			drawBrowse()
			if again and not f.order and f.buy:IsEnabled() then buyClick() end
		end)
		f.lines[i] = line
	end
	f:EnableMouseWheel(true)
	f:SetScript('OnMouseWheel', function(_, delta) f.state.offset = f.state.offset - delta * 3; drawBrowse() end)
	f.foot = S.Text(f, 11); f.foot:SetPoint('BOTTOMLEFT', 16, 12)
	f.buy = S.Button(f, 'Click a row to buy it', 330, 30, buyClick, true); f.buy:SetPoint('BOTTOMRIGHT', -16, 10)
	f.skip = S.Button(f, 'Skip', 54, 30, function() ns.Buy.Skip(); drawBrowse() end); f.skip:SetPoint('RIGHT', f.buy, 'LEFT', -6, 0)
	f.skip:Hide()
	f.status = S.Text(f, 12, C.gold); f.status:SetPoint('BOTTOMLEFT', 16, 32); f.status:SetWidth(width - 32 - 330 - 54 - 24); f.status:SetWordWrap(false)
	f:SetScript('OnShow', function() snap = nil; drawBrowse() end)
	f:Hide()
	return f
end
function ns.Browse(mode)
	if ns.Blocked() then return end
	if not B then B = buildBrowse() end
	if mode then B.state.mode, B.state.offset = mode, 0 end
	if B:IsShown() and not mode then B:Hide(); return end
	B:SetScale(ns.db and ns.db.settings and ns.db.settings.scale or 1)
	B:Show()
	drawBrowse()
end

ns.OnBuild = function(ui)
	local b = S.Button(ui.frame, 'Browse all', 92, 22, function() ns.Browse() end)
	b:SetPoint('BOTTOMRIGHT', ui.frame, 'TOPRIGHT', 0, -1)
	b:SetScript('OnEnter', function(self)
		S.Box(self, C.hover, C.gold)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine('Browse all')
		GameTooltip:AddLine('Every writ and Waylaid Crate with its prices, in a table you can sort.', 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	b:HookScript('OnLeave', function() GameTooltip:Hide() end)
	ui.browseBtn = b
end

local mm
local function placeButton()
	local s = ns.db.settings
	local a = math.rad(s.minimapAngle or 205)
	local r = (Minimap:GetWidth() or 140) / 2 + 6
	mm:ClearAllPoints()
	mm:SetPoint('CENTER', Minimap, 'CENTER', math.cos(a) * r, math.sin(a) * r)
end
local function minimapButton()
	if mm or not Minimap then return end
	mm = CreateFrame('Button', 'WritsAndFavorsMinimapButton', Minimap)
	mm:SetSize(31, 31)
	mm:SetFrameStrata('MEDIUM'); mm:SetFrameLevel(8)
	mm:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	mm:RegisterForDrag('LeftButton')
	mm:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
	local icon = mm:CreateTexture(nil, 'ARTWORK')
	icon:SetSize(19, 19); icon:SetPoint('TOPLEFT', 6, -6)
	icon:SetTexture(LOGO); icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	mm.icon = icon
	local ring = mm:CreateTexture(nil, 'OVERLAY')
	ring:SetSize(53, 53); ring:SetPoint('TOPLEFT')
	ring:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
	mm:SetScript('OnClick', function(_, button)
		if button == 'RightButton' then ns.Browse() else ns.UI.toggle() end
	end)
	mm:SetScript('OnDragStart', function(self)
		self:SetScript('OnUpdate', function()
			local cx, cy = Minimap:GetCenter()
			local x, y = GetCursorPosition()
			local sc = Minimap:GetEffectiveScale() or 1
			if not (cx and x) then return end
			ns.db.settings.minimapAngle = math.deg(math.atan2(y / sc - cy, x / sc - cx))
			placeButton()
		end)
	end)
	mm:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
	mm:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		GameTooltip:AddLine('Writs and Favors', C.gold[1], C.gold[2], C.gold[3])
		GameTooltip:AddLine('Left-click: the panel', 1, 1, 1)
		GameTooltip:AddLine('Right-click: every writ and crate', 1, 1, 1)
		GameTooltip:AddLine('Drag: move this button   /writs minimap: hide it', 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	mm:SetScript('OnLeave', function() GameTooltip:Hide() end)
	placeButton()
end
local function showButton()
	local hide = ns.db.settings.minimapHide
	if not hide then minimapButton() end
	if mm then mm:SetShown(not hide) end
end

function ns.Slash(arg)
	local s = ns.db and ns.db.settings
	if not s then return false end
	if arg:match('^%s*browse') or arg:match('^%s*list') or arg:match('^%s*all') then
		ns.Browse(arg:match('crate') and 'crates' or arg:match('writ') and 'writs' or nil)
		return true
	end
	if arg:match('^%s*places') then
		local n = 0
		for _, w in ipairs(D.writs) do
			local l = State.Learned(ns.db, w[2])
			if l then n = n + 1; say(('%d %s: %s, %s %s %s'):format(w[2], w[7], tostring(l.npc or '?'), l.zone, tostring(l.x or '?'), tostring(l.y or '?'))) end
		end
		say(n == 0 and 'no hand-ins learnt yet. Hand in a writ the table marks "not known yet" and where you did is kept.' or (n .. ' hand-ins learnt. Send these lines in and the next version routes them.'))
		return true
	end
	if arg:match('^%s*minimap') then
		s.minimapHide = not s.minimapHide or nil
		showButton()
		say(s.minimapHide and 'the minimap button is hidden (/writs minimap brings it back)' or 'the minimap button is shown')
		return true
	end
	if arg:match('^%s*tooltip') then
		s.tooltips = (s.tooltips == false) and true or false
		say(s.tooltips and 'item tooltips are on' or 'item tooltips are off (/writs tooltip turns them on)')
		return true
	end
	return false
end

local ev = CreateFrame('Frame')
ev:RegisterEvent('PLAYER_LOGIN')
ev:SetScript('OnEvent', function()
	if not ns.db then return end
	pcall(ns.House, ns.db)
	if wrongSide() then return end
	pcall(hookTips)
	pcall(showButton)
end)
