# WoWTCG

A collectible card game inside WoW Classic / Anniversary. Playing the game earns
**Pack Points**; 100 points buys a 5-card pack. Open packs, chase Legendaries,
fill your binder, dust your dupes, and flex your pulls in guild chat.

## Install

Copy this folder into your AddOns directory so the path is:

    World of Warcraft/_classic_era_/Interface/AddOns/WoWTCG/WoWTCG.toc

The folder must be named `WoWTCG`. If the game client is newer than the
`## Interface:` number in the TOC, enable "Load out of date AddOns".

## Earning Pack Points

| Activity        | Points |
|-----------------|--------|
| Mob kill        | 2      |
| Quest turn-in   | 25     |
| Honorable kill  | 5      |
| Boss kill       | 50     |
| Zone explored   | 10     |
| Level up        | 100    |

A pack costs **100 points** and contains 5 cards. Every pack holds at least one
Uncommon+; pity guarantees an Epic+ at 10 barren packs and a Legendary by 40.
Every card has a 1-in-20 chance of being a **foil** (any rarity) — foils shimmer
in the pack screen and in your binder. Duplicates can be dusted for points:
1/2/5/15/40/150 by rarity (non-foil spares are dusted first). Cards you have
not unlocked appear as anonymous "? ? ?" silhouettes in the binder.

## Commands

    /tcg                  toggle the collection binder
    /tcg open             open a pack
    /tcg buy              buy a pack (100 points)
    /tcg points           show your balance
    /tcg config           show settings; options:
    /tcg config announce OFF|GUILD|PARTY|SAY|EMOTE
    /tcg config minrarity 1-6
    /tcg config sounds on|off
    /tcg debug            testing helpers (grant points/packs, force legendary/foil, wipe)

Left-click cards in the pack screen to flip them one at a time; right-click to
reveal all. In the binder: left-click a card to preview it, right-click to dust
a duplicate. Collection and points are shared account-wide across characters.

## Development

Pure-logic modules are unit-tested outside the game:

    lua tests/run.lua

Card data lives in `Data/Cards.lua` ("Classic Vol. 1", 300 cards). Card ids are
permanent — never reuse or renumber them.
