--[[
    Djinni's Delve Tracker - main window

    Two tabs. "Character" is the working view: every delve quest with its state, the
    banked total, and where handing in now would leave you. "Warband" answers the other
    question, which alt is sitting on a stack you forgot about.

    Clicking a row drops a waypoint on that delve's entrance.

    The window resizes to its content rather than scrolling, so a patch adding delves just
    makes it taller.
]]

local ADDON_NAME, ns = ...
local DDT = ns.Addon
local L = ns.L

local MainWindow = {}
ns.MainWindow = MainWindow

local WIDTH        = 460
local ROW_HEIGHT   = 20
local HEADER_SPACE = 126   -- title bar, portrait, tab row, column header
local FOOTER_SPACE = 226   -- summary, cap line, buff row, wait list

local frame, charRows, warbandRows
local zoneHeadings = {}

--============================================================================
-- Small builders
--============================================================================

local function MakeFontString(parent, template, justify)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function MakeCheckbox(parent, label, tooltip, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)

    -- The template's own label is fiddly across versions; ours is one fontstring we
    -- control, anchored where we want it.
    local text = MakeFontString(cb, "GameFontNormalSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb.label = text

    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns.Refresh()
    end)
    cb:SetScript("OnEnter", function(self)
        if not tooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tooltip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", GameTooltip_Hide)

    cb.Sync = function(self) self:SetChecked(get() and true or false) end
    return cb
end

--============================================================================
-- Rows
--============================================================================

local function AcquireRow(parent, index, pool)
    local row = pool[index]
    if row then return row end

    row = CreateFrame("Button", nil, parent)
    row:SetSize(WIDTH - 60, ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.06)

    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.swatch:SetSize(8, 8)
    row.swatch:SetPoint("LEFT", 0, 0)

    row.name = MakeFontString(row, "GameFontHighlight")
    row.name:SetPoint("LEFT", row.swatch, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -150, 0)
    row.name:SetJustifyH("LEFT")

    row.status = MakeFontString(row, "GameFontHighlightSmall", "RIGHT")
    row.status:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.status:SetWidth(146)

    pool[index] = row
    return row
end

local function PlaceRow(row, panel, index)
    local offset = -(index - 1) * ROW_HEIGHT
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, offset)
    row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, offset)
end

--============================================================================
-- Character tab
--============================================================================

-- The zone a delve is grouped under, as a sort rank. A delve whose zone has not been
-- read yet sorts last, under its own heading.
local UNKNOWN_ZONE = 99

local function ZoneRank(questID)
    local entry = ns.Catalogue:Get(questID)
    return entry and ns.ZONE_ORDER[entry.zone] or UNKNOWN_ZONE
end

local function ZoneName(questID)
    local entry = ns.Catalogue:Get(questID)
    local info = entry and entry.zone and C_Map.GetMapInfo(entry.zone)
    return info and info.name or L["ZONE_UNKNOWN"]
end

local function SortedQuestIDs(rec)
    local ids = ns.Catalogue:Ordered()
    table.sort(ids, function(a, b)
        local za, zb = ZoneRank(a), ZoneRank(b)
        if za ~= zb then return za < zb end
        local sa = ns.STATE_ORDER[rec.quests[a] or ns.STATE.NOT_STARTED] or 9
        local sb = ns.STATE_ORDER[rec.quests[b] or ns.STATE.NOT_STARTED] or 9
        if sa ~= sb then return sa < sb end
        return ns.Catalogue:DisplayName(a) < ns.Catalogue:DisplayName(b)
    end)
    return ids
end

