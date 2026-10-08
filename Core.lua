local addonName, ZP = ...
local L = ZP.L
ZP.version = "1.16.0"
local events = CreateFrame("Frame")
local defaults = {
    hideErrors = true,
    maxZoom = true,
    zoomOnLogin = true,
    autoTracking = true,
    minerals = true,
    herbs = true,
    fish = true,
    auraSource = true,
    auraSourceTarget = true,
    chatItemIcons = true,
    chatClassIcons = true,
    chatRaceIcons = true,
    portraits3D = false,
    portraitModelSize = 76.5,
    portraitBackgroundTransparency = 100,
    portraitClassBackground = true,
    frameClassColors = false,
    itemBindingIcons = false,
    restedXP = true,
    xpStats = true,
    nameplateTargetEyes = false,
    healerMana = false,
    flightTimer = false,
    questObjectiveTarget = false,
    questTargetQuestie = true,
    questTargetMarker = false,
    questTargetMarkerIcon = 8,
    buffReminder = false,
    buffReminderPercent = 20,
    buffReminderAfterPercent = 20,
    buffReminderBeforeGlow = "pixel",
    buffReminderAfterGlow = "button",
    buffReminderColor = {r = 1, g = 0.78, b = 0.12},
    buffReminderGlowTransparency = 0,
}
local numericSettings = {
    portraitModelSize = {minimum = 50, maximum = 100, step = 0.5},
    portraitBackgroundTransparency = {minimum = 0, maximum = 100, step = 1},
    buffReminderPercent = {minimum = 5, maximum = 100, step = 5},
    buffReminderAfterPercent = {minimum = 0, maximum = 100, step = 5},
    buffReminderGlowTransparency = {minimum = 0, maximum = 100, step = 1},
    questTargetMarkerIcon = {minimum = 1, maximum = 8, step = 1},
}
local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function NormalizeNumber(key, value)
    if not Readable(value) or type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then return defaults[key] end
    local setting = numericSettings[key]
    value = math.max(setting.minimum, math.min(setting.maximum, value))
    return math.floor(value / setting.step + 0.5) * setting.step
end
local glowStyles = {pixel = true, button = true, autocast = true, proc = true}
local function NormalizeGlow(key, value)
    if Readable(value) and type(value) == "string" and glowStyles[value] then return value end
    return defaults[key]
end
local function NormalizeColor(value)
    local color = {}
    local accessible = Readable(value) and type(value) == "table"
    for _, key in ipairs({"r", "g", "b"}) do
        local channel = accessible and rawget(value, key)
        if not Readable(channel) or type(channel) ~= "number" or channel ~= channel
            or channel == math.huge or channel == -math.huge then
            channel = defaults.buffReminderColor[key]
        end
        color[key] = math.max(0, math.min(1, channel))
    end
    return color
end
local trackingSpells = {
    {key = "fish", spellID = 43308},
    {key = "herbs", spellID = 2383},
    {key = "minerals", spellID = 2580},
}
local warned = {}
local errorRegistration
local errorsOwned = false
local trackingPending = false
local worldReady = false

function ZP:WarnOnce(key, message)
    if not warned[key] then
        warned[key] = true
        print("|cffffcc66ZwykPlus:|r " .. message)
    end
end

function ZP:InitializeDB()
    if type(ZwykPlusDB) ~= "table" then ZwykPlusDB = {} end
    for key, value in pairs(defaults) do
        if numericSettings[key] then
            ZwykPlusDB[key] = NormalizeNumber(key, ZwykPlusDB[key])
        elseif key == "buffReminderBeforeGlow" or key == "buffReminderAfterGlow" then
            ZwykPlusDB[key] = NormalizeGlow(key, ZwykPlusDB[key])
        elseif key == "buffReminderColor" then
            ZwykPlusDB[key] = NormalizeColor(ZwykPlusDB[key])
        elseif not Readable(ZwykPlusDB[key]) or type(ZwykPlusDB[key]) ~= "boolean" then
            ZwykPlusDB[key] = value
        end
    end
    ZwykPlusDB.nameplateTargetEyesHidden = nil
    ZwykPlusDB.buffReminderSeconds = nil
    ZwykPlusDB.version = 19
    self.db = ZwykPlusDB
    if self.portraits3DActive == nil then self.portraits3DActive = self.db.portraits3D end
