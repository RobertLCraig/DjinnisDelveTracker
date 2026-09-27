# Decisions

Append-only. Newest at the bottom.

## D1. Ship a seed quest list, but discover the rest at runtime

**Decision.** `Data/Quests.lua` ships the ten known Midnight Delver's Call quest IDs, and the
Scanner also adds any quest it meets whose title shares the localised `Delver's Call` prefix.

**Why.** Hardcoding alone breaks the moment 12.1 adds delves. Discovery alone is useless on a
fresh install: you cannot show "not started" for a quest you have never seen. Together, the
addon is correct on day one and keeps up afterwards.

**How the prefix works.** The localised prefix is derived at runtime by taking the title of a
seed quest and cutting at the last `": "`. No locale table to maintain, and it self-heals if
Blizzard changes the wording, as long as one seed quest still resolves.

## D2. Account-wide storage, no per-character scope

**Decision.** Quest state, the XP curve, XP observations and the character roster all live in
`db.global`, keyed by GUID.

**Why.** The warband tab has to show characters you are not logged into, which per-character
saved variables cannot do. Anything else would mean two homes for the same fact.

## D3. Store base XP, apply multipliers at display time

**Decision.** Only the pre-War-Mode `baseXp` return of `GetQuestLogRewardXP` is persisted.

**Why.** A stored number that already had War Mode baked in would mean the same quest reads
differently depending on a setting that was on at the time, and there would be no way to tell
after the fact. Storing base keeps one canonical value and makes the buff toggles honest.

## D4. Project forward-level quest XP from the level XP curve (assumption, needs validation)

**Decision.** When the addon needs a quest's reward XP at a level it has never observed, it
scales the known value by the ratio of XP-to-next-level between the two levels:
`xp(target) ≈ xp(known) × curve(target) / curve(known)`. Observed values always win over the
model, and the UI marks any projection that used the model.

**Why.** Quest reward XP scales with level, but no API exposes the value at a level you are not
at. Some model is needed or the "wait until 88" comparison cannot exist. The level curve is the
only scaling curve the client actually gives us, and it is the right shape (monotonic, ~5% per
level).

**Status: UNVALIDATED.** This is a plausible model, not a documented one. The addon records every
real observation, so the assumption is testable: hand in a quest, and the projection-versus-actual
line in the debug output shows the error. Revisit once there are observations at two or more
levels for the same quest.

## D5. Read-only against the game

**Decision.** No API that accepts, abandons, shares or completes a quest is called anywhere.

**Why.** The whole value of the strategy is *not* handing quests in early. An addon that could
turn one in by accident would destroy exactly the thing it exists to protect. It also keeps the
addon clear of protected-function and taint problems.

## D6. Rested XP is excluded from the projection

**Decision.** `GetXPExhaustion()` is not part of the maths.

**Why.** Rested XP applies to creature kills, not quest turn-ins. Including it would inflate the
projection and break the success criterion of landing on the right level.

## D7. Decide War Mode by measurement, not by the client flag

**Decision.** Whether a quest takes the War Mode bonus is decided by comparing the two returns
of `GetQuestLogRewardXP`: the first already includes the bonus, so `total > base` proves it
applies. `C_QuestLog.QuestCanHaveWarModeBonus` is only a fallback for when War Mode is off and
there is nothing to measure. The answer is cached account-wide in `warModeQuests`.

**Why.** The first build trusted the flag, which reported false. The result was a summary
reading "x1.45" while the projection quietly used 1.30, an 11% error in the headline number
and, worse, a UI that disagreed with its own arithmetic. Whether the flag is wrong or means
something narrower does not matter: the client's own subtraction is the better source, and it
cannot drift from what the projection uses.

**Correction, and it matters.** The conclusion drawn here at the time, "War Mode does not apply
to these quests", was **wrong**. It came from a reading taken inside a delve, where War Mode is
never in effect. A turn-in outdoors in Voidstorm with War Mode active measured
`128,450 -> 186,252`, exactly **x1.4500**, which is x1.30 plus the full 15%. War Mode applies to
Delver's Call quests at face value; it is sanctuaries and instances that suppress it. See D12
for the caching rule that stops that misreading becoming permanent.

**Consequence.** The UI shows `projection.effective`, the multiplier derived from the
simulation, never the one implied by the settings. If a buff does not land, the number says so.

## D8. Measure quest XP growth per level once there is data to measure

**Decision.** `ScaleXP` prefers the geometric mean of observed `xp(level+n)/xp(level)` ratios
across all recorded observations, and only falls back to the D4 level-curve model when no
quest has been seen at two levels.

