-- Contract simulations only: native rendering and combat/taint still need WoW.
local source = REPO_ROOT .. "/src/ForTheHoard/Movement.lua"
local combat, cursorX, cursorY, created, nativeCalls, hookCalls, cursorItem, textureCount
local restricted = setmetatable({}, { __eq = function() error("restricted comparison") end })
local addon
local fractions = { TOPLEFT = { 0, 1 }, TOPRIGHT = { 1, 1 }, BOTTOMLEFT = { 0, 0 }, BOTTOMRIGHT = { 1, 0 } }

local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 0.00001, (message or "coordinate") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local methods = {}
function methods:GetParent() return self.parent end
function methods:GetName() return self.name end
function methods:GetBagID() return self.bag end
function methods:IsCombinedBagContainer() return self.kind == "combined" end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:GetWidth()
    local left, right = self.points and self.points.TOPLEFT, self.points and self.points.TOPRIGHT
    if left and right and left[2] == right[2] and left[3] == "TOPLEFT" and right[3] == "TOPRIGHT" then
        return left[2]:GetWidth() + right[4] - left[4]
    end
    return self.width
end
function methods:GetHeight() return self.height end
function methods:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
function methods:GetFrameLevel() return self.level end
function methods:IsForbidden() return self.forbidden or false end
function methods:IsShown() return self.shown end
function methods:SetHeight(height) self.height = height end
function methods:SetWidth(width) self.width = width end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetAlpha(alpha) self.alpha = alpha end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetVertexColor(...) self.vertex = { ... } end
function methods:SetAllPoints(target) self.allPoints = target end
function methods:CreateTexture()
    textureCount = textureCount + 1
    return setmetatable({ parent = self, shown = true, scripts = {}, hooks = {} }, { __index = methods })
end
function methods:CreateFontString() error("movement must not add a visible drag label") end
function methods:SetParent() error("movement must not reparent native windows") end
function methods:GetPoint() return unpack(self.point or {}) end
function methods:GetNumPoints()
    local count = 0
    for _ in pairs(self.points or {}) do count = count + 1 end
    return count
end
function methods:SetFrameLevel(level) self.level = level; self.levelWrites = (self.levelWrites or 0) + 1 end
function methods:EnableMouse(enabled) self.mouse = enabled end
function methods:RegisterForDrag(button) self.dragButton = button end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:HookScript(event, fn)
    self.hooks[event] = self.hooks[event] or {}
    table.insert(self.hooks[event], fn)
    return true
end
function methods:Fire(event, ...)
    if self.scripts[event] then self.scripts[event](self, ...) end
    for _, fn in ipairs(self.hooks[event] or {}) do fn(self, ...) end
end
function methods:Show()
    if not self.shown then self.shown = true; self:Fire("OnShow") end
end
function methods:Hide()
    if self.shown then self.shown = false; self:Fire("OnHide") end
end
function methods:ClearAllPoints()
    if self.native then assert(not combat, "native movement in combat") end
    self.point = nil
    self.points = nil
    self.clears = self.clears + 1
end
function methods:SetPoint(point, relative, relativePoint, x, y)
    if self.native then assert(not combat, "native movement in combat") end
    if self.failNextPoint then self.failNextPoint = nil; error("injected native anchor failure") end
    self.point = { point, relative, relativePoint, x, y }
    self.points = self.points or {}
    self.points[point] = self.point
end
function methods:GetLeft()
    if self.badGeometry then return restricted end
    if not self.parent then return 0 end
    local p, relative, rp, x = unpack(self.point)
    local ratio = relative:GetEffectiveScale() / self:GetEffectiveScale()
    return (relative:GetLeft() + fractions[rp][1] * relative:GetWidth()) * ratio + x - fractions[p][1] * self:GetWidth()
end
function methods:GetTop()
    if self.badGeometry then return restricted end
    if not self.parent then return self.height end
    local p, relative, rp, _, y = unpack(self.point)
    local ratio = relative:GetEffectiveScale() / self:GetEffectiveScale()
    local bottom = relative:GetTop() - relative.height
    return (bottom + fractions[rp][2] * relative.height) * ratio + y + (1 - fractions[p][2]) * self.height
end

local function newFrame(parent)
    created = created + 1
    local frame = setmetatable({
        parent = parent, width = 400, height = 300, scale = 1, level = 10,
        shown = true, scripts = {}, hooks = {}, clears = 0,
    }, { __index = methods })
    if parent and parent.children then parent.children[#parent.children + 1] = frame end
    return frame
end

local function setup(position, missingFrame, configure)
    combat, cursorX, cursorY, created, nativeCalls, hookCalls, cursorItem, textureCount = false, 400, 600, 0, 0, 0, false, 0
    CreateFrame = function(_, _, parent) return newFrame(parent) end
    InCombatLockdown = function() return combat end
    GetCursorPosition = function() return cursorX, cursorY end
    GetCursorInfo = function() if cursorItem then return "item", 2318 end end
    CursorHasItem = nil
    C_RestrictedActions = nil
    GameTooltip = nil
    BankFrame, ContainerFrameContainer, EventRegistry, UpdateUIPanelPositions = nil, nil, nil, nil
    ContainerFrame_GenerateFrame, UpdateScaleForFitForOpenPanels = nil, nil
    ContainerFrameSettingsManager, ShowUIPanel, HideUIPanel = nil, nil, nil
    for i = 1, 16 do _G["ContainerFrame" .. i] = nil end
    UIParent = newFrame()
    UIParent.width, UIParent.height, UIParent.scale = 1200, 900, 0.8
    ContainerFrameCombinedBags = nil
    if not missingFrame then ContainerFrameCombinedBags = newFrame(UIParent) end
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags.native = true
        ContainerFrameCombinedBags.kind = "combined"
        ContainerFrameCombinedBags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 85)
    end
    UpdateContainerFrameAnchors = function()
        nativeCalls = nativeCalls + 1
        if ContainerFrameCombinedBags then
            ContainerFrameCombinedBags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 85)
        end
    end
    hooksecurefunc = function(target, name, callback)
        hookCalls = hookCalls + 1
        if type(target) == "string" then target, name, callback = _G, target, name end
        local original = target[name]
        assert(type(original) == "function", "hook must name a real native function")
        target[name] = function(...) original(...); callback(...) end
    end
    addon = {
        db = { movement = { enabled = true } }, char = { position = position, bagPositions = {} },
        IsPublic = function(value) return not rawequal(value, restricted) end,
        ReportOnce = function() end,
    }
    addon.IsFiniteNumber = function(value)
        return addon.IsPublic(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
    end
    if configure then configure(addon) end
    assert(loadfile(source))("ForTheHoard", addon)
    addon.Movement:Initialize()
    return addon.Movement, ContainerFrameCombinedBags
end

local function mover(movement, frame)
    return assert(movement:GetMover(frame or ContainerFrameCombinedBags), "native window has no movement controller")
end

local function saved(x, y)
    return { point = "TOPLEFT", relativePoint = "TOPLEFT", x = x, y = y }
end

local function assertUIPosition(frame, x, y)
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    near(frame:GetLeft() * ratio, x, "left")
    near(frame:GetTop() * ratio - UIParent:GetTop(), y, "top")
end

-- Model only the public native layout contract: separate windows have a shared
-- parent and chained points, while bank panel events follow private reflow.
-- Native evidence: forever/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua
-- and forever/Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua
-- in https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns.
local function setupWindows(character, options)
    local bags, baselines, bank, callbacks = {}, {}, nil, {}
    local movement, combined = setup(character and character.position, false, function(host)
        host.char = character or { bagPositions = {} }
        host.char.bagPositions = host.char.bagPositions or {}
        ContainerFrameContainer = newFrame(UIParent)
        ContainerFrameContainer.width, ContainerFrameContainer.height = UIParent.width, UIParent.height
        ContainerFrameContainer:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        ContainerFrameContainer.ContainerFrames = bags
        ContainerFrameSettingsManager = { IsUsingCombinedBags = function() return false end }
        for index, id in ipairs(options and options.ids or { 0, 1, 2, 5, -1 }) do
            local frame = newFrame(ContainerFrameContainer)
            frame.native, frame.bag, frame.name = true, id, "ContainerFrame" .. index
            frame.width, frame.height = options and options.chainToCombined and 120 or 180, 260
            frame.scripts.OnDragStart = function() error("native body drag must not be replaced or invoked") end
            bags[index] = frame
            _G[frame.name] = frame
            if options and options.initialClosed then frame.shown = false end
        end
        bank = newFrame(UIParent)
        bank.native, bank.name, bank.width, bank.height = true, "BankFrame", 560, 460
        BankFrame = bank
        if options and options.individualLayout then ContainerFrameCombinedBags.shown = false end
        local function layoutBank()
            if options and options.trace then table.insert(options.trace, "bank") end
            bank:ClearAllPoints()
            bank:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -100)
        end
        local originalLayout = UpdateContainerFrameAnchors
        UpdateContainerFrameAnchors = function()
            if options and options.trace then table.insert(options.trace, "bags") end
            originalLayout()
            if options and options.individualLayout then
                -- Native placement stacks only shown windows upward, then
                -- starts a new column. This fixture records its public rects.
                local right, used, columnWidth, measured = UIParent.width - 20, 0, 0, 0
                for _, frame in ipairs(bags) do
                    if frame:IsShown() then
                        local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
                        local width, height = frame.width * ratio, frame.height * ratio
                        -- Native UpdateContainerFrameAnchors subtracts frame
                        -- heights from H-85 while its actual chain also adds
                        -- spacing. Preserve that distinction in this case.
                        local budgetUsed = options.nativeHeightOnlyBudget and measured or used
                        local budget = UIParent.height - (options.nativeHeightOnlyBudget and 85 or 100)
                        if budgetUsed > 0 and budgetUsed + height > budget then
                            right, used, columnWidth, measured = right - columnWidth - 11, 0, 0, 0
                        end
                        frame:ClearAllPoints()
                        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right / ratio, (85 + used) / ratio)
                        used, columnWidth = used + height + 8, math.max(columnWidth, width)
                        measured = measured + height
                    end
                end
                return
            end
            for index, frame in ipairs(bags) do
                -- Native GetContainerScale uses bank geometry. The fixture needs
                -- only two outcomes to expose a missed final native bag reflow.
                if options and options.bankDependentScale then
                    frame.scale = bank.point and bank:GetLeft() > 100 and 0.75 or 1
                end
                frame:ClearAllPoints()
                if index == 1 and options and options.chainToCombined then
                    frame:SetPoint("BOTTOMRIGHT", ContainerFrameCombinedBags, "BOTTOMLEFT", -8, 0)
                elseif index == 1 then frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 85)
                else frame:SetPoint("BOTTOMRIGHT", bags[index - 1], "BOTTOMLEFT", -8, 0) end
            end
        end
        UpdateUIPanelPositions = layoutBank
        UpdateScaleForFitForOpenPanels = function() bank.scale = 0.75; layoutBank() end
        EventRegistry = {
            RegisterCallback = function(_, event, callback, owner)
                callbacks[event] = callbacks[event] or {}
                table.insert(callbacks[event], { callback = callback, owner = owner })
            end,
            TriggerEvent = function(_, event, ...)
                for _, entry in ipairs(callbacks[event] or {}) do entry.callback(entry.owner, ...) end
            end,
        }
        -- Reflow of an already shown bank deliberately bypasses the public
        -- UpdateUIPanelPositions wrapper, just as the native panel delegate can.
        ShowUIPanel = function(frame)
            frame:Show()
            layoutBank()
            EventRegistry:TriggerEvent("UIParentPanelManager.ShowUIPanel", frame, false, "fixture")
        end
        HideUIPanel = function(frame)
            frame:Hide()
            layoutBank()
            EventRegistry:TriggerEvent("UIParentPanelManager.HideUIPanel", frame, false)
        end
        ContainerFrame_GenerateFrame = function(frame, _, id)
            frame.bag = id
            frame:Show()
            if type(frame.Raise) == "function" then frame:Raise() end
            UpdateContainerFrameAnchors()
            return frame
        end
        UpdateContainerFrameAnchors()
        layoutBank()
        for _, frame in ipairs(bags) do
            if frame.point then
                local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
                baselines[frame.bag] = { frame:GetLeft() * ratio, frame:GetTop() * ratio - UIParent:GetTop() }
            end
        end
        if options and options.decorate then options.decorate(host, bags, bank, ContainerFrameCombinedBags) end
    end)
    return movement, bags, bank, combined, baselines, callbacks
