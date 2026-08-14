--[[
    Djinni's Delve Tracker - live in-delve state

    What is happening inside the delve you are standing in: objectives and their progress,
    the Sanctified Banner, the treasure reward, and Brann's rank and XP.

    Read from the ScenarioHeaderDelves UI widget rather than a hardcoded list of spells,
    so a season that changes the objectives does not need a code change. Per-objective
    progress is not in the widget tooltip (it comes through empty); it lives in the
    dynamic text of the spell description, as "Some label: 3 / 4".

    This duplicates the Delve module in Djinni's Data Texts on purpose (DECISIONS D10).
    Fixes found here are worth carrying back there and vice versa.
]]

local ADDON_NAME, ns = ...
local DDT = ns.Addon
local L = ns.L

local DelveState = DDT:NewModule("DelveState", "AceEvent-3.0", "AceTimer-3.0")
ns.DelveState = DelveState

--============================================================================
-- State
--============================================================================

local inDelve      = false
local headerText   = nil     -- "Collegiate Calamity"
local tierText     = nil     -- "Tier 8"
local objectives   = {}      -- { name, earned, glow, progCur, progMax, progStr, text }
local criteria     = {}      -- scenario criteria, used when the widget has no spells
local rewardState  = nil
local rewardTip    = nil
local hasBountiful = false
local hasBanner    = false   -- latched for the run once seen; the buffs expire early
local companion    = nil
local delveMapID   = nil
local cachedWidget = nil

local xpTrack = {
    lastLevel = nil, lastCurrent = nil, lastMax = nil,
    sessionGained = 0, delveGained = 0, wasInDelve = false,
}

local mapPins = {}

--============================================================================
-- Helpers
--============================================================================

local function StripCodes(str)
    if not str then return "" end
    str = str:gsub("|c%x%x%x%x%x%x%x%x", "")
    str = str:gsub("|r", "")
    str = str:gsub("|H.-|h", "")
    str = str:gsub("|h", "")
    str = str:gsub("|T.-|t", "")
    return str
end

local function SpellLabel(spellID, tooltip)
    if spellID and spellID > 0 and C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if name and name ~= "" then return name end
    end
    if tooltip and tooltip ~= "" then
        local first = StripCodes(tooltip):match("^([^\n]+)")
        if first then return first end
    end
    return spellID and ("Spell " .. spellID) or "?"
end

-- Widget header names and quest delve names disagree on the leading article
-- ("The Shadow Enclave" vs "Shadow Enclave"), so both sides get flattened.
function DelveState:NameKey(text)
    if not text then return nil end
    text = text:lower():gsub("^the%s+", ""):gsub("[^%w]", "")
    return text ~= "" and text or nil
end

--============================================================================
-- Widget scanning
--============================================================================

-- Cheap authoritative gate. The widget is still the source of truth for what is *in* the
-- delve; this only answers whether we are in one at all.
local function InDelveInstance()
    if not (C_DelvesUI and C_DelvesUI.HasActiveDelve) then return false end
    local ok, active = pcall(C_DelvesUI.HasActiveDelve)
    return ok and active or false
end

