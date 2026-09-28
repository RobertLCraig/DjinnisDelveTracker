--[[
    Djinni's Delve Tracker - Core

    Tracks the ten Midnight Delver's Call quests and works out what the banked stack is
    worth. Read-only against the game: nothing here accepts, abandons or hands in a quest
    (DECISIONS D5).

    Load order matters. Core builds the AceAddon object and the database, so it comes after
    Data/ (plain tables) and Locales/, and before every module and UI file.
]]

local ADDON_NAME, ns = ...

local DDT = LibStub("AceAddon-3.0"):NewAddon(
    ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0"
)
ns.Addon = DDT
_G.DjinnisDelveTracker = DDT

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
ns.L = L

--============================================================================
-- Quest state enum (DATA-MODEL). Strings, so saved variables stay readable.
--============================================================================

ns.STATE = {
    NOT_STARTED = "NOT_STARTED",
    IN_PROGRESS = "IN_PROGRESS",
    READY       = "READY",
    TURNED_IN   = "TURNED_IN",
}

-- Display order for the character tab: what still needs doing floats to the top,
-- what is finished sinks.
ns.STATE_ORDER = {
    [ns.STATE.READY]       = 1,
    [ns.STATE.IN_PROGRESS] = 2,
    [ns.STATE.NOT_STARTED] = 3,
    [ns.STATE.TURNED_IN]   = 4,
}

ns.STATE_COLOR = {
    [ns.STATE.NOT_STARTED] = { r = 0.55, g = 0.55, b = 0.58 },
    [ns.STATE.IN_PROGRESS] = { r = 1.00, g = 0.82, b = 0.20 },
    [ns.STATE.READY]       = { r = 0.30, g = 0.95, b = 0.35 },
    [ns.STATE.TURNED_IN]   = { r = 0.35, g = 0.55, b = 0.85 },
}

ns.STATE_LABEL = {
    [ns.STATE.NOT_STARTED] = L["STATE_NOT_STARTED"],
    [ns.STATE.IN_PROGRESS] = L["STATE_IN_PROGRESS"],
    [ns.STATE.READY]       = L["STATE_READY"],
    [ns.STATE.TURNED_IN]   = L["STATE_TURNED_IN"],
}

ns.ICON = "Interface\\Icons\\inv_10_dungeonjewelry_titan_earring_1_color1"

--============================================================================
-- Saved variables (DATA-MODEL). Everything the addon knows is account-wide: the
-- warband tab has to show characters we are not logged into, and per-character
-- scope cannot do that.
--============================================================================

local defaults = {
    profile = {
        minimap = { hide = false },
        window  = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, scale = 1 },
        tracker = {
            show = true, locked = false,
            point = "TOP", relPoint = "TOP", x = 0, y = -220,
            scale = 1,
        },
        buffs = {
            warMode = "auto",   -- "auto" | "on" | "off"
            custom  = 0,        -- anything the aura scan cannot see
        },
        includeAllQuests = false,
        announce = true,
        debug    = false,
        bannerPins     = true,
        bannerPinScale = 2.5,
    },
    global = {
        catalogue     = {},   -- [questID] = { delve, title, seeded, firstSeen, mapID, x, y }
        xpCurve       = {},   -- [level]   = observed UnitXPMax
        questXP       = {},   -- [questID] = { [level] = base XP }
        warModeQuests = {},   -- [questID] = does the War Mode bonus measurably apply
        xpBuffs       = {},   -- [spellID] = percent, learned from buff descriptions
        turnIns       = {},   -- capped ledger of what turn-ins actually paid, and where
        calibration   = {},   -- [conditionKey] = { n, mean } measured XP multiplier
        calibrationRekeyed = false, -- one-time wipe after the key format changed
        warModeRecheck = false, -- one-time wipe of pre-D12 War Mode measurements
        characters    = {},   -- [GUID]    = character record
        pinsChecked   = false, -- one-time check for a banner-pin clash with DjinnisDataTexts
    },
}

--============================================================================
-- UI refresh fan-out
--
-- The Scanner has no business knowing which windows exist, and a window that is
-- not built yet must not break a scan. Each UI file registers a callback here and
-- every one of them is called behind pcall.
--============================================================================

local refreshers = {}

