# Djinni's Delve Tracker

**Orient before changing anything.** Read [docs/HANDOVER.md](docs/HANDOVER.md) first, then the
docs it indexes that bear on the task. Do not act on a partial read, and do not conclude
something is missing from one file alone.

## What this is

A World of Warcraft (Midnight, 12.0) addon that tracks the ten **Delver's Call** quests and
projects what handing in the banked stack would be worth. The goal is levelling alts fast:
the quests scale with character level, so you bank them all and dump them late.

## Hard rules

1. **Read-only against the game.** Never call an API that accepts, abandons, shares or hands in
   a quest. The addon exists to stop you handing in early; it must never be able to do it for
   you. See [docs/DECISIONS.md](docs/DECISIONS.md) D5.
2. **Store base XP, never multiplied XP.** `GetQuestLogRewardXP` returns `total, base`; `total`
   already has War Mode in it. Persist `base` only, apply multipliers at display time (D3).
3. **Never hardcode a localised string.** The Delver's Call title prefix is derived at runtime
   from a seed quest's own title (D1). Locale tables under `Locales/` are for our own UI text.
4. **The shipped XP curve is a seed, not truth.** Live `UnitXPMax()` always wins, and Blizzard
   retunes these numbers.

## Layout

```
Data/       static tables: seed quest IDs, seed XP curve
Modules/    Catalogue (known quests), Roster (character snapshots),
            Estimator (all the maths), Scanner (all the game reads and events)
UI/         MainWindow (two tabs), Tracker (compact panel)
Core.lua    AceAddon object, saved variables, broker, refresh fan-out
Options.lua AceConfig table and slash commands
```

Load order lives in `DjinnisDelveTracker.toc` and matters: `Data` → `Core` → `Modules` → `UI` →
`Options`.

## Conventions

- Ace3, matching Djinni's Warband Manager. Libraries are embedded under `libs/` via `embeds.xml`.
- UI files register a callback with `ns.RegisterRefresh`; the Scanner calls `ns.Refresh()` and
  never touches a frame directly.
- British spelling in prose and comments; American in API names, because the API is.
- `.\deploy.ps1` mirrors the addon into the live client. `docs/` is excluded from the deploy.

## Testing

There is no test harness: it is a WoW addon, so it is verified in game. Before deploying, run a
syntax check over everything outside `libs/`:

```powershell
Get-ChildItem -Recurse -Filter *.lua | Where-Object { $_.FullName -notlike '*\libs\*' } |
    ForEach-Object { & 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p $_.FullName }
```
