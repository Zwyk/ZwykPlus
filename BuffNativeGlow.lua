local _, ZP = ...

-- The native aura button owns aura visibility, its timer bar and animation
-- playback. Lua never reads the resulting duration, alpha or secret geometry.
local renderers = setmetatable({}, {__mode = "k"})
local styles = {pixel = true, autocast = true, button = true, proc = true}
local gateWidth, margin = 20000, 6

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
        and (not canaccessvalue or canaccessvalue(value))
end

local function Fraction(value, fallback)
    if not Public(value) or type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then return fallback end
    return math.max(0, math.min(1, value))
end

local function Layer(holder)
    local frame = CreateFrame("Frame", nil, holder)
    frame:SetAllPoints(holder)
    frame:EnableMouse(false)
    frame:Hide()
    return {frame = frame, textures = {}, groups = {}}
end

local function Texture(layer, texture, atlas)
    local region = layer.frame:CreateTexture(nil, "OVERLAY")
    if atlas then region:SetAtlas(texture) else region:SetTexture(texture) end
    region:SetBlendMode("ADD")
    layer.textures[#layer.textures + 1] = region
    return region
end

local function Alpha(group, order, from, to, duration)
    local animation = group:CreateAnimation("Alpha")
    animation:SetOrder(order)
    animation:SetFromAlpha(from)
    animation:SetToAlpha(to)
    animation:SetDuration(duration)
end

local function Pulse(layer, texture, phase, low, duration)
    local group = texture:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    -- Equal cycle lengths keep the rim's pulses staggered without Lua updates.
    local order = 1
    if phase > 0 then
        Alpha(group, order, low, low, phase)
        order = order + 1
    end
    Alpha(group, order, low, 1, duration)
    Alpha(group, order + 1, 1, low, duration)
    local rest = 1.2 - phase - duration * 2
    if rest > 0 then Alpha(group, order + 2, low, low, rest) end
    layer.groups[#layer.groups + 1] = group
end

local function Border(texture, frame, outset)
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", -outset, outset)
    texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", outset, -outset)
end

local function Build(frame)
    local state = {layers = {}, selected = nil, registered = {}}
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetWidth(gateWidth)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetAlpha(0)
    state.bar = bar
    state.fill = bar:GetStatusBarTexture()

    -- Secret-derived frame clipping can suppress rendering in restricted
    -- contexts. A fixed, nonzero-width mask follows the native fill instead;
    -- only its position changes, and no secret geometry is read by Lua.
    local mask = frame:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    mask:SetWidth(gateWidth)
    mask:SetPoint("TOPLEFT", state.fill, "TOPRIGHT", 0, 0)
    mask:SetPoint("BOTTOMLEFT", state.fill, "BOTTOMRIGHT", 0, 0)
    state.mask = mask
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder:EnableMouse(false)

    local pixel = Layer(holder)
    state.layers.pixel = pixel
    local corners = {"TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMLEFT"}
    for index, corner in ipairs(corners) do
        local left = corner == "TOPLEFT" or corner == "BOTTOMLEFT"
        local top = corner == "TOPLEFT" or corner == "TOPRIGHT"
        for axis = 1, 2 do
            local line = Texture(pixel, "Interface\\Buttons\\WHITE8X8")
            line:SetPoint(corner, pixel.frame, corner, left and -1 or 1, top and 1 or -1)
            line:SetSize(axis == 1 and 10 or 2, axis == 1 and 2 or 10)
            Pulse(pixel, line, (index - 1) * 0.2 + (axis - 1) * 0.1, 0.3, 0.15)
        end
    end

    local autocast = Layer(holder)
    state.layers.autocast = autocast
    for index, corner in ipairs(corners) do
        local spark = Texture(autocast, "Interface\\SpellActivationOverlay\\IconAlert")
        spark:SetTexCoord(0.0078125, 0.6171875, 0.00390625, 0.26953125)
        spark:SetSize(16, 16)
        spark:SetPoint("CENTER", autocast.frame, corner, 0, 0)
        Pulse(autocast, spark, (index - 1) * 0.2, 0.15, 0.25)
    end

    local button = Layer(holder)
    state.layers.button = button
    local halo = Texture(button, "Interface\\SpellActivationOverlay\\IconAlert")
    halo:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
    Border(halo, button.frame, margin)
    Pulse(button, halo, 0, 0.45, 0.6)

    local proc = Layer(holder)
    state.layers.proc = proc
    local flipbook = Texture(proc, "UI-HUD-ActionBar-Proc-Loop-Flipbook", true)
    Border(flipbook, proc.frame, margin)
    local loop = flipbook:CreateAnimationGroup()
    loop:SetLooping("REPEAT")
    local animation = loop:CreateAnimation("FlipBook")
    animation:SetOrder(1)
    animation:SetDuration(1)
    animation:SetFlipBookRows(6)
    animation:SetFlipBookColumns(5)
    animation:SetFlipBookFrames(30)
    proc.groups[1] = loop

    -- Every style, including ones selected later, shares the same native gate.
    for _, layer in pairs(state.layers) do
        for _, texture in ipairs(layer.textures) do texture:AddMaskTexture(mask) end
    end

    -- This call delegates the secret fraction and ticking to the client.
    frame:SetDurationBar(bar, {direction = Enum.StatusBarTimerDirection.RemainingTime})
    renderers[frame] = state
    return state
end

function ZP:ConfigureBuffNativeGlow(frame, button, threshold, style, red, green, blue, opacity)
    if not frame or not Enum or not Enum.StatusBarTimerDirection
        or Enum.StatusBarTimerDirection.RemainingTime == nil then return false, "native timer direction unavailable" end
    threshold = Fraction(threshold, 0.2)
    style = Public(style) and styles[style] and style or "pixel"
    red, green, blue = Fraction(red, 1), Fraction(green, 0.78), Fraction(blue, 0.12)
    opacity = Fraction(opacity, 1)
    local ok, failure = pcall(function()
        assert(type(frame.SetDurationBar) == "function"
            and type(frame.AddAuraShownAnimation) == "function"
            and type(frame.RemoveAuraShownAnimation) == "function")
        local state = renderers[frame] or Build(frame)
        local layer = state.layers[style]
        if state.selected ~= layer then
            if state.selected then
                for _, group in ipairs(state.selected.groups) do
                    frame:RemoveAuraShownAnimation(group)
                    state.registered[group] = nil
                    group:Stop()
                end
                state.selected.frame:Hide()
                state.selected = nil
            end
            -- Texture values are public configuration, written before adopting
            -- the groups. Registered targets all descend from the aura button.
            for _, texture in ipairs(layer.textures) do
                texture:SetDesaturated(true)
                texture:SetVertexColor(red, green, blue)
            end
            layer.frame:SetAlpha(opacity)
            layer.frame:Show()
            for _, group in ipairs(layer.groups) do
                frame:AddAuraShownAnimation(group)
                state.registered[group] = true
                -- The aura may already be visible after a settings change.
                -- Parent visibility still suppresses an absent aura.
                group:Play()
            end
            state.selected = layer
        else
            for _, texture in ipairs(layer.textures) do texture:SetVertexColor(red, green, blue) end
            layer.frame:SetAlpha(opacity)
            for _, group in ipairs(layer.groups) do group:Play() end
        end

        -- At fraction p the fixed mask begins at RIGHT + margin + (p-t)*K.
        -- Above t it lies past the glow; below t it sweeps over the icon rim.
        -- Its width remains K even at zero, avoiding zero-area mask leakage.
        state.bar:ClearAllPoints()
        state.bar:SetPoint("TOPLEFT", frame, "TOPRIGHT", margin - threshold * gateWidth, margin)
        state.bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", margin - threshold * gateWidth, -margin)
    end)
    if not ok then
        local state = renderers[frame]
        if state then
            -- A failed reconfiguration must not leave a partial glow beside
            -- the caller's supported fallback indicator.
            for group in pairs(state.registered) do
                pcall(frame.RemoveAuraShownAnimation, frame, group)
                pcall(group.Stop, group)
                state.registered[group] = nil
            end
            for _, layer in pairs(state.layers) do pcall(layer.frame.Hide, layer.frame) end
            state.selected = nil
        end
        return false, Public(failure) and type(failure) == "string" and failure or "native renderer unavailable"
    end
    return true
end

function ZP:ResumeBuffNativeGlow(frame)
    local state = renderers[frame]
    if not state or not state.selected then return false, "native glow not configured" end
    local ok, failure = pcall(function()
        -- Used after the public preview temporarily hides our wrapper. There
        -- is no visibility/progress query, target mutation or script callback.
        for _, group in ipairs(state.selected.groups) do group:Play() end
    end)
    if not ok then
        return false, Public(failure) and type(failure) == "string" and failure or "native animation resume unavailable"
    end
    return true
end