end

-- Anchor resets and changing native scales must preserve screen placement.
do
    local movement, frame = setup(saved(130, -75))
    assertUIPosition(frame, 130, -75)
    local count = created
    for index = 1, 20 do
        frame.scale = index % 2 == 0 and 0.75 or 1
        UpdateContainerFrameAnchors()
        movement:Refresh()
        assertUIPosition(frame, 130, -75)
    end
    assert(created == count and hookCalls == 1, "refresh leaked handles or hooks")
    assert(#frame.hooks.OnShow == 1 and #frame.hooks.OnSizeChanged == 1)
    frame:Hide()
    frame:Show()
    UpdateContainerFrameAnchors()
    assertUIPosition(frame, 130, -75)
end

-- Cursor deltas use physical pixels; save canonical UIParent units on release.
do
    local movement, frame = setup(saved(100, -100))
    local controller = mover(movement, frame)
    controller.handle:Fire("OnDragStart")
    assert(controller.drag)
    cursorX, cursorY = 480, 560
    controller.handle:Fire("OnUpdate")
    assertUIPosition(frame, 200, -150)
    UpdateContainerFrameAnchors()
    assertUIPosition(frame, 200, -150)
    controller.handle:Fire("OnDragStop")
    near(addon.char.position.x, 200)
    near(addon.char.position.y, -150)
    assert(not controller.drag and not controller.handle.scripts.OnUpdate)
    local persisted = addon.char.position
    movement, frame = setup(persisted)
    assertUIPosition(frame, 200, -150)
end

-- Clamp at all edges; retain the desired saved placement across resolution changes.
do
    local movement, frame = setup(saved(1100, -850))
    assertUIPosition(frame, 800, -600)
    near(addon.char.position.x, 1100)
    UIParent.width, UIParent.height = 1800, 1400
    movement:OnEvent("DISPLAY_SIZE_CHANGED")
    assertUIPosition(frame, 1100, -850)
    frame.width, frame.height = 2000, 1600
    frame:Fire("OnSizeChanged")
    assertUIPosition(frame, 0, 0)
end

-- Turning movement off restores native anchors but keeps the saved position.
do
    local movement, frame = setup(saved(100, -100))
    addon.db.movement.enabled = false
    movement:Refresh()
    assert(frame.point[1] == "BOTTOMRIGHT" and not mover(movement, frame).handle:IsShown())
    UpdateContainerFrameAnchors()
    assert(frame.point[1] == "BOTTOMRIGHT")
    addon.db.movement.enabled = true
    movement:Refresh()
    assertUIPosition(frame, 100, -100)
    movement:ResetPosition()
    assert(addon.char.position == nil and frame.point[1] == "BOTTOMRIGHT")
end

-- Combat start commits only the last safe drag update, without native frame writes.
do
    local movement, frame = setup(saved(100, -100))
    local controller = mover(movement, frame)
    controller:StartDrag()
    cursorX = 440
    controller:UpdateDrag()
    local clears = frame.clears
    combat = true
    movement:OnEvent("PLAYER_REGEN_DISABLED")
    controller:StartDrag()
    movement:Refresh()
    assert(not controller.drag and frame.clears == clears)
    near(addon.char.position.x, 150)
    movement:ResetPosition()
    assert(addon.char.position == nil and frame.clears == clears)
    combat = false
    movement:OnEvent("PLAYER_REGEN_ENABLED")
    assert(frame.point[1] == "BOTTOMRIGHT")
end

-- Disabled-in-combat state is reconciled after combat without losing the save.
do
    local movement, frame = setup(saved(100, -100))
    combat = true
    addon.db.movement.enabled = false
    movement:Refresh()
    combat = false
    movement:OnEvent("PLAYER_REGEN_ENABLED")
    assert(frame.point[1] == "BOTTOMRIGHT" and addon.char.position.x == 100)
end

-- Transient native availability can recover at a later event.
do
    local movement = setup(saved(120, -80), true)
    assert(movement:GetMover(ContainerFrameCombinedBags) == nil)
    ContainerFrameCombinedBags = newFrame(UIParent)
    ContainerFrameCombinedBags.native = true
    ContainerFrameCombinedBags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 85)
    movement:OnEvent("ADDON_LOADED")
    assertUIPosition(ContainerFrameCombinedBags, 120, -80)
end

-- Malformed/restricted geometry and saves must never be arithmetically consumed.
do
    local movement, frame = setup({ point = "TOPLEFT", relativePoint = "TOPLEFT", x = restricted, y = 0 })
    assert(frame.point[1] == "BOTTOMRIGHT")
    assert(rawequal(addon.char.position.x, restricted), "invalid save was overwritten")
    addon.char.position = saved(100, -100)
    frame.badGeometry = true
    local controller = mover(movement, frame)
    controller:StartDrag()
    assert(not controller.drag)
    frame.badGeometry = false
    frame.scale = 0
    local clears = frame.clears
    movement:Refresh()
    assert(frame.clears == clears)
end

-- Fullscreen reparenting belongs to Blizzard, so leave its anchors alone.
do
    local movement, frame = setup(saved(100, -100))
    frame.parent = newFrame(UIParent)
    local clears = frame.clears
    movement:Refresh()
    movement:Refresh()
    assert(frame.clears == clears)
end