end

function ZP:Are3DPortraitsEnabled()
    return self.portraits3DActive == true
end

function ZP:GetBuffReminderAppearance(after)
    local key = after and "buffReminderAfterGlow" or "buffReminderBeforeGlow"
    local style = NormalizeGlow(key, self.db and self.db[key])
    local color = NormalizeColor(self.db and self.db.buffReminderColor)
    local transparency = NormalizeNumber("buffReminderGlowTransparency", self.db and self.db.buffReminderGlowTransparency)
    return style, color.r, color.g, color.b, 1 - transparency / 100
end

function ZP:GetPortraitSetting(key)
    local value = self.db and self.db[key]
    if numericSettings[key] then return NormalizeNumber(key, value) end
    if key == "portraitClassBackground" then
        if Readable(value) and type(value) == "boolean" then return value end
        return defaults[key]
    end
end

function ZP:NeedsReload()
    return self.db and self.db.portraits3D ~= self.portraits3DActive
end

function ZP:ApplyErrors()
    if not self.db or not UIErrorsFrame then return end
    if self.db.hideErrors then
        if not errorsOwned then
            errorRegistration = UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE")
            errorsOwned = true
        end
        UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
        UIErrorsFrame:Show()
    elseif errorsOwned then
        if errorRegistration then
            UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
        end
        errorsOwned = false
    end
end

local function GetCameraCVar()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if get then return get("cameraDistanceMaxZoomFactor") end
end

