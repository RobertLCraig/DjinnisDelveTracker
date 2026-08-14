--[[
    Djinni's Delve Tracker - options and slash commands

    Settings live here; the numbers all live in Estimator. Nothing in this file changes
    game state either.
]]

local ADDON_NAME, ns = ...
local DDT = ns.Addon
local L = ns.L

local function Profile() return ns.db.profile end

local options = {
    type = "group",
    name = L["ADDON_NAME"],
    args = {
        display = {
            type = "group", inline = true, order = 1, name = L["OPT_GENERAL"],
            args = {
                minimap = {
                    type = "toggle", order = 1, width = "full",
                    name = L["OPT_SHOW_MINIMAP"],
                    get = function() return not Profile().minimap.hide end,
                    set = function(_, value)
                        Profile().minimap.hide = not value
                        DDT:RefreshConfig()
                    end,
                },
                tracker = {
                    type = "toggle", order = 2, width = "full",
                    name = L["OPT_SHOW_TRACKER"],
                    get = function() return Profile().tracker.show end,
                    set = function(_, value)
                        Profile().tracker.show = value
                        ns.Refresh()
                    end,
                },
                lock = {
                    type = "toggle", order = 3, width = "full",
                    name = L["OPT_LOCK_TRACKER"],
                    get = function() return Profile().tracker.locked end,
                    set = function(_, value) Profile().tracker.locked = value end,
                },
                scale = {
                    type = "range", order = 4, width = "full",
                    name = L["OPT_TRACKER_SCALE"],
                    min = 0.5, max = 2, step = 0.05,
                    get = function() return Profile().tracker.scale or 1 end,
                    set = function(_, value)
                        Profile().tracker.scale = value
                        ns.Refresh()
                    end,
                },
            },
        },
        behaviour = {
            type = "group", inline = true, order = 2, name = " ",
            args = {
                announce = {
                    type = "toggle", order = 1, width = "full",
                    name = L["OPT_ANNOUNCE"],
                    get = function() return Profile().announce end,
                    set = function(_, value) Profile().announce = value end,
                },
                includeAll = {
                    type = "toggle", order = 2, width = "full",
                    name = L["OPT_INCLUDE_ALL"], desc = L["OPT_INCLUDE_ALL_DESC"],
                    get = function() return Profile().includeAllQuests end,
                    set = function(_, value)
                        Profile().includeAllQuests = value
                        ns.Refresh()
                    end,
                },
                bannerPins = {
                    type = "toggle", order = 3, width = "full",
                    name = L["OPT_BANNER_PINS"], desc = L["OPT_BANNER_PINS_DESC"],
                    get = function() return Profile().bannerPins end,
                    set = function(_, value)
                        Profile().bannerPins = value
                        ns.DelveState:RefreshMapPins()
                    end,
                },
                bannerPinScale = {
                    type = "range", order = 4, width = "full",
                    name = L["OPT_BANNER_PIN_SCALE"],
                    min = 1, max = 5, step = 0.25,
                    disabled = function() return not Profile().bannerPins end,
                    get = function() return Profile().bannerPinScale or 2.5 end,
                    set = function(_, value)
                        Profile().bannerPinScale = value
                        ns.DelveState:RefreshMapPins()
                    end,
                },
                debug = {
                    type = "toggle", order = 5, width = "full",
                    name = L["OPT_DEBUG"],
                    get = function() return Profile().debug end,
                    set = function(_, value) Profile().debug = value end,
                },
                resetPos = {
                    type = "execute", order = 6,
                    name = L["OPT_RESET_POS"],
                    func = function()
                        ns.MainWindow:ResetPosition()
                        ns.Tracker:ResetPosition()
                    end,
                },
            },
        },
        characters = {
            type = "group", inline = true, order = 3, name = L["OPT_CHARACTERS"],
            args = {
                forget = {
                    type = "select", order = 1, width = "double",
                    name = L["OPT_FORGET"], desc = L["OPT_FORGET_DESC"],
                    values = function()
                        local values, current = {}, UnitGUID("player")
                        for _, rec in ipairs(ns.Roster:All()) do
                            if rec.guid ~= current then
                                values[rec.guid] = ("%s-%s (%d)"):format(
                                    rec.name or "?", rec.realm or "?", rec.level or 0)
                            end
                        end
                        return values
                    end,
                    get = function() return nil end,
                    set = function(_, guid)
                        ns.Roster:Forget(guid)
                        ns.Refresh()
                    end,
                },
            },
        },
    },
}

function ns.OpenOptions()
    LibStub("AceConfigDialog-3.0"):Open(ADDON_NAME)
end