-- A denied native permission must prevent attachment and writes until recovery.
do
    local movement = setup(saved(100, -100), true)
    ContainerFrameCombinedBags = newFrame(UIParent)
    ContainerFrameCombinedBags.native = true
    ContainerFrameCombinedBags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 85)
    C_RestrictedActions = { CheckAllowProtectedFunctions = function() return false end }
    local count = created
    movement:Refresh()
    assert(movement:GetMover(ContainerFrameCombinedBags) == nil and created == count)
    C_RestrictedActions.CheckAllowProtectedFunctions = function() return true end
    movement:OnEvent("ADDON_RESTRICTION_STATE_CHANGED")
    assert(movement:GetMover(ContainerFrameCombinedBags))
    local frame = ContainerFrameCombinedBags
    frame.forbidden = true
    local clears = frame.clears
    local controller = mover(movement, frame)
    controller:StartDrag()
    movement:Refresh()
    assert(not controller.drag and frame.clears == clears)
end

-- Unexpected native errors remain visible and cannot leave the recursion guard stuck.
do
    local movement, frame = setup(saved(100, -100))
    frame.failNextPoint = true
    local controller = mover(movement, frame)
    local ok, message = pcall(controller.ApplyPosition, controller, 120, -100)
    assert(not ok and message:find("injected native anchor failure", 1, true))
    assert(not controller.applying)
    UpdateContainerFrameAnchors()
    assertUIPosition(frame, 100, -100)
end

-- Display changes reapply and clamp existing placements.
do
    local movement, frame = setup(saved(100, -100))
    local clears = frame.clears
    UIParent.width, UIParent.height = 420, 350
    movement:OnEvent("DISPLAY_SIZE_CHANGED")
    assert(frame.clears > clears, "screen changes must still reapply position")
    assertUIPosition(frame, 20, -50)
end

-- No-change inventory events must not keep rewriting unchanged anchors. Native
-- reflow, changed saves and scale changes still need to restore actual geometry.
do
    local character = { bankPosition = saved(310, -140), bagPositions = { [0] = saved(100, -100) } }
    local movement, bags, bank = setupWindows(character)
    local counts = {}
    for _, frame in ipairs(bags) do counts[frame] = frame.clears end
    local bankClears, handles = bank.clears, created
    for _ = 1, 1000 do
        movement:OnEvent("BAG_UPDATE_DELAYED")
        movement:OnEvent("PLAYERBANKSLOTS_CHANGED")
    end
    for _, frame in ipairs(bags) do assert(frame.clears == counts[frame], "unchanged bag anchor was rewritten") end
    assert(bank.clears == bankClears and created == handles, "unchanged bank anchor or handles were recreated")
    UpdateContainerFrameAnchors()
    assertUIPosition(bags[1], 100, -100)
    assert(bags[1].clears > counts[bags[1]], "native reflow did not restore the saved bag")
    character.bagPositions[0] = saved(150, -120)
    movement:Refresh()
    assertUIPosition(bags[1], 150, -120)
    bags[1].scale = 0.75
    movement:OnEvent("UI_SCALE_CHANGED")
    assertUIPosition(bags[1], 150, -120)
end

-- Equal coordinates on a follower are not an independent anchor. Restricted or
-- failed point reads cannot be compared or cached as a successful placement.
do
    local movement, frame = setup(saved(100, -100))
    local controller = mover(movement, frame)
    local original = frame.GetPoint
    frame.GetPoint = function() return restricted, restricted, restricted, restricted, restricted end
    local clears = frame.clears
    assert(controller:ApplyPosition(100, -100))
    assert(frame.clears == clears + 1)
    frame.GetPoint = function() error("transient point read") end
    assert(controller:ApplyPosition(100, -100))
    frame.GetPoint = original
    local reference = newFrame(UIParent)
    reference:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
    frame:SetPoint("TOPLEFT", reference, "TOPLEFT", 0, 0)
    assert(controller:ApplyPosition(100, -100))
    local _, relative = frame:GetPoint()
    assert(relative == UIParent, "equal-position native follower was not detached")
end

-- Native chained bag points must all be resolved before any saved position is
-- applied. Unsaved followers remain in place without acquiring a saved record.
do
    local character = { position = saved(70, -60), bankPosition = saved(300, -150),
        bagPositions = { [0] = saved(100, -100), [1] = saved(350, -120) } }
    local movement, bags, bank, combined, native = setupWindows(character)
    assertUIPosition(combined, 70, -60)
    assertUIPosition(bank, 300, -150)
    assertUIPosition(bags[1], 100, -100)
    assertUIPosition(bags[2], 350, -120)
    for index = 3, #bags do
        local frame = bags[index]
        assertUIPosition(frame, unpack(native[frame.bag]))
        assert(frame:GetParent() == ContainerFrameContainer, "native bag parent changed")
        assert(frame.point[2] == UIParent, "unsaved follower still follows another bag")
        assert(character.bagPositions[frame.bag] == nil, "native baseline was persisted")
    end
    local controller = mover(movement, bags[1])
    controller:StartDrag()
    cursorX, cursorY = cursorX + 80, cursorY - 40
    controller:UpdateDrag()
    assertUIPosition(bags[1], 200, -150)
    assertUIPosition(bags[3], unpack(native[2]))
    controller:FinishDrag(true)
    UpdateContainerFrameAnchors()
    assertUIPosition(bags[1], 200, -150)
    assertUIPosition(bags[2], 350, -120)
    assertUIPosition(bags[3], unpack(native[2]))
end

-- Persistence follows the physical bag ID rather than the reused native frame.
-- Rebinding during a drag commits to its original ID and leaves the new save intact.
do
    local character = { bagPositions = { [1] = saved(200, -100), [3] = saved(600, -200) } }
    local movement, bags, _, _, native = setupWindows(character)
    local frame, controller = bags[2], mover(movement, bags[2])
    local handle = controller.handle
    controller:StartDrag()
    cursorX = cursorX + 40
    controller:UpdateDrag()
    ContainerFrame_GenerateFrame(frame, 16, 3)
    assert(not controller.drag, "reused frame kept an old bag drag")
    near(character.bagPositions[1].x, 250)
    near(character.bagPositions[3].x, 600)
    assertUIPosition(frame, 600, -200)
    assert(mover(movement, frame) == controller and controller.handle == handle)
    ContainerFrame_GenerateFrame(frame, 16, 4)
    assert(character.bagPositions[4] == nil, "new bag inherited the prior physical bag save")
    assertUIPosition(frame, unpack(native[1]))
    ContainerFrame_GenerateFrame(frame, 16, 1)
    assertUIPosition(frame, 250, -100)
end

