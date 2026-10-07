local addonName, ZP = ...
local L = ZP.L
ZP.version = "1.11.1"
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
    nameplateTargetEyes = false,
    healerMana = false,
    flightTimer = false,
    questObjectiveTarget = false,
    buffReminder = false,
    buffReminderSeconds = 30,
}
local numericSettings = {
    portraitModelSize = {minimum = 50, maximum = 100, step = 0.5},
    portraitBackgroundTransparency = {minimum = 0, maximum = 100, step = 1},
    buffReminderSeconds = {minimum = 5, maximum = 120, step = 5},
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
        elseif not Readable(ZwykPlusDB[key]) or type(ZwykPlusDB[key]) ~= "boolean" then
            ZwykPlusDB[key] = value
        end
    end
    ZwykPlusDB.nameplateTargetEyesHidden = nil
    ZwykPlusDB.version = 14
    self.db = ZwykPlusDB
    if self.portraits3DActive == nil then self.portraits3DActive = self.db.portraits3D end
end

function ZP:Are3DPortraitsEnabled()
    return self.portraits3DActive == true
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
    self.db[key] = numericSettings[key] and NormalizeNumber(key, value) or not not value
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
    elseif key == "buffReminder" or key == "buffReminderSeconds" then
        if self.RefreshBuffReminder then self:RefreshBuffReminder() end
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
    elseif key == "questObjectiveTarget" then
        if self.RefreshQuestTarget then self:RefreshQuestTarget() end
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
SlashCmdList.ZWYKPLUS = function(message)
    local command = type(message) == "string" and message:lower():match("^%s*(.-)%s*$") or ""
    if command == "portraits" or command == "debug portraits" then
        if ZP.ShowPortraitDiagnostics then ZP:ShowPortraitDiagnostics() end
    elseif command == "healers" then
        if ZP.ShowHealerManaMembers then ZP:ShowHealerManaMembers() end
    elseif command == "flight" then
        if ZP.ShowFlightTimerPreview then ZP:ShowFlightTimerPreview() end
    else
        ZP:ToggleOptions()
    end
end