local function SetCameraCVar(value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not set then return false end
    local ok, result = pcall(set, "cameraDistanceMaxZoomFactor", value)
    return ok and result ~= false
end

function ZP:ApplyCamera(zoomOut)
    if not self.db then return end
    if self.db.maxZoom then
        if self.db.cameraPrevious == nil then
            self.db.cameraPrevious = GetCameraCVar()
        end
        -- The client clamps this request to its supported maximum.
        if not SetCameraCVar(4) and not SetCameraCVar(2.6) then
            self:WarnOnce("camera", L.cameraFailed)
        end
        if zoomOut and CameraZoomOut then CameraZoomOut(100) end
    elseif self.db.cameraPrevious ~= nil then
        if SetCameraCVar(self.db.cameraPrevious) then
            self.db.cameraPrevious = nil
        else
            self:WarnOnce("cameraRestore", L.cameraRestoreFailed)
        end
    end
end

function ZP:CancelTracking()
    trackingPending = false
    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    events:UnregisterEvent("PLAYER_ALIVE")
    events:UnregisterEvent("PLAYER_UNGHOST")
end

local function ReadTracking(info, index)
    local name, _, active, _, _, spellID = info(index)
    if type(name) == "table" then
        return name.name, name.active, name.spellID
    end
    return name, active, spellID
end

function ZP:ApplyTracking()
    if not self.db or not self.db.autoTracking or not worldReady then
        self:CancelTracking()
        return
    end
    if InCombatLockdown() or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        trackingPending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_ALIVE")
        events:RegisterEvent("PLAYER_UNGHOST")
        return
    end
    self:CancelTracking()

    local api = C_Minimap
    local count = (api and api.GetNumTrackingTypes) or GetNumTrackingTypes
    local info = (api and api.GetTrackingInfo) or GetTrackingInfo
    local set = (api and api.SetTracking) or SetTracking
    if not (count and info and set) then
        self:WarnOnce("trackingMissing", L.trackingMissing)
        return
    end
    -- Highest priority last for clients which allow just one tracking spell.
    for _, spell in ipairs(trackingSpells) do
        if self.db[spell.key] then
            local localizedName
            if C_Spell and C_Spell.GetSpellName then
                localizedName = C_Spell.GetSpellName(spell.spellID)
            elseif GetSpellInfo then
                localizedName = GetSpellInfo(spell.spellID)
            end
            for index = 1, count() do
                local name, active, spellID = ReadTracking(info, index)
                if spellID == spell.spellID or (localizedName and name == localizedName) then
                    if active ~= true and active ~= 1 then
                        local ok, result = pcall(set, index, true)
                        if not ok or result == false then
                            self:WarnOnce("trackingBlocked", L.trackingBlocked)
                        end
                    end
                    break
                end
            end
        end
    end
end

function ZP:SetOption(key, value)
    if defaults[key] == nil then return end
    if numericSettings[key] then self.db[key] = NormalizeNumber(key, value)
    elseif key == "buffReminderBeforeGlow" or key == "buffReminderAfterGlow" then self.db[key] = NormalizeGlow(key, value)
    elseif key == "buffReminderColor" then self.db[key] = NormalizeColor(value)
    else self.db[key] = not not value end
    if key == "hideErrors" then
        self:ApplyErrors()
    elseif key == "maxZoom" or key == "zoomOnLogin" then
        self:ApplyCamera(self.db.zoomOnLogin)
    elseif key == "chatItemIcons" or key == "chatClassIcons" or key == "chatRaceIcons" then
        if self.RefreshChatIcons then self:RefreshChatIcons() end
    elseif key == "auraSource" or key == "auraSourceTarget" then
        if self.RefreshAuraTarget then self:RefreshAuraTarget() end
    elseif key == "portraits3D" then
        -- Native portrait mode is applied on reload; the checkbox is saved now.
    elseif key == "buffReminderBeforeGlow" or key == "buffReminderAfterGlow" or key == "buffReminderColor"
        or key == "buffReminderGlowTransparency" then
        if self.RefreshBuffReminder then self:RefreshBuffReminder(true) end
    elseif key == "buffReminder" or key == "buffReminderPercent" or key == "buffReminderAfterPercent" then
        if self.RefreshBuffReminder then self:RefreshBuffReminder() end
    elseif key == "questObjectiveTarget" or key == "questTargetQuestie" or key == "questTargetMarker"
        or key == "questTargetMarkerIcon" then
        if self.RefreshQuestTarget then self:RefreshQuestTarget() end
    elseif key == "restedXP" then
        if self.RefreshRestedXP then self:RefreshRestedXP() end
    elseif key == "xpStats" then
        if self.RefreshXPStats then self:RefreshXPStats() end
        if self.RefreshRestedXP then self:RefreshRestedXP() end
    elseif numericSettings[key] or key == "portraitClassBackground" then
        if self.RefreshPortraits then self:RefreshPortraits(false) end
    elseif key == "frameClassColors" then
        if self.RefreshNameColors then self:RefreshNameColors() end
    elseif key == "itemBindingIcons" then
        if self.RefreshItemBindingIcons then self:RefreshItemBindingIcons() end
    elseif key == "nameplateTargetEyes" then
        if self.RefreshNameplateTargetEyes then self:RefreshNameplateTargetEyes() end
    elseif key == "healerMana" then
        if self.RefreshHealerMana then self:RefreshHealerMana() end
    elseif key == "flightTimer" then
        if self.RefreshFlightTimer then self:RefreshFlightTimer() end
    else
        self:ApplyTracking()
    end
    if self.RefreshOptions then self:RefreshOptions() end
end

function ZP:ApplyAll()
    self:ApplyErrors()
    self:ApplyCamera(self.db.zoomOnLogin)
    self:ApplyTracking()
    if self.RefreshChatIcons then self:RefreshChatIcons() end
    if self.RefreshPortraits then self:RefreshPortraits(false) end
    if self.RefreshNameColors then self:RefreshNameColors() end
    if self.RefreshItemBindingIcons then self:RefreshItemBindingIcons() end
    if self.RefreshXPStats then self:RefreshXPStats() end
    if self.RefreshRestedXP then self:RefreshRestedXP() end
    if self.RefreshNameplateTargetEyes then self:RefreshNameplateTargetEyes() end
    if self.RefreshHealerMana then self:RefreshHealerMana() end
    if self.RefreshFlightTimer then self:RefreshFlightTimer() end
    if self.RefreshQuestTarget then self:RefreshQuestTarget() end
    if self.RefreshBuffReminder then self:RefreshBuffReminder() end
end

function ZP:ApplyFromOptions()
    self:ApplyAll()
    if not self:NeedsReload() then return end
    if InCombatLockdown and InCombatLockdown() then
        print("|cffffcc66ZwykPlus:|r " .. L.reloadCombat)
        return
    end
    -- Only called synchronously by the Apply button's hardware click.
    local reload = (C_UI and C_UI.Reload) or ReloadUI
    if reload then reload() else self:WarnOnce("reloadUnavailable", L.reloadUnavailable) end
end

local function CheckOldAddons()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not isLoaded then return end
    for _, name in ipairs({"HideUIErrors", "MaxZoomForever", "FindMineralsOnLogin"}) do
        if isLoaded(name) then
            ZP:WarnOnce("oldAddons", L.oldAddons)
            return
        end
    end
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        ZP:InitializeDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ZP:ApplyErrors()
        if ZP.InitializeAuraTooltips then ZP:InitializeAuraTooltips() end
        if ZP.InitializeAuraSourceTarget then ZP:InitializeAuraSourceTarget() end
        if ZP.InitializeChatIcons then ZP:InitializeChatIcons() end
        if ZP.InitializePortraits then ZP:InitializePortraits() end
        if ZP.InitializeNameColors then ZP:InitializeNameColors() end
        if ZP.InitializeItemBindingIcons then ZP:InitializeItemBindingIcons() end
        if ZP.InitializeRestedXP then ZP:InitializeRestedXP() end
        if ZP.InitializeXPStats then ZP:InitializeXPStats() end
        if ZP.InitializeNameplateTargetEyes then ZP:InitializeNameplateTargetEyes() end
        if ZP.InitializeHealerMana then ZP:InitializeHealerMana() end
        if ZP.InitializeFlightTimer then ZP:InitializeFlightTimer() end
        if ZP.InitializeQuestTarget then ZP:InitializeQuestTarget() end
        if ZP.InitializeBuffReminder then ZP:InitializeBuffReminder() end
        if ZP.RegisterSettings then ZP:RegisterSettings() end
        CheckOldAddons()
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_ENTERING_WORLD" then
        worldReady = true
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        ZP:ApplyCamera(ZP.db.zoomOnLogin)
        C_Timer.After(1, function() ZP:ApplyTracking() end)
    elseif trackingPending then
        ZP:ApplyTracking()
    end
end)

