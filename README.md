# Djinni's Delve Tracker

Tracks the ten **Delver's Call** quests in WoW: Midnight and tells you what handing in the
banked stack would actually get you.

## Why

Delver's Call reward XP scales with your character level, so the fast way to level an alt is to
run every delve, leave all ten quests sitting complete in your log, and hand them in as late as
you can with War Mode and any XP buffs running. The default UI gives you ten near-identical
quest log entries and no idea what the pile is worth.

## What it shows

- Every delve quest for the current character as **not started / in progress / banked / handed
  in**, updated as you play.
- The banked total in XP after buffs, and the level and percentage you would land on.
- A "if you wait until level N instead" comparison, so early turn-in has a visible price.
- Click any delve to drop a waypoint on its entrance, including ones you have not started.
- While you are inside a delve: live objective progress, the Sanctified Banner and where it
  spawns, whether the treasure reward is earned, and Brann's rank and XP.
- A Warband tab: every character, their level, and how many quests they are sitting on.
- A compact panel you can leave on screen, a minimap button, and a DataBroker feed.

It never accepts, abandons or hands in a quest. It only reads.

## Usage

| Command | Does |
|---|---|
| `/dvt` | Open or close the window |
| `/dvt config` | Settings |
| `/dvt scan` | Force a rescan |
| `/dvt reset` | Put the window and panel back in the middle |
| `/dvt debug` | Toggle debug output, including turn-in projection accuracy |
| `/dvt xp` | Dump the recorded reward-XP observations and the measured per-level growth |

`/delvetracker` works everywhere `/dvt` does. The short form used to be `/ddt`, which
collided with Djinni's Data Texts; see the comment in `Options.lua` for why that collision
resolved unpredictably rather than in load order.

## Notes

- XP for a quest you have not accepted is not readable by any addon, so the projection covers
  banked quests only.
- The "wait until level N" figures are modelled, not measured. See `docs/DECISIONS.md` D4.
- Delves added in a later patch are picked up automatically; no update needed.

## Installing from source

```powershell
.\deploy.ps1            # mirrors into the live client
.\deploy.ps1 -DryRun    # show what would change
```
