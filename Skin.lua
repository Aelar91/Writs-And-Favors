local _, ns = ...
local S = {}
ns.Skin = S

local WHITE = 'Interface\\Buttons\\WHITE8X8'
S.colors = {
	bg = { 0.067, 0.067, 0.071, 0.94 },
	panel = { 0.11, 0.11, 0.118, 0.96 },
	border = { 0.22, 0.22, 0.24, 1 },
	hover = { 0.17, 0.17, 0.18, 1 },
	text = { 0.92, 0.92, 0.92 },
	muted = { 0.58, 0.58, 0.6 },
	gold = { 1, 0.78, 0.25 },
	green = { 0.35, 0.8, 0.45 },
	red = { 1, 0.36, 0.36 },
}
local C = S.colors

local font
function S.Font()
	if font then return font end
	local lsm = LibStub and LibStub('LibSharedMedia-3.0', true)
	local f = lsm and lsm:Fetch('font', 'Expressway', true)
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if not f and loaded and loaded('EllesmereUI') then f = 'Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF' end
	font = f or STANDARD_TEXT_FONT
	return font
end

function S.Box(f, bg, border)
	bg, border = bg or C.bg, border or C.border
	if not f.skinBg then
		f.skinBg = f:CreateTexture(nil, 'BACKGROUND', nil, -8)
		f.skinBg:SetTexture(WHITE)
		f.skinBg:SetAllPoints()
		f.skinEdge = {}
		for i, pts in ipairs({ { 'TOPLEFT', 'TOPRIGHT', nil, 1 }, { 'BOTTOMLEFT', 'BOTTOMRIGHT', nil, 1 }, { 'TOPLEFT', 'BOTTOMLEFT', 1, nil }, { 'TOPRIGHT', 'BOTTOMRIGHT', 1, nil } }) do
			local t = f:CreateTexture(nil, 'BORDER', nil, 7)
			t:SetTexture(WHITE)
			t:SetPoint(pts[1]); t:SetPoint(pts[2])
			if pts[3] then t:SetWidth(pts[3]) else t:SetHeight(pts[4]) end
			f.skinEdge[i] = t
		end
	end
	f.skinBg:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
	for _, t in ipairs(f.skinEdge) do t:SetVertexColor(border[1], border[2], border[3], border[4] or 1) end
end

local fresh, waiting = {}, false
local function settle()
	waiting = false
	local list = fresh
	fresh = {}
	for _, t in ipairs(list) do
		local s = t.GetText and t:GetText()
		if s and s ~= '' then t:SetText(''); t:SetText(s) end
	end
end
S.Settle = settle

function S.Text(parent, size, color, justify)
	local t = parent:CreateFontString(nil, 'OVERLAY')
	if not t:SetFont(S.Font(), size or 12, '') then t:SetFont(STANDARD_TEXT_FONT, size or 12, '') end
	fresh[#fresh + 1] = t
	if not waiting and C_Timer and C_Timer.After then waiting = true; C_Timer.After(0.1, settle) end
	local c = color or C.text
	t:SetTextColor(c[1], c[2], c[3])
	t:SetJustifyH(justify or 'LEFT')
	t:SetShadowOffset(1, -1)
	t:SetShadowColor(0, 0, 0, 0.6)
	return t
end

function S.Button(parent, text, w, h, onClick, accent)
	local b = CreateFrame('Button', nil, parent)
	b:SetSize(w, h or 24)
	S.Box(b, C.panel, accent and { C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6, 1 } or C.border)
	b.label = S.Text(b, 12, accent and C.gold or C.text, 'CENTER')
	b.label:SetPoint('CENTER', 0, 0)
	b.label:SetWidth(math.max(1, w - 12))
	b.label:SetWordWrap(false)
	b:SetScript('OnSizeChanged', function(self, bw) if bw and bw > 12 then self.label:SetWidth(bw - 12) end end)
	b.SetText = function(self, s) self.label:SetText(s) end
	b.GetText = function(self) return self.label:GetText() end
	b:SetText(text)
	b:SetScript('OnEnter', function(self) if self:IsEnabled() then S.Box(self, C.hover, C.gold) end end)
	b:SetScript('OnLeave', function(self) S.Box(self, C.panel, accent and { C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6, 1 } or C.border) end)
	b:SetScript('OnDisable', function(self) self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
	b:SetScript('OnEnable', function(self) local c = accent and C.gold or C.text; self.label:SetTextColor(c[1], c[2], c[3]) end)
	if onClick then b:SetScript('OnClick', onClick) end
	return b
end

function S.Bar(parent, w, h)
	local bar = CreateFrame('StatusBar', nil, parent)
	bar:SetSize(w, h)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(C.green[1], C.green[2], C.green[3])
	S.Box(bar, { 0.16, 0.16, 0.17, 1 }, C.border)
	return bar
end

function S.Slider(parent, w)
	local s = CreateFrame('Slider', nil, parent)
	s:SetOrientation('HORIZONTAL')
	s:SetSize(w, 16)
	local track = s:CreateTexture(nil, 'BACKGROUND')
	track:SetTexture(WHITE); track:SetVertexColor(0.25, 0.25, 0.27, 1)
	track:SetPoint('LEFT'); track:SetPoint('RIGHT'); track:SetHeight(3)
	local th = s:CreateTexture(nil, 'OVERLAY')
	th:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
	th:SetSize(10, 16)
	s:SetThumbTexture(th)
	return s
end

function S.Heading(parent, text)
	local t = S.Text(parent, 11, C.muted)
	t:SetText(text:upper())
	return t
end
