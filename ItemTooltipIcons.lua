local _, ZP = ...
local initialized, arranging = false, false
local records = setmetatable({}, {__mode = "k"})
local requested = {}
local names = {"GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2"}

local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
        and (not canaccessvalue or canaccessvalue(value))
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value == value and math.abs(value) < 1e12
end

local function ID(value)
    return Number(value) and value > 0 and value % 1 == 0
end

local function String(value)
    return Readable(value) and type(value) == "string" and value ~= ""
end

local function Public(frame)
    if not Readable(frame) or not frame then return false end
    if type(frame) ~= "table" and type(frame) ~= "userdata" then return false end
    if frame.IsForbidden then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or not Readable(forbidden) or forbidden ~= false then return false end
    end
    return true
end

local function Shown(frame)
    if not Public(frame) or type(frame.IsShown) ~= "function" then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and Readable(shown) and shown == true
end

local function LinkID(link)
    if String(link) then return tonumber(link:match("item:(%d+)")) end
end

local function DataID(data, itemCallback)
    if not Readable(data) then return nil, true end
    if type(data) ~= "table" then return end
    local kind = data.type
    if not Readable(kind) then return nil, true end
    if not itemCallback and (not Enum or not Enum.TooltipDataType or kind ~= Enum.TooltipDataType.Item) then
        return nil, true
    end
    if ID(data.id) then return data.id, true end
    return LinkID(data.hyperlink), true
end

local function ItemID(tooltip, data)
    if not Readable(data) then return end
    if data ~= nil then return DataID(data, true) end
    local getter = tooltip.GetPrimaryTooltipData or tooltip.GetTooltipData
    if type(getter) == "function" then
        local ok, current = pcall(getter, tooltip)
        if not ok then return end
        local id, authoritative = DataID(current)
        if authoritative then return id end
    end
    -- Legacy GameTooltip setters expose the displayed link. Comparison
    -- tooltips instead use their own processor data above, never the source.
    if type(tooltip.GetItem) == "function" then
        local ok, _, link, id = pcall(tooltip.GetItem, tooltip)
        if ok then
            if ID(id) then return id end
            return LinkID(link)
        end
    end
end

local function Icon(id)
    local getter = C_Item and C_Item.GetItemIconByID or GetItemIcon
    if type(getter) == "function" then
        local ok, texture = pcall(getter, id)
        if ok and (ID(texture) or String(texture)) then return texture end
    end
    getter = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if type(getter) == "function" then
        local ok, _, _, _, _, texture = pcall(getter, id)
        if ok and (ID(texture) or String(texture)) then return texture end
    end
    if not requested[id] and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        requested[id] = true
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end

local function Rect(frame)
    if not Public(frame) or type(frame.GetRect) ~= "function" or type(frame.GetEffectiveScale) ~= "function" then return end
    local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
    local scaleOK, scale = pcall(frame.GetEffectiveScale, frame)
    if not ok or not scaleOK or not Number(left) or not Number(bottom)
        or not Number(width) or not Number(height) or not Number(scale)
        or width <= 0 or height <= 0 or scale <= 0 then return end
    return {left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale}, scale
end

local function Overlap(a, b)
    return a[1] < b[3] and a[3] > b[1] and a[2] < b[4] and a[4] > b[2]
end