-- Registered for both slash names, so it has to be a method on the addon object
-- rather than a closure (AceConsole resolves the string form against `self`).
function DDT:SlashHandler(input)
    input = (input or ""):lower():trim()
    if input == "config" or input == "options" then
        ns.OpenOptions()
    elseif input == "scan" then
        ns.Scanner:Scan()
        self:Print("rescanned")
    elseif input == "reset" then
        ns.MainWindow:ResetPosition()
        ns.Tracker:ResetPosition()
        self:Print("window positions reset")
    elseif input == "debug" then
        Profile().debug = not Profile().debug
        self:Print("debug " .. (Profile().debug and "on" or "off"))
    elseif input == "xp" then
        -- Dump the raw observations. This is what settles whether the scaling model in
        -- DECISIONS D4 survives, so it needs to be readable without a debugger.
        local growth = ns.Estimator:ObservedGrowth()
        self:Print(growth
            and ("measured quest XP growth: %.4f per level"):format(growth)
            or "no cross-level observations yet, scaling is still modelled")
        for questID, perQuest in pairs(ns.db.global.questXP) do
            local parts = {}
            for level, xp in pairs(perQuest) do
                parts[#parts + 1] = ("%d: %s"):format(level, ns.Comma(xp))
            end
            table.sort(parts)
            self:Print(("  %s  %s"):format(ns.Catalogue:DisplayName(questID), table.concat(parts, "  ")))
        end

        -- The turn-in ledger. Two entries with the same buffs and different zones are
        -- what answers "does handing in inside a city cost me the War Mode bonus".
        -- Warband Mentor is an achievement, not a buff, so when the buff line says
        -- "none detected" this is the only way to see whether it read at all.
        local mentorPct, mentorName = ns.Estimator:WarbandMentorBonus()
        self:Print(mentorPct
            and ("Warband Mentor: +%d%% (%s)"):format(mentorPct, mentorName or "?")
            or "Warband Mentor: none of the tiers read as earned")
        for _, tier in ipairs(ns.WARBAND_MENTOR) do
            local _, name, _, completed = GetAchievementInfo(tier.id)
            self:Print(("  %d %s  +%d%%  %s"):format(tier.id, name or "?", tier.pct,
                completed and "|cff40ff40earned|r" or "|cff808080no|r"))
        end

        -- Itemised, because a total on its own cannot tell a real second buff from the
        -- same bonus counted twice.
        local detected, detectedTotal, readable = ns.Estimator:DetectedXPBuffs()
        self:Print(readable and ("XP buffs: +%d%% total"):format(detectedTotal)
            or ("XP buffs: +%d%% total (auras unreadable)"):format(detectedTotal))
        for _, buff in ipairs(detected) do
            self:Print(("  +%d%%  %s%s"):format(buff.pct, buff.name or "?",
                buff.spellID and ("  spell " .. buff.spellID) or "  (achievement)"))
        end

        local measured, samples = ns.Estimator:MeasuredMultiplier()
        self:Print(("conditions now: %s"):format(ns.Estimator:CalibrationKey()))
        if measured then
            self:Print(("measured multiplier here: x%.4f from %d turn-in(s)"):format(measured, samples))
        else
            self:Print("no measurement for these conditions yet, using the modelled multiplier")
        end
        for key, entry in pairs(ns.db.global.calibration) do
            self:Print(("  %s  x%.4f  (%d)"):format(key, entry.mean, entry.n))
        end

        local ledger = ns.db.global.turnIns
        if #ledger == 0 then
            self:Print("no turn-ins recorded yet")
        else
            self:Print(("turn-ins (%d):"):format(#ledger))
            for _, entry in ipairs(ledger) do
                self:Print(("  L%d %s  base %s -> %s  |cffffffffx%.3f|r  warmode:%s buffs:+%d%%  %s%s"):format(
                    entry.level or 0, ns.Catalogue:DisplayName(entry.questID),
                    ns.Comma(entry.base), ns.Comma(entry.actual), entry.implied or 0,
                    entry.warMode or "?", entry.buffPct or 0,
                    entry.zone or "?", entry.resting and " (resting)" or ""))
            end
        end
    else
        ns.MainWindow:Toggle()
    end
end

function ns.SetupOptions()
    local dialog = LibStub("AceConfigDialog-3.0")

    options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(ns.db)
    options.args.profiles.order = 10

    LibStub("AceConfig-3.0"):RegisterOptionsTable(ADDON_NAME, options)
    dialog:SetDefaultSize(ADDON_NAME, 520, 460)
    ns.optionsFrame = dialog:AddToBlizOptions(ADDON_NAME, L["ADDON_NAME"])

    ns.db.RegisterCallback(DDT, "OnProfileChanged", "RefreshConfig")
    ns.db.RegisterCallback(DDT, "OnProfileCopied", "RefreshConfig")
    ns.db.RegisterCallback(DDT, "OnProfileReset", "RefreshConfig")

    -- "ddt" belongs to Djinni's Data Texts, which claims it as SlashCmdList["DDT"].
    -- Registering it here too put two entries in SlashCmdList that both resolve to
    -- the tag "/DDT", and ChatFrameUtil's ImportListToHash keeps whichever it reaches
    -- last while iterating a Lua hash. That is not load order and not alphabetical,
    -- so the winner was arbitrary and could flip when any other addon was added.
    -- Data Texts keeps /ddt; this addon answers to /dvt and /delvetracker.
    DDT:RegisterChatCommand("dvt", "SlashHandler")
    DDT:RegisterChatCommand("delvetracker", "SlashHandler")
end
