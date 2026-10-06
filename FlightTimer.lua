local _, ZP = ...
local L = ZP.L
local events = CreateFrame("Frame")
local frame, position, times, cache, pending, flight
local initialized, hooks, moving, requesting = false, {}, false, false
local elapsed = 0
local MAX_HOPS, WIDTH, ROW_HEIGHT = 40, 400, 18
local Update, Stop

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

local function Clock()
    local now = Call(GetTime)
    if Number(now) and now >= 0 then return now end
end

local function Duration(value)
    return Number(value) and value >= 1 and value <= 7200
end

local function Saved()
    if times then return end
    times = {}
    if Readable(ZwykPlusFlightTimes) and type(ZwykPlusFlightTimes) == "table" then
        for key, value in pairs(ZwykPlusFlightTimes) do
            if String(key) and #key <= 4096 and Duration(value) then times[key] = value end
        end
    end
    ZwykPlusFlightTimes = times
    local old = ZwykPlusFlightState
    if Readable(old) and type(old) == "table" then
        local p = old.position
        if Readable(p) and type(p) == "table" and Number(p.x) and Number(p.y) then
            position = {x = p.x, y = p.y}
        end
    end
    ZwykPlusFlightState = {position = position}
end

local function Key(points)
    local faction = Call(UnitFactionGroup, "player")
    local locale = Call(GetLocale)
    local parts = {String(faction) and faction or "?"}
    for _, point in ipairs(points) do
        local token = point.id and ("#" .. point.id) or ("@" .. (locale or "?") .. ":" .. point.name)
        parts[#parts + 1] = #token .. ":" .. token
    end
    return table.concat(parts, "/")
end

local function BaseTime(from, to)
    local learned = times[Key({from, to})]
    if Duration(learned) then return learned end
    local data = ZP.flightRouteData and from.id and ZP.flightRouteData[from.id]
    local duration = data and to.id and data[to.id]
    if Duration(duration) then return duration end
end

local function Multiplier()
    local api = C_Traits
    if not api or not api.GetConfigIDByTreeID or not api.GetNodeInfo then return 1, false end
    local ok, config = pcall(api.GetConfigIDByTreeID, 1188)
    if not ok or not Readable(config) then return 1, false end
    if config == nil then return 1, true end
    if not Number(config) then return 1, false end
    local node = Call(api.GetNodeInfo, config, 110300)
    if not Readable(node) or type(node) ~= "table" or not Number(node.activeRank) then return 1, false end
    return node.activeRank > 0 and 1.2 or 1, true
end

local function Snapshot()
    if not (ZP.db and ZP.db.flightTimer) then return end
    local count = Call(NumTaxiNodes)
    if not Number(count) or count < 1 or count > 300 or count ~= math.floor(count) then cache = nil; return end
    local nodes, routes = {}, {}
    local map = Call(GetTaxiMapID)
    local native = Number(map) and C_TaxiMap and Call(C_TaxiMap.GetAllTaxiNodes, map)
    if Readable(native) and type(native) == "table" then
        for _, node in pairs(native) do
            if Readable(node) and type(node) == "table" and Number(node.slotIndex) and Number(node.nodeID)
                and node.slotIndex >= 1 and node.slotIndex <= count and node.slotIndex == math.floor(node.slotIndex)
                and node.nodeID > 0 and node.nodeID == math.floor(node.nodeID) then
                nodes[node.slotIndex] = {id = node.nodeID}
            end
        end
    end
    for slot = 1, count do
        local name = Call(TaxiNodeName, slot)
        nodes[slot] = nodes[slot] or {}
        nodes[slot].name = String(name) and name or L.flightTimerUnknown
    end
    for slot = 1, count do
        local hops = Call(GetNumRoutes, slot)
        if Number(hops) and hops >= 1 and hops <= MAX_HOPS and hops == math.floor(hops) then
            local points, valid = {}, true
            for hop = 1, hops do
                local from, to = Call(TaxiGetNodeSlot, slot, hop, true), Call(TaxiGetNodeSlot, slot, hop, false)
                if not Number(from) or not Number(to) or not nodes[from] or not nodes[to]
                    or (hop > 1 and from ~= points[#points].slot) then valid = false; break end
                if hop == 1 then points[1] = {slot = from, id = nodes[from].id, name = nodes[from].name} end
                points[#points + 1] = {slot = to, id = nodes[to].id, name = nodes[to].name}
            end
            if valid and points[#points].slot == slot then routes[slot] = points end
        end
    end
    -- Keep this public snapshot across synchronous taxi-map closure before the post-hook.
    cache = {routes = routes, open = true}
end

local function Place()
    if not frame or moving then return end
    frame:ClearAllPoints()
    if position then
        local width, height = Call(UIParent.GetWidth, UIParent), Call(UIParent.GetHeight, UIParent)
        local x, y = position.x, position.y
        if Number(width) then x = math.max(0, math.min(x, math.max(0, width - WIDTH))) end
        if Number(height) then y = math.max(0, math.min(y, height)) end
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
    end
end

local function SavePosition()
    local x, y = Call(frame.GetLeft, frame), Call(frame.GetBottom, frame)
    local scale, parentScale = Call(frame.GetEffectiveScale, frame), Call(UIParent.GetEffectiveScale, UIParent)
    if Number(x) and Number(y) and Number(scale) and scale > 0 and Number(parentScale) and parentScale > 0 then
        position = {x = x * scale / parentScale, y = y * scale / parentScale}
        ZwykPlusFlightState.position = position
    end
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end
    Place()
end

local function Label(parent, point, x, y, width)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint(point, x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    return text
end

local function LandingAvailable()
    return flight and not flight.preview and not flight.requested
        and Call(UnitOnTaxi, "player") == true and Call(CanExitVehicle) == true
        and (not InCombatLockdown or Call(InCombatLockdown) == false) and type(TaxiRequestEarlyLanding) == "function"
end

local function CreatePanel()
    if frame then return end
    frame = CreateFrame("Frame", "ZwykPlusFlightTimerFrame", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(WIDTH, 160)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = {left = 3, right = 3, top = 3, bottom = 3}})
    frame:SetBackdropColor(0, 0, 0, 0.65)
    frame:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.8)
    frame.title = Label(frame, "TOPLEFT", 10, -10, 380)
    frame.progress = CreateFrame("StatusBar", nil, frame)
    frame.progress:SetPoint("TOPLEFT", 10, -29)
    frame.progress:SetSize(380, 14)
    frame.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.progress:SetStatusBarColor(0.2, 0.65, 0.9)
    frame.progress:SetMinMaxValues(0, 1)
    local background = frame.progress:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.1, 0.1, 0.1, 0.7)
    frame.time = Label(frame, "TOPLEFT", 10, -49, 245)
    frame.elapsedText = Label(frame, "TOPRIGHT", -10, -49, 125)
    frame.elapsedText:SetJustifyH("RIGHT")
    frame.list = CreateFrame("ScrollFrame", nil, frame)
    frame.list:SetPoint("TOPLEFT", 10, -71)
    frame.list:SetWidth(380)
    frame.list:EnableMouseWheel(true)
    frame.content = CreateFrame("Frame", nil, frame.list)
    frame.content:SetWidth(380)
    frame.list:SetScrollChild(frame.content)
    frame.list:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(frame.scrollMax or 0, self:GetVerticalScroll() - delta * ROW_HEIGHT * 2)))
    end)
    frame.rows = {}
    frame.land = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.land:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.land:SetSize(225, 24)
    frame.land:SetText(L.flightTimerLand)
    frame.land:SetScript("OnClick", function()
        if not LandingAvailable() then return end
        -- Only a hardware click requests landing; the timer never calls this API.
        requesting = true
        local ok, result = pcall(TaxiRequestEarlyLanding)
        requesting = false
        if ok and (not Readable(result) or result ~= false) and flight then
            flight.requested = true
            Update()
        end
    end)
    frame.note = Label(frame, "BOTTOMLEFT", 10, 14, 155)
    frame:SetScript("OnDragStart", function(self)
        if Call(IsAltKeyDown) == true then moving = true; self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        if not moving then return end
        self:StopMovingOrSizing(); moving = false; SavePosition()
    end)
    frame:SetScript("OnHide", function(self)
        if moving then self:StopMovingOrSizing(); moving = false; SavePosition() end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.flightTimerTitle, 1, 0.82, 0)
        GameTooltip:AddLine(L.flightTimerWaypointHelp, 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(L.flightTimerMoveHelp, 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
end

local function Row(index)
    if frame.rows[index] then return frame.rows[index] end
    local row = CreateFrame("Frame", nil, frame.content)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetSize(380, ROW_HEIGHT)
    row.name = Label(row, "LEFT", 0, 0, 275)
    row.time = Label(row, "RIGHT", 0, 0, 100)
    row.time:SetJustifyH("RIGHT")
    row.marker = frame.progress:CreateTexture(nil, "OVERLAY")
    row.marker:SetSize(2, 14)
    row.marker:SetColorTexture(1, 0.82, 0, 1)
    frame.rows[index] = row
    return row
end

local function Format(seconds)
    if not Number(seconds) then return L.flightTimerUnknown end
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function Estimate(points)
    local multiplier, knownPerk = Multiplier()
    local sum, known, identity = 0, true, true
    for _, point in ipairs(points) do
        if not point.id and point.name == L.flightTimerUnknown then identity = false end
    end
    local stops = {}
    for index = 2, #points do
        local duration = BaseTime(points[index - 1], points[index])
        if duration and known then sum = sum + duration else known = false end
        stops[#stops + 1] = {name = points[index].name, at = known and sum / multiplier or nil}
    end
    local key = Key(points)
    local recorded = times[key]
    local total = Duration(recorded) and recorded / multiplier or (known and sum / multiplier or nil)
    if known and sum > 0 and Duration(recorded) then
        for _, stop in ipairs(stops) do stop.at = stop.at * recorded / sum end
    end
    if total and stops[#stops] then stops[#stops].at = total end
    return {points = points, stops = stops, key = key, total = total, multiplier = multiplier,
        learnable = knownPerk and identity, baseTotal = known and sum or nil}
end

local function Render(now)
    local passed = math.max(0, now - flight.start)
    local count = #flight.stops
    frame.title:SetText(flight.points[1].name .. " → " .. flight.points[#flight.points].name)
    local left = not flight.requested and flight.total and (flight.total - passed) or nil
    frame.time:SetText(L.flightTimerRemaining .. ": " .. Format(left))
    frame.elapsedText:SetText(L.flightTimerElapsed .. ": " .. Format(passed))
    frame.progress:SetValue(flight.total and math.min(1, passed / flight.total) or 0)
    frame.note:SetText(flight.preview and L.flightTimerPreview or L.flightTimerEstimated)
    frame.land:SetText(flight.requested and L.flightTimerLandingRequested or L.flightTimerLand)
    frame.land:SetEnabled(not not LandingAvailable())
    for index, stop in ipairs(flight.stops) do
        local row = Row(index)
        row.stop = stop
        row.name:SetText(stop.name)
        row.time:SetText(Format(stop.at and stop.at - passed))
        local dim = stop.at and passed >= stop.at
        row.name:SetTextColor(dim and 0.5 or 1, dim and 0.5 or 1, dim and 0.5 or 1)
        row.time:SetTextColor(dim and 0.5 or 1, dim and 0.5 or 0.82, dim and 0.5 or 0.3)
        row.marker:Hide()
        if stop.at and flight.total then
            row.marker:ClearAllPoints()
            row.marker:SetPoint("CENTER", frame.progress, "LEFT", math.min(1, stop.at / flight.total) * 380, 0)
            row.marker:SetAlpha(dim and 0.3 or 1)
            row.marker:Show()
        end
        row:Show()
    end
    for index = count + 1, #frame.rows do
        frame.rows[index].stop = nil
        frame.rows[index]:Hide()
        frame.rows[index].marker:Hide()
    end
    local shown = math.min(count, 8)
    frame.content:SetHeight(math.max(1, count * ROW_HEIGHT))
    frame.list:SetHeight(math.max(1, shown * ROW_HEIGHT))
    frame.scrollMax = math.max(0, (count - shown) * ROW_HEIGHT)
    frame.list:SetVerticalScroll(math.min(frame.scrollMax, frame.list:GetVerticalScroll()))
    frame:SetHeight(110 + shown * ROW_HEIGHT)
end

Stop = function(learn)
    local regained = flight and flight.ended and flight.gainedAt and math.abs(flight.ended - flight.gainedAt) <= 2
    if flight and learn and not flight.preview and not flight.requested and flight.learnable and regained then
        local now = Clock()
        local measured = now and (flight.ended - flight.start) * flight.multiplier
        local expected = times[flight.key] or flight.baseTotal
        if Duration(measured) and (not expected or (measured >= expected * 0.6 and measured <= expected * 1.6)) then
            times[flight.key] = expected and (expected * 0.75 + measured * 0.25) or measured
        end
    end
    flight, pending = nil, nil
    events:SetScript("OnUpdate", nil)
    elapsed = 0
    if frame then frame:Hide() end
end

local function Poll(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.1 then return end
    elapsed = 0
    Update()
end

Update = function()
    local now = Clock()
    if not now then Stop(false); return end
    if pending then
        local onTaxi = Call(UnitOnTaxi, "player")
        if onTaxi == true then
            local departure = pending.departure or pending.clicked
            local exactStart = now - departure <= 2
            flight = Estimate(pending.points)
            flight.start = exactStart and departure or now
            flight.learnable = flight.learnable and exactStart
            pending = nil
            CreatePanel()
            frame.list:SetVerticalScroll(0)
            frame:Show()
        elseif now - pending.clicked > 15 then Stop(false); return end
    end
    if not flight then return end
    if flight.preview then
        if now - flight.start >= flight.total or Call(UnitOnTaxi, "player") == true then Stop(false); return end
    else
        local onTaxi = Call(UnitOnTaxi, "player")
        if onTaxi == false then
            flight.ended = flight.ended or now
            if now - flight.ended >= 0.2 then Stop(true); return end
        elseif onTaxi == true then
            flight.ended = nil
        else
            flight.learnable = false
        end
    end
    Render(now)
end

local function Taken(slot)
    if not (ZP.db and ZP.db.flightTimer) or not Number(slot) then return end
    local now = Clock()
    if not now then return end
    local points = cache and (cache.open or (cache.expires and cache.expires >= now)) and cache.routes[slot]
    Stop(false)
    pending = {clicked = now, points = points or {{name = L.flightTimerUnknown}, {name = L.flightTimerUnknown}}}
    events:SetScript("OnUpdate", Poll)
    Update()
end

local function InstallHooks()
    if not hooksecurefunc then return end
    if not hooks.take and type(TakeTaxiNode) == "function" then
        hooksecurefunc("TakeTaxiNode", Taken)
        hooks.take = true
    end
    if not hooks.land and type(TaxiRequestEarlyLanding) == "function" then
        hooksecurefunc("TaxiRequestEarlyLanding", function()
            if not requesting and flight and not flight.preview and Call(UnitOnTaxi, "player") == true then
                flight.requested = true
                Update()
            end
        end)
        hooks.land = true
    end
end

function ZP:ResetFlightTimerPosition()
    Saved()
    position = nil
    ZwykPlusFlightState.position = nil
    Place()
end

function ZP:ShowFlightTimerPreview()
    Saved()
    if flight and not flight.preview then return end
    if flight and flight.preview then Stop(false); return end
    if pending or Call(UnitOnTaxi, "player") == true then return end
    local now = Clock()
    if not now then return end
    flight = {preview = true, start = now, total = 30,
        points = {{name = L.flightTimerTitle}, {name = L.flightTimerPreview}},
        stops = {{name = L.flightTimerPreview .. " 1", at = 10}, {name = L.flightTimerPreview .. " 2", at = 20},
            {name = L.flightTimerPreview .. " 3", at = 30}}}
    CreatePanel()
    frame.list:SetVerticalScroll(0)
    frame:Show()
    events:SetScript("OnUpdate", Poll)
    Update()
end

function ZP:RefreshFlightTimer()
    Saved()
    InstallHooks()
    if not (self.db and self.db.flightTimer) then
        cache = nil
        if not (flight and flight.preview) then Stop(false) end
    elseif flight or pending then
        Update()
    end
end

function ZP:InitializeFlightTimer()
    if initialized then return end
    initialized = true
    for _, event in ipairs({"TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TAXI_NODE_STATUS_CHANGED", "PLAYER_CONTROL_LOST",
        "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_LOGOUT", "ADDON_LOADED",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "TAXIMAP_OPENED" or event == "TAXI_NODE_STATUS_CHANGED" then
            Snapshot()
        elseif event == "TAXIMAP_CLOSED" then
            if cache then cache.open = false; cache.expires = (Clock() or 0) + 10 end
        elseif event == "PLAYER_CONTROL_LOST" then
            if pending then pending.departure = Clock() end
            if pending or flight then Update() end
        elseif event == "PLAYER_CONTROL_GAINED" then
            if flight and not flight.preview then flight.gainedAt = Clock() end
            if pending or flight then Update() end
        elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGOUT" then
            Stop(false)
            cache = nil
        elseif event == "ADDON_LOADED" then
            InstallHooks()
        elseif flight then
            Update()
        end
    end)
    self:RefreshFlightTimer()
end
