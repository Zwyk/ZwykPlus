local _, ZP = ...
local initialized, events
local entries = {}
local states = {player = {}, target = {}, focus = {}}
local units = {"player", "target", "focus"}
local listeners, trackingEnabled = {}, false
local failedBars = setmetatable({}, {__mode = "k"})

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function PublicString(value)
    return Readable(value) and type(value) == "string" and value ~= ""
end

local function PublicNumber(value)
    return Readable(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function Enabled()
    return ZP.db and ZP.db.castTargetNames == true
end

local function SameCast(first, second)
    return PublicString(first) and PublicString(second) and first == second
end

local function Clear(entry)
    if entry and entry.hasText then
        entry.text:SetText("")
        entry.hasText = false
    end
end

local function Color(text, unit)
    text:SetTextColor(1, 1, 1)
    if not UnitSpellTargetClass then return end
    local ok, class = pcall(UnitSpellTargetClass, unit)
    -- A class token may be restricted too. Never use it as a Lua table key.
    if not ok or not PublicString(class) then return end
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local color = colors and colors[class]
    if not Readable(color) then return end
    if not color and C_ClassColor and C_ClassColor.GetClassColor then
        local success, result = pcall(C_ClassColor.GetClassColor, class)
        if success and Readable(result) then color = result end
    end
    if Readable(color) and type(color) == "table"
        and PublicNumber(color.r) and PublicNumber(color.g) and PublicNumber(color.b) then
        text:SetTextColor(color.r, color.g, color.b)
    end
end

local function Update(entry)
    Clear(entry)
    if not entry or not Enabled() then return end
    local bar, unit = entry.bar, entry.unit
    if not Readable(bar.casting) or not Readable(bar.channeling) then return end
    if not bar.casting and not bar.channeling then return end
    local state = states[unit]
    local channel = bar.channeling == true or state.kind == "channel"
    local name
    if channel then
        -- UnitSpellTargetName can return the previous hard-cast recipient for
        -- an entire channel. Only our own, matched SENT event is reliable here.
        if unit ~= "player" then return end
        name = state.sentTarget
        if type(name) == "nil" then return end
    else
        if UnitShouldDisplaySpellTargetName and UnitSpellTargetName then
            local ok, display = pcall(UnitShouldDisplaySpellTargetName, unit)
            if not ok or not Readable(display) or display ~= true then return end
            local success, result = pcall(UnitSpellTargetName, unit)
            if not success then return end
            name = result
        elseif unit == "player" then
            name = state.sentTarget
        end
        if type(name) == "nil" then return end
    end
    if Readable(name) and (type(name) ~= "string" or name == "") then return end
    if not channel then Color(entry.text, unit) else entry.text:SetTextColor(1, 1, 1) end
    -- SetText is a supported display sink. Restricted names are forwarded as-is:
    -- no concatenation, comparisons, string formatting, or GetText readback.
    entry.hasText = pcall(entry.text.SetText, entry.text, name)
end

local function UpdateUnit(unit)
    for _, entry in ipairs(entries) do
        if entry.unit == unit then Update(entry) end
    end
end

local function Accessible(frame)
    if not Readable(frame) or type(frame) ~= "table" or not frame.CreateFontString then return false end
    if frame.IsForbidden then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or not Readable(forbidden) or forbidden then return false end
    end
    return true
end

local function Install(bar, unit)
    if not Accessible(bar) then return end
    if failedBars[bar] then return end
    for _, entry in ipairs(entries) do if entry.bar == bar then return end end
    if InCombatLockdown and InCombatLockdown() then return end
    local ok, text = pcall(bar.CreateFontString, bar, nil, "OVERLAY", "GameFontHighlightSmall")
    if not ok or not text then return end
    local anchor = bar.Text
    if not Readable(anchor) then anchor = nil end
    if not anchor then
        anchor = bar.text
        if not Readable(anchor) then anchor = nil end
    end
    if not anchor then anchor = bar end
    local configured = pcall(function()
        text:SetText("")
        text:SetHeight(14)
        text:SetJustifyH("RIGHT")
        text:SetWordWrap(false)
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
        text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -1)
        text:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -1)
    end)
    if not configured then failedBars[bar] = true; return end
    local entry = {bar = bar, text = text, unit = unit}
    entries[#entries + 1] = entry
    if bar.HookScript then
        pcall(bar.HookScript, bar, "OnShow", function() Update(entry) end)
        pcall(bar.HookScript, bar, "OnHide", function() Clear(entry) end)
        pcall(bar.HookScript, bar, "OnEvent", function() Update(entry) end)
    end
    Update(entry)
end

local function InstallBars()
    -- Native bars may appear when their Blizzard addon loads. Build all regions
    -- before combat; combat updates only change our existing text and its color.
    Install(PlayerCastingBarFrame, "player")
    Install(CastingBarFrame, "player")
    Install(TargetFrameSpellBar, "target")
    Install(FocusFrameSpellBar, "focus")
    if TargetFrame then Install(TargetFrame.spellbar, "target") end
    if FocusFrame then Install(FocusFrame.spellbar, "focus") end
end

local starts = {
    UNIT_SPELLCAST_START = "cast",
    UNIT_SPELLCAST_CHANNEL_START = "channel",
    UNIT_SPELLCAST_EMPOWER_START = "empower",
}
local stops = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_FAILED_QUIET = true,
}

