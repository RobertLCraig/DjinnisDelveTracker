--[[
    Djinni's Delve Tracker - Catalogue

    The account-wide set of known Delver's Call quests. Seeded from Data/Quests.lua and
    extended at runtime by the Scanner (DECISIONS D1), so a patch that adds delves needs
    no code change.
]]

local ADDON_NAME, ns = ...

local Catalogue = {}
ns.Catalogue = Catalogue

--============================================================================
-- Localised title prefix
--
-- Every one of these quests is titled "<prefix>: <delve name>". Rather than keep a
-- translation table, we read the prefix off a seed quest's own localised title. One
-- seed resolving is enough, and it survives Blizzard rewording the quests.
--============================================================================

local cachedPrefix

function Catalogue:Prefix()
    if cachedPrefix then return cachedPrefix end
    for _, q in ipairs(ns.SEED_QUESTS) do
        local title = C_QuestLog.GetTitleForQuestID(q.id)
        if title then
            local prefix = title:match("^(.-):%s")
            if prefix and prefix ~= "" then
                cachedPrefix = prefix
                return cachedPrefix
            end
        end
    end
    return nil
end

-- Does this title belong to the Delver's Call family?
function Catalogue:TitleMatches(title)
    if not title then return false end
    local prefix = self:Prefix()
    if not prefix then return false end
    return title:sub(1, #prefix + 1) == prefix .. ":"
end

--============================================================================
-- Entries
--============================================================================

local function Entries()
    return ns.db and ns.db.global and ns.db.global.catalogue
end

function Catalogue:Get(questID)
    local all = Entries()
    return all and all[questID]
end

-- Record a quest, or refresh the cached title on one we already have.
-- Returns true when this was the first time we had seen it.
function Catalogue:Remember(questID, title, seeded)
    local all = Entries()
    if not all or not questID then return false end

    local entry = all[questID]
    local isNew = false
    if not entry then
        entry = { seeded = seeded or false, firstSeen = time() }
        all[questID] = entry
        isNew = true
    end

    title = title or C_QuestLog.GetTitleForQuestID(questID)
    if title and title ~= "" then
        entry.title = title
        entry.delve = title:match(":%s*(.+)$") or title
    end

    return isNew
end

-- Seed the ten known quests at load. Titles are usually not available this early, so
-- ask the client for the data and let Scanner's QUEST_DATA_LOAD_RESULT handler fill
-- in the real names; the English fallback keeps the list usable meanwhile.
function Catalogue:SeedFromData()
    local all = Entries()
    if not all then return end

    for _, q in ipairs(ns.SEED_QUESTS) do
        local entry = all[q.id]
        if not entry then
            entry = { seeded = true, firstSeen = time(), delve = q.delve }
            all[q.id] = entry
        end
        entry.seeded = true
        if not entry.title then
            entry.delve = entry.delve or q.delve
        end
    end
    self:RequestMissingTitles()
end

function Catalogue:RequestMissingTitles()
    local all = Entries()
    if not all or not C_QuestLog.RequestLoadQuestByID then return end
    for questID, entry in pairs(all) do
        if not entry.title then
            local title = C_QuestLog.GetTitleForQuestID(questID)
            if title and title ~= "" then
                entry.title = title
                entry.delve = title:match(":%s*(.+)$") or title
            else
                C_QuestLog.RequestLoadQuestByID(questID)
            end
        end
    end
end

function Catalogue:DisplayName(questID)
    local entry = self:Get(questID)
    if entry and entry.delve then return entry.delve end
    if entry and entry.title then return entry.title end
    return "Quest " .. tostring(questID)
end

function Catalogue:Count()
    local n = 0
    for _ in pairs(Entries() or {}) do n = n + 1 end
    return n
end

-- Stable alphabetical order by delve name, so rows do not jump around between
-- refreshes. Sorting by state happens in the UI, on top of this.
function Catalogue:Ordered()
    local out = {}
    for questID in pairs(Entries() or {}) do out[#out + 1] = questID end
    table.sort(out, function(a, b)
        local na, nb = Catalogue:DisplayName(a), Catalogue:DisplayName(b)
        if na == nb then return a < b end
        return na < nb
    end)
    return out
end