SLASH_ZWYKPLUS1 = "/zwykplus"
SLASH_ZWYKPLUS2 = "/zp"
function ZP:ShowBuffReminderDiagnostics()
    local report = self.GetBuffReminderDiagnostics and self:GetBuffReminderDiagnostics()
    print("|cffffcc66ZwykPlus " .. self.version .. " - " .. L.buffReminderDiagnostics .. "|r")
    if not report then print(L.buffReminderUnavailable); return end
    print(string.format(L.buffReminderDiagnosticSettings, report.enabled and L.yes or L.no,
        report.percent or 20, report.afterPercent or 20))
    print(string.format(L.buffReminderDiagnosticButtons, report.mappedButtons or 0))
    print(string.format(L.buffReminderDiagnosticAuras, report.publicAuras or 0, report.timingAvailable or 0,
        report.publicScanStatus or "?"))
    print(string.format(L.buffReminderDiagnosticEngine, report.engineConfigured or 0, report.enginePending or 0,
        report.engineFailed or 0))
end

function ZP:TestBuffReminder(after)
    local count = self.ShowBuffReminderPreview and self:ShowBuffReminderPreview(after == true) or 0
    if count == 0 then print("|cffffcc66ZwykPlus:|r " .. L.buffReminderNoButtons) end
end

SlashCmdList.ZWYKPLUS = function(message)
    local command = type(message) == "string" and message:lower():match("^%s*(.-)%s*$") or ""
    if command == "portraits" or command == "debug portraits" then
        if ZP.ShowPortraitDiagnostics then ZP:ShowPortraitDiagnostics() end
    elseif command == "healers" then
        if ZP.ShowHealerManaMembers then ZP:ShowHealerManaMembers() end
    elseif command == "flight" then
        if ZP.ShowFlightTimerPreview then ZP:ShowFlightTimerPreview() end
    elseif command == "buffs" or command == "debug buffs" then
        ZP:ShowBuffReminderDiagnostics()
    elseif command == "test buffs" then
        ZP:TestBuffReminder()
    elseif command == "test buffs after" then
        ZP:TestBuffReminder(true)
    else
        ZP:ToggleOptions()
    end
end
