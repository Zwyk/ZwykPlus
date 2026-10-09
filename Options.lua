local _, ZP = ...
local L = ZP.L
local controls = {}
local window
local pages, tabs = {}, {}
local pageHeading
local reloadNote
local diagnosticsWindow, diagnosticsText, diagnosticsMeasure
local diagnosticsHeading, diagnosticsHelp, diagnosticsProvider, diagnosticsTitle
local portraitWindow
local buffReminderWindow
local debuffReminderWindow
local questTargetWindow, questMarkerSelector
local healerManaWindow
local healerManaChoices = {}
local settingSliders = {}
local glowSelectors = {}
local buffColorButton, buffColorSession
local pageOrder = {"interface", "automation", "auras", "frames", "casting", "travel", "chat"}
local pageNames = {
    interface = L.categoryInterface, automation = L.categoryAutomation,
    auras = L.categoryAuras, frames = L.categoryFrames,
    travel = L.categoryTravel, chat = L.categoryChat,
    casting = L.categoryCasting,
}

local function SettingEnabled(dependency)
    if dependency == "spellReminders" then return ZP.db.buffReminder or ZP.db.debuffReminder end
    return not dependency or ZP.db[dependency]
end

local function Label(parent, text, x, y, width, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function Checkbox(parent, key, text, x, y, width, dependency, help)
    local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(24, 24)
    button.key = key
    button.dependency = dependency
    button.label = Label(parent, text, x + 28, y - 5, width, "GameFontHighlight")
    button:SetScript("OnClick", function(self)
        ZP:SetOption(self.key, self:GetChecked())
    end)
    if help then
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, 1, 0.82, 0)
            GameTooltip:AddLine(help, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    controls[#controls + 1] = button
    return button
end

local function SettingSlider(parent, key, text, y, minimum, maximum, step, help, low, high, format, dependency)
    local slider = CreateFrame("Slider", "ZwykPlus" .. key, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 30, y)
    slider:SetSize(360, 17)
    slider.key, slider.step = key, step
    slider.format = format or (step < 1 and "%.1f%%" or "%d%%")
    slider.dependency = dependency
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    for _, suffix in ipairs({"Text", "Low", "High"}) do
        local label = slider[suffix] or _G["ZwykPlus" .. key .. suffix]
        if label then label:Hide() end
    end
    Label(parent, text, 30, y + 23, 292, "GameFontNormal")
    slider.valueLabel = Label(parent, "", 335, y + 23, 55, "GameFontHighlight")
    Label(parent, low, 30, y - 20, 170)
    local highLabel = Label(parent, high, 200, y - 20, 190)
    highLabel:SetJustifyH("RIGHT")
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / self.step + 0.5) * self.step
        self.valueLabel:SetText(string.format(self.format, value))
        if not self.refreshing then ZP:SetOption(self.key, value) end
    end)
    slider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 0.82, 0)
        GameTooltip:AddLine(help, 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    settingSliders[#settingSliders + 1] = slider
    return slider
end

local glowChoices = {"pixel", "button", "autocast", "proc"}
local function GlowSelector(parent, key, text, y)
    Label(parent, text, 30, y - 8, 178, "GameFontNormal")
    local selector = CreateFrame("Frame", "ZwykPlus" .. key, parent, "UIDropDownMenuTemplate")
    selector:SetPoint("TOPLEFT", 204, y)
    UIDropDownMenu_SetWidth(selector, 170)
    UIDropDownMenu_SetFrameStrata(selector, "TOOLTIP")
    selector.key = key
    UIDropDownMenu_Initialize(selector, function(_, level)
        local selected = ZP:GetBuffReminderAppearance(key == "buffReminderAfterGlow")
        for _, style in ipairs(glowChoices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = L["buffReminderGlow_" .. style], style
            info.checked = selected == style
            info.func = function() ZP:SetOption(key, style) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    glowSelectors[#glowSelectors + 1] = selector
    return selector
end

local function QuestMarkerText(icon)
    local name = _G["RAID_TARGET_" .. icon] or L["questTargetMarker_" .. icon]
    return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. icon .. ":16:16:0:0|t " .. name
end

function ZP:ShowQuestTargetOptions()
    if not self.db then self:InitializeDB() end
    if not questTargetWindow then
        local panel = CreateFrame("Frame", "ZwykPlusQuestTargetOptions", UIParent, "BackdropTemplate")
        panel:Hide()
        panel:SetSize(420, 380)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("FULLSCREEN_DIALOG")
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        panel:SetMovable(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
        panel:SetBackdropColor(0.045, 0.04, 0.025, 1)
        panel:SetBackdropBorderColor(0.75, 0.58, 0.25, 1)
        Label(panel, L.questTargetOptionsTitle, 24, -20, 340, "GameFontNormalLarge")
        Label(panel, L.questTargetOptionsHelp, 24, -50, 372)
        Checkbox(panel, "questTargetQuestie", L.questTargetQuestie, 24, -114, 340,
            "questObjectiveTarget", L.questTargetQuestieHelp)
        Checkbox(panel, "questTargetMarker", L.questTargetMarker, 24, -164, 340,
            "questObjectiveTarget", L.questTargetMarkerHelp)
        Label(panel, L.questTargetMarkerIcon, 30, -219, 162, "GameFontNormal")
        local selector = CreateFrame("Frame", "ZwykPlusquestTargetMarkerIcon", panel, "UIDropDownMenuTemplate")
        selector:SetPoint("TOPLEFT", 204, -208)
        UIDropDownMenu_SetWidth(selector, 145)
        UIDropDownMenu_SetFrameStrata(selector, "TOOLTIP")
        UIDropDownMenu_Initialize(selector, function(_, level)
            for icon = 1, 8 do
                local info = UIDropDownMenu_CreateInfo()
                info.text, info.value = QuestMarkerText(icon), icon
                info.checked = ZP.db.questTargetMarkerIcon == icon
                info.func = function() ZP:SetOption("questTargetMarkerIcon", icon) end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        questMarkerSelector = selector
        Label(panel, L.questTargetMarkerNote, 24, -264, 372)
        local closeIcon = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        closeIcon:SetPoint("TOPRIGHT", -6, -6)
        closeIcon:SetScript("OnClick", function() panel:Hide() end)
        local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        close:SetPoint("BOTTOMRIGHT", -24, 15)
        close:SetSize(90, 24)
        close:SetText(L.close)
        close:SetScript("OnClick", function() panel:Hide() end)
        panel:SetScript("OnShow", function() ZP:RefreshOptions() end)
        UISpecialFrames[#UISpecialFrames + 1] = "ZwykPlusQuestTargetOptions"
        questTargetWindow = panel
    end
    questTargetWindow:Show()
end

local function OwnsBuffColorPicker(session)
    return session.picker[session.callbackKey] == session.swatch and session.picker.cancelFunc == session.cancel
end

local function CloseBuffColorPicker(cancel)
    local session = buffColorSession
    if not session then return end
    local picker = session.picker
    local owned = OwnsBuffColorPicker(session)
    local shown = owned and picker.IsShown and picker:IsShown()
    if cancel and shown then session.cancel() end
    session.closed, buffColorSession = true, nil
    if shown then picker:Hide() end
end

function ZP:ShowBuffReminderColorPicker()
    CloseBuffColorPicker(true)
    local picker = ColorPickerFrame
    if not picker then
        local loadAddon = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
        if loadAddon then pcall(loadAddon, "Blizzard_ColorPickerFrame") end
        picker = ColorPickerFrame
    end
    if not picker or not picker.GetColorRGB or not (picker.SetupColorPickerAndShow or picker.SetColorRGB) then
        self:WarnOnce("buffColorPicker", L.buffReminderColorUnavailable)
        return
    end
    local _, r, g, b, opacity = self:GetBuffReminderAppearance(false)
    local session = {picker = picker, original = {r = r, g = g, b = b}, transparency = (1 - opacity) * 100,
        setup = true, callbackKey = picker.SetupColorPickerAndShow and "swatchFunc" or "func"}
    buffColorSession = session
    session.swatch = function()
        if session.closed or session.setup or buffColorSession ~= session or not OwnsBuffColorPicker(session) then return end
        local ok, red, green, blue = pcall(picker.GetColorRGB, picker)
        if ok then ZP:SetOption("buffReminderColor", {r = red, g = green, b = blue}) end
        if session.hasOpacity then
            local alphaOK, alpha = pcall(picker.GetColorAlpha, picker)
            if alphaOK and not (issecretvalue and issecretvalue(alpha))
                and (not canaccessvalue or canaccessvalue(alpha)) and type(alpha) == "number"
                and alpha == alpha and alpha ~= math.huge and alpha ~= -math.huge then
                ZP:SetOption("buffReminderGlowTransparency", (1 - alpha) * 100)
            end
        end
    end
    session.cancel = function()
        if session.closed or buffColorSession ~= session or not OwnsBuffColorPicker(session) then return end
        session.closed, buffColorSession = true, nil
        ZP:SetOption("buffReminderColor", session.original)
        ZP:SetOption("buffReminderGlowTransparency", session.transparency)
    end
    if picker.HookScript and not picker.zwykPlusBuffColorHook then
        picker.zwykPlusBuffColorHook = true
        picker:HookScript("OnHide", function()
            local active = buffColorSession
            if active and active.picker == picker and not active.setup and OwnsBuffColorPicker(active) then
                -- Classic hides the picker before invoking its Cancel callback.
                -- Leave that callback one frame to restore the original values.
                if C_Timer and C_Timer.After then C_Timer.After(0, function()
                    if buffColorSession == active and not active.setup and OwnsBuffColorPicker(active)
                        and not picker:IsShown() then active.closed, buffColorSession = true, nil end
                end) end
            end
        end)
    end
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetFrameLevel(math.max(picker:GetFrameLevel(), (buffReminderWindow and buffReminderWindow:GetFrameLevel() or 0) + 30))
    local ok
    if picker.SetupColorPickerAndShow then
        -- Forever's modern picker uses opacity directly: 1 is fully visible.
        session.hasOpacity = type(picker.GetColorAlpha) == "function"
        ok = pcall(picker.SetupColorPickerAndShow, picker, {r = r, g = g, b = b,
            hasOpacity = session.hasOpacity, opacity = opacity, swatchFunc = session.swatch,
            opacityFunc = session.hasOpacity and session.swatch or nil, cancelFunc = session.cancel})
    else
        picker:Hide()
        picker.func, picker.swatchFunc, picker.cancelFunc = session.swatch, session.swatch, session.cancel
        picker.hasOpacity, picker.opacityFunc = false, nil
        ok = pcall(picker.SetColorRGB, picker, r, g, b)
        if ok then ok = pcall(picker.Show, picker) end
    end
    session.setup = false
    if not ok then CloseBuffColorPicker(false); self:WarnOnce("buffColorPicker", L.buffReminderColorUnavailable) end
end

function ZP:ShowPortraitOptions()
    if not self.db then self:InitializeDB() end
    if not portraitWindow then
        local panel = CreateFrame("Frame", "ZwykPlusPortraitOptions", UIParent, "BackdropTemplate")
        panel:Hide()
        panel:SetSize(420, 360)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("FULLSCREEN_DIALOG")
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        panel:SetMovable(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
        panel:SetBackdropColor(0.045, 0.04, 0.025, 1)
        panel:SetBackdropBorderColor(0.75, 0.58, 0.25, 1)
        Label(panel, L.portraitOptionsTitle, 24, -20, 340, "GameFontNormalLarge")
        Label(panel, L.portraitOptionsHelp, 24, -50, 372)
        SettingSlider(panel, "portraitModelSize", L.portraitModelSize, -112, 50, 100, 0.5,
            L.portraitModelSizeHelp, "50%", "100%")
        SettingSlider(panel, "portraitBackgroundTransparency", L.portraitBackgroundTransparency, -192, 0, 100, 1,
            L.portraitBackgroundTransparencyHelp, L.portraitBackgroundOpaque, L.portraitBackgroundTransparent)
        Checkbox(panel, "portraitClassBackground", L.portraitClassBackground, 24, -252, 340, nil, L.portraitClassBackgroundHelp)
        Label(panel, L.portraitOptionsSaved, 24, -299, 265)
        local closeIcon = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        closeIcon:SetPoint("TOPRIGHT", -6, -6)
        closeIcon:SetScript("OnClick", function() panel:Hide() end)
        local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        close:SetPoint("BOTTOMRIGHT", -24, 15)
        close:SetSize(90, 24)
        close:SetText(L.close)
        close:SetScript("OnClick", function() panel:Hide() end)
        panel:SetScript("OnShow", function() ZP:RefreshOptions() end)
        UISpecialFrames[#UISpecialFrames + 1] = "ZwykPlusPortraitOptions"
        portraitWindow = panel
    end
    portraitWindow:Show()
end

function ZP:ShowBuffReminderOptions()
    if not self.db then self:InitializeDB() end
    if not buffReminderWindow then
        local panel = CreateFrame("Frame", "ZwykPlusBuffReminderOptions", UIParent, "BackdropTemplate")
        panel:Hide()
        panel:SetSize(460, 670)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("FULLSCREEN_DIALOG")
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        panel:SetMovable(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
        panel:SetBackdropColor(0.045, 0.04, 0.025, 1)
        panel:SetBackdropBorderColor(0.75, 0.58, 0.25, 1)
        Label(panel, L.buffReminderOptionsTitle, 24, -20, 380, "GameFontNormalLarge")
        Label(panel, L.buffReminderOptionsHelp, 24, -50, 412)
        SettingSlider(panel, "buffReminderPercent", L.buffReminderPercent, -124, 5, 100, 5,
            L.buffReminderPercentHelp, "5%", "100%", L.buffReminderPercentFormat, "buffReminder")
        GlowSelector(panel, "buffReminderBeforeGlow", L.buffReminderBeforeGlow, -168)
        SettingSlider(panel, "buffReminderAfterPercent", L.buffReminderAfterPercent, -240, 0, 100, 5,
            L.buffReminderAfterPercentHelp, "0%", "100%", L.buffReminderPercentFormat, "buffReminder")
        GlowSelector(panel, "buffReminderAfterGlow", L.buffReminderAfterGlow, -284)
        Label(panel, L.buffReminderColor, 30, -338, 260, "GameFontNormal")
        buffColorButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        buffColorButton:SetPoint("TOPLEFT", 310, -330)
        buffColorButton:SetSize(110, 24)
        buffColorButton:SetText(L.buffReminderChooseColor)
        buffColorButton.swatch = buffColorButton:CreateTexture(nil, "OVERLAY")
        buffColorButton.swatch:SetPoint("LEFT", 8, 0)
        buffColorButton.swatch:SetSize(12, 12)
        buffColorButton:SetScript("OnClick", function() ZP:ShowBuffReminderColorPicker() end)
        SettingSlider(panel, "buffReminderGlowTransparency", L.buffReminderGlowTransparency, -393, 0, 100, 1,
            L.buffReminderGlowTransparencyHelp, L.portraitBackgroundOpaque, L.portraitBackgroundTransparent,
            L.buffReminderPercentFormat, "spellReminders")
        Label(panel, L.buffReminderSupported, 24, -454, 412)
        Label(panel, L.buffReminderAfterLimit, 24, -526, 412)
        local closeIcon = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        closeIcon:SetPoint("TOPRIGHT", -6, -6)
        closeIcon:SetScript("OnClick", function() panel:Hide() end)
        local preview = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        preview:SetPoint("TOPLEFT", 24, -590)
        preview:SetSize(198, 24)
        preview:SetText(L.buffReminderPreviewBefore)
        preview:SetScript("OnClick", function() ZP:TestBuffReminder(false) end)
        preview:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.buffReminderPreview, 1, 0.82, 0)
            GameTooltip:AddLine(L.buffReminderPreviewHelp, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        preview:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local previewAfter = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        previewAfter:SetPoint("TOPLEFT", 238, -590)
        previewAfter:SetSize(198, 24)
        previewAfter:SetText(L.buffReminderPreviewAfter)
        previewAfter:SetScript("OnClick", function() ZP:TestBuffReminder(true) end)
        previewAfter:SetScript("OnEnter", preview:GetScript("OnEnter"))
        previewAfter:SetScript("OnLeave", preview:GetScript("OnLeave"))
        local diagnostics = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        diagnostics:SetPoint("BOTTOMLEFT", 24, 15)
        diagnostics:SetSize(125, 24)
        diagnostics:SetText(L.buffReminderDiagnostics)
        diagnostics:SetScript("OnClick", function() ZP:ShowBuffReminderDiagnostics() end)
        local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        close:SetPoint("BOTTOMRIGHT", -24, 15)
        close:SetSize(90, 24)
        close:SetText(L.close)
        close:SetScript("OnClick", function() panel:Hide() end)
        panel:SetScript("OnShow", function() ZP:RefreshOptions() end)
        panel:SetScript("OnHide", function() CloseBuffColorPicker(true) end)
        UISpecialFrames[#UISpecialFrames + 1] = "ZwykPlusBuffReminderOptions"
        buffReminderWindow = panel
    end
    buffReminderWindow:Show()
end

function ZP:ShowDebuffReminderOptions()
    if not self.db then self:InitializeDB() end
    if not debuffReminderWindow then
        local panel = CreateFrame("Frame", "ZwykPlusDebuffReminderOptions", UIParent, "BackdropTemplate")
        panel:Hide()
        panel:SetSize(460, 440)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("FULLSCREEN_DIALOG")
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        panel:SetMovable(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
        panel:SetBackdropColor(0.045, 0.04, 0.025, 1)
        panel:SetBackdropBorderColor(0.75, 0.58, 0.25, 1)
        Label(panel, L.debuffReminderOptionsTitle, 24, -20, 380, "GameFontNormalLarge")
        Label(panel, L.debuffReminderHelp, 24, -50, 412)
        SettingSlider(panel, "debuffReminderPercent", L.buffReminderPercent, -180, 5, 100, 5,
            L.debuffReminderPercentHelp, "5%", "100%", L.buffReminderPercentFormat, "debuffReminder")
        Label(panel, L.debuffReminderAppearanceHelp, 24, -238, 412)
        local appearance = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        appearance:SetPoint("TOPLEFT", 24, -287)
        appearance:SetSize(224, 24)
        appearance:SetText(L.debuffReminderAppearance)
        appearance:SetScript("OnClick", function()
            ZP:ShowBuffReminderOptions()
            buffReminderWindow:SetFrameLevel(panel:GetFrameLevel() + 10)
        end)
        Label(panel, L.debuffReminderLimit, 24, -327, 412)
        local diagnostics = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        diagnostics:SetPoint("BOTTOMLEFT", 24, 15)
        diagnostics:SetSize(170, 24)
        diagnostics:SetText(L.debuffReminderDiagnostics)
        diagnostics:SetScript("OnClick", function() ZP:ShowDebuffReminderDiagnostics() end)
        local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        close:SetPoint("BOTTOMRIGHT", -24, 15)
        close:SetSize(90, 24)
        close:SetText(L.close)
        close:SetScript("OnClick", function() panel:Hide() end)
        local closeIcon = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        closeIcon:SetPoint("TOPRIGHT", -6, -6)
        closeIcon:SetScript("OnClick", function() panel:Hide() end)
        panel:SetScript("OnShow", function() ZP:RefreshOptions() end)
        UISpecialFrames[#UISpecialFrames + 1] = "ZwykPlusDebuffReminderOptions"
        debuffReminderWindow = panel
    end
    debuffReminderWindow:Show()
end

function ZP:RefreshHealerManaMembers()
    if not healerManaWindow then return end
    local members = self:GetHealerManaMembers()
    local count = math.min(40, #members)
    healerManaWindow:SetSize(620, math.max(220, 160 + math.ceil(count / 2) * 22))
    healerManaWindow.empty:SetShown(count == 0)
    for index, button in ipairs(healerManaChoices) do
        local member = members[index]
        if member then
            button.guid = member.guid
            button:SetChecked(member.selected)
            button:SetEnabled(member.guid ~= nil)
            button.label:SetText(member.name)
            button.label:SetTextColor(member.r or 1, member.g or 1, member.b or 1)
            button:SetAlpha(member.guid and 1 or 0.45)
            button.label:SetAlpha(member.guid and 1 or 0.45)
            button:Show()
            button.label:Show()
        else
            button.guid = nil
            button:Hide()
            button.label:Hide()
        end
    end
end

function ZP:ShowHealerManaMembers()
    if not self.db then self:InitializeDB() end
    if not healerManaWindow then
        local panel = CreateFrame("Frame", "ZwykPlusHealerManaMembers", UIParent, "BackdropTemplate")
        panel:Hide()
        panel:SetSize(620, 220)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("FULLSCREEN_DIALOG")
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        panel:SetMovable(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
        panel:SetBackdropColor(0.045, 0.04, 0.025, 1)
        panel:SetBackdropBorderColor(0.75, 0.58, 0.25, 1)
        Label(panel, L.healerManaSelectTitle, 24, -20, 545, "GameFontNormalLarge")
        Label(panel, L.healerManaSelectHelp, 24, -50, 572)
        panel.empty = Label(panel, L.healerManaNoGroup, 24, -104, 572)
        for index = 1, 40 do
            local x, y = 24 + ((index - 1) % 2) * 286, -104 - math.floor((index - 1) / 2) * 22
            local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
            button:SetPoint("TOPLEFT", x, y)
            button:SetSize(20, 20)
            button.label = Label(panel, "", x + 26, y - 3, 250, "GameFontHighlightSmall")
            if button.label.SetWordWrap then button.label:SetWordWrap(false) end
            button:SetScript("OnClick", function(self)
                if self.guid then ZP:SetHealerManaMember(self.guid, self:GetChecked()) end
                ZP:RefreshHealerManaMembers()
            end)
            healerManaChoices[index] = button
        end
        local automatic = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        automatic:SetPoint("BOTTOMLEFT", 24, 15)
        automatic:SetSize(205, 24)
        automatic:SetText(L.healerManaAuto)
        automatic:SetScript("OnClick", function()
            ZP:ClearHealerManaMembers()
            ZP:RefreshHealerManaMembers()
        end)
        local closeIcon = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        closeIcon:SetPoint("TOPRIGHT", -6, -6)
        closeIcon:SetScript("OnClick", function() panel:Hide() end)
        local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        close:SetPoint("BOTTOMRIGHT", -24, 15)
        close:SetSize(90, 24)
        close:SetText(L.close)
        close:SetScript("OnClick", function() panel:Hide() end)
        panel:SetScript("OnShow", function() ZP:RefreshHealerManaMembers() end)
        UISpecialFrames[#UISpecialFrames + 1] = "ZwykPlusHealerManaMembers"
        healerManaWindow = panel
    end
    self:RefreshHealerManaMembers()
    healerManaWindow:Show()
end

local function SelectPage(key)
    if not pages[key] then key = "interface" end
    for pageKey, page in pairs(pages) do
        page:SetShown(pageKey == key)
        tabs[pageKey].highlight:SetShown(pageKey == key)
    end
    pageHeading:SetText(pageNames[key])
    ZP.db.optionsPage = key
end

local function BuildPages()
    for index, key in ipairs(pageOrder) do
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", 178, -85)
        page:SetSize(398, 230)
        pages[key] = page
        local tab = CreateFrame("Button", nil, window)
        tab.pageKey = key
        tab:SetPoint("TOPLEFT", 18, -85 - (index - 1) * 31)
        tab:SetSize(138, 27)
        tab.highlight = tab:CreateTexture(nil, "BACKGROUND")
        tab.highlight:SetAllPoints()
        tab.highlight:SetColorTexture(0.45, 0.37, 0.02, 0.6)
        Label(tab, pageNames[key], 9, -7, 122, "GameFontNormal")
        tab:SetScript("OnClick", function(self) SelectPage(self.pageKey) end)
        tabs[key] = tab
    end
    local page = pages.interface
    Label(page, L.messagesGroup, 0, 0, 370, "GameFontNormal")
    Checkbox(page, "hideErrors", L.compactErrors, 0, -23, 355, nil, L.errorsHelp)
    Label(page, L.cameraGroup, 0, -54, 370, "GameFontNormal")
    Checkbox(page, "maxZoom", L.compactCamera, 0, -77, 355, nil, L.cameraHelp)
    Checkbox(page, "zoomOnLogin", L.compactZoom, 23, -104, 332, "maxZoom", L.zoom)
    Label(page, L.itemsGroup, 0, -129, 370, "GameFontNormal")
    Checkbox(page, "itemBindingIcons", L.itemBindingIcons, 0, -152, 355, nil, L.itemBindingIconsHelp)
    Checkbox(page, "restedXP", L.restedXP, 0, -179, 355, nil, L.restedXPHelp)
    Checkbox(page, "xpStats", L.xpStats, 0, -206, 355, nil, L.xpStatsHelp)

    page = pages.automation
    Label(page, L.trackingGroup, 0, 0, 370, "GameFontNormal")
    Checkbox(page, "autoTracking", L.tracking, 0, -23, 355, nil, L.trackingHelp)
    Checkbox(page, "minerals", L.minerals, 23, -65, 157, "autoTracking", L.trackingHelp)
    Checkbox(page, "herbs", L.herbs, 209, -65, 157, "autoTracking", L.trackingHelp)
    Checkbox(page, "fish", L.fish, 23, -96, 330, "autoTracking", L.trackingHelp)
    Label(page, L.trackingNote, 23, -142, 369)
    Checkbox(page, "questObjectiveTarget", L.questObjectiveTarget, 0, -200, 240, nil, L.questObjectiveTargetHelp)
    local configureQuests = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    configureQuests:SetPoint("TOPLEFT", 279, -200)
    configureQuests:SetSize(114, 24)
    configureQuests:SetText(L.configure)
    configureQuests:SetScript("OnClick", function() ZP:ShowQuestTargetOptions() end)

    page = pages.auras
    Label(page, L.tooltipGroup, 0, 0, 370, "GameFontNormal")
    Checkbox(page, "auraSource", L.compactAuras, 0, -23, 355, nil, L.auraSourceHelp .. " " .. L.auraColorHelp)
    Checkbox(page, "spellTooltipMetrics", L.spellTooltipMetrics, 0, -54, 355, nil, L.spellTooltipMetricsHelp)
    Label(page, L.clickGroup, 0, -87, 370, "GameFontNormal")
    Checkbox(page, "auraSourceTarget", L.compactAuraClick, 0, -110, 355, "auraSource", L.auraSourceTargetHelp)
    Label(page, L.auraReminderGroup, 0, -148, 370, "GameFontNormal")
    Checkbox(page, "buffReminder", L.buffReminder, 0, -171, 240, nil, L.buffReminderHelp)
    local configureBuffs = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    configureBuffs:SetPoint("TOPLEFT", 279, -171)
    configureBuffs:SetSize(114, 24)
    configureBuffs:SetText(L.configure)
    configureBuffs:SetScript("OnClick", function() ZP:ShowBuffReminderOptions() end)
    Checkbox(page, "debuffReminder", L.debuffReminder, 0, -202, 240, nil, L.debuffReminderHelp)
    local configureDebuffs = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    configureDebuffs:SetPoint("TOPLEFT", 279, -202)
    configureDebuffs:SetSize(114, 24)
    configureDebuffs:SetText(L.configure)
    configureDebuffs:SetScript("OnClick", function() ZP:ShowDebuffReminderOptions() end)

    page = pages.frames
    Label(page, L.portraitsGroup, 0, 0, 370, "GameFontNormal")
    Checkbox(page, "portraits3D", L.portraits3D, 0, -23, 240, nil, L.portraits3DHelp)
    local configure = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    configure:SetPoint("TOPLEFT", 279, -23)
    configure:SetSize(114, 24)
    configure:SetText(L.configure)
    configure:SetScript("OnClick", function() ZP:ShowPortraitOptions() end)
    local debug = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    debug:SetPoint("TOPLEFT", 28, -54)
    debug:SetSize(205, 24)
    debug:SetText(L.portraitDiagnostics)
    debug:SetScript("OnClick", function() ZP:ShowPortraitDiagnostics() end)
    debug:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.portraitDiagnostics)
        GameTooltip:AddLine(L.portraitDiagnosticsHelp, 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    debug:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Label(page, L.namesGroup, 0, -103, 370, "GameFontNormal")
    Checkbox(page, "frameClassColors", L.frameClassColors, 0, -126, 355, nil, L.frameClassColorsHelp)
    Label(page, L.nameplatesGroup, 0, -153, 370, "GameFontNormal")
    Checkbox(page, "nameplateTargetEyes", L.nameplateTargetEyes, 0, -176, 355, nil, L.nameplateTargetEyesHelp)
    Checkbox(page, "healerMana", L.healerMana, 0, -206, 240, nil, L.healerManaHelp)
    local resetMana = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    resetMana:SetPoint("TOPLEFT", 279, -206)
    resetMana:SetSize(114, 24)
    resetMana:SetText(L.healerManaReset)
    resetMana:SetScript("OnClick", function() ZP:ResetHealerManaPosition() end)

    page = pages.casting
    Label(page, L.manaSparkGroup, 0, 0, 370, "GameFontNormal")
    Checkbox(page, "manaSpark", L.manaSpark, 0, -23, 355, nil, L.manaSparkHelp)
    Checkbox(page, "manaSparkRegenTicks", L.manaSparkRegenTicks, 23, -54, 332, "manaSpark", L.manaSparkRegenTicksHelp)
    Label(page, L.manaSparkNote, 28, -94, 365)
    Label(page, L.castTargetsGroup, 0, -158, 370, "GameFontNormal")
    Checkbox(page, "castTargetNames", L.castTargetNames, 0, -181, 355, nil, L.castTargetNamesHelp)

    page = pages.travel
    Label(page, L.flightTimerTitle, 0, 0, 370, "GameFontNormal")
    Checkbox(page, "flightTimer", L.flightTimerTitle, 0, -23, 355, nil, L.flightTimerHelp)
    Label(page, L.flightTimerWaypointHelp, 28, -61, 365)
    Label(page, L.flightTimerMoveHelp, 28, -128, 365)
    local previewFlight = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    previewFlight:SetPoint("TOPLEFT", 28, -187)
    previewFlight:SetSize(150, 24)
    previewFlight:SetText(L.flightTimerPreview)
    previewFlight:SetScript("OnClick", function() ZP:ShowFlightTimerPreview() end)
    local resetFlight = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    resetFlight:SetPoint("TOPLEFT", 188, -187)
    resetFlight:SetSize(150, 24)
    resetFlight:SetText(L.flightTimerReset)
    resetFlight:SetScript("OnClick", function() ZP:ResetFlightTimerPosition() end)

    page = pages.chat
    Label(page, L.chatGroup, 0, 0, 370, "GameFontNormal")
    Checkbox(page, "chatItemIcons", L.compactItems, 0, -23, 355, nil, L.chatItemIcons)
    Checkbox(page, "chatClassIcons", L.compactClasses, 0, -54, 355, nil, L.chatClassIcons)
    Checkbox(page, "chatRaceIcons", L.compactRaces, 0, -85, 355, nil, L.chatRaceIcons)
    Label(page, L.chatIconsHelp, 28, -132, 365)
end

function ZP:RefreshOptions()
    if not self.db then return end
    for _, button in ipairs(controls) do
        button:SetChecked(self.db[button.key])
        local enabled = SettingEnabled(button.dependency)
        button:SetEnabled(enabled)
        button:SetAlpha(enabled and 1 or 0.45)
        button.label:SetAlpha(enabled and 1 or 0.45)
    end
    for _, slider in ipairs(settingSliders) do
        slider.refreshing = true
        slider:SetValue(self.db[slider.key])
        slider.valueLabel:SetText(string.format(slider.format, self.db[slider.key]))
        local enabled = SettingEnabled(slider.dependency)
        slider:SetEnabled(enabled)
        slider:SetAlpha(enabled and 1 or 0.45)
        slider.valueLabel:SetAlpha(enabled and 1 or 0.45)
        slider.refreshing = false
    end
    for _, selector in ipairs(glowSelectors) do
        local style = self:GetBuffReminderAppearance(selector.key == "buffReminderAfterGlow")
        UIDropDownMenu_SetSelectedValue(selector, style)
        UIDropDownMenu_SetText(selector, L["buffReminderGlow_" .. style])
        if SettingEnabled("spellReminders") then UIDropDownMenu_EnableDropDown(selector)
        else UIDropDownMenu_DisableDropDown(selector) end
    end
    if questMarkerSelector then
        UIDropDownMenu_SetSelectedValue(questMarkerSelector, self.db.questTargetMarkerIcon)
        UIDropDownMenu_SetText(questMarkerSelector, QuestMarkerText(self.db.questTargetMarkerIcon))
        if self.db.questObjectiveTarget and self.db.questTargetMarker then UIDropDownMenu_EnableDropDown(questMarkerSelector)
        else UIDropDownMenu_DisableDropDown(questMarkerSelector) end
    end
    if buffColorButton then
        local _, r, g, b, opacity = self:GetBuffReminderAppearance(false)
        buffColorButton.swatch:SetColorTexture(r, g, b, opacity)
        buffColorButton:SetEnabled(SettingEnabled("spellReminders"))
        buffColorButton:SetAlpha(SettingEnabled("spellReminders") and 1 or 0.45)
    end
    if reloadNote then
        local combat = InCombatLockdown and InCombatLockdown()
        reloadNote:SetText(combat and L.reloadCombatNote or L.reloadRequired)
        reloadNote:SetShown(self:NeedsReload())
    end
end

local function BuildOptions()
    window = CreateFrame("Frame", "ZwykPlusOptions", UIParent, "BackdropTemplate")
    window:SetSize(600, 390)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    window:SetBackdropColor(0.045, 0.04, 0.025, 1)
    window:SetBackdropBorderColor(0.75, 0.58, 0.25, 1)
    window:Hide()
    UISpecialFrames[#UISpecialFrames + 1] = "ZwykPlusOptions"

    Label(window, "|cffffcc66ZwykPlus|r", 24, -20, 148, "GameFontNormalLarge")
    Label(window, ZP.version, 24, -46, 130)
    pageHeading = Label(window, "", 178, -20, 370, "GameFontNormalLarge")
    Label(window, L.subtitle, 178, -48, 390)
    local closeIcon = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeIcon:SetPoint("TOPRIGHT", -6, -6)
    closeIcon:SetScript("OnClick", function() window:Hide() end)

    BuildPages()
    SelectPage(ZP.db.optionsPage)
    Label(window, L.compactSaved, 24, -328, 550)

    local apply = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    apply:SetSize(205, 24)
    apply:SetPoint("BOTTOMLEFT", 24, 15)
    apply:SetText(L.apply)
    apply:SetScript("OnClick", function() ZP:ApplyFromOptions() end)
    reloadNote = Label(window, "", 238, -354, 240)
    reloadNote:SetTextColor(1, 0.65, 0.15)
    local close = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    close:SetSize(90, 24)
    close:SetPoint("BOTTOMRIGHT", -24, 15)
    close:SetText(L.close)
    close:SetScript("OnClick", function() window:Hide() end)
    window:SetScript("OnShow", function() ZP:RefreshOptions() end)
    window:RegisterEvent("PLAYER_REGEN_DISABLED")
    window:RegisterEvent("PLAYER_REGEN_ENABLED")
    window:SetScript("OnEvent", function() ZP:RefreshOptions() end)
end

local function RefreshPortraitReport()
    local lines = diagnosticsProvider and diagnosticsProvider() or {L.portraitReportMissing}
    table.insert(lines, 1, "ZwykPlus " .. ZP.version .. " - " .. (diagnosticsTitle or L.portraitDiagnostics))
    local text = table.concat(lines, "\n")
    diagnosticsMeasure:SetText(text)
    diagnosticsText:SetHeight(math.max(270, diagnosticsMeasure:GetStringHeight() + 24))
    diagnosticsText:SetText(text)
    diagnosticsText:HighlightText()
end

function ZP:ShowDiagnostics(title, help, provider, reportName)
    diagnosticsTitle, diagnosticsProvider = reportName or title, provider
    if not diagnosticsWindow then
        local report = CreateFrame("Frame", "ZwykPlusPortraitDiagnostics", UIParent, "BackdropTemplate")
        report:SetSize(620, 420)
        report:SetPoint("CENTER")
        report:SetFrameStrata("FULLSCREEN_DIALOG")
        report:SetClampedToScreen(true)
        report:EnableMouse(true)
        report:SetMovable(true)
        report:RegisterForDrag("LeftButton")
        report:SetScript("OnDragStart", report.StartMoving)
        report:SetScript("OnDragStop", report.StopMovingOrSizing)
        report:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
        report:SetBackdropColor(0.045, 0.04, 0.025, 1)
        diagnosticsHeading = Label(report, title, 24, -20, 545, "GameFontNormalLarge")
        diagnosticsHelp = Label(report, help, 24, -50, 565)
        local closeIcon = CreateFrame("Button", nil, report, "UIPanelCloseButton")
        closeIcon:SetPoint("TOPRIGHT", -6, -6)
        closeIcon:SetScript("OnClick", function() report:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, report, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 24, -95)
        scroll:SetSize(542, 270)
        diagnosticsText = CreateFrame("EditBox", nil, scroll)
        diagnosticsText:SetMultiLine(true)
        diagnosticsText:SetAutoFocus(false)
        diagnosticsText:SetFontObject(ChatFontNormal)
        diagnosticsText:SetWidth(542)
        diagnosticsMeasure = report:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
        diagnosticsMeasure:SetWidth(542)
        diagnosticsMeasure:Hide()
        diagnosticsText:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        diagnosticsText:SetScript("OnEscapePressed", function() report:Hide() end)
        scroll:SetScrollChild(diagnosticsText)
        local refresh = CreateFrame("Button", nil, report, "UIPanelButtonTemplate")
        refresh:SetPoint("BOTTOMLEFT", 24, 15)
        refresh:SetSize(150, 24)
        refresh:SetText(L.refresh)
        refresh:SetScript("OnClick", RefreshPortraitReport)
        local close = CreateFrame("Button", nil, report, "UIPanelButtonTemplate")
        close:SetPoint("BOTTOMRIGHT", -24, 15)
        close:SetSize(90, 24)
        close:SetText(L.close)
        close:SetScript("OnClick", function() report:Hide() end)
        UISpecialFrames[#UISpecialFrames + 1] = "ZwykPlusPortraitDiagnostics"
        diagnosticsWindow = report
    end
    diagnosticsHeading:SetText(title)
    diagnosticsHelp:SetText(help)
    local level = 1
    for _, panel in pairs({portraitWindow, buffReminderWindow, debuffReminderWindow, questTargetWindow, healerManaWindow}) do
        level = math.max(level, panel:GetFrameLevel() + 10)
    end
    diagnosticsWindow:SetFrameLevel(level)
    RefreshPortraitReport()
    diagnosticsWindow:Show()
    diagnosticsText:SetFocus()
    diagnosticsText:HighlightText()
end

function ZP:ShowPortraitDiagnostics()
    self:ShowDiagnostics(L.portraitReportTitle, L.portraitReportHelp, function()
        return self.GetPortraitDiagnostics and self:GetPortraitDiagnostics() or {L.portraitReportMissing}
    end, L.portraitDiagnostics)
end

function ZP:ToggleOptions()
    if not self.db then self:InitializeDB() end
    if not window then BuildOptions() end
    if window:IsShown() then window:Hide() else window:Show() end
end

function ZP:RegisterSettings()
    if self.settingsPanel then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    panel.name = "ZwykPlus"
    Label(panel, "ZwykPlus", 16, -16, 480, "GameFontNormalLarge")
    Label(panel, L.settingsHelp, 16, -50, 480, "GameFontHighlight")
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(180, 26)
    button:SetPoint("TOPLEFT", 16, -100)
    button:SetText(L.open)
    button:SetScript("OnClick", function() ZP:ToggleOptions() end)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "ZwykPlus")
    Settings.RegisterAddOnCategory(category)
    self.settingsPanel = panel
end
