local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function newAddon(account, character)
    ForTheHoardDB, ForTheHoardCharacterDB = account, character
    SlashCmdList = {}
    CreateFrame = function()
        return { registered = {}, RegisterEvent = function(self, event) self.registered[event] = true end,
            SetScript = function() end }
    end
    DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    local addon = {}
    assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Core.lua"))("ForTheHoard", addon)
    return addon
end

local addon = newAddon()
assert(addon.eventFrame.registered.INPUT_DEVICE_INTERFACE_TRANSITION,
    "must subscribe to the native interface-style transition event")
for _, event in ipairs({ "BANK_TABS_CHANGED", "PLAYERBANKSLOTS_CHANGED", "BAG_CONTAINER_UPDATE" }) do
    assert(addon.eventFrame.registered[event], "missing bank refresh event: " .. event)
end
assert(addon:InitializeSavedState())
equal(addon.db.appearance.mode, "outline")
equal(addon.db.appearance.bagOutlineAlpha, 0.75)
equal(addon.db.movement.enabled, true)
assert(type(addon.char.bagPositions) == "table", "new characters need independent bag position storage")
addon.db.appearance.colors[1][1] = 0
equal(addon.defaults.appearance.colors[1][1], 0.77, "defaults are not shared with saved colors")
equal(#addon.bankColorChoices, 9, "bank choices cover base storage and eight bag positions")
addon.db.appearance.bankColors[1][1] = 0.9
equal(addon.defaults.appearance.bankColors[1][1], 0.68, "bank defaults are not shared with saves")
equal(addon.db.appearance.colors[1][1], 0, "bank colors do not change carried colors")

local future = { schemaVersion = 7, appearance = { mode = "future", outlineAlpha = 0 } }
local existingCharacter = { schemaVersion = 1 }
addon = newAddon(future, existingCharacter)
equal(addon:InitializeSavedState(), false)
equal(ForTheHoardDB, future)
equal(future.appearance.mode, "future")
equal(future.appearance.bagOutlineAlpha, nil, "unknown schema must not receive opacity migration")
equal(existingCharacter.position, nil)
equal(existingCharacter.schemaVersion, 1)

local unknown = { arbitrary = "retain me" }
addon = newAddon(unknown, nil)
equal(addon:InitializeSavedState(), false)
equal(unknown.schemaVersion, nil)
equal(unknown.arbitrary, "retain me")
equal(ForTheHoardCharacterDB, nil, "invalid root must not create another saved root")

local saved = { schemaVersion = 1, extra = "keep", appearance = {
    mode = "off", tintAlpha = 0, colors = { [1] = { 0.1, 0.2, 0.3, note = "keep" } },
}, movement = { enabled = false } }
addon = newAddon(saved, {})
assert(addon:InitializeSavedState())
equal(addon.db, saved)
equal(saved.extra, "keep")
equal(saved.appearance.tintAlpha, 0)
equal(saved.appearance.mode, "off")
equal(saved.movement.enabled, false)
equal(saved.appearance.colors[1].note, "keep")
equal(saved.appearance.colors[1][2], 0.2)
equal(saved.appearance.bankColors[1][1], 0.68, "existing version-one saves gain bank defaults")

local combinedPosition = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 77, y = -88 }
local bagPositions = { [1] = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 123, y = -45 },
    [99] = { future = "preserve" } }
local bankPosition = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 456, y = -78 }
local character = { schemaVersion = 1, position = combinedPosition, bagPositions = bagPositions,
    bankPosition = bankPosition, future = "keep" }
addon = newAddon(nil, character)
assert(addon:InitializeSavedState())
equal(addon.char, character)
equal(character.position, combinedPosition, "legacy combined placement must remain intact")
equal(character.bagPositions, bagPositions)
equal(character.bagPositions[99].future, "preserve")
equal(character.bankPosition, bankPosition)
equal(character.future, "keep")

local bankSaved = { schemaVersion = 1, appearance = { bankColors = {
    [1] = { 0.1, 0, 0.3, note = "keep bank notes" },
    [9] = { 0.9, 0.8, 0.7 }, [30] = { future = "retain" },
} } }
addon = newAddon(bankSaved)
assert(addon:InitializeSavedState())
equal(bankSaved.appearance.bankColors[1][2], 0, "zero color components are preserved")
equal(bankSaved.appearance.bankColors[1].note, "keep bank notes")
equal(bankSaved.appearance.bankColors[9][1], 0.9)
equal(bankSaved.appearance.bankColors[30].future, "retain")

local invalid = { schemaVersion = 1, appearance = { mode = "bad", tintAlpha = 0/0,
    outlineAlpha = math.huge, colors = { [0] = { -1, 3, "invalid" } },
    bankColors = { [1] = { math.huge, 0.2, -1 }, [9] = "invalid" },
} }
addon = newAddon(invalid)
assert(addon:InitializeSavedState())
equal(invalid.appearance.mode, "outline")
equal(invalid.appearance.tintAlpha, 0.5)
equal(invalid.appearance.outlineAlpha, 0.75)
equal(invalid.appearance.bagOutlineAlpha, 0.75)
equal(invalid.appearance.colors[0][1], 0.36)
equal(invalid.appearance.bankColors[1][1], 0.68)
equal(invalid.appearance.bankColors[1][2], 0.2)
equal(invalid.appearance.bankColors[1][3], 0.39)
equal(invalid.appearance.bankColors[9][1], 0.55)

