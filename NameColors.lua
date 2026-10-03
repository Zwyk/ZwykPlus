local _, ZP = ...
local events = CreateFrame("Frame")
local tracked = setmetatable({}, {__mode = "k"})
local hooks = {}
local initialized = false

local function IsPublic(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function IsNumber(value)
    return IsPublic(value) and type(value) == "number"
end

local function IsAccessible(region)
    return region and IsPublic(region) and not (region.IsForbidden and region:IsForbidden())
end

local function SameColor(a, b)
    if not (a and b) then return false end
    for i = 1, 4 do
        if math.abs(a[i] - b[i]) > 0.00001 then return false end
    end
    return true
end

local function GetNameRegion(frame)
    if not IsAccessible(frame) then return end
    local name = frame.name or frame.Name
    if not name and frame == PlayerFrame then name = PlayerName end
    if not name and frame.TargetFrameContent then
        local main = frame.TargetFrameContent.TargetFrameContentMain
        name = main and main.Name
    end
    if IsAccessible(name) and name.GetTextColor and name.SetTextColor then return name end
end

local function IsNativeFrame(frame)
    if not IsAccessible(frame) then return false end
    if tracked[frame] or frame == PlayerFrame or frame == TargetFrame or frame == FocusFrame then return true end
    if frame == (TargetFrame and TargetFrame.totFrame) or frame == (FocusFrame and FocusFrame.totFrame) then return true end
    if frame.GetParent and frame:GetParent() == PartyFrame and frame.Name then return true end
    local name = frame.GetName and frame:GetName()
    return IsPublic(name) and type(name) == "string" and
        (name:match("^CompactRaidFrame%d+$") or name:match("^CompactRaidGroup%d+Member%d+$") or
        name:match("^CompactPartyFrameMember%d+$")) ~= nil
end

local function GetClassColor(unit)
    if not IsPublic(unit) or type(unit) ~= "string" or not UnitIsPlayer or not UnitClass then return end
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    if not ok or not IsPublic(isPlayer) or not isPlayer then return end
    local classOK, _, class = pcall(UnitClass, unit)
    if not classOK or not IsPublic(class) or type(class) ~= "string" then return end
    local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if not color then return end
    for _, key in ipairs({"r", "g", "b"}) do
        if not IsNumber(color[key]) then return end
    end
    return color
end

local function ApplyName(frame, nativeColorUpdated)
    local name = GetNameRegion(frame)
    if not name then return end
    local ok, r, g, b, a = pcall(name.GetTextColor, name)
    if not ok or not IsNumber(r) or not IsNumber(g) or not IsNumber(b) then return end
    if not IsPublic(a) or (a ~= nil and type(a) ~= "number") then return end
    local current = {r, g, b, a or 1}
    local state = tracked[frame]
    if not state or state.name ~= name then
        state = {name = name, normal = current}
        tracked[frame] = state
    elseif nativeColorUpdated or not SameColor(current, state.applied) then
        -- Blizzard may have assigned a new default/reaction color since our last update.
        state.normal = current
        state.applied = nil
    end
    local color = ZP.db and ZP.db.frameClassColors and GetClassColor(frame.unit)
    if color then
        local target = {color.r, color.g, color.b, state.normal[4]}
        if not SameColor(current, target) then
            if not pcall(name.SetTextColor, name, target[1], target[2], target[3], target[4]) then return end
        end
        state.applied = target
    elseif state.applied then
        -- Restore only colors owned by this feature; keep later native/other-addon updates.
        pcall(name.SetTextColor, name, state.normal[1], state.normal[2], state.normal[3], state.normal[4])
        state.applied = nil
    end
end

local function InstallHooks()
    if not hooksecurefunc then return end
    for _, name in ipairs({"UnitFrame_Update", "CompactUnitFrame_UpdateName"}) do
        if not hooks[name] and type(_G[name]) == "function" then
            local compact = name == "CompactUnitFrame_UpdateName"
            hooksecurefunc(name, function(frame)
                if not IsNativeFrame(frame) then return end
                local nativeColorUpdated = false
                -- CompactUnitFrame_UpdateName repaints visible names even when the native
                -- color happens to equal our previous class color. UnitFrame_Update doesn't.
                local region = compact and not frame.UpdateNameOverride and GetNameRegion(frame)
                if region and region.IsShown then
                    local ok, shown = pcall(region.IsShown, region)
                    nativeColorUpdated = ok and IsPublic(shown) and shown == true
                end
                ApplyName(frame, nativeColorUpdated)
            end)
            hooks[name] = true
        end
    end
end

local function ApplyMembers(group)
    if not IsAccessible(group) then return end
    for _, frame in ipairs(group.memberUnitFrames or {}) do ApplyName(frame) end
end

function ZP:RefreshNameColors()
    if not self.db then return end
    InstallHooks()
    for frame in pairs(tracked) do ApplyName(frame) end
    ApplyName(PlayerFrame)
    ApplyName(TargetFrame)
    ApplyName(FocusFrame)
    if IsAccessible(TargetFrame) then ApplyName(TargetFrame.totFrame) end
    if IsAccessible(FocusFrame) then ApplyName(FocusFrame.totFrame) end
    if IsAccessible(PartyFrame) then
        for i = 1, 4 do ApplyName(PartyFrame["MemberFrame" .. i]) end
        local pool = PartyFrame.PartyMemberFramePool
        if pool and pool.EnumerateActive then
            for frame in pool:EnumerateActive() do ApplyName(frame) end
        end
    end
    ApplyMembers(CompactPartyFrame)
    for i = 1, 8 do ApplyMembers(_G["CompactRaidGroup" .. i]) end
    for i = 1, 40 do ApplyName(_G["CompactRaidFrame" .. i]) end
end

function ZP:InitializeNameColors()
    if initialized then return end
    initialized = true
    for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "GROUP_ROSTER_UPDATE", "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_CONNECTION"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function() ZP:RefreshNameColors() end)
    self:RefreshNameColors()
end
