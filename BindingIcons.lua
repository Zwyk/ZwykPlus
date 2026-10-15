local addonName, ZP = ...
local bagButtons = setmetatable({}, {__mode = "k"})
local rollFrames = setmetatable({}, {__mode = "k"})
local lootButtons = setmetatable({}, {__mode = "k"})
local lootScrollBoxes = setmetatable({}, {__mode = "k"})
local lootOwners = setmetatable({}, {__mode = "k"})
local windowButtons = setmetatable({}, {__mode = "k"})
local containers = setmetatable({}, {__mode = "k"})
local hooks = setmetatable({}, {__mode = "k"})
local globalHooks = {}
local bindTypes, requestedItems = {}, {}
local betterBags = {}
local betterBagItems = setmetatable({}, {__mode = "k"})
local betterBagOwners = setmetatable({}, {__mode = "k"})
local events, queued, refreshing
local QueueRefresh, RegisterRoll
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
    end
    local texture = record.texture
    texture:SetSize(record.size or 14, record.size or 14)
    texture:ClearAllPoints()
    local corner = record.corner or "BOTTOMLEFT"
    texture:SetPoint(corner, icon, corner, record.x or 1, record.y or 1)
    texture:SetTexture(texturePaths[state])
    if state == "open" then texture:SetVertexColor(0.25, 1, 0.35)
    else texture:SetVertexColor(1, 0.55, 0.15) end
    texture:SetAlpha(state == "open" and 0.75 or 1)
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

local function BagStateAt(bag, slot, expectedID, allowBank)
    if not (C_Container and C_Container.GetContainerItemInfo) then return end
    local maximum = NUM_TOTAL_BAG_FRAMES or NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    local inventory = Constants and Constants.InventoryConstants
    if inventory and Number(inventory.NumBagSlots) then
        maximum = inventory.NumBagSlots
        if Number(inventory.NumReagentBagSlots) then maximum = maximum + inventory.NumReagentBagSlots end
    end
    if not Number(maximum) then maximum = 4 end
    if not Number(bag) or (not allowBank and (bag < 0 or bag > maximum)) or not Number(slot) or slot < 1 then return end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok or not Readable(info) or type(info) ~= "table" then return end
    if Number(expectedID) and (not Number(info.itemID) or expectedID ~= info.itemID) then return end
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

local function BagState(button)
    if button.GetBankTabID and button.GetContainerSlotID then
        return BagStateAt(button:GetBankTabID(), button:GetContainerSlotID(), nil, true)
    end
    if button.GetBagID and button.GetID then return BagStateAt(button:GetBagID(), button:GetID()) end
end

local function LinkState(link, bound, catalog)
    if not ItemReference(link) then return end
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    local bindType = BindType(link, id)
    if not Readable(bound) then return end
    if bound == true and bindType and bindType >= 0 and bindType <= 3 then return "closed" end
    if bound == false and bindType == 2 then return "open" end
    -- A vendor's new stock has no owned item instance yet, as on loot rolls.
    if catalog then
        if bindType == 1 then return "closed" end
        if bindType == 2 then return "open" end
    end
end

local function TradeTargetState(index, link)
    local getter = C_TooltipInfo and C_TooltipInfo.GetTradeTargetItem
    local lineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemBinding
    if not getter or not Number(lineType) then return end
    local ok, info = pcall(getter, index)
    if not ok or not Readable(info) or type(info) ~= "table"
        or not Readable(info.lines) or type(info.lines) ~= "table" then return end
    for _, line in ipairs(info.lines) do
        if Readable(line) and type(line) == "table" and Readable(line.type) and line.type == lineType then
            local text = line.leftText
            if Readable(text) and type(text) == "string" then
                if type(ITEM_SOULBOUND) == "string" and text == ITEM_SOULBOUND then
                    return LinkState(link, true)
                elseif type(ITEM_BIND_ON_EQUIP) == "string" and text == ITEM_BIND_ON_EQUIP then
                    return LinkState(link, false)
                end
            end
        end
    end
end

