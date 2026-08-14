--[[
    Djinni's Delve Tracker - experience buffs

    Buffs that multiply quest XP, keyed by spell ID, value in percent.

    This table is a seed for exact values. Anything not listed is picked up by reading the
    spell description at runtime and pulling the percentage out of it, so a tier we have
    never seen still counts (DECISIONS D11). Learned values are cached account-wide.

    Timeways is the Timewalking event line and is the whole reason the delve-banking route
    works: it is tiered, and the tier you hold at turn-in is what the stack is worth.
]]

local ADDON_NAME, ns = ...

ns.XP_BUFFS = {
    [1269517] = 5,   -- Knowledge of the Timeways
}

-- Buffs the aura scan must skip, either because they do not grant a flat percentage or
-- because the addon already accounts for them somewhere else.
ns.XP_BUFF_IGNORE = {
    -- Enlisted, the War Mode aura. It appears at +15% only while War Mode is actually in
    -- effect, so counting it here would add War Mode on top of the explicit War Mode term
    -- in Multipliers() and model x1.60 where the truth is x1.45. War Mode stays on the
    -- explicit path because that one is gated per quest and can be toggled to plan a
    -- turn-in you have not made yet; an aura can only tell you about right now.
    [269083] = true,
}

-- Warband Mentored Leveling: +5% XP per level-90 character on the account, to a cap of
-- 25% at five. It is granted by an achievement series, not an aura, which is exactly why
-- an aura scan could never find it and why it kept paying out with War Mode off and the
-- Timewalking buff expired.
--
-- The tiers are cumulative, so the highest completed one is the answer, not the sum.
-- The same bonus also exists as a real aura, so reading both sources adds it twice. The
-- aura is preferred when present, because it is the live value; the achievement tiers
-- below are the fallback for when auras are unreadable.
ns.WARBAND_MENTOR_AURAS = {
    [430191] = true,   -- Warband Mentored Leveling
}

ns.WARBAND_MENTOR = {
    { id = 42328, pct = 5 },   -- One Warband Mentor: Midnight
    { id = 42329, pct = 10 },  -- Two
    { id = 42330, pct = 15 },  -- Three
    { id = 42331, pct = 20 },  -- Four
    { id = 42332, pct = 25 },  -- Five
}
