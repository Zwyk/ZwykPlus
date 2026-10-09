local _, ZP = ...
local L = ZP.L
local records = setmetatable({}, {__mode = "k"})
local initialized, rebuilding, refreshQueued = false, false, false
local parsedCache, cacheCount, requested = {}, 0, {}
local lastSpellID
local unpackArgs = unpack or table.unpack

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value == value and value >= 0 and value < 1e12
end

local function ID(value)
    return Number(value) and value > 0 and value == math.floor(value)
end

local function String(value)
    return Readable(value) and type(value) == "string" and value ~= ""
end

local function Table(value)
    return Readable(value) and type(value) == "table"
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil, false end
    local ok, value = pcall(fn, ...)
    if ok and Readable(value) then return value, true end
    return nil, false
end

local function Public(tooltip)
    if not Readable(tooltip) or (type(tooltip) ~= "table" and type(tooltip) ~= "userdata") then return false end
    if not Readable(tooltip.IsForbidden) then return false end
    if tooltip.IsForbidden then
        local forbidden, known = Call(tooltip.IsForbidden, tooltip)
        if not known or forbidden ~= false then return false end
    end
    return type(tooltip.AddLine) == "function" and type(tooltip.AddDoubleLine) == "function"
end

local resourceTokens = {[0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY", [6] = "RUNIC_POWER"}
local function ResourceName(cost)
    if String(cost.name) then
        local localized = _G[cost.name]
        return String(localized) and localized or cost.name
    end
    if Number(cost.type) then
        local token = resourceTokens[cost.type]
        if token and String(_G[token]) then return _G[token] end
    end
end

-- Resolve only explicit weapon/swing expressions. Seal totals are their added
-- output, not the white damage of the attacks used to trigger them.
function ZP:ResolveSpellMetrics(metrics, weapon)
    if not Table(metrics) then return end
    if not Table(metrics.components) then return metrics end
    weapon = Table(weapon) and weapon or {}
    local result = {}
    for key, value in pairs(metrics) do result[key] = value end
    result.components, result.damage, result.healing = {}, nil, nil
    for _, source in ipairs(metrics.components) do
        if not Table(source) or not String(source.kind) then return end
        local component = {}
        for key, value in pairs(source) do component[key] = value end
        local total = Number(source.total) and source.total or nil
        if String(source.sealModel) and ZP.ResolveSealModel then
            local model, known = Call(ZP.ResolveSealModel, ZP, source, weapon)
            if not known or not Table(model) or not Number(model.damage) then return nil, "weapon" end
            total = model.damage
            result.modelEstimate, result.modelTalentsUnknown = true, model.talentsUnknown
        end
        if Number(source.weaponCoefficient) then
            local normalized = Readable(source.normalizedWeapon) and source.normalizedWeapon == true
            local average = weapon.damage
            if normalized then average = weapon.normalizedDamage end
            if Readable(source.holyWeapon) and source.holyWeapon == true then average = weapon.holyDamage end
            if not Number(average) then return nil, "weapon" end
            if Readable(source.model) and source.model == "command" then
                if not Number(weapon.holySpellPower) then return nil, "weapon" end
                -- Current Forever Command: native weapon percentage applies to
                -- both the weapon hit and its 0.29 Holy spell-power share.
                average = average + weapon.holySpellPower * 0.29
            end
            total = average * source.weaponCoefficient + (Number(source.flatBonus) and source.flatBonus or 0)
            if Readable(metrics.holyStrike) and metrics.holyStrike == true then
                result.weaponContribution = average * source.weaponCoefficient
                result.flatContribution = Number(source.flatBonus) and source.flatBonus or 0
            end
            result.weaponEstimate = not normalized and not (Readable(source.holyWeapon) and source.holyWeapon == true)
        elseif Number(source.weaponDPSCoefficient) then
            if not Number(weapon.damage) or not Number(weapon.baseSpeed) or weapon.baseSpeed <= 0 then return nil, "weapon" end
            total = weapon.damage / weapon.baseSpeed * source.weaponDPSCoefficient
            result.weaponEstimate = true
        end
        if Readable(source.perSwing) and source.perSwing == true then
            if not Number(total) or not Number(weapon.speed) or weapon.speed <= 0
                or not Number(source.duration) or source.duration <= 0 then return nil, "weapon" end
            local attacks = source.duration / weapon.speed
            if Number(source.procsPerMinute) then
                if not Number(weapon.baseSpeed) or weapon.baseSpeed <= 0 then return nil, "weapon" end
                local chance = math.min(1, source.procsPerMinute * weapon.baseSpeed / 60)
                if Readable(source.model) and source.model == "command" then
                    -- Command's 1 s proc cooldown can skip subsequent auto
                    -- swings under extreme haste. Use the steady-state rate.
                    local skipped = math.max(0, math.ceil(1 / weapon.speed - 0.0000001) - 1)
                    chance = chance / (1 + chance * skipped)
                end
                attacks = attacks * chance
                result.procModel = source.procsPerMinute
            elseif Number(source.procChance) then attacks = attacks * source.procChance end
            total = total * attacks
            result.weaponSpeed, result.sealAttacks = weapon.speed, source.duration / weapon.speed
        end
        if not Number(total) or total <= 0 or (source.kind ~= "damage" and source.kind ~= "healing") then return end
        component.total = total
        result.components[#result.components + 1] = component
        result[source.kind] = (result[source.kind] or 0) + total
    end
    return result
end

function ZP:CalculateSpellMetrics(metrics, info, costs, timing)
    if not Table(metrics) or not Table(info) then return end
    local damage = Number(metrics.damage) and metrics.damage > 0 and metrics.damage or nil
    local healing = Number(metrics.healing) and metrics.healing > 0 and metrics.healing or nil
    if not damage and not healing then return end
    timing = Table(timing) and timing or {}
    local report = {damage = damage, healing = healing, resources = {}, targets = {1}, perTarget = {},
        groundArea = metrics.groundArea, weaponEstimate = metrics.weaponEstimate,
        weaponSpeed = metrics.weaponSpeed, sealAttacks = metrics.sealAttacks,
        conditional = metrics.conditional, partialEffects = metrics.partialEffects,
        modelEstimate = metrics.modelEstimate, modelTalentsUnknown = metrics.modelTalentsUnknown, procModel = metrics.procModel}
    report.holyStrike, report.weaponContribution, report.flatContribution = metrics.holyStrike, metrics.weaponContribution, metrics.flatContribution
    local duration = Number(metrics.duration) and metrics.duration > 0 and metrics.duration or nil
    local channel = Readable(metrics.channel) and metrics.channel == true
        or Readable(timing.channel) and timing.channel == true
    if Table(metrics.components) then
        for _, component in ipairs(metrics.components) do
            if Table(component) and String(component.kind) and (component.kind == "damage" or component.kind == "healing")
                and Readable(component.overtime) and component.overtime == true and Number(component.duration) and component.duration > 0 then
                local key = component.kind .. "Duration"
                report[key] = math.max(report[key] or 0, component.duration)
            end
        end
    elseif Readable(metrics.overtime) and metrics.overtime == true then
        report.damageDuration, report.healingDuration = damage and duration or nil, healing and duration or nil
    end
    report.effectiveSeconds = duration
    if channel then
        report.castSeconds = duration
    elseif Number(info.castTime) and info.castTime > 0 then
        report.castSeconds = info.castTime / 1000
    elseif Number(info.castTime) and info.castTime == 0 then
        local gcd = Readable(timing.gcdSeconds) and timing.gcdSeconds
        if gcd == nil then gcd = 1.5 end
        if Number(gcd) and gcd > 0 then report.castSeconds, report.timingReference = gcd, true end
    end
    if Readable(metrics.aoe) and metrics.aoe == true then report.targets[2] = 4 end
    local cap = ID(metrics.aoeTargetCap) and metrics.aoeTargetCap or 4
    if Table(costs) then
        local active = false
        for _, cost in ipairs(costs) do
            if not Table(cost) then report.resourceUnknown = true
            elseif not Readable(cost.requiredAuraID) or not Readable(cost.hasRequiredAura) then report.resourceUnknown = true
            elseif cost.requiredAuraID == nil or cost.requiredAuraID == 0 or cost.hasRequiredAura == true then
                active = true
                local name = ResourceName(cost)
                if not Number(cost.cost) or not Number(cost.minCost) or cost.cost ~= cost.minCost
                    or not Number(cost.costPerSec) or cost.costPerSec ~= 0 or not name then report.resourceUnknown = true
                elseif cost.cost > 0 then report.resources[#report.resources + 1] = {name = name, cost = cost.cost} end
            end
        end
        report.resourceFree = not report.resourceUnknown and #report.resources == 0 and (active or next(costs) == nil)
        if not active and next(costs) ~= nil then report.resourceUnknown = true end
    else report.resourceUnknown = true end
    for _, targets in ipairs(report.targets) do
        local count = targets == 1 and 1 or math.min(targets, cap)
        local entry = {targets = targets, hitTargets = count, damage = damage and damage * count,
            healing = healing and healing * count, efficiencies = {}}
        if Table(metrics.components) then
            entry.damage, entry.healing = nil, nil
            for _, component in ipairs(metrics.components) do
                if Table(component) and Number(component.total) and String(component.kind)
                    and (component.kind == "damage" or component.kind == "healing") then
                    local hits = Readable(component.aoe) and component.aoe == true and count or 1
                    if ID(component.targetCap) then hits = math.min(hits, component.targetCap) end
                    entry[component.kind] = (entry[component.kind] or 0) + component.total * hits
                end
            end
        end
        if report.castSeconds then
            entry.dps = entry.damage and entry.damage / report.castSeconds
            entry.hps = entry.healing and entry.healing / report.castSeconds
        end
        if report.damageDuration and entry.damage then entry.effectiveDPS = entry.damage / report.damageDuration end
        if report.healingDuration and entry.healing then entry.effectiveHPS = entry.healing / report.healingDuration end
        for _, resource in ipairs(report.resources) do
            entry.efficiencies[#entry.efficiencies + 1] = {name = resource.name, cost = resource.cost,
                dpc = entry.damage and entry.damage / resource.cost, hpc = entry.healing and entry.healing / resource.cost}
        end
        report.perTarget[#report.perTarget + 1] = entry
    end
    return report
end

local function Format(value)
    if not Number(value) then return "--" end
    local text = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
    if L.spellMetricsDecimalSeparator == "," then text = text:gsub("%.", ",") end
    return text
end

local function AddReport(tooltip, report, section)
    tooltip:AddLine(section and L["spellMetricsSection_" .. section] or L.spellMetricsHeader, 0.35, 0.75, 1)
    local one, four = report.perTarget[1], report.perTarget[2]
    if four then
        local label = four.hitTargets < 4 and string.format(L.spellMetricsTargetsCapped, 4, four.hitTargets)
            or string.format(L.spellMetricsTargets, 4)
        tooltip:AddDoubleLine(string.format(L.spellMetricsTargets, 1), label, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
    end
    local function Row(key, value, other, resource)
        if value == nil then return end
        local text = resource and string.format(L[key], resource, Format(value)) or string.format(L[key], Format(value))
        tooltip:AddDoubleLine(text, four and Format(other) or "", 0.75, 0.9, 1, 0.75, 0.9, 1)
    end
    Row("spellMetricsDamage", one.damage, four and four.damage)
    Row("spellMetricsHealing", one.healing, four and four.healing)
    if report.holyStrike and Number(report.weaponContribution) and Number(report.flatContribution)
        and String(L.spellMetricsHolyStrikeBreakdown) then
        tooltip:AddLine(string.format(L.spellMetricsHolyStrikeBreakdown, Format(report.weaponContribution), Format(report.flatContribution)), 0.7, 0.7, 0.7, true)
    end
    Row("spellMetricsEffectiveDPS", one.effectiveDPS, four and four.effectiveDPS)
    Row("spellMetricsEffectiveHPS", one.effectiveHPS, four and four.effectiveHPS)
    Row("spellMetricsCastDPS", one.dps, four and four.dps)
    Row("spellMetricsCastHPS", one.hps, four and four.hps)
    for index, efficiency in ipairs(one.efficiencies) do
        local other = four and four.efficiencies[index]
        Row("spellMetricsDPC", efficiency.dpc, other and other.dpc, efficiency.name)
        Row("spellMetricsHPC", efficiency.hpc, other and other.hpc, efficiency.name)
    end
    if report.resourceFree then tooltip:AddLine(L.spellMetricsFree, 0.7, 0.7, 0.7, true)
    elseif report.resourceUnknown then tooltip:AddLine(L.spellMetricsVariableCost, 0.7, 0.7, 0.7, true) end
    if report.castSeconds then tooltip:AddLine(string.format(L.spellMetricsTiming, Format(report.castSeconds)), 0.7, 0.7, 0.7)
    else tooltip:AddLine(L.spellMetricsNoTiming, 0.7, 0.7, 0.7, true) end
    if report.timingReference then tooltip:AddLine(string.format(L.spellMetricsTimingReference, report.castSeconds), 0.7, 0.7, 0.7, true) end
    if Number(report.weaponSpeed) and Number(report.sealAttacks) then
        tooltip:AddLine(string.format(L.spellMetricsSealAssumption, Format(report.sealAttacks), Format(report.weaponSpeed)), 0.7, 0.7, 0.7, true)
    end
    if report.groundArea then tooltip:AddLine(L.spellMetricsGroundAssumption, 0.7, 0.7, 0.7, true) end
    if report.weaponEstimate then tooltip:AddLine(L.spellMetricsWeaponEstimate, 0.7, 0.7, 0.7, true) end
    if report.holyStrike and String(L.spellMetricsHolyStrikeModel) then tooltip:AddLine(L.spellMetricsHolyStrikeModel, 0.7, 0.7, 0.7, true) end
    if report.conditional == "unstunned" then tooltip:AddLine(L.spellMetricsUnstunned, 0.7, 0.7, 0.7, true) end
    if report.partialEffects then tooltip:AddLine(L.spellMetricsPartialEffects, 0.7, 0.7, 0.7, true) end
    if report.modelEstimate then tooltip:AddLine(L.spellMetricsSealModel, 0.7, 0.7, 0.7, true) end
    if report.modelTalentsUnknown then tooltip:AddLine(L.spellMetricsTalentUnknown, 0.7, 0.7, 0.7, true) end
    if Number(report.procModel) then tooltip:AddLine(string.format(L.spellMetricsProcModel, Format(report.procModel)), 0.7, 0.7, 0.7, true) end
    tooltip:AddLine(L.spellMetricsEstimateNote, 0.65, 0.65, 0.65, true)
    tooltip:Show()
end

local function SpellInfo(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = Call(C_Spell.GetSpellInfo, id)
        if Table(info) and String(info.name) then return info end
        return
    end
    if GetSpellInfo then
        local ok, name, _, _, castTime = pcall(GetSpellInfo, id)
        if ok and String(name) then return {name = name, castTime = castTime} end
    end
end

local function GCD(id)
    if GetSpellBaseCooldown then
        local ok, _, gcd = pcall(GetSpellBaseCooldown, id)
        if ok and Number(gcd) and gcd <= 10000 then return gcd / 1000 end
    end
    return 1.5
end

function ZP:GetSpellWeaponContext(needDamage)
    local weapon = {}
    if UnitAttackSpeed then
        local ok, speed = pcall(UnitAttackSpeed, "player")
        if ok and Number(speed) and speed > 0 then weapon.speed = speed end
    end
    if not needDamage then return weapon end
    local power = Call(GetSpellBonusDamage, 2)
    if Number(power) then weapon.holySpellPower = power end
    local link = Call(GetInventoryItemLink, "player", 16)
    if not String(link) or not UnitDamage then return weapon end
    local ok, low, high, _, _, positiveDamage, negativeDamage, multiplier = pcall(UnitDamage, "player")
    if not ok or not Number(low) or not Number(high) or high < low then return weapon end
    -- UnitDamage already includes attack power, flat buffs and multipliers.
    weapon.damage = (low + high) / 2
    weapon.low, weapon.high = low, high
    if Readable(positiveDamage) and type(positiveDamage) == "number" then weapon.positiveDamage = positiveDamage end
    if Readable(negativeDamage) and type(negativeDamage) == "number" then weapon.negativeDamage = negativeDamage end
    if Number(multiplier) then weapon.multiplier = multiplier end
    if Number(multiplier) and multiplier > 0 then weapon.holyDamage = weapon.damage / multiplier end
    if not Number(multiplier) or multiplier <= 0 then return weapon end
    local itemAPI = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if type(itemAPI) ~= "function" then return weapon end
    local itemOK, _, _, _, location, _, class, subclass = pcall(itemAPI, link)
    if not itemOK or not Readable(location) or not Number(class) or not Number(subclass) or class ~= 2 then return weapon end
    weapon.itemLink, weapon.itemLocation, weapon.itemSubclass = link, location, subclass
    local normalizedSpeed
    if subclass == 15 then normalizedSpeed = 1.7
    elseif location == "INVTYPE_2HWEAPON" then normalizedSpeed = 3.3
    elseif location == "INVTYPE_WEAPON" or location == "INVTYPE_WEAPONMAINHAND" then normalizedSpeed = 2.4 end
    if not normalizedSpeed then return weapon end
    weapon.normalizedSpeed = normalizedSpeed
    weapon.twoHand = location == "INVTYPE_2HWEAPON"
    -- Equipped item tooltip speed is the base weapon delay. UnitAttackSpeed is
    -- hasted and must not be used to remove the weapon's AP contribution.
    local data = C_TooltipInfo and Call(C_TooltipInfo.GetInventoryItem, "player", 16)
    if not Table(data) or not Table(data.lines) then return weapon end
    local baseSpeed
    for index, line in ipairs(data.lines) do
        if index > 60 or not Table(line) then return weapon end
        local text = line.rightText
        if not Readable(text) then return weapon end
        if String(text) then
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local speed = text:match("^%s*Speed%s+(%d+[.,]%d+)%s*$")
                or text:match("^%s*Vitesse%s+(%d+[.,]%d+)%s*$")
            if speed then baseSpeed = tonumber((speed:gsub(",", "."))); break end
        end
    end
    if not Number(baseSpeed) or baseSpeed <= 0 then return weapon end
    weapon.baseSpeed = baseSpeed
    if not UnitAttackPower then return weapon end
    local powerOK, base, positive, negative = pcall(UnitAttackPower, "player")
    local function Signed(value)
        return Readable(value) and type(value) == "number" and value == value and math.abs(value) < 1e12
    end
    if not powerOK or not Signed(base) or not Signed(positive) or not Signed(negative) then return weapon end
    local attackPower = base + positive + negative
    if attackPower < 0 then return weapon end
    weapon.attackPower, weapon.baseAttackPower, weapon.positiveAttackPower, weapon.negativeAttackPower = attackPower, base, positive, negative
    -- Holy Strike converts normalized weapon output to Holy damage; a physical
    -- damage-only multiplier on the character-sheet hit must not carry over.
    local average = weapon.damage / multiplier + attackPower / 14 * (normalizedSpeed - baseSpeed)
    if Number(average) then weapon.normalizedDamage = average end
    return weapon
end

local function Description(data, id)
    local parts, channel = {}, false
    if data ~= nil then
        if not Table(data) or not Readable(data.type) or data.type ~= Enum.TooltipDataType.Spell then return end
        if not Readable(data.lines) then return end
        if data.lines ~= nil then
            if not Table(data.lines) then return end
            local descriptionType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.SpellDescription or 34
            for index, line in ipairs(data.lines) do
                if index > 60 then return end
                if not Table(line) or not Readable(line.type) then return end
                if line.type == descriptionType then
                    if not String(line.leftText) then return end
                    parts[#parts + 1] = line.leftText
                else
                    for _, key in ipairs({"leftText", "rightText"}) do
                        local text = line[key]
                        if String(text) then
                            text = text:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                            if text:find("channelled", 1, true) or text:find("channeled", 1, true)
                                or text:find("channeling", 1, true) or text:find("canalis", 1, true) then channel = true end
                        elseif not Readable(text) then return end
                    end
                end
            end
        end
    end
    if #parts > 0 then return table.concat(parts, " "), channel end
    local description
    if C_Spell and C_Spell.GetSpellDescription then description = Call(C_Spell.GetSpellDescription, id)
    else description = Call(GetSpellDescription, id) end
    if String(description) then return description, channel end
end

local function Parse(description, id, name)
    local locale = Call(GetLocale)
    if not String(locale) then return end
    local key = locale .. "\031" .. tostring(id) .. "\031" .. description
    if parsedCache[key] ~= nil then return parsedCache[key] or nil end
    local metrics = Call(ZP.ParseSpellMetrics, ZP, description, {spellID = id, spellName = name})
    if cacheCount >= 128 then parsedCache, cacheCount = {}, 0 end
    parsedCache[key], cacheCount = metrics or false, cacheCount + 1
    return metrics
end

local function StoreSource(record, getter, args)
    if not String(getter) or not Table(args) then return end
    local setter = "Set" .. getter:sub(4)
    if getter:sub(1, 3) ~= "Get" or not record.tooltip[setter] then return end
    local count = args.n
    if not Number(count) then count = #args end
    if count > 10 then return end
    local copy = {n = count}
    for index = 1, count do
        if not Readable(args[index]) then return end
        copy[index] = args[index]
    end
    record.setter, record.args = setter, copy
end

local function Costs(id)
    if C_Spell and C_Spell.GetSpellPowerCost then return Call(C_Spell.GetSpellPowerCost, id) end
    return Call(GetSpellPowerCost, id)
end

local function NeedsWeaponDamage(metrics)
    if not Table(metrics) or not Table(metrics.components) then return false end
    for _, component in ipairs(metrics.components) do
        if Table(component) and (Number(component.weaponCoefficient) or Number(component.weaponDPSCoefficient)
            or Number(component.procsPerMinute) or String(component.sealModel)) then return true end
    end
    return false
end

-- On-demand diagnostics use the same public inputs as the tooltip calculation.
-- Never stringify inaccessible values, including individual cost/tooltip fields.
function ZP:GetSpellMetricsDiagnostics(spellID)
    local id = spellID
    if Readable(id) and id == nil then id = lastSpellID or 10333 end
    local lines = {}
    local function Text(value)
        if not Readable(value) then return "private" end
        if value == nil then return "unavailable" end
        if type(value) == "number" then
            if value ~= value or math.abs(value) >= 1e12 then return "invalid" end
            return string.format("%.8g", value)
        end
        if type(value) == "boolean" then return value and "yes" or "no" end
        if type(value) ~= "string" then return "unavailable" end
        return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[\r\n]", " "):sub(1, 2400)
    end
    local function Line(key, value) lines[#lines + 1] = key .. "=" .. Text(value) end
    if not ID(id) then Line("spellID", id); return lines end
    local info = SpellInfo(id)
    Line("spellID", id)
    if Table(info) then
        Line("name", info.name)
        Line("castTimeMs", info.castTime)
    else Line("name", nil); Line("castTimeMs", nil) end
    Line("gcdReferenceSeconds", GCD(id))
    local data
    if Public(GameTooltip) then
        local current = Call(GameTooltip.GetTooltipData, GameTooltip)
        if Table(current) and ID(current.id) and current.id == id and Readable(current.type)
            and Enum and Enum.TooltipDataType and current.type == Enum.TooltipDataType.Spell then data = current end
    end
    local nativeKnown = true
    if data == nil and C_TooltipInfo and C_TooltipInfo.GetSpellByID then data, nativeKnown = Call(C_TooltipInfo.GetSpellByID, id) end
    local description, channel
    if nativeKnown then description, channel = Description(data, id) end
    Line("nativeDescription", description)
    local apiDescription
    if C_Spell and C_Spell.GetSpellDescription then apiDescription = Call(C_Spell.GetSpellDescription, id)
    else apiDescription = Call(GetSpellDescription, id) end
    Line("apiDescription", apiDescription)
    local metrics = Table(info) and String(description) and Parse(description, id, info.name)
    Line("parsed", Table(metrics))
    local weapon = self:GetSpellWeaponContext(true)
    for _, key in ipairs({"itemLink", "itemLocation", "itemSubclass", "low", "high", "positiveDamage", "negativeDamage", "multiplier",
        "damage", "holyDamage", "speed", "baseSpeed", "normalizedSpeed", "baseAttackPower", "positiveAttackPower", "negativeAttackPower",
        "attackPower", "holySpellPower", "normalizedDamage"}) do Line("weapon." .. key, weapon[key]) end
    local costs = Costs(id)
    if Table(costs) then
        for index, cost in ipairs(costs) do
            if index > 8 then break end
            if Table(cost) then
                for _, key in ipairs({"name", "type", "cost", "minCost", "costPercent", "costPerSec", "requiredAuraID", "hasRequiredAura"}) do
                    Line("cost" .. index .. "." .. key, cost[key])
                end
            else Line("cost" .. index, cost) end
        end
        if next(costs) == nil then Line("costs", "empty (free)") end
    else Line("costs", costs) end
    if not Table(metrics) then return lines end
    local function Output(part, label, partID, partInfo)
        if not Table(part) then return end
        if Table(part.components) then
            for index, component in ipairs(part.components) do
                if index > 8 then break end
                if Table(component) then
                    for _, key in ipairs({"kind", "weaponCoefficient", "nativeFlatBonus", "flatBonus", "normalizedWeapon", "total", "duration"}) do
                        Line(label .. ".component" .. index .. "." .. key, component[key])
                    end
                    if Readable(part.holyStrike) and part.holyStrike == true and Number(weapon.normalizedDamage)
                        and Number(component.weaponCoefficient) and Number(component.nativeFlatBonus) then
                        Line(label .. ".literalTooltipAlternative", weapon.normalizedDamage * component.weaponCoefficient + component.nativeFlatBonus)
                    end
                end
            end
        end
        local resolved, reason = self:ResolveSpellMetrics(part, weapon)
        Line(label .. ".resolveReason", reason or "ok")
        local report = resolved and self:CalculateSpellMetrics(resolved, partInfo or {}, Costs(partID), {channel = channel, gcdSeconds = GCD(partID)})
        if not Table(report) then Line(label .. ".report", "unavailable"); return end
        for _, key in ipairs({"damage", "healing", "weaponContribution", "flatContribution", "castSeconds", "damageDuration", "healingDuration"}) do
            Line(label .. "." .. key, report[key])
        end
        for _, target in ipairs(report.perTarget) do
            for _, key in ipairs({"damage", "healing", "dps", "hps", "effectiveDPS", "effectiveHPS"}) do
                if target[key] ~= nil then Line(label .. ".targets" .. target.targets .. "." .. key, target[key]) end
            end
        end
    end
    if Table(metrics.sections) then
        for _, section in ipairs(metrics.sections) do
            if Table(section) and String(section.kind) and (section.kind == "seal" or section.kind == "judgement") then
                local partID = section.kind == "judgement" and 20271 or id
                Output(section.metrics, section.kind, partID, SpellInfo(partID))
            end
        end
    else Output(metrics, "output", id, info) end
    return lines
end

local HookTooltip
local function Handle(tooltip, data, sourceID)
    if not Public(tooltip) then return end
    HookTooltip(tooltip)
    local record = records[tooltip]
    local getter = tooltip.GetProcessingTooltipInfo or tooltip.GetPrimaryTooltipInfo
    local info = Call(getter, tooltip)
    if Table(info) then StoreSource(record, info.getterName, info.getterArgs) end
    if not (ZP.db and ZP.db.spellTooltipMetrics) or record.added then return end
    if data ~= nil and not Table(data) then return end
    if Table(data) and (not Readable(data.type) or data.type ~= Enum.TooltipDataType.Spell) then return end
    local id = sourceID
    if Table(data) then id = data.id end
    if not ID(id) then return end
    lastSpellID = id
    local spell = SpellInfo(id)
    if not spell then
        if not requested[id] and C_Spell and C_Spell.RequestLoadSpellData then
            requested[id] = true
            pcall(C_Spell.RequestLoadSpellData, id)
        end
        return
    end
    local description, channel = Description(data, id)
    if not description then return end
    local metrics = Parse(description, id, spell.name)
    if not metrics then return end
    if Table(metrics.sections) then
        local reports = {}
        for _, section in ipairs(metrics.sections) do
            if Table(section) and (section.kind == "seal" or section.kind == "judgement") then
                local resolved, reason = ZP:ResolveSpellMetrics(section.metrics, ZP:GetSpellWeaponContext(NeedsWeaponDamage(section.metrics)))
                local sectionID = section.kind == "judgement" and 20271 or id
                local sectionInfo = section.kind == "judgement" and (SpellInfo(sectionID) or {}) or spell
                local report = resolved and ZP:CalculateSpellMetrics(resolved, sectionInfo, Costs(sectionID), {gcdSeconds = GCD(sectionID)})
                reports[#reports + 1] = {kind = section.kind, report = report, unsupported = section.unsupported or reason or "unavailable"}
            end
        end
        if #reports == 0 then return end
        record.added = true
        tooltip:AddLine(L.spellMetricsHeader, 0.35, 0.75, 1)
        for _, section in ipairs(reports) do
            if section.report then AddReport(tooltip, section.report, section.kind)
            else
                tooltip:AddLine(L["spellMetricsSection_" .. section.kind], 0.35, 0.75, 1)
                tooltip:AddLine(L["spellMetricsUnsupported_" .. section.unsupported] or L.spellMetricsUnsupported_unavailable, 0.7, 0.7, 0.7, true)
            end
        end
        tooltip:Show()
        return
    end
    local resolved = ZP:ResolveSpellMetrics(metrics, ZP:GetSpellWeaponContext(NeedsWeaponDamage(metrics)))
    local report = resolved and ZP:CalculateSpellMetrics(resolved, spell, Costs(id), {channel = channel, gcdSeconds = GCD(id)})
    if not report then return end
    record.added = true
    AddReport(tooltip, report)
end

local function SetterID(method, args)
    if method == "SetSpellByID" then return ID(args[1]) and args[1] end
    if method == "SetSpellBookItem" then
        if not ID(args[1]) or not Readable(args[2]) then return end
        if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
            local info = Call(C_SpellBook.GetSpellBookItemInfo, args[1], args[2])
            if Table(info) and ID(info.spellID) then return info.spellID end
            return
        end
        if GetSpellBookItemInfo then
            local ok, kind, id = pcall(GetSpellBookItemInfo, args[1], args[2])
            if ok and String(kind) and kind:lower() == "spell" and ID(id) then return id end
        end
    elseif method == "SetAction" and GetActionInfo then
        if not ID(args[1]) then return end
        local ok, kind, id = pcall(GetActionInfo, args[1])
        if not ok or not String(kind) or not ID(id) then return end
        if kind == "spell" then return id end
        if kind == "macro" and GetMacroSpell then
            local macroOK, first, _, third = pcall(GetMacroSpell, id)
            if macroOK then return ID(first) and first or ID(third) and third end
        end
    elseif method == "SetHyperlink" and String(args[1]) then
        local id = tonumber(args[1]:match("^spell:(%d+)"))
        if ID(id) then return id end
    end
end

HookTooltip = function(tooltip)
    if records[tooltip] or not Public(tooltip) or not tooltip.HookScript then return end
    local record = {tooltip = tooltip}
    records[tooltip] = record
    tooltip:HookScript("OnTooltipCleared", function() record.added, record.setter, record.args = nil, nil, nil end)
    if not hooksecurefunc then return end
    for _, method in ipairs({"SetSpellByID", "SetSpellBookItem", "SetAction", "SetHyperlink"}) do
        if type(tooltip[method]) == "function" then
            hooksecurefunc(tooltip, method, function(self, ...)
                if not Public(self) then return end
                local args = {n = select("#", ...), ...}
                StoreSource(record, "Get" .. method:sub(4), args)
                if record.added then return end
                local id = SetterID(method, args)
                if not ID(id) then return end
                local data, known = Call(self.GetTooltipData, self)
                if self.GetTooltipData and not known then return end
                if data == nil and C_TooltipInfo and C_TooltipInfo.GetSpellByID then
                    local native, accessible = Call(C_TooltipInfo.GetSpellByID, id)
                    if not accessible then return end
                    data = native
                end
                Handle(self, data, id)
            end)
        end
    end
end

function ZP:RefreshSpellTooltips()
    if rebuilding then return end
    rebuilding = true
    for tooltip, record in pairs(records) do
        if Public(tooltip) and record.setter and record.args then
            local shown = Call(tooltip.IsShown, tooltip)
            if shown == true then pcall(tooltip[record.setter], tooltip, unpackArgs(record.args, 1, record.args.n)) end
        end
    end
    rebuilding = false
end

local function QueueRefresh()
    if refreshQueued then return end
    local showing = false
    for tooltip, record in pairs(records) do
        if record.setter and Public(tooltip) and Call(tooltip.IsShown, tooltip) == true then showing = true; break end
    end
    if not showing then return end
    if C_Timer and type(C_Timer.After) == "function" then
        refreshQueued = true
        C_Timer.After(0.1, function() refreshQueued = false; ZP:RefreshSpellTooltips() end)
    else ZP:RefreshSpellTooltips() end
end

function ZP:InitializeSpellTooltips()
    if initialized then return end
    initialized = true
    HookTooltip(GameTooltip)
    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data) Handle(tooltip, data) end)
    end
    local events = CreateFrame("Frame")
    for _, event in ipairs({"SPELL_TEXT_UPDATE", "SPELL_DATA_LOAD_RESULT", "SPELLS_CHANGED",
        "PLAYER_EQUIPMENT_CHANGED", "UNIT_SPELL_HASTE", "UNIT_AURA", "UNIT_ATTACK_SPEED", "UNIT_DAMAGE", "UNIT_ATTACK_POWER"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" or event == "UNIT_SPELL_HASTE" or event == "UNIT_ATTACK_SPEED"
            or event == "UNIT_DAMAGE" or event == "UNIT_ATTACK_POWER" then
            if not Readable(unit) or unit ~= "player" then return end
        end
        if event == "SPELL_DATA_LOAD_RESULT" and ID(unit) then requested[unit] = nil end
        QueueRefresh()
    end)
end
