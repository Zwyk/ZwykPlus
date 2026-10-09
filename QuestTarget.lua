local _, ZP = ...
local events, queued
local QueueRefresh
local markerButton, markerRecord
local markerButtonName = "ZwykPlusQuestTargetMarkerButton"
local generation, recovering, combatActive = 0, false, false
local records = setmetatable({}, {__mode = "k"})
local hooked = setmetatable({}, {__mode = "k"})
local shown = setmetatable({}, {__mode = "k"})

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function String(value)
    return Readable(value) and type(value) == "string" and value ~= ""
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value == value
        and value > 0 and value < math.huge and value == math.floor(value)
end

local function InCombat()
    if not InCombatLockdown then return false end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not Readable(value) or value ~= false
end

local function PublicFrame(frame)
    if not Readable(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") then return false end
    if frame.IsForbidden then
        local ok, value = pcall(frame.IsForbidden, frame)
        if not ok or not Readable(value) or value ~= false then return false end
    end
    return frame.IsVisible ~= nil
end

local function Visible(frame)
    if not PublicFrame(frame) then return false end
    local ok, value = pcall(frame.IsVisible, frame)
    return ok and Readable(value) and value == true
end

local function SafeName(name)
    if not String(name) then return end
    name = name:match("^%s*(.-)%s*$")
    -- Names become a single macro argument, never executable text or conditions.
    if name == "" or #name > 160 or name:find("[%c%[%]|/\\]") then return end
    return name
end

local function FormatPattern(format)
    if not String(format) or #format > 250 then return end
    local parts, strings, index = {"^"}, 0, 1
    while index <= #format do
        local char = format:sub(index, index)
        if char == "%" then
            local rest = format:sub(index)
            if rest:sub(1, 2) == "%%" then
                parts[#parts + 1] = "%%"
                index = index + 2
            else
                local token, kind = rest:match("^(%%[sd])"), nil
                if token then kind = token:sub(-1) end
                if not token then
                    token = rest:match("^(%%%d+%$[sd])")
                    if token then kind = token:sub(-1) end
                end
                if not token then return end
                if kind == "s" then
                    strings = strings + 1
                    if strings > 1 then return end
                    parts[#parts + 1] = "(.+)"
                else
                    parts[#parts + 1] = "%d+"
                end
                index = index + #token
            end
        else
            parts[#parts + 1] = char:match("%s") and "%s*"
                or char:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            index = index + 1
        end
    end
    if strings ~= 1 then return end
    parts[#parts + 1] = "$"
    return table.concat(parts)
end

local function MonsterName(text)
    if not String(text) or #text > 500 or text:find("%c") then return end
    local pattern = FormatPattern(QUEST_MONSTERS_KILLED)
    local name = pattern and SafeName(text:match(pattern))
    if name then return name end
    -- Fallbacks for the standard English/French kill objectives only.
    local prefix = text:match("^(.-)%s*:%s*%d+%s*/%s*%d+%s*$")
        or text:match("^%s*%d+%s*/%s*%d+%s+(.+)%s*$")
    if not prefix then return end
    for _, suffix in ipairs({"slain", "killed", "tué", "tués", "tuée", "tuées", "tué%(s%)"}) do
        name = SafeName(prefix:match("^(.-)%s+" .. suffix .. "%s*$"))
        if name then return name end
    end
end

local function Candidates(block, key, module)
    if not PublicFrame(block) or not Readable(block.parentModule) or block.parentModule ~= module or not Number(block.id)
        or not Number(key) or not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and GetQuestLogLeaderBoard) then return end
    local ok, logIndex = pcall(C_QuestLog.GetLogIndexForQuestID, block.id)
    if not ok or not Number(logIndex) then return end
    local text, kind, finished
    ok, text, kind, finished = pcall(GetQuestLogLeaderBoard, key, logIndex, true)
    if not ok or not String(kind) or not String(text) or not Readable(finished) or finished ~= false then return end
    local raw
    local useQuestie = ZP.db and ZP.db.questTargetQuestie
    if Readable(useQuestie) and useQuestie == true and ZP.ResolveQuestObjective then
        local resolved, value = pcall(ZP.ResolveQuestObjective, ZP, block.id, key, text, kind)
        if resolved and Readable(value) and type(value) == "table" then raw = value end
    end
    local candidates, names = {}, {}
    for _, candidate in ipairs(raw or {}) do
        if #candidates >= 80 then break end
        if Readable(candidate) and type(candidate) == "table" then
            local name = SafeName(candidate.name)
            if name and not names[name] then
                local ids = {}
                if Number(candidate.npcID) then ids[candidate.npcID] = true end
                if Readable(candidate.npcIDs) and type(candidate.npcIDs) == "table" then
                    for _, id in ipairs(candidate.npcIDs) do if Number(id) then ids[id] = true end end
                end
                candidates[#candidates + 1] = {name = name, npcIDs = ids}
                names[name] = true
            end
        end
    end
    if #candidates == 0 and kind == "monster" then
        local name = MonsterName(text)
        if name then candidates[1] = {name = name, npcIDs = {}} end
    end
    if #candidates == 0 then return end
    local signature = {}
    for _, candidate in ipairs(candidates) do
        local ids = {}
        for id in pairs(candidate.npcIDs) do ids[#ids + 1] = id end
        table.sort(ids)
        signature[#signature + 1] = candidate.name .. "\031" .. table.concat(ids, ",")
    end
    return candidates, table.concat(signature, "\030")
end

local function HideTooltip(button)
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == button then GameTooltip:Hide() end
end

local function Hide(record)
    if markerRecord == record then markerRecord = nil end
    record.clicked = nil
    record.button:SetAttribute("type", nil)
    record.button:SetAttribute("macrotext", nil)
    record.button:Hide()
    HideTooltip(record.button)
end

local function Valid(record)
    local module, block, line = QuestObjectiveTracker, record.block, record.line
    if not (ZP.db and ZP.db.questObjectiveTarget) or InCombat() or not Visible(module)
        or not Visible(block) or not Visible(line) or not Readable(block.id) or block.id ~= record.questID then return false end
    local lines = block.usedLines
    if not Readable(lines) or type(lines) ~= "table" or not Readable(lines[record.key]) or lines[record.key] ~= line then return false end
    local _, signature = Candidates(block, record.key, module)
    return signature ~= nil and signature == record.signature
end

local function MarkerForTarget(candidate)
    local enabled, icon = ZP.db and ZP.db.questTargetMarker, ZP.db and ZP.db.questTargetMarkerIcon
    if not Readable(enabled) or enabled ~= true or not Number(icon) or icon > 8 or InCombat() then return end
    if not (UnitName and UnitGUID and UnitIsPlayer and UnitIsDeadOrGhost and CanBeRaidTarget
        and GetRaidTargetIndex and IsInRaid) then return end
    local ok, player = pcall(UnitIsPlayer, "target")
    if not ok or not Readable(player) or player ~= false then return end
    local dead
    ok, dead = pcall(UnitIsDeadOrGhost, "target")
    if not ok or not Readable(dead) or dead ~= false then return end
    local name, guid
    ok, name = pcall(UnitName, "target")
    if not ok or not String(name) or name ~= candidate.name then return end
    ok, guid = pcall(UnitGUID, "target")
    if not ok or not String(guid) then return end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-.+$")
    id = tonumber(id)
    if (kind ~= "Creature" and kind ~= "Vehicle") or not Number(id)
        or (next(candidate.npcIDs) and not candidate.npcIDs[id]) then return end
    local allowed
    ok, allowed = pcall(CanBeRaidTarget, "target")
    if not ok or not Readable(allowed) or allowed ~= true then return end
    local raid
    ok, raid = pcall(IsInRaid)
    if not ok or not Readable(raid) or type(raid) ~= "boolean" then return end
    if raid then
        local leaderOK, leader = pcall(UnitIsGroupLeader or function() end, "player")
        local assistOK, assistant = pcall(UnitIsGroupAssistant or function() end, "player")
        if not ((leaderOK and Readable(leader) and leader == true)
            or (assistOK and Readable(assistant) and assistant == true)) then return end
    end
    -- Preserve existing markers. An opaque marker index is unavailable, not zero.
    local existing
    ok, existing = pcall(GetRaidTargetIndex, "target")
    if not ok or not Readable(existing) or (existing ~= nil and existing ~= 0) then return end
    local unchanged, current = pcall(UnitGUID, "target")
    if not unchanged or not String(current) or current ~= guid or InCombat() then return end
    return icon
end

local function EnsureMarkerButton()
    if markerButton then return true end
    -- Blizzard's /click command executes this native action after /targetexact.
    -- Calling SetRaidTarget from an addon PostClick is protected even outside combat.
    local ok, button = pcall(CreateFrame, "Button", markerButtonName, UIParent, "InsecureActionButtonTemplate")
    if not ok or not button then return false end
    markerButton = button
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("unit", "target")
    button:SetAttribute("action", "set-unmarked")
    button:SetScript("PreClick", function()
        button:SetAttribute("type", nil)
        button:SetAttribute("marker", nil)
        local record = markerRecord
        markerRecord = nil
        if not record or not record.clicked or not Valid(record) then return end
        local icon = MarkerForTarget(record.clicked)
        if icon then
            button:SetAttribute("marker", icon)
            button:SetAttribute("type", "raidtarget")
        end
    end)
    button:SetScript("PostClick", function()
        -- A standalone /click must never reuse a previous quest click's target.
        button:SetAttribute("type", nil)
        button:SetAttribute("marker", nil)
    end)
    button:Hide()
    return true
end

local function TargetMacro(name)
    local macro = "/targetexact " .. name
    local enabled, icon = ZP.db and ZP.db.questTargetMarker, ZP.db and ZP.db.questTargetMarkerIcon
    if markerButton and Readable(enabled) and enabled == true and Number(icon) and icon <= 8 then
        macro = macro .. "\n/click " .. markerButtonName
    end
    return macro
end

local function Tooltip(record)
    if not GameTooltip then return end
    GameTooltip:SetOwner(record.button, "ANCHOR_LEFT")
    if Valid(record) then
        GameTooltip:SetText(string.format(ZP.L.questObjectiveTargetClick, record.name), 1, 0.82, 0)
        if #record.candidates > 1 and GameTooltip.AddLine then
            GameTooltip:AddLine(string.format(ZP.L.questObjectiveTargetChoice, record.cursor, #record.candidates), 0.85, 0.85, 0.85, true)
        end
    else
        GameTooltip:SetText(ZP.L.questObjectiveTargetUnavailable, 1, 0.82, 0)
    end
    GameTooltip:Show()
end

local function Attach(block, line, key, candidates, signature)
    EnsureMarkerButton()
    local record = records[line]
    if not record then
        -- Unlike SecureActionButtonTemplate, this does not protect the pooled native rows.
        -- Forever 1.60.1 (70245) explicitly supports its macrotext action outside combat.
        local ok, button = pcall(CreateFrame, "Button", nil, line, "InsecureActionButtonTemplate")
        if not ok or not button then return end
        record = {button = button, line = line}
        records[line] = record
        button:RegisterForClicks("LeftButtonUp")
        button:SetAttribute("useOnKeyDown", false)
        if button.SetPassThroughButtons then
            button:SetPassThroughButtons("RightButton", "MiddleButton", "Button4", "Button5")
        end
        button:SetAllPoints(line.Text)
        button:SetScript("PreClick", function()
            -- A pooled line may have changed before the queued layout refresh.
            if not Valid(record) then Hide(record); return end
            record.clicked = record.candidates[record.cursor]
            markerRecord = record
            record.button:SetAttribute("macrotext", TargetMacro(record.clicked.name))
        end)
        button:SetScript("PostClick", function()
            local candidate = record.clicked
            if markerRecord == record then markerRecord = nil end
            record.clicked = nil
            if not candidate or not Valid(record) then return end
            record.cursor = record.cursor % #record.candidates + 1
            record.name = record.candidates[record.cursor].name
            record.button:SetAttribute("macrotext", TargetMacro(record.name))
            if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == button then Tooltip(record) end
        end)
        button:SetScript("OnEnter", function() Tooltip(record) end)
        button:SetScript("OnLeave", function() HideTooltip(button) end)
        line:HookScript("OnHide", function() Hide(record) end)
        line:HookScript("OnShow", function() QueueRefresh() end)
    end
    if record.signature ~= signature then
        local nextName = record.name
        record.cursor = 1
        for index, candidate in ipairs(candidates) do if candidate.name == nextName then record.cursor = index; break end end
    end
    record.candidates, record.signature = candidates, signature
    record.block, record.questID, record.key = block, block.id, key
    record.name = candidates[record.cursor or 1].name
    record.button:SetAttribute("macrotext", TargetMacro(record.name))
    record.button:SetAttribute("type", "macro")
    record.button:Show()
    record.seen = true
end

local function CancelRefresh()
    generation = generation + 1
    queued, recovering = nil, false
end

QueueRefresh = function()
    if queued or combatActive or not (ZP.db and ZP.db.questObjectiveTarget) then return end
    if C_Timer and C_Timer.After then
        local token = generation
        queued = true
        C_Timer.After(recovering and 0.1 or 0, function()
            if token ~= generation then return end
            queued = false
            ZP:RefreshQuestTarget()
            -- REGEN_ENABLED can precede the actual lockdown release. Retry only
            -- during this handoff; disabling or entering combat invalidates it.
            if recovering then QueueRefresh() end
        end)
    else
        ZP:RefreshQuestTarget()
    end
end

function ZP:RefreshQuestTarget()
    for _, record in pairs(records) do record.seen = false end
    local module = QuestObjectiveTracker
    local enabled, blocked = self.db and self.db.questObjectiveTarget, combatActive or InCombat()
    if not enabled then CancelRefresh() end
    if enabled and not blocked then recovering = false end
    if enabled and not blocked and PublicFrame(module) then
        if not shown[module] and module.HookScript then
            shown[module] = pcall(module.HookScript, module, "OnShow", function() QueueRefresh() end)
        end
        if not hooked[module] and hooksecurefunc and type(module.EndLayout) == "function" then
            hooked[module] = pcall(hooksecurefunc, module, "EndLayout", QueueRefresh)
        end
        if Visible(module) and type(module.EnumerateActiveBlocks) == "function" then
            pcall(module.EnumerateActiveBlocks, module, function(block)
                if not Visible(block) or not Readable(block.parentModule) or block.parentModule ~= module then return end
                local lines = block.usedLines
                if not Readable(lines) or type(lines) ~= "table" then return end
                for key, line in pairs(lines) do
                    if Number(key) and Visible(line) and line.HookScript and PublicFrame(line.Text) then
                        local candidates, signature = Candidates(block, key, module)
                        if candidates then Attach(block, line, key, candidates, signature) end
                    end
                end
            end)
        end
    end
    for _, record in pairs(records) do if not record.seen then Hide(record) end end
end

function ZP:InitializeQuestTarget()
    if events then return end
    combatActive = InCombat()
    events = CreateFrame("Frame")
    if self.InitializeQuestObjectives then self:InitializeQuestObjectives(QueueRefresh) end
    for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE",
        "QUEST_WATCH_LIST_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event)
        if ZP.InvalidateQuestObjectives then ZP:InvalidateQuestObjectives() end
        if event == "ADDON_LOADED" and ZP.InitializeQuestObjectives then ZP:InitializeQuestObjectives(QueueRefresh) end
        if event == "PLAYER_REGEN_DISABLED" then
            combatActive = true
            CancelRefresh()
            for _, record in pairs(records) do Hide(record) end
        elseif event == "PLAYER_REGEN_ENABLED" then
            combatActive = false
            recovering = ZP.db and ZP.db.questObjectiveTarget or false
            QueueRefresh()
        else
            QueueRefresh()
        end
    end)
    self:RefreshQuestTarget()
end
