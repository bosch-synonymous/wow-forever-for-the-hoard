local _, Addon = ...

local Movement = { movers = {}, hooks = {}, discovered = {}, layoutFixed = {}, layoutFree = {}, layoutPlaced = {} }
Addon.Movement = Movement
local Mover = {}
Mover.__index = Mover

local function IsNumber(value)
    return Addon.IsFiniteNumber(value)
end

local function IsObject(value)
    return Addon.IsPublic(value) and (type(value) == "table" or type(value) == "userdata")
end

local function IsBag(value)
    return IsNumber(value) and value % 1 == 0 and (value == -1 or (value >= 0 and value <= 5))
end

local function IsResetBag(value)
    return IsBag(value) and value >= 0
end

local function IsEnabled()
    return type(Addon.db) == "table" and type(Addon.db.movement) == "table"
        and Addon.db.movement.enabled == true
end

local function IsInCombat()
    if type(InCombatLockdown) ~= "function" then return true end
    local combat = InCombatLockdown()
    return not Addon.IsPublic(combat) or combat ~= false
end

local function CanAccessFrame(frame)
    if not IsObject(frame) then return false end
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

local function Read(frame, method)
    if not CanAccessFrame(frame) or type(frame[method]) ~= "function" then return end
    local ok, value = pcall(frame[method], frame)
    if ok and Addon.IsPublic(value) then return value end
end

local function HasNativeParent(frame, kind)
    local parent = Read(frame, "GetParent")
    if not IsObject(UIParent) then return false end
    if parent == UIParent then return true end
    return kind == "bag" and CanAccessFrame(ContainerFrameContainer) and parent == ContainerFrameContainer
end

local function GetGeometry(frame, kind)
    if not HasNativeParent(frame, kind) or not CanAccessFrame(UIParent) then return end
    local parentScale, frameScale = Read(UIParent, "GetEffectiveScale"), Read(frame, "GetEffectiveScale")
    local width, height = Read(UIParent, "GetWidth"), Read(UIParent, "GetHeight")
    local frameWidth, frameHeight = Read(frame, "GetWidth"), Read(frame, "GetHeight")
    if not IsNumber(parentScale) or parentScale <= 0 or not IsNumber(frameScale) or frameScale <= 0
        or not IsNumber(width) or width <= 0 or not IsNumber(height) or height <= 0
        or not IsNumber(frameWidth) or frameWidth <= 0 or not IsNumber(frameHeight) or frameHeight <= 0 then return end
    local ratio = frameScale / parentScale
    frameWidth, frameHeight = frameWidth * ratio, frameHeight * ratio
    if not IsNumber(ratio) or ratio <= 0 or not IsNumber(frameWidth) or not IsNumber(frameHeight) then return end
    return ratio, width, height, frameWidth, frameHeight, parentScale
end

local function ReadCurrentPosition(frame, kind)
    local ratio = GetGeometry(frame, kind)
    if not ratio then return end
    local left, top = Read(frame, "GetLeft"), Read(frame, "GetTop")
    local parentLeft, parentTop = Read(UIParent, "GetLeft"), Read(UIParent, "GetTop")
    if not IsNumber(left) or not IsNumber(top) or not IsNumber(parentLeft) or not IsNumber(parentTop) then return end
    local x, y = left * ratio - parentLeft, top * ratio - parentTop
    if IsNumber(x) and IsNumber(y) then return x, y end
end

local function ReadPosition(position)
    if not Addon.IsPublic(position) or type(position) ~= "table" then return end
    if not Addon.IsPublic(position.point) or position.point ~= "TOPLEFT"
        or not Addon.IsPublic(position.relativePoint) or position.relativePoint ~= "TOPLEFT"
        or not IsNumber(position.x) or not IsNumber(position.y) then return end
    return position.x, position.y
end

local LAYOUT_GAP = 4

local function ClearList(list)
    for index = #list, 1, -1 do list[index] = nil end
end

local function FreePosition(rect, x, y, placed, width, height)
    if x < 0 or y < 0 or x + rect.width > width or y + rect.height > height then return false end
    for _, other in ipairs(placed) do
        if x < other.x + other.width + LAYOUT_GAP and x + rect.width + LAYOUT_GAP > other.x
            and y < other.y + other.height + LAYOUT_GAP and y + rect.height + LAYOUT_GAP > other.y then
            return false
        end
    end
    return true
