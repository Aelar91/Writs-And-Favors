local ADDON, ns = ...
local S = ns.Skin
local C = S.colors
local R = {}
ns.Recipes = R

local PREFIX = ns.EDITION == 'favor' and 'MerchantsFavor' or 'WritsAndFavors'
local W, PAD, RH, SHOWN = 470, 12, 22, 16
local PROF_W = 210
local OTHER = 'Other'
local STANDINGS = { 'Friendly', 'Honored', 'Revered', 'Exalted' }
local win

local function hex(c) return ('|cff%02x%02x%02x'):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local GOLD, MUTED, GREEN, WHITE = hex(C.gold), hex(C.muted), hex(C.green), hex(C.text)
local function commas(n)
	local s = tostring(math.floor(n or 0))
	local k
	repeat s, k = s:gsub('^(%d+)(%d%d%d)', '%1,%2') until k == 0
	return s
end
local function db() return ns.db end
local function char()
	local d = db()
	local c = d and ns.State and ns.State.Char and ns.State.Char(d)
	if not c then return nil end
	c.recipes = c.recipes or {}
	return c
end
local function side() return UnitFactionGroup and UnitFactionGroup('player') or nil end

local RECIPE_CLASS = 9
local function instant(id)
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not f then return nil end
	local ok, _, _, subType, _, icon, classID = pcall(f, id)
	if ok then return subType, classID, icon end
end

