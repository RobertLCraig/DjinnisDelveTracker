# Data Model

One saved variable, `DjinnisDelveTrackerDB`, managed by AceDB-3.0. Everything the addon knows
lives in `global` (shared by the whole account) or `profile` (settings). There is no `char`
scope: per-character facts live in the account-wide roster so alts are visible while you are
logged in as someone else.

## Quest state

The single enum every layer uses. Stored as a string so saved variables stay readable.

| Value | Meaning | Source of truth |
|---|---|---|
| `NOT_STARTED` | In the catalogue, not in the log, never completed | none of the below |
| `IN_PROGRESS` | In the log, objectives outstanding | `C_QuestLog.IsOnQuest(id)` |
| `READY` | In the log, objectives done, not handed in (**banked**) | `C_QuestLog.ReadyForTurnIn(id)` |
| `TURNED_IN` | Handed in on this character | `C_QuestLog.IsQuestFlaggedCompleted(id)` |

Evaluated in the order `TURNED_IN` → `READY` → `IN_PROGRESS` → `NOT_STARTED`; the first match
wins. A quest can be both on-quest and ready, so order matters.

## `db.global`

```lua
catalogue = {
    [questID] = {
        delve     = string,   -- delve name, from the localised quest title after ": "
        title     = string,   -- full localised quest title, cached for display
        seeded    = boolean,  -- true if it shipped in Data/Quests.lua, false if discovered
        firstSeen = number,   -- unix time (time()) the addon first recorded it
        mapID     = number,   -- uiMapID of the delve entrance, nil until located
        x, y      = number,   -- normalised map coordinates, 0-1 (NOT 0-100)
        locSource = string,   -- "quest" (C_QuestLog.GetNextWaypoint) or "poi"
                              -- (C_AreaPoiInfo, name-matched). "quest" wins.
    },
}

warModeQuests = {
    [questID] = boolean,  -- does the War Mode bonus measurably apply to this quest
}

xpBuffs = {
    [spellID] = number,   -- percent, learned by parsing the buff's own description
}

xpCurve = {
    [level] = number,  -- observed UnitXPMax() at that level; overrides the shipped seed
}

questXP = {
    [questID] = {
        [level] = number,  -- observed BASE reward XP (pre-War-Mode) at that character level
    },
}

characters = {
    [GUID] = {
        guid     = string,
        name     = string,
        realm    = string,
        class    = string,   -- locale-independent class file name, e.g. "MAGE"
        level    = number,
        xp       = number,   -- UnitXP at snapshot
        xpMax    = number,   -- UnitXPMax at snapshot
        warMode  = boolean,
        quests   = { [questID] = questState },  -- the enum above
        banked   = number,   -- count of READY quests at snapshot
        bankedXP = number,   -- summed BASE XP of those quests at snapshot, pre-multiplier
        updated  = number,   -- unix time of the snapshot
    },
}
```

### Units and conventions

- All XP values are **base** XP: the second return of `GetQuestLogRewardXP(questID)`, which
  excludes the War Mode bonus. Multipliers are applied at display time, never at storage time,
  so a stored number never depends on what buffs happened to be up when it was written.
- `level` is the character level the value was observed at, not the quest's own level.
- Times are `time()` (unix seconds), never formatted strings.
- `class` is the file name (`UnitClassBase`), so colouring works in any locale.
- `bankedXP` is a snapshot for the warband tab. It is stale by definition for a character you
  are not logged into, and the UI labels it with its `updated` time.

## `db.profile`

```lua
minimap  = { hide = false, minimapPos = number },   -- LibDBIcon owns the position keys
window   = { point, relPoint, x, y, scale },        -- main window placement
tracker  = { show, locked, point, relPoint, x, y, scale },
buffs    = {
    warMode = "auto",   -- "auto" | "on" | "off"; auto reads C_PvP.IsWarModeDesired()
    custom  = 0,        -- extra percent, integer, for anything the aura scan misses
},
includeAllQuests = false,   -- fold non-delve turn-in-ready quests into the projection
announce         = true,    -- chat line when a delve quest becomes ready
debug            = false,
```

## Derived values (never stored)

Computed on demand so they cannot drift from their inputs:

- **Multiplier** `= 1 + detectedBuffs/100 + custom/100 + warModeBonus/100`, where
  `detectedBuffs` is the summed percentage of every experience buff currently on the player
  (D11) and `warModeBonus` comes from `C_PvP.GetWarModeRewardBonus()` and applies only to
  quests that take it, decided by measurement rather than by the client flag (D7).
- **Effective multiplier** `= projection.totalXP / sum(base)`, computed by the simulation.
  This is the only multiplier the UI may display, because it is the one that was applied.
- **Observed growth**: geometric mean of `xp(level+n)/xp(level)` across every quest seen at
  more than one level. Overrides the modelled scaling once it exists (D8).
- **Projection** `{ level, xp, xpMax, pct, totalXP, levelsGained, atMaxLevel, estimated }` from
  `Estimator:Simulate()`. `estimated` is true when any quest XP in the run came from the scaling
  model rather than a live or observed reading, so the UI can mark the number as a projection.
