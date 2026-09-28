---
waiting_on: Rob, an in-game /reload on a character that showed the 13 rows - recheck 2026-10-06
---
# 0001 The delve list shows War Within delves

## What I need from you

**One in-game check. v0.6.7 is already installed; nothing to deploy.**

1. Log in on the character that showed 13 rows, `/reload`, open the window (left-click the
   tracker panel), and walk the steps below. Each has its own pass.

| # | Do | Pass |
|---|---|---|
| 1 | Look at the Character tab | 10 delves. Fungal Folly, The Skittering Breach, Tak-Rethan Abyss are gone |
| 2 | Click the Warband tab | No row or count for those three |
| 3 | Back on Character, read the wait list footer | "measured quest XP growth" is above +0.78%, near +1.08% |
| 4 | Accept a War Within Delver's Call quest, `/reload` | It does not reappear |
| 5 | Character tab | Headings in order: Eversong Woods, Zul'Aman, Harandar, Voidstorm |
| 6 | Read each heading's delves | Each delve sits under its real zone. None under "Zone not read yet" |
| 7 | Look at the bottom row | Fully visible, not cut off by the footer |

**Fail:** say which step, and for step 6 which delve went where. The likeliest step 6 failure is a
Silvermoon City delve (Collegiate Calamity, The Darkway or Parhelion Plaza) landing under "Zone not
read yet", because the city is probably its own map and not one of the four zone maps read.
Moving the card back to `todo/` with that note is enough.

**Why it needs you:** every criterion is what the game draws on screen, and no agent can run the
client.

## Goal

The Character and Warband tabs list the ten Midnight Delver's Call quests and nothing else.

**Found 2026-09-27** (Rob's screenshot): 13 rows. Fungal Folly (83758), The Skittering Breach
(83768) and Tak-Rethan Abyss (83771) are War Within delves. D1's title match let them in because
they share the `Delver's Call:` prefix.

**Built (32f9918, v0.6.6, deployed).** `Catalogue:Belongs` refuses any quest ID below the lowest
seed (93372). `Catalogue:PruneOlderExpansions` runs at load and removes the three from the
catalogue, `questXP` and every character's `quests`. Decision D14.

**Also built: group by zone (37e6b37, v0.6.7, deployed).** At login the addon reads the delve POIs
of the four Midnight zone maps (`ns.ZONE_MAPS`: 2395, 2437, 2413, 2405) and stores the zone on
each catalogue entry as `zone`. The Character tab puts a heading above each zone.

## Acceptance

All `proves: manual`: the steps in the table above are criteria 1-7.

## Comments

**2026-09-29** Adversarial review (unattended agent, not the builder). Verdict: code holds, only
in-game checks remain, so `human-review/`.

What was attacked:
- **Prune.** Ran `PruneOlderExpansions` and `Belongs` in a Lua 5.1 harness against a fake DB
  holding the three War Within IDs plus two Midnight ones, including a character record with no
  `quests` table. The three went from catalogue, `questXP` and character state; the two stayed;
  `Belongs(nil)` is false and a future higher ID is accepted. Clearing a key during `pairs` is
  legal Lua.
- **Second writers.** `questXP` and `rec.quests` are only ever written by `Scanner:Scan` iterating
  `Catalogue:Ordered()`, and both discovery paths go through `Remember`, which now calls
  `Belongs`. No path re-adds a War Within ID.
- **Load order.** `ID_FLOOR` is computed at file scope from `ns.SEED_QUESTS`; `Data\Quests.lua`
  loads before `Modules\Catalogue.lua` in the `.toc`. `PruneOlderExpansions` runs from
  `SeedFromData`, in `OnInitialize` right after AceDB is built (Ace fires it at `ADDON_LOADED`), so it does not hit the 2026-09-02 trap.
- **APIs** against `Blizzard_APIDocumentationGenerated`: `C_AreaPoiInfo.GetDelvesForMap`,
  `GetAreaPOIInfo` and `C_Map.GetMapInfo` exist, none is deprecated, and none declares a secret
  return, so `Normalise(info.name)` and `info.name` as a lookup key are not secret-value misuse.
- **Layout.** Heading slots run ahead of row indices; the returned `slot` count feeds the window
  height, so heading rows are paid for. Headings are hidden when the list shrinks. The sort
  comparator is consistent (zone rank, then state, then name).
- **Events.** The card added no `RegisterEvent`; `HarvestZones` rides the existing
  `ZONE_CHANGED_NEW_AREA` / `PLAYER_ENTERING_WORLD` handler.
- `luac -p` clean on every touched file. No browser surface exists; the surface is the game.

Not proven here: whether a delve POI appears on more than one of the four zone maps (last zone read
would win) and whether Silvermoon delves appear on Eversong's map at all. Step 6 settles both.

Security: **weakest point** is name matching, since a POI whose name normalises to another delve's
would file the wrong zone and waypoint; cosmetic only. **Unchecked:** nothing external enters; all
input is the game's own quest and map data. **Leaks:** nothing; the data is local SavedVariables.

Outside this card, raised as `0002`: the tracker panel is drag-movable but not in Edit Mode, and its
right-click opens the options panel directly.
