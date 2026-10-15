local _, ZP = ...

-- A dedicated native aura slot owns duration updates and visibility. Its
-- public wrapper is independent of competing buff/debuff glow renderers.
local displays = setmetatable({}, {__mode = "k"})

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
        and (not canaccessvalue or canaccessvalue(value))
end

local function Object(value)
    if not Public(value) or (type(value) ~= "table" and type(value) ~= "userdata") then return false end
    if type(value.IsForbidden) == "function" then
        local ok, forbidden = pcall(value.IsForbidden, value)
        if not ok or not Public(forbidden) or forbidden ~= false then return false end
    end
    return true
end

local function Level(frame)
    local value = frame:GetFrameLevel()
    assert(Public(value) and type(value) == "number" and value == value
        and value >= 0 and value < math.huge, "duration display frame level unavailable")
    return value
end

local function Family(family)
    if not Public(family) or type(family) ~= "table" then return end
    local ids, ordered = {}, {}
    for _, id in ipairs(family) do
        if not Public(id) or type(id) ~= "number" or id ~= id or id <= 0
            or id == math.huge or id ~= math.floor(id) then return end
        if not ids[id] then ids[id] = true; ordered[#ordered + 1] = id end
    end
    if #ordered == 0 then return end
    table.sort(ordered)
    for i, id in ipairs(ordered) do ordered[i] = tostring(id) end
    return table.concat(ordered, ","), ids
end

local function Enabled()
    local db = ZP.db
    return db and Public(db.buffReminder) and db.buffReminder == true
        and Public(db.buffReminderDurationText) and db.buffReminderDurationText == true or false
end

local function Hide(state)
    if state and state.wrapper then pcall(state.wrapper.Hide, state.wrapper) end
end

local function Prepare(button, state)
    if not state.wrapper then state.wrapper = CreateFrame("Frame", nil, UIParent) end
    if not state.wrapperBuilt then
        local wrapper, icon = state.wrapper, button.icon
        if Public(icon) and icon == nil then icon = button.Icon end
        if not Object(icon) then icon = button end
        wrapper:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        wrapper:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        wrapper:SetFrameLevel(Level(button) + 10)
        local strata = button:GetFrameStrata()
        assert(Public(strata) and type(strata) == "string", "duration display frame strata unavailable")
        wrapper:SetFrameStrata(strata)
        wrapper:EnableMouse(false)
        wrapper:Hide()
        state.wrapperBuilt = true
    end
    if not state.container then
        state.container = CreateFrame("AuraContainer", nil, state.wrapper, "CustomAuraContainerTemplate")
    end
    if not state.containerPrepared then
        state.container:SetAllPoints(state.wrapper)
        state.container:SetUnit("player")
        state.containerPrepared = true
    end
end

local function BuildText(frame, state)
    local holder = state.holder or CreateFrame("Frame", nil, frame)
    state.holder = holder
    holder:SetAllPoints(frame)
    holder:SetFrameLevel(Level(frame) + 3)
    holder:EnableMouse(false)
    local text = state.text or holder:CreateFontString(nil, "OVERLAY")
    state.text = text
    text:Hide()
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    text:SetTextColor(1, 1, 1, 1)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    state.textBuilt = true
end

local function BuildSwipe(frame, state)
    local cooldown = state.cooldown or CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    state.cooldown = cooldown
    cooldown:Hide()
    cooldown:SetAllPoints(frame)
    cooldown:SetFrameLevel(Level(frame) + 1)
    cooldown:EnableMouse(false)
    cooldown:SetReverse(true)
    cooldown:SetDrawSwipe(true)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.5)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetUseAuraDisplayTime(true)
    state.swipeBuilt = true
end

function ZP:ConfigureBuffDurationDisplay(existingFrame, button, showText, showSwipe, family)
    if not Public(button) or (type(button) ~= "table" and type(button) ~= "userdata") then
        return false, "duration display owner unavailable"
    end
    if not Public(existingFrame) or (type(existingFrame) ~= "table" and type(existingFrame) ~= "userdata") then
        return false, "duration display frame unavailable"
    end
    showText = Public(showText) and showText == true
    showSwipe = showText and Public(showSwipe) and showSwipe == true
    local state = displays[button]
    if not showText then Hide(state) end
    if InCombatLockdown then
        local ok, combat = pcall(InCombatLockdown)
        if not ok or not Public(combat) or combat ~= false then return false, "duration configuration deferred in combat" end
    end
    local ok, failure = pcall(function()
        assert(Object(existingFrame) and Object(button), "duration display owner unavailable")
        if not state and not showText then return end
        if not state then state = {}; displays[button] = state end
        state.ready = false
        local key, ids
        if showText then
            key, ids = Family(family)
            assert(key, "duration display spell family unavailable")
            Prepare(button, state)
            if state.familyKey ~= key then Hide(state) end
            if not state.frame then
                state.frame = state.container:AddAuraSlot("duration", "HELPFUL", {
                    candidateFilters = {includeSpellIDs = ids, maxDuration = math.huge},
                    initializeFrame = function(frame)
                        frame:SetAllPoints(state.container)
                        frame:SetMouseClickEnabled(false)
                        frame:SetMouseMotionEnabled(false)
                    end,
                })
            elseif state.familyKey ~= key then
                state.container:SetAuraSlotCandidateFilters("duration", {includeSpellIDs = ids, maxDuration = math.huge})
            end
        end
        local frame = state.frame
        if showText then
            assert(type(frame.SetDurationText) == "function", "native duration text unavailable")
            if not state.textBuilt then BuildText(frame, state) end
            if not state.textEnabled then
                frame:SetDurationText(state.text, {})
            end
            state.text:Show()
        elseif state.text then
            if state.textEnabled then frame:ClearDurationText() end
            state.text:Hide()
        end
        if showSwipe then
            assert(type(frame.SetDurationCooldown) == "function", "native duration swipe unavailable")
            if not state.swipeBuilt then BuildSwipe(frame, state) end
            if not state.swipeEnabled then
                frame:SetDurationCooldown(state.cooldown)
            end
        elseif state.cooldown then
            if state.swipeEnabled then frame:ClearDurationCooldown() end
            state.cooldown:Hide()
        end
        if state.container and state.containerEnabled ~= showText then
            state.container:SetEnabled(showText)
            state.containerEnabled = showText
        end
        state.textEnabled, state.swipeEnabled = showText, showSwipe
        state.family, state.familyKey, state.ready = family, key, showText
    end)
    if not ok then
        if state then
            Hide(state)
            if state.frame then
                pcall(state.frame.ClearDurationText, state.frame)
                pcall(state.frame.ClearDurationCooldown, state.frame)
            end
            state.textEnabled, state.swipeEnabled = false, false
            state.ready = false
        end
        return false, Public(failure) and type(failure) == "string" and failure:sub(1, 160)
            or "native duration display unavailable"
    end
    return true
end

function ZP:UpdateBuffDurationDisplay(button, family, visible, preview)
    if not Public(button) or (type(button) ~= "table" and type(button) ~= "userdata") then return false end
    local state = displays[button]
    if not state or not state.wrapper then return false end
    local key = Family(family)
    local matches = key ~= nil and key == state.familyKey
    local shown = Enabled() and state.ready and matches and Object(button)
        and Public(visible) and visible == true and Public(preview) and not preview or false
    local ok = pcall(state.wrapper.SetShown, state.wrapper, shown)
    return ok and shown
end

function ZP:HideBuffDurationDisplays()
    for _, state in pairs(displays) do Hide(state) end
end
