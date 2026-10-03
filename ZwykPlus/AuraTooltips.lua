local _, ZP = ...
local L = ZP.L
local initialized = false

local getters = {
    GetUnitAura = {},
    GetUnitBuff = {filter = "HELPFUL"},
    GetUnitDebuff = {filter = "HARMFUL"},
    GetUnitAuraByAuraInstanceID = {instance = true},
    GetUnitBuffByAuraInstanceID = {instance = true},
    GetUnitDebuffByAuraInstanceID = {instance = true},
}

local function Accessible(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function PlainString(value)
    return Accessible(value) and type(value) == "string" and value ~= ""
end

function ZP:GetAuraSourceUnit(unit, index, filter, byInstance)
    if not PlainString(unit) or not Accessible(index) or type(index) ~= "number" then return end
    if not Accessible(filter) then return end
    local api = C_UnitAuras
    local get
    if api then
        if byInstance then get = api.GetAuraDataByAuraInstanceID else get = api.GetAuraDataByIndex end
    end
    if get then
        local ok, aura
        if byInstance then
            ok, aura = pcall(get, unit, index)
        else
            ok, aura = pcall(get, unit, index, filter)
        end
        if ok and Accessible(aura) and type(aura) == "table" then
            local source = aura.sourceUnit
            if PlainString(source) then return source end
        end
    elseif not byInstance and UnitAura then
        -- Classic's global UnitAura returns the caster as its seventh value.
        local ok, _, _, _, _, _, _, source = pcall(UnitAura, unit, index, filter)
        if ok and PlainString(source) then return source end
    end
end

local function SourceColor(source)
    if not UnitClass then return 1, 0.82, 0 end
    if UnitIsPlayer then
        local ok, player = pcall(UnitIsPlayer, source)
        if not ok or not Accessible(player) or not player then return 1, 0.82, 0 end
    end
    local ok, _, class = pcall(UnitClass, source)
    if not ok or not PlainString(class) then return 1, 0.82, 0 end
    local color
    if C_ClassColor and C_ClassColor.GetClassColor then
        local colorOK, value = pcall(C_ClassColor.GetClassColor, class)
        if colorOK and Accessible(value) then color = value end
    end
    if not color and RAID_CLASS_COLORS then color = RAID_CLASS_COLORS[class] end
    if Accessible(color) and type(color) == "table" then
        local r, g, b = color.r, color.g, color.b
        if Accessible(r) and Accessible(g) and Accessible(b)
            and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return 1, 0.82, 0
end

local function AddSource(tooltip, unit, index, filter, byInstance)
    if not ZP.db or not ZP.db.auraSource then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local source = ZP:GetAuraSourceUnit(unit, index, filter, byInstance)
    if not source then return end
    local ok, name, realm = pcall(UnitName, source)
    if not ok or not PlainString(name) then return end
    if PlainString(realm) then name = name .. "-" .. realm end
    local r, g, b = SourceColor(source)
    tooltip:AddDoubleLine(L.source, name, 0.65, 0.65, 0.65, r, g, b)
    if ZP.PrepareAuraTarget and tooltip.GetOwner then ZP:PrepareAuraTarget(tooltip:GetOwner()) end
    return true
end

local function WithFilter(required, filter)
    if not Accessible(filter) then return end
    if required and PlainString(filter) then return required .. "|" .. filter end
    return required or filter
end

function ZP:InitializeAuraTooltips()
    if initialized then return end
    initialized = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.UnitAura then
        -- This also runs when Blizzard rebuilds a tooltip after an aura update.
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, function(tooltip)
            if not ZP.db or not ZP.db.auraSource then return end
            local getInfo = tooltip.GetProcessingTooltipInfo or tooltip.GetPrimaryTooltipInfo
            if not getInfo then return end
            local info = getInfo(tooltip)
            if not Accessible(info) or type(info) ~= "table" then return end
            local getter = info.getterName
            if not PlainString(getter) then return end
            local spec = getters[getter]
            local args = info.getterArgs
            if not spec or not Accessible(args) or type(args) ~= "table" then return end
            if not Accessible(args[3]) then return end
            AddSource(tooltip, args[1], args[2], WithFilter(spec.filter, args[3]), spec.instance)
        end)
    elseif GameTooltip and hooksecurefunc then
        -- Fallback for clients using the older tooltip setters.
        GameTooltip:HookScript("OnTooltipCleared", function(tooltip)
            tooltip.zwykPlusSourceAdded = nil
        end)
        for getter, spec in pairs(getters) do
            local method = "Set" .. getter:sub(4)
            if type(GameTooltip[method]) == "function" then
                hooksecurefunc(GameTooltip, method, function(tooltip, unit, index, filter)
                    if tooltip.zwykPlusSourceAdded or not Accessible(filter) then return end
                    if AddSource(tooltip, unit, index, WithFilter(spec.filter, filter), spec.instance) then
                        tooltip.zwykPlusSourceAdded = true
                        tooltip:Show()
                    end
                end)
            end
        end
    end
end
