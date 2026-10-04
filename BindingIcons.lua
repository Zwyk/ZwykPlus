local addonName, ZP = ...
local bagButtons = setmetatable({}, {__mode = "k"})
local rollFrames = setmetatable({}, {__mode = "k"})
local containers = setmetatable({}, {__mode = "k"})
local hooks = setmetatable({}, {__mode = "k"})
local globalHooks = {}
local bindTypes, requestedItems = {}, {}
local events, queued, refreshing
local texturePaths = {
    closed = "Interface\\AddOns\\" .. addonName .. "\\Textures\\BindingChainClosed.tga",
    open = "Interface\\AddOns\\" .. addonName .. "\\Textures\\BindingChainOpen.tga",
}

local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function ItemReference(value)
    return Readable(value) and ((type(value) == "string" and value ~= "")
        or (Number(value) and value > 0))
end

local function Usable(frame)
    return frame and frame.CreateTexture and frame.HookScript
        and (not frame.IsForbidden or not frame:IsForbidden())
end

local function Shown(frame)
    if not frame or not frame.IsShown then return false end
    local shown = frame:IsShown()
    return Readable(shown) and shown == true
end

local function SetIcon(record, state, parent, icon)
    if not state then
        if record.texture then record.texture:Hide() end
        return
    end
    if not record.texture then
        record.texture = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        record.texture:SetSize(14, 14)
    end
    local texture = record.texture
    texture:ClearAllPoints()
    texture:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
    texture:SetTexture(texturePaths[state])
    texture:Show()
end

local function ReadBindType(reference)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get or not ItemReference(reference) then return end
    -- Binding is return 14; GetItemInfoInstant does not include it.
    local ok, value = pcall(function() return select(14, get(reference)) end)
    if ok and Number(value) then return value end
end

local function BindType(link, id)
    if not Number(id) or id <= 0 then id = nil end
    if id and bindTypes[id] ~= nil then return bindTypes[id] end
    local reference = ItemReference(link) and link or id
    local value = ReadBindType(reference)
    if value == nil and id and not requestedItems[id] and C_Item and C_Item.RequestLoadItemDataByID then
        requestedItems[id] = true -- A cached request can finish synchronously.
        pcall(C_Item.RequestLoadItemDataByID, id)
        value = ReadBindType(reference)
    end
    if value ~= nil and id then bindTypes[id] = value end
    return value
end

local function BagLocation(bag, slot)
    if ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local ok, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
        if ok then return location end
    end
end

local function BagState(button)
    if not (C_Container and C_Container.GetContainerItemInfo and button.GetBagID and button.GetID) then return end
    local bag, slot = button:GetBagID(), button:GetID()
    local maximum = NUM_TOTAL_BAG_FRAMES or NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    local inventory = Constants and Constants.InventoryConstants
    if inventory and Number(inventory.NumBagSlots) then
        maximum = inventory.NumBagSlots
        if Number(inventory.NumReagentBagSlots) then maximum = maximum + inventory.NumReagentBagSlots end
    end
    if not Number(maximum) then maximum = 4 end
    if not Number(bag) or bag < 0 or bag > maximum or not Number(slot) or slot < 1 then return end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok or not Readable(info) or type(info) ~= "table" then return end
    local bound = info.isBound
    if not Readable(bound) then return end
    if bound == nil and C_Item and C_Item.IsBound then
        local location = BagLocation(bag, slot)
        if location then
            local boundOK, value = pcall(C_Item.IsBound, location)
            if boundOK and Readable(value) then bound = value end
        end
    end
    if type(bound) ~= "boolean" then return end
    local bindType = BindType(info.hyperlink, info.itemID)
    if bound then
        if bindType and bindType >= 0 and bindType <= 3 then return "closed" end
        -- Account-until-equip items become soulbound after equipping; the
        -- static bind type alone cannot distinguish the two instance states.
        if bindType == 9 and C_Item and C_Item.IsBoundToAccountUntilEquip then
            local location = BagLocation(bag, slot)
            if location then
                local accountOK, account = pcall(C_Item.IsBoundToAccountUntilEquip, location)
                if accountOK and Readable(account) and account == false then return "closed" end
            end
        end
    elseif bindType == 2 then
        return "open"
    end
end

local function RollState(frame)
    local id = frame.rollID
    if not Number(id) or id < 0 or not GetLootRollItemLink then return end
    local ok, link = pcall(GetLootRollItemLink, id)
    if not ok or not ItemReference(link) then return end
    local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    local bindType = BindType(link, itemID)
    if bindType == nil or bindType == 4 or bindType >= 7 then return end
    if GetLootRollItemInfo then
        local infoOK, pickup = pcall(function() return select(5, GetLootRollItemInfo(id)) end)
        if infoOK and Readable(pickup) and pickup == true then return "closed" end
    end
    if bindType == 1 then return "closed" end
    if bindType == 2 then return "open" end