end

local function FindFreePosition(rect, placed, width, height, columnBottom)
    if FreePosition(rect, rect.nativeX, rect.nativeY, placed, width, height) then
        return rect.nativeX, rect.nativeY
    end
    if rect.width > width or rect.height > height then return end
    -- Only seven physical carried bags exist. Candidate edges come from the
    -- screen and accepted rectangles, so the search is finite and small.
    local xs, ys = { 0, width - rect.width }, { 0, height - rect.height }
    local function Add(list, value, maximum)
        if IsNumber(value) then list[#list + 1] = math.max(0, math.min(value, maximum)) end
    end
    Add(xs, rect.nativeX, width - rect.width)
    Add(ys, rect.nativeY, height - rect.height)
    for _, other in ipairs(placed) do
        Add(xs, other.x - LAYOUT_GAP - rect.width, width - rect.width)
        Add(xs, other.x + other.width + LAYOUT_GAP, width - rect.width)
        Add(ys, other.y - LAYOUT_GAP - rect.height, height - rect.height)
        Add(ys, other.y + other.height + LAYOUT_GAP, height - rect.height)
    end
    if rect.nativeY < 0 and IsNumber(columnBottom) then
        -- Native height budgeting can omit the spaces between stacked bags.
        -- Wrap an overflowing bag to the bottom of a new column before looking
        -- for a location near its invalid, above-screen native rectangle.
        local y = columnBottom - rect.height
        local rightmost
        for _, x in ipairs(xs) do
            if FreePosition(rect, x, y, placed, width, height) and (not rightmost or x > rightmost) then
                rightmost = x
            end
        end
        if rightmost then return rightmost, y end
    end
    local bestX, bestY, bestDistance
    for _, x in ipairs(xs) do
        for _, y in ipairs(ys) do
            if FreePosition(rect, x, y, placed, width, height) then
                local distance = math.abs(x - rect.nativeX) + math.abs(y - rect.nativeY)
                if IsNumber(distance) and (not bestDistance or distance < bestDistance
                    or distance == bestDistance and (y < bestY or y == bestY and x > bestX)) then
                    bestX, bestY, bestDistance = x, y, distance
                end
            end
        end
    end
    return bestX, bestY
end

function Mover:GetSavedPosition()
    if type(Addon.char) ~= "table" then return end
    if self.kind == "combined" then return ReadPosition(Addon.char.position) end
    if self.kind == "bank" then return ReadPosition(Addon.char.bankPosition) end
    local positions = Addon.char.bagPositions
    if Addon.IsPublic(positions) and type(positions) == "table" and IsBag(self.identity) then
        return ReadPosition(positions[self.identity])
    end
end

function Mover:SavePosition(x, y, identity)
    if type(Addon.char) ~= "table" or not IsNumber(x) or not IsNumber(y) then return end
    local position = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = x, y = y }
    if self.kind == "combined" then
        Addon.char.position = position
    elseif self.kind == "bank" then
        Addon.char.bankPosition = position
    elseif IsBag(identity) then
        local positions = Addon.char.bagPositions
        if not Addon.IsPublic(positions) then return end
        if positions == nil then positions = {}; Addon.char.bagPositions = positions end
        if type(positions) == "table" then positions[identity] = position end
    end
end

function Mover:BindIdentity()
    if self.kind ~= "bag" then return end
    local identity = Read(self.frame, "GetBagID")
    if not IsBag(identity) then identity = nil end
    if self.identity ~= identity then
        -- Save against the identity captured before native frame reuse.
        self:FinishDrag(true)
        self.identity = identity
        self.applied = nil
    end
end

function Mover:CanMove()
    if not self.ready or IsInCombat() or not CanAccessFrame(self.frame) or not HasNativeParent(self.frame, self.kind) then return false end
    if self.kind == "bag" then
        local identity = Read(self.frame, "GetBagID")
        return IsBag(identity) and identity == self.identity
    end
    return true
end

local function OrderingProblem(failure)
    local detail = Addon.IsPublic(failure) and type(failure) == "string"
        and failure:gsub("[\r\n]", " "):sub(1, 180) or "Native window state is unavailable."
    Addon:ReportOnce("movement-ordering", "Inventory windows could not be grouped for overlap; movement remains available. " .. detail)
