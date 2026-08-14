--[[
    Djinni's Delve Tracker - live delve panel

    Sits above the quest list and only appears while you are inside a delve: objectives
    and their progress, the Sanctified Banner and where it spawns, the treasure reward,
    and Brann's rank and XP.

    Builds its own rows from a pool and reports its height back, so the main window can
    size itself around a section that changes shape constantly.
]]

local ADDON_NAME, ns = ...
local L = ns.L

local DelvePanel = {}
ns.DelvePanel = DelvePanel

local ROW_HEIGHT = 15
local BAR_HEIGHT = 7

local panel, rows, rowCount, yOffset

local DONE_MARK   = "|cff66ff66[+]|r"
local TODO_MARK   = "|cffff6666[ ]|r"
local COLOUR_DONE = { 0.45, 0.9, 0.45 }
local COLOUR_TODO = { 0.85, 0.85, 0.85 }
local COLOUR_GLOW = { 1.0, 0.9, 0.4 }

--============================================================================
-- Row pool
--============================================================================

local function AcquireRow(index)
    local row = rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW_HEIGHT)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.07)

    row.left = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.left:SetPoint("LEFT")
    row.left:SetJustifyH("LEFT")

    row.right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT")
    row.right:SetJustifyH("RIGHT")

    rows[index] = row
    return row
end

local function AddRow(leftText, rightText, leftColour, rightColour, onClick)
    rowCount = rowCount + 1
    local row = AcquireRow(rowCount)

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, yOffset)

    row.left:SetText(leftText or "")
    row.left:SetTextColor(unpack(leftColour or { 1, 1, 1 }))
    row.right:SetText(rightText or "")
    row.right:SetTextColor(unpack(rightColour or { 0.7, 0.7, 0.7 }))

    -- Pooled rows carry stale handlers, so both states are always set explicitly.
    if onClick then
        row:EnableMouse(true)
        row:SetScript("OnClick", onClick)
        row.highlight:SetAlpha(1)
    else
        row:EnableMouse(false)
        row:SetScript("OnClick", nil)
        row.highlight:SetAlpha(0)
    end

    row:Show()
    yOffset = yOffset - ROW_HEIGHT
    return row
end

--============================================================================
-- Sections
--============================================================================

local function AddObjectives(state)
    for _, objective in ipairs(state.objectives) do
        local done = objective.earned
            or (objective.progCur and objective.progMax and objective.progCur >= objective.progMax)
        local colour = done and COLOUR_DONE or (objective.glow and COLOUR_GLOW or COLOUR_TODO)
        local right = objective.progStr
            or (objective.text and objective.text ~= "" and objective.text or nil)
        AddRow((done and DONE_MARK or TODO_MARK) .. " " .. (objective.name or "?"), right, colour)
    end

    -- Criteria are the fallback path, only worth showing when the widget gave us nothing.
    if #state.objectives == 0 then
        for _, crit in ipairs(state.criteria) do
            local right = crit.quantityString ~= "" and crit.quantityString
                or (crit.totalQuantity > 1 and (crit.quantity .. "/" .. crit.totalQuantity) or nil)
            AddRow((crit.completed and DONE_MARK or TODO_MARK) .. " " .. crit.description, right,
                crit.completed and COLOUR_DONE or COLOUR_TODO)
        end
    end
end

local function AddBanner(state)
    if not state.hasBountiful then return end

    AddRow((state.hasBanner and DONE_MARK or TODO_MARK) .. " " .. L["BANNER_LABEL"],
        state.hasBanner and L["BANNER_COLLECTED"] or L["BANNER_AVAILABLE"],
        state.hasBanner and COLOUR_DONE or COLOUR_GLOW,
        state.hasBanner and { 0.4, 1, 0.4 } or { 1, 0.85, 0.4 })

    -- Once it is in hand the spawn list is noise.
    if state.hasBanner then return end

    for _, location in ipairs(ns.DelveState:BannerLocations() or {}) do
        local label = ("    |cff7fb8ff/way %.2f, %.2f|r"):format(location.x * 100, location.y * 100)
        if location.note then label = label .. "  |cff888888(" .. location.note .. ")|r" end
        local x, y = location.x, location.y
        AddRow(label, L["BANNER_SHOW_MAP"], { 0.85, 0.85, 0.85 }, { 0.5, 0.7, 1 },
            function() ns.DelveState:WaypointBanner(x, y) end)
    end
end

local function AddReward(state)
    if state.rewardState == nil or state.rewardState == Enum.UIWidgetRewardShownState.Hidden then
        return
    end
    local earned = (state.rewardState == Enum.UIWidgetRewardShownState.ShownEarned)
    AddRow((earned and DONE_MARK or TODO_MARK) .. " " .. L["REWARD_LABEL"],
        earned and L["REWARD_EARNED"] or L["REWARD_UNEARNED"],
        earned and COLOUR_DONE or COLOUR_TODO,
        earned and { 0.4, 1, 0.4 } or { 1, 0.5, 0.5 })
end

