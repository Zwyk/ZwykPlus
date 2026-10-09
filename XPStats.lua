local _, ZP = ...
local L = ZP.L
local events = CreateFrame("Frame")
local state, baseline, clock, initialized, queued, generation = nil, nil, nil, false, false, 0
local restedName, wantedLevel, retries, updateElapsed = nil, nil, 0, 0
local samplePending = false
local pending = {total = 0, quests = 0, kills = 0, bonus = 0, unknown = false, xpChanged = false}
local formats

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value == value
        and value >= 0 and value < math.huge
end

local function String(value)
    return Readable(value) and type(value) == "string" and value ~= ""
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil, false end
    local ok, value = pcall(fn, ...)
    if ok and Readable(value) then return value, true end
    return nil, false
end

local function RestedLabel()
    if type(GetRestState) ~= "function" then return end
    local ok, id, name = pcall(GetRestState)
    if ok and Readable(id) and id == 1 and String(name) then restedName = name end
end

local function Snapshot()
    RestedLabel()
    local xp, maximum, level = Call(UnitXP, "player"), Call(UnitXPMax, "player"), Call(UnitLevel, "player")
    if not Number(xp) or not Number(maximum) or maximum <= 0 or xp > maximum
        or not Number(level) or level < 1 or level ~= math.floor(level) then return end
    local pool, known = Call(GetXPExhaustion)
    if known and pool == nil then pool = 0 end
    known = known and Number(pool)
    local resting = Call(IsResting)
    if type(resting) ~= "boolean" then resting = nil end
    return {xp = xp, maximum = maximum, level = level, pool = known and pool or nil,
        resting = resting}
end

local function Active()
    if not (ZP.db and ZP.db.xpStats) then return false end
    local maximum = Call(UnitXPMax, "player")
    if not Number(maximum) or maximum <= 0 then return false end
    for _, fn in ipairs({GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel
        or IsPlayerAtEffectiveMaxLevel or false, IsXPUserDisabled or false}) do
        if type(fn) == "function" then
            local blocked, known = Call(fn)
            if not known or type(blocked) ~= "boolean" or blocked then return false end
        end
    end
    return true
end

local function AccrueTime()
    if not state then return end
    local now = Call(GetTime)
    -- A later readable clock can recover the whole interval. Do not turn a
    -- transient read failure into a permanent error in the saved statistics.
    if not Number(now) or clock and now < clock then return false end
    if not clock and (pending.xpChanged or pending.total > 0 or pending.quests > 0 or pending.unknown) then
        state.complete = false
    end
    if clock and now >= clock then state.elapsed = state.elapsed + now - clock end
    clock = now
    return true
end

local function ClearPending()
    pending = {total = 0, quests = 0, kills = 0, bonus = 0, unknown = false, xpChanged = false}
    wantedLevel, retries = nil, 0
end

