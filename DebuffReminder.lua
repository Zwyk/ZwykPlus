local _, ZP = ...
local events, queued, buildPending
local buttons = {}
local elapsed, scanElapsed = 0, 0
local threshold = 0.2
local eligible, targetReason = false, "disabled"
local publicAuraState, scanStatus = "inactive", "disabled"

-- Judgement applies a separate spell from its seal. Any Paladin's judgement
-- counts; a direct Crusader seal or Judgement action can show this reminder.
local judgementIDs = {21183, 20188, 20300, 20301, 20302, 20303}
local actionIDs = {[21082] = true, [20162] = true, [20305] = true,
    [20306] = true, [20307] = true, [20308] = true, [20271] = true}
local prefixes = {"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button"}

local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
        and (not canaccessvalue or canaccessvalue(value))
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function Enabled()
    local value = ZP.db and ZP.db.debuffReminder
    return Readable(value) and value == true
end

local function InCombat()
    if not InCombatLockdown then return false end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not Readable(value) or value ~= false
end

local function PublicButton(button)
    if not Readable(button) or not button then return false end
    if type(button) ~= "table" and type(button) ~= "userdata" then return false end
    if button.IsForbidden then
        local ok, value = pcall(button.IsForbidden, button)
        if not ok or not Readable(value) or value ~= false then return false end
    end
    return type(button.CreateTexture) == "function"
end

local function PublicBoolean(api, ...)
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, ...)
    if ok and Readable(value) and type(value) == "boolean" then return value end
end

local function TargetEligible()
    if not Enabled() then return false, "disabled" end
    local exists = PublicBoolean(UnitExists, "target")
    if exists ~= true then return false, exists == false and "no-target" or "restricted-target" end
    local visible = PublicBoolean(UnitIsVisible, "target")
    if visible ~= true then return false, visible == false and "target-hidden" or "restricted-target" end
    local dead = PublicBoolean(UnitIsDeadOrGhost, "target")
    if dead ~= false then return false, dead == true and "target-dead" or "restricted-target" end
    local attackable = PublicBoolean(UnitCanAttack, "player", "target")
    if attackable ~= true then return false, attackable == false and "friendly-target" or "restricted-target" end
    return true, "ok"
end

local function Appearance(after)
    if ZP.GetBuffReminderAppearance then return ZP:GetBuffReminderAppearance(after) end
    return after and "button" or "pixel", 1, 0.78, 0.12, 1
end

local function ActionSpell(button)
    if not PublicButton(button) then return nil end
    local action = button.action
    if not Readable(action) then return nil end
    if not Number(action) and type(button.GetPagedID) == "function" then
        local ok, value = pcall(button.GetPagedID, button)
        if ok and not Readable(value) then return nil end
        if ok and Number(value) then action = value end
    end
    if not Number(action) and type(button.GetAttribute) == "function" then
        local ok, value = pcall(button.GetAttribute, button, "action")
        if ok and Number(value) then action = value end
    end
    if not Number(action) or type(GetActionInfo) ~= "function" then return nil end
    local ok, kind, id = pcall(GetActionInfo, action)
    if ok and Readable(kind) and kind == "spell" and Number(id) and actionIDs[id] then return id end
end

local function NativeAvailable()
    return UIParent and type(ZP.ConfigureBuffNativeGlow) == "function"
        and AuraContainerSortMethod and AuraContainerSortMethod.ExpirationOnly ~= nil
        and AuraContainerSortDirection and AuraContainerSortDirection.Reverse ~= nil
end

