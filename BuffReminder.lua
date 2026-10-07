local _, ZP = ...
local events, queued, curve, colorCurve, threshold, previewUntil, buildPending
local buttons, records = {}, {}
local elapsed, scanElapsed = 0, 0
local scanStatus = "disabled"

-- Classic rank families, including their group versions. Only direct spell
-- buttons on Blizzard bars are supported; macros are deliberately not guessed.
local families = {
    PALADIN = {
        {20217, 25898, 1213408}, -- Kings / Greater Kings / alternate aura
        {19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916}, -- Might
        {19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918}, -- Wisdom
        {19977, 19978, 19979, 25890, 26650}, -- Light
        {1038, 25895}, -- Salvation
        {20911, 20912, 20913, 20914, 25899}, -- Sanctuary
        {1311649, 1311656, 20163, 20419, 20421, 20422, 20423}, -- Seal of Fury
        {20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293}, -- Righteousness
        {20375, 20915, 20918, 20919, 20920}, -- Command
        {20164}, -- Justice
        {20165, 20347, 20348, 20349}, -- Light
        {20166, 20356, 20357}, -- Wisdom
        {21082, 20162, 20305, 20306, 20307, 20308}, -- Crusader
        {25780}, -- Righteous Fury; use the live aura's actual duration.
        {1044}, -- Freedom
        {1022, 5599, 10278}, -- Protection
        {6940, 20729}, -- Sacrifice
        {498, 5573}, -- Divine Protection
        {642, 1020}, -- Divine Shield
        {20925, 20927, 20928}, -- Holy Shield
        {1311015}, -- Templar's Bulwark
    },
    PRIEST = {
        {1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564}, -- Fortitude
        {14752, 14818, 14819, 27841, 27681}, -- Divine Spirit
    },
    MAGE = {{1459, 1460, 1461, 10156, 10157, 23028}}, -- Intellect
    DRUID = {{1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850}}, -- Mark
}
local spellFamilies = {}
local prefixes = {"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button"}

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function Enabled()
    local value = ZP.db and ZP.db.buffReminder
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

local function Clear()
    records = {}
    for _, entry in pairs(buttons) do
        pcall(entry.texture.SetAlpha, entry.texture, 0)
        if entry.wrapper then pcall(entry.wrapper.Hide, entry.wrapper) end
    end
end

local function BuildCurve()
    local value = ZP.db and ZP.db.buffReminderPercent
    value = (Number(value) and math.max(5, math.min(100, value)) or 20) / 100
    if threshold == value and curve and (colorCurve
        or not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor)) then return end
    threshold, curve, colorCurve = value, nil, nil
    if not C_CurveUtil or not C_CurveUtil.CreateCurve then return end
    local ok, result = pcall(function()
        local c = C_CurveUtil.CreateCurve()
        -- Zero-span/permanent and expired durations remain invisible.
        c:AddPoint(0, 0)
        c:AddPoint(0.00001, 1)
        c:AddPoint(value, 1)
        c:AddPoint(value + 0.00001, 0)
        c:AddPoint(value + 1, 0)
        return c
    end)
    if ok and Readable(result) then curve = result end
    if C_CurveUtil.CreateColorCurve and CreateColor then
        local colorOK, colors = pcall(function()
            local c = C_CurveUtil.CreateColorCurve()
            c:AddPoint(0, CreateColor(1, 0.82, 0.15, 0))
            c:AddPoint(0.00001, CreateColor(1, 0.82, 0.15, 1))
            c:AddPoint(value, CreateColor(1, 0.82, 0.15, 1))
            c:AddPoint(value + 0.00001, CreateColor(1, 0.82, 0.15, 0))
            c:AddPoint(value + 1, CreateColor(1, 0.82, 0.15, 0))
            return c
        end)
        if colorOK and Readable(colors) then colorCurve = colors end
    end
end

