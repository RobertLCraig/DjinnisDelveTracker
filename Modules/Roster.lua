--[[
    Djinni's Delve Tracker - Roster

    Account-wide character snapshots, keyed by GUID (DECISIONS D2). Everything here is a
    snapshot: the record for a character you are not logged into is as fresh as the last
    time you played them, and the UI labels it with that time rather than pretending
    otherwise.
]]

local ADDON_NAME, ns = ...

local Roster = {}
ns.Roster = Roster

local function Characters()
    return ns.db and ns.db.global and ns.db.global.characters
end

function Roster:Current()
    local all = Characters()
    local guid = UnitGUID("player")
    return all and guid and all[guid] or nil
end

-- Create or refresh the record for whoever is logged in. Safe to call as often as you
-- like; it is a handful of assignments.
function Roster:EnsureCurrent()
    local all = Characters()
    local guid = UnitGUID("player")
    if not all or not guid then return nil end

    local rec = all[guid]
    if not rec then
        rec = { guid = guid, quests = {} }
        all[guid] = rec
    end
    rec.quests = rec.quests or {}

    local name, realm = UnitFullName("player")
    rec.name    = name or UnitName("player") or "?"
    rec.realm   = realm or GetRealmName()
    rec.class   = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
    rec.level   = UnitLevel("player") or 0
    rec.xp      = UnitXP("player") or 0
    rec.xpMax   = UnitXPMax("player") or 0
    rec.warMode = (C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired()) or false
    rec.updated = time()

    return rec
end

function Roster:Forget(guid)
    local all = Characters()
    if all then all[guid] = nil end
end

function Roster:ForgetAllOthers()
    local all = Characters()
    local guid = UnitGUID("player")
    if not all then return end
    for k in pairs(all) do
        if k ~= guid then all[k] = nil end
    end
end

-- Sorted for display: most banked first, then highest level, then name. The character
-- sitting on the biggest unclaimed stack is the one you want to see at the top.
function Roster:All()
    local out = {}
    for _, rec in pairs(Characters() or {}) do out[#out + 1] = rec end
    table.sort(out, function(a, b)
        local ab, bb = a.banked or 0, b.banked or 0
        if ab ~= bb then return ab > bb end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.name or "") < (b.name or "")
    end)
    return out
end