local function ConfigureNative(button, entry)
    local wasReady = entry.nativeReady and entry.containerEnabled
    entry.nativeReady, entry.nativePending = false, false
    if not entry.spellID or not NativeAvailable() then return end
    local style, red, green, blue, opacity = Appearance(false)
    local same = entry.nativeThreshold == threshold and entry.nativeStyle == style
        and entry.nativeRed == red and entry.nativeGreen == green and entry.nativeBlue == blue
        and entry.nativeOpacity == opacity
    if same and entry.containerEnabled and entry.container and entry.nativeGlowReady then
        entry.nativeReady = true
        return
    end
    if InCombat() then
        -- Existing native aura bindings keep ticking in combat. Rebinding their
        -- appearance, or creating a new action-button overlay, waits for safety.
        entry.nativeReady, entry.nativePending = wasReady or false, true
        buildPending = true
        return
    end
    if entry.nativeFailed then return end
    local ok, failure = pcall(function()
        if not entry.wrapper then
            local wrapper = CreateFrame("Frame", nil, UIParent)
            local icon = button.icon
            if Readable(icon) and icon == nil then icon = button.Icon end
            if not Readable(icon) or not icon or type(icon.GetObjectType) ~= "function" then icon = button end
            wrapper:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            wrapper:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            wrapper:SetFrameLevel(button:GetFrameLevel() + 8)
            wrapper:SetFrameStrata(button:GetFrameStrata())
            wrapper:EnableMouse(false)
            wrapper:Hide()
            entry.wrapper = wrapper
        end
        if not entry.container then
            local container = CreateFrame("AuraContainer", nil, entry.wrapper, "CustomAuraContainerTemplate")
            container:SetAllPoints(entry.wrapper)
            container:SetUnit("target")
            entry.container = container
        end
        local ids = {}
        for _, id in ipairs(judgementIDs) do ids[id] = true end
        local function ConfigureGlow(frame)
            local glowOK, ready, reason = pcall(ZP.ConfigureBuffNativeGlow, ZP, frame, button,
                threshold, style, red, green, blue, opacity)
            entry.nativeGlowReady = glowOK and Readable(ready) and ready == true
            entry.nativeGlowError = nil
            if not entry.nativeGlowReady then
                local errorText = glowOK and reason or ready
                if Readable(errorText) and type(errorText) == "string" then entry.nativeGlowError = errorText end
            end
        end
        if not entry.nativeFrame then
            entry.nativeFrame = entry.container:AddAuraSlot("crusader", "HARMFUL", {
                candidateFilters = {includeSpellIDs = ids, maxDuration = math.huge},
                sortMethod = AuraContainerSortMethod.ExpirationOnly,
                sortDirection = AuraContainerSortDirection.Reverse,
                initializeFrame = function(frame)
                    frame:SetAllPoints(entry.container)
                    frame:SetMouseClickEnabled(false)
                    frame:SetMouseMotionEnabled(false)
                    ConfigureGlow(frame)
                end,
            })
        else
            ConfigureGlow(entry.nativeFrame)
        end
        entry.container:SetEnabled(true)
        entry.containerEnabled = true
    end)
    entry.nativeFailed = not ok
    if ok then
        entry.nativeThreshold, entry.nativeStyle = threshold, style
        entry.nativeRed, entry.nativeGreen, entry.nativeBlue, entry.nativeOpacity = red, green, blue, opacity
        entry.nativeReady = true
    else
        if Readable(failure) and type(failure) == "string" then entry.nativeGlowError = failure end
        if entry.wrapper then pcall(entry.wrapper.Hide, entry.wrapper) end
        if entry.container then pcall(entry.container.SetEnabled, entry.container, false) end
        entry.containerEnabled = false
    end
end

local function BuildButtons()
    buildPending = InCombat()
    for _, entry in pairs(buttons) do entry.spellID = nil end
    for _, prefix in ipairs(prefixes) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            local spellID = ActionSpell(button)
            local entry = PublicButton(button) and buttons[button] or nil
            if not entry and spellID and not InCombat() then
                local ok, glow = pcall(ZP.CreateBuffGlow, ZP, button)
                if ok and Readable(glow) and glow then
                    entry = {texture = glow}
                    buttons[button] = entry
                end
            end
            if entry then
                entry.spellID = spellID
                if Enabled() then ConfigureNative(button, entry)
                else entry.nativeReady = false end
            end
        end
    end