local function RowTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.Catalogue:DisplayName(row.questID), 1, 1, 1)
    local entry = ns.Catalogue:Get(row.questID)
    if entry and entry.mapID then
        local info = C_Map.GetMapInfo(entry.mapID)
        GameTooltip:AddLine(("%s  %.1f, %.1f"):format(
            (info and info.name) or "?", (entry.x or 0) * 100, (entry.y or 0) * 100), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("|cFFAAAAAA" .. L["ROW_HINT"] .. "|r")
    GameTooltip:Show()
end

local function LayoutCharacterTab()
    local rec = ns.Roster:Current()
    if not rec then return 0 end

    local panel = frame.charPanel
    local ids = SortedQuestIDs(rec)

    -- A zone heading takes a row slot of its own, so slot runs ahead of the row index.
    local slot, headings, lastZone = 0, 0, nil

    for i, questID in ipairs(ids) do
        local zone = ZoneRank(questID)
        if zone ~= lastZone then
            lastZone = zone
            slot, headings = slot + 1, headings + 1
            local heading = zoneHeadings[headings]
            if not heading then
                heading = MakeFontString(panel, "GameFontNormal")
                zoneHeadings[headings] = heading
            end
            heading:ClearAllPoints()
            heading:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, -slot * ROW_HEIGHT + 3)
            heading:SetText(ZoneName(questID))
            heading:Show()
        end
        slot = slot + 1

        local row = AcquireRow(panel, i, charRows)
        local state = rec.quests[questID] or ns.STATE.NOT_STARTED
        local colour = ns.STATE_COLOR[state]

        PlaceRow(row, panel, slot)
        row.questID = questID
        row:SetScript("OnClick", function(self) ns.Locations:Waypoint(self.questID) end)
        row:SetScript("OnEnter", RowTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)

        row.swatch:SetVertexColor(colour.r, colour.g, colour.b)
        row.name:SetText(ns.Catalogue:DisplayName(questID))
        row.name:SetTextColor(colour.r, colour.g, colour.b)

        local statusText = ns.STATE_LABEL[state]
        if state == ns.STATE.READY then
            local xp = ns.Scanner:BaseXP(questID) or ns.Estimator:QuestXP(questID, rec.level)
            if xp then
                statusText = statusText .. "  |cffffffff" .. ns.Comma(xp) .. "|r"
            end
        elseif state == ns.STATE.IN_PROGRESS then
            local objectives = C_QuestLog.GetQuestObjectives(questID)
            if objectives and objectives[1] and objectives[1].text then
                statusText = objectives[1].text
            end
        end
        row.status:SetText(statusText)
        row.status:SetTextColor(colour.r, colour.g, colour.b)
        row:Show()
    end

    for i = #ids + 1, #charRows do charRows[i]:Hide() end
    for i = headings + 1, #zoneHeadings do zoneHeadings[i]:Hide() end
    return slot
end