local function ActionSlot(button)
    -- This is Blizzard's current paged action; an attribute can be a base slot.
    local action = button.action
    if not Readable(action) then return end
    if Number(action) then return action end
    if type(button.GetPagedID) == "function" then
        local ok, slot = pcall(button.GetPagedID, button)
        if ok and not Readable(slot) then return end
        if ok and Number(slot) then return slot end
    end
    if type(button.GetAttribute) == "function" then
        local ok, slot = pcall(button.GetAttribute, button, "action")
        if ok and Number(slot) then return slot end
    end
end

local function NativeReady()
    -- The template's mixins live in Blizzard's secure environment; they are
    -- deliberately not globals accessible to addons. CreateFrame validates
    -- the template below, and ADDON_LOADED retries if it is not loaded yet.
    return colorCurve and UIParent
        and Enum and Enum.DurationTextBindingProperty
        and Enum.DurationTextBindingProperty.RemainingPercent ~= nil
end

local function ConfigureNative(button, entry)
    entry.nativeReady, entry.nativePending = false, false
    if not entry.family or not NativeReady() then return end
    if entry.nativeFamily == entry.family and entry.nativeThreshold == threshold and entry.container then
        entry.nativeReady = pcall(entry.container.SetEnabled, entry.container, true)
        return
    end
    if InCombat() then entry.nativePending = true; return end
    if entry.nativeFailed then return end
    local ok = pcall(function()
        if not entry.wrapper then
            -- Parent the renderer to our own frame, not the protected action bar.
            local wrapper = CreateFrame("Frame", nil, UIParent)
            wrapper:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            wrapper:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            wrapper:SetFrameLevel(button:GetFrameLevel() + 8)
            wrapper:SetFrameStrata(button:GetFrameStrata())
            wrapper:EnableMouse(false)
            wrapper:Hide()
            entry.wrapper = wrapper
        end
        if not entry.container then
            local wrapper = entry.wrapper
            local container = CreateFrame("AuraContainer", nil, wrapper, "CustomAuraContainerTemplate")
            container:SetAllPoints(wrapper)
            container:SetUnit("player")
            entry.container = container
        end
        local ids = {}
        for _, id in ipairs(entry.family) do ids[id] = true end
        local options = {
            textFormat = {formatString = "!", components = {}},
            textColor = {curve = colorCurve, property = Enum.DurationTextBindingProperty.RemainingPercent},
        }
        if not entry.nativeFrame then
            entry.nativeFrame = entry.container:AddAuraSlot("reminder", "HELPFUL", {
                -- A non-nil duration filter also excludes permanent auras in
                -- the native container. This is not a remaining-time test.
                candidateFilters = {includeSpellIDs = ids, maxDuration = math.huge},
                initializeFrame = function(frame)
                    frame:SetAllPoints(entry.container)
                    frame:SetMouseClickEnabled(false)
                    frame:SetMouseMotionEnabled(false)
                    local text = frame:CreateFontString(nil, "OVERLAY")
                    text:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 4)
                    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
                    text:SetTextColor(1, 0.82, 0.15, 0)
                    entry.nativeText = text
                    frame:SetDurationText(text, options)
                end,
            })
        else
            entry.container:SetAuraSlotCandidateFilters("reminder", {includeSpellIDs = ids, maxDuration = math.huge})
            entry.nativeFrame:SetDurationText(entry.nativeText, options)
        end
        entry.container:SetEnabled(true)
    end)
    entry.nativeFailed = not ok
    if ok then
        entry.nativeFamily, entry.nativeThreshold = entry.family, threshold
        entry.nativeReady = true
    else
        if entry.wrapper then pcall(entry.wrapper.Hide, entry.wrapper) end
        if entry.container then pcall(entry.container.SetEnabled, entry.container, false) end
    end
end

