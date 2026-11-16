local _, ns = ...
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local D = ns.D
local State = {}
ns.State = State

local GOALS = { { 'Friendly', 3000 }, { 'Honored', 9000 }, { 'Revered', 21000 }, { 'Exalted', 42000 } }
State.GOALS = GOALS
local STANDING = { [4] = 'Neutral', [5] = 'Friendly', [6] = 'Honored', [7] = 'Revered', [8] = 'Exalted' }

function State.Rep()
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local f = C_Reputation.GetFactionDataByID(D.faction)
		if f then return f.currentStanding or 0, STANDING[f.reaction] or '', f.name end
	end
	if GetFactionInfoByID then
		local name, _, standingID, _, _, barValue = GetFactionInfoByID(D.faction)
		if name then return barValue or 0, STANDING[standingID] or '', name end
	end
	return 0, 'No standing yet', D.factionName or 'Durotar Supply and Logistics'
end

local function questDone(q)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(q) end
	return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(q)
end

function State.WritDay()
	local t = (GetServerTime and GetServerTime() or time()) + (GetQuestResetTime and GetQuestResetTime() or 0)
	return math.floor(t / 3600 + 0.5)
end
local function me() return UnitGUID and UnitGUID('player') or (UnitName('player') or '?') end

local writQuest = {}
for _, w in ipairs(D.writs) do writQuest[w[2]] = true end
local function turnedToday(db)
	db.turned = db.turned or {}
	local t = db.turned[me()]
	if not t or t.day ~= State.WritDay() then t = { day = State.WritDay(), q = {} }; db.turned[me()] = t end
	return t.q
end
local tf = CreateFrame('Frame')
tf:RegisterEvent('QUEST_TURNED_IN')
tf:SetScript('OnEvent', function(_, _, quest)
	if ns.db and writQuest[quest] then
		turnedToday(ns.db)[quest] = true
		if ns.Log then ns.Log('handed in writ quest ' .. quest) end
		local ok, at = pcall(State.Learn, ns.db, quest)
		if ok and at and ns.Log then ns.Log(('learnt hand-in of %d: %s %s, %s %s'):format(quest, tostring(at.npc), at.zone, tostring(at.x), tostring(at.y))) end
	end
end)

function State.Char(db)
	db.chars = db.chars or {}
	local g = me()
	db.chars[g] = db.chars[g] or {}
	return db.chars[g]