local function FindDelveWidget()
    if cachedWidget then
        local info = C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo(cachedWidget)
        if info and info.shownState ~= Enum.WidgetShownState.Hidden then return info end
        cachedWidget = nil
    end

    -- The active scenario step names its own widget set, which is more reliable than the
    -- standard accessors and, unlike them, survives a /reload inside a delve.
    local setIDs = {}
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
        local step = C_ScenarioInfo.GetScenarioStepInfo()
        if step and step.widgetSetID then setIDs[#setIDs + 1] = step.widgetSetID end
    end
    for _, getter in ipairs({
        C_UIWidgetManager.GetTopCenterWidgetSetID,
        C_UIWidgetManager.GetObjectiveTrackerWidgetSetID,
        C_UIWidgetManager.GetBelowMinimapWidgetSetID,
    }) do
        if getter then setIDs[#setIDs + 1] = getter() end
    end

    for _, setID in ipairs(setIDs) do
        local widgets = setID and C_UIWidgetManager.GetAllWidgetsBySetID(setID)
        for _, widget in ipairs(widgets or {}) do
            if widget.widgetType == Enum.UIWidgetVisualizationType.ScenarioHeaderDelves then
                local info = C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo(widget.widgetID)
                if info and info.shownState ~= Enum.WidgetShownState.Hidden then
                    cachedWidget = widget.widgetID
                    return info
                end
            end
        end
    end
    return nil
end

-- Pull "Enemy groups remaining: 0 / 4" out of a spell description. The last match wins,
-- because the description can carry both a static and a live copy of the line.
local function ParseProgress(spellID)
    if not (C_Spell and C_Spell.GetSpellDescription and spellID) then return nil end
    local desc = C_Spell.GetSpellDescription(spellID)
    if not desc or desc == "" then return nil end

    local label, current, total
    for text, a, b in desc:gmatch("([^\n:]+):%s*(%d+)%s*/%s*(%d+)") do
        label, current, total = text:gsub("^%s+", ""):gsub("%s+$", ""), tonumber(a), tonumber(b)
    end
    if not (current and total) then return nil end

    -- "remaining" counts down; flip it so every bar reads the same way.
    if label and label:lower():find("remaining") then current = total - current end
    return label, current, total
end

--============================================================================
-- Scenario criteria (fallback when the widget carries no spells)
--============================================================================

local function ReadCriteria()
    local out = {}
    if not (C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo and C_ScenarioInfo.GetCriteriaInfo) then
        return out
    end
    local step = C_ScenarioInfo.GetScenarioStepInfo()
    if not step or not step.numCriteria or step.numCriteria == 0 then return out end

    for i = 1, step.numCriteria do
        local crit = C_ScenarioInfo.GetCriteriaInfo(i)
        if type(crit) == "table" and crit.description and crit.description ~= "" then
            out[#out + 1] = {
                description    = crit.description,
                completed      = crit.completed and true or false,
                quantity       = crit.quantity or 0,
                totalQuantity  = crit.totalQuantity or 0,
                quantityString = crit.quantityString or "",
            }
        end
    end
    return out
end

--============================================================================
-- Companion (Brann)
--
-- Companion progression is modelled as a friendship faction, so the rank and XP come
-- from C_GossipInfo rather than anything delve-specific.
--============================================================================

local function ResolveCompanionFaction()
    if not (C_DelvesUI and C_DelvesUI.GetFactionForCompanion) then return nil end

    -- GetPlayerCompanionID only returns anything once the companion UI has been opened
    -- this session, so all three paths are needed.
    if GetPlayerCompanionID then
        local ok, id = pcall(GetPlayerCompanionID)
        if ok and id then
            local ok2, factionID = pcall(C_DelvesUI.GetFactionForCompanion, id)
            if ok2 and factionID and factionID > 0 then return factionID end
        end
    end

    local ok, factionID = pcall(C_DelvesUI.GetFactionForCompanion, nil)
    if ok and factionID and factionID > 0 then return factionID end

    if C_DelvesUI.GetCompanionInfoForActivePlayer then
        local ok2, infoID = pcall(C_DelvesUI.GetCompanionInfoForActivePlayer)
        if ok2 and infoID then
            local ok3, factionID2 = pcall(C_DelvesUI.GetFactionForCompanion, infoID)
            if ok3 and factionID2 and factionID2 > 0 then return factionID2 end
        end
    end
    return nil
end

local function UpdateCompanion()
    companion = nil

    local factionID = ResolveCompanionFaction()
    if not factionID then return end

    local ranks = C_GossipInfo.GetFriendshipReputationRanks(factionID)
    local rep   = C_GossipInfo.GetFriendshipReputation(factionID)
    if type(rep) ~= "table" then return end

    local current, max, isMax
    if rep.nextThreshold then
        current = (rep.standing or 0) - (rep.reactionThreshold or 0)
        max     = (rep.nextThreshold or 0) - (rep.reactionThreshold or 0)
        isMax   = false
    else
        current, max, isMax = 1, 1, true
    end

    local name = rep.name or ""
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(factionID)
        if type(data) == "table" and data.name then name = data.name end
    end

    local level = ranks and ranks.currentLevel or 0

    if inDelve and not xpTrack.wasInDelve then xpTrack.delveGained = 0 end
    xpTrack.wasInDelve = inDelve

    -- Rank thresholds for ranks we are not on are not exposed, so a multi-rank jump in
    -- one tick undercounts. UPDATE_FACTION fires per gain, so that is rare.
    if not isMax and xpTrack.lastLevel and xpTrack.lastCurrent and xpTrack.lastMax then
        local delta = 0
        if level == xpTrack.lastLevel then
            delta = current - xpTrack.lastCurrent
        elseif level > xpTrack.lastLevel then
            delta = (xpTrack.lastMax - xpTrack.lastCurrent) + current
        end
        if delta > 0 then
            xpTrack.sessionGained = xpTrack.sessionGained + delta
            if inDelve then xpTrack.delveGained = xpTrack.delveGained + delta end
        end
    end
    xpTrack.lastLevel, xpTrack.lastCurrent, xpTrack.lastMax = level, current, max

    companion = {
        name       = name,
        level      = level,
        maxRank    = ranks and ranks.maxLevel or 0,
        currentXP  = current,
        maxXP      = math.max(1, max),
        rankName   = rep.reaction or "",
        isMaxLevel = isMax,
        delveGained   = xpTrack.delveGained,
        sessionGained = xpTrack.sessionGained,
    }
end

--============================================================================
-- The scan
--============================================================================

function DelveState:Update()
    local wasInDelve = inDelve

    inDelve, headerText, tierText = false, nil, nil
    objectives, criteria = {}, {}
    rewardState, rewardTip, hasBountiful = nil, nil, false

    local info = FindDelveWidget()

    if not info then
        -- Straight after a /reload inside a delve the widget has not arrived yet, but
        -- the scenario criteria usually have, so they stand in for it.
        --
        -- Criteria alone are NOT a presence check: a dungeon has them too, which is how
        -- a Timewalking run showed up here as a delve with "Kin-Tara defeated" for an
        -- objective. C_DelvesUI.HasActiveDelve is the gate.
        if InDelveInstance() then
            criteria = ReadCriteria()
            if #criteria > 0 then inDelve = true end
        end
        if not inDelve and wasInDelve then
            hasBanner, delveMapID = false, nil
            self:RefreshMapPins()
        end
        UpdateCompanion()
        ns.Refresh()
        return
    end

    inDelve    = true
    headerText = info.headerText
    tierText   = info.tierText

    if not wasInDelve then
        hasBanner = false
        delveMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        self:WarnIfQuestMissing()
    end

    for _, spell in ipairs(type(info.spells) == "table" and info.spells or {}) do
        if spell.spellID == ns.BOUNTIFUL_SPELL_ID then
            hasBountiful = true
        else
            local label, current, total = ParseProgress(spell.spellID)
            objectives[#objectives + 1] = {
                spellID  = spell.spellID,
                name     = SpellLabel(spell.spellID, StripCodes(spell.tooltip or "")),
                text     = spell.text,
                earned   = spell.showAsEarned and true or false,
                glow     = (spell.showGlowState == Enum.WidgetShowGlowState.ShowGlow),
                progLabel = label,
                progCur  = current,
                progMax  = total,
                progStr  = current and (current .. "/" .. total) or nil,
            }
        end
    end

    -- Banner via the click buff. Latched, because the buffs expire well before the run
    -- ends and an indicator that flips back to "available" is worse than none.
    local aurasSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
    if not aurasSecret and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, spellID in ipairs(ns.BANNER_BUFF_SPELL_IDS) do
            if C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
                hasBanner = true
                break
            end
        end
    end

    if type(info.rewardInfo) == "table" then
        rewardState = info.rewardInfo.shownState
        rewardTip = StripCodes((rewardState == Enum.UIWidgetRewardShownState.ShownEarned)
            and info.rewardInfo.earnedTooltip or info.rewardInfo.unearnedTooltip)
    end

    criteria = ReadCriteria()
    UpdateCompanion()
    self:RefreshMapPins()
    ns.Refresh()
end

--============================================================================
-- Public snapshot
--============================================================================

function DelveState:IsActive() return inDelve end

-- Fired once on entering a delve. A run with the quest not accepted earns nothing, and by
-- the time you notice you have already spent the run, so it is worth a chat line as well
-- as the panel warning.
function DelveState:WarnIfQuestMissing()
    if not ns.db or not ns.db.profile.announce then return end

    local questID = self:MatchedQuestID()
    if not questID then return end

    local rec = ns.Roster:Current()
    if rec and rec.quests[questID] == ns.STATE.NOT_STARTED then
        DDT:Print(L["MSG_DELVE_NO_QUEST"]:format(ns.Catalogue:DisplayName(questID)))
    end
end

-- The catalogue quest for the delve we are standing in, so the window can tie the live
-- run to the row it will complete.
function DelveState:MatchedQuestID()
    if not headerText then return nil end
    local key = self:NameKey(headerText)
    for _, questID in ipairs(ns.Catalogue:Ordered()) do
        if self:NameKey(ns.Catalogue:DisplayName(questID)) == key then return questID end
    end
    return nil
end

function DelveState:BannerLocations()
    if not headerText then return nil end
    -- The banner table is keyed by widget header text, which does not always match the
    -- quest's delve name, so match on the flattened key rather than the raw string.
    local key = self:NameKey(headerText)
    for name, locations in pairs(ns.BANNER_LOCATIONS) do
        if self:NameKey(name) == key then return locations end
    end
    return nil
end

function DelveState:Get()
    local done, total = 0, 0
    for _, objective in ipairs(objectives) do
        total = total + 1
        if objective.earned or (objective.progCur and objective.progCur >= objective.progMax) then
            done = done + 1
        end
    end
    if hasBountiful then
        total = total + 1
        if hasBanner then done = done + 1 end
    end
    if total == 0 and #criteria > 0 then
        total = #criteria
        done = 0
        for _, crit in ipairs(criteria) do
            if crit.completed then done = done + 1 end
        end
    end

    return {
        active       = inDelve,
        name         = headerText,
        tier         = tierText,
        objectives   = objectives,
        criteria     = criteria,
        hasBountiful = hasBountiful,
        hasBanner    = hasBanner,
        rewardState  = rewardState,
        rewardTip    = rewardTip,
        companion    = companion,
        done         = done,
        total        = total,
        questID      = self:MatchedQuestID(),
    }
end

--============================================================================
-- Banner waypoints and map pins
--============================================================================

-- Delve maps usually refuse user waypoints, so fall back to printing the coordinates
-- and opening the map, where our pins already mark the spawns.
function DelveState:WaypointBanner(x, y)
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return end

    if C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    else
        DDT:Print(L["MSG_BANNER_WAY"]:format(x * 100, y * 100))
        if WorldMapFrame and not WorldMapFrame:IsShown() then ToggleWorldMap() end
    end
end

local function CreateMapPin()
    local canvas = WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
    if not canvas then return nil end

    local pin = CreateFrame("Frame", nil, canvas)
    pin:SetFrameStrata("HIGH")
    pin.icon = pin:CreateTexture(nil, "OVERLAY")
    pin.icon:SetAllPoints(pin)
    local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ns.BANNER_SPELL_ID)
    pin.icon:SetTexture(texture or 134400)
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["BANNER_PIN"], 1, 0.82, 0)
        if self.coordText then GameTooltip:AddLine(self.coordText, 0.7, 0.85, 1) end
        if self.note then GameTooltip:AddLine(self.note, 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", GameTooltip_Hide)
    return pin
end

function DelveState:RefreshMapPins()
    self:InstallMapHooks()
    for _, pin in ipairs(mapPins) do pin:Hide() end

    if not ns.db or not ns.db.profile.bannerPins then return end
    if not inDelve or hasBanner then return end
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end

    local canvas = WorldMapFrame.ScrollContainer.Child
    if not canvas then return end

    -- Only while looking at the delve's own map, or the pins land on arbitrary
    -- coordinates of whatever zone you happen to be browsing.
    local viewed = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not viewed or (delveMapID and viewed ~= delveMapID) then return end

    local locations = self:BannerLocations()
    if not locations then return end

    local width, height = canvas:GetSize()
    if not width or width == 0 then return end

    local scale = ns.db.profile.bannerPinScale or 2.5
    for i, location in ipairs(locations) do
        local pin = mapPins[i]
        if not pin then
            pin = CreateMapPin()
            if not pin then return end
            mapPins[i] = pin
        end
        pin:SetSize(20 * scale, 20 * scale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", location.x * width, -location.y * height)
        pin.coordText = ("/way %.2f, %.2f"):format(location.x * 100, location.y * 100)
        pin.note = location.note
        pin:Show()
    end
end

--============================================================================
-- Events
--============================================================================

function DelveState:OnEnable()
    self:RegisterEvent("UPDATE_UI_WIDGET")
    self:RegisterEvent("ACTIVE_DELVE_DATA_UPDATE", "Update")
    self:RegisterEvent("DELVE_ASSIST_ACTION", "Update")
    self:RegisterEvent("SCENARIO_UPDATE", "Update")
    self:RegisterEvent("SCENARIO_CRITERIA_UPDATE", "Update")
    self:RegisterEvent("SCENARIO_BONUS_OBJECTIVE_COMPLETE", "Update")
    self:RegisterEvent("SCENARIO_BONUS_VISIBILITY_UPDATE", "Update")
    self:RegisterEvent("UPDATE_FACTION", "Update")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "Update")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    self:RegisterEvent("UNIT_AURA")

    self:InstallHooks()
end

-- AceEvent has no unit-filtered registration, so the filter lives here. Only the banner
-- buff matters, so this does nothing once the banner is in hand.
function DelveState:UNIT_AURA(_, unit)
    if unit ~= "player" then return end
    if inDelve and not hasBanner then self:Update() end
end

-- Only our own widget type; every nameplate and tracker tick fires this event.
function DelveState:UPDATE_UI_WIDGET(_, widgetInfo)
    if widgetInfo and widgetInfo.widgetType == Enum.UIWidgetVisualizationType.ScenarioHeaderDelves then
        cachedWidget = widgetInfo.widgetID
        self:Update()
    end
end

-- Widget and scenario data are not pushed to the client yet when this fires inside a
-- delve, so retry a few times rather than showing an empty panel.
function DelveState:OnEnteringWorld()
    self:Update()
    for _, delay in ipairs({ 0.5, 1.5, 4.0 }) do
        self:ScheduleTimer("Update", delay)
    end
end

-- WorldMapFrame can still be unloaded when the addon enables, so this is retried from
-- RefreshMapPins rather than attempted once and silently given up on.
local mapHooked = false

function DelveState:InstallMapHooks()
    if mapHooked or not WorldMapFrame then return end
    mapHooked = true
    WorldMapFrame:HookScript("OnShow", function() DelveState:RefreshMapPins() end)
    if WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function() DelveState:RefreshMapPins() end)
    end
end

function DelveState:InstallHooks()
    self:InstallMapHooks()

    -- Tier 11+ delves grant no aura when the banner is clicked. The only signal left is
    -- an event toast, so read the resolved toast off the manager (the hook's own
    -- argument is a boolean, not the toast).
    if EventToastManagerFrame and EventToastManagerFrame.DisplayToast then
        hooksecurefunc(EventToastManagerFrame, "DisplayToast", function(frame)
            if not inDelve or hasBanner then return end
            local toast = frame and frame.currentDisplayingToast
            local title = toast and toast.toastInfo and toast.toastInfo.title
            if type(title) == "string" and title:find("Sanctified", 1, true) then
                hasBanner = true
                DelveState:Update()
            end
        end)
    end
end
