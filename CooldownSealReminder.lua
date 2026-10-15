local _, ZP = ...

-- CDM keeps ownership of the live aura state. Its opaque active boolean is
-- passed only to a rendering sink, never used to start timers or make choices.
local bindings, hooked = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
local source, sourceID, sourceViewer, events, refreshing
local status, items, forwards, errors, lastError = "disabled", {}, 0, 0, nil
local selectedCasts, unreadableCasts = 0, 0
local viewers = {"BuffIconCooldownViewer", "BuffBarCooldownViewer", "EssentialCooldownViewer", "UtilityCooldownViewer"}
local sealFamilies = {
    {1311649, 1311656, 20163, 20419, 20421, 20422, 20423},
    {20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293},
    {20375, 20915, 20918, 20919, 20920}, {20164},
    {20165, 20347, 20348, 20349}, {20166, 20356, 20357},
    {21082, 20162, 20305, 20306, 20307, 20308},
}
local sealFamilyByID = {}
for family, ids in ipairs(sealFamilies) do
    for _, id in ipairs(ids) do sealFamilyByID[id] = family end
end

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
        and (not canaccessvalue or canaccessvalue(value))
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value > 0 and value < math.huge and value == math.floor(value)
end

local function Selection()
    local id = ZwykPlusLastSeal
    local family = Number(id) and sealFamilyByID[id]
    if family and family ~= 7 then return id, family end
end

local function Flag(value)
    if not Public(value) then return "private" end
    if value == nil then return "missing" end
    if type(value) ~= "boolean" then return "invalid" end
    return value and "yes" or "no"
end

local function Enabled()
    local db = ZP.db
    return db and Public(db.buffReminder) and db.buffReminder == true
        and Public(db.buffReminderMissingSeal) and db.buffReminderMissingSeal == true or false
end

local function ViewerEnabled()
    local getter = C_CVar and C_CVar.GetCVarBool or GetCVarBool
    if type(getter) ~= "function" then return false end
    local ok, enabled = pcall(getter, "cooldownViewerEnabled")
    return ok and Public(enabled) and enabled == true
end

local function Object(object)
    if not Public(object) or (type(object) ~= "table" and type(object) ~= "userdata") then return false end
    if type(object.IsForbidden) == "function" then
        local ok, forbidden = pcall(object.IsForbidden, object)
        if not ok or not Public(forbidden) or forbidden ~= false then return false end
    end
    return true
end

local function Visible(viewer)
    if not Object(viewer) or type(viewer.IsVisible) ~= "function" then return false end
    local ok, visible = pcall(viewer.IsVisible, viewer)
    return ok and Public(visible) and visible == true
end

local function Error(value)
    errors = errors + 1
    lastError = Public(value) and type(value) == "string" and value:sub(1, 160) or "CDM render request failed"
end

local function Hide(binding)
    binding.eligible = false
    if binding.glow then
        pcall(binding.glow.Hide, binding.glow)
        pcall(binding.glow.SetAlpha, binding.glow, 0)
    end
end

local function ClearSource()
    source, sourceID, sourceViewer = nil, nil, nil
    for _, binding in pairs(bindings) do Hide(binding) end
end

local function ObserveCast(unit, spellID)
    if not Public(unit) or unit ~= "player" then return end
    if not Number(spellID) then unreadableCasts = unreadableCasts + 1; return end
    local family = sealFamilyByID[spellID]
    -- Crusader is a temporary step before Judgement, not the seal to resume.
    if not family or family == 7 then return end
    ZwykPlusLastSeal = spellID
    selectedCasts = selectedCasts + 1
    for _, binding in pairs(bindings) do
        if binding.family ~= family then Hide(binding) end
    end
end

local function Forward(binding, active)
    -- Do not test, compare, format, or remember active: it may be a secret.
    local ok, failure = pcall(binding.glow.SetAlphaFromBoolean, binding.glow, active, 0, 1)
    if ok then forwards = forwards + 1 else Error(failure); Hide(binding) end
    return ok
end

local function Ready()
    if not Enabled() or not ViewerEnabled() or not source or not Visible(sourceViewer) then return false end
    local ok, id = pcall(source.GetCooldownID, source)
    return ok and Number(id) and id == sourceID
end