-- Compile the client's own localized printf formats. Capture numbers by their
-- argument position, including French formats that reorder %n$s and %n$d.
local function Compile(format)
    if not String(format) or #format > 1000 then return end
    local pattern, arguments, index, nextArgument = {"^"}, {}, 1, 1
    while index <= #format do
        local char = format:sub(index, index)
        if char == "%" then
            local rest = format:sub(index)
            if rest:sub(1, 2) == "%%" then
                pattern[#pattern + 1], index = "%%", index + 2
            else
                local position, kind = rest:match("^%%(%d+)%$([sd])")
                local token
                if position then token = rest:match("^%%%d+%$[sd]"); position = tonumber(position)
                else
                    token, kind = rest:match("^(%%([sd]))")
                    position, nextArgument = nextArgument, nextArgument + 1
                end
                if not token or not position or position < 1 or position > 12 then return end
                arguments[#arguments + 1] = position
                pattern[#pattern + 1] = "(.-)"
                index = index + #token
            end
        else
            pattern[#pattern + 1] = char:match("%s") and "%s*"
                or char:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            index = index + 1
        end
    end
    pattern[#pattern + 1] = "$"
    return table.concat(pattern), arguments
end

local function BuildFormats()
    formats = {}
    local function Add(key, bonus, unnamed)
        local pattern, arguments = Compile(_G[key])
        if pattern then formats[#formats + 1] = {pattern = pattern, arguments = arguments, bonus = bonus, unnamed = unnamed} end
    end
    -- Group/raid variants must precede the plain variant: its final %s could
    -- otherwise swallow the group-bonus suffix as part of the rested label.
    for _, suffix in ipairs({"_GROUP", "_RAID", ""}) do
        for _, id in ipairs({1, 2, 4, 5}) do Add("COMBATLOG_XPGAIN_EXHAUSTION" .. id .. suffix, true) end
        Add("COMBATLOG_XPGAIN_FIRSTPERSON" .. suffix)
        Add("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED" .. suffix, false, true)
    end
end

local function Integer(text)
    if Number(text) and text == math.floor(text) then return text end
    if not String(text) then return end
    text = text:gsub("\194\160", ""):gsub("\226\128\175", ""):gsub("[%s,%.']", "")
    if not text:match("^%d+$") then return end
    local value = tonumber(text)
    if Number(value) then return value end
end

local function CombatGain(text)
    if not String(text) or #text > 2000 then return end
    RestedLabel()
    if not formats or #formats == 0 then BuildFormats() end
    for _, format in ipairs(formats) do
        local captures = {text:match(format.pattern)}
        if #captures > 0 then
            local args = {}
            for index, position in ipairs(format.arguments) do args[position] = captures[index] end
            local amount = Integer(args[format.unnamed and 1 or 2])
            if not amount then return end
            local bonus = 0
            if format.bonus then
                local extra = Integer(args[3])
                if not extra or extra > amount then return end
                if extra > 0 then
                    if not restedName or args[4] ~= restedName then return end
                    bonus = extra
                end
            end
            return amount, bonus, not format.unnamed
        end
    end
end

local QueueSample
local function Sample(final)
    if not state then return end
    AccrueTime()
    local current = Snapshot()
    samplePending = true
    if not current then
        -- Retain both the last readable XP and award metadata. The next valid
        -- snapshot can still reconcile this interval, including one level-up.
        return false
    end
    local changingLevel = baseline and (current.level < baseline.level
        or current.level == baseline.level and (current.xp < baseline.xp or current.maximum ~= baseline.maximum))
    if (wantedLevel and current.level < wantedLevel) or changingLevel then
        if not final and retries < 15 then retries = retries + 1; QueueSample() end
        return false
    end
    local gain
    if baseline then
        if current.level == baseline.level and current.xp >= baseline.xp then gain = current.xp - baseline.xp
        elseif current.level == baseline.level + 1 then gain = baseline.maximum - baseline.xp + current.xp end
    else
        -- Login can precede the first readable XP snapshot. With no recorded
        -- awards yet, this establishes the start rather than a lost interval.
        if pending.xpChanged or pending.total > 0 or pending.quests > 0 or pending.unknown then
            state.complete, state.splitKnown, state.eligibleKnown = false, false, false
        end
    end
    if baseline and not gain then
        -- More than one level cannot be reconciled from these two snapshots.
        state.complete, state.splitKnown, state.eligibleKnown = false, false, false
    elseif gain == 0 and (pending.total > 0 or pending.quests > 0) then
        -- The combat message can arrive just before its native XP update.
        if not final and retries < 15 then retries = retries + 1; QueueSample() end
        -- After the short burst, OnUpdate retries once a second. Keeping the
        -- metadata also lets logout report an award that could not be saved.
        return false
    elseif gain and gain > 0 then
        local matched = pending.total <= gain and pending.bonus <= pending.kills and pending.bonus <= gain
        -- Quest rewards may also have an unnamed XP chat message. Only use the
        -- quest payload to explain the residual, never add it to chat XP twice.
        local classified = pending.total == gain or pending.total + pending.quests == gain
        -- XP can update before the localized award message. Allow a short
        -- settling window before declaring its rested split unavailable.
        if not classified and not final and retries < 2 then
            retries = retries + 1
            QueueSample()
            return false
        end
        state.gained = state.gained + gain
        local bonus = matched and pending.bonus or 0
        local poolDrop = baseline and baseline.pool and current.pool and math.max(0, baseline.pool - current.pool)
        local noRest = baseline and baseline.pool == 0 and current.pool == 0
        if not matched or ((pending.unknown or not classified) and not noRest)
            or (poolDrop and poolDrop > 0 and bonus == 0) then state.splitKnown = false end
        if not matched or pending.unknown or not classified then state.eligibleKnown = false end
        state.bonus = state.bonus + bonus
        state.eligible = state.eligible + (matched and pending.kills - bonus or 0)
        -- Native rested thresholds cover doubled XP, hence the default /2.
        -- A clean observed bonus can also identify a client using bonus units.
        if poolDrop and bonus > 0 and matched and classified and not pending.unknown
            and baseline.resting == false and current.resting == false then
            if math.abs(poolDrop - bonus) < 0.01 then state.poolFactor = 1
            elseif math.abs(poolDrop - bonus * 2) < 0.01 then state.poolFactor = 2 end
        end
    end
    baseline = current
    samplePending = false
    ClearPending()
    return true
end

QueueSample = function()
    if queued then return end
    if not (C_Timer and type(C_Timer.After) == "function") then Sample(); return end
    queued = true
    local token = generation
    C_Timer.After(0.1, function()
        if token ~= generation then return end
        queued = false
        Sample()
        ZP:RefreshXPStats()
    end)
end

local function NewState()
    return {version = 1, elapsed = 0, gained = 0, bonus = 0, eligible = 0,
        splitKnown = true, eligibleKnown = true, complete = true, poolFactor = 2}
end

local function LoadState()
    local saved = ZwykPlusXPState
    local valid = Readable(saved) and type(saved) == "table" and Readable(saved.version) and saved.version == 1
    if valid then
        for _, key in ipairs({"elapsed", "gained", "bonus", "eligible"}) do
            if not Number(saved[key]) then valid = false; break end
        end
        for _, key in ipairs({"splitKnown", "eligibleKnown", "complete"}) do
            if not Readable(saved[key]) or type(saved[key]) ~= "boolean" then valid = false; break end
        end
        if valid and (saved.bonus > saved.gained or saved.eligible > saved.gained - saved.bonus) then valid = false end
        if valid and (not Readable(saved.poolFactor) or (saved.poolFactor ~= 1 and saved.poolFactor ~= 2)) then valid = false end
    end
    state = valid and saved or NewState()
    ZwykPlusXPState = state
end

function ZP:GetXPStatistics()
    if not state then return end
    local timeKnown = AccrueTime()
    local info = {elapsed = state.elapsed, gained = state.gained, bonus = state.bonus, eligible = state.eligible,
        complete = state.complete and timeKnown ~= false, splitKnown = state.splitKnown, eligibleKnown = state.eligibleKnown}
    info.partialRate = not info.complete
    local current = Snapshot()
    if state.elapsed >= 1 then
        info.totalRate = state.gained * 3600 / state.elapsed
        if state.splitKnown then
            local base = (state.gained - state.bonus) / state.elapsed
            info.baseRate = base * 3600
            if current and current.pool and base > 0 then
                local remaining, eligible = current.maximum - current.xp, state.eligible / state.elapsed
                if current.pool == 0 or eligible == 0 and state.eligibleKnown then info.secondsToLevel = remaining / base
                elseif state.eligibleKnown and eligible > 0 then
                    local boostTime, rate = current.pool / state.poolFactor / eligible, base + eligible
                    if remaining <= rate * boostTime then info.secondsToLevel = remaining / rate
                    else info.secondsToLevel = boostTime + (remaining - rate * boostTime) / base end
                end
                if info.secondsToLevel then info.estimateMethod = "rested" end
            end
        end
        if current and not info.secondsToLevel and info.totalRate > 0 then
            -- Useful historical-rate projection when the rested split or pool
            -- is unavailable. It does not claim to model the remaining reserve.
            info.secondsToLevel = (current.maximum - current.xp) * 3600 / info.totalRate
            info.estimateMethod = "observed"
        end
    end
    return info
end

local function FormatNumber(value)
    if not Number(value) then return L.xpStatsUnknown end
    local integer = math.floor(value + 0.5)
    local text, known = Call(BreakUpLargeNumbers, integer)
    return known and String(text) and text or tostring(integer)
end

local function Duration(seconds)
    if not Number(seconds) then return L.xpStatsUnknown end
    seconds = math.ceil(seconds)
    local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
    if hours > 0 then return string.format("%sh %02dm", tostring(hours), minutes) end
    return string.format("%dm %02ds", minutes, seconds % 60)
end

local function StatisticLabels(info)
    local total, base, estimate = FormatNumber(info.totalRate), FormatNumber(info.baseRate), Duration(info.secondsToLevel)
    if info.partialRate then
        if info.totalRate then total = string.format(L.xpStatsApproximate, total) end
        if info.baseRate then base = string.format(L.xpStatsApproximate, base) end
    end
    if info.secondsToLevel and (info.partialRate or info.estimateMethod == "observed") then
        estimate = string.format(L.xpStatsApproximate, estimate)
    end
    return total, base, estimate
end

function ZP:XPStatsBarLabel()
    if not Active() then return end
    local info = self:GetXPStatistics()
    if info then
        local total, base, estimate = StatisticLabels(info)
        return string.format(L.xpStatsBarFormat, total, base, estimate)
    end
end

function ZP:XPStatsTooltipLines()
    if not Active() then return {} end
    local info = self:GetXPStatistics()
    if not info then return {} end
    local total, base, estimate = StatisticLabels(info)
    local lines = {
        string.format(L.xpStatsTooltipElapsed, Duration(info.elapsed)),
        string.format(L.xpStatsTooltipGained, FormatNumber(info.gained)),
        string.format(L.xpStatsTooltipBonus, FormatNumber(info.splitKnown and info.bonus or nil)),
        string.format(L.xpStatsTooltipRate, total),
        string.format(L.xpStatsTooltipBaseRate, base),
        string.format(L.xpStatsTooltipEstimate, estimate),
    }
    if not info.complete then lines[#lines + 1] = L.xpStatsIncomplete end
    if not info.splitKnown then lines[#lines + 1] = L.xpStatsBonusUnavailable
    elseif not info.eligibleKnown and (not info.secondsToLevel or info.estimateMethod == "observed") then
        lines[#lines + 1] = L.xpStatsEstimateUnavailable
    end
    if info.estimateMethod == "observed" then lines[#lines + 1] = L.xpStatsEstimateObserved end
    lines[#lines + 1] = L.xpStatsTooltipClick
    return lines
end

function ZP:RefreshXPStats()
    if self.RefreshRestedXP then self:RefreshRestedXP() end
end

function ZP:ResetXPStats()
    generation, queued = generation + 1, false
    samplePending = false
    ClearPending()
    state = NewState()
    ZwykPlusXPState = state
    baseline, clock = Snapshot(), Call(GetTime)
    clock = Number(clock) and clock or nil
    samplePending = baseline == nil
    -- An unreadable first snapshot is retried; it has not lost any recorded
    -- interval yet. Later award events without a baseline mark a genuine gap.
    self:RefreshXPStats()
end

function ZP:PromptXPStatsReset()
    if Active() and StaticPopup_Show then StaticPopup_Show("ZWYKPLUS_RESET_XP_STATS") end
end

function ZP:InitializeXPStats()
    if initialized then return end
    initialized = true
    LoadState()
    baseline, clock = Snapshot(), Call(GetTime)
    clock = Number(clock) and clock or nil
    samplePending = baseline == nil
    if StaticPopupDialogs then
        StaticPopupDialogs.ZWYKPLUS_RESET_XP_STATS = {
            text = L.xpStatsResetTitle, button1 = L.xpStatsResetAccept, button2 = L.xpStatsResetCancel,
            OnAccept = function() ZP:ResetXPStats() end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
        "UPDATE_EXHAUSTION", "CHAT_MSG_COMBAT_XP_GAIN", "QUEST_TURNED_IN", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, arg, xpReward)
        if event == "PLAYER_LOGOUT" then
            generation, queued = generation + 1, false
            if Sample(true) == false or AccrueTime() == false then
                state.complete, state.splitKnown, state.eligibleKnown = false, false, false
            end
        elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
            local amount, bonus, kill = CombatGain(arg)
            if amount then
                pending.total = pending.total + amount
                pending.bonus = pending.bonus + bonus
                if kill then pending.kills = pending.kills + amount end
            else pending.unknown = true end
            QueueSample()
        elseif event == "QUEST_TURNED_IN" then
            if Number(xpReward) then pending.quests = pending.quests + xpReward
            else pending.unknown = true end
            QueueSample()
        elseif event == "PLAYER_LEVEL_UP" then
            if Number(arg) and arg >= 1 then wantedLevel = math.max(wantedLevel or 0, arg) end
            QueueSample()
        elseif event == "PLAYER_XP_UPDATE" then
            if Readable(arg) and arg == "player" then pending.xpChanged = true; QueueSample() end
        else
            QueueSample()
        end
    end)
    events:SetScript("OnUpdate", function(_, elapsed)
        if not Number(elapsed) then return end
        updateElapsed = updateElapsed + elapsed
        if updateElapsed < 1 then return end
        updateElapsed = 0
        AccrueTime()
        if samplePending then QueueSample() end
        ZP:RefreshXPStats()
    end)
    self:RefreshXPStats()
end
