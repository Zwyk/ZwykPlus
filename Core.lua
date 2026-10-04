local addonName, ZP = ...
local L = ZP.L
ZP.version = "1.5.1"
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
    frameClassColors = false,
}
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
        if type(ZwykPlusDB[key]) ~= "boolean" then ZwykPlusDB[key] = value end
    end
    ZwykPlusDB.version = 6
    self.db = ZwykPlusDB
    if self.portraits3DActive == nil then self.portraits3DActive = self.db.portraits3D end
end

function ZP:Are3DPortraitsEnabled()
    return self.portraits3DActive == true
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
    self.db[key] = not not value
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
    elseif key == "frameClassColors" then
        if self.RefreshNameColors then self:RefreshNameColors() end
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
    if self.RefreshPortraits then self:RefreshPortraits(true) end
    if self.RefreshNameColors then self:RefreshNameColors() end
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
    else
        ZP:ToggleOptions()
    end
end
