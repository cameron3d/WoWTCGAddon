# WoWTCG — In-Game Collectible Card Game Addon (Design Spec)

**Date:** 2026-08-07
**Target:** WoW Classic Era / Anniversary realms (1.15.x client)
**Status:** Approved by user 2026-08-07

## Concept

A WoW Classic addon implementing a collectible card game layer over normal gameplay.
Playing the game (quests, kills, honor, bosses, exploration, leveling) earns **Pack
Points**. 100 points buys a **Pack** of 5 random cards. Packs are opened in a reveal
UI (left-click cards one at a time, right-click to reveal all). Cards depict WoW
spells, NPCs, and items across six rarity tiers using the game's own quality colors:

| Tier | Rarity    | Color  | Quality index |
|------|-----------|--------|---------------|
| 1    | Junk      | Gray   | 0             |
| 2    | Common    | White  | 1             |
| 3    | Uncommon  | Green  | 2             |
| 4    | Rare      | Blue   | 3             |
| 5    | Epic      | Purple | 4             |
| 6    | Legendary | Orange | 5             |

## Scope (v1)

- Earn Pack Points from gameplay events.
- Buy and open packs (5-card reveal UI with flip interaction).
- Collection browser ("binder") with filters, search, completion tracking.
- Duplicate handling: dupes stack with a count and can be **dusted** into Pack Points.
- Chat flexing: optional auto-announce of Epic+ pulls; `[WoWTCG:id]` tokens become
  clickable card links for other addon users.
- Debug/test slash commands.

**Out of scope (v1):** trading, dueling/gameplay with cards, multiple card sets,
minimap-button libraries (LDB/DataBroker), localization beyond enUS.

## Architecture

Modular vanilla Lua — no external libraries. One file per concern. Addon table shared
across files via the standard `local ADDON_NAME, ns = ...` vararg namespace pattern.

```
WoWTCG/                    (repo root == addon folder; drops into Interface/AddOns)
├── WoWTCG.toc             Interface 11507 (bump to current client build as needed)
├── Core.lua               init, SavedVariables, slash commands, minimap button
├── Data/
│   └── Cards.lua          curated ~300-card database (pure data)
├── PointsEngine.lua       gameplay event listeners → award points
├── PackSystem.lua         pack purchase, rarity rolls, pity, dusting (pure logic)
├── ChatFlex.lua           announcements + chat-token rendering/click handling
├── UI/
│   ├── CardWidget.lua     reusable card frame factory (art, border, flip anim)
│   ├── PackOpening.lua    5-card reveal screen
│   └── Collection.lua     binder browser
├── docs/                  (ignored by the game client)
└── tests/                 pure-Lua unit tests + WoW API stub (ignored by client)
```

Load order in the .toc follows the list above: data and logic before UI.

### Module boundaries

- **Data/Cards.lua** exports `ns.CARDS` (array) and `ns.CardsById` (map). No logic.
- **PackSystem.lua** is pure logic over injected state + RNG (`math.random` injectable
  for tests): `CanAfford()`, `BuyPack()`, `RollPack()`, `DustCard()`, `DustAllDupes()`.
  No frame/UI code — unit-testable outside the game.
- **PointsEngine.lua** maps game events to `ns.AddPoints(amount, reason)`. All point
  values live in one `ns.POINT_VALUES` table.
- **UI modules** read state through `ns` accessors and never mutate SavedVariables
  directly except via PackSystem/Core functions.

## Card database

Each card:

```lua
{ id = 101, name = "Frostbolt", type = "SPELL", rarity = 3,
  icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
  flavor = "Slows them down. Permanently, if you're lucky." }
```

- `id` is a stable integer, never reused. ID ranges by type for readability:
  1–99 reserved, 100s–200s spells, 300s–400s NPCs, 500s–600s items (approximate).
- Icons are hardcoded `Interface\Icons\...` paths — render instantly with no
  server cache dependency.
- Target distribution (~300 cards): 40 Junk / 90 Common / 80 Uncommon / 55 Rare /
  25 Epic / 10 Legendary. Mix of SPELL/NPC/ITEM in every tier.
- Tone: Junk is literal junk (Broken Fang, Murloc Fin Soup); Legendary is the
  Classic pantheon (Ragnaros, Onyxia, Thunderfury, Sulfuras, ...). Flavor text is
  short, lore-flavored, lightly funny.

## Economy

**Pack cost:** 100 points. **Target rate:** ~1 pack per 20–30 min of active play.

| Source          | Event                                        | Points |
|-----------------|----------------------------------------------|--------|
| Mob kill        | `COMBAT_LOG_EVENT_UNFILTERED` → `PARTY_KILL` (player/pet source) | 2 |
| Quest turn-in   | `QUEST_TURNED_IN`                            | 25     |
| Honor kill      | `CHAT_MSG_COMBAT_HONOR_GAIN` (with honor amount) | 5  |
| Boss kill       | `ENCOUNTER_END` (success == 1)               | 50     |
| Zone explored   | `UI_INFO_MESSAGE` (exploration message types)| 10     |
| Level up        | `PLAYER_LEVEL_UP`                            | 100    |

All values in `ns.POINT_VALUES` for easy tuning. Points and collection are
**account-wide** (`WoWTCG_DB` in SavedVariables, not PerCharacter).

## Pack rolls

Each of the 5 cards rolls rarity independently:

Junk 20% / Common 45% / Uncommon 20% / Rare 10% / Epic 4% / Legendary 1%.

Then a uniform pick among that tier's cards. Guarantees, applied in order:

1. **Pack floor:** if no card in the pack rolled Uncommon+, upgrade the last card
   to Uncommon.
