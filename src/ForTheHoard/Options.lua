local _, Addon = ...
local Options = { controls = {}, tooltipHooks = {}, dropdownSettings = {} }
Addon.Options = Options

local bagChoices = { { 0, "Backpack" }, { 1, "Bag 1" }, { 2, "Bag 2" }, { 3, "Bag 3" },
    { 4, "Bag 4" }, { 5, "Reagent slot" }, { -1, "Keyring" } }

local function owned(key, create)
    local object = Options.controls[key]
    if not object then
        object = create()
        Options.controls[key] = object
    end
    return object
end

local function diagnostic(key, failure, message)
    local detail = Addon.IsPublic(failure) and type(failure) == "string"
        and failure:gsub("[\r\n]", " "):sub(1, 180) or "Diagnostic unavailable."
    Addon:ReportOnce(key, (message or "Settings could not finish opening; reopen them to retry. ") .. detail)
end

local function ensureScriptHook(control, event, state, key)
    if state.ready then return true end
    if state.uncertain then return false end
    local callback = Addon.IsPublic(control) and control and control.HookScript
    if not Addon.IsPublic(callback) or type(callback) ~= "function" then
        state.status = "missing"
        diagnostic(key, "The game's " .. event .. " handler is unavailable.", "Settings could not attach a handler; reopen to retry. ")
        return false
    end
    local ok, result = pcall(callback, control, event, state.callback)
    if ok and Addon.IsPublic(result) and result == true then
        state.ready, state.status = true, "ready"
        return true
    end
    if not ok then
        state.status = "throw"
        diagnostic(key, result, "Settings could not attach a handler; reopen to retry. ")
    elseif Addon.IsPublic(result) and result == false then
        state.status = "rejected"
        diagnostic(key, "The game's " .. event .. " handler was not accepted.", "Settings could not attach a handler; reopen to retry. ")
    else
        -- Registration may already have happened. Retain its callback and do
        -- not repeat an installation whose acceptance cannot be confirmed.
        state.uncertain, state.status = true, "uncertain"
        diagnostic(key, "The game's " .. event .. " handler could not be confirmed.", "Settings handler confirmation is unavailable; reload to retry. ")
    end
    return false
end

local function label(parent, text, x, y, font, key)
    local region = owned(key or "label:" .. text, function()
        return parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    end)
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    region:SetText(text)
    region:SetJustifyH("LEFT")
    return region
end