end

function Mover:HasOrderingScope(record)
    if record.kind ~= self.kind or not HasNativeParent(self.frame, self.kind) then return false end
    return self.kind ~= "bag" or IsBag(Read(self.frame, "GetBagID"))
end

function Mover:SetOrderingFlags(topLevel, flatten)
    if not self:CanMove() then error("Native window access is temporarily unavailable.") end
    local frame = self.frame
    local currentTop, currentFlatten = Read(frame, "IsToplevel"), Read(frame, "GetFlattensRenderLayers")
    if type(currentTop) ~= "boolean" or type(currentFlatten) ~= "boolean" then
        error("Native window grouping flags are unreadable.")
    end
    if currentTop ~= topLevel then frame:SetToplevel(topLevel) end
    -- Top-level can affect flattening. Read back its local flag after that setter.
    if not self:CanMove() then error("Native window access changed during grouping.") end
    currentFlatten = Read(frame, "GetFlattensRenderLayers")
    if type(currentFlatten) ~= "boolean" then error("Native window grouping flags are unreadable.") end
    if currentFlatten ~= flatten then frame:SetFlattensRenderLayers(flatten) end
    if Read(frame, "IsToplevel") ~= topLevel or Read(frame, "GetFlattensRenderLayers") ~= flatten then
        error("Native window grouping did not accept the requested flags.")
    end
end

function Mover:RestoreOrdering()
    local record = self.ordering
    if not record then return true end
    if not self:HasOrderingScope(record) or not self:CanMove() then record.restorePending = true; return false end
    local ok, failure = pcall(self.SetOrderingFlags, self, record.topLevel, record.flatten)
    if ok then self.ordering = nil
    else record.restorePending = true; OrderingProblem(failure) end
    return ok
end

function Mover:EnableOrdering()
    if not IsEnabled() or not self:CanMove() or Read(self.frame, "IsVisible") ~= true then return false end
    local record = self.ordering
    if record and not self:HasOrderingScope(record) then return false end
    if record and record.restorePending then
        if not self:RestoreOrdering() then return false end
        record = nil
    end
    local frame = self.frame
    if not record then
        local topLevel, flatten = Read(frame, "IsToplevel"), Read(frame, "GetFlattensRenderLayers")
        if type(topLevel) ~= "boolean" or type(flatten) ~= "boolean"
            or type(frame.SetToplevel) ~= "function" or type(frame.SetFlattensRenderLayers) ~= "function" then
            OrderingProblem("Native window grouping is unavailable on this client.")
            return false
        end
        -- Flags belong to the native frame, including a live rebind to another bag.
        record = { kind = self.kind, topLevel = topLevel, flatten = flatten }
        self.ordering = record -- Retain the original local flags before either setter.
    end
    local ok, failure = pcall(self.SetOrderingFlags, self, true, true)
    if ok and type(frame.GetEffectivelyFlattensRenderLayers) == "function"
        and Read(frame, "GetEffectivelyFlattensRenderLayers") ~= true then
        ok, failure = false, "Native window grouping did not become effective."
    end
    if not ok then
        record.ready = false
        OrderingProblem(failure)
        self:RestoreOrdering()
        return false
    end
    record.ready = true
    return true
end

function Mover:RaiseOrdering()
    if not self:EnableOrdering() or type(self.frame.Raise) ~= "function" then return false end
    local ok, failure = pcall(self.frame.Raise, self.frame)
    if not ok then OrderingProblem(failure) end
    return ok
end

function Mover:HasLayoutHook()
    if self.kind == "bank" then return Movement.hooks.UpdateUIPanelPositions or Movement.panelEvents end
    return Movement.hooks.UpdateContainerFrameAnchors
end

