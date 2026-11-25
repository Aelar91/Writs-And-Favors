local ADDON, ns = ...
local S = ns.Skin
local C = S.colors
local Tour = {}
ns.Tour = Tour

local STEPS = {
	{ 'Welcome', "This plans your Craftsman's Writs: which to buy for the least gold, and the quickest route to hand them in. Six short steps show you round." },
	{ 'What you want', 'Pick the standing to reach and by when. More days means fewer and cheaper writs each day, because a writ can be handed in once a day.', 'goal', 'days' },
	{ 'Scan', "Scan reads the Auction House's prices for the writs and their items. The plan is then made for you, and made again whenever you change something.", 'scan' },
	{ 'Buy', 'The list is what to buy. The gold button buys the next line at its live price: one click each. Skip leaves a line out.', 'box', 'buy' },
	{ 'The way round', 'Once it is bought, Guide me takes you through the hand-ins step by step: a waypoint for each place and the hand-ins done for you. Send to RestedXP opens the same route as a RestedXP guide.', 'guide', 'rxp' },
	{ 'The rest', "The Favor box is the Merchant's Favor you want to hold at the end; Recipes beside it adds up the recipes you tick. Pick No reputation to plan Favor alone. Browse lists every writ and crate in a table you can buy from. The cog has the options.", 'optsBtn', 'browseBtn' },
}
Tour.STEPS = STEPS

local win, ring, at
local function settings() return ns.db and ns.db.settings end
local function parts() return ns.UI and ns.UI.parts and ns.UI.parts() end

local function build()
	local w = CreateFrame('Frame', 'WritsAndFavorsTour', UIParent)
	w:SetSize(300, 150)
	w:SetFrameStrata('FULLSCREEN_DIALOG')
	w:EnableMouse(true)
	S.Box(w, C.panel, C.gold)
	w.count = S.Text(w, 11, C.muted, 'RIGHT'); w.count:SetPoint('TOPRIGHT', -12, -13)
	w.title = S.Text(w, 14, C.gold); w.title:SetPoint('TOPLEFT', 12, -11)
	w.text = S.Text(w, 12, C.text); w.text:SetPoint('TOPLEFT', 12, -36); w.text:SetWidth(276); w.text:SetWordWrap(true); w.text:SetSpacing(3)
	w.skip = S.Button(w, 'Skip the tour', 100, 24, function() Tour.Stop(true) end); w.skip:SetPoint('BOTTOMLEFT', 12, 10)
	w.next = S.Button(w, 'Next', 70, 24, function() Tour.Go(1) end, true); w.next:SetPoint('BOTTOMRIGHT', -12, 10)
	w.back = S.Button(w, 'Back', 60, 24, function() Tour.Go(-1) end); w.back:SetPoint('RIGHT', w.next, 'LEFT', -6, 0)
	w:Hide()
	local r = CreateFrame('Frame', nil, UIParent)
	r:SetFrameStrata('FULLSCREEN_DIALOG')
	S.Box(r, { 1, 0.78, 0.25, 0.08 }, C.gold)
	r:Hide()
	return w, r
end

local function draw()
	local ui = parts()
	if not (at and ui and ui.frame and ui.frame:IsShown()) then
		if win then win:Hide(); ring:Hide() end
		return
	end
	if not win then win, ring = build() end
	local s = STEPS[at]
	win.title:SetText(s[1])
	win.text:SetText(s[2])
	win.count:SetText(at .. ' of ' .. #STEPS)
	win.next:SetText(at == #STEPS and 'Done' or 'Next')
	if at > 1 then win.back:Enable() else win.back:Disable() end
	win:SetScale(ui.frame:GetScale() or 1)
	win:ClearAllPoints()
	local right = ui.frame:GetRight()
	local wide = UIParent:GetWidth()
	if right and wide and right * (ui.frame:GetScale() or 1) + 320 > wide then win:SetPoint('TOPRIGHT', ui.frame, 'TOPLEFT', -8, 0)
	else win:SetPoint('TOPLEFT', ui.frame, 'TOPRIGHT', 8, 0) end
	local h = win.text:GetStringHeight()
	win:SetHeight(36 + ((h and h > 10) and h or 60) + 14 + 24 + 10)
	win:Show()
	local a, b = s[3] and ui[s[3]], s[4] and ui[s[4]]
	b = b or a
	if a and b and a.IsShown and a:IsShown() then
		ring:ClearAllPoints()
		ring:SetPoint('TOPLEFT', a, 'TOPLEFT', -4, 4)
		ring:SetPoint('BOTTOMRIGHT', b, 'BOTTOMRIGHT', 4, -4)
		ring:Show()
	else
		ring:Hide()
	end
end

function Tour.Active() return at ~= nil end
function Tour.Step() return at end
function Tour.Start()
	if not parts() then return false end
	at = 1
	draw()
	return true
end
function Tour.Stop(done)
	at = nil
	if done and settings() then settings().tour = true end
	draw()
end
function Tour.Go(by)
	if not at then return end
	if at + by > #STEPS then return Tour.Stop(true) end
	at = math.max(1, at + by)
	draw()
end
function Tour.Auto()
	local s = settings()
	if not s or s.tour or at then return end
	if C_Timer and C_Timer.After then C_Timer.After(0.5, function() if not (settings() or {}).tour and not at then Tour.Start() end end) end
end
function Tour.Closed() if at then at = nil; draw() end end
