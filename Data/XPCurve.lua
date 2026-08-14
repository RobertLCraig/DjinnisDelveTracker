--[[
    Djinni's Delve Tracker - XP per level seed

    XP required to advance FROM the given level TO the next one, for Midnight's 80-89 band.
    Totals 4,963,065 XP for 80 -> 90.

    This is a seed, not truth: Blizzard has already retuned this band once and can again.
    Every value is overwritten by the live UnitXPMax() the moment a character of that level
    logs in, and the override lives in db.global.xpCurve (DATA-MODEL).
]]

local ADDON_NAME, ns = ...

ns.XP_SEED = {
    [80] = 403725,
    [81] = 423390,
    [82] = 443395,
    [83] = 463740,
    [84] = 484430,
    [85] = 505455,
    [86] = 526825,
    [87] = 548535,
    [88] = 570590,
    [89] = 592980,
}

-- Used only when extrapolating past the end of the seed (a future level cap): the seed
-- band climbs by roughly this much per level.
ns.XP_GROWTH_PER_LEVEL = 1.045

ns.MAX_LEVEL_FALLBACK = 90