function Mover:ApplyPosition(x, y, nativePlacement)
    if self.applying or not self:CanMove() or not IsNumber(x) or not IsNumber(y) then return false end
    local ratio, width, height, frameWidth, frameHeight = GetGeometry(self.frame, self.kind)
    if not ratio then return false end
    -- Keep the title visible even if a window exceeds the available screen.
    if not nativePlacement then
        x = math.max(0, math.min(x, math.max(0, width - frameWidth)))
        y = math.min(0, math.max(y, math.min(0, frameHeight - height)))
    end
    local offsetX, offsetY = x / ratio, y / ratio
    if not IsNumber(offsetX) or not IsNumber(offsetY) then return false end
    -- A routine content update often leaves our anchor intact. Read it back
    -- instead of repeating native layout writes. Equal screen coordinates alone
    -- are insufficient: a bag still chained to another window must be detached.
    if Read(self.frame, "GetNumPoints") == 1 and type(self.frame.GetPoint) == "function" then
        local ok, point, relative, relativePoint, currentX, currentY = pcall(self.frame.GetPoint, self.frame, 1)
        if ok and Addon.IsPublic(point) and Addon.IsPublic(relative) and Addon.IsPublic(relativePoint)
            and point == "TOPLEFT" and relative == UIParent and relativePoint == "TOPLEFT"
            and IsNumber(currentX) and IsNumber(currentY) and currentX == offsetX and currentY == offsetY then
            self.applied = true
            return true, x, y
        end
    end
    self.applying = true
    local ok, failure = pcall(function()
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", offsetX, offsetY)
    end)
    self.applying = nil
    if not ok then self:FinishDrag(true); error(failure, 0) end
    self.applied = true
    return true, x, y
end

function Mover:FinishDrag(save)
    local drag = self.drag
    self.drag = nil
    if self.handle then self.handle:SetScript("OnUpdate", nil) end
    if save and drag then self:SavePosition(drag.lastX, drag.lastY, drag.identity) end
end

function Mover:UpdateDrag()
    local drag = self.drag
    if not drag then return end
    if self.kind == "bag" then self:BindIdentity() end
    if self.drag ~= drag or not IsEnabled() or not self:CanMove() or Read(self.frame, "IsShown") ~= true then
        self:FinishDrag(true)
        return
    end
    local _, _, _, _, _, parentScale = GetGeometry(self.frame, self.kind)
    if not parentScale then self:FinishDrag(true); return end
    local cursorX, cursorY = GetCursorPosition()
    if not IsNumber(cursorX) or not IsNumber(cursorY) then self:FinishDrag(true); return end
    local x = drag.startX + (cursorX - drag.cursorX) / parentScale
    local y = drag.startY + (cursorY - drag.cursorY) / parentScale
    if not IsNumber(x) or not IsNumber(y) then self:FinishDrag(true); return end
    if x ~= drag.lastX or y ~= drag.lastY then
        local applied, clampedX, clampedY = self:ApplyPosition(x, y)
        if applied then drag.lastX, drag.lastY = clampedX, clampedY end
    end
end

function Mover:StartDrag()
    self:BindIdentity()
    if not IsEnabled() or not self:HasLayoutHook() or not self:CanMove() or Read(self.frame, "IsShown") ~= true
        or type(GetCursorPosition) ~= "function" then return end
    if type(GetCursorInfo) == "function" then
        local ok, cursor = pcall(GetCursorInfo)
        if not ok or not Addon.IsPublic(cursor) or cursor ~= nil then return end
    elseif type(CursorHasItem) == "function" then
        local ok, hasItem = pcall(CursorHasItem)
        if not ok or not Addon.IsPublic(hasItem) or hasItem ~= false then return end
    else
        return
    end
    self:RaiseOrdering()
    -- Native separate bags are chained; resolve every window before detaching any.
    if self.kind ~= "bank" then Movement:DetachIndividualBags() end
    local x, y = ReadCurrentPosition(self.frame, self.kind)
    local cursorX, cursorY = GetCursorPosition()
    if not IsNumber(x) or not IsNumber(y) or not IsNumber(cursorX) or not IsNumber(cursorY) then return end
    Movement:FinishDrags(true)
    self.drag = { startX = x, startY = y, cursorX = cursorX, cursorY = cursorY,
        lastX = x, lastY = y, identity = self.identity }
    self.handle:SetScript("OnUpdate", function() self:UpdateDrag() end)
end

function Mover:RestorePosition()
    if self.applying or Movement.restoring or not IsEnabled() or not self:HasLayoutHook() then return end
    self:BindIdentity()
    if not self:CanMove() or Read(self.frame, "IsShown") ~= true then return end
    local x, y
    if self.drag then x, y = self.drag.lastX, self.drag.lastY else x, y = self:GetSavedPosition() end
    if x then self:ApplyPosition(x, y) end
