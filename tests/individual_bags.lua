-- Contract simulations: native clicks, pooled frames and close ownership.
-- WoW rendering, protected frames and input timing still require the client.
local source = REPO_ROOT .. "/src/ForTheHoard/IndividualBags.lua"
local restricted = setmetatable({}, {
    __eq = function() error("restricted comparison") end,
    __lt = function() error("restricted ordering") end,
    __tostring = function() error("restricted formatting") end,
})
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function Pack(...) return { n = select("#", ...), ... } end
local methods = {}
function methods:IsShown() return self.shown == true end
function methods:IsVisible() return self:IsShown() end
function methods:IsForbidden() return self.forbidden == true end
function methods:IsProtected() return self.protected end
function methods:GetName() return self.name end
function methods:GetID() return self.bagID end
function methods:GetBagID() return self.bagID end
function methods:GetBagSize() return self.size end
function methods:IsBackpack() return self.role == "backpack" end
function methods:GetParent() return UIParent end
function methods:GetScript(event) return self.scripts[event] end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback)
    self.hooks[event] = self.hooks[event] or {}
    self.hooks[event][#self.hooks[event] + 1] = callback
    return true
end
function methods:Fire(event, ...)
    local result
    if self.scripts[event] then result = Pack(self.scripts[event](self, ...)) end
    for _, callback in ipairs(self.hooks[event] or {}) do callback(self, ...) end
    if result then return unpack(result, 1, result.n) end
end
function methods:Show()
    if self.shown then return end
    self.shown = true
    self:Fire("OnShow")
end
function methods:Hide()
    if not self.shown then return end
    self.shown = false
    self:Fire("OnHide")
end
function methods:IsCombinedBagContainer() return self.combined == true end
function methods:CanUseForBagID(id)
    if self.combined then return id >= 0 and id <= 4 end
    if self.role == "backpack" then return id == 0 end
    if id == 5 then return self.role == "reagent" end
    return true
end
function methods:Update()
    self.contentUpdates = self.contentUpdates + 1
end
function methods:UpdateItems() self.itemUpdates = self.itemUpdates + 1 end
function methods:UpdateItemLayout() self.layouts = self.layouts + 1 end
function methods:OnCloseClicked() return CloseBag(self:GetBagID()) end

local function Setup(options)
    options = options or {}
    local state = {
        shift = false, control = false, alt = false, cursor = nil, quick = false,
        combat = false, gamepad = false, combined = true, allowed = true, denied = false,
        sizes = { [0] = 16, [1] = 8, [2] = 12, [3] = 14, [4] = 16, [5] = 10 },
        clicks = {}, closes = {}, hooks = 0, generates = 0, updates = 0,
        reports = {}, callbacks = {}, timers = {}, cvarWrites = 0, closeAllCalls = 0,
    }
    securecallfunction = function(callback, ...)
        state.secureCalls = (state.secureCalls or 0) + 1
        state.secureCallback = callback
        return callback(...)
    end
    local function Frame(name, bagID, role)
        return setmetatable({ name = name, bagID = bagID, role = role,
            shown = false, scripts = {}, hooks = {}, contentUpdates = 0, itemUpdates = 0, layouts = 0 },
            { __index = methods })
    end
    UIParent = Frame("UIParent"); UIParent.shown = true
    ContainerFrameCombinedBags = Frame("ContainerFrameCombinedBags", 0)
    ContainerFrameCombinedBags.combined = true
    local raw = { Frame("ContainerFrame1", 0, "backpack"), Frame("ContainerFrame2", 1, "normal"),
        Frame("ContainerFrame3", 5, "reagent"), Frame("ContainerFrame4", 2, "normal"),
        Frame("ContainerFrame5", 3, "normal"), Frame("ContainerFrame6", 4, "normal") }
    for i, frame in ipairs(raw) do _G["ContainerFrame" .. i] = frame end
    NUM_CONTAINER_FRAMES = #raw
    ContainerFrameContainer = options.namedFallback and nil or { ContainerFrames = { ContainerFrameCombinedBags, unpack(raw) } }
    if not options.noRegistry then
        EventRegistry = {
            RegisterCallback = function(_, event, callback, owner)
                state.callbacks[event] = state.callbacks[event] or {}
                table.insert(state.callbacks[event], { callback, owner })
            end,
            TriggerEvent = function(_, event, ...)
                for _, entry in ipairs(state.callbacks[event] or {}) do entry[1](entry[2], ...) end
            end,
        }
    else EventRegistry = nil end
    InCombatLockdown = function() return state.combat end
    InputUtil = { IsGamepadUIEnabled = function() return state.gamepad end }
    IsShiftKeyDown = function() return state.shift end
    IsControlKeyDown = function() return state.control end
    IsAltKeyDown = function() return state.alt end
    GetCursorInfo = function() if state.cursor then return unpack(state.cursor) end end
    CursorHasItem = function() return state.cursor ~= nil end
    QuickKeybindFrame = { IsShown = function() return state.quick end }
    KeybindFrames_InQuickKeybindMode = function() return state.quick end
    C_RestrictedActions = { CheckAllowProtectedFunctions = function(frame, silent)
        Check(silent == true, "permission checks must suppress native errors")
        return not state.denied and not frame.denied
    end }
    C_Container = { GetContainerNumSlots = function(bagID) return state.sizes[bagID] end }
    ContainerFrame_GetContainerNumSlots = C_Container.GetContainerNumSlots
    ContainerFrame_AllowedToOpenBags = function() return state.allowed end
    ContainerFrameSettingsManager = {
        IsUsingCombinedBags = function(_, bagID)
            return state.combined and (bagID == nil or bagID >= 0 and bagID <= 4)
        end,
        SetUsingCombinedBags = function() error("combined mode must not be rewritten") end,
        CheckBagSetup = function() end, MarkBagsShownDirty = function() end,
    }
    local nativeManager = ContainerFrameSettingsManager.IsUsingCombinedBags
    GetCVarBool = function(name)
        if name == "combinedBags" then return state.combined end
        return false
    end
    C_CVar = { GetCVarBool = GetCVarBool }
    SetCVar = function() state.cvarWrites = state.cvarWrites + 1; error("unexpected CVar write") end
    C_CVar.SetCVar = SetCVar
    C_Timer = { After = function(_, callback) state.timers[#state.timers + 1] = callback end }
    CreateFrame = function() error("individual bags must reuse native frames") end
    hooksecurefunc = function(object, method, callback)
        if type(object) == "string" then callback, method, object = method, object, _G end
        local original = assert(object[method], "hooked unavailable function " .. tostring(method))
        state.hooks = state.hooks + 1
        object[method] = function(...)
            local result = Pack(original(...))
            callback(...)
            return unpack(result, 1, result.n)
        end
    end
    local function AnyRaw()
        for _, frame in ipairs(raw) do if frame:IsShown() then return true end end
        return false
    end
    function ContainerFrame_GenerateFrame(frame, size, bagID)
        state.generates = state.generates + 1
        if state.generateFailure == "before" then error("injected generation failure") end
        frame.bagID, frame.size = bagID, size
        frame:Show()
        if state.generateFailure == "after" then error("injected partial generation failure") end
        frame:UpdateItemLayout(); frame:Update()
    end
    ContainerFrame_GetOpenFrame = function() error("combined-selecting frame lookup must not be used") end
    ToggleBag_Individual = function() error("native helper still chooses combined frame") end
    function ToggleBackpack()
        if not state.allowed then return end
        if state.combined then
            -- Native combined toggle considers individually shown bags open,
            -- then hides only the combined frame. The module must reconcile.
            if ContainerFrameCombinedBags:IsShown() or AnyRaw() then ContainerFrameCombinedBags:Hide()
            else ContainerFrameCombinedBags:Show() end
        elseif raw[1]:IsShown() then CloseAllBags()
        else ContainerFrame_GenerateFrame(raw[1], state.sizes[0], 0) end
    end
    function ToggleBag(bagID)
        if not state.allowed then return end
        if ContainerFrameSettingsManager:IsUsingCombinedBags(bagID) then ToggleBackpack()
        else
            local frame = bagID == 0 and raw[1] or bagID == 5 and raw[3]
            if not frame then
                for _, candidate in ipairs(raw) do
                    if candidate.role == "normal" and candidate:IsShown() and candidate:GetBagID() == bagID then frame = candidate; break end
                end
                if not frame then
                    for _, candidate in ipairs(raw) do
                        if candidate.role == "normal" and not candidate:IsShown() then frame = candidate; break end
                    end
                end
            end
            assert(frame, "native individual fixture exhausted its pool")
            if frame:IsShown() and frame.bagID == bagID then frame:Hide()
            else ContainerFrame_GenerateFrame(frame, state.sizes[bagID], bagID) end
        end
    end
    function CloseBag(bagID)
        state.closes[#state.closes + 1] = bagID
        if ContainerFrameSettingsManager:IsUsingCombinedBags(bagID) then
            ContainerFrameCombinedBags:Hide()
        else
            for _, frame in ipairs(raw) do if frame.bagID == bagID then frame:Hide() end end
        end
    end
    function CloseBackpack()
        -- Combined-mode dispatch does not discover a separately shown bag 0.
        local frame = state.combined and ContainerFrameCombinedBags or raw[1]
        local wasShown = frame:IsShown()
        frame:Hide()
        return wasShown
    end
    function IsBagOpen(bagID)
        if bagID >= 0 and bagID <= 4 and ContainerFrameCombinedBags:IsShown() then return true end
        for _, frame in ipairs(raw) do
            if frame:IsShown() and frame:GetBagID() == bagID then return true end
        end
        return false
    end
    function IsAnyBagOpen()
        return ContainerFrameCombinedBags:IsShown() or AnyRaw()
    end
    local function OpenAllNative()
        if state.combined then ContainerFrameCombinedBags:Show()
        else ContainerFrame_GenerateFrame(raw[1], state.sizes[0], 0) end
        if state.sizes[5] > 0 then ContainerFrame_GenerateFrame(raw[3], state.sizes[5], 5) end
    end
    function ToggleAllBags()
        if not state.allowed then return end
        local closed, available = 0, 1
        if IsBagOpen(0) then closed = closed + 1; CloseBackpack() end
        -- The verified desktop combined path skips generic bags 1..4.
        if state.sizes[5] > 0 then available = available + 1 end
        if IsBagOpen(5) then closed = closed + 1; CloseBag(5) end
        if closed < available then OpenAllNative(); return end
        state.toggleAssertions = (state.toggleAssertions or 0) + 1
        assert(IsAnyBagOpen() == false, "native ToggleAllBags close invariant failed")
        if EventRegistry then EventRegistry:TriggerEvent("ContainerFrame.CloseAllBags") end
    end
    function CloseAllBags(owner, forceUpdate)
        state.closeAllCalls = state.closeAllCalls + 1
        if owner and owner:GetName() ~= state.nativeOpener then
            if forceUpdate then state.updates = state.updates + 1 end
            return false
        end
        CloseBackpack()
        for bagID = 1, 5 do CloseBag(bagID) end
        if EventRegistry then EventRegistry:TriggerEvent("ContainerFrame.CloseAllBags") end
        return true
    end
    function ContainerFrame_UpdateAll()
        for _, frame in ipairs(raw) do if frame:IsShown() then frame:Update() end end
    end
    function UpdateContainerFrameAnchors()
        for _, frame in ipairs(raw) do if frame:IsShown() then frame:UpdateItemLayout() end end
    end
    local buttons, nativeScripts = {}, {}
    for bagID = 0, 5 do
        local name = bagID == 0 and "MainMenuBarBackpackButton"
            or bagID == 5 and "CharacterReagentBag0Slot" or "CharacterBag" .. (bagID - 1) .. "Slot"
        local button = Frame(name, bagID)
        button.scripts.OnClick = function(self, mouseButton, down, ...)
            state.clicks[#state.clicks + 1] = { button = self, mouseButton = mouseButton,
                down = down, extra = Pack(...), cursor = state.cursor }
            if mouseButton == "LeftButton" and not down and not state.cursor then ToggleBag(self:GetBagID()) end
            return "native-result", self.bagID
        end
        for _, script in ipairs({ "OnDragStart", "OnReceiveDrag", "OnEnter", "OnLeave" }) do
            button.scripts[script] = function() state[script] = (state[script] or 0) + 1 end
        end
        nativeScripts[button] = {}
        for event, callback in pairs(button.scripts) do nativeScripts[button][event] = callback end
        _G[name], buttons[bagID] = button, button
    end
    KeyRingButton = nil
    local addon = { reports = state.reports,
        IsPublic = function(value) return not rawequal(value, restricted) end,
        Print = function(_, message) state.reports[#state.reports + 1] = message end,
        ReportOnce = function(_, key, message) state.reports[key] = message end,
    }
    addon.IsFiniteNumber = function(value)
        return addon.IsPublic(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    addon.Colors = { Refresh = function() end }
    if options.configure then options.configure(state, raw, buttons, addon) end
    assert(loadfile(source))("ForTheHoard", addon)
    addon.IndividualBags:Initialize()
    local function Flush()
        local pending = state.timers; state.timers = {}
        for _, callback in ipairs(pending) do callback() end
    end
    local function Solo(bagID)
        local count, selected = 0
        for _, frame in ipairs(raw) do
            if frame:IsShown() then count, selected = count + 1, frame end
        end
        Check(count == 1 and selected.bagID == bagID, "expected only selected individual bag " .. bagID)
        Check(not ContainerFrameCombinedBags:IsShown(), "combined frame remained open with solo bag")
        return selected
    end
    local function Closed()
        for _, frame in ipairs(raw) do Check(not frame:IsShown(), "owned individual bag remained shown") end
    end
    local function Opened(ids)
        local expected, selected, count = {}, {}, 0
        for _, id in ipairs(ids) do expected[id] = true end
        for _, frame in ipairs(raw) do
            if frame:IsShown() then
                count = count + 1
                Check(expected[frame.bagID] == true and not selected[frame.bagID], "unexpected or duplicate individual bag")
                selected[frame.bagID] = frame
            end
        end
        Check(count == #ids, "individual open count differed from requested bags")
        for _, id in ipairs(ids) do Check(selected[id] ~= nil, "selected bag missing: " .. id) end
        Check(not ContainerFrameCombinedBags:IsShown(), "combined frame remained open with selected bags")
        return selected
    end
    local function NativeIntact()
        Check(ContainerFrameSettingsManager.IsUsingCombinedBags == nativeManager, "manager was monkeypatched")
        Check(state.cvarWrites == 0, "combined setting was rewritten")
        for button, scripts in pairs(nativeScripts) do
            for _, event in ipairs({ "OnDragStart", "OnReceiveDrag", "OnEnter", "OnLeave" }) do
                Check(button:GetScript(event) == scripts[event], "native " .. event .. " was replaced")
            end
        end
    end
    return addon.IndividualBags, state, buttons, raw, Flush, Solo, Closed, NativeIntact, Opened
end

-- Toggle All counts the separately shown backpack as open, but native
-- CloseBackpack targets combined UI. Correct it before the native assertion.
for _, reagentPresent in ipairs({ false, true }) do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    state.sizes[5] = reagentPresent and 10 or 0
    Check(module:OpenBag(0), "selected backpack did not open")
    solo(0)
    local ok, detail = pcall(ToggleAllBags)
    Check(ok, "toggle-all failed from selected backpack: " .. tostring(detail))
    flush()
    if reagentPresent then
        Check(ContainerFrameCombinedBags:IsShown() and raw[3]:IsShown(),
            "toggle-all from partial bags did not open combined and reagent views")
        Check(not raw[1]:IsShown() and not raw[2]:IsShown(), "toggle-all left a solo view open")
        ok, detail = pcall(ToggleAllBags)
        Check(ok, "toggle-all failed closing combined and reagent views: " .. tostring(detail))
        flush(); closed()
    else
        closed()
    end
    Check(not IsAnyBagOpen(), "toggle-all close left a native bag open")
    Check((state.toggleAssertions or 0) > 0, "fixture did not exercise the native close assertion")
    ToggleAllBags(); flush()
    Check(ContainerFrameCombinedBags:IsShown(), "toggle-all did not reopen combined bags")
    Check(raw[3]:IsShown() == reagentPresent, "reagent view ignored equipped capacity")
    ToggleAllBags(); flush(); closed()
    Check(not ContainerFrameCombinedBags:IsShown(), "toggle-all did not close combined bags")
    Check(module:OpenBag(1), "selected ordinary bag did not reopen")
    CloseBackpack(); flush(); solo(1)
    intact()
end

-- Native bag frames can be unprotected: close those safely on combat entry
-- before the native Toggle All path can observe a leftover selected backpack.
do
    local module, state, buttons, raw, flush, solo, closed = Setup()
    state.sizes[5], raw[1].protected = 0, false
    module:OpenBag(0); solo(0)
    state.combat = true
    module:OnEvent("PLAYER_REGEN_DISABLED"); flush(); closed()
    local ok, detail = pcall(ToggleAllBags)
    Check(ok, "combat Toggle All retained the selected-backpack invariant failure: " .. tostring(detail))
    Check(ContainerFrameCombinedBags:IsShown(), "combat Toggle All did not retain native opening")
end
for _, restriction in ipairs({ "protected", "unknown", "restricted", "denied" }) do
    local module, state, buttons, raw, flush, solo, closed = Setup()
    module:OpenBag(0); solo(0)
    if restriction == "protected" then raw[1].protected = true
    elseif restriction == "restricted" then raw[1].protected = restricted
    elseif restriction == "denied" then raw[1].protected = false; state.denied = true end
    state.combat = true
    module:OnEvent("PLAYER_REGEN_DISABLED")
    Check(raw[1]:IsShown(), "combat cleanup ignored " .. restriction .. " frame state")
    state.combat, state.denied = false, false
    module:OnEvent("PLAYER_REGEN_ENABLED"); flush(); closed()
end

-- The narrow gesture selects one bag; normal clicks then restore combined UI.
do
    local module, state, buttons, raw, flush, solo, closed, intact = Setup()
    for bagID = 0, 5 do
        state.shift = true
        local before = #state.clicks
        buttons[bagID]:Fire("OnClick", "LeftButton", false)
        flush()
        solo(bagID)
        Check(#state.clicks == before, "handled Shift click reached native all-bags behavior")
        buttons[bagID]:Fire("OnClick", "LeftButton", false)
        flush(); closed()
    end
    state.shift = true; buttons[2]:Fire("OnClick", "LeftButton", false); solo(2)
    state.shift = false
    local a, b = buttons[2]:Fire("OnClick", "LeftButton", false, "retained argument")
    flush(); closed()
    Check(ContainerFrameCombinedBags:IsShown(), "normal click failed to open combined bags")
    Check(a == "native-result" and b == 2, "native click return values were lost")
    Check(state.clicks[#state.clicks].extra[1] == "retained argument", "native arguments were changed")
    intact()
end

-- Cursor placement, right clicks, other modifiers, quickbind and mouse-down
-- must delegate exactly once without replacing inherited interactions.
do
    local module, state, buttons, raw, flush, solo, closed, intact = Setup()
    local function Delegated(mouse, down)
        local previous = #state.clicks
        local previousCursor = state.cursor
        buttons[1]:Fire("OnClick", mouse, down, "tail")
        flush()
        Check(#state.clicks == previous + 1, "ordinary input was not delegated exactly once")
        Check(state.clicks[#state.clicks].cursor == previousCursor, "addon changed user cursor before native delegation")
    end
    state.shift, state.cursor = true, { "item", 2318, "link" }
    Delegated("LeftButton", false); closed()
    state.cursor = nil
    Delegated("RightButton", false); closed()
    Delegated("LeftButton", true); closed()
    state.control = true; Delegated("LeftButton", false); closed(); ContainerFrameCombinedBags:Hide()
    state.control, state.alt = false, true
    Delegated("LeftButton", false); closed(); ContainerFrameCombinedBags:Hide()
    state.alt, state.quick = false, true
    Delegated("LeftButton", false); closed()
    for _, event in ipairs({ "OnDragStart", "OnReceiveDrag", "OnEnter", "OnLeave" }) do
        buttons[1]:Fire(event)
        Check(state[event] == 1, "inherited " .. event .. " did not run")
    end
    intact()
end

-- Shift opens any subset in any order. Existing selected windows retain their
-- frames, and repeating one Shift click toggles only that physical bag.
for _, order in ipairs({ { 0, 1, 2, 3, 4, 5 }, { 5, 4, 3, 2, 1, 0 }, { 3, 0, 5, 1, 4, 2 } }) do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    ContainerFrameCombinedBags:Show()
    state.shift = true
    local ids, retained = {}, {}
    for _, id in ipairs(order) do
        buttons[id]:Fire("OnClick", "LeftButton", false)
        flush()
        ids[#ids + 1] = id
        local visible = opened(ids)
        for previous, frame in pairs(retained) do Check(visible[previous] == frame, "opening one bag replaced another selected frame") end
        retained[id] = visible[id]
        Check(module:GetOwnedFrame(id) == visible[id], "owned lookup did not match visible physical bag")
    end
    Check(#state.clicks == 0 and state.closeAllCalls == 0, "selected opens invoked native Shift or Close All")
    local generations = state.generates
    buttons[2]:Fire("OnClick", "LeftButton", false); flush()
    local remaining = opened({ 0, 1, 3, 4, 5 })
    Check(module:GetOwnedFrame(2) == nil and state.generates == generations, "selected close regenerated or retained its bag")
    for id, frame in pairs(remaining) do Check(frame == retained[id], "selected toggle changed another frame") end
    buttons[2]:Fire("OnClick", "LeftButton", false); flush()
    opened({ 0, 1, 2, 3, 4, 5 })
    state.shift = false
    local first, second = buttons[4]:Fire("OnClick", "LeftButton", false, "multi tail")
    flush(); closed()
    Check(ContainerFrameCombinedBags:IsShown(), "normal click did not return multiple selected bags to combined UI")
    Check(first == "native-result" and second == 4 and #state.clicks == 1, "normal input delegation changed after multiple selection")
    Check(state.clicks[1].extra[1] == "multi tail", "multiple selection lost native click arguments")
    Check(state.closeAllCalls == 0, "normal selection cleanup invoked native Close All")
    intact()
end

-- Close All's native invariant must also hold with several carried windows.
-- Reagent bag 5 remains available for native Toggle All to count separately.
for _, reagentPresent in ipairs({ false, true }) do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    state.sizes[5] = reagentPresent and 10 or 0
    module:OpenBag(0); module:OpenBag(1)
    if reagentPresent then module:OpenBag(5); opened({ 0, 1, 5 }) else opened({ 0, 1 }) end
    local ok, detail = pcall(ToggleAllBags)
    Check(ok, "native toggle-all failed from multiple selected bags: " .. tostring(detail))
    flush(); closed()
    Check(not IsAnyBagOpen(), "native toggle-all left selected views after a complete close")
    Check((state.toggleAssertions or 0) > 0, "multiple selected views bypassed native close assertion")
    ToggleAllBags(); flush()
    Check(ContainerFrameCombinedBags:IsShown() and raw[3]:IsShown() == reagentPresent, "native all-bag reopening was altered")
    ToggleAllBags(); flush(); closed()
    intact()
end

-- Shift selection also works when native individual mode is preferred. Normal
-- clicks and keyboard backpack toggles then keep their individual native scope.
for _, order in ipairs({ { 1, 2, 0, 5, 3, 4 }, { 4, 5, 3, 0, 2, 1 } }) do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    state.combined, state.shift = false, true
    local ids = {}
    for _, id in ipairs(order) do
        buttons[id]:Fire("OnClick", "LeftButton", false); flush()
        ids[#ids + 1] = id
        opened(ids)
    end
    Check(#state.clicks == 0 and state.closeAllCalls == 0, "native individual preference bypassed Shift selection")
    state.shift = false
    buttons[1]:Fire("OnClick", "LeftButton", false); flush()
    opened({ 0, 2, 3, 4, 5 })
    Check(#state.clicks == 1 and module:GetOwnedFrame(1) == nil, "normal individual click did not toggle its native bag")
    ToggleBackpack(); flush(); closed()
    Check(state.closeAllCalls == 1, "native individual keyboard backpack did not retain its real Close All behavior")
    intact()
end

-- Native reagent-capable frames also accept ordinary bag IDs. Prefer a later
-- free generic frame so selecting a normal bag does not consume the only frame
-- capable of showing reagent bag 5.
do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    ContainerFrame_GenerateFrame(raw[2], state.sizes[3], 3)
    Check(module:OpenBag(1), "normal bag could not open with earlier generic frame occupied")
    Check(module:GetOwnedFrame(1) == raw[4], "normal bag consumed reagent-capable frame before a free generic candidate")
    Check(module:OpenBag(5) and module:GetOwnedFrame(5) == raw[3], "later reagent bag lost its capable native frame")
    opened({ 1, 3, 5 })
    module:CloseSolo()
    Check(raw[2]:IsShown() and raw[2]:GetBagID() == 3, "candidate preference changed an unowned native bag")
    intact()
end

-- Combined UI can coexist with native reagent storage. Shift from that state
-- closes combined and keeps the selected view open; only a later repeat toggles
-- it closed. Other native individual views remain outside owned cleanup.
for _, previouslyOwned in ipairs({ false, true }) do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    if previouslyOwned then module:OpenBag(5)
    else ContainerFrame_GenerateFrame(raw[3], state.sizes[5], 5) end
    ContainerFrame_GenerateFrame(raw[2], state.sizes[2], 2)
    -- A real temporary restriction can defer the combined OnShow cleanup for
    -- an already owned selected view. Permission recovers before this gesture.
    state.denied = previouslyOwned
    ContainerFrameCombinedBags:Show()
    Check(raw[3]:IsShown() and raw[2]:IsShown(), "fixture did not retain concurrent native views")
    state.denied, state.shift = false, true
    local generations, closes = state.generates, state.closeAllCalls
    buttons[5]:Fire("OnClick", "LeftButton", false); flush()
    local visible = opened({ 2, 5 })
    Check(visible[5] == raw[3] and visible[2] == raw[2], "combined transition replaced or closed an existing individual view")
    Check(module:GetOwnedFrame(5) == raw[3] and module:GetOwnedFrame(2) == nil, "combined transition adopted an unrelated native view")
    Check(state.generates == generations and state.closeAllCalls == closes and #state.clicks == 0,
        "combined transition regenerated selected storage or invoked native Shift/Close All")
    module:Refresh(); flush(); opened({ 2, 5 })
    buttons[5]:Fire("OnClick", "LeftButton", false); flush(); solo(2)
    Check(module:GetOwnedFrame(5) == nil, "repeated Shift did not close just the selected view")
    intact()
end

-- Adopting a shown pooled frame under its new physical ID must remove its old
-- bag alias. Looking up the old ID cannot then erase the new owned record.
do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    module:OpenBag(1)
    local selected = solo(1)
    state.denied = true
    ContainerFrameCombinedBags:Show()
    selected.bagID = 3
    state.denied, state.shift = false, true
    buttons[3]:Fire("OnClick", "LeftButton", false); flush(); solo(3)
    Check(module:GetOwnedFrame(1) == nil, "old physical ID retained a shown-frame alias")
    Check(module:GetOwnedFrame(3) == selected, "stale lookup erased the newly adopted bag ownership")
    module:CloseSolo(); closed()
    intact()
end

-- Explicit closes affect only matching owned windows; native windows which
-- were already open before selection remain outside the module's ownership.
for _, noRegistry in ipairs({ false, true }) do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup({ noRegistry = noRegistry })
    module:OpenBag(1); module:OpenBag(2); module:OpenBag(5)
    local visible = opened({ 1, 2, 5 })
    CloseBag(1); flush(); opened({ 2, 5 })
    visible[2]:OnCloseClicked(); flush(); solo(5)
    CloseBackpack(); flush(); solo(5)
    local unrelated = { GetName = function() return "UnrelatedPanel" end }
    CloseAllBags(unrelated, true); flush(); solo(5)
    Check(state.updates == 1, "rejected native close lost its force-update behavior")
    CloseAllBags(); flush(); closed()
    ContainerFrame_GenerateFrame(raw[3], state.sizes[5], 5)
    module:OpenBag(1); opened({ 1, 5 })
    module:CloseSolo(); flush(); solo(5)
    Check(module:GetOwnedFrame(5) == nil, "preexisting native reagent view was adopted without a gesture")
    raw[3]:Hide()
    intact()
end

-- Close ownership follows actual native closures; unrelated panel dismissal
-- is not permission to close the selected bag.
for _, noRegistry in ipairs({ false, true }) do
    local module, state, buttons, raw, flush, solo, closed = Setup({ noRegistry = noRegistry })
    Check(module:OpenBag(1), "direct selected open failed")
    local selected = solo(1)
    local unrelated = { GetName = function() return "UnrelatedPanel" end }
    CloseAllBags(unrelated, true); flush(); solo(1)
    Check(state.updates == 1, "unrelated force-update did not retain its native behavior")
    CloseBag(2); flush(); solo(1)
    selected:OnCloseClicked(); flush(); closed()
    module:OpenBag(1); solo(1)
    CloseAllBags(); flush(); closed()
    module:OpenBag(2); solo(2)
    ContainerFrameCombinedBags:Show(); flush(); closed()
    ContainerFrameCombinedBags:Hide()
    module:OpenBag(1); solo(1)
    ToggleBackpack(); flush(); closed()
end

-- Refreshing hooks and relayouts reuses the pool and preserves native content.
do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    local initialWrapper, initialHooks = buttons[1]:GetScript("OnClick"), state.hooks
    local nativeUpdate, nativeLayout = raw[2].Update, raw[2].UpdateItemLayout
    for _ = 1, 15 do module:Refresh() end
    Check(buttons[1]:GetScript("OnClick") == initialWrapper and state.hooks == initialHooks,
        "refresh stacked input wrappers or hooks")
    module:OpenBag(1); local selected = solo(1)
    local updates, layouts = selected.contentUpdates, selected.layouts
    ContainerFrame_UpdateAll(); UpdateContainerFrameAnchors()
    Check(selected.contentUpdates == updates + 1 and selected.layouts == layouts + 1,
        "native data updates or relayout were intercepted")
    Check(raw[2].Update == nativeUpdate and raw[2].UpdateItemLayout == nativeLayout,
        "native update implementation was replaced")
    module:OpenBag(2)
    local together = opened({ 1, 2 })
    Check(together[1] == selected and together[2] ~= selected, "opening another normal bag replaced the first view")
    for _ = 1, 15 do module:CloseSolo(); module:OpenBag(1) end
    Check(solo(1) == selected, "repeated opening failed to reuse native frame")
    intact()
end

-- Unknown, protected and non-desktop paths do not start a solo session.
do
    local module, state, buttons, raw, flush, solo, closed = Setup()
    state.combined = false; state.shift = true
    local before = #state.clicks
    buttons[1]:Fire("OnClick", "LeftButton", false); flush()
    Check(#state.clicks == before, "Shift click in native individual mode was not handled")
    solo(1); module:CloseSolo(); closed()
    state.combined, state.combat = true, true
    Check(not module:OpenBag(1), "combat allowed individual opening"); closed()
    state.combat, state.denied = false, true
    Check(not module:OpenBag(1), "native permission denial was ignored"); closed()
    state.denied, state.gamepad = false, true
    Check(not module:OpenBag(1), "gamepad UI used desktop override"); closed()
    state.gamepad, state.allowed = false, false
    Check(not module:OpenBag(1), "native panel permission was ignored"); closed()
    state.allowed = true
    for _, bagID in ipairs({ -100, 6, 1.5, restricted }) do
        Check(not module:OpenBag(bagID), "invalid/restricted bag ID was used"); closed()
    end
    state.sizes[1] = restricted
    Check(not module:OpenBag(1), "restricted bag capacity was used"); closed()
    state.sizes[1] = 8; state.gamepad = restricted
    Check(not module:OpenBag(1), "unknown input mode allowed opening"); closed()
end

-- Missing pool metadata can use named frames; generation failure must not
-- leave a half-open solo frame or re-enter native Shift/all-bag behavior.
for _, failure in ipairs({ "before", "after" }) do
    local module, state, buttons, raw, flush, solo, closed = Setup({ namedFallback = true })
    state.generateFailure, state.shift = failure, true
    local ok = pcall(function() buttons[1]:Fire("OnClick", "LeftButton", false) end)
    flush()
    Check(ok, "native generation failure escaped the gesture boundary")
    closed()
    Check(#state.clicks == 0, "failed generation fell through to native Shift behavior")
    Check(next(state.reports) ~= nil, "native generation failure was swallowed")
    state.generateFailure = nil
    Check(module:OpenBag(1), "generation did not recover on a later explicit attempt")
    solo(1)
end

-- A failed additional generation consumes only that gesture and rolls back
-- its candidate frame. Previously opened selected bags remain available.
for _, failure in ipairs({ "before", "after" }) do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup({ namedFallback = true })
    module:OpenBag(1)
    local first = solo(1)
    state.generateFailure, state.shift = failure, true
    local ok = pcall(function() buttons[2]:Fire("OnClick", "LeftButton", false) end)
    flush()
    Check(ok and #state.clicks == 0, "failed additional open escaped or reached native Shift behavior")
    Check(solo(1) == first and module:GetOwnedFrame(1) == first, "failed additional open discarded an existing selected bag")
    Check(module:GetOwnedFrame(2) == nil and next(state.reports) ~= nil, "failed additional open stayed owned or lost diagnostic")
    state.generateFailure = nil
    Check(module:OpenBag(2), "additional open could not recover on explicit retry")
    opened({ 1, 2 })
    Check(state.closeAllCalls == 0, "additional generation used global Close All")
    intact()
end

-- Lifecycle cleanup is per owned identity. One protected or repurposed frame
-- cannot cause the other owned windows to be lost or somebody else's view hidden.
do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    module:OpenBag(0); module:OpenBag(1); module:OpenBag(2); module:OpenBag(5)
    local visible = opened({ 0, 1, 2, 5 })
    module:OnEvent("BAG_CLOSED", 1); opened({ 0, 2, 5 })
    state.sizes[2] = state.sizes[2] + 4
    module:OnEvent("BAG_UPDATE_DELAYED"); opened({ 0, 5 })
    module:OpenBag(1); module:OpenBag(2)
    visible = opened({ 0, 1, 2, 5 })
    for _, frame in pairs(visible) do frame.protected = false end
    visible[1].protected = true
    state.combat = true
    module:OnEvent("PLAYER_REGEN_DISABLED"); flush(); solo(1)
    Check(module:GetOwnedFrame(1) == visible[1], "deferred combat close lost protected ownership")
    state.combat, state.denied = false, true
    module:OnEvent("PLAYER_REGEN_ENABLED"); solo(1)
    state.denied = false
    module:OnEvent("ADDON_RESTRICTION_STATE_CHANGED"); flush(); closed()
    module:OpenBag(1); module:OpenBag(2)
    visible = opened({ 1, 2 })
    visible[1].bagID = 4
    module:CloseOwnedBag(1)
    Check(visible[1]:IsShown() and visible[2]:IsShown(), "per-bag cleanup hid a repurposed or unrelated frame")
    Check(module:GetOwnedFrame(1) == nil and module:GetOwnedFrame(2) == visible[2], "repurposed ownership was not pruned independently")
    module:CloseSolo()
    Check(visible[1]:IsShown() and not visible[2]:IsShown(), "global owned cleanup crossed native pooled ownership")
    intact()
end

-- Native combined display, keyboard toggle and mode changes clear the full
-- owned set, retaining native input behavior and a reusable frame pool.
for _, transition in ipairs({ "combined", "keyboard", "gamepad" }) do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    module:OpenBag(1); module:OpenBag(2); module:OpenBag(5); opened({ 1, 2, 5 })
    if transition == "combined" then ContainerFrameCombinedBags:Show()
    elseif transition == "keyboard" then ToggleBackpack()
    elseif transition == "gamepad" then state.gamepad = true; module:OnEvent("INPUT_DEVICE_INTERFACE_TRANSITION") end
    flush(); closed()
    for _, id in ipairs({ 1, 2, 5 }) do Check(module:GetOwnedFrame(id) == nil, "transition left stale bag ownership") end
    intact()
end

-- An unreadable pooled identity cannot produce a second copy of the same bag.
-- A temporarily rejected selected close retries only that bag after recovery.
for _, obstruction in ipairs({ "identity", "hide" }) do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    module:OpenBag(1); module:OpenBag(2)
    local visible, failing = opened({ 1, 2 }), true
    local selected = visible[1]
    if obstruction == "identity" then selected.bagID = restricted
    else
        selected.Hide = function(self)
            if failing then error("injected selected close failure") end
            return methods.Hide(self)
        end
    end
    local generations = state.generates
    state.shift = true
    buttons[1]:Fire("OnClick", "LeftButton", false); flush()
    Check(#state.clicks == 0 and state.generates == generations, "unavailable selected close opened a duplicate or invoked native Shift")
    Check(selected:IsShown() and visible[2]:IsShown(), "unavailable selected close affected another visible bag")
    if obstruction == "identity" then
        Check(module:CloseOwnedBag(1) == false, "unknown pooled identity was hidden or forgotten")
        selected.bagID = 1
    end
    failing = false
    module:Refresh(); flush(); solo(2)
    Check(module:GetOwnedFrame(1) == nil and module:GetOwnedFrame(2) == visible[2], "pending selected close crossed bag ownership")
    intact()
end

-- Combat cleanup can close permitted unprotected views while a protected
-- sibling remains pending. Bag-specific events likewise clean only their bag.
do
    local module, state, buttons, raw, flush, solo, closed, intact, opened = Setup()
    module:OpenBag(0); module:OpenBag(1); module:OpenBag(2); module:OpenBag(5)
    local visible = opened({ 0, 1, 2, 5 })
    for _, frame in pairs(visible) do frame.protected = false end
    visible[1].protected = true
    state.combat = true
    module:OnEvent("PLAYER_REGEN_DISABLED"); flush(); solo(1)
    for _, id in ipairs({ 0, 2, 5 }) do Check(module:GetOwnedFrame(id) == nil, "safe combat cleanup retained another selected bag") end
    state.combat, state.denied = false, true
    module:OnEvent("PLAYER_REGEN_ENABLED"); flush(); solo(1)
    state.denied = false
    module:OnEvent("ADDON_RESTRICTION_STATE_CHANGED"); flush(); closed()
    module:OpenBag(1); module:OpenBag(2); module:OpenBag(5)
    module:OnEvent("BAG_CLOSED", 1); flush(); opened({ 2, 5 })
    state.sizes[2] = state.sizes[2] + 1
    module:OnEvent("BAG_UPDATE_DELAYED"); flush(); solo(5)
    module:CloseSolo(); closed()
    intact()
end

-- Lifecycle cleanup respects temporary write restrictions and frame reuse.
do
    local module, state, buttons, raw, flush, solo, closed = Setup()
    module:OpenBag(1); solo(1)
    module:OnEvent("BAG_CLOSED", 2); solo(1)
    state.combat = true
    module:OnEvent("BAG_CLOSED", 1)
    Check(raw[2]:IsShown(), "combat closure wrote to the native frame")
    state.combat, state.denied = false, true
    module:OnEvent("PLAYER_REGEN_ENABLED")
    Check(raw[2]:IsShown(), "pending closure ignored a denied native permission")
    state.denied = false
    module:OnEvent("ADDON_RESTRICTION_STATE_CHANGED"); flush(); closed()
    module:OpenBag(1); solo(1)
    state.gamepad = true
    module:OnEvent("INPUT_DEVICE_INTERFACE_TRANSITION"); flush(); closed()
    state.gamepad = false
    module:OnEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
    module:OpenBag(1); solo(1)
    state.combined = false; module:Refresh(); flush(); solo(1)
    state.combined = true; module:CloseSolo()
    module:Refresh(); module:OpenBag(1); solo(1)
    state.sizes[1] = 12
    module:OnEvent("BAG_UPDATE_DELAYED"); flush(); closed()
    module:OpenBag(1); local selected = solo(1)
    selected.bagID = 3 -- Native code has repurposed the pooled frame.
    module:CloseSolo()
    Check(selected:IsShown(), "cleanup hid a pooled frame now owned by another bag")
    Check(module:OpenBag(2) and selected:IsShown(), "opening another bag hid a pooled frame now owned by native UI")
    Check(module:GetOwnedFrame(2) ~= nil and module:GetOwnedFrame(2) ~= selected, "frame acquisition reused or failed to avoid an unrelated visible bag")
    module:CloseSolo()
    Check(selected:IsShown(), "owned cleanup hid a native repurposed frame")
end

-- Combined-view cleanup must be available before replacing native tray clicks.
-- An explicit rejection or throw may retry the same callback later.
for _, failureKind in ipairs({ "false", "throw" }) do
    local failing, attempts, callback = true, 0, nil
    local module, state, buttons, raw, flush, solo = Setup({ configure = function()
        ContainerFrameCombinedBags.HookScript = function(self, event, current)
            Check(event == "OnShow", "combined setup requested an unrelated script")
            attempts = attempts + 1
            if callback then Check(callback == current, "combined retry replaced callback") end
            callback = current
            if failing then
                if failureKind == "throw" then error("injected native callback rejection") end
                return false
            end
            return methods.HookScript(self, event, current)
        end
    end })
    Check(module.buttons[buttons[1]] == nil and module.combined == nil,
        "failed combined callback replaced native click handling")
    Check(not module:OpenBag(1) and state.generates == 0, "failed combined callback allowed takeover")
    failing = false; module:Refresh()
    Check(attempts == 2 and module.buttons[buttons[1]] ~= nil, "explicit callback failure did not recover")
    Check(module:OpenBag(1), "recovered combined callback did not permit selected opening")
    solo(1)
    for _ = 1, 10 do module:Refresh() end
    Check(attempts == 2 and #ContainerFrameCombinedBags.hooks.OnShow == 1,
        "successful combined callback was reinstalled")
end

-- An uncertain success-shaped result must not be retried or install wrappers,
-- whether the native callback was actually registered or never attached.
for _, resultKind in ipairs({ "nil", "secret", "number", "string" }) do
    for _, registered in ipairs({ false, true }) do
        local attempts = 0
        local module, state, buttons = Setup({ configure = function()
            ContainerFrameCombinedBags.HookScript = function(self, event, callback)
                attempts = attempts + 1
                if registered then methods.HookScript(self, event, callback) end
                if resultKind == "secret" then return restricted end
                if resultKind == "number" then return 0 end
                if resultKind == "string" then return "ok" end
            end
        end })
        for _ = 1, 20 do module:Refresh() end
        Check(attempts == 1 and module.combined == nil and module.buttons[buttons[1]] == nil,
            "unknown combined result claimed readiness or duplicated hooks")
        Check(#(ContainerFrameCombinedBags.hooks.OnShow or {}) == (registered and 1 or 0))
        Check(not module:OpenBag(1) and state.generates == 0)
        Check(state.reports["individual-script-OnShow"] ~= nil, "uncertain callback lacked a diagnostic")
    end
end

-- Selected-frame cleanup is required before hiding combined UI, generating a
-- new window or adopting an already visible native one.
for _, alreadyShown in ipairs({ false, true }) do
    local module, state, buttons, raw, flush, solo = Setup()
    local selected, failing, attempts, callback = raw[2], true, 0, nil
    selected.HookScript = function(self, event, current)
        attempts = attempts + 1
        if callback then Check(callback == current, "selected frame retry replaced callback") end
        callback = current
        if failing then return false end
        return methods.HookScript(self, event, current)
    end
    if alreadyShown then selected:Show() end
    ContainerFrameCombinedBags:Show()
    Check(module:OpenBag(1) and state.generates == 0 and ContainerFrameCombinedBags:IsShown(),
        "failed frame cleanup changed native window state")
    Check(module:GetOwnedFrame(1) == nil and selected:IsShown() == alreadyShown)
    failing = false
    Check(module:OpenBag(1), "selected frame callback did not recover")
    solo(1)
    Check(attempts == 2 and #selected.hooks.OnHide == 1)
    selected:Hide()
    Check(module:GetOwnedFrame(1) == nil, "recovered native hide failed to clear ownership")
end

for _, resultKind in ipairs({ "nil", "secret", "number", "string" }) do
    for _, registered in ipairs({ false, true }) do
        local module, state, buttons, raw = Setup()
        local selected, attempts = raw[2], 0
        selected.HookScript = function(self, event, callback)
            attempts = attempts + 1
            if registered then methods.HookScript(self, event, callback) end
            if resultKind == "secret" then return restricted end
            if resultKind == "number" then return 0 end
            if resultKind == "string" then return "ok" end
        end
        ContainerFrameCombinedBags:Show()
        for _ = 1, 20 do Check(module:OpenBag(1), "unavailable selected view fell through to native Open All") end
        Check(attempts == 1 and state.generates == 0 and module:GetOwnedFrame(1) == nil
            and ContainerFrameCombinedBags:IsShown(), "uncertain frame cleanup took over native state")
        Check(#(selected.hooks.OnHide or {}) == (registered and 1 or 0))
        Check(state.reports["individual-script-OnHide"] ~= nil)
    end
end

-- Verify delegation through the native execution boundary. This fixture checks
-- which function is dispatched and its arguments, not WoW's taint machinery.
do
    local module, state, buttons = Setup()
    local original = module.buttons[buttons[1]].original
    local result, id = buttons[1]:Fire("OnClick", "LeftButton", false, "tail")
    Check(state.secureCalls == 1 and state.secureCallback == original,
        "ordinary bag click bypassed the native execution boundary")
    Check(result == "native-result" and id == 1 and state.clicks[1].extra[1] == "tail",
        "native delegation lost arguments or return values")
end
do
    local module, state = Setup()
    Check(module:OpenBag(2), "separate bag failed to open")
    Check(state.secureCalls == 1 and state.secureCallback == ContainerFrame_GenerateFrame,
        "separate bag initialized native items directly from addon execution")
end
do
    local module, state, buttons = Setup({ configure = function() securecallfunction = nil end })
    Check(next(module.buttons) == nil, "missing execution boundary replaced native bag clicks")
    Check(module:OpenBag(1) == false and state.generates == 0,
        "missing execution boundary allowed insecure native item initialization")
    buttons[1]:Fire("OnClick", "LeftButton", false)
    Check(#state.clicks == 1, "unavailable shortcut prevented native bag interaction")
end

print("individual bags: " .. checks .. " contract checks")
