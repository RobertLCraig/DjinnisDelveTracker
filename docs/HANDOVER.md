# Handover: Djinni's Delve Tracker

**Stage:** active, v0.5.0. The projection is now calibrated from real turn-ins rather than
modelled from buffs (D13). Not yet re-run in game.
**Last session:** 2026-07-21.

## The +25% is Warband Mentored Leveling (solved)

Two turn-ins in Aman'zar Village paid **157,187** against a base of **125,750**: exactly
**+25.0%**, twice, with War Mode off and the Timewalking buff expired. The cause is **Warband
Mentored Leveling**: +5% XP per level-90 character on the account, capped at +25% with five.

It is granted by an achievement series (42328-42332, One through Five Warband Mentors:
Midnight), **not an aura**, which is why the aura scan could never have found it. The tiers are
cumulative, so the highest completed one is the whole bonus. `Estimator:WarbandMentorBonus`
reads it, it appears in the buff line like any other source, and `ACHIEVEMENT_EARNED` refreshes
it when another alt dings 90.

This does not retire D13. The calibration stayed useful precisely because it was right about the
number while the model was wrong about the reason, and it is what will catch the next source
neither of us knows about.

## Quest XP scaling: measured, and it inverts the premise

Three readings of the same quest family, one per level:

| Level | Base XP | Growth |
|---|---|---|
| 85 | 124,400 | |
| 86 | 125,750 | +1.09% |
| 87 | 127,100 | +1.07% |

Flat **+1,350 per level**, about **+1.08%**, against an XP bar that grows **~4.2%** per level.
So the banked stack is worth *fewer* levels the longer it is held, roughly 3% of a level lost
per level waited, before the cap-burn on top.

Confirmed across **eight quests** at all three levels, every one identical, measured growth
1.0108 per level. `/dvt xp` output, 2026-07-21 23:25.

**This contradicts the community advice the project started from.** "Bank everything and dump
at 88" is wrong: the raw XP number rises, the levels it buys falls. The wait-list now shows
this from measured data (D8 growth) rather than the modelled curve, and
[PRD.md](PRD.md) has been rewritten around the measurement.

Second observation from the same turn-ins: base XP was **125,750** where every earlier reading
was **124,400**. If a level-up happened in between, quest XP grew 1.1% for a level where the XP
bar grew 4.2%, which would mean **waiting to hand in loses levels rather than gaining them**,
inverting the premise in [PRD.md](PRD.md). `/dvt xp` shows the level each value was recorded at.
Confirm before acting on it.

## Doc index

| Doc | Covers |
|---|---|
| [PRD.md](PRD.md) | Purpose, goals, success criteria, scope, constraints, requirements |
| [DATA-MODEL.md](DATA-MODEL.md) | Saved-variable schema, the quest state enum, units |
| [DECISIONS.md](DECISIONS.md) | D1-D10, including the unvalidated scaling assumption |
| [../CLAUDE.md](../CLAUDE.md) | Hard rules and code layout |
| [../README.md](../README.md) | User-facing description and slash commands |

`docs/spec/` and `docs/build/` exist and are empty; nothing has needed them yet.

## Goal in one line

Show the state of every Midnight Delver's Call quest and what handing in the banked stack would
be worth, so alts can be levelled on the bank-then-dump route. Full statement in
[PRD.md](PRD.md).

## Canonical data shape

One saved variable, `DjinnisDelveTrackerDB`. Everything account-wide in `db.global`:
`catalogue` (known quests), `xpCurve` (observed XP per level), `questXP` (observed base reward
XP per quest per level), `characters` (per-GUID snapshots). Settings in `db.profile`. The quest
state enum is `NOT_STARTED | IN_PROGRESS | READY | TURNED_IN`, resolved in that reverse order.
Full detail in [DATA-MODEL.md](DATA-MODEL.md); do not invent a second shape.

## Established facts

- The ten Midnight Delver's Call quest IDs are in `Data/Quests.lua`, taken from Wowhead and
  verified one by one against the live quest pages: 93372, 93384, 93385, 93386, 93409, 93410,
  93416, 93421, 93427, 93428. Note it is **ten**, not the eight most guides claim.
- XP to go 80 → 90 is 4,963,065, per-level values in `Data/XPCurve.lua`.
- `GetQuestLogRewardXP(questID)` returns `total, base`; `total` already includes War Mode.
  Verified in `wow-ui-source` `QuestUtils.lua:761`.
- `QUEST_TURNED_IN` carries the XP actually granted, which is the only ground truth available
  for checking the projection.
- Live client is 12.0.7, interface 120007. `wow-ui-source` is checked out at
  `c:\Dev\WoWAddons\wow-ui-source` and is current; use it to verify any API before using it.

## Current state

v0.1.0 ran in game and worked: ten rows, correct states, six banked at 124,400 base each on a
level 85 character. Two real defects showed up in that screenshot and are now fixed, plus
click-to-waypoint added. All syntax-checked with `luac -p` and deployed. **v0.2.0 has not been
run in game.**

Found and fixed:

1. **The War Mode bonus was not being applied but the header claimed it was.** The summary read
   x1.45 while the projection used 1.30, caught by reconciling the displayed total (983,994)
   against both candidate multipliers. Cause: `QuestCanHaveWarModeBonus` returns false for these
   quests. Now measured from `GetQuestLogRewardXP`'s two returns, and the UI shows the
   multiplier the simulation actually applied. See D7.
