local ADDON, ns = ...
local D, Plan, State, Scan, Buy, Guide, S = ns.D, ns.Plan, ns.State, ns.Scan, ns.Buy, ns.Guide, ns.Skin
local C = S.colors
local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

local FAVOR_ONLY = ns.EDITION == 'favor'
local NPC = D.waylaid.handIn.npc
local NPC_AT = ns.HandInAt or (NPC .. ' in the Crossroads')
local MAGE_NAMES = 'Orgrimmar, Undercity, Thunder Bluff'
if D.mage then local t = {}; for i, m in ipairs(D.mage) do t[i] = m[2] end; MAGE_NAMES = table.concat(t, ', ') end
local PREFIX = FAVOR_ONLY and 'MerchantsFavor' or 'WritsAndFavors'
local DBNAME = PREFIX .. 'DB'
local DEFAULTS = { goal = 2, days = 1, minute = 1000, speed = 50, bags = 30, stock = 5, scale = 1.1, favorGoal = 100 }
local function minuteOf(v) return v <= 50 and math.floor(v / 50 * 1000 + 0.5) or math.floor(1000 + (v - 50) / 50 * 9000 + 0.5) end
local function speedOf(m) return m <= 1000 and m / 1000 * 50 or 50 + math.min(1, (m - 1000) / 9000) * 50 end
local FAVOR_GOALS = { 25, 50, 100, 150, 200, 300, 500, 700, 1000, 1500 }
local W, PAD, ROW = 400, 16, 24
local IW = W - PAD * 2
local db, ui, plan

local function settings() return db.settings end
local function mine()
	db.chars = db.chars or {}
	local g = UnitGUID and UnitGUID('player') or 'me'
	db.chars[g] = db.chars[g] or {}
	return db.chars[g]
end
local function bagCap()
	local n = State.FreeSlots()
	if not n then return settings().bags or 30 end
	return math.max(8, n)
end
local function whenText(days) return days <= 1 and 'today' or days == 2 and 'tomorrow' or ('in ' .. days .. ' days') end

local oneOff, oneToken = nil, 0
local function startBuy(shopping, cb, o)
	if oneOff then return end
	Buy.Start(shopping, cb, o)
end
local function clearBuy()
	if oneOff then return end
	Buy.Clear()
end