end

local function BagIcon(button)
    return button.icon or button.Icon
        or (GetItemButtonIconTexture and GetItemButtonIconTexture(button))
end

local function RefreshBag(button, record)
    local icon = BagIcon(button)
    local state
    if ZP.db and ZP.db.itemBindingIcons and Shown(button) and icon then state = BagState(button) end
    SetIcon(record, state, button, icon)
end

local function RefreshRoll(frame, record)
    local parent = frame.IconFrame
    local icon = parent and parent.Icon
    local state
    if ZP.db and ZP.db.itemBindingIcons and Shown(frame) and Usable(parent) and icon then state = RollState(frame) end
    SetIcon(record, state, parent, icon)
end

local function HookMethod(object, method, callback)
    if not object or type(object[method]) ~= "function" or not hooksecurefunc then return end
    local methods = hooks[object]
    if not methods then methods = {}; hooks[object] = methods end
    if not methods[method] then
        local ok = pcall(hooksecurefunc, object, method, callback)
        if ok then methods[method] = true end
    end
end

local function RegisterBag(button)
    if not Usable(button) then return end
    local record = bagButtons[button]
    if not record then
        record = {}; bagButtons[button] = record
        button:HookScript("OnShow", function() RefreshBag(button, record) end)
        button:HookScript("OnHide", function() SetIcon(record) end)
        HookMethod(button, "Initialize", function() RefreshBag(button, record) end)
    end
    RefreshBag(button, record)
end

local function RegisterRoll(frame)
    if not Usable(frame) then return end
    local record = rollFrames[frame]
    if not record then
        record = {}; rollFrames[frame] = record
        frame:HookScript("OnShow", function() RefreshRoll(frame, record) end)
        frame:HookScript("OnHide", function() SetIcon(record) end)
    end
    RefreshRoll(frame, record)
end

local function RefreshContainer(frame)
    if not Usable(frame) then return end
    if not containers[frame] then
        containers[frame] = true
        frame:HookScript("OnShow", function() RefreshContainer(frame) end)
        HookMethod(frame, "UpdateItems", RefreshContainer)
        HookMethod(frame, "UpdateItemSlots", RefreshContainer)
    end
    if frame.EnumerateValidItems then
        for _, button in frame:EnumerateValidItems() do RegisterBag(button) end
    elseif type(frame.Items) == "table" then
        for _, button in pairs(frame.Items) do RegisterBag(button) end
    end
end

local function Discover()
    -- Hook the mixins for future objects and the existing instances above:
    -- native frames created earlier already have their own copied methods.
    HookMethod(ContainerFrameMixin, "UpdateItems", RefreshContainer)
    HookMethod(ContainerFrameMixin, "UpdateItemSlots", RefreshContainer)
    HookMethod(ContainerFrameItemButtonMixin, "Initialize", RegisterBag)
    if not globalHooks.roll and type(GroupLootFrame_SetupItemDisplay) == "function" and hooksecurefunc then
        local ok = pcall(hooksecurefunc, "GroupLootFrame_SetupItemDisplay", RegisterRoll)
        if ok then globalHooks.roll = true end
    end
    local count = Number(NUM_CONTAINER_FRAMES) and NUM_CONTAINER_FRAMES or 13
    for i = 1, count do RefreshContainer(_G["ContainerFrame" .. i]) end
    RefreshContainer(ContainerFrameCombinedBags)
    count = Number(NUM_GROUP_LOOT_FRAMES) and NUM_GROUP_LOOT_FRAMES or 4
    for i = 1, count do RegisterRoll(_G["GroupLootFrame" .. i]) end
    if GroupLootContainer and type(GroupLootContainer.rollFrames) == "table" then
        for _, frame in pairs(GroupLootContainer.rollFrames) do RegisterRoll(frame) end
    end
end

function ZP:RefreshItemBindingIcons()
    if refreshing then return end
    refreshing = true
    Discover()
    for button, record in pairs(bagButtons) do RefreshBag(button, record) end
    for frame, record in pairs(rollFrames) do RefreshRoll(frame, record) end
    refreshing = false
end

local function QueueRefresh()
    if queued then return end
    if C_Timer and C_Timer.After then
        queued = true
        C_Timer.After(0, function()
            queued = false
            ZP:RefreshItemBindingIcons()
        end)
    else
        ZP:RefreshItemBindingIcons()
    end
end

function ZP:InitializeItemBindingIcons()
    if events then return end
    events = CreateFrame("Frame")
    for _, event in ipairs({"BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "USE_COMBINED_BAGS_CHANGED",
        "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "PLAYER_ENTERING_WORLD", "ADDON_LOADED",
        "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, id)
        if event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
            if not Number(id) or not requestedItems[id] then return end
        end
        QueueRefresh()
    end)
    self:RefreshItemBindingIcons()
end
