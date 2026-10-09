local _, ZP = ...
local L = ZP.L
local events = CreateFrame("Frame")
local panel, saved, members
local lastReport = {state = "inactive", members = {}}
local elapsed, rosterElapsed = 0, 0
local initialized, moving = false, false
local manaType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function String(value)
    return Readable(value) and type(value) == "string" and value ~= ""
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and Readable(value) then return value end
end

local function State()
    if saved then return saved end
    saved = {members = {}}
    local old = ZwykPlusHealerManaState
    if Readable(old) and type(old) == "table" then
        local position = old.position
        if Readable(position) and type(position) == "table" and Number(position.x) and Number(position.y) then
            saved.position = {x = position.x, y = position.y}
        end
        if Readable(old.members) and type(old.members) == "table" then
            for guid, value in pairs(old.members) do
                if String(guid) and #guid <= 128 and Readable(value) and type(value) == "boolean" then
                    saved.members[guid] = value
                end
            end
        end
    end
    ZwykPlusHealerManaState = saved
    return saved
end

local function Group()
    local raid = Call(IsInRaid) == true
    local count = Call(raid and GetNumGroupMembers or GetNumSubgroupMembers)
    if not Number(count) then count = Call(raid and GetNumRaidMembers or GetNumPartyMembers) end
    if not raid and not Number(count) then
        count = Call(GetNumGroupMembers)
        if Number(count) then count = count - 1 end
    end
    if not Number(count) or count < 1 then return raid, 0 end
    return raid, math.min(raid and 40 or 4, math.floor(count))
end

local function DisplayName(unit)
    local name = NameUtil and Call(NameUtil.FormatUnitNameForDisplay, unit, true)
    if String(name) then return name end
    if not UnitName then return L.healerManaUnknown end
    local ok, first, second = pcall(UnitName, unit)
    if not ok or not String(first) then return L.healerManaUnknown end
    if String(second) then
        local separator = Constants and Constants.CharacterNameSeparatorConsts
            and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
        first = first .. (String(separator) and separator or " ") .. second
    end
    return first
end

local function Class(unit)
    if not UnitClass then return nil, 1, 1, 1 end
    local ok, _, class = pcall(UnitClass, unit)
    if not ok or not String(class) then return nil, 1, 1, 1 end
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local color = colors and colors[class]
    if Readable(color) and type(color) == "table" and Number(color.r) and Number(color.g) and Number(color.b) then
        return class, color.r, color.g, color.b
    end
    return class, 1, 1, 1
end

local function Role(unit, raidIndex)
    local role = Call(UnitGroupRolesAssigned, unit)
    if String(role) and role ~= "NONE" then return role end
    if raidIndex and GetRaidRosterInfo then
        -- The tenth return is MAINTANK/MAINASSIST; the twelfth is the assigned combat role.
        local values = {pcall(GetRaidRosterInfo, raidIndex)}
        if values[1] and String(values[13]) then return values[13] end
    end
end

function ZP:GetHealerManaMembers()
    local state = State()
    local raid, count = Group()
    local list = {}
    if count == 0 then return list end
    for index = raid and 1 or 0, count do
        local unit = raid and ("raid" .. index) or (index == 0 and "player" or "party" .. index)
        if Call(UnitExists, unit) == true then
            local guid = Call(UnitGUID, unit)
            if not String(guid) then guid = nil end
            local selected = Role(unit, raid and index or nil) == "HEALER"
            if guid and state.members[guid] ~= nil then selected = state.members[guid] end
            local class, r, g, b = Class(unit)
            list[#list + 1] = {unit = unit, guid = guid, name = DisplayName(unit), class = class,
                r = r, g = g, b = b, selected = selected}
        end
    end
    return list
end

function ZP:SetHealerManaMember(guid, selected)
    if not String(guid) or not Readable(selected) or type(selected) ~= "boolean" then return end
    -- A stale selector must never change an unrelated member after a roster update.
    for _, member in ipairs(self:GetHealerManaMembers()) do
        if member.guid == guid then
            State().members[guid] = selected
            self:RefreshHealerMana()
            return
        end
    end
end

