local _, ns = ...
local D = ns.D
local L = {}
ns.L = L

local locale = GetLocale and GetLocale() or 'enUS'
L.locale = locale
L.english = locale == 'enUS' or locale == 'enGB'

local slots, pending, left = {}, {}, 0
local function slot(id, t, k)
	slots[id] = slots[id] or {}
	table.insert(slots[id], { t, k })
	if not pending[id] then pending[id] = true; left = left + 1 end
end
if not L.english then
	for _, w in ipairs(D.writs) do slot(w[1], w, 7); slot(w[3], w, 8) end
	if D.waylaid and D.waylaid.names then for id in pairs(D.waylaid.names) do slot(id, D.waylaid.names, id) end end
end

local function gameName(id)
	local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if not n and GetItemInfo then n = GetItemInfo(id) end
	return n
end
local function take(id)
	if not pending[id] then return true end
	local n = gameName(id)
	if not n or n == '' then return false end
	for _, s in ipairs(slots[id]) do s[1][s[2]] = n end
	pending[id] = nil
	left = left - 1
	return true
end
function L.Load()
	if left == 0 then return 0 end
	local ask = {}
	for id in pairs(pending) do ask[#ask + 1] = id end
	for _, id in ipairs(ask) do
		if not take(id) and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
	end
	return left
end
function L.Missing() return left end
function L.Has(id) return not pending[id] end

if not L.english then
	local f = CreateFrame('Frame')
	f:RegisterEvent('PLAYER_LOGIN')
	f:RegisterEvent('GET_ITEM_INFO_RECEIVED')
	f:SetScript('OnEvent', function(_, event, id)
		if event == 'PLAYER_LOGIN' then L.Load() elseif id and pending[id] then take(id) end
	end)
end

local function cont(b) return b and b >= 128 and b < 192 end
local function shared(names)
	if #names < 2 then return nil end
	local first = names[1]
	local pre, suf = #first, #first
	for i = 2, #names do
		local s = names[i]
		local k = 0
		while k < pre and k < #s and first:byte(k + 1) == s:byte(k + 1) do k = k + 1 end
		pre = k
		k = 0
		while k < suf and k < #s and first:byte(#first - k) == s:byte(#s - k) do k = k + 1 end
		suf = k
	end
	while pre > 0 and cont(first:byte(pre + 1)) do pre = pre - 1 end
	while suf > 0 and cont(first:byte(#first - suf + 1)) do suf = suf - 1 end
	local function tidy(s) return (s:gsub('^[%s%p]+', ''):gsub('[%s%p]+$', '')) end
	local a, b = tidy(first:sub(1, pre)), tidy(first:sub(#first - suf + 1))
	if #a >= 4 then return a end
	if #b >= 4 then return b end
	return nil
end
L.Shared = shared

local function namesOf(ids)
	local out = {}
	for _, id in ipairs(ids) do if not pending[id] then local s = slots[id] and slots[id][1]; if s then out[#out + 1] = s[1][s[2]] end end end
	return out
end
function L.WritSearch()
	if L.english then return "Craftsman's Writ" end
	local ids = {}
	for _, w in ipairs(D.writs) do ids[#ids + 1] = w[1] end
	return shared(namesOf(ids))
end
function L.CrateSearch()
	if L.english then return 'Waylaid Crate' end
	local ids = {}
	for _, c in ipairs(D.waylaid.crates) do ids[#ids + 1] = c[1] end
	return shared(namesOf(ids))
end
function L.Terms(terms)
	if L.english then return terms end
	local out, seen = {}, {}
	for _, t in ipairs(terms) do
		for _, id in ipairs(t[2]) do
			if not seen[id] and not pending[id] then
				seen[id] = true
				local s = slots[id] and slots[id][1]
				if s then out[#out + 1] = { s[1][s[2]], { id } } end
			end
		end
	end
	return out
end
