local _, ZP = ...
local L = ZP.L
local controls = {}
local window

local function Label(parent, text, x, y, width, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function Checkbox(parent, key, text, x, y, width, dependency)
    local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(28, 28)
    button.key = key
    button.dependency = dependency
    button.label = Label(parent, text, x + 32, y - 6, width, "GameFontHighlight")
    button:SetScript("OnClick", function(self)
        ZP:SetOption(self.key, self:GetChecked())
    end)
    controls[#controls + 1] = button
    return button
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
end

local function BuildOptions()
    window = CreateFrame("Frame", "ZwykPlusOptions", UIParent, "BackdropTemplate")
    window:SetSize(560, 722)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    window:SetBackdropColor(0.06, 0.06, 0.06, 0.98)
    window:SetBackdropBorderColor(0.75, 0.58, 0.25, 1)
    window:Hide()
    UISpecialFrames[#UISpecialFrames + 1] = "ZwykPlusOptions"

    Label(window, "|cffffcc66ZwykPlus|r", 24, -20, 440, "GameFontNormalLarge")
    Label(window, L.subtitle, 24, -48, 500)
    local closeIcon = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeIcon:SetPoint("TOPRIGHT", -6, -6)
    closeIcon:SetScript("OnClick", function() window:Hide() end)

    Checkbox(window, "hideErrors", L.errors, 22, -77, 470)
    Label(window, L.errorsHelp, 54, -108, 476)

    Checkbox(window, "maxZoom", L.camera, 22, -141, 470)
    Label(window, L.cameraHelp, 54, -173, 476)
    Checkbox(window, "zoomOnLogin", L.zoom, 49, -199, 440, "maxZoom")

    Checkbox(window, "autoTracking", L.tracking, 22, -245, 470)
    Label(window, L.trackingHelp, 54, -277, 476)
    Checkbox(window, "minerals", L.minerals, 49, -300, 135, "autoTracking")
    Checkbox(window, "herbs", L.herbs, 225, -300, 130, "autoTracking")
    Checkbox(window, "fish", L.fish, 393, -300, 125, "autoTracking")
    Label(window, L.trackingNote, 54, -335, 476)
    Checkbox(window, "auraSource", L.auraSource, 22, -373, 470)
    Label(window, L.auraSourceHelp, 54, -405, 476)
    Checkbox(window, "auraSourceTarget", L.auraSourceTarget, 49, -436, 440, "auraSource")
    Label(window, L.auraSourceTargetHelp, 81, -467, 449)
    Checkbox(window, "chatItemIcons", L.chatItemIcons, 22, -503, 470)
    Checkbox(window, "chatClassIcons", L.chatClassIcons, 22, -539, 470)
    Checkbox(window, "chatRaceIcons", L.chatRaceIcons, 22, -575, 470)
    Label(window, L.chatIconsHelp, 54, -612, 476)
    Label(window, L.saved, 24, -653, 510)

    local apply = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    apply:SetSize(230, 24)
    apply:SetPoint("BOTTOMLEFT", 24, 15)
    apply:SetText(L.apply)
    apply:SetScript("OnClick", function() ZP:ApplyAll() end)
    local close = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    close:SetSize(90, 24)
    close:SetPoint("BOTTOMRIGHT", -24, 15)
    close:SetText(L.close)
    close:SetScript("OnClick", function() window:Hide() end)
    window:SetScript("OnShow", function() ZP:RefreshOptions() end)
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