local STALE = 20 * 3600
local checkOK, checkWin = false, nil
local function unchecked()
	local ok, st = pcall(State.Read, db)
	if not ok then return {} end
	local now_ = GetServerTime and GetServerTime() or time()
	local out = {}
	if not st.seen.mail or now_ - st.seen.mail > STALE then out[#out + 1] = 'mailbox' end
	if not st.seen.bank or now_ - st.seen.bank > STALE then out[#out + 1] = 'bank' end
	return out
end
local function guardBuy(go)
	if checkOK then return go() end
	local miss = unchecked()
	if #miss == 0 then return go() end
	if not checkWin then
		local w = CreateFrame('Frame', PREFIX .. 'Check', UIParent)
		w:SetSize(360, 150)
		w:SetFrameStrata('FULLSCREEN_DIALOG')
		w:EnableMouse(true)
		S.Box(w, C.panel, C.gold)
		w.title = S.Text(w, 14, C.gold); w.title:SetPoint('TOPLEFT', 14, -12)
		w.text = S.Text(w, 12, C.text); w.text:SetPoint('TOPLEFT', 14, -36); w.text:SetWidth(332); w.text:SetWordWrap(true); w.text:SetSpacing(3)
		w.wait = S.Button(w, "I'll check first", 160, 28, function() w:Hide() end, true); w.wait:SetPoint('BOTTOMLEFT', 14, 12)
		w.go = S.Button(w, 'Proceed anyway', 160, 28, function()
			checkOK = true
			w:Hide()
			if w.run then w.run() end
		end); w.go:SetPoint('BOTTOMRIGHT', -14, 12)
		checkWin = w
	end
	local w = checkWin
	local what = #miss == 2 and 'mailbox or your bank' or miss[1]
	w.title:SetText('Check your ' .. (#miss == 2 and 'mailbox and bank' or miss[1]) .. ' first?')
	w.text:SetText(('You haven\'t opened your %s today, so what\'s in %s isn\'t counted. You could buy writs, crates or items you already have.\n\nOpen %s once and the list updates by itself.'):format(what, #miss == 2 and 'them' or 'it', #miss == 2 and 'each' or 'it'))
	w.run = go
	w:ClearAllPoints()
	w:SetPoint('CENTER', UIParent, 'CENTER', 0, 80)
	w:SetScale(settings().scale or 1)
	w:Show()
	local function fit()
		local h = w.text:GetStringHeight()
		if not h or h < 20 then h = 96 end
		w:SetHeight(36 + h + 18 + 28 + 14)
	end
	fit()
	C_Timer.After(0, function() if w:IsShown() then fit() end end)
end

local function prices()
	local p = {}
	for id, v in pairs(db.prices or {}) do p[id] = v end
	local fb = Scan.Fallback(p, settings().stock)
	return p, fb
end
local function commas(n)
	local s = tostring(math.floor(n))
	while true do
		local t, k = s:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
		s = t
		if k == 0 then return s end
	end
end
local function hex(c) return ('|cff%02x%02x%02x'):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local GOLD, MUTED, GREEN, RED, WHITE = hex(C.gold), hex(C.muted), hex(C.green), hex(C.red), hex(C.text)
local QUALITY = { [0] = '|cff9d9d9d', [1] = '|cffffffff', [2] = '|cff1eff00', [3] = '|cff0070dd', [4] = '|cffa335ee', [5] = '|cffff8000' }
local dataQuality = {}
for _, w in ipairs(D.writs) do dataQuality[w[3]] = w[10] end
local function qualityHex(id)
	local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
	q = q or dataQuality[id] or 1
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	return (c and c.hex) or QUALITY[q] or WHITE
end

local status, statusErr
local function setStatus(msg, err) status, statusErr = msg, err; if msg then ns.Log((err and 'error: ' or '') .. msg) end end

local refresh

local openMenu
local function dropdown(parent, w, options, get, set)
	local b = S.Button(parent, '', w, 24)
	local menu = CreateFrame('Frame', nil, b)
	menu:SetFrameStrata('DIALOG')
	menu:SetPoint('TOPLEFT', b, 'BOTTOMLEFT', 0, -2)
	S.Box(menu, C.panel, C.border)
	menu:Hide()
	local items = {}
	local function fill()
		local opts = options()
		for i, o in ipairs(opts) do
			local it = items[i]
			if not it then
				it = CreateFrame('Button', nil, menu)
				it:SetSize(w - 2, 22)
				it:SetPoint('TOPLEFT', 1, -1 - (i - 1) * 22)
				it.text = S.Text(it, 12); it.text:SetPoint('LEFT', 8, 0)
				local hl = it:CreateTexture(nil, 'HIGHLIGHT'); hl:SetAllPoints(); hl:SetColorTexture(1, 0.78, 0.25, 0.15)
				items[i] = it
			end
			it.text:SetText((o.value == get() and GOLD or WHITE) .. o.text .. '|r')
			it:SetScript('OnClick', function() menu:Hide(); openMenu = nil; set(o.value); refresh(); if ui and ui.changed then ui.changed() end end)
			it:Show()
		end
		for i = #opts + 1, #items do items[i]:Hide() end
		menu:SetSize(w, #opts * 22 + 2)
	end
	b:SetScript('OnClick', function()
		if menu:IsShown() then menu:Hide(); openMenu = nil; return end
		if openMenu then openMenu:Hide() end
		fill(); menu:Show(); openMenu = menu
	end)
	b.update = function()
		for _, o in ipairs(options()) do if o.value == get() then b:SetText(o.text .. '  ' .. MUTED .. 'v|r') end end
	end
	return b
end

local function rowFrame(parent, i)
	local r = CreateFrame('Frame', nil, parent)
	r:SetSize(IW - 10, ROW)
	r:SetPoint('TOPLEFT', 0, -(i - 1) * ROW)
	r.bg = r:CreateTexture(nil, 'BACKGROUND'); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 0.78, 0.25, 0.10)
	r.icon = r:CreateTexture(nil, 'ARTWORK'); r.icon:SetSize(18, 18); r.icon:SetPoint('LEFT', 4, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.badge = r:CreateTexture(nil, 'OVERLAY'); r.badge:SetSize(10, 10); r.badge:SetPoint('BOTTOMRIGHT', r.icon, 'BOTTOMRIGHT', 3, -3)
	r:EnableMouse(true)
	r:SetScript('OnEnter', function(self)
		if not self.id then return end
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		GameTooltip:SetItemByID(self.id)
		if self.tip then GameTooltip:AddLine(self.tip, 1, 0.78, 0.25, true) end
		GameTooltip:Show()
	end)
	r:SetScript('OnLeave', function() GameTooltip:Hide() end)
	r.name = S.Text(r, 12); r.name:SetPoint('LEFT', 28, 0); r.name:SetWidth(210); r.name:SetWordWrap(false)
	r.rep = S.Text(r, 11, C.muted, 'RIGHT'); r.rep:SetPoint('RIGHT', -76, 0); r.rep:SetWidth(54)
	r.cost = S.Text(r, 12, C.text, 'RIGHT'); r.cost:SetPoint('RIGHT', -4, 0); r.cost:SetWidth(70)
	return r
end

local ui_drawRoute, ui_drawHeld, ui_applyMapMode, ui_hideRoute, ui_openPicker
local MAP_W, MAP_TOP, LIST_W = 1000, 40, 300
local CONT = { [0] = 1415, [1] = 1414 }
local CONT_NAME = { [1414] = 'Kalimdor', [1415] = 'Eastern Kingdoms' }
local OM_W = 460
local function omMode() return not FAVOR_ONLY and ns.OMRoute and ns.OMRoute.Available() and settings().routeMap ~= 'here' and true or false end
local function LW() return ui and ui.omMode and (OM_W - 2 * PAD + 10) or LIST_W end
local ORANGE = '|cffffa040'
local function picksOf() local m = mine(); m.picks = m.picks or {}; return m.picks end
local function candState(r)
	local picked = picksOf()[r.writ]
	if r.done then return 'done', MUTED .. 'handed in today|r' end
	if not r.ready and not (r.writCost and r.itemCost) then return 'none', MUTED .. 'not on the AH|r' end
	if picked then return 'picked', GREEN .. 'picked|r' end
	if ui.inPlan and ui.inPlan[r.writ] then return 'planned', GOLD .. 'planned|r' end
	if r.thin then return 'thin', ORANGE .. ('thin stock (%d up)'):format(math.min(r.writUp or 0, r.itemUp or 0)) .. '|r' end
	return 'free', ''
end
local function candCost(r)
	if r.ready then return 'held' end
	if r.writCost and r.itemCost then return Plan.Money(r.writCost + r.itemCost) end
	return '-'
end
local function candLine(r)
	local _, words = candState(r)
	return ('%s  %s%s|r  +%d%s'):format(r.name, WHITE, candCost(r), r.rep, words ~= '' and ('  ' .. words) or '')
end
local function perRep(r) if r.ready then return 0 end if r.writCost and r.itemCost then return (r.writCost + r.itemCost - r.pouch) / r.rep end end
local function grossCost(r) if r.ready then return 0 end return (r.writCost or 0) + (r.itemCost or 0) end
local function short(c)
	c = math.floor((c or 0) / 100 + 0.5)
	local g, sv = math.floor(c / 100), c % 100
	if g > 0 then return sv > 0 and (g .. 'g ' .. sv .. 's') or (g .. 'g') end
	return sv .. 's'
end
local function valueColor(t)
	t = math.max(0, math.min(1, t or 0.5))
	if t < 0.5 then local k = t / 0.5; return { 0.3 + 0.7 * k, 0.9 - 0.05 * k, 0.35 - 0.15 * k } end
	local k = (t - 0.5) / 0.5
	return { 1, 0.85 - 0.55 * k, 0.2 + 0.05 * k }
end
local function colorHex(c) return ('|cff%02x%02x%02x'):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end
local function swatch(c) return ('|TInterface\\Buttons\\WHITE8X8:9:9:0:0:8:8:0:8:0:8:%d:%d:%d|t'):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end
local STATE_COLOR = { picked = { 0.45, 1, 0.6 }, thin = { 1, 0.63, 0.25 }, done = { 0.55, 0.55, 0.55 }, none = { 0.6, 0.16, 0.14 } }
ns.writColors = { value = valueColor, state = STATE_COLOR }

local function pickTotals()
	local rows = plan and plan.rows
	local set = picksOf()
	local n, repSum, gold, ws = 0, 0, 0, {}
	for _, r in ipairs(rows or {}) do
		if set[r.writ] and not r.done and r.place and (r.ready or r.cost) then
			n, repSum = n + 1, repSum + r.rep
			gold = gold + (r.ready and -r.pouch or (r.writCost or 0) + (r.itemCost or 0))
			ws[#ws + 1] = r
		end
	end
	if n == 0 then return nil end
	local key = {}
	for _, r in ipairs(ws) do key[#key + 1] = r.writ end
	key = table.concat(key, ',')
	if ui.pickRouteKey ~= key then
		local _, class = UnitClass('player')
		local ok, route = pcall(Plan.Route, { writs = ws, start = State.Start(), bags = bagCap(), hearth = State.Hearth(), druid = class == 'DRUID', mage = class == 'MAGE' })
		ui.pickRouteKey, ui.pickMin = key, ok and route and math.floor(route.total / 60 + 0.5) or nil
	end
	return ('Picks: %d writ%s, +%s rep, %s to buy%s'):format(n, n == 1 and '' or 's', commas(repSum), Plan.Money(gold), ui.pickMin and (', about ' .. ui.pickMin .. ' min') or '')
end

local nodeByName = {}
for _, n in pairs(D.nodes) do nodeByName[n[1]] = n end
local function contPos(map, x, y)
	if not (map and x and C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
	local ok, inst, world = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
	if not (ok and inst and world and CONT[inst]) then return end
	local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, inst, world, CONT[inst])
	if not (ok2 and pos) then return end
	return { c = CONT[inst], x = pos.x, y = pos.y, map = map, zx = x, zy = y }
end
local ZMAX, ZONE_ART, CLUSTER_PX = 16, 0.55, 26
local HILITE = { 0.35, 1, 0.55, 1 }
local function artLayer(mapID)
	if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return end
	local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
	local L = ok and type(layers) == 'table' and layers[1]
	if not (L and L.layerWidth and L.tileWidth) then return end
	local ok2, ids = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
	if not (ok2 and type(ids) == 'table' and #ids > 0) then return end
	return L, ids
end
local function tileArt(m, pool, L, ids, x, y, w, h, view, sub)
	local cols = math.ceil(L.layerWidth / L.tileWidth)
	local sx, sy = w / L.layerWidth, h / L.layerHeight
	local tw, th = L.tileWidth * sx, L.tileHeight * sy
	local n = 0
	for i, fid in ipairs(ids) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local tx, ty = x + col * tw, y + row * th
		local cw, ch = math.min(L.tileWidth, L.layerWidth - col * L.tileWidth), math.min(L.tileHeight, L.layerHeight - row * L.tileHeight)
		if cw > 0 and ch > 0 and tx < view.r and tx + cw * sx > view.l and ty < view.b and ty + ch * sy > view.t then
			n = n + 1
			local t = m[pool][n]
			if not t then t = m.art:CreateTexture(nil, 'BACKGROUND', nil, sub); m[pool][n] = t end
			t:SetTexture(fid, nil, nil, 'TRILINEAR')
			t:SetSize(cw * sx, ch * sy)
			t:SetTexCoord(0, cw / L.tileWidth, 0, ch / L.tileHeight)
			t:ClearAllPoints(); t:SetPoint('TOPLEFT', m.art, 'TOPLEFT', tx, -ty)
			t:Show()
		end
	end
	for i = n + 1, #m[pool] do m[pool][i]:Hide() end
	return n
end
local zoneCache = {}
local function zonesOf(cont)
	if zoneCache[cont] then return zoneCache[cont] end
	local out, seen = {}, {}
	local function add(id, name)
		if not id or seen[id] or not (C_Map and C_Map.GetMapRectOnMap) then return end
		seen[id] = true
		local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, id, cont)
		if ok and l and r and t and b and r > l and b > t and r - l < 0.9 then out[#out + 1] = { id = id, name = name, l = l, r = r, t = t, b = b } end
	end
	if C_Map and C_Map.GetMapChildrenInfo then
		local ok, kids = pcall(C_Map.GetMapChildrenInfo, cont, (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3)
		if ok and type(kids) == 'table' then for _, k in ipairs(kids) do add(k.mapID, k.name) end end
	end
	for _, pl in ipairs(D.places) do add(pl[3], pl[2]) end
	zoneCache[cont] = out
	return out
end
local function zoneAt(cont, x, y)
	local zones = zonesOf(cont)
	if C_Map and C_Map.GetMapInfoAtPosition then
		local ok, info = pcall(C_Map.GetMapInfoAtPosition, cont, x, y)
		if ok and type(info) == 'table' then for _, z in ipairs(zones) do if z.id == info.mapID then return z end end end
	end
	local best
	for _, z in ipairs(zones) do
		if x >= z.l and x <= z.r and y >= z.t and y <= z.b and (not best or (z.r - z.l) * (z.b - z.t) < (best.r - best.l) * (best.b - best.t)) then best = z end
	end
	return best
end

local STYLE = { ride = { 0.92, 0.92, 0.92, 0.85 }, fly = C.gold, boat = { 0.45, 0.75, 1, 1 } }
local function useLine(m)
	if not m.art.CreateLine then return nil end
	m.li = m.li + 1
	local l = m.lines[m.li]
	if not l then l = m.art:CreateLine(nil, 'ARTWORK'); m.lines[m.li] = l end
	return l
end
local function useSq(m)
	m.si = m.si + 1
	local t = m.sqs[m.si]
	if not t then t = m.art:CreateTexture(nil, 'ARTWORK'); m.sqs[m.si] = t end
	return t
end
local function clip(a, b, v)
	local x0, y0, dx, dy = a.x, a.y, b.x - a.x, b.y - a.y
	local t0, t1 = 0, 1
	for _, pq in ipairs({ { -dx, x0 - v.l }, { dx, v.r - x0 }, { -dy, y0 - v.t }, { dy, v.b - y0 } }) do
		local p, q = pq[1], pq[2]
		if p == 0 then if q < 0 then return end
		else
			local r = q / p
			if p < 0 then if r > t1 then return end if r > t0 then t0 = r end
			else if r < t0 then return end if r < t1 then t1 = r end end
		end
	end
	return { x = x0 + dx * t0, y = y0 + dy * t0 }, { x = x0 + dx * t1, y = y0 + dy * t1 }
end
local function seg(m, a, b, style, view, rec)
	a, b = clip(a, b, view)
	if not a then return end
	local c = STYLE[style] or STYLE.ride
	local dx, dy = b.x - a.x, b.y - a.y
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then return end
	if style == 'boat' then
		for d = 0, len, 7 do
			local t = useSq(m)
			t:SetColorTexture(c[1], c[2], c[3], 1); t:SetSize(3, 3)
			t:ClearAllPoints(); t:SetPoint('CENTER', m.art, 'TOPLEFT', a.x + dx * d / len, -(a.y + dy * d / len)); t:Show()
			rec[#rec + 1] = { t, 'sq', c }
		end
		return
	end
	local on, off = (style == 'fly') and 8 or len, (style == 'fly') and 5 or 0
	local d = 0
	while d < len do
		local e = math.min(len, d + on)
		local l = useLine(m)
		if not l then return end
		l:SetThickness(2)
		l:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		l:SetStartPoint('TOPLEFT', m.art, a.x + dx * d / len, -(a.y + dy * d / len))
		l:SetEndPoint('TOPLEFT', m.art, a.x + dx * e / len, -(a.y + dy * e / len))
		l:Show()
		rec[#rec + 1] = { l, 'line', c }
		d = e + off
	end
end
local function useFrame(m, pool, make)
	m[pool .. 'i'] = (m[pool .. 'i'] or 0) + 1
	local f = m[pool][m[pool .. 'i']]
	if not f then
		f = make()
		m[pool][m[pool .. 'i']] = f
		f:EnableMouse(true)
		f:SetScript('OnEnter', function(self)
			if self.hover then self.hover(true) end
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			for i, line in ipairs(self.tip or {}) do GameTooltip:AddLine(line, 1, i == 1 and 0.78 or 1, i == 1 and 0.25 or 1, true) end
			GameTooltip:Show()
		end)
		f:SetScript('OnLeave', function(self) if self.hover then self.hover(false) end GameTooltip:Hide() end)
		f:SetScript('OnMouseUp', function(self, btn) if self.click and btn ~= 'RightButton' then self.click() end end)
	end
	f.hover, f.click, f.tip = nil, nil, nil
	f:Show()
	return f
end
local function stopFrame(m)
	local d = CreateFrame('Frame', nil, m.art)
	d:SetSize(18, 18)
	S.Box(d, C.gold, { 0, 0, 0, 1 })
	d.n = S.Text(d, 11, { 0.05, 0.05, 0.05 }, 'CENTER'); d.n:SetPoint('CENTER'); d.n:SetShadowOffset(0, 0)
	d.badge = CreateFrame('Frame', nil, d)
	d.badge:SetSize(14, 14); d.badge:SetPoint('BOTTOMLEFT', d, 'TOPRIGHT', -4, -4)
	S.Box(d.badge, { 0.1, 0.1, 0.1, 1 }, C.gold)
	d.badge.n = S.Text(d.badge, 9, C.text, 'CENTER'); d.badge.n:SetPoint('CENTER')
	return d
end
local function clusterFrame(m)
	local g = CreateFrame('Frame', nil, m.art)
	g:SetSize(80, 18)
	S.Box(g, C.gold, { 0, 0, 0, 1 })
	g.t = S.Text(g, 11, { 0.05, 0.05, 0.05 }, 'CENTER'); g.t:SetPoint('CENTER'); g.t:SetShadowOffset(0, 0)
	return g
end
local function legFrame(m)
	local g = CreateFrame('Frame', nil, m.art)
	g:SetSize(40, 14)
	S.Box(g, { 0.05, 0.05, 0.05, 0.8 }, { 0, 0, 0, 0 })
	g.t = S.Text(g, 10, C.text, 'CENTER'); g.t:SetPoint('CENTER')
	return g
end
local function zoneLabel(m)
	m.zli = m.zli + 1
	local t = m.zlabels[m.zli]
	if not t then
		t = m.art:CreateFontString(nil, 'ARTWORK')
		if not t:SetFont(S.Font(), 13, 'OUTLINE') then t:SetFont(STANDARD_TEXT_FONT, 13, 'OUTLINE') end
		t:SetTextColor(1, 0.92, 0.75); t:SetAlpha(0.55)
		m.zlabels[m.zli] = t
	end
	t:Show()
	return t
end

local function shownRoute()
	if ui.mapSource == 'held' then return ui.heldRoute end
	return plan and plan.route
end

local function viewSize(m)
	local w, h = m:GetWidth(), m:GetHeight()
	if not w or w <= 0 then w = MAP_W - LIST_W - 2 * PAD - 8 end
	if not h or h <= 0 then h = ((ui.mapWin and ui.mapWin:GetHeight()) or 640) - MAP_TOP - PAD - 8 end
	return w, h
end
local function baseSize(m, L)
	local vw, vh = viewSize(m)
	local fit = math.min(vw / L.layerWidth, vh / L.layerHeight)
	return L.layerWidth * fit, L.layerHeight * fit, vw, vh
end
local function fitView(pts, cont)
	local v = { cont = cont, cx = 0.5, cy = 0.5, z = 1 }
	local L = artLayer(cont)
	if not (L and #pts > 0) then return v end
	local aw, ah, vw, vh = baseSize(ui.map, L)
	local x0, x1, y0, y1 = 1, 0, 1, 0
	for _, p in ipairs(pts) do x0, x1, y0, y1 = math.min(x0, p.x), math.max(x1, p.x), math.min(y0, p.y), math.max(y1, p.y) end
	local sw, sh = math.max(x1 - x0, 0.03) * 1.3 + 0.02, math.max(y1 - y0, 0.03) * 1.3 + 0.02
	v.z = math.max(1, math.min(ZMAX, math.min(vw / (sw * aw), vh / (sh * ah))))
	v.cx, v.cy = (x0 + x1) / 2, (y0 + y1) / 2
	return v
end

local mapRender
local function hiLeg(li, on)
	if ui.omMode then return ns.OMRoute.Highlight(li, on) end
	local d = ui.mapData
	local leg = d and d.legs[li]
	if not leg then return end
	for _, r in ipairs(leg.drawn or {}) do
		local o, kind, c = r[1], r[2], on and HILITE or r[3]
		if kind == 'line' then o:SetThickness(on and 4 or 2); o:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		else o:SetSize(on and 5 or 3, on and 5 or 3); o:SetColorTexture(c[1], c[2], c[3], 1) end
	end
	if leg.label then S.Box(leg.label, on and { 0.1, 0.3, 0.15, 0.95 } or { 0.05, 0.05, 0.05, 0.8 }, on and HILITE or { 0, 0, 0, 0 }) end
	for _, i in ipairs({ li - 1, li }) do
		local s = i == 0 and d.start or d.stops[i]
		local f = s and s.frame
		if f then S.Box(f, on and HILITE or C.gold, { 0, 0, 0, 1 }) end
	end
end
local function mapGo(pos, z)
	if not pos then return end
	if ui.omMode then return ns.OMRoute.Go(pos) end
	if pos.c ~= ui.mapCont then ui.mapContPicked = pos.c; ui.drawRoute() end
	local v = ui.mapView
	if not v then return end
	v.cx, v.cy, v.z = pos.x, pos.y, math.max(v.z, z or 6)
	mapRender()
end
local function zoomAround(f, mx, my)
	local m, v = ui.map, ui.mapView
	if not (v and m.aw) then return end
	mx, my = mx or m.vw / 2, my or m.vh / 2
	local px, py = (m.ox + mx) / m.aw, (m.oy + my) / m.ah
	local z = math.max(1, math.min(ZMAX, v.z * f))
	if z == v.z then return end
	local aw, ah = m.aw * z / v.z, m.ah * z / v.z
	v.z = z
	v.cx, v.cy = (px * aw - mx + m.vw / 2) / aw, (py * ah - my + m.vh / 2) / ah
	mapRender()
end

mapRender = function()
	local m, d, v = ui.map, ui.mapData, ui.mapView
	m.li, m.si, m.stopsi, m.legsi, m.clustersi, m.zli = 0, 0, 0, 0, 0, 0
	for _, l in ipairs(m.lines) do l:Hide() end
	for _, t in ipairs(m.sqs) do t:Hide() end
	m.othersi, m.oclustersi = 0, 0
	m.others, m.oclusters = m.others or {}, m.oclusters or {}
	for _, pool in ipairs({ m.stops, m.legs, m.clusters, m.zlabels, m.others, m.oclusters }) do for _, f in ipairs(pool) do f:Hide() end end
	if not (d and v) then for _, t in ipairs(m.tiles) do t:Hide() end for _, t in ipairs(m.ztiles) do t:Hide() end return end
	local L, ids = artLayer(d.cont)
	m.none:SetShown(not L)
	m.none:SetText("The map isn't available here; the steps are on the left.")
	if not L then return end
	local aw0, ah0, vw, vh = baseSize(m, L)
	local aw, ah = aw0 * v.z, ah0 * v.z
	local function hold(c, a, vs) if a <= vs then return 0.5 end local h = vs / 2 / a; return math.max(h, math.min(1 - h, c)) end
	v.cx, v.cy = hold(v.cx, aw, vw), hold(v.cy, ah, vh)
	local ox, oy = v.cx * aw - vw / 2, v.cy * ah - vh / 2
	m.aw, m.ah, m.ox, m.oy, m.vw, m.vh = aw, ah, ox, oy, vw, vh
	m.art:SetSize(aw, ah)
	m.art:ClearAllPoints(); m.art:SetPoint('TOPLEFT', m, 'TOPLEFT', -ox, oy)
	local near = { l = ox - vw / 2, r = ox + vw * 1.5, t = oy - vh / 2, b = oy + vh * 1.5 }
	local inView = function(x, y) return x >= ox - 20 and x <= ox + vw + 20 and y >= oy - 20 and y <= oy + vh + 20 end
	tileArt(m, 'tiles', L, ids, 0, 0, aw, ah, near, 0)
	m.zone = nil
	local z = v.z > 1.5 and zoneAt(d.cont, v.cx, v.cy)
	if z and (z.r - z.l) * aw >= vw * ZONE_ART then
		local ZL, zids = artLayer(z.id)
		if ZL then tileArt(m, 'ztiles', ZL, zids, z.l * aw, z.t * ah, (z.r - z.l) * aw, (z.b - z.t) * ah, near, 1); m.zone = z end
	end
	if not m.zone then for _, t in ipairs(m.ztiles) do t:Hide() end end
	for _, zn in ipairs(zonesOf(d.cont)) do
		local zx, zy = (zn.l + zn.r) / 2 * aw, (zn.t + zn.b) / 2 * ah
		if (zn.r - zn.l) * aw >= 90 and inView(zx, zy) and zn.name then
			local t = zoneLabel(m)
			t:SetText(zn.name)
			t:ClearAllPoints(); t:SetPoint('CENTER', m.art, 'TOPLEFT', zx, -zy)
		end
	end
	local function P(p) return p and p.c == d.cont and { x = p.x * aw, y = p.y * ah } or nil end
	for li, leg in ipairs(d.legs) do
		leg.drawn, leg.label = {}, nil
		for _, s in ipairs(leg.segs) do
			local a, b = P(s[1]), P(s[2])
			if a and b then seg(m, a, b, s[3], near, leg.drawn) end
		end
		local a, b = P(leg.from), P(leg.to)
		if a and b then
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			if math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) >= 56 and inView(mx, my) then
				local g = useFrame(m, 'legs', function() return legFrame(m) end)
				g.t:SetText(leg.min .. ' min')
				g:ClearAllPoints(); g:SetPoint('CENTER', m.art, 'TOPLEFT', mx, -my)
				g.tip = leg.tip
				g.hover = function(on) hiLeg(li, on) end
				S.Box(g, { 0.05, 0.05, 0.05, 0.8 }, { 0, 0, 0, 0 })
				leg.label = g
			end
		end
	end
	local level = (m.art:GetFrameLevel() or 1) + 5
	local groups = {}
	for _, st in ipairs(d.stops) do
		st.frame = nil
		local q = P(st.pos)
		if q then
			local g
			if v.z < ZMAX then
				for _, c in ipairs(groups) do if (c.x - q.x) ^ 2 + (c.y - q.y) ^ 2 < CLUSTER_PX ^ 2 then g = c; break end end
			end
			if g then g.members[#g.members + 1] = st
			else groups[#groups + 1] = { x = q.x, y = q.y, members = { st } } end
		end
	end
	local function stopAt(s, q, label, badge)
		local f = useFrame(m, 'stops', function() return stopFrame(m) end)
		f:ClearAllPoints(); f:SetPoint('CENTER', m.art, 'TOPLEFT', q.x, -q.y)
		f.n:SetText(label)
		f.badge:SetShown(badge ~= nil)
		if badge then f.badge.n:SetText(badge) end
		f.tip = s.tip
		f:SetFrameLevel(level)
		S.Box(f, C.gold, { 0, 0, 0, 1 })
		s.frame = f
		return f
	end
	local sq = P(d.start.pos)
	d.start.frame = nil
	if sq then stopAt(d.start, sq, 'S').click = function() mapGo(d.start.pos, 6) end end
	for _, g in ipairs(groups) do
		if #g.members == 1 then
			local s = g.members[1]
			local f = stopAt(s, g, tostring(s.n), s.badge)
			f.hover = function(on) hiLeg(s.n, on) end
			f.click = function() if s.pick then s.pick() else mapGo(s.pos, math.min(ZMAX, (ui.mapView.z or 1) * 2)) end end
		else
			local hand, zones, zname, x, y = 0, {}, nil, 0, 0
			local tip = {}
			for _, s in ipairs(g.members) do
				local q = P(s.pos)
				x, y = x + q.x, y + q.y
				hand = hand + (s.hand or 0)
				if s.zone and not zones[s.zone] then zones[s.zone] = true; zname = zname and '' or s.zone end
				tip[#tip + 1] = s.tip[1] .. (s.hand and s.hand > 0 and (': ' .. s.hand .. ' hand-in' .. (s.hand > 1 and 's' or '')) or '')
			end
			x, y = x / #g.members, y / #g.members
			local c = useFrame(m, 'clusters', function() return clusterFrame(m) end)
			local text = (zname and zname ~= '' and zname or (#g.members .. ' stops')) .. ': ' .. hand .. ' hand-in' .. (hand == 1 and '' or 's')
			c.t:SetText(text)
			c:SetSize(math.max(60, (c.t:GetStringWidth() or #text * 6) + 14), 18)
			c:ClearAllPoints(); c:SetPoint('CENTER', m.art, 'TOPLEFT', x, -y)
			c:SetFrameLevel(level + 1)
			table.insert(tip, 1, ('Stops %s (click to zoom in)'):format(table.concat((function() local n = {}; for _, s in ipairs(g.members) do n[#n + 1] = s.n end; return n end)(), ', ')))
			c.tip = tip
			local pts = {}
			for _, s in ipairs(g.members) do pts[#pts + 1] = s.pos; s.frame = c end
			c.click = function()
				local nv = fitView(pts, d.cont)
				nv.z = math.max(nv.z, math.min(ZMAX, v.z * 2))
				ui.mapView = nv; nv.key = v.key
				mapRender()
			end
		end
	end
	local og = {}
	for _, o in ipairs(d.others or {}) do
		local q = P(o.pos)
		if q then
			local g
			if v.z < ZMAX then for _, c in ipairs(og) do if (c.x - q.x) ^ 2 + (c.y - q.y) ^ 2 < CLUSTER_PX ^ 2 then g = c; break end end end
			if g then g.members[#g.members + 1] = o else og[#og + 1] = { x = q.x, y = q.y, members = { o } } end
		end
	end
	for _, g in ipairs(og) do
		if #g.members == 1 then
			local o = g.members[1]
			local f = useFrame(m, 'others', function() local x = stopFrame(m); x:SetSize(14, 14); x.badge:Hide(); return x end)
			f:ClearAllPoints(); f:SetPoint('CENTER', m.art, 'TOPLEFT', g.x, -g.y)
			f.n:SetText(tostring(o.n)); f.badge:Hide()
			S.Box(f, o.picked and HILITE or { 0.62, 0.62, 0.62, o.open and 0.9 or 0.45 }, { 0, 0, 0, 1 })
			f:SetAlpha(o.open and 1 or 0.6)
			f:SetFrameLevel(level - 2)
			f.tip, f.click = o.tip, o.pick
		else
			local c = useFrame(m, 'oclusters', function() local x = clusterFrame(m); return x end)
			local n, x, y, pts = 0, 0, 0, {}
			for _, o in ipairs(g.members) do local q = P(o.pos); x, y = x + q.x, y + q.y; n = n + o.n; pts[#pts + 1] = o.pos end
			c.t:SetText(n .. ' other writs')
			c:SetSize(math.max(60, (c.t:GetStringWidth() or 60) + 14), 16)
			S.Box(c, { 0.55, 0.55, 0.55, 0.85 }, { 0, 0, 0, 1 })
			c:ClearAllPoints(); c:SetPoint('CENTER', m.art, 'TOPLEFT', x / #g.members, -y / #g.members)
			c:SetFrameLevel(level - 1)
			c.tip = { n .. ' other writs here: click to zoom in' }
			c.click = function() local nv = fitView(pts, d.cont); nv.z = math.max(nv.z, math.min(ZMAX, v.z * 2)); nv.key = v.key; ui.mapView = nv; mapRender() end
		end
	end
	ui.mapZoomText:SetText(('x%.1f'):format(v.z))
end

local function routeShown() return ui.mapWin and (ui.mapWin:IsShown() or (ui.omMode and ns.OMRoute and ns.OMRoute.IsOn())) end
ui_drawRoute = function()
	local w = ui.mapWin
	if not routeShown() then return end
	local route = shownRoute()
	local m = ui.map
	if ui.segAuto then
		local heldMode, mineMode = ui.mapSource == 'held', mine().planMode == 'picks'
		local edge = { C.gold[1] * 0.7, C.gold[2] * 0.7, C.gold[3] * 0.7, 1 }
		for b, on in pairs({ [ui.segAuto] = not heldMode and not mineMode, [ui.segMine] = not heldMode and mineMode, [ui.segHeld] = heldMode }) do
			local text = b == ui.segAuto and 'Auto plan' or b == ui.segMine and 'Pick my own' or 'Hand in what I have'
			b:SetText((on and GOLD or WHITE) .. text .. '|r')
			S.Box(b, on and C.hover or C.panel, on and edge or C.border)
		end
		S.Box(ui.showAll.box, settings().showOthers ~= false and C.gold or { 0.08, 0.08, 0.08, 1 }, C.border)
		ui.modeLine:SetText(heldMode and 'Writs in your bags, mail and bank: their route, nothing to buy.'
			or mineMode and 'Only the writs you pick on the map: nothing chosen for you.'
			or 'Planned from your goal and the AH prices: the writs chosen for you.')
		local totals = pickTotals()
		ui.pickTotals:SetText(totals or (MUTED .. (mineMode and 'Nothing picked: click writs on the map to pick them.' or 'Click a writ on the map to add it to the plan.') .. '|r'))
		ui.pickClear:SetShown(totals ~= nil)
	end
	local hr = ui.heldInfo
	if ui.mapSource == 'held' and hr then
		local extra = {}
		if #hr.needItem > 0 then extra[#extra + 1] = #hr.needItem .. ' need their item' end
		if #hr.noPlace > 0 then extra[#extra + 1] = #hr.noPlace .. ' with no known hand-in' end
		if #hr.doneToday > 0 then extra[#extra + 1] = #hr.doneToday .. ' already handed in today (tomorrow)' end
		ui.mapSummary:SetText(route and (('%d writs held: this route, %d min, +%s rep%s'):format(#hr.writs, math.floor(route.total / 60 + 0.5), commas(hr.rep), #extra > 0 and ('. ' .. table.concat(extra, ', ')) or ''))
			or ('Nothing held to hand in now' .. (#extra > 0 and (': ' .. table.concat(extra, ', ')) or '.')))
	else
		local text
		if route then
			local days = settings().days
			local who = mine().planMode == 'picks' and 'Your picks' or (days > 1 and ('Auto: day 1 of ' .. days .. ', for ' .. (State.GOALS[settings().goal] or {})[1]) or ('Auto: today, for ' .. (State.GOALS[settings().goal] or {})[1]))
			local writs = 0
			for _, l in ipairs(route.legs) do if not l.mail then writs = writs + #l.writs end end
			text = ('%s%s|r: %d writs, %d stops, about %d min, %s in flights'):format(WHITE, who, writs, #route.legs, math.floor(route.total / 60 + 0.5), Plan.Money(route.fares))
			local list = Buy.List()
			local wl, il = 0, 0
			for _, e in ipairs(list or {}) do
				local left = e.need - e.bought
				if left > 0 then if e.writ then wl = wl + left else il = il + left end end
			end
			if wl + il > 0 then
				text = text .. '\n' .. ORANGE .. ('Buy first: %d writ%s and %d item%s (BUY LIST, at the AH). The route starts at a mailbox to collect them.'):format(wl, wl == 1 and '' or 's', il, il == 1 and '' or 's') .. '|r'
			else
				text = text .. '\n' .. GREEN .. 'Everything bought or held: collect any mail on the way, and go.|r'
			end
		else
			text = plan and plan.mine and 'Nothing picked yet: every writ is on the map. Click one to pick it; its shopping list and route follow.' or 'Plan first: the route shows here.'
		end
		ui.mapSummary:SetText(text)
	end
	local steps = route and Plan.RouteSteps(route) or {}
	ui.inPlan = {}
	if plan and plan.days and plan.days[1] then for _, pk in ipairs(plan.days[1].writs) do ui.inPlan[pk.writ] = true end end
	local byPlace = {}
	if plan and plan.rows and ui.mapSource ~= 'held' then
		for _, r in ipairs(plan.rows) do
			if r.place and r.rep > 0 then byPlace[r.place] = byPlace[r.place] or {}; table.insert(byPlace[r.place], r) end
		end
	end
	ui.byPlace = byPlace
	local vals = {}
	for _, list in pairs(byPlace) do
		for _, r in ipairs(list) do
			local st_ = candState(r)
			if st_ ~= 'done' and st_ ~= 'none' and not r.ready then vals[#vals + 1] = perRep(r) end
		end
	end
	table.sort(vals)
	local function valueT(x)
		if not x or #vals < 2 then return 0.5 end
		local lo = 0
		for _, v in ipairs(vals) do if v < x then lo = lo + 1 end end
		return lo / (#vals - 1)
	end
	local function placeSum(list)
		local sm = { n = 0, cost = 0, net = 0, rep = 0, open = {}, done = 0, none = 0, picked = 0, thin = 0, free = 0 }
		for _, r in ipairs(list) do
			local st_ = candState(r)
			if st_ == 'done' then sm.done = sm.done + 1
			elseif st_ == 'none' then sm.none = sm.none + 1
			else
				sm.n, sm.cost, sm.rep = sm.n + 1, sm.cost + grossCost(r), sm.rep + r.rep
				sm.net = sm.net + (perRep(r) or 0) * r.rep
				sm.open[#sm.open + 1] = r
				if st_ == 'picked' then sm.picked = sm.picked + 1 elseif st_ == 'thin' then sm.thin = sm.thin + 1 else sm.free = sm.free + 1 end
				local pr = perRep(r)
				if pr and (not sm.bestPer or pr < sm.bestPer) then sm.best, sm.bestPer = r, pr end
			end
		end
		sm.state = sm.picked > 0 and 'picked' or sm.free > 0 and 'avail' or sm.thin > 0 and 'thin' or (sm.done > 0 and sm.none == 0) and 'done' or 'none'
		sm.color = STATE_COLOR[sm.state] or valueColor(valueT(sm.bestPer))
		sm.value = valueColor(valueT(sm.bestPer))
		sm.label = sm.best and (sm.best.ready and 'held' or short(grossCost(sm.best))) or nil
		return sm
	end
	local function placeTip(place, title)
		local tip = { title }
		for _, r in ipairs(byPlace[place] or {}) do tip[#tip + 1] = candLine(r) end
		tip[#tip + 1] = MUTED .. 'Click: pick writs here|r'
		return tip
	end
	local stops = {}
	for _, st in ipairs(steps) do
		if st.row then
			stops[#stops + 1] = st
			st.n = #stops
			local pl = D.places[st.row]
			st.pos = contPos(pl[3], pl[4], pl[5])
			st.zone = pl[2]
			st.hand = st.kind == 'stop' and (#(st.writs or {}) + (st.label and 1 or 0)) or 0
			st.badge = st.kind == 'mail' and 'M' or tostring(st.hand)
			st.tip = { st.n .. '. ' .. (st.text:match('^[^:]+') or '') }
			for _, wr in ipairs(st.writs or {}) do st.tip[#st.tip + 1] = (wr.n > 1 and (wr.n .. ' x ') or '') .. wr.itemName end
			if st.label then st.tip[#st.tip + 1] = 'Shipping Label (+2,000)' end
			if byPlace[st.row] and st.kind == 'stop' then
				local place = st.row
				st.tip = placeTip(place, st.tip[1])
				st.pick = function() ui.openPicker(place) end
			end
		end
	end
	local others = {}
	local nonePicked = mine().planMode == 'picks' and not (plan and plan.picks and #plan.picks > 0)
	if settings().showOthers ~= false or nonePicked then
		local onRoute = {}
		for _, st in ipairs(stops) do onRoute[st.row] = true end
		for place = 1, #D.places do
			local list = byPlace[place]
			if list and not onRoute[place] then
				local pl = D.places[place]
				local pos = contPos(pl[3], pl[4], pl[5])
				if pos then
					local sm = placeSum(list)
					others[#others + 1] = { pos = pos, place = place, n = sm.n > 0 and sm.n or #list, zone = pl[2], open = sm.n > 0, picked = sm.picked > 0,
						state = sm.state, color = sm.color, value = sm.value, label = sm.label, sum = sm,
						tip = placeTip(place, pl[1] .. (pl[2] and (', ' .. pl[2]) or '')), pick = function() ui.openPicker(place) end }
				end
			end
		end
	end
	local zoneSums, zs = {}, {}
	for place = 1, #D.places do
		local list = byPlace[place]
		if list then
			local pl = D.places[place]
			local zn = pl[2] or pl[1]
			local z = zs[zn]
			if not z then z = { name = zn, n = 0, cost = 0, net = 0, rep = 0, rows = {}, pts = {}, done = 0, all = 0 }; zs[zn] = z; zoneSums[#zoneSums + 1] = z end
			local sm = placeSum(list)
			z.n, z.cost, z.net, z.rep, z.done, z.all = z.n + sm.n, z.cost + sm.cost, z.net + sm.net, z.rep + sm.rep, z.done + sm.done, z.all + #list
			for _, r in ipairs(sm.open) do z.rows[#z.rows + 1] = r end
			local pos = contPos(pl[3], pl[4], pl[5])
			if pos then z.pts[#z.pts + 1] = pos end
		end
	end
	ui.zoneMin = (ui.zoneMinFor == plan) and ui.zoneMin or {}
	ui.zoneMinFor = plan
	for _, z in ipairs(zoneSums) do
		z.per = z.rep > 0 and z.net / z.rep or nil
		z.color = z.n > 0 and valueColor(valueT(z.per)) or STATE_COLOR.done
		z.allPicked = function()
			if #z.rows == 0 then return false end
			for _, r in ipairs(z.rows) do if not picksOf()[r.writ] then return false end end
			return true
		end
		z.pickAll = function()
			local set, on = picksOf(), not z.allPicked()
			for _, r in ipairs(z.rows) do set[r.writ] = on or nil end
			if ui.doPlan then ui.doPlan() end
			ui.drawRoute()
		end
		z.minutes = function()
			if ui.zoneMin[z.name] == nil then
				local _, class = UnitClass('player')
				local ok, rt = pcall(Plan.Route, { writs = z.rows, start = State.Start(), bags = bagCap(), hearth = State.Hearth(), druid = class == 'DRUID', mage = class == 'MAGE' })
				ui.zoneMin[z.name] = (ok and rt and #z.rows > 0) and math.floor(rt.total / 60 + 0.5) or false
			end
			return ui.zoneMin[z.name] or nil
		end
		z.short = z.n > 0 and ('%d writ%s · %s · +%s'):format(z.n, z.n == 1 and '' or 's', short(z.cost), commas(z.rep)) or (z.done > 0 and 'all handed in today' or 'none on the AH')
	end
	table.sort(zoneSums, function(a, b)
		if (a.n > 0) ~= (b.n > 0) then return a.n > 0 end
		if a.per and b.per and a.per ~= b.per then return a.per < b.per end
		return a.name < b.name
	end)
	ui.zoneSums = zoneSums
	do local nextLeg; for i = #steps, 1, -1 do if steps[i].row then nextLeg = steps[i].n end steps[i].li = nextLeg end end
	local byZone, zoneOrder = {}, {}
	for _, st in ipairs(stops) do
		local zn = st.zone or '?'
		local e = byZone[zn]
		if not e then e = { name = zn, hand = 0, sec = 0, mail = 0, pts = {} }; byZone[zn] = e; zoneOrder[#zoneOrder + 1] = e end
		e.hand = e.hand + st.hand
		if st.kind == 'mail' then e.mail = e.mail + 1 end
		local leg = route.legs[st.n]
		e.sec = e.sec + (leg and leg.sec or 0)
		if st.pos then e.pts[#e.pts + 1] = st.pos end
	end
	local rows = {}
	if #zoneOrder > 1 then
		rows[#rows + 1] = { head = 'BY ZONE' }
		for _, e in ipairs(zoneOrder) do
			local bits = {}
			if e.hand > 0 then bits[#bits + 1] = e.hand .. ' hand-in' .. (e.hand == 1 and '' or 's') end
			if e.mail > 0 then bits[#bits + 1] = 'mailbox' end
			bits[#bits + 1] = math.max(1, math.floor(e.sec / 60 + 0.5)) .. ' min'
			rows[#rows + 1] = { text = WHITE .. e.name .. '|r' .. MUTED .. ': ' .. table.concat(bits, ', ') .. '|r', zone = e }
		end
		rows[#rows + 1] = { head = 'STEPS' }
	end
	for _, st in ipairs(steps) do rows[#rows + 1] = { step = st } end
	local y = 0
	for i, row in ipairs(rows) do
		local r = ui.routeRows[i]
		if not r then
			r = CreateFrame('Frame', nil, ui.routeList)
			r.t = S.Text(r, 12); r.t:SetPoint('TOPLEFT', 44, 0); r.t:SetWidth(LW() - 60); r.t:SetWordWrap(true)
			r.m = S.Text(r, 11, C.muted, 'RIGHT'); r.m:SetPoint('TOPLEFT', 0, 0); r.m:SetWidth(38)
			r.hl = r:CreateTexture(nil, 'BACKGROUND'); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.06); r.hl:Hide()
			r:EnableMouse(true)
			r:SetScript('OnEnter', function(self)
				if self.li or self.zone then self.hl:Show() end
				if self.li then hiLeg(self.li, true) end
				if not self.writs or #self.writs == 0 then return end
				GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
				for _, wr in ipairs(self.writs) do GameTooltip:AddLine((wr.n > 1 and (wr.n .. ' x ') or '') .. wr.itemName, 1, 1, 1) end
				GameTooltip:Show()
			end)
			r:SetScript('OnLeave', function(self) self.hl:Hide(); if self.li then hiLeg(self.li, false) end GameTooltip:Hide() end)
			r:SetScript('OnMouseUp', function(self) if self.go then self.go() end end)
			ui.routeRows[i] = r
		end
		r.writs, r.li, r.zone, r.go = nil, nil, nil, nil
		r.t:ClearAllPoints()
		if r.btn then r.btn:Hide() end
		if row.zsum then
			local z = row.zsum
			local mins = z.minutes()
			r.t:SetPoint('TOPLEFT', 0, 0)
			r.t:SetText(('%s %s%s|r  %s%s|r%s'):format(swatch(z.color), WHITE, z.name, MUTED, z.short, mins and ('  ~' .. mins .. ' min') or ''))
			r.m:SetText('')
			r.zone = z
			r.go = function() if ui.omMode then return ns.OMRoute.Fit(z.pts) end mapGo(z.pts[1], 4) end
			if not r.btn then
				r.btn = S.Button(r, 'Pick all', 58, 18, function(self) if self.z then self.z.pickAll() end end)
				r.btn:SetPoint('TOPRIGHT', 0, 1)
			end
			r.btn.z = z
			r.btn:SetText(z.allPicked() and 'Unpick' or 'Pick all')
			r.btn:Show()
		elseif row.head then
			r.t:SetPoint('TOPLEFT', 0, i == 1 and 0 or -6); r.t:SetText(GOLD .. row.head .. '|r'); r.m:SetText('')
		elseif row.zone then
			r.t:SetPoint('TOPLEFT', 0, 0); r.t:SetText(row.text); r.m:SetText('')
			r.zone = row.zone
			r.go = function()
				local pts = row.zone.pts
				if #pts == 0 then return end
				if ui.omMode then return ns.OMRoute.Fit(pts) end
				if pts[1].c ~= ui.mapCont then ui.mapContPicked = pts[1].c; ui.drawRoute() end
				local same = {}
				for _, p in ipairs(pts) do if p.c == pts[1].c then same[#same + 1] = p end end
				local nv = fitView(same, pts[1].c); nv.key = ui.mapView and ui.mapView.key
				ui.mapView = nv; mapRender()
			end
		else
			local st = row.step
			local stop = st.kind == 'stop' or st.kind == 'mail'
			r.t:SetPoint('TOPLEFT', 44, 0)
			r.t:SetText((stop and (GOLD .. st.n .. '.|r ') or MUTED) .. st.text .. (stop and '' or '|r'))
			r.m:SetText(st.at and (math.floor(st.at / 60 + 0.5) .. ' min') or '')
			r.writs, r.li = st.writs, st.li
			local target = st.li and stops[st.li]
			if target and target.pos then r.go = function() mapGo(target.pos, 6) end end
		end
		r.t:SetWidth(row.step and (LW() - 60) or row.zsum and (LW() - 80) or (LW() - 16))
		local hgt = math.max(16, (r.t:GetStringHeight() or 14) + 5) + (row.head and i > 1 and 6 or 0)
		r:SetSize(LW() - 10, hgt)
		r:ClearAllPoints(); r:SetPoint('TOPLEFT', 0, -y)
		r:Show()
		y = y + hgt
	end
	for i = #rows + 1, #ui.routeRows do ui.routeRows[i]:Hide() end
	ui.routeList:SetHeight(math.max(1, y))
	if ui.fitStrip then ui.fitStrip(y) end
	if not route then
		if #others > 0 then
			local sp = D.nodes[State.Start()]
			local spos = sp and contPos(sp[2], sp[3], sp[4])
			local count = {}
			for _, o in ipairs(others) do count[o.pos.c] = (count[o.pos.c] or 0) + 1 end
			local cont = ui.mapContPicked or (((count[1414] or 0) >= (count[1415] or 0)) and 1414 or 1415)
			ui.mapCont = cont
			ui.mapData = { cont = cont, stops = {}, legs = {}, others = others, zones = zoneSums, start = { pos = spos, tip = { 'Start' } } }
			if ui.omMode then ns.OMRoute.SetData(ui.mapData); return end
			local key = 'others:' .. cont
			if not ui.mapView or ui.mapView.key ~= key then
				local pts = {}
				for _, o in ipairs(others) do if o.pos.c == cont then pts[#pts + 1] = o.pos end end
				ui.mapView = fitView(pts, cont); ui.mapView.key = key
			end
			return mapRender()
		end
		ui.mapData = nil
		if ui.omMode then ns.OMRoute.SetData(nil) else m.none:SetText(''); mapRender() end
		return
	end
	local sn = D.nodes[route.start]
	local startPos = contPos(sn[2], sn[3], sn[4])
	local count = {}
	for _, st in ipairs(stops) do if st.pos then count[st.pos.c] = (count[st.pos.c] or 0) + 1 end end
	local cont = ui.mapCont
	if not cont or not count[cont] then cont = ((count[1414] or 0) >= (count[1415] or 0)) and 1414 or 1415 end
	if ui.mapContPicked then cont = ui.mapContPicked end
	ui.mapCont = cont
	ui.contK:SetText((cont == 1414 and GOLD or WHITE) .. 'Kalimdor' .. (count[1414] and (' (' .. count[1414] .. ')') or '') .. '|r')
	ui.contE:SetText((cont == 1415 and GOLD or WHITE) .. 'Eastern Kingdoms' .. (count[1415] and (' (' .. count[1415] .. ')') or '') .. '|r')
	local legs = {}
	local prev = startPos
	for li, leg in ipairs(route.legs) do
		local stop = stops[li]
		local cur = prev
		local how, segs = {}, {}
		if leg.port then
			local nd = D.nodes[leg.port.node]
			cur = nd and contPos(nd[2], nd[3], nd[4]) or cur
			how[#how + 1] = (leg.port.kind == 'hearth' and 'Hearth to ' or 'Teleport to ') .. leg.port.name
		end
		for _, h in ipairs(leg.hops) do
			local kind, from, to, map, x, y_ = unpack(D.hops[h])
			local dep = contPos(map, x, y_) or cur
			if cur and dep then segs[#segs + 1] = { cur, dep, 'ride' } end
			local tn = nodeByName[to]
			local arr = tn and contPos(tn[2], tn[3], tn[4]) or nil
			if arr and dep then segs[#segs + 1] = { dep, arr, kind == 'fly' and 'fly' or 'boat' } end
			how[#how + 1] = (kind == 'fly' and 'Flight ' or ((kind == 'zeppelin' and 'Zeppelin ' or 'Boat '))) .. from .. ' to ' .. to
			cur = arr or dep
		end
		if stop and stop.pos and cur then segs[#segs + 1] = { cur, stop.pos, 'ride' } end
		if #how == 0 then how[1] = 'Ride' end
		local min = math.max(1, math.floor(leg.sec / 60 + 0.5))
		legs[li] = { segs = segs, from = prev, to = stop and stop.pos, min = min,
			tip = { ('%d min to %s'):format(min, stop and (stop.text:match('^[^:]+') or '') or ''), table.concat(how, ', ') .. (leg.fare and leg.fare > 0 and ('. Flights ' .. Plan.Money(leg.fare)) or '') } }
		prev = stop and stop.pos or prev
	end
	ui.mapData = { cont = cont, stops = stops, legs = legs, others = others, zones = zoneSums, start = { pos = startPos, tip = { 'Start: ' .. sn[1] } } }
	if ui.omMode then ns.OMRoute.SetData(ui.mapData); return end
	local key = tostring(route) .. ':' .. cont
	if not ui.mapView or ui.mapView.key ~= key then
		local pts = {}
		if startPos and startPos.c == cont then pts[1] = startPos end
		for _, st in ipairs(stops) do if st.pos and st.pos.c == cont then pts[#pts + 1] = st.pos end end
		ui.mapView = fitView(pts, cont)
		ui.mapView.key = key
	end
	mapRender()
end

local function heldRoute()
	local st = State.Read(db)
	local items = {}
	for id, k in pairs(st.items) do items[id] = k end
	local out = { writs = {}, needItem = {}, noPlace = {}, doneToday = {}, rep = 0 }
	for _, w in ipairs(D.writs) do
		local writ, quest, item, n, tier, place, wname, iname, stack = unpack(w)
		if (st.held[writ] or 0) > 0 then
			local e = { writ = writ, quest = quest, item = item, n = n, tier = tier, place = place, name = wname, itemName = iname, stack = stack, rep = D.rep[tier] }
			if st.done[quest] then out.doneToday[#out.doneToday + 1] = e
			elseif not place then out.noPlace[#out.noPlace + 1] = e
			elseif (items[item] or 0) < n then out.needItem[#out.needItem + 1] = e
			else
				items[item] = items[item] - n
				out.writs[#out.writs + 1] = e
				out.rep = out.rep + e.rep
			end
		end
	end
	local label = State.Label()
	local withLabel = not label.done and (label.held or label.onQuest)
	if withLabel then out.rep = out.rep + label.rep end
	if #out.writs == 0 and not withLabel then return out, nil end
	local inMail = false
	for _ in pairs(st.from.mail) do inMail = true end
	for _ in pairs(st.from.bought) do inMail = true end
	local _, class = UnitClass('player')
	local route = Plan.Route({ writs = out.writs, start = State.Start(), bags = inMail and bagCap() or 0, hearth = State.Hearth(), druid = class == 'DRUID', mage = class == 'MAGE', label = withLabel and label or nil })
	return out, route
end

local function buildMap()
	local w = CreateFrame('Frame', PREFIX .. 'Route', UIParent)
	w:SetSize(MAP_W, 640)
	w:SetFrameStrata('HIGH')
	w:SetPoint('TOPLEFT', ui.frame, 'TOPRIGHT', 6, 0)
	w:SetScale(settings().scale or 1)
	S.Box(w, C.bg, C.border)
	local head = CreateFrame('Frame', nil, w)
	head:SetPoint('TOPLEFT', 1, -1); head:SetPoint('TOPRIGHT', -1, -1); head:SetHeight(30)
	S.Box(head, C.panel, { 0, 0, 0, 0 })
	local title = S.Text(head, 14, C.gold); title:SetPoint('LEFT', PAD - 1, 0); title:SetText('Route')
	local close = S.Button(head, 'x', 24, 22, function() ui_hideRoute() end); close:SetPoint('RIGHT', -4, 0)
	ui.mapClose = close
	ui.mapFold = S.Button(head, '<', 24, 22, function() ui.foldRoute(true) end); ui.mapFold:SetPoint('RIGHT', close, 'LEFT', -4, 0)
	local function tipFor(b, title, text)
		b:HookScript('OnEnter', function(self) GameTooltip:SetOwner(self, 'ANCHOR_BOTTOM'); GameTooltip:AddLine(title); GameTooltip:AddLine(text, 1, 1, 1, true); GameTooltip:Show() end)
		b:HookScript('OnLeave', function() GameTooltip:Hide() end)
	end
	ui.contE = S.Button(head, 'Eastern Kingdoms', 150, 22, function() ui.mapContPicked = 1415; ui.drawRoute() end)
	ui.contE:SetPoint('RIGHT', close, 'LEFT', -16, 0)
	ui.contK = S.Button(head, 'Kalimdor', 110, 22, function() ui.mapContPicked = 1414; ui.drawRoute() end)
	ui.contK:SetPoint('RIGHT', ui.contE, 'LEFT', -4, 0)
	ui.mapModeBtn = S.Button(w, 'OpenMap', 80, 22, function()
		settings().routeMap = ui.omMode and 'here' or 'openmap'
		ui_applyMapMode()
		if ui.omMode then ns.OMRoute.Open(true) else ns.OMRoute.SetOn(false) end
		ui.drawRoute()
	end)
	ui.mapModeBtn:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_BOTTOM')
		GameTooltip:AddLine('Where the map is')
		GameTooltip:AddLine(ui.omMode and "On OpenMap's world map (M): the steps here move it. Click for the map in this window instead."
			or "In this window. Click to put the route on OpenMap's world map instead.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	ui.mapModeBtn:HookScript('OnLeave', function() GameTooltip:Hide() end)
	ui.mapFitBtn = S.Button(head, 'Fit', 40, 22, function() ns.OMRoute.Open(true) end)
	ui.mapFitBtn:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_BOTTOM')
		GameTooltip:AddLine('The whole route')
		GameTooltip:AddLine("Opens the world map fitted to the route. Click a step or a zone here to go to it; a group on the map zooms in.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	ui.mapFitBtn:HookScript('OnLeave', function() GameTooltip:Hide() end)
	local seg = CreateFrame('Frame', nil, w)
	seg:SetPoint('TOPLEFT', PAD, -40); seg:SetSize(LIST_W - 10, 22)
	ui.planSeg = seg

	local function choose(which)
		if which == 'held' then return ui.routeHeld(true) end
		ui.mapSource = 'plan'
		mine().planMode = which
		if ui.doPlan then ui.doPlan() end
		ui.drawRoute()
	end
	ui.segAuto = S.Button(seg, 'Auto plan', 72, 22, function() choose('auto') end); ui.segAuto:SetPoint('LEFT', 0, 0)
	ui.segMine = S.Button(seg, 'Pick my own', 88, 22, function() choose('picks') end); ui.segMine:SetPoint('LEFT', ui.segAuto, 'RIGHT', -1, 0)
	ui.segHeld = S.Button(seg, 'Hand in what I have', 128, 22, function() choose('held') end); ui.segHeld:SetPoint('LEFT', ui.segMine, 'RIGHT', -1, 0)
	tipFor(ui.segAuto, 'Auto plan', 'Planned from your goal (the reputation and days in the panel) and the AH prices: the writs chosen for you, bought, then this route.')
	tipFor(ui.segMine, 'Pick my own', 'Only the writs you pick on the map, nothing chosen for you: their shopping list, then their route. Clear empties it.')
	tipFor(ui.segHeld, 'Hand in what I have', 'The writs already in your bags, mail and bank, with their items: their route. Nothing to buy.')
	ui.modeLine = S.Text(w, 11, C.muted); ui.modeLine:SetPoint('TOPLEFT', PAD, -66); ui.modeLine:SetWidth(LIST_W - 10)
	local sa = CreateFrame('Button', nil, w)
	sa:SetPoint('TOPLEFT', PAD, -84); sa:SetSize(LIST_W - 10, 18)
	sa.box = CreateFrame('Frame', nil, sa); sa.box:SetSize(13, 13); sa.box:SetPoint('LEFT', 2, 0)
	sa.t = S.Text(sa, 12); sa.t:SetPoint('LEFT', sa.box, 'RIGHT', 7, 0); sa.t:SetText('Show all writs on the map')
	sa:SetScript('OnClick', function() settings().showOthers = settings().showOthers == false; ui.drawRoute() end)
	tipFor(sa, 'Show all writs', 'Every writ hand-in on the map, coloured by value and state, to pick from. Off: only the route.')
	ui.showAll = sa
	ui.mapSummary = S.Text(w, 12); ui.mapSummary:SetPoint('TOPLEFT', PAD, -110); ui.mapSummary:SetWidth(LIST_W - 10)
	local pr = CreateFrame('Frame', nil, w)
	pr:SetPoint('TOPLEFT', ui.mapSummary, 'BOTTOMLEFT', 0, -6); pr:SetSize(LIST_W - 10, 20)
	ui.pickRow = pr
	ui.pickTotals = S.Text(pr, 11, C.text); ui.pickTotals:SetPoint('LEFT'); ui.pickTotals:SetWidth(LIST_W - 110)
	ui.pickClear = S.Button(pr, 'Clear my picks', 96, 20, function() mine().picks = {}; if ui.doPlan then ui.doPlan() end; ui.drawRoute() end)
	ui.pickClear:SetPoint('RIGHT')
	tipFor(ui.pickClear, 'Clear my picks', 'Unpicks every writ you picked. (Auto still plans its own writs for your goal.)')
	local sf = CreateFrame('ScrollFrame', nil, w)
	sf:SetPoint('TOPLEFT', pr, 'BOTTOMLEFT', 0, -6); sf:SetPoint('BOTTOMLEFT', PAD, 96); sf:SetWidth(LIST_W - 10)
	local rc = CreateFrame('Frame', nil, sf)
	rc:SetSize(LIST_W - 10, 400)
	sf:SetScrollChild(rc)
	sf:EnableMouseWheel(true)
	sf:SetScript('OnMouseWheel', function(self, d)
		local max = math.max(0, rc:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 36)))
	end)
	ui.routeList, ui.routeRows, ui.mapSF = rc, {}, sf
	local key = S.Text(w, 11, C.muted); key:SetPoint('BOTTOMLEFT', PAD, 44); key:SetWidth(LIST_W - 10)
	ui.mapKey = key
	ui.mapRxp = S.Button(w, 'Send route to RestedXP', 186, 26, function() ui.sendToRXP(shownRoute()) end, true)
	ui.mapRxp:SetPoint('BOTTOMLEFT', PAD, 10)
	tipFor(ui.mapRxp, 'Send route to RestedXP', 'This route as a RestedXP guide (group "Writs and Favors"), opened for you.')
	ui.mapModeBtn:SetPoint('LEFT', ui.mapRxp, 'RIGHT', 8, 0)
	key:SetText(WHITE .. '---|r ride   ' .. GOLD .. '- - -|r flight   |cff73bfff. . .|r boat, zeppelin   badge: hand-ins\nWheel: zoom   drag: move   click a step: go to it')
	local mb = CreateFrame('Frame', nil, w)
	ui.mapBox = mb
	mb:SetPoint('TOPLEFT', LIST_W + PAD, -MAP_TOP); mb:SetPoint('BOTTOMRIGHT', -PAD, PAD)
	S.Box(mb, { 0.03, 0.03, 0.035, 1 }, C.border)
	local m = CreateFrame('Frame', PREFIX .. 'RouteMap', mb)
	m:SetPoint('TOPLEFT', 4, -4); m:SetPoint('BOTTOMRIGHT', -4, 4)
	if m.SetClipsChildren then m:SetClipsChildren(true) end
	m.art = CreateFrame('Frame', nil, m)
	m.art:SetPoint('TOPLEFT')
	m.tiles, m.ztiles, m.lines, m.sqs, m.stops, m.legs, m.clusters, m.zlabels = {}, {}, {}, {}, {}, {}, {}, {}
	m.none = S.Text(m, 12, C.muted, 'CENTER'); m.none:SetPoint('CENTER')
	m:EnableMouse(true); m:EnableMouseWheel(true)
	local function cursor()
		local x, y = GetCursorPosition()
		local sc, l, t = m:GetEffectiveScale() or 1, m:GetLeft(), m:GetTop()
		if not (x and l and t) then return end
		return x / sc - l, t - y / sc
	end
	m:SetScript('OnMouseWheel', function(_, delta) if ui.picker then ui.picker:Hide() end local mx, my = cursor(); zoomAround(delta > 0 and 1.5 or 1 / 1.5, mx, my) end)
	m:SetScript('OnMouseDown', function(self, btn)
		if ui.picker then ui.picker:Hide() end
		if btn ~= 'LeftButton' or not ui.mapView then return end
		local x, y = GetCursorPosition()
		if x then self.drag = { x = x, y = y, cx = ui.mapView.cx, cy = ui.mapView.cy, s = self:GetEffectiveScale() or 1, at = 0 } end
	end)
	m:SetScript('OnMouseUp', function(self) if self.drag then self.drag = nil; mapRender() end end)
	m:SetScript('OnHide', function(self) self.drag = nil end)
	m:SetScript('OnUpdate', function(self)
		local dr, v = self.drag, ui.mapView
		if not (dr and v and self.aw) then return end
		local x, y = GetCursorPosition()
		v.cx = dr.cx - (x - dr.x) / dr.s / self.aw
		v.cy = dr.cy + (y - dr.y) / dr.s / self.ah
		local now = GetTime()
		if now - dr.at > 0.05 then dr.at = now; mapRender() end
	end)
	local zb = CreateFrame('Frame', nil, mb)
	zb:SetSize(150, 24); zb:SetPoint('TOPRIGHT', -8, -8)
	zb:SetFrameLevel((m:GetFrameLevel() or 1) + 50)
	local zfit = S.Button(zb, 'Fit', 40, 22, function() if ui.mapView then ui.mapView.key = nil end ui.drawRoute() end)
	zfit:SetPoint('RIGHT')
	local zout = S.Button(zb, '-', 24, 22, function() zoomAround(1 / 1.5) end); zout:SetPoint('RIGHT', zfit, 'LEFT', -4, 0)
	local zin = S.Button(zb, '+', 24, 22, function() zoomAround(1.5) end); zin:SetPoint('RIGHT', zout, 'LEFT', -4, 0)
	ui.mapZoomText = S.Text(zb, 11, C.muted, 'RIGHT'); ui.mapZoomText:SetPoint('RIGHT', zin, 'LEFT', -6, 0)
	for _, b in ipairs({ zfit, zout, zin }) do
		b:HookScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
			GameTooltip:AddLine(self == zfit and 'Back to the whole route' or self == zin and 'Zoom in' or 'Zoom out')
			GameTooltip:AddLine('Mouse wheel zooms where the cursor is; drag to move. Click a stop or a group to zoom in on it.', 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:HookScript('OnLeave', function() GameTooltip:Hide() end)
	end
	ui.map, ui.mapWin = m, w
	w:Hide()
end
local function fillPicker()
	local pk = ui.picker
	local list = ui.byPlace and ui.byPlace[pk.place] or {}
	local pl = D.places[pk.place]
	pk.title:SetText(pl and (pl[1] .. (pl[2] and (MUTED .. ', ' .. pl[2] .. '|r') or '')) or '')
	local y = -30
	for i, r in ipairs(list) do
		local row = pk.rows[i]
		if not row then
			row = CreateFrame('Button', nil, pk)
			row:SetHeight(20)
			row.hl = row:CreateTexture(nil, 'BACKGROUND'); row.hl:SetAllPoints(); row.hl:SetColorTexture(1, 1, 1, 0.07); row.hl:Hide()
			row.box = CreateFrame('Frame', nil, row); row.box:SetSize(12, 12); row.box:SetPoint('LEFT', 2, 0)
			row.t = S.Text(row, 12); row.t:SetPoint('LEFT', 20, 0); row.t:SetPoint('RIGHT', -2, 0)
			row:SetScript('OnEnter', function(self) if self.can then self.hl:Show() end end)
			row:SetScript('OnLeave', function(self) self.hl:Hide() end)
			row:SetScript('OnClick', function(self)
				if not self.can then return end
				local set = picksOf()
				set[self.writ] = not set[self.writ] or nil
				if ui.doPlan then ui.doPlan() end
				ui.drawRoute()
				fillPicker()
			end)
			pk.rows[i] = row
		end
		local state = candState(r)
		row.writ, row.can = r.writ, state ~= 'done' and state ~= 'none'
		local on = state == 'picked'
		S.Box(row.box, on and C.green or (state == 'planned' and C.gold) or { 0.1, 0.1, 0.1, 1 }, row.can and C.border or { 0.15, 0.15, 0.15, 1 })
		row.t:SetText(candLine(r))
		row.t:SetAlpha(row.can and 1 or 0.55)
		row:ClearAllPoints(); row:SetPoint('TOPLEFT', 8, y); row:SetPoint('TOPRIGHT', -8, y)
		row:Show()
		y = y - 21
	end
	for i = #list + 1, #pk.rows do pk.rows[i]:Hide() end
	pk.foot:SetText((pickTotals() or (MUTED .. 'Nothing picked yet|r')) .. '\n' .. MUTED .. (mine().planMode == 'picks' and 'My picks: only these are planned' or 'Auto plan: picks are planned first, the rest round them') .. '|r')
	pk:SetHeight(-y + 44)
end
ui_openPicker = function(place)
	if not (ui.byPlace and ui.byPlace[place]) then return end
	local pk = ui.picker
	if not pk then
		pk = CreateFrame('Frame', PREFIX .. 'Picker', UIParent)
		pk:SetSize(400, 120)
		pk:SetFrameStrata('TOOLTIP')
		pk:SetClampedToScreen(true)
		pk:EnableMouse(true)
		S.Box(pk, C.bg, C.border)
		pk.title = S.Text(pk, 13, C.gold); pk.title:SetPoint('TOPLEFT', 10, -9); pk.title:SetPoint('TOPRIGHT', -34, -9)
		local x = S.Button(pk, 'x', 22, 20, function() pk:Hide() end); x:SetPoint('TOPRIGHT', -4, -4)
		pk.foot = S.Text(pk, 11, C.text); pk.foot:SetPoint('BOTTOMLEFT', 10, 8); pk.foot:SetPoint('BOTTOMRIGHT', -10, 8)
		pk.rows = {}
		ui.picker = pk
		if UISpecialFrames then table.insert(UISpecialFrames, pk:GetName()) end
	end
	pk.place = place
	fillPicker()
	local cx, cy = GetCursorPosition()
	local sc = UIParent:GetEffectiveScale() or 1
	pk:ClearAllPoints()
	if cx then pk:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', cx / sc + 14, cy / sc - 6) else pk:SetPoint('CENTER') end
	pk:Show()
	if ui.omMode and ns.OMRoute then ns.OMRoute.WatchView(function() if ui.picker then ui.picker:Hide() end end) end
end

local function mapUp() return WorldMapFrame and WorldMapFrame:IsShown() end
local function placeStrip()
	local w = ui.mapWin
	if not (w and ui.omMode) then return end
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	w:ClearAllPoints()
	if sc and mapUp() then w:SetPoint('TOPLEFT', sc, 'TOPLEFT', 10, -10)
	else w:SetPoint('TOPLEFT', ui.frame, 'TOPRIGHT', 6, 0) end
	if ui.routeTab then
		ui.routeTab:ClearAllPoints()
		if sc then ui.routeTab:SetPoint('BOTTOMLEFT', sc, 'BOTTOMLEFT', 10, 10) end
	end
end
local function fitStrip(listH)
	local w = ui.mapWin
	if not (w and ui.omMode) then return end
	local h = 110 + (ui.mapSummary:GetStringHeight() or 14) + 6 + 20 + 6 + (listH or 0) + 100
	local most = 640
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	if sc and mapUp() and sc:GetHeight() and w:GetEffectiveScale() and w:GetEffectiveScale() > 0 then
		most = sc:GetHeight() * sc:GetEffectiveScale() / w:GetEffectiveScale() - 20
	end
	w:SetHeight(math.max(240, math.min(most, h)))
end
local function fold(on)
	settings().routeFolded = on and true or nil
	if not ui.routeTab then
		local t = S.Button(UIParent, 'Route  >', 72, 24, function() fold(false) end)
		t:SetFrameStrata('FULLSCREEN_DIALOG')
		ui.routeTab = t
	end
	placeStrip()
	ui.routeTab:SetShown(on and mapUp() and ns.OMRoute.IsOn() or false)
	if on then ui.mapWin:Hide() elseif ns.OMRoute.IsOn() then ui.mapWin:Show(); ui.drawRoute() end
end
local mapHooked
local function hookMap()
	if mapHooked or not WorldMapFrame then return end
	mapHooked = true
	WorldMapFrame:HookScript('OnShow', function()
		if not (ui and ui.omMode and ns.OMRoute and ns.OMRoute.IsOn()) then return end
		if ui.frame:IsShown() and not InCombatLockdown() then ui.hidForMap = true; ui.frame:Hide() end
		placeStrip()
		if settings().routeFolded then fold(true) else ui.mapWin:Show(); ui.drawRoute() end
	end)
	WorldMapFrame:HookScript('OnHide', function()
		if not ui then return end
		if ui.routeTab then ui.routeTab:Hide() end
		if ui.omMode and ui.mapWin then ui.mapWin:Hide() end
		if ui.hidForMap then
			if InCombatLockdown() then ui.showAfterCombat = true
			else ui.hidForMap = nil; ui.frame:Show(); refresh() end
		end
	end)
end

ui_applyMapMode = function()
	if not ui.mapWin then return end
	ui.omMode = omMode()
	local om = ui.omMode
	local lw = LW() - 10
	ui.mapWin:SetWidth(om and OM_W or MAP_W)
	ui.fitStrip, ui.foldRoute = fitStrip, fold
	if om then hookMap(); placeStrip() else ui.mapWin:ClearAllPoints(); ui.mapWin:SetPoint('TOPLEFT', ui.frame, 'TOPRIGHT', 6, 0) end
	ui.mapFold:SetShown(om)
	ui.planSeg:SetWidth(lw); ui.showAll:SetWidth(lw); ui.pickTotals:SetWidth(lw - 100); ui.modeLine:SetWidth(lw)
	ui.mapKey:ClearAllPoints(); ui.mapKey:SetPoint('BOTTOMLEFT', PAD, 44)
	ui.mapSF:SetPoint('BOTTOMLEFT', PAD, om and 96 or 76)
	ui.mapWin:SetFrameStrata(om and 'FULLSCREEN_DIALOG' or 'HIGH')
	ui.mapSummary:SetWidth(lw); ui.mapSF:SetWidth(lw); ui.routeList:SetWidth(lw); ui.mapKey:SetWidth(lw)
	ui.pickRow:SetWidth(lw); ui.pickTotals:SetWidth(lw)
	ui.mapBox:SetShown(not om)
	ui.contK:SetShown(not om); ui.contE:SetShown(not om)
	local avail = not FAVOR_ONLY and ns.OMRoute and ns.OMRoute.Available()
	ui.mapModeBtn:SetShown(avail and true or false)
	ui.mapModeBtn:SetText(om and 'Map: OpenMap' or 'Map: here')
	ui.mapModeBtn:SetWidth(om and 96 or 80)
	ui.mapFitBtn:SetShown(om)
	ui.mapFitBtn:ClearAllPoints(); ui.mapFitBtn:SetPoint('RIGHT', ui.mapFold, 'LEFT', -6, 0)
	local legend = WHITE .. '---|r ride   ' .. GOLD .. '- - -|r flight   |cff73bfff. . .|r boat, zeppelin   badge: hand-ins\n'
	if om then
		legend = legend .. 'Writs: ' .. swatch(valueColor(0)) .. ' cheap ' .. swatch(valueColor(0.5)) .. ' ' .. swatch(valueColor(1)) .. ' dear a rep   '
			.. swatch(STATE_COLOR.picked) .. ' picked   ' .. swatch(STATE_COLOR.thin) .. ' thin stock\n'
			.. swatch(STATE_COLOR.done) .. ' handed in today   ' .. swatch(STATE_COLOR.none) .. ' not on the AH   numbered: on the route\n'
	end
	ui.mapKey:SetText(legend .. (om and 'Click a writ to pick it; a zone: zoom in, Shift: pick it all.' or 'Wheel: zoom   drag: move   click a step: go to it'))
	local fh = 40 + 30 + 90 + 50 + 50
	ui.fitBase = fh
end
local function showRoute(src)
	if not ui.mapWin then buildMap() end
	if src then ui.mapSource = src end
	ui.mapWin:SetScale(settings().scale or 1)
	ui_applyMapMode()
	ui.mapWin:Show()
	ui.drawRoute()
	if ui.omMode then ns.OMRoute.Open(true) end
end
ui_hideRoute = function()
	if ui.mapWin then ui.mapWin:Hide() end
	if ui.picker then ui.picker:Hide() end
	if ns.OMRoute then ns.OMRoute.SetOn(false) end
end
local function routeHeld(show)
	local info, route = heldRoute()
	ui.heldInfo, ui.heldRoute = info, route
	if route then refresh(('%d writs held: this route, %d min, +%s rep%s'):format(#info.writs, math.floor(route.total / 60 + 0.5), commas(info.rep), #info.needItem > 0 and ('. ' .. #info.needItem .. ' need their item') or ''))
	else refresh('Nothing held to hand in now' .. (#info.needItem > 0 and (': ' .. #info.needItem .. ' writs need their item') or ''), true) end
	if show ~= false then showRoute('held') end
end

local function ago(t)
	if not t then return nil end
	local m = math.floor(((GetServerTime and GetServerTime() or time()) - t) / 60)
	return m < 60 and (m .. ' min ago') or m < 1440 and (math.floor(m / 60) .. ' h ago') or (math.floor(m / 1440) .. ' days ago')
end
ui_drawHeld = function()
	local ok, st = pcall(State.Read, db)
	if not ok then return end
	local favor = mine().mode == 'favor'
	local first, second = {}, {}
	if favor then
		local W = D.waylaid
		for _, c in ipairs(W.crates) do first[c[1]] = true; for _, o in ipairs(c[5]) do second[o[1]] = true end end
		for _, t in pairs(W.sealed) do for _, id in pairs(t) do first[id] = true end end
	else
		for _, w in ipairs(D.writs) do first[w[1]] = true; second[w[3]] = true end
	end
	local function count(src)
		local w, i = 0, 0
		for id, n in pairs(src) do if first[id] then w = w + n elseif second[id] then i = i + n end end
		return w, i
	end
	local A, B = favor and 'crates' or 'writs', favor and 'bundle items' or 'items'
	local bw, bi = count(st.from.bags)
	local mw, mi = count(st.from.mail)
	local kw, ki = count(st.from.bank)
	local gw, gi = count(st.from.bought)
	local tw, ti = bw + mw + kw + gw, bi + mi + ki + gi
	local parts = { ('Held: %d %s, %d %s'):format(tw, A, ti, B) }
	if not st.seen.mail then parts[#parts + 1] = 'open your mailbox once to count it' end
	if not st.seen.bank then parts[#parts + 1] = 'open your bank once to count it' end
	if kw + ki > 0 then parts[#parts + 1] = 'take the bank ones out before you go' end
	ui.held.text:SetText(table.concat(parts, '. '))
	ui.held.lines = {
		{ 'In your bags', ('%d %s, %d %s (now)'):format(bw, A, bi, B) },
		{ 'In your mail', st.seen.mail and ('%d %s, %d %s (%s)'):format(mw, A, mi, B, ago(st.seen.mail)) or 'not seen yet: open your mailbox' },
		{ 'In your bank', st.seen.bank and ('%d %s, %d %s (%s)'):format(kw, A, ki, B, ago(st.seen.bank)) or 'not seen yet: open your bank' },
	}
	if gw + gi > 0 then ui.held.lines[#ui.held.lines + 1] = { 'Bought, in the mail', ('%d %s, %d %s (not collected yet)'):format(gw, A, gi, B) } end
end

local function dock()
	local f = ui.frame
	f:SetScale(settings().scale or 1)
	if settings().pos then
		local p = settings().pos
		f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	elseif AuctionHouseFrame then
		f:ClearAllPoints(); f:SetPoint('TOPLEFT', AuctionHouseFrame, 'TOPRIGHT', 8, 0)
	end
end
local function setScale(v)
	settings().scale = math.max(0.7, math.min(1.6, math.floor(v * 20 + 0.5) / 20))
	if ui then ui.frame:SetScale(settings().scale) end
end

local ui_fillButton, trackFor, trackLine
local function build()
	local f = CreateFrame('Frame', PREFIX .. 'Frame', UIParent)
	f:SetSize(W, 600)
	f:SetPoint('CENTER')
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag('LeftButton')
	f:SetScript('OnDragStart', f.StartMoving)
	f:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		settings().pos = { p, rp, x, y }
	end)
	f:SetFrameStrata('HIGH')
	S.Box(f, C.bg, C.border)
	ui = { frame = f, rows = {} }
	local token = 0
	function ui.changed()
		token = token + 1
		local mine = token
		C_Timer.After(0.4, function() if mine == token and plan and not Scan.Busy() and ui.doPlan then ui.doPlan() end end)
	end

	local head = CreateFrame('Frame', nil, f)
	head:SetPoint('TOPLEFT', 1, -1); head:SetPoint('TOPRIGHT', -1, -1); head:SetHeight(30)
	S.Box(head, C.panel, { 0, 0, 0, 0 })
	local titleX = PAD - 1
	if not FAVOR_ONLY then
		local logo = head:CreateTexture(nil, 'ARTWORK')
		logo:SetSize(20, 20); logo:SetPoint('LEFT', 8, 0)
		logo:SetTexture('Interface\\AddOns\\' .. ADDON .. '\\logo.tga')
		ui.logo = logo
		titleX = 33
	end
	local title = S.Text(head, 14, C.gold); title:SetPoint('LEFT', titleX, 0); title:SetText(FAVOR_ONLY and "Merchant's Favor" or 'Writs and Favors')
	ui.title = title
	local close = S.Button(head, 'x', 24, 22, function() f:Hide() end); close:SetPoint('RIGHT', -4, 0)
	local bigger = S.Button(head, 'A+', 30, 22, function() setScale(settings().scale + 0.05) end); bigger:SetPoint('RIGHT', close, 'LEFT', -4, 0)
	local smaller = S.Button(head, 'A-', 30, 22, function() setScale(settings().scale - 0.05) end); smaller:SetPoint('RIGHT', bigger, 'LEFT', -4, 0)
	ui.routeBtn = S.Button(head, 'Route', 48, 22, function()
		if ui.mapWin and ui.mapWin:IsShown() then ui_hideRoute() else ui.showRoute() end
	end)
	ui.routeBtn:SetPoint('RIGHT', smaller, 'LEFT', -8, 0)
	function ui.switchMode(mode)
		mode = mode or ((mine().mode == 'favor') and 'writs' or 'favor')
		mine().mode = mode
		plan = nil
		ui.track = nil
		clearBuy()
		ui.summary:SetText('')
		refresh(mine().mode == 'favor' and "Merchant's Favor: Scan for live crate prices, then Plan" or 'Craftsman\'s Writs')
		if ui.doPlan then ui.doPlan() end
	end
	ui.modeBtn = S.Button(head, 'Favor', 48, 22, function() ui.switchMode() end)
	ui.modeBtn:SetPoint('RIGHT', ui.routeBtn, 'LEFT', -4, 0)
	ui.optsBtn = S.Button(head, '', 24, 22, function() ui.opts:SetShown(not ui.opts:IsShown()) end)
	do
		local cog = ui.optsBtn:CreateTexture(nil, 'ARTWORK')
		cog:SetSize(16, 16); cog:SetPoint('CENTER')
		cog:SetTexture('Interface\\Buttons\\UI-OptionsButton')
		ui.optsBtn.cog = cog
		ui.optsBtn:HookScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_TOP')
			GameTooltip:AddLine('Options')
			GameTooltip:AddLine('Buy for today or every day, thinly listed writs, your free bag slots, and what it found about your character.', 1, 1, 1, true)
			GameTooltip:Show()
		end)
		ui.optsBtn:HookScript('OnLeave', function() GameTooltip:Hide() end)
	end
	ui.optsBtn:SetPoint('RIGHT', ui.modeBtn, 'LEFT', -4, 0)
	f:SetScript('OnHide', function() if ui.mapWin and not (ui.omMode and WorldMapFrame and WorldMapFrame:IsShown()) then ui.mapWin:Hide() end end)

	ui.faction = S.Text(f, 13); ui.faction:SetPoint('TOPLEFT', PAD, -44)
	ui.standing = S.Text(f, 12, C.muted, 'RIGHT'); ui.standing:SetPoint('TOPRIGHT', -PAD, -45)
	ui.bar = S.Bar(f, IW, 6); ui.bar:SetPoint('TOPLEFT', PAD, -64)

	ui.goalHead = S.Heading(f, 'Goal', IW)
	ui.goalHead:SetPoint('TOPLEFT', PAD, -84)
	local goals = function()
		local o = {}
		if mine().mode == 'favor' then
			for i, n in ipairs(FAVOR_GOALS) do o[i] = { text = '+' .. n .. ' Favor', value = n } end
		else
			for i, g in ipairs(State.GOALS) do o[i] = { text = g[1], value = i } end
		end
		return o
	end
	ui.goal = dropdown(f, 112, goals, function() return mine().mode == 'favor' and settings().favorGoal or settings().goal end,
		function(v) if mine().mode == 'favor' then settings().favorGoal = v else settings().goal = v end end)
	ui.goal:SetPoint('TOPLEFT', PAD, -104)
	local dayOpts = function()
		local o = {}
		for d = 1, 7 do o[d] = { text = whenText(d), value = d } end
		o[8] = { text = 'in 14 days', value = 14 }
		return o
	end
	ui.days = dropdown(f, 112, dayOpts, function() return settings().days end, function(v) settings().days = v end)
	ui.days:SetPoint('TOPLEFT', PAD + 120, -104)
	ui.reach = S.Text(f, 12, C.muted); ui.reach:SetPoint('TOPLEFT', PAD, -82); ui.reach:SetText('Reach')
	local function tipOn(b, title, text)
		b:HookScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_TOP')
			GameTooltip:AddLine(title)
			GameTooltip:AddLine(text(), 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:HookScript('OnLeave', function() GameTooltip:Hide() end)
	end
	tipOn(ui.goal, 'What to reach', function()
		return mine().mode == 'favor' and "How much Merchant's Favor to buy crates for." or 'The standing with ' .. (D.factionName or 'Durotar Supply and Logistics') .. ' you want to reach.'
	end)
	tipOn(ui.days, 'By when', function()
		return 'When you want to be there. Today: every writ it takes is bought and handed in today. Tomorrow or later: spread over those days. A writ can be handed in once a day, so more days means fewer and cheaper writs each day.'
	end)

	ui.minute = S.Text(f, 12); ui.minute:SetPoint('TOPLEFT', PAD, -140)
	local s = S.Slider(f, IW)
	ui.slider = s
	s:SetPoint('TOPLEFT', PAD, -158)
	s:SetMinMaxValues(0, 100)
	s:SetValueStep(1)
	s:SetObeyStepOnDrag(true)
	s:SetValue(settings().speed or 50)
	s:SetScript('OnValueChanged', function(_, v)
		v = math.floor(v + 0.5)
		if v ~= settings().speed then settings().speed = v; settings().minute = minuteOf(v); refresh(); ui.changed() end
	end)
	local lo = S.Text(f, 12, C.text); lo:SetPoint('TOPLEFT', PAD, -178); lo:SetText('Cheaper')
	local hi = S.Text(f, 12, C.text, 'RIGHT'); hi:SetPoint('TOPRIGHT', -PAD, -178); hi:SetText('Quicker')
	ui.timeBits = { s, lo, hi }
	ui.slider = s
	s:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine('Cheaper or quicker')
		GameTooltip:AddLine('Left: the cheapest writs, wherever they are. Right: writs close together, so a shorter run, even if they cost a bit more.', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	s:SetScript('OnLeave', function() GameTooltip:Hide() end)

	local bw = math.floor((IW - 24) / 4)
	ui.scan = S.Button(f, 'Scan', bw, 28, function()
		if mine().mode == 'favor' then return ui.favorScan() end
		local quick = Scan.Quick(db) and not IsShiftKeyDown()
		ui.track = nil
		Scan.Start(db, function(d, t, what) refresh(('Scanning %d/%d%s'):format(d, t, what and (': ' .. what) or '...')) end,
			function(msg, failed)
				refresh(msg, failed)
				if failed then return end
				ui.doPlan()
				ui.writsStage2(1, { started = GetServerTime and GetServerTime() or time(), full = 0 })
			end, { quick = quick and mine().mode ~= 'favor', favor = mine().mode == 'favor' })
	end)
	ui.scan:SetPoint('TOPLEFT', PAD, -200)
	ui.plan = S.Button(f, 'Plan', bw, 28, function() ui.doPlan() end)
	ui.plan:SetPoint('TOPLEFT', PAD + bw + 8, -200)
	ui.held2 = S.Button(f, 'Route held', bw, 28, function() ui.routeHeld() end)
	ui.held2:SetPoint('TOPLEFT', PAD + (bw + 8) * 2, -200)
	ui.rxp = S.Button(f, 'To RestedXP', bw, 28, function() ui.sendToRXP() end)
	ui.rxp:SetPoint('TOPLEFT', PAD + (bw + 8) * 3, -200)
	ui.fill = ui_fillButton(f, bw)
	ui.fill:SetPoint('TOPLEFT', PAD + (bw + 8) * 2, -200)
	ui.auto = S.Button(f, 'Auto hand-in', bw, 28, function()
		settings().autoHandIn = not (settings().autoHandIn ~= false)
		refresh(settings().autoHandIn ~= false and 'Auto hand-in on: talk to ' .. NPC .. ' and the Sealed crates go in (Shift to skip)' or 'Auto hand-in off')
	end)
	ui.auto:SetPoint('TOPLEFT', PAD + (bw + 8) * 3, -200)
	ui.way = S.Button(f, 'Waypoint: ' .. NPC, bw, 28, function() ui.waypoint() end)

	ui.todayHead = S.Heading(f, 'Today', IW)
	ui.todayHead:SetPoint('TOPLEFT', PAD, -242)
	local alert = CreateFrame('Frame', nil, f)
	alert:SetPoint('TOPLEFT', ui.todayHead, 'BOTTOMLEFT', 0, -10); alert:SetSize(IW, 36)
	S.Box(alert, { 0.25, 0.19, 0.06, 0.55 }, { C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6, 1 })
	alert.icon = alert:CreateTexture(nil, 'ARTWORK'); alert.icon:SetSize(22, 22); alert.icon:SetPoint('LEFT', 7, 0); alert.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	alert.text = S.Text(alert, 12, C.gold); alert.text:SetPoint('LEFT', 36, 0); alert.text:SetWidth(IW - 42)
	alert:EnableMouse(true)
	alert:SetScript('OnEnter', function(self)
		if not self.item then return end
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT'); GameTooltip:SetItemByID(self.item); GameTooltip:Show()
	end)
	alert:SetScript('OnLeave', function() GameTooltip:Hide() end)
	alert:Hide()
	ui.alert = alert
	ui.summary = S.Text(f, 12); ui.summary:SetPoint('TOPLEFT', PAD, -262); ui.summary:SetWidth(IW); ui.summary:SetSpacing(3)
	local tipHit = CreateFrame('Frame', nil, f)
	tipHit:SetPoint('TOPLEFT', ui.summary, 'TOPLEFT'); tipHit:SetPoint('BOTTOMRIGHT', ui.summary, 'BOTTOMRIGHT')
	tipHit:EnableMouse(true)
	tipHit:SetScript('OnEnter', function(self)
		if not ui.summaryTip then return end
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		for i, l in ipairs(ui.summaryTip) do
			if type(l) == 'table' then GameTooltip:AddDoubleLine(l[1], l[2], 0.9, 0.9, 0.9, 1, 0.78, 0.25) else GameTooltip:AddLine(l, i == 1 and 1 or 0.9, i == 1 and 0.78 or 0.9, i == 1 and 0.25 or 0.9, true) end
		end
		GameTooltip:Show()
	end)
	tipHit:SetScript('OnLeave', function() GameTooltip:Hide() end)
	local held = CreateFrame('Frame', nil, f)
	ui.trackText = S.Text(f, 12); ui.trackText:SetPoint('TOPLEFT', ui.summary, 'BOTTOMLEFT', 0, -6); ui.trackText:SetWidth(IW); ui.trackText:SetSpacing(3)
	held:SetPoint('TOPLEFT', ui.trackText, 'BOTTOMLEFT', 0, -6); held:SetSize(IW, 16)
	held.text = S.Text(held, 11, C.muted); held.text:SetPoint('LEFT'); held.text:SetPoint('RIGHT'); held.text:SetWordWrap(false)
	held:EnableMouse(true)
	held:SetScript('OnEnter', function(self)
		if not self.lines then return end
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		GameTooltip:AddLine('Held writs and items')
		for _, l in ipairs(self.lines) do GameTooltip:AddDoubleLine(l[1], l[2], 0.9, 0.9, 0.9, 0.6, 0.6, 0.6) end
		GameTooltip:Show()
	end)
	held:SetScript('OnLeave', function() GameTooltip:Hide() end)
	ui.held = held

	local listHead = S.Heading(f, 'Buy list', IW)
	listHead:SetPoint('TOPLEFT', held, 'BOTTOMLEFT', 0, -12)
	ui.listHead = listHead
	local function scope(v)
		mine().scope = v
		if v == 'all' then setStatus("Buying for every day: today's prices for all of them; later days' could be lower or higher") end
		if plan and ui.doPlan then ui.doPlan() else refresh() end
	end
	ui.scopeBtn = S.Button(f, 'For today', 104, 20, function() scope((mine().scope or 'day') == 'day' and 'all' or 'day') end)
	ui.scopeBtn:SetPoint('RIGHT', f, 'RIGHT', -PAD, 0); ui.scopeBtn:SetPoint('BOTTOM', listHead, 'BOTTOM', 0, -6)
	local box = CreateFrame('Frame', nil, f)
	box:SetPoint('TOPLEFT', listHead, 'BOTTOMLEFT', 0, -8)
	box:SetPoint('BOTTOMRIGHT', -PAD, 96)
	ui.box = box
	S.Box(box, { 0.05, 0.05, 0.055, 0.9 }, C.border)
	local sf = CreateFrame('ScrollFrame', nil, box)
	sf:SetPoint('TOPLEFT', 4, -4); sf:SetPoint('BOTTOMRIGHT', -4, 4)
	local child = CreateFrame('Frame', nil, sf)
	child:SetSize(IW - 10, 400)
	sf:SetScrollChild(child)
	sf:EnableMouseWheel(true)
	sf:SetScript('OnMouseWheel', function(self, d)
		local max = math.max(0, child:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * ROW * 2)))
	end)
	ui.list, ui.listFrame = child, sf
	ui.empty = S.Text(child, 12, C.muted); ui.empty:SetPoint('TOPLEFT', 6, -6); ui.empty:SetWidth(IW - 24)

	ui.buy = S.Button(f, 'Buy', IW - 136, 32, function() guardBuy(function() Buy.Click(IsShiftKeyDown()) end) end, true)
	ui.buy:SetPoint('BOTTOMLEFT', PAD, 54)
	ui.anyway = S.Button(f, 'Anyway', 64, 32, function() Buy.Click(true) end)
	ui.anyway:SetPoint('BOTTOMLEFT', PAD + IW - 130, 54)
	ui.skip = S.Button(f, 'Skip', 58, 32, function() Buy.Skip() end)
	ui.skip:SetPoint('BOTTOMRIGHT', -PAD, 54)
	ui.status = S.Text(f, 12); ui.status:SetPoint('BOTTOMLEFT', PAD, 12); ui.status:SetWidth(IW); ui.status:SetWordWrap(true)

	local op = CreateFrame('Frame', nil, f)
	op:SetFrameStrata('DIALOG')
	op:SetSize(260, 156)
	op:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -4, -34)
	S.Box(op, C.panel, C.gold)
	local function row(text, y) local t = S.Text(op, 11, C.muted); t:SetPoint('TOPLEFT', 10, y); t:SetText(text); return t end
	row('Free bag slots', -10)
	ui.bagsText = S.Text(op, 12, C.text); ui.bagsText:SetPoint('TOPLEFT', 10, -30); ui.bagsText:SetWidth(112)
	local bagTip = CreateFrame('Frame', nil, op)
	bagTip:SetPoint('TOPLEFT', 6, -6); bagTip:SetSize(118, 44); bagTip:EnableMouse(true)
	bagTip:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		GameTooltip:AddLine('Free bag slots')
		GameTooltip:AddLine('Counted from your bags. The route stops at a mailbox for as many writs and items as fit, hands them in, and stops at the next mailbox for more. More free slots: fewer mailbox stops.', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	bagTip:SetScript('OnLeave', function() GameTooltip:Hide() end)
	row('Buy for', -10):SetPoint('TOPLEFT', 130, -10)
	ui.scopeBtn:SetParent(op); ui.scopeBtn:ClearAllPoints(); ui.scopeBtn:SetPoint('TOPLEFT', 130, -26); ui.scopeBtn:SetSize(110, 24)
	row('Thinly listed writs', -60)
	local stockOpts = function() local o = {}; for _, n in ipairs({ 0, 3, 5, 10 }) do o[#o + 1] = { text = n == 0 and 'Plan them all' or ('Skip under ' .. n .. ' listed'), value = n } end; return o end
	ui.stock = dropdown(op, 110, stockOpts, function() return settings().stock end, function(v) settings().stock = v end)
	ui.stock:SetParent(op); ui.stock:ClearAllPoints(); ui.stock:SetPoint('TOPLEFT', 10, -76); ui.stock:SetWidth(150)
	ui.stock:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:AddLine('Thinly listed writs')
		GameTooltip:AddLine('Leave out a writ when fewer than this many of it, or of the item it wants, are on the Auction House: a few listings are often bait or gone by the time you buy. Writs you already hold are always planned.', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	ui.stock:HookScript('OnLeave', function() GameTooltip:Hide() end)
	ui.found = S.Text(op, 11, C.text); ui.found:SetPoint('TOPLEFT', 10, -110); ui.found:SetWidth(230)
	op:Hide()
	ui.opts = op
	if ui.status.SetMaxLines then ui.status:SetMaxLines(2) end

	f:Hide()
end

local LIST_MIN, LIST_MAX = 3, 12
local function layout(favor)
	if InCombatLockdown() then return end
	local f = ui.frame
	local function put(o, ...) o:ClearAllPoints(); o:SetPoint(...) end
	local half = math.floor((IW - 8) / 2)
	local third = math.floor((IW - 16) / 3)
	if ui.laidOut ~= favor then
		ui.laidOut = favor
		if favor then
			ui.goal:SetWidth(112); put(ui.goal, 'TOPLEFT', PAD, -72)
			ui.reach:Hide()
			ui.scan:SetSize(IW - 112 - 8, 24); put(ui.scan, 'TOPLEFT', ui.goal, 'TOPRIGHT', 8, 0)
			put(ui.todayHead, 'TOPLEFT', PAD, -110)
			put(ui.listHead, 'TOPLEFT', ui.trackText, 'BOTTOMLEFT', 0, -12)
		else
			ui.reach:Show()
			ui.goal:SetWidth(92); put(ui.goal, 'TOPLEFT', PAD + 44, -76)
			ui.days:SetWidth(92); put(ui.days, 'TOPLEFT', ui.goal, 'TOPRIGHT', 6, 0)
			ui.scan:SetSize(IW - 44 - 92 - 92 - 12, 24); put(ui.scan, 'TOPLEFT', ui.days, 'TOPRIGHT', 6, 0)
			put(ui.timeBits[2], 'TOPLEFT', PAD, -110)
			put(ui.timeBits[3], 'TOPRIGHT', -PAD, -110)
			ui.slider:SetWidth(IW - 130); put(ui.slider, 'TOP', ui.frame, 'TOP', 0, -108)
			put(ui.todayHead, 'TOPLEFT', PAD, -136)
			put(ui.listHead, 'TOPLEFT', ui.held, 'BOTTOMLEFT', 0, -12)
		end
		put(ui.box, 'TOPLEFT', ui.listHead, 'BOTTOMLEFT', 0, -8); ui.box:SetWidth(IW)
		put(ui.buy, 'TOPLEFT', ui.box, 'BOTTOMLEFT', 0, -10)
		put(ui.skip, 'TOPRIGHT', ui.box, 'BOTTOMRIGHT', 0, -10)
		put(ui.anyway, 'TOPRIGHT', ui.skip, 'TOPLEFT', -6, 0)
		ui.fill:SetSize(third, 28)
		ui.auto:SetSize(third, 28); put(ui.auto, 'TOPLEFT', ui.buy, 'BOTTOMLEFT', third + 8, -8)
		ui.way:SetSize(third, 28); put(ui.way, 'TOPLEFT', ui.auto, 'TOPRIGHT', 8, 0)
		put(ui.status, 'TOPLEFT', ui.buy, 'BOTTOMLEFT', 0, favor and -(8 + 28 + 10) or -10)
	end
	local list = Buy.List()
	local n = math.max(LIST_MIN, math.min(LIST_MAX, list and #list or 0))
	ui.box:SetHeight(n * ROW + 8)
	local tries = 0
	local function settle()
		tries = tries + 1
		local top, bottom, buyBottom = f:GetTop(), ui.status:GetBottom(), ui.buy:GetBottom()
		if InCombatLockdown() or not (top and bottom and buyBottom) then
			if tries < 50 then C_Timer.After(0.2, settle) end
			return
		end
		ui.fill:ClearAllPoints()
		ui.fill:SetPoint('TOPLEFT', f, 'TOPLEFT', PAD, -math.floor(top - buyBottom + 8))
		local h = math.floor(top - bottom + 12)
		f:SetHeight(h)
		if ui.mapWin then ui.mapWin:SetHeight(h) end
	end
	C_Timer.After(0, settle)
end

local refreshBody
function refresh(msg, err)
	if ns.OnRefresh then ns.OnRefresh() end
	if not ui then return end
	local ok, e = pcall(refreshBody, msg, err)
	if not ok then
		ns.Log('display error: ' .. tostring(e))
		pcall(ui.status.SetText, ui.status, RED .. 'Display error (/writs debug): ' .. tostring(e) .. '|r')
	end
end
function refreshBody(msg, err)
	if msg then setStatus(msg, err) end
	local lb = State.Label()
	local a = ui.alert
	if lb.done or mine().mode == 'favor' then a:Hide()
	else
		a.item = lb.item
		a.icon:SetTexture(GetIcon and GetIcon(lb.item) or 134400)
		a.text:SetText(lb.held and 'Shipping Label in your bags: use it, then hand it in to ' .. NPC_AT .. '. +2,000 rep, counted in the plan'
			or lb.onQuest and 'Shipping Label quest: hand it in to ' .. NPC_AT .. '. +2,000 rep, counted in the plan'
			or 'Shipping Label not done: +2,000 rep, once, counted in the plan. It comes with your first writs; ' .. NPC_AT .. ' takes it')
		a:Show()
	end
	ui.summary:ClearAllPoints()
	if a:IsShown() then ui.summary:SetPoint('TOPLEFT', a, 'BOTTOMLEFT', 0, -8) else ui.summary:SetPoint('TOPLEFT', ui.todayHead, 'BOTTOMLEFT', 0, -10) end
	local sc = mine().scope or 'day'
	ui.scopeBtn:SetText(sc == 'all' and 'For every day' or 'For today')
	ui.listHead:SetText(oneOff and ('BUY LIST  ' .. WHITE .. 'from the table: ' .. (oneOff.title or '') .. '|r') or ui.buyHead or 'BUY LIST')
	ui.routeBtn.label:SetTextColor(unpack((ui.mapWin and ui.mapWin:IsShown()) and C.gold or C.text))
	if routeShown() then ui.drawRoute() end
	ui.drawHeld()
	local raw, standing, name = State.Rep()
	local goal = State.GOALS[settings().goal]
	local favor = mine().mode == 'favor'
	ui.title:SetText(FAVOR_ONLY and "Merchant's Favor" or 'Writs and Favors')
	ui.todayHead:SetText(favor and 'THIS PURCHASE' or 'THIS PLAN')
	ui.trackText:SetText(ui.trackLine())
	ui.optsBtn:SetShown(not favor)
	if favor then ui.opts:Hide() end
	if ui.stock then ui.stock.update() end
	do
		local _, cls = UnitClass('player')
		local hs = State.Hearth()
		ui.found:SetText(('Hearthstone: %s\nTeleports: %s'):format(hs and D.nodes[hs] and D.nodes[hs][1] or 'not a known inn', cls == 'MAGE' and ('mage (' .. MAGE_NAMES .. ')') or cls == 'DRUID' and 'druid (Moonglade)' or 'none'))
	end
	if not favor then ui.summaryTip = nil end
	ui.modeBtn:SetText(favor and 'Writs' or 'Favor')
	ui.held2:Hide(); ui.rxp:Hide(); ui.routeBtn:SetShown(not favor)
	ui.plan:Hide()
	ui.modeBtn:SetShown(not FAVOR_ONLY)
	ui.goalHead:Hide()
	ui.held:SetShown(not favor)
	ui.minute:Hide()
	ui.layout(favor)
	ui.auto:SetShown(favor)
	ui.way:SetShown(favor)
	ui.auto:SetText(settings().autoHandIn ~= false and 'Auto hand-in: on' or 'Auto hand-in: off')
	ui.auto.label:SetTextColor(unpack(settings().autoHandIn ~= false and C.gold or C.muted))
	if not InCombatLockdown() then ui.fill:SetShown(favor) end
	ui.fill.update()
	if favor and ui.mapWin then ui.mapWin:Hide() end
	if favor then
		local have = State.Favor(db)
		ui.faction:SetText("Merchant's Favor" .. (have and ('  ' .. WHITE .. commas(have) .. '|r') or ''))
		local got = plan and plan.favor and plan.favor.got
		ui.standing:SetText(have and got and ('after this purchase ' .. WHITE .. commas(have + got) .. '|r') or (have and '' or MUTED .. '(not found yet)|r'))
		ui.bar:Hide()
	else
		ui.faction:SetText(name)
		ui.standing:SetText(('%s  ' .. WHITE .. '%s|r / %s'):format(standing, commas(raw), commas(goal[2])))
		ui.bar:Show()
		ui.bar:SetMinMaxValues(0, goal[2])
		ui.bar:SetValue(math.min(raw, goal[2]))
	end
	ui.goal.update(); ui.days.update()
	do
		local free = State.FreeSlots()
		ui.bagsText:SetText(free and (free .. (free < 12 and (RED .. '  (make room)|r') or '')) or (MUTED .. 'not known|r'))
	end
	ui.days:SetShown(not favor)
	for _, x in ipairs(ui.timeBits) do x:SetShown(not favor) end
	local now_ = GetServerTime and GetServerTime() or time()
	local age = favor and (db.favorAt and (('live prices %d min old'):format(math.floor((now_ - db.favorAt) / 60))) or 'no crate scan yet')
		or (db.scanAt and (('prices %d min old'):format(math.floor((now_ - db.scanAt) / 60))) or 'no scan yet')
	ui.status:SetText((status and ((statusErr and RED or GOLD) .. status .. '|r   ') or '') .. MUTED .. age .. '|r')
	ui.scan:SetText(favor and 'Scan crates' or (Scan.Quick(db) and 'Scan again' or 'Scan'))
	local list, cur = Buy.List()
	local n = list and #list or 0
	local p0 = Buy.Pending()
	for i = 1, n do
		local e = list[i]
		local r = ui.rows[i] or rowFrame(ui.list, i)
		ui.rows[i] = r
		r.id = e.id
		r.icon:SetTexture(GetIcon and GetIcon(e.writ and e.item or e.id) or 134400)
		if e.writ then r.badge:SetTexture(GetIcon and GetIcon(e.id) or 134400); r.badge:Show() else r.badge:Hide() end
		r.tip = e.plan and ('Planned at ' .. Plan.Money(e.plan) .. ' each' .. (e.live and math.abs(e.live - e.plan) > e.plan * 0.05 and (', now ' .. Plan.Money(e.live)) or '')) or nil
		local done = e.bought >= e.need
		local nm = e.writ and e.name:gsub("^Craftsman's Writ: ", 'Writ: ') or (e.as or e.name)
		r.name:SetText((e.writ and WHITE or qualityHex(e.id)) .. (e.need > 1 and (e.need .. ' x ') or '') .. nm .. '|r')
		r.rep:SetText(e.repText or (e.rep and (e.rep .. ' rep') or ''))
		local moved = e.live and e.plan and math.abs(e.live - e.plan) > e.plan * 0.05
		local stack = false
		if done then r.cost:SetText(GREEN .. (e.bought > e.need and ('bought ' .. e.bought) or 'bought') .. '|r')
		elseif stack then r.cost:SetText(GOLD .. 'x' .. p0.qty .. '|r ' .. Plan.Money(p0.total))
		else r.cost:SetText(moved and ((e.live > e.plan and RED or GREEN) .. Plan.Money(e.live * e.need) .. '|r') or (e.plan and Plan.Money(e.plan * e.need) or '?')) end
		r.bg:SetShown(i == cur and not done)
		r:Show()
	end
	for i = n + 1, #ui.rows do ui.rows[i]:Hide() end
	ui.list:SetHeight(math.max(1, n * ROW))
	if ui.layout then ui.layout(mine().mode == 'favor') end
	ui.empty:SetShown(n == 0)
	ui.empty:SetText(plan and plan.reason or (mine().mode == 'favor' and 'Click Scan crates: your buy list shows here.' or 'Scan the Auction House, then Plan. Your buy list shows here.'))
	local p = Buy.Pending()
	if p and Buy.Step() == 'ready' then
		ui.buy:SetText(Buy.Label())
		ui.buy:Enable()
		ui.anyway:SetShown(p.over and true or false)
	else
		ui.buy:SetText(p and Buy.Label() or (list and cur > n and n > 0 and 'All bought' or 'Buy'))
		ui.buy:Disable()
		ui.anyway:Hide()
	end
end

local function noPlan(why, msg, rows)
	plan = { reason = why, rows = rows, mine = mine().planMode == 'picks' or nil }
	clearBuy()
	ui.summary:SetText('')
	refresh(msg or why, true)
end

local function planNow()
	local raw = State.Rep()
	local goal = State.GOALS[settings().goal]
	local label = State.Label()
	local labelRep = label.done and 0 or label.rep
	local need = goal[2] - raw - labelRep
	if goal[2] - raw <= 0 then return noPlan(('You are already %s (%s). Pick a higher goal.'):format(goal[1], commas(raw)), 'Already at the goal') end
	if need <= 0 then return noPlan(('The Shipping Label alone gets you to %s: hand it in to ' .. NPC_AT .. ' (+2,000).'):format(goal[1]), 'Shipping Label is enough') end
	local s = settings()
	local p, fb = prices()
	local state = State.Read(db)
	local start = State.Start()
	local rows = Plan.Rows(p, state, s.stock)
	local priced, held, anyPrice, doneToday = 0, 0, false, 0
	for _, r in ipairs(rows) do
		if r.cost then priced = priced + 1 end
		if r.ready then held = held + 1 end
		if r.writCost then anyPrice = true end
		if r.done then doneToday = doneToday + 1 end
	end
	if not anyPrice then return noPlan('No prices yet: open the Auction House and click Scan.', 'No prices yet') end
	local set = picksOf()
	local picked = 0
	for _, r in ipairs(rows) do
		if set[r.writ] then
			r.picked = true
			if not r.done then picked = picked + 1 end
			if not r.cost and r.writCost and r.itemCost then r.cost = r.writCost + r.itemCost - r.pouch end
		end
	end
	local mineMode = mine().planMode == 'picks'
	if mineMode then
		plan = Plan.Picked({ rows = rows, picks = set, need = need })
		plan.rows = rows
		if #plan.picks == 0 then
			plan.route, plan.shopping = nil, {}
			clearBuy()
			ui.buyHead = 'BUY LIST  ' .. WHITE .. 'my picks: none yet|r'
			ui.summary:SetText(WHITE .. 'My picks: none yet|r\n' .. MUTED .. 'Open Route: every writ is on the map. Click one to pick it; the shopping list and the route follow.|r')
			return refresh(picked > 0 and 'My picks: none of them can be done today' or 'My picks: pick writs on the map (Route)')
		end
	else
		plan = Plan.Goal({ rows = rows, need = need, days = s.days, perSec = s.minute / 60, start = start, force = set })
		plan.rows = rows
	end
	ns.Log(('plan: need %d, %d priced, %d plannable, %d handed in today (%d by the game, %d seen by us), %d picks, today max %d'):format(need, priced, plan.usable, doneToday, state.doneBy.flag, state.doneBy.ours, #plan.picks, plan.today))
	if plan.usable == 0 then
		return noPlan(('No writ can be planned: %d priced with %d+ up (writ and item), none with a known hand-in. Try Scan again.'):format(priced, s.stock), 'Nothing to plan', rows)
	end
	local day = plan.days[1]
	if not day or #day.writs == 0 then
		if plan.today == 0 then return noPlan(('Nothing to plan today: all %d writs you could do are handed in today. Plan again after the daily reset.'):format(plan.doneToday), 'Nothing to plan today', rows) end
		return noPlan(('Nothing planned for today (%d writs could be). /writs debug says more.'):format(plan.usable), 'Nothing to plan today', rows)
	end
	local _, class = UnitClass('player')
	plan.route = Plan.Route({ writs = day.writs, start = start, bags = bagCap(), hearth = State.Hearth(), druid = class == 'DRUID', mage = class == 'MAGE', label = not label.done and label or nil })
	local scope = mineMode and 'day' or (mine().scope or 'day')
	plan.shopping = Plan.Shopping(scope == 'all' and plan.days or { day }, p, state.held, state.items)
	do
		local pos, k = {}, 0
		for _, l in ipairs(plan.route.legs) do
			if not l.mail then for _, w in ipairs(l.writs) do k = k + 1; pos[w.writ] = pos[w.writ] or k end end
		end
		local writOf = {}
		for _, w in ipairs(D.writs) do writOf[w[3]] = w[1] end
		local function key(e) return pos[e.writ and e.id or writOf[e.id]] or math.huge end
		for i, e in ipairs(plan.shopping) do e.order = i end
		table.sort(plan.shopping, function(a, b)
			local ka, kb = key(a), key(b)
			if ka ~= kb then return ka > kb end
			if (a.writ and true or false) ~= (b.writ and true or false) then return a.writ and true or false end
			return a.order < b.order
		end)
	end
	plan.state = state
	local spend, lines = 0, 0
	for _, e in ipairs(plan.shopping) do spend = spend + (e.cost or 0); lines = lines + 1 end
	ui.buyHead = ('BUY LIST  %s%s: %d to buy, %s|r'):format(WHITE, mineMode and 'my picks' or scope == 'all' and ('every day (' .. #plan.days .. ')') or 'today', lines, Plan.Money(spend))
	local short = plan.got < need
	local span = whenText(s.days)
	local goalLine
	if mineMode then
		goalLine = (short and GOLD or GREEN) .. ('My picks give +%s of the %s %s needs%s.|r'):format(commas(plan.got), commas(need), goal[1],
			#plan.skipped > 0 and (' (' .. #plan.skipped .. ' picked can\'t be done today)') or '')
	elseif short then
		goalLine = RED .. ('%s needs %s more%s. %s gives %s at most (each writ once a day): about %s days.|r')
			:format(goal[1], commas(need), labelRep > 0 and ' after the Shipping Label' or '', s.days == 1 and 'Today' or s.days == 2 and 'Today and tomorrow' or (s.days .. ' days'), commas(plan.got), tostring(plan.daysNeeded or '?'))
	else
		local buys = 0
		for _, pk in ipairs(plan.picks) do buys = buys + pk.days end
		goalLine = GREEN .. ('%s %s: %s more%s, %d hand-ins (%d different writs), %s.|r'):format(goal[1], span, commas(need), labelRep > 0 and ' after the Shipping Label' or '', buys, #plan.picks, Plan.Money(plan.gold))
	end
	local notes = {}
	notes[#notes + 1] = ('from %s, %s in flights, pouches counted'):format(D.nodes[start][1], Plan.Money(plan.route.fares))
	if doneToday > 0 then notes[#notes + 1] = doneToday .. ' handed in today (left out)' end
	if held > 0 then notes[#notes + 1] = held .. ' writs held' end
	if picked > 0 and not mineMode then notes[#notes + 1] = picked .. ' picked by hand' end
	if fb > 0 then notes[#notes + 1] = fb .. ' prices from Auctionator/TSM' end
	if labelRep > 0 then notes[#notes + 1] = 'Shipping Label +2,000 counted, ' .. NPC .. ' on the route' end
	do
		local free = State.FreeSlots()
		if free and free < 12 then notes[#notes + 1] = RED .. 'only ' .. free .. ' free bag slots: more mailbox stops (make room, then Scan again)|r' .. MUTED end
	end
	if #plan.shopping > 50 then notes[#notes + 1] = RED .. 'More than 50 purchases: the mailbox shows 50 at a time. Take out the first batch, and the rest arrive as you make space|r' .. MUTED end
	ui.summary:SetText(('%s%s: %d writs   %s rep   %s   %d min|r\n%s%s.|r\n%s')
		:format(WHITE, mineMode and 'My picks' or s.days == 1 and 'Today' or ('Day 1 of ' .. s.days), #day.writs, commas(day.rep), Plan.Money(day.gold), math.floor(plan.route.total / 60 + 0.5),
			MUTED, table.concat(notes, '. '), goalLine))
	startBuy(plan.shopping, refresh, {
		done = 'All bought. Take them out of the mail, then Route (title bar): the hand-in route, and To RestedXP there.',
		onBought = function(e, qty, paid)
			local t = ui.trackFor()
			t.spent, t.planned = t.spent + paid, t.planned + (e.plan or 0) * qty
			State.Bought(db, e.id, qty)
		end,
	})
	local t = ui.trackFor()
	t.planWrits, t.planRep = #day.writs, day.rep
	refresh(('Planned: %d writs, %d purchases'):format(#day.writs, #plan.shopping))
end

local function doPlan()
	local ok, err = pcall(planNow)
	if not ok then refresh('Plan failed: ' .. tostring(err), true) end
end

local function sendToRXP(route)
	route = route or (plan and plan.route)
	if not route then return refresh('Plan first', true) end
	local name = 'Writs ' .. date('%d %b %H:%M')
	local ok0, text = pcall(Guide.Text, route, name)
	if not ok0 then return refresh('Guide failed: ' .. tostring(text), true) end
	db.guide = { name = name, text = text, day = State.WritDay() }
	local ok, msg = ns.SendToRXP(name, text, true)
	if ok then refresh(msg or ('Sent to RestedXP: ' .. name)) else refresh('RestedXP: ' .. (msg or 'failed'), true) end
end

local function ladderOf(p)
	return function(id)
		local x = p[id]
		if not x then return nil end
		if x.ladder and #x.ladder > 0 then return x.ladder end
		if x.each then return { { x.each, x.up or 0 } } end
	end
end
local function favorNow(noBuy)
	local s = settings()
	local W = D.waylaid
	local need = s.favorGoal or 100
	local p = {}
	for id, v in pairs(db.prices or {}) do p[id] = v end
	local st = State.Read(db)
	local fp = Plan.Favor({ need = need, ladder = ladderOf(p), held = st.items })
	if #fp.crates == 0 and fp.sealed == 0 then
		return noPlan('No Waylaid Crates priced yet: open the Auction House and click Scan crates (live prices for every crate and bundle).', 'No crate prices yet')
	end
	plan = { favor = fp, need = need }
	local per = {}
	for _, c in ipairs(fp.crates) do per[c.id] = c end
	local shopping, spend, slots = {}, 0, 0
	for _, b in ipairs(fp.buy) do
		local c = per[b.item]
		local units = b.units
		shopping[#shopping + 1] = { id = b.item, name = W.names[b.item] or ('Item ' .. b.item), need = units, each = math.floor(b.cost / math.max(1, units) + 0.5),
			repText = c and (Plan.Money(c.perFavor) .. '/F') or nil }
		spend = spend + b.cost
		slots = slots + math.ceil(units / math.max(1, W.stack[b.item] or 1))
	end
	plan.shopping = shopping
	local hand = {}
	for _, c in ipairs(fp.crates) do hand[#hand + 1] = { kind = c.kind, tier = c.tier, count = c.count } end
	for kind, tiers in pairs(W.sealed) do for tier, id in pairs(tiers) do if fp.sealedCount[id] then hand[#hand + 1] = { kind = kind, tier = tier, count = fp.sealedCount[id] } end end end
	plan.hand = hand
	local lines = {}
	for i, c in ipairs(fp.crates) do
		if i <= 3 then lines[#lines + 1] = ('%s %s x%d at %s a Favor'):format((c.tier:gsub('^%l', string.upper)), c.type, c.count, Plan.Money(c.perFavor)) end
	end
	local crates = 0
	for _, c in ipairs(fp.crates) do crates = crates + c.count end
	local age = db.favorAt and math.floor(((GetServerTime and GetServerTime() or time()) - db.favorAt) / 60)
	ui.summary:SetText(('%s%d crates for +%s Merchant\'s Favor|r\nCost to buy: %s%s|r\nBack from hand-ins: %s%s|r\n%s%s|r%s')
		:format(WHITE, crates, commas(fp.got), GOLD, Plan.Money(spend), GREEN, Plan.Money(fp.back),
			MUTED, age and ('Prices: ' .. age .. ' min old') or 'Prices: no crate scan yet (Scan crates)',
			fp.short and ('\n' .. RED .. ('Only %s Favor of crates up now (of %s).'):format(commas(fp.got), commas(need)) .. '|r') or ''))
	local tip = { 'This purchase' }
	for _, c in ipairs(fp.crates) do tip[#tip + 1] = { ('%d x %s %s'):format(c.count, (c.tier:gsub('^%l', string.upper)), c.type), Plan.Money(c.perFavor) .. ' a Favor' } end
	if fp.sealed > 0 then tip[#tip + 1] = { 'Sealed crates held', '+' .. fp.sealed .. ' Favor' } end
	tip[#tip + 1] = { 'Net cost', Plan.Money(fp.cost) .. ' (' .. Plan.Money(fp.got > 0 and fp.cost / fp.got or 0) .. ' a Favor)' }
	ui.summaryTip = tip
	ui.buyHead = ('BUY LIST  %scrates and bundles: %d to buy, %s|r'):format(WHITE, #shopping, Plan.Money(spend))
	if noBuy then clearBuy()
	else
		startBuy(shopping, refresh, {
			done = ('All bought. Take them out of the mail, fill your crates (Fill), then hand them in to ' .. NPC_AT .. '%s.')
				:format(settings().autoHandIn ~= false and ' (auto hand-in is on)' or ''),
			onBought = function(e, qty, paid)
				local t = ui.trackFor()
				t.spent, t.planned = t.spent + paid, t.planned + (e.plan or 0) * qty
				State.Bought(db, e.id, qty)
			end,
		})
	end
	local t = ui.trackFor()
	if t.spent == 0 and t.handed == 0 then
		t.crates, t.expectBack = 0, 0
		for _, c in ipairs(fp.crates) do t.crates = t.crates + c.count end
		t.expectBack = fp.back
	end
	refresh(('Planned: %d crates for %s Favor, %d purchases'):format(crates, commas(fp.got), #shopping))
end
local FRESH = 15 * 60
local favorScan
local function favorStage2(round, counts)
	local ok, err = pcall(favorNow, true)
	if not ok then return refresh('Plan failed: ' .. tostring(err), true) end
	local fp = plan and plan.favor
	local now_ = GetServerTime and GetServerTime() or time()
	local ids = {}
	if fp then
		for _, b in ipairs(fp.buy) do
			local pr = db.prices[b.item]
			if not (pr and pr.full and pr.at and pr.at >= (counts.started or now_)) then ids[#ids + 1] = b.item end
		end
	end
	if #ids == 0 or round > 2 then
		pcall(favorNow)
		return refresh(('Live crate prices: %d browses and %d full searches. %s'):format(counts.browse, counts.full, plan and plan.favor and ('Plan: +' .. commas(plan.favor.got) .. ' Favor for ' .. Plan.Money(plan.favor.cost)) or ''))
	end
	Scan.Start(db, function(d, t, what) refresh(('Pricing the crates picked %d/%d%s'):format(d, t, what and (': ' .. what) or '...')) end,
		function(msg, failed)
			if failed then return refresh(msg, true) end
			counts.full = counts.full + #ids
			favorStage2(round + 1, counts)
		end, { favor = true, full = ids })
end
function favorScan(all)
	local now_ = GetServerTime and GetServerTime() or time()
	local counts = { browse = 0, full = 0 }
	counts.started = now_
	ui.track = nil
	Scan.Start(db, function(d, t, what) refresh(('Scanning crates %d/%d%s'):format(d, t, what and (': ' .. what) or '...')) end,
		function(msg, failed)
			if failed then return refresh(msg, true) end
			counts.browse = Scan.Count()
			favorStage2(1, counts)
		end, { favor = true })
end

local function waypoint()
	local h = D.waylaid.handIn
	if not h then return end
	local x, y = h.x / 100, h.y / 100
	if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(h.map) then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(h.map, x, y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
		return refresh(('Waypoint set: %s, %s %.1f, %.1f'):format(h.npc, h.zone, h.x, h.y))
	end
	if TomTom and TomTom.AddWaypoint then
		TomTom:AddWaypoint(h.map, x, y, { title = h.npc, persistent = false })
		return refresh(('TomTom waypoint: %s, %s %.1f, %.1f'):format(h.npc, h.zone, h.x, h.y))
	end
	DEFAULT_CHAT_FRAME:AddMessage(('%s: %s %.1f, %.1f'):format(h.npc, h.zone, h.x, h.y))
	refresh(('%s is at %s %.1f, %.1f (no waypoint addon)'):format(h.npc, h.zone, h.x, h.y))
end

local function writsStage2(round, counts)
	if mine().mode == 'favor' or not (plan and plan.shopping) then return end
	local avg = Scan.Avg()
	if avg and avg > 0.6 then return refresh(('Prices from the quick scan (the AH answers in %.1f s; not checking every listing)'):format(avg)) end
	local ids = {}
	for _, e in ipairs(plan.shopping) do
		local pr = db.prices[e.id]
		if not (pr and pr.full and pr.at and pr.at >= counts.started) then ids[#ids + 1] = e.id end
	end
	if #ids == 0 or round > 2 then
		return refresh(('Live prices: every listing of the %d things to buy checked (%d searches)'):format(#plan.shopping, counts.full))
	end
	Scan.Start(db, function(d, t, what) refresh(('Checking the listings %d/%d%s'):format(d, t, what and (': ' .. what) or '...')) end,
		function(msg, failed)
			if failed then return refresh(msg, true) end
			counts.full = counts.full + #ids
			ui.doPlan()
			writsStage2(round + 1, counts)
		end, { full = ids })
end
local replanToken = 0
local function replanSoon()
	replanToken = replanToken + 1
	local t = replanToken
	C_Timer.After(1, function()
		local st = Buy.Step()
		if t ~= replanToken or not plan or Scan.Busy() or st == 'buying' or st == 'price' then return end
		if not Scan.IsOpen() then return end
		if mine().mode == 'favor' and ui.track and ((ui.track.spent or 0) > 0 or (ui.track.handed or 0) > 0) then return end
		ui.doPlan()
	end)
end

local function doFavor()
	local ok, err = pcall(favorNow)
	if not ok then refresh('Plan failed: ' .. tostring(err), true) end
end
local function favorHeld()
	local W = D.waylaid
	local st = State.Read(db)
	local hand, n, favor = {}, 0, 0
	for _, c in ipairs(W.crates) do
		local k = st.items[c[1]] or 0
		if k > 0 then hand[#hand + 1] = { kind = c[3], tier = c[2], count = k }; n = n + k; favor = favor + k * W.favor[c[3]][c[2]] end
	end
	for kind, tiers in pairs(W.sealed) do
		for tier, id in pairs(tiers) do
			local k = st.items[id] or 0
			if k > 0 then hand[#hand + 1] = { kind = kind, tier = tier, count = k }; n = n + k; favor = favor + k * W.favor[kind][tier] end
		end
	end
	local info = { writs = {}, needItem = {}, noPlace = {}, doneToday = {}, rep = 0 }
	if n == 0 then ui.heldInfo, ui.heldRoute = info, nil; return refresh('No crates held now', true) end
	local inMail = false
	for id in pairs(st.from.mail) do if W.names[id] then inMail = true end end
	for id in pairs(st.from.bought) do if W.names[id] then inMail = true end end
	local label = State.Label()
	local _, class = UnitClass('player')
	ui.heldRoute = Plan.Route({ writs = {}, start = State.Start(), bags = inMail and bagCap() or 0, hearth = State.Hearth(), druid = class == 'DRUID', mage = class == 'MAGE', crates = Guide.CrateGroups(hand), crateSlots = math.ceil(n / 5), label = not label.done and (label.held or label.onQuest) and label or nil })
	ui.heldInfo = info
	refresh(('%d crates held: this route, %d min, +%s Favor (filled ones; unfilled need their bundle)'):format(n, math.floor(ui.heldRoute.total / 60 + 0.5), commas(favor)))
	ui.showRoute('held')
end

local function debugDump()
	local function say(s) DEFAULT_CHAT_FRAME:AddMessage('|cff33ccffWrits:|r ' .. s) end
	local raw, standing, name = State.Rep()
	local goal = State.GOALS[settings().goal]
	local s = settings()
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	say(('v%s, %s %s %d, goal %s %d in %d day(s), minute %s, bags %d, least up %d, scale %.2f'):format(meta and meta(ADDON, 'Version') or '?', name, standing, raw, goal[1], goal[2], s.days, Plan.Money(s.minute), bagCap(), s.stock, s.scale or 1))
	local _, class = UnitClass('player')
	local start, hearth = State.Start(), State.Hearth()
	say(('start %s, hearth %s (bind "%s"), class %s'):format(D.nodes[start] and D.nodes[start][1] or tostring(start), hearth and D.nodes[hearth][1] or 'none', tostring(GetBindLocation and GetBindLocation()), tostring(class)))
	local isWrit = {}
	for _, w in ipairs(D.writs) do isWrit[w[1]] = true end
	local nw, ni, kinds = 0, 0, { commodity = 0, item = 0 }
	for id, p in pairs(db.prices or {}) do
		if isWrit[id] then nw = nw + 1 else ni = ni + 1 end
		if p.kind then kinds[p.kind] = (kinds[p.kind] or 0) + 1 end
	end
	say(('prices: %d writs, %d items (%d known commodity, %d item), scanned %s, full scan %s, %d searches a full scan'):format(nw, ni, kinds.commodity, kinds.item, db.scanAt and date('%H:%M', db.scanAt) or 'never', db.fullAt and date('%H:%M', db.fullAt) or 'never', #D.terms + 1))
	say('scan: ' .. Scan.Info())
	local ok, st = pcall(State.Read, db)
	if ok then
		local held, done, ids = 0, 0, {}
		for _ in pairs(st.held) do held = held + 1 end
		for q in pairs(st.done) do done = done + 1; if #ids < 60 then ids[#ids + 1] = q end end
		table.sort(ids)
		say(('writs held %d, handed in today %d (%d by the game, %d seen by us), Auctionator %s, TSM %s, RestedXP %s'):format(held, done, st.doneBy.flag, st.doneBy.ours, (Auctionator and Auctionator.API) and 'yes' or 'no', TSM_API and 'yes' or 'no', (RXPGuides and RXPGuides.RegisterGuide) and 'yes' or 'no'))
		say('handed in today: ' .. table.concat(ids, ' '))
	else say('reading bags failed: ' .. tostring(st)) end
	if plan and plan.reason then say('plan: ' .. plan.reason)
	elseif plan and plan.picks then say(('plan: need %d, got %d, %d picks, %d plannable, %d done today, today max %d, days needed %s'):format(plan.need, plan.got, #plan.picks, plan.usable or 0, plan.doneToday or 0, plan.today or 0, tostring(plan.daysNeeded)))
	else say('plan: none yet') end
	local list, cur = Buy.List()
	local p = Buy.Pending()
	say(('buy: %s, line %d of %d, %s'):format(list and 'list' or 'no list', cur or 0, list and #list or 0, p and (p.kind .. ' ' .. p.qty .. ' for ' .. Plan.Money(p.total) .. (p.over and ' (over the plan)' or '')) or 'nothing ready to buy'))
	say('status: ' .. tostring(status))
	if db.handins and #db.handins > 0 then
		local by = {}
		for _, r in ipairs(db.handins) do
			local k = r.tier .. ' ' .. r.kind
			local b = by[k] or { n = 0, money = 0, favor = 0, fn = 0, em = r.expectMoney, ef = r.expectFavor }
			b.n, b.money = b.n + 1, b.money + (r.money or 0)
			if r.favor then b.favor, b.fn = b.favor + r.favor, b.fn + 1 end
			by[k] = b
		end
		say('hand-ins (actual each, we assume):')
		for k, b in pairs(by) do
			say(('  %s x%d: money %s (%s), Favor %s (%d)'):format(k, b.n, Plan.Money(b.money / b.n), Plan.Money(b.em or 0), b.fn > 0 and ('%.1f'):format(b.favor / b.fn) or '?', b.ef or 0))
		end
	end
	local log = db.log or {}
	for k = math.max(1, #log - 9), #log do say('  ' .. log[k]) end
end

local function toggle(show)
	if ns.Blocked and ns.Blocked() then return end
	if not ui then
		build()
		ui.doPlan = function() if mine().mode == 'favor' then doFavor() else doPlan() end end
		ui.routeHeld = function(show) if mine().mode == 'favor' then favorHeld() else routeHeld(show) end end
		ui.sendToRXP, ui.drawRoute, ui.drawHeld, ui.showRoute, ui.favorScan = sendToRXP, ui_drawRoute, ui_drawHeld, showRoute, favorScan
		ui.openPicker = ui_openPicker
		ui.layout = function(favor)
			local ok, e = pcall(layout, favor)
			if not ok then ns.Log('layout error: ' .. tostring(e)); ui.laidOut = nil end
		end
		ui.writsStage2, ui.replanSoon, ui.waypoint = writsStage2, replanSoon, waypoint
		ui.trackFor, ui.trackLine = trackFor, trackLine
		if ns.OnBuild then pcall(ns.OnBuild, ui) end
	end
	if show == nil then show = not ui.frame:IsShown() end
	if show then dock(); ui.frame:Show(); refresh() else ui.frame:Hide() end
end

local regen = CreateFrame('Frame')
regen:RegisterEvent('PLAYER_REGEN_ENABLED')
regen:SetScript('OnEvent', function()
	if ui and ui.showAfterCombat then ui.showAfterCombat, ui.hidForMap = nil, nil; ui.frame:Show(); refresh() end
end)
local ev = CreateFrame('Frame')
ev:RegisterEvent('ADDON_LOADED')
ev:RegisterEvent('AUCTION_HOUSE_SHOW')
ev:RegisterEvent('MAIL_INBOX_UPDATE')
ev:RegisterEvent('BANKFRAME_OPENED')
ev:RegisterEvent('CURRENCY_DISPLAY_UPDATE')
ev:RegisterEvent('PLAYERBANKSLOTS_CHANGED')
ev:RegisterEvent('BANKFRAME_CLOSED')
ev:SetScript('OnEvent', function(_, event, arg)
	if event == 'ADDON_LOADED' and arg == ADDON then
		_G[DBNAME] = _G[DBNAME] or {}
		db = _G[DBNAME]
		ns.db = db
		db.prices = db.prices or {}
		db.settings = db.settings or {}
		for k, v in pairs(DEFAULTS) do if db.settings[k] == nil then db.settings[k] = v end end
		if db.settings.speed == nil or db.settings.speed == 50 and db.settings.minute ~= 1000 then db.settings.speed = math.floor(speedOf(db.settings.minute or 1000) + 0.5) end
		db.settings.minute = minuteOf(db.settings.speed)
		if not ({ [0] = true, [3] = true, [5] = true, [10] = true })[db.settings.stock] then db.settings.stock = 5 end
		if db.guide and db.guide.day == State.WritDay() and RXPGuides and RXPGuides.RegisterGuide then pcall(RXPGuides.RegisterGuide, db.guide.text) end
		if FAVOR_ONLY then mine().mode = 'favor' end
	elseif event == 'AUCTION_HOUSE_SHOW' then
		if ns.Blocked and ns.Blocked(true) then return end
		toggle(true)
		if not plan then ui.doPlan() end
	elseif event == 'MAIL_INBOX_UPDATE' and db then
		State.ReadMail(db)
		if ui and ui.frame:IsShown() and plan and mine().mode ~= 'favor' then ui.replanSoon() end
		if ui and ui.frame:IsShown() then refresh() end
	elseif event == 'CURRENCY_DISPLAY_UPDATE' then
		if ui and ui.frame:IsShown() and mine().mode == 'favor' then refresh() end
	elseif (event == 'BANKFRAME_OPENED' or event == 'PLAYERBANKSLOTS_CHANGED' or event == 'BANKFRAME_CLOSED') and db then
		State.ReadBank(db)
		if ui and ui.frame:IsShown() then refresh() end
	end
end)

local GetItemCount_ = (C_Item and C_Item.GetItemCount) or GetItemCount
local function nextFill()
	local W = D.waylaid
	local left, pick = 0, nil
	for _, c in ipairs(W.crates) do
		local n = GetItemCount_(c[1]) or 0
		if n > 0 then
			local opt
			for _, o in ipairs(c[5]) do if (GetItemCount_(o[1]) or 0) >= o[2] then opt = o; break end end
			if opt then
				left = left + n
				if not pick then pick = { crate = c[1], item = opt[1], n = opt[2] } end
			end
		end
	end
	return pick, left
end
function ui_fillButton(parent, w)
	local b = CreateFrame('Button', PREFIX .. 'Fill', parent, 'SecureActionButtonTemplate')
	b:SetSize(w, 28)
	b:RegisterForClicks('AnyUp', 'AnyDown')
	b:SetAttribute('type', 'macro')
	S.Box(b, C.panel, { C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6, 1 })
	b.label = S.Text(b, 12, C.gold, 'CENTER'); b.label:SetPoint('LEFT', 4, 0); b.label:SetPoint('RIGHT', -4, 0)
	b.update = function()
		local pick, left = nextFill()
		b.label:SetText(pick and ('Fill: ' .. left .. ' left') or 'Fill: none')
		b.label:SetTextColor(unpack(pick and C.gold or C.muted))
		b.pick = pick
	end
	b:SetScript('PreClick', function(self)
		if InCombatLockdown() then return end
		local pick = nextFill()
		self:SetAttribute('macrotext', pick and ('/use item:' .. pick.crate .. '\n/use item:' .. pick.item .. '\n/click StaticPopup1Button1') or '')
		if pick then ns.Log(('fill: crate %d with %d x %d'):format(pick.crate, pick.n, pick.item)) end
	end)
	b:SetScript('PostClick', function() C_Timer.After(0.5, function() if ui then ui.fill.update() end end) end)
	b:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine('Fill your Waylaid Crates')
		GameTooltip:AddLine('Click again and again: each click fills the next crate in your bags with a bundle you have.', 1, 1, 1, true)
		if self.pick then GameTooltip:AddLine('Next: ' .. (D.waylaid.names[self.pick.crate] or '') .. ' with ' .. self.pick.n .. ' ' .. (D.waylaid.names[self.pick.item] or ''), 0.6, 0.6, 0.6, true) end
		GameTooltip:Show()
	end)
	b:SetScript('OnLeave', function() GameTooltip:Hide() end)
	b:Hide()
	return b
end
local bagWatch = CreateFrame('Frame')
bagWatch:RegisterEvent('BAG_UPDATE_DELAYED')
local bagToken = 0
bagWatch:SetScript('OnEvent', function()
	if not (ui and ui.fill and ui.frame:IsShown()) then return end
	ui.fill.update()
	if not plan then return end
	ui.replanSoon()
end)

local DOKIMI = tostring(D.waylaid.handIn.id or 256386)
local HANDIN = { [98247] = true, [98248] = true }
for _, tiers in pairs(D.waylaid.quests) do for _, q in pairs(tiers) do HANDIN[q] = true end end
local function atDokimi()
	local g = UnitGUID and UnitGUID('npc')
	return g and select(6, strsplit('-', g)) == DOKIMI
end
local function autoOn() return db and db.settings and db.settings.autoHandIn ~= false and not IsShiftKeyDown() and atDokimi() end
local SEALED_OF = {}
for kind, tiers in pairs(D.waylaid.quests) do for tier, q in pairs(tiers) do SEALED_OF[q] = D.waylaid.sealed[kind][tier] end end
local function canHandIn(q)
	if not HANDIN[q] then return false end
	local item = SEALED_OF[q]
	if item then return (GetItemCount_(item) or 0) > 0 end
	local lb = State.Label()
	return lb.quest == q and not lb.done and (lb.held or lb.onQuest) or false
end
ns.CanHandIn = canHandIn
local qf = CreateFrame('Frame')
for _, e in ipairs({ 'GOSSIP_SHOW', 'QUEST_GREETING', 'QUEST_DETAIL', 'QUEST_PROGRESS', 'QUEST_COMPLETE' }) do qf:RegisterEvent(e) end
qf:SetScript('OnEvent', function(_, event)
	if not autoOn() then return end
	local ok, err = pcall(function()
		if event == 'GOSSIP_SHOW' and C_GossipInfo then
			for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
				if canHandIn(q.questID) and q.isComplete ~= false then return C_GossipInfo.SelectActiveQuest(q.questID) end
			end
			for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
				if canHandIn(q.questID) then return C_GossipInfo.SelectAvailableQuest(q.questID) end
			end
		elseif event == 'QUEST_GREETING' then
			for i = 1, GetNumActiveQuests() do
				local id = GetActiveQuestID and GetActiveQuestID(i)
				if id and canHandIn(id) then return SelectActiveQuest(i) end
			end
			for i = 1, GetNumAvailableQuests() do
				local id = select(5, GetAvailableQuestInfo(i))
				if id and canHandIn(id) then return SelectAvailableQuest(i) end
			end
		elseif HANDIN[GetQuestID() or 0] then
			if event == 'QUEST_DETAIL' then AcceptQuest()
			elseif event == 'QUEST_PROGRESS' then
				if IsQuestCompletable() then CompleteQuest()
				else
					ns.Log('auto hand-in: quest ' .. tostring(GetQuestID()) .. ' can\'t be completed, left')
					if DeclineQuest then DeclineQuest() elseif CloseQuest then CloseQuest() end
				end
			elseif event == 'QUEST_COMPLETE' then
				if (GetNumQuestChoices() or 0) <= 1 then GetQuestReward(1); ns.Log('handed in quest ' .. GetQuestID()) end
			end
		end
	end)
	if not ok then ns.Log('auto hand-in: ' .. tostring(err)) end
end)

function trackFor()
	ui.track = ui.track or { spent = 0, planned = 0, handed = 0, back = 0, expect = 0, crates = 0, expectBack = 0 }
	return ui.track
end
local function signed(c) return (c >= 0 and '+' or '-') .. Plan.Money(math.abs(c)) end
function trackLine()
	local t = ui.track
	if not t or (t.spent == 0 and t.handed == 0 and (t.writsIn or 0) == 0) then return '' end
	local out = {}
	if t.spent > 0 then
		local d = t.spent - t.planned
		out[#out + 1] = ('Bought: %s%s|r (planned %s, %s%s|r)'):format(WHITE, Plan.Money(t.spent), Plan.Money(t.planned), d > 0 and RED or GREEN, signed(d))
	end
	if (t.writsIn or 0) > 0 then
		out[#out + 1] = ('Handed in %d%s writs: %s+%s rep|r'):format(t.writsIn, t.planWrits and ('/' .. t.planWrits) or '', GREEN, commas(t.repIn or 0))
	end
	if t.handed > 0 then
		local d = t.back - t.expect
		out[#out + 1] = ('Handed in %d%s: back %s%s|r (expected %s, %s%s|r)'):format(t.handed, t.crates > 0 and ('/' .. t.crates) or '', WHITE, Plan.Money(t.back), Plan.Money(t.expect), d < 0 and RED or GREEN, signed(d))
		if t.favorIn then
			local df = t.favorIn - (t.favorExpect or 0)
			out[#out + 1] = ('Favor: %s+%d|r (expected +%d, %s%s%d|r)'):format(WHITE, t.favorIn, t.favorExpect or 0, df < 0 and RED or GREEN, df >= 0 and '+' or '', df)
		end
	end
	return table.concat(out, '\n')
end
local writRep = {}
for _, w in ipairs(D.writs) do writRep[w[2]] = D.rep[w[5]] end
local crateTier, questInfo = {}, {}
for kind, tiers in pairs(D.waylaid.quests) do for tier, q in pairs(tiers) do crateTier[q] = tier; questInfo[q] = { kind = kind, tier = tier } end end
local handWatch = CreateFrame('Frame')
handWatch:RegisterEvent('QUEST_TURNED_IN')
handWatch:SetScript('OnEvent', function(_, _, quest, _, money)
	local tier = crateTier[quest]
	if writRep[quest] and ui then
		local t = trackFor()
		t.writsIn, t.repIn = (t.writsIn or 0) + 1, (t.repIn or 0) + writRep[quest]
		if ui.frame:IsShown() then refresh() end
		return
	end
	if not (tier and ui) then return end
	local t = trackFor()
	local info = questInfo[quest]
	local expectFavor = D.waylaid.favor[info.kind][info.tier] or 0
	t.handed, t.back, t.expect = t.handed + 1, t.back + (money or 0), t.expect + (D.waylaid.money[tier] or 0)
	t.favorExpect = (t.favorExpect or 0) + expectFavor
	local before = State.Favor(db)
	db.handins = db.handins or {}
	local rec = { at = GetServerTime and GetServerTime() or time(), quest = quest, kind = info.kind, tier = info.tier, money = money or 0, expectMoney = D.waylaid.money[tier] or 0, expectFavor = expectFavor }
	table.insert(db.handins, rec)
	while #db.handins > 300 do table.remove(db.handins, 1) end
	ns.Log(('hand-in %s %s: %s (expected %s)'):format(info.tier, info.kind, Plan.Money(money or 0), Plan.Money(rec.expectMoney)))
	C_Timer.After(1.5, function()
		local after = State.Favor(db)
		if before and after then
			rec.favor = after - before
			t.favorIn = (t.favorIn or 0) + rec.favor
			if ui.frame:IsShown() then refresh() end
		end
	end)
	if ui.frame:IsShown() then refresh() end
end)

local function endOne(replan)
	if not oneOff then return end
	oneOff = nil
	oneToken = oneToken + 1
	local t = oneToken
	if not (replan and ui and ui.doPlan and plan) then return end
	C_Timer.After(3, function()
		local st = Buy.Step()
		if t ~= oneToken or oneOff or Scan.Busy() or st == 'buying' or st == 'price' then return end
		ui.doPlan()
	end)
end
local function buyOne(shopping, o)
	if not Scan.IsOpen() then return false, 'Open the Auction House to buy' end
	if Scan.Busy() then return false, 'A scan is running: wait for it to end' end
	local st = Buy.Step()
	if st == 'buying' or st == 'price' then return false, 'A purchase is under way' end
	oneToken = oneToken + 1
	oneOff = { title = o.title }
	local mine_ = oneOff
	Buy.Start(shopping, function(msg)
		local list, cur = Buy.List()
		local over = not list or cur > #list
		if over and oneOff == mine_ then endOne(true) end
		if o.onChange then pcall(o.onChange, msg, over) end
		refresh(msg)
	end, {
		done = o.done,
		onBought = function(e, qty, paid)
			State.Bought(db, e.id, qty)
			if o.onBought then pcall(o.onBought, e, qty, paid) end
		end,
	})
	return true
end
ns.UI = {
	buyOne = buyOne,
	guard = function(go) guardBuy(go) end,
	buyStop = function() if oneOff then endOne(false); Buy.Clear(); if ui and ui.doPlan and plan then ui.doPlan() else refresh() end end end,
	buying = function() return oneOff ~= nil end,
	bagCap = bagCap,
	toggle = function(show) toggle(show) end,
	prices = prices,
	shown = function() return ui and ui.frame:IsShown() or false end,
}

local function slash(arg)
	arg = (arg or ''):lower()
	if ns.Blocked and ns.Blocked() then return end
	if ns.Slash and ns.Slash(arg) then return end
	if arg:match('^%s*debug') then return debugDump() end
	if arg:match('^%s*plan') then if ui and ui.doPlan then ui.doPlan() end; return end
	if arg:match('^%s*reset') then settings().pos = nil; if ui then dock() end; return end
	if arg:match('^%s*held') then
		local c = State.Char(db)
		if arg:match('forget') then
			c.mail, c.mailAt, c.bank, c.bankAt, c.bought = {}, nil, {}, nil, nil
			print('|cffffc840Writs and Favors|r: forgot the mail and bank snapshots, and what was bought and not collected, for this character. Open the mailbox and the bank to read them again.')
			if ui and ui.doPlan and mine().mode ~= 'favor' then ui.doPlan() end
			return
		end
		local st = State.Read(db)
		local names = {}
		for _, w in ipairs(D.writs) do names[w[1]] = w[7]; names[w[3]] = names[w[3]] or w[8] end
		local now = GetServerTime and GetServerTime() or time()
		local function age(t) return t and (math.floor((now - t) / 60) .. ' min ago') or 'never' end
		print('|cffffc840Writs and Favors|r: what the plans count as held (writs and their items only):')
		for _, src in ipairs({ 'bags', 'mail', 'bank', 'bought' }) do
			local lines = {}
			for id, n in pairs(st.from[src] or {}) do if names[id] then lines[#lines + 1] = n .. ' x ' .. names[id] end end
			table.sort(lines)
			local when = src == 'bags' and 'now' or src == 'bought' and 'at the AH, not collected from the mail yet' or ('read ' .. age(src == 'mail' and c.mailAt or c.bankAt))
			print(('  %s (%s): %s'):format(src, when, #lines > 0 and table.concat(lines, ', ') or 'nothing'))
		end
		print('  /writs held forget: forget the mail and bank snapshots (read again at the next mailbox or bank)')
		return
	end
	if arg:match('^%s*map') and ns.OMRoute and ns.OMRoute.Available() then
		if ns.OMRoute.IsOn() then ns.OMRoute.SetOn(false) elseif ui and ui.mapData then ns.OMRoute.SetData(ui.mapData); ns.OMRoute.Open(true) end
		return
	end
	local sc = arg:match('^%s*scale%s+([%d%.]+)')
	if sc then return setScale(tonumber(sc) or 1) end
	toggle()
end
if FAVOR_ONLY then
	SLASH_JAMFAVOR1 = '/favor'
	SlashCmdList.JAMFAVOR = slash
else
	local function inMode(mode)
		return function(arg)
			if (arg or ''):match('%S') then return slash(arg) end
			if ns.Blocked and ns.Blocked() then return end
			if not ui then toggle(false) end
			local here = ui.frame:IsShown()
			if (mine().mode == 'favor') ~= (mode == 'favor') then
				ui.switchMode(mode)
				return toggle(true)
			end
			toggle(not here)
		end
	end
	SLASH_JAMWRITS1 = '/writs'
	SlashCmdList.JAMWRITS = inMode('writs')
	SLASH_JAMWF1 = '/wf'
	SlashCmdList.JAMWF = slash
	SLASH_JAMFAVOR1 = '/favor'
	SlashCmdList.JAMFAVOR = inMode('favor')
end
