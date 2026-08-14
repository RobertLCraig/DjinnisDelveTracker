--[[
    Djinni's Delve Tracker - Scanner

    Reads quest state off the game, discovers delve quests we have not met before, and
    records every reward-XP value it sees so the Estimator has real data to work from.

    Read-only (DECISIONS D5). Every call in here is a getter.
]]

local ADDON_NAME, ns = ...
local DDT = ns.Addon
local L = ns.L

local Scanner = DDT:NewModule("Scanner", "AceEvent-3.0", "AceTimer-3.0")
ns.Scanner = Scanner

-- QUEST_LOG_UPDATE fires in bursts, several times for one accept. Coalesce.
local SCAN_DEBOUNCE = 0.4

--============================================================================
-- Reading the game
--============================================================================

-- DATA-MODEL: first match wins, and the order matters because a quest can be both
-- on-quest and ready to hand in.
function Scanner:StateFor(questID)
    if C_QuestLog.IsQuestFlaggedCompleted(questID) then return ns.STATE.TURNED_IN end
    if C_QuestLog.ReadyForTurnIn(questID) then return ns.STATE.READY end
    if C_QuestLog.IsOnQuest(questID) then return ns.STATE.IN_PROGRESS end
    return ns.STATE.NOT_STARTED
end

-- Reward XP as the client reports it: total (War Mode already included) and base.
--
-- GetQuestLogRewardXP only has data for quests in your log, which is the whole reason
-- the projection covers banked quests only (PRD constraints).
function Scanner:RewardXP(questID)
    if not C_QuestLog.IsOnQuest(questID) then return nil, nil end
    if HaveQuestRewardData and not HaveQuestRewardData(questID) then
        if C_QuestLog.RequestLoadQuestByID then C_QuestLog.RequestLoadQuestByID(questID) end
        return nil, nil
    end
    local total, base = GetQuestLogRewardXP(questID)
    base = base or total
    if not base or base <= 0 then return nil, nil end
    return total or base, base
end

-- Base (pre-War-Mode) reward XP. This is the one we store (DECISIONS D3).
function Scanner:BaseXP(questID)
    local _, base = self:RewardXP(questID)
    return base
end

-- Does the War Mode bonus actually land on this quest?
--
-- C_QuestLog.QuestCanHaveWarModeBonus was the obvious answer and it disagrees with the
-- client's own arithmetic for these quests, which is what made the first build claim
-- x1.45 while quietly projecting x1.30 (DECISIONS D7). So when War Mode is on we measure
-- rather than ask: the first return of GetQuestLogRewardXP already has the bonus baked
-- in, so total > base is proof it applies and total == base is proof it does not. The
-- answer is cached account-wide, because with War Mode off there is nothing to measure.
function Scanner:QuestTakesWarMode(questID)
    local remembered = ns.db and ns.db.global.warModeQuests
    local cached = remembered and remembered[questID]

    if C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired() then
        local total, base = self:RewardXP(questID)
        if total and base then
            local applies = total > base
            if remembered then
                -- Asymmetric on purpose. A positive is proof: the client would not add
                -- the bonus to a quest that cannot take it. A negative proves nothing
                -- unless War Mode is actually in effect where we are standing, because
                -- inside an instance or a sanctuary the client reports no bonus for
                -- every quest. Caching a negative read inside a delve is what would
                -- make the addon claim War Mode never applies (DECISIONS D12).
                local active = C_PvP.IsWarModeActive and C_PvP.IsWarModeActive()
                if applies then
                    remembered[questID] = true
                elseif active and cached ~= true then
                    remembered[questID] = false
                end
            end
            if applies then return true end
        end
    end

    if cached ~= nil then return cached end
    if C_QuestLog.QuestCanHaveWarModeBonus then
        return C_QuestLog.QuestCanHaveWarModeBonus(questID) and true or false
    end
    return false
end

--============================================================================
-- Discovery
--============================================================================

