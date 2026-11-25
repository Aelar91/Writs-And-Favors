local _, ns = ...
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local D = ns.D
local Scan = {}
ns.Scan = Scan

local TIMEOUT = 8
local MAX_PAGES = 12
local FRESH = 15 * 60
local L = ns.L

local isWrit, writOf = {}, {}
for _, w in ipairs(D.writs) do
	isWrit[w[1]] = true
	writOf[w[3]] = writOf[w[3]] or {}
	table.insert(writOf[w[3]], w[1])
end

local f = CreateFrame('Frame')
local q, busy, waiting, started, db, onDone, onProgress, opts
local done, total, pages, spent, answers = 0, 0, 0, 0, 0
local ahOpen, readyWait = false, nil
local stage = 'idle'

local function now() return GetServerTime and GetServerTime() or time() end

function ns.Log(msg)
	local db = ns.db
	if not db then return end
	db.log = db.log or {}
	table.insert(db.log, date('%H:%M:%S') .. ' ' .. tostring(msg))
	while #db.log > 120 do table.remove(db.log, 1) end
end

local function finish(msg, failed)
	busy, waiting, stage = false, nil, failed and 'failed' or 'done'
	if answers > 0 and db then db.searchAvg, db.searchN = spent / answers, answers end
	ns.Log('scan: ' .. msg .. (answers > 0 and (' (avg answer %.2f s)'):format(spent / answers) or ''))
	if onDone then onDone(msg, failed) end
end
local function guard(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then finish('Scan failed: ' .. tostring(err), true) end
end

local nextQuery, queueItems, queueFavor, queueHerbs, readLadder
local function answered()
	if waiting and waiting.sent then spent, answers = spent + (GetTime() - waiting.sent), answers + 1 end
	waiting = nil
	done = done + 1
	if onProgress then onProgress(done, total) end
	C_Timer.After(0, function() guard(nextQuery) end)
end

function nextQuery()
	if not busy or waiting then return end
	local job = q[1]
	if not job then
		local writs, items = 0, 0
		for id, p in pairs(db.prices) do
			if p.at and p.at >= started then if isWrit[id] then writs = writs + 1 else items = items + 1 end end
		end
		return finish(('Scan done: %d writs and %d items priced, %d searches in %d s'):format(writs, items, done, now() - started))
	end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		readyWait = readyWait or GetTime()
		if GetTime() - readyWait > 5 and onProgress then onProgress(done, total, 'waiting for the Auction House') end
		C_Timer.After(0.1, function() guard(nextQuery) end) -- also woken by AUCTION_HOUSE_THROTTLED_SYSTEM_READY
		return
	end
	readyWait = nil
	table.remove(q, 1)
	waiting, pages = job, 0
	job.sent = GetTime()
	stage = job.writs and 'writs' or job.crates and 'crates' or 'items'
	if job.search then
		C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(job.search), { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }, false)
	else
		C_AuctionHouse.SendBrowseQuery({ searchString = job.term or '', sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }, filters = {}, itemClassFilters = job.class and { job.class } or {} })
	end
	local sent = job
	C_Timer.After(TIMEOUT, function()
		if waiting ~= sent then return end
		if sent.search then
			if (C_AuctionHouse.GetCommoditySearchResultsQuantity(sent.search) or 0) > 0 then readLadder(sent.search, 'commodity'); return guard(answered) end
			local key = C_AuctionHouse.MakeItemKey(sent.search)
			if (C_AuctionHouse.GetItemSearchResultsQuantity(key) or 0) > 0 then readLadder(key, 'item'); return guard(answered) end
		end
		ns.Log('scan: no answer for ' .. (sent.term and ('"' .. sent.term .. '"') or ('item ' .. tostring(sent.search))))
		guard((sent.writs and queueItems) or (sent.crates and queueFavor) or (sent.herbs and queueHerbs) or answered)
	end)
end

local function readBrowse()
	local job = waiting
	local seen = {}
	for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
		local id = r.itemKey and r.itemKey.itemID
		if id and job.want[id] and (r.minPrice or 0) > 0 then
			local p = seen[id] and db.prices[id]
			if p then
				p.each, p.up = math.min(p.each, r.minPrice), p.up + (r.totalQuantity or 0)
			else
				db.prices[id] = { each = r.minPrice, up = r.totalQuantity or 0, at = job.at }
				seen[id] = true
			end
		end
	end
	if not C_AuctionHouse.HasFullBrowseResults() and pages < MAX_PAGES then
		pages = pages + 1
		C_AuctionHouse.RequestMoreBrowseResults()
		return
	end
	if C_AuctionHouse.HasFullBrowseResults() and (next(seen) or not job.herbs) then
		local gone = 0
		for id in pairs(job.want) do
			local old = db.prices[id]
			if not seen[id] and old and old.at ~= job.at and (old.each or (old.up or 0) > 0) then
				db.prices[id] = { up = 0, at = job.at }
				gone = gone + 1
			end
		end
		if gone > 0 then ns.Log(('scan: %d no longer up%s'):format(gone, job.term and (' ("' .. job.term .. '")') or '')) end
	end
	if job.writs then queueItems() elseif job.crates then queueFavor() elseif job.herbs then queueHerbs() else answered() end
