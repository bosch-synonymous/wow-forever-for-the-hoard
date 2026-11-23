SlashCmdList = {}
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local addon = {}
assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Core.lua"))("ForTheHoard", addon)
assert(addon:InitializeSavedState())
assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Options.lua"))("ForTheHoard", addon)
local refreshes = 0
addon.RefreshAppearance = function() refreshes = refreshes + 1 end

local picker = { hooks = {}, shown = false }
ColorPickerFrame = picker
function picker:HookScript(event, callback) self.hooks[event] = callback; return true end
function picker:IsShown() return self.shown end
function picker:GetExtraInfo() return self.info and self.info.extraInfo end
function picker:GetColorRGB() return self.r, self.g, self.b end
function picker:Hide()
    self.shown = false
    if self.hooks.OnHide then self.hooks.OnHide() end
end
function picker:SetupColorPickerAndShow(info)
    self.info = info
    self.r, self.g, self.b = info.r, info.g, info.b
    info.swatchFunc() -- Native setup can call the callback before showing.
    self.shown = true
end
function picker:Preview(r, g, b)
    self.r, self.g, self.b = r, g, b
    self.info.swatchFunc()
end
function picker:Cancel()
    self.info.cancelFunc()
    self:Hide()
end

local function colorEquals(bag, r, g, b)
    local c = addon.db.appearance.colors[bag]
    assert(c[1] == r and c[2] == g and c[3] == b, "unexpected color")
end

addon.Options:ChooseColor(1)
local stale = picker.info.swatchFunc
picker:Preview(0.1, 0.2, 0.3)
colorEquals(1, 0.1, 0.2, 0.3)
picker:Cancel()
colorEquals(1, 0.77, 0.57, 0.29)
assert(addon.Options.colorSession == nil)

addon.Options:ChooseColor(1)
picker:Preview(0.2, 0.3, 0.4)
picker:Hide() -- Accepted color persists.
colorEquals(1, 0.2, 0.3, 0.4)
addon.Options:ChooseColor(1)
picker:Preview(0.6, 0.7, 0.8)
picker:Cancel()
colorEquals(1, 0.2, 0.3, 0.4)
stale()
colorEquals(1, 0.2, 0.3, 0.4)

addon.Options:ChooseColor(2)
picker:Preview(0.3, 0.4, 0.5)
addon.Options:CloseOwnedPicker(true)
colorEquals(2, 0.61, 0.48, 0.70)
assert(not picker.shown)

addon.Options:ChooseColor(1)
local foreign = { extraInfo = {} }
picker.info = foreign -- Another owner has taken over the shared picker.
addon.Options:CloseOwnedPicker(true)
assert(picker.shown and picker.info == foreign, "must not hide a foreign picker")
assert(addon.Options.colorSession == nil)
addon.Options:ChooseColor(2)
assert(picker.info == foreign, "must not replace a visible foreign picker")

picker:Hide()
addon.Options:ChooseColor(1)
picker:Preview(math.huge, 0.5, 0.5)
colorEquals(1, 0.2, 0.3, 0.4)
picker:Cancel()
assert(refreshes > 0)

local bankOriginal = { unpack(addon.db.appearance.bankColors[1]) }
addon.Options:ChooseColor(1, true)
local staleBankPreview = picker.info.swatchFunc
picker:Preview(0.7, 0.6, 0.5)
assert(addon.db.appearance.bankColors[1][1] == 0.7)
colorEquals(1, 0.2, 0.3, 0.4)
picker:Cancel()
assert(addon.db.appearance.bankColors[1][1] == bankOriginal[1], "bank cancel restores its own palette")
addon.Options:ChooseColor(1, true)
picker:Preview(0.6, 0.5, 0.4)
picker:Hide()
addon.Options:ChooseColor(1, true)
picker:Preview(0.9, 0.8, 0.7)
addon.Options:CloseOwnedPicker(true)
assert(addon.db.appearance.bankColors[1][1] == 0.6, "panel dismissal restores the accepted bank color")
addon.Options:ChooseColor(1)
staleBankPreview()
assert(addon.db.appearance.bankColors[1][1] == 0.6, "stale bank picker cannot mutate another session")
picker:Cancel()
colorEquals(1, 0.2, 0.3, 0.4)

local received = false
addon.db.appearance.colors[1][4] = { future = "preserve without using" }
addon.Options.panel = { IsVisible = function() return true end }
addon.Options.controlsBuilt = true
addon.Options.dropdowns, addon.Options.sliders = {}, {}
addon.Options.outline = { SetEnabled = function() end, SetAlpha = function() end }
addon.Options.outlineTitle = { SetAlpha = function() end }
addon.Options.bankSwatches = {}
addon.Options.swatches = { [1] = { SetColorTexture = function(_, r, g, b, alpha, ...)
    assert(r == 0.2 and g == 0.3 and b == 0.4 and alpha == 1 and select("#", ...) == 0)
    received = true
end } }
addon.Options.movable = { SetChecked = function() end }
addon.Options:Refresh()
assert(received, "swatch should receive only validated RGB and explicit opacity")