local function OnUnitEvent(unit, event, _, first, second, third, fourth, fifth)
    local state = states[unit]
    local castBarID = third
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        castBarID = fourth
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        castBarID = fifth
    end
    if event == "UNIT_SPELLCAST_SENT" then
        -- SENT payload: unit, recipient, castGUID, spellID. Keeping a value is
        -- allowed; matching uses only public GUIDs, never the recipient's name.
        state.pending = {target = first, guid = second}
        return
    end
    if starts[event] then
        local pending = state.pending
        state.pending, state.sentTarget = nil, nil
        state.kind, state.guid = starts[event], first
        state.castBarID = PublicNumber(castBarID) and castBarID or nil
        if unit == "player" and pending and SameCast(pending.guid, first) then
            state.sentTarget = pending.target
        end
    elseif stops[event] then
        -- A delayed stop for an older cast must not clear the next cast's name.
        if PublicString(state.guid) and PublicString(first) and state.guid ~= first then return end
        if PublicNumber(state.castBarID) and PublicNumber(castBarID)
            and state.castBarID ~= castBarID then return end
        state.kind, state.guid, state.castBarID, state.sentTarget = nil, nil, nil, nil
        if state.pending and SameCast(state.pending.guid, first) then state.pending = nil end
        UpdateUnit(unit)
        return
    end
    UpdateUnit(unit)
end

function ZP:RefreshCastTargets()
    if not initialized then return end
    local enabled = Enabled() == true
    if enabled ~= trackingEnabled then
        trackingEnabled = enabled
        for _, unit in ipairs(units) do
            states[unit] = {}
            local listener = listeners[unit]
            if listener then
                listener:UnregisterAllEvents()
                if enabled then
                    for event in pairs(starts) do pcall(listener.RegisterUnitEvent, listener, event, unit) end
                    for event in pairs(stops) do pcall(listener.RegisterUnitEvent, listener, event, unit) end
                    for _, event in ipairs({"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE",
                        "UNIT_SPELLCAST_EMPOWER_UPDATE"}) do
                        pcall(listener.RegisterUnitEvent, listener, event, unit)
                    end
                    if unit == "player" then
                        pcall(listener.RegisterUnitEvent, listener, "UNIT_SPELLCAST_SENT", unit)
                    end
                end
            end
        end
    end
    InstallBars()
    for _, entry in ipairs(entries) do Update(entry) end
end

function ZP:InitializeCastTargets()
    if initialized then return end
    initialized = true
    events = CreateFrame("Frame")
    for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
        "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED"}) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
            local unit = event == "PLAYER_TARGET_CHANGED" and "target" or "focus"
            states[unit] = {}
        elseif event == "PLAYER_ENTERING_WORLD" then
            for _, unit in ipairs(units) do states[unit] = {} end
        end
        ZP:RefreshCastTargets()
    end)
    for _, unit in ipairs(units) do
        local listener = CreateFrame("Frame")
        listeners[unit] = listener
        listener:SetScript("OnEvent", function(_, event, ...)
            OnUnitEvent(unit, event, ...)
        end)
    end
    self:RefreshCastTargets()
end
