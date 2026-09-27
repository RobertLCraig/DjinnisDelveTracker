--[[
    Djinni's Delve Tracker - seed quest catalogue

    The ten Midnight (12.0) Delver's Call quests, one per delve. All are level 80 and
    their reward XP scales with character level, which is what makes banking them worth
    doing (DECISIONS D1).

    The English delve names here are display fallbacks only. The real, localised title is
    resolved at runtime with C_QuestLog.GetTitleForQuestID and cached in the catalogue, and
    the Scanner picks up any delve quest Blizzard adds later by matching the same title
    prefix. So this list not being exhaustive forever is expected, not a bug.
]]

local ADDON_NAME, ns = ...

ns.SEED_QUESTS = {
    { id = 93372, delve = "Shadow Enclave" },
    { id = 93384, delve = "Collegiate Calamity" },
    { id = 93385, delve = "The Darkway" },
    { id = 93386, delve = "Parhelion Plaza" },
    { id = 93409, delve = "Atal'Aman" },
    { id = 93410, delve = "Twilight Crypts" },
    { id = 93416, delve = "The Gulf of Memory" },
    { id = 93421, delve = "The Grudge Pit" },
    { id = 93427, delve = "Sunkiller Sanctum" },
    { id = 93428, delve = "Shadowguard Point" },
}

-- The four Midnight zones, in levelling order, which is the order the list groups by.
-- uiMapIDs taken from the in-game-tested waypoints in DjinnisDataTexts'
-- MajesticBeast.lua. Which delve sits in which zone is not written down here: it is read
-- off each zone's delve POIs at runtime (Locations:HarvestZones), and the zone name
-- comes from C_Map.GetMapInfo, so it is localised.
ns.ZONE_MAPS = {
    2395,   -- Eversong Woods
    2437,   -- Zul'Aman
    2413,   -- Harandar
    2405,   -- Voidstorm
}

ns.ZONE_ORDER = {}
for i, mapID in ipairs(ns.ZONE_MAPS) do ns.ZONE_ORDER[mapID] = i end