local function WindowState(button, record)
    local kind, owner = record.kind, record.owner
    if not Shown(owner) then return end
    local tab, index
    if kind == "tradePlayer" or kind == "tradeTarget" then
        -- Trade slot IDs belong to the row; its child item button has ID 0.
        local row = button.GetParent and button:GetParent()
        index = row and row.GetID and row:GetID()
    else
        tab = MerchantFrame and MerchantFrame.selectedTab
        if not Readable(tab) then return end
        index = button.GetID and button:GetID()
    end
    if kind == "buybackLatest" then
        if not GetNumBuybackItems or tab ~= 1 then return end
        index = GetNumBuybackItems()
    end
    if not Number(index) or index < 1 then return end
    local linkGetter, infoGetter, boundIndex, catalog
    if kind == "merchant" and tab == 1 then
        linkGetter, catalog = GetMerchantItemLink, true
    elseif (kind == "merchant" and tab == 2) or kind == "buybackLatest" then
        linkGetter, infoGetter, boundIndex = GetBuybackItemLink, GetBuybackItemInfo, 7
    elseif kind == "tradePlayer" then
        linkGetter, infoGetter, boundIndex = GetTradePlayerItemLink, GetTradePlayerItemInfo, 7
    elseif kind == "tradeTarget" then
        linkGetter = GetTradeTargetItemLink
    end
    if type(linkGetter) ~= "function" then return end
    local ok, link = pcall(linkGetter, index)
    if not ok or not ItemReference(link) then return end
    if kind == "tradeTarget" then return TradeTargetState(index, link) end
    local bound
    if infoGetter then
        local infoOK, value = pcall(function() return select(boundIndex, infoGetter(index)) end)
        if not infoOK then return end
        bound = value
    end
    return LinkState(link, bound, catalog)
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
    return button.IconTexture or button.icon or button.Icon
        or (GetItemButtonIconTexture and GetItemButtonIconTexture(button))
end

local function LootState(row)
    if not GetLootSlotLink or not GetLootSlotType then return end
    -- Modern rows are pooled and their button ID is not the loot slot.
    local slot
    if type(row.GetSlotIndex) == "function" then
        local ok, value = pcall(row.GetSlotIndex, row)
        if ok then slot = value end
    else
        slot = row.slot -- Original paged LootButton frames store the actual slot here.
    end
    if not Number(slot) or slot < 1 then return end
    local itemType = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or LOOT_SLOT_ITEM
    if not Number(itemType) then return end
    local typeOK, slotType = pcall(GetLootSlotType, slot)
    if not typeOK or not Number(slotType) or slotType ~= itemType then return end
    local linkOK, link = pcall(GetLootSlotLink, slot)
    if linkOK then return LinkState(link, nil, true) end
end

local function BetterBagsData(item)
    if not Readable(item) or type(item) ~= "table" or not Readable(item.isFreeSlot)
        or item.isFreeSlot or not Readable(item.staticData) or item.staticData or not item.GetItemData then return end
    local ok, data = pcall(item.GetItemData, item)
    if not ok or not Readable(data) or type(data) ~= "table" or not Readable(data.isItemEmpty)
        or data.isItemEmpty or not Readable(data.isFreeSlot) or data.isFreeSlot
        or not Readable(data.isItemGap) or data.isItemGap
        or not Readable(data.itemInfo) or type(data.itemInfo) ~= "table" then return end
    return data
end

local function BetterBagsSlotState(data)
    if not Readable(data) or type(data) ~= "table" then return end
    local id = Readable(data.itemInfo) and type(data.itemInfo) == "table" and data.itemInfo.itemID
    if not Number(id) then return end
    -- BetterBags' data points to the real root slot, even for virtual groups.
    -- Its interaction button can instead have the sentinel bag ID -3.
    local bag = data.bagid
    local constants = betterBags.constants
    local bank = Number(bag) and constants and
        ((constants.BANK_BAGS and constants.BANK_BAGS[bag]) or
         (constants.ACCOUNT_BANK_BAGS and constants.ACCOUNT_BANK_BAGS[bag]))
    return BagStateAt(bag, data.slotid, id, Readable(bank) and bank ~= nil and bank ~= false)
end