end

function queueItems()
	local need = {}
	for item, writs in pairs(writOf) do
		local p = db.prices[item]
		local fresh = opts.quick and p and p.at and now() - p.at < FRESH
		if not fresh then
			for _, writ in ipairs(writs) do
				local pw = db.prices[writ]
				if (pw and pw.at == started and (pw.up or 0) > 0) or GetItemCount(writ) > 0 then need[item] = true end
			end
		end
	end
	local terms = L.Terms(D.terms)
	for _, t in ipairs(terms) do
		local want, any = {}, false
		for _, id in ipairs(t[2]) do want[id] = true; if need[id] then any = true end end
		if any then q[#q + 1] = { term = t[1], want = want, at = started } end
	end
	total = done + 1 + #q
	ns.Log(('scan: writs read, %d item searches queued (of %d)'):format(#q, #terms))
	answered()
end

local needed
function queueFavor()
	local W = D.waylaid
	needed = {}
	for _, c in ipairs(W.crates) do
		local pc = db.prices[c[1]]
		if pc and pc.at == started and (pc.up or 0) > 0 then for _, o in ipairs(c[5]) do needed[o[1]] = true end end
	end
	local herbWant, anyHerb = {}, false
	for _, id in ipairs(W.herbs) do herbWant[id] = true; if needed[id] then anyHerb = true end end
	if anyHerb then q[#q + 1] = { class = { classID = 7, subClassID = 9 }, want = herbWant, herbs = true, at = started, label = 'herbs' } end
	for _, t in ipairs(L.Terms(W.terms)) do
		local want, any = {}, false
		for _, id in ipairs(t[2]) do want[id] = true; if needed[id] then any = true end end
		if any then q[#q + 1] = { term = t[1], want = want, at = started } end
	end
	total = done + 1 + #q
	ns.Log(('scan: crates read, %d browses queued for their bundles'):format(#q))
	answered()
end
function queueHerbs()
	local got = 0
	for _, id in ipairs(D.waylaid.herbs) do local pr = db.prices[id]; if pr and pr.at == started then got = got + 1 end end
	if got > 0 then return answered() end
	local missing = 0
	for _, t in ipairs(L.Terms(D.waylaid.herbTerms)) do
		local want, any = {}, false
		for _, id in ipairs(t[2]) do
			want[id] = true
			local pr = db.prices[id]
			if needed and needed[id] and not (pr and pr.at == started) then any = true end
		end
		if any then table.insert(q, 1, { term = t[1], want = want, at = started }); missing = missing + 1 end
	end
	if missing > 0 then ns.Log(('scan: the herb category left %d herbs, browsing them by name'):format(missing)) end
	total = done + 1 + #q
	answered()
end
local LADDER = 200
function readLadder(key, kind)
	local id = kind == 'commodity' and key or key.itemID
	local ladder, up = {}, 0
	if kind == 'commodity' then
		for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(id) or 0 do
			local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
			if r and r.unitPrice then
				up = up + (r.quantity or 0)
				if #ladder < LADDER then ladder[#ladder + 1] = { r.unitPrice, r.quantity or 0 } end
			end
		end
	else
		for i = 1, C_AuctionHouse.GetNumItemSearchResults(key) or 0 do
			local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
			if r and r.buyoutAmount and not r.containsOwnerItem then
				local qty = r.quantity or 1
				up = up + qty
				if #ladder < LADDER then ladder[#ladder + 1] = { r.buyoutAmount, qty } end
			end
		end
		table.sort(ladder, function(a, b) return a[1] < b[1] end)
	end
	if #ladder == 0 and db.prices[id] and db.prices[id].each then db.prices[id].full = true; return end
	db.prices[id] = { each = ladder[1] and ladder[1][1], up = up, ladder = ladder, kind = kind, at = started, full = true }
end

local function onEvent(event, arg, arg2)
	if event == 'AUCTION_HOUSE_SHOW' then ahOpen = true; return end
	if event == 'AUCTION_HOUSE_CLOSED' then
		ahOpen = false
		if busy then finish(('Stopped: the Auction House closed (%d of %d done)'):format(done, total), true) end
		return
	end
	if event == 'AUCTION_HOUSE_THROTTLED_SYSTEM_READY' then
		if busy and not waiting then nextQuery() elseif not busy and ns.Buy then ns.Buy.OnEvent(event) end
		return
	end
	if ns.Buy and not busy then ns.Buy.OnEvent(event, arg, arg2) end
	if not (busy and waiting) then return end
	if waiting.search then
		if event == 'COMMODITY_SEARCH_RESULTS_UPDATED' and arg == waiting.search then readLadder(arg, 'commodity'); answered()
		elseif event == 'ITEM_SEARCH_RESULTS_UPDATED' and arg and arg.itemID == waiting.search then readLadder(arg, 'item'); answered() end
		return
	end
	if event == 'AUCTION_HOUSE_BROWSE_RESULTS_UPDATED' or event == 'AUCTION_HOUSE_BROWSE_RESULTS_ADDED' then readBrowse() end
end
f:SetScript('OnEvent', function(_, event, arg, arg2) guard(onEvent, event, arg, arg2) end)
if C_AuctionHouse then
	for _, e in ipairs({ 'AUCTION_HOUSE_SHOW', 'AUCTION_HOUSE_CLOSED', 'AUCTION_HOUSE_THROTTLED_SYSTEM_READY', 'AUCTION_HOUSE_BROWSE_RESULTS_UPDATED', 'AUCTION_HOUSE_BROWSE_RESULTS_ADDED', 'COMMODITY_SEARCH_RESULTS_UPDATED', 'ITEM_SEARCH_RESULTS_UPDATED', 'ITEM_SEARCH_RESULTS_ADDED', 'COMMODITY_PRICE_UPDATED', 'COMMODITY_PRICE_UNAVAILABLE', 'COMMODITY_PURCHASE_SUCCEEDED', 'COMMODITY_PURCHASE_FAILED', 'AUCTION_HOUSE_PURCHASE_COMPLETED', 'AUCTION_HOUSE_SHOW_ERROR', 'UI_ERROR_MESSAGE' }) do pcall(f.RegisterEvent, f, e) end
end

function Scan.Busy() return busy end
function Scan.Avg() return answers > 0 and spent / answers or nil, answers end
function Scan.Count() return done end
function Scan.IsOpen() return ahOpen or (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or false end
function Scan.Info()
	return ('stage %s, busy %s, %d of %d searches, %d queued, waiting for %s, avg answer %s, AH open %s, throttle ready %s')
		:format(stage, tostring(busy), done, total, q and #q or 0, waiting and (waiting.term and ('"' .. waiting.term .. '"') or ('item ' .. tostring(waiting.search))) or 'nothing',
			answers > 0 and ('%.2f s'):format(spent / answers) or '-', tostring(Scan.IsOpen()),
			tostring(C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and C_AuctionHouse.IsThrottledMessageSystemReady()))
end
function Scan.Quick(db) return db.fullAt and now() - db.fullAt < FRESH end

function Scan.Start(store, progress, doneFn, o)
	if busy then return progress(done, total, 'already scanning') end
	if not (C_AuctionHouse and Scan.IsOpen()) then return doneFn('Open the Auction House first', true) end
	o = o or {}
	local word = not o.full and (o.favor and L.CrateSearch() or not o.favor and L.WritSearch()) or nil
	if not o.full and not word then
		local n = L.Load()
		return doneFn(('The game is still loading item names in your language (%d to come). Try Scan again in a moment.'):format(n), true)
	end
	L.Load()
	db, onProgress, onDone, opts = store, progress, doneFn, o
	db.prices = db.prices or {}
	started = now()
	local want = {}
	if opts.full then
		q = {}
		for _, id in ipairs(opts.full) do q[#q + 1] = { search = id, at = started } end
	elseif opts.favor then
		for _, c in ipairs(D.waylaid.crates) do want[c[1]] = true end
		q = { { term = word, want = want, crates = true, at = started } }
	else
		for id in pairs(isWrit) do want[id] = true end
		q = { { term = word, want = want, writs = true, at = started } }
		local crateWord = opts.receipts and L.CrateSearch()
		if crateWord then
			local cw = {}
			for _, c in ipairs(D.waylaid.crates) do cw[c[1]] = true end
			q[#q + 1] = { term = crateWord, want = cw, crates = true, at = started }
		end
	end
	done, total, busy, waiting, spent, answers = 0, 1, true, nil, 0, 0
	if opts.full then db.favorFullAt = started elseif opts.favor then db.favorAt = started else db.scanAt = started end
	if not opts.quick and not opts.favor then db.fullAt = started end
	stage = 'writs'
	ns.Log('scan: started' .. (opts.favor and ' (Waylaid Crates)' or opts.quick and ' (quick)' or ''))
	if progress then progress(0, 1, opts.favor and 'searching for the crates' or 'searching for the writs') end
	guard(nextQuery)
end

function Scan.Fallback(prices, stock)
	local tsm = TSM_API and TSM_API.GetCustomPriceValue
	local A = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (tsm or (A and A.GetAuctionPriceByItemID)) then return 0 end
	local n = 0
	local function fill(id)
		if prices[id] then return end
		local p, src
		if A and A.GetAuctionPriceByItemID then
			local ok, v = pcall(A.GetAuctionPriceByItemID, 'WritsAndFavors', id)
			if ok and v and v > 0 then p, src = v, 'Auctionator' end
		end
		if not p and tsm then
			local ok, v = pcall(tsm, 'DBMinBuyout', 'i:' .. id)
			if ok and v and v > 0 then p, src = v, 'TSM' end
		end
		if p then prices[id] = { each = p, up = stock, source = src }; n = n + 1 end
	end
	for _, w in ipairs(D.writs) do fill(w[1]); fill(w[3]) end
	return n
end
