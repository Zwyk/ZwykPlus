local _, ZP = ...
local records = {}
local failures = {}
local events
local Update

local function Accessible(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function String(value)
    return Accessible(value) and type(value) == "string" and value ~= ""
end

local function Enabled()
    if ZP.Are3DPortraitsEnabled then return ZP:Are3DPortraitsEnabled() end
    return ZP.db and ZP.db.portraits3D
end

local function Restore(record, reason)
    record.reason = reason
    record.waiting = false
    record.model:SetScript("OnUpdate", nil)
    record.model:Hide()
    record.guid, record.unit = nil, nil
    if record.active then
        record.active = false
        record.portrait:SetShown(record.wasShown)
    end
end

local function WaitForModel(record)
    record.reason = "waiting for model"
    record.waiting = true
    record.loadAge, record.checkAge = record.loadAge or 0, 0
    if record.active then
        record.active = false
        record.portrait:SetShown(record.wasShown)
    end
    -- Hidden PlayerModels can postpone loading. Render transparently while the 2D fallback remains visible.
    record.model:SetAlpha(0)
    record.model:Show()
    record.model:SetScript("OnUpdate", function(_, elapsed)
        if not Accessible(elapsed) or type(elapsed) ~= "number" then return end
        record.loadAge = record.loadAge + elapsed
        record.checkAge = record.checkAge + elapsed
        if record.loadAge >= 5 then
            Restore(record, "model load timed out; Apply retries")
            record.guid, record.unit = nil, nil
        elseif record.checkAge >= 0.2 then
            record.checkAge = 0
            Update(record, false)
        end
    end)
end

Update = function(record, force)
    if record.binding then return end
    local frame, model = record.frame, record.model
    if not Enabled() then Restore(record, "disabled"); return end
    if frame.IsShown and not frame:IsShown() then Restore(record, "native frame hidden"); return end
    local unit = frame.unit
    if not String(unit) then Restore(record, "public unit token unavailable"); return end
    if not UnitIsVisible then Restore(record, "unit visibility API unavailable"); return end
    local visibleOK, visible = pcall(UnitIsVisible, unit)
    if not visibleOK or not Accessible(visible) or not visible then
        Restore(record, visibleOK and Accessible(visible) and "unit not visible" or "unit visibility restricted/unavailable")
        record.guid, record.unit = nil, nil
        return
    end
    if UnitIsDeadOrGhost then
        local ok, dead = pcall(UnitIsDeadOrGhost, unit)
        if not ok or not Accessible(dead) or dead then
            Restore(record, ok and Accessible(dead) and "dead or ghost" or "unit status restricted/unavailable")
            record.guid, record.unit = nil, nil
            return
        end
    end
    -- GUID is an optional cache hint, never a prerequisite for SetUnit with a public unit token.
    local guid
    if UnitGUID then
        local ok, value = pcall(UnitGUID, unit)
        if ok and String(value) then guid = value end
    end
    if force or record.guid ~= guid or record.unit ~= unit then
        record.guid, record.unit = guid, unit
        record.configured = false
        record.loadAge = 0
        record.binding = true
        model:SetAlpha(0)
        model:Show()
        model:ClearModel()
        local ok, result = pcall(model.SetUnit, model, unit)
        record.binding = false
        record.setUnitResult = not ok and "error" or not Accessible(result) and "restricted" or
            result == false and "false" or result == true and "true" or "no return"
        if not ok or not Accessible(result) or result == false then
            Restore(record, ok and "SetUnit rejected/restricted" or "SetUnit failed")
            record.guid, record.unit = nil, nil
            return
        end
    end
    local modelOK, modelID = pcall(model.GetModelFileID, model)
    if not modelOK or not Accessible(modelID) then
        Restore(record, "model ID restricted/unavailable")
        record.guid, record.unit = nil, nil
        return
    end
    if type(modelID) ~= "number" or modelID <= 0 then
        WaitForModel(record)
        return
    end
    if not record.configured then
        -- Configure after asynchronous loading, which can reset the model's camera/animation.
        local ok = pcall(function()
            model:SetPortraitZoom(1)
            model:SetPosition(0, 0, 0)
            model:SetFacing(0)
            model:SetAnimation(0, 0) -- Stand/idle, animation ID 0.
            if model.SetPaused then model:SetPaused(false) end
        end)
        if not ok then
            Restore(record, "head camera/idle animation configuration failed")
            record.guid, record.unit = nil, nil
            return
        end
        record.configured = true
    end
    if not record.active then
        record.wasShown = record.portrait:IsShown()
        record.active = true
    end
    record.reason, record.waiting = "3D active", false
    model:SetScript("OnUpdate", nil)
    record.portrait:Hide()
    model:SetAlpha(1)
    model:Show()
end

local function Portrait(frame)
    return frame.portrait or frame.Portrait or
        (frame.PlayerFrameContainer and frame.PlayerFrameContainer.PlayerPortrait) or
        (frame.TargetFrameContainer and frame.TargetFrameContainer.Portrait)
end

local function AddFrame(frame, label)
    if not frame or records[frame] then return end
    if frame.IsForbidden and frame:IsForbidden() then failures[label] = "forbidden frame"; return end
    local portrait = Portrait(frame)
    if not portrait or not portrait.GetParent then failures[label] = "no native portrait"; return end
    local parent = portrait:GetParent()
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, parent)
    if not ok or not model then failures[label] = "model creation failed"; return end
    if not (model.SetUnit and model.SetPortraitZoom and model.GetModelFileID and model.SetAnimation) then
        failures[label] = "missing model API"; model:Hide(); return
    end
    -- Preserve loaded contents across visibility changes; otherwise a cached unit can point to an empty model.
    if model.SetKeepModelOnHide then model:SetKeepModelOnHide(true) end
    model:Hide()
    model:SetAllPoints(portrait)
    model:EnableMouse(false)
    -- Stay behind native frame borders and keep unit-frame mouse interactions intact.
    model:SetFrameLevel(parent:GetFrameLevel())
    if model.SetModelDrawLayer then model:SetModelDrawLayer("BACKGROUND") end
    local record = {frame = frame, portrait = portrait, model = model, label = label, reason = "not updated"}
    records[frame] = record
    failures[label] = nil
    model:SetScript("OnModelLoaded", function()
        record.configured = false
        Update(record, false)
    end)
    model:SetScript("OnAnimFinished", function()
        if record.active and Enabled() then model:SetAnimation(0, 0) end
    end)
