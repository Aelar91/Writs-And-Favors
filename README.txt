Writs and Favors 0.19.0 (trial)
=================================

Craftsman's Writs and Merchant's Favor, planned in game. It scans the Auction House, picks the writs that reach your
reputation goal for the least gold (or the least time), buys them a click each, and gives you the hand-in route. It
also finds the cheapest Waylaid Crates for Merchant's Favor, fills them and hands them in.

Horde and Alliance. Each side has its own routes, reputation and crate hand-in: Durotar Supply and Logistics and
Dokimi in the Crossroads for the Horde; the Azeroth Commerce Authority and Marcy Baker at Three Corners in Redridge
Mountains for the Alliance. The Alliance side is new in 0.19.0 and has not been played yet: please report anything
odd (a hand-in NPC who won't talk to you, a Hearthstone it doesn't recognise, a route that makes no sense).

Install
-------
1. Close the game (a new addon needs a restart, not just /reload).
2. Unzip so the folder sits at:  World of Warcraft\_forever_\Interface\AddOns\WritsAndFavors
3. Start the game. On the character screen, AddOns: make sure "Writs and Favors" is ticked.

Works on its own. Better with (all optional):
- RestedXP (RXPGuides): the hand-in route as a guide with the arrow.
- OpenMap: the route drawn on the world map, and writs picked by clicking them there.
- Auctionator or TradeSkillMaster: a first plan from their last scan, before you scan yourself.

Writs
-----
1. Open the Auction House. The panel opens beside it (/writs opens it anywhere).
2. Pick the standing to reach and by when: today, tomorrow, or in more days (a writ can be handed in once a day,
   so more days means fewer and cheaper writs each day). The slider: left for the cheapest writs wherever they
   are, right for writs close together (a shorter run that costs a bit more).
3. Click Scan. It searches for the writs, then their items, and plans by itself. "Scan again" within 15 minutes only
   refreshes what has gone stale; Shift-click scans everything.
4. THIS PLAN says how many writs, the reputation, the gold and the minutes. The BUY LIST is what to buy.
5. Buy: click the big button once for each line. Stackable things (potions, cloth) take two clicks, "Check price"
   then "Buy". If a price has gone up more than 25% since the scan it asks for "Anyway"; "Skip" moves on.
   What you buy arrives in your mailbox.
6. Route (title bar): the hand-in route, starting at a mailbox to collect what you bought. "Send route to RestedXP"
   opens it as a guide. With OpenMap the route is on the world map: click a writ there to add it to the plan, or
   choose "Pick my own" to plan only the writs you pick. "Hand in what I have" routes what you already hold.

Writs and items in your bags, mailbox and bank count first: open your mailbox and bank once so it can see them.
Hover the "Held:" line for what it counted. Opts (title bar): buying for today or every day, and whether to skip
writs with only a few listed. Your free bag slots are counted for you: the route stops at a mailbox for as much as
fits, hands it in, and stops at the next mailbox for more. More free slots means fewer mailbox stops.

Tooltips, the table and the minimap button
------------------------------------------
- Hover a writ, a writ's item, a Waylaid Crate or a bundle item anywhere (bags, mail, Auction House): the tooltip
  says what it still costs you, what it gives, and what that comes to a reputation or a Favor.
- "Browse all" (the tab above the panel, or right-click the minimap button): every writ and every crate in a table.
  Click a column to sort by it; the best value is marked. "Cost / rep" and "Cost / Favor" are the gold one
  reputation or one Favor costs.
- Buying from the table (at the Auction House): click a row, then the Buy button at the bottom. One click starts,
  then a click buys each thing (two for stackables: Check price, then Buy). A writ buys the writ and its items; a
  crate buys the crate and its cheapest fill. When it is done the same button buys another, so the cheapest crate
  can be bought again and again. Double-clicking a row starts it too.
- The minimap button: left-click opens the panel, right-click the table, drag moves it.

Merchant's Favor
----------------
1. Click Favor in the title bar (or type /favor).
2. Pick how much Favor to get, then click "Scan crates".
3. Buy each line, take everything out of the mail, then click "Fill" again and again: each click fills the next crate.
4. The Waypoint button puts a waypoint on who takes your crates (Dokimi, or Marcy Baker for the Alliance). With "Auto hand-in: on", talking to her hands in your Sealed crates,
   one each time. Hold Shift to talk to her normally.

Commands
--------
/writs          the panel on the writs          /favor    the panel on Merchant's Favor
/writs held     what it counts as held          /writs held forget   forget the mail and bank it remembers
/writs scale 1.2   the panel's size (or A- / A+)   /writs reset   back beside the Auction House
/writs map      the route on or off OpenMap's map
/writs browse   the table of every writ and crate   /writs minimap   the minimap button on or off
/writs tooltip  the item tooltips on or off          /writs places    the hand-ins it has learnt (see below)

Known limits
------------
- Every purchase is a click: the game doesn't let addons buy on their own.
- Prices are the moment you scan; listings can sell before you buy. The buy button always shows the live price.
- A very big goal in 1 day (100 or so writs) makes the plan pause for a moment.
- Fill only works out of combat.
- Prices are kept for each realm and faction: a character on another realm scans its own.
- 43 of the Expert and Artisan writs have no known hand-in yet (the table says "not known yet"), so they are not
  planned or routed. If you hand one in, the addon keeps where you did: type /writs places and send the lines in,
  and the next version routes them.
- Auto hand-in (at Dokimi or Marcy Baker) hands in one Sealed crate each time the quest window opens. If she does not offer the next
  one by herself, talk to her again.
- Other languages: the Auction House searches use your game's own item names, so scans and buying work, but the
  panel's words are English, a scan takes more searches, and the Hearthstone may not be recognised.

If something goes wrong
-----------------------
Type /writs debug and copy what it prints in chat. If you have BugSack, copy the error from it too (the file name and
line matter). Say what you clicked just before, and what the status line at the bottom of the panel said.