end

local function PublicQueriesAllowed()
    local api = C_Secrets
    if not api then return false end
    if PublicBoolean(api.HasSecretRestrictions) == false then return true end
    if type(api.ShouldSpellAuraBeSecret) ~= "function" then return false end
    for _, id in ipairs(judgementIDs) do
        -- A public nil is not proof of absence until the complete family is
        -- explicitly readable. Restricted queries may conceal an active aura.
        if PublicBoolean(api.ShouldSpellAuraBeSecret, id) ~= false then return false end
    end
    return true
end

local function ScanAuras()
    eligible, targetReason = TargetEligible()
    publicAuraState, scanStatus = "inactive", targetReason
    if not eligible then return end
    publicAuraState = "unknown"
    local api = C_UnitAuras
    if not api or type(api.GetUnitAuraBySpellID) ~= "function" then scanStatus = "aura-api-unavailable"; return end
    if not PublicQueriesAllowed() then scanStatus = "restricted-auras"; return end
    local seen, unknown = false, false
    for _, id in ipairs(judgementIDs) do
        local ok, aura = pcall(api.GetUnitAuraBySpellID, "target", id)
        if not ok or not Readable(aura) then unknown = true
        elseif aura == nil then -- Known readable absence for this rank.
        elseif type(aura) == "table" then seen = true
        else unknown = true end
    end
    if seen then publicAuraState, scanStatus = "present", "ok"
    elseif unknown then scanStatus = "restricted-aura-result"
    else publicAuraState, scanStatus = "missing", "ok" end
end

local function Render()
    eligible, targetReason = TargetEligible()
    if not eligible then publicAuraState, scanStatus = "inactive", targetReason end
    local preview = ZP.IsBuffReminderPreviewActive and ZP:IsBuffReminderPreviewActive()
    local missing = eligible and not preview and publicAuraState == "missing"
    local style, red, green, blue, opacity = Appearance(true)
    for button, entry in pairs(buttons) do
        -- Public action identity is rechecked before each render so paging or
        -- replacing an action never keeps a glow on an unrelated spell.
        local mapped = entry.spellID and ActionSpell(button) ~= nil
        local visible = PublicButton(button) and PublicBoolean(button.IsVisible, button) == true
        local appearanceOK, applied = pcall(entry.texture.SetReminderAppearance,
            entry.texture, style, red, green, blue, opacity)
        local showMissing = missing and mapped and visible and appearanceOK and applied ~= false or false
        pcall(entry.texture.SetAlpha, entry.texture, showMissing and 1 or 0)
        pcall(entry.texture.SetShown, entry.texture, showMissing)
        entry.missingShown = showMissing
        if entry.wrapper then
            -- Lua controls only the public wrapper. The native child selects
            -- any caster's longest judgement and owns its timing/visibility.
            local shown = eligible and not preview and mapped and visible and not missing
                and entry.nativeReady and entry.nativeGlowReady or false
            pcall(entry.wrapper.SetShown, entry.wrapper, shown)
            if shown and not entry.nativeWasShown and type(ZP.ResumeBuffNativeGlow) == "function" then
                local ok, ready, reason = pcall(ZP.ResumeBuffNativeGlow, ZP, entry.nativeFrame)
                if not ok or ready == false then
                    local errorText = ok and reason or ready
                    if Readable(errorText) and type(errorText) == "string" then entry.nativeGlowError = errorText end
                end
            end
            entry.nativeWasShown = shown
        end
    end
end

local function Stop()
    publicAuraState, scanStatus = "inactive", "disabled"
    eligible, targetReason = false, "disabled"
    for _, entry in pairs(buttons) do
        pcall(entry.texture.SetAlpha, entry.texture, 0)
        pcall(entry.texture.Hide, entry.texture)
        entry.missingShown = false
        if entry.wrapper then pcall(entry.wrapper.Hide, entry.wrapper) end
        entry.nativeWasShown, entry.nativeReady = false, false
        if entry.container then pcall(entry.container.SetEnabled, entry.container, false) end
        entry.containerEnabled = false
    end
    events:SetScript("OnUpdate", nil)
