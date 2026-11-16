<img src="media/logo.png" width="96" alt="Writs and Favors">

# Writs and Favors

A World of Warcraft: Forever addon. **Writs and Favors** works out your Craftsman's Writs and Merchant's Favor for you, in game. Tell it the standing you want and by when. It scans the Auction House, picks the writs that get you there for the least gold (or the least time), buys them with a click each, and gives you the route to hand them in.

**Horde and Alliance.** Each side has its own routes, reputation and crate hand-in: Durotar Supply and Logistics and Dokimi in the Crossroads for the Horde; the Azeroth Commerce Authority and Marcy Baker at Three Corners in Redridge Mountains for the Alliance. The Alliance side is new and hasn't been played yet, so please report anything odd.

## Craftsman's Writs

- **Plans to your goal.** Pick the standing to reach and by when: today, tomorrow or in more days. The plan shows how many writs, the reputation, the gold and the minutes.
- **Cheapest or quickest.** One slider goes from the cheapest writs wherever they hand in, to writs close together for a shorter run.
- **Quick scans.** It searches only for the writs and their items. Scanning again within 15 minutes refreshes only what has gone stale.
- **One click a purchase.** The buy list goes line by line. If a price has gone up more than 25% since the scan, it asks before buying.
- **Counts what you have.** Writs and items in your bags, mailbox and bank come off the list first. It reminds you before buying if you haven't opened your mailbox or bank.
- **Guide me.** The route step by step with no other addon: a waypoint for each place, a button that targets who takes the writ, stars them and uses it, and the hand-in done for you.
- **The hand-in route.** The quickest order by flight, boat, zeppelin or tram, Hearthstone and class teleports. It counts your free bag slots and stops at mailboxes where they are least out of the way.

## Merchant's Favor

- Finds the cheapest Waylaid Crates to fill for the Favor you want, and shows what the hand-ins pay back.
- Buys the crates and what goes in them, then fills a crate each click.
- Hands in your Sealed crates when you talk to Dokimi (Horde) or Marcy Baker (Alliance). Hold Shift to talk normally.
- Shows how much Favor you hold.

## Tooltips, table and minimap button

- **Item tooltips.** Hover a writ, a writ's item, a Waylaid Crate or a bundle item anywhere. The tooltip shows what it still costs you, what it gives, and the cost per reputation or per Favor.
- **Browse all.** Every writ and every crate in one table. Click a column to sort; the best value is marked.
- **Buy from the table.** Click a row, then Buy: a writ with its items, or a crate with its cheapest fill. The same button buys another, so the cheapest crate can be bought again and again.
- **Minimap button.** Left-click for the panel, right-click for the table.
- **Any game language.** Auction House searches use your game's own item names. The panel's text is English.

## Better with (all optional)

- **RestedXP Guides:** the hand-in route as a RestedXP guide, if you prefer it to the built-in one.
- **OpenMap:** the route drawn on the world map, and writs picked by clicking them there.
- **Auctionator or TradeSkillMaster:** a first plan from their last prices, before you scan yourself.

## Getting started

1. Open the Auction House. The panel opens beside it (`/writs` opens it anywhere).
2. Pick the standing to reach and by when, then click **Scan**.
3. Click the buy button once for each line of the buy list.
4. Click **Route** for the hand-in route, then **Guide me** to be taken through it.

For Merchant's Favor, click **Favor** in the title bar or type `/favor`.

## Commands

| Command | What it does |
|---|---|
| `/writs` or `/wf` | Opens the panel on the writs |
| `/favor` | Opens the panel on Merchant's Favor |
| `/writs browse` | Opens the table of every writ and crate |
| `/writs held` | Shows what it counts as held |
| `/writs scale 1.2` | Sets the panel's size |
| `/writs reset` | Puts the panel back beside the Auction House |
| `/writs minimap` | Shows or hides the minimap button |
| `/writs tooltip` | Turns the item tooltips on or off |
| `/writs places` | Lists the hand-ins the addon has learnt in game |
| `/writs debug` | Prints details to send with a problem report |

## Good to know

- Every purchase is your own click. The game doesn't let addons buy by themselves.
- Prices are from the moment you scan. The buy button always shows the live price.
- Prices are kept for each realm and faction.
- Open your mailbox and bank once so the addon can see what's in them.
- 41 of the Artisan and Expert writs have no known hand-in yet, so they are not routed. Buy one, use it, and the addon keeps where the game marks it; `/writs places` lists them to send in.

## Credits and licence

Free software under the GPL version 3. Source: [github.com/Aelar91/Writs-And-Favors](https://github.com/Aelar91/Writs-And-Favors). The travel data is made from [Polestar](https://github.com/fitzforge/polestar)'s reference data (GPL-3.0). The writ and crate facts were looked up on Wowhead, and flight prices and item details come from Blizzard's client data by way of wago.tools. The full list is in CREDITS.txt inside the addon. No libraries are bundled.

World of Warcraft is a trademark of Blizzard Entertainment. This addon is not made or endorsed by Blizzard.

## Install

From CurseForge, or by hand: download the latest release's zip and unzip it so the folder sits at
`World of Warcraft\_forever_\Interface\AddOns\WritsAndFavors`. A new addon needs the game restarted, not just /reload.

## This repository

The addon as it is released. A version tag is packaged and uploaded to CurseForge by the GitHub Action in
`.github/workflows`. Licence: GPL-3.0 (LICENSE.txt); the data's sources are in CREDITS.txt.