function R.All()
	local out, byId = {}, {}
	local mySide = side()
	for _, e in ipairs(ns.Shop or {}) do
		local id, name, favor, prof, skill, who = e[1], e[2], e[3], e[4], e[5], e[6]
		if not who or not mySide or who == mySide then
			local row = { id = id, name = name, favor = favor, prof = prof, skill = skill or 0, standing = (e[7] or 0) > 0 and e[7] or nil, other = prof == OTHER or nil }
			byId[id] = row
			out[#out + 1] = row
		end
	end
	local d = db()
	for id, s in pairs(d and d.shop or {}) do
		local sub, classID = instant(id)
		local row = byId[id]
		if row then
			if s.favor and s.favor > 0 then row.favor, row.seen = s.favor, true end
		elseif classID == RECIPE_CLASS or (classID == nil and s.recipe) then
			row = { id = id, name = s.name or ('item ' .. id), favor = s.favor or 0, prof = sub or s.prof, skill = s.skill or 0, seen = true }
			byId[id] = row
			out[#out + 1] = row
		end
	end
	for _, row in ipairs(out) do
		local sub, classID = instant(row.id)
		if sub and sub ~= '' and classID == RECIPE_CLASS then row.profLocal = sub end
	end
	return out
end

function R.Skills()
	local t, any = {}, false
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() or 0 do
			local name, isHeader, _, rank = GetSkillLineInfo(i)
			if name and not isHeader then t[name] = rank or 0; any = true end
		end
	elseif GetProfessions and GetProfessionInfo then
		for _, idx in ipairs({ GetProfessions() }) do
			if idx then
				local name, _, rank = GetProfessionInfo(idx)
				if name then t[name] = rank or 0; any = true end
			end
		end
	end
	return any and t or nil
end

local scanTip
local knownCache = {}
function R.IsKnown(id)
	if knownCache[id] ~= nil then return knownCache[id] end
	local want = rawget(_G, 'ITEM_SPELL_KNOWN')
	if not want then return false end
	local found, sure = false, false
	if C_TooltipInfo and C_TooltipInfo.GetItemByID then
		local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
		if ok and type(data) == 'table' and type(data.lines) == 'table' then
			sure = #data.lines > 1
			for _, l in ipairs(data.lines) do if l.leftText == want then found = true end end
		end
	else
		local ok = pcall(function()
			if not scanTip then scanTip = CreateFrame('GameTooltip', PREFIX .. 'ScanTip', nil, 'GameTooltipTemplate') end
			scanTip:SetOwner(WorldFrame or UIParent, 'ANCHOR_NONE')
			scanTip:ClearLines()
			scanTip:SetHyperlink('item:' .. id)
			local n = tonumber(scanTip:NumLines()) or 0
			sure = n > 1
			for i = 2, n do
				local fs = _G[PREFIX .. 'ScanTipTextLeft' .. i]
				if fs and fs:GetText() == want then found = true end
			end
		end)
		if not ok then return false end
	end
	if sure then knownCache[id] = found end
	return found
end
function R.Forget() knownCache = {} end

function R.Rows(o)
	o = o or {}
	local skills = (not o.all) and R.Skills() or nil
	local q = o.search and o.search ~= '' and o.search:lower() or nil
	local rows, known, other = {}, 0, 0
	local picks = (char() or {}).recipes or {}
	local okRep, rep = pcall(ns.State.Rep)
	rep = okRep and tonumber(rep) or nil
	for _, r in ipairs(R.All()) do
		local prof = r.profLocal or r.prof
		if R.IsKnown(r.id) then
			known = known + 1
			if picks[r.id] then picks[r.id] = nil end
		elseif skills and prof and not r.other and skills[prof] == nil then
			other = other + 1
		elseif not q or r.name:lower():find(q, 1, true) or (prof and prof:lower():find(q, 1, true)) then
			r.rank = skills and prof and skills[prof] or nil
			r.lowRep = r.standing and rep and ns.State.GOALS[r.standing] and rep < ns.State.GOALS[r.standing][2] or nil
			r.picked = picks[r.id] and true or false
			rows[#rows + 1] = r
		end
	end
	table.sort(rows, function(a, b)
		local pa, pb = a.profLocal or a.prof or '', b.profLocal or b.prof or ''
		if (a.other or false) ~= (b.other or false) then return not a.other end
		if pa ~= pb then return pa < pb end
		if a.skill ~= b.skill then return a.skill < b.skill end
		return a.name < b.name
	end)
	return rows, known, other
end

function R.Picked()
	local picks = (char() or {}).recipes or {}
	local n, favor = 0, 0
	for _, r in ipairs(R.All()) do
		if picks[r.id] and not R.IsKnown(r.id) then n, favor = n + 1, favor + (r.favor or 0) end
	end
	return n, favor
end
local function apply(always)
	local n, favor = R.Picked()
	if (always or n > 0) and ns.UI and ns.UI.setFavorWant then ns.UI.setFavorWant(favor) end
	return n, favor
end
function R.Pick(id, on)
	local c = char()
	if not c then return end
	c.recipes[id] = on and true or nil
	apply(true)
	if win and win:IsShown() then R.Draw() end
end
function R.Clear()
	local c = char()
	if not c then return end
	c.recipes = {}
	apply(true)
	if win and win:IsShown() then R.Draw() end
end

local function favorCurrency()
	local _, id = ns.State.Favor(db())
	local name
	if id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
		if ok and info then name = info.name end
	end
	return id, name
end
function R.ReadMerchant()
	local d = db()
	if not (d and GetMerchantNumItems and GetMerchantItemCostInfo and GetMerchantItemCostItem) then return 0 end
	local cid, cname = favorCurrency()
	local seen = 0
	for i = 1, GetMerchantNumItems() or 0 do
		local id = GetMerchantItemID and GetMerchantItemID(i)
		if not id and GetMerchantItemLink then
			local link = GetMerchantItemLink(i)
			id = link and tonumber(link:match('item:(%d+)'))
		end
		local favor
		for k = 1, GetMerchantItemCostInfo(i) or 0 do
			local _, value, link, currencyName = GetMerchantItemCostItem(i, k)
			if (cid and link and link:find('currency:' .. cid, 1, true)) or (cname and currencyName == cname) then favor = value end
		end
		if id and favor and favor > 0 then
			local name
			if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
				local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
				name = ok and info and info.name or nil
			elseif GetMerchantItemInfo then
				name = GetMerchantItemInfo(i)
			end
			local sub, classID = instant(id)
			d.shop = d.shop or {}
			d.shop[id] = { name = name or (d.shop[id] and d.shop[id].name), favor = favor, recipe = (classID == RECIPE_CLASS) or (classID == nil and d.shop[id] and d.shop[id].recipe) or nil, prof = sub }
			seen = seen + 1
		end
	end
	if seen > 0 then
		if ns.Log then ns.Log(('recipes: %d things for Favor seen at this vendor'):format(seen)) end
		apply()
		if win and win:IsShown() then R.Draw() end
	end
	return seen
end

local function tipFor(b, title, text)
	b:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:HookScript('OnLeave', function() GameTooltip:Hide() end)
end

local function build()
	local f = CreateFrame('Frame', PREFIX .. 'Recipes', UIParent)
	f:SetSize(W, 34 + 34 + 20 + SHOWN * RH + 8 + 62)
	f:SetFrameStrata('HIGH')
	f:EnableMouse(true)
	S.Box(f, C.bg, C.border)
	f.state = { offset = 0, all = false, search = '' }

	local head = CreateFrame('Frame', nil, f)
	head:SetPoint('TOPLEFT', 1, -1); head:SetPoint('TOPRIGHT', -1, -1); head:SetHeight(30)
	S.Box(head, C.panel, { 0, 0, 0, 0 })
	local title = S.Text(head, 13, C.gold); title:SetPoint('LEFT', PAD, 0); title:SetText("What to buy with Merchant's Favor")
	local close = S.Button(head, 'x', 24, 22, function() f:Hide() end); close:SetPoint('RIGHT', -4, 0)

	local eb = CreateFrame('EditBox', PREFIX .. 'RecipeSearch', f)
	eb:SetSize(190, 24); eb:SetPoint('TOPLEFT', PAD, -38)
	S.Box(eb, C.panel, C.border)
	if not eb:SetFont(S.Font(), 12, '') then eb:SetFont(STANDARD_TEXT_FONT, 12, '') end
	eb:SetTextColor(C.text[1], C.text[2], C.text[3])
	eb:SetAutoFocus(false); eb:SetMaxLetters(40); eb:SetTextInsets(8, 8, 0, 0)
	eb.hint = S.Text(eb, 12, C.muted); eb.hint:SetPoint('LEFT', 8, 0); eb.hint:SetText('Search')
	eb:SetScript('OnTextChanged', function(self)
		local t = self:GetText() or ''
		self.hint:SetShown(t == '')
		if t ~= f.state.search then f.state.search, f.state.offset = t, 0; R.Draw() end
	end)
	eb:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)
	eb:SetScript('OnEscapePressed', function(self) self:SetText(''); self:ClearFocus() end)
	f.search = eb
	f.mineBtn = S.Button(f, 'My professions', 150, 24, function() f.state.all = not f.state.all; f.state.offset = 0; R.Draw() end)
	f.mineBtn:SetPoint('TOPRIGHT', -PAD, -38)
	tipFor(f.mineBtn, 'Whose recipes', "My professions: only recipes this character's professions can learn. Click for every recipe sold for Favor, and again to come back.")

	local hName = S.Text(f, 11, C.muted); hName:SetPoint('TOPLEFT', PAD + 24, -70); hName:SetText('RECIPE')
	local hProf = S.Text(f, 11, C.muted); hProf:SetPoint('TOPLEFT', W - PAD - PROF_W - 60, -70); hProf:SetText('NEEDS')
	local hFavor = S.Text(f, 11, C.muted, 'RIGHT'); hFavor:SetPoint('TOPRIGHT', -PAD - 4, -70); hFavor:SetText('FAVOR')

	local box = CreateFrame('Frame', nil, f)
	box:SetPoint('TOPLEFT', PAD, -86); box:SetSize(W - PAD * 2, SHOWN * RH + 8)
	S.Box(box, { 0.05, 0.05, 0.055, 0.9 }, C.border)
	box:EnableMouseWheel(true)
	box:SetScript('OnMouseWheel', function(_, d)
		local max = math.max(0, #(f.rows or {}) - SHOWN)
		f.state.offset = math.max(0, math.min(max, f.state.offset - d * 3))
		R.Draw(true)
	end)
	f.box = box
	f.empty = S.Text(box, 12, C.muted); f.empty:SetPoint('TOPLEFT', 8, -8); f.empty:SetWidth(W - PAD * 2 - 16); f.empty:SetWordWrap(true); f.empty:SetSpacing(3)
	f.lines = {}
	for i = 1, SHOWN do
		local r = CreateFrame('Button', nil, box)
		r:SetPoint('TOPLEFT', 4, -4 - (i - 1) * RH); r:SetSize(W - PAD * 2 - 8, RH)
		r.hi = r:CreateTexture(nil, 'BACKGROUND'); r.hi:SetAllPoints(); r.hi:SetColorTexture(1, 1, 1, 0.06); r.hi:Hide()
		r.tick = S.Text(r, 13, C.gold); r.tick:SetPoint('LEFT', 4, 0); r.tick:SetWidth(16)
		r.name = S.Text(r, 12, C.text); r.name:SetPoint('LEFT', 24, 0); r.name:SetWidth(W - PAD * 2 - 8 - 24 - PROF_W - 66); r.name:SetWordWrap(false)
		r.prof = S.Text(r, 11, C.muted); r.prof:SetPoint('LEFT', W - PAD * 2 - 8 - PROF_W - 60, 0); r.prof:SetWidth(PROF_W); r.prof:SetWordWrap(false)
		r.favor = S.Text(r, 12, C.text, 'RIGHT'); r.favor:SetPoint('RIGHT', -4, 0); r.favor:SetWidth(54)
		r:SetScript('OnClick', function(self) if self.row then R.Pick(self.row.id, not self.row.picked) end end)
		r:SetScript('OnEnter', function(self)
			self.hi:Show()
			if not self.row then return end
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.row.id) else GameTooltip:SetHyperlink('item:' .. self.row.id) end
			GameTooltip:Show()
		end)
		r:SetScript('OnLeave', function(self) self.hi:Hide(); GameTooltip:Hide() end)
		f.lines[i] = r
	end

	f.sum = S.Text(f, 13, C.text); f.sum:SetPoint('BOTTOMLEFT', PAD, 34); f.sum:SetWidth(W - PAD * 2 - 80)
	f.note = S.Text(f, 11, C.muted); f.note:SetPoint('BOTTOMLEFT', PAD, 12); f.note:SetWidth(W - PAD * 2); f.note:SetWordWrap(false)
	f.clear = S.Button(f, 'Clear', 64, 22, function() R.Clear() end); f.clear:SetPoint('BOTTOMRIGHT', -PAD, 30)
	tipFor(f.clear, 'Clear', 'Unticks every recipe, and sets the Favor wanted back to none.')
	if UISpecialFrames then table.insert(UISpecialFrames, PREFIX .. 'Recipes') end
	f:Hide()
	win = f
	return f
end

function R.Draw(keepScroll)
	local f = win
	if not f then return end
	if not keepScroll then
		R.Forget()
		f.rows, f.known, f.other = R.Rows({ all = f.state.all, search = f.state.search })
	end
	local rows = f.rows or {}
	f.state.offset = math.max(0, math.min(f.state.offset, math.max(0, #rows - SHOWN)))
	for i = 1, SHOWN do
		local line, r = f.lines[i], rows[f.state.offset + i]
		line.row = r
		if r then
			line.tick:SetText(r.picked and '|TInterface\\Buttons\\UI-CheckBox-Check:16:16|t' or (MUTED .. '\194\183|r'))
			line.name:SetText((r.picked and GOLD or WHITE) .. r.name .. '|r')
			local prof = r.other and (r.prof ~= OTHER and r.prof or '') or (r.profLocal or r.prof or '')
			local low = r.rank and r.skill and r.skill > r.rank
			local needs = prof .. ((r.skill or 0) > 0 and ((low and ' |cffff6060' or ' ') .. r.skill .. (low and '|r' or '')) or '')
			if r.standing then needs = needs .. (needs ~= '' and ', ' or '') .. (r.lowRep and '|cffff6060' or '') .. STANDINGS[r.standing] .. (r.lowRep and '|r' or '') end
			line.prof:SetText(needs)
			line.favor:SetText((r.favor or 0) > 0 and commas(r.favor) or (MUTED .. '?|r'))
			line:Show()
		else
			line:Hide()
		end
	end
	local total = #R.All()
	f.empty:SetShown(#rows == 0)
	if #rows == 0 then
		f.empty:SetText(total == 0 and "No recipes listed yet. Open the Favor vendor at the camp once: what they sell for Merchant's Favor is read and shows here."
			or (f.state.search ~= '' and 'Nothing matches the search.')
			or (not f.state.all and (f.other or 0) > 0 and ("None left for your professions. %d are for other professions: click My professions to see them."):format(f.other))
			or 'You already know every recipe sold for Favor.')
	end
	f.mineBtn:SetText(f.state.all and 'All professions' or 'My professions')
	local n, favor = R.Picked()
	local held = (ns.State.Favor(db())) or 0
	if n == 0 then
		f.sum:SetText(MUTED .. 'Click the recipes you want.|r')
	else
		f.sum:SetText(('%s%d picked: %s Favor|r  %s'):format(GOLD, n, commas(favor),
			held >= favor and (GREEN .. 'you have enough|r') or (MUTED .. ('you have %s, %s to get|r'):format(commas(held), commas(favor - held)))))
	end
	local bits = {}
	if n > 0 then bits[#bits + 1] = 'The Favor box follows your picks.' end
	if (f.known or 0) > 0 then bits[#bits + 1] = f.known .. ' already known: left out.' end
	if n == 0 and #rows > 0 then bits[#bits + 1] = 'Red: a skill or standing you are short of.' end
	if #rows > SHOWN then bits[#bits + 1] = ('%d-%d of %d (wheel)'):format(f.state.offset + 1, math.min(#rows, f.state.offset + SHOWN), #rows) end
	f.note:SetText(table.concat(bits, '  '))
	f.clear:SetShown(n > 0)
end

function R.Shown() return win and win:IsShown() or false end
function R.Toggle(show)
	local ui = ns.UI and ns.UI.parts and ns.UI.parts()
	if not win then build() end
	if show == nil then show = not win:IsShown() end
	if not show then win:Hide(); return end
	win:ClearAllPoints()
	if ui and ui.frame and ui.frame:IsShown() then
		win:SetPoint('TOPLEFT', ui.frame, 'TOPRIGHT', 6, 0)
		win:SetScale(ui.frame:GetScale() or 1)
	else
		win:SetPoint('CENTER')
	end
	win:Show()
	R.Draw()
end

local ev = CreateFrame('Frame')
ev:RegisterEvent('MERCHANT_SHOW')
ev:RegisterEvent('MERCHANT_UPDATE')
pcall(ev.RegisterEvent, ev, 'NEW_RECIPE_LEARNED')
pcall(ev.RegisterEvent, ev, 'GET_ITEM_INFO_RECEIVED')
local drawSoon = false
ev:SetScript('OnEvent', function(_, event)
	if not db() then return end
	if event == 'MERCHANT_SHOW' or event == 'MERCHANT_UPDATE' then
		pcall(R.ReadMerchant)
	elseif event == 'NEW_RECIPE_LEARNED' then
		R.Forget()
		apply()
		if win and win:IsShown() then R.Draw() end
	elseif win and win:IsShown() and not drawSoon and C_Timer then
		drawSoon = true
		C_Timer.After(0.5, function() drawSoon = false; if win and win:IsShown() then R.Draw() end end)
	end
end)
