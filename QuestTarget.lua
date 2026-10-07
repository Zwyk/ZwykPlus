local _, ZP = ...
local events, queued
local QueueRefresh
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
    if not prefix then return end
    for _, suffix in ipairs({"slain", "killed", "tué", "tués", "tuée", "tuées", "tué%(s%)"}) do
        name = SafeName(prefix:match("^(.-)%s+" .. suffix .. "%s*$"))
        if name then return name end
    end
end

local function ObjectiveName(block, key, module)
    if not PublicFrame(block) or not Readable(block.parentModule) or block.parentModule ~= module or not Number(block.id)
        or not Number(key) or not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and GetQuestLogLeaderBoard) then return end
    local ok, logIndex = pcall(C_QuestLog.GetLogIndexForQuestID, block.id)
    if not ok or not Number(logIndex) then return end
    local text, kind, finished
    ok, text, kind, finished = pcall(GetQuestLogLeaderBoard, key, logIndex, true)
    if not ok or not Readable(kind) or kind ~= "monster" or not Readable(finished) or finished ~= false then return end
    return MonsterName(text)
end

local function HideTooltip(button)
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == button then GameTooltip:Hide() end
end

local function Hide(record)
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
    return ObjectiveName(block, record.key, module) == record.name
end

local function Attach(block, line, key, name)
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
            if not Valid(record) then Hide(record) end
        end)
        button:SetScript("OnEnter", function()
            if not GameTooltip then return end
            GameTooltip:SetOwner(button, "ANCHOR_LEFT")
            if Valid(record) then
                GameTooltip:SetText(string.format(ZP.L.questObjectiveTargetClick, record.name), 1, 0.82, 0)
            else
                GameTooltip:SetText(ZP.L.questObjectiveTargetUnavailable, 1, 0.82, 0)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() HideTooltip(button) end)
        line:HookScript("OnHide", function() Hide(record) end)
        line:HookScript("OnShow", function() QueueRefresh() end)
    end
    record.block, record.questID, record.key, record.name = block, block.id, key, name
    record.button:SetAttribute("macrotext", "/targetexact " .. name)
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
                        local name = ObjectiveName(block, key, module)
                        if name then Attach(block, line, key, name) end
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
    for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE",
        "QUEST_WATCH_LIST_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event)
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
