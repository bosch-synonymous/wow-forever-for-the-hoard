-- Decoration integration contract: physical locations, row boundaries, pooling, and opt-out.
local allocations = { frames = 0, textures = 0 }
local combat = false
local secret = {}
local infoBySlot = {}
local Region = {}
Region.__index = Region
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
function Region:ClearAllPoints() self.points = {} end
function Region:SetHeight(value) self.height = value end
function Region:SetWidth(value) self.width = value end
function Region:SetColorTexture(...) self.color = { ... } end
function Region:SetDrawLayer(layer, sublevel)
    self.layer, self.sublevel = layer, sublevel
    self.layerWrites = (self.layerWrites or 0) + 1
end

local Frame = setmetatable({}, { __index = Region })
Frame.__index = Frame
function Frame:GetObjectType() return "Frame" end
function Frame:IsForbidden() return self.forbidden == true end
function Frame:EnableMouse(value) self.mouseEnabled = value end
function Frame:SetFrameLevel(value) self.level = value end
function Frame:GetFrameLevel() return self.level or 10 end
function Frame:IsShown() return self.shown ~= false end
function Frame:IsVisible() return self:IsShown() and (not self.parent or self.parent:IsVisible()) end
function Frame:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function Frame:GetScript(name) return self.scripts and self.scripts[name] end
function Frame:HookScript(name, callback)
    self.hookCounts = self.hookCounts or {}
    self.hookCounts[name] = (self.hookCounts[name] or 0) + 1
    self.scriptHooks = self.scriptHooks or {}
    self.scriptHooks[name] = self.scriptHooks[name] or {}
    table.insert(self.scriptHooks[name], callback)
    return true
end
function Frame:CreateTexture(name, layer, template, sublevel)
    if self.textureFailureCountdown then
        self.textureFailureCountdown = self.textureFailureCountdown - 1
        if self.textureFailureCountdown == 0 then
            self.textureFailureCountdown = nil
            error("Injected texture creation failure")
        end
    end
    allocations.textures = allocations.textures + 1
    return setmetatable({ layer = layer, sublevel = sublevel, parent = self }, Region)
end
function Frame:GetBagID() return self.bag end
function Frame:GetID() return self.slot end
function Frame:IsExtended() return self.extended == true end
function Frame:GetRect() return self.left, self.bottom, self.width, self.height end
function Frame:Initialize(container, bag, slot)
    self.bag, self.slot, self.parent = bag, slot, container
end
function Frame:SetMatchesSearch(matches) self.nativeMatchesSearch = matches end
function Frame:UpdateItems() end
function Frame:UpdateItemLayout() end
function Frame:UpdateItemSlots() end
function Frame:UpdateFrameSize() end

function CreateFrame(_, _, parent)
    allocations.frames = allocations.frames + 1
    return setmetatable({ parent = parent, shown = true }, Frame)
end
function InCombatLockdown() return combat end
function hooksecurefunc(object, method, callback)
    if type(object) == "string" then
        callback, method, object = method, object, _G
    end
    local original = object[method]
    assert(type(original) == "function")
    object[method] = function(...)
        local results = { original(...) }
        callback(...)
        return unpack(results)
    end
end
C_Container = {
    GetContainerItemInfo = function(bag, slot) return infoBySlot[bag .. ":" .. slot] end,
}
C_RestrictedActions = {
    CheckAllowProtectedFunctions = function(frame, silent)
        assert(silent == true, "Eligibility checks must suppress blocked-action errors")
        return not frame.denied
    end,
}
local addon = {
    db = { appearance = {
        mode = "tint", outline = "groups", tintAlpha = 0.16, outlineAlpha = 0.65, bagOutlineAlpha = 0.65,
        colors = { [0] = { 0.2, 0.4, 0.6 }, [1] = { 0.8, 0.3, 0.1 }, [5] = { 0.4, 0.7, 0.2 } },
    } },
    reports = {},
    IsPublic = function(value) return value ~= secret end,
}
addon.IsFiniteNumber = function(value)
    return value ~= secret and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end
function addon:ReportOnce(key, message) self.reports[key] = message end

