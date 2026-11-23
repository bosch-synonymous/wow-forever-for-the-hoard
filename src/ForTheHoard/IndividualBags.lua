local _, Addon = ...

local IndividualBags = { buttons = {}, frames = {}, hooks = {}, owned = {}, byBag = {} }
Addon.IndividualBags = IndividualBags

local function IsBag(id)
    return Addon.IsFiniteNumber(id) and id % 1 == 0 and id >= 0 and id <= 5
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and Addon.IsPublic(value) then return value end
end

local function IsObject(value)
    return Addon.IsPublic(value) and (type(value) == "table" or type(value) == "userdata")
end

local function CanAccess(frame)
    if not IsObject(frame) then return false end
    if type(frame.IsForbidden) == "function" and Read(frame.IsForbidden, frame) ~= false then return false end
    if C_RestrictedActions and type(C_RestrictedActions.CheckAllowProtectedFunctions) == "function"
        and Read(C_RestrictedActions.CheckAllowProtectedFunctions, frame, true) ~= true then return false end
    return true
end

local function OutOfCombat()
    return Read(InCombatLockdown) == false
end

local function Desktop()
    return InputUtil and Read(InputUtil.IsGamepadUIEnabled) == false
end

local function CombinedPreference()
    local manager = ContainerFrameSettingsManager
    if IsObject(manager) then return Read(manager.IsUsingCombinedBags, manager) end
end

local function CombinedMode()
    return CombinedPreference() == true
end

local function EmptyCursor()
    -- A missing getter is not evidence that the cursor is empty.
    if type(GetCursorInfo) ~= "function" then return false end
    local ok, kind = pcall(GetCursorInfo)
    return ok and Addon.IsPublic(kind) and kind == nil
end

function IndividualBags:ForgetFrame(frame)
    local record = self.owned[frame]
    if not record then return end
    self.owned[frame] = nil
    if self.byBag[record.bag] == frame then self.byBag[record.bag] = nil end
end

function IndividualBags:GetOwnedFrame(id)
    if not IsBag(id) then return end
    local frame = self.byBag[id]
    if not frame or not CanAccess(frame) then return end
    local currentID = Read(frame.GetBagID, frame)
    if not Addon.IsFiniteNumber(currentID) then return end
    if currentID ~= id or Read(frame.IsShown, frame) == false then
        self:ForgetFrame(frame)
        return
    end
    if Read(frame.IsShown, frame) == true then return frame end
end

function IndividualBags:CloseFrame(frame)
    local record = self.owned[frame]
    if not record then return true end
    if not CanAccess(frame) or (not OutOfCombat() and Read(frame.IsProtected, frame) ~= false) then
        record.closePending = true
        return false
    end
    local currentID = Read(frame.GetBagID, frame)
    if not Addon.IsFiniteNumber(currentID) then record.closePending = true; return false end
    if currentID ~= record.bag or Read(frame.IsShown, frame) == false then
        -- A native pooled frame may already represent somebody else's bag.
        self:ForgetFrame(frame)
        return true
    end
    local ok = pcall(frame.Hide, frame)
    if not ok then
        record.closePending = true
        Addon:ReportOnce("individual-close", "A separate bag window cannot close yet; it will retry when inventory access returns.")
        return false
    end
    if self.owned[frame] == record and Read(frame.IsShown, frame) ~= false then
        record.closePending = true
        return false
    end
    self:ForgetFrame(frame)
    return true
end

function IndividualBags:CloseOwnedBag(id)
    if not IsBag(id) then return true end
    local frame = self.byBag[id]
    return not frame or self:CloseFrame(frame)
end

function IndividualBags:CloseOwned()
    local closed = true
    for frame in pairs(self.owned) do
        if not self:CloseFrame(frame) then closed = false end
    end
    return closed
end

-- Retain the former cleanup entry point for callers; there is no singleton view.
function IndividualBags:CloseSolo()
    return self:CloseOwned()
end