local function AddCompanion(state)
    local info = state.companion
    if not info then return end

    yOffset = yOffset - 4

    local levelText = "Lv " .. info.level
    if info.maxRank and info.maxRank > 0 then levelText = levelText .. " / " .. info.maxRank end

    if info.isMaxLevel then
        AddRow("|cffffd100" .. (info.name or "?") .. "|r  |cffaaaaaa" .. levelText .. "|r",
            L["COMPANION_MAX"], { 1, 0.82, 0 }, COLOUR_DONE)
        return
    end

    AddRow("|cffffd100" .. (info.name or "?") .. "|r  |cffaaaaaa" .. levelText .. "|r",
        ("%s / %s"):format(ns.Comma(info.currentXP), ns.Comma(info.maxXP)),
        { 1, 0.82, 0 }, { 0.85, 0.7, 1 })

    local fraction = math.min(1, math.max(0, info.currentXP / info.maxXP))
    panel.barBG:ClearAllPoints()
    panel.barBG:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset - 2)
    panel.barBG:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    panel.barBG:Show()

    panel.bar:ClearAllPoints()
    panel.bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset - 2)
    panel.bar:SetWidth(math.max(1, (panel:GetWidth() or 400) * fraction))
    panel.bar:Show()

    yOffset = yOffset - BAR_HEIGHT - 5

    AddRow(("|cffaaaaaa%s|r  |cffffffff+%s|r"):format(L["COMPANION_THIS_DELVE"], ns.Comma(info.delveGained)),
        ("|cffaaaaaa%s|r  |cffffffff+%s|r"):format(L["COMPANION_SESSION"], ns.Comma(info.sessionGained)),
        { 0.85, 0.85, 0.85 }, { 0.85, 0.85, 0.85 })
end

--============================================================================
-- Public
--============================================================================

function DelvePanel:Build(parent)
    panel = CreateFrame("Frame", nil, parent)
    panel:SetHeight(1)
    rows = {}

    panel.barBG = panel:CreateTexture(nil, "ARTWORK")
    panel.barBG:SetColorTexture(0.15, 0.15, 0.15, 0.85)
    panel.barBG:SetHeight(BAR_HEIGHT)
    panel.barBG:Hide()

    panel.bar = panel:CreateTexture(nil, "ARTWORK", nil, 1)
    panel.bar:SetColorTexture(0.58, 0.0, 0.82, 0.9)
    panel.bar:SetHeight(BAR_HEIGHT)
    panel.bar:Hide()

    panel.divider = panel:CreateTexture(nil, "ARTWORK")
    panel.divider:SetColorTexture(1, 1, 1, 0.12)
    panel.divider:SetHeight(1)
    panel.divider:Hide()

    return panel
end

-- Rebuild the section and return the height it needs. Zero when not in a delve, which
-- collapses it out of the layout entirely.
function DelvePanel:Refresh()
    if not panel then return 0 end

    for _, row in ipairs(rows) do row:Hide() end
    panel.barBG:Hide()
    panel.bar:Hide()
    panel.divider:Hide()

    local state = ns.DelveState and ns.DelveState:Get()
    if not state or not state.active then
        panel:Hide()
        panel:SetHeight(1)
        return 0
    end

    rowCount, yOffset = 0, 0

    -- Title, with the state of the quest this run will complete.
    local title = state.name or L["DELVE_GENERIC"]
    if state.tier and state.tier ~= "" then
        title = title .. "  |cffaaaaaa(" .. state.tier .. ")|r"
    end
    local questRight, questColour, warning
    if state.questID then
        local rec = ns.Roster:Current()
        local questState = rec and rec.quests[state.questID]
        if questState then
            questRight = ns.STATE_LABEL[questState]
            local colour = ns.STATE_COLOR[questState]
            questColour = { colour.r, colour.g, colour.b }
            -- The whole point of the addon is not wasting a delve run. Running one
            -- without its quest accepted earns nothing, so it gets shouted about.
            if questState == ns.STATE.NOT_STARTED then
                warning = L["DELVE_QUEST_MISSING"]
            elseif questState == ns.STATE.TURNED_IN then
                warning = L["DELVE_QUEST_DONE"]
            end
        end
    else
        questRight = L["DELVE_NO_QUEST"]
        questColour = { 0.6, 0.6, 0.6 }
    end
    AddRow(title, questRight, { 1, 0.82, 0 }, questColour)
    if warning then
        AddRow("|cffff4040" .. warning .. "|r", nil, { 1, 0.25, 0.25 })
    end

    if state.total > 0 then
        AddRow("|cffaaaaaa" .. L["OBJECTIVES"] .. "|r",
            ("%d/%d"):format(state.done, state.total), { 0.67, 0.67, 0.67 })
    end

    AddObjectives(state)
    AddBanner(state)
    AddReward(state)

    if state.total == 0 and #state.criteria == 0 and not state.hasBountiful then
        AddRow("  " .. L["NO_OBJECTIVES"], nil, { 0.5, 0.5, 0.5 })
    end

    AddCompanion(state)

    local height = math.abs(yOffset) + 6
    panel.divider:ClearAllPoints()
    panel.divider:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 2)
    panel.divider:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 2)
    panel.divider:Show()

    panel:SetHeight(height)
    panel:Show()
    return height
end
