local _, ZP = ...
local L = ZP.L
local initialized = false
local hookedTooltips = setmetatable({}, {__mode = "k"})
local sources, unitGUIDs = {}, {}
local trackedUnits = {player = true, target = true, focus = true, pet = true}

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

local function ForbiddenTooltip(tooltip)
    if not Accessible(tooltip) or not tooltip then return true end
    local check = tooltip.IsForbidden
    if not Accessible(check) then return true end
    if not check then return false end
    local ok, forbidden = pcall(check, tooltip)
    return not ok or not Accessible(forbidden) or forbidden
end

local function AuraData(unit, index, filter, byInstance)
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
            return aura
        end
    end
end

function ZP:GetAuraSourceUnit(unit, index, filter, byInstance)
    local aura = AuraData(unit, index, filter, byInstance)
    if aura then
        local source = aura.sourceUnit
        if PlainString(source) then return source end
    elseif not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) and not byInstance and UnitAura
        and PlainString(unit) and Accessible(index) and type(index) == "number" and Accessible(filter) then
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

local function SourceName(source)
    if not UnitName then return end
    local ok, name, second = pcall(UnitName, source)
    if not ok or not PlainString(name) or not Accessible(second) then return end
    -- Forever's Camelot formatter treats the second return as a surname.
    -- Other clients keep their native realm-name formatting through this helper.
    if NameUtil and NameUtil.FormatUnitNameForDisplay then
        local formattedOK, formatted = pcall(NameUtil.FormatUnitNameForDisplay, source, true)
        if formattedOK and PlainString(formatted) then return formatted end
    end
    if PlainString(second) then
        local separators = Constants and Constants.CharacterNameSeparatorConsts
        local separator = separators and separators.CHARACTERNAME_SURNAME_SEPARATOR
        name = name .. (PlainString(separator) and separator or " ") .. second
    end
    return name
end

local function GUID(unit)
    if not UnitGUID or not PlainString(unit) then return end
    local ok, guid = pcall(UnitGUID, unit)
    if ok and PlainString(guid) then return guid end
end

local function TrackUnit(unit)
    if not PlainString(unit) then return end
    local guid = GUID(unit)
    local previous = unitGUIDs[unit]
    unitGUIDs[unit] = guid
    if previous and previous ~= guid then
        local stillTracked = false
        for _, otherGUID in pairs(unitGUIDs) do
            if otherGUID == previous then stillTracked = true; break end
        end
        if not stillTracked then sources[previous] = nil end
    end
    trackedUnits[unit] = true
    return guid
end

