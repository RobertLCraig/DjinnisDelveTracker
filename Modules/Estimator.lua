--[[
    Djinni's Delve Tracker - Estimator

    Turns the banked stack into "you would land on level N, M% in".

    Two things make this more than a sum. Quest reward XP scales with character level, so
    a quest is worth more after you level than before, which means the order of a ten-quest
    turn-in changes the answer. And the buffs that multiply quest XP are partly invisible to
    the client. Both are handled explicitly here rather than fudged.
]]

local ADDON_NAME, ns = ...
local L = ns.L

local Estimator = {}
ns.Estimator = Estimator

local MAX_AURAS = 40

--============================================================================
-- The level curve
--============================================================================

function Estimator:MaxLevel()
    if GetMaxLevelForPlayerExpansion then
        local max = GetMaxLevelForPlayerExpansion()
        if max and max > 0 then return max end
    end
    return ns.MAX_LEVEL_FALLBACK
end

-- XP needed to get from `level` to `level + 1`. Observed values beat the shipped seed,
-- and past the end of both we extrapolate rather than return nil, so a future level cap
-- degrades to an approximation instead of a broken projection.
function Estimator:XPToLevel(level)
    if not level then return nil end

    local observed = ns.db and ns.db.global and ns.db.global.xpCurve[level]
    if observed and observed > 0 then return observed end

    if ns.XP_SEED[level] then return ns.XP_SEED[level] end

    local best, bestLevel
    for l, v in pairs(ns.XP_SEED) do
        if not bestLevel or math.abs(l - level) < math.abs(bestLevel - level) then
            best, bestLevel = v, l
        end
    end
    if not best then return nil end
    return math.floor(best * (ns.XP_GROWTH_PER_LEVEL ^ (level - bestLevel)))
end

--============================================================================
-- Quest XP
--============================================================================

