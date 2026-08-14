--[[
    Djinni's Delve Tracker - Sanctified Banner data

    Known Sanctified Banner spawn locations, keyed by the delve name the scenario widget
    reports. Coordinates are normalised 0-1 (the /way value divided by 100).

    Each delve has several possible spawns and only one is live per run, so all known
    spawns are listed and you check whichever is nearest.

    Source: wowhead.com/spell=1269416 community comments (patch 12.0.1), by way of the
    Delve module in Djinni's Data Texts, which has had these in the field for a while.
]]

local ADDON_NAME, ns = ...

ns.BANNER_LOCATIONS = {
    ["Collegiate Calamity"] = {
        { x = 0.8136, y = 0.3986 },
        { x = 0.4660, y = 0.8429, note = "Invasive Glow variant" },
    },
    ["Darkway"] = {
        { x = 0.4961, y = 0.3752 },
        { x = 0.5366, y = 0.4989 },
    },
    ["Grudge Pit"] = {
        { x = 0.5522, y = 0.6439 },
    },
    ["Parhelion Plaza"] = {
        { x = 0.2413, y = 0.8814 },
        { x = 0.6470, y = 0.6350 },
        { x = 0.2303, y = 0.1509 },
    },
    ["Twilight Crypts"] = {
        { x = 0.4491, y = 0.5472 },
    },
    ["Atal'Aman"] = {
        { x = 0.4057, y = 0.5784 },
        { x = 0.5738, y = 0.8309 },
    },
    ["Shadowguard Point"] = {
        { x = 0.4947, y = 0.5511 },
    },
    ["The Gulf of Memory"] = {
        { x = 0.5651, y = 0.4652 },
        { x = 0.4132, y = 0.2374, note = "Upper Rootway variant" },
    },
    ["The Shadow Enclave"] = {
        { x = 0.4600, y = 0.2200 },
    },
}

-- Presence of this spell in the scenario widget means the delve carries the Sanctified
-- Banner objective at all.
ns.BOUNTIFUL_SPELL_ID = 462940

-- Buffs granted by clicking the banner. Which one appears varies by delve variant and
-- tier, and Tier 11+ delves grant none at all (see DelveState's toast hook), so this is
-- a fallback list rather than a definitive test.
--   1272756  Ward of Light
--   1273058  Holy Reinforcements
--   1271918  Sanctified Touch
ns.BANNER_BUFF_SPELL_IDS = { 1272756, 1273058, 1271918 }

-- Icon for the banner map pin.
ns.BANNER_SPELL_ID = 1269416