function ZP:ClearHealerManaMembers()
    State().members = {}
    self:RefreshHealerMana()
end

local function Rect(frame)
    if not Readable(frame) or not frame then return end
    if frame.IsForbidden and Call(frame.IsForbidden, frame) ~= false then return end
    if not frame.GetRect or not frame.GetEffectiveScale then return end
    if Call(frame.IsShown, frame) ~= true then return end
    local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
    local scale = Call(frame.GetEffectiveScale, frame)
    local parentScale = Call(UIParent.GetEffectiveScale, UIParent)
    local screenWidth, screenHeight = Call(UIParent.GetWidth, UIParent), Call(UIParent.GetHeight, UIParent)
    if not ok or not Number(left) or not Number(bottom) or not Number(width) or not Number(height)
        or width <= 0 or height <= 0 or not Number(scale) or scale <= 0
        or not Number(parentScale) or parentScale <= 0 or not Number(screenWidth) or not Number(screenHeight) then return end
    local ratio = scale / parentScale
    left, bottom, width, height = left * ratio, bottom * ratio, width * ratio, height * ratio
    -- Compact raid layout briefly uses a 3000-pixel placeholder before sizing next frame.
    if width > screenWidth or height > screenHeight or left < 0 or left > screenWidth
        or bottom < 0 or bottom + height > screenHeight then return end
    return left, bottom + height
end

local function Position()
    if not panel or moving then return end
    local position = State().position
    panel:ClearAllPoints()
    if position then
        local width, height = Call(UIParent.GetWidth, UIParent), Call(UIParent.GetHeight, UIParent)
        local x, y = position.x, position.y
        if Number(width) then x = math.max(0, math.min(x, math.max(0, width - 180))) end
        if Number(height) then y = math.max(0, math.min(y, height)) end
        panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        return
    end
    local raid = Group()
    local candidates = raid and {"CompactRaidFrameContainer", "RaidFrame"}
        or {"CompactPartyFrame", "PartyFrame", "PartyMemberFrame1"}
    for _, name in ipairs(candidates) do
        local x, y = Rect(_G[name])
        if x then
            panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y + 8)
            return
        end
    end
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -160)
end

local function SavePosition()
    if not panel then return end
    local left, bottom = Call(panel.GetLeft, panel), Call(panel.GetBottom, panel)
    local scale, parentScale = Call(panel.GetEffectiveScale, panel), Call(UIParent.GetEffectiveScale, UIParent)
    if Number(left) and Number(bottom) and Number(scale) and scale > 0 and Number(parentScale) and parentScale > 0 then
        State().position = {x = left * scale / parentScale, y = bottom * scale / parentScale}
    end
    if panel.SetUserPlaced then panel:SetUserPlaced(false) end
    Position()
end

function ZP:ResetHealerManaPosition()
    State().position = nil
    Position()
end

local function CreatePanel()
    if panel then return end
    panel = CreateFrame("Frame", "ZwykPlusHealerManaFrame", UIParent, "BackdropTemplate")
    panel:Hide()
    panel:SetSize(180, 40)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1, insets = {left = 1, right = 1, top = 1, bottom = 1}})
    panel:SetBackdropColor(0, 0, 0, 0.35)
    panel:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.3)
    panel.average = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.average:SetPoint("TOPLEFT", 5, -5)
    panel.average:SetWidth(170)
    panel.average:SetJustifyH("LEFT")
    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.empty:SetPoint("TOPLEFT", 5, -22)
    panel.empty:SetWidth(170)
    panel.empty:SetJustifyH("LEFT")
    panel.empty:SetText(L.healerManaEmpty)
    panel.rows = {}
    panel:SetScript("OnDragStart", function(self)
        if Call(IsAltKeyDown) == true then moving = true; self:StartMoving() end
    end)
    panel:SetScript("OnDragStop", function(self)
        if not moving then return end
        self:StopMovingOrSizing()
        moving = false
        SavePosition()
    end)
    panel:SetScript("OnHide", function(self)
        if moving then self:StopMovingOrSizing(); moving = false; SavePosition() end
    end)
    panel:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and ZP.ShowHealerManaMembers then ZP:ShowHealerManaMembers() end
    end)
    panel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.healerManaTitle, 1, 0.82, 0)
        GameTooltip:AddLine(L.healerManaHelp, 0.85, 0.85, 0.85, true)
        if lastReport.state == "restricted" then
            GameTooltip:AddLine(L.healerManaRestrictedHelp, 1, 0.82, 0, true)
        elseif lastReport.state == "unavailable" then
            GameTooltip:AddLine(L.healerManaUnavailableHelp, 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end)
    panel:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Row(index)
    local row = panel.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, panel)
    row:SetPoint("TOPLEFT", 5, -22 - (index - 1) * 15)
    row:SetSize(170, 15)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT")
    row.icon:SetSize(12, 12)
    row.mana = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.mana:SetPoint("LEFT", 15, 0)
    row.mana:SetWidth(42)
    row.mana:SetJustifyH("RIGHT")
    if row.mana.SetWordWrap then row.mana:SetWordWrap(false) end
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 61, 0)
    row.name:SetWidth(109)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    panel.rows[index] = row
    return row