**Why.** D4 is not merely unproven, it is circular for the wait-list. Scaling quest XP by the
same curve as the level bar makes the stack worth an identical number of levels at every
turn-in level, so the "hand in at 85 / 86 / 87 / 88" comparison came out flat by construction
and looked like a finding when it was an artefact. Real observations break the circularity.
Until they exist the UI says the comparison is modelled rather than showing four numbers that
imply a difference they cannot express.

**How the data arrives.** Banked quests sit in the log across a level-up, so a single ding with
a quest banked yields the same quest at two levels. `/dvt xp` dumps what has been recorded.

## D9. Two sources for delve entrance locations

**Decision.** Coordinates come from `C_QuestLog.GetNextWaypoint` for quests in the log, and
from `C_AreaPoiInfo.GetDelvesForMap` matched to a quest by delve name otherwise. Quest
waypoints win. Everything is cached account-wide in the catalogue.

**Why.** Neither source alone is enough. Quest waypoints are exact but need the quest accepted,
which is precisely what a "not started" row is not. POIs work for delves you have never
touched but have to be matched by name, which is fuzzier. Caching account-wide means one
character walking the continent makes every alt's list clickable.

## D10. Duplicate the live-delve tracking rather than depend on Djinni's Data Texts

**Decision.** `Modules/DelveState.lua` reimplements the widget scanning, Sanctified Banner
tracking, treasure reward state and companion XP that the Delve module in Djinni's Data Texts
already does. The two are independent copies.

**Why.** Data Texts keeps its namespace private (`local addonName, ns = ...`) and its Delve
module registers with an internal ActiveActivity aggregator rather than publishing a broker, so
there is nothing to read from outside. The alternatives were exporting an API from that addon,
which would make this one go blank whenever it is disabled, or extracting a shared library,
which means refactoring a module that works. Neither was worth it for a self-contained addon.

**Consequence.** Season changes that break the widget parsing break it in two places. Fixes
found here are worth carrying back, and vice versa. The banner coordinate table in
`Data/Banners.lua` is the same data with the same provenance.

**Related.** Both addons draw map pins on the banner spawns, which would double up. On first
run the addon detects Data Texts, turns its own pins off, and says so. The toggle stays.

## D11. Read XP buffs off the player, do not ask the user to type them

**Decision.** Every experience buff on the player is detected by scanning auras. Known spell
IDs (`Data/XPBuffs.lua`) give exact percentages; anything else has its percentage parsed out
of `C_Spell.GetSpellDescription` and cached account-wide in `xpBuffs`. The hardcoded Darkmoon
Faire toggle is gone. A manual "other bonus %" remains for whatever the scan cannot see.

**Why.** The Timewalking buff is the reason the whole route works, and it is **tiered**:
Knowledge of the Timeways is 5%, Mastery of the Timeways is 30%. A hardcoded number is wrong
for most of the run, and a number the user types is wrong the moment the tier changes and they
forget. The buff is on the player; read it there.

The Darkmoon toggle went because its 10% was a guess that was never verified, and because with
detection running it would double-count the Faire buff on anyone who left it ticked.

**Risk.** The description parse only trusts a percentage in text that mentions "experience",
which is English. Known spell IDs work in any locale; the parser does not. Seed the table as
IDs are confirmed.

**Backstop.** `QUEST_TURNED_IN` reports the XP actually granted. When it misses the projection
by more than 5%, the addon says so in chat, because a missing buff makes every later projection
wrong by the same amount until it is found.

## D12. Trust a positive War Mode reading anywhere, a negative one only where War Mode is live

**Decision.** `IsWarModeDesired` (the toggle) and `IsWarModeActive` (in effect where you are
standing) are treated as different questions. The projection uses desired, because it is a plan
for a turn-in that may happen elsewhere. Measurement caching is asymmetric: `total > base` is
cached as a positive from anywhere, but a negative is only cached when War Mode is *active*,
and never overwrites a positive.

**Why.** D7 measures the bonus from the client's own arithmetic, which is the right source, but
the reading is location-dependent. War Mode is not in effect inside an instance or a sanctuary,
and a delve is an instance. So the original "War Mode does not apply to these quests" may be an
artefact of having measured inside a delve rather than a fact about the quests, and caching that
negative account-wide would have made it permanent and invisible. A positive has no such
problem: the client would not add a bonus to a quest that cannot take one.

**Consequence.** When War Mode is on but not in effect, the UI says so in amber and warns that
readings taken there are unreliable, instead of asserting anything about the quests.

