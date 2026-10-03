local _, ZP = ...
local overlay, owner, events, unavailable
local leaveHooks = setmetatable({}, {__mode = "k"})

local function Accessible(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function String(value)
    return Accessible(value) and type(value) == "string" and value ~= ""
end

local function OutOfCombat()
    return InCombatLockdown and not InCombatLockdown()
end

local function Enabled()
    return ZP.db and ZP.db.auraSource and ZP.db.auraSourceTarget
end

local function SourceForButton(button)
    if not Accessible(button) or not button then return end
    if button.IsForbidden and button:IsForbidden() then return end
    if not Accessible(button.isExample) or button.isExample then return end
    local kind = button.auraType
    if not String(kind) or (kind ~= "Buff" and kind ~= "Debuff" and kind ~= "DeadlyDebuff") then return end
    local info = button.buttonInfo
    if not Accessible(info) or type(info) ~= "table" then return end
    local unit = button.unit
    if not Accessible(unit) then return end
    if not String(unit) then unit = PlayerFrame and PlayerFrame.unit end
    local id = button.deadlyInstanceID
    if not Accessible(id) then return end
    if id == nil then id = info.auraInstanceID end
    if not Accessible(id) then return end
    local filter = kind == "Buff" and "HELPFUL" or "HARMFUL"
    local source = ZP:GetAuraSourceUnit(unit, id ~= nil and id or info.index, filter, id ~= nil)
    if not source or not UnitExists then return end
    local ok, exists = pcall(UnitExists, source)
    if ok and Accessible(exists) and exists then return source end
end

local function HideOverlay()
    owner = nil
    if overlay and OutOfCombat() then
        overlay:Hide()
        overlay:SetAttribute("type1", nil)
        overlay:SetAttribute("unit", nil)
    end
end

local function CreateOverlay()
    if overlay or unavailable or not OutOfCombat() or not RegisterStateDriver then return end
    local button = CreateFrame("Button", "ZwykPlusAuraTarget", UIParent,
        "SecureActionButtonTemplate,SecureHandlerStateTemplate")
    button:Hide()
    if not (button.SetPassThroughButtons and button.SetMouseMotionEnabled) then unavailable = true; return end
    button:SetFrameStrata("TOOLTIP")
    button:EnableMouse(true)
    -- Keep hover tooltips and right-click buff cancellation on Blizzard's original button.
    button:SetMouseMotionEnabled(false)
    button:SetPassThroughButtons("RightButton", "MiddleButton", "Button4", "Button5")
    button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    button:SetAttribute("_onstate-combat", [[
        if newstate == "1" then
            self:Hide()
            self:SetAttribute("type1", nil)
            self:SetAttribute("unit", nil)
        end
    ]])
    RegisterStateDriver(button, "combat", "[combat] 1; 0")
    -- Leave the template's secure OnClick intact. Addon code only supplies attributes.
    button:SetScript("PreClick", function(self)
        if not OutOfCombat() then return end
        local source = Enabled() and SourceForButton(owner)
        self:SetAttribute("unit", source or nil)
        self:SetAttribute("type1", source and "target" or nil)
    end)
    overlay = button
end

function ZP:RefreshAuraTarget()
    HideOverlay()
end

function ZP:PrepareAuraTarget(button)
    if not Enabled() or not OutOfCombat() then return end
    local source = SourceForButton(button)
    if not source then HideOverlay(); return end
    CreateOverlay()
    if not overlay then return end
    if not (button.GetLeft and button.GetBottom and button.GetWidth and button.GetHeight
        and button.GetEffectiveScale and button.HookScript) then HideOverlay(); return end
    local left, bottom = button:GetLeft(), button:GetBottom()
    local width, height = button:GetWidth(), button:GetHeight()
    local scale, rootScale = button:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local values = {left, bottom, width, height, scale, rootScale}
    for index = 1, 6 do
        local value = values[index]
        if not Accessible(value) or type(value) ~= "number" then HideOverlay(); return end
    end
    if not left or not bottom or not width or not height or not scale or not rootScale
        or width <= 0 or height <= 0 or scale <= 0 or rootScale <= 0 then HideOverlay(); return end
    local ratio = scale / rootScale
    -- Use numerical screen coordinates, not anchors to moving aura buttons.
    -- Secure dependents must not restrict Blizzard's combat aura layout.
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * ratio, bottom * ratio)
    overlay:SetSize(width * ratio, height * ratio)
    overlay:SetAttribute("unit", source)
    overlay:SetAttribute("type1", "target")
    owner = button
    if not leaveHooks[button] then
        button:HookScript("OnLeave", function(self)
            if owner == self then HideOverlay() end
        end)
        leaveHooks[button] = true
    end
    overlay:Show()
end

function ZP:InitializeAuraSourceTarget()
    if events then return end
    events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function()
        HideOverlay()
        if OutOfCombat() then CreateOverlay() end
    end)
    CreateOverlay()
end
