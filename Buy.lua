local _, ns = ...
local Buy = {}
ns.Buy = Buy

local PRICE_GUARD = 1.25
local TRIES = { 1, 2, 4 } -- seconds to wait before asking again
local MORE = 2 -- requests for more of a key's results
local PRICE_WAIT = 5 -- seconds for the locked price after Check price
local SORTS = function() return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } end
local list, cur, pending, onChange
local opts = {}
local step, asked = 'idle', 0 -- idle, wait, browse, search, ready, price, buying

local function changed(msg) if onChange then onChange(msg) end end
local function entry() return list and list[cur] end
local function left(e) return e.need - e.bought end
local function log(msg) if ns.Log then ns.Log('buy: ' .. msg) end end
local M = function(c) return ns.Plan.Money(c) end

local prepare
local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then step = 'idle'; changed('Buying failed: ' .. tostring(err)); log('error ' .. tostring(err)) end
end
local function later(sec, fn) C_Timer.After(sec, function() safe(fn) end) end

local function setPending(p)
	local e = entry()
	p.over = p.stage ~= 'start' and e.plan and p.each > e.plan * PRICE_GUARD or false
	pending, step = p, 'ready'
	e.live = p.each
	local name = e.as or e.name
	local msg
	if p.stage == 'start' then msg = ('%s: click Check price, then Buy (two clicks for a commodity)'):format(name)
	else msg = ('Ready: %d %s for %s'):format(p.qty, name, M(p.total)) end
	if p.stage ~= 'start' and e.plan and math.abs(p.each - e.plan) > e.plan * 0.05 then
		msg = ('%s: was %s, now %s each%s'):format(name, M(e.plan), M(p.each), p.why and (' (' .. p.why .. ')') or '')
	end
	changed(msg)
end
function Buy.Label()
	local p = pending
	if not p then return nil end
	if p.stage == 'start' then return ('Check price: %d for ~%s'):format(p.qty, M(p.total)) end
	local e = entry()
	if e and p.kind == 'item' and left(e) > 1 then return ('Buy 1 for %s (%d to go)'):format(M(p.total), left(e)) end
	return ('Buy %d for %s'):format(p.qty, M(p.total))
end

