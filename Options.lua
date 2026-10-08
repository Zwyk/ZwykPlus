local _, ZP = ...
local L = ZP.L
local controls = {}
local window
local pages, tabs = {}, {}
local pageHeading
local reloadNote
local diagnosticsWindow, diagnosticsText, diagnosticsMeasure
local portraitWindow
local buffReminderWindow
local healerManaWindow
local healerManaChoices = {}
local settingSliders = {}
local pageOrder = {"interface", "automation", "auras", "frames", "travel", "chat"}
local pageNames = {
    interface = L.categoryInterface, automation = L.categoryAutomation,
    auras = L.categoryAuras, frames = L.categoryFrames,
    travel = L.categoryTravel, chat = L.categoryChat,
}

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
        panel:SetSize(420, 460)
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
        Label(panel, L.buffReminderOptionsTitle, 24, -20, 340, "GameFontNormalLarge")
        Label(panel, L.buffReminderOptionsHelp, 24, -50, 372)
        SettingSlider(panel, "buffReminderPercent", L.buffReminderPercent, -132, 5, 100, 5,
            L.buffReminderPercentHelp, "5%", "100%", L.buffReminderPercentFormat, "buffReminder")
        SettingSlider(panel, "buffReminderAfterPercent", L.buffReminderAfterPercent, -212, 0, 100, 5,
            L.buffReminderAfterPercentHelp, "0%", "100%", L.buffReminderPercentFormat, "buffReminder")
        Label(panel, L.buffReminderSupported, 24, -264, 372)
        Label(panel, L.buffReminderAfterLimit, 24, -354, 372)
        local closeIcon = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        closeIcon:SetPoint("TOPRIGHT", -6, -6)
        closeIcon:SetScript("OnClick", function() panel:Hide() end)
        local preview = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        preview:SetPoint("BOTTOMLEFT", 24, 15)
        preview:SetSize(105, 24)
        preview:SetText(L.buffReminderPreview)
        preview:SetScript("OnClick", function() ZP:TestBuffReminder() end)
        preview:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.buffReminderPreview, 1, 0.82, 0)
            GameTooltip:AddLine(L.buffReminderPreviewHelp, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        preview:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local diagnostics = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        diagnostics:SetPoint("BOTTOMLEFT", 139, 15)
        diagnostics:SetSize(125, 24)
        diagnostics:SetText(L.buffReminderDiagnostics)
        diagnostics:SetScript("OnClick", function() ZP:ShowBuffReminderDiagnostics() end)
        local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        close:SetPoint("BOTTOMRIGHT", -24, 15)
        close:SetSize(90, 24)
        close:SetText(L.close)
        close:SetScript("OnClick", function() panel:Hide() end)
        panel:SetScript("OnShow", function() ZP:RefreshOptions() end)
        UISpecialFrames[#UISpecialFrames + 1] = "ZwykPlusBuffReminderOptions"
        buffReminderWindow = panel
    end
    buffReminderWindow:Show()
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
    Label(page, L.cameraGroup, 0, -80, 370, "GameFontNormal")
    Checkbox(page, "maxZoom", L.compactCamera, 0, -103, 355, nil, L.cameraHelp)
    Checkbox(page, "zoomOnLogin", L.compactZoom, 23, -133, 332, "maxZoom", L.zoom)
    Label(page, L.itemsGroup, 0, -183, 370, "GameFontNormal")
    Checkbox(page, "itemBindingIcons", L.itemBindingIcons, 0, -206, 355, nil, L.itemBindingIconsHelp)

    page = pages.automation
    Label(page, L.trackingGroup, 0, 0, 370, "GameFontNormal")
    Checkbox(page, "autoTracking", L.tracking, 0, -23, 355, nil, L.trackingHelp)
    Checkbox(page, "minerals", L.minerals, 23, -65, 157, "autoTracking", L.trackingHelp)
    Checkbox(page, "herbs", L.herbs, 209, -65, 157, "autoTracking", L.trackingHelp)
    Checkbox(page, "fish", L.fish, 23, -96, 330, "autoTracking", L.trackingHelp)
    Label(page, L.trackingNote, 23, -142, 369)
    Checkbox(page, "questObjectiveTarget", L.questObjectiveTarget, 0, -200, 355, nil, L.questObjectiveTargetHelp)

    page = pages.auras
    Label(page, L.tooltipGroup, 0, 0, 370, "GameFontNormal")
    Checkbox(page, "auraSource", L.compactAuras, 0, -23, 355, nil, L.auraSourceHelp)
    Label(page, L.auraColorHelp, 28, -56, 365)
    Label(page, L.clickGroup, 0, -82, 370, "GameFontNormal")
    Checkbox(page, "auraSourceTarget", L.compactAuraClick, 0, -105, 355, "auraSource", L.auraSourceTargetHelp)
    Label(page, L.auraClickNote, 28, -139, 365)
    Label(page, L.buffReminderGroup, 0, -179, 370, "GameFontNormal")
    Checkbox(page, "buffReminder", L.buffReminder, 0, -202, 240, nil, L.buffReminderHelp)
    local configureBuffs = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    configureBuffs:SetPoint("TOPLEFT", 279, -202)
    configureBuffs:SetSize(114, 24)
    configureBuffs:SetText(L.configure)
    configureBuffs:SetScript("OnClick", function() ZP:ShowBuffReminderOptions() end)

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
        local enabled = not button.dependency or self.db[button.dependency]
        button:SetEnabled(enabled)
        button:SetAlpha(enabled and 1 or 0.45)
        button.label:SetAlpha(enabled and 1 or 0.45)
    end
    for _, slider in ipairs(settingSliders) do
        slider.refreshing = true
        slider:SetValue(self.db[slider.key])
        slider.valueLabel:SetText(string.format(slider.format, self.db[slider.key]))
        local enabled = not slider.dependency or self.db[slider.dependency]
        slider:SetEnabled(enabled)
        slider:SetAlpha(enabled and 1 or 0.45)
        slider.valueLabel:SetAlpha(enabled and 1 or 0.45)
        slider.refreshing = false
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
    local lines = ZP.GetPortraitDiagnostics and ZP:GetPortraitDiagnostics() or {L.portraitReportMissing}
    table.insert(lines, 1, "ZwykPlus " .. ZP.version .. " - " .. L.portraitDiagnostics)
    local text = table.concat(lines, "\n")
    diagnosticsMeasure:SetText(text)
    diagnosticsText:SetHeight(math.max(270, diagnosticsMeasure:GetStringHeight() + 24))
    diagnosticsText:SetText(text)
    diagnosticsText:HighlightText()
end

function ZP:ShowPortraitDiagnostics()
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
        Label(report, L.portraitReportTitle, 24, -20, 545, "GameFontNormalLarge")
        Label(report, L.portraitReportHelp, 24, -50, 565)
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
    RefreshPortraitReport()
    diagnosticsWindow:Show()
    diagnosticsText:SetFocus()
    diagnosticsText:HighlightText()
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
