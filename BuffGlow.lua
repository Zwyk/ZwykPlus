local _, ZP = ...

local styles = {pixel = true, autocast = true, button = true, proc = true}

local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
        and (not canaccessvalue or canaccessvalue(value))
end

local function Number(value, fallback)
    if not Readable(value) or type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then return fallback end
    return math.max(0, math.min(1, value))
end

function ZP:CreateBuffGlow(button)
    local icon = button.icon
    if Readable(icon) and icon == nil then icon = button.Icon end
    if not Readable(icon) or not icon or type(icon.GetObjectType) ~= "function" then icon = button end
    -- Only this outer gate receives the aura curve's potentially opaque alpha.
    -- LibCustomGlow always sees a separate host with ordinary appearance values.
    local gate = CreateFrame("Frame", nil, UIParent)
    gate:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    gate:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    gate:SetFrameLevel(button:GetFrameLevel() + 8)
    gate:SetFrameStrata(button:GetFrameStrata())
    gate:EnableMouse(false)
    gate:SetAlpha(0)
    gate:Hide()
    local host = CreateFrame("Frame", nil, gate)
    host:SetAllPoints(gate)
    host:SetFrameLevel(gate:GetFrameLevel())
    host:EnableMouse(false)
    host:Hide()
    local library = LibStub and LibStub("LibCustomGlow-1.0", true)
    local appearance, started

    local function Stop()
        -- Hiding before ButtonGlow_Stop bypasses its visible fade-out, so a
        -- style change never leaves the old rim visible alongside the new one.
        host:Hide()
        if library and started then
            if started == "pixel" then library.PixelGlow_Stop(host, "ZwykPlus")
            elseif started == "autocast" then library.AutoCastGlow_Stop(host, "ZwykPlus")
            elseif started == "button" then library.ButtonGlow_Stop(host)
            elseif started == "proc" then library.ProcGlow_Stop(host, "ZwykPlus") end
        end
        started = nil
    end

    local function Start()
        if started or not appearance or not library then return end
        host:Show()
        local color = {appearance[2], appearance[3], appearance[4], 1}
        local style = appearance[1]
        if style == "pixel" then
            library.PixelGlow_Start(host, color, 8, 0.25, nil, 2, 0, 0, false, "ZwykPlus", 0)
        elseif style == "autocast" then
            library.AutoCastGlow_Start(host, color, 4, 0.125, 1, 0, 0, "ZwykPlus", 0)
        elseif style == "button" then
            library.ButtonGlow_Start(host, color, 0.125, 0)
        else
            library.ProcGlow_Start(host, {color = color, startAnim = true, key = "ZwykPlus", frameLevel = 0})
        end
        started = style
    end

    function gate:SetReminderAppearance(style, red, green, blue, opacity)
        style = Readable(style) and styles[style] and style or "pixel"
        red, green, blue = Number(red, 1), Number(green, 0.78), Number(blue, 0.12)
        opacity = Number(opacity, 1)
        local changed = not appearance or appearance[1] ~= style or appearance[2] ~= red
            or appearance[3] ~= green or appearance[4] ~= blue
        appearance = {style, red, green, blue, opacity}
        -- Ordinary opacity multiplies through inheritance, without reading or
        -- calculating with the gate's opaque aura-controlled alpha.
        host:SetAlpha(opacity)
        if changed then Stop() end
        Start()
        return library ~= nil
    end

    gate:SetScript("OnShow", Start)
    gate:SetScript("OnHide", Stop)
    gate:SetScript("OnSizeChanged", function()
        -- Blizzard's button/proc textures calculate their halo margins at
        -- startup. Rebuild from the icon's new public dimensions after a resize.
        if appearance then Stop(); Start() end
    end)
    return gate
end
