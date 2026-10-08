local addonName, ZP = ...

-- Forever model, not the generic speed range printed in the seal tooltip.
-- Data/formula: ElliotWood/Forever 56c11f4e2bc69caa5d7995aaf0ffb0e68466c730,
-- sim/paladin/seal_of_righteousness.go and sim/core/spelldata/spells_auto_gen.go.
-- {base amount, amount per level, minimum level, maximum level, Holy SP share}
local righteousness = {
    [21084] = {108, 18, 1, 7, 0.058},
    [20154] = {108, 18, 1, 7, 0.058},
    [20287] = {216, 17, 10, 16, 0.125},
    [20288] = {352, 23, 18, 24, 0.185},
    [20289] = {541, 31, 26, 32, 0.2},
    [20290] = {785, 37, 34, 40, 0.2},
    [20291] = {1082, 41, 42, 48, 0.2},
    [20292] = {1407, 47, 50, 56, 0.2},
    [20293] = {1786, 47, 58, 64, 0.2},
}

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Number(value)
    if not Readable(value) or type(value) ~= "number" or value ~= value
        or value < 0 or value > 1e10 then return nil end
    return value
end

local function Table(value)
    return Readable(value) and type(value) == "table"
end

local function Call(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, ...)
    if not ok or not Readable(value) then return nil end
    return value
end

local function Rank(value)
    value = Number(value)
    return value and value <= 5 and value == math.floor(value) and value or nil
end

local function ModernTalentRank()
    if not C_ClassTalents or type(C_ClassTalents.GetActiveConfigID) ~= "function" then return nil, false end
    if not C_Traits or type(C_Traits.GetConfigInfo) ~= "function"
        or type(C_Traits.GetTreeNodes) ~= "function" or type(C_Traits.GetNodeInfo) ~= "function"
        or type(C_Traits.GetEntryInfo) ~= "function" or type(C_Traits.GetDefinitionInfo) ~= "function"
        or type(C_Traits.ConfigHasStagedChanges) ~= "function" then return nil, true end
    local configID = Number(Call(C_ClassTalents.GetActiveConfigID))
    if not configID or configID <= 0 then return nil, true end
    -- A staged talent preview must not change estimated combat output.
    if Call(C_Traits.ConfigHasStagedChanges, configID) ~= false then return nil, true end
    local config = Call(C_Traits.GetConfigInfo, configID)
    if not Table(config) or not Table(config.treeIDs) or #config.treeIDs > 8 then return nil, true end
    for _, treeID in ipairs(config.treeIDs) do
        if not Number(treeID) then return nil, true end
        local nodes = Call(C_Traits.GetTreeNodes, treeID)
        if not Table(nodes) or #nodes > 200 then return nil, true end
        for _, nodeID in ipairs(nodes) do
            if not Number(nodeID) then return nil, true end
            local node = Call(C_Traits.GetNodeInfo, configID, nodeID)
            if not Table(node) or not Table(node.entryIDs) or #node.entryIDs > 8 then return nil, true end
            for _, entryID in ipairs(node.entryIDs) do
                if not Number(entryID) then return nil, true end
                local entry = Call(C_Traits.GetEntryInfo, configID, entryID)
                if not Table(entry) then return nil, true end
                local definitionID = Number(entry.definitionID)
                local definition = definitionID and Call(C_Traits.GetDefinitionInfo, definitionID)
                if definitionID and not Table(definition) then return nil, true end
                local spellID = Table(definition) and Number(definition.spellID)
                if spellID == 20224 then
                    -- Improved Seals is a single-entry, five-rank talent in
                    -- this model. Reject a future different tree definition.
                    if #node.entryIDs ~= 1 or Rank(entry.maxRanks) ~= 5 then return nil, true end
                    return Rank(node.activeRank), true
                end
            end
        end
    end
    return nil, true
end

local function LegacyTalentRank()
    if type(GetNumTalentTabs) ~= "function" or type(GetNumTalents) ~= "function"
        or type(GetTalentInfo) ~= "function" then return nil end
    local tabs = Number(Call(GetNumTalentTabs))
    if not tabs or tabs < 1 or tabs > 8 then return nil end
    local localizedName = C_Spell and Call(C_Spell.GetSpellName, 20224)
    for tab = 1, tabs do
        local count = Number(Call(GetNumTalents, tab))
        if not count or count > 60 then return nil end
        for index = 1, count do
            local ok, name, _, _, _, rank, maximum = pcall(GetTalentInfo, tab, index)
            if not ok or not Readable(name) then return nil end
            if type(name) == "string" and (name == "Improved Seals" or name == "Sceaux améliorés"
                or (type(localizedName) == "string" and name == localizedName)) then
                if Rank(maximum) ~= 5 then return nil end
                return Rank(rank)
            end
        end
    end
    return nil
end

local talentCache
function ZP:InvalidateSpellSealModels()
    talentCache = nil
end

local function ImprovedSealsRank()
    local now = Number(Call(GetTime))
    if talentCache and now and now < talentCache.expires then return talentCache.rank end
    local rank, modern = ModernTalentRank()
    -- Do not use legacy data to infer values hidden by a modern API.
    if not modern then rank = LegacyTalentRank() end
    talentCache = {rank = rank, expires = now and now + 30 or 0}
    return rank
end

-- Returns the additional Holy damage per landed noncritical main-hand swing.
-- weapon.baseSpeed is the item's base delay, not UnitAttackSpeed's haste-
-- modified interval. The runtime applies the latter only to swing frequency.
function ZP:ResolveSealModel(component, weapon)
    if not Table(component) or not Readable(component.sealModel) or component.sealModel ~= "righteousness"
        or not Table(weapon) then return nil end
    local spellID = Number(component.spellID)
    local row = spellID and righteousness[spellID]
    local speed = Number(weapon.baseSpeed)
    if not row or not speed or speed <= 0 or speed > 20
        or not Readable(weapon.twoHand) or type(weapon.twoHand) ~= "boolean" then return nil end
    local level = Number(Call(UnitLevel, "player"))
    local power = Number(Call(GetSpellBonusDamage, 2))
    if not level or level < row[3] or level > 100 or not power then return nil end
    local value = row[1] + row[2] * (math.min(level, row[4]) - row[3])
    local multiplier = weapon.twoHand and 1.2 or 0.85
    local damage = value / 100 * speed * multiplier
        + power * row[5] * (weapon.twoHand and 1.2 or 1)
    local rank = ImprovedSealsRank()
    if rank then damage = damage * (1 + rank * 0.03) end
    damage = Number(damage)
    if not damage or damage <= 0 then return nil end
    return {damage = damage, talentsUnknown = rank == nil, improvedSealsRank = rank,
        model = "righteousness", excludesHolyMultipliers = true}
end

if CreateFrame then
    local frame = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
        "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "SPELLS_CHANGED"}) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function() talentCache = nil end)
end