local function BetterBagsState(record)
    if record.cleared then return end
    local item = record.betterBagsItem
    local data = BetterBagsData(item)
    if not data or not Shown(item.frame) then return end
    local state = BetterBagsSlotState(data)
    if not state then return end
    -- Hashes normally separate binding scopes. Check represented child slots
    -- too, so a stale or mixed merged group never claims one binding state.
    local api = betterBags.items
    local merged = Number(data.stackedCount) and Number(data.itemInfo.currentItemCount)
        and data.stackedCount > data.itemInfo.currentItemCount
    if merged and api and api.GetAllSlotInfo and api.GetItemDataFromSlotKey and Readable(data.itemHash)
        and type(data.itemHash) == "string" and Readable(item.kind) then
        local ok, slots = pcall(api.GetAllSlotInfo, api)
        local group = ok and Readable(slots) and type(slots) == "table" and slots[item.kind]
        local stacks = Readable(group) and type(group) == "table" and group.stacks
        if stacks and stacks.GetStackInfo then
            local stackOK, stack = pcall(stacks.GetStackInfo, stacks, data.itemHash)
            if stackOK and Readable(stack) and type(stack) == "table" and stack.rootItem == data.slotkey
                and Readable(stack.slotkeys) and type(stack.slotkeys) == "table" then
                local visible = group.visibleItemsBySlotKey
                if not Readable(visible) or type(visible) ~= "table" then return end
                for key in pairs(stack.slotkeys) do
                    if not Readable(key) or type(key) ~= "string" then return end
                    -- Independently displayed partial stacks are not included
                    -- in this root, even when they share the same item hash.
                    if visible[key] == nil then
                        local childOK, child = pcall(api.GetItemDataFromSlotKey, api, key)
                        if not childOK or BetterBagsSlotState(child) ~= state then return end
                    end
                end
            end
        end
    end
    return state
end

local function RefreshBag(button, record)
    local icon = BagIcon(button)
    local state
    if ZP.db and ZP.db.itemBindingIcons and Shown(button) and icon then
        if record.betterBagsItem then
            -- Icon textures can still have template dimensions during item/Updated.
            -- Use the current decoration geometry, including subsequent row/grid resizing.
            local width = button.GetWidth and button:GetWidth()
            local height = button.GetHeight and button:GetHeight()
            record.size = Number(width) and width > 0 and Number(height) and height > 0
                and math.min(width, height) <= 24 and 10 or 14
            state = BetterBagsState(record)
        elseif not icon.IsShown or Shown(icon) then
            state = BagState(button)
        end
    end
    SetIcon(record, state, button, icon)
end

local function RefreshRoll(frame, record)
    local parent = frame.IconFrame
    local icon = parent and parent.Icon
    local state
    if ZP.db and ZP.db.itemBindingIcons and Shown(frame) and Usable(parent) and icon then state = RollState(frame) end
    SetIcon(record, state, parent, icon)
end

local function RefreshLoot(button, record)
    local icon = BagIcon(button)
    local state
    if ZP.db and ZP.db.itemBindingIcons and Shown(LootFrame) and Shown(record.row)
        and Shown(button) and icon and (not icon.IsShown or Shown(icon)) then
        state = LootState(record.row)
    end
    SetIcon(record, state, button, icon)
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

local function RegisterLoot(row)
    if not Usable(row) then return end
    local button = row.Item or row
    if not Usable(button) then return end
    local record = lootButtons[button]
    if not record then
        record = {}; lootButtons[button] = record
        button:HookScript("OnShow", function() RefreshLoot(button, record) end)
        button:HookScript("OnHide", function() SetIcon(record) end)
        if row ~= button then
            row:HookScript("OnShow", function() RefreshLoot(button, record) end)
            row:HookScript("OnHide", function() SetIcon(record) end)
        end
        HookMethod(row, "Init", function() RefreshLoot(button, record) end)
    end
    record.row = row
    RefreshLoot(button, record)
end

local function DiscoverLoot()
    HookMethod(LootFrameElementMixin, "Init", RegisterLoot)
    local scrollBox = LootFrame and LootFrame.ScrollBox
    if scrollBox then
        if not lootScrollBoxes[scrollBox] and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
            -- Register after initialization; the slot is read afresh on every reuse.
            lootScrollBoxes[scrollBox] = pcall(ScrollUtil.AddInitializedFrameCallback, scrollBox,
                function(_, row) RegisterLoot(row) end, ZP)
        end
        if type(scrollBox.EnumerateFrames) == "function" then
            for _, row in scrollBox:EnumerateFrames() do RegisterLoot(row) end
        end
    end
    local count = Number(LOOTFRAME_NUMBUTTONS) and LOOTFRAME_NUMBUTTONS or 4
    for i = 1, count do RegisterLoot(_G["LootButton" .. i]) end
    if Usable(LootFrame) and not lootOwners[LootFrame] then
        lootOwners[LootFrame] = true
        LootFrame:HookScript("OnHide", function()
            for _, record in pairs(lootButtons) do SetIcon(record) end
        end)
    end
    for name, callback in pairs({LootFrame_Update = DiscoverLoot, LootFrame_UpdateButton = DiscoverLoot,
        GroupLootFrame_SetupItemDisplay = RegisterRoll, GroupLootFrame_OnShow = RegisterRoll}) do
        if not globalHooks[name] and type(_G[name]) == "function" and hooksecurefunc then
            globalHooks[name] = pcall(hooksecurefunc, name, callback)
        end
    end
