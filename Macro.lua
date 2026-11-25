local ADDON, ns = ...
if ns.EDITION == 'favor' then return end
local Macro = {}
ns.Macro = Macro
Macro.NAME = 'Writs'
local ICON = 'INV_Misc_QuestionMark' -- (the game then shows the icon of what the macro will use)
local told

local function on() return not (ns.db and ns.db.settings and ns.db.settings.macro == false) end
function Macro.Body()
	local Nav = ns.Nav
	local pouch = Nav and Nav.Pouch()
	if pouch then return '/use item:' .. pouch, 'open a coin pouch' end
	local writ = Nav and Nav.WritMacro()
	if writ then return writ, 'use the writ' end
	local lb = ns.State and ns.State.Label and ns.State.Label()
	if lb and lb.held and not lb.done and not lb.onQuest then return '/use item:' .. lb.item, 'use the Shipping Label' end
	local R = ns.Plan and ns.Plan.RECEIPT
	local crate, _, _, _, clean
	if ns.NextStamp then crate, _, _, _, clean = ns.NextStamp() end
	local function stamp() return '/use item:' .. R.item .. '\n/use item:' .. crate .. '\n/click StaticPopup1Button1', 'a receipt onto a crate' end
	if crate and clean then return stamp() end
	local fill = ns.NextFill and ns.NextFill()
	if fill then return '/use item:' .. fill.crate .. '\n/use item:' .. fill.item .. '\n/click StaticPopup1Button1', 'fill a crate' end
	if crate then return stamp() end
	return '', 'nothing to do'
end
function Macro.Text() local body = Macro.Body(); return '#showtooltip' .. (body ~= '' and ('\n' .. body) or '') end

function Macro.Update(force)
	if not (on() or force) then return false end
	if not (GetMacroIndexByName and CreateMacro and EditMacro) then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	local text = Macro.Text()
	local i = GetMacroIndexByName(Macro.NAME) or 0
	if i == 0 then
		if text == '#showtooltip' and not force then return false end
		local n = GetNumMacros and GetNumMacros() or 0
		if n >= (MAX_ACCOUNT_MACROS or 120) then
			if not told then told = true; print('|cffffc840Writs and Favors|r: no room for its macro (your general macros are full).') end
			return false
		end
		local ok = pcall(CreateMacro, Macro.NAME, ICON, text, nil)
		if ok and not told then
			told = true
			print('|cffffc840Writs and Favors|r: made a macro called "Writs" (Esc, Macros, General). Put it on a key: it opens coin pouches, uses the step\'s writ, fills crates and puts receipts on them. /writs macro picks it up.')
		end
		return ok
	end
	if GetMacroBody and GetMacroBody(i) == text then return true end
	return (pcall(EditMacro, i, Macro.NAME, nil, text))
end
function Macro.Pickup()
	if InCombatLockdown and InCombatLockdown() then print('|cffffc840Writs and Favors|r: not in combat.'); return false end
	Macro.Update(true)
	local i = GetMacroIndexByName and GetMacroIndexByName(Macro.NAME) or 0
	if i == 0 or not PickupMacro then return false end
	PickupMacro(i)
	print('|cffffc840Writs and Favors|r: the "Writs" macro is on your cursor. Drop it on an action bar, then give that button a key.')
	return true
end

local BARS = { { 0, 'ACTIONBUTTON' }, { 60, 'MULTIACTIONBAR1BUTTON' }, { 48, 'MULTIACTIONBAR2BUTTON' }, { 24, 'MULTIACTIONBAR3BUTTON' }, { 36, 'MULTIACTIONBAR4BUTTON' } }
function Macro.Keys()
	local keys, seen = {}, {}
	local function add(...)
		for i = 1, select('#', ...) do
			local k = select(i, ...)
			if k and not seen[k] then seen[k] = true; keys[#keys + 1] = k end
		end
	end
	if not GetBindingKey then return keys end
	add(GetBindingKey('MACRO ' .. Macro.NAME))
	if not (GetActionInfo and GetActionText) then return keys end
	local function holds(slot)
		local ok, kind = pcall(GetActionInfo, slot)
		return ok and kind == 'macro' and GetActionText(slot) == Macro.NAME
	end
	for _, bar in ipairs(BARS) do
		for b = 1, 12 do
			if holds(bar[1] + b) then add(GetBindingKey(bar[2] .. b)) end
		end
	end
	for slot = 1, 120 do
		if holds(slot) then add(GetBindingKey('CLICK BT4Button' .. slot .. ':Keybind')); add(GetBindingKey('CLICK BT4Button' .. slot .. ':LeftButton')) end
	end
	return keys
end

local owner = CreateFrame('Frame')
local talk = {}
function Macro.Talking() return talk.on and true or false end
function Macro.TalkOff()
	if not talk.on then return end
	if InCombatLockdown and InCombatLockdown() then talk.clear = true return end
	talk.on, talk.clear = nil, nil
	if ClearOverrideBindings then pcall(ClearOverrideBindings, owner) end
	if ns.Log then ns.Log('hand-in key: off') end
end
function Macro.TalkOn(more)
	if not on() or not (SetOverrideBinding and UnitExists) then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	talk.more, talk.till = more, (GetTime and GetTime() or 0) + 30
	if talk.on then return true end
	if not UnitExists('target') then
		if ns.Log then ns.Log('hand-in key: nothing targeted, left') end
		return false
	end
	local keys = Macro.Keys()
	if #keys == 0 then
		if ns.Log then ns.Log('hand-in key: the Writs macro has no key') end
		if not talk.told then talk.told = true; print('|cffffc840Writs and Favors|r: the game closes the window after each crate. Put the "Writs" macro on a key (/writs macro) and that key will talk to the hand-in for each next crate.') end
		return false
	end
	for _, k in ipairs(keys) do pcall(SetOverrideBinding, owner, true, k, 'INTERACTTARGET') end
	talk.on, talk.name = true, UnitName and UnitName('target') or nil
	if ns.Log then ns.Log('hand-in key: ' .. table.concat(keys, ', ') .. ' talks to ' .. tostring(talk.name)) end
	if not talk.said then talk.said = true; print('|cffffc840Writs and Favors|r: press your Writs key (' .. keys[1] .. ') for each next crate: it talks to the hand-in for you.') end
	local function watch()
		if not talk.on then return end
		local ok, left = pcall(talk.more)
		if not (ok and left) or (GetTime and GetTime() or 0) > talk.till or not UnitExists('target') or (UnitName and UnitName('target')) ~= talk.name then return Macro.TalkOff() end
		C_Timer.After(0.5, watch)
	end
	if C_Timer and C_Timer.After then C_Timer.After(0.5, watch) end
	return true
end

local ev = CreateFrame('Frame')
for _, e in ipairs({ 'PLAYER_LOGIN', 'BAG_UPDATE_DELAYED', 'PLAYER_REGEN_ENABLED' }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_LOGIN' and C_Timer and C_Timer.After then C_Timer.After(3, function() pcall(Macro.Update) end) return end
	if event == 'PLAYER_REGEN_ENABLED' and talk.clear then Macro.TalkOff() end
	pcall(Macro.Update)
end)