2. **Epic pity:** `packsSinceEpic` counter; on the 10th consecutive pack without an
   Epic+, one slot is forced to Epic. Counter resets on any natural or forced Epic+.
3. **Legendary pity:** `packsSinceLegendary`; on the 40th consecutive pack without a
   Legendary, one slot is forced to Legendary. Resets on any Legendary.

Pity counters persist in SavedVariables. Forced upgrades replace the lowest-rarity
slot in the pack.

## Dusting

Duplicates stack (`collection[cardID] = count`). Any copy beyond the first can be
dusted for points by rarity: **1 / 2 / 5 / 15 / 40 / 150**. Collection UI offers
per-card "Dust duplicate" and a "Dust all duplicates" button (with confirmation).
Dusting never removes the last copy.

## Pack opening UI

- Opened from the binder ("Open Pack" button, shows owned pack count) or `/tcg open`.
- Modal frame, dimmed backdrop, 5 face-down card backs in a row.
- **Left-click** a card back → flip animation, reveal card (icon, name in rarity
  color, rarity border, type tag, flavor text). Epic+ reveals get a glow flash and
  a sound (`PlaySound` with an existing game kit sound).
- **Right-click** anywhere on the frame → reveal all remaining at once.
- "NEW" badge on first-time cards; dupe count shown on repeats.
- After all 5 revealed: summary line + "Open another" (if affordable) / "Done".

## Collection UI

- 3×3 card grid per page, page arrows, drag-to-move main frame, closes on Escape
  (via `UISpecialFrames`).
- Filters: rarity dropdown, type dropdown, owned/unowned/all toggle; name search box.
- Unowned cards render as darkened silhouettes with "?" (name hidden for unowned
  Epic+ to preserve mystery; shown for lower tiers).
- Header: Pack Points, packs owned, Buy Pack button, completion % overall and
  per-rarity, Dust-all-dupes button.
- Clicking an owned card opens a larger preview popout (same widget, bigger scale).

## Chat flexing

- Setting: announce channel (OFF / GUILD / PARTY / SAY / EMOTE), default OFF, plus
  minimum announced rarity (default Epic).
- Announce text example: `just pulled [WoWTCG:412] from a pack!` sent via
  `SendChatMessage` — plain text with an embedded token, since WoW strips unknown
  custom hyperlinks from real chat.
- Receiving side: `ChatFrame_AddMessageEventFilter` on all common chat events
  rewrites `[WoWTCG:412]` → `|cffa335ee|HWoWTCG:card:412|h[Onyxia]|h|r` for users
  running the addon. A hooked `SetItemRef`/`ChatFrame_OnHyperlinkShow` handler opens
  the card preview when clicked. Non-users just see the plain token — harmless.
- Local pull toasts always print to the player's own chat frame in rarity color.

## Slash commands

```
/tcg                  toggle collection window
/tcg open             open a pack (if owned)
/tcg buy              buy a pack
/tcg points           print current points
/tcg config           print/toggle settings (announce channel, min rarity, sounds)
/tcg debug points N   grant N points        (debug)
/tcg debug pack       grant a free pack     (debug)
/tcg debug legendary  force next pack to contain a Legendary (debug)
/tcg debug resetpity  reset pity counters   (debug)
/tcg debug wipe       full data reset with confirmation (debug)
```

Minimap button (plain vanilla Button frame anchored to Minimap, draggable around the
rim, position saved) toggles the collection window.

## SavedVariables schema

```lua
WoWTCG_DB = {
  version = 1,               -- schema version for future migrations
  points = 0,
  packs = 0,                 -- unopened packs
  collection = {},           -- [cardID] = count
  pity = { epic = 0, legendary = 0 },
  stats = { packsOpened = 0, totalPoints = 0, dusted = 0,
            byReason = {} }, -- points earned per source
  settings = { announceChannel = "OFF", announceMinRarity = 5,
               sounds = true, minimap = { angle = 200 } },
}
```

`version` gates a migration function in Core.lua on ADDON_LOADED.

## Error handling

- All event handlers wrap their body so a bad payload never hard-errors mid-combat
  (nil-check event args; unknown quest/encounter IDs still award points).
- SavedVariables loaded defensively: missing keys backfilled from a defaults table
  (deep-fill, never overwrite existing values).
- `RollPack` asserts the card DB has at least one card per rarity at load and
  falls back one tier down if a tier is somehow empty.

## Testing

- `tests/wow_api_stub.lua`: minimal fakes (`CreateFrame` no-op tree, `math.random`
  seedable, event dispatch helper).
- Pure-logic unit tests (plain Lua, runnable with `lua tests/run.lua` on Lua 5.1+):
  - rarity distribution over large N within tolerance
  - pack floor guarantee always holds
  - pity triggers at exactly 10/40 and resets correctly
  - dust math and never-dust-last-copy rule
  - points engine event → value mapping, honor parse, account totals
  - card DB integrity: unique IDs, valid rarity, icon path present, distribution counts
- In-game verification via `/tcg debug` commands.

## Risks / notes

- **Interface number drift:** .toc pins `## Interface: 11507`; Anniversary client
  patches will require bumping (check with `/dump (select(4, GetBuildInfo()))`).
  "Load out of date AddOns" covers the gap meanwhile.
- `ENCOUNTER_END` exists on the 1.15 Classic Era client; if a specific fight doesn't
  fire it, boss points are simply missed — acceptable.
- Exploration detection via `UI_INFO_MESSAGE` compares against discovery message
  types; if the client changes these, exploration points silently stop — acceptable.
- Kill farming (gray mobs) is possible; v1 accepts this (personal-use addon).
