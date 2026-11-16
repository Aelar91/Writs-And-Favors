local _, ns = ...
if ns.EDITION == 'favor' then return end
local S = ns.Skin
local R = {}
ns.OMRoute = R

local GOLD = { 0.95, 0.78, 0.35 }              -- OpenMap's flight-route gold
local EDGE = { 0.25, 0.16, 0.05 }              -- and its lines' dark edge
local RIDE = { 0.97, 0.94, 0.86 }              -- riding: parchment white
local SEA = { 0.45, 0.75, 1 }                  -- a boat or zeppelin: dots
local LIT = { 0.45, 1, 0.6 }                   -- a highlighted leg and its stops
local INK = { 0.13, 0.09, 0.05, 0.94 }         -- the markers' dark middle
local CORE, RIM = 1.6, 3.4                     -- line widths, px on screen
local MARK, CLUSTER_PX, LEG_LABEL_PX = 20, 24, 70
local CIRCLE = 'Interface\\CharacterFrame\\TempPortraitAlphaMask'

local function API()
	local OM = rawget(_G, 'OpenMapAPI')
	if type(OM) == 'table' and OM.major == 1 and OM.WorldFromMap and OM.MapFromWorld and OM.IsStitched then return OM end
end
function R.Available() return API() ~= nil and rawget(_G, 'WorldMapFrame') ~= nil end
local function stitched() local OM = API(); return OM and OM.IsStitched() and WorldMapFrame:IsShown() end

