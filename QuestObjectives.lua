local _, ZP = ...
local cache, readyAPI, updateAPI, onChanged = {}, nil, nil, nil

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Table(value)
    return Readable(value) and type(value) == "table"
end

local function String(value)
    return Readable(value) and type(value) == "string" and value ~= ""
end

local function ID(value)
    return Readable(value) and type(value) == "number" and value > 0
        and value < math.huge and value == math.floor(value)
end

local function Name(value)
    if not String(value) then return end
    value = value:match("^%s*(.-)%s*$")
    if value == "" or #value > 160 or value:find("[%c%[%]|/\\]") then return end
    return value
end

local function Call(func, ...)
    if type(func) ~= "function" then return end
    local ok, value = pcall(func, ...)
    if ok and Readable(value) then return value end
end

local function Module(name)
    if not Table(QuestieLoader) then return end
    local module = Call(QuestieLoader.ImportModule, QuestieLoader, name)
    if Table(module) then return module end
end

local function Provider()
    if not Table(Questie) then return end
    if Table(Questie.API) and (not Readable(Questie.API.isReady)
        or (Questie.API.isReady ~= nil and Questie.API.isReady ~= true)) then return end
    local locale = Module("l10n")
    local providerLocale = locale and Call(locale.GetUILocale, locale)
    local clientLocale = Call(GetLocale)
    if String(providerLocale) and String(clientLocale) and providerLocale ~= clientLocale then return end
    local db = Module("QuestieDB")
    if db and type(db.GetQuest) == "function" and type(db.QueryNPCSingle) == "function" then return db end
end

local function Description(text)
    if not String(text) or #text > 500 or text:find("%c") then return end
    local lib = Module("QuestieLib")
    local description = lib and Call(lib.GetFullObjectiveText, text)
    if not String(description) then
        -- Classic uses a trailing counter; Forever can put it before the name.
        description = text:match("^(.-)%s*:%s*%d+%s*/%s*%d+%s*$")
            or text:match("^(.-)%s*：%s*%d+%s*/%s*%d+%s*$")
            or text:match("^%s*%d+%s*/%s*%d+%s+(.+)$") or text
    end
    return description:match("^%s*(.-)%s*$"):gsub("%s+", " ")
end

local function Matches(text, description)
    return String(text) and Description(text) == description
end

local function CurrentArea()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local mapID = Call(C_Map.GetBestMapForUnit, "player")
    local zones = ID(mapID) and Module("ZoneDB")
    local areaID = zones and Call(zones.GetAreaIdByUiMapId, zones, mapID)
    if ID(areaID) then return areaID end
end

local function Item(db, itemID)
    local item = Call(db.GetItem, db, itemID)
    if Table(item) then return item end
end

local function ItemField(db, itemID, key)
    local value = Call(db.QueryItemSingle, itemID, key)
    if value ~= nil then return value end
    local item = Item(db, itemID)
    return item and item[key]
end

local function DataMatches(db, data, description)
    if not Table(data) or not String(data.Type) then return false end
    if Matches(data.Text, description) then return true end
    if data.Type == "item" and ID(data.Id) then
        return Matches(ItemField(db, data.Id, "name"), description)
    end
    if data.Type == "monster" and ID(data.Id) then
        local npcName = Name(Call(db.QueryNPCSingle, data.Id, "name"))
        if npcName then
            if description == npcName then return true end
            for _, suffix in ipairs({" slain", " killed", " tué", " tués", " tuée", " tuées", " tué(s)"}) do
                if description == npcName .. suffix then return true end
            end
        end
    end
    return false
end

local function FindData(db, quest, description, kind)
    if not Table(quest.ObjectiveData) then return end
    -- Questie copies ObjectiveData[index].Id into runtime rows, then replaces
    -- their descriptions with native text. That description cannot validate the
    -- copied ID. Match the DB's own text/entity name instead of trusting order.
    local found
    for _, data in pairs(quest.ObjectiveData) do
        if Table(data) and Readable(data.Type) and ((kind == "item" and data.Type == "item")
            or (kind == "monster" and (data.Type == "monster" or data.Type == "killcredit"))
            or (kind == "killcredit" and data.Type == "killcredit")) and DataMatches(db, data, description) then
            -- Equal text naming different objectives is ambiguous; leave that line unchanged.
            if found and (found ~= data) then return end
            found = data
        end
    end
    return found
end

