local _, ZP = ...
local events, queued, curve, threshold
local buttons, records = {}, {}
local elapsed, scanElapsed = 0, 0

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
    for _, entry in pairs(buttons) do pcall(entry.texture.SetAlpha, entry.texture, 0) end
end

local function BuildCurve()
    local value = ZP.db and ZP.db.buffReminderSeconds
    value = Number(value) and math.max(5, math.min(120, value)) or 30
    if threshold == value and curve then return end
    threshold, curve = value, nil
    if not C_CurveUtil or not C_CurveUtil.CreateCurve then return end
    local ok, result = pcall(function()
        local c = C_CurveUtil.CreateCurve()
        -- Zero-span/permanent and expired durations remain invisible.
        c:AddPoint(0, 0)
        c:AddPoint(0.001, 1)
        c:AddPoint(value, 1)
        c:AddPoint(value + 0.001, 0)
        c:AddPoint(value + 1, 0)
        return c
    end)
    if ok and Readable(result) then curve = result end
end

local function BuildButtons()
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
                local slot = button.action
                if entry and Number(slot) and GetActionInfo
                    and C_ActionBar and C_ActionBar.FindSpellActionButtons then
                    local ok, kind, id = pcall(GetActionInfo, slot)
                    if ok and Readable(kind) and kind == "spell" and Number(id) then
                        local family = spellFamilies[id]
                        if family then
                            local found, slots = pcall(C_ActionBar.FindSpellActionButtons, id)
                            if found and Readable(slots) and type(slots) == "table" then
                                for j = 1, 240 do
                                    local action = slots[j]
                                    if not Readable(action) then break end
                                    if action == nil then break end
                                    if Number(action) and action == slot then entry.family = family; break end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function ScanAuras()
    records = {}
    local api = C_UnitAuras
    if not api or not api.GetAuraDataByIndex then return end
    local duplicate = {}
    for i = 1, 255 do
        local ok, aura = pcall(api.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not Readable(aura) then records = {}; return end
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
                        and type(duration.EvaluateRemainingDuration) == "function" then
                        record.duration = duration
                    end
                end
                if not record.duration then
                    local duration, expires = aura.duration, aura.expirationTime
                    if Number(duration) and duration > 0 and Number(expires) and expires > 0 then
                        record.expires = expires
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
    for button, entry in pairs(buttons) do
        local record = entry.family and records[entry.family]
        local ok = false
        if Enabled() and record and PublicButton(button) then
            if record.duration and curve then
                local evaluated, alpha = pcall(record.duration.EvaluateRemainingDuration, record.duration, curve)
                -- The curve output may be secret. Pass it only to the rendering
                -- sink; never compare it, format it, or read back the texture alpha.
                if evaluated then ok = pcall(entry.texture.SetAlpha, entry.texture, alpha) end
            elseif record.expires and GetTime then
                local remaining = record.expires - GetTime()
                ok = pcall(entry.texture.SetAlpha, entry.texture,
                    remaining > 0 and remaining <= threshold and 1 or 0)
            end
        end
        if not ok then pcall(entry.texture.SetAlpha, entry.texture, 0) end
    end
end

function ZP:RefreshBuffReminder()
    if not events then return end
    Clear()
    elapsed, scanElapsed = 0, 0
    if not Enabled() then events:SetScript("OnUpdate", nil); return end
    BuildCurve()
    BuildButtons()
    ScanAuras()
    Render()
    events:SetScript("OnUpdate", function(_, delta)
        elapsed, scanElapsed = elapsed + delta, scanElapsed + delta
        if elapsed < 0.2 then return end
        elapsed = 0
        -- Revalidate public aura access periodically as well as on UNIT_AURA;
        -- a restricted/missing buff is never represented by a cached old timer.
        if scanElapsed >= 1 then scanElapsed = 0; ScanAuras() end
        Render()
    end)
end

local function QueueRefresh()
    if queued or not Enabled() then return end
    queued = true
    local refresh = function() queued = nil; ZP:RefreshBuffReminder() end
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
    events:SetScript("OnEvent", function()
        -- Immediately discard old access/state at transitions before coalescing
        -- scans, including UNIT_AURA events whose payload is restricted.
        Clear()
        QueueRefresh()
    end)
    self:RefreshBuffReminder()
end
