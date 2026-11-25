local ADDON, ns = ...
local S, C = ns.Skin, ns.Skin.colors
local Options = {}
ns.Options = Options

local function s() return ns.db and ns.db.settings end

Options.items = {
	{ key = 'tooltips', text = 'Prices on item tooltips',
	  tip = 'Hovering a writ, a writ\'s item, a Waylaid Crate or something that fills one shows what it costs you and what it gives. Off: those tooltips are left as the game has them.',
	  get = function() return s().tooltips ~= false end, set = function(v) s().tooltips = v and true or false end },
	{ key = 'myLevel', text = 'Only plan writ hand-ins for my level',
	  tip = 'Below level 45 the plan takes you to Friendly with the quickest hand-ins near home (Horde: Ashenvale, the south of Felwood, Stonetalon), adding others only if those are not enough; from 45 it goes to zones up to 3 levels above yours. Off: any hand-in, wherever it is.',
	  get = function() return not s().allZones end, set = function(v) s().allZones = (not v) or nil end },
	{ key = 'minimap', text = 'Minimap button',
	  tip = 'The button on the minimap: left-click for the panel, right-click for the table of every writ and crate. Off: /writs still opens the panel.',
	  get = function() return not s().minimapHide end, set = function(v) s().minimapHide = (not v) or nil; if ns.ShowMinimap then ns.ShowMinimap() end end },
	{ key = 'remind', text = 'Ask before buying when the mailbox or bank hasn\'t been opened',
	  tip = 'What\'s in your mailbox and bank is only counted once you\'ve opened them that day. On: the first Buy click asks, so you don\'t buy what you already have. Off: it buys straight away.',
	  get = function() return s().remind ~= false end, set = function(v) s().remind = v and true or false end },
	{ key = 'autoHandIn', text = 'Hand in Sealed crates when you talk to the crate hand-in',
	  tip = 'Talking to Dokimi (Horde) or Marcy Baker (Alliance) hands in your Sealed crates, one for each quest window. Hold Shift to talk normally. Off: you hand them in yourself.',
	  get = function() return s().autoHandIn ~= false end, set = function(v) s().autoHandIn = v and true or false end },
	{ key = 'autoMail', text = 'Guide: take the step\'s things out of the mailbox',
	  tip = 'While the guide runs (Guide me) and its step is a mailbox, opening the mailbox takes out the writs and items that step asks for, and your crates. Mail with money to pay is never touched. Off: you take them out yourself.',
	  get = function() return s().autoMail ~= false end, set = function(v) s().autoMail = v and true or false end },
	{ key = 'macro', text = 'Keep a "Writs" macro for a key',
	  tip = 'One macro among your general macros that always does what\'s next: opens a coin pouch, uses the step\'s writ, fills a crate or puts a receipt on one. Put it on a key and press it as often as you like. Off: the macro is left as it is and no longer updated.',
	  get = function() return s().macro ~= false end, set = function(v) s().macro = v and true or false; if v and ns.Macro then ns.Macro.Update() end end },
	{ key = 'star', text = 'Guide: put a star on who takes the writ',
	  tip = 'While the guide runs (Guide me), its button targets who takes the writ and marks them with a star so they\'re easy to spot. Off: they\'re targeted and not marked.',
	  get = function() return s().star ~= false end, set = function(v) s().star = v and true or false end },
}
local function after() if ns.UI and ns.UI.refresh then pcall(ns.UI.refresh) end end
function Options.Set(key, v)
	for _, it in ipairs(Options.items) do
		if it.key == key then it.set(v); after(); return true end
	end
	return false
end
function Options.Get(key)
	for _, it in ipairs(Options.items) do if it.key == key then return it.get() end end
end