-- The former single outline opacity affected items and bag buttons. Upgrade
-- missing button opacity once, including zero, then keep the choices independent.
for _, alpha in ipairs({ 0, 0.31, 1 }) do
    local store = { schemaVersion = 1, appearance = { outlineAlpha = alpha, future = "keep" } }
    local migrated = newAddon(store)
    assert(migrated:InitializeSavedState())
    equal(store.appearance.outlineAlpha, alpha)
    equal(store.appearance.bagOutlineAlpha, alpha, "migration must preserve the old visible bag-border opacity")
    equal(store.appearance.future, "keep")
    store.appearance.outlineAlpha = 0.87
    assert(migrated:InitializeSavedState())
    equal(store.appearance.bagOutlineAlpha, alpha, "reinitialization must not repeat opacity migration")
end
for _, alpha in ipairs({ 0, 0.22, 1 }) do
    local store = { schemaVersion = 1, appearance = { outlineAlpha = 0.81, bagOutlineAlpha = alpha } }
    local current = newAddon(store)
    assert(current:InitializeSavedState())
    equal(store.appearance.bagOutlineAlpha, alpha, "an explicit button opacity must survive initialization")
    equal(store.appearance.outlineAlpha, 0.81)
end
for _, alpha in ipairs({ -0.1, 1.1, math.huge, 0/0, "invalid", false }) do
    local store = { schemaVersion = 1, appearance = { outlineAlpha = 0.31, bagOutlineAlpha = alpha } }
    local current = newAddon(store)
    assert(current:InitializeSavedState())
    equal(store.appearance.bagOutlineAlpha, 0.75, "malformed explicit opacity must use its validated default")
    equal(store.appearance.outlineAlpha, 0.31)
end
local blockedAccount = { schemaVersion = 1, appearance = { outlineAlpha = 0 } }
local blocked = newAddon(blockedAccount, { schemaVersion = 99 })
equal(blocked:InitializeSavedState(), false)
equal(blockedAccount.appearance.bagOutlineAlpha, nil, "validate both saved roots before migrating either")