local function HookItem(item)
    if hooked[item] or type(hooksecurefunc) ~= "function" then return end
    hooked[item] = true
    if type(item.SetIsActive) == "function" then
        hooksecurefunc(item, "SetIsActive", function(self, active)
            if self == source then
                if not Ready() then ClearSource(); return end
                for _, binding in pairs(bindings) do
                    if binding.eligible and binding.glow then Forward(binding, active) end
                end
            end
        end)
    end
    for _, method in ipairs({"SetCooldownID", "ResetCooldownData"}) do
        if type(item[method]) == "function" then
            local reset = method == "ResetCooldownData"
            hooksecurefunc(item, method, function(self)
                if self == source then
                    local ok, id = pcall(self.GetCooldownID, self)
                    if reset or not ok or not Number(id) or id ~= sourceID then ClearSource() end
                end
                if not refreshing then ZP:RefreshCooldownSealReminder() end
            end)
        end
    end
end

local function RequiredFamilies()
    local required, getter = {}, C_SpellBook and C_SpellBook.IsSpellKnown
    for family, ids in ipairs(sealFamilies) do
        local known, uncertain = false, type(getter) ~= "function"
        if not uncertain then
            for _, id in ipairs(ids) do
                local ok, value = pcall(getter, id)
                if not ok or not Public(value) or type(value) ~= "boolean" then uncertain = true
                elseif value == true then known = true end
            end
        end
        if known or uncertain then required[family] = true end
    end
    return required
end