local function UpdateSummary()
    local summary = ns.Estimator:Summary()
    if not summary then return end

    frame.bankedText:SetText(L["SUMMARY_BANKED"]:format(summary.banked, summary.total))
    local projection = summary.projection

    if projection then
        -- The multiplier shown is the one the projection actually used, not the one the
        -- settings imply. They differ whenever a quest refuses a buff (DECISIONS D7).
        -- Say which multiplier this is. A measured one beats the modelled sum of buffs
        -- and the difference has been large enough to matter (DECISIONS D13).
        local _, samples = ns.Estimator:MeasuredMultiplier()
        local multText = L["SUMMARY_MULT"]:format(projection.effective)
        if samples then
            multText = ("|cff40ff40%s|r |cff808080%s|r"):format(multText,
                L["MULT_MEASURED"]:format(samples))
        else
            multText = ("|cffaaaaaa%s %s|r"):format(multText, L["MULT_MODELLED"])
        end
        frame.xpText:SetText(("%s   %s"):format(
            L["SUMMARY_XP"]:format(ns.Comma(projection.totalXP)), multText))

        -- The cap warning gets its own line. Appended to the projection it ran straight
        -- through the "+N levels" count on the right.
        if projection.capped then
            frame.projectionText:SetText(L["PROJECT_CAPPED"]:format(projection.level))
            frame.capText:SetText(projection.wasted > 0
                and ("|cffff8040" .. L["WAITLIST_WASTED"]:format(ns.Comma(projection.wasted)) .. "|r")
                or "")
        else
            frame.projectionText:SetText(L["PROJECT_NOW"]:format(projection.level, projection.pct))
            frame.capText:SetText("")
        end
        frame.gainText:SetText(projection.levelsGained > 0
            and L["PROJECT_GAIN"]:format(projection.levelsGained) or "")
    else
        frame.xpText:SetText("")
        frame.projectionText:SetText("|cff808080" .. L["PROJECT_NOTHING"] .. "|r")
        frame.gainText:SetText("")
        frame.capText:SetText("")
    end

    if summary.unknown > 0 then
        frame.warnText:SetText("|cffffcc00" .. L["UNKNOWN_XP"]:format(summary.unknown) .. "|r")
    elseif projection and projection.estimated then
        frame.warnText:SetText("|cff808080" .. L["PROJECT_ESTIMATED"] .. "|r")
    else
        frame.warnText:SetText("")
    end

    -- Wait-list: leaving the stack alone and handing in later.
    local waitRows, flat = ns.Estimator:WaitRows(summary.entries, summary.level)
    for i, waitRow in ipairs(frame.waitRows) do
        local data = waitRows[i]
        if data then
            local left = L["WAITLIST_ROW"]:format(data.level)
            -- A negative delta means the stack overflows the level cap and the excess is
            -- burned. Say how much, and never in the colour that means "better".
            if data.capped and data.wasted > 0 then
                left = left .. ("  |cffff8040%s|r"):format(L["WAITLIST_WASTED"]:format(ns.Comma(data.wasted)))
            end
            waitRow.left:SetText(left)

            local delta
            if math.abs(data.delta) < 0.005 then
                delta = "|cff808080+0.00 lv|r"
            elseif data.delta < 0 then
                delta = ("|cffff6060%+0.2f lv|r"):format(data.delta)
            else
                delta = ("|cff40ff40%+0.2f lv|r"):format(data.delta)
            end
            waitRow.right:SetText(("%s   %s"):format(ns.Comma(data.totalXP), delta))
            waitRow:Show()
        else
            waitRow:Hide()
        end
    end
    -- Once quest XP has been seen at more than one level, the measured growth is the
    -- whole argument for or against waiting, so it goes in the header.
    local growth = ns.Estimator:ObservedGrowth()
    if growth then
        frame.waitHeader:SetText(("%s  |cffaaaaaa%s|r"):format(L["WAITLIST_HEADER"],
            L["WAITLIST_GROWTH"]:format((growth - 1) * 100)))
    else
        frame.waitHeader:SetText(L["WAITLIST_HEADER"])
    end
    frame.waitHeader:SetShown(#waitRows > 0)
    -- Only caveat the flat result while it is an artefact of the model. Once real
    -- cross-level observations exist, a flat answer is a finding, not a placeholder.
    frame.waitNote:SetShown(#waitRows > 0 and flat and not ns.Estimator:HasCrossLevelData())

    frame.warModeCheck:Sync()
    frame.customBox:SetNumber(tonumber(ns.db.profile.buffs.custom) or 0)

    local detected, detectedTotal, readable = ns.Estimator:DetectedXPBuffs()
    if not readable then
        frame.buffsText:SetText("|cff808080" .. L["BUFF_AURAS_HIDDEN"] .. "|r")
    elseif #detected == 0 then
        frame.buffsText:SetText("|cff808080" .. L["BUFF_NONE"] .. "|r")
    else
        frame.buffsText:SetText(("|cff40ff40+%d%%|r |cffaaaaaa%s|r"):format(
            detectedTotal, L["BUFF_COUNT"]:format(#detected)))
    end

    -- Say out loud when War Mode is on but the quests do not take it, instead of
    -- letting the tick sit there implying a bonus that is not in the number.
    local label = ("%s |cffaaaaaa+%d%%|r"):format(L["BUFF_WARMODE"], ns.Estimator:WarModeBonus())
    local status = ns.Estimator:WarModeStatus()
    local note = ""

    if status == "inactive" then
        -- Standing in a city or an instance. Everything the client reports about the
        -- War Mode bonus right now is unreliable, including the line below it.
        label = label .. " |cffffcc00*|r"
        note = "|cffffcc00" .. L["WARMODE_INACTIVE"] .. "|r"
    elseif status == "active" and projection and projection.questCount > 0
        and projection.warModeCount == 0 then
        label = label .. " |cffff6060*|r"
        note = "|cffff6060" .. L["WARMODE_NOT_APPLIED"] .. "|r"
    end

    frame.warModeCheck.label:SetText(label)
    frame.warModeNote:SetText(note)
end

--============================================================================
-- Warband tab
--============================================================================

local function LayoutWarbandTab()
    local panel = frame.warbandPanel
    local all = ns.Roster:All()
    local currentGUID = UnitGUID("player")

    for i, rec in ipairs(all) do
        local row = AcquireRow(panel, i, warbandRows)
        PlaceRow(row, panel, i)
        row.questID = nil
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)

        local r, g, b = ns.ClassColor(rec.class)
        local banked = rec.banked or 0
        row.swatch:SetVertexColor(r, g, b)
        row.name:SetText(("%s  |cffaaaaaa%d|r"):format(rec.name or "?", rec.level or 0))
        row.name:SetTextColor(r, g, b)

        local colour = banked > 0 and ns.STATE_COLOR[ns.STATE.READY] or ns.STATE_COLOR[ns.STATE.NOT_STARTED]
        local suffix = (rec.guid == currentGUID) and "" or ("  |cff707070" .. ns.AgoText(rec.updated) .. "|r")
        row.status:SetText(("%d/%d%s"):format(banked, ns.Catalogue:Count(), suffix))
        row.status:SetTextColor(colour.r, colour.g, colour.b)
        row:Show()
    end

    for i = #all + 1, #warbandRows do warbandRows[i]:Hide() end
    frame.emptyText:SetShown(#all == 0)
    return #all
end

--============================================================================
-- Frame construction
--============================================================================

local function SelectTab(which)
    frame.tab = which
    local isChar = (which == "character")

    frame.charPanel:SetShown(isChar)
    frame.summaryPanel:SetShown(isChar)
    frame.warbandPanel:SetShown(not isChar)
    frame.emptyText:SetShown(false)

    -- Both stay clickable; the active one is held highlighted. Disabling the active tab
    -- read backwards, the greyed-out button looked like the one you could not see.
    if isChar then
        frame.charTab:LockHighlight()
        frame.warbandTab:UnlockHighlight()
    else
        frame.charTab:UnlockHighlight()
        frame.warbandTab:LockHighlight()
    end

    MainWindow:Refresh()
end

local function Build()
    frame = CreateFrame("Frame", "DjinnisDelveTrackerFrame", UIParent, "PortraitFrameTemplate")
    frame:SetSize(WIDTH, 480)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.SavePosition(self, ns.db.profile.window)
    end)
    frame:SetClampedToScreen(true)
    frame:Hide()

    if frame.SetTitle then frame:SetTitle(L["ADDON_NAME"]) end
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(ns.ICON)
    elseif frame.PortraitContainer and frame.PortraitContainer.portrait then
        frame.PortraitContainer.portrait:SetTexture(ns.ICON)
    end
    tinsert(UISpecialFrames, "DjinnisDelveTrackerFrame")

    -- Tabs sit below the portrait ring, which juts down past the title bar and covered
    -- the first tab when they were level with it.
    frame.charTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.charTab:SetSize(110, 22)
    frame.charTab:SetPoint("TOPLEFT", 16, -62)
    frame.charTab:SetText(L["TAB_CHARACTER"])
    frame.charTab:SetScript("OnClick", function() SelectTab("character") end)

    frame.warbandTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.warbandTab:SetSize(110, 22)
    frame.warbandTab:SetPoint("LEFT", frame.charTab, "RIGHT", 6, 0)
    frame.warbandTab:SetText(L["TAB_WARBAND"])
    frame.warbandTab:SetScript("OnClick", function() SelectTab("warband") end)

    -- Live delve section. Collapses to nothing when you are not in a delve, so the
    -- column header below it is anchored to the panel rather than to the tabs.
    frame.delvePanel = ns.DelvePanel:Build(frame)
    frame.delvePanel:SetPoint("TOPLEFT", frame.charTab, "BOTTOMLEFT", 4, -8)
    frame.delvePanel:SetWidth(WIDTH - 44)

    -- Column header
    frame.headerDelve = MakeFontString(frame, "GameFontNormalSmall")
    frame.headerDelve:SetPoint("TOPLEFT", frame.delvePanel, "BOTTOMLEFT", 4, -8)
    frame.headerDelve:SetText(L["COL_DELVE"])

    frame.headerStatus = MakeFontString(frame, "GameFontNormalSmall", "RIGHT")
    frame.headerStatus:SetPoint("TOP", frame.headerDelve, "TOP", 0, 0)
    frame.headerStatus:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    frame.headerStatus:SetText(L["COL_STATUS"])

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", frame.headerDelve, "BOTTOMLEFT", -4, -3)
    divider:SetPoint("TOPRIGHT", frame.headerStatus, "BOTTOMRIGHT", 4, -3)

    -- Row containers
    frame.charPanel = CreateFrame("Frame", nil, frame)
    frame.charPanel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 4, -6)
    frame.charPanel:SetPoint("TOPRIGHT", divider, "BOTTOMRIGHT", -4, -6)
    frame.charPanel:SetHeight(1)

    frame.warbandPanel = CreateFrame("Frame", nil, frame)
    frame.warbandPanel:SetAllPoints(frame.charPanel)
    frame.warbandPanel:Hide()

    frame.emptyText = MakeFontString(frame, "GameFontDisable")
    frame.emptyText:SetPoint("TOP", frame.charPanel, "TOP", 0, -20)
    frame.emptyText:SetText(L["NO_CHARACTERS"])
    frame.emptyText:Hide()

    -- Summary block, pinned to the bottom of the window
    local summary = CreateFrame("Frame", nil, frame)
    summary:SetPoint("BOTTOMLEFT", 20, 16)
    summary:SetPoint("BOTTOMRIGHT", -20, 16)
    summary:SetHeight(FOOTER_SPACE - 24)
    frame.summaryPanel = summary

    local topLine = summary:CreateTexture(nil, "ARTWORK")
    topLine:SetColorTexture(1, 1, 1, 0.12)
    topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT", 0, 0)
    topLine:SetPoint("TOPRIGHT", 0, 0)

    frame.bankedText = MakeFontString(summary, "GameFontNormalLarge")
    frame.bankedText:SetPoint("TOPLEFT", 0, -10)

    frame.xpText = MakeFontString(summary, "GameFontHighlight", "RIGHT")
    frame.xpText:SetPoint("TOPRIGHT", 0, -12)

    frame.projectionText = MakeFontString(summary, "GameFontNormal")
    frame.projectionText:SetPoint("TOPLEFT", frame.bankedText, "BOTTOMLEFT", 0, -6)

    frame.gainText = MakeFontString(summary, "GameFontHighlightSmall", "RIGHT")
    frame.gainText:SetPoint("TOPRIGHT", frame.xpText, "BOTTOMRIGHT", 0, -6)

    frame.capText = MakeFontString(summary, "GameFontHighlightSmall")
    frame.capText:SetPoint("TOPLEFT", frame.projectionText, "BOTTOMLEFT", 0, -3)

    frame.warnText = MakeFontString(summary, "GameFontHighlightSmall")
    frame.warnText:SetPoint("TOPLEFT", frame.capText, "BOTTOMLEFT", 0, -3)

    -- Buff controls
    frame.warModeCheck = MakeCheckbox(summary, L["BUFF_WARMODE"], L["BUFF_WARMODE_DESC"],
        function() return ns.Estimator:WarModeActive() end,
        function(value) ns.db.profile.buffs.warMode = value and "on" or "off" end)
    frame.warModeCheck:SetPoint("TOPLEFT", frame.warnText, "BOTTOMLEFT", -4, -4)

    -- Detected XP buffs are read off the player rather than ticked, so this is a label,
    -- not a control. Only the total goes on the line: three buff names is far more text
    -- than the row can hold, and it was overlapping everything around it. The names live
    -- in a tooltip, which needs a mouse-enabled frame since fontstrings take no input.
    frame.buffsHover = CreateFrame("Frame", nil, summary)
    frame.buffsHover:SetPoint("LEFT", frame.warModeCheck, "LEFT", 186, 0)
    frame.buffsHover:SetSize(150, 18)
    frame.buffsHover:EnableMouse(true)
    frame.buffsHover:SetScript("OnEnter", function(self)
        local detected = ns.Estimator:DetectedXPBuffs()
        if #detected == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["BUFF_TOOLTIP_TITLE"], 1, 1, 1)
        for _, buff in ipairs(detected) do
            GameTooltip:AddDoubleLine(buff.name or "?", ("+%d%%"):format(buff.pct),
                0.85, 0.85, 0.85, 0.4, 1, 0.4)
        end
        GameTooltip:Show()
    end)
    frame.buffsHover:SetScript("OnLeave", GameTooltip_Hide)

    frame.buffsText = MakeFontString(frame.buffsHover, "GameFontHighlightSmall")
    frame.buffsText:SetPoint("LEFT")
    frame.buffsText:SetWordWrap(false)

    frame.customBox = CreateFrame("EditBox", nil, summary, "InputBoxTemplate")
    frame.customBox:SetSize(40, 20)
    frame.customBox:SetPoint("TOPRIGHT", frame.gainText, "BOTTOMRIGHT", -4, -10)
    frame.customBox:SetAutoFocus(false)
    frame.customBox:SetScript("OnEnterPressed", function(self)
        ns.db.profile.buffs.custom = tonumber(self:GetText()) or 0
        self:ClearFocus()
        ns.Refresh()
    end)
    frame.customBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    frame.customLabel = MakeFontString(summary, "GameFontNormalSmall", "RIGHT")
    frame.customLabel:SetPoint("RIGHT", frame.customBox, "LEFT", -4, 0)
    frame.customLabel:SetText(L["BUFF_CUSTOM"])

    frame.warModeNote = MakeFontString(summary, "GameFontHighlightSmall")
    frame.warModeNote:SetPoint("TOPLEFT", frame.warModeCheck, "BOTTOMLEFT", 4, -2)

    -- Wait list
    frame.waitHeader = MakeFontString(summary, "GameFontNormalSmall")
    frame.waitHeader:SetPoint("TOPLEFT", frame.warModeNote, "BOTTOMLEFT", 0, -6)
    frame.waitHeader:SetText(L["WAITLIST_HEADER"])

    frame.waitRows = {}
    for i = 1, 4 do
        local waitRow = CreateFrame("Frame", nil, summary)
        waitRow:SetHeight(14)
        waitRow:SetPoint("TOPLEFT", frame.waitHeader, "BOTTOMLEFT", 8, -((i - 1) * 14) - 2)
        waitRow:SetPoint("RIGHT", summary, "RIGHT", 0, 0)
        waitRow.left = MakeFontString(waitRow, "GameFontHighlightSmall")
        waitRow.left:SetPoint("LEFT")
        waitRow.right = MakeFontString(waitRow, "GameFontHighlightSmall", "RIGHT")
        waitRow.right:SetPoint("RIGHT")
        frame.waitRows[i] = waitRow
    end

    frame.waitNote = MakeFontString(summary, "GameFontDisableSmall")
    frame.waitNote:SetPoint("TOPLEFT", frame.waitRows[4], "BOTTOMLEFT", -8, -4)
    frame.waitNote:SetPoint("RIGHT", summary, "RIGHT", 0, 0)
    frame.waitNote:SetJustifyH("LEFT")
    frame.waitNote:SetText(L["WAITLIST_FLAT"])
    frame.waitNote:Hide()

    charRows, warbandRows = {}, {}
    ns.RestorePosition(frame, ns.db.profile.window)
    SelectTab("character")
end

--============================================================================
-- Public
--============================================================================

function MainWindow:Refresh()
    if not frame or not frame:IsShown() then return end

    local count, delveHeight
    if frame.tab == "warband" then
        count = LayoutWarbandTab()
        frame.delvePanel:Hide()
        frame.delvePanel:SetHeight(1)
        delveHeight = 0
    else
        count = LayoutCharacterTab()
        UpdateSummary()
        delveHeight = ns.DelvePanel:Refresh()
    end

    -- The summary is anchored to the bottom edge, so its height has to grow with the
    -- window or the wrapped note spills out through the frame border.
    local footer = FOOTER_SPACE
    if frame.tab == "warband" then
        footer = 30
    elseif frame.waitNote:IsShown() then
        footer = footer + math.ceil(frame.waitNote:GetStringHeight()) + 8
    end
    frame.summaryPanel:SetHeight(math.max(1, footer - 24))
    frame.charPanel:SetHeight(math.max(1, count * ROW_HEIGHT))
    frame:SetHeight(HEADER_SPACE + delveHeight + math.max(count, 1) * ROW_HEIGHT + footer)
end

function MainWindow:Show()
    if not frame then Build() end
    frame:Show()
    self:Refresh()
end

function MainWindow:Hide()
    if frame then frame:Hide() end
end

function MainWindow:Toggle()
    if frame and frame:IsShown() then self:Hide() else self:Show() end
end

function MainWindow:ResetPosition()
    if not frame then return end
    local cfg = ns.db.profile.window
    cfg.point, cfg.relPoint, cfg.x, cfg.y = "CENTER", "CENTER", 0, 0
    ns.RestorePosition(frame, cfg)
end

ns.RegisterRefresh(function() MainWindow:Refresh() end)