local function PublicNumber(value)
    return Accessible(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

local function AuraIdentity(aura)
    if not Accessible(aura) or type(aura) ~= "table" then return end
    local id, spell = aura.auraInstanceID, aura.spellId
    if PublicNumber(id) and id > 0 and PublicNumber(spell) and spell > 0 then return id, spell end
end

local function RememberSource(unit, aura, fresh)
    local guid = TrackUnit(unit)
    local id, spell = AuraIdentity(aura)
    if not guid then return end
    if not id then sources[guid] = nil; return end
    local entries = sources[guid]
    if not entries then entries = {}; sources[guid] = entries end
    local previous = not fresh and entries[id]
    local duration, expiration, source = aura.duration, aura.expirationTime, aura.sourceUnit
    -- A changed timer can be a refresh by a different caster. Never inherit the
    -- previous attribution unless this exact public application is unchanged.
    if not PublicNumber(duration) or not PublicNumber(expiration) or not Accessible(source) then
        entries[id] = nil
        return
    end
    if previous and (previous.spell ~= spell or previous.duration ~= duration or previous.expiration ~= expiration) then
        previous = nil
    end
    local name, casterGUID
    if PlainString(source) then
        casterGUID = GUID(source)
        name = SourceName(source)
        if casterGUID ~= GUID(source) then name = nil end
        if previous and casterGUID and casterGUID ~= previous.casterGUID then previous = nil end
    end
    if name and casterGUID then
        local r, g, b = SourceColor(source)
        previous = {spell = spell, duration = duration, expiration = expiration,
            casterGUID = casterGUID, name = name, r = r, g = g, b = b}
    end
    entries[id] = previous
    return previous
end

local function ScanSources(unit)
    local guid = TrackUnit(unit)
    local api = C_UnitAuras
    if not guid or not api or not api.GetAuraDataByIndex then return end
    local seen = {}
    for _, filter in ipairs({"HELPFUL", "HARMFUL"}) do
        for index = 1, 255 do
            local ok, aura = pcall(api.GetAuraDataByIndex, unit, index, filter)
            if not ok or not Accessible(aura) then sources[guid] = nil; return end
            if aura == nil then break end
            local id = AuraIdentity(aura)
            if id then seen[id] = true; RememberSource(unit, aura) end
        end
    end
    for id in pairs(sources[guid] or {}) do
        if not seen[id] then sources[guid][id] = nil end
    end
end

local function UpdateSources(unit, info)
    local guid = TrackUnit(unit)
    if not guid then return end
    -- A private update cannot establish that the saved application still has
    -- the same caster. Drop it rather than carrying names through that gap.
    if not Accessible(info) then sources[guid] = nil; return end
    if type(info) ~= "table" then ScanSources(unit); return end
    if not Accessible(info.isFullUpdate) then sources[guid] = nil; return end
    if info.isFullUpdate then ScanSources(unit); return end
    local removed, added, updated = info.removedAuraInstanceIDs, info.addedAuras, info.updatedAuraInstanceIDs
    if not Accessible(removed) or not Accessible(added) or not Accessible(updated) then sources[guid] = nil; return end
    if type(removed) == "table" then
        for _, id in ipairs(removed) do
            if not PublicNumber(id) then
                sources[guid] = nil
            elseif sources[guid] then
                sources[guid][id] = nil
            end
        end
    end
    if type(added) == "table" then
        for _, aura in ipairs(added) do RememberSource(unit, aura, true) end
    end
    if type(updated) == "table" then
        for _, id in ipairs(updated) do
            if PublicNumber(id) then
                local aura = AuraData(unit, id, nil, true)
                local actualID = AuraIdentity(aura)
                if actualID == id then
                    RememberSource(unit, aura)
                elseif sources[guid] then
                    sources[guid][id] = nil
                end
            else
                sources[guid] = nil
            end
        end
    end
end

local function SourceForDisplay(unit, index, filter, byInstance)
    local guid = TrackUnit(unit)
    local aura = AuraData(unit, index, filter, byInstance)
    if aura then
        local saved = RememberSource(unit, aura)
        if saved then return saved.name, saved.r, saved.g, saved.b end
        local source = aura.sourceUnit
        if PlainString(source) then
            local name = SourceName(source)
            if name then return name, SourceColor(source) end
        end
    else
        if guid then sources[guid] = nil end
        -- Index-only legacy clients cannot safely cache an aura application.
        local source = ZP:GetAuraSourceUnit(unit, index, filter, byInstance)
        if source then
            local name = SourceName(source)
            if name then return name, SourceColor(source) end
        end
    end
end

local function AddSource(tooltip, unit, index, filter, byInstance)
    if not ZP.db or not ZP.db.auraSource then return end
    if ForbiddenTooltip(tooltip) then return end
    if tooltip.zwykPlusSourceAdded then return end
    local name, r, g, b = SourceForDisplay(unit, index, filter, byInstance)
    if not name then return end
    tooltip:AddDoubleLine(L.source, name, 0.65, 0.65, 0.65, r, g, b)
    tooltip.zwykPlusSourceAdded = true
    if ZP.PrepareAuraTarget and tooltip.GetOwner then ZP:PrepareAuraTarget(tooltip:GetOwner()) end
    return true
end

local function WithFilter(required, filter)
    if not Accessible(filter) then return end
    if required and PlainString(filter) then return required .. "|" .. filter end
    return required or filter
end

local function HookTooltip(tooltip)
    if ForbiddenTooltip(tooltip) or hookedTooltips[tooltip] then return end
    if not tooltip.HookScript then return end
    hookedTooltips[tooltip] = true
    tooltip:HookScript("OnTooltipCleared", function(self)
        self.zwykPlusSourceAdded = nil
    end)
    if not hooksecurefunc then return end
    -- Public unit-frame and addon tooltips may use setters without processor metadata.
    for getter, spec in pairs(getters) do
        local method = "Set" .. getter:sub(4)
        if type(tooltip[method]) == "function" then
            hooksecurefunc(tooltip, method, function(self, unit, index, filter)
                if not Accessible(filter) then return end
                if AddSource(self, unit, index, WithFilter(spec.filter, filter), spec.instance) then
                    self:Show()
                end
            end)
        end
    end
end

function ZP:InitializeAuraTooltips()
    if initialized then return end
    initialized = true
    local events = CreateFrame("Frame")
    for _, event in ipairs({"UNIT_AURA", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET", "PLAYER_ENTERING_WORLD"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, unit, info)
        if not ZP.db or not ZP.db.auraSource then sources, unitGUIDs = {}, {}; return end
        if event == "UNIT_AURA" then
            if PlainString(unit) and trackedUnits[unit] then UpdateSources(unit, info) end
        elseif event == "PLAYER_TARGET_CHANGED" then
            ScanSources("target")
        elseif event == "PLAYER_FOCUS_CHANGED" then
            ScanSources("focus")
        elseif event == "UNIT_PET" then
            if PlainString(unit) and unit == "player" then ScanSources("pet") end
        else
            sources, unitGUIDs = {}, {}
            trackedUnits = {player = true, target = true, focus = true, pet = true}
            for token in pairs(trackedUnits) do ScanSources(token) end
        end
    end)
    if ZP.db and ZP.db.auraSource then
        for unit in pairs(trackedUnits) do ScanSources(unit) end
    end
    HookTooltip(GameTooltip)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.UnitAura then
        -- This also runs when Blizzard rebuilds a tooltip after an aura update.
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, function(tooltip)
            if not ZP.db or not ZP.db.auraSource then return end
            -- Target auras can use Blizzard's forbidden AuraButtonTooltip. Never
            -- read its processing fields, hook it, or call its tooltip setters.
            if ForbiddenTooltip(tooltip) then return end
            HookTooltip(tooltip)
            local getInfo = tooltip.GetProcessingTooltipInfo or tooltip.GetPrimaryTooltipInfo
            if not getInfo then return end
            local ok, info = pcall(getInfo, tooltip)
            if not ok then return end
            if not Accessible(info) or type(info) ~= "table" then return end
            local getter = info.getterName
            if not PlainString(getter) then return end
            local spec = getters[getter]
            local args = info.getterArgs
            if not spec or not Accessible(args) or type(args) ~= "table" then return end
            if not Accessible(args[3]) then return end
            AddSource(tooltip, args[1], args[2], WithFilter(spec.filter, args[3]), spec.instance)
        end)
    end
end
