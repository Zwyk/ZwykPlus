local _, ZP = ...
local initialized, rebuilding = false, false
local records = setmetatable({}, {__mode = "k"})

local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
        and (not canaccessvalue or canaccessvalue(value))
end

local function String(value)
    return Readable(value) and type(value) == "string" and value:find("%S") ~= nil
end

local function Public(tooltip)
    if not Readable(tooltip) or not tooltip then return false end
    if type(tooltip) ~= "table" and type(tooltip) ~= "userdata" then return false end
    if tooltip.IsForbidden then
        local ok, value = pcall(tooltip.IsForbidden, tooltip)
        if not ok or not Readable(value) or value ~= false then return false end
    end
    return true
end

local function Unit(tooltip)
    local getter = tooltip.GetProcessingTooltipInfo or tooltip.GetPrimaryTooltipInfo
    if type(getter) == "function" then
        local ok, info = pcall(getter, tooltip)
        if ok and Readable(info) and type(info) == "table" then
            local name, args = info.getterName, info.getterArgs
            if String(name) and name == "GetUnit" and Readable(args) and type(args) == "table" then
                if String(args[1]) then return args[1] end
                return
            end
        end
    end
    if type(tooltip.GetUnit) == "function" then
        local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
        if ok and String(unit) then return unit end
    end
end

local HookTooltip
local function AddRank(tooltip, unit)
    if not Public(tooltip) then return end
    HookTooltip(tooltip)
    local record = records[tooltip]
    if not record or record.added or not (ZP.db and ZP.db.guildRankTooltip) then return end
    if not String(unit) then unit = Unit(tooltip) end
    if not String(unit) or type(UnitIsPlayer) ~= "function" or type(GetGuildInfo) ~= "function" then return end
    local ok, player = pcall(UnitIsPlayer, unit)
    if not ok or not Readable(player) or player ~= true then return end
    local guild, rank
    ok, guild, rank = pcall(GetGuildInfo, unit)
    if not ok or not String(guild) or not String(rank) or type(tooltip.AddDoubleLine) ~= "function" then return end
    -- Use the actual rank title from this player's guild, never our own roster
    -- or a numeric rank index. Native rebuilding owns the rest of the tooltip.
    local added = pcall(tooltip.AddDoubleLine, tooltip, ZP.L.guildRank, rank, 0.65, 0.65, 0.65, 0.25, 1, 0.25)
    if added then record.added = true end
    return added
end

HookTooltip = function(tooltip)
    if not Public(tooltip) or records[tooltip] or type(tooltip.HookScript) ~= "function" then return end
    local record = {}
    local ok = pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function()
        record.added = nil
    end)
    if not ok then return end
    records[tooltip] = record
    if type(hooksecurefunc) == "function" and type(tooltip.SetUnit) == "function" then
        pcall(hooksecurefunc, tooltip, "SetUnit", function(self, unit)
            if AddRank(self, unit) and type(self.Show) == "function" then pcall(self.Show, self) end
        end)
    end
end

function ZP:RefreshGuildRankTooltip()
    if rebuilding then return end
    rebuilding = true
    for tooltip in pairs(records) do
        if Public(tooltip) and type(tooltip.IsShown) == "function" then
            local ok, shown = pcall(tooltip.IsShown, tooltip)
            local unit = ok and Readable(shown) and shown == true and Unit(tooltip)
            if String(unit) then
                -- Refresh the existing native data/owner. Legacy tooltips keep
                -- their displayed public unit through the setter fallback.
                if type(tooltip.RefreshData) == "function" then pcall(tooltip.RefreshData, tooltip)
                elseif type(tooltip.SetUnit) == "function" then pcall(tooltip.SetUnit, tooltip, unit) end
            end
        end
    end
    rebuilding = false
end

function ZP:InitializeGuildRankTooltip()
    if initialized then return end
    initialized = true
    HookTooltip(GameTooltip)
    HookTooltip(ItemRefTooltip)
    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit ~= nil then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tooltip)
            AddRank(tooltip)
        end)
    end
    local events = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "UNIT_NAME_UPDATE", "ADDON_LOADED"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "ADDON_LOADED" then HookTooltip(GameTooltip); HookTooltip(ItemRefTooltip) end
        if ZP.db and ZP.db.guildRankTooltip then ZP:RefreshGuildRankTooltip() end
    end)
end