local function Arrange()
    if arranging then return end
    arranging = true
    local screen = Rect(UIParent)
    local obstacles, placed = {}, {}
    for tooltip in pairs(records) do
        if Shown(tooltip) then
            local rect = Rect(tooltip)
            if rect then obstacles[#obstacles + 1] = rect end
            -- Blizzard puts "Currently Equipped" above comparison tooltips.
            local header = tooltip.CompareHeader
            if Shown(header) then
                rect = Rect(header)
                if rect then obstacles[#obstacles + 1] = rect end
            end
        end
    end
    for tooltip, record in pairs(records) do
        if Public(tooltip) and record.frame then
            record.frame:Hide()
            if ZP.db and ZP.db.itemTooltipIcons and record.texture and Shown(tooltip) and screen then
                local rect, scale = Rect(tooltip)
                if rect then
                    local l, b, r, t = rect[1], rect[2], rect[3], rect[4]
                    local size, gap = 32 * scale, 4 * scale
                    -- Above the right edge keeps icons clear of adjacent
                    -- comparison text. Other positions handle screen edges.
                    local candidates = {
                        {"BOTTOMRIGHT", "TOPRIGHT", 0, 4, {r - size, t + gap, r, t + gap + size}},
                        {"BOTTOMRIGHT", "TOPRIGHT", 0, 26, {r - size, t + 26 * scale, r, t + 26 * scale + size}},
                        {"TOPRIGHT", "TOPLEFT", -4, 0, {l - gap - size, t - size, l - gap, t}},
                        {"TOPLEFT", "TOPRIGHT", 4, 0, {r + gap, t - size, r + gap + size, t}},
                        {"TOPRIGHT", "BOTTOMRIGHT", 0, -4, {r - size, b - gap - size, r, b - gap}},
                    }
                    for _, candidate in ipairs(candidates) do
                        local box = candidate[5]
                        local free = box[1] >= screen[1] and box[2] >= screen[2]
                            and box[3] <= screen[3] and box[4] <= screen[4]
                        if free then
                            for _, other in ipairs(obstacles) do if Overlap(box, other) then free = false; break end end
                            for _, other in ipairs(placed) do if Overlap(box, other) then free = false; break end end
                        end
                        if free then
                            record.frame:ClearAllPoints()
                            record.frame:SetPoint(candidate[1], tooltip, candidate[2], candidate[3], candidate[4])
                            record.frame:Show()
                            placed[#placed + 1] = box
                            break
                        end
                    end
                end
            end
        end
    end
    arranging = false
end

local HookTooltip
local function Update(tooltip, data)
    if not Public(tooltip) then return end
    HookTooltip(tooltip)
    local record = records[tooltip]
    if not record then return end
    record.id, record.texture = nil, nil
    if ZP.db and ZP.db.itemTooltipIcons then
        local id = ItemID(tooltip, data)
        if ID(id) then
            record.id, record.texture = id, Icon(id)
            if record.texture then
                if not record.frame then
                    local frame = CreateFrame("Frame", nil, tooltip)
                    frame:SetSize(32, 32)
                    frame:EnableMouse(false)
                    local border = frame:CreateTexture(nil, "BACKGROUND")
                    border:SetAllPoints()
                    border:SetColorTexture(0.05, 0.05, 0.05, 1)
                    local texture = frame:CreateTexture(nil, "ARTWORK")
                    texture:SetPoint("TOPLEFT", 1, -1)
                    texture:SetPoint("BOTTOMRIGHT", -1, 1)
                    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    record.frame, record.icon = frame, texture
                end
                record.icon:SetTexture(record.texture)
            end
        end
    end
    Arrange()
end

HookTooltip = function(tooltip)
    if not Public(tooltip) or records[tooltip] or type(tooltip.HookScript) ~= "function" then return end
    local record = {}
    records[tooltip] = record
    local function Clear()
        record.id, record.texture = nil, nil
        if Public(tooltip) and record.frame then record.frame:Hide() end
        Arrange()
    end
    pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", Clear)
    pcall(tooltip.HookScript, tooltip, "OnHide", Clear)
    pcall(tooltip.HookScript, tooltip, "OnShow", function(self) Update(self) end)
    pcall(tooltip.HookScript, tooltip, "OnSizeChanged", Arrange)
    -- Older tooltip templates lack processor callbacks. Invalid item getters
    -- are harmless here: Update clears the old icon before querying the item.
    pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self) Update(self) end)
    if type(hooksecurefunc) == "function" then
        for _, method in ipairs({"SetHyperlink", "SetItemByID", "SetBagItem", "SetInventoryItem", "SetLootItem",
            "SetLootRollItem", "SetMerchantItem", "SetBuybackItem", "SetTradePlayerItem", "SetTradeTargetItem",
            "SetAuctionItem", "SetAuctionSellItem", "SetCompareItem"}) do
            if type(tooltip[method]) == "function" then
                pcall(hooksecurefunc, tooltip, method, function(self) Update(self) end)
            end
        end
        if type(tooltip.SetPoint) == "function" then pcall(hooksecurefunc, tooltip, "SetPoint", Arrange) end
    end
end

function ZP:RefreshItemTooltipIcons()
    for _, name in ipairs(names) do HookTooltip(_G[name]) end
    for tooltip, record in pairs(records) do
        if Public(tooltip) then
            if Shown(tooltip) then Update(tooltip)
            else
                record.id, record.texture = nil, nil
                if record.frame then record.frame:Hide() end
            end
        end
    end
    Arrange()
end

function ZP:InitializeItemTooltipIcons()
    if initialized then return end
    initialized = true
    for _, name in ipairs(names) do HookTooltip(_G[name]) end
    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item ~= nil then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip, data) Update(tooltip, data) end)
    end
    local events = CreateFrame("Frame")
    for _, event in ipairs({"ADDON_LOADED", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, id)
        if event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
            if not ID(id) then return end
            for tooltip, record in pairs(records) do
                if record.id == id and Shown(tooltip) then Update(tooltip) end
            end
        else ZP:RefreshItemTooltipIcons() end
    end)
    self:RefreshItemTooltipIcons()
end