local function BuildButtons()
    -- REGEN_ENABLED can arrive before the client releases lockdown. Remember
    -- even an empty first build so newly enabled features recover afterward.
    buildPending = InCombat()
    local _, class
    if UnitClass then
        local ok, name, value = pcall(UnitClass, "player")
        if ok and Readable(value) then class = value end
    end
    spellFamilies = {}
    for _, family in ipairs(families[class] or {}) do
        for _, id in ipairs(family) do spellFamilies[id] = family end
    end
    for _, entry in pairs(buttons) do entry.family = nil end
    for _, prefix in ipairs(prefixes) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if PublicButton(button) then
                local entry = buttons[button]
                if not entry and not InCombat() then
                    local ok, texture = pcall(function()
                        local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
                        t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                        t:SetBlendMode("ADD")
                        t:SetPoint("TOPLEFT", button, "TOPLEFT", -7, 7)
                        t:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 7, -7)
                        t:SetVertexColor(1, 0.82, 0.15, 1)
                        t:SetAlpha(0)
                        return t
                    end)
                    if ok and Readable(texture) and texture then
                        entry = {texture = texture}
                        buttons[button] = entry
                    end
                end
                local slot = ActionSlot(button)
                if entry and Number(slot) and GetActionInfo then
                    local ok, kind, id = pcall(GetActionInfo, slot)
                    if ok and Readable(kind) and kind == "spell" and Number(id) then
                        local family = spellFamilies[id]
                        if family then entry.family = family end
                    end
                end
                if entry then
                    if Enabled() then ConfigureNative(button, entry)
                    else entry.nativeReady = false end
                end
            end
        end
    end
end