function ns.RegisterRefresh(fn)
    refreshers[#refreshers + 1] = fn
end

function ns.Refresh()
    for i = 1, #refreshers do
        local ok, err = pcall(refreshers[i])
        if not ok then DDT:Debug("refresh error: " .. tostring(err)) end
    end
end

--============================================================================
-- Helpers
--============================================================================

function DDT:Print(msg)
    print("|cFF8E6FD8" .. L["ADDON_NAME"] .. ":|r " .. tostring(msg))
end

function DDT:Debug(msg)
    if self.db and self.db.profile and self.db.profile.debug then
        print("|cFF8888FF[DDT dbg]|r " .. tostring(msg))
    end
end

function ns.Comma(n)
    return BreakUpLargeNumbers(math.floor(tonumber(n) or 0))
end

function ns.ClassColor(classFile)
    local c = classFile and (C_ClassColor and C_ClassColor.GetClassColor(classFile))
    if c then return c.r, c.g, c.b end
    local raid = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if raid then return raid.r, raid.g, raid.b end
    return 1, 1, 1
end

-- "3h", "2d", "just now" - deliberately coarse, this only labels snapshot staleness.
function ns.AgoText(t)
    if not t then return L["NEVER"] end
    local secs = time() - t
    if secs < 60 then return "just now" end
    if secs < 3600 then return L["UPDATED_AGO"]:format(math.floor(secs / 60) .. "m") end
    if secs < 86400 then return L["UPDATED_AGO"]:format(math.floor(secs / 3600) .. "h") end
    return L["UPDATED_AGO"]:format(math.floor(secs / 86400) .. "d")
end

-- Restore/persist a frame's placement. Shared by the main window and the tracker
-- so there is one implementation of "remember where I put it".
function ns.RestorePosition(frame, cfg)
    frame:ClearAllPoints()
    frame:SetPoint(cfg.point or "CENTER", UIParent, cfg.relPoint or "CENTER", cfg.x or 0, cfg.y or 0)
    frame:SetScale(cfg.scale or 1)
end

function ns.SavePosition(frame, cfg)
    local point, _, relPoint, x, y = frame:GetPoint()
    cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint, x, y
end

-- Right-click on the tracker panel or the broker icon. A right-click offers a menu,
-- it never acts by itself.
function ns.OpenContextMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["ADDON_NAME"])
        root:CreateButton(L["MENU_OPTIONS"], function()
            if ns.OpenOptions then ns.OpenOptions() end
        end)
        root:CreateCheckbox(L["OPT_LOCK_TRACKER"],
            function() return ns.db.profile.tracker.locked end,
            function() ns.db.profile.tracker.locked = not ns.db.profile.tracker.locked end)
    end)
end

--============================================================================
-- LDB / minimap
--============================================================================

local function BuildBroker()
    local ldb = LibStub("LibDataBroker-1.1", true)
    if not ldb then return end

    local obj = ldb:NewDataObject(ADDON_NAME, {
        type = "data source",
        text = "-",
        icon = ns.ICON,
        OnClick = function(owner, button)
            if button == "RightButton" then
                ns.OpenContextMenu(owner)
            else
                if ns.MainWindow then ns.MainWindow:Toggle() end
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(L["ADDON_NAME"])
            local summary = ns.Estimator and ns.Estimator:Summary()
            if summary then
                tt:AddDoubleLine(L["TOOLTIP_STACK"],
                    L["SUMMARY_BANKED"]:format(summary.banked, summary.total))
                if summary.projection then
                    local p = summary.projection
                    tt:AddDoubleLine(L["SUMMARY_XP"]:format(ns.Comma(p.totalXP)),
                        p.capped and ("|cff40ff40" .. p.level .. "|r")
                                 or ("|cff40ff40" .. p.level .. " (" .. math.floor(p.pct) .. "%)|r"))
                end
            end
            tt:AddLine(" ")
            tt:AddLine("|cFFAAAAAA" .. L["BROKER_LEFT_CLICK"] .. "|r")
            tt:AddLine("|cFFAAAAAA" .. L["BROKER_RIGHT_CLICK"] .. "|r")
        end,
    })
    ns.broker = obj

    local icon = LibStub("LibDBIcon-1.0", true)
    if icon and obj then
        icon:Register(ADDON_NAME, obj, DDT.db.profile.minimap)
    end
end

local function UpdateBroker()
    if not ns.broker then return end
    local summary = ns.Estimator and ns.Estimator:Summary()
    if not summary then return end
    ns.broker.text = summary.banked .. "/" .. summary.total
end

--============================================================================
-- Lifecycle
--============================================================================

function DDT:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("DjinnisDelveTrackerDB", defaults, true)
    ns.db = self.db

    ns.Catalogue:SeedFromData()
    ns.Roster:EnsureCurrent()

    -- Anything cached before D12 could be a negative read taken inside a delve, where
    -- War Mode is never in effect. Those are worthless and would stick forever, so the
    -- cache is dropped once and rebuilt under the new rules.
    if not self.db.global.warModeRecheck then
        self.db.global.warModeRecheck = true
        wipe(self.db.global.warModeQuests)
    end

    -- The calibration key dropped its resting component, so old keys can never match
    -- again. Wipe rather than leave dead entries that look like data.
    if not self.db.global.calibrationRekeyed then
        self.db.global.calibrationRekeyed = true
        wipe(self.db.global.calibration)
    end

    -- Djinni's Data Texts pins the same banner spawns. Doubling them up looks broken,
    -- so defer to it once, say why, and leave the choice with the user after that.
    if not self.db.global.pinsChecked then
        self.db.global.pinsChecked = true
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DjinnisDataTexts")
        if loaded then
            self.db.profile.bannerPins = false
            self:Print(L["MSG_PINS_OFF_DDT"])
        end
    end

    if ns.SetupOptions then ns.SetupOptions() end
    BuildBroker()
    ns.RegisterRefresh(UpdateBroker)
end

function DDT:OnEnable()
    -- The Scanner owns every quest event; Core only needs the login-time refresh.
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function DDT:PLAYER_ENTERING_WORLD()
    ns.Roster:EnsureCurrent()
    if ns.Scanner then ns.Scanner:RequestScan() end
end

function DDT:RefreshConfig()
    local icon = LibStub("LibDBIcon-1.0", true)
    if icon then
        if self.db.profile.minimap.hide then icon:Hide(ADDON_NAME) else icon:Show(ADDON_NAME) end
    end
    ns.Refresh()
end