local function tooltip(control, title, text)
    local hooks = Options.tooltipHooks[control]
    if not hooks then hooks = {}; Options.tooltipHooks[control] = hooks end
    if not hooks.enter then
        local state = {}; hooks.enter = state
        state.callback = function(self)
            if not state.ready or not hooks.leave.ready or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(title)
            GameTooltip:AddLine(text, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end
    if not hooks.leave then
        local state = {}; hooks.leave = state
        state.callback = function() if state.ready and GameTooltip then GameTooltip:Hide() end end
    end
    ensureScriptHook(control, "OnEnter", hooks.enter, "options-tooltip-enter")
    ensureScriptHook(control, "OnLeave", hooks.leave, "options-tooltip-leave")
end

local function retryTooltips()
    for control, hooks in pairs(Options.tooltipHooks) do
        ensureScriptHook(control, "OnEnter", hooks.enter, "options-tooltip-enter")
        ensureScriptHook(control, "OnLeave", hooks.leave, "options-tooltip-leave")
    end
end

local function button(parent, text, width, x, y, callback)
    local control = owned("button:" .. text, function() return CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") end)
    control:SetSize(width, 24)
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    control:SetText(text)
    control:SetScript("OnClick", callback)
    return control
end

local function colorButtons(parent, choices, bank)
    local swatches, buttons = {}, {}
    for index, entry in ipairs(choices) do
        local position, text = entry[1], entry[2]
        local swatch = button(parent, text, 116, 0, 0, function() Options:ChooseColor(position, bank) end)
        local dot = owned("swatch:" .. text, function() return swatch:CreateTexture(nil, "OVERLAY") end)
        dot:SetSize(8, 8)
        dot:SetPoint("LEFT", 6, 0)
        swatches[position] = dot
        buttons[index] = swatch
        tooltip(swatch, text, bank
            and "Choose a color for this bank position. Its items keep this color across bank pages."
            or "Choose a color for this equipped position. Identical bags can use different colors.")
    end
    return swatches, buttons
end

local function dropdown(parent, title, y, choices, getter, setter)
    local titleRegion = label(parent, title, 0, y - 5)
    local control = owned("dropdown:" .. title, function() return CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate") end)
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", 205, y)
    control:SetWidth(225)
    control:SetDefaultText(title)
    local setting = Options.dropdownSettings[title]
    if not setting then
        setting = { control = control, getter = getter, value = getter() }
        Options.dropdownSettings[title] = setting
    end
    if not setting.menuReady then
        control:SetupMenu(function(_, rootDescription)
            for _, entry in ipairs(choices) do
                local value, text = entry[1], entry[2]
                rootDescription:CreateRadio(text, function() return getter() == value end,
                    function() setter(value) end)
            end
        end)
        setting.value, setting.menuReady = getter(), true
    end
    Options.dropdowns[#Options.dropdowns + 1] = setting
    return control, titleRegion
end

local function slider(parent, title, y, getter, setter, active)
    local titleRegion = label(parent, title, 0, y)
    local valueRegion = label(parent, "", 390, y, nil, "value:" .. title)
    local control = owned("slider:" .. title, function() return CreateFrame("Slider", nil, parent) end)
    control:SetOrientation("HORIZONTAL")
    control:SetSize(225, 16)
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", 205, y - 22)
    control:SetMinMaxValues(0, 100)
    control:SetValueStep(1)
    control:SetObeyStepOnDrag(true)
    control:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local track = owned("track:" .. title, function() return control:CreateTexture(nil, "BACKGROUND") end)
    track:SetColorTexture(0.35, 0.35, 0.35, 0.7)
    track:SetHeight(3)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    control:SetScript("OnValueChanged", function(_, value)
        if not Addon.IsFiniteNumber(value) then return end
        if not Options.syncing and not active() then return end
        local normalized = math.max(0, math.min(100, math.floor(value + 0.5)))
        valueRegion:SetText(normalized .. "%")
        if not Options.syncing then setter(normalized / 100) end
    end)
    return { control = control, value = valueRegion, title = titleRegion, getter = getter, active = active }
end

local function ownsPickerToken(picker, token)
    if not Addon.IsPublic(picker) or not picker then return false end
    local callback = picker.GetExtraInfo
    if not Addon.IsPublic(callback) or type(callback) ~= "function" then return false end
    local ok, info = pcall(callback, picker)
    return ok and Addon.IsPublic(info) and info == token
end

function Options:CloseOwnedPicker(restore)
    local session = self.colorSession
    local picker = ColorPickerFrame
    if not session then return end
    self.colorSession = nil
    if not ownsPickerToken(picker, session.token) then return end
    if restore then
        local color = session.color
        color[1], color[2], color[3] = unpack(session.original)
        Addon:RefreshAppearance()
    end
    picker:Hide()
end

function Options:ClosePalettePicker(bank)
    local session = self.colorSession
    if session and session.bank == bank then self:CloseOwnedPicker(false) end
end

function Options:ChooseColor(bag, bank)
    if not ColorPickerFrame and C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame")
    end
    local picker = ColorPickerFrame
    if not picker or type(picker.SetupColorPickerAndShow) ~= "function" then
        Addon:ReportOnce("color-picker", "The game's color picker is unavailable.")
        return
    end
    -- Never replace another addon's active color-picker session.
    if picker:IsShown() then
        Addon:Print("Close the open color picker before choosing a bag color.")
        return
    end
    local hook = self.pickerHook
    if not hook or hook.picker ~= picker then
        hook = { picker = picker }; self.pickerHook = hook
        hook.callback = function()
            if hook.ready and self.colorSession and ownsPickerToken(picker, self.colorSession.token) then
                self.colorSession = nil
            end
        end
    end
    self.pickerHooked = ensureScriptHook(picker, "OnHide", hook, "options-picker-hook")
    if not self.pickerHooked then self.colorSession = nil; return end
    local palette = bank and Addon.db.appearance.bankColors or Addon.db.appearance.colors
    local color = palette[bag]
    local session = { bank = bank and true or false, color = color,
        original = { color[1], color[2], color[3] }, token = {} }
    self.colorSession = session
    local function ownsSession()
        return self.colorSession == session and ownsPickerToken(picker, session.token)
    end
    picker:SetupColorPickerAndShow({
        r = color[1], g = color[2], b = color[3], hasOpacity = false, extraInfo = session.token,
        swatchFunc = function()
            if not ownsSession() then return end
            local r, g, b = picker:GetColorRGB()
            if not Addon.IsFiniteNumber(r) or not Addon.IsFiniteNumber(g) or not Addon.IsFiniteNumber(b) then return end
            if r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then return end
            color[1], color[2], color[3] = r, g, b
            Addon:RefreshAppearance()
        end,
        cancelFunc = function()
            if not ownsSession() then return end
            color[1], color[2], color[3] = unpack(session.original)
            self.colorSession = nil
            Addon:RefreshAppearance()
        end,
    })
end

function Options:Initialize()
    if self.categoryRegistered then return true end
    if not Settings or type(Settings.RegisterCanvasLayoutCategory) ~= "function"
        or type(Settings.RegisterAddOnCategory) ~= "function" then
        Addon:ReportOnce("settings", "The game's Settings panel is unavailable. Use /fth help for commands.")
        return false
    end
    local ok, failure = pcall(function()
        local panel = self.panel
        if not panel then panel = CreateFrame("Frame"); self.panel = panel end
        if not self.panelReady then
            panel:Hide()
            panel:SetScript("OnShow", function()
                self.syncing = true
                local shown, detail = pcall(function()
                    self:BuildControls()
                    self:Refresh()
                end)
                self.syncing = false
                if not shown then diagnostic("options-build", detail) end
            end)
            panel:SetScript("OnHide", function() self:CloseOwnedPicker(true) end)
            self.panelReady = true
        end
        if not self.categoryObject then self.categoryObject = Settings.RegisterCanvasLayoutCategory(panel, "For the Hoard") end
        Settings.RegisterAddOnCategory(self.categoryObject)
        self.categoryRegistered = true
    end)
    if not ok then diagnostic("options-register", failure) end
    return ok
end

function Options:BuildControls()
    if self.controlsBuilt then retryTooltips(); self:LayoutControls(); return end
    local panel = self.panel
    self.dropdowns = {}
    self.title = label(panel, "For the Hoard", 16, -16, "GameFontNormalLarge")
    local content = owned("content", function() return CreateFrame("Frame", nil, panel) end)
    self.content = content
    content:Hide()
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -48)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
    if not self.bodySizeChanged then
        self.bodySizeChanged = function()
            if self.controlsBuilt then self:LayoutControls() end
        end
    end
    if not self.bodySizeHooked then
        content:SetScript("OnSizeChanged", self.bodySizeChanged)
        self.bodySizeHooked = true
    end

    self.mode, self.modeTitle = dropdown(content, "Bag and bank appearance", 0,
        { { "off", "Off" }, { "tint", "Background tint" }, { "outline", "Outline" } },
        function() return Addon.db.appearance.mode end,
        function(value) Addon.db.appearance.mode = value; Addon:RefreshAppearance() end)
    self.outline, self.outlineTitle = dropdown(content, "Outline shape", 0,
        { { "groups", "Bag cartouches" }, { "slots", "Individual slots" } },
        function() return Addon.db.appearance.outline end,
        function(value)
            if Addon.db.appearance.mode ~= "outline" then return end
            Addon.db.appearance.outline = value
            Addon:RefreshAppearance()
        end)
    self.tintSlider = slider(content, "Tint opacity", 0,
        function() return Addon.db.appearance.tintAlpha end,
        function(value) Addon.db.appearance.tintAlpha = value; Addon:RefreshAppearance() end,
        function() return Addon.db.appearance.mode == "tint" end)
    tooltip(self.tintSlider.control, "Tint opacity",
        "Controls item-slot background tint in Tint mode.")
    self.outlineSlider = slider(content, "Item outline opacity", 0,
        function() return Addon.db.appearance.outlineAlpha end,
        function(value) Addon.db.appearance.outlineAlpha = value; Addon:RefreshAppearance() end,
        function() return Addon.db.appearance.mode == "outline" end)
    tooltip(self.outlineSlider.control, "Item outline opacity",
        "Controls individual item-slot outlines and bag cartouches in Outline mode.")
    self.bagOutlineSlider = slider(content, "Bag button outline opacity", 0,
        function() return Addon.db.appearance.bagOutlineAlpha end,
        function(value) Addon.db.appearance.bagOutlineAlpha = value; Addon:RefreshAppearance() end,
        function() return Addon.db.appearance.mode == "tint" or Addon.db.appearance.mode == "outline" end)
    tooltip(self.bagOutlineSlider.control, "Bag button outline opacity",
        "Controls equipped bag-button borders, including personal-bank bag buttons, in Tint and Outline modes.")
    self.sliders = { self.tintSlider, self.outlineSlider, self.bagOutlineSlider }

    self.carryTitle = label(content, "Bag slot colors", 0, 0)
    self.swatches, self.swatchButtons = colorButtons(content, bagChoices, false)
    self.resetBagColors = button(content, "Reset bag colors", 116, 0, 0, function() Addon:ResetColors(false) end)
    tooltip(self.resetBagColors, "Reset bag colors", "Restore only carried-bag colors to their defaults.")
    self.bankTitle = label(content, "Bank slot colors", 0, 0)
    self.bankSwatches, self.bankSwatchButtons = colorButtons(content, Addon.bankColorChoices, true)
    self.resetBankColors = button(content, "Reset bank colors", 116, 0, 0, function() Addon:ResetColors(true) end)
    tooltip(self.resetBankColors, "Reset bank colors", "Restore only bank storage and bank-bag colors to their defaults.")

    self.movable = owned("movable", function() return CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate") end)
    self.movable.Text:SetText("Moveable windows")
    self.movable:SetScript("OnClick", function(control)
        Addon.db.movement.enabled = control:GetChecked() and true or false
        Addon.Movement:Refresh()
        self:Refresh()
    end)
    self.reset = button(content, "Reset bag and bank positions", 225, 0, 0, function() Addon.Movement:ResetPosition() end)

    self.controlsBuilt = true
    self:LayoutControls()
end

local function place(control, parent, x, y, width, height)
    control:ClearAllPoints()
    control:SetSize(width, height)
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

local function layout(self, width)
    local body = self.content
    local columnWidth = (width - 24) / 2
    local right = columnWidth + 24
    place(self.title, self.panel, 16, 16, width, 24)
    self.title:SetJustifyH("LEFT")
    self.title:SetJustifyV("TOP")
    local swatchWidth = (columnWidth - 8) / 2

    place(self.modeTitle, body, 0, 0, columnWidth, 18)
    place(self.mode, body, 0, 22, columnWidth, 26)
    place(self.outlineTitle, body, 0, 66, columnWidth, 18)
    place(self.outline, body, 0, 88, columnWidth, 26)
    for index, setting in ipairs(self.sliders) do
        local y = 124 + (index - 1) * 50
        place(setting.title, body, 0, y, columnWidth, 18)
        place(setting.control, body, 0, y + 22, columnWidth - 44, 16)
        place(setting.value, body, columnWidth - 36, y + 20, 36, 20)
        setting.value:SetJustifyH("RIGHT")
    end

    place(self.carryTitle, body, right, 0, columnWidth, 18)
    place(self.bankTitle, body, right, 155, columnWidth, 18)
    for index, control in ipairs(self.swatchButtons) do
        place(control, body, right + ((index - 1) % 2) * (swatchWidth + 8),
            25 + math.floor((index - 1) / 2) * 28, swatchWidth, 24)
    end
    place(self.resetBagColors, body, right + swatchWidth + 8,
        25 + math.floor((#self.swatchButtons - 1) / 2) * 28, swatchWidth, 24)
    for index, control in ipairs(self.bankSwatchButtons) do
        place(control, body, right + ((index - 1) % 2) * (swatchWidth + 8),
            180 + math.floor((index - 1) / 2) * 28, swatchWidth, 24)
    end
    place(self.resetBankColors, body, right + swatchWidth + 8,
        180 + math.floor((#self.bankSwatchButtons - 1) / 2) * 28, swatchWidth, 24)

    place(self.movable, body, 0, 280, 24, 24)
    place(self.movable.Text, body, 28, 282, columnWidth - 28, 20)
    self.movable.Text:SetJustifyH("LEFT")
    self.movable.Text:SetJustifyV("TOP")
    place(self.reset, body, 0, 314, math.min(225, columnWidth), 24)

end

function Options:LayoutControls()
    if not self.controlsBuilt or self.layingOut then return false end
    local body = self.content
    local width, height = body:GetWidth(), body:GetHeight()
    if not Addon.IsFiniteNumber(width) or not Addon.IsFiniteNumber(height) or width <= 0 or height <= 0 then
        self.layoutWidth, self.layoutHeight = nil, nil
        body:Hide()
        return false
    end
    if self.layoutWidth == width and self.layoutHeight == height then body:Show(); return true end
    self.layoutWidth, self.layoutHeight = nil, nil
    self.layingOut = true
    local ok, failure = pcall(layout, self, width)
    self.layingOut = false
    if ok then
        self.layoutWidth, self.layoutHeight = width, height
        body:Show()
    else
        body:Hide()
        diagnostic("options-layout", failure)
    end
    return ok
end

local function synchronize(self)
    local outlineEnabled = Addon.db.appearance.mode == "outline"
    if self.outlineEnabled ~= outlineEnabled then
        self.outline:SetEnabled(outlineEnabled)
        local alpha = outlineEnabled and 1 or 0.45
        self.outline:SetAlpha(alpha)
        self.outlineTitle:SetAlpha(alpha)
        self.outlineEnabled = outlineEnabled
    end
    for _, setting in ipairs(self.dropdowns) do
        local value = setting.getter()
        if setting.value ~= value then
            -- Menu structure is static. Re-evaluate its selection without rebuilding it.
            if type(setting.control.Update) == "function" then
                setting.control:Update()
            else
                setting.control:GenerateMenu()
            end
            setting.value = value
        end
    end
    for _, setting in ipairs(self.sliders) do
        local enabled = setting.active()
        if setting.enabled ~= enabled then
            setting.control:SetEnabled(enabled)
            local alpha = enabled and 1 or 0.45
            setting.control:SetAlpha(alpha)
            setting.title:SetAlpha(alpha)
            setting.value:SetAlpha(alpha)
            setting.enabled = enabled
        end
        local percentage = math.floor(setting.getter() * 100 + 0.5)
        setting.control:SetValue(percentage)
        setting.value:SetText(percentage .. "%")
    end
    for bag, swatch in pairs(self.swatches) do
        local color = Addon.db.appearance.colors[bag]
        swatch:SetColorTexture(color[1], color[2], color[3], 1)
    end
    for position, swatch in pairs(self.bankSwatches) do
        local color = Addon.db.appearance.bankColors[position]
        swatch:SetColorTexture(color[1], color[2], color[3], 1)
    end
    self.movable:SetChecked(Addon.db.movement.enabled)
end

function Options:Refresh()
    if not self.controlsBuilt or not self.panel:IsVisible() then return end
    self.syncing = true
    local ok, failure = pcall(synchronize, self)
    self.syncing = false
    if not ok then diagnostic("options-refresh", failure) end
end

function Options:Open()
    if not self:Initialize() then return end
    if self.categoryObject and Settings and type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(self.categoryObject:GetID())
    else
        Addon:Print("Settings are unavailable. /fth help lists the available commands.")
    end
end