-- Existing bank placement must survive actual post-layout notifications. A
-- different panel opens while bank remains shown, so a bank OnShow hook cannot help.
do
    local movement, bags, bank, _, _, callbacks = setupWindows({ bankPosition = saved(320, -170), bagPositions = {} })
    assert(#callbacks["UIParentPanelManager.ShowUIPanel"] == 1)
    assert(#callbacks["UIParentPanelManager.HideUIPanel"] == 1)
    local unrelated = newFrame(UIParent)
    ShowUIPanel(unrelated)
    assertUIPosition(bank, 320, -170)
    HideUIPanel(unrelated)
    assertUIPosition(bank, 320, -170)
    UpdateUIPanelPositions(bank)
    assertUIPosition(bank, 320, -170)
    UpdateScaleForFitForOpenPanels()
    assertUIPosition(bank, 320, -170)
    HideUIPanel(bank)
    local clears = bank.clears
    movement:Refresh()
    assert(bank.clears == clears and bank.point[5] == -100, "hidden bank received a saved-position write")
    ShowUIPanel(bank)
    assertUIPosition(bank, 320, -170)
    bank.width, bank.height = 2000, 1600
    bank:Fire("OnSizeChanged")
    assertUIPosition(bank, 0, 0)
    assert(addon.char.bankPosition.x == 320, "clamping overwrote desired bank placement")
    assert(bags[1]:GetParent() == ContainerFrameContainer)
end

-- Every supported save is independent. Disabling preserves all records and
-- restores native layouts; reset clears known IDs even when their bags are absent.
do
    local future = saved(11, -12)
    local character = { position = saved(70, -60), bankPosition = saved(300, -150), bagPositions = { [99] = future } }
    for id = -1, 5 do character.bagPositions[id] = saved(120 + id * 30, -80 - id * 20) end
    local movement, bags, bank, combined, native = setupWindows(character)
    addon.db.movement.enabled = false
    movement:Refresh()
    assert(combined.point[1] == "BOTTOMRIGHT" and bank.point[5] == -100)
    for _, frame in ipairs(bags) do
        assertUIPosition(frame, unpack(native[frame.bag]))
        assert(not mover(movement, frame).handle:IsShown())
    end
    assert(character.position.x == 70 and character.bankPosition.x == 300)
    for id = -1, 5 do assert(character.bagPositions[id]) end
    addon.db.movement.enabled = true
    movement:Refresh()
    assertUIPosition(combined, 70, -60)
    assertUIPosition(bank, 300, -150)
    assertUIPosition(bags[1], 120, -80)
    movement:ResetPosition()
    assert(character.position == nil and character.bankPosition == nil)
    for id = -1, 5 do assert(character.bagPositions[id] == nil) end
    assert(character.bagPositions[99] == future, "reset removed an unknown future bag key")
    assert(combined.point[1] == "BOTTOMRIGHT" and bank.point[5] == -100)
    for index, frame in ipairs(bags) do
        assertUIPosition(frame, unpack(native[frame.bag]))
        assert(frame.point[2] == (index == 1 and UIParent or bags[index - 1]), "reset did not restore native bag chains")
    end
end

-- The default layout needs no addon point writes. Combined-window dragging
-- still detaches native separate followers before the first cursor movement.
do
    local movement, bags, bank, combined, native = setupWindows({ bagPositions = {} }, { chainToCombined = true })
    local counts = {}
    for _, frame in ipairs(bags) do counts[frame] = frame.clears end
    local combinedClears, bankClears = combined.clears, bank.clears
    for _ = 1, 20 do movement:Refresh() end
    assert(combined.clears == combinedClears and bank.clears == bankClears)
    for _, frame in ipairs(bags) do assert(frame.clears == counts[frame], "default layout was unnecessarily detached") end
    assert(bags[1].point[2] == combined)
    local controller = mover(movement, combined)
    controller:StartDrag()
    cursorX = cursorX - 80
    controller:UpdateDrag()
    for _, frame in ipairs(bags) do
        assertUIPosition(frame, unpack(native[frame.bag]))
        assert(frame.point[2] == UIParent, "combined dragging moved a native bag follower")
        assert(addon.char.bagPositions[frame.bag] == nil)
    end
    controller:FinishDrag(true)
end

-- Denied/foreign windows prevent a global restore from indirectly moving them.
-- After recovery, restore native bank placement before bag scale/layout reads it.
do
    local trace = {}
    local movement, bags, bank = setupWindows({ bankPosition = saved(300, -100), bagPositions = { [1] = saved(200, -100) } }, { trace = trace })
    C_RestrictedActions = { CheckAllowProtectedFunctions = function(frame) return frame ~= bags[2] end }
    addon.db.movement.enabled = false
    local calls, clears = nativeCalls, bags[2].clears
    movement:Refresh()
    assert(nativeCalls == calls and bags[2].clears == clears, "native global bypassed denied bag restoration")
    C_RestrictedActions = nil
    bags[2].parent = newFrame(UIParent)
    movement:Refresh()
    assert(nativeCalls == calls and bags[2].clears == clears, "native global moved a foreign-parent bag")
    bags[2].parent = ContainerFrameContainer
    for index = #trace, 1, -1 do trace[index] = nil end
    -- Bank was safely restored during the first disabled pass; put it through
    -- a fresh custom cycle so the following disable must restore both kinds.
    addon.db.movement.enabled = true
    movement:Refresh()
    for index = #trace, 1, -1 do trace[index] = nil end
    addon.db.movement.enabled = false
    movement:Refresh()
    assert(trace[1] == "bank" and trace[2] == "bags", "bag native scale/layout ran before bank restoration")
    assertUIPosition(bank, 40, -100)
end

-- Without a verified native layout hook, custom placement must not apply.
do
    local movement, frame = setup(saved(100, -100), false, function() UpdateContainerFrameAnchors = nil end)
    assert(frame.point[1] == "BOTTOMRIGHT" and not mover(movement, frame).handle:IsShown())
    frame:Fire("OnSizeChanged")
    mover(movement, frame):StartDrag()
    assert(not mover(movement, frame).drag)
    assert(frame.point[1] == "BOTTOMRIGHT", "size callback applied a position without a restorable native layout")
    local count = created
    local foreign = newFrame(newFrame(UIParent))
    foreign.bag = 1
    ContainerFrame1 = foreign
    movement:Refresh()
    assert(movement:GetMover(foreign) == nil and created == count + 2, "foreign window received an owned handle")
end

-- A custom bank can alter native bag scale even when no bag has a custom save.
-- Restore it before reflowing bags; an inaccessible bank must defer the whole
-- dependency until a later permitted refresh.
for _, action in ipairs({ "disable", "reset" }) do
    local trace = {}
    local movement, bags, bank = setupWindows({ bankPosition = saved(450, -100), bagPositions = {} },
        { bankDependentScale = true, trace = trace })
    UpdateContainerFrameAnchors()
    near(bags[1].scale, 0.75)
    C_RestrictedActions = { CheckAllowProtectedFunctions = function(frame) return frame ~= bank end }
    local calls, clears = nativeCalls, bank.clears
    if action == "disable" then addon.db.movement.enabled = false; movement:Refresh()
    else movement:ResetPosition() end
    assert(nativeCalls == calls and bank.clears == clears, "bank-dependent native restore ran before access recovered")
    C_RestrictedActions = nil
    for index = #trace, 1, -1 do trace[index] = nil end
    movement:OnEvent("ADDON_RESTRICTION_STATE_CHANGED")
    assert(trace[1] == "bank" and trace[2] == "bags", "bank-only restore skipped or misordered native bag reflow")
    assertUIPosition(bank, 40, -100)
    near(bags[1].scale, 1)
end

-- Cursor ownership, combat and native permissions apply to bank and individual
-- handles as they do to the combined window. Native scripts remain untouched.
do
    local movement, bags, bank = setupWindows({ bankPosition = saved(300, -100), bagPositions = { [1] = saved(200, -100) } })
    local controller, bankMover = mover(movement, bags[2]), mover(movement, bank)
    local originalDrag = bags[2].scripts.OnDragStart
    cursorItem = true
    local clears = bags[2].clears + bank.clears
    controller:StartDrag()
    bankMover:StartDrag()
    assert(not controller.drag and not bankMover.drag and cursorItem, "drag consumed or ignored a cursor item")
    assert(bags[2].clears + bank.clears == clears, "cursor item triggered native anchor writes")
    GetCursorInfo = function() return restricted end
    controller:StartDrag()
    assert(not controller.drag, "restricted cursor data was treated as empty")
    GetCursorInfo = nil
    controller:StartDrag()
    assert(not controller.drag, "missing cursor contracts were treated as empty")
    CursorHasItem = function() return true end
    controller:StartDrag()
    assert(not controller.drag, "native item cursor fallback was ignored")
    CursorHasItem = function() return false end
    cursorItem = false
    controller:StartDrag()
    cursorX = cursorX + 40
    controller:UpdateDrag()
    clears = bags[2].clears + bank.clears
    combat = true
    movement:OnEvent("PLAYER_REGEN_DISABLED")
    bankMover:StartDrag()
    movement:Refresh()
    assert(not controller.drag and not bankMover.drag and bags[2].clears + bank.clears == clears)
    near(addon.char.bagPositions[1].x, 250)
    combat = false
    movement:OnEvent("PLAYER_REGEN_ENABLED")
    assertUIPosition(bags[2], 250, -100)
    assert(bags[2].scripts.OnDragStart == originalDrag, "native body drag handler changed")
    bank.forbidden = true
    bags[2].parent = newFrame(UIParent)
    clears = bags[2].clears + bank.clears
    bankMover:StartDrag()
    controller:StartDrag()
    movement:Refresh()
    assert(not controller.drag and not bankMover.drag and bags[2].clears + bank.clears == clears)
end

-- Every supported physical bag and bank writes its own record on release.
-- The combined backpack record stays separate from physical backpack ID zero.
do
    local character = { position = saved(70, -60), bankPosition = saved(300, -100), bagPositions = {} }
    local movement, bags, bank = setupWindows(character)
    local bankMover = mover(movement, bank)
    bankMover:StartDrag()
    cursorX, cursorY = cursorX + 40, cursorY - 20
    bankMover:UpdateDrag()
    bankMover:FinishDrag(true)
    near(character.bankPosition.x, 350)
    near(character.bankPosition.y, -125)
    near(character.position.x, 70)
    for _, frame in ipairs(bags) do
        local controller = mover(movement, frame)
        controller:StartDrag()
        cursorX = cursorX - 16
        controller:UpdateDrag()
        controller:FinishDrag(true)
        local record = assert(character.bagPositions[frame.bag], "physical bag drag did not save its ID")
        assertUIPosition(frame, record.x, record.y)
    end
    for _, id in ipairs({ 3, 4 }) do
        ContainerFrame_GenerateFrame(bags[2], 16, id)
        local controller = mover(movement, bags[2])
        controller:StartDrag()
        cursorX = cursorX - 16
        controller:UpdateDrag()
        controller:FinishDrag(true)
        assert(character.bagPositions[id], "later physical bag identity could not be saved")
    end
    near(character.position.x, 70)
    near(character.bankPosition.x, 350)
end

-- Lazy bank UI discovery attaches on the actual addon event, retaining the
-- already installed native panel hook and the character's bank save.
do
    local movement = setup(nil, false, function(host)
        host.char.bankPosition = saved(300, -100)
        UpdateUIPanelPositions = function()
            if BankFrame then BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -100) end
        end
    end)
    BankFrame = newFrame(UIParent)
    BankFrame.native = true
    BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -100)
    local count = created
    movement:OnEvent("ADDON_LOADED", "Blizzard_BankUI")
    assertUIPosition(BankFrame, 300, -100)
    assert(mover(movement, BankFrame).handle:IsShown() and created == count + 1)
    movement:OnEvent("ADDON_LOADED", "Blizzard_BankUI")
    assert(created == count + 1)
end

