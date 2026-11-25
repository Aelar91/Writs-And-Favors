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
	if checkOK or settings().remind == false then return go() end -- (turned off in the game's options: Options.lua)
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
		w.wait = S.Button(w, "Don't buy yet", 160, 28, function() w:Hide() end); w.wait:SetPoint('BOTTOMLEFT', 14, 12)
		w.go = S.Button(w, 'Buy anyway', 160, 28, function()
			checkOK = true
			w:Hide()
			if w.run then w.run() end
		end, true); w.go:SetPoint('BOTTOMRIGHT', -14, 12)
		checkWin = w
	end
	local w = checkWin
	local what = #miss == 2 and 'mailbox or your bank' or miss[1]
	w.title:SetText('Check your ' .. (#miss == 2 and 'mailbox and bank' or miss[1]) .. ' first?')
	w.text:SetText(('You haven\'t opened your %s today, so what\'s in %s isn\'t counted. You could buy writs, crates or items you already have.\n\nOpen %s once and the list updates by itself. Buy anyway?'):format(what, #miss == 2 and 'them' or 'it', #miss == 2 and 'each' or 'it'))
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
local function nb(s) return (tostring(s):gsub(' ', '\194\160')) end
local DOT = ' \194\183 '
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
local ARROW_W = 20
local function dropdown(parent, w, options, get, set)
	local b = S.Button(parent, '', w, 24)
	b.label:ClearAllPoints(); b.label:SetPoint('LEFT', 8, 0); b.label:SetJustifyH('LEFT')
	local function fitLabel(bw) b.label:SetWidth(math.max(1, (bw or w) - ARROW_W - 12)) end
	fitLabel(w)
	b:SetScript('OnSizeChanged', function(_, bw) if bw and bw > ARROW_W + 12 then fitLabel(bw) end end)
	local sep = b:CreateTexture(nil, 'ARTWORK')
	sep:SetColorTexture(C.border[1], C.border[2], C.border[3], C.border[4] or 1)
	sep:SetPoint('TOPRIGHT', -ARROW_W, -4); sep:SetPoint('BOTTOMRIGHT', -ARROW_W, 4); sep:SetWidth(1)
	local arrow = b:CreateTexture(nil, 'OVERLAY')
	arrow:SetTexture('Interface\\Buttons\\Arrow-Down-Up')
	arrow:SetSize(12, 12); arrow:SetPoint('CENTER', b, 'RIGHT', -ARROW_W / 2, -3)
	arrow:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
	b.arrow = arrow
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
		for _, o in ipairs(options()) do if o.value == get() then b:SetText(o.text) end end
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
	r.name = S.Text(r, 12); r.name:SetPoint('LEFT', 28, 0); r.name:SetWidth(186); r.name:SetWordWrap(false)
	r.rep = S.Text(r, 11, C.muted, 'RIGHT'); r.rep:SetPoint('RIGHT', -76, 0); r.rep:SetWidth(64); r.rep:SetWordWrap(false)
	r.cost = S.Text(r, 12, C.text, 'RIGHT'); r.cost:SetPoint('RIGHT', -4, 0); r.cost:SetWidth(70)
	return r
end
local ui_drawHeld
local function valueColor(t)
	t = math.max(0, math.min(1, t or 0.5))
	if t < 0.5 then local k = t / 0.5; return { 0.3 + 0.7 * k, 0.9 - 0.05 * k, 0.35 - 0.15 * k } end
	local k = (t - 0.5) / 0.5
	return { 1, 0.85 - 0.55 * k, 0.2 + 0.05 * k }
end
local STATE_COLOR = { picked = { 0.45, 1, 0.6 }, thin = { 1, 0.63, 0.25 }, done = { 0.55, 0.55, 0.55 }, none = { 0.6, 0.16, 0.14 } }
ns.writColors = { value = valueColor, state = STATE_COLOR }
local function shownRoute()
	if ui.mapSource == 'held' then return ui.heldRoute end
	return plan and plan.route
end

local function useFlights()
	if not (ns.Net and D.G) then return 0 end
	local known, unread = State.Flights(db)
	if ns.Net.Use(known) then ns.Log('flight points: ' .. ns.Net.Key()) end
	return unread or 0
end
local function labelNeedsCrate(label, mail)
	if label.done or label.held or label.onQuest or label.banked then return false end
	mail = mail or ((State.Char(db) or {}).mail or {})
	return not ((mail[label.item] or 0) > 0)
end
local function heldRoute()
	useFlights()
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
	local route = Plan.Route({ writs = out.writs, level = UnitLevel and UnitLevel('player') or nil, start = State.Start(), bags = inMail and bagCap() or 0, hearth = State.Hearth(), druid = class == 'DRUID', mage = class == 'MAGE', label = withLabel and label or nil })
	return out, route
end

local function warnLines(writs, level)
	local at, out = {}, {}
	for _, w in ipairs(writs) do at[#at + 1] = w.place end
	local zs = Plan.Warn(at, level)
	if #zs == 1 then out[1] = RED .. Plan.WarnText(zs[1][1], zs[1][2], level) .. '|r'
	elseif #zs > 1 then
		local names = {}
		for _, z in ipairs(zs) do names[#names + 1] = ('%s (%d+)'):format(z[1], z[2]) end
		out[1] = RED .. ('Above your level (%d): %s. You can still do them, but expect to die a few times.|r'):format(level, table.concat(names, ', '))
	end
	return out
end
local function routeHeld()
	local info, route = heldRoute()
	ui.heldInfo, ui.heldRoute = info, route
	local need = #info.needItem > 0 and (#info.needItem .. (#info.needItem == 1 and ' more writ needs its item' or ' more writs need their item')) or nil
	if not route then
		ui.mapSource = 'plan'
		return refresh('Nothing held to hand in now' .. (need and (': ' .. need) or ''), true)
	end
	ui.mapSource = 'held'
	clearBuy()
	ui.buyHead = 'BUY LIST  ' .. WHITE .. 'nothing to buy|r'
	local min = math.floor(route.total / 60 + 0.5)
	local lines = {
		WHITE .. table.concat({ nb(#info.writs .. (#info.writs == 1 and ' writ held' or ' writs held')), nb('+' .. commas(info.rep) .. ' rep'), nb(min .. ' min') }, DOT) .. '|r',
		GREEN .. 'Nothing to buy. Guide me or Send to RestedXP takes you round them.|r',
	}
	if need then lines[#lines + 1] = GOLD .. need .. ': left out.|r' end
	for _, l in ipairs(warnLines(info.writs, UnitLevel and UnitLevel('player') or 0)) do lines[#lines + 1] = l end
	ui.summary:SetText(table.concat(lines, '\n'))
	refresh(('%d writs held: this route, %d min, +%s rep'):format(#info.writs, min, commas(info.rep)))
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
	local function some(n, word) return n .. ' ' .. (n == 1 and word:gsub('s$', '') or word) end
	local parts = {}
	if tw + ti > 0 then parts[1] = ('You hold %s and %s: left off the list.'):format(some(tw, A), some(ti, B)) end
	if kw + ki > 0 then parts[#parts + 1] = ('%d in your bank: take %s out first.'):format(kw + ki, kw + ki == 1 and 'it' or 'them') end
	local unseen = (not st.seen.mail and not st.seen.bank) and 'mailbox and bank' or not st.seen.mail and 'mailbox' or not st.seen.bank and 'bank' or nil
	if unseen then parts[#parts + 1] = ('Open your %s once to count what\'s there.'):format(unseen) end
	ui.held.text:SetText(table.concat(parts, ' '))
	local hh = ui.held.text:GetStringHeight()
	ui.held:SetHeight(#parts == 0 and 1 or (hh and hh > 10) and hh or 16)
	ui.held.lines = {
		{ 'In your bags', ('%d %s, %d %s (now)'):format(bw, A, bi, B) },
		{ 'In your mail', st.seen.mail and ('%d %s, %d %s (%s)'):format(mw, A, mi, B, ago(st.seen.mail)) or 'not seen yet: open your mailbox' },
		{ 'In your bank', st.seen.bank and ('%d %s, %d %s (%s)'):format(kw, A, ki, B, ago(st.seen.bank)) or 'not seen yet: open your bank' },
	}
	if gw + gi > 0 then ui.held.lines[#ui.held.lines + 1] = { 'Bought, in the mail', ('%d %s, %d %s (not collected yet)'):format(gw, A, gi, B) } end
end

local function inFight(quiet)
	if not (InCombatLockdown and InCombatLockdown()) then return false end
	if not quiet then print('|cffffc840Writs and Favors|r: not in combat. Try again once the fight is over.') end
	return true
end
local function dock()
	local f = ui.frame
	if inFight(true) then return end
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
	if ui and not inFight(true) then ui.frame:SetScale(settings().scale) end
end

local ui_fillButton, ui_stampButton, trackFor, trackLine
local function build()
	local f = CreateFrame('Frame', PREFIX .. 'Frame', UIParent)
	f:SetSize(W, 600)
	f:SetPoint('CENTER')
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag('LeftButton')
	f:SetScript('OnDragStart', function(self) if not inFight(true) then self:StartMoving() end end)
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
		ui.mapSource = 'plan'
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
	local close = S.Button(head, 'x', 24, 22, function() if not inFight() then f:Hide() end end); close:SetPoint('RIGHT', -4, 0)
	ui.head = head
	ui.browseBtn = S.Button(head, 'Browse', 58, 22, function() if ns.Browse then ns.Browse() end end)
	ui.browseBtn:SetPoint('RIGHT', close, 'LEFT', -8, 0)
	function ui.switchMode(mode)
		mode = mode or ((mine().mode == 'favor') and 'writs' or 'favor')
		if not FAVOR_ONLY then
			local s = settings()
			if mode == 'favor' and s.goal ~= 0 then s.lastGoal = s.goal; s.goal = 0
			elseif mode ~= 'favor' and s.goal == 0 then s.goal = s.lastGoal or 2 end
		end
		mine().mode = mode
		plan = nil
		ui.track = nil
		clearBuy()
		ui.summary:SetText('')
		refresh(mine().mode == 'favor' and "Merchant's Favor: Scan crates for live prices" or 'Craftsman\'s Writs')
		if ui.doPlan then ui.doPlan() end
	end
	ui.modeBtn = S.Button(head, 'Favor', 52, 22, function() ui.switchMode() end, true)
	ui.modeBtn:SetPoint('RIGHT', ui.browseBtn, 'LEFT', -4, 0)
	ui.modeBtn:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		local favor = mine().mode == 'favor'
		GameTooltip:AddLine(favor and 'Switch to Reputation' or "Switch to Merchant's Favor")
		GameTooltip:AddLine(favor and 'Reputation with ' .. (D.factionName or 'the faction') .. ": Craftsman's Writs and Forged Delivery Receipt crates, planned to the standing you want." or 'Waylaid Crates: the cheapest to fill for the Favor you want.', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	ui.modeBtn:HookScript('OnLeave', function() GameTooltip:Hide() end)
	ui.optsBtn = S.Button(head, '', 24, 22, function() ui.opts:SetShown(not ui.opts:IsShown()) end)
	do
		local cog = ui.optsBtn:CreateTexture(nil, 'ARTWORK')
		cog:SetSize(16, 16); cog:SetPoint('CENTER')
		cog:SetTexture('Interface\\Buttons\\UI-OptionsButton')
		ui.optsBtn.cog = cog
		ui.optsBtn:HookScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_TOP')
			GameTooltip:AddLine('Options')
			GameTooltip:AddLine('Skipping writs with few listings, the size of the panel, and the way to all the settings.', 1, 1, 1, true)
			GameTooltip:Show()
		end)
		ui.optsBtn:HookScript('OnLeave', function() GameTooltip:Hide() end)
	end
	ui.optsBtn:SetPoint('RIGHT', ui.browseBtn, 'LEFT', -4, 0)
	f:SetScript('OnHide', function()
		if ns.Recipes and ns.Recipes.Shown() then ns.Recipes.Toggle(false) end
		if ns.Tour then ns.Tour.Closed() end
	end)

	ui.faction = S.Text(f, 13); ui.faction:SetPoint('TOPLEFT', PAD, -44)
	ui.standing = S.Text(f, 12, C.muted, 'RIGHT'); ui.standing:SetPoint('TOPRIGHT', -PAD, -45)
	ui.bar = S.Bar(f, IW, 6); ui.bar:SetPoint('TOPLEFT', PAD, -64)

	ui.goalHead = S.Heading(f, 'Goal', IW)
	ui.goalHead:SetPoint('TOPLEFT', PAD, -84)
	local goals = function()
		local o = { { text = 'No reputation', value = 0 } }
		for i, g in ipairs(State.GOALS) do o[#o + 1] = { text = g[1], value = i } end
		return o
	end
	ui.goal = dropdown(f, 112, goals, function() return settings().goal end, function(v)
		settings().goal = v
		local m = v == 0 and 'favor' or 'writs'
		if mine().mode ~= m then ui.switchMode(m) end
	end)
	ui.favorLabel = S.Text(f, 12, C.muted); ui.favorLabel:SetText('Favor')
	ui.favorHint = S.Text(f, 12, C.muted)
	do
		local eb = CreateFrame('EditBox', PREFIX .. 'FavorWant', f)
		eb:SetSize(64, 24)
		S.Box(eb, C.panel, C.border)
		if not eb:SetFont(S.Font(), 12, '') then eb:SetFont(STANDARD_TEXT_FONT, 12, '') end
		eb:SetTextColor(C.text[1], C.text[2], C.text[3])
		eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(5); eb:SetTextInsets(8, 8, 0, 0)
		local function apply()
			local v = math.max(0, math.min(99999, math.floor(tonumber(eb:GetText() or '') or 0)))
			if v == (settings().favorWant or 0) then return end
			settings().favorWant = v
			refresh()
			if plan and ui.changed then ui.changed() elseif ui.doPlan and not Scan.Busy() then ui.doPlan() end
		end
		eb.apply = apply
		function ui.setFavorWant(v)
			v = math.max(0, math.min(99999, math.floor(tonumber(v) or 0)))
			if v == (settings().favorWant or 0) then return end
			settings().favorWant = v
			refresh()
			if plan and ui.changed then ui.changed() elseif ui.doPlan and not Scan.Busy() then ui.doPlan() end
		end
		eb:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)
		eb:SetScript('OnEscapePressed', function(self) self:SetText(tostring(settings().favorWant or 0)); self:ClearFocus() end)
		eb:SetScript('OnEditFocusLost', apply)
		eb.update = function()
			if not (eb.HasFocus and eb:HasFocus()) then eb:SetText(tostring(settings().favorWant or (FAVOR_ONLY and ((State.Favor(db) or 0) + (settings().favorGoal or 100))) or 0)) end
			local held = State.Favor(db) or 0
			local want = settings().favorWant or 0
			ui.favorHint:SetText(want <= 0 and ('you have ' .. commas(held)) or want <= held and (GREEN .. 'you have ' .. commas(held) .. '|r') or ('have ' .. commas(held) .. ', ' .. commas(want - held) .. ' to get'))
		end
		eb:SetScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_TOP')
			GameTooltip:AddLine("Merchant's Favor to have at the end")
			GameTooltip:AddLine('How much Favor you want to hold once the plan is done, on top of what the plan itself spends on Forged Delivery Receipts. 0: none wanted. The plan fills Waylaid Crates for what you are short of.', 1, 1, 1, true)
			GameTooltip:Show()
		end)
		eb:SetScript('OnLeave', function() GameTooltip:Hide() end)
		ui.favorBox = eb
	end
	ui.recipesBtn = S.Button(f, 'Recipes', 72, 24, function() if ns.Recipes then ns.Recipes.Toggle() end end)
	ui.recipesBtn:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine('Recipes for Favor')
		GameTooltip:AddLine("The recipes sold for Merchant's Favor, for your professions, less the ones you know. Tick the ones you want and the Favor box becomes what they cost.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	ui.recipesBtn:HookScript('OnLeave', function() GameTooltip:Hide() end)
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
		return 'The standing with ' .. (D.factionName or 'Durotar Supply and Logistics') .. ' you want to reach. No reputation: the plan is only for the Favor number below.'
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
		ui.mapSource = 'plan'
		local quick = Scan.Quick(db) and not IsShiftKeyDown()
		ui.track = nil
		Scan.Start(db, function(d, t, what) refresh(('Scanning %d/%d%s'):format(d, t, what and (': ' .. what) or '...')) end,
			function(msg, failed)
				refresh(msg, failed)
				if failed then return end
				ui.doPlan()
				ui.writsStage2(1, { started = GetServerTime and GetServerTime() or time(), full = 0 })
			end, { quick = quick and mine().mode ~= 'favor', favor = mine().mode == 'favor', receipts = (settings().receipts or 0) > 0 or (settings().favorWant or 0) > 0 or labelNeedsCrate(State.Label()) })
	end)
	ui.scan:SetPoint('TOPLEFT', PAD, -200)
	ui.plan = S.Button(f, 'Plan', bw, 28, function() ui.doPlan() end)
	ui.plan:SetPoint('TOPLEFT', PAD + bw + 8, -200)
	ui.guide = S.Button(f, 'Guide me', bw, 28, function()
		local route = shownRoute()
		if not route then return refresh('Scan first: there is no plan yet', true) end
		if not ns.Nav then return end
		local n = ns.Nav.Start(route)
		refresh(n > 0 and ('Guide started: ' .. n .. ' steps. Follow the waypoint; the small window says what to do') or 'Nothing on this route to guide', n == 0)
	end, true)
	ui.guide:SetPoint('TOPLEFT', PAD + (bw + 8) * 2, -200)
	ui.rxp = S.Button(f, 'Send to RestedXP', bw, 28, function() ui.sendToRXP(shownRoute()) end)
	ui.rxp:SetPoint('TOPLEFT', PAD + (bw + 8) * 3, -200)
	for b, tip in pairs({
		[ui.guide] = { 'Guide me', 'Takes you round the hand-ins step by step, with no other addon: a waypoint for each place, a button for each writ, the hand-in done for you. Buy first.' },
		[ui.rxp] = { 'Send to RestedXP', 'The same route as a RestedXP guide (group "Writs and Favors"), opened for you. Needs RestedXP Guides.' },
	}) do
		b:HookScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_TOP')
			GameTooltip:AddLine(tip[1])
			GameTooltip:AddLine(tip[2], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:HookScript('OnLeave', function() GameTooltip:Hide() end)
	end
	ui.fill = ui_fillButton(f, bw)
	ui.stamp = ui_stampButton(f, bw)
	ui.stamp:SetPoint('TOPLEFT', PAD + bw + 8, -200)
	ui.fill:SetPoint('TOPLEFT', PAD + (bw + 8) * 2, -200)
	ui.auto = S.Button(f, 'Auto hand-in', bw, 28, function()
		settings().autoHandIn = not (settings().autoHandIn ~= false)
		refresh(settings().autoHandIn ~= false and 'Auto hand-in on: talk to ' .. NPC .. ' and the Sealed crates go in (Shift to skip)' or 'Auto hand-in off')
	end)
	ui.auto:SetPoint('TOPLEFT', PAD + (bw + 8) * 3, -200)
	ui.way = S.Button(f, 'Waypoint', bw, 28, function() ui.waypoint() end)
	ui.way:SetPoint('TOPLEFT', PAD, -200)
	ui.way:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine('Waypoint: ' .. NPC)
		GameTooltip:AddLine('Puts a waypoint on ' .. NPC_AT .. ', where the crates are handed in.', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	ui.way:HookScript('OnLeave', function() GameTooltip:Hide() end)

	ui.todayHead = S.Heading(f, 'Today', IW)
	ui.todayHead:SetPoint('TOPLEFT', PAD, -242)
	function ui.choosePlan(which)
		if which == 'held' then return ui.routeHeld(true) end
		ui.mapSource = 'plan'
		if ui.doPlan then ui.doPlan() else refresh() end
	end
	do
		local row = CreateFrame('Frame', nil, f)
		row:SetSize(178, 22)
		row:SetPoint('RIGHT', f, 'RIGHT', -PAD, 0); row:SetPoint('TOP', ui.todayHead, 'TOP', 0, 6)
		local function seg(text, which, w, x, tip)
			local b = S.Button(row, text, w, 22, function() ui.choosePlan(which) end)
			b:SetPoint('LEFT', x, 0)
			b:HookScript('OnEnter', function(self)
				GameTooltip:SetOwner(self, 'ANCHOR_TOP')
				GameTooltip:AddLine(text)
				GameTooltip:AddLine(tip, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			b:HookScript('OnLeave', function() GameTooltip:Hide() end)
			return b
		end
		ui.pAuto = seg('Auto plan', 'auto', 80, 0, 'What to buy for the standing you picked, by the day you picked. Guide me and Send to RestedXP take you round it.')
		ui.pHeld = seg('What I have', 'held', 98, 79, 'The writs already in your bags, mail and bank: Guide me and Send to RestedXP take you round those instead. Nothing to buy.')
		ui.planRow = row
		function ui.colourPlanRow()
			local heldMode = ui.mapSource == 'held'
			local edge = { C.gold[1] * 0.7, C.gold[2] * 0.7, C.gold[3] * 0.7, 1 }
			for b, on in pairs({ [ui.pAuto] = not heldMode, [ui.pHeld] = heldMode }) do
				b:SetText((on and GOLD or WHITE) .. (b == ui.pAuto and 'Auto plan' or 'What I have') .. '|r')
				S.Box(b, on and C.hover or C.panel, on and edge or C.border)
			end
		end
	end
	local alert = CreateFrame('Frame', nil, f)
	alert:SetPoint('TOPLEFT', ui.todayHead, 'BOTTOMLEFT', 0, -14); alert:SetSize(IW, 48)
	S.Box(alert, { 0.25, 0.19, 0.06, 0.55 }, { C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6, 1 })
	alert.icon = alert:CreateTexture(nil, 'ARTWORK'); alert.icon:SetSize(22, 22); alert.icon:SetPoint('LEFT', 10, 0); alert.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	alert.text = S.Text(alert, 12, C.gold); alert.text:SetPoint('LEFT', 42, 0); alert.text:SetWidth(IW - 54); alert.text:SetWordWrap(true); alert.text:SetSpacing(2)
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
	held.text = S.Text(held, 11, C.muted); held.text:SetPoint('TOPLEFT'); held.text:SetWidth(IW); held.text:SetWordWrap(true); held.text:SetSpacing(2)
	held:EnableMouse(true)
	held:SetScript('OnEnter', function(self)
		if not self.lines then return end
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		GameTooltip:AddLine('What you already have')
		GameTooltip:AddLine('Counted from your bags, mailbox and bank, and left off the buy list.', 1, 1, 1, true)
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
	ui.scopeBtn = S.Button(f, 'Buy: today', 112, 20, function() scope((mine().scope or 'day') == 'day' and 'all' or 'day') end)
	ui.scopeBtn:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine('What to buy now')
		GameTooltip:AddLine('Your plan runs over more than one day. Buy today\'s writs only, or every day\'s now at today\'s prices. Click to switch.', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	ui.scopeBtn:HookScript('OnLeave', function() GameTooltip:Hide() end)
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
	op:SetSize(260, 190)
	op:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -4, -34)
	S.Box(op, C.panel, C.gold)
	local function row(text, y) local t = S.Text(op, 11, C.muted); t:SetPoint('TOPLEFT', 10, y); t:SetText(text); return t end
	local opTitle = S.Text(op, 13, C.gold); opTitle:SetPoint('TOPLEFT', 10, -10); opTitle:SetText('Plan options')
	row('Skip writs with few listings', -36)
	local stockOpts = function() local o = {}; for _, n in ipairs({ 0, 3, 5, 10 }) do o[#o + 1] = { text = n == 0 and 'Never skip' or ('Fewer than ' .. n .. ' listed'), value = n } end; return o end
	ui.stock = dropdown(op, 110, stockOpts, function() return settings().stock end, function(v) settings().stock = v end)
	ui.stock:SetParent(op); ui.stock:ClearAllPoints(); ui.stock:SetPoint('TOPLEFT', 10, -52); ui.stock:SetWidth(170)
	ui.stock:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:AddLine('Skip writs with few listings')
		GameTooltip:AddLine('Leaves a writ out of the plan when fewer than this many of it, or of the item it wants, are on the Auction House: a few listings are often bait or gone by the time you buy. Writs you already hold are always planned.', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	ui.stock:HookScript('OnLeave', function() GameTooltip:Hide() end)
	row('Forged Delivery Receipts', -134)
	local rcOpts = function()
		local o = {}
		for _, n in ipairs({ 0, 99, 100 }) do o[#o + 1] = { text = n == 0 and 'Off: writs only' or n == 99 and 'On: crates where cheaper' or 'Crates only: no writs', value = n } end
		return o
	end
	ui.receipts = dropdown(op, 200, rcOpts, function() local v = settings().receipts or 0; return v >= 100 and 100 or v > 0 and 99 or 0 end, function(v) settings().receipts = v end)
	ui.receipts:SetPoint('TOPLEFT', 10, -150)
	ui.receipts:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:AddLine('Forged Delivery Receipts')
		GameTooltip:AddLine('A receipt (15 Merchant\'s Favor from the Uncertified Scribe, from Friendly) on an empty Waylaid Crate hands it in for 50 reputation. On: the plan uses crates in place of writs where that is cheaper or quicker. The Favor you hold is used first; for the rest, crates to fill and their bundles go on the buy list too. Crates only: no writs at all, and if too few crates are up the plan says how far they get you. Each hand-in pays 1s back, which is counted.', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	ui.receipts:HookScript('OnLeave', function() GameTooltip:Hide() end)
	row('Panel size', -86)
	local smaller = S.Button(op, 'A-', 34, 22, function() setScale(settings().scale - 0.05); refresh() end); smaller:SetPoint('TOPLEFT', 10, -102)
	local bigger = S.Button(op, 'A+', 34, 22, function() setScale(settings().scale + 0.05); refresh() end); bigger:SetPoint('LEFT', smaller, 'RIGHT', 4, 0)
	ui.sizeText = S.Text(op, 12, C.text); ui.sizeText:SetPoint('LEFT', bigger, 'RIGHT', 10, 0)
	local all = S.Button(op, 'All settings', 92, 20, function() op:Hide(); if ns.Options then ns.Options.Open() end end)
	all:SetPoint('TOPRIGHT', -8, -6)
	all:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:AddLine('All settings')
		GameTooltip:AddLine('Opens the addon\'s page in the game\'s options (Esc, Options, AddOns): item tooltips, the minimap button, the mailbox and bank reminder, the size of the panel.', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	all:HookScript('OnLeave', function() GameTooltip:Hide() end)
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
	local rcRow = not favor and ((settings().receipts or 0) > 0 or (settings().favorWant or 0) > 0 or ui.labelFill ~= nil)
	local key = favor and 'favor' or rcRow and 'receipts' or 'writs'
	if ui.laidOut ~= key then
		ui.laidOut = key
		if favor then
			if FAVOR_ONLY then
				ui.goal:Hide(); ui.reach:Hide(); ui.favorHint:Hide()
				put(ui.favorLabel, 'TOPLEFT', PAD, -78)
				put(ui.favorBox, 'TOPLEFT', PAD + 44, -72)
				put(ui.recipesBtn, 'TOPLEFT', ui.favorBox, 'TOPRIGHT', 8, 0)
				ui.scan:SetSize(IW - 44 - 64 - 8 - 72 - 8, 24); put(ui.scan, 'TOPLEFT', ui.recipesBtn, 'TOPRIGHT', 8, 0)
				put(ui.todayHead, 'TOPLEFT', PAD, -110)
			else
				ui.reach:Show()
				ui.goal:SetWidth(120); put(ui.goal, 'TOPLEFT', PAD + 44, -76)
				ui.scan:SetSize(IW - 44 - 120 - 6, 24); put(ui.scan, 'TOPLEFT', ui.goal, 'TOPRIGHT', 6, 0)
				put(ui.favorLabel, 'TOPLEFT', PAD, -110)
				put(ui.favorBox, 'TOPLEFT', PAD + 44, -104)
				put(ui.recipesBtn, 'TOPLEFT', ui.favorBox, 'TOPRIGHT', 8, 0)
				put(ui.favorHint, 'LEFT', ui.recipesBtn, 'RIGHT', 8, 0)
				put(ui.todayHead, 'TOPLEFT', PAD, -140)
			end
			put(ui.listHead, 'TOPLEFT', ui.trackText, 'BOTTOMLEFT', 0, -12)
		else
			ui.reach:Show()
			ui.goal:SetWidth(104); put(ui.goal, 'TOPLEFT', PAD + 44, -76)
			ui.days:SetWidth(104); put(ui.days, 'TOPLEFT', ui.goal, 'TOPRIGHT', 6, 0)
			ui.scan:SetSize(IW - 44 - 104 - 104 - 12, 24); put(ui.scan, 'TOPLEFT', ui.days, 'TOPRIGHT', 6, 0)
			put(ui.favorLabel, 'TOPLEFT', PAD, -110)
			put(ui.favorBox, 'TOPLEFT', PAD + 44, -104)
			put(ui.recipesBtn, 'TOPLEFT', ui.favorBox, 'TOPRIGHT', 8, 0)
			put(ui.favorHint, 'LEFT', ui.recipesBtn, 'RIGHT', 8, 0)
			put(ui.timeBits[2], 'TOPLEFT', PAD, -138)
			put(ui.timeBits[3], 'TOPRIGHT', -PAD, -138)
			ui.slider:SetWidth(IW - 130); put(ui.slider, 'TOP', ui.frame, 'TOP', 0, -136)
			put(ui.todayHead, 'TOPLEFT', PAD, -164)
			put(ui.listHead, 'TOPLEFT', ui.held, 'BOTTOMLEFT', 0, -12)
		end
		put(ui.box, 'TOPLEFT', ui.listHead, 'BOTTOMLEFT', 0, -8); ui.box:SetWidth(IW)
		put(ui.buy, 'TOPLEFT', ui.box, 'BOTTOMLEFT', 0, -10)
		put(ui.skip, 'TOPRIGHT', ui.box, 'BOTTOMRIGHT', 0, -10)
		put(ui.anyway, 'TOPRIGHT', ui.skip, 'TOPLEFT', -6, 0)
		ui.fill:SetSize(third, 28)
		ui.auto:SetSize(third, 28); put(ui.auto, 'TOPLEFT', ui.buy, 'BOTTOMLEFT', third + 8, -8)
		ui.way:SetSize(third, 28); put(ui.way, 'TOPLEFT', ui.auto, 'TOPRIGHT', 8, 0)
		ui.stamp:SetSize(third, 28)
		local rowsUnder = ((favor or rcRow) and 1 or 0) + (favor and 0 or 1)
		ui.guide:SetSize(half, 28); put(ui.guide, 'TOPLEFT', ui.buy, 'BOTTOMLEFT', 0, rcRow and -(8 + 28 + 8) or -8)
		ui.rxp:SetSize(half, 28); put(ui.rxp, 'TOPLEFT', ui.guide, 'TOPRIGHT', 8, 0)
		put(ui.status, 'TOPLEFT', ui.buy, 'BOTTOMLEFT', 0, rowsUnder > 0 and -(rowsUnder * 36 + 10) or -10)
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
		ui.stamp:ClearAllPoints()
		ui.stamp:SetPoint('TOPLEFT', f, 'TOPLEFT', PAD + third + 8, -math.floor(top - buyBottom + 8))
		for _, b in ipairs({ ui.fill, ui.stamp, ui.auto, ui.way, ui.guide, ui.rxp }) do
			local l = b.label
			local t = l and l:GetText()
			if t and t ~= '' then l:SetText(''); l:SetText(t) end
		end
		local h = math.floor(top - bottom + 12)
		f:SetHeight(h)
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
		local inMail = ((State.Char(db) or {}).mail or {})[lb.item]
		a.text:SetText(lb.held and 'Shipping Label: use it (click this), then hand it in to ' .. NPC_AT .. ' for +2,000 rep and 50 Favor (in the plan).'
			or lb.banked and 'Shipping Label: it is in your bank. Take it out, use it, and hand it in to ' .. NPC_AT .. ' for +2,000 rep.'
			or inMail and 'Shipping Label: it is in your mail. Take it out, use it, and hand it in to ' .. NPC_AT .. ' for +2,000 rep.'
			or lb.onQuest and 'Shipping Label: hand it in to ' .. NPC_AT .. ' for +2,000 rep (in the plan).'
			or 'Shipping Label not done: +2,000 rep and 50 Favor, once (in the plan). The first Waylaid Crate you fill gives it; hand it in to ' .. NPC_AT .. '.')
		a:Show()
		local th = a.text:GetStringHeight()
		a:SetHeight(math.max(40, ((th and th > 10) and th or 28) + 20))
	end
	ui.summary:ClearAllPoints()
	if a:IsShown() then ui.summary:SetPoint('TOPLEFT', a, 'BOTTOMLEFT', 0, -12) else ui.summary:SetPoint('TOPLEFT', ui.todayHead, 'BOTTOMLEFT', 0, -14) end
	local sc = mine().scope or 'day'
	ui.scopeBtn:SetText(sc == 'all' and 'Buy: every day' or 'Buy: today')
	ui.listHead:SetText(oneOff and ('BUY LIST  ' .. WHITE .. 'from the table: ' .. (oneOff.title or '') .. '|r') or ui.buyHead or 'BUY LIST')
	ui.drawHeld()
	local raw, standing, name = State.Rep()
	local goal = State.GOALS[settings().goal] or State.GOALS[1]
	local favor = mine().mode == 'favor'
	ui.title:SetText(FAVOR_ONLY and "Merchant's Favor" or 'Writs and Favors')
	ui.todayHead:SetText(favor and 'THIS PURCHASE' or 'PLAN')
	ui.trackText:SetText(ui.trackLine())
	ui.optsBtn:SetShown(not favor)
	if favor then ui.opts:Hide() end
	if ui.stock then ui.stock.update() end
	ui.sizeText:SetText(math.floor((settings().scale or 1) * 100 + 0.5) .. '%')
	if not favor then
		local tip
		if plan and plan.route then
			tip = { 'This plan', 'The gold on the first line is your cost after the hand-ins pay out: what you pay at the Auction House, less the writs\' coin pouches, the money for crates filled for Favor, and the 1s a receipt crate pays.' }
			if plan.payNow and (plan.payBack or 0) > 0 then
				tip[#tip + 1] = { 'Pay now', Plan.Money(plan.payNow) }
				tip[#tip + 1] = { 'Back at hand-in, about', Plan.Money(plan.payBack) }
			end
			tip[#tip + 1] = 'The minutes are the hand-in run: flights, rides and mailbox stops.'
			for _, m in ipairs(plan.more or {}) do tip[#tip + 1] = m end
		end
		ui.summaryTip = tip
	end
	ui.modeBtn:SetText(favor and 'Rep' or 'Favor')
	ui.guide:SetShown(not favor); ui.rxp:SetShown(not favor)
	ui.plan:Hide()
	ui.modeBtn:Hide()
	ui.goalHead:Hide()
	ui.held:SetShown(not favor)
	ui.minute:Hide()
	ui.layout(favor)
	ui.auto:SetShown(favor)
	ui.way:SetShown(favor)
	ui.auto:SetText(settings().autoHandIn ~= false and 'Auto hand-in: on' or 'Auto hand-in: off')
	ui.auto.label:SetTextColor(unpack(settings().autoHandIn ~= false and C.gold or C.muted))
	local rcOn = not favor and ((settings().receipts or 0) > 0 or (settings().favorWant or 0) > 0 or ui.labelFill ~= nil)
	if not InCombatLockdown() then ui.fill:SetShown(favor or rcOn); ui.stamp:SetShown(rcOn) end
	ui.fill.update(); ui.stamp.update()
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
	ui.goal.update(); ui.days.update(); ui.receipts.update(); ui.favorBox.update()
	ui.days:SetShown(not favor)
	ui.planRow:SetShown(not favor)
	ui.colourPlanRow()
	ui.scopeBtn:SetShown(not favor and (settings().days or 1) > 1 and not oneOff)
	for _, x in ipairs(ui.timeBits) do x:SetShown(not favor) end
	local now_ = GetServerTime and GetServerTime() or time()
	local age = favor and (db.favorAt and (('live prices %d min old'):format(math.floor((now_ - db.favorAt) / 60))) or 'no crate scan yet')
		or (db.scanAt and (('prices %d min old'):format(math.floor((now_ - db.scanAt) / 60))) or 'no scan yet')
	ui.status:SetText((status and ((statusErr and RED or GOLD) .. status .. '|r   ') or '') .. MUTED .. nb(age) .. '|r')
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
	if n == 0 and ui.listFrame.SetVerticalScroll then ui.listFrame:SetVerticalScroll(0) end
	local emptyText = plan and plan.reason and 'Nothing to buy.'
	if ui.mapSource == 'held' and mine().mode ~= 'favor' then emptyText = 'Nothing to buy: these are the writs you already hold.' end
	if not emptyText and plan and plan.shopping and #plan.shopping == 0 and mine().mode ~= 'favor' then
		emptyText = 'Nothing to buy: you already hold what this plan needs.' .. (ui.takeOut and ('\n\nFirst ' .. ui.takeOut .. '. Then Fill and Receipt light up.') or '')
	end
	ui.empty:SetText(emptyText or (mine().mode == 'favor' and 'Click Scan crates: your buy list shows here.' or 'Click Scan: your buy list shows here.'))
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
	plan = { reason = why, rows = rows }
	clearBuy()
	ui.buyHead = nil
	ui.summary:SetText(RED .. why .. '|r')
	ui.summaryTip = nil
	refresh(msg or why, true)
end

local function tooLow()
	local level = UnitLevel and UnitLevel('player') or 0
	if level <= 0 or level >= Plan.MIN_LEVEL then return false end
	noPlan(('You are level %d: writs and Waylaid Crates need level %d, so this character has nothing to plan. Open the panel on the character who will hand them in.'):format(level, Plan.MIN_LEVEL), 'Needs level ' .. Plan.MIN_LEVEL)
	return true
end

local function planNow()
	local raw = State.Rep()
	local goal = State.GOALS[settings().goal] or State.GOALS[2]
	local label = State.Label()
	local labelRep = label.done and 0 or label.rep
	local need = goal[2] - raw - labelRep
	if goal[2] - raw <= 0 then return noPlan(('You are already %s (%s). Pick a higher standing, or No reputation to plan Favor alone.'):format(goal[1], commas(raw)), 'Already at the goal') end
	if tooLow() then return end
	if need <= 0 then return noPlan(('The Shipping Label alone gets you to %s: %shand it in to ' .. NPC_AT .. ' (+2,000).'):format(goal[1], labelNeedsCrate(label) and 'fill any one Waylaid Crate to get it, then ' or ''), 'Shipping Label is enough') end
	ui.labelFill = nil
	local unread = useFlights()
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
	local allRows = rows
	local myLevel = UnitLevel and UnitLevel('player') or 0
	local toFriendly = math.max(0, State.GOALS[1][2] - raw - labelRep)
	local levelOut
	rows, levelOut = Plan.ForWrits({ rows = rows, level = myLevel, start = start, all = s.allZones, toFriendly = toFriendly, target = (s.receipts or 0) > 0 and toFriendly > 0 and toFriendly or need, days = s.days })
	local function ladder(id)
		local x = p[id]
		if not x then return nil end
		if x.ladder and #x.ladder > 0 then return x.ladder end
		if x.each then return { { x.each, x.up or 0 } } end
	end
	local heldOK, tooHigh, tooHighAt
	ladder, heldOK, tooHigh, tooHighAt = Plan.ForLevel(myLevel, ladder, state.items)
	label.needsCrate = labelNeedsCrate(label, (state.from or {}).mail) or nil
	local labelFavor = label.done and 0 or (label.favor or 0)
	do
		local function goalFor(n, today)
			if today and s.days > 1 then
				local g = Plan.Goal({ rows = rows, need = n, days = 1, perSec = s.minute / 60, start = start })
				if g.got >= n then return g end
			end
			return Plan.Goal({ rows = rows, need = n, days = s.days, perSec = s.minute / 60, start = start })
		end
		local cap = s.receipts or 0
		local rc, why, tries, base
		ui.tooHigh, ui.tooHighAt = nil, nil
		local favorWant = s.favorWant or 0
		if (cap > 0 or favorWant > 0) and need > 0 and D.dokimi then
			local R = Plan.RECEIPT
			local favorHeld = (State.Favor(db) or 0) + labelFavor
			ui.tooHigh, ui.tooHighAt = tooHigh, tooHighAt
			local rcHeld, heldSum = (C_Item and C_Item.GetItemCount or GetItemCount)(R.item, true) or 0, 0
			for _, c in ipairs(D.waylaid.crates) do
				heldSum = heldSum + (state.items[c[1]] or 0) * 7
				for _, o in ipairs(c[5]) do heldSum = heldSum + (state.items[o[1]] or 0) end
			end
			for _, t in pairs(D.waylaid.sealed) do for _, id in pairs(t) do heldSum = heldSum + (state.items[id] or 0) * 13 end end
			local key = table.concat({ need, s.days, s.minute, cap, math.floor(favorHeld / R.favor), rcHeld, heldSum, toFriendly, db.scanAt or 0, db.favorAt or 0, db.favorFullAt or 0, start, held, doneToday, myLevel, favorWant, tostring(s.allZones), ns.Net and ns.Net.Key() or '' }, ':')
			local kept = ui.rcKept and ui.rcKept.key == key and ui.rcKept.n or nil
			rc, why, tries, base = Plan.Receipts({ need = need, ladder = ladder, favorHeld = favorHeld, held = heldOK, receiptsHeld = rcHeld, extra = favorWant, max = cap <= 0 and 0 or nil, writsFirst = toFriendly, goalFor = goalFor, trip = Plan.TripCost(start, s.minute / 60, D.dokimi), only = cap >= 100, fixed = kept })
			if not kept then ns.Log(('receipts: %d Favor held; tried %s; %s'):format(favorHeld, table.concat((rc and rc.tries) or tries or {}, ', '), rc and ('chose ' .. rc.n) or ('none: ' .. tostring(why)))) end
			ui.rcKept = { key = key, n = rc and rc.n or 0 }
			if rc then
				plan = rc.goal
				rc.today, rc.favorHeld, rc.receiptsHeld, rc.writsFirst = rc.n, favorHeld, rcHeld, toFriendly
				plan.receipts = rc
				plan.need, plan.got, plan.gold = need, plan.got + rc.n * R.rep, plan.gold + rc.cost + rc.favorGold
				plan.days = { plan.days[1] and { day = 1, writs = plan.days[1].writs, rep = plan.days[1].rep, gold = plan.days[1].gold } or { day = 1, writs = {}, rep = 0, gold = 0 }, unpack(plan.days, 2) }
				plan.days[1].rep, plan.days[1].gold = plan.days[1].rep + rc.n * R.rep, plan.days[1].gold + rc.cost + rc.favorGold
			end
		end
		if not rc then
			if cap >= 100 and why and not why:find('Friendly', 1, true) then
				return noPlan(('Crates only, and no receipt crates can be planned: %s. Scan again, or allow writs (the cog).'):format(why), 'No crates to plan', rows)
			end
			plan = base or goalFor(need)
			plan.receiptWhy = why
		end
		plan.rows = allRows
	end
	ns.Log(('plan: level %d, %d writs left out for it'):format(myLevel, levelOut or 0))
	ns.Log(('plan: need %d, %d priced, %d plannable, %d handed in today (%d by the game, %d seen by us), %d picks, today max %d'):format(need, priced, plan.usable, doneToday, state.doneBy.flag, state.doneBy.ours, #plan.picks, plan.today))
	if plan.usable == 0 and not plan.receipts then
		if (levelOut or 0) > 0 then return noPlan(('No writ can be planned for level %d: %d are for higher levels or out of reach. Scan again later, or turn off "Only plan writ hand-ins for my level" (All settings).'):format(myLevel, levelOut), 'Nothing for your level', allRows) end
		return noPlan(('No writ can be planned: %d priced with %d+ up (writ and item), none with a known hand-in. Try Scan again.'):format(priced, s.stock), 'Nothing to plan', rows)
	end
	local day = plan.days[1]
	if not day or (#day.writs == 0 and not plan.receipts) then
		if plan.today == 0 then return noPlan(('Nothing to plan today: all %d writs you could do are handed in today. Scan again after the daily reset.'):format(plan.doneToday), 'Nothing to plan today', rows) end
		return noPlan(('Nothing planned for today (%d writs could be). /writs debug says more.'):format(plan.usable), 'Nothing to plan today', rows)
	end
	local _, class = UnitClass('player')
	local stage1 = plan.receipts and plan.receipts.n > 0 and (plan.receipts.favorShort or 0) > 0 and plan.receipts.favorPlan and true or false
	plan.stage = stage1 and 1 or (plan.receipts and plan.receipts.n > 0 and 2) or nil
	local labelPlan
	if label.needsCrate then
		local fills = plan.receipts and plan.receipts.favorPlan and #plan.receipts.favorPlan.crates > 0
		if not fills then
			labelPlan = Plan.LabelCrate(ladder, heldOK, plan.receipts and plan.receipts.units)
			if labelPlan then ui.labelFill = labelPlan.crates end
		end
	end
	local favorOnlyCrates, favorOnlySlots
	if labelPlan and not (plan.receipts and plan.receipts.n > 0 and not stage1) then
		favorOnlyCrates, favorOnlySlots = Guide.CrateGroups(labelPlan.crates), 2
	end
	if plan.receipts and (plan.receipts.n == 0 or stage1) and plan.receipts.favorPlan and #plan.receipts.favorPlan.crates > 0 and Guide and Guide.CrateGroups then
		favorOnlyCrates, favorOnlySlots = Guide.CrateGroups(plan.receipts.favorPlan.crates), 0
		for _, c in ipairs(plan.receipts.favorPlan.crates) do favorOnlySlots = favorOnlySlots + math.ceil(c.count / 5) + #(c.bundles or {}) end
	end
	plan.route = Plan.Route({ writs = day.writs, level = myLevel, start = start, bags = bagCap(), hearth = State.Hearth(), druid = class == 'DRUID', mage = class == 'MAGE', label = not label.done and label or nil, receipts = not stage1 and plan.receipts and plan.receipts.today or nil, receiptFill = not stage1 and plan.receipts and (labelPlan and labelPlan.crates or plan.receipts.favorPlan and plan.receipts.favorPlan.crates) or nil, crates = favorOnlyCrates, crateSlots = favorOnlySlots, receiptsLast = not stage1 and plan.receipts and (plan.receipts.writsFirst or 0) > 0 or nil })
	local scope = mine().scope or 'day'
	plan.shopping = Plan.Shopping(scope == 'all' and plan.days or { day }, p, state.held, state.items)
	if plan.receipts then
		local rc = plan.receipts
		local want, order, empties = {}, {}, {}
		local function add(id, n) if not want[id] then want[id] = 0; order[#order + 1] = id end; want[id] = want[id] + n end
		for _, u in ipairs(stage1 and {} or rc.units) do
			if not u.held then add(u.id, 1); empties[u.id] = (empties[u.id] or 0) + 1 end
		end
		if rc.favorPlan then for _, b in ipairs(rc.favorPlan.buy) do if (b.units or 0) > 0 then add(b.item, b.units) end end end
		for _, id in ipairs(order) do
			local n = want[id]
			local cost = Plan.CostOf(p[id], n)
			plan.shopping[#plan.shopping + 1] = { id = id, name = (D.waylaid.names and D.waylaid.names[id]) or ('item ' .. id), need = n, cost = cost, each = cost and math.floor(cost / n + 0.5) or nil,
				repText = empties[id] and ('+' .. (empties[id] * Plan.RECEIPT.rep) .. ' rep') or 'for Favor' }
		end
	end
	if labelPlan then
		for _, b in ipairs(labelPlan.buy) do
			if (b.units or 0) > 0 then
				local line
				for _, e in ipairs(plan.shopping) do if e.id == b.item then line = e end end
				if line then
					line.need = line.need + b.units
					line.cost = Plan.CostOf(p[b.item], line.need)
					line.each = line.cost and math.floor(line.cost / line.need + 0.5) or nil
				else
					plan.shopping[#plan.shopping + 1] = { id = b.item, name = (D.waylaid.names and D.waylaid.names[b.item]) or ('item ' .. b.item), need = b.units, cost = b.cost, each = math.floor(b.cost / b.units + 0.5), repText = 'for the Label' }
				end
			end
		end
		plan.gold = plan.gold + labelPlan.cost
		day = { day = 1, writs = day.writs, rep = day.rep, gold = day.gold + labelPlan.cost }
	end
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
	ui.buyHead = ('BUY LIST  %s%d to buy, %s|r'):format(WHITE, lines, Plan.Money(spend))
	local short = plan.got < need
	local span = whenText(s.days)
	local rc = plan.receipts
	local nCrates = rc and rc.n or 0
	local what = {}
	if nCrates > 0 then what[#what + 1] = nCrates .. (nCrates == 1 and ' crate' or ' crates') end
	if #day.writs > 0 or nCrates == 0 then what[#what + 1] = #day.writs .. (#day.writs == 1 and ' writ' or ' writs') end
	local head = table.concat({ nb((s.days > 1 and 'Today: ' or '') .. table.concat(what, ' + ')), nb('+' .. commas(day.rep) .. ' rep'), nb(Plan.Money(day.gold)), nb(math.floor(plan.route.total / 60 + 0.5) .. ' min') }, DOT)
	local favorTail = (rc and (s.favorWant or 0) > 0) and (', with %s Favor'):format(commas(s.favorWant)) or ''
	local goalLine
	if short and rc and (s.receipts or 0) >= 100 then
		goalLine = RED .. ('Crates only: the crates up now give +%s of the %s to %s. Scan again later, or allow writs (the cog).|r'):format(commas(plan.got), commas(need), goal[1])
	elseif short then
		goalLine = RED .. ('Short of %s %s: +%s of %s%s. A writ is once a day: about %s days.|r'):format(goal[1], span, commas(plan.got), commas(need), labelRep > 0 and ' after the Shipping Label' or '', tostring(plan.daysNeeded or '?'))
	elseif s.days > 1 then
		goalLine = GREEN .. ('Reaches %s %s%s: %s in all.|r'):format(goal[1], span, favorTail, Plan.Money(plan.gold))
	else
		goalLine = GREEN .. ('Reaches %s today%s.|r'):format(goal[1], favorTail)
	end
	local todo, more = {}, {}
	if label.needsCrate and not (plan.receipts and plan.receipts.favorPlan and #plan.receipts.favorPlan.crates > 0) then
		todo[#todo + 1] = GOLD .. ('Fill 1 Waylaid Crate%s: it gives the Shipping Label (+2,000 rep, +50 Favor).|r'):format(labelPlan and ' (Fill)' or ' (none priced: Scan)')
	end
	for _, l in ipairs(warnLines(day.writs, myLevel)) do todo[#todo + 1] = l end
	if unread > 0 and myLevel > 0 and myLevel < 60 then
		todo[#todo + 1] = MUTED .. 'Open a flight master\'s map on each continent so the route uses only the flights you have.|r'
	end
	if (levelOut or 0) > 0 then more[#more + 1] = { 'Left out for your level or reach', levelOut .. ' writs' } end
	more[#more + 1] = { 'From', D.nodes[start][1] }
	more[#more + 1] = { 'Flights', Plan.Money(plan.route.fares) }
	do
		local back = 0
		for _, w in ipairs(scope == 'all' and plan.picks or day.writs) do back = back + (w.pouch or 0) * (scope == 'all' and (w.days or 1) or 1) end
		if rc then
			back = back + rc.n * Plan.RECEIPT.back
			if rc.favorPlan then back = back + (rc.favorPlan.back or 0) end
		end
		plan.payNow, plan.payBack = spend, back
	end
	if s.days > 1 then
		local buys = 0
		for _, pk in ipairs(plan.picks) do buys = buys + pk.days end
		more[#more + 1] = { 'Writ hand-ins in all', tostring(buys) }
	end
	if doneToday > 0 then more[#more + 1] = { 'Handed in today already', tostring(doneToday) } end
	if plan.receiptWhy and (s.receipts or 0) > 0 then todo[#todo + 1] = GOLD .. 'No receipt crates in this plan: ' .. plan.receiptWhy .. '.|r' end
	if (ui.tooHigh or 0) > 0 then more[#more + 1] = ('%d of your crates need level %d: left out.'):format(ui.tooHigh, ui.tooHighAt or 0) end
	ui.receiptFill, ui.receiptN, ui.takeOut = nil, nil, nil
	if rc then
		ui.receiptFill, ui.receiptN = rc.favorPlan and rc.favorPlan.crates or nil, not stage1 and rc.n or 0
		if rc.n > 0 then more[#more + 1] = { 'Receipts', ('%d, %s Favor'):format(rc.n, commas(rc.favor)) } end
		if (rc.writsFirst or 0) > 0 then todo[#todo + 1] = GOLD .. ('Writs first: receipts are sold from Friendly (%s to go).|r'):format(commas(rc.writsFirst)) end
		do
			local mineC = 0
			for _, u in ipairs(rc.units) do if u.held then mineC = mineC + 1 end end
			local got = {}
			if mineC > 0 then got[#got + 1] = mineC .. ' crates' end
			if (rc.receiptsHeld or 0) > 0 then got[#got + 1] = math.min(rc.receiptsHeld, rc.n) .. ' receipts' end
			if #got > 0 then more[#more + 1] = { 'Yours already', table.concat(got, ', ') } end
		end
		do
			local want, isCrateId = {}, {}
			for _, c in ipairs(D.waylaid.crates) do isCrateId[c[1]] = true end
			for _, u in ipairs(stage1 and {} or rc.units) do if u.held and u.id then want[u.id] = (want[u.id] or 0) + 1 end end
			if rc.favorPlan then
				for _, c in ipairs(rc.favorPlan.crates or {}) do
					want[c.id] = (want[c.id] or 0) + c.count
					for _, b in ipairs(c.bundles or {}) do want[b.item] = (want[b.item] or 0) + (b.n or 0) * (b.count or 0) end
				end
				for _, b in ipairs(rc.favorPlan.buy or {}) do if want[b.item] then want[b.item] = want[b.item] - (b.units or 0) end end
			end
			local from = state.from or {}
			local out = { mail = { 0, 0 }, bank = { 0, 0 } }
			for id, n in pairs(want) do
				local left = n - ((from.bags or {})[id] or 0)
				for _, src in ipairs({ 'mail', 'bank' }) do
					local take = math.max(0, math.min(left, (from[src] or {})[id] or 0))
					if take > 0 then local o = out[src]; o[isCrateId[id] and 1 or 2] = o[isCrateId[id] and 1 or 2] + take; left = left - take end
				end
			end
			local parts = {}
			for _, src in ipairs({ 'mail', 'bank' }) do
				local o, t = out[src], {}
				if o[1] > 0 then t[#t + 1] = o[1] .. (o[1] == 1 and ' crate' or ' crates') end
				if o[2] > 0 then t[#t + 1] = o[2] .. ' items to fill them' end
				if #t > 0 then parts[#parts + 1] = table.concat(t, ' and ') .. ' from the ' .. src end
			end
			ui.takeOut = #parts > 0 and ('take ' .. table.concat(parts, ', ')) or nil
			if ui.takeOut then todo[#todo + 1] = GOLD .. 'First ' .. ui.takeOut .. '.|r' end
		end
		if rc.favorShort > 0 then
			local fill = 0
			for _, c in ipairs(rc.favorPlan and rc.favorPlan.crates or {}) do fill = fill + c.count end
			plan.fillN = fill
			if fill > 0 and not stage1 then todo[#todo + 1] = GOLD .. ('Fill %d crate%s for the Favor.|r'):format(fill, fill == 1 and '' or 's') end
		elseif rc.n > 0 then
			local buyR = math.max(0, rc.n - (rc.receiptsHeld or 0))
			if labelFavor > 0 and (State.Favor(db) or 0) < buyR * Plan.RECEIPT.favor then todo[#todo + 1] = GOLD .. 'Hand in the Shipping Label first: its 50 Favor is counted.|r' end
			todo[#todo + 1] = GOLD .. ('You have the Favor. Leave these crates empty: %sput one on each (Receipt) and hand them in.|r')
				:format(buyR > 0 and ('buy %d receipts from the Scribe (%s Favor), '):format(buyR, commas(buyR * Plan.RECEIPT.favor)) or '')
		end
	end
	if fb > 0 then more[#more + 1] = { 'Prices from Auctionator/TSM', fb .. ' (Scan for live ones)' } end
	if labelRep > 0 then more[#more + 1] = { 'Shipping Label', '+2,000, counted' }; more[#more + 1] = { 'Its Favor', '+' .. labelFavor .. ', counted' } end
	do
		local free = State.FreeSlots()
		if free and free < 12 then todo[#todo + 1] = RED .. 'Only ' .. free .. ' free bag slots: more mailbox stops.|r' end
	end
	if #plan.shopping > 50 then todo[#todo + 1] = RED .. 'Over 50 purchases: the mailbox shows 50 at a time, the rest arrive as you make space.|r' end
	plan.more = more
	do
		local lines = { WHITE .. head .. '|r', goalLine }
		if stage1 then
			local mins = math.floor(plan.route.total / 60 + 0.5)
			local bits = { nb(('Step 1 of 2: get %s Favor'):format(commas(rc.favorShort))), nb(('fill %d crates'):format(plan.fillN or 0)) }
			if #day.writs > 0 then bits[#bits + 1] = nb(#day.writs .. (#day.writs == 1 and ' writ' or ' writs')) end
			bits[#bits + 1] = nb(mins .. ' min')
			lines = { WHITE .. table.concat(bits, DOT) .. '|r',
				GOLD .. 'Buy the list, fill these crates and hand them in.|r',
				MUTED .. ('Step 2, once you have the Favor: %d empty crates for receipts (+%s rep). Scan again then.|r'):format(rc.n, commas(rc.n * Plan.RECEIPT.rep)),
				goalLine }
		end
		for _, t in ipairs(todo) do lines[#lines + 1] = t end
		ui.summary:SetText(table.concat(lines, '\n'))
	end
	startBuy(plan.shopping, refresh, {
		done = 'All bought. Now Guide me takes you round the hand-ins, or Send to RestedXP.',
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
	if not route then return refresh('Scan first: there is no plan yet', true) end
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
	local favorHeldNow = State.Favor(db) or 0
	if tooLow() then return end
	local want = s.favorWant or (FAVOR_ONLY and (favorHeldNow + (s.favorGoal or 100))) or 0
	if want <= 0 then return noPlan(FAVOR_ONLY and 'Type the Favor you want to have in the box above.' or 'Nothing asked for: pick a standing to reach, or type the Favor you want to have.', 'Nothing to plan') end
	if want <= favorHeldNow then return noPlan(('You already have %s Favor. Type a higher number to get more.'):format(commas(favorHeldNow)), 'Favor already held') end
	local lbl = State.Label()
	local bonus = lbl.done and 0 or (lbl.favor or 0)
	local need = math.max(1, want - favorHeldNow - bonus)
	useFlights()
	local p = {}
	for id, v in pairs(db.prices or {}) do p[id] = v end
	local st = State.Read(db)
	local lad, heldOK = Plan.ForLevel(UnitLevel and UnitLevel('player') or 0, ladderOf(p), st.items)
	local fp = Plan.Favor({ need = need, ladder = lad, held = heldOK })
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
	ui.summary:SetText(('%s%d crate%s for +%s Merchant\'s Favor|r\nCost to buy: %s%s|r\nBack from hand-ins: %s%s|r\n%s%s|r%s')
		:format(WHITE, crates, crates == 1 and '' or 's', commas(fp.got), GOLD, Plan.Money(spend), GREEN, Plan.Money(fp.back),
			MUTED, age and ('Prices: ' .. age .. ' min old') or 'Prices: no crate scan yet (Scan crates)',
			fp.short and ('\n' .. RED .. ('Only %s Favor of crates up now (of %s).'):format(commas(fp.got), commas(need)) .. '|r') or '') .. (bonus > 0 and ('\n' .. GOLD .. ('+%d from the Shipping Label: the first crate you fill gives it, hand it in too.|r'):format(bonus)) or '') .. (function()
				local fh = Plan.FillHeld(lad, heldOK)
				plan.fillHeld = fh
				if not fh then return '' end
				local bought = {}
				for _, b in ipairs(fp.buy) do bought[b.item] = (bought[b.item] or 0) + (b.units or 0) end
				local used = 0
				for _, c in ipairs(fp.crates) do used = used + math.max(0, c.count - (bought[c.id] or 0)) end
				fh.used = used
				local s1 = ('\n%sYour %d empty crates: this plan fills %d of them.|r'):format(MUTED, fh.held, used)
				if fh.fill > 0 then
					s1 = s1 .. ('\n%sFilling %s: +%s Favor for %s (%s a Favor).|r'):format(MUTED, fh.fill == fh.held and 'them all' or (fh.fill .. ' of them'), commas(fh.favor), Plan.Money(fh.cost), Plan.Money(fh.perFavor))
				end
				return s1
			end)())
	local tip = { 'This purchase' }
	for _, c in ipairs(fp.crates) do tip[#tip + 1] = { ('%d x %s %s'):format(c.count, (c.tier:gsub('^%l', string.upper)), c.type), Plan.Money(c.perFavor) .. ' a Favor' } end
	if fp.sealed > 0 then tip[#tip + 1] = { 'Sealed crates held', '+' .. fp.sealed .. ' Favor' } end
	tip[#tip + 1] = { 'Net cost', Plan.Money(fp.cost) .. ' (' .. Plan.Money(fp.got > 0 and fp.cost / fp.got or 0) .. ' a Favor)' }
	if plan.fillHeld then
		local fh = plan.fillHeld
		tip[#tip + 1] = 'Your crates count as free, so the plan fills one of yours whenever that is the cheapest Favor. Where it buys another kind instead, that crate and its bundle together cost less than the bundle for yours.'
		tip[#tip + 1] = { 'Empty crates you hold', tostring(fh.held) }
		tip[#tip + 1] = { 'Filled by this plan', tostring(fh.used or 0) }
		if fh.fill > 0 then tip[#tip + 1] = { 'Filling ' .. fh.fill .. ' of yours', '+' .. commas(fh.favor) .. ' Favor, ' .. Plan.Money(fh.cost) } end
		if fh.sell > 0 then tip[#tip + 1] = { 'Sold instead, about', Plan.Money(fh.sell) .. ' (at the cheapest listing, 1s each to post)' } end
	end
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
	ui.mapSource = 'held'
	refresh(('%d crates held: this route, %d min, +%s Favor (filled ones; unfilled need their bundle)'):format(n, math.floor(ui.heldRoute.total / 60 + 0.5), commas(favor)))
end

local function debugDump()
	local function say(s) DEFAULT_CHAT_FRAME:AddMessage('|cff33ccffWrits:|r ' .. s) end
	local raw, standing, name = State.Rep()
	local goal = State.GOALS[settings().goal] or State.GOALS[2]
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
		ui.doPlan = function()
			if mine().mode == 'favor' then return doFavor() end
			if ui.mapSource == 'held' then routeHeld() end
			if ui.mapSource ~= 'held' then doPlan() end
		end
		ui.routeHeld = function(show) if mine().mode == 'favor' then favorHeld() else routeHeld(show) end end
		ui.sendToRXP, ui.drawHeld, ui.favorScan = sendToRXP, ui_drawHeld, favorScan
		ui.layout = function(favor)
			local ok, e = pcall(layout, favor)
			if not ok then ns.Log('layout error: ' .. tostring(e)); ui.laidOut = nil end
		end
		ui.writsStage2, ui.replanSoon, ui.waypoint = writsStage2, replanSoon, waypoint
		ui.trackFor, ui.trackLine = trackFor, trackLine
		if ns.OnBuild then pcall(ns.OnBuild, ui) end
	end
	if show == nil then show = not ui.frame:IsShown() end
	if show == (ui.frame:IsShown() and true or false) then if show then dock(); refresh() end return end
	if inFight() then return end
	if show then
		dock(); ui.frame:Show(); refresh()
		if ns.Tour and not FAVOR_ONLY and mine().mode ~= 'favor' then ns.Tour.Auto() end
	else ui.frame:Hide() end
end

local regen = CreateFrame('Frame')
regen:RegisterEvent('PLAYER_REGEN_ENABLED')
regen:SetScript('OnEvent', function()
	if ui and ui.showAfterCombat then ui.showAfterCombat, ui.hidForMap = nil, nil; ui.frame:Show(); refresh() end
end)
local atMail = false
local ev = CreateFrame('Frame')
ev:RegisterEvent('ADDON_LOADED')
ev:RegisterEvent('AUCTION_HOUSE_SHOW')
ev:RegisterEvent('MAIL_INBOX_UPDATE')
ev:RegisterEvent('MAIL_SHOW')
ev:RegisterEvent('MAIL_CLOSED')
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
		if FAVOR_ONLY then mine().mode = 'favor' else mine().mode = settings().goal == 0 and 'favor' or 'writs' end
	elseif event == 'AUCTION_HOUSE_SHOW' then
		if ns.Blocked and ns.Blocked(true) then return end
		toggle(true)
		if not plan then ui.doPlan() end
	elseif event == 'MAIL_SHOW' then atMail = true
	elseif event == 'MAIL_CLOSED' then atMail = false
	elseif event == 'MAIL_INBOX_UPDATE' and db then
		if not atMail then return end
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
				local can = 0
				for _, o in ipairs(c[5]) do can = can + math.floor((GetItemCount_(o[1]) or 0) / o[2]) end
				left = left + math.min(n, can)
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
		if (UnitCastingInfo and UnitCastingInfo('player')) or (UnitChannelInfo and UnitChannelInfo('player')) then pick = nil end
		self:SetAttribute('macrotext', pick and ('/use item:' .. pick.crate .. '\n/use item:' .. pick.item .. '\n/click StaticPopup1Button1') or '')
		if pick then ns.Log(('fill: crate %d with %d x %d'):format(pick.crate, pick.n, pick.item)) end
	end)
	b:SetScript('PostClick', function() C_Timer.After(0.5, function() if ui then ui.fill.update() end end) end)
	b:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine('Fill your Waylaid Crates')
		GameTooltip:AddLine('Click again and again: each click fills the next crate in your bags with a bundle you have.', 1, 1, 1, true)
		if self.pick then GameTooltip:AddLine('Next: ' .. (D.waylaid.names[self.pick.crate] or '') .. ' with ' .. self.pick.n .. ' ' .. (D.waylaid.names[self.pick.item] or ''), 0.6, 0.6, 0.6, true) end
		if ui and ui.receiptFill and Guide and Guide.FillLines and not FAVOR_ONLY and mine().mode ~= 'favor' then
			local lines, nFill = Guide.FillLines(ui.receiptFill)
			GameTooltip:AddLine(' ')
			GameTooltip:AddLine(('This plan fills %d crates, for the Favor its receipts cost:'):format(nFill), 1, 0.82, 0.25, true)
			for _, l in ipairs(lines) do GameTooltip:AddLine(l, 1, 1, 1, true) end
			GameTooltip:AddLine(('Your other %d crates stay empty: they get the receipts. Fill only fills a crate whose items are in your bags, so it fills exactly these.'):format(ui.receiptN or 0), 0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript('OnLeave', function() GameTooltip:Hide() end)
	b:Hide()
	return b
end
local function nextStamp()
	local R = Plan.RECEIPT
	local have = GetItemCount_(R.item) or 0
	local empties, pick, spare = 0, nil, nil
	for _, c in ipairs(D.waylaid.crates) do
		local n = GetItemCount_(c[1]) or 0
		if n > 0 then
			empties = empties + n
			local fillable = false
			for _, o in ipairs(c[5]) do if (GetItemCount_(o[1]) or 0) >= o[2] then fillable = true; break end end
			if not fillable then pick = pick or c[1] else spare = spare or c[1] end
		end
	end
	return (have > 0 and (pick or spare)) or nil, math.min(have, empties), have, empties, pick ~= nil
end
ns.NextFill, ns.NextStamp = nextFill, nextStamp -- (Macro.lua)
function ui_stampButton(parent, w)
	local b = CreateFrame('Button', PREFIX .. 'Stamp', parent, 'SecureActionButtonTemplate')
	b:SetSize(w, 28)
	b:RegisterForClicks('AnyUp', 'AnyDown')
	b:SetAttribute('type', 'macro')
	S.Box(b, C.panel, { C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6, 1 })
	b.label = S.Text(b, 12, C.gold, 'CENTER'); b.label:SetPoint('CENTER'); b.label:SetWidth(math.max(1, w - 8)); b.label:SetWordWrap(false)
	b:SetScript('OnSizeChanged', function(self, bw) if bw and bw > 8 then self.label:SetWidth(bw - 8) end end)
	b.label:SetText('Receipt: none')
	b.update = function()
		local crate, left, have, empties = nextStamp()
		b.label:SetText(crate and ('Receipt: ' .. left .. ' left') or 'Receipt: none')
		b.label:SetTextColor(unpack(crate and C.gold or C.muted))
		b.crate, b.have, b.empties = crate, have, empties
	end
	b:SetScript('PreClick', function(self)
		if InCombatLockdown() then return end
		local crate = nextStamp()
		if (UnitCastingInfo and UnitCastingInfo('player')) or (UnitChannelInfo and UnitChannelInfo('player')) then crate = nil end
		self:SetAttribute('macrotext', crate and ('/use item:' .. Plan.RECEIPT.item .. '\n/use item:' .. crate .. '\n/click StaticPopup1Button1') or '')
		if crate then ns.Log('receipt: onto crate ' .. crate) end
	end)
	b:SetScript('PostClick', function() C_Timer.After(0.5, function() if ui then ui.stamp.update() end end) end)
	b:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine('Forged Delivery Receipt')
		GameTooltip:AddLine('Each click puts a receipt from your bags onto an empty Waylaid Crate. Hand the crate in for 50 reputation. Fill the crates you bought for Favor first: a crate with its bundle in your bags is left for last.', 1, 1, 1, true)
		GameTooltip:AddLine(('In your bags: %d receipts, %d unfilled crates'):format(self.have or 0, self.empties or 0), 0.6, 0.6, 0.6, true)
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
	ui.stamp.update()
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
local tried, lastBags = {}, nil
local QUEST_OF = {}
for _, c in ipairs(D.waylaid.crates) do QUEST_OF[c[1]] = D.waylaid.quests[c[3]] and D.waylaid.quests[c[3]][c[2]] end
local function stampedOf() local c = db and State.Char(db); if not c then return {} end; c.stamped = c.stamped or {}; return c.stamped end
local function receiptsOn() return not FAVOR_ONLY and db and db.settings and (db.settings.receipts or 0) > 0 end
local function watchStamps()
	local now = { r = GetItemCount_(Plan.RECEIPT.item) or 0 }
	for id in pairs(QUEST_OF) do now[id] = GetItemCount_(id) or 0 end
	local away = (MailFrame and MailFrame.IsShown and MailFrame:IsShown()) or (BankFrame and BankFrame.IsShown and BankFrame:IsShown())
	if lastBags and now.r < lastBags.r and not away then
		local used = lastBags.r - now.r
		local st = stampedOf()
		for id, q in pairs(QUEST_OF) do
			local gone = math.min(used, (lastBags[id] or 0) - now[id])
			if gone > 0 then st[q] = (st[q] or 0) + gone; used = used - gone; ns.Log(('receipt: %d onto crate %d (quest %d)'):format(gone, id, q)) end
		end
	end
	lastBags = now
	for q in pairs(tried) do tried[q] = nil end
end
local stampWatch = CreateFrame('Frame')
stampWatch:RegisterEvent('BAG_UPDATE_DELAYED')
stampWatch:RegisterEvent('PLAYER_ENTERING_WORLD')
stampWatch:SetScript('OnEvent', function() pcall(watchStamps) end)
local RECEIPT_QUEST = 93862
HANDIN[RECEIPT_QUEST] = true
local function canHandIn(q)
	if not HANDIN[q] then return false end
	if q == RECEIPT_QUEST then return not tried[q] end
	local item = SEALED_OF[q]
	if item then return (GetItemCount_(item) or 0) > 0 end
	local lb = State.Label()
	return lb.quest == q and not lb.done and (lb.held or lb.onQuest) or false
end
ns.CanHandIn = canHandIn
local qf = CreateFrame('Frame')
local function lookAgain(n)
	if not (C_Timer and C_GossipInfo) then return end
	C_Timer.After(0.4, function()
		if not autoOn() then return end
		local av = C_GossipInfo.GetAvailableQuests() or {}
		for _, q in ipairs(av) do
			if canHandIn(q.questID) then ns.Log('hand-in: quest ' .. q.questID .. ' picked on a second look'); return C_GossipInfo.SelectAvailableQuest(q.questID) end
		end
		if n > 1 then return lookAgain(n - 1) end
		if GossipFrame and GossipFrame:IsShown() and #av == 0 then tried[RECEIPT_QUEST] = true; ns.Log('hand-in: nothing offered, no receipt crate left') end
	end)
end
for _, e in ipairs({ 'GOSSIP_SHOW', 'QUEST_GREETING', 'QUEST_DETAIL', 'QUEST_PROGRESS', 'QUEST_COMPLETE' }) do qf:RegisterEvent(e) end
qf:SetScript('OnEvent', function(_, event)
	if event == 'QUEST_DETAIL' and db and db.settings and db.settings.autoHandIn ~= false and not IsShiftKeyDown() then
		local lb = State.Label()
		if not lb.done and GetQuestID and GetQuestID() == lb.quest then ns.Log('Shipping Label: quest taken'); return AcceptQuest() end
	end
	if not autoOn() then return end
	do
		local sealed = 0
		for _, item in pairs(SEALED_OF) do sealed = sealed + (GetItemCount_(item) or 0) end
		local act, av = '-', '-'
		if event == 'GOSSIP_SHOW' and C_GossipInfo then act, av = #(C_GossipInfo.GetActiveQuests() or {}), #(C_GossipInfo.GetAvailableQuests() or {})
		elseif event == 'QUEST_GREETING' then act, av = GetNumActiveQuests() or 0, GetNumAvailableQuests() or 0 end
		qf.lastWindow = GetTime()
		ns.Log(('hand-in window: %s quest %s, %s active, %s available, %d Sealed held'):format(event, tostring(GetQuestID and GetQuestID() or '-'), tostring(act), tostring(av), sealed))
	end
	local ok, err = pcall(function()
		if event == 'GOSSIP_SHOW' and C_GossipInfo then
			for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
				if canHandIn(q.questID) and q.isComplete ~= false then return C_GossipInfo.SelectActiveQuest(q.questID) end
			end
			for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
				if canHandIn(q.questID) then return C_GossipInfo.SelectAvailableQuest(q.questID) end
			end
			do
				local ids = {}
				for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do ids[#ids + 1] = tostring(q.questID) end
				for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do ids[#ids + 1] = 'on ' .. tostring(q.questID) end
				ns.Log('hand-in: nothing picked; offered: ' .. (#ids > 0 and table.concat(ids, ', ') or 'none') .. (tried[RECEIPT_QUEST] and ' (receipt quest left alone)' or ''))
			end
			lookAgain(3)
		elseif event == 'QUEST_GREETING' then
			for i = 1, GetNumActiveQuests() do
				local id = GetActiveQuestID and GetActiveQuestID(i)
				if id and canHandIn(id) then return SelectActiveQuest(i) end
			end
			for i = 1, GetNumAvailableQuests() do
				local id = select(5, GetAvailableQuestInfo(i))
				if id and canHandIn(id) then return SelectAvailableQuest(i) end
			end
			tried[RECEIPT_QUEST] = true
		elseif HANDIN[GetQuestID() or 0] then
			if event == 'QUEST_DETAIL' then AcceptQuest()
			elseif event == 'QUEST_PROGRESS' then
				if IsQuestCompletable() then CompleteQuest()
				else
					ns.Log('auto hand-in: quest ' .. tostring(GetQuestID()) .. ' can\'t be completed, left')
					local q = GetQuestID()
					if q then tried[q] = true; local st = stampedOf(); st[q] = nil end
					if DeclineQuest then DeclineQuest() elseif CloseQuest then CloseQuest() end
				end
			elseif event == 'QUEST_COMPLETE' then
				if (GetNumQuestChoices() or 0) <= 1 then
					GetQuestReward(1); ns.Log('handed in quest ' .. GetQuestID())
					do
						local q, st = GetQuestID(), stampedOf()
						if (st[q] or 0) > 0 and (GetItemCount_(SEALED_OF[q] or 0) or 0) == 0 then st[q] = st[q] > 1 and st[q] - 1 or nil end
					end
					local at = GetTime()
					qf.lastWindow = at
					C_Timer.After(0.4, function()
						if qf.lastWindow ~= at or not ns.Macro then return end
						local function more()
							for q in pairs(SEALED_OF) do if canHandIn(q) then return true end end
							if canHandIn(RECEIPT_QUEST) then return true end
							return false
						end
						if more() then ns.Macro.TalkOn(more) end
					end)
					C_Timer.After(1.5, function()
						if qf.lastWindow == at then ns.Log('hand-in: no window came back by itself after that one') end
					end)
				else ns.Log('hand-in: a reward to choose, left to you') end
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
	parts = function() return ui end,
	setFavorWant = function(v) if ui and ui.setFavorWant then ui.setFavorWant(v) elseif db then db.settings.favorWant = math.max(0, math.floor(tonumber(v) or 0)) end end,
	setScale = function(v) setScale(v) end,
	resetPos = function() settings().pos = nil; if ui then dock() end end,
	refresh = function() if ui then refresh() end end,
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
