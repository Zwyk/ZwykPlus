local _, ZP = ...

-- Forever db4d14ac96f8b7ab2cc9db4fe65eb0cc4b9f847d, sim/core/spell.go
-- and sim/paladin/*.go. Native descriptions are noncritical amounts; current
-- caster crit stats are separate. Outcomes below override parent/trigger DBC
-- differences without treating all periodic effects as equivalent.
local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value == value and value >= 0 and value < 1e12
end

local function Table(value)
    return Readable(value) and type(value) == "table"
end

local function Call(func, ...)
    if type(func) ~= "function" then return end
    local ok, value = pcall(func, ...)
    if ok and Readable(value) then return value end
end

local profiles, seals, lightSeals = {}, {}, {}
local function Family(ids, mode, holyPower, periodic)
    local profile = {mode = mode, holyPower = holyPower, periodic = periodic}
    for _, id in ipairs(ids) do profiles[id] = profile end
end
Family({679, 678, 1866, 680, 2495, 5569, 10332, 10333}, "melee", 3)
Family({1311606, 20473, 20929, 20930, 1311604, 25912, 25911, 25902,
    1311605, 25914, 25913, 25903}, "spell", 3)
Family({635, 639, 647, 1026, 1042, 3472, 10328, 10329, 25292,
    19750, 19939, 19940, 19941, 19942, 19943, 879, 5614, 5615, 10312, 10313, 10314,
    2812, 10318, 429147}, "spell", 1)
Family({24275, 24274, 24239}, "ranged", 1)
Family({26573, 20116, 20922, 20923, 20924, 1280345, 1280346, 1280347, 1280348, 1280349}, "spell", 1, true)
Family({20187, 20280, 20281, 20282, 20283, 20284, 20285, 20286,
    20424, 20467, 20963, 20964, 20965, 20966, 20425, 20962, 20961, 20967, 20968,
    20183, 20231, 20232, 20411, 20412, 20413, 20414, 20415, 20416, 20417, 20418,
    1311647, 1311650, 1311654, 1311655}, "melee", 1, true)
Family({407632}, "melee")
Family({20925, 20927, 20928}, "none") -- Holy Shield hits cannot crit.
for _, id in ipairs({20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293,
    20375, 20915, 20918, 20919, 20920, 1311649, 1311656, 20163, 20419, 20421, 20422, 20423}) do
    seals[id] = true
end
for _, id in ipairs({20165, 20347, 20348, 20349}) do lightSeals[id] = true end

local function PlayerClass()
    if type(UnitClass) ~= "function" then return end
    local ok, _, token = pcall(UnitClass, "player")
    if ok and Readable(token) and type(token) == "string" then return token end
end

local function Profile(component, id, section)
    if not Readable(component.overtime) then return end
    if section == "seal" or section == "judgement" then
        if seals[id] and component.kind == "damage" then return {mode = "melee", holyPower = 1, periodic = true} end
        if lightSeals[id] then return {mode = "none"} end
    end
    local profile = profiles[id]
    local data = ZP.spellCritData or {}
    local triggered = component.overtime and data.periodicTriggered and data.periodicTriggered[id]
    if profile and profile.mode == "none" then return profile end
    if data.cannotCrit and data.cannotCrit[id] and not triggered then return {mode = "none"} end
    if component.overtime then
        if not (profile and profile.periodic or data.periodic and data.periodic[id]
            or data.periodicTriggered and data.periodicTriggered[id]) then return {mode = "none"} end
    end
    if profile then return profile end
    if data.ranged and data.ranged[id] then return {mode = "ranged"} end
    if data.melee and data.melee[id] then return {mode = "melee"} end
    if Number(component.weaponCoefficient) or Number(component.weaponDPSCoefficient) then return {mode = "melee"} end
    return {mode = "spell"}
end

-- Return a fresh result: never put live crit stats or scaled amounts in the
-- cached parser/model object. A mixed hit + DoT is weighted component by component.
function ZP:ApplySpellCritMetrics(metrics, spellID, section)
    if not Table(metrics) or not Number(spellID) or spellID <= 0 then return metrics end
    local sources = metrics.components
    if not Table(sources) then
        sources = {}
        for _, kind in ipairs({"damage", "healing"}) do
            if Number(metrics[kind]) then sources[#sources + 1] = {kind = kind, total = metrics[kind], overtime = metrics.overtime} end
        end
    end
    local result = {}
    for key, value in pairs(metrics) do result[key] = value end
    result.components, result.critComponents = {}, {}
    result.critIncluded, result.critIncomplete = false, false
    result.baseDamage, result.baseHealing = metrics.damage, metrics.healing
    result.damage, result.healing = nil, nil
    local class, rates, holyPower = PlayerClass(), {}, nil
    for index, source in ipairs(sources) do
        if not Table(source) or not Number(source.total) or not Readable(source.kind)
            or (source.kind ~= "damage" and source.kind ~= "healing") then return metrics end
        local component = {}
        for key, value in pairs(source) do component[key] = value end
        local profile = Profile(component, spellID, section)
        local details = {mode = profile and profile.mode or "unknown", kind = source.kind, base = source.total, factor = 1}
        if profile and profile.mode == "none" then
            details.reason = "cannot-crit"
        elseif profile then
            local mode = profile.mode
            if rates[mode] == nil then
                local func
                if mode == "melee" then func = GetCritChance
                elseif mode == "ranged" then func = GetRangedCritChance
                else func = GetSpellCritChance end
                local chance = Call(func)
                rates[mode] = Number(chance) and chance <= 100 and chance or false
            end
            local chance = rates[mode]
            if chance ~= false then
                local bonus = 0
                if profile.holyPower and (class == "PALADIN" or class == nil) then
                    if holyPower == nil then
                        local rank = Call(self.GetSpellMetricTalentRank, self, 5923, 5, "Holy Power", "Puissance sacrée")
                        holyPower = Number(rank) and rank <= 5 and rank == math.floor(rank) and rank or false
                    end
                    if holyPower ~= false then bonus = holyPower * profile.holyPower
                    else result.critIncomplete, details.talentUnknown = true, true end
                end
                details.baseChance, details.bonusChance = chance, bonus
                details.chance, details.multiplier = math.min(100, chance + bonus), mode == "spell" and 1.5 or 2
                details.factor = 1 + details.chance / 100 * (details.multiplier - 1)
                component.total = source.total * details.factor
                result.critIncluded = true
            else result.critIncomplete, details.reason = true, "crit-unavailable" end
        else result.critIncomplete, details.reason = true, "classification-unavailable" end
        result.critComponents[index] = details
        result.components[index] = component
        result[source.kind] = (result[source.kind] or 0) + component.total
    end
    return result
end