local panel, category
local function tipOn(frame, title, text)
	frame:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:AddLine(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:HookScript('OnLeave', function() GameTooltip:Hide() end)
end
local function build()
	local p = CreateFrame('Frame', 'WritsAndFavorsOptions')
	p.name = 'Writs and Favors'
	local title = S.Text(p, 18, C.gold); title:SetPoint('TOPLEFT', 16, -16); title:SetText('Writs and Favors')
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local ver = S.Text(p, 12, C.muted); ver:SetPoint('LEFT', title, 'RIGHT', 10, -1)
	ver:SetText('version ' .. tostring(meta and meta(ADDON, 'Version') or '?'))
	local sub = S.Text(p, 12, C.muted); sub:SetPoint('TOPLEFT', 16, -44); sub:SetWidth(560); sub:SetWordWrap(true)
	sub:SetText('The standing to reach, the days and cheaper or quicker are on the panel itself (/writs, or open the Auction House).')

	p.checks = {}
	local y = -78
	for _, it in ipairs(Options.items) do
		local cb = CreateFrame('CheckButton', nil, p, 'UICheckButtonTemplate')
		cb:SetSize(26, 26)
		cb:SetPoint('TOPLEFT', 14, y)
		cb.label = S.Text(p, 13, C.text); cb.label:SetPoint('LEFT', cb, 'RIGHT', 4, 0); cb.label:SetText(it.text)
		cb:SetHitRectInsets(0, -420, 0, 0)
		cb:SetScript('OnClick', function(self)
			Options.Set(it.key, not it.get())
			self:SetChecked(it.get())
		end)
		tipOn(cb, it.text, it.tip)
		cb.item = it
		p.checks[#p.checks + 1] = cb
		y = y - 30
	end

	y = y - 12
	local sl = S.Text(p, 13, C.text); sl:SetPoint('TOPLEFT', 18, y); sl:SetText('Size of the panel')
	p.scaleText = S.Text(p, 13, C.gold); p.scaleText:SetPoint('LEFT', sl, 'RIGHT', 10, 0)
	local sc = S.Slider(p, 260)
	sc:SetPoint('TOPLEFT', 18, y - 24)
	sc:SetMinMaxValues(70, 160)
	sc:SetValueStep(5)
	if sc.SetObeyStepOnDrag then sc:SetObeyStepOnDrag(true) end
	sc:SetScript('OnValueChanged', function(_, v)
		if p.filling then return end
		v = math.floor(v / 5 + 0.5) * 5
		if ns.UI and ns.UI.setScale then ns.UI.setScale(v / 100) elseif s() then s().scale = v / 100 end
		p.scaleText:SetText(v .. '%')
	end)
	tipOn(sc, 'Size of the panel', 'How big the panel and the table are drawn. The A- and A+ buttons on the panel do the same.')
	p.scale = sc
	y = y - 62

	local reset = S.Button(p, 'Put the panel back', 160, 26, function() if ns.UI and ns.UI.resetPos then ns.UI.resetPos() end end)
	reset:SetPoint('TOPLEFT', 18, y)
	tipOn(reset, 'Put the panel back', 'Moves the panel back beside the Auction House, if you dragged it somewhere.')
	local open = S.Button(p, 'Open the panel', 140, 26, function()
		if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
		if ns.UI and ns.UI.toggle then ns.UI.toggle(true) end
	end, true)
	open:SetPoint('LEFT', reset, 'RIGHT', 8, 0)
	local tour = S.Button(p, 'Show the tour', 130, 26, function()
		if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
		if ns.UI and ns.UI.toggle then ns.UI.toggle(true) end
		if ns.Tour then ns.Tour.Start() end
	end)
	tour:SetPoint('LEFT', open, 'RIGHT', 8, 0)
	tipOn(tour, 'Show the tour', 'Seven short steps round the panel: what each part is for.')
	local mac = S.Button(p, 'Pick up the macro', 150, 26, function() if ns.Macro then ns.Macro.Pickup() end end)
	mac:SetPoint('TOPLEFT', reset, 'BOTTOMLEFT', 0, -8)
	tipOn(mac, 'Pick up the macro', 'Puts the "Writs" macro on your cursor: drop it on an action bar and give that button a key.')

	local function fill()
		if not s() then return end
		p.filling = true
		for _, cb in ipairs(p.checks) do cb:SetChecked(cb.item.get()) end
		local v = math.floor((s().scale or 1) * 100 + 0.5)
		sc:SetValue(v)
		p.scaleText:SetText(v .. '%')
		p.filling = false
	end
	p.Fill = fill
	p:SetScript('OnShow', fill)
	return p
end

local function register()
	if panel or not s() then return end
	panel = build()
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
	Options.panel = panel
end

function Options.Open()
	register()
	if not panel then return false end
	if InCombatLockdown and InCombatLockdown() then
		print('|cffffc840Writs and Favors|r: not in combat. Open the options again once the fight is over')
		return false
	end
	if category and Settings and Settings.OpenToCategory then
		local id = category.GetID and category:GetID() or category.ID
		return (pcall(Settings.OpenToCategory, id))
	elseif InterfaceOptionsFrame_OpenToCategory then
		pcall(InterfaceOptionsFrame_OpenToCategory, panel)
		return (pcall(InterfaceOptionsFrame_OpenToCategory, panel))
	end
	return false
end

local ev = CreateFrame('Frame')
ev:RegisterEvent('PLAYER_LOGIN')
ev:SetScript('OnEvent', function() pcall(register) end)
