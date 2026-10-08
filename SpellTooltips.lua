local _, ZP = ...
local L = ZP.L
local records = setmetatable({}, {__mode = "k"})
local initialized, rebuilding, refreshQueued = false, false, false
local parsedCache, cacheCount, requested = {}, 0, {}
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

function ZP:CalculateSpellMetrics(metrics, info, costs, timing)
    if not Table(metrics) or not Table(info) then return end
    local damage = Number(metrics.damage) and metrics.damage > 0 and metrics.damage or nil
    local healing = Number(metrics.healing) and metrics.healing > 0 and metrics.healing or nil
    if not damage and not healing then return end
    timing = Table(timing) and timing or {}
    local report = {damage = damage, healing = healing, resources = {}, targets = {1}, perTarget = {}}
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

local function AddReport(tooltip, report)
    tooltip:AddLine(L.spellMetricsHeader, 0.35, 0.75, 1)
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

local function Parse(description)
    local locale = Call(GetLocale)
    if not String(locale) then return end
    local key = locale .. "\031" .. description
    if parsedCache[key] ~= nil then return parsedCache[key] or nil end
    local metrics = Call(ZP.ParseSpellMetrics, ZP, description)
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
    local metrics = Parse(description)
    if not metrics then return end
    local costs
    if C_Spell and C_Spell.GetSpellPowerCost then costs = Call(C_Spell.GetSpellPowerCost, id)
    else costs = Call(GetSpellPowerCost, id) end
    local report = ZP:CalculateSpellMetrics(metrics, spell, costs, {channel = channel, gcdSeconds = GCD(id)})
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
        "PLAYER_EQUIPMENT_CHANGED", "UNIT_SPELL_HASTE", "UNIT_AURA"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" or event == "UNIT_SPELL_HASTE" then
            if not Readable(unit) or unit ~= "player" then return end
        end
        if event == "SPELL_DATA_LOAD_RESULT" and ID(unit) then requested[unit] = nil end
        QueueRefresh()
    end)
end
