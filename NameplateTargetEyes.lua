local addonName, ZP = ...
local units = {}
local plates = setmetatable({}, {__mode = "k"})
local events, queued
local elapsed = 0
local loggingOut, legacyVisibility
local visibilityCVars = {
    "nameplateShowAll", "nameplateShowEnemies", "nameplateShowEnemyMinions", "nameplateShowEnemyMinus",
    "nameplateShowFriendlyPlayers", "nameplateShowFriendlyPlayerMinions", "nameplateShowFriendlyNpcs",
}
local texturePath = "Interface\\AddOns\\" .. addonName .. "\\Textures\\NameplateTargetEye.tga"

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function NameplateUnit(unit)
    return Readable(unit) and type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

local function InCombat()
    if not InCombatLockdown then return false end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not Readable(value) or value ~= false
end

local function GetVisibility(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return end
    local ok, value = pcall(get, name)
    if ok and Readable(value) and (value == "0" or value == "1") then return value end
end

local function RestoreVisibility(name)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not set then return false end
    pcall(set, name, "0")
    return GetVisibility(name) == "0"
end

local function RestoreLegacyVisibility()
    -- Recovery only: older versions temporarily enabled these per-character CVars.
    -- Never enable categories, suppress native graphics or create replacement names.
    if not legacyVisibility then
        legacyVisibility = {}
        if Readable(ZwykPlusNameplateState) and type(ZwykPlusNameplateState) == "table" then
            for _, name in ipairs(visibilityCVars) do
                local value = ZwykPlusNameplateState[name]
                if Readable(value) and value == "0" then legacyVisibility[name] = value end
            end
        end
        ZwykPlusNameplateState = next(legacyVisibility) and legacyVisibility or nil
    end
    if not next(legacyVisibility) or InCombat() then return end
    for name, original in pairs(legacyVisibility) do
        local value = GetVisibility(name)
        if value == original or (value == "1" and RestoreVisibility(name)) then legacyVisibility[name] = nil end
    end
    ZwykPlusNameplateState = next(legacyVisibility) and legacyVisibility or nil
end

local function PublicPlate(plate)
    if not Readable(plate) or not plate then return false end
    if type(plate) ~= "table" and type(plate) ~= "userdata" then return false end
    if plate.IsForbidden then
        local ok, forbidden = pcall(plate.IsForbidden, plate)
        if not ok or not Readable(forbidden) or forbidden ~= false then return false end
    end
    return plate.CreateTexture and plate.HookScript and plate.IsShown
end

local function GetPlate(unit)
    if not NameplateUnit(unit) or not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    -- Never request forbidden nameplates or access their private UnitFrame.
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if ok and PublicPlate(plate) then return plate end
end

local function PlateUnit(plate)
    if not PublicPlate(plate) then return end
    local unit
    if plate.GetUnit then
        local ok, value = pcall(plate.GetUnit, plate)
        if ok then unit = value end
    else
        unit = plate.unitToken
    end
    if NameplateUnit(unit) then return unit end
end

local function Hide(record)
    if record and record.texture then record.texture:Hide() end
end

local function RefreshPlate(record)
    local unit, plate = record.unit, record.plate
    if not NameplateUnit(unit) or not PublicPlate(plate) or GetPlate(unit) ~= plate then
        Hide(record); return
    end
    local shown = plate:IsShown()
    if not Readable(shown) or shown ~= true then Hide(record); return end
    -- Native baseplates are reused. Recheck their public token, not pooled
    -- name/health/aura children that may now belong to another unit.
    if plate.GetUnit and PlateUnit(plate) ~= unit then Hide(record); return end
    if not (ZP.db and ZP.db.nameplateTargetEyes) then Hide(record); return end
    if not UnitIsUnit then Hide(record); return end
    local ok, targeting = pcall(UnitIsUnit, unit .. "target", "player")
    if not ok then Hide(record); return end
    local secret = issecretvalue and issecretvalue(targeting)
    if not secret then
        if not Readable(targeting) or type(targeting) ~= "boolean" or not targeting then
            Hide(record); return
        end
    end
    if not record.texture then
        local texture = plate:CreateTexture(nil, "OVERLAY", nil, 7)
        texture:SetSize(16, 16)
        texture:SetPoint("BOTTOM", plate, "TOP", 0, 2)
        texture:SetTexture(texturePath)
        texture:Hide()
        record.texture = texture
    end
    local texture = record.texture
    if texture.SetAlphaFromBoolean then
        -- This supported rendering API accepts secret booleans. Pass the
        -- comparison straight through; never inspect it or read alpha back.
        local rendered = pcall(texture.SetAlphaFromBoolean, texture, targeting)
        if rendered then texture:Show(); return end
    end
    if secret then Hide(record); return end
    texture:SetAlpha(1)
    texture:Show()
end

local function RefreshVisible()
    for _, record in pairs(units) do RefreshPlate(record) end
end

local function Poll(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.2 then return end
    elapsed = 0
    RefreshVisible()
end

local function UpdatePolling()
    if not events then return end
    local active = next(units) ~= nil and ZP.db and ZP.db.nameplateTargetEyes
    events:SetScript("OnUpdate", active and Poll or nil)
    if not active then elapsed = 0 end
end

local function Attach(unit)
    local plate = GetPlate(unit)
    if not plate then return end
    local record = plates[plate]
    if not record then
        record = {plate = plate}
        plates[plate] = record
        plate:HookScript("OnHide", function() Hide(record) end)
        plate:HookScript("OnShow", function() RefreshPlate(record) end)
    end
    local previous = units[unit]
    if previous and previous ~= record then
        Hide(previous)
        previous.unit = nil
    end
    if record.unit and record.unit ~= unit then units[record.unit] = nil end
    record.unit = unit
    units[unit] = record
    RefreshPlate(record)
end

local function Discover()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, visible = pcall(C_NamePlate.GetNamePlates)
    if not ok or not Readable(visible) or type(visible) ~= "table" then return end
    for _, plate in pairs(visible) do
        local unit = PlateUnit(plate)
        if unit then Attach(unit) end
    end
end

function ZP:RefreshNameplateTargetEyes()
    if loggingOut then return end
    RestoreLegacyVisibility()
    if not (self.db and self.db.nameplateTargetEyes) then
        for _, record in pairs(plates) do Hide(record) end
        UpdatePolling()
        return
    end
    Discover()
    RefreshVisible()
    UpdatePolling()
end

local function QueueRefresh()
    if queued then return end
    if C_Timer and C_Timer.After then
        queued = true
        C_Timer.After(0, function()
            queued = false
            ZP:RefreshNameplateTargetEyes()
        end)
    else
        ZP:RefreshNameplateTargetEyes()
    end
end

function ZP:InitializeNameplateTargetEyes()
    if events then return end
    events = CreateFrame("Frame")
    for _, event in ipairs({"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_TARGET",
        "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "ADDON_LOADED", "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED", "CVAR_UPDATE", "PLAYER_LOGOUT"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_LOGOUT" then
            loggingOut = true
            RestoreLegacyVisibility()
            for _, record in pairs(plates) do Hide(record) end
            events:SetScript("OnUpdate", nil)
        elseif event == "CVAR_UPDATE" then
            if not legacyVisibility or not next(legacyVisibility) then return end
            if not Readable(unit) or type(unit) ~= "string" then return end
            for _, name in ipairs(visibilityCVars) do
                if unit:lower() == name:lower() then QueueRefresh(); break end
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if not NameplateUnit(unit) then return end
            local record = units[unit]
            Hide(record)
            if record then record.unit = nil end
            units[unit] = nil
            UpdatePolling()
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            if not NameplateUnit(unit) or not (ZP.db and ZP.db.nameplateTargetEyes) then return end
            Attach(unit)
            UpdatePolling()
            -- Native and addon event order can differ during assignment.
            QueueRefresh()
        elseif event == "UNIT_TARGET" then
            if NameplateUnit(unit) and units[unit] then RefreshPlate(units[unit]) end
        elseif event == "PLAYER_ENTERING_WORLD" then
            for token, record in pairs(units) do
                Hide(record)
                record.unit = nil
                units[token] = nil
            end
            UpdatePolling()
            QueueRefresh()
        else
            QueueRefresh()
        end
    end)
    self:RefreshNameplateTargetEyes()
end
