local _, ZP = ...
local events, timer, timerSpan, duration, overlay, spark, bar
local initialized, enabled, ticks, mana = false, false, false, false
local sweepEnd, window, manaUpdated
local Fail
local hooked = setmetatable({}, {__mode = "k"})
local manaType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local FIVE_SECONDS, REGEN_INTERVAL = 5, 2

local function Public(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and Public(value) then return value end
end

local function Accessible(frame)
    return Public(frame) and frame and not (frame.IsForbidden and Call(frame.IsForbidden, frame))
end

local function FindBar()
    -- Forever uses the modern native frame hierarchy; retain the old aliases
    -- for clients whose default frame still exposes PlayerFrameManaBar.
    local main = PlayerFrame and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
    local found = main and main.ManaBarArea and main.ManaBarArea.ManaBar
    found = found or PlayerFrameManaBar or (PlayerFrame and (PlayerFrame.manabar or PlayerFrame.ManaBar))
    if Accessible(found) and found.GetStatusBarTexture then return found end
end

local function Visible()
    return bar and Call(bar.IsVisible, bar) == true
end

local function Draw()
    if not overlay then return end
    if enabled and sweepEnd and mana and Visible() and (window or ticks) then
        local ok = pcall(overlay.SetTimerDuration, overlay, duration, Enum.StatusBarInterpolation.Immediate,
            Enum.StatusBarTimerDirection.ElapsedTime)
        if not ok then Fail(); return end
        overlay:Show()
    else
        overlay:Hide()
    end
end

local function Idle()
    if timer then timer:Stop() end
    sweepEnd, window, manaUpdated = nil, false, false
    if overlay then overlay:Hide() end
end

Fail = function()
    enabled = false
    Idle()
    events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    events:UnregisterEvent("UNIT_POWER_UPDATE")
    if ZP.WarnOnce and ZP.L and ZP.L.manaSparkUnavailable then
        ZP:WarnOnce("manaSparkUnavailable", ZP.L.manaSparkUnavailable)
    end
end

local function Sweep(length, start)
    local now = Call(GetTime)
    if not Number(now) then Idle(); return end
    if not Number(start) or start + length <= now then start = now end
    sweepEnd = start + length
    if not pcall(duration.SetTimeFromStart, duration, start, length) then Fail(); return end
    Draw()
    if not enabled then return end
    timer:Stop()
    timerSpan:SetDuration(sweepEnd - now)
    timer:Play()
end

local function UpdateListening()
    if not events then return end
    -- Only addon-owned frames and event registrations change in combat.
    events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    events:UnregisterEvent("UNIT_POWER_UPDATE")
    if enabled and overlay and Visible() then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        if ticks then events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player") end
    else
        Idle()
    end
end

local function ReadPowerType()
    mana = Call(UnitPowerType, "player") == manaType
    Draw()
end

local function CostsMana(spellID)
    if not Number(spellID) or spellID <= 0 then return false end
    local fn = C_Spell and C_Spell.GetSpellPowerCost or GetSpellPowerCost
    local costs = Call(fn, spellID)
    if type(costs) ~= "table" then return false end
    for _, cost in ipairs(costs) do
        if Public(cost) and type(cost) == "table" and Public(cost.type) and cost.type == manaType then
            -- A restricted amount is not read or compared. The public cost
            -- type is only a spending estimate, as in Ellesmere's indicator.
            if not Public(cost.cost) then return true end
            if Number(cost.cost) and cost.cost > 0 then return true end
        end
    end
    return false
end

local function Attach()
    if InCombatLockdown and InCombatLockdown() then return overlay and bar == FindBar() end
    local found = FindBar()
    if not found then return false end
    if not overlay then
        if not (C_DurationUtil and C_DurationUtil.CreateDuration and Enum
            and Enum.StatusBarInterpolation and Enum.StatusBarTimerDirection) then return false end
        duration = C_DurationUtil.CreateDuration()
        if not (duration and duration.SetTimeFromStart) then return false end
        overlay = CreateFrame("StatusBar", nil, UIParent)
        if not overlay.SetTimerDuration then overlay:Hide(); overlay = nil; return false end
        overlay:EnableMouse(false)
        overlay:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        overlay:GetStatusBarTexture():SetAlpha(0)
        overlay:SetMinMaxValues(0, 1)
        overlay:SetValue(0)
        overlay:Hide()
        spark = overlay:CreateTexture(nil, "OVERLAY")
        spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        spark:SetBlendMode("ADD")
        timer = events:CreateAnimationGroup()
        timerSpan = timer:CreateAnimation("Animation")
        timer:SetScript("OnFinished", function()
            if enabled and ticks and Visible() and (window or manaUpdated) then
                window, manaUpdated = false, false
                Sweep(REGEN_INTERVAL, sweepEnd)
            else
                Idle()
            end
        end)
    end
    bar = found
    overlay:ClearAllPoints()
    overlay:SetAllPoints(bar)
    local level = Call(bar.GetFrameLevel, bar)
    overlay:SetFrameLevel(Number(level) and level + 2 or 3)
    local strata = Call(bar.GetFrameStrata, bar)
    overlay:SetFrameStrata(type(strata) == "string" and strata or "LOW")
    local vertical = Call(bar.GetOrientation, bar) == "VERTICAL"
    local reverse = Call(bar.GetReverseFill, bar) == true
    overlay:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    overlay:SetReverseFill(reverse)
    local fill = overlay:GetStatusBarTexture()
    spark:ClearAllPoints()
    if vertical then
        spark:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
        spark:SetPoint("LEFT", fill, reverse and "BOTTOMLEFT" or "TOPLEFT")
        spark:SetPoint("RIGHT", fill, reverse and "BOTTOMRIGHT" or "TOPRIGHT")
        spark:SetHeight(8)
    else
        spark:SetTexCoord(0, 1, 0, 1)
        spark:SetPoint("TOP", fill, reverse and "TOPLEFT" or "TOPRIGHT")
        spark:SetPoint("BOTTOM", fill, reverse and "BOTTOMLEFT" or "BOTTOMRIGHT")
        spark:SetWidth(8)
    end
    if not hooked[bar] and bar.HookScript then
        hooked[bar] = true
        bar:HookScript("OnShow", function(self)
            if bar == self then ReadPowerType(); UpdateListening(); Draw() end
        end)
        bar:HookScript("OnHide", function(self)
            if bar == self then UpdateListening() end
        end)
    end
    return true
end

function ZP:RefreshManaSpark()
    if not initialized then return end
    enabled = self.db and self.db.manaSpark == true or false
    ticks = self.db and self.db.manaSparkRegenTicks == true or false
    -- Non-mana classes never allocate an overlay or cast/regen listeners.
    local class
    if UnitClass then
        local ok, _, second = pcall(UnitClass, "player")
        if ok and Public(second) then class = second end
    end
    if class == "WARRIOR" or class == "ROGUE" then enabled = false end
    if enabled then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        local ok, attached = pcall(Attach)
        if not ok then
            -- Failed setup must not interrupt the remaining login modules.
            Fail()
            overlay, spark, timer, timerSpan, duration = nil, nil, nil, nil, nil
        elseif not attached and not (InCombatLockdown and InCombatLockdown()) then
            Fail()
        end
        ReadPowerType()
    else
        events:UnregisterAllEvents()
        Idle()
    end
    UpdateListening()
end

function ZP:InitializeManaSpark()
    if initialized then self:RefreshManaSpark(); return end
    initialized = true
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event, unit, arg2, spellID)
        if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
            ZP:RefreshManaSpark()
        elseif event == "UNIT_DISPLAYPOWER" then
            if Public(unit) and unit == "player" then ReadPowerType() end
        elseif not Public(unit) or unit ~= "player" then
            return
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if enabled and Visible() and CostsMana(spellID) then
                window, manaUpdated = true, false
                Sweep(FIVE_SECONDS)
            end
        elseif event == "UNIT_POWER_UPDATE" then
            -- Regen tick cadence is an estimate; no current/max mana is read.
            if Public(arg2) and arg2 == "MANA" and not window and ticks then
                if sweepEnd then manaUpdated = true else Sweep(REGEN_INTERVAL) end
            end
        end
    end)
    self:RefreshManaSpark()
end