ContainerFrameCombinedBags = CreateFrame("Frame")
ContainerFrameCombinedBags.Items = {}
local container = ContainerFrameCombinedBags
local function Slot(bag, slot, column, row, occupied)
    local frame = CreateFrame("Frame", nil, container)
    frame.bag, frame.slot = bag, slot
    frame.left, frame.bottom, frame.width, frame.height = column * 42, 300 - row * 42, 37, 37
    infoBySlot[bag .. ":" .. slot] = occupied and { isFiltered = false } or nil
    container.Items[#container.Items + 1] = frame
    return frame
end
local a = Slot(0, 1, 0, 0, true)
local b = Slot(0, 2, 1, 0, false)
-- Native ItemButton art is layered independently of whether its icon contains
-- an item or an empty-slot atlas. Model the shipped layers, not their pixels.
local nativeSlotArt = {}
for _, button in ipairs({ a, b }) do
    local art = {
        icon = { layer = "BORDER", sublevel = 0 },
        NormalTexture = { layer = "ARTWORK", sublevel = 0 },
        IconBorder = { layer = "OVERLAY", sublevel = 0 },
        IconQuestTexture = { layer = "OVERLAY", sublevel = 2 },
        searchOverlay = { layer = "OVERLAY", sublevel = 4 },
        ItemContextOverlay = { layer = "OVERLAY", sublevel = 5 },
        Count = { layer = "ARTWORK", sublevel = 0, insetX = -5, insetY = 2 },
    }
    for key, region in pairs(art) do
        region.SetDrawLayer = function() error("native slot art was reordered") end
        region.SetColorTexture = function() error("native slot art was recolored") end
        region.SetPoint = function() error("native slot art was moved") end
        button[key] = region
    end
    nativeSlotArt[button] = art
end
local nativeSlotClick = function() end
a:SetScript("OnClick", nativeSlotClick)
local otherBag = Slot(1, 1, 2, 0, true)
local afterOtherBag = Slot(0, 3, 3, 0, true)
local nextRow = Slot(0, 4, 0, 1, true)
local nextRowEnd = Slot(0, 5, 1, 1, false)
local gapLeft = Slot(0, 6, 0, 2, true)
local gapRight = Slot(0, 7, 2, 2, true)

assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Colors.lua"))("ForTheHoard", addon)
local colors = addon.Colors
colors:Initialize()
assert(next(addon.reports) == nil, "Initial decoration should succeed")
assert(colors.slots[a].fill.shown and colors.slots[b].fill.shown, "Occupied and empty slots both receive an accent")
assert(colors.slots[a].fill.color[1] == colors.slots[b].fill.color[1], "The same physical bag has one color")
assert(colors.slots[a].fill.color[1] ~= colors.slots[otherBag].fill.color[1], "Distinct equipped positions remain distinct")
assert(colors.slots[a].edges == nil and allocations.textures == #container.Items,
    "Tint mode creates one fill per content slot, with no unused borders")
local geometryReads = 0
local nativeRect = a.GetRect
a.GetRect = function() geometryReads = geometryReads + 1; return nativeRect(a) end
colors:Refresh()
assert(geometryReads == 0, "Tint rendering does not build grouping geometry")

local initialTextures = allocations.textures
for i = 1, 20 do colors:Refresh() end
assert(allocations.textures == initialTextures, "Refreshes reuse slot regions")
assert(a.hookCounts.OnHide == 1, "A pooled slot must be hooked once")

addon.db.appearance.mode = "outline"
colors:Refresh()
local groups = colors.containers[container].groups
assert(geometryReads > 0, "Cartouches still read actual slot geometry")
assert(#groups == 6, "Rows, different bags, and hidden gaps split group cartouches")
assert(groups[1].points[1][2] == a and groups[1].points[2][2] == b, "First group encloses only its adjacent run")
assert(groups[2].points[1][2] == otherBag and groups[2].points[2][2] == otherBag, "A different bag gets a separate boundary")
assert(groups[3].points[1][2] == afterOtherBag, "The first bag cannot bridge across another bag")
assert(groups[4].points[1][2] == nextRow and groups[4].points[2][2] == nextRowEnd, "A wrapped row has its own segment")
assert(groups[5].points[1][2] == gapLeft and groups[6].points[1][2] == gapRight, "A gap is never enclosed as an invented slot")
assert(groups[1].mouseEnabled == false, "Group outlines cannot intercept item clicks")
-- A cartouche must remain above every member's opaque surfaces, including a
-- raised middle item. Keep its stronger stroke outside the item artwork and
-- leave a gap between the differently colored neighboring bag segments.
local raisedMiddle = Slot(0, 9, 4, 0, true)
local runEnd = Slot(0, 10, 5, 0, true)
raisedMiddle.level = 30
colors:Refresh()
assert(groups[3].points[2][2] == runEnd and groups[3]:GetFrameLevel() > raisedMiddle:GetFrameLevel(),
    "Cartouche disappeared behind a member whose level exceeds the endpoints")
local topPadding = groups[1].points[1][5]
local neighborGap = otherBag.left - (b.left + b.width)
assert(groups[1].edges[1].height == 2 and groups[1].edges[3].width == 2,
    "Cartouches need a readable two-unit perimeter")
assert(topPadding >= groups[1].edges[1].height and -groups[1].points[1][4] >= groups[1].edges[3].width,
    "Foreground cartouche stroke intrudes into native item artwork")
assert(topPadding * 2 < neighborGap, "Neighboring bag cartouches overlap in the native gutter")
for _, alpha in ipairs({ 0, 0.5, 0.75, 1 }) do
    addon.db.appearance.outlineAlpha, addon.db.appearance.tintAlpha = alpha, 0.99
    colors:Refresh()
    assert(groups[1].edges[1].color[4] == alpha, "Cartouche alpha does not follow Outline opacity")
    assert(groups[1].edges[1].color[1] == addon.db.appearance.colors[0][1], "Cartouche changed the chosen color")
end
addon.db.appearance.outlineAlpha, addon.db.appearance.tintAlpha = 0.65, 0.16
raisedMiddle.level = 40
colors:Refresh()
assert(groups[3]:GetFrameLevel() > raisedMiddle:GetFrameLevel(), "Native reflow kept a stale cartouche level")
local groupFrames, groupTextures = allocations.frames, allocations.textures
for i = 1, 20 do colors:Refresh() end
assert(allocations.frames == groupFrames and allocations.textures == groupTextures, "Cartouche redraws keep resources bounded")

addon.db.appearance.outline = "slots"
geometryReads = 0
colors:Refresh()
assert(not groups[1].shown and colors.slots[a].edges[1].shown, "Slot borders and group cartouches remain separate choices")
local layerOrder = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
for _, button in ipairs({ a, b }) do
    local edges = colors.slots[button].edges
    assert(edges[1].height == 2 and edges[2].height == 2 and edges[3].width == 2 and edges[4].width == 2,
        "Occupied and empty slots need the same readable two-unit perimeter")
    for _, edge in ipairs(edges) do
        for key, region in pairs(nativeSlotArt[button]) do
            assert(button[key] == region, "Slot decoration replaced native artwork")
            assert(layerOrder[edge.layer] > layerOrder[region.layer]
                or (edge.layer == region.layer and edge.sublevel > region.sublevel),
                "Native icon, quality, quest or search art can hide an item-slot edge")
        end
    end
    -- The inner edges end exactly at the native item bounds: icon and count
    -- remain inside. Expanded native glow/hover artwork is not raster-emulated.
    local left, right, top, bottom = edges[3], edges[4], edges[1], edges[2]
    assert(left.points[1][4] + left.width <= 0 and right.points[1][4] - right.width >= 0
        and top.points[1][5] - top.height >= 0 and bottom.points[1][5] + bottom.height <= 0,
        "The foreground perimeter intrudes into the icon or native count inset")
    assert(left.points[1][2] == button and right.points[1][2] == button
        and top.points[1][2] == button and bottom.points[1][2] == button,
        "Slot edges must stay anchored to their own pooled item button")
end
local aEdges, bEdges = colors.slots[a].edges, colors.slots[b].edges
assert(a.left + a.width + aEdges[4].points[1][4] < b.left + bEdges[3].points[1][4],
    "Adjacent slot outlines overlap in the native five-unit gutter")
local slotFrames, slotTextures = allocations.frames, allocations.textures
for _, alpha in ipairs({ 0, 0.5, 0.75, 1 }) do
    addon.db.appearance.outlineAlpha = alpha
    a:SetMatchesSearch(false)
    colors:Refresh()
    for index, edge in ipairs(aEdges) do
        assert(edge == colors.slots[a].edges[index] and math.abs(edge.color[4] - alpha * 0.2) < 0.00001,
            "Foreground slot edges changed selected opacity or native search dimming")
        assert(edge.color[1] == addon.db.appearance.colors[0][1]
            and edge.color[2] == addon.db.appearance.colors[0][2]
            and edge.color[3] == addon.db.appearance.colors[0][3], "Slot edges changed the selected RGB")
        assert(bEdges[index].color[4] == alpha, "An unfiltered empty-slot perimeter changed its opacity")
    end
end
assert(allocations.frames == slotFrames and allocations.textures == slotTextures,
    "Foreground slot outlines reuse their four textures without extra frames")
assert(a:GetScript("OnClick") == nativeSlotClick and nativeSlotArt[a].Count.insetX == -5
    and nativeSlotArt[a].Count.insetY == 2, "Slot outlines changed native item handling or count anchors")
addon.db.appearance.outlineAlpha = 0.65
assert(geometryReads == 0, "Individual slot borders do not build grouping geometry")

addon.db.appearance.mode = "tint"
a:SetMatchesSearch(false)
colors:Refresh()
assert(math.abs(colors.slots[a].fill.color[4] - 0.032) < 0.00001, "Accent respects native search dimming")
a:Initialize(container, 5, 1)
colors:Refresh()
assert(colors.slots[a].fill.color[1] == 0.4, "Reused slots use their current bag, never stale pool identity")
assert(a.nativeMatchesSearch == false, "Decoration does not alter native search state")

local beforeCombat = allocations.textures
combat = true
addon.db.appearance.outline = "groups"
addon.db.appearance.mode = "outline"
colors:Refresh()
assert(allocations.textures == beforeCombat, "Structural decoration waits until combat ends")
combat = false
colors:OnEvent("PLAYER_REGEN_ENABLED")
colors:Refresh()
assert(groups[1].shown, "Deferred rendering resumes after combat")

addon.db.appearance.mode = "off"
colors:Refresh()
for _, state in pairs(colors.slots) do
    assert(not state.fill.shown, "Off hides all owned fills")
    for _, edge in ipairs(state.edges) do assert(not edge.shown, "Off hides all owned borders") end
end
for _, group in ipairs(groups) do assert(not group.shown, "Off hides all cartouches") end

addon.db.appearance.mode = "tint"
addon.db.appearance.colors[5] = { secret, 0.2, 0.3 }
colors:Refresh()
assert(not colors.slots[a].fill.shown, "A restricted palette value is never operated on")
assert(next(addon.reports) == nil, "All supported paths should remain diagnostic-free")

local recovering = Slot(1, 2, 0, 3, true)
recovering.textureFailureCountdown = 3
addon.db.appearance.mode = "outline"
addon.db.appearance.outline = "slots"
local beforeRecovery = allocations.textures
colors:Refresh()
local partial = colors.slots[recovering]
local retainedEdge = partial.edges[1]
assert(not partial.edgesReady and not retainedEdge.shown and partial.fill == nil,
    "Partial outline initialization stays hidden and does not allocate an unused fill")
assert(addon.reports["colors-regions"]:find("Injected texture creation failure", 1, true), "The diagnostic preserves the original failure")
colors:Refresh()
assert(partial.edgesReady and partial.edges[1] == retainedEdge and partial.edges[1].shown,
    "A transient creation failure resumes using owned regions")
assert(allocations.textures - beforeRecovery == 4, "Outline recovery retains exactly four borders and no unused fill")

local denied = Slot(1, 3, 0, 4, true)
denied.denied = true
denied.GetBagID = function() error("A denied native slot must not be read") end
local forbidden = Slot(1, 4, 1, 4, true)
forbidden.forbidden = true
forbidden.GetBagID = function() error("A forbidden native slot must not be read") end
local beforeDenied = allocations.textures
colors:Refresh()
assert(colors.slots[denied] == nil and colors.slots[forbidden] == nil, "Restricted native slots are not hooked")
assert(allocations.textures == beforeDenied, "Restricted native slots receive no new decoration")

local nativeCombat = InCombatLockdown
InCombatLockdown = function() return secret end
colors:Refresh()
assert(allocations.textures == beforeDenied, "Unknown combat state never permits new decoration")
InCombatLockdown = nativeCombat

-- Equipped icon accents use physical container identities, independently of occupied contents.
addon.db.appearance.mode = "tint"
addon.db.appearance.colors[5] = { 0.4, 0.7, 0.2 }
addon.db.appearance.colors[2] = { 0.12, 0.23, 0.34 }
addon.db.appearance.colors[3] = { 0.21, 0.32, 0.43 }
addon.db.appearance.colors[4] = { 0.31, 0.42, 0.53 }
addon.db.appearance.colors[-1] = { 0.72, 0.63, 0.54 }
local nativeClick, nativeDrag, nativeReceive = function() end, function() end, function() end
local untouchedNativeArt = {
    SetColorTexture = function() error("Native button artwork must stay untouched") end,
    SetVertexColor = function() error("Native button artwork must stay untouched") end,
    SetAtlas = function() error("Native button artwork must stay untouched") end,
}
local function Icon(bag, inventorySlot)
    local frame = CreateFrame("Frame")
    frame.bag, frame.slot = bag, inventorySlot
    frame.icon, frame.SlotHighlightTexture = untouchedNativeArt, untouchedNativeArt
    frame:SetScript("OnClick", nativeClick)
    frame:SetScript("OnDragStart", nativeDrag)
    frame:SetScript("OnReceiveDrag", nativeReceive)
    frame.UpdateTextures = function() end
    frame.UpdateOrientation = function() end
    return frame
end
MainMenuBarBackpackButton = Icon(0, 0)
MainMenuBarBackpackButton.GetBagID = function() return 99 end -- Its named native role is canonical.
CharacterBag0Slot = Icon(1, 20)
CharacterBag1Slot = Icon(2, 21)
CharacterBag2Slot = Icon(3, 22)
CharacterBag3Slot = Icon(4, 23)
CharacterBag3Slot.HasBagEquipped = function() return false end
CharacterReagentBag0Slot = Icon(5, 24)
KeyRingButton = Icon(-1, -1)
KeyRingButton.GetBagID = function() return -31 end -- Desktop native inventory-conversion pitfall.
local padReagent, padKeyring = Icon(5, 24), Icon(-1, -1)
GamepadBagBar = CreateFrame("Frame")
function GamepadBagBar:GetBagButton(bag)
    if bag == 5 then return padReagent end
    if bag == -1 then return padKeyring end
end

colors:Refresh()
local iconState = colors.icons[CharacterBag0Slot]
assert(iconState and iconState.ready and iconState.edges[1].shown, "Tint mode also outlines equipped bag icons")
assert(iconState.fill == nil, "Bag icons receive outlines without filled color overlays")
assert(iconState.edges[1].color[1] == addon.db.appearance.colors[1][1], "Bag inventory slot 20 resolves through GetBagID to container 1")
assert(colors.icons[CharacterBag1Slot].edges[1].color[1] == 0.12, "Equal item artwork does not collapse distinct bag-position colors")
assert(colors.icons[MainMenuBarBackpackButton].edges[1].color[1] == 0.2, "Backpack uses its explicit physical identity")
assert(colors.icons[KeyRingButton].edges[1].color[1] == 0.72, "Desktop keyring bypasses inherited inventory arithmetic")
assert(colors.icons[CharacterReagentBag0Slot].edges[1].color[1] == 0.4, "Reagent position uses its selected color")
assert(colors.icons[CharacterBag3Slot].edges[1].shown, "An empty equipped position retains its assigned accent")
assert(colors.icons[padReagent].edges[1].color[1] == 0.4 and colors.icons[padKeyring].edges[1].color[1] == 0.72,
    "Gamepad icons share their physical bag identities")
assert(colors.icons[padReagent].edges[1].height == 3 and colors.icons[padKeyring].edges[1].height == 3,
    "Equivalent equipped bag icons share the stronger toolbar treatment")
assert(iconState.edges[1].layer == "OVERLAY" and iconState.edges[1].sublevel == 7, "Opaque native icon artwork cannot hide the owned outline")
assert(iconState.edges[1].height == 3 and iconState.edges[2].height == 3
    and iconState.edges[3].width == 3 and iconState.edges[4].width == 3,
    "Equipped toolbar borders must remain substantial beside native gold framing")
local expectedOffsets = {
    { { -1, 1 }, { 1, 1 } }, { { -1, -1 }, { 1, -1 } },
    { { -1, 1 }, { -1, -1 } }, { { 1, 1 }, { 1, -1 } },
}
for index, edge in ipairs(iconState.edges) do
    for pointIndex, point in ipairs(edge.points) do
        local offset = expectedOffsets[index][pointIndex]
        assert(point[2] == CharacterBag0Slot and point[4] == offset[1] and point[5] == offset[2],
            "Toolbar borders must retain their existing outer footprint")
    end
end
assert(iconState.edges[2].height + iconState.edges[2].points[1][5] == 2
    and iconState.edges[4].width - iconState.edges[4].points[1][4] == 2,
    "The stronger stroke must leave the native count's two-unit bottom/right inset clear")
assert(CharacterBag0Slot:GetScript("OnClick") == nativeClick and CharacterBag0Slot:GetScript("OnDragStart") == nativeDrag
    and CharacterBag0Slot:GetScript("OnReceiveDrag") == nativeReceive, "Outline does not intercept Shift-click, dragging or item placement")

local iconTextureCount, iconFrameCount = allocations.textures, allocations.frames
addon.db.appearance.colors[1][1] = 0.92
addon.db.appearance.colors[1][2] = 0.81
addon.db.appearance.bagOutlineAlpha = 0.44
colors:Refresh()
assert(iconState.edges[1].color[1] == 0.92 and iconState.edges[1].color[2] == 0.81
    and iconState.edges[1].color[4] == 0.44, "Live color and opacity edits recolor existing icon regions")
addon.db.appearance.tintAlpha = 0.16
addon.db.appearance.bagOutlineAlpha = 1
colors:Refresh()
assert(iconState.edges[1].color[4] == 1 and iconState.edges[1].height == 3,
    "Full outline opacity must produce a solid toolbar stroke independently of background tint")
assert(colors.slots[otherBag].fill.color[4] == 0.16, "Toolbar emphasis must preserve item-slot tint opacity")
addon.db.appearance.bagOutlineAlpha = 0
colors:Refresh()
assert(iconState.edges[1].color[4] == 0, "Zero outline opacity must still hide the toolbar stroke")
addon.db.appearance.bagOutlineAlpha = 0.44
for i = 1, 20 do colors:Refresh() end
assert(allocations.textures == iconTextureCount and allocations.frames == iconFrameCount, "Live icon recoloring keeps allocations bounded")
assert(CharacterBag0Slot.hookCounts.OnShow == 1 and CharacterBag0Slot.hookCounts.OnHide == 1, "Native icon hooks are installed once")
local paletteBuffer = colors.palette[1]
colors:Refresh()
assert(colors.palette[1] == paletteBuffer, "Live RGB validation reuses the bounded per-position palette buffers")
colors.driver:Hide()
colors:OnEvent("BAG_UPDATE_DELAYED")
assert(colors.driver.shown, "Inventory updates still schedule a coalesced appearance redraw")
colors.driver:Hide()
CharacterBag0Slot:UpdateTextures()
assert(colors.driver.shown, "A native icon redraw schedules one coalesced refresh")

addon.db.appearance.mode = "outline"
colors:Refresh()
assert(iconState.edges[1].shown and iconState.edges[1].color[1] == 0.92, "Outline mode also accents the physical bag icon")
local previousShape = addon.db.appearance.outline
addon.db.appearance.outlineAlpha, addon.db.appearance.bagOutlineAlpha = 0.25, 0.8
addon.db.appearance.outline = "slots"
otherBag:SetMatchesSearch(true)
colors:Refresh()
assert(colors.slots[otherBag].edges[1].color[4] == 0.25 and iconState.edges[1].color[4] == 0.8,
    "item and equipped-button outlines did not use independent opacities")
otherBag:SetMatchesSearch(false)
colors:Refresh()
assert(math.abs(colors.slots[otherBag].edges[1].color[4] - 0.05) < 0.00001 and iconState.edges[1].color[4] == 0.8,
    "item search fading changed equipped-button opacity")
otherBag:SetMatchesSearch(true)
addon.db.appearance.outline = "groups"
addon.db.appearance.bagOutlineAlpha = 0
colors:Refresh()
assert(colors.containers[container].groups[1].edges[1].color[4] == 0.25 and iconState.edges[1].color[4] == 0,
    "zero button opacity changed cartouche opacity")
addon.db.appearance.outlineAlpha, addon.db.appearance.bagOutlineAlpha = 0, 1
colors:Refresh()
assert(colors.containers[container].groups[1].edges[1].color[4] == 0 and iconState.edges[1].color[4] == 1,
    "zero content opacity hid independent equipped-button borders")
addon.db.appearance.outline, addon.db.appearance.outlineAlpha, addon.db.appearance.bagOutlineAlpha = previousShape, 0.65, 0.44
addon.db.appearance.mode = "off"
colors:Refresh()
for _, state in pairs(colors.icons) do
    for _, edge in ipairs(state.edges) do assert(not edge.shown, "Off removes every owned icon outline") end
end

addon.db.appearance.mode = "tint"
CharacterBag1Slot.GetBagID = function() return secret end
CharacterBag2Slot.GetBagID = function() return nil end
CharacterBag3Slot.GetBagID = function() return 24 end
colors:Refresh()
assert(not colors.icons[CharacterBag1Slot].edges[1].shown and not colors.icons[CharacterBag2Slot].edges[1].shown
    and not colors.icons[CharacterBag3Slot].edges[1].shown, "Unavailable, restricted and inventory-valued getter results are not treated as bag identities")

local late = Icon(2, 21)
CharacterBag1Slot = late
colors:OnEvent("ADDON_LOADED")
colors:Refresh()
assert(colors.icons[late].edges[1].shown, "New native icon instances are discovered on later events")
local deniedIcon = Icon(3, 22)
deniedIcon.denied = true
deniedIcon.GetBagID = function() error("Denied icon identity must not be read") end
CharacterBag2Slot = deniedIcon
local beforeDeniedIcon = allocations.textures
colors:Refresh()
assert(colors.icons[deniedIcon] == nil and allocations.textures == beforeDeniedIcon, "A denied native icon receives no hooks or decorative regions")
assert(CharacterBag0Slot.icon == untouchedNativeArt and CharacterBag0Slot.SlotHighlightTexture == untouchedNativeArt,
    "Native icon and hover artwork retain their original objects")

-- A retained driver is not ready until its script is installed. Failed setup
-- retries through normal inventory events without allocating replacement frames.
local function FreshColors()
    local fresh = {
        db = { appearance = { mode = "off" } }, reports = {},
        IsPublic = addon.IsPublic, IsFiniteNumber = addon.IsFiniteNumber,
    }
    function fresh:ReportOnce(key, message)
        if not self.reports[key] then self.reports[key] = message; self.reportCount = (self.reportCount or 0) + 1 end
    end
    assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Colors.lua"))("ForTheHoard", fresh)
    return fresh.Colors, fresh
end
do
    local originalCreate = CreateFrame
    for _, failure in ipairs({ "create", "hide", "script" }) do
        local blocked, created, retained = true, 0, nil
        CreateFrame = function(...)
            if failure == "create" and blocked then error("Injected driver allocation failure") end
            created = created + 1
            local frame = originalCreate(...)
            retained = frame
            local originalHide, originalSetScript = frame.Hide, frame.SetScript
            frame.Hide = function(self)
                if failure == "hide" and blocked then error("Injected driver visibility failure") end
                return originalHide(self)
            end
            frame.SetScript = function(self, script, callback)
                if failure == "script" and blocked then error("Injected driver script failure") end
                return originalSetScript(self, script, callback)
            end
            return frame
        end
        local retry, owner = FreshColors()
        retry:Initialize()
        retry:OnEvent("BAG_UPDATE_DELAYED")
        assert(not retry.driverReady and owner.reportCount == 1, "Persistent driver setup failure stays bounded and diagnosable")
        assert(not retained or retained:GetScript("OnUpdate") == nil, "An incomplete driver cannot run a failing idle update")
        local before = created
        blocked = false
        retry:OnEvent("PLAYER_REGEN_ENABLED")
        assert(retry.driverReady and retry.driver:GetScript("OnUpdate"), "A later inventory event resumes incomplete driver setup")
        assert(created == (failure == "create" and before + 1 or before), "Driver recovery retains the previously allocated frame")
        if retained then assert(retry.driver == retained) end
        local readyFrame, callback = retry.driver, retry.driver:GetScript("OnUpdate")
        callback(readyFrame)
        assert(not readyFrame.shown, "Recovered driver consumes and clears the queued redraw")
        for index = 1, 20 do retry:Initialize() end
        assert(retry.driver == readyFrame and retry.driver:GetScript("OnUpdate") == callback and created == 1,
            "Healthy initialization reuses the same driver and callback")
    end
    CreateFrame = originalCreate
end

-- Each concrete native hook may fail transiently. Retry only the missing hook,
-- keeping successful script hooks, callbacks and decoration state intact.
do
    local originalHook = hooksecurefunc
    for _, kind in ipairs({ "container", "slot", "icon" }) do
        local retry = FreshColors()
        retry.driver, retry.driverReady = CreateFrame("Frame"), true
        local widget = CreateFrame("Frame")
        local target = kind == "container" and "UpdateSearchResults" or kind == "slot" and "SetMatchesSearch" or "UpdateTextures"
        widget[target] = function() end
        local blocked, attempts = true, 0
        hooksecurefunc = function(object, method, callback)
            if object == widget and method == target then
                attempts = attempts + 1
                if blocked then error("Injected native method hook failure") end
            end
            return originalHook(object, method, callback)
        end
        local function Watch()
            if kind == "container" then return retry:WatchContainer(widget) end
            if kind == "slot" then return retry:WatchSlot(widget, container) end
            return retry:WatchBagIcon(widget)
        end
        local retained = Watch()
        Watch()
        assert(not retained.hooks[target] and attempts == 2, "A failed native method hook is retried on later discovery")
        blocked = false
        Watch()
        local framesBefore, texturesBefore = allocations.frames, allocations.textures
        local attemptsAfter = attempts
        for index = 1, 20 do assert(Watch() == retained) end
        assert(retained.hooks[target] and attempts == attemptsAfter, "Successful native method hooks are never duplicated")
        assert(widget.hookCounts.OnHide == 1 and (kind == "slot" or widget.hookCounts.OnShow == 1),
            "Retrying methods preserves already installed visibility hooks")
        retry.driver:Hide()
        widget[target](widget, false)
        assert(retry.driver.shown, "Recovered native method hook schedules the existing coalesced driver")
        if kind == "slot" then assert(retained.matchesSearch == false, "Recovered search hook caches current native dimming") end
        assert(allocations.frames == framesBefore and allocations.textures == texturesBefore, "Hook recovery does not allocate regions")
    end
    hooksecurefunc = originalHook
end
do
    for _, kind in ipairs({ "container", "slot", "icon" }) do
      for _, failure in ipairs({ "throw", "false" }) do
        local retry = FreshColors()
        retry.driver, retry.driverReady = CreateFrame("Frame"), true
        local widget = CreateFrame("Frame")
        local blocked = true
        local originalScriptHook = widget.HookScript
        widget.HookScript = function(self, script, callback)
            if script == "OnHide" and blocked then
                if failure == "false" then return false end
                error("Injected native visibility hook failure")
            end
            return originalScriptHook(self, script, callback)
        end
        local function Watch()
            if kind == "container" then return retry:WatchContainer(widget) end
            if kind == "slot" then return retry:WatchSlot(widget, container) end
            return retry:WatchBagIcon(widget)
        end
        local retained = Watch()
        Watch()
        assert(not retained.scripts.OnHide, "Failed visibility setup is retained as incomplete")
        blocked = false
        for index = 1, 20 do assert(Watch() == retained) end
        assert(retained.scripts.OnHide and widget.hookCounts.OnHide == 1
            and (kind == "slot" or widget.hookCounts.OnShow == 1), "Partial visibility setup resumes without duplicating successful hooks")
        local decoration
        if kind == "container" then
            decoration = CreateFrame("Frame", nil, widget)
            retained.groups[1] = decoration
        else
            decoration = widget:CreateTexture()
            retained.fill = decoration
        end
        decoration:Show()
        for _, callback in ipairs(widget.scriptHooks.OnHide) do callback(widget) end
        assert(not decoration.shown, "Recovered release hook clears the retained group/slot/icon decoration")
      end
    end
end
do
    for _, result in ipairs({ "nil", "secret", "other" }) do
        local retry = FreshColors()
        local widget = CreateFrame("Frame")
        local calls = 0
        local hook = widget.HookScript
        widget.HookScript = function(self, script, callback)
            calls = calls + 1
            hook(self, script, callback)
            if result == "secret" then return secret end
            if result == "other" then return "uncertain" end
        end
        local retained = retry:WatchSlot(widget, container)
        for index = 1, 20 do retry:WatchSlot(widget, container) end
        assert(calls == 1 and not retained.scripts.OnHide and #widget.scriptHooks.OnHide == 1,
            "Uncertain native hook return must not claim readiness or duplicate a possibly attached callback")
    end
end
do
    local originalHook, originalGenerate = hooksecurefunc, ContainerFrame_GenerateFrame
    local blocked, attempts = true, 0
    ContainerFrame_GenerateFrame = function() end
    hooksecurefunc = function(object, method, callback)
        if object == "ContainerFrame_GenerateFrame" then
            attempts = attempts + 1
            if blocked then error("Injected native generation hook failure") end
        end
        return originalHook(object, method, callback)
    end
    local retry = FreshColors()
    retry:Initialize()
    assert(not retry.globalHooks.generate, "Failed global hook remains eligible for retry")
    blocked = false
    retry:OnEvent("ADDON_LOADED")
    assert(retry.globalHooks.generate and attempts == 2, "Later events recover a failed native generation hook")
    for index = 1, 20 do retry:Initialize() end
    retry.driver:Hide()
    ContainerFrame_GenerateFrame()
    assert(retry.driver.shown and attempts == 2, "Recovered global hook queues redraw without duplicate registrations")
    hooksecurefunc, ContainerFrame_GenerateFrame = originalHook, originalGenerate
end
-- Separate bags use an empty atlas on the same BORDER icon as real items.
-- Model that native surface, and exercise completed visual-state notifications
-- rather than using a nullable inventory-data query as proof of emptiness.
do
    local oldCombined, oldContainers, oldGamepad = ContainerFrameCombinedBags, ContainerFrameContainer, GamepadBagBar
    local individual = CreateFrame("Frame")
    local button = CreateFrame("Frame", nil, individual)
    button.bag, button.slot = 1, 91
    button.left, button.bottom, button.width, button.height = 0, 300, 37, 37
    individual.Items = { button }
    ContainerFrameCombinedBags, ContainerFrameContainer, GamepadBagBar = nil, { ContainerFrames = { individual } }, nil
    local visual, combined = nil, false
    local function hasItem() return visual end -- Native SetHasItem stores 1 or nil.
    function button:IsCombined() return combined end
    button.HasItem = hasItem
    function button:SetHasItem(value) visual = value and 1 or nil end
    local nativeIcon = { layer = "BORDER", sublevel = 0 }
    local nativeCue = { layer = "ARTWORK", sublevel = 0 }
    for _, region in ipairs({ nativeIcon, nativeCue }) do
        region.SetDrawLayer = function() error("native art was reordered") end
        region.SetColorTexture = function() error("native art was recolored") end
        region.SetVertexColor = region.SetColorTexture
    end
    button.icon, button.EmptyBagIcon = nativeIcon, nativeCue
    local originalClick = function() end
    button:SetScript("OnClick", originalClick)
    local retry, fresh = FreshColors()
    fresh.db.appearance = { mode = "tint", outline = "slots", tintAlpha = 0.5,
        outlineAlpha = 0.65, bagOutlineAlpha = 0.65, colors = { [1] = { 0.2, 0.4, 0.6 } } }
    local nativeSetter = button.SetHasItem
    button.SetHasItem = nil
    retry:Initialize()
    local fill = assert(retry.slots[button].fill)
    local frameCount, textureCount = allocations.frames, allocations.textures
    local function tick()
        assert(retry.driver.shown, "native visual update did not schedule a tint refresh")
        retry.driver:GetScript("OnUpdate")(retry.driver)
    end
    local function empty()
        assert(fill.shown and fill.layer == "BORDER" and fill.sublevel > nativeIcon.sublevel,
            "individual empty-slot backdrop covers the owned tint")
        assert(nativeCue.layer == "ARTWORK", "tint changed the native foreground cue")
    end
    local function low()
        assert(fill.shown and fill.layer == "BACKGROUND" and fill.sublevel == -8,
            "occupied or unknown visual state received a foreground tint")
    end
    low()
    button.SetHasItem = nativeSetter
    local originalHook = hooksecurefunc
    hooksecurefunc = function(object, method, callback)
        if object == button and method == "SetHasItem" then error("injected visual-state hook failure") end
        return originalHook(object, method, callback)
    end
    retry:Refresh(); low()
    assert(fresh.reports["colors-hook-SetHasItem"], "failed safety hook lost its diagnostic")
    hooksecurefunc = originalHook
    retry:Refresh(); empty()
    local emptyLayerWrites = fill.layerWrites
    retry.driver:Hide()
    for _ = 1, 20 do button:SetHasItem(nil) end
    assert(fill.shown and not retry.driver.shown and fill.layerWrites == emptyLayerWrites,
        "repeated native empty cooldown updates invalidated tint or scheduled redraws")
    button:SetHasItem(12345)
    assert(not fill.shown and retry.driver.shown,
        "native occupied-state change left foreground tint visible before deferred redraw")
    tick(); low()
    button:SetHasItem(nil); button:SetMatchesSearch(true); tick(); empty()
    local cachedSearch = retry.slots[button].matchesSearch
    button:SetHasItem(secret)
    assert(not fill.shown and retry.slots[button].matchesSearch == cachedSearch,
        "unknown native state retained foreground tint or discarded cached search state")
    tick(); low()
    button:SetHasItem(nil); button:SetMatchesSearch(true); tick(); empty()
    for _, alpha in ipairs({ 0, 0.16, 0.75, 1 }) do
        fresh.db.appearance.tintAlpha = alpha
        visual = 1; button:SetMatchesSearch(true); tick(); low()
        assert(fill.color[4] == alpha)
        visual = nil; button:SetMatchesSearch(true); tick(); empty()
        assert(fill.color[4] == alpha)
        button:SetMatchesSearch(false); tick(); empty()
        assert(math.abs(fill.color[4] - alpha * 0.2) < 0.000001, "raised empty tint lost search fading")
    end
    local writes = fill.layerWrites
    for _ = 1, 20 do button:SetMatchesSearch(true); tick(); empty() end
    assert(fill.layerWrites == writes, "unchanged empty presentation repeated layer writes")
    for _, getter in ipairs({ function() return 1 end, function() return false end,
        function() return secret end, function() error("unavailable native visual state") end }) do
        button.HasItem = getter; button:SetMatchesSearch(true); tick(); low()
        button.HasItem = hasItem; button:SetMatchesSearch(true); tick(); empty()
    end
    button.HasItem = nil; button:SetMatchesSearch(true); tick(); low()
    button.HasItem = hasItem
    for _, presentation in ipairs({ true, secret, "unknown" }) do
        combined = presentation; button:SetMatchesSearch(true); tick(); low()
    end
    local combinedGetter = button.IsCombined
    button.IsCombined = function() error("unknown native presentation") end
    button:SetMatchesSearch(true); tick(); low()
    button.IsCombined = nil
    button:SetMatchesSearch(true); tick(); low()
    button.IsCombined, combined = combinedGetter, false
    button:SetMatchesSearch(true); tick(); empty()

    -- A failed occupied-state reset must hide the foreground fill and retain
    -- its pending transition, so the next normal update can safely retry it.
    local originalLayer, blocked = fill.SetDrawLayer, true
    fill.SetDrawLayer = function(self, ...)
        if blocked then error("injected owned layer failure") end
        return originalLayer(self, ...)
    end
    visual = 1; button:SetMatchesSearch(true); tick()
    assert(not fill.shown and fresh.reports["colors-refresh"]:find("injected owned layer failure", 1, true),
        "failed layer reset left a tint overlay visible over item artwork")
    blocked = false; button:SetMatchesSearch(true); tick(); low()
    fill.SetDrawLayer = originalLayer
    visual = nil; button:SetMatchesSearch(true); tick(); empty()
    fresh.db.appearance.mode = "off"; retry:Refresh()
    assert(not fill.shown, "Off retained an elevated empty-slot fill")
    retry.driver:Hide()
    for _ = 1, 20 do button:SetHasItem(12345) end
    assert(not retry.driver.shown, "hidden foreground fills scheduled repeated occupied cooldown redraws in Off")
    button:SetHasItem(nil)
    fresh.db.appearance.mode = "tint"; retry:Refresh(); empty()
    assert(retry.slots[button].fill == fill and allocations.frames == frameCount and allocations.textures == textureCount,
        "visual-state transitions replaced or accumulated decoration resources")
    assert(button.icon == nativeIcon and nativeIcon.layer == "BORDER" and nativeIcon.sublevel == 0
        and button.EmptyBagIcon == nativeCue and button:GetScript("OnClick") == originalClick,
        "empty tint changed native item artwork, layers or input handlers")
    ContainerFrameCombinedBags, ContainerFrameContainer, GamepadBagBar = oldCombined, oldContainers, oldGamepad
end
print("colors.lua: passed")