-- Model only the frame lifecycle and documented menu selection contract.
-- These counters measure requested work, not native UI memory attribution.
local frames, menus, radios, selectionUpdates, writes = 0, 0, 0, 0, 0
local widgetCount, allWidgets = 0, {}
local methods = {}
local function widget(parent, kind, template)
    local result = setmetatable({ scripts = {}, shown = true, parent = parent,
        kind = kind, template = template, anchors = {} }, { __index = methods })
    widgetCount = widgetCount + 1
    allWidgets[#allWidgets + 1] = result
    return result
end
for _, method in ipairs({ "SetDefaultText",
    "SetOrientation", "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag", "SetThumbTexture",
    "SetJustifyH", "SetJustifyV", "SetChecked", "SetColorTexture" }) do
    methods[method] = function() writes = writes + 1 end
end
local fractions = { TOPLEFT = { 0, 0 }, TOPRIGHT = { 1, 0 }, BOTTOMLEFT = { 0, 1 }, BOTTOMRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, RIGHT = { 1, 0.5 }, TOP = { 0.5, 0 }, BOTTOM = { 0.5, 1 }, CENTER = { 0.5, 0.5 } }
function methods:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, self.parent, point end
    relative, relativePoint = relative or self.parent, relativePoint or point
    self.anchors[point] = { relative = relative, relativePoint = relativePoint, x = x or 0, y = y or 0 }
    writes = writes + 1
end
function methods:ClearAllPoints() self.anchors = {}; writes = writes + 1 end
function methods:SetSize(width, height) self.width, self.height = width, height; writes = writes + 1 end
function methods:SetWidth(width) self.width = width; writes = writes + 1 end
function methods:SetHeight(height) self.height = height; writes = writes + 1 end
function methods:SetScale() error("settings must not scale the native fonts or canvas") end
function methods:SetScrollChild() error("settings must fit without a scroll child") end
function methods:GetParent() return self.parent end
function methods:GetRect()
    local function axis(component, dimension)
        local firstFraction, firstTarget, secondFraction, secondTarget
        for point, anchor in pairs(self.anchors) do
            local relative = anchor.relative
            local left, top, width, height = 0, 0, 0, 0
            if relative then left, top, width, height = relative:GetRect() end
            local offset = component == 1 and anchor.x or -anchor.y
            local target = (component == 1 and left or top) + fractions[anchor.relativePoint][component]
                * (component == 1 and width or height) + offset
            local fraction = fractions[point][component]
            if firstFraction == nil then firstFraction, firstTarget = fraction, target
            elseif fraction ~= firstFraction then secondFraction, secondTarget = fraction, target; break end
        end
        local size = self[dimension]
        if secondFraction then size = (secondTarget - firstTarget) / (secondFraction - firstFraction) end
        size = size or 0
        return firstFraction and firstTarget - firstFraction * size or 0, size
    end
    local x, width = axis(1, "width")
    local y, height = axis(2, "height")
    return x, y, width, height
end
function methods:GetWidth() local _, _, width = self:GetRect(); return width end
function methods:GetHeight() local _, _, _, height = self:GetRect(); return height end
function methods:Fire(event, ...)
    if self.scripts[event] then return self.scripts[event](self, ...) end
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:SetEnabled(enabled) self.enabled = enabled; writes = writes + 1 end
function methods:SetAlpha(alpha) self.alpha = alpha; writes = writes + 1 end
function methods:SetText(text) self.text = text; writes = writes + 1 end
function methods:SetJustifyH(value) self.justifyH = value; writes = writes + 1 end
-- Independent, deliberately wide native-metric inputs. These are not font
-- raster measurements; they expose the old 96-unit label truncation contract.
local intrinsicWidths = { ["Tint opacity"] = 105, ["Item outline opacity"] = 156,
    ["Bag button outline opacity"] = 224, ["Moveable windows"] = 146 }
function methods:GetUnboundedStringWidth() return intrinsicWidths[self.text] or 0 end
function methods:HookScript(event, callback)
    self.hookCounts = self.hookCounts or {}
    self.hookCounts[event] = (self.hookCounts[event] or 0) + 1
    self.scripts[event] = callback
    return true
end
function methods:CreateFontString(_, _, font) local region = widget(self, "FontString"); region.font = font; return region end
function methods:CreateTexture() return widget(self, "Texture") end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and not self.parentHidden and (not self.parent or self.parent:IsVisible()) end
function methods:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetValue(value)
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:GenerateMenu()
    menus = menus + 1
    self.entries = {}
    local root = { CreateRadio = function(_, text, selected, action)
        radios = radios + 1
        self.entries[#self.entries + 1] = { text = text, selected = selected, action = action }
    end }
    self.generator(self, root)
    self:Update()
end
function methods:SetupMenu(generator) self.generator = generator; self:GenerateMenu() end
function methods:Update()
    selectionUpdates = selectionUpdates + 1
    self.selectedText = nil
    for _, entry in ipairs(self.entries) do
        if entry.selected() then self.selectedText = entry.text end
    end
end
CreateFrame = function(kind, _, parent, template)
    assert(kind ~= "ScrollFrame", "settings must not allocate a scroll frame")
    frames = frames + 1
    local frame = widget(parent, kind, template)
    frame.Text = widget(frame, "FontString")
    return frame
end
local registered
Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        registered = panel
        panel.width, panel.height = 665, 601 -- Native Settings canvas, not resized by the addon.
        return { GetID = function() return 123 end }
    end,
    RegisterAddOnCategory = function(category) assert(category:GetID() == 123) end,
    OpenToCategory = function(id) assert(id == 123); registered:Show() end,
}
-- A fresh module, with the previous picker test's saved settings preserved.
assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Options.lua"))("ForTheHoard", addon)
addon.RefreshAppearance = function() refreshes = refreshes + 1; addon.Options:Refresh() end
addon.ready = true
addon.Options:Initialize()
assert(frames == 1 and menus == 0 and radios == 0 and not registered:IsShown(),
    "login should register only a hidden settings canvas")
addon.Options:Refresh()
assert(frames == 1 and menus == 0, "hidden settings should allocate no controls or menus")
addon.Options:Open()
assert(addon.Options.controlsBuilt and frames > 1 and menus == 2 and radios == 5)
for position = 1, 9 do
    assert(addon.Options.bankSwatches[position], "all supported bank positions have color controls")
end
assert(addon.Options.mode.selectedText == "Outline")
local builtFrames, builtMenus, builtRadios, initialUpdates = frames, menus, radios, selectionUpdates
for _ = 1, 100 do addon.Options:Refresh() end
assert(menus == builtMenus and radios == builtRadios and selectionUpdates == initialUpdates,
    "unchanged refreshes should leave dropdown menus and selections alone")
addon.db.appearance.mode = "tint"
addon.Options:Refresh()
assert(addon.Options.mode.selectedText == "Background tint" and selectionUpdates == initialUpdates + 1)
assert(menus == builtMenus and radios == builtRadios, "selection updates must reuse menu descriptions")
addon.Options:ChooseColor(1)
for _ = 1, 100 do picker:Preview(0.3, 0.4, 0.5) end
assert(menus == builtMenus and selectionUpdates == initialUpdates + 1,
    "color previews must not rebuild or traverse dropdowns")
registered.parentHidden = true -- Closing Settings can hide an ancestor only.
local parentHiddenWrites = writes
addon.Options:Refresh()
assert(writes == parentHiddenWrites and registered:IsShown(),
    "an invisible category must defer updates even when its own shown flag remains true")
registered.parentHidden = nil
registered:Hide() -- Cancels our preview without rebuilding hidden controls.
local hiddenWrites = writes
addon.db.appearance.mode = "off"
addon.Options:Refresh()
assert(writes == hiddenWrites, "hidden settings should defer all widget updates")
addon.Options:Open()
assert(frames == builtFrames, "reopening settings should reuse controls")
-- Native dropdown child OnShow scripts regenerate their menus. This lifecycle
-- fixture counts only work requested by our code; it omits those child scripts.
assert(addon.Options.mode.selectedText == "Off", "show should catch up with hidden changes")

-- A native Settings registration can fail independently of canvas allocation.
-- Retry each incomplete stage without replacing the retained panel/category.
local originalCanvasRegistration = Settings.RegisterCanvasLayoutCategory
local originalAddOnRegistration = Settings.RegisterAddOnCategory
for _, stage in ipairs({ "canvas", "addon" }) do
    assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Options.lua"))("ForTheHoard", addon)
    local options, failing, canvasCalls, messages = addon.Options, true, 0, {}
    addon.reports = {}
    addon.Print = function(_, message) messages[#messages + 1] = message end
    Settings.RegisterCanvasLayoutCategory = function(...)
        canvasCalls = canvasCalls + 1
        if stage == "canvas" and failing then error("injected " .. stage .. " registration") end
        return originalCanvasRegistration(...)
    end
    Settings.RegisterAddOnCategory = function(...)
        if stage == "addon" and failing then error("injected " .. stage .. " registration") end
        return originalAddOnRegistration(...)
    end
    local count = frames
    assert(options:Initialize() == false)
    local panel, category = options.panel, options.categoryObject
    for _ = 1, 3 do assert(pcall(options.Open, options)) end
    assert(frames == count + 1 and options.panel == panel, "registration retry replaced its native canvas")
    assert(#messages == 1 and messages[1]:find("injected " .. stage .. " registration", 1, true),
        "registration failure lost its diagnostic or repeated chat output")
    failing = false
    options:Open()
    assert(options.controlsBuilt and options.panel == panel and panel:IsShown(), "Settings registration did not recover")
    if stage == "addon" then
        assert(canvasCalls == 1 and options.categoryObject == category, "addon registration retried an already registered canvas")
    end
    options.panel:Hide()
end
Settings.RegisterCanvasLayoutCategory = originalCanvasRegistration
Settings.RegisterAddOnCategory = originalAddOnRegistration

-- Partial control setup retains every created frame/region and completed hook.
-- Reopening must diagnose once, recover later, and use the original objects.
local originalCreate = CreateFrame
for _, stage in ipairs({ "create", "setter", "hook" }) do
    assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Options.lua"))("ForTheHoard", addon)
    local options, failing, messages = addon.Options, true, {}
    addon.reports = {}
    addon.Print = function(_, message) messages[#messages + 1] = message end
    options:Initialize()
    local panel = options.panel
    local tintBefore, outlineBefore, bagBefore = addon.db.appearance.tintAlpha,
        addon.db.appearance.outlineAlpha, addon.db.appearance.bagOutlineAlpha
    CreateFrame = function(kind, ...)
        if stage == "create" and kind == "DropdownButton" and failing then error("injected control " .. stage) end
        local result = originalCreate(kind, ...)
        if stage == "setter" and kind == "DropdownButton" then
            result.SetWidth = function(self, ...)
                if failing then error("injected control " .. stage) end
                return methods.SetWidth(self, ...)
            end
        elseif stage == "hook" and kind == "Button" then
            result.HookScript = function(self, event, callback)
                if event == "OnLeave" and failing then error("injected control " .. stage) end
                return methods.HookScript(self, event, callback)
            end
        elseif stage == "hook" and kind == "Slider" then
            result.SetMinMaxValues = function(self, ...)
                methods.SetMinMaxValues(self, ...)
                -- Retrying a native setter may invoke the retained callback.
                if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, 0) end
            end
        end
        return result
    end
    assert(pcall(options.Open, options), "control setup escaped native OnShow")
    assert((not not options.controlsBuilt) == (stage == "hook") and #messages == 1,
        "optional tooltip failure must not block the settings controls")
    local retainedContent, count, regions = options.content, frames, widgetCount
    for _ = 1, 3 do panel:Hide(); assert(pcall(options.Open, options)) end
    assert(frames == count and widgetCount == regions, "failed control retry allocated another partial tree")
    assert(addon.db.appearance.tintAlpha == tintBefore and addon.db.appearance.outlineAlpha == outlineBefore
        and addon.db.appearance.bagOutlineAlpha == bagBefore,
        "retrying control initialization wrote a preference through an existing callback")
    assert(#messages == 1 and messages[1]:find("injected control " .. stage, 1, true), "control retry lost or repeated its diagnostic")
    failing = false
    panel:Hide(); options:Open()
    assert(options.controlsBuilt and options.content == retainedContent and panel == options.panel,
        "control recovery did not reuse retained resources")
    local completeFrames, completeRegions, completeMenus = frames, widgetCount, menus
    for _ = 1, 3 do panel:Hide(); options:Open() end
    assert(frames == completeFrames and widgetCount == completeRegions and menus == completeMenus,
        "recovered Settings repeated setup allocations or menus")
    for _, control in ipairs(allWidgets) do
        for _, hooks in pairs(control.hookCounts or {}) do assert(hooks == 1, "partial setup duplicated a native tooltip hook") end
    end
    assert(options.tintSlider.value ~= options.outlineSlider.value and options.bagOutlineSlider.value ~= options.outlineSlider.value
        and options.bagOutlineSlider.value ~= options.tintSlider.value, "slider labels were shared during partial reuse")
    panel:Hide()
    CreateFrame = originalCreate
end

-- A native refresh setter failure cannot leave initialization suppression on,
-- which would silently discard later user changes to a slider.
do
    local options, messages = addon.Options, {}
    addon.reports = {}
    addon.Print = function(_, message) messages[#messages + 1] = message end
    options:Open()
    local swatch = options.swatches[1]
    swatch.SetColorTexture = function() error("injected refresh setter") end
    for _ = 1, 3 do assert(pcall(options.Refresh, options)) end
    assert(options.syncing == false and #messages == 1 and messages[1]:find("injected refresh setter", 1, true))
    swatch.SetColorTexture = nil
    addon.db.appearance.mode = "tint"
    options:Refresh()
    options.tintSlider.control:SetValue(42)
    assert(addon.db.appearance.tintAlpha == 0.42 and options.syncing == false, "refresh failure disabled later user edits")
end

-- A failed picker lifecycle hook must be retried. Otherwise accepting a later
-- preview leaves a stale session that panel dismissal can incorrectly cancel.
do
    assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Options.lua"))("ForTheHoard", addon)
    local options, messages, failing = addon.Options, {}, true
    addon.reports = {}
    addon.Print = function(_, message) messages[#messages + 1] = message end
    options:Initialize(); options:Open()
    local originalHook, attempts = picker.HookScript, 0
    picker.HookScript = function(self, event, callback)
        attempts = attempts + 1
        if failing then error("injected picker visibility hook") end
        return originalHook(self, event, callback)
    end
    assert(pcall(options.ChooseColor, options, 1))
    assert(not picker:IsShown() and options.colorSession == nil and #messages == 1,
        "failed picker hook escaped or kept a partial session")
    failing = false
    options:ChooseColor(1)
    assert(picker:IsShown() and attempts == 2, "picker visibility hook did not retry")
    picker:Preview(0.11, 0.22, 0.33)
    picker:Hide()
    assert(options.colorSession == nil, "accepted picker retained its preview session")
    options.panel:Hide()
    colorEquals(1, 0.11, 0.22, 0.33)
    picker.HookScript = originalHook
end

-- Outline shape and the independent opacity values follow their active modes.
-- Native menu callbacks can outlive an enabled state, so exercise those too.
do
    local options = addon.Options
    options:Open()
    local appearance = addon.db.appearance
    local count, regions, roots, choices = frames, widgetCount, menus, radios
    local shapeChoices = {}
    for _, entry in ipairs(options.outline.entries) do shapeChoices[entry.text] = entry.action end
    local chooseGroups, chooseSlots = shapeChoices["Bag cartouches"], shapeChoices["Individual slots"]
    assert(type(chooseGroups) == "function" and type(chooseSlots) == "function")
    appearance.mode, appearance.outline = "tint", "groups"
    options:Refresh()
    assert(options.outline.enabled == false and options.outline.alpha == 0.45 and options.outlineTitle.alpha == 0.45,
        "Tint mode did not disable and dim the shape dropdown and label")
    local calls = refreshes
    chooseSlots()
    assert(appearance.outline == "groups" and options.outline.selectedText == "Bag cartouches" and refreshes == calls,
        "an inactive shape callback changed the stored choice or requested an appearance refresh")
    appearance.mode = "outline"
    options:Refresh()
    assert(options.outline.enabled == true and options.outline.alpha == 1 and options.outlineTitle.alpha == 1
        and options.outline.selectedText == "Bag cartouches", "Outline mode failed to restore the remembered shape control")
    chooseSlots()
    assert(appearance.outline == "slots" and options.outline.selectedText == "Individual slots" and refreshes == calls + 1,
        "an active shape choice failed to update appearance through the native menu callback")
    appearance.mode = "tint" -- Native enabled state is still from Outline.
    chooseGroups()
    assert(appearance.outline == "slots" and refreshes == calls + 1,
        "a stale enabled shape callback ignored the live Tint mode")
    appearance.tintAlpha, appearance.outlineAlpha, appearance.bagOutlineAlpha = 0.75, 0.50, 0.60
    appearance.mode = "outline"
    options:Refresh()
    local tint, outline, bag = options.tintSlider, options.outlineSlider, options.bagOutlineSlider
    assert(tint.control.enabled == false and outline.control.enabled == true and bag.control.enabled == true,
        "Outline mode did not disable only Tint opacity")
    assert(tint.control.alpha == 0.45 and tint.title.alpha == 0.45 and tint.value.alpha == 0.45,
        "inactive Tint opacity did not dim its slider, label and percentage")
    assert(outline.control.alpha == 1 and outline.title.alpha == 1 and outline.value.alpha == 1)
    assert(tint.value.text == "75%" and outline.value.text == "50%" and bag.value.text == "60%",
        "mode change lost independent remembered opacity displays")
    calls = refreshes
    tint.control:SetValue(91)
    assert(appearance.tintAlpha == 0.75 and tint.value.text == "75%" and refreshes == calls,
        "disabled Tint callback changed a preference or its displayed value")
    -- A callback already queued before the mode changed must consult the live
    -- mode, even before Refresh has disabled its native control.
    appearance.mode = "off"
    chooseGroups()
    outline.control:SetValue(92)
    bag.control:SetValue(92)
    assert(appearance.outline == "slots" and appearance.outlineAlpha == 0.50
        and appearance.bagOutlineAlpha == 0.60 and refreshes == calls,
        "stale enabled callback ignored the current Off mode")
    options:Refresh()
    assert(options.outline.enabled == false and options.outline.alpha == 0.45 and options.outlineTitle.alpha == 0.45,
        "Off mode did not disable and dim the remembered shape")
    chooseGroups()
    assert(appearance.outline == "slots" and refreshes == calls, "disabled Off-mode shape callback changed appearance")
    assert(tint.control.enabled == false and outline.control.enabled == false and bag.control.enabled == false)
    assert(outline.control.alpha == 0.45 and outline.title.alpha == 0.45 and outline.value.alpha == 0.45)
    appearance.mode = "tint"
    options:Refresh()
    chooseGroups()
    assert(options.outline.enabled == false and appearance.outline == "slots" and refreshes == calls,
        "Tint mode lost or modified the remembered inactive shape")
    assert(tint.control.enabled == true and outline.control.enabled == false and bag.control.enabled == true,
        "Tint mode did not separate content outlines from bag-button borders")
    assert(tint.control.alpha == 1 and tint.title.alpha == 1 and tint.value.alpha == 1)
    tint.control:SetValue(62)
    outline.control:SetValue(88)
    bag.control:SetValue(88)
    assert(appearance.tintAlpha == 0.62 and appearance.outlineAlpha == 0.50 and appearance.bagOutlineAlpha == 0.88,
        "editing bag-button opacity in Tint changed the disabled content-outline preference")
    appearance.mode = "outline"
    options:Refresh()
    assert(options.outline.enabled == true and options.outline.selectedText == "Individual slots",
        "reactivating outlines forgot the last selected shape")
    chooseGroups()
    assert(appearance.outline == "groups" and options.outline.selectedText == "Bag cartouches",
        "reactivated shape choices did not remain usable")
    tint.control:SetValue(13)
    outline.control:SetValue(45)
    bag.control:SetValue(27)
    assert(appearance.tintAlpha == 0.62 and appearance.outlineAlpha == 0.45 and appearance.bagOutlineAlpha == 0.27,
        "independent content and button opacity edits were not separated")
    for _ = 1, 5 do
        for _, mode in ipairs({ "off", "tint", "outline" }) do appearance.mode = mode; options:Refresh() end
    end
    assert(appearance.tintAlpha == 0.62 and appearance.outlineAlpha == 0.45 and appearance.bagOutlineAlpha == 0.27,
        "mode transitions rewrote saved opacity values")
    assert(appearance.outline == "groups" and options.outline.enabled == true
        and options.outline.selectedText == "Bag cartouches", "mode transitions rewrote the remembered outline shape")
    assert(frames == count and widgetCount == regions and menus == roots and radios == choices,
        "shape or opacity mode transitions allocated controls or rebuilt menus")
end

-- Fit the native canvas using recorded parent/anchor geometry. This does not
-- fake native font rasterization; real wrapping/artwork still need the client.
local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 0.00001, (message or "geometry") .. ": " .. actual .. " ~= " .. expected)
end
local function rect(object)
    local x, y, width, height = object:GetRect()
    assert(addon.IsFiniteNumber(x) and addon.IsFiniteNumber(y) and addon.IsFiniteNumber(width)
        and addon.IsFiniteNumber(height) and width > 0 and height > 0, "control has unresolved geometry")
    return { x = x, y = y, width = width, height = height }
end
local function within(object, parent)
    local child, bounds = rect(object), rect(parent)
    assert(child.x >= bounds.x - 0.00001 and child.y >= bounds.y - 0.00001
        and child.x + child.width <= bounds.x + bounds.width + 0.00001
        and child.y + child.height <= bounds.y + bounds.height + 0.00001, "control escaped its native canvas")
    return child
end
local function compact(options, width, height)
    assert(options.content:GetParent() == options.panel and options.content.kind == "Frame"
        and options.content.template == nil and options.content:IsShown(), "body is not a visible direct canvas child")
    near(options.panel:GetWidth(), width, "native canvas width was rewritten")
    near(options.panel:GetHeight(), height, "native canvas height was rewritten")
    near(options.content:GetWidth(), width - 32)
    near(options.content:GetHeight(), height - 64)
    within(options.content, options.panel)
    within(options.title, options.panel)
    assert(options.title.font == "GameFontNormalLarge", "compact layout changed the native title font")
    local objects = { options.modeTitle, options.mode, options.outlineTitle, options.outline,
        options.carryTitle, options.bankTitle, options.movable, options.movable.Text, options.reset,
        options.resetBagColors, options.resetBankColors }
    for _, setting in ipairs(options.sliders) do
        objects[#objects + 1], objects[#objects + 2], objects[#objects + 3] = setting.title, setting.control, setting.value
        assert(setting.control:GetWidth() >= 140, "compact opacity track became too narrow")
        local textWidth = setting.title:GetUnboundedStringWidth()
        assert(textWidth > 0 and textWidth <= setting.title:GetWidth(), "opacity label cannot fit its native glyph width")
        assert(setting.title.font == "GameFontNormal" and setting.title.justifyH == "LEFT", "opacity label changed font or alignment")
    end
    local carryNames = { "Backpack", "Bag 1", "Bag 2", "Bag 3", "Bag 4", "Reagent slot", "Keyring" }
    assert(#options.swatchButtons == 7 and #options.bankSwatchButtons == 9)
    for index, control in ipairs(options.swatchButtons) do
        assert(control.text == carryNames[index] and control:GetWidth() >= 116, "carried swatch lost its full label or target width")
        assert(control.kind == "Button" and control.template == "UIPanelButtonTemplate")
        objects[#objects + 1] = control
    end
    for index, control in ipairs(options.bankSwatchButtons) do
        assert(control.text == addon.bankColorChoices[index][2] and control:GetWidth() >= 116,
            "bank swatch lost its full label or target width")
        objects[#objects + 1] = control
    end
    for _, entry in ipairs({ { options.resetBagColors, options.swatchButtons[7], "Reset bag colors" },
        { options.resetBankColors, options.bankSwatchButtons[9], "Reset bank colors" } }) do
        local control, last, text = entry[1], entry[2], entry[3]
        local resetRect, lastRect = rect(control), rect(last)
        assert(control.text == text and control.kind == "Button" and control.template == "UIPanelButtonTemplate",
            "palette reset lost its label or native button")
        near(resetRect.y, lastRect.y, "palette reset added a row")
        near(resetRect.x, lastRect.x + lastRect.width + 8, "palette reset did not use the spare last-row column")
        near(resetRect.width, lastRect.width, "palette reset changed the palette column width")
        assert(resetRect.width >= 128 and resetRect.height == 24, "palette reset target became too small")
    end
    local rectangles = {}
    for _, object in ipairs(objects) do rectangles[#rectangles + 1] = within(object, options.content) end
    for index, first in ipairs(rectangles) do
        for secondIndex = index + 1, #rectangles do
            local second = rectangles[secondIndex]
            assert(first.x + first.width <= second.x + 0.00001 or second.x + second.width <= first.x + 0.00001
                or first.y + first.height <= second.y + 0.00001 or second.y + second.height <= first.y + 0.00001,
                "compact controls overlap")
        end
    end
    local left, right = rect(options.mode), rect(options.swatchButtons[1])
    assert(options.movable.Text.text == "Moveable windows" and options.movable.Text:GetUnboundedStringWidth() <= options.movable.Text:GetWidth())
    assert(options.carryTitle.text == "Bag slot colors" and options.bankTitle.text == "Bank slot colors"
        and options.carryTitle.justifyH == "LEFT" and options.bankTitle.justifyH == "LEFT")
    assert(right.x - left.x - left.width >= 20, "palette and appearance columns lost their separation")
end

do
    local options = addon.Options
    options:Open()
    compact(options, 665, 601)
    local count, regions, roots = frames, widgetCount, menus
    local retainedBody, retainedReset = options.content, options.reset
    for _ = 1, 10 do
        for _, size in ipairs({ { 630, 590 }, { 760, 640 }, { 665, 601 } }) do
            options.panel.width, options.panel.height = size[1], size[2]
            options.content:Fire("OnSizeChanged", options.content:GetWidth(), options.content:GetHeight())
            compact(options, size[1], size[2])
        end
    end
    assert(frames == count and widgetCount == regions and menus == roots, "resizing rebuilt controls, regions or menu roots")
    assert(options.content == retainedBody and options.reset == retainedReset)
    local unchanged = writes
    for _ = 1, 20 do options.content:Fire("OnSizeChanged", 633, 537) end
    assert(writes == unchanged, "unchanged size notifications repeated layout writes")

    local failing, messages, originalPoint = true, {}, options.reset.SetPoint
    addon.reports = {}
    addon.Print = function(_, message) messages[#messages + 1] = message end
    options.reset.SetPoint = function(self, ...)
        if failing then error("injected compact layout setter") end
        return originalPoint(self, ...)
    end
    options.panel.width, options.panel.height = 630, 590
    for _ = 1, 3 do assert(pcall(options.content.Fire, options.content, "OnSizeChanged", 598, 526)) end
    assert(not options.content:IsShown() and options.syncing == false and options.layingOut == false,
        "failed layout exposed partial controls or retained a guard")
    assert(#messages == 1 and messages[1]:find("injected compact layout setter", 1, true))
    assert(frames == count and widgetCount == regions, "failed layout retry allocated replacement controls")
    failing = false
    options.panel:Hide(); options:Open()
    compact(options, 630, 590)
    assert(options.content == retainedBody and options.reset == retainedReset and frames == count and widgetCount == regions)
    options.reset.SetPoint = originalPoint
end

-- Reset buttons exercise the real Core method, including picker closure before
-- copying defaults. A stale preview/cancel must not resurrect the old palette.
do
    local options, originalTooltip = addon.Options, GameTooltip
    assert(type(addon.ResetColors) == "function", "Core palette reset is required for the UI integration")
    local appearance = addon.db.appearance
    local mode, shape = appearance.mode, appearance.outline
    local tint, outline, bagOutline = appearance.tintAlpha, appearance.outlineAlpha, appearance.bagOutlineAlpha
    local movement = addon.db.movement.enabled
    local function palette(bank) return bank and appearance.bankColors or appearance.colors end
    local function setColor(bank, r, g, b)
        local color = palette(bank)[1]
        color[1], color[2], color[3] = r, g, b
    end
    local function sameColor(bank, r, g, b)
        local color = palette(bank)[1]
        assert(color[1] == r and color[2] == g and color[3] == b, "reset or picker affected the wrong color")
    end
    local function defaultColor(bank)
        local defaults = bank and addon.defaults.appearance.bankColors or addon.defaults.appearance.colors
        sameColor(bank, defaults[1][1], defaults[1][2], defaults[1][3])
    end
    local function reset(bank)
        local control = bank and options.resetBankColors or options.resetBagColors
        control.scripts.OnClick(control)
    end
    for _, bank in ipairs({ false, true }) do
        setColor(bank, 0.11, 0.22, 0.33)
        setColor(not bank, 0.44, 0.55, 0.66)
        options:ChooseColor(1, bank)
        assert(options.colorSession.bank == bank)
        picker:Preview(0.21, 0.31, 0.41)
        local staleInfo = picker.info
        reset(bank)
        assert(not picker:IsShown() and options.colorSession == nil, "palette reset left its preview active")
        defaultColor(bank)
        sameColor(not bank, 0.44, 0.55, 0.66)
        staleInfo.cancelFunc(); staleInfo.swatchFunc()
        options.panel:Hide(); options:Open()
        defaultColor(bank)
        sameColor(not bank, 0.44, 0.55, 0.66)

        -- Resetting the other palette must leave this preview usable, including
        -- restoring its accepted color if the user subsequently cancels it.
        setColor(bank, 0.12, 0.23, 0.34)
        setColor(not bank, 0.45, 0.56, 0.67)
        options:ChooseColor(1, bank)
        picker:Preview(0.22, 0.33, 0.44)
        local retainedSession, retainedInfo = options.colorSession, picker.info
        reset(not bank)
        assert(picker:IsShown() and options.colorSession == retainedSession and picker.info == retainedInfo,
            "resetting a different palette dismissed its active picker")
        sameColor(bank, 0.22, 0.33, 0.44)
        defaultColor(not bank)
        picker:Cancel()
        sameColor(bank, 0.12, 0.23, 0.34)
        defaultColor(not bank)
    end
    local originalSecret, originalExtraInfo, originalHide = issecretvalue, picker.GetExtraInfo, picker.Hide
    local secret = {}
    issecretvalue = function(value) return value == secret or (originalSecret and originalSecret(value)) or false end
    for _, bank in ipairs({ false, true }) do
        for _, owner in ipairs({ "foreign", "restricted", "throw" }) do
            options:ChooseColor(1, bank)
            picker:Preview(0.24, 0.35, 0.46)
            local staleInfo, retainedSession = picker.info, options.colorSession
            local reads, hides = 0, 0
            local foreignInfo = { extraInfo = owner == "restricted" and secret or {} }
            picker.info = foreignInfo
            picker.GetExtraInfo = function(self)
                reads = reads + 1
                if owner == "throw" then error("unavailable foreign picker owner") end
                return originalExtraInfo(self)
            end
            picker.Hide = function() hides = hides + 1 end
            options:ClosePalettePicker(not bank)
            assert(reads == 0 and options.colorSession == retainedSession,
                "closing the other palette inspected or released a foreign picker")
            assert(pcall(reset, bank), "palette reset escaped unreadable picker ownership")
            assert(reads == 1 and hides == 0 and picker:IsShown() and picker.info == foreignInfo
                and options.colorSession == nil, "palette reset dismissed or replaced a foreign picker")
            defaultColor(bank)
            staleInfo.cancelFunc(); staleInfo.swatchFunc()
            defaultColor(bank)
            picker.GetExtraInfo, picker.Hide = originalExtraInfo, originalHide
            picker:Hide()
        end
    end
    issecretvalue = originalSecret
    assert(appearance.mode == mode and appearance.outline == shape and appearance.tintAlpha == tint
        and appearance.outlineAlpha == outline and appearance.bagOutlineAlpha == bagOutline
        and addon.db.movement.enabled == movement,
        "palette reset changed appearance or movement preferences")
    local tooltipTitle, tooltipText
    GameTooltip = { SetOwner = function() end, SetText = function(_, text) tooltipTitle = text end,
        AddLine = function(_, text) tooltipText = text end, Show = function() end, Hide = function() end }
    options.resetBagColors:Fire("OnEnter")
    assert(tooltipTitle == "Reset bag colors" and tooltipText:find("only carried-bag colors", 1, true))
    options.resetBankColors:Fire("OnEnter")
    assert(tooltipTitle == "Reset bank colors" and tooltipText:find("only bank storage and bank-bag colors", 1, true))
    GameTooltip = originalTooltip
end

-- HookScript's native boolean result is part of readiness. A rejected/throwing
-- mandatory close hook retries with one retained callback; uncertain acceptance
-- may already have installed it, so it is quarantined without opening a picker.
do
    local originalPicker, originalSecret = ColorPickerFrame, issecretvalue
    local secret = {}
    issecretvalue = function(value) return value == secret or (originalSecret and originalSecret(value)) or false end
    for _, case in ipairs({ { "false", false }, { "throw" }, { "nil" }, { "restricted", secret },
        { "number", 1 }, { "string", "accepted" }, { "object", {} } }) do
        assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Options.lua"))("ForTheHoard", addon)
        local options, attempts, callback, accepted, setupCalls = addon.Options, 0, nil, false, 0
        local candidate = { hooks = {}, shown = false }
        ColorPickerFrame = candidate
        for _, method in ipairs({ "IsShown", "GetExtraInfo", "GetColorRGB", "Hide", "Preview", "Cancel" }) do
            candidate[method] = originalPicker[method]
        end
        candidate.SetupColorPickerAndShow = function(self, info)
            setupCalls = setupCalls + 1
            return originalPicker.SetupColorPickerAndShow(self, info)
        end
        candidate.HookScript = function(self, event, current)
            attempts = attempts + 1
            assert(callback == nil or callback == current, "picker retry replaced its owned callback")
            callback = current
            if accepted then return originalPicker.HookScript(self, event, current) end
            if case[1] == "throw" then error("injected picker hook throw") end
            if case[1] ~= "false" then originalPicker.HookScript(self, event, current) end
            return case[2]
        end
        addon.reports = {}
        for _ = 1, 3 do options:ChooseColor(1) end
        assert(not candidate:IsShown() and options.colorSession == nil and options.pickerHooked == false
            and setupCalls == 0 and not options.pickerHook.ready,
            "unconfirmed picker lifecycle hook opened or retained an owned session")
        accepted = true
        options:ChooseColor(1)
        if case[1] == "false" or case[1] == "throw" then
            assert(attempts == 4 and candidate:IsShown() and options.pickerHooked == true and setupCalls == 1,
                "a known-failed picker hook did not recover")
            candidate:Hide()
            assert(options.colorSession == nil, "recovered picker acceptance retained stale ownership")
        else
            assert(attempts == 1 and setupCalls == 0 and not candidate:IsShown() and options.pickerHook.uncertain,
                "uncertain picker hook was retried or claimed ready")
            if candidate.hooks.OnHide then candidate.hooks.OnHide() end
            assert(options.colorSession == nil, "quarantined picker callback created a session")
        end
    end
    -- Shared native extraInfo belongs to the current picker owner and may be
    -- unreadable. Stale callbacks and closing Settings must preserve that owner.
    for _, unavailable in ipairs({ "restricted", "throw" }) do
        assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Options.lua"))("ForTheHoard", addon)
        local options, foreignHidden = addon.Options, 0
        local candidate = { hooks = {}, shown = false }
        ColorPickerFrame = candidate
        for _, method in ipairs({ "HookScript", "IsShown", "GetExtraInfo", "GetColorRGB", "Hide", "Preview",
            "Cancel", "SetupColorPickerAndShow" }) do candidate[method] = originalPicker[method] end
        options:ChooseColor(1)
        local stalePreview, color = candidate.info.swatchFunc, addon.db.appearance.colors[1]
        local before = { color[1], color[2], color[3] }
        candidate.GetExtraInfo = function()
            if unavailable == "throw" then error("foreign picker information unavailable") end
            return secret
        end
        candidate.Hide = function() foreignHidden = foreignHidden + 1 end
        candidate.r, candidate.g, candidate.b = 0.99, 0.98, 0.97
        assert(pcall(stalePreview), "unreadable foreign picker ownership escaped a swatch callback")
        assert(pcall(candidate.hooks.OnHide), "unreadable foreign picker ownership escaped the native hide callback")
        assert(pcall(options.CloseOwnedPicker, options, true) and options.colorSession == nil and foreignHidden == 0,
            "Settings dismissed another owner's unreadable picker")
        assert(color[1] == before[1] and color[2] == before[2] and color[3] == before[3],
            "stale private picker callbacks changed a saved color")
    end
    ColorPickerFrame, issecretvalue = originalPicker, originalSecret
end

-- Tooltip hooks are optional. They cannot make the settings unusable, and an
-- accepted-but-unconfirmed native callback stays inert rather than duplicating
-- on every reopen or pretending to be ready.
do
    local originalSecret, originalTooltip = issecretvalue, GameTooltip
    local secret = {}
    issecretvalue = function(value) return value == secret or (originalSecret and originalSecret(value)) or false end
    for _, case in ipairs({ { "false", "OnEnter", false }, { "throw", "OnLeave" }, { "nil", "OnEnter" },
        { "restricted", "OnLeave", secret }, { "number", "OnEnter", 1 }, { "string", "OnLeave", "accepted" },
        { "object", "OnEnter", {} } }) do
        assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Options.lua"))("ForTheHoard", addon)
        local options, attempts, retained, accepted, target = addon.Options, 0, nil, false, nil
        local shown, hidden = 0, 0
        GameTooltip = { SetOwner = function() end, SetText = function() end, AddLine = function() end,
            Show = function() shown = shown + 1 end, Hide = function() hidden = hidden + 1 end }
        CreateFrame = function(kind, ...)
            local result = originalCreate(kind, ...)
            if kind == "Button" then
                result.HookScript = function(self, event, callback)
                    if self.text ~= "Backpack" or event ~= case[2] then return methods.HookScript(self, event, callback) end
                    target, attempts = self, attempts + 1
                    assert(retained == nil or retained == callback, "tooltip retry replaced its owned callback")
                    retained = callback
                    if accepted then return methods.HookScript(self, event, callback) end
                    if case[1] == "throw" then error("injected tooltip hook throw") end
                    if case[1] ~= "false" then methods.HookScript(self, event, callback) end
                    return case[3]
                end
            end
            return result
        end
        addon.reports = {}
        options:Open()
        local state = options.tooltipHooks[target][case[2] == "OnEnter" and "enter" or "leave"]
        assert(options.controlsBuilt and not state.ready, "optional tooltip readiness blocked settings or accepted failure")
        local frameCount, regionCount, menuCount = frames, widgetCount, menus
        target:Fire(case[2])
        assert(shown == 0 and hidden == 0, "unconfirmed tooltip callback changed native presentation")
        for _ = 1, 3 do options.panel:Hide(); options:Open() end
        accepted = true
        options.panel:Hide(); options:Open()
        if case[1] == "false" or case[1] == "throw" then
            assert(attempts == 5 and state.ready, "known-failed tooltip hook did not retry and recover")
            target:Fire(case[2])
            assert((case[2] == "OnEnter" and shown == 1) or (case[2] == "OnLeave" and hidden == 1),
                "accepted tooltip callback remained unavailable")
        else
            assert(attempts == 1 and state.uncertain and not state.ready and target.hookCounts[case[2]] == 1,
                "uncertain tooltip installation duplicated hooks or claimed readiness")
            target:Fire(case[2])
            assert(shown == 0 and hidden == 0, "quarantined tooltip callback became active")
        end
        assert(frames == frameCount and widgetCount == regionCount and menus == menuCount,
            "tooltip recovery rebuilt retained settings resources")
        options.panel:Hide()
        CreateFrame = originalCreate
    end
    issecretvalue, GameTooltip = originalSecret, originalTooltip
end

print("Options: compact canvas, readable labels, palette resets, opacity modes and lifecycle recovery passed")