2. **The wait-list was circular.** Every row read "1.9 lv" because scaling quest XP by the level
   curve makes levels-worth constant by construction. Now prefers measured growth, shows the
   delta against handing in now, and labels itself as modelled until real data exists. See D8.
3. The portrait ring covered the Character tab; tabs moved below it, and the active tab is now
   highlighted rather than disabled.
4. Changing a buff toggle refreshed the window but not the tracker panel, so the two disagreed.

v0.3.0 added live in-delve tracking, reimplemented from the Delve module in Djinni's Data
Texts (D10): `Modules/DelveState.lua` reads the `ScenarioHeaderDelves` widget for objectives
and their progress, latches the Sanctified Banner, reads the treasure reward state and Brann's
rank and XP; `UI/DelvePanel.lua` renders it above the quest list; `Data/Banners.lua` carries the
spawn coordinates. The panel collapses to nothing outside a delve.

v0.3.1 fixed two things the live run exposed:

- **The level cap was being modelled but not reported.** A stack big enough to push past 90
  burns the overflow, which showed up as a bare "-0.22 lv" on the level-88 wait row, in green.
  `Simulate` now returns `wasted`, and both the wait rows and the headline say how much XP a
  turn-in throws away. Negative deltas are no longer coloured as improvements.
- **No warning for running a delve without its quest.** The screenshot caught exactly that:
  inside The Shadow Enclave with the quest "Not started", earning nothing. The panel now says
  so in red, and entering a delve in that state prints a chat line.

v0.4.0 replaced manual buff entry with aura detection (D11). The Timewalking buff is tiered
(Knowledge of the Timeways 5%, Mastery of the Timeways 30%) and is the reason the route works,
so typing a number was always going to be stale. `Data/XPBuffs.lua` seeds spell 1269517 at 5%;
anything else has its percentage parsed from the spell description and cached. The hardcoded
Darkmoon toggle is gone: its 10% was never verified and it would have double-counted against
detection. `QUEST_TURNED_IN` now shouts when a turn-in misses the projection by over 5%.

Also fixed in passing: both `DelveState` and `Scanner` called `self:RegisterUnitEvent`, which
**AceEvent-3.0 does not have**. That would have errored on load. They register `UNIT_AURA` and
filter on the unit argument instead.

## Verified end to end, 2026-07-21

A full ten-quest run from level 85 to 89 with the ledger recording every turn-in. Model and
measurement now agree to four decimal places under both conditions.

| Condition | Turn-ins | Multiplier |
|---|---|---|
| Sanctuary (Silvermoon), War Mode on or off | 4 | x1.3000 |
| Outdoors (Voidstorm, Harandar, Reliquary), War Mode active | 4 | x1.4500 |

x1.30 = Warband Mentor 25% + Knowledge of Timeways 5%. x1.45 adds War Mode's 15%, which
sanctuaries suppress. `Multipliers()` now models both correctly, so the calibration is
confirming the model rather than compensating for it.

Base reward XP, confirmed across ten quests and five levels:

    base = 124,400 + 1,350 x (level - 85)

Exactly +1,350 per level with no deviation anywhere in the data.

**Known cosmetic wart.** `db.global.calibration` still holds a stale `active:45` entry from
before the `Enlisted` double count was fixed. It can never match a current key, so it is inert,
but it shows up in `/dvt xp` looking like data. Wipe it if it causes confusion; do not wipe the
whole table or the good samples go with it.

## Next steps

1. **The project is not in git.** All of the above, including the evidence trail in
   `DECISIONS.md` which is worth more than the code, exists only on disk. Offered at the start
   of the session, never actioned.
2. Enter a delve without its quest and confirm the red warning and the chat line fire, then
   accept the quest and confirm they clear. Written from a screenshot, never tested live.
3. Click a delve row, including a "not started" one, and confirm the waypoint lands on the
   entrance. If "not started" rows report no location, `C_AreaPoiInfo.GetDelvesForMap` name
   matching is failing; check `/dump C_AreaPoiInfo.GetDelvesForMap(C_Map.GetBestMapForUnit("player"))`.
4. Run a second character to check the Warband tab, and a fresh alt to confirm an empty
   catalogue still lists all ten rows.

Done in this session: the D4/D8 scaling question (measured, 1.0107 per level), the War Mode
question (measured, +15% outdoors and nothing in sanctuaries), and the buff detection.

## Risks and open questions

- The community claim that turning in at 88 is "dramatically more" than 87 is **disproved**:
  in raw XP yes, in levels no, because base grows +1,350 flat against a bar that compounds at
  4.2%. Held for the record because it is the premise the project started from.
  [PRD.md](PRD.md) has been rewritten around the measurement.
- Discovery of a not-yet-accepted quest relies on `C_QuestLog.GetQuestsOnMap` returning delve
  quest offers. Untested. Only matters for delves added after this version.
- The description parser that reads a percentage out of a buff tooltip only fires on text
  containing "experience", which is English (D11). Known spell IDs work in any locale.
- **The live-delve code is a second copy** of logic that already exists in Djinni's Data Texts
  (D10). Season changes that break widget parsing break both. Banner detection in particular is
  fiddly: Tier 11+ delves grant no aura, so it hangs off an event toast whose title contains
  "Sanctified".
- Both addons pin banner spawns. Ours default off when Data Texts is detected, once, with a
  chat line saying why. If pins are missing, that is the first thing to check.
- No test harness exists and none is planned. Verification is in game.