end

function Mover:AttachScript(event)
    if self.frameHooks[event] then return true end
    if self.frameHookStatus[event] == "unknown" then return false end
    local ok, result = pcall(self.frame.HookScript, self.frame, event, self.frameCallbacks[event])
    if ok and Addon.IsPublic(result) and result == true then
        self.frameHooks[event], self.frameHookStatus[event] = true, "ready"
        return true
    end
    local uncertain = ok and (not Addon.IsPublic(result) or result ~= false)
    self.frameHookStatus[event] = uncertain and "unknown" or "retry"
    local detail = not ok and Addon.IsPublic(result) and type(result) == "string"
        and result:gsub("[\r\n]", " "):sub(1, 180) or ""
    Addon:ReportOnce("movement-script-" .. self.kind .. "-" .. event,
        uncertain and "A native window callback did not confirm setup; this window's movement remains inactive until reload."
        or "A native window callback could not attach; movement will retry on an inventory update. " .. detail)
    return false
end

function Mover:Attach()
    local frame = self.frame
    local handle = self.handle
    if not handle then
        handle = CreateFrame("Frame", nil, frame)
        self.handle = handle
    end
    if not self.handleCallbacks then
        self.handleCallbacks = {
            OnMouseDown = function() self:RaiseOrdering() end,
            OnDragStart = function() self:StartDrag() end,
            OnDragStop = function() self:UpdateDrag(); self:FinishDrag(true) end,
            OnHide = function() self:FinishDrag(true) end,
        }
    end
    if not self.handleConfigured then
        -- The native portrait, close control and lower search controls stay accessible.
        -- This transparent title strip adds no label, texture or native input replacement.
        handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, -4)
        handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -4)
        handle:SetHeight(23)
        local level = Read(frame, "GetFrameLevel")
        if IsNumber(level) then handle:SetFrameLevel(level + 20) end
        handle:EnableMouse(true)
        handle:RegisterForDrag("LeftButton")
        for event, callback in pairs(self.handleCallbacks) do handle:SetScript(event, callback) end
        self.handleConfigured = true
    end
    self.frameHooks = self.frameHooks or {}
    self.frameHookStatus = self.frameHookStatus or {}
    if not self.frameCallbacks then
        self.frameCallbacks = {
            OnShow = function() Movement:Refresh(); self:RaiseOrdering() end,
            OnHide = function() self:FinishDrag(true); self:RestoreOrdering() end,
            OnSizeChanged = function() self:RestorePosition() end,
        }
    end
    local show = self:AttachScript("OnShow")
    local hide = self:AttachScript("OnHide")
    local size = self:AttachScript("OnSizeChanged")
    self.ready = show and hide and size
    if not self.ready then handle:Hide() end
end

function Movement:GetMover(frame)
    if not IsObject(frame) then return end
    return self.movers[frame]
end