local function ask(e, try, what, send, check)
	if ns.Scan and not ns.Scan.IsOpen() then
		step = 'wait'
		return later(1, function() ask(e, try, what, send, check) end)
	end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() or (ns.Scan and ns.Scan.Busy()) then
		step = 'wait'
		return later(0.2, function() ask(e, try, what, send, check) end)
	end
	step = what
	asked = asked + 1
	send()
	local mine = asked
	later(TRIES[try + 1] or 4, function()
		if mine ~= asked or step ~= what or entry() ~= e then return end
		if check and check() then return end
		if TRIES[try + 1] then log('no answer for ' .. e.name .. ' (' .. what .. '), try ' .. (try + 1)); return ask(e, try + 1, what, send, check) end
		step = 'idle'
		changed('No answer for ' .. e.name .. ' after ' .. (#TRIES + 1) .. ' tries (none up?). Skip it, or Plan again.')
	end)
end

local function readCommodity(e)
	local n, total, got = left(e), 0, 0
	for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(e.id) or 0 do
		local r = C_AuctionHouse.GetCommoditySearchResultInfo(e.id, i)
		if r and r.unitPrice then
			local take = math.min(n - got, r.quantity or 0)
			total, got = total + take * r.unitPrice, got + take
			if got >= n then break end
		end
	end
	if got < n then step = 'idle'; return changed(('Only %d of %d %s up. Skip it, or Plan again.'):format(got, n, e.name)) end
	setPending({ kind = 'commodity', stage = 'start', qty = n, total = total, each = total / n })
end

local searchKey
local function readItem(e, key)
	local need = left(e)
	local best, cheapest, own, bidOnly, n = nil, nil, 0, 0, C_AuctionHouse.GetNumItemSearchResults(key) or 0
	for i = 1, n do
		local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
		if r then
			local qty = r.quantity or 1
			if r.containsOwnerItem then own = own + 1
			elseif not r.buyoutAmount then bidOnly = bidOnly + 1
			else
				local each = r.buyoutAmount
				if not cheapest or each < cheapest then cheapest = each end
				if not best or each < best.each then
					best = { auction = r.auctionID, buyout = r.buyoutAmount, up = qty, each = each, link = r.itemLink }
				end
			end
		end
	end
	e.more = e.more or {}
	local more = e.more[e.k] or 0
	if C_AuctionHouse.HasFullItemSearchResults and not C_AuctionHouse.HasFullItemSearchResults(key) and more < MORE and C_AuctionHouse.RequestMoreItemSearchResults then
		e.more[e.k] = more + 1
		C_AuctionHouse.RequestMoreItemSearchResults(key)
	end
	log(('%s: %d results, best %s (%s up at it), own %d, bid only %d, more asked %d'):format(e.name, n, best and math.floor(best.each) or '-', best and best.up or '-', own, bidOnly, e.more[e.k] or 0))
	if best then
		if pending and pending.auction == best.auction then return end
		e.as = best.link and best.link:match('%[(.-)%]') or nil
		local why = {}
		if own > 0 then why[#why + 1] = 'cheaper ones are yours' end
		if bidOnly > 0 then why[#why + 1] = 'some are bid only' end
		if #why == 0 and e.plan and best.each > e.plan * 1.05 then why[#why + 1] = 'the cheaper listing has gone' end
		setPending({ kind = 'item', auction = best.auction, total = best.buyout, qty = 1, each = best.each, why = #why > 0 and table.concat(why, ', ') or nil })
	elseif e.keys and e.k and e.k < #e.keys then
		log(e.name .. ': nothing to buy outright in kind ' .. e.k .. ', trying the next')
		searchKey(e, e.k + 1)
	elseif step == 'search' then
		step = 'idle'
		changed(('No %s to buy outright (%d yours, %d bid only). Skip it.'):format(e.name, own, bidOnly))
	end
end

local function onSearched(e, kind, key)
	if step ~= 'search' then return end
	e.kind = kind
	ns.db.prices[e.id] = ns.db.prices[e.id] or {}
	ns.db.prices[e.id].kind = kind
	if kind == 'commodity' then readCommodity(e) else readItem(e, key) end
end

function searchKey(e, k)
	local key = e.keys[k]
	e.k = k
	changed('Finding ' .. e.name .. (#e.keys > 1 and (' (' .. k .. ' of ' .. #e.keys .. ' kinds)') or '') .. '...')
	ask(e, 0, 'search', function() C_AuctionHouse.SendSearchQuery(key, SORTS(), false) end, function()
		if (C_AuctionHouse.GetCommoditySearchResultsQuantity(e.id) or 0) > 0 then log('read commodity results for ' .. e.name); onSearched(e, 'commodity'); return true end
		if (C_AuctionHouse.GetItemSearchResultsQuantity(key) or 0) > 0 then log('read item results for ' .. e.name); onSearched(e, 'item', key); return true end
	end)
end

local function readKeys(e)
	local keys = {}
	for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
		local key = r.itemKey
		if key and key.itemID == e.id and (r.totalQuantity or 0) > 0 then keys[#keys + 1] = { key = key, price = r.minPrice or 0 } end
	end
	if #keys == 0 and C_AuctionHouse.HasFullBrowseResults and not C_AuctionHouse.HasFullBrowseResults() and (e.browseMore or 0) < MORE then
		e.browseMore = (e.browseMore or 0) + 1
		return C_AuctionHouse.RequestMoreBrowseResults()
	end
	table.sort(keys, function(a, b) return a.price < b.price end)
	e.keys = {}
	for n, x in ipairs(keys) do e.keys[n] = x.key end
	log(('%s: %d kinds up'):format(e.name, #e.keys))
	if #e.keys == 0 then step = 'idle'; return changed('None of ' .. e.name .. ' up now. Skip it, or Plan again.') end
	searchKey(e, 1)
end

function prepare()
	pending = nil
	local e = entry()
	while e and e.bought >= e.need do cur = cur + 1; e = entry() end
	if not e then step = 'idle'; return changed(opts.done or 'All bought. Send the route to RestedXP.') end
	e.more, e.browseMore, e.keys, e.k = {}, 0, nil, nil
	changed('Finding ' .. e.name .. '...')
	ask(e, 0, 'browse', function() C_AuctionHouse.SendBrowseQuery({ searchString = e.name, sorts = SORTS(), filters = {}, itemClassFilters = {} }) end)
end

function Buy.Start(shopping, cb, o)
	list, cur, onChange, pending, step = {}, 1, cb, nil, 'idle'
	opts = o or {}
	for _, s in ipairs(shopping) do list[#list + 1] = { id = s.id, name = s.name, need = s.need, bought = 0, plan = s.each, writ = s.writ, rep = s.rep, item = s.item, repText = s.repText } end
	safe(prepare)
end
function Buy.List() return list, cur end
function Buy.Pending() return pending end
function Buy.Step() return step end

local function bought(e, qty)
	e.bought = e.bought + qty
	if opts.onBought then pcall(opts.onBought, e, qty, pending and pending.total or 0) end
	log('bought ' .. qty .. ' ' .. e.name)
	changed('Bought ' .. qty .. ' ' .. (e.as or e.name))
	pending = nil
	later(0.3, prepare)
end

local function handle(event, a, b)
	local e = entry()
	if not e then return end
	if (event == 'AUCTION_HOUSE_BROWSE_RESULTS_UPDATED' or event == 'AUCTION_HOUSE_BROWSE_RESULTS_ADDED') and step == 'browse' then readKeys(e)
	elseif event == 'COMMODITY_SEARCH_RESULTS_UPDATED' and a == e.id and step == 'search' then onSearched(e, 'commodity')
	elseif event == 'ITEM_SEARCH_RESULTS_UPDATED' and a and a.itemID == e.id and step == 'search' then onSearched(e, 'item', e.keys and e.keys[e.k] or a)
	elseif (event == 'ITEM_SEARCH_RESULTS_UPDATED' or event == 'ITEM_SEARCH_RESULTS_ADDED') and a and a.itemID == e.id and step == 'ready' and pending and pending.kind == 'item' then readItem(e, e.keys and e.keys[e.k] or a)
	elseif event == 'COMMODITY_PRICE_UPDATED' and step == 'price' and pending then
		setPending({ kind = 'commodity', stage = 'confirm', qty = pending.qty, each = a, total = b })
	elseif event == 'COMMODITY_PRICE_UNAVAILABLE' and step == 'price' then
		step = 'idle'
		changed('Not enough ' .. e.name .. ' up. Skip it, or Plan again.')
	elseif event == 'COMMODITY_PURCHASE_SUCCEEDED' and step == 'buying' and pending and pending.kind == 'commodity' then bought(e, pending.qty)
	elseif event == 'AUCTION_HOUSE_PURCHASE_COMPLETED' and step == 'buying' and pending and a == pending.auction then bought(e, pending.qty)
	elseif event == 'COMMODITY_PURCHASE_FAILED' and step == 'buying' then
		changed('That purchase failed (the price moved). Finding it again...')
		later(0.5, prepare)
	elseif event == 'AUCTION_HOUSE_THROTTLED_SYSTEM_READY' and step == 'wait' then
	end
end
function Buy.OnEvent(event, a, b) safe(handle, event, a, b) end

function Buy.Click(anyway)
	local e, p = entry(), pending
	if not (e and p) or step ~= 'ready' then return end
	if p.kind == 'commodity' and p.stage == 'start' then
		step = 'price'
		C_AuctionHouse.StartCommoditiesPurchase(e.id, p.qty)
		changed('Asking the price of ' .. p.qty .. ' ' .. e.name .. '...')
		local mine = p
		later(PRICE_WAIT, function()
			if step == 'price' and pending == mine then
				step = 'ready'
				changed('No price from the AH for ' .. e.name .. ': click Check price again, or Skip.')
			end
		end)
		return
	end
	if p.over and not anyway then return changed(('%s is %s each now (planned %s): click Anyway, or Skip'):format(e.name, M(p.each), M(e.plan))) end
	if GetMoney() < p.total then return changed('Not enough gold for ' .. e.name) end
	step = 'buying'
	if p.kind == 'commodity' then C_AuctionHouse.ConfirmCommoditiesPurchase(e.id, p.qty)
	else C_AuctionHouse.PlaceBid(p.auction, p.total) end
	changed('Buying ' .. p.qty .. ' ' .. (e.as or e.name) .. '...')
end

function Buy.Skip()
	if not entry() then return end
	if pending and pending.kind == 'commodity' and pending.stage == 'confirm' and C_AuctionHouse.CancelCommoditiesPurchase then
		C_AuctionHouse.CancelCommoditiesPurchase()
	end
	cur = cur + 1
	safe(prepare)
end

function Buy.Clear() list, cur, pending, step = nil, 1, nil, 'idle' end