end

local function Candidates()
    local candidates = {}
    for _, name in ipairs({"PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame"}) do
        candidates[#candidates + 1] = {label = name, frame = _G[name]}
    end
    if PartyFrame and PartyFrame.MemberFrame then
        for index, frame in ipairs(PartyFrame.MemberFrame) do
            candidates[#candidates + 1] = {label = "PartyFrame.MemberFrame" .. index, frame = frame}
        end
    end
    for i = 1, 4 do
        local frame = _G["PartyMemberFrame" .. i]
        if frame then candidates[#candidates + 1] = {label = "PartyMemberFrame" .. i, frame = frame} end
    end
    return candidates
end

local function Discover()
    for _, entry in ipairs(Candidates()) do AddFrame(entry.frame, entry.label) end
end

local function Value(object, method)
    if not object or not object[method] then return "unavailable" end
    local ok, value = pcall(object[method], object)
    if not ok then return "error" end
    if not Accessible(value) then return "restricted" end
    if type(value) == "boolean" then return value and "yes" or "no" end
    if type(value) == "number" or type(value) == "string" then return tostring(value) end
    return "unavailable"
end

function ZP:GetPortraitDiagnostics()
    local saved, enabled = self.db and self.db.portraits3D, Enabled()
    local combat = InCombatLockdown and InCombatLockdown()
    local lines = {"3D portraits: saved=" .. (saved and "yes" or "no") .. "; active=" .. (enabled and "yes" or "no") ..
        "; pendingReload=" .. (not not saved ~= not not enabled and "yes" or "no") .. "; combat=" .. (combat and "yes" or "no")}
    for _, entry in ipairs(Candidates()) do
        local frame, record = entry.frame, entry.frame and records[entry.frame]
        local reason = record and record.reason or failures[entry.label] or
            (not frame and "native frame unavailable" or not enabled and "disabled" or combat and "creation deferred in combat" or "not initialized")
        lines[#lines + 1] = entry.label .. ": " .. reason
        if record then
            local unit = String(frame.unit) and frame.unit or "restricted/unavailable"
            lines[#lines + 1] = "  unit=" .. unit .. "; SetUnit=" .. (record.setUnitResult or "not called") ..
                "; loading=" .. (record.waiting and "yes" or "no") .. "; modelID=" .. Value(record.model, "GetModelFileID") ..
                "; 2Dshown=" .. Value(record.portrait, "IsShown") .. "; 3Dshown=" .. Value(record.model, "IsShown") ..
                "; 3Dvisible=" .. Value(record.model, "IsVisible") .. "; alpha=" .. Value(record.model, "GetAlpha") ..
                "; keepOnHide=" .. Value(record.model, "GetKeepModelOnHide")
            lines[#lines + 1] = "  portrait=" .. Value(record.portrait, "GetWidth") .. "x" .. Value(record.portrait, "GetHeight") ..
                "; model=" .. Value(record.model, "GetWidth") .. "x" .. Value(record.model, "GetHeight") ..
                "; frameLevel=" .. Value(record.model, "GetFrameLevel") .. "; drawLayer=" .. Value(record.model, "GetModelDrawLayer")
            lines[#lines + 1] = "  headZoom=" .. (record.configured and "1" or "not configured") ..
                "; idleAnimation=" .. (record.configured and "Stand (0)" or "not configured") .. "; paused=" .. Value(record.model, "GetPaused")
        end
    end
    return lines
end

function ZP:RefreshPortraits(force)
    if Enabled() then
        -- Creating/layout changes wait until combat ends; existing model content can update.
        if not InCombatLockdown or not InCombatLockdown() then Discover() end
    end
    for _, record in pairs(records) do Update(record, force) end
end

function ZP:InitializePortraits()
    if events then return end
    events = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "GROUP_ROSTER_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION",
        "UNIT_FLAGS", "UNIT_PET", "PLAYER_REGEN_ENABLED", "ADDON_LOADED"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event)
        ZP:RefreshPortraits(event ~= "ADDON_LOADED" and event ~= "PLAYER_REGEN_ENABLED" and event ~= "UNIT_FLAGS")
    end)
    if hooksecurefunc and UnitFramePortrait_Update then
        hooksecurefunc("UnitFramePortrait_Update", function(frame)
            local record = records[frame]
            if record then Update(record, false) end
        end)
    end
    self:RefreshPortraits(true)
end