function Scanner:DiscoverFromLog()
    if not ns.Catalogue:Prefix() then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and ns.Catalogue:TitleMatches(info.title) then
            if ns.Catalogue:Remember(info.questID, info.title, false) then
                self:AnnounceDiscovery(info.title)
            end
        end
    end
end

-- The map is the only place a quest we have never accepted shows up, so this is what
-- lets a fresh alt learn about a delve by flying past it.
function Scanner:DiscoverFromMap()
    if not ns.Catalogue:Prefix() then return end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID or not C_QuestLog.GetQuestsOnMap then return end

    local quests = C_QuestLog.GetQuestsOnMap(mapID)
    if not quests then return end
    for _, q in ipairs(quests) do
        local questID = q.questID
        if questID then
            local title = C_QuestLog.GetTitleForQuestID(questID)
            if ns.Catalogue:TitleMatches(title) then
                if ns.Catalogue:Remember(questID, title, false) then
                    self:AnnounceDiscovery(title)
                end
            end
        end
    end
end

function Scanner:AnnounceDiscovery(title)
    DDT:Debug("discovered " .. tostring(title))
    if ns.db.profile.announce then
        DDT:Print(L["MSG_DISCOVERED"]:format(tostring(title)))
    end
end

--============================================================================
-- The scan
--============================================================================

function Scanner:RequestScan()
    if self.scanTimer then return end
    self.scanTimer = self:ScheduleTimer("Scan", SCAN_DEBOUNCE)
end

function Scanner:Scan()
    self.scanTimer = nil
    if not ns.db then return end

    ns.Catalogue:RequestMissingTitles()
    self:DiscoverFromLog()
    ns.Locations:HarvestFromQuests()

    local rec = ns.Roster:EnsureCurrent()
    if not rec then return end

    local level = rec.level
    -- The live value always beats the shipped seed for the level we are actually on.
    if rec.xpMax and rec.xpMax > 0 then
        ns.db.global.xpCurve[level] = rec.xpMax
    end

    local banked, bankedXP = 0, 0
    local newlyReady

    for _, questID in ipairs(ns.Catalogue:Ordered()) do
        local state = self:StateFor(questID)
        local previous = rec.quests[questID]
        rec.quests[questID] = state

        local xp = self:BaseXP(questID)
        if xp then
            local perQuest = ns.db.global.questXP[questID]
            if not perQuest then
                perQuest = {}
                ns.db.global.questXP[questID] = perQuest
            end
            perQuest[level] = xp
        end

        if state == ns.STATE.READY then
            banked = banked + 1
            bankedXP = bankedXP + (xp or ns.Estimator:QuestXP(questID, level) or 0)
            -- previous being nil means this is the first scan of the session, not a
            -- transition, so it must not fire the announcement.
            if previous and previous ~= state then
                newlyReady = ns.Catalogue:DisplayName(questID)
            end
        end
    end

    rec.banked   = banked
    rec.bankedXP = bankedXP

    if newlyReady and ns.db.profile.announce then
        DDT:Print(L["MSG_READY"]:format(newlyReady, banked))
    end

    ns.Refresh()
end

--============================================================================
-- Events
--============================================================================

function Scanner:OnEnable()
    self:RegisterEvent("QUEST_LOG_UPDATE", "RequestScan")
    self:RegisterEvent("QUEST_ACCEPTED", "RequestScan")
    self:RegisterEvent("QUEST_REMOVED", "RequestScan")
    self:RegisterEvent("PLAYER_XP_UPDATE", "RequestScan")
    self:RegisterEvent("QUEST_DATA_LOAD_RESULT", "RequestScan")
    self:RegisterEvent("QUEST_TURNED_IN")
    self:RegisterEvent("PLAYER_LEVEL_UP")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZoneChanged")
    -- XP buffs are read off the player's auras, so the displayed multiplier has to
    -- follow them. AceEvent has no unit-filtered registration, so the unit is checked
    -- here, and the refresh is heavily debounced: this fires constantly in combat.
    self:RegisterEvent("UNIT_AURA")
    -- Warband Mentor is an achievement, so its tier moves when an alt dings 90.
    self:RegisterEvent("ACHIEVEMENT_EARNED", "RequestBuffRefresh")
