--[[
    Djinni's Delve Tracker - compact panel

    One line you can leave on screen while you run the delves: how many are banked and
    where handing in right now would put you. Left-click opens the main window, drag to
    move it while it is unlocked.
]]

local ADDON_NAME, ns = ...
local L = ns.L

local Tracker = {}
ns.Tracker = Tracker

local panel

-- Edit Mode: anything on screen is movable from it. Same approach as
-- DjinnisUIEnhancements/EditMode.lua, cut down to a box you select and drag: the
-- panel has one setting worth editing (scale) and the options panel already has it.
-- Blizzard's selection box, with its OnMouseDown and drag scripts replaced, because
-- the stock ones hand the frame to EditModeManagerFrame:SelectSystem, which only knows
-- Blizzard systems. The position is saved in the same fields the unlocked drag uses,
-- so there is nothing to migrate.
local function AddToEditMode()
    local sel = CreateFrame("Frame", nil, panel, "EditModeSystemSelectionTemplate")
    sel:SetAllPoints()
    sel:SetFrameStrata("HIGH") -- over Blizzard's own boxes (UIEnhancements, 2026-09-21)
    sel.system = { GetSystemName = function() return L["ADDON_NAME"] end }
    sel:Hide()

    sel:SetScript("OnDragStart", function()
        if not InCombatLockdown() then panel:StartMoving() end
    end)
    sel:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        ns.SavePosition(panel, ns.db.profile.tracker)
    end)
    sel:SetScript("OnMouseDown", function()
        EditModeManagerFrame:ClearSelectedSystem()
        sel:ShowSelected()
    end)
    hooksecurefunc(EditModeManagerFrame, "SelectSystem", function()
        if sel:IsShown() then sel:ShowHighlighted() end
    end)

    EventRegistry:RegisterCallback("EditMode.Enter", function()
        sel:ShowHighlighted()
    end, sel)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        sel:Hide()
    end, sel)
    if EditModeManagerFrame:IsEditModeActive() then sel:ShowHighlighted() end
end

local function Build()
    panel = CreateFrame("Frame", "DjinnisDelveTrackerPanel", UIParent, "BackdropTemplate")
    panel:SetSize(200, 30)
    panel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0, 0, 0, 0.55)
    panel:SetBackdropBorderColor(0, 0, 0, 0.9)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")

    panel:SetScript("OnDragStart", function(self)
        if not ns.db.profile.tracker.locked then self:StartMoving() end
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.SavePosition(self, ns.db.profile.tracker)
    end)
    panel:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ns.OpenContextMenu(panel)
        else
            ns.MainWindow:Toggle()
        end
    end)
    panel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["ADDON_NAME"], 1, 1, 1)
        local summary = ns.Estimator:Summary()
        if summary and summary.projection then
            local p = summary.projection
            GameTooltip:AddLine(L["TRACKER_LINE"]:format(
                summary.banked, summary.total, p.level, math.floor(p.pct)), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(L["SUMMARY_XP"]:format(ns.Comma(p.totalXP)), 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFAAAAAA" .. L["BROKER_LEFT_CLICK"] .. "|r")
        GameTooltip:AddLine("|cFFAAAAAA" .. L["BROKER_RIGHT_CLICK"] .. "|r")
        GameTooltip:Show()
    end)
    panel:SetScript("OnLeave", GameTooltip_Hide)

    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.text:SetPoint("CENTER")

    ns.RestorePosition(panel, ns.db.profile.tracker)
    AddToEditMode()
end

function Tracker:Refresh()
    if not ns.db then return end
    if not ns.db.profile.tracker.show then
        if panel then panel:Hide() end
        return
    end

    if not panel then Build() end
    panel:SetScale(ns.db.profile.tracker.scale or 1)

    local summary = ns.Estimator:Summary()
    if not summary then
        panel:Hide()
        return
    end

    local text
    if summary.projection then
        local p = summary.projection
        text = ("|cffffffff%d/%d|r  |cff40ff40%d|r |cffaaaaaa%d%%|r"):format(
            summary.banked, summary.total, p.level, math.floor(p.pct))
    else
        text = ("|cffffffff%d/%d|r  |cff808080-|r"):format(summary.banked, summary.total)
    end

    -- Inside a delve, the objective count is the thing you actually want on screen.
    local delve = ns.DelveState and ns.DelveState:Get()
    if delve and delve.active and delve.total > 0 then
        text = text .. ("   |cffffcc33%d/%d|r"):format(delve.done, delve.total)
    end
    panel.text:SetText(text)
    panel:SetWidth(math.max(120, panel.text:GetStringWidth() + 28))
    panel:Show()
end

function Tracker:ResetPosition()
    local cfg = ns.db.profile.tracker
    cfg.point, cfg.relPoint, cfg.x, cfg.y = "TOP", "TOP", 0, -220
    if panel then ns.RestorePosition(panel, cfg) end
end

ns.RegisterRefresh(function() Tracker:Refresh() end)
