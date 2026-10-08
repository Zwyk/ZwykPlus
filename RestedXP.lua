local _, ZP = ...
local L = ZP.L
local events = CreateFrame("Frame")
local bars, ticks, tooltips = {}, {}, {}
local manager, initialized, rebuilding

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil, false end
    local ok, value = pcall(fn, ...)
    if ok and Readable(value) then return value, true end
    return nil, false
end

local function Public(frame)
    if not Readable(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") then return false end
    if frame.IsForbidden then
        local forbidden, ok = Call(frame.IsForbidden, frame)
        if not ok or forbidden then return false end
    end
    return true
end

local function Amount()
    if not (ZP.db and ZP.db.restedXP) then return end
    local maximum, valid = Call(UnitXPMax, "player")
    if not valid or not Number(maximum) or maximum <= 0 then return end
    for _, check in ipairs({GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel
        or IsPlayerAtEffectiveMaxLevel or false, IsXPUserDisabled or false}) do
        if type(check) == "function" then
            local blocked, accessible = Call(check)
            if not accessible or type(blocked) ~= "boolean" or blocked then return end
        end
    end
    local rested, accessible = Call(GetXPExhaustion)
    if not accessible then return end
    -- Native GetXPExhaustion returns nil when there is no rested bonus pool.
    if rested == nil then rested = 0 end
    if not Number(rested) or rested < 0 then return end
    local percentage = rested / maximum * 100
    if not Number(percentage) then return end
    local amount = math.floor(rested + 0.5)
    local formatted, grouped = Call(BreakUpLargeNumbers, amount)
    if not grouped or type(formatted) ~= "string" then formatted = tostring(amount) end
    local percent = string.format("%.1f", percentage):gsub("%.0$", "")
    return formatted, percent
end

local function Label(tooltip)
    local amount, percent = Amount()
    local key = tooltip and "restedXPTooltipFormat" or "restedXPBarFormat"
    local rest = amount and string.format(L[key], amount, percent)
    if tooltip then return rest end
    local stats = ZP.XPStatsBarLabel and ZP:XPStatsBarLabel()
    if rest and stats then return rest .. "  |  " .. stats end
    return rest or stats
end

local function TooltipLabels()
    local labels, rest = {}, Label(true)
    if rest then labels[#labels + 1] = rest end
    if ZP.XPStatsTooltipLines then
        for _, text in ipairs(ZP:XPStatsTooltipLines()) do labels[#labels + 1] = text end
    end
    return labels
end

local function ApplyText(entry)
    if entry.writing or not Public(entry.text) then return end
    local current, accessible = Call(entry.text.GetText, entry.text)
    if not accessible or type(current) ~= "string" then return end
    if current ~= entry.owned then entry.original = current end
    local label = Label(false)
    local value = label and entry.original and (entry.original .. "  |  " .. label) or entry.original
    entry.owned = label and value or nil
    if value and value ~= current then
        entry.writing = true
        entry.text:SetText(value)
        entry.writing = nil
    end
end

local function TooltipLine(tooltip, index)
    local name, accessible = Call(tooltip.GetName, tooltip)
    if accessible and type(name) == "string" and Number(index) then
        local line = _G[name .. "TextLeft" .. index]
        if Public(line) then return line end
    end
end

local function AppropriateTooltip()
    local tooltip, accessible = Call(GetAppropriateTooltip)
    if accessible and Public(tooltip) then return tooltip end
    if Public(GameTooltip) then return GameTooltip end
end

local function OwnedTooltip(tooltip, entry)
    if not entry or not entry.index or not entry.owned then return false end
    for index, text in ipairs(entry.owned) do
        local line = TooltipLine(tooltip, entry.index + index - 1)
        local current, accessible
        if line then current, accessible = Call(line.GetText, line) end
        if not accessible or current ~= text then return false end
    end
    return true
end

local function UpdateTooltip(tooltip, entry, labels)
    for index, text in ipairs(labels) do TooltipLine(tooltip, entry.index + index - 1):SetText(text) end
    entry.owned = labels
end

local function AddTooltip(tick)
    if rebuilding then return end
    local labels, tooltip = TooltipLabels(), AppropriateTooltip()
    if not tooltip or type(tooltip.AddLine) ~= "function" then return end
    local entry = tooltips[tooltip]
    if OwnedTooltip(tooltip, entry) then
        if #entry.owned == #labels then
            UpdateTooltip(tooltip, entry, labels)
            tooltip:Show()
        end
        return
    end
    if not entry then
        entry = {}
        tooltips[tooltip] = entry
        if tooltip.HookScript then
            tooltip:HookScript("OnTooltipCleared", function() entry.index, entry.owned, entry.tick = nil, nil, nil end)
        end
    end
    entry.tick = tick
    if #labels == 0 then return end
    for _, text in ipairs(labels) do tooltip:AddLine(text, 0.35, 0.7, 1, true) end
    local count, accessible = Call(tooltip.NumLines, tooltip)
    entry.index = accessible and Number(count) and count - #labels + 1 or nil
    entry.owned, entry.tick = labels, tick
    tooltip:Show()
end

local function RefreshTooltips()
    for tooltip, entry in pairs(tooltips) do
        if (entry.owned or entry.tick) and Public(tooltip) then
            local shown, accessible = Call(tooltip.IsShown, tooltip)
            if accessible and shown then
                if OwnedTooltip(tooltip, entry) then
                    local labels = TooltipLabels()
                    if #labels == #entry.owned then
                        UpdateTooltip(tooltip, entry, labels)
                    elseif Public(entry.tick) and type(entry.tick.ExhaustionToolTipText) == "function" then
                        -- Rebuild native content when our line count changes. Other
                        -- tooltip posthooks still run, and the new block is added once.
                        local tick = entry.tick
                        rebuilding = true
                        pcall(tick.ExhaustionToolTipText, tick)
                        rebuilding = nil
                        entry.index, entry.owned, entry.tick = nil, nil, tick
                        AddTooltip(tick)
                    else
                        for index in ipairs(entry.owned) do
                            TooltipLine(tooltip, entry.index + index - 1):SetText("")
                        end
                        entry.owned = nil
                    end
                    tooltip:Show()
                elseif not entry.owned and entry.tick then
                    AddTooltip(entry.tick)
                end
            end
        end
    end
end

local function HookBar(bar, text)
    if not Public(bar) then return end
    if not text then
        local overlay = bar.OverlayFrame
        text = Public(overlay) and overlay.Text or bar.TextString
    end
    if not Public(text) or type(text.SetText) ~= "function" then return end
    local entry = bars[bar]
    if not entry then
        entry = {text = text}
        bars[bar] = entry
        hooksecurefunc(text, "SetText", function() ApplyText(entry) end)
        if bar.HookScript then
            bar:HookScript("OnShow", function() ApplyText(entry) end)
            bar:HookScript("OnEnter", function() AddTooltip(bar.ExhaustionTick) end)
            bar:HookScript("OnMouseUp", function(_, button)
                if button == "LeftButton" and ZP.PromptXPStatsReset then ZP:PromptXPStatsReset() end
            end)
        end
    end
    local tick = bar.ExhaustionTick
    if Public(tick) and not ticks[tick] then
        ticks[tick] = true
        if tick.HookScript then
            tick:HookScript("OnMouseUp", function(_, button)
                if button == "LeftButton" and ZP.PromptXPStatsReset then ZP:PromptXPStatsReset() end
            end)
        end
        if type(tick.ExhaustionToolTipText) == "function" then
            hooksecurefunc(tick, "ExhaustionToolTipText", function() AddTooltip(tick) end)
        elseif tick.HookScript then
            tick:HookScript("OnEnter", function() AddTooltip(tick) end)
        end
    end
    ApplyText(entry)
end

local function FindBars()
    if Public(MainMenuXPBar) then HookBar(MainMenuXPBar, MainMenuXPBarText) end
    local native = StatusTrackingBarManager
    if not Public(native) then return end
    if native ~= manager and type(native.UpdateBarsShown) == "function" then
        manager = native
        hooksecurefunc(native, "UpdateBarsShown", function() ZP:RefreshRestedXP() end)
    end
    local containers = native.barContainers
    if not Readable(containers) or type(containers) ~= "table" then return end
    for _, container in ipairs(containers) do
        if Public(container) and Readable(container.bars) and type(container.bars) == "table" then
            for _, bar in pairs(container.bars) do
                if Public(bar) and Readable(bar.isExpBar) and bar.isExpBar == true then HookBar(bar) end
            end
        end
    end
end

function ZP:RefreshRestedXP()
    FindBars()
    for _, entry in pairs(bars) do ApplyText(entry) end
    RefreshTooltips()
end

function ZP:InitializeRestedXP()
    if initialized then return end
    initialized = true
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION",
        "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING", "UPDATE_EXPANSION_LEVEL", "PLAYER_MAX_LEVEL_UPDATE",
        "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "ADDON_LOADED"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, unit)
        if event ~= "PLAYER_XP_UPDATE" or unit == "player" then ZP:RefreshRestedXP() end
    end)
    self:RefreshRestedXP()
end