function Movement:Discover()
    for frame in pairs(self.discovered) do self.discovered[frame] = nil end
    local function Add(frame, kind)
        if not CanAccessFrame(frame) or type(frame.HookScript) ~= "function" or not HasNativeParent(frame, kind) then return end
        if kind == "bag" and not IsBag(Read(frame, "GetBagID")) then return end
        if self.discovered[frame] then return end
        self.discovered[frame] = true
        local mover = self.movers[frame]
        if not mover then
            mover = setmetatable({ frame = frame, kind = kind }, Mover)
            self.movers[frame] = mover
            mover:BindIdentity()
        else
            mover:BindIdentity()
        end
        if not mover.ready then
            local ok, failure = pcall(mover.Attach, mover)
            if not ok then
                if mover.handle then mover.handle:Hide() end
                local detail = Addon.IsPublic(failure) and type(failure) == "string" and failure:gsub("[\r\n]", " "):sub(1, 180) or ""
                Addon:ReportOnce("movement-handle-" .. mover.kind,
                    "A window drag handle could not be created; it will retry on the next inventory update. " .. detail)
            end
        end
    end
    Add(ContainerFrameCombinedBags, "combined")
    Add(BankFrame, "bank")
    if CanAccessFrame(ContainerFrameContainer) and type(ContainerFrameContainer.ContainerFrames) == "table" then
        for index = 1, math.min(#ContainerFrameContainer.ContainerFrames, 16) do
            Add(ContainerFrameContainer.ContainerFrames[index], "bag")
        end
    end
    for index = 1, 16 do Add(_G["ContainerFrame" .. index], "bag") end
end

function Movement:FinishDrags(save)
    for _, mover in pairs(self.movers) do mover:FinishDrag(save) end
end

function Movement:DetachIndividualBags()
    if IsInCombat() or self.restoring or not IsEnabled() then return end
    -- First snapshot all resolved native anchors. Applying one saved bag before
    -- this pass would pull its unsaved followers away from their native baseline.
    for _, mover in pairs(self.movers) do
        mover.nativeX, mover.nativeY = nil, nil
        if mover.kind == "bag" then
            mover:BindIdentity()
            if mover:CanMove() and Read(mover.frame, "IsShown") == true then
                mover.nativeX, mover.nativeY = ReadCurrentPosition(mover.frame, mover.kind)
            end
        end
    end
    for _, mover in pairs(self.movers) do
        if mover.kind == "bag" and mover.nativeX then mover:ApplyPosition(mover.nativeX, mover.nativeY, true) end
    end
end

function Movement:ArrangeIndividualBags()
    local fixed, free, placed = self.layoutFixed, self.layoutFree, self.layoutPlaced
    ClearList(fixed); ClearList(free); ClearList(placed)
    local screenWidth, screenHeight, columnBottom
    local customCarry = false
    -- Snapshot first: moving a native predecessor changes its followers' rects.
    for _, mover in pairs(self.movers) do
        if mover.kind == "bag" and mover:CanMove() and Read(mover.frame, "IsShown") == true then
            local _, width, height, itemWidth, itemHeight = GetGeometry(mover.frame, mover.kind)
            local nativeX, nativeY = ReadCurrentPosition(mover.frame, mover.kind)
            if width and nativeX and IsNumber(nativeX + itemWidth) and IsNumber(-nativeY + itemHeight) then
                local x, y = mover:GetSavedPosition()
                if mover.drag then x, y = mover.drag.lastX, mover.drag.lastY end
                local custom = x ~= nil
                local rect = mover.layoutRect or {}
                mover.layoutRect = rect
                rect.mover, rect.width, rect.height = mover, itemWidth, itemHeight
                rect.nativeX, rect.nativeY, rect.custom = nativeX, -nativeY, custom
                if custom then
                    rect.x = math.max(0, math.min(x, math.max(0, width - itemWidth)))
                    rect.y = math.max(0, math.min(-y, math.max(0, height - itemHeight)))
                else
                    rect.x, rect.y = nativeX, -nativeY
                end
                screenWidth, screenHeight = width, height
                if not custom then
                    local bottom = rect.nativeY + rect.height
                    if bottom > 0 and bottom <= height then
                        columnBottom = math.max(columnBottom or bottom, bottom)
                    end
                    rect.order = mover.identity == -1 and 6 or mover.identity
                    free[#free + 1] = rect
                else
                    fixed[#fixed + 1] = rect
                    placed[#placed + 1] = rect
                    customCarry = true
                end
            end
        end
    end
    if not screenWidth then return end
    table.sort(free, function(a, b) return a.order < b.order end)
    local changed = false
    for _, rect in ipairs(free) do
        local x, y = FindFreePosition(rect, placed, screenWidth, screenHeight, columnBottom)
        -- If there is no fitting candidate, retain native placement rather than
        -- clamping several windows onto the same screen edge.
        rect.x, rect.y = x or rect.nativeX, y or rect.nativeY
        if rect.x ~= rect.nativeX or rect.y ~= rect.nativeY then changed = true end
        placed[#placed + 1] = rect
    end
    if customCarry or changed then
        -- All locations are planned. Detach native followers before restoring
        -- custom locations, without writing any automatic location to saves.
        for _, rect in ipairs(free) do rect.mover:ApplyPosition(rect.x, -rect.y, true) end
    end
    for _, rect in ipairs(fixed) do
        rect.mover:ApplyPosition(rect.x, -rect.y)
    end
end

function Movement:AfterNativeAnchors()
    if self.handlingLayout or self.restoring or not IsEnabled() or not self.hooks.UpdateContainerFrameAnchors then return end
    if IsInCombat() then self.pending = true; return end
    self.handlingLayout = true
    local ok, failure = pcall(function()
        self:Discover()
        if Read(ContainerFrameCombinedBags, "IsShown") == true then
            -- Combined view and its separate special containers keep their
            -- existing native layout. Shift-opened individual views close it.
            local custom = false
            for _, mover in pairs(self.movers) do
                if mover.kind ~= "bank" and mover:CanMove() and Read(mover.frame, "IsShown") == true then
                    local x = mover:GetSavedPosition()
                    if mover.drag or x then custom = true; break end
                end
            end
            if custom then self:DetachIndividualBags() end
            for _, mover in pairs(self.movers) do
                if mover.kind ~= "bank" then mover:RestorePosition() end
            end
        else
            self:ArrangeIndividualBags()
        end
    end)
    self.handlingLayout = nil
    if not ok then error(failure, 0) end
end

function Movement:AfterPanelAnchors()
    if self.restoring or not IsEnabled() or not (self.hooks.UpdateUIPanelPositions or self.panelEvents) then return end
    if IsInCombat() then self.pending = true; return end
    self:Discover()
    local mover = self:GetMover(BankFrame)
    if mover then mover:RestorePosition() end
end

function Movement:InstallHooks()
    if type(hooksecurefunc) == "function" then
        if not self.hookCallbacks then
            self.hookCallbacks = {
                UpdateContainerFrameAnchors = function() self:AfterNativeAnchors() end,
                ContainerFrame_GenerateFrame = function(frame)
                    self:Refresh()
                    local mover = self:GetMover(frame)
                    if mover then mover:RaiseOrdering() end
                end,
                UpdateUIPanelPositions = function() self:AfterPanelAnchors() end,
                UpdateScaleForFitForOpenPanels = function() self:AfterPanelAnchors() end,
            }
        end
        for name, callback in pairs(self.hookCallbacks) do
            if not self.hooks[name] and type(_G[name]) == "function" then
                hooksecurefunc(name, callback)
                self.hooks[name] = true
            end
        end
    end
    if IsObject(EventRegistry) and type(EventRegistry.RegisterCallback) == "function" and not self.panelEvents then
        -- These fire after private native panel reflow, which can bypass the globals.
        EventRegistry:RegisterCallback("UIParentPanelManager.ShowUIPanel", function() self:AfterPanelAnchors() end, self)
        EventRegistry:RegisterCallback("UIParentPanelManager.HideUIPanel", function() self:AfterPanelAnchors() end, self)
        self.panelEvents = true
    end
end

function Movement:RestoreNative()
    if IsInCombat() then self.restorePending = true; return end
    self.restoring = true
    local ok, failure = pcall(function()
        local needsBags, needsBank, bagsAllowed = self.nativeBagsPending == true, false, true
        for _, mover in pairs(self.movers) do
            if mover.kind ~= "bank" and not mover:CanMove() then bagsAllowed = false end
            if mover.applied then
                if mover.kind == "bank" then
                    needsBank = true
                else
                    needsBags = true
                end
            end
        end
        local bankDone = not needsBank
        local bank = self:GetMover(BankFrame)
        if needsBank and bank and bank:CanMove() and type(UpdateUIPanelPositions) == "function" then
            UpdateUIPanelPositions(BankFrame)
            bankDone = true
            -- A moved bank can change native bag scaling even with no moved bags.
            needsBags = true
        end
        -- Native bag scaling uses the bank's right edge, so restore the bank first.
        local bagsDone = not needsBags
        if needsBags and bagsAllowed and bankDone and type(UpdateContainerFrameAnchors) == "function" then
            UpdateContainerFrameAnchors()
            bagsDone = true
        end
        self.nativeBagsPending = needsBags and not bagsDone or nil
        for _, mover in pairs(self.movers) do
            if (mover.kind == "bank" and bankDone) or (mover.kind ~= "bank" and bagsDone) then mover.applied = nil end
        end
        self.restorePending = not (bagsDone and bankDone) or nil
    end)
    self.restoring = nil
    if not ok then self.restorePending = true; error(failure, 0) end
end

function Movement:Initialize()
    self:Refresh()
end

function Movement:RestoreBagDefaults()
    if not self.bagResetPending or self.bagResetRestoring or IsInCombat() then return end
    self:Discover()
    local visible = false
    for _, mover in pairs(self.movers) do
        if mover.kind == "bag" then
            local shown = Read(mover.frame, "IsShown")
            if IsResetBag(mover.identity) then
                if shown ~= true and shown ~= false then return end
                if shown then visible = true end
            elseif mover.identity == nil and shown ~= false then return end
        end
    end
    -- Closed bags receive fresh native anchors when their frame is generated.
    if not visible then self.bagResetPending = nil; return end
    if not self.hooks.UpdateContainerFrameAnchors or type(UpdateContainerFrameAnchors) ~= "function" then return end
    -- Native layout can touch the whole carried family. Its existing posthook
    -- restores retained combined/keyring positions and active drags afterward.
    for _, mover in pairs(self.movers) do
        if mover.kind ~= "bank" and Read(mover.frame, "IsShown") ~= false and not mover:CanMove() then return end
    end
    self.bagResetRestoring = true
    local ok, failure = pcall(UpdateContainerFrameAnchors)
    self.bagResetRestoring = nil
    if ok then self.bagResetPending = nil
    else
        local detail = Addon.IsPublic(failure) and type(failure) == "string"
            and failure:gsub("[\r\n]", " "):sub(1, 180) or "Diagnostic unavailable."
        Addon:ReportOnce("movement-reset-bags", "Bag positions were cleared; native placement will retry on an inventory update. " .. detail)
    end
end

function Movement:Refresh()
    if IsInCombat() then self.pending = true; return end
    self.pending = nil
    self:InstallHooks()
    self:Discover()
    self:RestoreBagDefaults()
    for _, mover in pairs(self.movers) do
        if mover.ordering and (not IsEnabled() or mover.ordering.restorePending
            or Read(mover.frame, "IsVisible") ~= true or not mover:CanMove()) then
            mover:RestoreOrdering()
        end
    end
    if not IsEnabled() then
        self:FinishDrags(true)
        for _, mover in pairs(self.movers) do if mover.handle then mover.handle:Hide() end end
        self:RestoreNative()
        return
    end
    if self.restorePending then self:RestoreNative() end
    for _, mover in pairs(self.movers) do
        local width = Read(mover.frame, "GetWidth")
        local hasHook = mover:HasLayoutHook()
        if mover:CanMove() and hasHook and IsNumber(width) and width > 92 then
            mover.handle:Show()
        else
            if mover.handle then mover.handle:Hide() end
            if not hasHook then Addon:ReportOnce("movement-anchors-" .. mover.kind,
                "Window movement is unavailable because a native layout hook is missing.") end
        end
        mover:EnableOrdering()
    end
    self:AfterNativeAnchors()
    self:AfterPanelAnchors()
end

function Movement:ResetBagPositions()
    -- Cancel only the selected family's drag before identity discovery can
    -- save its old coordinates into a just-cleared bag-position record.
    for _, mover in pairs(self.movers) do
        if mover.kind == "bag" and (IsResetBag(mover.identity)
            or (mover.drag and IsResetBag(mover.drag.identity))) then mover:FinishDrag(false) end
    end
    if Addon.IsPublic(Addon.char) and type(Addon.char) == "table" then
        local positions = Addon.char.bagPositions
        if Addon.IsPublic(positions) and type(positions) == "table" then
            for id = 0, 5 do positions[id] = nil end
        end
    end
    self.bagResetPending = true
    if not IsInCombat() then self:InstallHooks(); self:RestoreBagDefaults() end
end

function Movement:ResetPosition()
    self:FinishDrags(false)
    if type(Addon.char) == "table" then
        Addon.char.position, Addon.char.bankPosition = nil, nil
        local positions = Addon.char.bagPositions
        if Addon.IsPublic(positions) and type(positions) == "table" then
            for id = -1, 5 do positions[id] = nil end
        end
    end
    self.restorePending = true
    self:Refresh()
end

function Movement:OnEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then self:FinishDrags(true); return end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then self:FinishDrags(true) end
    self:Refresh()
end