local data, on, hot          -- the route (UI.lua's map data), drawn or not, the highlighted leg
local layer, dirty
local pool = { mark = {}, cluster = {}, caption = {}, line = {}, dot = {}, other = {}, ocluster = {}, zbadge = {}, zdot = {} }
local ZONE_ZOOM = 4.5
local function hex(c) return ('|cff%02x%02x%02x'):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end
local used = {}
local last = {}              -- what the last layout was for: host map, canvas scale and size, the view box

local function world(p)
	if not p then return end
	if p.u == nil and p.map and p.zx then
		local OM = API()
		local u, v = OM.WorldFromMap(p.map, p.zx / 100, p.zy / 100)
		if u then p.u, p.v = u, v else return end
	end
	return p.u and p
end

local function take(kind, make)
	used[kind] = (used[kind] or 0) + 1
	local o = pool[kind][used[kind]]
	if not o then o = make(); pool[kind][used[kind]] = o end
	o:Show()
	return o
end
local function circle(f, layerName, sub, size, color)
	local t = f:CreateTexture(nil, layerName, nil, sub)
	t:SetColorTexture(1, 1, 1, 1)
	t:SetSize(size, size); t:SetPoint('CENTER')
	local m = f:CreateMaskTexture()
	m:SetTexture(CIRCLE, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
	m:SetAllPoints(t)
	t:AddMaskTexture(m)
	t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	return t
end
local function font(fs, size) if not fs:SetFont(STANDARD_TEXT_FONT, size, 'OUTLINE') then fs:SetFontObject(GameFontHighlight) end end
local function hoverable(f)
	f:EnableMouse(true)
	f:SetScript('OnEnter', function(self)
		if self.leg then R.Highlight(self.leg, true) end
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		for i, line in ipairs(self.tip or {}) do GameTooltip:AddLine(line, 1, i == 1 and 0.82 or 1, i == 1 and 0 or 1, true) end
		GameTooltip:Show()
	end)
	f:SetScript('OnLeave', function(self) if self.leg then R.Highlight(self.leg, false) end GameTooltip:Hide() end)
	f:SetScript('OnMouseUp', function(self, btn) if btn == 'LeftButton' and self.click then self.click() end end)
end
local function newMark(size)
	size = size or MARK
	local f = CreateFrame('Frame', nil, layer)
	f:SetSize(size, size)
	f.shadow = circle(f, 'BACKGROUND', 0, size + 3, { 0, 0, 0, 0.75 })
	f.ring = circle(f, 'BORDER', 0, size, GOLD)
	f.fill = circle(f, 'ARTWORK', 0, size - 4, INK)
	f.n = f:CreateFontString(nil, 'OVERLAY'); font(f.n, 11)
	f.n:SetSize(size + 8, size); f.n:SetPoint('CENTER', f.ring, 'CENTER', 0.5, 0)
	f.n:SetJustifyH('CENTER'); f.n:SetJustifyV('MIDDLE'); f.n:SetWordWrap(false); f.n:SetTextColor(1, 0.9, 0.6)
	f.badge = CreateFrame('Frame', nil, f)
	f.badge:SetSize(14, 14); f.badge:SetPoint('CENTER', f, 'TOPRIGHT', -1, -1)
	f.badge.shadow = circle(f.badge, 'BACKGROUND', 0, 16, { 0, 0, 0, 0.8 })
	f.badge.fill = circle(f.badge, 'ARTWORK', 0, 13, GOLD)
	f.badge.n = f.badge:CreateFontString(nil, 'OVERLAY'); f.badge.n:SetFont(STANDARD_TEXT_FONT, 9, '')
	f.badge.n:SetSize(18, 14); f.badge.n:SetPoint('CENTER', f.badge.fill, 'CENTER', 0.5, 0); f.badge.n:SetJustifyH('CENTER'); f.badge.n:SetJustifyV('MIDDLE')
	f.badge.n:SetTextColor(0.1, 0.07, 0.03); f.badge.n:SetShadowOffset(0, 0)
	f.mail = f.badge:CreateTexture(nil, 'OVERLAY'); f.mail:SetAllPoints(); f.mail:SetTexture('Interface\\Minimap\\Tracking\\Mailbox')
	hoverable(f)
	return f
end
local function newCluster()
	local f = CreateFrame('Frame', nil, layer)
	f:SetSize(80, 20)
	local function plate(inset, c, sub)
		local t = f:CreateTexture(nil, 'BACKGROUND', nil, sub)
		t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		t:SetPoint('TOPLEFT', inset, -inset); t:SetPoint('BOTTOMRIGHT', -inset, inset)
	end
	plate(-2, { 0, 0, 0, 0.6 }, 0); plate(0, { GOLD[1], GOLD[2], GOLD[3], 0.9 }, 1); plate(1, INK, 2)
	f.t = f:CreateFontString(nil, 'OVERLAY'); font(f.t, 12); f.t:SetPoint('CENTER', 0, 0)
	hoverable(f)
	return f
end
local function newCaption()
	local f = CreateFrame('Frame', nil, layer)
	f:SetSize(40, 14)
	f.t = f:CreateFontString(nil, 'OVERLAY'); font(f.t, 11); f.t:SetPoint('CENTER'); f.t:SetTextColor(1, 1, 1, 0.9)
	hoverable(f)
	return f
end
local function newLine() return layer:CreateLine(nil, 'ARTWORK') end
local function newDot() local t = layer:CreateTexture(nil, 'ARTWORK'); t:SetTexture('Interface\\Buttons\\WHITE8X8'); return t end

local function clip(a, b, v)
	local x0, y0, dx, dy = a.x, a.y, b.x - a.x, b.y - a.y
	local t0, t1 = 0, 1
	for _, pq in ipairs({ { -dx, x0 - v.l }, { dx, v.r - x0 }, { -dy, y0 - v.t }, { dy, v.b - y0 } }) do
		local p, q = pq[1], pq[2]
		if p == 0 then if q < 0 then return end
		else
			local r = q / p
			if p < 0 then if r > t1 then return end if r > t0 then t0 = r end
			else if r < t0 then return end if r < t1 then t1 = r end end
		end
	end
	return { x = x0 + dx * t0, y = y0 + dy * t0 }, { x = x0 + dx * t1, y = y0 + dy * t1 }
end
local function piece(x1, y1, x2, y2, c, rec)
	for k = 1, 2 do
		local l = take('line', newLine)
		local w = k == 1 and RIM or CORE
		local col = k == 1 and EDGE or c
		l:SetDrawLayer('ARTWORK', k)
		l:SetThickness(w)
		l:SetColorTexture(col[1], col[2], col[3], k == 1 and 0.8 or 0.95)
		l:ClearAllPoints()
		l:SetStartPoint('TOPLEFT', layer, x1, -y1)
		l:SetEndPoint('TOPLEFT', layer, x2, -y2)
		if k == 2 then rec[#rec + 1] = { l, 'line', c } end
	end
end
local function dot(x, y, c, rec)
	for k = 1, 2 do
		local t = take('dot', newDot)
		local s = k == 1 and 6.5 or 4
		t:SetDrawLayer('ARTWORK', k)
		t:SetSize(s, s)
		local col = k == 1 and EDGE or c
		t:SetVertexColor(col[1], col[2], col[3], k == 1 and 0.8 or 1)
		t:ClearAllPoints(); t:SetPoint('CENTER', layer, 'TOPLEFT', x, -y)
		if k == 2 then rec[#rec + 1] = { t, 'dot', c } end
	end
end
local function seg(a, b, style, box, rec)
	a, b = clip(a, b, box)
	if not a then return end
	local dx, dy = b.x - a.x, b.y - a.y
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then return end
	if style == 'boat' then
		for d = 0, len, 9 do dot(a.x + dx * d / len, a.y + dy * d / len, SEA, rec) end
	elseif style == 'fly' then
		local d = 0
		while d < len do
			local e = math.min(len, d + 9)
			piece(a.x + dx * d / len, a.y + dy * d / len, a.x + dx * e / len, a.y + dy * e / len, GOLD, rec)
			d = e + 6
		end
	else
		piece(a.x, a.y, b.x, b.y, RIDE, rec)
	end
end

local function hideAll()
	for _, list in pairs(pool) do for _, o in ipairs(list) do o:Hide() end end
	if layer then layer:Hide() end
end

local function viewNow()
	local canvas = WorldMapFrame:GetCanvas()
	local sc = WorldMapFrame.ScrollContainer
	if not (canvas and sc) then return end
	local cs = canvas:GetScale()
	local cw, ch = canvas:GetWidth(), canvas:GetHeight()
	local cl, ct = canvas:GetLeft(), canvas:GetTop()
	local sl, st, sw, sh = sc:GetLeft(), sc:GetTop(), sc:GetWidth(), sc:GetHeight()
	if not (cs and cs > 0 and cw and cw > 0 and cl and sl) then return end
	local ce, se = canvas:GetEffectiveScale(), sc:GetEffectiveScale()
	local e = ce / cs                                   -- the layer's effective scale
	local vl, vt = (sl * se - cl * ce) / e, (ct * ce - st * se) / e
	return { host = WorldMapFrame:GetMapID(), cs = cs, cw = cw, ch = ch, l = vl, t = vt, w = sw * se / e, h = sh * se / e }
end

local function layout(v)
	used = {}
	local OM = API()
	layer:SetParent(WorldMapFrame:GetCanvas())
	layer:SetFrameLevel((OM.ArtTopLevel and OM.ArtTopLevel() or 2000) + 40)
	layer:SetScale(1 / v.cs)
	layer:ClearAllPoints(); layer:SetPoint('TOPLEFT', WorldMapFrame:GetCanvas(), 'TOPLEFT')
	layer:SetSize(v.cw * v.cs, v.ch * v.cs)
	layer:Show()
	local box = { l = v.l - v.w, r = v.l + 2 * v.w, t = v.t - v.h, b = v.t + 2 * v.h }
	last = { host = v.host, cs = v.cs, cw = v.cw, l = v.l, t = v.t, w = v.w, h = v.h }
	local function P(p)
		p = world(p)
		if not p then return end
		local x, y = OM.MapFromWorld(v.host, p.u, p.v)
		if not x then return end
		return { x = x * v.cw * v.cs, y = y * v.ch * v.cs }
	end
	local near = function(q) return q.x > box.l and q.x < box.r and q.y > box.t and q.y < box.b end
	for li, leg in ipairs(data.legs) do
		leg.omDrawn, leg.omCaption = {}, nil
		for _, s in ipairs(leg.segs) do
			local a, b = P(s[1]), P(s[2])
			if a and b then seg(a, b, s[3], box, leg.omDrawn) end
		end
		local a, b = P(leg.from), P(leg.to)
		if a and b and math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) >= LEG_LABEL_PX then
			local m = { x = (a.x + b.x) / 2, y = (a.y + b.y) / 2 }
			if near(m) then
				local c = take('caption', newCaption)
				c.t:SetText(leg.min .. ' min'); c.t:SetTextColor(1, 1, 1, 0.9)
				c:SetSize((c.t:GetStringWidth() or 30) + 6, 14)
				c:ClearAllPoints(); c:SetPoint('CENTER', layer, 'TOPLEFT', m.x, -m.y)
				c.tip, c.leg, c.click = leg.tip, li, nil
				leg.omCaption = c
			end
		end
	end
	local groups = {}
	for _, st in ipairs(data.stops) do
		st.omFrame = nil
		local q = P(st.pos)
		if q and near(q) then
			local g
			for _, c in ipairs(groups) do if (c.x - q.x) ^ 2 + (c.y - q.y) ^ 2 < CLUSTER_PX ^ 2 then g = c; break end end
			if g then g.members[#g.members + 1] = st else groups[#groups + 1] = { x = q.x, y = q.y, members = { st } } end
		end
	end
	local function mark(s, q, label, badge)
		local f = take('mark', newMark)
		f:ClearAllPoints(); f:SetPoint('CENTER', layer, 'TOPLEFT', q.x, -q.y)
		f.n:SetText(label)
		f.badge:SetShown(badge ~= nil)
		f.mail:SetShown(badge == 'M'); f.badge.fill:SetShown(badge ~= 'M'); f.badge.n:SetShown(badge ~= 'M')
		if badge and badge ~= 'M' then f.badge.n:SetText(badge) end
		f.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
		f.tip, f.leg, f.click = s.tip, nil, nil
		f:SetFrameLevel((layer:GetFrameLevel() or 0) + 3)
		s.omFrame = f
		return f
	end
	local sq = P(data.start.pos)
	data.start.omFrame = nil
	if sq and near(sq) then mark(data.start, sq, 'S').click = function() R.Go(data.start.pos) end end
	for _, g in ipairs(groups) do
		if #g.members == 1 then
			local s = g.members[1]
			local f = mark(s, g, tostring(s.n), s.badge)
			f.leg = s.n
			f.click = function() if s.pick then s.pick() else R.Go(s.pos) end end
		else
			local hand, zones, zname, x, y, nums, pts, tip = 0, {}, nil, 0, 0, {}, {}, {}
			for _, s in ipairs(g.members) do
				local q = P(s.pos)
				x, y = x + q.x, y + q.y
				hand = hand + (s.hand or 0)
				if s.zone and not zones[s.zone] then zones[s.zone] = true; zname = zname and '' or s.zone end
				nums[#nums + 1] = s.n
				pts[#pts + 1] = s.pos
				tip[#tip + 1] = s.tip[1] .. (s.hand and s.hand > 0 and (': ' .. s.hand .. ' hand-in' .. (s.hand > 1 and 's' or '')) or '')
			end
			local c = take('cluster', newCluster)
			local name = (zname and zname ~= '') and zname or (#g.members .. ' stops')
			c.t:SetText(('|cffffe7a8%s|r  %d hand-in%s'):format(name, hand, hand == 1 and '' or 's'))
			c:SetSize((c.t:GetStringWidth() or (#name * 7 + 60)) + 16, 20)
			c:ClearAllPoints(); c:SetPoint('CENTER', layer, 'TOPLEFT', x / #g.members, -y / #g.members)
			c:SetFrameLevel((layer:GetFrameLevel() or 0) + 6)
			table.insert(tip, 1, ('Stops %s: click to zoom in'):format(table.concat(nums, ', ')))
			c.tip, c.leg = tip, nil
			c.click = function() R.Fit(pts) end
			for _, s in ipairs(g.members) do s.omFrame = c end
		end
	end
	local _, _, zoomNow = OM.GetView()
	local zonal = zoomNow and zoomNow < ZONE_ZOOM and data.zones and #data.zones > 0
	local og = {}
	if zonal then
		local drawn = {}
		for _, z in ipairs(data.zones) do
			local x, y, k = 0, 0, 0
			for _, pt in ipairs(z.pts) do local q = P(pt); if q then x, y, k = x + q.x, y + q.y, k + 1 end end
			if k > 0 then
				x, y = x / k, y / k
				if near({ x = x, y = y }) then
					local text = z.n > 0 and ('%s  %s%s|r'):format(z.name, hex(z.color), z.short) or (z.name .. '  |cff8c8c8c' .. z.short .. '|r')
					local wdt = #text * 5.6 + 20
					local clash = false
					for _, d in ipairs(drawn) do if math.abs(d.x - x) < (d.w + wdt) / 2 + 4 and math.abs(d.y - y) < 22 then clash = true; break end end
					local tip = { z.name, z.n > 0 and ('%d writ%s open today: %s to buy, +%d rep'):format(z.n, z.n == 1 and '' or 's', z.short:match('· ([^·]+) ·') or '', z.rep) or z.short }
					if z.done > 0 then tip[#tip + 1] = z.done .. ' handed in today' end
					local mins = z.n > 0 and z.minutes and z.minutes()
					if mins then tip[#tip + 1] = ('All of them: about %d min from your start'):format(mins) end
					tip[#tip + 1] = '|cff8c8c8cClick: zoom in.' .. (z.n > 0 and ' Shift-click: pick the whole zone.' or '') .. '|r'
					local f
					if clash or z.n == 0 then
						f = take('zdot', function() local d = newMark(12); d.badge:Hide(); d.n:SetText(''); return d end)
						f.ring:SetVertexColor(z.color[1], z.color[2], z.color[3], 1)
						f:SetAlpha(z.n > 0 and 1 or 0.5)
					else
						f = take('zbadge', newCluster)
						f.t:SetText(text)
						f:SetSize((f.t:GetStringWidth() or (wdt - 16)) + 16, 20)
						f:SetAlpha(1)
						drawn[#drawn + 1] = { x = x, y = y, w = wdt }
					end
					f:ClearAllPoints(); f:SetPoint('CENTER', layer, 'TOPLEFT', x, -y)
					f:SetFrameLevel((layer:GetFrameLevel() or 0) + 2)
					f.tip, f.leg = tip, nil
					local pts = z.pts
					f.click = function() if IsShiftKeyDown() and z.n > 0 and z.pickAll then z.pickAll() else R.Fit(pts) end end
				end
			end
		end
	else
		for _, o in ipairs(data.others or {}) do
			local q = P(o.pos)
			if q and near(q) then
				local g
				for _, c in ipairs(og) do if (c.x - q.x) ^ 2 + (c.y - q.y) ^ 2 < (CLUSTER_PX - 4) ^ 2 then g = c; break end end
				if g then g.members[#g.members + 1] = o else og[#og + 1] = { x = q.x, y = q.y, members = { o } } end
			end
		end
	end
	for _, g in ipairs(og) do
		if #g.members == 1 then
			local o = g.members[1]
			local f = take('other', function()
				local x = newMark(19)
				x.badge:Hide()
				x.glow = circle(x, 'BACKGROUND', -1, 28, { LIT[1], LIT[2], LIT[3], 0.35 })
				x.tick = x:CreateTexture(nil, 'OVERLAY'); x.tick:SetSize(13, 13); x.tick:SetPoint('CENTER'); x.tick:SetTexture('Interface\\RaidFrame\\ReadyCheck-Ready')
				x.cap = x:CreateFontString(nil, 'OVERLAY'); font(x.cap, 11); x.cap:SetPoint('LEFT', x, 'RIGHT', 3, 0)
				return x
			end)
			f:ClearAllPoints(); f:SetPoint('CENTER', layer, 'TOPLEFT', g.x, -g.y)
			f.badge:Hide()
			local c = o.color or { 0.75, 0.75, 0.72 }
			f.ring:SetVertexColor(c[1], c[2], c[3], 1)
			local done, none = o.state == 'done', o.state == 'none'
			f.tick:SetShown(done)
			f.n:SetText(done and '' or tostring(o.n))
			f.n:SetTextColor(none and 0.7 or 1, none and 0.5 or 0.95, none and 0.5 or 0.8)
			f.glow:SetShown(o.state == 'picked')
			f.cap:SetText((not done and not none and o.label) and (hex(o.state == 'thin' and c or o.value or c) .. o.label .. (o.state == 'thin' and ' thin' or '') .. '|r') or '')
			f:SetAlpha(done and 0.6 or none and 0.55 or 1)
			f:SetFrameLevel((layer:GetFrameLevel() or 0) + 1)
			f.tip, f.leg, f.click = o.tip, nil, o.pick
		else
			local c = take('ocluster', newCluster)
			local n, x, y, pts = 0, 0, 0, {}
			for _, o in ipairs(g.members) do local q = P(o.pos); x, y = x + q.x, y + q.y; n = n + o.n; pts[#pts + 1] = o.pos end
			c.t:SetText(('|cffd8d8d0%d other writs|r'):format(n))
			c:SetSize((c.t:GetStringWidth() or 80) + 16, 18)
			c:SetAlpha(0.8)
			c:ClearAllPoints(); c:SetPoint('CENTER', layer, 'TOPLEFT', x / #g.members, -y / #g.members)
			c:SetFrameLevel((layer:GetFrameLevel() or 0) + 2)
			c.tip, c.leg = { n .. ' other writs here: click to zoom in' }, nil
			c.click = function() R.Fit(pts) end
		end
	end
	for kind, list in pairs(pool) do for i = (used[kind] or 0) + 1, #list do list[i]:Hide() end end
	if hot then R.Highlight(hot, true) end
end

local watch
local function check()
	if not (on and data and stitched()) then if layer then hideAll() end return end
	local v = viewNow()
	if not v then return end
	if watch and (watch.host ~= v.host or math.abs(watch.cs - v.cs) > watch.cs * 0.01 or math.abs(watch.l - v.l) > 6 or math.abs(watch.t - v.t) > 6) then
		local fn = watch.fn; watch = nil; fn()
	end
	local moved = last.host ~= v.host or last.cw ~= v.cw or not last.cs or math.abs(last.cs - v.cs) > last.cs * 0.002
		or math.abs(v.l - last.l) > last.w * 0.6 or math.abs(v.t - last.t) > last.h * 0.6
	if moved or dirty then dirty = false; layout(v) end
end

local driver
local function ensure()
	if layer or not R.Available() then return layer ~= nil end
	layer = CreateFrame('Frame', 'WritsAndFavorsOpenMapRoute', WorldMapFrame:GetCanvas())
	layer:Hide()
	driver = CreateFrame('Frame', nil, WorldMapFrame)
	driver:SetScript('OnUpdate', function() local ok, e = pcall(check); if not ok and ns.Log then ns.Log('openmap route: ' .. tostring(e)); on = false; hideAll() end end)
	local OM = API()
	if OM.RegisterCallback then
		OM.RegisterCallback(R, 'OpenMap_StitchedChanged', function() dirty = true end)
		OM.RegisterCallback(R, 'OpenMap_ViewChanged', function() dirty = dirty or false end)
	end
	return true
end

local function shows()
	local OM = API()
	local u0, v0, z = OM.GetView()
	local v = viewNow()
	if not (u0 and v and z) then return end
	local a1, b1 = OM.WorldFromMap(v.host, 0, 0)
	local a2, b2 = OM.WorldFromMap(v.host, 1, 1)
	if not (a1 and a2) then return end
	return v.w / (v.cw * v.cs) * (a2 - a1), v.h / (v.ch * v.cs) * (b2 - b1), z
end
local function fit(pts, least)
	local OM = API()
	if not (OM and OM.ShowWorld and stitched()) then return false end
	local u0, u1, v0, v1
	for _, p in ipairs(pts) do
		p = world(p)
		if p then
			u0, u1 = math.min(u0 or p.u, p.u), math.max(u1 or p.u, p.u)
			v0, v1 = math.min(v0 or p.v, p.v), math.max(v1 or p.v, p.v)
		end
	end
	if not u0 then return false end
	local fx, fy, z = shows()
	if not fx then return false end
	least = least or 0.01
	local du, dv = math.max(u1 - u0, least) * 1.35, math.max(v1 - v0, least * 0.66) * 1.35
	OM.ShowWorld((u0 + u1) / 2, (v0 + v1) / 2, math.max(1, z * math.min(fx / du, fy / dv)))
	return true
end

local function offInstance()
	if InCombatLockdown() or not (C_Map and C_Map.GetMapInfo and WorldMapFrame.SetMapID) then return end
	local id = WorldMapFrame:GetMapID()
	local info = id and C_Map.GetMapInfo(id)
	local dungeon = (Enum and Enum.UIMapType and Enum.UIMapType.Dungeon) or 4
	if info and info.mapType and info.mapType >= dungeon then
		local d = data
		local p = d and ((d.stops[1] and d.stops[1].pos) or d.start.pos or (d.others and d.others[1] and d.others[1].pos))
		WorldMapFrame:SetMapID(p and p.map or 947)
	end
end

local function soon(fn, tries)
	tries = tries or 25
	if fn() or tries <= 0 then return end
	C_Timer.After(0.1, function() soon(fn, tries - 1) end)
end

function R.WatchView(fn)
	if not (stitched() and viewNow()) then watch = nil; return end
	local v = viewNow()
	watch = { host = v.host, cs = v.cs, l = v.l, t = v.t, fn = fn }
	local sc = WorldMapFrame.ScrollContainer
	if sc and not R.clickHooked then
		R.clickHooked = true
		sc:HookScript('OnMouseDown', function() if watch then local f = watch.fn; watch = nil; f() end end)
	end
end
function R.Unwatch() watch = nil end
function R.SetData(d)
	data = d
	dirty = true
end
function R.IsOn() return on and true or false end
function R.SetOn(v)
	on = v and true or false
	if on then ensure() end
	dirty = true
	if not on then hot = nil; hideAll() end
end
function R.Open(fitIt)
	if not ensure() then return false end
	R.SetOn(true)
	if not WorldMapFrame:IsShown() then
		if InCombatLockdown() then return false end
		if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
	end
	offInstance()
	if fitIt ~= false then soon(function() offInstance(); return R.FitRoute() end) end
	return true
end
function R.FitRoute()
	if not data then return false end
	local pts = { data.start.pos }
	for _, s in ipairs(data.stops) do pts[#pts + 1] = s.pos end
	if #data.stops == 0 then for _, o in ipairs(data.others or {}) do if o.open then pts[#pts + 1] = o.pos end end end
	return fit(pts, 0.02)
end
function R.Fit(pts) if not R.Open(false) then return end soon(function() return fit(pts, 0.012) end) end
function R.Go(p) if not R.Open(false) then return end soon(function() return fit({ p }, 0.03) end) end
function R.Highlight(li, lit)
	if not data then return end
	hot = lit and li or (hot ~= li and hot or nil)
	local leg = data.legs[li]
	if not leg then return end
	for _, r in ipairs(leg.omDrawn or {}) do
		local o, kind, c = r[1], r[2], lit and LIT or r[3]
		if kind == 'line' then o:SetColorTexture(c[1], c[2], c[3], 0.95); o:SetThickness(lit and 2.6 or CORE)
		else o:SetVertexColor(c[1], c[2], c[3], 1) end
	end
	if leg.omCaption then leg.omCaption.t:SetTextColor(lit and LIT[1] or 1, lit and LIT[2] or 1, lit and LIT[3] or 1, 0.95) end
	for _, i in ipairs({ li - 1, li }) do
		local s = i == 0 and data.start or data.stops[i]
		local f = s and s.omFrame
		if f and f.ring then local c = lit and LIT or GOLD; f.ring:SetVertexColor(c[1], c[2], c[3], 1) end
	end
end

local OM = API()
if OM and OM.RegisterMenuToggle then
	pcall(OM.RegisterMenuToggle, 'WritsAndFavors', {
		id = 'route', label = 'Writs route', section = 'Writs and Favors',
		icon = 'Interface\\Icons\\INV_Scroll_03',
		get = function() return on and true or false end,
		set = function(v) R.SetOn(v) end,
	})
end
