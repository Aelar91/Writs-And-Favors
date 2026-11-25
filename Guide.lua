local _, ns = ...
local D = ns.D
local Guide = {}
ns.Guide = Guide

Guide.GROUP = 'Writs and Favors'
Guide.POUCHES = { 284583, 284584, 284585, 284586 }

local function clean(s) return (tostring(s):gsub('%]%]', '] ]'):gsub('[\r\n]+', ' ')) end
local function itemcount(ids)
	if #ids == 0 then return {} end
	local seen, u = {}, {}
	for _, id in ipairs(ids) do if not seen[id] then seen[id] = true; u[#u + 1] = id end end
	return { '    .itemcount ' .. table.concat(u, ';') .. ',1' }
end
local function push(out, ...)
	for i = 1, select('#', ...) do
		local x = select(i, ...)
		if type(x) == 'table' then for _, l in ipairs(x) do out[#out + 1] = l end else out[#out + 1] = x end
	end
end

local TIER = { apprentice = 'Apprentice', journeyman = 'Journeyman', expert = 'Expert', artisan = 'Artisan' }
function Guide.CrateGroups(crates)
	local W = D.waylaid
	local by, out = {}, {}
	for _, c in ipairs(crates) do
		local k = c.kind .. c.tier
		if not by[k] then
			local ids = {}
			for _, w in ipairs(W.crates) do if w[3] == c.kind and w[2] == c.tier then ids[#ids + 1] = w[1] end end
			by[k] = { kind = c.kind, tier = c.tier, count = 0, waylaid = ids, sealed = W.sealed[c.kind][c.tier], quest = W.quests[c.kind][c.tier] }
			out[#out + 1] = by[k]
		end
		by[k].count = by[k].count + (c.count or 0)
	end
	return out
end
function Guide.FillLines(fill)
	local names = D.waylaid.names or {}
	local out, n = {}, 0
	for _, c in ipairs(fill or {}) do
		n = n + c.count
		local with = {}
		for _, b in ipairs(c.bundles or {}) do
			with[#with + 1] = ((#c.bundles > 1) and (b.count .. ' with ') or '') .. b.n .. ' ' .. (names[b.item] or ('item ' .. b.item)) .. ((#c.bundles > 1) and '' or ' each')
		end
		out[#out + 1] = c.count .. ' x ' .. ((names[c.id] or ('crate ' .. c.id)):gsub('^Waylaid Crate: ', '')) .. ': ' .. table.concat(with, ', ')
	end
	return out, n
end
local function fillStep(out, groups, goto)
	local ids = {}
	for _, g in ipairs(groups) do for _, id in ipairs(g.waylaid) do ids[#ids + 1] = id end end
	if #ids == 0 then return end
	push(out, 'step', '    .itemcount ' .. table.concat(ids, ';') .. ',1', goto, '    +Fill your Waylaid Crates: use each one (its button) with its items in your bags')
	for _, id in ipairs(ids) do push(out, '    .use ' .. id) end
end
local function crateSteps(out, groups, goto)
	for _, g in ipairs(groups) do
		push(out, 'step', '    .itemcount ' .. g.sealed .. ',1', goto, '    >>Talk to |cRXP_FRIENDLY_' .. clean(D.waylaid.handIn.npc) .. '|r',
			'    .turnin ' .. g.quest .. ' >>Hand in ' .. (g.count > 0 and (g.count .. ' ') or 'every ') .. 'Sealed ' .. TIER[g.tier] .. ' Crate' .. (g.count ~= 1 and 's' or '') .. ' (' .. g.kind .. '), one at a time',
			'    +Hand in every Sealed ' .. TIER[g.tier] .. ' Crate (' .. g.kind .. ') you have', '    .target ' .. clean(D.waylaid.handIn.npc))
	end
end

function Guide.Text(route, name)
	local out = {}
	push(out, '<< ' .. (D.side or 'Horde'), '#forever', '#version 1', '#name ' .. clean(name), '#group ' .. Guide.GROUP, '')
	local stops, mails = 0, 0
	for _, l in ipairs(route.legs) do if l.mail then mails = mails + 1 else stops = stops + 1 end end
	push(out, ('-- %d stops and %d mailboxes from %s, about %d min (Writs and Favors, planned in game)'):format(stops, mails, D.nodes[route.start][1], math.floor(route.total / 60 + 0.5)))
	local handed = {}
	for _, l in ipairs(route.legs) do
		local writIds, quests = {}, {}
		for _, w in ipairs(l.writs) do writIds[#writIds + 1] = w.writ; quests[#quests + 1] = w.quest end
		local left
		if #writIds == 0 then left = {} -- the Shipping Label's stop alone: its own steps skip once it's done
		elseif l.mail then left = { '    .isQuestAvailable ' .. table.concat(quests, ','), '    .itemcount ' .. table.concat(writIds, ';') .. ',<' .. #writIds }
		else left = { '    .isQuestAvailable ' .. table.concat(quests, ','), unpack(itemcount(writIds)) } end
		if l.port then
			if l.port.kind == 'hearth' then push(out, 'step', left, '    .hs >>Hearth to ' .. clean(l.port.name))
			else push(out, 'step', left, '    .usespell ' .. l.port.spell, '    .zone ' .. l.port.map .. ' >>Cast |cRXP_WARN_Teleport: ' .. clean(l.port.name) .. '|r' .. (l.port.rune and ' (a Rune of Teleportation)' or '')) end
		end
		for _, h in ipairs(l.hops) do
			local kind, from, to, map, x, y, npc, toMap = unpack(D.hops[h])
			local at = map and { '    .goto ' .. map .. ',' .. x .. ',' .. y } or {}
			if kind == 'fly' then
				push(out, 'step', left, at, npc and ('    >>Talk to |cRXP_FRIENDLY_' .. clean(npc) .. '|r at ' .. clean(from) .. ' and fly to ' .. clean(to)) or ('    >>Fly to ' .. clean(to)), '    .fly ' .. clean(to), npc and ('    .target ' .. clean(npc)) or {})
			else
				push(out, 'step', left, at, toMap and ('    .zone ' .. toMap .. ' >>Take the ' .. kind .. ' from ' .. clean(from) .. ' to ' .. clean(to)) or ('    >>Take the ' .. kind .. ' from ' .. clean(from) .. ' to ' .. clean(to)))
			end
		end
		local label, zone, map, x, y = unpack(D.places[l.row])
		local goto = (map and x) and { '    .goto ' .. map .. ',' .. x .. ',' .. y } or {}
		if l.mail then
			local take = {}
			for _, w in ipairs(l.writs) do push(take, '    .collect ' .. w.writ .. ',1,' .. w.quest .. ',1', '    .collect ' .. w.item .. ',' .. w.n .. ',' .. w.quest .. ',2') end
			push(out, 'step', left, goto, '    >>Open the mailbox and take out ' .. (#l.writs > 0 and 'each writ and its items below' or '') .. (#l.writs > 0 and l.crateMail and ', and ' or '') .. (l.crateMail and 'your Waylaid Crates and their bundles' or ''), take)
			if l.crateMail then
				push(out, '    +Take your Waylaid Crates and their bundles out of the mail')
				fillStep(out, l.crateMail, goto)
			end
		else
			local zl = route.level and ns.Plan.Over(l.row, route.level)
			local warn = zl and ('    >>|cRXP_WARN_' .. clean(ns.Plan.WarnText(zone, zl, route.level)) .. '|r') or {}
			for k, w in ipairs(l.writs) do
				local n = clean(w.itemName)
				push(out, 'step', itemcount({ w.writ }), goto, k == 1 and warn or {},
					'    .use ' .. w.writ .. " >>|cRXP_WARN_Use the|r [|cRXP_LOOT_Craftsman's Writ: " .. n .. '|r] |cRXP_WARN_to start its quest|r',
					'    .collect ' .. w.writ .. ',1,' .. w.quest,
					'    .daily ' .. w.quest .. " >>Accept Craftsman's Writ: " .. n)
				push(out, 'step', itemcount({ w.writ }), goto, '    >>Talk to |cRXP_FRIENDLY_' .. clean(label) .. '|r',
					'    .dailyturnin ' .. w.quest .. " >>Turn in Craftsman's Writ: " .. n .. (w.n > 1 and (' (' .. w.n .. ')') or ''),
					'    .target ' .. clean(label))
				handed[#handed + 1] = w
			end
			local function labelSteps()
				local li, lq = l.label.item, l.label.quest
				push(out, 'step', '    .itemcount ' .. li .. ',1', goto,
					'    .use ' .. li .. ' >>|cRXP_WARN_Use the|r [|cRXP_LOOT_Shipping Label|r] |cRXP_WARN_to start its quest|r',
					'    .collect ' .. li .. ',1,' .. lq,
					'    .accept ' .. lq .. ' >>Accept Shipping Label')
				push(out, 'step', '    .isOnQuest ' .. lq, goto, '    >>Talk to |cRXP_FRIENDLY_' .. clean(D.waylaid.handIn.npc) .. '|r',
					'    .turnin ' .. lq .. ' >>Turn in Shipping Label (2,000 reputation and 50 Favor, once)', '    .target ' .. clean(D.waylaid.handIn.npc))
			end
			local labelAfter = l.label and l.label.needsCrate and (l.crates or (l.receipts and l.receiptFill))
			if l.label and not labelAfter then labelSteps() end
			if l.crates then
				fillStep(out, l.crates, goto)
				if labelAfter then labelSteps() end
				crateSteps(out, l.crates, goto)
			end
			if l.receipts then
				if l.receiptFill then
					local groups = Guide.CrateGroups(l.receiptFill)
					local lines, nFill = Guide.FillLines(l.receiptFill)
					push(out, 'step', goto, '    +Fill ONLY ' .. (nFill == 1 and 'this 1 crate' or ('these ' .. nFill .. ' crates')) .. (l.label and l.label.needsCrate and nFill == 1 and ', for the Shipping Label: ' or ', for the Favor your receipts cost: ') .. clean(table.concat(lines, '; ')) .. '. Leave your other ' .. l.receipts .. ' crates EMPTY: they get the receipts')
					for _, c in ipairs(l.receiptFill) do push(out, '    .use ' .. c.id) end
					if labelAfter and not l.crates then labelSteps() end
					crateSteps(out, groups, goto)
				end
				push(out, 'step', goto, '    >>Buy ' .. l.receipts .. ' Forged Delivery Receipt' .. (l.receipts == 1 and '' or 's') .. ' from the Uncertified Scribe at the camp (15 Favor each). Use one on each empty Waylaid Crate (the Receipt button on the panel), then hand the crates in to |cRXP_FRIENDLY_' .. clean(D.waylaid.handIn.npc) .. '|r: 50 reputation each',
					'    .target ' .. clean(D.waylaid.handIn.npc))
			end
		end
	end
	local back = 0
	for _, w in ipairs(handed) do back = back + (D.pouch[w.tier] or 0) end
	if #handed > 0 then
		push(out, 'step', '    .itemcount ' .. table.concat(Guide.POUCHES, ';') .. ',1', '    +Open your coin pouches: your money back! (about ' .. ns.Plan.Money(back) .. ' from ' .. #handed .. ' writs)')
		for _, id in ipairs(Guide.POUCHES) do push(out, '    .use ' .. id) end
	end
	push(out, 'step', '    >>All handed in. Well done.')
	return table.concat(out, '\n')
end

local function nodeNamed(name) for id, n in pairs(D.nodes) do if n[1] == name then return id, n end end end
function Guide.Steps(route)
	local out = {}
	local function add(s) out[#out + 1] = s; return s end
	for _, l in ipairs(route.legs) do
		local label, zone, map, x, y = unpack(D.places[l.row])
		if l.port then
			local n = D.nodes[l.port.node]
			add({ kind = 'port', hearth = l.port.kind == 'hearth' or nil, spell = l.port.spell,
				text = l.port.kind == 'hearth' and ('Use your Hearthstone (' .. l.port.name .. ')') or ('Cast Teleport: ' .. l.port.name .. (l.port.rune and ' (a Rune of Teleportation)' or '')),
				arrive = n and { map = n[2], x = n[3], y = n[4] } or nil })
		end
		for _, h in ipairs(l.hops) do
			local kind, from, to, hmap, hx, hy, npc, toMap = unpack(D.hops[h])
			if kind == 'fly' then
				local _, n = nodeNamed(to)
				add({ kind = 'fly', map = hmap, x = hx, y = hy, npc = npc,
					text = (npc and ('Talk to ' .. npc .. ' at ' .. from) or ('At ' .. from)) .. ' and fly to ' .. to,
					arrive = n and { map = n[2], x = n[3], y = n[4] } or nil })
			else
				add({ kind = 'ride', map = hmap, x = hx, y = hy, toMap = toMap, text = 'Take the ' .. kind .. ' from ' .. from .. ' to ' .. to })
			end
		end
		if l.mail then
			local need, names = {}, {}
			for _, w in ipairs(l.writs) do
				need[#need + 1] = { w.writ, 1 }
				need[#need + 1] = { w.item, w.n }
				names[#names + 1] = (w.n > 1 and (w.n .. ' x ') or '') .. w.itemName
			end
			local what = #l.writs > 0 and (#l.writs .. ' writ' .. (#l.writs == 1 and '' or 's') .. ' and what they ask for') or ''
			if l.crateMail then what = what .. (what ~= '' and ', and ' or '') .. 'your crates and bundles' end
			add({ kind = 'mail', map = map, x = x, y = y, need = need, crates = l.crateMail and true or nil, text = label .. ': take out ' .. what, detail = table.concat(names, ', ') })
		else
			local zl = route.level and ns.Plan.Over(l.row, route.level)
			local warn = zl and ns.Plan.WarnText(zone, zl, route.level) or nil
			for _, w in ipairs(l.writs) do
				add({ kind = 'writ', map = map, x = x, y = y, npc = label, zone = zone, warn = warn, writ = w.writ, quest = w.quest, item = w.item, n = w.n,
					text = 'Hand in ' .. (w.n > 1 and (w.n .. ' x ') or '') .. w.itemName .. ' to ' .. label })
			end
			local function labelStep()
				add({ kind = 'label', map = map, x = x, y = y, npc = label, zone = zone, writ = l.label.item, quest = l.label.quest,
					text = 'Use your Shipping Label and hand it in to ' .. label .. ' (2,000 reputation and 50 Favor, once)' .. (l.label.needsCrate and '. The first crate you fill gives it' or '') })
			end
			local labelAfter = l.label and l.label.needsCrate and l.receipts and l.receiptFill
			if l.label and not labelAfter then labelStep() end
			if l.crates then
				local ids = {}
				for _, g in ipairs(l.crates) do ids[#ids + 1] = g.sealed end
				add({ kind = 'crates', map = map, x = x, y = y, npc = label, zone = zone, sealed = ids, text = 'Hand in your Sealed crates to ' .. label })
			end
			if l.receipts and l.receiptFill then
				local lines, nFill = Guide.FillLines(l.receiptFill)
				local ids = {}
				for _, g in ipairs(Guide.CrateGroups(l.receiptFill)) do ids[#ids + 1] = g.sealed end
				add({ kind = 'fill', map = map, x = x, y = y, npc = label, zone = zone,
					text = 'Fill ' .. nFill .. ' crate' .. (nFill == 1 and '' or 's') .. ' for Favor: ' .. table.concat(lines, '; '),
					detail = 'Fill, on the panel (or your Writs macro), fills exactly these. Your other ' .. l.receipts .. ' crates stay empty: they get the receipts.' })
				if labelAfter then labelStep() end
				add({ kind = 'crates', map = map, x = x, y = y, npc = label, zone = zone, sealed = ids, text = 'Hand in the ' .. nFill .. ' Sealed crate' .. (nFill == 1 and '' or 's') .. ' to ' .. label .. ': the Favor for your receipts' })
			end
			if l.receipts then
				add({ kind = 'receipts', map = map, x = x, y = y, npc = label, zone = zone, n = l.receipts,
					text = 'Buy ' .. l.receipts .. ' Forged Delivery Receipt' .. (l.receipts == 1 and '' or 's') .. ' from the Uncertified Scribe (15 Favor each), use one on each empty Waylaid Crate, and hand the crates in to ' .. label,
					detail = 'Receipt, on the panel (or your Writs macro), puts one on each empty crate. 50 reputation each.' })
			end
		end
	end
	return out
end