end

local function RefreshWindow(button, record)
    local icon = BagIcon(button)
    local state
    if ZP.db and ZP.db.itemBindingIcons and Shown(button) and icon
        and (not icon.IsShown or Shown(icon)) then state = WindowState(button, record) end
    SetIcon(record, state, button, icon)
end

local function RegisterWindow(button, kind, owner)
    if not Usable(button) then return end
    local record = windowButtons[button]
    if not record then
        record = {}; windowButtons[button] = record
        button:HookScript("OnShow", function() RefreshWindow(button, record) end)
        button:HookScript("OnHide", function() SetIcon(record) end)
    end
    record.kind, record.owner = kind, owner
    RefreshWindow(button, record)
end

local function RegisterBag(button)
    if not Usable(button) then return end
    local record = bagButtons[button]
    if not record then record = {}; bagButtons[button] = record end
    if not record.hooked then
        record.hooked = true
        button:HookScript("OnShow", function() RefreshBag(button, record) end)
        button:HookScript("OnHide", function() SetIcon(record) end)
        button:HookScript("OnSizeChanged", function()
            if record.betterBagsItem then RefreshBag(button, record) end
        end)
        HookMethod(button, "Initialize", function() RefreshBag(button, record) end)
        if button.GetBankTabID and button.GetContainerSlotID then
            HookMethod(button, "Refresh", function() RefreshBag(button, record) end)
        end
    end
    RefreshBag(button, record)
end

local function RegisterBetterBagsItem(_, item, decoration)
    if not Readable(item) or type(item) ~= "table" or not Usable(decoration) then return end
    local previous = betterBagItems[item]
    if previous and previous ~= decoration and bagButtons[previous] then
        bagButtons[previous].cleared = true
        SetIcon(bagButtons[previous])
    end
    local record = bagButtons[decoration] or {}
    bagButtons[decoration] = record
    local previousItem = record.betterBagsItem
    if previousItem and previousItem ~= item and betterBagItems[previousItem] == decoration then
        betterBagItems[previousItem] = nil
    end
    record.betterBagsItem, record.cleared = item, false
    record.corner, record.x, record.y = "TOPRIGHT", -1, -1
    betterBagItems[item] = decoration
    RegisterBag(decoration)
    if Usable(item.frame) and not betterBagOwners[item.frame] then
        betterBagOwners[item.frame] = true
        item.frame:HookScript("OnShow", function()
            local current = betterBagItems[item]
            if current and bagButtons[current] then RefreshBag(current, bagButtons[current]) end
        end)
        item.frame:HookScript("OnHide", function()
            local current = betterBagItems[item]
            if current then SetIcon(bagButtons[current] or {}) end
        end)
    end
    if not Shown(item.frame) and QueueRefresh then QueueRefresh() end
end

local function ClearBetterBagsItem(_, item, decoration)
    for _, button in pairs({decoration, betterBagItems[item]}) do
        local record = bagButtons[button]
        if record and record.betterBagsItem == item then record.cleared = true; SetIcon(record) end
    end
end

local function DiscoverBetterBags()
    if not LibStub then return end
    local ok, addon = pcall(function()
        local ace = LibStub("AceAddon-3.0", true)
        return ace and ace:GetAddon("BetterBags", true)
    end)
    if not ok or not addon or not addon.GetModule then return end
    local function module(name)
        local success, value = pcall(addon.GetModule, addon, name, true)
        if success then return value end
    end
    local bus = module("Events")
    if not bus or not bus.RegisterMessage or not bus._messageMap or not bus._eventHandler then return end
    betterBags.items, betterBags.constants = module("Items"), module("Constants")
    if not betterBags.updated then
        betterBags.updated = pcall(bus.RegisterMessage, bus, "item/Updated", RegisterBetterBagsItem)
    end
    if not betterBags.clearing then
        betterBags.clearing = pcall(bus.RegisterMessage, bus, "item/Clearing", ClearBetterBagsItem)
    end
    if not (ZP.db and ZP.db.itemBindingIcons) then return end
    local itemFrames, themes, context = module("ItemFrame"), module("Themes"), module("Context")
    if not itemFrames or not themes or not themes.GetItemButton or not context or not context.New then return end
    local contextOK, ctx = pcall(context.New, context, "ZwykPlusBindingIcons")
    if not contextOK or not ctx then return end
    local seen = {}
    local function visit(item)
        if seen[item] then return end
        seen[item] = true
        if not BetterBagsData(item) or not Shown(item.frame) then return end
        if item.frame.IsVisible and not item.frame:IsVisible() then return end
        local success, decoration = pcall(themes.GetItemButton, themes, ctx, item)
        if success then RegisterBetterBagsItem(ctx, item, decoration) end
    end
    for _, item in pairs(itemFrames.buttonsBySlotkey or {}) do visit(item) end
    for item in pairs(itemFrames.activeItems or {}) do visit(item) end