local function ScanAuras()
    records = {}
    scanStatus = "unavailable"
    local api = C_UnitAuras
    if not api or not api.GetAuraDataByIndex then return end
    scanStatus = "ok"
    local duplicate = {}
    for i = 1, 255 do
        local ok, aura = pcall(api.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not Readable(aura) then records = {}; scanStatus = "blocked"; return end
        if aura == nil then break end
        if type(aura) == "table" then
            local id = aura.spellId
            local family = Number(id) and spellFamilies[id]
            if family then
                if records[family] then duplicate[family] = true end
                local record = {spellID = id}
                local instance = aura.auraInstanceID
                if Number(instance) and api.GetAuraDuration and curve then
                    local durationOK, duration = pcall(api.GetAuraDuration, "player", instance)
                    if durationOK and Readable(duration) and duration
                        and type(duration.EvaluateRemainingPercent) == "function" then
                        record.duration = duration
                    end
                end
                if not record.duration then
                    local duration, expires = aura.duration, aura.expirationTime
                    if Number(duration) and duration > 0 and Number(expires) and expires > 0 then
                        record.expires, record.total = expires, duration
                    end
                end
                records[family] = record
            end
        end
    end
    -- Do not guess which of multiple simultaneous ranks is the effective buff.
    for family in pairs(duplicate) do records[family] = nil end
end

local function Render()
    local now = GetTime and GetTime() or 0
    local preview = previewUntil and now < previewUntil
    for button, entry in pairs(buttons) do
        local record = entry.family and records[entry.family]
        local ok = false
        if preview and entry.family and PublicButton(button) then
            ok = pcall(entry.texture.SetAlpha, entry.texture, 1)
        elseif Enabled() and record and PublicButton(button) then
            if record.duration and curve then
                local evaluated, alpha = pcall(record.duration.EvaluateRemainingPercent, record.duration, curve)
                -- The curve output may be secret. Pass it only to the rendering
                -- sink; never compare it, format it, or read back the texture alpha.
                if evaluated then ok = pcall(entry.texture.SetAlpha, entry.texture, alpha) end
            elseif record.expires and GetTime then
                local remaining = record.expires - GetTime()
                ok = pcall(entry.texture.SetAlpha, entry.texture,
                    remaining > 0 and remaining / record.total <= threshold and 1 or 0)
            end
        end
        if not ok then pcall(entry.texture.SetAlpha, entry.texture, 0) end
        if entry.wrapper then
            local visible = false
            if type(button.IsVisible) == "function" then
                local shown, value = pcall(button.IsVisible, button)
                visible = shown and Readable(value) and value == true
            end
            -- This visibility follows only public button/configuration state.
            -- The native binding alone decides when a private aura's ! appears.
            pcall(entry.wrapper.SetShown, entry.wrapper,
                not preview and Enabled() and entry.nativeReady and visible or false)
        end
    end
end

local function StartTicker()
    events:SetScript("OnUpdate", function(_, delta)
        elapsed, scanElapsed = elapsed + delta, scanElapsed + delta
        if elapsed < 0.2 then return end
        elapsed = 0
        if previewUntil and GetTime() >= previewUntil then previewUntil = nil end
        if not Enabled() and not previewUntil then Clear(); events:SetScript("OnUpdate", nil); return end
        if Enabled() and scanElapsed >= 1 then
            scanElapsed = 0
            if buildPending and not InCombat() then BuildButtons() end
            ScanAuras()
        end
        Render()
    end)
end

function ZP:RefreshBuffReminder(preservePreview)
    if not events then return end
    if not preservePreview then previewUntil = nil end
    Clear()
    elapsed, scanElapsed = 0, 0
    if not Enabled() then
        scanStatus = "disabled"
        for _, entry in pairs(buttons) do
            if entry.container then pcall(entry.container.SetEnabled, entry.container, false) end
        end
        if previewUntil and GetTime() < previewUntil then
            BuildCurve(); BuildButtons(); Render(); StartTicker()
        else
            previewUntil = nil
            events:SetScript("OnUpdate", nil)
        end
        return
    end
    BuildCurve()
    BuildButtons()
    ScanAuras()
    Render()
    StartTicker()
end

function ZP:ShowBuffReminderPreview()
    if not events then return 0 end
    Clear()
    BuildCurve()
    BuildButtons()
    local count = 0
    for button, entry in pairs(buttons) do
        local visible = true
        if type(button.IsVisible) == "function" then
            local ok, value = pcall(button.IsVisible, button)
            visible = ok and Readable(value) and value == true
        end
        if entry.family and visible then count = count + 1 end
    end
    if count > 0 then previewUntil = GetTime() + 5; elapsed, scanElapsed = 0, 0; StartTicker(); Render() end
    return count
end

function ZP:GetBuffReminderDiagnostics()
    local result = {enabled = Enabled(), percent = (threshold or 0.2) * 100, mappedButtons = 0,
        publicAuras = 0, timingAvailable = 0, status = scanStatus, publicScanStatus = scanStatus, engineConfigured = 0,
        enginePending = 0, engineFailed = 0, previewActive = previewUntil ~= nil}
    for _, entry in pairs(buttons) do
        if entry.family then
            result.mappedButtons = result.mappedButtons + 1
            if entry.nativeReady then result.engineConfigured = result.engineConfigured + 1 end
            if entry.nativePending then result.enginePending = result.enginePending + 1 end
            if entry.nativeFailed then result.engineFailed = result.engineFailed + 1 end
        end
    end
    for _, record in pairs(records) do
        result.publicAuras = result.publicAuras + 1
        if record.duration or record.expires then result.timingAvailable = result.timingAvailable + 1 end
    end
    return result
end

local function QueueRefresh()
    if queued or (not Enabled() and not previewUntil) then return end
    queued = true
    local refresh = function() queued = nil; ZP:RefreshBuffReminder(true) end
    if C_Timer and C_Timer.After then C_Timer.After(0, refresh) else refresh() end
end

function ZP:InitializeBuffReminder()
    if events then return end
    events = CreateFrame("Frame")
    events:RegisterUnitEvent("UNIT_AURA", "player")
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "ENCOUNTER_START", "ENCOUNTER_END", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_BONUS_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
        "SPELLS_CHANGED", "ADDON_LOADED"}) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function(_, event)
        if event == "ADDON_LOADED" then
            for _, entry in pairs(buttons) do entry.nativeFailed = nil end
        end
        -- Immediately discard old access/state at transitions before coalescing
        -- scans, including UNIT_AURA events whose payload is restricted.
        Clear()
        QueueRefresh()
    end)
    self:RefreshBuffReminder()
end