function IndividualBags:FindFrame(id, shown)
    local seen, fallback = {}, nil
    local function Candidate(frame)
        if not IsObject(frame) or seen[frame] then return nil end
        seen[frame] = true
        if frame == ContainerFrameCombinedBags or not CanAccess(frame) then return nil end
        if Read(frame.IsCombinedBagContainer, frame) ~= false
            or Read(frame.CanUseForBagID, frame, id) ~= true
            or type(frame.Hide) ~= "function" or type(frame.HookScript) ~= "function" then return nil end
        if id == 0 and Read(frame.IsBackpack, frame) ~= true then return nil end
        if Read(frame.IsShown, frame) ~= (shown == true) then return nil end
        if shown and Read(frame.GetBagID, frame) ~= id then return nil end
        return frame
    end
    local function Choose(frame)
        local candidate = Candidate(frame)
        if candidate and not shown and id ~= 5 and Read(candidate.CanUseForBagID, candidate, 5) == true then
            -- The reagent-capable native template also accepts ordinary bags.
            -- Prefer another free generic frame so reagent storage can still open.
            fallback = fallback or candidate
            return
        end
        return candidate
    end
    local container = ContainerFrameContainer
    if IsObject(container) and Addon.IsPublic(container.ContainerFrames)
        and type(container.ContainerFrames) == "table" then
        for index = 1, math.min(#container.ContainerFrames, 16) do
            local candidate = Choose(container.ContainerFrames[index])
            if candidate then return candidate end
        end
    end
    for index = 1, 16 do
        local candidate = Choose(_G["ContainerFrame" .. index])
        if candidate then return candidate end
    end
    return fallback
end

function IndividualBags:WatchFrame(frame)
    local state = self.frames[frame]
    if not state then state = {}; self.frames[frame] = state end
    if not state.hideCallback then state.hideCallback = function() self:ForgetFrame(frame) end end
    return self:AttachScript(frame, state, "OnHide", "hideHook", "hideStatus", state.hideCallback)
end

function IndividualBags:AttachScript(frame, state, event, readyKey, statusKey, callback)
    if state[readyKey] then return true end
    if state[statusKey] == "unknown" or not CanAccess(frame) or type(frame.HookScript) ~= "function" then return false end
    local ok, result = pcall(frame.HookScript, frame, event, callback)
    if ok and Addon.IsPublic(result) and result == true then
        state[readyKey], state[statusKey] = true, "ready"
        return true
    end
    local uncertain = ok and (not Addon.IsPublic(result) or result ~= false)
    state[statusKey] = uncertain and "unknown" or "retry"
    Addon:ReportOnce("individual-script-" .. event,
        uncertain and "A native bag callback did not confirm setup; the separate-bag shortcut remains inactive for this window until reload."
        or "A native bag callback could not attach; the separate-bag shortcut will retry on an inventory update.")
    return false
end

function IndividualBags:WatchCombined(frame)
    if not CanAccess(frame) then return false end
    local state = self.frames[frame]
    if not state then state = {}; self.frames[frame] = state end
    if not state.showCallback then state.showCallback = function() self:CloseOwned() end end
    if not self:AttachScript(frame, state, "OnShow", "showHook", "showStatus", state.showCallback) then return false end
    self.combined = frame
    return true
end

function IndividualBags:OpenBag(id)
    if not IsBag(id) or not Desktop() or not OutOfCombat() or not EmptyCursor()
        or Read(ContainerFrame_AllowedToOpenBags) ~= true then return false end
    local preference = CombinedPreference()
    if preference ~= true and preference ~= false then return false end
    if type(ContainerFrame_GenerateFrame) ~= "function"
        or not C_Container or type(C_Container.GetContainerNumSlots) ~= "function"
        or not self.hooks.closeBag or not self.hooks.closeAll or self.combined ~= ContainerFrameCombinedBags then return false end
    if id == 0 and not self.hooks.closeBackpack then return false end
    if not CanAccess(ContainerFrameCombinedBags) then return false end

    local owned = self.byBag[id]
    local shown = self:GetOwnedFrame(id)
    -- An unreadable owned view is not a free slot for another copy of this bag.
    if owned and self.byBag[id] == owned and not shown then return true end
    shown = shown or self:FindFrame(id, true)
    if shown then
        if not self:WatchFrame(shown) then return true end
        local combined = ContainerFrameCombinedBags
        if Read(combined.IsShown, combined) == true then
            -- Reagent storage can already be shown alongside the combined view.
            -- This click enters individual viewing before selected-only toggling applies.
            self.changing = true
            local ok, detail = pcall(function()
                if not OutOfCombat() or not Desktop() or not EmptyCursor() or not CanAccess(combined)
                    or not CanAccess(shown) or Read(shown.IsShown, shown) ~= true
                    or Read(shown.GetBagID, shown) ~= id or Read(shown.CanUseForBagID, shown, id) ~= true
                    or Read(ContainerFrame_AllowedToOpenBags) ~= true then
                    error("The bag window is no longer available.")
                end
                self:ForgetFrame(shown)
                self.owned[shown], self.byBag[id] = { frame = shown, bag = id }, shown
                combined:Hide()
                if Read(combined.IsShown, combined) ~= false then error("The combined bag window cannot close yet.") end
            end)
            self.changing = nil
            if not ok then
                local message = Addon.IsPublic(detail) and type(detail) == "string" and detail or "Diagnostic unavailable."
                Addon:ReportOnce("individual-open", "Could not open the selected bag: " .. message)
            end
            return true
        end
        self:ForgetFrame(shown)
        self.owned[shown], self.byBag[id] = { frame = shown, bag = id }, shown
        self:CloseOwnedBag(id)
        return true
    end
    local size = Read(C_Container.GetContainerNumSlots, id)
    if not Addon.IsFiniteNumber(size) or size % 1 ~= 0 or size <= 0 or size > 512 then return false end
    local frame = self:FindFrame(id)
    if not frame then
        Addon:ReportOnce("individual-frame", "A separate window for that bag is unavailable.")
        -- Falling through would invoke native Shift/Open All and replace existing views.
        return true
    end
    if not self:WatchFrame(frame) then return true end

    self.changing = true
    local ok, detail = pcall(function()
        if not OutOfCombat() or not Desktop() or not EmptyCursor()
            or not CanAccess(frame) or Read(frame.IsShown, frame) ~= false
            or Read(frame.CanUseForBagID, frame, id) ~= true
            or Read(ContainerFrame_AllowedToOpenBags) ~= true then
            error("The bag window is no longer available.")
        end
        -- Close only the combined window; other individual bags and native owner stay intact.
        local combined = ContainerFrameCombinedBags
        if not CanAccess(combined) then error("The combined bag window is no longer available.") end
        local visible = Read(combined.IsShown, combined)
        if visible ~= true and visible ~= false then error("The combined bag window is no longer available.") end
        if visible then combined:Hide() end
        if not OutOfCombat() or not CanAccess(frame) or Read(frame.IsShown, frame) ~= false
            or Read(combined.IsShown, combined) ~= false then error("The bag window is no longer available.") end
        self:ForgetFrame(frame)
        self.owned[frame], self.byBag[id] = { frame = frame, bag = id }, frame
        ContainerFrame_GenerateFrame(frame, size, id)
    end)
    self.changing = nil
    if not ok then
        if self.byBag[id] == frame then self:CloseFrame(frame) end
        local message = Addon.IsPublic(detail) and type(detail) == "string" and detail or "Diagnostic unavailable."
        Addon:ReportOnce("individual-open", "Could not open the selected bag: " .. message)
    end
    -- Once window state has changed, do not fall through into native Shift/Open All.
    return true
end

function IndividualBags:WatchButton(button)
    if self.buttons[button] or not CanAccess(button) or type(button.GetScript) ~= "function"
        or type(button.SetScript) ~= "function" or type(button.GetBagID) ~= "function" then return end
    local original = button:GetScript("OnClick")
    if type(original) ~= "function" then return end
    local wrapper = function(owner, mouseButton, down, ...)
        if owner == button and Addon.IsPublic(mouseButton) and mouseButton == "LeftButton"
            and Addon.IsPublic(down) and down ~= true and Desktop() and OutOfCombat() and CanAccess(button) then
            local id = Read(button.GetBagID, button)
            local plainModifiers = Read(IsControlKeyDown) == false and Read(IsAltKeyDown) == false
            local notBinding = type(KeybindFrames_InQuickKeybindMode) == "function"
                and Read(KeybindFrames_InQuickKeybindMode) == false
            if IsBag(id) and plainModifiers and notBinding and EmptyCursor() then
                if Read(IsShiftKeyDown) == true then
                    if self:OpenBag(id) then return end
                elseif Read(IsShiftKeyDown) == false and CombinedMode() then
                    -- Native combined toggling otherwise sees individual views as already open.
                    self:CloseOwned()
                end
            end
        end
        return original(owner, mouseButton, down, ...)
    end
    -- Only OnClick is intercepted. Native drag, item placement, hover and other clicks remain native.
    button:SetScript("OnClick", wrapper)
    self.buttons[button] = { original = original, wrapper = wrapper }
end

function IndividualBags:HookGlobal(key, name, callback)
    if self.hooks[key] or type(_G[name]) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    local ok = pcall(hooksecurefunc, name, callback)
    if ok then self.hooks[key] = true end
end

function IndividualBags:Refresh()
    if not OutOfCombat() then return end
    if not Desktop() then
        self:CloseOwned()
    else
        for frame, record in pairs(self.owned) do
            if record.closePending then self:CloseFrame(frame) end
        end
    end
    self:HookGlobal("closeBag", "CloseBag", function(id)
        if IsBag(id) then self:CloseOwnedBag(id) end
    end)
    self:HookGlobal("closeBackpack", "CloseBackpack", function()
        -- ToggleAllBags calls this before asserting that the backpack really closed.
        if self:GetOwnedFrame(0) then
            if CombinedMode() then
                -- Combined-mode native ToggleAll skips generic bags after closing the backpack.
                for id = 0, 4 do self:CloseOwnedBag(id) end
            else
                self:CloseOwnedBag(0)
            end
        end
    end)
    if not self.hooks.closeAll and EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        EventRegistry:RegisterCallback("ContainerFrame.CloseAllBags", function() self:CloseOwned() end, self)
        self.hooks.closeAll = true
    elseif not self.hooks.closeAll then
        -- Unscoped closes always pass the native owner check. Scoped closes may be rejected.
        self:HookGlobal("closeAll", "CloseAllBags", function(owner)
            if Addon.IsPublic(owner) and owner == nil then self:CloseOwned() end
        end)
    end
    self:HookGlobal("toggleBackpack", "ToggleBackpack", function()
        if not self.changing and CombinedMode() and Read(ContainerFrame_AllowedToOpenBags) == true then self:CloseOwned() end
    end)

    local combined = ContainerFrameCombinedBags
    if not self:WatchCombined(combined) or not self.hooks.closeBag or not self.hooks.closeAll then return end
    if not Desktop() then return end
    self:WatchButton(MainMenuBarBackpackButton)
    for index = 0, 3 do self:WatchButton(_G["CharacterBag" .. index .. "Slot"]) end
    self:WatchButton(CharacterReagentBag0Slot)
end

function IndividualBags:Initialize()
    self:Refresh()
end

function IndividualBags:OnEvent(event, id)
    if event == "PLAYER_REGEN_DISABLED" then
        self:CloseOwned()
    elseif event == "BAG_CLOSED" and IsBag(id) then
        self:CloseOwnedBag(id)
    elseif event == "BAG_UPDATE_DELAYED" and C_Container then
        for frame, record in pairs(self.owned) do
            if CanAccess(frame) then
                local size = Read(C_Container.GetContainerNumSlots, record.bag)
                local displayed = Read(frame.GetBagSize, frame)
                if Addon.IsFiniteNumber(size) and Addon.IsFiniteNumber(displayed) and size ~= displayed then self:CloseFrame(frame) end
            end
        end
    end
    if event == "ADDON_LOADED" or event == "PLAYER_REGEN_ENABLED" or event == "INPUT_DEVICE_INTERFACE_TRANSITION"
        or event == "ADDON_RESTRICTION_STATE_CHANGED" then self:Refresh() end
end