local function Metadata(info, required)
    if not Public(info) or type(info) ~= "table" then return nil, 0 end
    local ids, seen, families = {}, {}, {}
    local function Add(id)
        if Number(id) and not seen[id] then
            seen[id] = true; ids[#ids + 1] = id
            if sealFamilyByID[id] then families[sealFamilyByID[id]] = true end
        end
    end
    Add(info.spellID); Add(info.overrideSpellID); Add(info.overrideTooltipSpellID)
    local linked, sealOnlyLinks = info.linkedSpellIDs, true
    if Public(linked) and type(linked) == "table" then
        for _, id in ipairs(linked) do
            Add(id)
            if not Number(id) or not sealFamilyByID[id] then sealOnlyLinks = false end
        end
    else sealOnlyLinks = false end
    local count = 0
    for _ in pairs(families) do count = count + 1 end
    table.sort(ids)
    for i, id in ipairs(ids) do ids[i] = tostring(id) end
    -- Forever's grouped Seals placeholder need not be learned or marked as
    -- an aura itself. Its native buff row tracks the linked self-cast seals.
    -- Require the complete recognized group before relaxing those flags.
    local sealPlaceholder = seen[1323522] == true and count == #sealFamilies and sealOnlyLinks
    local usable = sealPlaceholder or Public(info.isKnown) and info.isKnown == true
        and Public(info.hasAura) and info.hasAura == true
        and Public(info.selfAura) and info.selfAura == true and sealOnlyLinks
    local coversKnown = true
    for family in pairs(required) do if not families[family] then coversKnown = false end end
    local flags = "; known=" .. Flag(info.isKnown) .. "; hasAura=" .. Flag(info.hasAura)
        .. "; selfAura=" .. Flag(info.selfAura) .. "; sealPlaceholder=" .. (sealPlaceholder and "yes" or "no")
    return table.concat(ids, ","), count, usable, coversKnown, sealOnlyLinks, flags
end

local function InitializeEvents()
    if events then return end
    events = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "COOLDOWN_VIEWER_DATA_LOADED",
        "COOLDOWN_VIEWER_TABLE_HOTFIXED", "CVAR_UPDATE", "PLAYER_REGEN_ENABLED"}) do
        pcall(events.RegisterEvent, events, event)
    end
    if type(events.RegisterUnitEvent) == "function" then
        pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
    else pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_SUCCEEDED") end
    events:SetScript("OnEvent", function(_, event, unit, _castGUID, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then ObserveCast(unit, spellID)
        else ZP:RefreshCooldownSealReminder() end
    end)
end

function ZP:RefreshCooldownSealReminder()
    if refreshing then return end
    refreshing = true
    InitializeEvents()
    local enabled, selected, selectedID, selectedViewer = Enabled()
    local required = RequiredFamilies()
    items = {}
    local api = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if type(api) == "function" then
        for index, name in ipairs(viewers) do
            local viewer = _G[name]
            if Object(viewer) then
                if not hooked[viewer] then
                    hooked[viewer] = true
                    if type(viewer.HookScript) == "function" then
                        viewer:HookScript("OnHide", function()
                            if viewer == sourceViewer then ClearSource(); status = "viewer-hidden" end
                        end)
                        viewer:HookScript("OnShow", function() ZP:RefreshCooldownSealReminder() end)
                    end
                    if index <= 2 and type(hooksecurefunc) == "function" and type(viewer.OnAcquireItemFrame) == "function" then
                        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, item)
                            if Enabled() and Object(item) then HookItem(item) end
                        end)
                    end
                end
                local pool = viewer.itemFramePool
                if Public(pool) and type(pool) == "table" and type(pool.EnumerateActive) == "function" then
                    local ok, failure = pcall(function()
                        for item in pool:EnumerateActive() do
                            if Object(item) and type(item.GetCooldownID) == "function" then
                                if index <= 2 and enabled then HookItem(item) end
                                local got, id = pcall(item.GetCooldownID, item)
                                if got and Number(id) then
                                    local read, info = pcall(api, id)
                                    local ids, count, usable, coversKnown, sealOnlyLinks, flags = nil, 0, false, false, false, ""
                                    if read then ids, count, usable, coversKnown, sealOnlyLinks, flags = Metadata(info, required) end
                                    items[#items + 1] = name .. ": cooldown=" .. id .. "; spells=" .. (ids or "unavailable")
                                        .. "; sealFamilies=" .. count .. "; trackable=" .. (usable and "yes" or "no")
                                        .. "; coversKnown=" .. (coversKnown and "yes" or "no")
                                        .. "; sealOnlyLinks=" .. (sealOnlyLinks and "yes" or "no") .. (flags or "")
                                    if index <= 2 and enabled then
                                        if not selected and usable and coversKnown and count >= 2 and ViewerEnabled() and Visible(viewer)
                                            and type(item.IsActive) == "function" then
                                            selected, selectedID, selectedViewer = item, id, viewer
                                        end
                                    end
                                end
                            end
                        end
                    end)
                    if not ok then Error(failure) end
                end
            end
        end
    end
    if source ~= selected or sourceID ~= selectedID or sourceViewer ~= selectedViewer then ClearSource() end
    source, sourceID, sourceViewer = selected, selectedID, selectedViewer
    status = not enabled and "disabled" or type(api) ~= "function" and "CDM-unavailable"
        or not ViewerEnabled() and "CDM-disabled"
        or source and (Selection() and "native-presence-forwarding" or "waiting-for-seal-cast")
        or "grouped-seal-source-unavailable"
    refreshing = false
end

function ZP:UpdateCooldownSealReminderButton(button, isSeal, visible, preview, spellID)
    if not Public(button) or (type(button) ~= "table" and type(button) ~= "userdata") then return false end
    local binding = bindings[button]
    local eligible = Enabled() and Object(button) and isSeal == true and visible == true and not preview and Ready()
    if not binding and not eligible then return false end
    if not eligible then if binding then Hide(binding) end; return false end
    local _, selectedFamily = Selection()
    local family = Number(spellID) and sealFamilyByID[spellID]
    if not selectedFamily or family ~= selectedFamily then
        if binding then Hide(binding) end
        -- Own every seal's missing state so the ordinary after-expiry path
        -- cannot light a different seal while this mode is available.
        return true
    end
    if not binding then binding = {}; bindings[button] = binding end
    binding.family, binding.eligible = family, true
    if not binding.glow then
        local ok, glow = pcall(self.CreateBuffGlow, self, button)
        if not ok or not Object(glow) then Error(glow); binding.eligible = false; return false end
        binding.glow = glow
    end
    local glow = binding.glow
    if type(glow.SetAlphaFromBoolean) ~= "function" then Error("native boolean alpha unavailable"); Hide(binding); return false end
    local style, red, green, blue, opacity = "button", 1, 0.78, 0.12, 1
    if self.GetBuffReminderAppearance then style, red, green, blue, opacity = self:GetBuffReminderAppearance(true) end
    local ok, applied = pcall(glow.SetReminderAppearance, glow, style, red, green, blue, opacity)
    if not ok or not Public(applied) or applied == false then Error(applied); Hide(binding); return false end
    local shown, failure = pcall(glow.Show, glow)
    if not shown then Error(failure); Hide(binding); return false end
    local read, active = pcall(source.IsActive, source)
    if read then return Forward(binding, active) end
    Error(active); Hide(binding)
    return false
end

function ZP:GetCooldownSealReminderDiagnostics()
    self:RefreshCooldownSealReminder()
    local count = 0
    for _, binding in pairs(bindings) do if binding.eligible then count = count + 1 end end
    local selectedID, selectedFamily = Selection()
    local result = {enabled = Enabled(), status = status, sourceCooldownID = sourceID,
        selectedSpellID = selectedID, selectedFamily = selectedFamily and sealFamilies[selectedFamily][1],
        selectedCasts = selectedCasts, unreadableCasts = unreadableCasts,
        bindings = count, forwards = forwards, errors = errors, lastError = lastError, items = {}}
    for i, line in ipairs(items) do result.items[i] = line end
    return result
end