end

RegisterRoll = function(frame)
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

local function RefreshBank(panel)
    if not panel or type(panel.EnumerateValidItems) ~= "function" then return end
    HookMethod(panel, "GenerateItemSlotsForSelectedTab", RefreshBank)
    HookMethod(panel, "RefreshAllItemsForSelectedTab", RefreshBank)
    for button in panel:EnumerateValidItems() do RegisterBag(button) end
end

local function RefreshMerchantWindows()
    local count = math.max(Number(MERCHANT_ITEMS_PER_PAGE) and MERCHANT_ITEMS_PER_PAGE or 10,
        Number(BUYBACK_ITEMS_PER_PAGE) and BUYBACK_ITEMS_PER_PAGE or 12)
    for i = 1, count do
        RegisterWindow(_G["MerchantItem" .. i .. "ItemButton"], "merchant", MerchantFrame)
    end
    RegisterWindow(MerchantBuyBackItemItemButton, "buybackLatest", MerchantFrame)
end

local function RefreshTradePlayer(index)
    if Number(index) and index >= 1 then
        RegisterWindow(_G["TradePlayerItem" .. index .. "ItemButton"], "tradePlayer", TradeFrame)
    end
end

local function RefreshTradeTarget(index)
    if Number(index) and index >= 1 then
        RegisterWindow(_G["TradeRecipientItem" .. index .. "ItemButton"], "tradeTarget", TradeFrame)
    end
end

local function DiscoverWindows()
    RefreshMerchantWindows()
    local count = Number(MAX_TRADE_ITEMS) and MAX_TRADE_ITEMS or 7
    for i = 1, count do RefreshTradePlayer(i); RefreshTradeTarget(i) end
    for name, callback in pairs({MerchantFrame_UpdateMerchantInfo = RefreshMerchantWindows,
        MerchantFrame_UpdateBuybackInfo = RefreshMerchantWindows,
        TradeFrame_UpdatePlayerItem = RefreshTradePlayer, TradeFrame_UpdateTargetItem = RefreshTradeTarget}) do
        if not globalHooks[name] and type(_G[name]) == "function" and hooksecurefunc then
            globalHooks[name] = pcall(hooksecurefunc, name, callback)
        end
    end
    HookMethod(BankPanelMixin, "GenerateItemSlotsForSelectedTab", RefreshBank)
    HookMethod(BankPanelMixin, "RefreshAllItemsForSelectedTab", RefreshBank)
    HookMethod(BankPanelItemButtonMixin, "Init", RegisterBag)
    HookMethod(CamelotBankPanelItemButtonMixin, "Init", RegisterBag)
    RefreshBank(BankFrame and BankFrame.BankPanel)
end

local function Discover()
    -- Hook the mixins for future objects and the existing instances above:
    -- native frames created earlier already have their own copied methods.
    HookMethod(ContainerFrameMixin, "UpdateItems", RefreshContainer)
    HookMethod(ContainerFrameMixin, "UpdateItemSlots", RefreshContainer)
    HookMethod(ContainerFrameItemButtonMixin, "Initialize", RegisterBag)
    DiscoverLoot()
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
    DiscoverBetterBags()
    DiscoverWindows()
    for button, record in pairs(lootButtons) do RefreshLoot(button, record) end
    for button, record in pairs(windowButtons) do RefreshWindow(button, record) end
    for button, record in pairs(bagButtons) do RefreshBag(button, record) end
    for frame, record in pairs(rollFrames) do RefreshRoll(frame, record) end
    refreshing = false
end

QueueRefresh = function()
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
        "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "PLAYER_ENTERING_WORLD", "ADDON_LOADED",
        "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED",
        "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
        "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE",
        "TRADE_SHOW", "TRADE_CLOSED", "TRADE_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, id)
        if event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
            if not Number(id) or not requestedItems[id] then return end
        end
        QueueRefresh()
    end)
    self:RefreshItemBindingIcons()
    QueueRefresh() -- BetterBags' Ace modules can initialize later in this tick.
end
