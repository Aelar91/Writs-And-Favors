local ADDON, ns = ...
if ns.EDITION == 'favor' then return end
local D, Guide, State, S = ns.D, ns.Guide, ns.State, ns.Skin
local C = S.colors
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local Nav = {}
ns.Nav = Nav

local STAR = 1
local NEAR = 4 -- map units (a hundredth of the map across) that count as there
local win, nav, ttPin -- the window; the saved state { steps, at, name, day }; TomTom's waypoint
local function say(msg) print('|cffffc840Writs and Favors|r: ' .. msg) end
local function log(msg) if ns.Log then ns.Log('guide: ' .. msg) end end
local function hex(c) return ('|cff%02x%02x%02x'):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local GOLD, MUTED, GREEN = hex(C.gold), hex(C.muted), hex(C.green)

local function store()
	local db = ns.db
	if not db then return nil end
	return State.Char(db)
end
local function step() return nav and nav.steps[nav.at] end
local writQuest = {}
for _, w in ipairs(D.writs) do writQuest[w[2]] = w end

local function here()
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player')
	local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, 'player')
	if not pos then return map end
	local x, y
	if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
	return map, x and x * 100, y and y * 100
end
local function near(p)
	if not (p and p.map) then return false end
	local map, x, y = here()
	if map ~= p.map then return false end
	if not (x and p.x) then return true end
	return math.sqrt((x - p.x) ^ 2 + (y - p.y) ^ 2) <= NEAR
end
local function questDone(q)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(q) end
	return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(q)
end

local function clearWaypoint()
	if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
	if ttPin and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, ttPin) end
	ttPin = nil
end
local function setWaypoint(s)
	if not (s and s.map and s.x) then return end
	local x, y = s.x / 100, s.y / 100
	if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(s.map) then
		local ok = pcall(function()
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(s.map, x, y))
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
		end)
		if ok then return end
	end
	if TomTom and TomTom.AddWaypoint then
		if ttPin and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, ttPin) end
		local ok, pin = pcall(TomTom.AddWaypoint, TomTom, s.map, x, y, { title = s.npc or s.text, persistent = false })
		ttPin = ok and pin or nil
	end
end

local function isDone(s)
	if s.kind == 'port' then return near(s.arrive) and true or (s.arrive and select(1, here()) == s.arrive.map)
	elseif s.kind == 'fly' then return near(s.arrive) or (s.flew and not (UnitOnTaxi and UnitOnTaxi('player')))
	elseif s.kind == 'ride' then return s.toMap ~= nil and select(1, here()) == s.toMap
	elseif s.kind == 'mail' then
		if #s.need == 0 then return s.emptied or false end
		for _, n in ipairs(s.need) do if (GetItemCount(n[1]) or 0) < n[2] then return false end end
		return true
	elseif s.kind == 'writ' or s.kind == 'label' then return s.handed or questDone(s.quest) or false
	elseif s.kind == 'crates' then
		if not s.seen then return false end
		for _, id in ipairs(s.sealed) do if (GetItemCount(id) or 0) > 0 then return false end end
		return true
	elseif s.kind == 'fill' then
		if ns.NextFill and ns.NextFill() then s.seen = true; return false end
		return s.seen or false
	elseif s.kind == 'receipts' then
		if (s.turned or 0) < (s.n or 1) then return false end
		local W = D.waylaid
		for _, c in ipairs(W.crates) do if (GetItemCount(c[1]) or 0) > 0 then return false end end
		for _, t in pairs(W.sealed or {}) do for _, id in pairs(t) do if (GetItemCount(id) or 0) > 0 then return false end end end
		return true
	end
	return false
end