local function AddIDs(ids, values)
    if not Table(values) then return end
    for _, npcID in pairs(values) do if ID(npcID) then ids[npcID] = true end end
end

local function Candidates(db, ids, areaID, itemID)
    local candidates, names = {}, {}
    for npcID in pairs(ids) do
        local name = Name(Call(db.QueryNPCSingle, npcID, "name"))
        if name then
            local spawns = Call(db.QueryNPCSingle, npcID, "spawns")
            local nearby = areaID and Table(spawns) and Table(spawns[areaID]) and next(spawns[areaID]) ~= nil or false
            local candidate = names[name]
            if not candidate then
                candidate = {name = name, npcID = npcID, npcIDs = {}, inCurrentZone = nearby, source = "Questie", itemID = itemID}
                names[name], candidates[#candidates + 1] = candidate, candidate
            end
            candidate.npcID = math.min(candidate.npcID, npcID)
            candidate.npcIDs[#candidate.npcIDs + 1] = npcID
            candidate.inCurrentZone = candidate.inCurrentZone or nearby
        end
    end
    table.sort(candidates, function(a, b)
        if a.inCurrentZone ~= b.inCurrentZone then return a.inCurrentZone end
        return a.npcID < b.npcID
    end)
    for _, candidate in ipairs(candidates) do table.sort(candidate.npcIDs) end
    while #candidates > 80 do candidates[#candidates] = nil end
    if #candidates > 0 then return candidates end
end

function ZP:InvalidateQuestObjectives(questID)
    if ID(questID) then cache[questID] = nil else cache = {} end
end

function ZP:InitializeQuestObjectives(callback)
    if type(callback) == "function" then onChanged = callback end
    local api = Table(Questie) and Table(Questie.API) and Questie.API
    if not api then return end
    local function Changed(questID)
        ZP:InvalidateQuestObjectives(questID)
        if onChanged then onChanged() end
    end
    if api ~= readyAPI and type(api.RegisterOnReady) == "function" then
        readyAPI = api
        if not pcall(api.RegisterOnReady, function() Changed() end) then readyAPI = nil end
    end
    if api ~= updateAPI and type(api.RegisterForQuestUpdates) == "function" then
        updateAPI = api
        if not pcall(api.RegisterForQuestUpdates, Changed) then updateAPI = nil end
    end
end

-- The returned arrays belong to the resolver cache; consumers must not modify them.
function ZP:ResolveQuestObjective(questID, objectiveIndex, text, kind)
    if not ID(questID) or not ID(objectiveIndex) or not String(kind)
        or (kind ~= "item" and kind ~= "monster" and kind ~= "killcredit" and kind ~= "event") then return end
    local db, description = Provider(), Description(text)
    if not db or not description or description == "" then return end
    local areaID = CurrentArea()
    local key = objectiveIndex .. ":" .. kind .. ":" .. description .. ":" .. (areaID or 0)
    cache[questID] = cache[questID] or {}
    local stored = cache[questID][key]
    if stored ~= nil then return stored or nil end
    -- GetQuest is a dot-call in Questie, unlike its GetItem/GetNPC methods.
    local quest = Call(db.GetQuest, questID)
    if not Table(quest) then return end
    local ids, itemID = {}, nil
    local data = FindData(db, quest, description, kind)
    if data then
        if data.Type == "monster" and ID(data.Id) then ids[data.Id] = true
        elseif data.Type == "killcredit" then AddIDs(ids, data.IdList)
        elseif data.Type == "item" and ID(data.Id) then
            itemID = data.Id
            local drops = ItemField(db, itemID, "npcDrops")
            -- GetItem.Sources also contains vendors as "monster" entries. Only
            -- npcDrops establishes that a target can actually drop this item.
            AddIDs(ids, drops)
        end
    end
    if kind == "event" and Table(quest.ObjectiveData) then
        local event = quest.ObjectiveData[objectiveIndex]
        if Table(event) and Readable(event.Type) and event.Type == "event" and Matches(event.Text, description)
            and Table(quest.SpecialObjectives) then
            for _, extra in pairs(quest.SpecialObjectives) do
                if Table(extra) and Readable(extra.RealObjectiveIndex) and extra.RealObjectiveIndex == objectiveIndex
                    and Readable(extra.Type) and extra.Type == "monster" and ID(extra.Id) then ids[extra.Id] = true end
            end
        end
    end
    local result = Candidates(db, ids, areaID, itemID)
    cache[questID][key] = result or false
    return result
end
