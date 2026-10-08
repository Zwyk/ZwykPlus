local _, ZP = ...
local events, queued, curve, colorCurve, threshold, previewUntil, previewAfter, buildPending
local curveRed, curveGreen, curveBlue, curveOpacity
local buttons, records, mappedFamilies = {}, {}, {}
local expiryHistory, historyValidated, removedAt = {}, false, {}
local expiryDiscardCounts, expiryLastReason, expiryLastSpellID, expiryLastRemaining = {}, nil, nil, nil
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

local function AfterFraction()
    local value = ZP.db and ZP.db.buffReminderAfterPercent
    return (Number(value) and math.max(0, math.min(100, value)) or 20) / 100
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

local function Appearance(after)
    if ZP.GetBuffReminderAppearance then return ZP:GetBuffReminderAppearance(after) end
    return after and "button" or "pixel", 1, 0.78, 0.12, 1
end

local function DropHistory(family, reason)
    local history = expiryHistory[family]
    if not history then return end
    expiryHistory[family] = nil
    expiryDiscardCounts[reason] = (expiryDiscardCounts[reason] or 0) + 1
    expiryLastReason, expiryLastSpellID = reason, history.spellID
    expiryLastRemaining = history.expires - GetTime()
end

local function DropAllHistory(reason)
    for family in pairs(expiryHistory) do DropHistory(family, reason) end
end

local function Clear(discardHistory, reason)
    records = {}
    historyValidated = false
    if discardHistory then
        DropAllHistory(reason or "reset")
        removedAt = {}
    end
    for _, entry in pairs(buttons) do
        pcall(entry.texture.SetAlpha, entry.texture, 0)
        pcall(entry.texture.Hide, entry.texture)
        if entry.wrapper then pcall(entry.wrapper.Hide, entry.wrapper) end
    end
end

local function BuildCurve()
    local value = ZP.db and ZP.db.buffReminderPercent
    value = (Number(value) and math.max(5, math.min(100, value)) or 20) / 100
    local _, red, green, blue, opacity = Appearance(false)
    if threshold == value and curve and (colorCurve
        or not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor))
        and curveRed == red and curveGreen == green and curveBlue == blue and curveOpacity == opacity then return end
    threshold, curve, colorCurve = value, nil, nil
    curveRed, curveGreen, curveBlue, curveOpacity = red, green, blue, opacity
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
            c:AddPoint(0, CreateColor(red, green, blue, 0))
            c:AddPoint(0.00001, CreateColor(red, green, blue, opacity))
            c:AddPoint(value, CreateColor(red, green, blue, opacity))
            c:AddPoint(value + 0.00001, CreateColor(red, green, blue, 0))
            c:AddPoint(value + 1, CreateColor(red, green, blue, 0))
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
    if entry.nativeFamily == entry.family and entry.nativeThreshold == threshold
        and entry.nativeColorCurve == colorCurve and entry.container then
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
                    text:SetTextColor(curveRed, curveGreen, curveBlue, 0)
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
        entry.nativeFamily, entry.nativeThreshold, entry.nativeColorCurve = entry.family, threshold, colorCurve
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
                local slot, family = ActionSlot(button), nil
                if Number(slot) and GetActionInfo then
                    local ok, kind, id = pcall(GetActionInfo, slot)
                    if ok and Readable(kind) and kind == "spell" and Number(id) then family = spellFamilies[id] end
                end
                if not entry and family and not InCombat() then
                    local ok, texture = pcall(ZP.CreateBuffGlow, ZP, button)
                    if ok and Readable(texture) and texture then
                        entry = {texture = texture}
                        buttons[button] = entry
                    end
                end
                if entry then
                    entry.family = family
                    if Enabled() then ConfigureNative(button, entry)
                    else entry.nativeReady = false end
                end
            end
        end
    end
    mappedFamilies = {}
    for _, entry in pairs(buttons) do
        if entry.family then mappedFamilies[entry.family] = true end
    end
    for family in pairs(expiryHistory) do
        if not mappedFamilies[family] then DropHistory(family, "unmapped-button") end
    end
end