end

local function Mana(unit)
    local connected, dead = Call(UnitIsConnected, unit), Call(UnitIsDeadOrGhost, unit)
    if connected == false then return nil, L.healerManaOffline, {state = "offline", excluded = true} end
    if dead == true then return nil, L.healerManaDead, {state = "dead", excluded = true} end
    if connected ~= true or dead ~= false then return nil, "?", {state = "unavailable"} end
    local hasMana = Call(UnitHasPowerType, unit, manaType)
    if hasMana == false then return nil, "?", {state = "no-mana", excluded = true} end
    -- Explicit mana type retains a druid's mana while in a rage/energy form.
    local maximum = Call(UnitPowerMax, unit, manaType)
    if Number(maximum) and maximum <= 0 then return nil, "?", {state = "no-mana", excluded = true} end
    local native, percent
    local curve = CurveConstants and CurveConstants.ScaleTo100
    if curve and type(UnitPowerPercent) == "function" then
        local ok, value = pcall(UnitPowerPercent, unit, manaType, false, curve)
        if ok and Number(value) then percent = math.max(0, math.min(100, value))
        elseif ok and issecretvalue and issecretvalue(value) then
            -- Store no derived information. This value may only reach a native
            -- text sink; even its truthiness is never used to select a branch.
            native = {state = "restricted", value = value,
                active = hasMana == true or (Number(maximum) and maximum > 0), source = "native-percent"}
        end
    end
    if Number(percent) then
        return percent, string.format("%d%%", math.floor(percent + 0.5)), {state = "public", source = "native-percent"}
    end
    local current = Call(UnitPower, unit, manaType)
    if Number(current) and Number(maximum) then
        percent = math.max(0, math.min(100, current / maximum * 100))
        return percent, string.format("%d%%", math.floor(percent + 0.5)), {state = "public", source = "power-values"}
    end
    return nil, "?", native or {state = "unavailable"}
end

local function PercentColor(label, percent)
    if not percent then label:SetTextColor(0.6, 0.6, 0.6)
    elseif percent < 25 then label:SetTextColor(1, 0.25, 0.2)
    elseif percent < 50 then label:SetTextColor(1, 0.82, 0)
    else label:SetTextColor(0.2, 1, 0.2) end
end