-- Per-level growth in quest reward XP, measured rather than assumed: the geometric mean
-- of the ratios between observations of the same quest at different levels. Returns nil
-- until some quest has been seen at two levels, which is why the addon keeps recording
-- every value it reads (DECISIONS D8).
function Estimator:ObservedGrowth()
    local sum, count = 0, 0
    for _, perQuest in pairs(ns.db and ns.db.global.questXP or {}) do
        local levels = {}
        for level in pairs(perQuest) do levels[#levels + 1] = level end
        table.sort(levels)
        for i = 2, #levels do
            local from, to = levels[i - 1], levels[i]
            if perQuest[from] > 0 then
                sum = sum + (perQuest[to] / perQuest[from]) ^ (1 / (to - from))
                count = count + 1
            end
        end
    end
    if count == 0 then return nil end
    return sum / count
end

-- Scale a reward value between levels.
--
-- Measured growth wins when it exists. Otherwise this falls back to the level curve as
-- the shape, which is the assumption in DECISIONS D4 and is circular for the wait-list:
-- scale quest XP by the same curve as the level bar and the stack is worth an identical
-- number of levels at every turn-in level, by construction. Second return marks the
-- value as modelled either way, since both are extrapolation.
function Estimator:ScaleXP(xp, fromLevel, toLevel)
    if not xp then return nil, false end
    if fromLevel == toLevel then return xp, false end

    local growth = self:ObservedGrowth()
    if growth and growth > 0 then
        return xp * (growth ^ (toLevel - fromLevel)), true
    end

    local from, to = self:XPToLevel(fromLevel), self:XPToLevel(toLevel)
    if not from or not to or from <= 0 then return xp, true end
    return xp * (to / from), true
end

-- Best base XP we can offer for a quest at a level: an exact observation if we have one,
-- otherwise the nearest observation scaled across.
function Estimator:QuestXP(questID, level)
    local perQuest = ns.db and ns.db.global and ns.db.global.questXP[questID]
    if not perQuest then return nil, false end
    if perQuest[level] then return perQuest[level], false end

    local nearest
    for observedLevel in pairs(perQuest) do
        if not nearest or math.abs(observedLevel - level) < math.abs(nearest - level) then
            nearest = observedLevel
        end
    end
    if not nearest then return nil, false end
    return self:ScaleXP(perQuest[nearest], nearest, level)
end

--============================================================================
-- Buff multipliers
--============================================================================

function Estimator:WarModeActive()
    local mode = ns.db.profile.buffs.warMode
    if mode == "on" then return true end
    if mode == "off" then return false end
    return (C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired()) or false
end

function Estimator:WarModeBonus()
    local bonus = C_PvP and C_PvP.GetWarModeRewardBonus and C_PvP.GetWarModeRewardBonus()
    return bonus or 0
end

-- "off" | "inactive" | "active".
--
-- Desired and active are different questions. Desired is the toggle; active is whether
-- War Mode is in effect where you are standing, which it is not in a sanctuary or inside
-- an instance. The projection uses desired, because it is a plan for a turn-in that may
-- happen somewhere else, but anything measured while inactive is untrustworthy and the
-- UI has to say so (DECISIONS D12).
function Estimator:WarModeStatus()
    if not self:WarModeActive() then return "off" end
    local active = C_PvP and C_PvP.IsWarModeActive and C_PvP.IsWarModeActive()
    return active and "active" or "inactive"
end

--============================================================================
-- Experience buffs on the player
--
-- Timeways is tiered and there is no API that says "quest XP is boosted by N%", so the
-- percentage is read out of the buff's own description text. Exact values for known
-- spell IDs win; anything else is parsed once and cached (DECISIONS D11).
--============================================================================

local parsedBuffs = {}   -- [spellID] = percent or false, session cache

local function ParseXPPercent(spellID)
    if parsedBuffs[spellID] ~= nil then return parsedBuffs[spellID] or nil end

    local percent
    if C_Spell and C_Spell.GetSpellDescription then
        local description = C_Spell.GetSpellDescription(spellID)
        if description and description ~= "" then
            -- Only trust a percentage that sits in a description talking about
            -- experience, or every haste buff in the game becomes an XP bonus.
            if description:lower():find("experience", 1, true) then
                percent = tonumber(description:match("(%d+)%s*%%"))
            end
        end
    end

    parsedBuffs[spellID] = percent or false
    return percent
end

-- Warband Mentored Leveling, from the achievement series rather than an aura. Returns the
-- percentage and the achievement's own name, or nil when none of the tiers are done.
function Estimator:WarbandMentorBonus()
    if not GetAchievementInfo then return nil end

    -- Cumulative tiers: the highest completed one is the whole bonus, not a summand.
    for index = #ns.WARBAND_MENTOR, 1, -1 do
        local tier = ns.WARBAND_MENTOR[index]
        local _, name, _, completed = GetAchievementInfo(tier.id)
        if completed then return tier.pct, name end
    end
    return nil
end

-- Everything that multiplies quest XP: a list of { name, pct }, the summed percentage,
-- and whether auras were readable. Not all of it comes from auras, so the aura-readable
-- flag must not short-circuit the rest.
function Estimator:DetectedXPBuffs()
    local found, total = {}, 0

    -- Auras first, so a Warband Mentor aura can suppress the achievement fallback. Doing
    -- it the other way round is what made the total read +55% instead of +30%: the same
    -- bonus arrived once as achievement 42332 and once as spell 430191.
    local sawMentorAura = false

    if (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())
        or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        local mentorPct, mentorName = self:WarbandMentorBonus()
        if mentorPct then
            found[#found + 1] = { name = mentorName or L["BUFF_MENTOR"], pct = mentorPct }
            total = total + mentorPct
        end
        return found, total, false
    end

    local learned = ns.db and ns.db.global.xpBuffs
    for index = 1, MAX_AURAS do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if not aura then break end

        local spellID = aura.spellId
        if spellID and not ns.XP_BUFF_IGNORE[spellID] then
            if ns.WARBAND_MENTOR_AURAS[spellID] then sawMentorAura = true end

            local percent = ns.XP_BUFFS[spellID] or (learned and learned[spellID]) or ParseXPPercent(spellID)
            if percent and percent > 0 then
                if learned then learned[spellID] = percent end
                found[#found + 1] = { name = aura.name, pct = percent, spellID = spellID }
                total = total + percent
            end
        end
    end

    -- Only when the aura is absent, so the bonus is counted exactly once.
    if not sawMentorAura then
        local mentorPct, mentorName = self:WarbandMentorBonus()
        if mentorPct then
            table.insert(found, 1, { name = mentorName or L["BUFF_MENTOR"], pct = mentorPct })
            total = total + mentorPct
        end
    end

    return found, total, true
end

-- Returns the multiplier for a quest that takes the War Mode bonus, the multiplier for
-- one that does not, and a list of {label, pct} describing where it came from.
function Estimator:Multipliers()
    local buffs = ns.db.profile.buffs
    local shared, parts = 1, {}

    local detected, detectedTotal = self:DetectedXPBuffs()
    for _, buff in ipairs(detected) do
        parts[#parts + 1] = { label = buff.name, pct = buff.pct }
    end
    shared = shared + detectedTotal / 100

    local custom = tonumber(buffs.custom) or 0
    if custom ~= 0 then
        shared = shared + custom / 100
        parts[#parts + 1] = { label = L["BUFF_CUSTOM"], pct = custom }
    end

    local warMode = shared
    if self:WarModeActive() then
        local bonus = self:WarModeBonus()
        if bonus > 0 then
            warMode = shared + bonus / 100
            parts[#parts + 1] = { label = L["BUFF_WARMODE"], pct = bonus }
        end
    end

    return warMode, shared, parts
end

--============================================================================
-- Calibration
--
-- The model adds up the buffs it can see. Reality has repeatedly disagreed with it, and
-- reality is what pays out. So every turn-in records what it actually paid, keyed by the
-- conditions it happened under, and a measurement for the current conditions overrides
-- the model outright (DECISIONS D13).
--
-- The key is the condition signature: War Mode status plus the detected buff total. Two
-- turn-ins under the same signature are the same experiment.
--============================================================================

-- Resting was in this key while it was a candidate explanation for an unaccounted +25%.
-- That +25% turned out to be Warband Mentor, which is account-level and constant, so
-- splitting on resting only fragmented the samples: walking out of an inn threw away a
-- perfectly good measurement and dropped the projection back to the model. It stays in
-- the ledger for analysis, out of the key.
function Estimator:CalibrationKey()
    local _, buffTotal = self:DetectedXPBuffs()
    return ("%s:%d"):format(self:WarModeStatus(), math.floor((buffTotal or 0) + 0.5))
end

-- The measured multiplier for the conditions you are in right now, and how many turn-ins
-- back it. Nil when this combination has never been observed.
function Estimator:MeasuredMultiplier()
    local calibration = ns.db and ns.db.global.calibration
    local entry = calibration and calibration[self:CalibrationKey()]
    if entry and entry.n and entry.n > 0 then return entry.mean, entry.n end
    return nil
end

function Estimator:RecordMeasurement(key, implied)
    local calibration = ns.db and ns.db.global.calibration
    if not calibration or not implied or implied <= 0 then return end

    local entry = calibration[key]
    if not entry then
        entry = { n = 0, mean = 0 }
        calibration[key] = entry
    end
    -- Running mean, so a single odd turn-in cannot swing the projection far.
    entry.n = entry.n + 1
    entry.mean = entry.mean + (implied - entry.mean) / entry.n
end

function Estimator:ApplyMultiplier(base, takesWarMode)
    local measured = self:MeasuredMultiplier()
    if measured then return math.floor((base or 0) * measured) end

    local warMode, shared = self:Multipliers()
    return math.floor((base or 0) * (takesWarMode and warMode or shared))
end

--============================================================================
-- Building the stack
--============================================================================

-- One entry per quest you could hand in right now.
--   xp       base reward XP, pre-multiplier
--   atLevel  the character level that xp was read at
--   warMode  whether the War Mode bonus applies to this quest
function Estimator:BankedEntries()
    local rec = ns.Roster:Current()
    if not rec then return {}, 0 end

    local level = rec.level
    local entries, unknown = {}, 0

    for _, questID in ipairs(ns.Catalogue:Ordered()) do
        if rec.quests[questID] == ns.STATE.READY then
            local xp = ns.Scanner:BaseXP(questID) or self:QuestXP(questID, level)
            if xp then
                entries[#entries + 1] = {
                    id      = questID,
                    xp      = xp,
                    atLevel = level,
                    warMode = ns.Scanner:QuestTakesWarMode(questID),
                }
            else
                unknown = unknown + 1
            end
        end
    end

    if ns.db.profile.includeAllQuests then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            local questID = info and not info.isHeader and info.questID
            if questID and not ns.Catalogue:Get(questID) and C_QuestLog.ReadyForTurnIn(questID) then
                local xp = ns.Scanner:BaseXP(questID)
                if xp then
                    entries[#entries + 1] = {
                        id      = questID,
                        xp      = xp,
                        atLevel = level,
                        warMode = ns.Scanner:QuestTakesWarMode(questID),
                        other   = true,
                    }
                end
            end
        end
    end

    return entries, unknown
end

--============================================================================
-- The simulation
--============================================================================

-- Hand the entries in one at a time, levelling up as we go and re-scaling each
-- remaining quest to the level we have reached. That re-scale is why this is a loop
-- and not a sum: crossing a level boundary partway through the stack makes everything
-- after it worth more.
function Estimator:Simulate(entries, startLevel, startXP)
    local maxLevel = self:MaxLevel()
    local level    = startLevel
    local xp       = startXP or 0
    local total, baseTotal, estimated, capped = 0, 0, false, false
    local warModeCount, wasted = 0, 0

    for _, entry in ipairs(entries) do
        local base, modelled = entry.xp, false
        if entry.atLevel ~= level then
            base, modelled = self:ScaleXP(entry.xp, entry.atLevel, level)
        end
        estimated = estimated or modelled

        local gain = self:ApplyMultiplier(base, entry.warMode)
        total = total + gain
        baseTotal = baseTotal + base
        if entry.warMode then warModeCount = warModeCount + 1 end

        if level >= maxLevel then
            -- Still granted, still worthless. Counted separately so the UI can say how
            -- much of the stack a late turn-in throws away.
            capped = true
            wasted = wasted + gain
        else
            xp = xp + gain
            local need = self:XPToLevel(level)
            while need and level < maxLevel and xp >= need do
                xp = xp - need
                level = level + 1
                need = self:XPToLevel(level)
            end
            if level >= maxLevel then
                capped = true
                wasted = wasted + xp
                xp = 0
            end
        end
    end

    local xpMax = self:XPToLevel(level) or 1
    return {
        level        = level,
        xp           = math.floor(xp),
        xpMax        = xpMax,
        pct          = math.min(100, (xp / xpMax) * 100),
        totalXP      = total,
        levelsGained = level - startLevel,
        capped       = capped,
        wasted       = wasted,
        estimated    = estimated,
        -- The multiplier that was actually applied, derived from the run rather than
        -- from the settings. The two disagree whenever a quest refuses a buff, and the
        -- UI must show this one (DECISIONS D7).
        effective    = baseTotal > 0 and (total / baseTotal) or 1,
        warModeCount = warModeCount,
        questCount   = #entries,
        -- Levels the stack is worth, including the fraction, for comparing turn-in levels.
        levelsWorth  = (level - startLevel) + (xpMax > 0 and (xp / xpMax) or 0),
    }
end

-- What the same stack would be worth if you left it alone and handed in at `level`
-- instead. Used for the "wait until 88" comparison; always modelled, by definition.
function Estimator:ValueAtLevel(entries, level)
    local shifted = {}
    for i, entry in ipairs(entries) do
        shifted[i] = {
            id = entry.id, xp = entry.xp, atLevel = entry.atLevel, warMode = entry.warMode,
        }
    end
    return self:Simulate(shifted, level, 0)
end

--============================================================================
-- What the UI asks for
--============================================================================

function Estimator:Summary()
    local rec = ns.Roster:Current()
    if not rec then return nil end

    local entries, unknown = self:BankedEntries()
    local summary = {
        banked  = rec.banked or 0,
        total   = ns.Catalogue:Count(),
        unknown = unknown,
        level   = rec.level,
        entries = entries,
    }

    if #entries > 0 then
        summary.projection = self:Simulate(entries, rec.level, rec.xp or 0)
    end

    return summary
end

-- Has any single quest been seen at two different character levels? Until one has, the
-- scaling in DECISIONS D4 is a model with nothing behind it, and the wait-list is
-- circular: scaling quest XP by the level curve makes "levels worth" constant by
-- construction, so every row comes out identical. The UI says so rather than printing
-- four numbers that look like a comparison and are not.
function Estimator:HasCrossLevelData()
    for _, perQuest in pairs(ns.db and ns.db.global.questXP or {}) do
        local count = 0
        for _ in pairs(perQuest) do
            count = count + 1
            if count > 1 then return true end
        end
    end
    return false
end

-- Rows for "if you wait": this level and the next three, stopping at the cap. `delta` is
-- levels gained versus handing in at `fromLevel`, which is the number that actually
-- answers "is waiting worth it".
function Estimator:WaitRows(entries, fromLevel)
    local rows, maxLevel = {}, self:MaxLevel()
    if #entries == 0 then return rows, false end

    local baseline
    for level = fromLevel, math.min(fromLevel + 3, maxLevel - 1) do
        local result = self:ValueAtLevel(entries, level)
        baseline = baseline or result.levelsWorth
        rows[#rows + 1] = {
            level   = level,
            totalXP = result.totalXP,
            levels  = result.levelsWorth,
            delta   = result.levelsWorth - baseline,
            capped  = result.capped,
            wasted  = result.wasted,
        }
    end

    local flat = true
    for _, row in ipairs(rows) do
        if math.abs(row.delta) >= 0.01 then flat = false break end
    end
    return rows, flat
end