end

function Scanner:UNIT_AURA(_, unit)
    if unit ~= "player" then return end
    self:RequestBuffRefresh()
end

function Scanner:RequestBuffRefresh()
    if self.buffTimer then return end
    self.buffTimer = self:ScheduleTimer(function()
        Scanner.buffTimer = nil
        ns.Refresh()
    end, 1.0)
end

function Scanner:OnZoneChanged()
    self:DiscoverFromMap()
    ns.Locations:HarvestNearby()
    self:RequestScan()
end

-- The event hands us the XP that was actually granted, which is the only ground truth
-- we ever get for the projection. With debug on it prints the error, which is how
-- DECISIONS D4 gets validated or thrown out.
-- Record what a turn-in actually paid, and the conditions it happened under. This is the
-- only ground truth the addon ever gets, and it is what settles arguments the API cannot:
-- whether a buff applies, and whether handing in inside a city costs you the War Mode
-- bonus (DECISIONS D12). Compare two entries with different `active` or `zone` values.
local LEDGER_CAP = 50

function Scanner:RecordTurnIn(questID, base, actual)
    local ledger = ns.db and ns.db.global.turnIns
    if not ledger then return end

    local _, buffPct = ns.Estimator:DetectedXPBuffs()
    local implied = base > 0 and (actual / base) or 0
    local key = ns.Estimator:CalibrationKey()

    ledger[#ledger + 1] = {
        questID  = questID,
        level    = UnitLevel("player"),
        base     = base,
        actual   = actual,
        implied  = implied,
        key      = key,
        warMode  = ns.Estimator:WarModeStatus(),
        buffPct  = buffPct,
        zone     = GetZoneText(),
        resting  = IsResting() and true or false,
        at       = time(),
    }
    while #ledger > LEDGER_CAP do table.remove(ledger, 1) end

    -- Feed the measurement back into the projection. From here on, these conditions use
    -- what was actually paid rather than the sum of the buffs we could identify.
    ns.Estimator:RecordMeasurement(key, implied)
end

function Scanner:QUEST_TURNED_IN(_, questID, xpReward)
    if ns.Catalogue:Get(questID) and xpReward and xpReward > 0 then
        local rec = ns.Roster:Current()
        local base = rec and ns.Estimator:QuestXP(questID, rec.level)
        if base then
            self:RecordTurnIn(questID, base, xpReward)
            local predicted = ns.Estimator:ApplyMultiplier(base, self:QuestTakesWarMode(questID))
            local errPct = predicted > 0 and ((xpReward - predicted) / predicted * 100) or 0
            DDT:Debug(L["MSG_TURNIN_CHECK"]:format(ns.Comma(predicted), ns.Comma(xpReward), errPct))
            -- A projection that misses by more than a rounding error means a buff is
            -- missing from the multiplier. Worth saying out loud, not just in debug:
            -- every later projection is wrong by the same amount until it is fixed.
            if math.abs(errPct) > 5 and ns.db.profile.announce then
                DDT:Print(L["MSG_BUFF_DRIFT"]:format(ns.Comma(xpReward), errPct, ns.Comma(predicted)))
            end
        end
    end
    self:RequestScan()
end

function Scanner:PLAYER_LEVEL_UP(_, newLevel)
    -- UnitXPMax is still the old level's value inside this event; read it next frame.
    self:ScheduleTimer(function()
        local rec = ns.Roster:EnsureCurrent()
        if rec and rec.xpMax and rec.xpMax > 0 then
            ns.db.global.xpCurve[rec.level] = rec.xpMax
        end
        Scanner:RequestScan()
    end, 0.5)
end