end
local IDS = {}
for _, w in ipairs(D.writs) do IDS[#IDS + 1] = w[1]; IDS[#IDS + 1] = w[3] end
for id in pairs(D.waylaid.names) do IDS[#IDS + 1] = id end
State.IDS = IDS

function State.Read(db)
	local me_ = State.Char(db)
	local held, items, done = {}, {}, {}
	local from = { bags = {}, mail = me_.mail or {}, bank = me_.bank or {}, bought = me_.bought or {} }
	for _, id in ipairs(IDS) do
		local b = GetItemCount(id) or 0
		if b > 0 then from.bags[id] = b end
	end
	local isWrit = {}
	for _, w in ipairs(D.writs) do isWrit[w[1]] = true end
	for _, src in pairs(from) do
		for id, n in pairs(src) do
			if isWrit[id] then held[id] = (held[id] or 0) + n else items[id] = (items[id] or 0) + n end
		end
	end
	local seen = turnedToday(db)
	local flag, ours = 0, 0
	for _, w in ipairs(D.writs) do
		local quest = w[2]
		if questDone(quest) then done[quest] = true; flag = flag + 1
		elseif seen[quest] then done[quest] = true; ours = ours + 1 end
	end
	return { held = held, items = items, from = from, seen = { mail = me_.mailAt, bank = me_.bankAt }, done = done, doneBy = { flag = flag, ours = ours } }
end

function State.Bought(db, id, qty)
	local c = State.Char(db)
	c.bought = c.bought or {}
	c.bought[id] = (c.bought[id] or 0) + (qty or 1)
end

function State.ReadBank(db)
	local bank = {}
	for _, id in ipairs(IDS) do
		local all, bags = GetItemCount(id, true) or 0, GetItemCount(id) or 0
		if all > bags then bank[id] = all - bags end
	end
	local c = State.Char(db)
	c.bank, c.bankAt = bank, GetServerTime and GetServerTime() or time()
end

State.LABEL = { Horde = { item = 280180, quest = 98248 }, Alliance = { item = 280179, quest = 98247 } }
function State.Label()
	local l = D.label or State.LABEL[UnitFactionGroup and UnitFactionGroup('player') or 'Horde'] or State.LABEL.Horde
	local onQuest = C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(l.quest) or false
	return { item = l.item, quest = l.quest, rep = 2000, done = questDone(l.quest) and true or false, held = (GetItemCount(l.item) or 0) > 0, onQuest = onQuest }
end

function State.ReadMail(db)
	local mail = {}
	for i = 1, (GetInboxNumItems() or 0) do
		for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
			local link = GetInboxItemLink(i, a)
			local id = link and tonumber(link:match('item:(%d+)'))
			if id then
				local _, _, _, count = GetInboxItem(i, a)
				mail[id] = (mail[id] or 0) + (count or 1)
			end
		end
	end
	local c = State.Char(db)
	c.mail, c.mailAt = mail, GetServerTime and GetServerTime() or time()
	if not MailFrame or MailFrame:IsShown() then c.bought = nil end
end

function State.FreeSlots()
	local free = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	if not free then return nil end
	local n = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local ok, slots, family = pcall(free, bag)
		if ok and slots and (not family or family == 0) then n = n + slots end
	end
	return n
end

local noPlace = {}
for _, w in ipairs(D.writs) do if not w[6] then noPlace[w[2]] = w end end
function State.Learn(db, quest)
	local w = noPlace[quest]
	if not (db and w) then return nil end
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player')
	local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, 'player')
	local x, y
	if pos then if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end end
	local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	local zone = (info and info.name) or (GetRealZoneText and GetRealZoneText()) or nil
	if not zone then return nil end
	local npc = UnitName and (UnitName('npc') or UnitName('target')) or nil
	db.learned = db.learned or {}
	db.learned[quest] = { zone = zone, map = map, x = x and math.floor(x * 1000 + 0.5) / 10 or nil, y = y and math.floor(y * 1000 + 0.5) / 10 or nil, npc = npc }
	return db.learned[quest]
end
function State.Learned(db, quest) return db and db.learned and db.learned[quest] or nil end

function State.Hearth()
	local bind = GetBindLocation and GetBindLocation()
	if not bind then return nil end
	local function plain(s) return (s:gsub('^The ', ''):gsub(' Base Camp$', ''):gsub(' City$', ''):gsub(' Isle$', ''):gsub(' Stronghold$', '')) end
	bind = plain(bind)
	if D.innAlias and D.innAlias[bind] then return D.innAlias[bind] end
	for _, id in ipairs(D.inns) do
		if plain(D.nodes[id][1]) == bind then return id end
	end
	return nil
end

function State.Class()
	local _, class = UnitClass('player')
	return class
end

function State.Start()
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player')
	for id, n in pairs(D.nodes) do if n[2] == map then return id end end
	local zone = GetMinimapZoneText and GetMinimapZoneText() or ''
	for id, n in pairs(D.nodes) do if n[1] == zone then return id end end
	return D.home or 23
end

local FAVOR_NAME = "merchant's favor"
function State.Favor(db)
	if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
	local id = db and db.favorCurrency
	if not id then
		if C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo then
			for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
				local info = C_CurrencyInfo.GetCurrencyListInfo(i)
				if info and info.isHeader and not info.isHeaderExpanded and C_CurrencyInfo.ExpandCurrencyList then C_CurrencyInfo.ExpandCurrencyList(i, true) end
			end
			for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
				local info = C_CurrencyInfo.GetCurrencyListInfo(i)
				if info and info.name and info.name:lower() == FAVOR_NAME then
					local link = C_CurrencyInfo.GetCurrencyListLink and C_CurrencyInfo.GetCurrencyListLink(i)
					id = link and tonumber(link:match('currency:(%d+)'))
					if id then break end
				end
			end
		end
		if not id then
			for k = 1, 5000 do
				local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, k)
				if ok and info and info.name and info.name:lower() == FAVOR_NAME then id = k; break end
			end
		end
		if not id then return nil end
		if db then db.favorCurrency = id end
	end
	local info = C_CurrencyInfo.GetCurrencyInfo(id)
	return info and info.quantity, id
end
