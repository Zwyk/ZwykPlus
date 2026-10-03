local _, ZP = ...
local records = {}
local events

local function Accessible(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function String(value)
    return Accessible(value) and type(value) == "string" and value ~= ""
end

local function Restore(record)
    record.model:Hide()
    if record.active then
        record.active = false
        record.portrait:SetShown(record.wasShown)
    end
end

local function Update(record, force)
    local frame, model = record.frame, record.model
    if not ZP.db or not ZP.db.portraits3D or (frame.IsShown and not frame:IsShown()) then
        Restore(record)
        return
    end
    local unit = frame.unit
    if not String(unit) or not (UnitGUID and UnitIsVisible) then Restore(record); return end
    local visibleOK, visible = pcall(UnitIsVisible, unit)
    local guidOK, guid = pcall(UnitGUID, unit)
    if not visibleOK or not Accessible(visible) or not visible or not guidOK or not String(guid) then
        Restore(record)
        record.guid = nil
        return
    end
    if UnitIsDeadOrGhost then
        local ok, dead = pcall(UnitIsDeadOrGhost, unit)
        if not ok or not Accessible(dead) or dead then Restore(record); record.guid = nil; return end
    end
    if force or record.guid ~= guid or record.unit ~= unit then
        record.guid, record.unit = guid, unit
        model:ClearModel()
        local ok, result = pcall(model.SetUnit, model, unit)
        if not ok or not Accessible(result) or result == false then Restore(record); record.guid = nil; return end
        model:SetPortraitZoom(1)
        model:SetPosition(0, 0, 0)
        model:SetFacing(0)
    end
    local modelOK, modelID = pcall(model.GetModelFileID, model)
    if not modelOK or not Accessible(modelID) or type(modelID) ~= "number" or modelID <= 0 then
        Restore(record)
        return
    end
    if not record.active then
        record.wasShown = record.portrait:IsShown()
        record.active = true
    end
    record.portrait:Hide()
    model:Show()
end

local function AddFrame(frame)
    if not frame or records[frame] then return end
    local portrait = frame.portrait or frame.Portrait
    if not portrait or not portrait.GetParent then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    local parent = portrait:GetParent()
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, parent)
    if not ok or not model then return end
    if not (model.SetUnit and model.SetPortraitZoom and model.GetModelFileID) then model:Hide(); return end
    model:Hide()
    model:SetAllPoints(portrait)
    model:EnableMouse(false)
    -- Stay behind native frame borders and keep unit-frame mouse interactions intact.
    model:SetFrameLevel(parent:GetFrameLevel())
    if model.SetModelDrawLayer then model:SetModelDrawLayer("BACKGROUND") end
    local record = {frame = frame, portrait = portrait, model = model}
    records[frame] = record
    model:SetScript("OnModelLoaded", function() Update(record, false) end)
end

local function Discover()
    for _, name in ipairs({"PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame"}) do AddFrame(_G[name]) end
    if PartyFrame and PartyFrame.MemberFrame then
        for _, frame in ipairs(PartyFrame.MemberFrame) do AddFrame(frame) end
    end
    for i = 1, 4 do AddFrame(_G["PartyMemberFrame" .. i]) end
end

function ZP:RefreshPortraits(force)
    if self.db and self.db.portraits3D then
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
        ZP:RefreshPortraits(event == "UNIT_MODEL_CHANGED" or event == "UNIT_PORTRAIT_UPDATE")
    end)
    if hooksecurefunc and UnitFramePortrait_Update then
        hooksecurefunc("UnitFramePortrait_Update", function(frame)
            local record = records[frame]
            if record then Update(record, false) end
        end)
    end
    self:RefreshPortraits(true)
end
