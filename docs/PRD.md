# PRD: Djinni's Delve Tracker

## Purpose

Midnight's alt-levelling route runs through the ten **Delver's Call** quests, one per delve.
The default UI makes it hard to run: the quest log shows ten near-identical entries with no
sense of which delves are still untouched, and nothing anywhere tells you what the completed
ones are actually worth. This addon answers both questions at a glance, per character and
across the warband.

### The banking premise was wrong

This project started from the widely repeated advice that Delver's Call reward XP scales with
level, so you should bank all ten and hand them in as late as possible. The addon measured it,
and that is not what happens.

Across eight quests observed at three consecutive levels, base reward XP moved in a flat line:

| Level | Base XP |
|---|---|
| 85 | 124,400 |
| 86 | 125,750 |
| 87 | 127,100 |
| 88 | 128,450 |

**Exactly +1,350 per level**, about +1.08%, giving `base = 124,400 + 1,350 x (level - 85)`.
The XP required per level grows about **4.2%** over the same range. So the raw number on the quest does rise with level, which is what everyone
reports, but it rises far slower than the bar it has to fill. A banked stack is worth roughly
3% of a level less for every level you hold it, before any overflow burned at the cap.

**Holding quests costs levels.** The addon's job is therefore not to help you bank them, it is
to show you what you have, what it is worth right now, and what waiting would cost.

## Goals

1. Show the state of every Delver's Call quest for the current character in one view:
   **not started / in progress / ready to hand in / handed in**.
2. Show what handing in the completed ones right now would get you: total XP after buffs, the
   level you would land on, and how far into it.
   Corollary, from the measurement above: show the **cost of waiting**, so the case for handing
   in early is visible rather than argued.
3. Show the same banked count and level for every character in the warband, so you can see which
   alt is sitting on an unclaimed stack.
4. Keep working when Blizzard adds delves in a later patch, without a code change.

## Success criteria

- On a character mid-run, the window lists all ten delves with the correct state, and the state
  updates within a second of accepting, completing, or handing in a quest.
- The "hand in now" projection lands on the same level and within ~1% of the same progress bar
  position as the real turn-in. Verified by handing in a real stack and comparing.
- A character who has never been near a delve still sees all ten rows, as "not started".
- A fresh alt with an empty database sees a usable projection, using the shipped XP curve.
- Nothing in the addon accepts, abandons, or hands in a quest. It is read-only against the game.

## Scope

In scope:

- Per-character Delver's Call quest state, with automatic discovery of new delve quests.
- XP projection with a level-up simulation and toggleable buff multipliers.
- A "what is the stack worth if I wait until level N" comparison.
- Warband tab listing every character seen, with level and banked count.
- Compact always-on tracker panel, minimap button, DataBroker feed, slash commands.
- An optional toggle to fold every other turn-in-ready quest in the log into the projection.
- Click a delve row to set a waypoint on its entrance, including delves you have not started.

Non-goals:

- Any automation of questing, delve entry, or turn-in. Read-only, deliberately.
- Routing, maps, or "which delve is nearest" guidance. Other addons do that.
- Tracking delve completion itself, or Bountiful/tiered delve rewards. The quest is the unit.
- Season, Great Vault, or gear progress. Not a delve-progress addon, a levelling addon.

## Constraints

- `GetQuestLogRewardXP(questID)` only returns reward data for quests **in your log**. XP for a
  quest you have not accepted is unknown until it is accepted, so the projection covers banked
  quests only and the UI must say so rather than silently under-report.
- Quest reward XP scales with level, so a value read at level 84 is not the value you get at 88.
  Projecting forward needs a scaling model. See [DECISIONS.md](DECISIONS.md) D4.
- Rested XP does not apply to quest turn-ins. It must not appear in the projection.
- Live XP requirements per level can change in a patch. The shipped curve is a seed, not truth.
- Everything must survive Blizzard renaming or relocating delves in a later patch.

## Requirements

| # | Requirement |
|---|---|
| R1 | Resolve state for every quest in the catalogue: not started, in progress, ready, handed in. |
| R2 | Discover previously unknown Delver's Call quests from the quest log and the world map, and add them to the account-wide catalogue. |
| R3 | Record base reward XP per quest per level as it is observed, account-wide. |
| R4 | Project the banked stack forward with per-quest level-up simulation and buff multipliers. |
| R5 | Detect War Mode and its live bonus percentage automatically; allow manual override. |
| R6 | Snapshot every character's level, XP and quest states into an account-wide roster. |
| R7 | Persist a self-correcting XP-per-level curve, seeded with known Midnight values. |
| R8 | Never call an API that changes game state. |
| R9 | Cache delve entrance coordinates account-wide and set a waypoint on row click. |
| R10 | Display the multiplier the projection actually applied, never the one the settings imply. |
