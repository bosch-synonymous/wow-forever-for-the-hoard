local addonName, Addon = ...

Addon.name = addonName
Addon.version = "0.1.25"

function Addon.IsPublic(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return false
    end
    if type(canaccessvalue) == "function" and not canaccessvalue(value) then
        return false
    end
    return true
end

function Addon.IsFiniteNumber(value)
    return Addon.IsPublic(value) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end

Addon.defaults = {
    schemaVersion = 1,
    appearance = {
        mode = "outline", outline = "groups", tintAlpha = 0.5, outlineAlpha = 0.75, bagOutlineAlpha = 0.75,
        colors = {
            [0] = { 0.36, 0.62, 0.65 },
            [1] = { 0.77, 0.57, 0.29 },
            [2] = { 0.61, 0.48, 0.70 },
            [3] = { 0.39, 0.64, 0.42 },
            [4] = { 0.74, 0.43, 0.43 },
            [5] = { 0.42, 0.55, 0.79 },
            [-1] = { 0.68, 0.64, 0.39 },
        },
        bankColors = {
            [1] = { 0.68, 0.64, 0.39 },
            [2] = { 0.36, 0.62, 0.65 },
            [3] = { 0.77, 0.57, 0.29 },
            [4] = { 0.61, 0.48, 0.70 },
            [5] = { 0.39, 0.64, 0.42 },
            [6] = { 0.74, 0.43, 0.43 },
            [7] = { 0.42, 0.55, 0.79 },
            [8] = { 0.75, 0.48, 0.64 },
            [9] = { 0.55, 0.64, 0.36 },
        },
    },
    movement = { enabled = true },
}

Addon.bankColorChoices = {
    { 1, "Bank storage" }, { 2, "Bank bag 1" }, { 3, "Bank bag 2" },
    { 4, "Bank bag 3" }, { 5, "Bank bag 4" }, { 6, "Bank bag 5" },
    { 7, "Bank bag 6" }, { 8, "Bank bag 7" }, { 9, "Bank bag 8" },
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function mergeKnownDefaults(target, defaults)
    for key, default in pairs(defaults) do
        local existing = target[key]
        if not Addon.IsPublic(existing) or type(existing) ~= type(default) then
            target[key] = copy(default)
        elseif type(default) == "table" then
            mergeKnownDefaults(existing, default)
        end
    end
end

local function initializeStore(existing, defaults)
    if existing == nil then return copy(defaults) end
    if not Addon.IsPublic(existing) or type(existing) ~= "table" then return nil end
    local version = existing.schemaVersion
    if not Addon.IsPublic(version) then return nil end
    if version == nil then
        if next(existing) ~= nil then return nil end
    elseif version ~= 1 then
        return nil
    end
    mergeKnownDefaults(existing, defaults)
    return existing
end

local function isChoice(value, choices)
    if not Addon.IsPublic(value) or type(value) ~= "string" then return false end
    for _, choice in ipairs(choices) do
        if value == choice then return true end
    end
    return false
end

function Addon:Print(message)
    if not self.IsPublic(message) or type(message) ~= "string" then return end
    local text = "|cffc6a66bFor the Hoard:|r " .. message
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    elseif type(print) == "function" then
        print(text)
    end
end

function Addon:ReportOnce(key, message)
    self.reports = self.reports or {}
    if self.reports[key] then return end
    self.reports[key] = true
    self:Print(message)
end

function Addon:InitializeSavedState()
    -- Validate both roots before merging either; unfamiliar saves remain untouched.
    local function recognized(value)
        if value == nil then return true end
        if not self.IsPublic(value) or type(value) ~= "table" then return false end
        local version = value.schemaVersion
        if not self.IsPublic(version) then return false end
        return version == 1 or (version == nil and next(value) == nil)
    end
    if not recognized(ForTheHoardDB) or not recognized(ForTheHoardCharacterDB) then
        self:ReportOnce("saved-schema", "Saved settings have an unfamiliar format. They have been preserved; the addon is inactive.")
        return false
    end
    -- The former outline setting controlled both content and bag buttons.
    -- Preserve that visible choice once, before defaults fill the new field.
    local previous = type(ForTheHoardDB) == "table" and ForTheHoardDB.appearance
    if self.IsPublic(previous) and type(previous) == "table" and self.IsPublic(previous.bagOutlineAlpha)
        and previous.bagOutlineAlpha == nil and self.IsFiniteNumber(previous.outlineAlpha)
        and previous.outlineAlpha >= 0 and previous.outlineAlpha <= 1 then
        previous.bagOutlineAlpha = previous.outlineAlpha
    end
    self.db = initializeStore(ForTheHoardDB, self.defaults)
    self.char = initializeStore(ForTheHoardCharacterDB, { schemaVersion = 1, bagPositions = {} })
    ForTheHoardDB, ForTheHoardCharacterDB = self.db, self.char

    local appearance = self.db.appearance
    if not isChoice(appearance.mode, { "off", "tint", "outline" }) then appearance.mode = self.defaults.appearance.mode end
    if not isChoice(appearance.outline, { "slots", "groups" }) then appearance.outline = self.defaults.appearance.outline end
    for _, key in ipairs({ "tintAlpha", "outlineAlpha", "bagOutlineAlpha" }) do
        if not self.IsFiniteNumber(appearance[key]) or appearance[key] < 0 or appearance[key] > 1 then
            appearance[key] = self.defaults.appearance[key]
        end
    end
    for _, palette in ipairs({ "colors", "bankColors" }) do
        for bag, default in pairs(self.defaults.appearance[palette]) do
            local color = appearance[palette][bag]
            for component = 1, 3 do
                if not self.IsFiniteNumber(color[component]) or color[component] < 0 or color[component] > 1 then
                    color[component] = default[component]
                end
            end
        end
    end
    return true
end

local moduleNames = { "Colors", "Movement", "IndividualBags", "Options" }

function Addon:RunModule(name, method, ...)
    local module = self[name]
    if not module or type(module[method]) ~= "function" then return end
    local ok, failure = pcall(module[method], module, ...)
    local key = "module-" .. name .. "-" .. method
    if ok then
        if self.reports then self.reports[key] = nil end
    else
        local detail = self.IsPublic(failure) and type(failure) == "string" and failure or "Diagnostic unavailable."
        self:ReportOnce(key, name .. " could not " .. method .. ": " .. detail)
    end
    return ok
end

function Addon:Refresh()
    if not self.ready then return end
    for _, name in ipairs(moduleNames) do
        self:RunModule(name, "Refresh")
    end
end

function Addon:RefreshAppearance()
    if not self.ready then return end
    self:RunModule("Colors", "Refresh")
    self:RunModule("Options", "Refresh")
end

function Addon:ResetColors(bank)
    if not self.IsPublic(bank) or (bank ~= nil and type(bank) ~= "boolean") then return false end
    if not self.ready or not self.IsPublic(self.db) or type(self.db) ~= "table" then return false end
    local appearance = self.db.appearance
    if not self.IsPublic(appearance) or type(appearance) ~= "table" then return false end
    local paletteName = bank == true and "bankColors" or "colors"
    local palette = appearance[paletteName]
    if not self.IsPublic(palette) or type(palette) ~= "table" then return false end
    local entries = {}
    for position, default in pairs(self.defaults.appearance[paletteName]) do
        local color = palette[position]
        if not self.IsPublic(color) then return false end
        if type(color) ~= "table" then color = {} end
        entries[#entries + 1] = { position = position, color = color, default = default }
    end
    -- End a matching live preview before writing defaults, so stale preview or
    -- cancel callbacks cannot restore a pre-reset color. Other owners stay open.
    if self:RunModule("Options", "ClosePalettePicker", bank == true) == false then return false end
    for _, entry in ipairs(entries) do
        for component = 1, 3 do entry.color[component] = entry.default[component] end
        palette[entry.position] = entry.color
    end
    self:RefreshAppearance()
    return true
end

function Addon:HandleSlash(message)
    if not self.ready then
        self:Print("The addon is not active. Check its earlier diagnostic.")
        return
    end
    local command, argument = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command, argument = command:lower(), argument:lower()
    if command == "" or command == "settings" then
        self.Options:Open()
    elseif command == "bankdebug" then
        self:RunModule("Colors", "PrintBankDebug")
    elseif command == "banktrace" then
        if argument == "start" then
            self:RunModule("Colors", "StartBankTrace")
        elseif argument == "stop" then
            self:RunModule("Colors", "StopBankTrace")
        elseif argument == "" then
            self:RunModule("Colors", "PrintBankTrace")
        else
            self:Print("Use /fth banktrace start, /fth banktrace, or /fth banktrace stop.")
        end
    elseif command == "mode" and isChoice(argument, { "off", "tint", "outline" }) then
        self.db.appearance.mode = argument
        self:RefreshAppearance()
    elseif command == "resetbags" then
        if self:RunModule("Movement", "ResetBagPositions") then
            self:Print("Individual bag positions cleared; automatic placement updates when permitted.")
        end
    elseif command == "reset" and argument == "" then
        self.Movement:ResetPosition()
        self:Print("Bag and bank positions reset.")
    elseif command == "move" and isChoice(argument, { "on", "off" }) then
        self.db.movement.enabled = argument == "on"
        self.Movement:Refresh()
        self.Options:Refresh()
    else
        self:Print("/fth settings; /fth mode off|tint|outline; /fth move on|off; /fth reset; /fth resetbags; /fth bankdebug; /fth banktrace [start|stop]")
    end
end

function Addon:OnEvent(event, ...)
    if event == "ADDON_LOADED" and ... == addonName then
        self.savedReady = self:InitializeSavedState()
        return
    end
    if event == "PLAYER_LOGIN" then
        if not self.savedReady then return end
        self.ready = true
        for _, name in ipairs(moduleNames) do
            self:RunModule(name, "Initialize")
        end
        self:Refresh()
        return
    end
    if not self.ready then return end
    for _, name in ipairs(moduleNames) do
        self:RunModule(name, "OnEvent", event, ...)
    end
end

local events = CreateFrame("Frame")
Addon.eventFrame = events
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "INPUT_DEVICE_INTERFACE_TRANSITION", "ADDON_RESTRICTION_STATE_CHANGED", "BAG_CLOSED",
    "BANK_TABS_CHANGED", "PLAYERBANKSLOTS_CHANGED", "BAG_CONTAINER_UPDATE",
}) do
    -- Optional input-style events differ between clients; feature hooks still refresh.
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...) Addon:OnEvent(event, ...) end)

SLASH_FORTHEHOARD1 = "/fth"
SLASH_FORTHEHOARD2 = "/forthehoard"
SlashCmdList.FORTHEHOARD = function(message) Addon:HandleSlash(message) end