-- Native frame reuse and repeated native layout do not accumulate handles,
-- callbacks or textures. The header strip stays within native title controls.
do
    local movement, bags, bank, combined, _, callbacks = setupWindows({ bagPositions = {} })
    local frames, textures, hooks = created, textureCount, hookCalls
    for _, frame in ipairs({ combined, bank, unpack(bags) }) do
        local handle = mover(movement, frame).handle
        assert(handle:IsShown() and handle.mouse and handle.dragButton == "LeftButton")
        assert(handle.parent == frame and handle.height <= 23, "handle escaped the native header")
        if frame == combined or frame == bank then assert(frame.scripts.OnDragStart == nil) end
    end
    for index = 1, 30 do
        ContainerFrame_GenerateFrame(bags[2], 16, index % 2 == 0 and 1 or 3)
        movement:Refresh()
        ShowUIPanel(bank)
    end
    assert(created == frames and textureCount == textures and hookCalls == hooks, "window refresh leaked resources")
    assert(#callbacks["UIParentPanelManager.ShowUIPanel"] == 1 and #callbacks["UIParentPanelManager.HideUIPanel"] == 1)
    for _, frame in ipairs({ combined, bank, unpack(bags) }) do
        assert(#frame.hooks.OnShow == 1 and #frame.hooks.OnHide == 1 and #frame.hooks.OnSizeChanged == 1)
    end
end

-- Native setup can fail before a handle exists or after some resources/hooks
-- exist. Keep the first diagnostic and recover on a later refresh using those
-- same owned objects, without registering already completed native hooks again.
for _, failurePoint in ipairs({ "create", "point", "hook" }) do
    local failing, handles, reports, reported = true, {}, {}, {}
    local detail = "injected attachment " .. failurePoint
    local movement, frame = setup(saved(130, -75), false, function(host)
        host.ReportOnce = function(_, key, message)
            if not reported[key] then reported[key] = true; table.insert(reports, message) end
        end
        local originalCreate = CreateFrame
        CreateFrame = function(...)
            if failurePoint == "create" and failing then error(detail) end
            local handle = originalCreate(...)
            table.insert(handles, handle)
            if failurePoint == "point" then
                handle.SetPoint = function(self, ...)
                    if failing then error(detail) end
                    return methods.SetPoint(self, ...)
                end
            end
            return handle
        end
        if failurePoint == "hook" then
            ContainerFrameCombinedBags.HookScript = function(self, event, callback)
                if event == "OnHide" and failing then error(detail) end
                return methods.HookScript(self, event, callback)
            end
        end
    end)
    local controller = mover(movement, frame)
    local retainedHandle = controller.handle
    assert(#reports == 1 and reports[1]:find(detail, 1, true), "setup lost its original diagnostic")
    assert(not controller.drag and frame.point[1] == "BOTTOMRIGHT", "partially configured handle moved the native window")
    if retainedHandle then assert(not retainedHandle:IsShown()) end
    failing = false
    movement:Refresh()
    assert(mover(movement, frame) == controller, "setup recovery replaced its retained controller")
    assert(#handles == 1 and (not retainedHandle or controller.handle == retainedHandle), "setup recovery leaked a native handle")
    assert(controller.handle:IsShown() and controller.handle.scripts.OnDragStart)
    assertUIPosition(frame, 130, -75)
    local count, hooks = created, hookCalls
    for _ = 1, 5 do movement:Refresh() end
    assert(created == count and hookCalls == hooks and #handles == 1)
    assert(#frame.hooks.OnShow == 1 and #frame.hooks.OnHide == 1 and #frame.hooks.OnSizeChanged == 1)
end

local function visibleRects(bags)
    local result = {}
    for _, frame in ipairs(bags) do
        if frame:IsShown() then
            local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            result[#result + 1] = { frame = frame, x = frame:GetLeft() * ratio,
                y = UIParent:GetTop() - frame:GetTop() * ratio,
                width = frame.width * ratio, height = frame.height * ratio }
        end
    end
    return result
end

local function assertNoOverlap(bags)
    local rectangles = visibleRects(bags)
    for index, rect in ipairs(rectangles) do
        assert(rect.x >= -0.00001 and rect.y >= -0.00001
            and rect.x + rect.width <= UIParent.width + 0.00001
            and rect.y + rect.height <= UIParent.height + 0.00001, "automatic bag position escaped the screen")
        for otherIndex = index + 1, #rectangles do
            local other = rectangles[otherIndex]
            assert(rect.x + rect.width <= other.x or other.x + other.width <= rect.x
                or rect.y + rect.height <= other.y or other.y + other.height <= rect.y,
                "automatically placed bags overlap")
        end
    end
    return rectangles
end

-- Opening order can change which physical bag receives a pooled native frame.
-- Every prefix of all 24 four-bag permutations must remain a usable layout.
local function permutations(values, first, run)
    if first > #values then run(values); return end
    for index = first, #values do
        values[first], values[index] = values[index], values[first]
        permutations(values, first + 1, run)
        values[first], values[index] = values[index], values[first]
    end
end
permutations({ 0, 1, 2, 5 }, 1, function(order)
    local character = { bagPositions = {} }
    local movement, bags = setupWindows(character, { individualLayout = true, initialClosed = true })
    for index, id in ipairs(order) do
        ContainerFrame_GenerateFrame(bags[index], 16, id)
        assertNoOverlap(bags)
        assert(next(character.bagPositions) == nil, "first-open placement must not create remembered positions")
    end
    local writes = {}
    for _, frame in ipairs(bags) do writes[frame] = frame.clears end
    for _ = 1, 10 do movement:Refresh() end
    for _, frame in ipairs(bags) do assert(frame.clears == writes[frame], "valid native defaults should not be rewritten") end
end)

-- A remembered bag can occupy another bag's native default. Place the newly
-- opened, unsaved bag around it, retaining both the saved choice and no-save status.
do
    local character = { bagPositions = {} }
    local movement, bags = setupWindows(character, { individualLayout = true, initialClosed = true })
    ContainerFrame_GenerateFrame(bags[1], 16, 1)
    ContainerFrame_GenerateFrame(bags[2], 16, 2)
    local defaults = visibleRects(bags)
    local occupied = defaults[2]
    bags[2]:Hide(); UpdateContainerFrameAnchors()
    local remembered = saved(occupied.x, -occupied.y)
    character.bagPositions[1] = remembered
    movement:Refresh()
    ContainerFrame_GenerateFrame(bags[2], 16, 2)
    assertNoOverlap(bags)
    assertUIPosition(bags[1], remembered.x, remembered.y)
    assert(character.bagPositions[1] == remembered and character.bagPositions[2] == nil,
        "collision avoidance must preserve user positions and leave automatic placement transient")
    local controller = mover(movement, bags[1])
    controller:StartDrag()
    controller:UpdateDrag()
    controller:FinishDrag(true)
    assertNoOverlap(bags)
    movement:ResetPosition()
    assert(next(character.bagPositions) == nil)
    assertNoOverlap(bags)
    for _, frame in ipairs(bags) do frame:Hide() end
    UpdateContainerFrameAnchors()
    ContainerFrame_GenerateFrame(bags[1], 16, 2)
    ContainerFrame_GenerateFrame(bags[2], 16, 1)
    assertNoOverlap(bags)
    assert(next(character.bagPositions) == nil, "reset/reverse reopening persisted automatic coordinates")
end

-- All physical positions, mixed capacities and scales also use native-first
-- defaults, including after remembered positions are cleared through Settings.
do
    local character = { bagPositions = {} }
    local movement, bags = setupWindows(character, { individualLayout = true, initialClosed = true,
        ids = { 0, 1, 2, 3, 4, 5, -1 } })
    for index, frame in ipairs(bags) do
        frame.width, frame.height = 140 + index * 12, 130 + index * 22
        frame.scale = index % 2 == 0 and 0.75 or 1
    end
    for index = #bags, 1, -1 do
        ContainerFrame_GenerateFrame(bags[index], 16, bags[index].bag)
        assertNoOverlap(bags)
    end
    local handles = created
    character.bagPositions[0] = saved(5000, -5000)
    movement:Refresh()
    assertNoOverlap(bags)
    assert(character.bagPositions[0].x == 5000 and character.bagPositions[0].y == -5000,
        "display clamping must not rewrite a preferred saved position")
    movement:ResetPosition()
    assertNoOverlap(bags)
    assert(created == handles and next(character.bagPositions) == nil, "reset rebuilt handles or remembered auto layout")
end

-- Native's column budget counts 807 pixels of frame height, which fits H-85,
-- while five actual 8-pixel anchor gaps put the sixth frame's top at -32.
-- Repair that overflow by starting the next column at the existing bottom
-- baseline. A nearest-to-invalid-native-point search incorrectly chooses top.
do
    local character = { bagPositions = {} }
    local movement, bags = setupWindows(character, { individualLayout = true, initialClosed = true,
        nativeHeightOnlyBudget = true, ids = { 0, 1, 2, 3, 4, 5 } })
    local heights = { 150, 122, 125, 130, 140, 140 }
    for index, frame in ipairs(bags) do frame.height = heights[index] end
    for index, frame in ipairs(bags) do ContainerFrame_GenerateFrame(frame, 16, index - 1) end
    local rectangles = assertNoOverlap(bags)
    local first, last = rectangles[1], rectangles[6]
    near(first.y + first.height, UIParent.height - 85, "native bottom baseline")
    near(last.y + last.height, first.y + first.height, "new column should begin at the native bottom baseline")
    assert(last.x + last.width <= first.x, "top-overflow repair did not start a column to the left")
    assert(next(character.bagPositions) == nil, "new-column placement must remain transient")
    local used = 0
    for index = 1, 5 do
        local rect = rectangles[index]
        near(rect.x, UIParent.width - 20 - rect.width, "valid native column x")
        near(rect.y, UIParent.height - 85 - used - rect.height, "valid native column y")
        used = used + rect.height + 8
    end
    movement:ResetPosition()
    rectangles = assertNoOverlap(bags)
    near(rectangles[6].y + rectangles[6].height, rectangles[1].y + rectangles[1].height,
        "reset should retain bottom-first new-column placement")
    assert(next(character.bagPositions) == nil)
    local remembered = saved(700, -25)
    character.bagPositions[5] = remembered
    UpdateContainerFrameAnchors()
    assertNoOverlap(bags)
    assertUIPosition(bags[6], remembered.x, remembered.y)
    assert(character.bagPositions[5] == remembered, "overflow correction replaced an explicit saved position")
end

-- A manually positioned bag can occupy the nearest bottom slot. Continue
-- leftward along the bottom baseline without moving that saved obstacle or
-- sending the overflowing automatic bag back to the top of the screen.
do
    local obstacle = saved(816, -675)
    local character = { bagPositions = { [-1] = obstacle } }
    local movement, bags = setupWindows(character, { individualLayout = true, initialClosed = true,
        nativeHeightOnlyBudget = true, ids = { 0, 1, 2, 3, 4, 5, -1 } })
    -- The saved obstacle reaches the screen's bottom (900), which must not
    -- replace the unsaved native column baseline (815).
    local heights = { 150, 122, 125, 130, 140, 140, 225 }
    for index, frame in ipairs(bags) do frame.height = heights[index] end
    for index, frame in ipairs(bags) do ContainerFrame_GenerateFrame(frame, 16, index == 7 and -1 or index - 1) end
    local rectangles = assertNoOverlap(bags)
    local first, last, blocker = rectangles[1], rectangles[6], rectangles[7]
    near(last.y + last.height, first.y + first.height, "blocked bottom slot should select another bottom position")
    assert(last.x + last.width <= blocker.x, "overflow repair did not continue left around the saved bottom obstacle")
    assertUIPosition(bags[7], obstacle.x, obstacle.y)
    assert(character.bagPositions[-1] == obstacle and character.bagPositions[5] == nil,
        "bottom fallback changed manual persistence or remembered automatic placement")
    movement:ResetPosition()
    rectangles = assertNoOverlap(bags)
    near(rectangles[6].y + rectangles[6].height, rectangles[1].y + rectangles[1].height)
    assert(next(character.bagPositions) == nil)
end

-- Model the documented native compositing/top-level behavior, not renderer
-- pixels or undocumented SetFrameLevel descendant propagation. Internal levels
-- deliberately span 0..511; each locally flattened window is one external unit.
local function setupOrdering()
    local state = { order = {}, roots = {}, nodes = {}, raises = 0, flagWrites = 0, clicks = 0, hovers = 0, reports = {} }
    local function effective(frame)
        if frame.effectiveResult ~= nil then return frame.effectiveResult end
        return frame.flatten == true or frame.topLevel == true or frame.parent and effective(frame.parent) or false
    end
    local function raise(frame)
        for index = #state.order, 1, -1 do if state.order[index] == frame then table.remove(state.order, index) end end
        state.order[#state.order + 1] = frame
        state.raises = state.raises + 1
    end
    local function flag(frame, which, value)
        assert(not combat, "addon changed native grouping in combat")
        state.flagWrites = state.flagWrites + 1
        frame.flagWrites = (frame.flagWrites or 0) + 1
        local phase = frame.flagFailure and frame.flagFailure(which, value)
        if phase == "before" then error("injected native grouping failure") end
        if frame.ignoreFlag ~= which then frame[which] = value end
        if frame.topChangesFlatten and which == "topLevel" then frame.flatten = value end
        if phase == "after" then error("injected native grouping failure after write") end
    end
    local function decorate(frame, initiallyTop)
        frame.level, frame.topLevel, frame.flatten, frame.strata = 2, initiallyTop, false, "MEDIUM"
        frame.children, frame.mouse = {}, true
        frame.originalParent, frame.originalNativeDrag = frame.parent, frame.scripts.OnDragStart
        frame.GetFlattensRenderLayers = function(self) return self.flatten end
        frame.GetEffectivelyFlattensRenderLayers = effective
        frame.IsToplevel = function(self) return self.topLevel end
        frame.SetToplevel = function(self, value) flag(self, "topLevel", value) end
        frame.SetFlattensRenderLayers = function(self, value) flag(self, "flatten", value) end
        frame.Raise = function(self)
            assert(not combat, "addon raised a native window in combat")
            if self.raiseFailure then error("injected native raise failure") end
            raise(self)
        end
        frame.SetFrameStrata = function() error("native strata must stay unchanged") end
        frame.SetFixedFrameLevel = function() error("native fixed-level flags must stay unchanged") end
        state.roots[#state.roots + 1] = frame
        local function child(parent, name, level, x, y, width, height, mouse)
            local node = newFrame(parent)
            node.name, node.level, node.strata, node.mouse, node.children = name, level, "MEDIUM", mouse, {}
            node.originalParent, node.originalLevel, node.fixed = parent, level, name == "Title"
            node:SetSize(width, height)
            node:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
            state.nodes[#state.nodes + 1] = node
            return node
        end
        frame.Bg = child(frame, "Bg", 0, 0, 0, frame.width, frame.height, false)
        frame.Item = child(frame, "Item", 10, 20, 60, 36, 36, true)
        frame.Portrait = child(frame, "Portrait", 400, 0, 0, 32, 32, false)
        frame.NineSlice = child(frame, "NineSlice", 500, 0, 0, frame.width, frame.height, false)
        frame.Title = child(frame, "Title", 510, 32, 0, frame.width - 64, 24, false)
        frame.Close = child(frame, "Close", 511, frame.width - 26, 4, 20, 20, true)
        child(frame.Item, "Cooldown", 11, 0, 0, 36, 36, false)
        frame.Item:SetScript("OnClick", function() state.clicks = state.clicks + 1; state.clickedCursor = cursorItem end)
        frame.Item:SetScript("OnEnter", function() state.hovers = state.hovers + 1 end)
        frame.Item.originalClick, frame.Item.originalHover = frame.Item.scripts.OnClick, frame.Item.scripts.OnEnter
    end
    local character = { bagPositions = { [0] = saved(190, -100), [1] = saved(100, -150), [3] = saved(100, -150) } }
    local movement, bags, bank, combined = setupWindows(character, { individualLayout = true, initialClosed = true,
        ids = { 0, 1 }, decorate = function(host, frames, bankFrame, combinedFrame)
            ContainerFrameContainer.topLevel = true -- Shared native parent already flattens effectively.
            host.ReportOnce = function(_, key, message) if not state.reports[key] then state.reports[key] = message end end
            decorate(combinedFrame, true); decorate(bankFrame, true)
            for _, frame in ipairs(frames) do decorate(frame, false) end
        end })
    function state:Unit(node)
        for _ = 1, 32 do
            if not node then return nil end
            if node.flatten == true or node.topLevel == true then return node end
            node = node.parent
        end
    end
    function state:Click(node)
        local ancestor = node
        for _ = 1, 32 do
            if not ancestor then break end
            if ancestor.topLevel then raise(ancestor); break end -- Documented native activation.
            ancestor = ancestor.parent
        end
        node:Fire("OnMouseDown", "LeftButton")
        node:Fire("OnClick", "LeftButton")
    end
    function state:Untouched()
        for _, node in ipairs(self.nodes) do
            assert(node.level == node.originalLevel and not node.levelWrites and node.parent == node.originalParent
                and node.strata == "MEDIUM" and node.fixed == (node.name == "Title"),
                "grouping changed a native descendant level, parent, strata or fixed flag")
        end
        for _, frame in ipairs(self.roots) do
            assert(frame.level == 2 and not frame.levelWrites and frame.parent == frame.originalParent and frame.strata == "MEDIUM")
            assert(frame.Item.scripts.OnClick == frame.Item.originalClick and frame.Item.scripts.OnEnter == frame.Item.originalHover
                and frame.scripts.OnDragStart == frame.originalNativeDrag, "grouping replaced native input scripts")
        end
    end
    return movement, bags, state, bank, combined
end

-- Each frame gets its OWN native unit, even though its shared parent already
-- flattens effectively. Native child input is preserved, not intercepted.
do
    local movement, bags, state = setupOrdering()
    local back, front = bags[2], bags[1]
    assert(back:GetEffectivelyFlattensRenderLayers() and not back:GetFlattensRenderLayers())
    ContainerFrame_GenerateFrame(back, 16, 1)
    ContainerFrame_GenerateFrame(front, 16, 0)
    assert(back.topLevel and back.flatten and front.topLevel and front.flatten)
    assert(state.order[#state.order] == front and state:Unit(back.Item) == back and state:Unit(front.Title) == front,
        "separate windows did not acquire independent native groups")
    assertUIPosition(back, 100, -150); assertUIPosition(front, 190, -100)
    local calls = state.raises
    for _ = 1, 20 do movement:Refresh() end
    assert(state.raises == calls, "routine refresh repeatedly raised windows")
    state:Click(back.Item)
    back.Item:Fire("OnEnter")
    assert(state.order[#state.order] == back and state.clicks == 1 and state.hovers == 1)
    cursorItem = true
    state:Click(front.Item)
    assert(state.clicks == 2 and state.clickedCursor == true and cursorItem, "window grouping changed native cursor/item input")
    cursorItem = false
    local controller = mover(movement, back)
    controller.handle:Fire("OnMouseDown", "LeftButton")
    assert(state.order[#state.order] == back, "an exposed underlying title handle did not bring its window forward")
    local x, y = addon.char.bagPositions[1].x, addon.char.bagPositions[1].y
    controller:StartDrag(); controller:FinishDrag(true)
    assertUIPosition(back, x, y)
    local late = newFrame(back)
    late.level = back.Item.level + 1 -- Owned Colors cartouche, created after movement setup.
    assert(state:Unit(late) == back, "late decoration escaped its native window group")
    local count, hooks, flags = created, hookCalls, state.flagWrites
    for index = 1, 1000 do mover(movement, bags[index % 2 + 1]).handle:Fire("OnMouseDown", "LeftButton") end
    assert(created == count and hookCalls == hooks and state.flagWrites == flags and #state.order <= #state.roots,
        "focus accumulated objects, hooks or repeated flag writes")
    front.raiseFailure = true
    calls = state.raises
    for _ = 1, 3 do assert(pcall(mover(movement, front).handle.Fire, mover(movement, front).handle, "OnMouseDown", "LeftButton")) end
    assert(state.raises == calls and state.reports["movement-ordering"]:find("injected native raise failure", 1, true),
        "failed native Raise escaped input or lost its bounded diagnostic")
    front.raiseFailure = false
    mover(movement, front).handle:Fire("OnMouseDown", "LeftButton")
    assert(state.order[#state.order] == front, "native Raise did not recover on a later interaction")
    state:Untouched()
    -- A visible native frame can be rebound without hiding. Its original flags
    -- belong to that frame, not to the previously represented physical bag.
    ContainerFrame_GenerateFrame(back, 16, 3)
    assert(back.topLevel and back.flatten)
    assertUIPosition(back, 100, -150)
    addon.db.movement.enabled = false; movement:Refresh()
    assert(not back.topLevel and not back.flatten and not front.topLevel and not front.flatten,
        "no-hide bag reuse lost the original native frame flags")
    assert(addon.char.bagPositions[3].x == 100 and addon.char.bagPositions[3].y == -150,
        "grouping changed remembered placement during native restoration")
    state:Untouched()
end

-- Restore local flags exactly, including native top-level frames whose local
-- flatten flag began false, and setters which change both flags together.
for _, original in ipairs({ { false, false }, { false, true }, { true, false }, { true, true } }) do
    local movement, bags, state = setupOrdering()
    local frame = bags[1]
    frame.topLevel, frame.flatten, frame.topChangesFlatten = original[1], original[2], true
    local writes = state.flagWrites
    ContainerFrame_GenerateFrame(frame, 16, 0)
    assert(frame.topLevel and frame.flatten)
    if original[1] and original[2] then assert(state.flagWrites == writes, "native grouped frame was rewritten unnecessarily") end
    frame:Hide()
    assert(frame.topLevel == original[1] and frame.flatten == original[2], "hide did not restore original local flags")
    frame:Show()
    assert(frame.topLevel and frame.flatten)
    movement:ResetPosition()
    assert(frame.topLevel and frame.flatten, "position reset disabled active native grouping")
    addon.db.movement.enabled = false; movement:Refresh()
    assert(frame.topLevel == original[1] and frame.flatten == original[2])
    state:Untouched()
end

-- Partial native setters/readback failures roll back the captured flags. The
-- feature retries later without preventing geometry or native item behavior.
for _, failure in ipairs({ "top-after", "flatten-before", "flatten-after", "readback" }) do
    local movement, bags, state = setupOrdering()
    local frame, failing = bags[1], true
    frame.flagFailure = function(which, value)
        if not failing or not value then return end
        if failure == "top-after" and which == "topLevel" then return "after" end
        if failure == "flatten-before" and which == "flatten" then return "before" end
        if failure == "flatten-after" and which == "flatten" then return "after" end
    end
    if failure == "readback" then frame.ignoreFlag = "flatten" end
    ContainerFrame_GenerateFrame(frame, 16, 0)
    assert(not frame.topLevel and not frame.flatten, "partial grouping left a native flag behind")
    assertUIPosition(frame, 190, -100)
    assert(mover(movement, frame).handle:IsShown(), "unavailable grouping disabled independent movement")
    local count = 0; for _ in pairs(state.reports) do count = count + 1 end
    assert(count == 1, "grouping failure was swallowed or repeated")
    failing, frame.ignoreFlag = false, nil
    movement:Refresh()
    assert(frame.topLevel and frame.flatten, "grouping did not recover on a later update")
    state:Untouched()
end

-- Deferred restoration retains the baseline through combat, temporary denial,
-- unreadable identities and foreign parents; it never writes into that scope.
do
    local movement, bags, state = setupOrdering()
    local frame = bags[1]
    ContainerFrame_GenerateFrame(frame, 16, 0)
    local writes, raises = frame.flagWrites, state.raises
    combat = true
    mover(movement, frame).handle:Fire("OnMouseDown", "LeftButton")
    mover(movement, frame):StartDrag()
    frame:Hide()
    assert(frame.topLevel and frame.flatten and frame.flagWrites == writes and state.raises == raises)
    combat = false
    movement:OnEvent("PLAYER_REGEN_ENABLED")
    assert(not frame.topLevel and not frame.flatten, "hidden combat-deferred flags were not restored")
    frame:Show()
    local parent = frame.parent
    frame.parent = newFrame(UIParent)
    addon.db.movement.enabled = false
    writes = frame.flagWrites
    movement:Refresh()
    assert(frame.flagWrites == writes and frame.topLevel and frame.flatten, "restore wrote into a foreign parent")
    frame.parent = parent
    frame.bag = restricted
    movement:Refresh()
    assert(frame.flagWrites == writes, "restore used an unreadable physical identity")
    frame.bag = 0
    C_RestrictedActions = { CheckAllowProtectedFunctions = function(object) return object ~= frame end }
    movement:Refresh()
    assert(frame.flagWrites == writes, "restore ignored native permission denial")
    C_RestrictedActions = nil
    movement:OnEvent("ADDON_RESTRICTION_STATE_CHANGED")
    assert(not frame.topLevel and not frame.flatten)
    state:Untouched()
end

-- A setter can also fail during cleanup. Preserve its original baseline and
-- finish the restore later rather than adopting partially restored flags.
do
    local movement, bags, state = setupOrdering()
    local frame, failing = bags[1], true
    ContainerFrame_GenerateFrame(frame, 16, 0)
    frame.flagFailure = function(which, value) if failing and which == "flatten" and value == false then return "before" end end
    addon.db.movement.enabled = false
    movement:Refresh()
    assert(not frame.topLevel and frame.flatten, "fixture did not exercise partial cleanup")
    failing = false
    movement:Refresh()
    assert(not frame.topLevel and not frame.flatten, "cleanup retry lost its captured native baseline")
    state:Untouched()
end

-- Conditional-secret own/effective flag reads are unavailable information, not
-- false flags. Geometry remains usable, and public readback can recover later.
for _, unreadable in ipairs({ "own", "effective" }) do
    local movement, bags, state = setupOrdering()
    local frame, originalGetter = bags[1], bags[1].GetFlattensRenderLayers
    if unreadable == "own" then frame.GetFlattensRenderLayers = function() return restricted end
    else frame.effectiveResult = restricted end
    ContainerFrame_GenerateFrame(frame, 16, 0)
    assert(not frame.topLevel and not frame.flatten, "unreadable grouping state left a native mutation")
    assertUIPosition(frame, 190, -100)
    frame.GetFlattensRenderLayers, frame.effectiveResult = originalGetter, nil
    movement:Refresh()
    assert(frame.topLevel and frame.flatten, "public grouping state did not recover")
    state:Untouched()
end

-- HookScript can reject without throwing. Movement must stay inactive until
-- every required native callback confirms success, then reuse the first handle
-- and callback on an explicit-false retry.
for _, rejectedEvent in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do
    local failing, attempts, callbacks = true, {}, {}
    local movement, frame = setup(saved(130, -75), false, function()
        ContainerFrameCombinedBags.HookScript = function(self, event, callback)
            attempts[event] = (attempts[event] or 0) + 1
            if callbacks[event] then assert(callbacks[event] == callback, "hook retry replaced its callback") end
            callbacks[event] = callback
            if event == rejectedEvent and failing then return false end
            return methods.HookScript(self, event, callback)
        end
    end)
    local controller = mover(movement, frame)
    local handle, count = controller.handle, created
    assert(not controller.ready and not handle:IsShown() and frame.point[1] == "BOTTOMRIGHT",
        "a rejected native callback enabled movement")
    controller:StartDrag()
    assert(not controller.drag)
    local rejectedAttempts = attempts[rejectedEvent]
    failing = false
    movement:Refresh()
    assert(controller.ready and controller.handle == handle and created == count)
    assertUIPosition(frame, 130, -75)
    for _, event in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do
        assert(attempts[event] == (event == rejectedEvent and rejectedAttempts + 1 or 1))
        assert(#frame.hooks[event] == 1, "hook recovery duplicated a completed callback")
    end
end

-- An off-contract result can follow registration. It is neither success nor
-- a safe invitation to register again, even if the next call could succeed.
for _, resultKind in ipairs({ "nil", "secret", "number", "string" }) do
    for _, registered in ipairs({ false, true }) do
        local attempts, reports, callback, recovering = 0, {}, nil, false
        local movement, frame = setup(saved(130, -75), false, function(host)
            host.ReportOnce = function(_, key, message) reports[key] = reports[key] or message end
            ContainerFrameCombinedBags.HookScript = function(self, event, current)
                if event ~= "OnShow" then return methods.HookScript(self, event, current) end
                attempts = attempts + 1
                if callback then assert(callback == current) end
                callback = current
                if registered then methods.HookScript(self, event, current) end
                if recovering then return true end
                if resultKind == "secret" then return restricted end
                if resultKind == "number" then return 0 end
                if resultKind == "string" then return "ok" end
            end
        end)
        local controller = mover(movement, frame)
        local handle, count = controller.handle, created
        recovering = true
        for _ = 1, 20 do movement:Refresh() end
        frame:Hide(); frame:Show()
        controller:StartDrag()
        assert(attempts == 1 and created == count and controller.handle == handle,
            "uncertain hook setup duplicated resources")
        assert(not controller.ready and not controller.drag and not handle:IsShown()
            and frame.point[1] == "BOTTOMRIGHT", "unknown hook result enabled native takeover")
        assert(#(frame.hooks.OnShow or {}) == (registered and 1 or 0))
        assert(next(reports), "unknown hook setup lacked a diagnostic")
    end
end

local function resetCharacter()
    local character = { position = saved(70, -60), bankPosition = saved(300, -150),
        bagPositions = { [-1] = saved(120, -40), [99] = saved(11, -12), future = { keep = true } } }
    for id = 0, 5 do character.bagPositions[id] = saved(200 + id * 35, -80 - id * 20) end
    return character
end

-- The narrow reset clears exactly0..5 and actually restores native/default
-- placement, without committing a cancelled individual drag back into saves.
do
    local character = resetCharacter()
    local combinedSave, bankSave, keyringSave, future = character.position, character.bankPosition,
        character.bagPositions[-1], character.bagPositions[99]
    local movement, bags, bank, combined, native = setupWindows(character,
        { ids = { 0, 1, 2, 3, 4, 5, -1 }, individualLayout = true })
    local controller = mover(movement, bags[3])
    controller:StartDrag(); cursorX = cursorX + 40; controller:UpdateDrag()
    assert(controller.drag, "reset fixture never began its individual drag")
    local bankClears, bankPoint = bank.clears, bank.point
    movement:ResetBagPositions()
    assert(not controller.drag and not controller.handle.scripts.OnUpdate)
    controller.handle:Fire("OnDragStop")
    for id = 0, 5 do assert(character.bagPositions[id] == nil, "bag reset recreated a cleared save") end
    for _, frame in ipairs(bags) do
        if frame.bag >= 0 then assertUIPosition(frame, unpack(native[frame.bag])) end
    end
    assertUIPosition(bags[7], keyringSave.x, keyringSave.y)
    assert(character.position == combinedSave and character.bankPosition == bankSave
        and character.bagPositions[-1] == keyringSave and character.bagPositions[99] == future
        and character.bagPositions.future.keep, "bag reset changed another saved family")
    assert(bank.clears == bankClears and bank.point == bankPoint, "bag reset explicitly reanchored the bank")
    assert(not movement.bagResetPending)
end

-- The excluded family's active drag and unsaved current coordinates survive
-- the native carried-family reflow; its old saved record is not overwritten.
for _, excluded in ipairs({ "combined", "bank", "keyring" }) do
    local character = resetCharacter()
    local movement, bags, bank, combined = setupWindows(character,
        { ids = { 0, 1, 2, 3, 4, 5, -1 }, individualLayout = excluded ~= "combined" })
    local frame = excluded == "combined" and combined or excluded == "bank" and bank or bags[7]
    local controller = mover(movement, frame)
    controller:StartDrag(); cursorX = cursorX + 24; cursorY = cursorY - 16; controller:UpdateDrag()
    local drag = assert(controller.drag, "excluded drag did not start")
    local combinedSave, bankSave, keyringSave = character.position, character.bankPosition, character.bagPositions[-1]
    local x, y = drag.lastX, drag.lastY
    movement:ResetBagPositions()
    assert(controller.drag == drag and controller.handle.scripts.OnUpdate, "bag reset ended an excluded drag")
    assertUIPosition(frame, x, y)
    assert(character.position == combinedSave and character.bankPosition == bankSave and character.bagPositions[-1] == keyringSave,
        "bag reset saved another window's in-progress drag")
    controller:FinishDrag(false)
end

-- Closed windows need no native anchor writes. Their next real native
-- generation starts with cleared carried records and default positioning.
do
    local character = resetCharacter()
    local movement, bags, bank, combined = setupWindows(character,
        { ids = { 0, 1, 2, 3, 4, 5, -1 }, individualLayout = true, initialClosed = true })
    local calls, bankPoint, combinedPoint = nativeCalls, bank.point, combined.point
    movement:ResetBagPositions()
    assert(nativeCalls == calls and bank.point == bankPoint and combined.point == combinedPoint,
        "closed-bag reset performed a needless native reflow")
    assert(not movement.bagResetPending)
    ContainerFrame_GenerateFrame(bags[4], 16, 3)
    assert(character.bagPositions[3] == nil)
    local ratio = bags[4]:GetEffectiveScale() / UIParent:GetEffectiveScale()
    assertUIPosition(bags[4], UIParent.width - 20 - bags[4].width * ratio,
        -(UIParent.height - 85 - bags[4].height * ratio))
end

-- The request clears records immediately but defers unsafe family reflow.
-- Recovery must restore native placements without losing the excluded saves.
for _, restriction in ipairs({ "combat", "denied", "parent" }) do
    local character = resetCharacter()
    local movement, bags, bank, combined, native = setupWindows(character,
        { ids = { 0, 1, 2, 3, 4, 5, -1 }, individualLayout = true })
    local bankSave, keyringSave, parent = character.bankPosition, character.bagPositions[-1], bags[1].parent
    if restriction == "combat" then combat = true
    elseif restriction == "denied" then
        C_RestrictedActions = { CheckAllowProtectedFunctions = function(frame) return frame ~= bags[1] end }
    else bags[1].parent = newFrame(UIParent) end
    local calls, bankPoint = nativeCalls, bank.point
    movement:ResetBagPositions()
    for id = 0, 5 do assert(character.bagPositions[id] == nil) end
    assert(movement.bagResetPending and nativeCalls == calls and bank.point == bankPoint,
        "bag reset bypassed " .. restriction .. " restrictions")
    combat, C_RestrictedActions, bags[1].parent = false, nil, parent
    movement:OnEvent("PLAYER_REGEN_ENABLED")
    assert(not movement.bagResetPending and nativeCalls == calls + 1)
    for _, frame in ipairs(bags) do if frame.bag >= 0 then assertUIPosition(frame, unpack(native[frame.bag])) end end
    assert(character.bankPosition == bankSave and character.bagPositions[-1] == keyringSave)
end

do
    local character = resetCharacter()
    local movement, bags, bank, combined, native = setupWindows(character,
        { ids = { 0, 1, 2, 3, 4, 5, -1 }, individualLayout = true })
    local anchors, reports = UpdateContainerFrameAnchors, {}
    addon.ReportOnce = function(_, key, message) reports[key] = reports[key] or message end
    UpdateContainerFrameAnchors = function() error("injected bag reset layout failure") end
    movement:ResetBagPositions()
    assert(movement.bagResetPending and reports["movement-reset-bags"]:find("injected bag reset layout failure", 1, true))
    UpdateContainerFrameAnchors = anchors
    movement:Refresh()
    assert(not movement.bagResetPending)
    for _, frame in ipairs(bags) do if frame.bag >= 0 then assertUIPosition(frame, unpack(native[frame.bag])) end end
end

print("movement: native window grouping, lifecycle recovery, independent placement and combat checks passed")
