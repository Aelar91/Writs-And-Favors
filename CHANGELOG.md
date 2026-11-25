# Writs and Favors

## 0.21.0

### Lower levels
- Below level 45 the plan takes you to Friendly by the quickest hand-ins near home, adding others only when those are not enough. Horde: Ashenvale, the south of Felwood and Stonetalon (Ashenvale and Felwood's south, with the Shipping Label, are exactly Friendly). Alliance: Duskwood, Swamp of Sorrows and Wetlands. From 45 it goes to zones up to 3 levels above yours. Off in the options (Only plan writ hand-ins for my level).
- A hand-in in a zone well above your level says so, on the plan and in the guide.
- The three hand-ins on Archmage Xylem's tower in Azshara are only planned from level 45, which the way up needs.
- Routes use only the flight points you have. Open a flight master's map once on each continent so the addon knows them; until then it goes by your level.
- Crates your level is too low to hand in (Expert from 20, Artisan from 35) are not bought.

### Reputation and Favor
- One page for both: pick the standing to reach (or No reputation), by when, and type the Merchant's Favor you want to hold at the end.
- **Recipes** (beside the Favor box): the recipes sold for Merchant's Favor, for your professions, less the ones you know, and the other rewards. Tick the ones you want and the Favor box becomes what they cost.
- **Forged Delivery Receipts** (the cog's menu, off by default): empty Waylaid Crates handed in for 50 reputation each, in place of writs where that is cheaper or quicker, or for the whole goal (Crates only: no writs at all). Two steps, so crates to fill and crates to leave empty are never bought together: first the Favor, then the empty crates and a receipt on each. They are sold from Friendly, so below it the plan takes writs there first. Crates, receipts and Favor you already have are counted, and the crates are handed in for you.
- Shipping Label: it comes from the first Waylaid Crate you fill, not from a writ. If you do not have it the plan buys and fills one crate for it. Its 50 Favor is counted as well as its 2,000 reputation, and its quest is taken for you when you use it.

### Buying and the route
- Simpler: the panel buys what you need, then **Guide me** or **Send to RestedXP** (under the Buy button) takes you round the hand-ins. The Route window, its map, My picks and the OpenMap drawing are gone.
- The plan reads in a few lines: what it is, whether it reaches your goal, and what you have to do. The rest, with what you pay now and what the hand-ins pay back, is on its tooltip.
- By PLAN on the panel: Auto plan, or What I have (the writs you already hold, with nothing to buy).
- Guide me: the writ and the coin pouch are icons to click, a Next step button, every writ for the same NPC started before you talk to them, and a mailbox step takes what it asks for out of the mail (never mail with money to pay; off in the options).
- A "Writs" macro among your general macros that does what is next: open a coin pouch, use the step's writ, put a receipt on a crate, fill a crate, talk to the crate hand-in. /writs macro picks it up for an action bar. Off in the options.
- 27 more hand-ins: 14 Artisan and Expert writs are still without one (41 before).
- A short tour the first time the panel opens (/writs tour to see it again), and an options page (Esc, Options, AddOns, or /writs options).
- Fill counts only the crates your items will fill, and Fill ignores a click while the last one is still casting.

### Fixed
- Why nothing can be planned is always said on the panel. Below level 10 it says writs and crates need level 10, not that there are no crates.
- Scan prices are kept for the right realm now that the game gives no realm name.
- The plan could ask for far more crates than were on the Auction House: what a scan no longer finds is now dropped.
- The Elixir of Ogre's Strength writ was on the wrong quest, so handing it in was not noticed. Torwa Pathfinder is in Un'Goro Crater, not Tanaris.
- "Script ran too long" on plans that need most of the writs.
- A purchase the Auction House never answers (the auction sold a moment before) is looked up again, not left on "Buying...".
- Writs in the mail keep counting as held away from a mailbox.
- In combat the panel and the guide window wait to be shown, hidden or moved, which the game blocks.
- Starting away from a town: the nearest flight point of the zone, not any of them.
- Clearer buttons on the mailbox and bank reminder, which can be turned off; dropdowns that look like dropdowns; lines that no longer break before a lone word or run over a name.

## 0.20.0
- Guide me: the hand-in route step by step with no other addon. A waypoint for each place, a button that targets who takes the writ, stars them and uses it, and the hand-in done for you. RestedXP is still there if you prefer it.
- Two more hand-ins (Mechanical Dragonling, Potion of Demonslaying) and six hand-in positions corrected.
- A writ with no known hand-in: use it, and the addon reads where the game marks it (/writs places).

## 0.19.1
- Listed under Auctions in the game's AddOns list.
- The route on the world map sits on the map's left; folded, its tab is at the bottom left. The "Every zone" list is gone, so the steps have more room.
- A cog for the options.
- The mailbox and bank reminder is as tall as its text (its buttons sat on the last line).

## 0.19.0
- Alliance: the addon now works for both sides. The Alliance has its own routes, reputation (Azeroth Commerce Authority) and crate hand-in (Marcy Baker at Three Corners in Redridge Mountains). New and not played yet: please report anything odd.

## 0.18.0
- Asks before the first purchase if your mailbox or bank hasn't been opened, so you don't buy what you already have.
- The logo on the panel and the table. No more lines under the headings. Browse all sits on the panel's top edge.

## 0.17.0
- Buy from the table: click a row, then Buy. A writ with its items, or a crate with its cheapest fill; the same button buys another.
- Free bag slots are counted for you. Days read "today", "tomorrow", "in 3 days".
- Routes: mailbox stops where they are least out of the way; a druid's Teleport: Moonglade and a mage's teleports used as often as they help.
- Crate auto hand-in no longer gets stuck on a crate you don't hold.
- Table columns renamed "Cost / rep" and "Cost / Favor"; the Kind column removed.

## 0.16.1
- Fixed button labels being blank the first time the panel opened.

## 0.16.0
- Item tooltips, the Browse all table, a minimap button, game clients that aren't English, prices kept for each realm and faction.
