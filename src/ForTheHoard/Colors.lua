local _, Addon = ...

local Colors = {
    slots = {},
    containers = {},
    icons = {},
    palette = {},
    paletteBuffers = {},
    bankPalette = {},
    bankPaletteBuffers = {},
    bankPositions = {},
    globalHooks = {},
}
Addon.Colors = Colors

local abs, min, max = math.abs, math.min, math.max
local PADDING = 1.5
local EDGE_WIDTH = 1
local SLOT_OUTLINE_PADDING = 2
local SLOT_OUTLINE_WIDTH = 2
local ICON_PADDING = 1
local TOOLBAR_EDGE_WIDTH = 3
local GROUP_PADDING = 2
local GROUP_EDGE_WIDTH = 2
local DIVIDER_CLEARANCE = 1
-- Product guard for an incompatible/foreign bank layout; the measured native
-- correction is 13 units. Never turn an unexpected rectangle into a large resize.
local MAX_BANK_FOOTER_EXTRA = 64
local CONTAINER_METHODS = { "UpdateItemSlots", "UpdateItemLayout", "UpdateItems", "UpdateFrameSize",
    "GenerateItemSlotsForSelectedTab", "RefreshAllItemsForSelectedTab", "UpdateSearchResults", "RefreshBagButtons" }
local ICON_METHODS = { "UpdateTextures", "UpdateBorderAtlases", "UpdateOrientation" }
local BAG_ICONS = {
    { "MainMenuBarBackpackButton", 0, true },
    { "CharacterBag0Slot", 1 },
    { "CharacterBag1Slot", 2 },
    { "CharacterBag2Slot", 3 },
    { "CharacterBag3Slot", 4 },
    { "CharacterReagentBag0Slot", 5 },
    { "KeyRingButton", -1, true },
}

local function Diagnostic(message, detail)
    if Addon.IsPublic(detail) and type(detail) == "string" then
        return message .. " " .. detail:gsub("[\r\n]", " "):sub(1, 180)
    end
    return message
end

local function IsNumber(value)
    return Addon.IsFiniteNumber(value)
end

local function IsBag(value)
    return IsNumber(value) and value % 1 == 0 and (value == -1 or (value >= 0 and value <= 5))
end

local function CanAccessFrame(frame)
    if not Addon.IsPublic(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") then return false end
    if type(frame.IsForbidden) == "function" then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or not Addon.IsPublic(forbidden) or forbidden ~= false then return false end
    end
    if C_RestrictedActions and type(C_RestrictedActions.CheckAllowProtectedFunctions) == "function" then
        local ok, allowed = pcall(C_RestrictedActions.CheckAllowProtectedFunctions, frame, true)
        if not ok or not Addon.IsPublic(allowed) or allowed ~= true then return false end
    end
    return true
end

local function Read(object, method, ...)
    if not CanAccessFrame(object) or type(object[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(object[method], object, ...)
    if ok and Addon.IsPublic(value) then
        return value
    end
end

local function HideSlot(state)
    if state.fill then state.fill:Hide(); state.fillShown = false end
    if state.edges then
        for _, edge in ipairs(state.edges) do edge:Hide() end
    end
end

local function NewEdges(parent, edges, layer, sublevel)
    for i = 1, 4 do
        if not edges[i] then edges[i] = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or -7) end
    end
    return edges
end

local function AnchorEdges(edges, target, padding, width)
    width = width or EDGE_WIDTH
    edges[1]:SetPoint("TOPLEFT", target, "TOPLEFT", -padding, padding)
    edges[1]:SetPoint("TOPRIGHT", target, "TOPRIGHT", padding, padding)
    edges[1]:SetHeight(width)
    edges[2]:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -padding, -padding)
    edges[2]:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", padding, -padding)
    edges[2]:SetHeight(width)
    edges[3]:SetPoint("TOPLEFT", target, "TOPLEFT", -padding, padding)
    edges[3]:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -padding, -padding)
    edges[3]:SetWidth(width)
    edges[4]:SetPoint("TOPRIGHT", target, "TOPRIGHT", padding, padding)
    edges[4]:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", padding, -padding)
    edges[4]:SetWidth(width)
end

local function ShowEdges(edges, color, alpha)
    for _, edge in ipairs(edges) do
        edge:SetColorTexture(color[1], color[2], color[3], alpha)
        edge:Show()
    end
end

local function GetColor(appearance, bag, target, field)
    local colors = appearance[field or "colors"]
    if not Addon.IsPublic(colors) or type(colors) ~= "table" then return nil end
    local color = colors[bag]
    if not Addon.IsPublic(color) or type(color) ~= "table" then return nil end
    local r, g, b = color[1], color[2], color[3]
    if not IsNumber(r) or not IsNumber(g) or not IsNumber(b) then return nil end
    target[1], target[2], target[3] = max(0, min(1, r)), max(0, min(1, g)), max(0, min(1, b))
    return target
end

local function GetAlpha(value, fallback)
    return IsNumber(value) and max(0, min(1, value)) or fallback
end

local BANK_TRACE_LIMIT = 32
local BANK_TRACE_PENDING_LIMIT = 16
local BANK_TRACE_METHODS = { "SetSize", "SetHeight", "SetWidth", "SetScale", "SetParent", "GenerateItemSlotsForSelectedTab" }
local function TraceNumber(value)
    if not Addon.IsPublic(value) then return "secret" end
    if IsNumber(value) then return value end
    if value == nil then return "nil" end
    return type(value) == "number" and "invalid" or type(value)
end
local function TraceReadNumber(frame, method, ...)
    if not Addon.IsPublic(frame) then return "secret" end
    if frame == nil then return "missing" end
    if not CanAccessFrame(frame) then return "denied" end
    if not Addon.IsPublic(frame[method]) then return "secret" end
    if type(frame[method]) ~= "function" then return "missing" end
    local ok, value = pcall(frame[method], frame, ...)
    return ok and TraceNumber(value) or "throw"
end
local function TraceVisibility(frame)
    if not CanAccessFrame(frame) then return "denied" end
    if not Addon.IsPublic(frame.IsVisible) then return "secret" end
    if type(frame.IsVisible) ~= "function" then return "missing" end
    local ok, visible = pcall(frame.IsVisible, frame)
    if not ok then return "throw" end
    if not Addon.IsPublic(visible) then return "secret" end
    if type(visible) == "boolean" then return visible end
    return "invalid"
end
local function TraceScalar(value)
    if not Addon.IsPublic(value) then return "secret" end
    if IsNumber(value) then return string.format("%.6g", value) end
    if value == nil then return "nil" end
    if type(value) == "boolean" then return value and "true" or "false" end
    if type(value) == "string" then return value:gsub("[%c|]", "?"):sub(1, 160) end
    return "object"
end
local function TraceCaller()
    if not Addon.IsPublic(debugstack) then return "secret" end
    if type(debugstack) ~= "function" then return "unavailable" end
    local ok, stack = pcall(debugstack, 3)
    if not ok then return "throw" end
    if not Addon.IsPublic(stack) then return "secret" end
    if type(stack) ~= "string" then return "invalid" end
    stack = stack:sub(1, 2048):gsub(string.char(92), "/")
    local hint, native
    for line in stack:gmatch("[^\r\n]+") do
        local file, number = line:match('(Interface/AddOns/[%w_/%-%.]+%.lua)"%]:(%d+)')
        local path = file and (file .. ":" .. number) or line:match("(Interface/AddOns/[%w_/%-%.]+%.lua:%d+)")
        if path and not path:find("ForTheHoard/Colors.lua", 1, true) then return path:sub(1, 160) end
        if not hint then
            local short, lineNumber = line:match('^%s*%[string "([@%w_/%-%.]+%.lua)"%]:(%d+)')
            if short and (short:sub(1, 1) == "@" or short:sub(1, 3) == "...") then
                local basename = short:match("([%w_%-]+%.lua)$")
                if basename and basename ~= "Colors.lua" then hint = "hint:" .. basename .. ":" .. lineNumber end
            end
        end
        if not hint and line:match("^%s*[%w_/%-%.]+%.lua:%d+") then
            local basename = line:match("([%w_%-]+%.lua:%d+)")
            if basename and not basename:match("^Colors%.lua:") then hint = "hint:" .. basename end
        end
        if line:find("[C]", 1, true) then native = true end
    end
    return hint or (native and "native-C" or "unavailable")
end