**Answered by measurement.** Whether handing in at Silvermoon costs the bonus is not documented
anywhere authoritative I could find, so the ledger settled it. Four turn-ins in Silvermoon City
on 2026-07-21, two with War Mode opted **in** and two opted **out**:

    L87 Collegiate Calamity  127,100 -> 165,230  x1.300   (War Mode on)
    L87 Parhelion Plaza      127,100 -> 165,230  x1.300   (War Mode on)
    L88 Shadow Enclave       128,450 -> 166,985  x1.300   (War Mode off)
    L88 The Darkway          128,450 -> 166,985  x1.300   (War Mode off)

x1.3000 every time, to four decimal places, and **identical with War Mode on and off**. That is
Warband Mentor 25% plus Knowledge of Timeways 5% and nothing else. Inside a sanctuary, War Mode
pays nothing. The UI now says "hand in outdoors or you forgo the bonus" rather than merely
flagging the reading as unreliable.

The remaining alternative, that War Mode never applies to these quests anywhere, was then
excluded by a turn-in outdoors in Voidstorm with War Mode active:

    L88 Sunkiller Sanctum    128,450 -> 186,252  x1.450   (Voidstorm, War Mode active)

x1.4500 is x1.30 plus exactly 15%. **War Mode works, sanctuaries suppress it.** Handing the
stack in at Silvermoon rather than stepping outside costs 15% of the lot.

**Third double count found in the same dump.** War Mode also exists as an aura, `Enlisted`
(269083, +15%), present only while War Mode is in effect. The aura scan was about to add it on
top of the explicit War Mode term and model x1.60 against a measured x1.45. It is now in
`XP_BUFF_IGNORE`. War Mode stays on the explicit path because that one is gated per quest and
can be toggled to plan a turn-in you have not made yet.

## D13. Measurement overrides the model

**Decision.** Every turn-in records its implied multiplier (`actual / base`) against a condition
signature: War Mode status, detected buff total, and whether you were resting. When a signature
has been measured, `ApplyMultiplier` uses the running mean of those measurements and ignores the
modelled sum entirely. The UI labels the number "measured (n)" or "modelled".

**Why.** The model has now been wrong three times in a row, each time for a different reason:
the War Mode flag lied (D7), Timeways was tiered and unread (D11), and then a turn-in with War
Mode **off**, no Timewalking buff and no detectable aura paid exactly **+25.0%** twice in a row
against a projection of x1.00. Three unexplained discrepancies is enough evidence that
enumerating buffs is not a reliable way to predict quest XP in this expansion.

The addon does not need to know *why* the multiplier is 1.25. It needs the projection to be
right. Measurement gives that without an explanation, and it keeps working when Blizzard adds a
source we have never heard of.

**Consequence.** The model is now a cold-start fallback for conditions never observed, not the
primary path. Change the conditions (turn War Mode on, gain a Timeways tier, leave the inn) and
the signature changes, the measurement no longer applies, and the addon falls back to the model
until that combination has been seen once.

**Resolved afterwards.** The +25% was **Warband Mentored Leveling**, +5% per level-90 character
on the account to a cap of 25%. It exists **both** as achievements 42328-42332 and as aura
spell 430191, and reading both added it twice: a `/dvt xp` dump showed +55% where the truth was
+30%. The aura wins when present, because it is the live value; the achievements are the
fallback for when auras are unreadable. Counting a bonus once is the whole job here, and it took
an itemised diagnostic to notice, which is why `/dvt xp` lists every source with its spell ID
rather than just a total.

That does not weaken the decision, it demonstrates it. The calibration had the projection right
while the model was wrong about the reason, which is the whole point: the number matters, the
explanation is optional. Measurement stays the primary path.

## D14. Discovery takes Midnight quests only, by quest ID

**Decision.** The Scanner only adds a `Delver's Call` quest whose ID is at or above the lowest
seed ID (93372). On load, anything already stored below that line is removed: the catalogue
entry, its `questXP` readings and every character's state for it.

**Why.** The War Within delves use the same title prefix, so D1's title match let in Fungal
Folly (83758), The Skittering Breach (83768) and Tak-Rethan Abyss (83771). They showed as rows
in the Midnight list (found 2026-09-27: 13 rows where there should be 10). They pay a flat
~1,300 XP that does not grow with level, and that pulled the measured growth (D8) down to
+0.78% per level against the +1.08% measured on Midnight quests alone.

Quest IDs only go up, so a quest Blizzard adds to Midnight later gets a higher ID and is still
discovered. The zone of the quest waypoint was rejected: the stored `mapID` values (2537, 424, 875)
put Midnight and War Within quests on the same maps, so they cannot tell the two apart.