local function ScanAuras()
    records = {}
    historyValidated = false
    local removals = removedAt
    removedAt = {}
    scanStatus = "unavailable"
    local api = C_UnitAuras
    if not api or not api.GetAuraDataByIndex then DropAllHistory("unavailable-api"); return end
    scanStatus = "ok"
    local duplicate, seen, identityBlocked, complete = {}, {}, false, false
    local now, after = GetTime(), AfterFraction()
    if after == 0 then DropAllHistory("after-disabled") end
    for i = 1, 255 do
        local ok, aura = pcall(api.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not Readable(aura) then
            records = {}; DropAllHistory("restricted-scan"); scanStatus = "blocked"; return
        end
        if aura == nil then complete = true; break end
        if type(aura) == "table" then
            local id = aura.spellId
            if not Number(id) then identityBlocked = true end
            local family = Number(id) and spellFamilies[id]
            if family then
                seen[family] = true
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
                -- A duration handle may contain private timing. Only these
                -- independently readable numbers can arm a post-expiry timer.
                local total, expires = aura.duration, aura.expirationTime
                if Number(total) and total > 0 and Number(expires) and expires > 0 then
                    record.expires, record.total = expires, total
                    local previous = expiryHistory[family]
                    if mappedFamilies[family] and after > 0 and expires > now then
                        expiryHistory[family] = {expires = expires, total = total,
                            spellID = id, instanceID = Number(instance) and instance or nil}
                    elseif not previous or previous.expires ~= expires or previous.total ~= total then
                        DropHistory(family, "timing-changed")
                    end
                else
                    DropHistory(family, "missing-public-timing")
                end
                records[family] = record
            end
        else
            identityBlocked = true
        end
    end
    -- Do not guess which of multiple simultaneous ranks is the effective buff.
    for family in pairs(duplicate) do records[family] = nil; DropHistory(family, "duplicate-family") end
    if identityBlocked or not complete then
        -- An unknown identity could be a refresh of a remembered family. Do
        -- not infer absence or keep a cached timer through restricted data.
        DropAllHistory(identityBlocked and "restricted-identities" or "incomplete-scan")
        return
    end
    for family, history in pairs(expiryHistory) do
        local finish = history.expires + history.total * after
        -- The queued scan can straddle expiry. A removal already observed
        -- before expiry must not turn into a natural-expiration reminder.
        if not seen[family] and (removals[family] or now) < history.expires then
            DropHistory(family, "early-removal")
        elseif not Number(finish) or now >= finish then
            DropHistory(family, "expired-window")
        end
    end
    historyValidated = true
end

local function AfterExpiry(family, now)
    if not historyValidated then return false end
    local history = family and expiryHistory[family]
    local after = AfterFraction()
    return history and after > 0 and now >= history.expires
        and now < history.expires + history.total * after or false
end

local function Render()
    local now = GetTime and GetTime() or 0
    local preview = previewUntil and now < previewUntil
    for button, entry in pairs(buttons) do
        local record = entry.family and records[entry.family]
        local public, visible = PublicButton(button), false
        if public and type(button.IsVisible) == "function" then
            local shown, value = pcall(button.IsVisible, button)
            visible = shown and Readable(value) and value == true
        end
        local after = Enabled() and AfterExpiry(entry.family, now)
        local style, red, green, blue, opacity = Appearance(preview and previewAfter or not preview and after)
        local appearanceOK, applied = pcall(entry.texture.SetReminderAppearance, entry.texture, style, red, green, blue, opacity)
        appearanceOK = appearanceOK and applied ~= false
        -- Visibility is public configuration/button state, never curve alpha.
        pcall(entry.texture.SetShown, entry.texture,
            appearanceOK and ((preview and entry.family) or (Enabled() and record) or after) and public and visible or false)
        local ok = false
        if preview and entry.family and public then
            ok = pcall(entry.texture.SetAlpha, entry.texture, 1)
        elseif public and after then
            ok = pcall(entry.texture.SetAlpha, entry.texture, 1)
        elseif Enabled() and record and public then
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
            -- This visibility follows only public button/configuration state.
            -- The native binding alone decides when a private aura's ! appears.
            pcall(entry.wrapper.SetShown, entry.wrapper,
                not preview and Enabled() and entry.family and public and entry.nativeReady and visible or false)
        end
    end
end

local function StartTicker()
    events:SetScript("OnUpdate", function(_, delta)
        elapsed, scanElapsed = elapsed + delta, scanElapsed + delta
        if elapsed < 0.2 then return end
        elapsed = 0
        if previewUntil and GetTime() >= previewUntil then previewUntil = nil end
        if not Enabled() and not previewUntil then Clear(true, "disabled"); events:SetScript("OnUpdate", nil); return end
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
        Clear(true, "disabled")
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

function ZP:ShowBuffReminderPreview(after)
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
    if count > 0 then
        previewUntil, previewAfter = GetTime() + 5, after == true
        elapsed, scanElapsed = 0, 0; StartTicker(); Render()
    end
    return count
end

function ZP:GetBuffReminderDiagnostics()
    local result = {enabled = Enabled(), percent = (threshold or 0.2) * 100,
        afterPercent = AfterFraction() * 100, mappedButtons = 0,
        publicAuras = 0, timingAvailable = 0, status = scanStatus, publicScanStatus = scanStatus, engineConfigured = 0,
        enginePending = 0, engineFailed = 0, previewActive = previewUntil ~= nil,
        publicTimedAuras = 0, postExpiryTimers = 0, postExpiryActive = 0,
        historyValidated = historyValidated, expiryLastReason = expiryLastReason,
        expiryLastSpellID = expiryLastSpellID, expiryLastRemaining = expiryLastRemaining,
        expiryDiscardCounts = {}}
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
        if record.expires then result.publicTimedAuras = result.publicTimedAuras + 1 end
    end
    local now = GetTime()
    for family in pairs(expiryHistory) do
        result.postExpiryTimers = result.postExpiryTimers + 1
        if AfterExpiry(family, now) then result.postExpiryActive = result.postExpiryActive + 1 end
    end
    for reason, count in pairs(expiryDiscardCounts) do result.expiryDiscardCounts[reason] = count end
    return result
end

local function CapturePublicAbsences(now)
    local api = C_UnitAuras
    if not api or not api.GetAuraDataByAuraInstanceID then return end
    for family, history in pairs(expiryHistory) do
        if history.instanceID then
            local ok, aura = pcall(api.GetAuraDataByAuraInstanceID, "player", history.instanceID)
            if not ok or not Readable(aura) then
                DropHistory(family, "restricted-removal")
            elseif aura == nil then
                removedAt[family] = removedAt[family] and math.min(removedAt[family], now) or now
            elseif type(aura) ~= "table" then
                DropHistory(family, "restricted-removal")
            end
        end
    end
end

local function CaptureRemovalTimes(updateInfo)
    local now = GetTime()
    -- A public incremental payload identifies which remembered aura actually
    -- disappeared. An unrelated aura event must not supply an earlier removal
    -- time for a buff that naturally expires before the queued scan executes.
    if not Readable(updateInfo) or type(updateInfo) ~= "table" then CapturePublicAbsences(now); return end
    local full = updateInfo.isFullUpdate
    if not Readable(full) or full == true then CapturePublicAbsences(now); return end
    local ids = updateInfo.removedAuraInstanceIDs
    if not Readable(ids) then CapturePublicAbsences(now); return end
    if ids == nil then return end
    if type(ids) ~= "table" then CapturePublicAbsences(now); return end
    for _, id in ipairs(ids) do
        if not Number(id) then CapturePublicAbsences(now); return end
        for family, history in pairs(expiryHistory) do
            if history.instanceID == id then
                removedAt[family] = removedAt[family] and math.min(removedAt[family], now) or now
            end
        end
    end
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
    events:SetScript("OnEvent", function(_, event, unit, updateInfo)
        if event == "UNIT_AURA" then
            CaptureRemovalTimes(updateInfo)
        end
        if event == "ADDON_LOADED" then
            for _, entry in pairs(buttons) do entry.nativeFailed = nil end
        end
        -- Suspend rendering immediately. Combat/encounter history can only be
        -- used again after a complete, public scan validates it; a restricted
        -- scan discards it. World changes still reset the whole lifecycle.
        Clear(event == "PLAYER_ENTERING_WORLD", event)
        QueueRefresh()
    end)
    self:RefreshBuffReminder()
end
