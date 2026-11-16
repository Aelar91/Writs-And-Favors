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
		if #s.need == 0 then return false end
		for _, n in ipairs(s.need) do if (GetItemCount(n[1]) or 0) < n[2] then return false end end
		return true
	elseif s.kind == 'writ' or s.kind == 'label' then return s.handed or questDone(s.quest) or false
	elseif s.kind == 'crates' then
		if not s.seen then return false end
		for _, id in ipairs(s.sealed) do if (GetItemCount(id) or 0) > 0 then return false end end
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
	f.next = S.Button(f, '>', 22, 20, function() if nav then go(nav.at + 1) end end); f.next:SetPoint('RIGHT', f.close, 'LEFT', -4, 0)
	f.prev = S.Button(f, '<', 22, 20, function() if nav then go(nav.at - 1) end end); f.prev:SetPoint('RIGHT', f.next, 'LEFT', -4, 0)
	f.text = S.Text(f, 13, C.text); f.text:SetPoint('TOPLEFT', 10, -32); f.text:SetWidth(310); f.text:SetWordWrap(true); f.text:SetSpacing(2)
	f.where = S.Text(f, 11, C.muted); f.where:SetPoint('BOTTOMLEFT', 10, 10); f.where:SetWidth(180); f.where:SetWordWrap(false)
	local b = CreateFrame('Button', 'WritsAndFavorsGuideUse', f, 'SecureActionButtonTemplate')
	b:SetSize(120, 26)
	b:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -8, 8)
	b:RegisterForClicks('AnyUp', 'AnyDown')
	b:SetAttribute('type', 'macro')
	S.Box(b, C.panel, { C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6, 1 })
	b.label = S.Text(b, 12, C.gold, 'CENTER'); b.label:SetPoint('CENTER'); b.label:SetWidth(112); b.label:SetWordWrap(false)
	b.icon = b:CreateTexture(nil, 'ARTWORK'); b.icon:SetSize(18, 18); b.icon:SetPoint('RIGHT', b, 'LEFT', -6, 0); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetScript('PreClick', function(self)
		if InCombatLockdown() then return end
		local s = step()
		local lines = {}
		if s and s.npc then lines[#lines + 1] = '/target ' .. s.npc; lines[#lines + 1] = '/tm ' .. STAR end
		if s and s.writ then lines[#lines + 1] = '/use item:' .. s.writ end
		self:SetAttribute('macrotext', table.concat(lines, '\n'))
	end)
	b:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine('Use the writ')
		GameTooltip:AddLine('Targets who takes it, puts a star on them and uses the writ to start its quest. Then talk to them: it is handed in for you (hold Shift to do it yourself).', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript('OnLeave', function() GameTooltip:Hide() end)
	f.use = b
	f:Hide()
	return f
end

function draw()
	if not nav then if win then win:Hide() end return end
	if not win then win = build() end
	local c = store()
	win:ClearAllPoints()
	if c and c.guideAt then win:SetPoint(c.guideAt[1], UIParent, c.guideAt[2], c.guideAt[3], c.guideAt[4]) else win:SetPoint('TOP', UIParent, 'TOP', 0, -140) end
	local s = step()
	local n = #nav.steps
	if not s then
		win.title:SetText(('Route: done (%d steps)'):format(n))
		win.text:SetText(GREEN .. 'All handed in. Well done.|r\n' .. MUTED .. 'Open your coin pouches: your money back.|r')
		win.where:SetText('')
		if not InCombatLockdown() then win.use:Hide() end
		win.next:Disable(); win.prev:Enable()
	else
		win.title:SetText(('Route: step %d of %d'):format(nav.at, n))
		win.text:SetText(s.text .. (s.detail and s.detail ~= '' and ('\n' .. MUTED .. s.detail .. '|r') or ''))
		local info = s.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(s.map)
		local zone = s.zone or (info and info.name)
		win.where:SetText(s.x and ((zone and (zone .. '  ') or '') .. ('%.1f, %.1f'):format(s.x, s.y)) or '')
		local usable = (s.kind == 'writ' or s.kind == 'label') and (GetItemCount(s.writ) or 0) > 0
		if not InCombatLockdown() then win.use:SetShown(s.kind == 'writ' or s.kind == 'label') end
		win.use.label:SetText(usable and 'Use the writ' or (s.kind == 'label' and 'Talk to ' .. (s.npc or '') or 'Writ used'))
		local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
		win.use.icon:SetTexture(s.writ and GetIcon and GetIcon(s.writ) or nil)
		win.next:Enable()
		if nav.at > 1 then win.prev:Enable() else win.prev:Disable() end
	end
	win:SetScale(ns.db and ns.db.settings and ns.db.settings.scale or 1)
	win:Show()
	local h = win.text:GetStringHeight()
	win:SetHeight(32 + ((h and h > 10) and h or 34) + 44)
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
	if win then win:Hide() end
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
	if SetRaidTarget then pcall(SetRaidTarget, unit, STAR) end
end

local function auto() return nav ~= nil and not (IsShiftKeyDown and IsShiftKeyDown()) end
local function ours(q) return q and writQuest[q] ~= nil end
local function onQuestEvent(event)
	if not auto() then return end
	if event == 'GOSSIP_SHOW' and C_GossipInfo and C_GossipInfo.GetActiveQuests then
		for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
			if ours(q.questID) and q.isComplete ~= false then return C_GossipInfo.SelectActiveQuest(q.questID) end
		end
	elseif event == 'QUEST_GREETING' and GetNumActiveQuests then
		for i = 1, GetNumActiveQuests() do
			local id = GetActiveQuestID and GetActiveQuestID(i)
			if ours(id) then return SelectActiveQuest(i) end
		end
	elseif ours(GetQuestID and GetQuestID()) then
		if event == 'QUEST_DETAIL' then AcceptQuest()
		elseif event == 'QUEST_PROGRESS' then if IsQuestCompletable() then CompleteQuest() end
		elseif event == 'QUEST_COMPLETE' then if (GetNumQuestChoices() or 0) <= 1 then GetQuestReward(1) end end
	end
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'QUEST_TURNED_IN', 'BAG_UPDATE_DELAYED', 'ZONE_CHANGED_NEW_AREA', 'ZONE_CHANGED', 'PLAYER_CONTROL_GAINED', 'PLAYER_CONTROL_LOST',
	'PLAYER_TARGET_CHANGED', 'UPDATE_MOUSEOVER_UNIT', 'GOSSIP_SHOW', 'QUEST_GREETING', 'QUEST_DETAIL', 'QUEST_PROGRESS', 'QUEST_COMPLETE', 'PLAYER_REGEN_ENABLED' }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript('OnEvent', function(_, event, arg)
	if event == 'PLAYER_LOGIN' then return Nav.Resume() end
	if not nav then return end
	local ok, err = pcall(function()
		if event == 'QUEST_TURNED_IN' then
			for _, s in ipairs(nav.steps) do if (s.kind == 'writ' or s.kind == 'label') and s.quest == arg then s.handed = true end end
			advance()
		elseif event == 'PLAYER_CONTROL_LOST' then
			local s = step()
			if s and s.kind == 'fly' and UnitOnTaxi and UnitOnTaxi('player') then s.flew = true end
		elseif event == 'PLAYER_TARGET_CHANGED' then star('target')
		elseif event == 'UPDATE_MOUSEOVER_UNIT' then star('mouseover')
		elseif event == 'GOSSIP_SHOW' or event == 'QUEST_GREETING' or event == 'QUEST_DETAIL' or event == 'QUEST_PROGRESS' or event == 'QUEST_COMPLETE' then
			star('npc')
			onQuestEvent(event)
		else
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
end)