function Colors:RecordBankSize(owner, role, event, first, second)
    if not self.bankSizeTraceEnabled then return end
    local trace = self.bankSizeTrace
    if not trace or trace.owner ~= owner or trace.busy then return end
    local visible = TraceVisibility(owner)
    if visible == true and not trace.active then
        trace.session, trace.active, trace.partial = trace.session + 1, true, event == "attach"
        trace.preStored, trace.preDropped = #trace.pending, trace.pendingDropped
        trace.events, trace.dropped, trace.errors = trace.pending, trace.pendingDropped, trace.pendingErrors
        trace.pending, trace.pendingDropped, trace.pendingErrors = {}, 0, 0
    end
    local events = trace.active and trace.events or trace.pending
    local droppedKey, errorsKey = trace.active and "dropped" or "pendingDropped", trace.active and "errors" or "pendingErrors"
    -- The cap precedes all height and stack reads. High-frequency resize calls
    -- after capture cannot keep forcing layout observations or allocating logs.
    local limit = trace.active and BANK_TRACE_LIMIT or BANK_TRACE_PENDING_LIMIT
    if #events >= limit then trace[droppedKey] = trace[droppedKey] + 1; return end
    trace.busy = true
    local ok, entry = pcall(function()
        local footer = self.bankFooter
        return { role = role, event = event, first = TraceNumber(first), second = TraceNumber(second),
            root = TraceReadNumber(owner, "GetHeight", true), panel = TraceReadNumber(trace.panel, "GetHeight", true),
            own = footer and footer.writing == true or false, visible = visible,
            demand = trace.dumping == true, caller = TraceCaller() }
    end)
    trace.busy = nil
    if not ok then
        trace[errorsKey] = trace[errorsKey] + 1
        entry = { role = role, event = event, first = "capture-error", second = "capture-error",
            root = "unavailable", panel = "unavailable", own = false, visible = visible,
            demand = trace.dumping == true, caller = "unavailable" }
    end
    events[#events + 1] = entry
end

function Colors:EnsureBankSizeTrace()
    if not self.bankSizeTraceEnabled then return end
    local owner = BankFrame
    if not CanAccessFrame(owner) then return end
    local panel = owner.BankPanel
    if Addon.IsPublic(panel) and panel == nil then panel = BankPanel end
    local trace = self.bankSizeTrace
    if not trace then
        trace = { targets = {}, events = {}, pending = {}, session = 0, active = false,
            dropped = 0, errors = 0, pendingDropped = 0, pendingErrors = 0 }
        self.bankSizeTrace = trace
    end
    if trace.owner ~= owner then
        trace.owner, trace.active, trace.attached = owner, false, nil
        trace.pending, trace.pendingDropped, trace.pendingErrors = {}, 0, 0
    end
    trace.panel = CanAccessFrame(panel) and panel or nil
    local function Attach(frame, role)
        if not CanAccessFrame(frame) then return end
        local state = trace.targets[frame]
        if not state then
            state = { methods = {}, scripts = {}, callbacks = {}, status = {} }
            trace.targets[frame] = state
        end
        for _, name in ipairs(BANK_TRACE_METHODS) do
            if role == "panel" or name ~= "GenerateItemSlotsForSelectedTab" then
                if not state.callbacks[name] then
                    local eventName = name
                    state.callbacks[name] = function(_, a, b) self:RecordBankSize(owner, role, eventName, a, b) end
                end
                if not state.methods[name] and type(frame[name]) == "function" and type(hooksecurefunc) == "function" then
                    local ok = pcall(hooksecurefunc, frame, name, state.callbacks[name])
                    state.methods[name], state.status[name] = ok or nil, ok and "ok" or "throw"
                end
            end
        end
        for _, name in ipairs({ "OnSizeChanged", "OnShow", "OnHide" }) do
            if not state.callbacks[name] then
                local eventName = name
                state.callbacks[name] = function(_, a, b)
                    if not self.bankSizeTraceEnabled then return end
                    if eventName == "OnHide" and role == "bank" then
                        if trace.owner == owner then trace.active = false end
                    else self:RecordBankSize(owner, role, eventName, a, b) end
                end
            end
            if not state.scripts[name] and state.status[name] ~= "unknown" and type(frame.HookScript) == "function" then
                local ok, result = pcall(frame.HookScript, frame, name, state.callbacks[name])
                if ok and Addon.IsPublic(result) and result == true then state.scripts[name], state.status[name] = true, "ok"
                elseif ok and (not Addon.IsPublic(result) or result ~= false) then state.status[name] = "unknown"
                else state.status[name] = ok and "false" or "throw" end
            end
        end
    end
    Attach(owner, "bank")
    Attach(trace.panel, "panel")
    -- A bounded pending buffer preserves sizing BEFORE native Show. The first
    -- visible callback commits it; the appended OnShow never discards it.
    if not trace.attached then
        trace.attached = true
        self:RecordBankSize(owner, "bank", "attach")
    elseif not trace.active and Read(owner, "IsVisible") == true then self:RecordBankSize(owner, "bank", "visible") end
end

function Colors:StartBankTrace()
    self.bankSizeTraceEnabled, self.bankSizeTraceStarted = true, true
    local trace = self.bankSizeTrace
    if trace then
        -- Keep the retained hook records and callbacks; rearming must not add
        -- another native hook to an object that has already been observed.
        trace.events, trace.pending, trace.session = {}, {}, 0
        trace.active, trace.attached, trace.partial = false, nil, nil
        trace.dropped, trace.errors, trace.pendingDropped, trace.pendingErrors = 0, 0, 0, 0
        trace.preStored, trace.preDropped, trace.dumping, trace.busy = nil, nil, nil, nil
    end
    self:EnsureBankSizeTrace()
    Addon:Print("Bank sizing capture started. Close and reopen the bank, then use /fth banktrace.")
end

function Colors:StopBankTrace()
    self.bankSizeTraceEnabled = false
    if self.bankSizeTrace then self.bankSizeTrace.active = false end
    Addon:Print("Bank sizing capture stopped. /fth banktrace prints the retained capture.")
end

function Colors:PrintBankTrace()
    if not self.bankSizeTraceStarted then
        Addon:Print("Bank sizing capture is off. Use /fth banktrace start before reproducing a sizing problem.")
        return
    end
    local trace = self.bankSizeTrace
    local owner = trace and trace.owner or BankFrame
    local panel = trace and trace.panel
    local movement
    if Addon.IsPublic(Addon.db) and type(Addon.db) == "table" and Addon.IsPublic(Addon.db.movement)
        and type(Addon.db.movement) == "table" then movement = Addon.db.movement.enabled end
    local lines, current = {}, {}
    local function Current(frame, role)
        local rect = "missing"
        if CanAccessFrame(frame) and type(frame.GetRect) == "function" then
            local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
            rect = ok and (TraceScalar(TraceNumber(left)) .. "," .. TraceScalar(TraceNumber(bottom)) .. ","
                .. TraceScalar(TraceNumber(width)) .. "," .. TraceScalar(TraceNumber(height))) or "throw"
        end
        current[#current + 1] = role .. " now normal=" .. TraceScalar(TraceReadNumber(frame, "GetHeight"))
            .. " explicit=" .. TraceScalar(TraceReadNumber(frame, "GetHeight", true)) .. " rect=" .. rect
            .. " scale=" .. TraceScalar(TraceReadNumber(frame, "GetScale"))
            .. " effective=" .. TraceScalar(TraceReadNumber(frame, "GetEffectiveScale"))
    end
    local wasDumping = trace and trace.dumping
    if trace then trace.dumping = true end
    local currentOK = pcall(function() Current(owner, "bank"); Current(panel, "panel") end)
    if trace then trace.dumping = wasDumping end
    if not currentOK then current[#current + 1] = "current snapshot unavailable" end
    local pending = trace and trace.session == 0
    local events = trace and (pending and trace.pending or trace.events) or {}
    lines[#lines + 1] = "banktrace v=" .. TraceScalar(Addon.version) .. " session=" .. TraceScalar(trace and trace.session or 0)
        .. " enabled=" .. TraceScalar(self.bankSizeTraceEnabled == true)
        .. " active=" .. TraceScalar(trace and trace.active or false) .. " partial=" .. TraceScalar(trace and trace.partial or false)
        .. " stored=" .. #events .. " dropped=" .. TraceScalar(trace and (pending and trace.pendingDropped or trace.dropped) or 0)
        .. " preStored=" .. TraceScalar(trace and (pending and #trace.pending or trace.preStored) or 0)
        .. " preDropped=" .. TraceScalar(trace and (pending and trace.pendingDropped or trace.preDropped) or 0)
        .. " errors=" .. TraceScalar(trace and (pending and trace.pendingErrors or trace.errors) or 0)
        .. " pending=" .. TraceScalar(trace and #trace.pending or 0)
        .. " pendingDropped=" .. TraceScalar(trace and trace.pendingDropped or 0) .. " movement=" .. TraceScalar(movement)
    for _, line in ipairs(current) do lines[#lines + 1] = line end
    local function Coverage(frame, role)
        local state = trace and trace.targets[frame]
        local fields = {}
        for _, name in ipairs({ "SetSize", "SetHeight", "SetWidth", "SetScale", "SetParent", "GenerateItemSlotsForSelectedTab", "OnSizeChanged", "OnShow", "OnHide" }) do
            if role == "panel" or name ~= "GenerateItemSlotsForSelectedTab" then
                fields[#fields + 1] = name .. ":" .. (state and state.status[name] or "missing")
            end
        end
        lines[#lines + 1] = role .. " hooks " .. table.concat(fields, " ")
    end
    Coverage(owner, "bank"); Coverage(panel, "panel")
    for index, entry in ipairs(events) do
        lines[#lines + 1] = index .. " " .. entry.role .. "." .. entry.event .. " args=" .. TraceScalar(entry.first) .. "," .. TraceScalar(entry.second)
            .. " H=" .. TraceScalar(entry.root) .. "/" .. TraceScalar(entry.panel) .. " own=" .. TraceScalar(entry.own)
            .. " visible=" .. TraceScalar(entry.visible) .. " dump=" .. TraceScalar(entry.demand)
            .. " callerHint=" .. TraceScalar(entry.caller)
    end
    for _, line in ipairs(lines) do Addon:Print(line) end
end

function Colors:RequestRefresh(settled)
    if self.refreshing then return end
    self.bankFooterSettleQueued = settled == true
    if not self.driverReady then self:EnsureDriver() end
    if not self.globalHooks.generate then self:EnsureGenerateHook() end
    if self.driverReady then self.driver:Show() end
end

function Colors:HookMethod(object, method, callback, recorded)
    if recorded[method] then return end
    if not CanAccessFrame(object) then return end
    if type(object[method]) ~= "function" then return end
    if type(hooksecurefunc) ~= "function" then return end
    local ok, detail = pcall(hooksecurefunc, object, method, callback)
    if ok then
        recorded[method] = true
    else
        Addon:ReportOnce("colors-hook-" .. method, Diagnostic("Bag colors could not attach to a native inventory update.", detail))
    end
end

function Colors:HookScript(object, script, callback, recorded)
    if recorded[script] then return end
    local unknown = self.scriptHookUnknown and self.scriptHookUnknown[object]
    if unknown and unknown[script] then return end
    if not CanAccessFrame(object) or type(object.HookScript) ~= "function" then return end
    local ok, detail = pcall(object.HookScript, object, script, callback)
    if ok and Addon.IsPublic(detail) and detail == true then
        recorded[script] = true
    else
        -- Only an explicit false is a known rejected installation. Uncertain
        -- returns may have attached the callback, so do not duplicate it.
        if ok and (not Addon.IsPublic(detail) or detail ~= false) then
            self.scriptHookUnknown = self.scriptHookUnknown or {}
            unknown = unknown or {}
            self.scriptHookUnknown[object], unknown[script] = unknown, true
        end
        Addon:ReportOnce("colors-script-" .. script, Diagnostic("Bag colors could not attach to native inventory visibility.", detail))
    end
end

function Colors:WatchContainer(container)
    if not CanAccessFrame(container) then return nil end
    local state = self.containers[container]
    if not state then
        state = { hooks = {}, scripts = {}, groups = {} }
        self.containers[container] = state
        state.refresh = function() self:RequestRefresh() end
        state.hide = function()
            for _, group in ipairs(state.groups) do group:Hide() end
            for button, slot in pairs(self.slots) do
                if slot.container == container then HideSlot(slot) end
            end
            if self.bankDivider and self.bankDivider.owner == container then self:RestoreBankDivider() end
            self:RequestRefresh()
        end
    end
    for _, method in ipairs(CONTAINER_METHODS) do
        local callback = state.refresh
        if method == "GenerateItemSlotsForSelectedTab" and type(container[method]) == "function" then
            if not state.generate then
                state.generate = function()
                    self:BankFooterLayoutGenerated(container)
                    self:RequestRefresh()
                end
            end
            callback = state.generate
        end
        self:HookMethod(container, method, callback, state.hooks)
    end
    self:HookScript(container, "OnShow", state.refresh, state.scripts)
    self:HookScript(container, "OnHide", state.hide, state.scripts)
    return state
end

local function InvalidateRaisedTint(button, hasItem)
    if not Addon.IsPublic(button) then return end
    local state = Colors.slots[button]
    if not state or not state.fillRaised or not state.fillShown then return end
    -- SetHasItem runs before native occupied artwork is installed. Repeated
    -- empty cooldown updates need no invalidation or additional redraw work.
    if Addon.IsPublic(hasItem) and (hasItem == nil or hasItem == false) then return end
    if state.fill then state.fill:Hide(); state.fillShown = false end
    Colors:RequestRefresh()
end

function Colors:WatchSlot(button, container, initializer)
    if not CanAccessFrame(button) then return nil end
    local state = self.slots[button]
    if not state then
        state = { hooks = {}, scripts = {} }
        self.slots[button] = state
        state.initialize = function()
            -- The pool can give this button a different bag and slot next time.
            state.matchesSearch = nil
            HideSlot(state)
            self:RequestRefresh()
        end
        state.search = function(_, matches)
            if Addon.IsPublic(matches) and type(matches) == "boolean" then
                state.matchesSearch = matches
            else
                state.matchesSearch = nil
            end
            self:RequestRefresh()
        end
        state.hide = function()
            HideSlot(state)
            self:RequestRefresh()
        end
    end
    self:HookMethod(button, initializer or "Initialize", state.initialize, state.hooks)
    self:HookMethod(button, "SetHasItem", InvalidateRaisedTint, state.hooks)
    self:HookMethod(button, "SetMatchesSearch", state.search, state.hooks)
    self:HookScript(button, "OnHide", state.hide, state.scripts)
    state.container = container
    state.bank = initializer == "Init"
    return state
end

function Colors:RefreshBankPalette(appearance)
    for id in pairs(self.bankPositions) do self.bankPositions[id] = nil end
    for position = 1, 9 do self.bankPalette[position] = nil end
    local indices = Enum and Enum.BagIndex
    if not Addon.IsPublic(indices) or type(indices) ~= "table" then return end
    for position = 1, 9 do
        local id = indices["CharacterBankTab_" .. position]
        if IsNumber(id) and id % 1 == 0 and id > 5 then
            local buffer = self.bankPaletteBuffers[position]
            if not buffer then
                buffer = {}
                self.bankPaletteBuffers[position] = buffer
            end
            self.bankPositions[id] = position
            self.bankPalette[position] = GetColor(appearance, position, buffer, "bankColors")
        end
    end
end

function Colors:BankPosition(bankType, id)
    local character = Enum and Enum.BankType and Enum.BankType.Character
    if not IsNumber(character) or not Addon.IsPublic(bankType) or bankType ~= character
        or not IsNumber(id) or id % 1 ~= 0 then return nil end
    return self.bankPositions[id]
end

function Colors:EnsureSlotRegions(button, state, style)
    if not CanAccessFrame(button) then return false end
    local tint = style == "tint"
    if (tint and state.fillReady) or (not tint and state.edgesReady) then return true end
    local ok, detail = pcall(function()
        if tint then
            -- Bank slots have an extra BACKGROUND/0 surface. Tint must sit
            -- above that surface while remaining below native item artwork.
            if not state.fill then state.fill = button:CreateTexture(nil, "BACKGROUND", nil, state.bank and 1 or -8) end
            state.fill:SetPoint("TOPLEFT", button, "TOPLEFT", -PADDING, PADDING)
            state.fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", PADDING, -PADDING)
            state.fillRaised = false
            state.fillReady = true
        else
            state.edges = state.edges or {}
            -- Keep the whole stroke outside the icon/count area, above native
            -- quality/quest/search framing, with room in the five-unit gutter.
            NewEdges(button, state.edges, "OVERLAY", 7)
            AnchorEdges(state.edges, button, SLOT_OUTLINE_PADDING, SLOT_OUTLINE_WIDTH)
            state.edgesReady = true
        end
        HideSlot(state)
        state.ready = true
    end)
    if not ok then
        HideSlot(state)
        Addon:ReportOnce("colors-regions", Diagnostic("Bag colors could not create decorative regions.", detail))
        return false
    end
    return true
end

function Colors:RefreshPalette(appearance)
    for bag = -1, 5 do
        local buffer = self.paletteBuffers[bag]
        if not buffer then
            buffer = {}
            self.paletteBuffers[bag] = buffer
        end
        -- Revalidate live color edits once per position; slots borrow our small RGB buffers.
        self.palette[bag] = GetColor(appearance, bag, buffer)
    end
end

function Colors:ShowSlot(button, state, color, matchesSearch, style, alpha)
    if not self:EnsureSlotRegions(button, state, style) then return end
    local factor = matchesSearch and 1 or 0.2
    if style == "tint" then
        -- Individual bags put their empty backdrop on the icon's BORDER layer.
        -- Observe completed native visual state; failed/unknown reads stay below
        -- the icon so an occupied item can never receive this tint overlay.
        local raised = false
        if not state.bank and state.hooks.SetHasItem and Read(button, "IsCombined") == false
            and type(button.HasItem) == "function" then
            local ok, hasItem = pcall(button.HasItem, button)
            raised = ok and Addon.IsPublic(hasItem) and hasItem == nil
        end
        if state.fillRaised ~= raised then
            state.fill:SetDrawLayer(raised and "BORDER" or "BACKGROUND", raised and 1 or (state.bank and 1 or -8))
            state.fillRaised = raised
        end
        -- Exposed gutter remains visible beside occupied-slot artwork.
        state.fill:SetColorTexture(color[1], color[2], color[3], alpha * factor)
        state.fill:Show()
        state.fillShown = true
    else
        ShowEdges(state.edges, color, alpha * factor)
    end
end

function Colors:WatchBagIcon(button)
    if not CanAccessFrame(button) then return nil end
    local state = self.icons[button]
    if not state then
        state = { hooks = {}, scripts = {}, edges = {} }
        self.icons[button] = state
        state.refresh = function() self:RequestRefresh() end
        state.hide = function() HideSlot(state) end
    end
    for _, method in ipairs(ICON_METHODS) do self:HookMethod(button, method, state.refresh, state.hooks) end
    self:HookScript(button, "OnShow", state.refresh, state.scripts)
    self:HookScript(button, "OnHide", state.hide, state.scripts)
    return state
end

function Colors:EnsureIconRegions(button, state, toolbar)
    if not CanAccessFrame(button) then return false end
    if state.ready then return true end
    local ok, detail = pcall(function()
        -- Native icon, pressed art, count and hover textures keep their own state.
        NewEdges(button, state.edges, "OVERLAY", 7)
        -- Thicken toolbar borders inward without expanding the existing outer
        -- footprint or covering the native count's two-unit corner inset.
        AnchorEdges(state.edges, button, ICON_PADDING, toolbar and TOOLBAR_EDGE_WIDTH or EDGE_WIDTH)
        HideSlot(state)
        state.ready = true
    end)
    if not ok then
        HideSlot(state)
        Addon:ReportOnce("colors-icon-regions", Diagnostic("Bag icon colors could not create an outline.", detail))
        return false
    end
    return true
end

function Colors:RefreshBagIcons(alpha)
    local seen = {}
    local function Apply(button, expectedBag, fixedIdentity)
        if not CanAccessFrame(button) or seen[button] then return end
        seen[button] = true
        -- GetID is an inventory slot on ordinary bag buttons, not a container ID.
        -- Desktop keyring inherits the inventory conversion; its named identity is -1.
        local bag = expectedBag
        if not fixedIdentity and type(button.GetBagID) == "function" then
            bag = Read(button, "GetBagID")
        end
        if not IsBag(bag) then return end
        local state = self:WatchBagIcon(button)
        local color = self.palette[bag]
        if state and color and Read(button, "IsVisible") == true and self:EnsureIconRegions(button, state, true) then
            ShowEdges(state.edges, color, alpha)
        end
    end
    for _, entry in ipairs(BAG_ICONS) do Apply(_G[entry[1]], entry[2], entry[3]) end
    if CanAccessFrame(GamepadBagBar) and type(GamepadBagBar.GetBagButton) == "function" then
        for bag = -1, 5 do Apply(Read(GamepadBagBar, "GetBagButton", bag), bag, false) end
    end
end

function Colors:FindContainers()
    local found, seen = {}, {}
    local function Add(container)
        if CanAccessFrame(container) and not seen[container] and type(container.GetObjectType) == "function" then
            seen[container] = true
            found[#found + 1] = container
        end
    end
    Add(ContainerFrameCombinedBags)
    if ContainerFrameContainer and type(ContainerFrameContainer.ContainerFrames) == "table" then
        for _, container in ipairs(ContainerFrameContainer.ContainerFrames) do Add(container) end
    end
    -- Named frames are also used by clients whose parent array is unavailable.
    for i = 1, 16 do Add(_G["ContainerFrame" .. i]) end
    return found
end

function Colors:CollectSlot(button, container, bag, slot, color, style, alpha, entries, initializer)
    if not CanAccessFrame(button) or not IsNumber(slot) or slot <= 0 or slot % 1 ~= 0 or not color
        or Read(button, "IsVisible") ~= true or Read(button, "IsExtended") == true then return end
    local state = self:WatchSlot(button, container, initializer)
    if not state then return end
    local grouped = style == "groups"
    local left, bottom, width, height, level
    if grouped then
        if type(button.GetRect) ~= "function" then return end
        local ok
        ok, left, bottom, width, height = pcall(button.GetRect, button)
        if not ok or not IsNumber(left) or not IsNumber(bottom) or not IsNumber(width) or not IsNumber(height)
            or width <= 0 or height <= 0 or not IsNumber(left + width) or not IsNumber(bottom + height) then return end
        level = Read(button, "GetFrameLevel")
        if not IsNumber(level) or level < 0 then return end
    end
    local matches = state.matchesSearch
    if matches == nil and C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local readOK, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if readOK and Addon.IsPublic(info) and type(info) == "table"
            and Addon.IsPublic(info.isFiltered) and type(info.isFiltered) == "boolean" then
            matches = not info.isFiltered
        end
    end
    if grouped then
        entries[#entries + 1] = {
            button = button, bag = bag, color = color,
            left = left, right = left + width, top = bottom + height,
            bottom = bottom, width = width, height = height,
            level = level,
            matchesSearch = matches ~= false,
        }
    else
        self:ShowSlot(button, state, color, matches ~= false, style, alpha)
    end
end

function Colors:CollectEntries(container, style, alpha)
    local entries = style == "groups" and {} or nil
    if not CanAccessFrame(container) or Read(container, "IsVisible") ~= true then return entries end
    if type(container.Items) ~= "table" then return entries end
    for i = 1, min(#container.Items, 512) do
        local button = container.Items[i]
        if CanAccessFrame(button) and type(button.GetBagID) == "function" then
            local bag, slot = Read(button, "GetBagID"), Read(button, "GetID")
            local collapsed = false
            if GamepadBagBar and type(GamepadBagBar.GetBagButton) == "function" and IsBag(bag) then
                local bagButton = Read(GamepadBagBar, "GetBagButton", bag)
                if bagButton and Addon.IsPublic(bagButton.isCollapsed) then collapsed = bagButton.isCollapsed == true end
            end
            if IsBag(bag) and not collapsed then
                self:CollectSlot(button, container, bag, slot, self.palette[bag], style, alpha, entries)
            end
        end
    end
    return entries
end

function Colors:VisitNativePool(owner, method, visitor, ...)
    -- Native frame pools enumerate their active object as the iterator's first value.
    -- The pool and iterator state are Lua objects, not FrameScriptObjects.
    if not Addon.IsPublic(owner) or type(owner) ~= "table" or type(owner[method]) ~= "function" then return false end
    local ok, iterator, poolState, previous = pcall(owner[method], owner)
    if not ok or not Addon.IsPublic(iterator) or type(iterator) ~= "function"
        or not Addon.IsPublic(poolState) or not Addon.IsPublic(previous) then return false end
    for _ = 1, 512 do
        local stepOK, object = pcall(iterator, poolState, previous)
        if not stepOK then
            Addon:ReportOnce("colors-bank-pool", Diagnostic("Bank colors could not inspect the native slot pool.", object))
            return false
        end
        if not Addon.IsPublic(object) then return false end
        if object == nil then return true end
        previous = object
        visitor(self, object, ...)
    end
    return false
end

local function ScaledVerticalBounds(region)
    if not CanAccessFrame(region) or type(region.GetScaledRect) ~= "function" then return end
    local ok, left, bottom, width, height = pcall(region.GetScaledRect, region)
    if ok and IsNumber(left) and IsNumber(bottom) and IsNumber(width) and IsNumber(height)
        and width > 0 and height > 0 and IsNumber(left + width) and IsNumber(bottom + height) then
        return bottom, bottom + height
    end
end

local function ReadDividerAnchor(region, owner)
    if Read(region, "GetNumPoints") ~= 1 or type(region.GetPoint) ~= "function" then return end
    local ok, point, relative, relativePoint, x, y = pcall(region.GetPoint, region, 1)
    if ok and Addon.IsPublic(point) and point == "BOTTOM" and Addon.IsPublic(relative) and relative == owner
        and Addon.IsPublic(relativePoint) and relativePoint == "BOTTOM" and IsNumber(x) and IsNumber(y) then
        return x, y
    end
end

local function CollectRegions(frame) return { frame:GetRegions() } end

local function IdentifyBankDivider(frame, regions)
    local found
    for index = 1, #regions do
        local region = regions[index]
        if not CanAccessFrame(region) or Read(region, "GetParent") ~= frame then return end
        local kind = Read(region, "GetObjectType")
        if type(kind) ~= "string" then return end
        if type(region.GetAtlas) == "function" then
            local ok, atlas = pcall(region.GetAtlas, region)
            if not ok or not Addon.IsPublic(atlas) then return end
            if atlas == "bank-divider" then
                if found then return end
                found = region
            end
        elseif kind ~= "FontString" and kind ~= "Line" then return end
    end
    if found and Read(found, "IsVisible") == true then return found end
end

function Colors:FindBankDivider(frame)
    local recorded = self.bankDivider
    local count = Read(frame, "GetNumRegions")
    if not IsNumber(count) or count % 1 ~= 0 or count < 1 or count > 128 then return end
    local regions = recorded and recorded.owner == frame and recorded.regionCount == count and recorded.regions
    if not regions then
        if type(frame.GetRegions) ~= "function" then return end
        local ok
        ok, regions = pcall(CollectRegions, frame)
        if not ok or #regions ~= count then return end
    end
    local found = IdentifyBankDivider(frame, regions)
    if not found then return end
    if recorded and recorded.owner == frame and recorded.region == found then
        recorded.regionCount, recorded.regions = count, regions
        return recorded
    end
    if recorded and not self:RestoreBankDivider() then return end
    local x, y = ReadDividerAnchor(found, frame)
    local scale = Read(found, "GetScale")
    if not x or not IsNumber(scale) or scale <= 0 then return end
    recorded = { region = found, owner = frame, x = x, y = y, currentY = y,
        scale = scale, regionCount = count, regions = regions }
    self.bankDivider = recorded
    return recorded
end

local function ExplicitHeight(frame)
    local value = Read(frame, "GetHeight", true)
    if IsNumber(value) and value > 0 then return value end
end

local function HasCenteredBankPanel(panel, owner)
    if Read(panel, "GetNumPoints") ~= 1 or type(panel.GetPoint) ~= "function" then return false end
    local ok, point, relative, relativePoint, x, y = pcall(panel.GetPoint, panel, 1)
    return ok and Addon.IsPublic(point) and point == "LEFT" and Addon.IsPublic(relative) and relative == owner
        and Addon.IsPublic(relativePoint) and relativePoint == "LEFT" and IsNumber(x) and IsNumber(y)
end

function Colors:BankFooterLayoutGenerated(panel)
    local recorded = self.bankFooter
    if recorded and recorded.panel == panel and not recorded.writing then recorded.nativeReset = true end
end

function Colors:RebaseBankFooter(recorded)
    if not recorded.nativeReset then return true end
    local root, panel = ExplicitHeight(recorded.owner), ExplicitHeight(recorded.panel)
    if not root or not panel then return false end
    if root == recorded.nativeRootHeight and panel == recorded.nativePanelHeight then
        -- A genuine native reset may restore exactly our original dimensions.
        -- That also ends a foreign resize episode without adopting any of our
        -- expanded dimensions as a new baseline.
        recorded.currentRootHeight, recorded.currentPanelHeight = root, panel
        recorded.attemptRootHeight, recorded.attemptPanelHeight = nil, nil
        recorded.foreignRoot, recorded.foreignPanel, recorded.abandoned = nil, nil, nil
        recorded.extra, recorded.restorePending, recorded.nativeReset = 0, nil, nil
        return true
    end
    -- Generation can return before SetSize. Do not adopt our current enlarged
    -- pair as a native baseline merely because that posthook ran.
    if root == recorded.currentRootHeight or panel == recorded.currentPanelHeight then
        recorded.nativeReset = nil
        return true
    end
    recorded.nativeRootHeight, recorded.nativePanelHeight = root, panel
    recorded.currentRootHeight, recorded.currentPanelHeight = root, panel
    recorded.attemptRootHeight, recorded.attemptPanelHeight = nil, nil
    recorded.foreignRoot, recorded.foreignPanel, recorded.abandoned = nil, nil, nil
    recorded.extra, recorded.restorePending, recorded.nativeReset = 0, nil, nil
    return true
end

function Colors:WriteBankFooterHeight(recorded, frame, target, currentKey, attemptKey, foreignKey)
    if recorded[foreignKey] then return true end -- Preserve another owner's resize.
    local current = ExplicitHeight(frame)
    if not current or not CanAccessFrame(frame) or type(frame.SetHeight) ~= "function" then return false end
    if current ~= recorded[currentKey] and current ~= recorded[attemptKey] then
        recorded[foreignKey], recorded.abandoned = true, true
        Addon:ReportOnce("colors-bank-footer-owner", "Bank window sizing changed elsewhere; its current size was preserved.")
        return false
    end
    if current == target then recorded[currentKey], recorded[attemptKey] = target, nil; return true end
    recorded[attemptKey] = target
    recorded.writing = true
    local ok, detail = pcall(frame.SetHeight, frame, target)
    recorded.writing = nil
    local actual = ExplicitHeight(frame)
    if ok and actual == target then
        recorded[currentKey], recorded[attemptKey] = target, nil
        return true, actual ~= current
    end
    Addon:ReportOnce("colors-bank-footer-write", Diagnostic("Bank footer sizing could not finish; it will retry on the next update.", detail))
    return false
end

function Colors:ApplyBankFooterHeights(recorded, rootHeight, panelHeight, restoring, suppressSettle)
    if type(InCombatLockdown) ~= "function" then return false end
    local combat = InCombatLockdown()
    if not Addon.IsPublic(combat) or combat ~= false then return false end
    if not CanAccessFrame(recorded.owner) or not CanAccessFrame(recorded.panel)
        or Read(recorded.panel, "GetParent") ~= recorded.owner then return false end
    if not restoring and recorded.abandoned then return false end
    local rootOK, rootChanged = self:WriteBankFooterHeight(recorded, recorded.owner, rootHeight,
        "currentRootHeight", "attemptRootHeight", "foreignRoot")
    local panelOK, panelChanged
    if rootOK or restoring then
        panelOK, panelChanged = self:WriteBankFooterHeight(recorded, recorded.panel, panelHeight,
            "currentPanelHeight", "attemptPanelHeight", "foreignPanel")
    end
    if not rootOK or not panelOK then
        recorded.restorePending = true
        if not restoring then self:RestoreBankFooter(true) end
        return false
    end
    if (rootChanged or panelChanged) and not suppressSettle then
        self.bankFooterChanged = restoring and "restore" or "growth"
    end
    return true
end

function Colors:RestoreBankFooter(suppressSettle)
    local recorded = self.bankFooter
    if not recorded then return true end
    if not self:RebaseBankFooter(recorded) then return false end
    recorded.restorePending = true
    local ok = self:ApplyBankFooterHeights(recorded, recorded.nativeRootHeight, recorded.nativePanelHeight, true, suppressSettle)
    if ok then recorded.extra, recorded.restorePending = 0, nil end
    return ok
end

-- Existing visibility/mode cleanup calls share the new paired-height owner.
function Colors:RestoreBankDivider() return self:RestoreBankFooter() end

function Colors:MeasureBankFooter(control, text, padding)
    local measure = self.bankDividerMeasure
    if not measure or not measure.active then return end
    if not Addon.IsPublic(control) then measure.valid = false; return end
    if control == nil then return end
    local visible = Read(control, "IsVisible")
    if visible == false then return end
    local bottom, top = ScaledVerticalBounds(control)
    if visible ~= true or not top then measure.valid = false; return end
    if text then
        -- The native BagText box is 40 units tall with MIDDLE alignment. Use
        -- its actual line height, rather than reserving its blank padding.
        local height, scale = Read(control, "GetStringHeight"), Read(control, "GetEffectiveScale")
        if Read(control, "GetJustifyV") ~= "MIDDLE" or not IsNumber(height) or height < 0
            or not IsNumber(scale) or scale <= 0 then measure.valid = false; return end
        top = (bottom + top + height * scale) * 0.5
        if not IsNumber(top) then measure.valid = false; return end
    end
    if padding then
        local scale = Read(control, "GetEffectiveScale")
        if not IsNumber(scale) or scale <= 0 then measure.valid = false; return end
        top = top + padding * scale
        if not IsNumber(top) then measure.valid = false; return end
    end
    measure.high = measure.high and max(measure.high, top) or top
end

function Colors:CollectBankSlot(button, panel, style, alpha, entries)
    local measure = self.bankDividerMeasure
    if not CanAccessFrame(button) or not Addon.IsPublic(button.isInitialized) then
        if measure and measure.active then measure.valid = false end
        return
    end
    if button.isInitialized ~= true then return end
    local bankType = Read(button, "GetBankType")
    local bag, slot = Read(button, "GetBankTabID"), Read(button, "GetContainerSlotID")
    local position = self:BankPosition(bankType, bag)
    if position then
        if measure and measure.active and IsNumber(slot) and slot > 0 and slot % 1 == 0
            then
            local visible = Read(button, "IsVisible")
            if visible == true then
                local bottom = ScaledVerticalBounds(button)
                if bottom then measure.low = measure.low and min(measure.low, bottom) or bottom
                else measure.valid = false end
            elseif visible ~= false then measure.valid = false end
        end
        self:CollectSlot(button, panel, bag, slot, self.bankPalette[position], style, alpha, entries, "Init")
    end
end

function Colors:UpdateBankFooter(frame, panel, itemBottom, holderTop, valid)
    local divider = self.bankDivider
    if not divider or divider.owner ~= frame then return end
    local rootScale, panelScale = Read(frame, "GetEffectiveScale"), Read(panel, "GetEffectiveScale")
    local bottom, top = ScaledVerticalBounds(divider.region)
    local rootHeight, panelHeight = ExplicitHeight(frame), ExplicitHeight(panel)
    local dividerX, dividerY = ReadDividerAnchor(divider.region, frame)
    local state = self.containers[panel]
    if not valid or not IsNumber(itemBottom) or not IsNumber(holderTop) or not bottom
        or not IsNumber(rootScale) or rootScale <= 0 or not IsNumber(panelScale) or panelScale <= 0
        or not rootHeight or not panelHeight or not state or not state.hooks.GenerateItemSlotsForSelectedTab
        or not HasCenteredBankPanel(panel, frame) or dividerX ~= divider.x or dividerY ~= divider.y then
        self:RestoreBankFooter()
        Addon:ReportOnce("colors-bank-footer-layout", "Bank footer geometry is unavailable; the native size was preserved.")
        return
    end
    local recorded = self.bankFooter
    if recorded and (recorded.owner ~= frame or recorded.panel ~= panel) then
        if not self:RestoreBankFooter() then return end
        recorded = nil
    end
    if not recorded then
        recorded = { owner = frame, panel = panel, nativeRootHeight = rootHeight, nativePanelHeight = panelHeight,
            currentRootHeight = rootHeight, currentPanelHeight = panelHeight, extra = 0 }
        self.bankFooter = recorded
    end
    if not self:RebaseBankFooter(recorded) then return end
    if recorded.restorePending or recorded.abandoned then self:RestoreBankFooter(); return end
    local rootApplied = (rootHeight - recorded.nativeRootHeight) * rootScale
    local panelApplied = (panelHeight - recorded.nativePanelHeight) * panelScale
    -- LEFT-centered BankPanel shares half of each height delta. Removing this
    -- gain reconstructs the native gap and prevents shrink/reapply oscillation.
    local gain = (rootApplied + panelApplied) * 0.5
    local needed = max(0, top - itemBottom + gain + (GROUP_PADDING + DIVIDER_CLEARANCE) * panelScale)
    local extra = math.ceil(needed / rootScale)
    local panelExtra = extra * rootScale / panelScale
    local targetRoot = recorded.nativeRootHeight + extra
    local targetPanel = recorded.nativePanelHeight + panelExtra
    if not IsNumber(rootApplied) or not IsNumber(panelApplied) or not IsNumber(gain) or not IsNumber(needed)
        or not IsNumber(extra) or not IsNumber(panelExtra) or not IsNumber(targetRoot) or not IsNumber(targetPanel)
        or extra > MAX_BANK_FOOTER_EXTRA or panelExtra > MAX_BANK_FOOTER_EXTRA then
        self:RestoreBankFooter()
        Addon:ReportOnce("colors-bank-footer-layout", "Bank footer geometry is unavailable; the native size was preserved.")
        return
    end
    if self.bankFooterSettling and (targetRoot ~= rootHeight or targetPanel ~= panelHeight) then
        self:RestoreBankFooter(true)
        Addon:ReportOnce("colors-bank-footer-settle", "Bank footer sizing did not settle; the next native update will retry.")
        return
    end
    -- Heights move the entire footer together; its existing divider/control
    -- clearance must already be safe. No divider or control anchor is changed.
    if needed > 0 and bottom < holderTop + DIVIDER_CLEARANCE * panelScale then
        self:RestoreBankFooter()
        Addon:ReportOnce("colors-bank-footer-space", "Native bank footer controls overlap; the native size was preserved.")
        return
    end
    if self:ApplyBankFooterHeights(recorded, targetRoot, targetPanel) then recorded.extra = extra end
end

function Colors:PaintBankIcon(button, alpha)
    -- All active native footer controls reserve space, including locked or
    -- otherwise uncolored holders whose storage identity is unavailable.
    self:MeasureBankFooter(button, false, ICON_PADDING)
    if not CanAccessFrame(button) or Read(button, "IsVisible") ~= true then return end
    local id = Read(button, "GetExactBankTabSlot")
    local position = self:BankPosition(button.bankType, id)
    if not position or not Addon.IsPublic(button.bagSlotID) or button.bagSlotID ~= position then return end
    if Read(button.DisabledOverlay, "IsShown") ~= false then return end
    local color = self.bankPalette[position]
    local state = color and self:WatchBagIcon(button)
    if state and self:EnsureIconRegions(button, state) then ShowEdges(state.edges, color, alpha) end
end

function Colors:RefreshBank(appearance, style, alpha, bagOutlineAlpha)
    self:EnsureBankSizeTrace()
    local frame = BankFrame
    if self.bankDividerMeasure then self.bankDividerMeasure.active = false end
    if not CanAccessFrame(frame) or Read(frame, "IsVisible") ~= true then self:RestoreBankDivider(); return end
    local panel = frame.BankPanel or BankPanel
    if not CanAccessFrame(panel) or Read(panel, "IsVisible") ~= true then self:RestoreBankDivider(); return end
    self:WatchContainer(frame)
    self:WatchContainer(panel)
    local character = Enum and Enum.BankType and Enum.BankType.Character
    if not IsNumber(character) or Read(panel, "GetActiveBankType") ~= character then self:RestoreBankDivider(); return end
    self:RefreshBankPalette(appearance)
    if IsNumber(alpha) and alpha > 0 and self:FindBankDivider(frame) then
        self.bankDividerMeasure = self.bankDividerMeasure or {}
        local measure = self.bankDividerMeasure
        measure.low, measure.high, measure.valid, measure.active = nil, nil, true, true
        self:MeasureBankFooter(frame.BagText, true)
        self:MeasureBankFooter(frame.BagCost)
        self:MeasureBankFooter(panel.MoneyDisplay)
        self:MeasureBankFooter(panel.PurchaseButton)
    else self:RestoreBankDivider() end
    local entries = style == "groups" and {} or nil
    local itemsOK = self:VisitNativePool(panel, "EnumerateValidItems", self.CollectBankSlot, panel, style, alpha, entries)
    local iconsOK = self:VisitNativePool(frame.itemButtonBagPool, "EnumerateActive", self.PaintBankIcon, bagOutlineAlpha)
    local measure = self.bankDividerMeasure
    if measure and measure.active then
        self:UpdateBankFooter(frame, panel, measure.low, measure.high, measure.valid and itemsOK and iconsOK)
        measure.active = false
    end
    return panel, entries
end

-- Explicit, read-only client evidence. Do not reuse discovery/painting helpers
-- here: they can acquire ownership, restore anchors, or request inventory data.
function Colors:PrintBankDebug()
    local function Pack(...) return { n = select("#", ...), ... } end
    local function Call(callback, ...)
        if not Addon.IsPublic(callback) then return { status = "secret" } end
        if type(callback) ~= "function" then return { status = "missing" } end
        local result = Pack(pcall(callback, ...))
        if not result[1] then return { status = "throw" } end
        for index = 2, result.n do
            if not Addon.IsPublic(result[index]) then return { status = "secret" } end
        end
        for index = 1, result.n - 1 do result[index] = result[index + 1] end
        result[result.n] = nil
        result.n, result.status = result.n - 1, "ok"
        return result
    end
    local function Probe(object, method, luaObject)
        if not Addon.IsPublic(object) then return { status = "secret" } end
        if object == nil then return { status = "missing" } end
        if type(object) ~= "table" and type(object) ~= "userdata" then return { status = "invalid" } end
        if not luaObject and not CanAccessFrame(object) then return { status = "denied" } end
        return Call(object[method], object)
    end
    local function Member(object, key)
        if CanAccessFrame(object) then return object[key] end
    end
    local function MethodStatus(object, method)
        if not CanAccessFrame(object) then return "denied" end
        local callback = object[method]
        if not Addon.IsPublic(callback) then return "secret" end
        return type(callback) == "function" and "callable" or "missing"
    end
    local function Value(result, index) if result.status == "ok" then return result[index or 1] end end
    local function Scalar(value)
        if not Addon.IsPublic(value) then return "secret" end
        if value == nil then return "nil" end
        if type(value) == "boolean" then return value and "true" or "false" end
        if IsNumber(value) then return string.format("%.6g", value) end
        if type(value) == "number" then return "invalid-number" end
        if type(value) == "string" then return value:gsub("[%c|]", "?"):sub(1, 64) end
        return "object"
    end
    local function Field(result, index)
        return result.status == "ok" and Scalar(result[index or 1]) or result.status
    end
    local function Rect(object, method)
        local result = Probe(object, method or "GetScaledRect")
        local left, bottom, width, height = Value(result, 1), Value(result, 2), Value(result, 3), Value(result, 4)
        local reason = result.status
        if reason == "ok" then
            if not IsNumber(left) or not IsNumber(bottom) or not IsNumber(width) or not IsNumber(height)
                or not IsNumber(left + width) or not IsNumber(bottom + height) then reason = "invalid"
            elseif width <= 0 then reason = "width<=0"
            elseif height <= 0 then reason = "height<=0" end
        end
        return { probe = result, bottom = bottom, top = IsNumber(bottom) and IsNumber(height) and bottom + height or nil,
            height = height, valid = reason == "ok", reason = reason }
    end
    local function RectText(rect)
        if rect.probe.status ~= "ok" then return rect.probe.status end
        return "(" .. Field(rect.probe, 1) .. "," .. Field(rect.probe, 2) .. ","
            .. Field(rect.probe, 3) .. "," .. Field(rect.probe, 4) .. ")/" .. rect.reason
    end
    local function ScanPool(owner, method, visitor, native)
        if native and not CanAccessFrame(owner) then return 0, "denied" end
        local start = Probe(owner, method, true)
        if start.status ~= "ok" then return 0, start.status end
        local iterator, state, previous = start[1], start[2], start[3]
        if type(iterator) ~= "function" then return 0, "invalid-iterator" end
        for count = 0, 511 do
            local step = Call(iterator, state, previous)
            if step.status ~= "ok" then return count, step.status end
            local object = step[1]
            if object == nil then return count, "ok" end
            previous = object
            visitor(object, count + 1)
        end
        return 512, "limit"
    end
    local ok, lines = pcall(function()
        local output, gate = {}, nil
        local function Gate(reason) if not gate then gate = reason end end
        local function Line(message) output[#output + 1] = message end
        local appearance
        if Addon.IsPublic(Addon.db) and type(Addon.db) == "table" then appearance = Addon.db.appearance end
        if not Addon.IsPublic(appearance) or type(appearance) ~= "table" then appearance = {} end
        local mode, shape, alpha = appearance.mode, appearance.outline, appearance.outlineAlpha
        local tint = Addon.IsPublic(mode) and mode == "tint"
        if tint then alpha = appearance.tintAlpha end
        local effectiveAlpha = GetAlpha(alpha, tint and 0.5 or 0.75)
        local combat = Call(InCombatLockdown)
        if Value(combat) ~= false then Gate("combat=" .. Field(combat)) end
        if not Addon.IsPublic(mode) or (mode ~= "outline" and mode ~= "tint") then Gate("mode=" .. Scalar(mode)) end
        if effectiveAlpha <= 0 then Gate("content-alpha=0") end
        local toc = C_AddOns and Call(C_AddOns.GetAddOnMetadata, "ForTheHoard", "Version") or { status = "missing" }
        Line("bankdebug core=" .. Scalar(Addon.version) .. " toc=" .. Field(toc) .. " mode=" .. Scalar(mode)
            .. " shape=" .. Scalar(shape) .. " alpha=" .. Scalar(alpha) .. " effective=" .. Scalar(effectiveAlpha)
            .. " combat=" .. Field(combat))

        local frame = Addon.IsPublic(BankFrame) and BankFrame or nil
        local frameAccess = CanAccessFrame(frame)
        local panel
        if frameAccess then panel = frame.BankPanel end
        if Addon.IsPublic(panel) and panel == nil then panel = BankPanel end
        local frameVisible, frameType = Probe(frame, "IsVisible"), Probe(frame, "GetActiveBankType")
        local panelVisible, panelType, panelScale = Probe(panel, "IsVisible"), Probe(panel, "GetActiveBankType"), Probe(panel, "GetEffectiveScale")
        local scale = Value(panelScale)
        if not frameAccess then Gate("bank-access")
        elseif Value(frameVisible) ~= true then Gate("bank-visible=" .. Field(frameVisible))
        elseif not CanAccessFrame(panel) then Gate("panel-access")
        elseif Value(panelVisible) ~= true then Gate("panel-visible=" .. Field(panelVisible)) end
        local character = Enum and Enum.BankType and Enum.BankType.Character
        if not IsNumber(character) or Value(panelType) ~= character then Gate("panel-type=" .. Field(panelType)) end
        Line("bank visible=" .. Field(frameVisible) .. " type=" .. Field(frameType) .. " panel visible="
            .. Field(panelVisible) .. " type=" .. Field(panelType) .. " scale=" .. Field(panelScale))

        local count, live = Probe(frame, "GetNumRegions"), nil
        local number = Value(count)
        local recorded = self.bankDivider
        local footer = self.bankFooter
        local useCached = recorded and recorded.owner == frame and recorded.regionCount == number and recorded.regions
        if IsNumber(number) and number % 1 == 0 and number >= 1 and number <= 128 then
            live = Probe(frame, "GetRegions")
            if not useCached then
                if live.status ~= "ok" then Gate("regions=" .. live.status)
                elseif live.n ~= number then Gate("region-count-mismatch") end
            end
        else Gate("region-count=" .. Field(count)) end
        local regions = useCached or (live and live.status == "ok" and live)
        local firstReject, candidate, candidateIndex, candidates = nil, nil, nil, 0
        local cachedSame = live and live.status == "ok" and true or nil
        local regionMap, writeGuard = {}, nil
        if regions and IsNumber(number) and number >= 1 and number <= 128 then
            for index = 1, number do
                local region = regions[index]
                if useCached and live and live.status == "ok" and region ~= live[index] then cachedSame = false end
                local parent, kind, atlas = Probe(region, "GetParent"), Probe(region, "GetObjectType"), Probe(region, "GetAtlas")
                local rejection
                if not CanAccessFrame(region) then rejection = "access"
                elseif Value(parent) ~= frame then rejection = "parent=" .. (parent.status == "ok" and "other" or parent.status)
                elseif type(Value(kind)) ~= "string" then rejection = "kind=" .. Field(kind)
                elseif atlas.status ~= "ok" and not (atlas.status == "missing"
                    and (Value(kind) == "FontString" or Value(kind) == "Line")) then rejection = "atlas=" .. atlas.status end
                if rejection and not firstReject then
                    firstReject = "region" .. index .. ":" .. rejection .. " kind=" .. Field(kind) .. " atlas=" .. Field(atlas)
                end
                if Value(atlas) == "bank-divider" then
                    candidates = candidates + 1
                    if not candidate then candidate, candidateIndex = region, index end
                end
                if #regionMap < 16 then
                    regionMap[#regionMap + 1] = index .. ":" .. Field(kind):sub(1, 16) .. ":" .. Field(atlas):sub(1, 32)
                end
            end
        end
        if firstReject then Gate(firstReject)
        elseif candidates ~= 1 then Gate("divider-candidates=" .. candidates) end
        Line("regions count=" .. Field(count) .. " returned=" .. (live and (live.status == "ok" and Scalar(live.n) or live.status) or "not-read")
            .. " source=" .. (useCached and "cached" or "live") .. " cachedSame=" .. Scalar(cachedSame)
            .. " candidates=" .. candidates .. " firstReject=" .. (firstReject or "none"))
        if candidates == 0 and #regionMap > 0 then
            Line("regionMap " .. table.concat(regionMap, "; ", 1, min(8, #regionMap)))
            if #regionMap > 8 then Line("regionMap+ " .. table.concat(regionMap, "; ", 9)
                .. (number > #regionMap and "; truncated" or "")) end
        end

        local candidateParent, candidateVisible = Probe(candidate, "GetParent"), Probe(candidate, "IsVisible")
        local ownScale, effectiveScale = Probe(candidate, "GetScale"), Probe(candidate, "GetEffectiveScale")
        if candidate then Line("divider index=" .. Scalar(candidateIndex) .. " kind=" .. Field(Probe(candidate, "GetObjectType"))
            .. " parentOwner=" .. Scalar(Value(candidateParent) == frame) .. " visible=" .. Field(candidateVisible)
            .. " ownScale=" .. Field(ownScale) .. " effectiveScale=" .. Field(effectiveScale)
            .. " rootSetHeight=" .. MethodStatus(frame, "SetHeight") .. " panelSetHeight=" .. MethodStatus(panel, "SetHeight")) end
        if Value(candidateVisible) ~= true then Gate("divider-visible=" .. Field(candidateVisible)) end
        if not recorded and (not IsNumber(Value(ownScale)) or Value(ownScale) <= 0) then Gate("divider-scale=" .. Field(ownScale)) end
        local points = Probe(candidate, "GetNumPoints")
        local anchor = candidate and CanAccessFrame(candidate) and Call(candidate.GetPoint, candidate, 1) or { status = "missing" }
        local relative = Value(anchor, 2)
        local ownerEq = frame ~= nil and anchor.status == "ok" and relative == frame
        local relativeKind = anchor.status ~= "ok" and anchor.status or (ownerEq and "owner" or (relative == nil and "nil"
            or (type(relative) == "string" and Scalar(relative) or type(relative))))
        if candidate then Line("anchor n=" .. Field(points) .. " point=" .. Field(anchor, 1) .. " relative=" .. relativeKind
            .. " ownerEq=" .. Scalar(ownerEq) .. " parentEq=" .. Scalar(anchor.status == "ok" and Value(candidateParent) ~= nil and relative == Value(candidateParent))
            .. " relativePoint=" .. Field(anchor, 3) .. " x=" .. Field(anchor, 4) .. " y=" .. Field(anchor, 5)) end
        if Value(points) ~= 1 or anchor.status ~= "ok" or Value(anchor, 1) ~= "BOTTOM" or relative ~= frame
            or Value(anchor, 3) ~= "BOTTOM" or not IsNumber(Value(anchor, 4)) or not IsNumber(Value(anchor, 5)) then Gate("anchor-contract") end
        if recorded and recorded.owner == frame and recorded.region == candidate and anchor.status == "ok"
            and (Value(anchor, 4) ~= recorded.x or Value(anchor, 5) ~= recorded.y) then Gate("divider-anchor-changed") end
        local fullRect, dividerRect = Rect(candidate, "GetRect"), Rect(candidate)
        if candidate then Line("divider rect=" .. RectText(fullRect) .. " scaled=" .. RectText(dividerRect)) end
        local rootHeight = CanAccessFrame(frame) and Call(frame.GetHeight, frame, true) or { status = "denied" }
        local panelHeight = CanAccessFrame(panel) and Call(panel.GetHeight, panel, true) or { status = "denied" }
        local rootScale = Probe(frame, "GetEffectiveScale")
        local panelAnchor = CanAccessFrame(panel) and Call(panel.GetPoint, panel, 1) or { status = "denied" }
        if not HasCenteredBankPanel(panel, frame) then Gate("panel-anchor-contract") end
        Line("footerLedger exists=" .. Scalar(footer ~= nil) .. " root=" .. Field(rootHeight) .. " panel=" .. Field(panelHeight)
            .. " rootScale=" .. Field(rootScale) .. " nativeRoot=" .. Scalar(footer and footer.nativeRootHeight)
            .. " nativePanel=" .. Scalar(footer and footer.nativePanelHeight) .. " currentRoot=" .. Scalar(footer and footer.currentRootHeight)
            .. " currentPanel=" .. Scalar(footer and footer.currentPanelHeight) .. " attemptRoot=" .. Scalar(footer and footer.attemptRootHeight)
            .. " attemptPanel=" .. Scalar(footer and footer.attemptPanelHeight) .. " extra=" .. Scalar(footer and footer.extra)
            .. " nativeReset=" .. Scalar(footer and footer.nativeReset) .. " restorePending=" .. Scalar(footer and footer.restorePending)
            .. " abandoned=" .. Scalar(footer and footer.abandoned)
            .. " panelAnchor=" .. Field(panelAnchor, 1) .. "/" .. Field(panelAnchor, 3)
            .. " ownerEq=" .. Scalar(panelAnchor.status == "ok" and Value(panelAnchor, 2) == frame))
        if footer and footer.abandoned then Gate("ownership-abandoned") end
        if footer and not footer.nativeReset and footer.owner == frame and footer.panel == panel then
            if Value(rootHeight) ~= footer.currentRootHeight and Value(rootHeight) ~= footer.attemptRootHeight then writeGuard = "root-height-changed" end
            if Value(panelHeight) ~= footer.currentPanelHeight and Value(panelHeight) ~= footer.attemptPanelHeight then writeGuard = "panel-height-changed" end
        end
        for _, object in ipairs({ frame, panel }) do
            if MethodStatus(object, "SetHeight") ~= "callable" and not writeGuard then writeGuard = "SetHeight=" .. MethodStatus(object, "SetHeight") end
        end

        local low, itemUnknown, itemVisible = nil, 0, 0
        local itemCount, itemScan = ScanPool(panel, "EnumerateValidItems", function(button)
            if not CanAccessFrame(button) or not Addon.IsPublic(button.isInitialized) then itemUnknown = itemUnknown + 1; return end
            if button.isInitialized ~= true then return end
            local position = self:BankPosition(Value(Probe(button, "GetBankType")), Value(Probe(button, "GetBankTabID")))
            local slot, visible = Value(Probe(button, "GetContainerSlotID")), Probe(button, "IsVisible")
            if not position or not IsNumber(slot) or slot <= 0 or slot % 1 ~= 0 then return end
            if Value(visible) == true then
                itemVisible = itemVisible + 1
                local rect = Rect(button)
                if rect.valid then low = low and min(low, rect.bottom) or rect.bottom else itemUnknown = itemUnknown + 1 end
            elseif Value(visible) ~= false then itemUnknown = itemUnknown + 1 end
        end, true)
        Line("items active=" .. itemCount .. " visiblePersonal=" .. itemVisible .. " unknown=" .. itemUnknown
            .. " scan=" .. itemScan .. " lowestBottom=" .. Scalar(low))

        local high, highSource, holderUnknown, holderVisible, holderRect, holderScale = nil, nil, 0, 0, nil, nil
        local holderCount, holderScan = ScanPool(frameAccess and frame.itemButtonBagPool, "EnumerateActive", function(button, index)
            local visible = Probe(button, "IsVisible")
            if Value(visible) == false then return end
            if Value(visible) ~= true then holderUnknown = holderUnknown + 1; return end
            holderVisible = holderVisible + 1
            local rect, own = Rect(button), Probe(button, "GetEffectiveScale")
            local effective = Value(own)
            if rect.valid and IsNumber(effective) and effective > 0 and IsNumber(rect.top + ICON_PADDING * effective) then
                local top = rect.top + ICON_PADDING * effective
                if not high or top > high then high, highSource, holderRect, holderScale = top, "holder" .. index, rect, own end
            else holderUnknown = holderUnknown + 1 end
        end)
        Line("holders active=" .. holderCount .. " visible=" .. holderVisible .. " unknown=" .. holderUnknown .. " scan=" .. holderScan
            .. " highestPadded=" .. Scalar(high) .. " rect=" .. (holderRect and RectText(holderRect) or "unknown")
            .. " scale=" .. (holderScale and Field(holderScale) or "unknown"))
        local footerUnknown = 0
        local function Footer(label, object, text)
            local visible, rect = Probe(object, "IsVisible"), nil
            local top, extra = nil, ""
            local height, align, textScale
            if text or label == "BagCost" then
                height, align, textScale = Probe(object, "GetStringHeight"), Probe(object, "GetJustifyV"), Probe(object, "GetEffectiveScale")
                extra = " textH=" .. Field(height) .. " textW=" .. Field(Probe(object, "GetStringWidth"))
                    .. " align=" .. Field(align) .. " scale=" .. Field(textScale)
            end
            if not Addon.IsPublic(object) or (object ~= nil and Value(visible) ~= false) then
                rect = Rect(object)
                if Value(visible) == true and rect.valid then
                    top = rect.top
                    if text then
                        local h, s = Value(height), Value(textScale)
                        if Value(align) == "MIDDLE" and IsNumber(h) and h >= 0 and IsNumber(s) and s > 0 then
                            top = (rect.bottom + rect.top + h * s) * 0.5
                        else top = nil end
                    end
                end
                if not IsNumber(top) then footerUnknown = footerUnknown + 1
                elseif not high or top > high then high, highSource = top, label end
            end
            Line(label .. " visible=" .. Field(visible) .. " rect=" .. (rect and RectText(rect) or "not-read")
                .. extra .. " measuredTop=" .. Scalar(top))
        end
        Footer("BagText", Member(frame, "BagText"), true)
        Footer("BagCost", Member(frame, "BagCost"))
        Footer("MoneyDisplay", Member(panel, "MoneyDisplay"))
        Footer("PurchaseButton", Member(panel, "PurchaseButton"))

        local needed, targetTop, lowerLimit, rootExtra, targetRoot, targetPanel, available, gain
        local rootEffective, rootValue, panelValue = Value(rootScale), Value(rootHeight), Value(panelHeight)
        if itemScan ~= "ok" or holderScan ~= "ok" or itemUnknown > 0 or holderUnknown > 0 or footerUnknown > 0 then Gate("measurement-unavailable") end
        if not IsNumber(low) or not IsNumber(high) or not dividerRect.valid or not IsNumber(scale) or scale <= 0
            or not IsNumber(rootEffective) or rootEffective <= 0 or not IsNumber(rootValue) or rootValue <= 0
            or not IsNumber(panelValue) or panelValue <= 0 then Gate("geometry-unavailable")
        else
            local nativeRoot, nativePanel = rootValue, panelValue
            if footer and footer.owner == frame and footer.panel == panel then
                nativeRoot, nativePanel = footer.nativeRootHeight, footer.nativePanelHeight
                if footer.nativeReset and rootValue ~= footer.currentRootHeight and panelValue ~= footer.currentPanelHeight then
                    nativeRoot, nativePanel = rootValue, panelValue
                end
            end
            gain = ((rootValue - nativeRoot) * rootEffective + (panelValue - nativePanel) * scale) * 0.5
            targetTop = low - (GROUP_PADDING + DIVIDER_CLEARANCE) * scale
            lowerLimit = high + DIVIDER_CLEARANCE * scale
            needed = max(0, dividerRect.top - targetTop + gain)
            rootExtra = math.ceil(needed / rootEffective)
            targetRoot, targetPanel = nativeRoot + rootExtra, nativePanel + rootExtra * rootEffective / scale
            available = targetTop - lowerLimit
            if not IsNumber(targetTop) or not IsNumber(lowerLimit) or not IsNumber(gain) or not IsNumber(needed)
                or not IsNumber(rootExtra) or not IsNumber(targetRoot) or not IsNumber(targetPanel) or not IsNumber(available) then Gate("geometry-overflow")
            elseif rootExtra > MAX_BANK_FOOTER_EXTRA or targetPanel - nativePanel > MAX_BANK_FOOTER_EXTRA then Gate("footer-extra-limit")
            elseif needed > 0 and dividerRect.bottom < lowerLimit then Gate("native-footer-overlap") end
        end
        Line("calc targetTop=" .. Scalar(targetTop) .. " footerHigh=" .. Scalar(high) .. " from=" .. Scalar(highSource)
            .. " lowerLimit=" .. Scalar(lowerLimit) .. " appliedGain=" .. Scalar(gain) .. " neededPhysical=" .. Scalar(needed)
            .. " extraRoot=" .. Scalar(rootExtra) .. " targetRoot=" .. Scalar(targetRoot) .. " targetPanel=" .. Scalar(targetPanel)
            .. " availableHeight=" .. Scalar(available)
            .. " dividerHeight=" .. Scalar(dividerRect.height))
        if writeGuard then Gate("write:" .. writeGuard) end
        local panelState = CanAccessFrame(panel) and self.containers[panel]
        local bankState = frameAccess and self.containers[frame]
        if not panelState or not panelState.hooks.GenerateItemSlotsForSelectedTab then Gate("generation-hook-unavailable") end
        Line("gate=" .. (gate or (targetRoot == rootValue and targetPanel == panelValue and "already-sized" or "eligible"))
            .. " writeGuard=" .. (writeGuard or "clear")
            .. " queued=" .. Field(Probe(self.driver, "IsShown")) .. " refreshing=" .. Scalar(self.refreshing)
            .. " pageHook=" .. Scalar(panelState and panelState.hooks.GenerateItemSlotsForSelectedTab)
            .. " bagHook=" .. Scalar(bankState and bankState.hooks.RefreshBagButtons))
        return output
    end)
    if not ok then
        Addon:Print("bankdebug: read-only snapshot unavailable (unexpected probe failure).")
        return
    end
    for _, line in ipairs(lines) do Addon:Print(line) end
end

local function RowRuns(entries)
    table.sort(entries, function(a, b)
        if a.top ~= b.top then return a.top > b.top end
        return a.left < b.left
    end)
    local rows, row = {}, nil
    for _, entry in ipairs(entries) do
        if not row or abs(row.top - entry.top) > 1 or abs(row.bottom - entry.bottom) > 1 then
            row = { top = entry.top, bottom = entry.bottom, entries = {} }
            rows[#rows + 1] = row
        end
        row.entries[#row.entries + 1] = entry
    end
    local runs = {}
    for _, currentRow in ipairs(rows) do
        table.sort(currentRow.entries, function(a, b) return a.left < b.left end)
        local run
        for _, entry in ipairs(currentRow.entries) do
            local previous = run and run.last
            local adjacent = previous and entry.left >= previous.right - 1
                and entry.left - previous.right <= min(previous.width, entry.width) * 0.5
            if not run or run.bag ~= entry.bag or not adjacent then
                run = { bag = entry.bag, first = entry, last = entry, level = entry.level, matchesSearch = entry.matchesSearch }
                runs[#runs + 1] = run
            else
                run.last = entry
                run.level = max(run.level, entry.level)
                run.matchesSearch = run.matchesSearch or entry.matchesSearch
            end
        end
    end
    return runs
end

function Colors:ShowGroup(container, state, index, run, alpha)
    if not CanAccessFrame(container) or not CanAccessFrame(run.first.button) or not CanAccessFrame(run.last.button) then return end
    local group = state.groups[index]
    if not group then
        group = CreateFrame("Frame", nil, container)
        state.groups[index] = group
        group:Hide()
    end
    if not group.edgesReady then
        local ok, detail = pcall(function()
            group:EnableMouse(false)
            group.edges = group.edges or {}
            NewEdges(group, group.edges)
            AnchorEdges(group.edges, group, 0, GROUP_EDGE_WIDTH)
            group.edgesReady = true
        end)
        if not ok then
            group:Hide()
            Addon:ReportOnce("colors-groups", Diagnostic("Bag colors could not create a group outline.", detail))
            return
        end
    end
    local first, last = run.first.button, run.last.button
    -- Keep a readable perimeter above the native item surfaces. The stroke
    -- stays outside the item rectangles, leaving artwork and count glyphs clear.
    local level = run.level + 1
    if not IsNumber(level) or level <= run.level then group:Hide(); return end
    group:SetFrameLevel(level)
    group:ClearAllPoints()
    group:SetPoint("TOPLEFT", first, "TOPLEFT", -GROUP_PADDING, GROUP_PADDING)
    group:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", GROUP_PADDING, -GROUP_PADDING)
    ShowEdges(group.edges, run.first.color, alpha * (run.matchesSearch and 1 or 0.2))
    group:Show()
end

function Colors:Refresh(settled)
    if self.refreshing then return end
    if self.driverReady then self.driver:Hide() end
    -- Creating/anchoring decoration on native frame descendants waits for combat to end.
    if type(InCombatLockdown) ~= "function" then return end
    local combat = InCombatLockdown()
    if not Addon.IsPublic(combat) or combat ~= false then return end
    self.bankFooterSettling = settled == true
    self.refreshing = true
    self.bankFooterChanged = false
    local ok, detail = pcall(function()
        for _, state in pairs(self.slots) do HideSlot(state) end
        for _, state in pairs(self.icons) do HideSlot(state) end
        for _, state in pairs(self.containers) do
            for _, group in ipairs(state.groups) do group:Hide() end
        end
        local appearance = Addon.db and Addon.db.appearance
        if type(appearance) ~= "table" then self:RestoreBankDivider(); return end
        local mode = appearance.mode
        local containers = self:FindContainers()
        for _, container in ipairs(containers) do self:WatchContainer(container) end
        if mode ~= "tint" and mode ~= "outline" then self:RestoreBankDivider(); return end
        local tintAlpha = GetAlpha(appearance.tintAlpha, 0.5)
        local outlineAlpha = GetAlpha(appearance.outlineAlpha, 0.75)
        local bagOutlineAlpha = GetAlpha(appearance.bagOutlineAlpha, 0.75)
        self:RefreshPalette(appearance)
        self:RefreshBagIcons(bagOutlineAlpha)
        local style = mode == "tint" and "tint" or (appearance.outline == "groups" and "groups" or "slots")
        local alpha = mode == "tint" and tintAlpha or outlineAlpha
        for _, container in ipairs(containers) do
            local entries = self:CollectEntries(container, style, alpha)
            if style == "groups" then
                for index, run in ipairs(RowRuns(entries)) do
                    self:ShowGroup(container, self.containers[container], index, run, outlineAlpha)
                end
            end
        end
        local bankPanel, bankEntries = self:RefreshBank(appearance, style, alpha, bagOutlineAlpha)
        if bankPanel and style == "groups" then
            for index, run in ipairs(RowRuns(bankEntries)) do
                self:ShowGroup(bankPanel, self.containers[bankPanel], index, run, outlineAlpha)
            end
        end
    end)
    self.refreshing = false
    self.bankFooterSettling = nil
    if not ok then
        for _, state in pairs(self.slots) do HideSlot(state) end
        for _, state in pairs(self.icons) do HideSlot(state) end
        for _, state in pairs(self.containers) do
            for _, group in ipairs(state.groups) do group:Hide() end
        end
        self:RestoreBankFooter()
        self.bankFooterChanged = false
        Addon:ReportOnce("colors-refresh", Diagnostic("Bag colors could not update.", detail))
    end
    local change = self.bankFooterChanged
    local settleAgain = ok and change and not settled
    self.bankFooterChanged = false
    -- Successful cleanup after an external recovery needs a fresh measurement;
    -- successful growth gets only its bounded settled/readback pass.
    if settleAgain then self:RequestRefresh(change == "growth") end
end

function Colors:EnsureDriver()
    if self.driverReady then return true end
    local ok, detail = pcall(function()
        if not self.driver then self.driver = CreateFrame("Frame") end
        if not self.driverUpdate then
            self.driverUpdate = function()
                self.driver:Hide()
                local settled = self.bankFooterSettleQueued
                self.bankFooterSettleQueued = nil
                self:Refresh(settled)
            end
        end
        self.driver:Hide()
        self.driver:SetScript("OnUpdate", self.driverUpdate)
        self.driverReady = true
    end)
    if not ok then Addon:ReportOnce("colors-driver", Diagnostic("Bag colors could not start their redraw handler; a later inventory update will retry.", detail)) end
    return self.driverReady == true
end

function Colors:EnsureGenerateHook()
    if self.globalHooks.generate then return end
    -- Hook concrete containers/buttons, rather than a mixin already copied into pooled instances.
    if type(hooksecurefunc) == "function" and type(ContainerFrame_GenerateFrame) == "function" then
        if not self.generateRefresh then self.generateRefresh = function() self:RequestRefresh() end end
        local ok, detail = pcall(hooksecurefunc, "ContainerFrame_GenerateFrame", self.generateRefresh)
        if ok then
            self.globalHooks.generate = true
        else
            Addon:ReportOnce("colors-hook-generate", Diagnostic("Bag colors could not attach to native bag creation.", detail))
        end
    end
end

function Colors:Initialize()
    self:EnsureBankSizeTrace()
    self:EnsureDriver()
    self:EnsureGenerateHook()
    self:Refresh()
end

function Colors:OnEvent(event)
    self:EnsureBankSizeTrace()
    self:RequestRefresh()
end
