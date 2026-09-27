--[[
    Djinni's Delve Tracker - delve entrance locations

    Two independent sources, because neither covers everything:

      Quest waypoints  C_QuestLog.GetNextWaypoint only works for quests in your log, but
                       when it works it points exactly where the game wants you to go.
      Delve POIs       C_AreaPoiInfo.GetDelvesForMap works for delves you have never
                       touched, which is the only way a "not started" row can be
                       clickable. Matched to a quest by name.

    Coordinates are cached account-wide, so once any character has been near a delve every
    alt can click straight to it.
]]

local ADDON_NAME, ns = ...
local DDT = ns.Addon
local L = ns.L

local Locations = {}
ns.Locations = Locations

--============================================================================
-- Name matching
--
-- POI names and quest titles agree on the delve name but not always on punctuation or
-- case, so both sides get flattened before comparison.
--============================================================================

local function Normalise(text)
    if not text then return nil end
    -- The leading article comes and goes between sources ("The Shadow Enclave" on one
    -- side, "Shadow Enclave" on the other), so it goes too.
    text = text:lower():gsub("^the%s+", ""):gsub("[^%w]", "")
    return text ~= "" and text or nil
end

--============================================================================
-- Harvesting
--============================================================================

local function Store(questID, mapID, x, y, source)
    local entry = ns.Catalogue:Get(questID)
    if not entry or not mapID or not x or not y then return false end
    -- A quest waypoint is the game's own answer, so it wins over a name-matched POI.
    if entry.locSource == "quest" and source ~= "quest" then return false end
    entry.mapID, entry.x, entry.y, entry.locSource = mapID, x, y, source
    return true
end

function Locations:HarvestFromQuests()
    if not C_QuestLog.GetNextWaypoint then return end
    for _, questID in ipairs(ns.Catalogue:Ordered()) do
        if C_QuestLog.IsOnQuest(questID) then
            local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
            Store(questID, mapID, x, y, "quest")
        end
    end
end

-- Match every delve POI on a map to a catalogue entry by delve name.
function Locations:HarvestFromMap(mapID)
    if not mapID or not C_AreaPoiInfo or not C_AreaPoiInfo.GetDelvesForMap then return 0 end

    local poiIDs = C_AreaPoiInfo.GetDelvesForMap(mapID)
    if not poiIDs or #poiIDs == 0 then return 0 end

    local byName = {}
    for _, questID in ipairs(ns.Catalogue:Ordered()) do
        local key = Normalise(ns.Catalogue:DisplayName(questID))
        if key then byName[key] = questID end
    end

    local isZone = ns.ZONE_ORDER[mapID] ~= nil
    local found = 0
    for _, poiID in ipairs(poiIDs) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
        local questID = info and info.name and byName[Normalise(info.name)]
        -- The zone is recorded apart from the coordinates, because a quest waypoint
        -- can own those and it points wherever the quest wants, not at the delve's zone.
        if questID and isZone then ns.Catalogue:Get(questID).zone = mapID end
        if questID and info.position then
            local x, y = info.position:GetXY()
            if Store(questID, mapID, x, y, "poi") then found = found + 1 end
        end
    end
    return found
end

-- Every Midnight zone, wherever the player is standing. This is what fills in the zone
-- each delve is grouped under, so the grouping works on the first login.
function Locations:HarvestZones()
    for _, mapID in ipairs(ns.ZONE_MAPS) do self:HarvestFromMap(mapID) end
end

-- The current zone, and every other zone on the same continent. Walking the continent
-- means one flight into Midnight populates the whole list rather than needing a lap of
-- all ten delves.
function Locations:HarvestNearby()
    if not C_Map or not C_Map.GetBestMapForUnit then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end

    self:HarvestFromMap(mapID)

    local continent, guard = mapID, 0
    while continent and guard < 10 do
        local info = C_Map.GetMapInfo(continent)
        if not info then break end
        if info.mapType and Enum.UIMapType and info.mapType <= Enum.UIMapType.Continent then break end
        continent = info.parentMapID
        guard = guard + 1
    end
    if not continent or continent == mapID then return end

    local zones = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(continent, nil, true)
    if not zones then return end
    for _, zone in ipairs(zones) do
        if zone.mapID ~= mapID then self:HarvestFromMap(zone.mapID) end
    end
end

--============================================================================
-- Waypoints
--============================================================================

function Locations:Has(questID)
    local entry = ns.Catalogue:Get(questID)
    return entry and entry.mapID and entry.x and entry.y or false
end

-- Drop a map pin on the delve entrance and super-track it. If we have no coordinates,
-- fall back to super-tracking the quest itself, which at least puts an arrow up for a
-- quest you are already on.
function Locations:Waypoint(questID)
    local entry = ns.Catalogue:Get(questID)
    local name = ns.Catalogue:DisplayName(questID)

    if entry and entry.mapID and entry.x and entry.y then
        if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(entry.mapID) then
            DDT:Print(L["MSG_WAYPOINT_BLOCKED"]:format(name))
            return false
        end
        local point = UiMapPoint.CreateFromCoordinates(entry.mapID, entry.x, entry.y)
        C_Map.SetUserWaypoint(point)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        DDT:Print(L["MSG_WAYPOINT_SET"]:format(name, entry.x * 100, entry.y * 100))
        return true
    end

    if C_QuestLog.IsOnQuest(questID) and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        C_SuperTrack.SetSuperTrackedQuestID(questID)
        DDT:Print(L["MSG_WAYPOINT_QUEST"]:format(name))
        return true
    end

    DDT:Print(L["MSG_WAYPOINT_UNKNOWN"]:format(name))
    return false
end