local initialized = {}
for _, name in ipairs({ "Colors", "Movement", "IndividualBags", "Options" }) do
    local moduleName = name
    addon[name] = {
        Initialize = function() initialized[#initialized + 1] = moduleName end,
        Refresh = function() end,
    }
end
addon.savedReady = true
addon:OnEvent("PLAYER_LOGIN")
equal(table.concat(initialized, ","), "Colors,Movement,IndividualBags,Options")
equal(addon.ready, true)

local continued, diagnostics = 0, {}
addon.Print = function(_, text) diagnostics[#diagnostics + 1] = text end
addon.Colors.OnEvent = function() error("native decoration failure") end
addon.Movement.OnEvent = function() continued = continued + 1 end
addon:OnEvent("BAG_UPDATE_DELAYED")
addon:OnEvent("BAG_UPDATE_DELAYED")
equal(continued, 2, "one feature failure must not block another feature")
equal(#diagnostics, 1, "repeat identical failure should be coalesced")
assert(diagnostics[1]:find("native decoration failure", 1, true), "original diagnostic must be retained")
addon.Colors.OnEvent = function() end
addon:OnEvent("BAG_UPDATE_DELAYED")
addon.Colors.OnEvent = function() error("another native failure") end
addon:OnEvent("BAG_UPDATE_DELAYED")
equal(#diagnostics, 2, "a new failure after recovery must be reported")

local bankDebugCalls = 0
addon.Colors.PrintBankDebug = function() bankDebugCalls = bankDebugCalls + 1 end
local bankTraceCalls = 0
addon.Colors.PrintBankTrace = function() bankTraceCalls = bankTraceCalls + 1 end
local traceStarts, traceStops = 0, 0
addon.Colors.StartBankTrace = function() traceStarts = traceStarts + 1 end
addon.Colors.StopBankTrace = function() traceStops = traceStops + 1 end
local bagPositionResets, allPositionResets = 0, 0
addon.Movement.ResetBagPositions = function() bagPositionResets = bagPositionResets + 1 end
addon.Movement.ResetPosition = function() allPositionResets = allPositionResets + 1 end
addon:HandleSlash("resetbags")
equal(bagPositionResets, 1, "bag-only reset dispatches its scoped movement operation")
equal(allPositionResets, 0, "bag-only reset must not clear combined or bank positions")
addon:HandleSlash("reset unexpected")
equal(allPositionResets, 0, "an unsupported reset scope must not fall through to clearing every position")
addon:HandleSlash("bankdebug")
equal(bankDebugCalls, 1, "bankdebug dispatches the read-only bank probe")
addon:HandleSlash("banktrace")
equal(bankTraceCalls, 1, "banktrace dispatches the bounded sizing trace")
addon:HandleSlash("banktrace start")
addon:HandleSlash("banktrace stop")
equal(traceStarts, 1, "explicit start enables temporary bank tracing")
equal(traceStops, 1, "explicit stop disables temporary bank tracing")
addon:HandleSlash("banktrace invalid")
equal(traceStarts, 1, "unknown trace commands cannot enable collection")
equal(bankTraceCalls, 1, "unknown trace commands cannot materialize a diagnostic snapshot")
equal(addon.db.appearance.mode, "outline", "diagnostic dispatch does not change settings")
addon.ready = false
addon:HandleSlash("resetbags")
equal(bagPositionResets, 1, "an inactive saved store cannot reset individual positions")
addon:HandleSlash("bankdebug")
equal(bankDebugCalls, 1, "inactive saved state cannot run the bank probe")
addon:HandleSlash("banktrace")
equal(bankTraceCalls, 1, "inactive saved state cannot print the bank trace")
addon:HandleSlash("banktrace start")
addon:HandleSlash("banktrace stop")
equal(traceStarts, 1, "inactive saved state cannot enable bank tracing")
equal(traceStops, 1, "inactive saved state cannot change trace state")
addon.ready = true

-- Palette resets must preserve the other palette, unrelated preferences and
-- unknown fields, while retaining color-table identities used by UI controls.
local futureBag, futureBank = { note = "future bag" }, { note = "future bank" }
local resetStore = { schemaVersion = 1, appearance = {
    mode = "tint", outline = "slots", tintAlpha = 0.21, outlineAlpha = 0.42, bagOutlineAlpha = 0.63,
    colors = { [0] = { 0.1, 0.2, 0.3, note = "keep" }, [99] = futureBag },
    bankColors = { [1] = { 0.9, 0.8, 0.7 }, [99] = futureBank },
}, movement = { enabled = false } }
local resetCharacter = { schemaVersion = 1, bagPositions = { [5] = { x = 5, y = -5 } },
    position = { x = 10, y = -10 }, bankPosition = { x = 20, y = -20 } }
local resetAddon = newAddon(resetStore, resetCharacter)
assert(resetAddon:InitializeSavedState())
local bagPalette, bankPalette = resetStore.appearance.colors, resetStore.appearance.bankColors
local bagColor, bankColor = bagPalette[0], bankPalette[1]
local closeCalls, paintCalls = {}, 0
resetAddon.ready = true
resetAddon.Options = { ClosePalettePicker = function(_, bank)
    closeCalls[#closeCalls + 1] = bank and "bank" or "bags"
    equal(bank and bankColor[1] or bagColor[1], bank and 0.9 or 0.1,
        "end the matching preview before replacing its current RGB")
end, Refresh = function() end }
resetAddon.Colors = { Refresh = function() paintCalls = paintCalls + 1 end }
assert(resetAddon:ResetColors(false))
for position, color in pairs(resetAddon.defaults.appearance.colors) do
    for component = 1, 3 do equal(bagPalette[position][component], color[component]) end
end
equal(bagPalette[0], bagColor); equal(bagColor.note, "keep"); equal(bagPalette[99], futureBag)
equal(bankPalette[1], bankColor); equal(bankColor[1], 0.9); equal(bankPalette[99], futureBank)
bagColor[1] = 0.44
assert(resetAddon:ResetColors(true))
for position, color in pairs(resetAddon.defaults.appearance.bankColors) do
    for component = 1, 3 do equal(bankPalette[position][component], color[component]) end
end
equal(bagColor[1], 0.44, "bank reset leaves the current bag palette alone")
equal(bankPalette[1], bankColor); equal(bankPalette[99], futureBank)
equal(table.concat(closeCalls, ","), "bags,bank"); equal(paintCalls, 2)
equal(resetStore.appearance.mode, "tint"); equal(resetStore.appearance.outline, "slots")
equal(resetStore.appearance.tintAlpha, 0.21); equal(resetStore.appearance.outlineAlpha, 0.42)
equal(resetStore.appearance.bagOutlineAlpha, 0.63)
equal(resetStore.movement.enabled, false)
equal(resetAddon.char, resetCharacter); equal(resetCharacter.bagPositions[5].x, 5)
equal(resetCharacter.position.x, 10); equal(resetCharacter.bankPosition.x, 20)
equal(resetAddon.defaults.appearance.colors[0][1], 0.36, "reset must not alias saved colors to defaults")
resetAddon.Options.ClosePalettePicker = function() error("picker teardown rejected") end
resetAddon.Print = function() end
equal(resetAddon:ResetColors(false), false)
equal(bagColor[1], 0.44, "failed preview teardown must leave the palette untouched")
equal(paintCalls, 2)
resetAddon.ready = false
equal(resetAddon:ResetColors(true), false); equal(resetAddon:ResetColors("bank"), false)
equal(paintCalls, 2)

local restricted = {}
issecretvalue = function(value) return rawequal(value, restricted) end
equal(addon.IsPublic(restricted), false)
equal(addon.IsFiniteNumber(restricted), false)
equal(addon.IsFiniteNumber(0), true)
equal(addon.IsFiniteNumber(math.huge), false)
issecretvalue = nil