local draw
local function go(to)
	if not nav then return end
	nav.at = math.max(1, math.min(#nav.steps + 1, to))
	local s = step()
	if s then
		s.flew = nil
		if s.kind == 'receipts' then s.turned = 0 end
		if s.kind == 'fill' then s.seen = false end
		if s.kind == 'mail' then s.emptied = nil end
		if s.kind == 'crates' then
			s.seen = false
			for _, id in ipairs(s.sealed) do if (GetItemCount(id) or 0) > 0 then s.seen = true end end
		end
		setWaypoint(s)
		log(('step %d of %d: %s'):format(nav.at, #nav.steps, s.text))
	else
		clearWaypoint()
	end
	draw()
end
local function advance()
	if not nav then return end
	local moved = false
	for _ = 1, #nav.steps do
		local s = step()
		if not (s and isDone(s)) then break end
		nav.at = nav.at + 1
		moved = true
	end
	if moved then go(nav.at) end
end

function Nav.Pouch()
	local first, n = nil, 0
	for _, id in ipairs(Guide.POUCHES) do
		local c = GetItemCount(id) or 0
		if c > 0 then first = first or id; n = n + c end
	end
	return first, n
end
local function onQuest(q) return (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(q)) and true or false end
function Nav.ToStart()
	local s = step()
	if not (s and (s.kind == 'writ' or s.kind == 'label') and s.writ) then return nil, 0 end
	local first, n = nil, 0
	for i = nav.at, #nav.steps do
		local x = nav.steps[i]
		if not ((x.kind == 'writ' or x.kind == 'label') and x.npc == s.npc) then break end
		if not x.handed and (GetItemCount(x.writ) or 0) > 0 and not onQuest(x.quest) then first = first or x; n = n + 1 end
	end
	return first, n
end
function Nav.WritMacro()
	local s = Nav.ToStart()
	if not s then return nil end
	local lines = {}
	local starOn = not (ns.db and ns.db.settings and ns.db.settings.star == false) -- (the game's options: Options.lua)
	if s.npc then
		lines[#lines + 1] = '/target ' .. s.npc
		if starOn then lines[#lines + 1] = '/tm ' .. STAR end
	end
	lines[#lines + 1] = '/use item:' .. s.writ
	return table.concat(lines, '\n')
end

local mailOpen, mailRead, taking, took, toldFull, toldMore = false, false, nil, 0, false, false
local function crateThings()
	local out, W, mail = {}, D.waylaid, (store() or {}).mail or {}
	if not W then return out end
	local function held(id) return (GetItemCount(id) or 0) > 0 or (mail[id] or 0) > 0 end
	for _, c in ipairs(W.crates) do
		out[c[1]] = true
		if held(c[1]) then for _, o in ipairs(c[5]) do out[o[1]] = true end end
	end
	for _, t in pairs(W.sealed or {}) do for _, id in pairs(t) do out[id] = true end end
	if ns.Plan and ns.Plan.RECEIPT then out[ns.Plan.RECEIPT.item] = true end
	return out
end
local function mailWants(s)
	local want, any = {}, false
	for _, n in ipairs(s.need) do
		local short = n[2] - (GetItemCount(n[1]) or 0)
		if short > 0 then want[n[1]] = true; any = true end
	end
	if s.crates then for id in pairs(crateThings()) do want[id] = true; any = true end end
	return any and want or nil
end
local function mailFind(want)
	if not (GetInboxNumItems and GetInboxItemLink) then return end
	for i = (GetInboxNumItems() or 0), 1, -1 do
		local cod = GetInboxHeaderInfo and select(6, GetInboxHeaderInfo(i)) or 0
		if (cod or 0) == 0 then
			for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
				local link = GetInboxItemLink(i, a)
				local id = link and tonumber(link:match('item:(%d+)'))
				if id and want[id] then return i, a end
			end
		end
	end
end
local function mailTake()
	local s = step()
	if not (mailOpen and mailRead and s and s.kind == 'mail') then return end
	local want = mailWants(s)
	local i, a = nil, nil
	if want then i, a = mailFind(want) end
	if not i then
		if s.crates and not s.emptied then s.emptied = true; pcall(advance) end
		if took > 0 then say(('took %d thing%s out of the mail for this step.'):format(took, took == 1 and '' or 's')); took = 0 end
		local shown, all = GetInboxNumItems()
		if want and not s.crates and all and shown and all > shown and not toldMore then
			toldMore = true
			say('there is more mail than the mailbox shows at once. Close it and open it again for the rest.')
		end
		return
	end
	if ns.db and ns.db.settings and ns.db.settings.autoMail == false then return end
	if not TakeInboxItem then return end
	if taking and (GetTime() - taking) < 2 then return end
	local free = State.FreeSlots and State.FreeSlots()
	if free == 0 then
		if not toldFull then toldFull = true; say('your bags are full: the rest stays in the mail.') end
		return
	end
	taking = GetTime()
	took = took + 1
	pcall(TakeInboxItem, i, a)
end
function Nav.MailEvent(event)
	if event == 'MAIL_SHOW' then mailOpen, mailRead, taking, took, toldFull, toldMore = true, false, nil, 0, false, false
	elseif event == 'MAIL_CLOSED' then mailOpen, mailRead = false, false
	elseif event == 'MAIL_INBOX_UPDATE' then mailRead = true; mailTake()
	elseif event == 'BAG_UPDATE_DELAYED' then taking = nil; mailTake() end
end

local function build()
	local f = CreateFrame('Frame', 'WritsAndFavorsGuide', UIParent)
	f:SetSize(330, 118)
	f:SetFrameStrata('MEDIUM')
	f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
	f:RegisterForDrag('LeftButton')
	f:SetScript('OnDragStart', f.StartMoving)
	f:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		local c = store()
		if c then local p, _, rp, x, y = self:GetPoint(); c.guideAt = { p, rp, x, y } end
	end)
	S.Box(f, C.bg, C.border)
	local logo = f:CreateTexture(nil, 'ARTWORK')
	logo:SetSize(16, 16); logo:SetPoint('TOPLEFT', 8, -7); logo:SetTexture('Interface\\AddOns\\' .. ADDON .. '\\logo.tga')
	f.title = S.Text(f, 12, C.gold); f.title:SetPoint('TOPLEFT', 30, -9)
	f.close = S.Button(f, 'x', 22, 20, function() Nav.Stop() end); f.close:SetPoint('TOPRIGHT', -4, -4)
	f.prev = S.Button(f, '<', 22, 20, function() if nav then go(nav.at - 1) end end); f.prev:SetPoint('RIGHT', f.close, 'LEFT', -4, 0)
	f.next = S.Button(f, 'Next step', 92, 28, function() if nav then go(nav.at + 1) end end, true); f.next:SetPoint('BOTTOMRIGHT', -8, 8)
	f.text = S.Text(f, 13, C.text); f.text:SetPoint('TOPLEFT', 10, -32); f.text:SetWidth(310); f.text:SetWordWrap(true); f.text:SetSpacing(2)
	f.where = S.Text(f, 11, C.muted); f.where:SetPoint('BOTTOMLEFT', 10, 20); f.where:SetWidth(130); f.where:SetWordWrap(false)
	local function icon(name, tipTitle, tipText)
		local b = CreateFrame('Button', name, f, 'SecureActionButtonTemplate')
		b:SetSize(38, 38)
		b:RegisterForClicks('AnyUp', 'AnyDown')
		b:SetAttribute('type', 'macro')
		S.Box(b, C.panel, { C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6, 1 })
		b.icon = b:CreateTexture(nil, 'ARTWORK'); b.icon:SetPoint('TOPLEFT', 2, -2); b.icon:SetPoint('BOTTOMRIGHT', -2, 2); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.count = S.Text(b, 12, C.text, 'RIGHT'); b.count:SetPoint('BOTTOMRIGHT', -3, 3)
		b:SetScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_TOP')
			GameTooltip:AddLine(tipTitle)
			GameTooltip:AddLine(tipText, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript('OnLeave', function() GameTooltip:Hide() end)
		b:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 8, 8)
		return b
	end
	local b = icon('WritsAndFavorsGuideUse', 'Use the writ', 'Targets who takes it, puts a star on them and uses the writ to start its quest. Then talk to them: it is handed in for you (hold Shift to do it yourself).')
	b:SetScript('PreClick', function(self)
		if InCombatLockdown() then return end
		self:SetAttribute('macrotext', Nav.WritMacro() or '')
	end)
	local p = icon('WritsAndFavorsGuidePouch', 'Open a coin pouch', 'Your money back from a writ handed in. Each click opens one.')
	p:SetScript('PreClick', function(self)
		if InCombatLockdown() then return end
		local id = Nav.Pouch()
		self:SetAttribute('macrotext', id and ('/use item:' .. id) or '')
	end)
	f.pouch = p
	f.use = b
	f:Hide()
	return f
end

function draw()
	local fight = InCombatLockdown and InCombatLockdown()
	if not nav then if win and not fight then win:Hide() end return end
	if not win then
		if fight then return end
		win = build()
	end
	local c = store()
	if not fight then
		win:ClearAllPoints()
		if c and c.guideAt then win:SetPoint(c.guideAt[1], UIParent, c.guideAt[2], c.guideAt[3], c.guideAt[4]) else win:SetPoint('TOP', UIParent, 'TOP', 0, -140) end
	end
	local s = step()
	local n = #nav.steps
	local icons = 0
	local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
	if not s then
		win.title:SetText(('Route: done (%d steps)'):format(n))
		win.text:SetText(GREEN .. 'All handed in. Well done.|r\n' .. MUTED .. 'Open your coin pouches: your money back.|r')
		win.where:SetText('')
		if not InCombatLockdown() then win.use:Hide() end
		win.next:Disable(); win.prev:Enable()
		icons = 0
	else
		win.title:SetText(('Route: step %d of %d'):format(nav.at, n))
		win.text:SetText(s.text .. (s.detail and s.detail ~= '' and ('\n' .. MUTED .. s.detail .. '|r') or ''))
		local info = s.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(s.map)
		local zone = s.zone or (info and info.name)
		win.where:SetText(s.x and ((zone and (zone .. '  ') or '') .. ('%.1f, %.1f'):format(s.x, s.y)) or '')
		local writStep = s.kind == 'writ' or s.kind == 'label'
		local first, starts = Nav.ToStart()
		local usable = first ~= nil
		if not InCombatLockdown() then win.use:SetShown(writStep) end
		local shownWrit = first and first.writ or s.writ
		win.use.icon:SetTexture(shownWrit and GetIcon and GetIcon(shownWrit) or nil)
		win.use.count:SetText(starts > 1 and starts or '')
		if writStep and starts > 1 then
			win.text:SetText(s.text .. '\n' .. GOLD .. ('%d writs for %s: click the icon once for each, then talk once.|r'):format(starts, s.npc or 'them'))
		elseif writStep and not usable then
			win.text:SetText(s.text .. '\n' .. MUTED .. 'Talk to ' .. (s.npc or 'them') .. ': it is handed in for you.|r')
		end
		if s.warn then win.text:SetText((win.text:GetText() or s.text) .. '\n|cffff6060' .. s.warn .. '|r') end
		if win.use.icon.SetDesaturated then win.use.icon:SetDesaturated(not usable) end
		win.use:SetAlpha(usable and 1 or 0.45)
		icons = writStep and 1 or 0
		win.next:Enable()
		win.next:SetText(nav.at >= n and 'Finish' or 'Next step')
		if nav.at > 1 then win.prev:Enable() else win.prev:Disable() end
	end
	local pouch, pouches = Nav.Pouch()
	win.pouch.icon:SetTexture(pouch and GetIcon and GetIcon(pouch) or nil)
	win.pouch.count:SetText(pouches > 1 and pouches or '')
	if not fight then
		win.pouch:SetShown(pouch ~= nil)
		win.pouch:ClearAllPoints()
		win.pouch:SetPoint('BOTTOMLEFT', win, 'BOTTOMLEFT', 8 + icons * 44, 8)
	end
	if pouch then icons = icons + 1 end
	win.where:ClearAllPoints()
	win.where:SetPoint('BOTTOMLEFT', win, 'BOTTOMLEFT', 10 + icons * 44, 20)
	win.where:SetWidth(math.max(40, 216 - icons * 44))
	if ns.Macro then ns.Macro.Update() end
	if fight then return end
	win:SetScale(ns.db and ns.db.settings and ns.db.settings.scale or 1)
	win:Show()
	local h = win.text:GetStringHeight()
	win:SetHeight(32 + ((h and h > 10) and h or 34) + 56)
end

function Nav.Start(route)
	local steps = Guide.Steps(route)
	if #steps == 0 then return 0 end
	nav = { steps = steps, at = 1, day = State.WritDay() }
	local c = store()
	if c then c.guide = nav end
	go(1)
	advance()
	return #steps
end
function Nav.Stop()
	nav = nil
	local c = store()
	if c then c.guide = nil end
	clearWaypoint()
	draw() -- hides the window (once out of combat)
end
function Nav.Active() return nav ~= nil end
function Nav.Resume()
	local c = store()
	if c and c.guide and c.guide.day == State.WritDay() and type(c.guide.steps) == 'table' and #c.guide.steps > 0 then
		nav = c.guide
		go(nav.at or 1)
		advance()
	elseif c then c.guide = nil end
end
function Nav.Step() return step(), nav and nav.at, nav and #nav.steps end
function Nav.Go(to) go(to) end
function Nav.Check() advance() end

local function star(unit)
	local s = step()
	if not (s and s.npc and UnitName and UnitExists and UnitExists(unit)) then return end
	if UnitName(unit) ~= s.npc then return end
	if GetRaidTargetIndex and GetRaidTargetIndex(unit) == STAR then return end
	if ns.db and ns.db.settings and ns.db.settings.star == false then return end -- (Options.lua)
	if SetRaidTarget then pcall(SetRaidTarget, unit, STAR) end
end

local function auto() return nav ~= nil and not (IsShiftKeyDown and IsShiftKeyDown()) end
local function ours(q) return q and writQuest[q] ~= nil end
local function onQuestEvent(event)
	if not auto() then return end
	if event == 'GOSSIP_SHOW' and C_GossipInfo and C_GossipInfo.GetActiveQuests then
		for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
			if ours(q.questID) and q.isComplete ~= false then log('gossip: hand in ' .. q.questID); return C_GossipInfo.SelectActiveQuest(q.questID) end
		end
		log('gossip: nothing of ours ready (' .. #(C_GossipInfo.GetActiveQuests() or {}) .. ' active)')
	elseif event == 'QUEST_GREETING' and GetNumActiveQuests then
		for i = 1, GetNumActiveQuests() do
			local id = GetActiveQuestID and GetActiveQuestID(i)
			if ours(id) then return SelectActiveQuest(i) end
		end
	elseif ours(GetQuestID and GetQuestID()) then
		log(event .. ' ' .. tostring(GetQuestID()))
		if event == 'QUEST_DETAIL' then AcceptQuest()
		elseif event == 'QUEST_PROGRESS' then if IsQuestCompletable() then CompleteQuest() end
		elseif event == 'QUEST_COMPLETE' then if (GetNumQuestChoices() or 0) <= 1 then GetQuestReward(1) end end
	end
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'QUEST_TURNED_IN', 'BAG_UPDATE_DELAYED', 'ZONE_CHANGED_NEW_AREA', 'ZONE_CHANGED', 'PLAYER_CONTROL_GAINED', 'PLAYER_CONTROL_LOST',
	'PLAYER_TARGET_CHANGED', 'UPDATE_MOUSEOVER_UNIT', 'MAIL_SHOW', 'MAIL_CLOSED', 'MAIL_INBOX_UPDATE', 'GOSSIP_SHOW', 'QUEST_GREETING', 'QUEST_DETAIL', 'QUEST_PROGRESS', 'QUEST_COMPLETE', 'PLAYER_REGEN_ENABLED' }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript('OnEvent', function(_, event, arg)
	if event == 'PLAYER_LOGIN' then return Nav.Resume() end
	if not nav then return end
	local ok, err = pcall(function()
		if event == 'QUEST_TURNED_IN' then
			for _, s in ipairs(nav.steps) do if (s.kind == 'writ' or s.kind == 'label') and s.quest == arg then s.handed = true end end
			local s = step()
			if s and s.kind == 'receipts' and not writQuest[arg] then s.turned = (s.turned or 0) + 1 end
			log('handed in quest ' .. tostring(arg))
			advance()
			draw()
		elseif event == 'MAIL_SHOW' or event == 'MAIL_CLOSED' or event == 'MAIL_INBOX_UPDATE' then
			Nav.MailEvent(event)
		elseif event == 'PLAYER_CONTROL_LOST' then
			local s = step()
			if s and s.kind == 'fly' and UnitOnTaxi and UnitOnTaxi('player') then s.flew = true end
		elseif event == 'PLAYER_TARGET_CHANGED' then star('target')
		elseif event == 'UPDATE_MOUSEOVER_UNIT' then star('mouseover')
		elseif event == 'GOSSIP_SHOW' or event == 'QUEST_GREETING' or event == 'QUEST_DETAIL' or event == 'QUEST_PROGRESS' or event == 'QUEST_COMPLETE' then
			star('npc')
			onQuestEvent(event)
		else
			if event == 'BAG_UPDATE_DELAYED' then Nav.MailEvent(event) end
			advance()
			if event == 'BAG_UPDATE_DELAYED' or event == 'PLAYER_REGEN_ENABLED' then draw() end
		end
	end)
	if not ok then log('error ' .. tostring(err)) end
end)
local since = 0
ev:SetScript('OnUpdate', function(_, dt)
	since = since + (dt or 0)
	if since < 1 then return end
	since = 0
	local s = step()
	if not s then return end
	if s.kind == 'fly' and UnitOnTaxi and UnitOnTaxi('player') then s.flew = true end
	if s.kind == 'port' or s.kind == 'fly' or s.kind == 'ride' then pcall(advance) end
	if s.kind == 'mail' and mailOpen then pcall(mailTake) end -- (a take that got no answer: tried again)
end)