end

local function StartTicker()
    events:SetScript("OnUpdate", function(_, delta)
        elapsed, scanElapsed = elapsed + delta, scanElapsed + delta
        if elapsed < 0.2 then return end
        elapsed = 0
        if not Enabled() then Stop(); return end
        if scanElapsed >= 1 then
            scanElapsed = 0
            if buildPending and not InCombat() then BuildButtons() end
            ScanAuras()
        end
        Render()
    end)
end

function ZP:IsDebuffReminderButtonOwned(button)
    -- Ownership is deliberately independent of secret aura presence. It gives
    -- this target reminder precedence over a player-seal reminder on the same
    -- action while the target can usefully receive Judgement of the Crusader.
    return TargetEligible() and ActionSpell(button) ~= nil or false
end

function ZP:RefreshDebuffReminder()
    if not events then return end
    elapsed, scanElapsed = 0, 0
    if not Enabled() then Stop(); return end
    local value = ZP.db and ZP.db.debuffReminderPercent
    threshold = (Number(value) and math.max(5, math.min(100, value)) or 20) / 100
    BuildButtons()
    ScanAuras()
    Render()
    StartTicker()
end

function ZP:GetDebuffReminderDiagnostics()
    local result = {enabled = Enabled(), eligible = eligible, percent = threshold * 100,
        status = scanStatus, targetReason = targetReason, publicAuraState = publicAuraState,
        missing = eligible and publicAuraState == "missing", mappedButtons = 0,
        engineConfigured = 0, enginePending = 0, engineFailed = 0, nativeGlows = 0,
        nativeGlowLastError = nil, publicMissingGlows = 0, missingGlows = 0}
    for _, entry in pairs(buttons) do
        if entry.spellID then
            result.mappedButtons = result.mappedButtons + 1
            if entry.nativeReady then result.engineConfigured = result.engineConfigured + 1 end
            if entry.nativePending then result.enginePending = result.enginePending + 1 end
            if entry.nativeFailed or (entry.nativeReady and not entry.nativeGlowReady) then
                result.engineFailed = result.engineFailed + 1
            end
            if entry.nativeReady and entry.nativeGlowReady then result.nativeGlows = result.nativeGlows + 1 end
            if entry.missingShown then
                result.publicMissingGlows = result.publicMissingGlows + 1
                result.missingGlows = result.missingGlows + 1
            end
            result.nativeGlowLastError = entry.nativeGlowError or result.nativeGlowLastError
        end
    end
    return result
end

local function QueueRefresh()
    if queued or not Enabled() then return end
    queued = true
    local refresh = function() queued = nil; ZP:RefreshDebuffReminder() end
    if C_Timer and C_Timer.After then C_Timer.After(0, refresh) else refresh() end
end

function ZP:InitializeDebuffReminder()
    if events then return end
    events = CreateFrame("Frame")
    for _, event in ipairs({"UNIT_AURA", "UNIT_FLAGS", "UNIT_HEALTH", "UNIT_FACTION"}) do
        events:RegisterUnitEvent(event, "target")
    end
    for _, event in ipairs({"PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ENCOUNTER_START", "ENCOUNTER_END",
        "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
        "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR", "SPELLS_CHANGED", "ADDON_LOADED"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "ADDON_LOADED" then
            for _, entry in pairs(buttons) do entry.nativeFailed = nil end
        end
        -- No missing state survives a target/aura/combat change without a new
        -- allowed scan. Native expiry bindings continue independently.
        publicAuraState, scanStatus = "unknown", "pending"
        Render()
        QueueRefresh()
    end)
    self:RefreshDebuffReminder()
end
