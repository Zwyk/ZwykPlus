local _, ZP = ...
local chatFrames = {}
local hookedText = setmetatable({}, {__mode = "k"})
local players = {}
local itemIcons, requestedItems, atlasIcons = {}, {}, {}
local events
local realm
local raceAtlasNames = {
    Scourge = "Undead",
    HighmountainTauren = "Highmountain",
    LightforgedDraenei = "Lightforged",
    ZandalariTroll = "Zandalari",
    EarthenDwarf = "Earthen",
    Harronir = "Haranir",
}

local function Accessible(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function PublicString(value)
    return Accessible(value) and type(value) == "string" and value ~= ""
end

local function NameKey(name)
    if not PublicString(name) then return end
    local character, server = name:match("^([^-]+)%-(.+)$")
    if not character then character, server = name, realm end
    if not server then return end
    return character:lower() .. "-" .. server:gsub("%s", ""):lower()
end

local function RememberPlayer(name, guid)
    if not PublicString(guid) or not guid:match("^Player%-") then return false end
    local key = NameKey(name)
    if not key or players[key] == guid then return false end
    players[key] = guid
    return true
end

function ZP:RefreshChatIcons()
    for frame in pairs(chatFrames) do frame:MarkDisplayDirty() end
end

local function RememberUnit(unit)
    if not (UnitGUID and UnitName) then return end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not PublicString(guid) or not guid:match("^Player%-") then return end
    local nameOK, name, server = pcall(UnitName, unit)
    if not nameOK or not PublicString(name) or not Accessible(server) then return end
    if PublicString(server) then name = name .. "-" .. server end
    return RememberPlayer(name, guid)
end

local function RememberUnits()
    local changed = RememberUnit("player")
    for _, unit in ipairs({"target", "focus", "mouseover"}) do
        changed = RememberUnit(unit) or changed
    end
    for i = 1, 4 do changed = RememberUnit("party" .. i) or changed end
    for i = 1, 40 do changed = RememberUnit("raid" .. i) or changed end
    if changed then ZP:RefreshChatIcons() end
end

local function ItemIcon(id)
    if not id or id <= 0 then return end
    if itemIcons[id] then return itemIcons[id] end
    local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if get then
        local ok, icon = pcall(get, id)
        if ok and Accessible(icon) and type(icon) == "number" and icon > 0 then
            local markup = "|T" .. icon .. ":0|t"
            itemIcons[id] = markup
            return markup
        end
    end
    if not requestedItems[id] and C_Item and C_Item.RequestLoadItemDataByID then
        -- Set this first: cached item data can complete synchronously.
        requestedItems[id] = true
        pcall(C_Item.RequestLoadItemDataByID, id)
        -- Recheck once in case the request completed during this display update.
        return ItemIcon(id)
    end
end

local function AtlasIcon(atlas)
    if not PublicString(atlas) then return end
    if atlasIcons[atlas] ~= nil then return atlasIcons[atlas] or nil end
    if not (C_Texture and C_Texture.GetAtlasInfo and CreateAtlasMarkup) then return end
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    if not ok or not Accessible(info) or not info then
        atlasIcons[atlas] = false
        return
    end
    local markupOK, markup = pcall(CreateAtlasMarkup, atlas, 0, 0)
    if markupOK and PublicString(markup) then
        atlasIcons[atlas] = markup
        return markup
    end
end

local function PlayerIcons(guid)
    if not PublicString(guid) or not guid:match("^Player%-") or not GetPlayerInfoByGUID then return end
    local ok, _, class, _, race, sex = pcall(GetPlayerInfoByGUID, guid)
    if not ok then return end
    local classIcon, raceIcon
    if ZP.db.chatClassIcons and PublicString(class) then
        local atlas
        if GetClassAtlas then
            local atlasOK, value = pcall(GetClassAtlas, class)
            if atlasOK and PublicString(value) then atlas = value end
        end
        classIcon = AtlasIcon(atlas or ("classicon-" .. class:lower()))
    end
    if ZP.db.chatRaceIcons and PublicString(race) and Accessible(sex) and (sex == 2 or sex == 3) then
        local raceName = raceAtlasNames[race] or race
        local suffix = raceName .. (sex == 3 and "-female" or "-male")
        raceIcon = AtlasIcon("raceicon128-" .. suffix) or AtlasIcon("raceicon-" .. suffix)
    end
    if classIcon and raceIcon then return classIcon .. raceIcon end
    return classIcon or raceIcon
end

local function LinkIcons(kind, payload)
    if kind == "item" and ZP.db.chatItemIcons then
        return ItemIcon(tonumber(payload:match("^(%d+):") or payload:match("^(%d+)$")))
    elseif ZP.db.chatClassIcons or ZP.db.chatRaceIcons then
        if kind == "player" or kind == "playerCommunity" or kind == "playerGM" then
            local key = NameKey(payload:match("^([^:]+)"))
            return key and PlayerIcons(players[key])
        elseif kind == "unit" then
            return PlayerIcons(payload:match("^([^:]+)"))
        end
    end
end

function ZP:FormatChatText(text)
    if not self.db or not PublicString(text) then return text end
    if not (self.db.chatItemIcons or self.db.chatClassIcons or self.db.chatRaceIcons) then return text end
    if not text:find("|H", 1, true) then return text end
    local pieces, cursor = {}, 1
    while true do
        local first, last, link, kind, payload, label = text:find("(|H([^:|]+):([^|]-)|h(.-)|h)", cursor)
        if not first then break end
        local before = text:sub(cursor, first - 1)
        local color = before:match("(|c%x%x%x%x%x%x%x%x)$") or ""
        local prefix = before:sub(1, #before - #color)
        -- Avoid duplicating icons if another display formatter already supplied one.
        local hasIcon = prefix:find("|[ta]%s*$") or label:find("|T", 1, true) or label:find("|A:", 1, true)
        local icons = not hasIcon and LinkIcons(kind, payload)
        if icons then
            -- Place textures outside the color code, so item quality/class colors do not tint them.
            pieces[#pieces + 1] = prefix .. icons .. " " .. color .. link
        else
            pieces[#pieces + 1] = before .. link
        end
        cursor = last + 1
    end
    pieces[#pieces + 1] = text:sub(cursor)
    return table.concat(pieces)
end

local function HookFontString(_, fontString)
    if hookedText[fontString] or not fontString.SetText then return end
    hookedText[fontString] = true
    local setText = fontString.SetText
    fontString.SetText = function(self, text, ...)
        return setText(self, ZP:FormatChatText(text), ...)
    end
end

local function HookChatFrame(frame)
    if chatFrames[frame] or not (frame.InitializeFontString and frame.MarkDisplayDirty) then return end
    chatFrames[frame] = true
    -- Forever initializes each pooled line before writing it, including display-only updates.
    hooksecurefunc(frame, "InitializeFontString", HookFontString)
    frame:MarkDisplayDirty()
end

function ZP:InitializeChatIcons()
    if events then return end
    realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not PublicString(realm) then realm = GetRealmName and GetRealmName() end
    if not PublicString(realm) then realm = nil end
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "ITEM_DATA_LOAD_RESULT" then
            local id, success = ...
            if Accessible(id) and Accessible(success) and success and requestedItems[id] then
                ZP:RefreshChatIcons()
            end
        elseif event:match("^CHAT_MSG_") then
            -- Standard chat payload: sender name at 2, player GUID at 12.
            if RememberPlayer(select(2, ...), select(12, ...)) then ZP:RefreshChatIcons() end
        else
            RememberUnits()
        end
    end)
    for _, event in ipairs({"ITEM_DATA_LOAD_RESULT", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
        "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_ENTERING_WORLD", "CHAT_MSG_CHANNEL"}) do
        events:RegisterEvent(event)
    end
    for _, group in pairs(ChatTypeGroup or {}) do
        for _, event in ipairs(group) do
            if event:match("^CHAT_MSG_") then events:RegisterEvent(event) end
        end
    end
    for i = 1, NUM_CHAT_WINDOWS or 0 do
        local frame = _G["ChatFrame" .. i]
        if frame then HookChatFrame(frame) end
    end
    if ChatFrameMixin and ChatFrameMixin.OnLoad then
        hooksecurefunc(ChatFrameMixin, "OnLoad", HookChatFrame)
    elseif ChatFrame_OnLoad then
        hooksecurefunc("ChatFrame_OnLoad", HookChatFrame)
    end
    RememberUnits()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if loaded and loaded("ChatLinkIcons") then self:WarnOnce("chatIconsConflict", self.L.chatIconsConflict) end
end