local function Render()
    local index, total, count, blocked, restricted = 0, 0, 0, 0, 0
    local singleNative
    lastReport = {state = "unavailable", members = {}, public = 0, excluded = 0}
    for _, member in ipairs(members or {}) do
        if member.selected then
            index = index + 1
            local row = Row(index)
            row.unit = member.unit
            row.name:SetText(member.name)
            row.name:SetTextColor(member.r, member.g, member.b)
            local coords = CLASS_ICON_TCOORDS and member.class and CLASS_ICON_TCOORDS[member.class]
            if Readable(coords) and type(coords) == "table" and Number(coords[1]) and Number(coords[2])
                and Number(coords[3]) and Number(coords[4]) then
                row.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                row.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                row.icon:SetTexCoord(0, 1, 0, 1)
            end
            local percent, text, info = Mana(member.unit)
            row.mana:SetText(text)
            PercentColor(row.mana, percent)
            if info.state == "restricted" and row.mana.SetFormattedText then
                local rendered = pcall(row.mana.SetFormattedText, row.mana, "%.0f%%", info.value)
                if not rendered then row.mana:SetText("?") end
            end
            if Number(percent) then total, count = total + percent, count + 1
            elseif info.excluded then lastReport.excluded = lastReport.excluded + 1
            else
                blocked = blocked + 1
                if info.state == "restricted" then
                    restricted = restricted + 1
                    if info.active then singleNative = info end
                end
            end
            lastReport.members[#lastReport.members + 1] = {unit = member.unit, name = member.name,
                state = info.state, source = info.source or "--"}
            row:Show()
        end
    end
    for i = index + 1, #panel.rows do panel.rows[i].unit = nil; panel.rows[i]:Hide() end
    local average = count > 0 and blocked == 0 and total / count or nil
    lastReport.public, lastReport.restricted, lastReport.unavailable = count, restricted, blocked - restricted
    if Number(average) then
        panel.average:SetText(L.healerManaAverage .. ": " .. string.format("%d%%", math.floor(average + 0.5)))
        lastReport.state = "public"
    elseif count == 0 and blocked == 1 and singleNative and panel.average.SetFormattedText then
        -- With one eligible healer, the mean is their percentage itself. The
        -- engine can display it directly without secret arithmetic/readback.
        local ok = pcall(panel.average.SetFormattedText, panel.average, "%s: %.0f%%", L.healerManaAverage, singleNative.value)
        if ok then lastReport.state = "native-single"
        else panel.average:SetText(L.healerManaAverage .. ": " .. L.healerManaUnavailable) end
    else
        lastReport.state = restricted > 0 and "restricted" or "unavailable"
        panel.average:SetText(L.healerManaAverage .. ": " .. (restricted > 0 and L.healerManaRestricted or L.healerManaUnavailable))
    end
    PercentColor(panel.average, average)
    panel.empty:SetShown(index == 0)
    panel:SetHeight(index > 0 and (27 + index * 15) or 60)
end

function ZP:RefreshHealerMana()
    local _, count = Group()
    if not (self.db and self.db.healerMana) or count == 0 then
        if panel then panel:Hide() end
        events:SetScript("OnUpdate", nil)
        members = nil
        lastReport = {state = "inactive", members = {}}
        elapsed, rosterElapsed = 0, 0
    else
        CreatePanel()
        members = self:GetHealerManaMembers()
        Render()
        Position()
        panel:Show()
        events:SetScript("OnUpdate", function(_, delta)
            elapsed, rosterElapsed = elapsed + delta, rosterElapsed + delta
            if rosterElapsed >= 1 then
                rosterElapsed = 0
                ZP:RefreshHealerMana()
            elseif elapsed >= 0.25 then
                elapsed = 0
                Render()
            end
        end)
    end
    if self.RefreshHealerManaMembers then self:RefreshHealerManaMembers() end
end

function ZP:GetHealerManaDiagnostics()
    local lines = {string.format(L.healerManaDiagnosticAverage, lastReport.state or "inactive",
        lastReport.public or 0, lastReport.restricted or 0, lastReport.unavailable or 0, lastReport.excluded or 0)}
    for _, member in ipairs(lastReport.members) do
        lines[#lines + 1] = string.format("%s (%s): %s; source=%s", member.name, member.unit, member.state, member.source)
    end
    return lines
end

function ZP:ShowHealerManaDiagnostics()
    if self.ShowDiagnostics then
        self:ShowDiagnostics(L.healerManaDiagnostics, L.healerManaDiagnosticsHelp, function()
            return self:GetHealerManaDiagnostics()
        end)
    end
end

function ZP:InitializeHealerMana()
    if initialized then return end
    initialized = true
    State()
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
        "ROLE_CHANGED_INFORM", "UNIT_NAME_UPDATE", "ADDON_LOADED"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function() ZP:RefreshHealerMana() end)
    self:RefreshHealerMana()
end
