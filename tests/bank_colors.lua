-- Native-bank contract fixture. No bank transactions or addon implementations
-- are simulated here: only pooled identities, visibility and visual ownership.
local allocations = { frames = 0, textures = 0 }
local combat, identityMistakes, bankReads = false, 0, 0
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
function Region:SetSize(width, height) self.width, self.height = width, height end
function Region:SetColorTexture(...) self.color = { ... } end
function Region:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
local Frame = setmetatable({}, { __index = Region })
Frame.__index = Frame
function Frame:GetObjectType() return "Frame" end
function Frame:GetParent() return self.parent end
function Frame:IsForbidden() return self.forbidden == true end
function Frame:IsShown() return self.shown ~= false end
function Frame:IsVisible() return self:IsShown() and (not self.parent or self.parent:IsVisible()) end
function Frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Frame:SetScript(name, callback) self.scripts[name] = callback end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, callback)
    self.scriptHooks[name] = self.scriptHooks[name] or {}
    self.scriptHooks[name][#self.scriptHooks[name] + 1] = callback
    return true
end
function Frame:Fire(name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, callback in ipairs(self.scriptHooks[name] or {}) do callback(self, ...) end
end
function Frame:Show()
    if self.shown == false then self.shown = true; self:Fire("OnShow") end
end
function Frame:Hide()
    if self.shown ~= false then self.shown = false; self:Fire("OnHide") end
end
function Frame:EnableMouse(value) self.mouseEnabled = value end
function Frame:GetFrameLevel() return self.level or 10 end
function Frame:SetFrameLevel(value) self.level = value end
function Frame:GetRect() return self.left, self.bottom, self.width, self.height end
function Frame:IsExtended() return false end
function Frame:CreateTexture(_, layer, _, sublevel)
    allocations.textures = allocations.textures + 1
    return setmetatable({ shown = false, layer = layer, sublevel = sublevel }, Region)
end
function Frame:SetMatchesSearch(matches) self.nativeMatches = matches end
function Frame:UpdateItems() end
function Frame:UpdateItemLayout() end
function Frame:UpdateItemSlots() end
function Frame:UpdateFrameSize() end
function Frame:Refresh() end
function Frame:UpdateTextures() end
function Frame:SetItemLocation(location) self.itemLocation = location end
function CreateFrame(_, _, parent)
    allocations.frames = allocations.frames + 1
    return setmetatable({ parent = parent, shown = true, scripts = {}, scriptHooks = {} }, Frame)
end
function hooksecurefunc(object, method, callback)
    if type(object) == "string" then callback, method, object = method, object, _G end
    local original = assert(object[method])
    object[method] = function(...)
        local results = { original(...) }
        callback(...)
        return unpack(results)
    end
end
function InCombatLockdown() return combat end
C_RestrictedActions = { CheckAllowProtectedFunctions = function(frame, silent)
    assert(silent == true, "native permission probes must remain silent")
    return not frame.denied
end }
Enum = {
    BankType = { Character = 0, Guild = 1, Account = 2 },
    BagIndex = { Backpack = 0, Keyring = -1, Characterbanktab = -2, Accountbanktab = -3,
        CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
        CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11,
        CharacterBankTab_7 = 12, CharacterBankTab_8 = 13, CharacterBankTab_9 = 14,
        AccountBankTab_1 = 15, AccountBankTab_9 = 23 },
}
C_Container = {
    GetContainerItemInfo = function(bag, slot)
        if bag >= 6 then bankReads = bankReads + 1 end
        return infoBySlot[bag .. ":" .. slot]
    end,
    PickupContainerItem = function() error("bank decoration must not move items") end,
    SortBags = function() error("bank decoration must not organize carried items") end,
}
C_Bank = {
    ShouldUsePlayerBagsInBank = function() return true end,
    CanViewBank = function(bankType) return bankType == Enum.BankType.Character end,
    FetchPurchasedBankTabData = function(bankType)
        if bankType == Enum.BankType.Character then return { { ID = 6 }, { ID = 7 }, { ID = 8 }, { ID = 14 } } end
        return {}
    end,
    AutoDepositItemsIntoBank = function() error("bank decoration must not deposit items") end,
    PurchaseBankTab = function() error("bank decoration must not purchase storage") end,
}
ContainerFrame_GenerateFrame = function() end
ContainerFrameContainer = nil
for index = 1, 16 do _G["ContainerFrame" .. index] = nil end
GamepadBagBar, KeyRingButton, MainMenuBarBackpackButton = nil, nil, nil
for index = 0, 3 do _G["CharacterBag" .. index .. "Slot"] = nil end
CharacterReagentBag0Slot = nil

local function Pool()
    local pool = { active = {} }
    function pool:EnumerateActive() return next, self.active end
    function pool:GetNumActive()
        local count = 0; for _ in pairs(self.active) do count = count + 1 end; return count
    end
    function pool:Add(button) self.active[button] = true; button:Show() end
    function pool:ReleaseAll()
        for button in pairs(self.active) do button.isInitialized = false; button:Hide() end
        self.active = {}
    end
    return pool
end

local addon = {
    db = { appearance = { mode = "tint", outline = "groups", tintAlpha = 0.16, outlineAlpha = 0.65, bagOutlineAlpha = 0.65,
        colors = { [-1] = { 0.9, 0.9, 0.9 }, [0] = { 0.1, 0.1, 0.1 }, [1] = { 0.12, 0.23, 0.34 },
            [2] = { 0.2, 0.3, 0.4 }, [3] = { 0.3, 0.4, 0.5 }, [4] = { 0.4, 0.5, 0.6 }, [5] = { 0.5, 0.6, 0.7 } },
        bankColors = {},
    } },
    bankColorChoices = {}, reports = {},
    IsPublic = function(value) return not rawequal(value, secret) end,
}
for position = 1, 9 do
    addon.db.appearance.bankColors[position] = { 0.5 + position / 25, 0.2 + position / 30, 0.3 }
    addon.bankColorChoices[position] = { position, position == 1 and "Bank storage" or "Bank bag " .. (position - 1) }
end
function addon.IsFiniteNumber(value)
    return addon.IsPublic(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
function addon:ReportOnce(key, message) self.reports[key] = message end

-- Keep a carried bag visible beside the bank to expose namespace collisions.
ContainerFrameCombinedBags = CreateFrame("Frame")
local carried = CreateFrame("Frame", nil, ContainerFrameCombinedBags)
function carried:GetBagID() return 1 end
function carried:GetID() return 1 end
function carried:Initialize() end
carried.left, carried.bottom, carried.width, carried.height = 0, 300, 37, 37
ContainerFrameCombinedBags.Items = { carried }
infoBySlot["1:1"] = { isFiltered = false }

BankFrame = CreateFrame("Frame")
local bank, panel = BankFrame, CreateFrame("Frame", nil, BankFrame)
BankFrame.BankPanel = panel
bank.bankType, panel.bankType = Enum.BankType.Character, Enum.BankType.Character
panel.itemButtonPool, bank.itemButtonBagPool = Pool(), Pool()
function bank:GetActiveBankType() return self.bankType end
function panel:GetActiveBankType() return self.bankType end
function panel:EnumerateValidItems() return self.itemButtonPool:EnumerateActive() end
function bank:RefreshBagButtons() end
function bank:RefreshAll() self:RefreshBagButtons(); self.BankPanel:GenerateItemSlotsForSelectedTab() end
function panel:GenerateItemSlotsForSelectedTab() end
function panel:RefreshAllItemsForSelectedTab()
    for button in self:EnumerateValidItems() do button:Refresh() end
end
function panel:UpdateSearchResults()
    for button in self:EnumerateValidItems() do button:Refresh() end
end

local untouchedArt = {
    SetColorTexture = function() error("native bank art was recolored") end,
    SetVertexColor = function() error("native bank art was recolored") end,
    SetAtlas = function() error("native bank atlas was replaced") end,
    SetDrawLayer = function() error("native bank artwork was reordered") end,
}
local nativeAssets = {}
local function NativeLayer(layer, sublevel)
    local texture = setmetatable({ layer = layer, sublevel = sublevel }, { __index = untouchedArt })
    function texture:GetDrawLayer() return self.layer, self.sublevel end
    function texture:GetObjectType() return "Texture" end
    function texture:GetParent() return self.parent end
    function texture:GetAtlas() return self.atlas end
    return texture
end
local nativeClick, nativeDrag, nativeReceive, nativeEnter = function() end, function() end, function() end, function() end
local function NativeScripts(button)
    button:SetScript("OnClick", nativeClick)
    button:SetScript("OnDragStart", nativeDrag)
    button:SetScript("OnReceiveDrag", nativeReceive)
    button:SetScript("OnEnter", nativeEnter)
    -- Native bank backgrounds are opaque at BACKGROUND0. Item artwork starts
    -- above that at BORDER0; normal/search/hover art must keep its own state.
    button.Background = NativeLayer("BACKGROUND", 0)
    button.icon = NativeLayer("BORDER", 0)
    button.BagIndicator, button.NormalTexture, button.SearchOverlay = untouchedArt, untouchedArt, untouchedArt
    nativeAssets[button] = { icon = button.icon, Background = button.Background,
        BagIndicator = button.BagIndicator, NormalTexture = button.NormalTexture, SearchOverlay = button.SearchOverlay }
end
local function Content(bankTab, slot, column, row, occupied)
    local button = CreateFrame("Frame", nil, panel)
    button.bankType, button.bankTabID, button.containerSlotID = Enum.BankType.Character, bankTab, slot
    button.isInitialized = true
    button.left, button.bottom, button.width, button.height = column * 50, 300 - row * 47, 37, 37
    function button:GetBankType() return self.bankType end
    function button:GetBankTabID() return self.bankTabID end
    function button:GetContainerSlotID() return self.containerSlotID end
    function button:GetID() identityMistakes = identityMistakes + 1; error("bank item GetID is not its container slot") end
    function button:Init(bankType, tab, containerSlot)
        self.bankType, self.bankTabID, self.containerSlotID = bankType, tab, containerSlot
        self.isInitialized = true
        self:Refresh()
    end
    function button:Refresh()
        local info = C_Container.GetContainerItemInfo(self.bankTabID, self.containerSlotID)
        self.itemInfo = info
        self:SetMatchesSearch(not (info and info.isFiltered))
    end
    infoBySlot[bankTab .. ":" .. slot] = occupied and { isFiltered = false } or nil
    NativeScripts(button)
    panel.itemButtonPool:Add(button)
    return button
end
local baseA = Content(6, 1, 0, 0, true)
local baseB = Content(6, 2, 1, 0, false)
local firstBagA = Content(7, 1, 2, 0, true)
local baseC = Content(6, 3, 3, 0, true)
local firstBagB = Content(7, 2, 0, 1, true)
local firstBagC = Content(7, 3, 1, 1, false)
local gapLeft = Content(7, 4, 0, 2, true)
local gapRight = Content(7, 5, 2, 2, false)
local lastBag = Content(14, 1, 3, 2, true)
local validItems = { baseA, baseB, firstBagA, baseC, firstBagB, firstBagC, gapLeft, gapRight, lastBag }

local function BagIcon(position, locked)
    local button = CreateFrame("Frame", nil, bank)
    button.bankType, button.bagSlotID, button.isInitialized = Enum.BankType.Character, position, true
    function button:GetExactBankTabSlot() return 6 + self.bagSlotID - 1 end
    function button:GetID() identityMistakes = identityMistakes + 1; error("bank icon GetID is an inventory identifier") end
    function button:GetBagAndSlot() return -2, self.bagSlotID end
    button.DisabledOverlay = CreateFrame("Frame", nil, button)
    button.DisabledOverlay:SetShown(locked)
    NativeScripts(button)
    bank.itemButtonBagPool:Add(button)
    return button
end
local firstBagIcon, lastBagIcon, lockedIcon = BagIcon(2, false), BagIcon(9, false), BagIcon(4, true)
local wrongBankType = Content(6, 1, 4, 0, true)
wrongBankType.bankType = Enum.BankType.Account
local wrongContainer = Content(1, 1, 5, 0, true) -- Character bank must not borrow carried bag 1's palette.
local holder = Content(-2, 2, 6, 0, true) -- Location of the bag item, not the bag's contents.
local uninitialized = Content(8, 1, 7, 0, true)
uninitialized.isInitialized = false

-- The native bank addon may not exist yet when our own addon loads.
bank:Hide()
BankFrame = nil
assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Colors.lua"))("ForTheHoard", addon)
local colors = addon.Colors
colors:Initialize()
local function VisibleFill(button)
    local state = colors.slots[button]
    return state and state.fill and state.fill.shown and state.fill
end
local function Hidden(button)
    local state = colors.slots[button]
    if not state then return true end
    if state.fill and state.fill.shown then return false end
    for _, edge in ipairs(state.edges or {}) do if edge.shown then return false end end
    return true
end
local function IconEdge(button)
    local state = colors.icons[button]
    return state and state.edges and state.edges[1]
end
local refreshPasses = 0
local nativeRefresh = colors.Refresh
function colors:Refresh(...)
    refreshPasses = refreshPasses + 1
    return nativeRefresh(self, ...)
end
local function DriverTick()
    assert(colors.driver:IsShown(), "native bank change did not queue the appearance driver")
    local before = refreshPasses
    colors.driver:Fire("OnUpdate")
    assert(refreshPasses == before + 1 and not colors.driver:IsShown(),
        "coalesced bank appearance did not render exactly once and go idle")
end
assert(colors.containers[panel] == nil and colors.slots[baseA] == nil,
    "missing native bank was treated as available at initialization")
BankFrame = bank
colors:OnEvent("ADDON_LOADED", "Blizzard_UIPanels_Game")
bankReads = 0
DriverTick()
assert(bankReads == 0 and colors.slots[baseA] == nil,
    "late but hidden bank was scanned before opening")
bank:Show()
colors:OnEvent("BANKFRAME_OPENED")
DriverTick()
assert(VisibleFill(baseA) and VisibleFill(baseB), "occupied and empty base-bank storage must both receive tint")
assert(VisibleFill(firstBagA) and VisibleFill(lastBag), "equipped bank bags must be discovered through native pool identities")
assert(VisibleFill(baseA).color[1] == addon.db.appearance.bankColors[1][1], "base bank uses position 1")
assert(VisibleFill(firstBagA).color[1] == addon.db.appearance.bankColors[2][1], "first equipped bank bag uses position 2")
assert(VisibleFill(lastBag).color[1] == addon.db.appearance.bankColors[9][1], "last declared personal bank position is supported")
assert(VisibleFill(carried).color[1] == addon.db.appearance.colors[1][1], "bank additions changed carried bag colors")
assert(VisibleFill(carried).color[1] ~= VisibleFill(baseA).color[1], "bank palette aliased the carried palette")
assert(Hidden(wrongBankType), "account identity was accepted as personal bank storage")
assert(Hidden(wrongContainer), "carried identity was accepted as personal bank storage")
assert(Hidden(holder), "bank-bag holder pseudo-container was accepted as item storage")
assert(Hidden(uninitialized), "uninitialized pooled button was accepted as personal bank storage")
assert(IconEdge(firstBagIcon) and IconEdge(firstBagIcon).shown
    and IconEdge(firstBagIcon).color[1] == VisibleFill(firstBagA).color[1], "bank bag icon must match its content color")
assert(IconEdge(firstBagIcon).height == 1 and IconEdge(firstBagIcon).points[1][4] == -1,
    "Toolbar visibility correction must preserve bank icon geometry")
assert(IconEdge(lastBagIcon) and IconEdge(lastBagIcon).color[1] == addon.db.appearance.bankColors[9][1],
    "bank icon identity incorrectly used an inventory slot or pseudo-container")
assert(not IconEdge(lockedIcon) or not IconEdge(lockedIcon).shown, "unpurchased bank slot received an equipped-bag accent")

-- Layer ordering is a contract assertion, not a raster simulation: the same
-- selected opacity must reach both bag types without hiding beneath bank art.
local layerRank = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local function Above(upper, lower)
    local upperRank, lowerRank = assert(layerRank[upper.layer]), assert(layerRank[lower.layer])
    return upperRank > lowerRank or upperRank == lowerRank and upper.sublevel > lower.sublevel
end
local bankFill, carriedFill = VisibleFill(baseA), VisibleFill(carried)
assert(Above(bankFill, baseA.Background), "owned bank tint is covered by the opaque native bank background")
assert(Above(baseA.icon, bankFill), "owned bank tint covers native item artwork")
assert(carriedFill.layer == "BACKGROUND" and carriedFill.sublevel == -8,
    "bank-layer correction unexpectedly changed the carried tint layer")
local oldBankRGB = { unpack(addon.db.appearance.bankColors[1]) }
local oldAlpha = addon.db.appearance.tintAlpha
for channel = 1, 3 do addon.db.appearance.bankColors[1][channel] = addon.db.appearance.colors[1][channel] end
local tintTextureCount = allocations.textures
for _, alpha in ipairs({ 0.16, 0, 1 }) do
    addon.db.appearance.tintAlpha = alpha
    baseA:SetMatchesSearch(true); carried:SetMatchesSearch(true)
    colors:Refresh()
    assert(colors.slots[baseA].fill == bankFill and colors.slots[carried].fill == carriedFill,
        "changing opacity replaced a retained tint texture")
    for channel = 1, 3 do
        assert(bankFill.color[channel] == carriedFill.color[channel], "bank tint compensated with different RGB values")
    end
    assert(bankFill.color[4] == alpha and carriedFill.color[4] == alpha,
        "bank and carried bags do not honor the same requested tint opacity")
    baseA:SetMatchesSearch(false); carried:SetMatchesSearch(false)
    colors:Refresh()
    assert(math.abs(bankFill.color[4] - alpha * 0.2) < 0.0000001
        and math.abs(carriedFill.color[4] - alpha * 0.2) < 0.0000001,
        "search filtering changed bank and carried opacity differently")
    assert(Above(bankFill, baseA.Background) and Above(baseA.icon, bankFill),
        "repainting moved bank tint outside the native background/item-art layers")
end
assert(allocations.textures == tintTextureCount, "bank opacity updates allocated replacement textures")
for channel = 1, 3 do addon.db.appearance.bankColors[1][channel] = oldBankRGB[channel] end
addon.db.appearance.tintAlpha = oldAlpha
baseA:SetMatchesSearch(true); carried:SetMatchesSearch(true)
colors:Refresh()

-- Concrete native hooks must request a repaint; manual Refresh calls would
-- hide missing lifecycle subscriptions. Several changes share one driver tick.
baseA:Init(Enum.BankType.Character, 14, 1)
panel:GenerateItemSlotsForSelectedTab()
bank:RefreshBagButtons()
DriverTick()
assert(VisibleFill(baseA).color[1] == addon.db.appearance.bankColors[9][1],
    "native Init/page generation did not repaint the reused button")
baseA:Init(Enum.BankType.Character, 6, 1)
panel:GenerateItemSlotsForSelectedTab()
DriverTick()
infoBySlot["6:1"].isFiltered = true
panel:UpdateSearchResults()
DriverTick()
assert(math.abs(VisibleFill(baseA).color[4] - 0.032) < 0.00001,
    "native bank search hook did not repaint search dimming")
infoBySlot["6:1"].isFiltered = false
panel:UpdateSearchResults()
DriverTick()
firstBagIcon.bagSlotID = 9
bank:RefreshBagButtons()
DriverTick()
assert(IconEdge(firstBagIcon).color[1] == addon.db.appearance.bankColors[9][1],
    "native bank bag-button refresh did not repaint reused icon identity")
firstBagIcon.bagSlotID = 2
bank:RefreshBagButtons()
DriverTick()

local firstBankIndex = Enum.BagIndex.CharacterBankTab_1
Enum.BagIndex.CharacterBankTab_1 = 1 -- A malformed/other-product domain overlaps a carried position.
colors:Refresh()
assert(Hidden(baseA) and VisibleFill(carried).color[1] == addon.db.appearance.colors[1][1],
    "an overlapping bank enum reused a carried bag color or corrupted the carried palette")
Enum.BagIndex.CharacterBankTab_1 = firstBankIndex
colors:Refresh()

baseA:SetMatchesSearch(false)
colors:Refresh()
assert(math.abs(VisibleFill(baseA).color[4] - 0.032) < 0.00001, "bank tint ignores native search dimming")
assert(baseA.nativeMatches == false, "appearance overwrote native bank search state")

addon.db.appearance.mode, addon.db.appearance.outline = "outline", "groups"
baseB.level = 16
colors:Refresh()
local groups = colors.containers[panel].groups
assert(#groups == 7, "bank rows, intervening bags and wide gaps must split cartouches")
assert(groups[1].points[1][2] == baseA and groups[1].points[2][2] == baseB,
    "native 13px bank spacing should keep neighboring slots in their bag cartouche")
for _, group in ipairs(groups) do assert(group.mouseEnabled == false, "bank cartouches intercept native clicks") end
assert(groups[1]:GetFrameLevel() > baseB:GetFrameLevel(), "Bank cartouche remains behind native item surfaces")
assert(groups[1].edges[1].height == 2 and groups[1].edges[3].width == 2,
    "Bank cartouche stroke does not match carried cartouches")
assert(groups[1].points[1][5] >= groups[1].edges[1].height,
    "Bank cartouche covers native artwork instead of the outside perimeter")
assert(groups[1].edges[1].color[4] == addon.db.appearance.outlineAlpha,
    "Bank cartouche ignores the shared outline opacity")

-- Personal-bank icons share the equipped-button setting, not content opacity.
baseA:SetMatchesSearch(true); baseB:SetMatchesSearch(true); firstBagA:SetMatchesSearch(true)
for _, pair in ipairs({ { 0.25, 0.8 }, { 0, 1 }, { 1, 0 } }) do
    addon.db.appearance.outlineAlpha, addon.db.appearance.bagOutlineAlpha = pair[1], pair[2]
    addon.db.appearance.outline = "groups"
    colors:Refresh()
    assert(groups[1].edges[1].color[4] == pair[1] and IconEdge(firstBagIcon).color[4] == pair[2],
        "bank cartouches and bag buttons did not separate their opacities")
    addon.db.appearance.outline = "slots"
    colors:Refresh()
    assert(colors.slots[firstBagA].edges[1].color[4] == pair[1] and IconEdge(firstBagIcon).color[4] == pair[2],
        "bank slot outlines inherited equipped-button opacity")
    addon.db.appearance.mode = "tint"
    colors:Refresh()
    assert(VisibleFill(firstBagA).color[4] == addon.db.appearance.tintAlpha and IconEdge(firstBagIcon).color[4] == pair[2],
        "bank equipped-button opacity changed content tint")
    addon.db.appearance.mode = "outline"
end
addon.db.appearance.outlineAlpha, addon.db.appearance.bagOutlineAlpha = 0.65, 0.65

addon.db.appearance.outline = "slots"
colors:Refresh()
assert(colors.slots[firstBagA].edges[1].shown and not groups[1].shown,
    "bank individual outlines did not replace cartouches")
assert(colors.slots[firstBagA].edges[1].height == 2,
    "Bank and carried item slots must share the readable exterior perimeter")

-- Pool reuse must use Init's current bank-tab/container-slot fields immediately.
addon.db.appearance.mode = "tint"
colors:Refresh()
baseA:Init(Enum.BankType.Character, 14, 1)
assert(Hidden(baseA), "pooled bank slot kept its old accent between native Init and repaint")
colors:Refresh()
assert(VisibleFill(baseA).color[1] == addon.db.appearance.bankColors[9][1], "reused button kept its old bank position")
baseA:Init(Enum.BankType.Account, 15, 1)
colors:Refresh()
assert(Hidden(baseA), "account-tab reuse retained a personal-bank accent")
firstBagIcon.bagSlotID = 9
bank:RefreshBagButtons(); colors:Refresh()
assert(IconEdge(firstBagIcon).color[1] == addon.db.appearance.bankColors[9][1], "reused bank icon kept its old position")

-- Warm every lazy style and the worst-case run count, then cycle pages using
-- the same native objects. Nothing should allocate per tab or per page.
for index, button in ipairs(validItems) do button:Init(Enum.BankType.Character, 5 + index, 1) end
addon.db.appearance.mode = "tint"; colors:Refresh()
addon.db.appearance.mode, addon.db.appearance.outline = "outline", "slots"; colors:Refresh()
addon.db.appearance.outline = "groups"; colors:Refresh()
local warmTextures, warmFrames = allocations.textures, allocations.frames
for cycle = 1, 30 do
    for index, button in ipairs(validItems) do button:Init(Enum.BankType.Character, 6 + ((index + cycle) % 9), 1) end
    panel:GenerateItemSlotsForSelectedTab(); colors:Refresh()
end
assert(allocations.textures == warmTextures and allocations.frames == warmFrames,
    "native page reuse leaked decorative textures or cartouche frames")
assert(#baseA.scriptHooks.OnHide == 1 and #firstBagIcon.scriptHooks.OnHide == 1,
    "pooled bank objects accumulated duplicate hooks")

addon.db.appearance.mode = "tint"
baseA:Init(Enum.BankType.Character, 14, 1)
colors:Refresh()
baseA.bankTabID = secret
colors:Refresh()
assert(Hidden(baseA), "restricted bank-tab identity retained an old accent")
baseA.bankTabID, baseA.containerSlotID = 14, secret
colors:Refresh()
assert(Hidden(baseA), "restricted bank slot was used or guessed through GetID")
baseA.containerSlotID = 1
local ninthRed = addon.db.appearance.bankColors[9][1]
addon.db.appearance.bankColors[9][1] = secret
colors:Refresh()
assert(Hidden(baseA), "restricted bank palette component was operated on")
addon.db.appearance.bankColors[9][1] = ninthRed
local exactIdentity = firstBagIcon.GetExactBankTabSlot
firstBagIcon.GetExactBankTabSlot = function() return secret end
colors:Refresh()
assert(not IconEdge(firstBagIcon).shown, "restricted bank icon identity retained its old accent")
firstBagIcon.GetExactBankTabSlot = exactIdentity
firstBagIcon.GetExactBankTabSlot = function() return 7 end
colors:Refresh()
assert(not IconEdge(firstBagIcon).shown, "conflicting bank-bag position and exact tab ID were accepted")
firstBagIcon.GetExactBankTabSlot = exactIdentity
firstBagIcon.bankType = Enum.BankType.Account
colors:Refresh()
assert(not IconEdge(firstBagIcon).shown, "account reuse of a bank icon retained a personal accent")
firstBagIcon.bankType = Enum.BankType.Character

addon.db.appearance.mode = "tint"; colors:Refresh()
bank:Hide(); colors:Refresh(); bankReads = 0
colors:Refresh()
assert(bankReads == 0, "closed bank caused stale container-data reads")
for _, button in ipairs(validItems) do assert(Hidden(button), "closed bank kept a slot accent visible") end
assert(not IconEdge(firstBagIcon).shown, "closed bank kept a bank-bag icon accent visible")
bank:Show(); colors:Refresh()
assert(VisibleFill(baseA), "bank reopen did not restore current native content accents")
panel:Hide(); colors:Refresh(); bankReads = 0
colors:Refresh()
assert(bankReads == 0 and Hidden(baseA), "hidden bank panel was still scanned or decorated")
panel:Show(); colors:Refresh()
panel.itemButtonPool:ReleaseAll(); colors:Refresh()
for _, button in ipairs(validItems) do assert(Hidden(button), "released pool button retained an old accent") end

addon.db.appearance.mode = "off"; colors:Refresh()
for _, state in pairs(colors.slots) do
    if state.fill then assert(not state.fill.shown, "Off kept an owned bank/carried fill") end
    for _, edge in ipairs(state.edges or {}) do assert(not edge.shown, "Off kept an owned slot outline") end
end
for _, state in pairs(colors.icons) do
    for _, edge in ipairs(state.edges or {}) do assert(not edge.shown, "Off kept a bank icon outline") end
end

combat = true
local deferred = Content(7, 1, 0, 0, true)
local beforeCombat = allocations.textures
addon.db.appearance.mode = "tint"
colors:Refresh()
assert(colors.slots[deferred] == nil and allocations.textures == beforeCombat,
    "bank decoration created native descendants during combat")
combat = false
colors:OnEvent("PLAYER_REGEN_ENABLED"); colors:Refresh()
assert(VisibleFill(deferred), "bank decoration did not recover after combat")

local denied = Content(7, 1, 0, 0, true)
denied.denied = true
denied.GetBankTabID = function() error("denied bank identity must not be read") end
addon.db.appearance.mode = "tint"
local beforeDenied = allocations.textures
colors:Refresh()
assert(colors.slots[denied] == nil and allocations.textures == beforeDenied, "denied native bank button was decorated")
assert(identityMistakes == 0, "bank code guessed identity from GetID")
assert(firstBagIcon:GetScript("OnClick") == nativeClick and firstBagIcon:GetScript("OnDragStart") == nativeDrag
    and firstBagIcon:GetScript("OnReceiveDrag") == nativeReceive and firstBagIcon:GetScript("OnEnter") == nativeEnter,
    "bank icon decoration replaced native purchase, dragging or hover behavior")
assert(firstBagA:GetScript("OnClick") == nativeClick and firstBagA:GetScript("OnDragStart") == nativeDrag
    and firstBagA:GetScript("OnReceiveDrag") == nativeReceive, "bank slot decoration changed item transactions")
for button, assets in pairs(nativeAssets) do
    for name, original in pairs(assets) do assert(button[name] == original, "native bank " .. name .. " object was replaced") end
    assert(button.Background.layer == "BACKGROUND" and button.Background.sublevel == 0
        and button.icon.layer == "BORDER" and button.icon.sublevel == 0, "native bank art draw order was changed")
end
assert(next(addon.reports) == nil, "supported bank paths unexpectedly reported a failure")

-- The shipped divider is an unnamed direct texture, scaled to .48 and anchored
-- BOTTOM at y220. Captured bounding geometry does not rasterize its atlas ink.
local oldBank, oldCombined = BankFrame, ContainerFrameCombinedBags
-- The root stays at its TOP anchor; the native panel is LEFT-centered on it.
-- Item geometry follows the panel TOP, while divider/holders follow root BOTTOM.
-- The initial physical rects are calibrated from the user's0.1.19 snapshot;
-- this does not claim that unrecorded native baseline heights were measured.
local function FooterFixture(beforeInitialize)
    local fixture = { rootScale = 0.711111, panelScale = 0.711111, rows = 7 }
    fixture.scale = fixture.panelScale
    local root, panel, viewport = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")
    root.parent, panel.parent, root.BankPanel = viewport, root, panel
    root.height, panel.height, root.width, panel.width = 507, 507, 560, 480
    root.nativeHeight, panel.nativeHeight, root.heightWrites, panel.heightWrites = 507, 507, 0, 0
    fixture.top = 409.982 - 220 * 0.48 * fixture.rootScale + root.height * fixture.rootScale
    local capturedItemOffset = (fixture.top - 413.867) / fixture.panelScale - 37 - 63 - (fixture.rows - 1) * 47
    root.bankType, panel.bankType = Enum.BankType.Character, Enum.BankType.Character
    root.itemButtonBagPool, panel.itemButtonPool = Pool(), Pool()
    function root:GetActiveBankType() return self.bankType end
    function panel:GetActiveBankType() return self.bankType end
    function root:GetEffectiveScale() return fixture.rootScale end
    function panel:GetEffectiveScale() return fixture.panelScale end
    function root:GetScale() return fixture.rootScale end
    function panel:GetScale() return fixture.panelScale / fixture.rootScale end
    function root:GetParent() return viewport end
    local function Height(frame)
        if frame.failReadback and frame.height ~= frame.nativeHeight then error("injected height readback failure") end
        return frame.height
    end
    root.GetHeight, panel.GetHeight = Height, Height
    local function SetHeight(frame, height)
        frame.heightWrites = frame.heightWrites + 1
        if frame.failBefore then error("injected height setter failure") end
        if frame.rejectHeight then return end
        frame.height = height
        frame:Fire("OnSizeChanged", frame.width, height)
        if frame.failAfter then frame.failAfter = nil; error("injected post-height setter failure") end
    end
    root.SetHeight, panel.SetHeight = SetHeight, SetHeight
    local function RootTop()
        local delta = (root.height - 507) * fixture.rootScale
        if fixture.anchorMode == "BOTTOMLEFT" then return fixture.top + delta end
        if fixture.anchorMode == "CENTER" then return fixture.top + delta * 0.5 end
        return fixture.top
    end
    function root:GetScaledRect()
        return 0, RootTop() - self.height * fixture.rootScale, self.width * fixture.rootScale, self.height * fixture.rootScale
    end
    function panel:GetScaledRect()
        local center = RootTop() - root.height * fixture.rootScale * 0.5
        local height = self.height * fixture.panelScale
        return 0, center - height * 0.5, self.width * fixture.panelScale, height
    end
    local function Rect(frame)
        local left, bottom, width, height = frame:GetScaledRect()
        local scale = frame:GetEffectiveScale()
        return left / scale, bottom / scale, width / scale, height / scale
    end
    root.GetRect, panel.GetRect = Rect, Rect
    local function Top(frame)
        local _, bottom, _, height = frame:GetScaledRect()
        return (bottom + height) / frame:GetEffectiveScale()
    end
    root.GetTop, panel.GetTop = Top, Top
    function root:GetNumPoints() return 1 end
    function root:GetPoint() return fixture.anchorMode or "TOPLEFT", viewport, fixture.anchorMode or "TOPLEFT", 0, 0 end
    function panel:GetNumPoints() return 1 end
    function panel:GetPoint() return "LEFT", root, "LEFT", 0, 0 end
    fixture.pointWrites = 0
    local function PreservePoint()
        fixture.pointWrites = fixture.pointWrites + 1
        error("footer sizing must preserve native window anchors")
    end
    root.SetPoint, panel.SetPoint = PreservePoint, PreservePoint
    function root:GetWidth() return self.width end
    function panel:GetWidth() return self.width end
    function panel:EnumerateValidItems() return self.itemButtonPool:EnumerateActive() end
    function root:RefreshBagButtons() end
    function panel:GenerateItemSlotsForSelectedTab(rows)
        if fixture.skipNativeHeight then return end -- Native loading can return before setting either height.
        fixture.rows = rows or fixture.rows
        local nativeHeight = 460 + math.max(0, fixture.rows - 6) * 47
        root.nativeHeight, panel.nativeHeight = nativeHeight, nativeHeight
        root:SetHeight(nativeHeight)
        panel:SetHeight(nativeHeight)
    end
    local item = CreateFrame("Frame", nil, panel)
    item.bankType, item.bankTabID, item.containerSlotID, item.isInitialized = Enum.BankType.Character, 6, 1, true
    function item:GetBankType() return self.bankType end
    function item:GetBankTabID() return self.bankTabID end
    function item:GetContainerSlotID() return self.containerSlotID end
    function item:Init() end
    function item:GetEffectiveScale() return fixture.panelScale end
    function item:GetScaledRect()
        local _, bottom, _, height = panel:GetScaledRect()
        local inset = 63 + (fixture.rows - 1) * 47 + capturedItemOffset
        return 20 * fixture.panelScale, bottom + height - (inset + 37) * fixture.panelScale,
            37 * fixture.panelScale, 37 * fixture.panelScale
    end
    item.GetRect = Rect
    function item:GetPoint() return "TOPLEFT", panel, "TOPLEFT", 20, -(63 + (fixture.rows - 1) * 47 + capturedItemOffset) end
    panel.itemButtonPool:Add(item)
    local function Holder(position, locked)
        local holder = CreateFrame("Frame", nil, root)
        holder.bankType, holder.bagSlotID, holder.isInitialized = Enum.BankType.Character, position, true
        holder.DisabledOverlay = CreateFrame("Frame", nil, holder)
        holder.DisabledOverlay:SetShown(locked)
        function holder:GetExactBankTabSlot() return 5 + self.bagSlotID end
        function holder:GetBagAndSlot() return -2, self.bagSlotID end
        function holder:GetScale() return 0.75 end
        function holder:GetEffectiveScale() return fixture.rootScale * 0.75 end
        function holder:GetScaledRect()
            local _, rootBottom = root:GetScaledRect()
            local scale = self:GetEffectiveScale()
            local bottom = self.bottom and self.bottom * fixture.panelScale or (115 - 37 * 0.5) * scale
            return 200 * scale, rootBottom + bottom, 37 * scale, 37 * scale
        end
        root.itemButtonBagPool:Add(holder)
        return holder
    end
    local holder, locked = Holder(2, false), Holder(3, true)
    local divider = { parent = root, atlas = "bank-divider", scale = 0.48, shown = true,
        points = { { "BOTTOM", root, "BOTTOM", 0, 220 } }, writes = 0 }
    function divider:IsForbidden() return self.forbidden == true end
    function divider:GetObjectType() return "Texture" end
    function divider:GetParent() return self.parent end
    function divider:GetAtlas() return self.atlas end
    function divider:IsShown() return self.shown end
    function divider:IsVisible() return self.shown and root:IsVisible() end
    function divider:GetScale() return self.scale end
    function divider:GetEffectiveScale() return self.scale * fixture.rootScale end
    function divider:GetNumPoints() return #self.points end
    function divider:GetPoint() return unpack(self.points[1]) end
    function divider:SetPoint()
        self.writes = self.writes + 1
        error("native divider anchoring must remain unchanged")
    end
    function divider:GetScaledRect()
        local _, bottom = root:GetScaledRect()
        local scale = self:GetEffectiveScale()
        return 0, bottom + self.points[1][5] * scale, 800 * scale, 32 * scale
    end
    divider.GetRect = Rect
    local background = NativeLayer("BACKGROUND", 0); background.parent = root
    root.regions = { background, divider }
    function root:GetNumRegions() return #self.regions end
    function root:GetRegions() return unpack(self.regions) end
    local fresh = { version = "test-client", db = { appearance = { mode = "outline", outline = "slots", outlineAlpha = 0.65,
        tintAlpha = 0.16, bagOutlineAlpha = 0.65, colors = {}, bankColors = addon.db.appearance.bankColors } },
        bankColorChoices = addon.bankColorChoices, reports = {}, reportCounts = {},
        IsPublic = addon.IsPublic, IsFiniteNumber = addon.IsFiniteNumber }
    function fresh:ReportOnce(key, message)
        if not self.reports[key] then self.reportCounts[key] = (self.reportCounts[key] or 0) + 1 end
        self.reports[key] = message
    end
    fixture.root, fixture.panel, fixture.item = root, panel, item
    fixture.holder, fixture.locked, fixture.divider, fixture.addon = holder, locked, divider, fresh
    function fixture:Bounds()
        local _, itemBottom, _, itemHeight = item:GetScaledRect()
        local _, dividerBottom, _, dividerHeight = divider:GetScaledRect()
        local highest
        for button in root.itemButtonBagPool:EnumerateActive() do
            if button:IsVisible() then
                local _, bottom, _, height = button:GetScaledRect()
                highest = math.max(highest or -math.huge, bottom + height + button:GetEffectiveScale())
            end
        end
        return itemBottom, dividerBottom, dividerHeight, highest, itemBottom + itemHeight
    end
    fixture.initial = { fixture:Bounds() }
    function fixture:AnchorY() return self.divider.points[1][5] end
    function fixture:Settle()
        local ticks = 0
        while self.colors.driver:IsShown() do
            ticks = ticks + 1
            assert(ticks <= 4, "Owned bank height changes caused an endless appearance/layout loop")
            self.colors.driver:Fire("OnUpdate")
        end
    end
    function fixture:Refresh() self.colors:Refresh(); self:Settle() end
    function fixture:Clearance()
        local itemBottom, dividerBottom, dividerHeight, highest = self:Bounds()
        assert(dividerBottom + dividerHeight <= itemBottom - 3 * self.panelScale + 0.00001,
            "Footer space still leaves native divider over the item perimeter")
        assert(dividerBottom >= highest + self.panelScale - 0.00001,
            "Footer space moved the native divider into a bag-holder outline")
        assert(self:AnchorY() == 220 and divider.writes == 0 and self.pointWrites == 0,
            "Footer layout changed a native window/divider anchor")
    end
    BankFrame, ContainerFrameCombinedBags = root, nil
    if beforeInitialize then beforeInitialize(fixture) end
    assert(loadfile(REPO_ROOT .. "/src/ForTheHoard/Colors.lua"))("ForTheHoard", fresh)
    fixture.colors = fresh.Colors
    fixture.colors:Initialize(); fixture:Settle()
    return fixture
end

local liveFooter = FooterFixture()
assert(math.abs(liveFooter.initial[1] - 413.867) < 0.000001 and math.abs(liveFooter.initial[2] - 409.982) < 0.000001,
    "The regression no longer starts from the actual client item/divider positions")
assert(math.abs(liveFooter.initial[3] - 10.9227) < 0.0001 and math.abs(liveFooter.initial[4] - 406.622) < 0.00001,
    "The native32-unit divider/.48 and37-unit holder/.75 scale contract changed")
assert(liveFooter.root.height == 520 and liveFooter.panel.height == 520,
    "The captured client overlap requires thirteen units of real root and panel footer space")
liveFooter:Clearance()
assert(math.abs(select(5, liveFooter:Bounds()) - liveFooter.initial[5]) < 0.00001,
    "Adding footer space shifted the native top-anchored item grid")
local heightWrites = liveFooter.root.heightWrites + liveFooter.panel.heightWrites
local footerFrames, footerTextures = allocations.frames, allocations.textures
for _ = 1, 30 do liveFooter:Refresh() end
assert(liveFooter.root.heightWrites + liveFooter.panel.heightWrites == heightWrites
    and allocations.frames == footerFrames and allocations.textures == footerTextures,
    "Settled footer layout repeats height writes or allocates native resources")
liveFooter.skipNativeHeight = true
liveFooter.panel:GenerateItemSlotsForSelectedTab(); liveFooter:Settle()
liveFooter.addon.db.appearance.mode = "off"; liveFooter:Refresh()
assert(liveFooter.root.height == 507 and liveFooter.panel.height == 507,
    "A native generation early return adopted our expanded height as the original baseline")
liveFooter.skipNativeHeight = false
liveFooter.addon.db.appearance.mode = "outline"; liveFooter:Refresh()
liveFooter.panel:GenerateItemSlotsForSelectedTab(7); liveFooter:Settle()
assert(liveFooter.root.height == 520 and liveFooter.panel.height == 520,
    "Native regeneration at the same original height accumulated footer growth")
liveFooter.panel:GenerateItemSlotsForSelectedTab(8)
assert(liveFooter.colors.driver:IsShown(), "Native page generation did not request footer reflow")
liveFooter:Settle(); liveFooter:Clearance()
assert(liveFooter.root.height == 567 and liveFooter.panel.height == 567,
    "Native row-height changes did not rebase both original heights before adding the measured space")
liveFooter.panel:GenerateItemSlotsForSelectedTab(3); liveFooter:Settle()
assert(liveFooter.root.height == 460 and liveFooter.panel.height == 460,
    "A shorter native page retained unnecessary footer height")
liveFooter.panel:GenerateItemSlotsForSelectedTab(7); liveFooter:Settle(); liveFooter:Clearance()
heightWrites = liveFooter.root.heightWrites + liveFooter.panel.heightWrites
liveFooter.addon.db.appearance.mode = "tint"; liveFooter:Refresh(); liveFooter:Clearance()
liveFooter.addon.db.appearance.mode = "outline"; liveFooter.addon.db.appearance.outline = "groups"; liveFooter:Refresh(); liveFooter:Clearance()
liveFooter.addon.db.appearance.outline = "slots"; liveFooter:Refresh(); liveFooter:Clearance()
assert(liveFooter.root.heightWrites + liveFooter.panel.heightWrites == heightWrites,
    "Switching active tint/outline/shape changed an already settled footer height")
liveFooter.rootScale, liveFooter.panelScale = liveFooter.rootScale * 0.8, liveFooter.panelScale * 0.8
liveFooter.scale = liveFooter.panelScale
liveFooter:Refresh(); liveFooter:Clearance()
assert(liveFooter.root.height == 520 and liveFooter.panel.height == 520
    and liveFooter.root.heightWrites + liveFooter.panel.heightWrites == heightWrites,
    "A uniform live UI-scale change cached physical geometry or accumulated footer height")
for _, inactive in ipairs({ "off", "outline-zero", "tint-zero" }) do
    if inactive == "outline-zero" then liveFooter.addon.db.appearance.outlineAlpha, liveFooter.addon.db.appearance.bagOutlineAlpha = 0, 1
    elseif inactive == "tint-zero" then liveFooter.addon.db.appearance.mode, liveFooter.addon.db.appearance.tintAlpha = "tint", 0
    else liveFooter.addon.db.appearance.mode = inactive end
    liveFooter:Refresh()
    assert(liveFooter.root.height == 507 and liveFooter.panel.height == 507,
        "Inactive item outlines retained custom native footer heights")
    if inactive == "outline-zero" then
        local icon = liveFooter.colors.icons[liveFooter.holder]
        assert(icon and icon.edges[1].shown and icon.edges[1].color[4] == 1,
            "Equipped bag-button opacity alone should not activate content footer space")
    end
    liveFooter.addon.db.appearance.mode, liveFooter.addon.db.appearance.outlineAlpha, liveFooter.addon.db.appearance.tintAlpha = "outline", 0.65, 0.16
    liveFooter:Refresh(); liveFooter:Clearance()
end
liveFooter.root:Hide(); liveFooter:Settle()
assert(liveFooter.root.height == 507 and liveFooter.panel.height == 507, "Bank dismissal did not restore both native heights")
liveFooter.root:Show(); liveFooter:Settle(); liveFooter:Clearance()
liveFooter.panel.bankType = Enum.BankType.Account; liveFooter:Refresh()
assert(liveFooter.root.height == 507 and liveFooter.panel.height == 507, "Account-panel reuse kept personal-bank footer space")

local unequalScale = FooterFixture(function(f) f.panelScale = 0.8; f.scale = f.panelScale end)
local rootDelta = (unequalScale.root.height - 507) * unequalScale.rootScale
local panelDelta = (unequalScale.panel.height - 507) * unequalScale.panelScale
assert(math.abs(rootDelta - panelDelta) < 0.00001, "Root/panel heights grew by unequal physical amounts")
unequalScale:Clearance()
for _, anchorMode in ipairs({ "BOTTOMLEFT", "CENTER" }) do
    local anchored = FooterFixture(function(f) f.anchorMode = anchorMode end)
    anchored:Clearance()
    assert(anchored.root.height == 520 and anchored.panel.height == 520 and anchored.root:GetPoint() == anchorMode,
        "Moving-window anchor mode changed measured footer growth or its anchor identity")
    local translation = 13 * anchored.rootScale * (anchorMode == "CENTER" and 0.5 or 1)
    assert(math.abs(select(5, anchored:Bounds()) - anchored.initial[5] - translation) < 0.00001,
        "Footer sizing failed to preserve the native translation of a bottom/center anchored window")
    local writes = anchored.root.heightWrites + anchored.panel.heightWrites
    for _ = 1, 10 do anchored:Refresh() end
    assert(anchored.root.heightWrites + anchored.panel.heightWrites == writes,
        "A bottom/center anchored bank caused a height reflow loop")
    anchored.addon.db.appearance.mode = "off"; anchored:Refresh()
    assert(anchored.root.height == 507 and anchored.panel.height == 507
        and anchored.pointWrites == 0 and anchored.divider.writes == 0,
        "Bottom/center anchored bank cleanup changed native anchors or restore baselines")
end
local foreignHeight = FooterFixture()
foreignHeight.root:SetHeight(foreignHeight.root.height + 7)
local foreignRoot = foreignHeight.root.height
foreignHeight.addon.db.appearance.mode = "off"; foreignHeight:Refresh()
assert(foreignHeight.root.height == foreignRoot and foreignHeight.panel.height == 507,
    "Footer cleanup must preserve the foreign side and restore the still-owned side")
local originalReset = FooterFixture()
originalReset.addon.db.appearance.mode = "off"; originalReset:Refresh()
originalReset.root:SetHeight(493.0625); originalReset.panel:SetHeight(493.0625)
originalReset.addon.db.appearance.mode = "outline"; originalReset:Refresh()
assert(originalReset.colors.bankFooter.abandoned, "Foreign sizing episode was not recognized")
originalReset.panel:GenerateItemSlotsForSelectedTab(7); originalReset:Settle()
assert(not originalReset.colors.bankFooter.abandoned and originalReset.root.height == 520
    and originalReset.panel.height == 520, "A native reset to the original507 pair failed to release foreign ownership")
originalReset.addon.db.appearance.mode = "off"; originalReset:Refresh()
assert(originalReset.root.height == 507 and originalReset.panel.height == 507,
    "Original-pair recovery lost native restoration dimensions")
local deferredFooter = FooterFixture()
combat = true; deferredFooter.addon.db.appearance.mode = "off"; deferredFooter:Refresh()
assert(deferredFooter.root.height == 520 and deferredFooter.panel.height == 520, "Footer heights changed in combat")
combat = false; deferredFooter.colors:OnEvent("PLAYER_REGEN_ENABLED"); deferredFooter:Settle()
assert(deferredFooter.root.height == 507 and deferredFooter.panel.height == 507, "Deferred footer restoration did not recover")
local deniedFooter = FooterFixture()
deniedFooter.panel.denied = true; deniedFooter.addon.db.appearance.mode = "off"; deniedFooter:Refresh()
assert(deniedFooter.root.height == 520 and deniedFooter.panel.height == 520, "Partial access denial allowed a half-pair restoration")
deniedFooter.panel.denied = false; deniedFooter:Refresh()
assert(deniedFooter.root.height == 507 and deniedFooter.panel.height == 507, "Denied footer restoration was not retained for retry")
for _, failure in ipairs({ "failBefore", "rejectHeight", "failReadback" }) do
    local broken = FooterFixture(function(f) f.panel[failure] = true end)
    assert(next(broken.addon.reports) ~= nil, "Partial native height failure lost its diagnostic")
    broken.panel[failure] = nil; broken:Refresh()
    assert(broken.root.height == 520 and broken.panel.height == 520,
        "A recovered " .. failure .. " did not restore active footer spacing: root=" .. broken.root.height .. " panel=" .. broken.panel.height)
    broken:Clearance()
    broken.addon.db.appearance.mode = "off"; broken:Refresh()
    assert(broken.root.height == 507 and broken.panel.height == 507, "A height-pair failure lost its native restore baselines")
end
local afterHeight = FooterFixture(function(f) f.panel.failAfter = true end)
afterHeight:Refresh(); afterHeight:Clearance()
afterHeight.panel.failBefore = true; afterHeight.addon.db.appearance.mode = "off"; afterHeight:Refresh()
afterHeight.panel.failBefore = nil; afterHeight:Refresh()
assert(afterHeight.root.height == 507 and afterHeight.panel.height == 507, "Partial restore failure could not recover both original heights")
for _, unavailable in ipairs({
    function(f) f.root.GetHeight = false end,
    function(f) f.panel.GetHeight = function() return secret end end,
    function(f) f.root.GetEffectiveScale = function() return secret end end,
    function(f) f.item.GetScaledRect = function() return 0, secret, 37, 37 end end,
    function(f) f.locked.GetScaledRect = function() error("unavailable holder geometry") end end,
    function(f) f.root.regions[#f.root.regions + 1] = setmetatable({}, { __index = f.divider }) end,
    function(f) f.panel.GetNumPoints = false end,
    function(f) f.panel.GetNumPoints = function() return 2 end end,
    function(f) f.panel.GetPoint = function() return "TOPLEFT", f.root, "TOPLEFT", 0, 0 end end,
    function(f) f.panel.GetPoint = function() return "LEFT", secret, "LEFT", 0, 0 end end,
    function(f) f.panel.GetPoint = function() return "LEFT", f.root, "LEFT", 0, secret end end,
    function(f) f.panel.GetPoint = function() error("unavailable panel anchor") end end,
    function(f)
        local original = f.item.GetScaledRect
        f.item.GetScaledRect = function(self)
            local left, bottom, width, height = original(self)
            return left, bottom - 100 * f.panelScale, width, height
        end
    end,
    function(f)
        f.panelScale = 0.005
        f.item.GetScaledRect = function()
            local _, bottom, _, height = f.divider:GetScaledRect()
            return 0, bottom + height - 0.5, 37 * f.panelScale, 37 * f.panelScale
        end
    end,
}) do
    local skipped = FooterFixture(unavailable)
    assert(skipped.root.heightWrites == 0 and skipped.panel.heightWrites == 0
        and skipped.root.height == 507 and skipped.panel.height == 507 and skipped.divider.writes == 0,
        "Unavailable native height/geometry was guessed into bank resizing")
end
local changedPanelAnchor = FooterFixture()
local nativePanelAnchor = changedPanelAnchor.panel.GetPoint
changedPanelAnchor.panel.GetPoint = function() return "TOPLEFT", changedPanelAnchor.root, "TOPLEFT", 0, 0 end
changedPanelAnchor:Refresh()
assert(changedPanelAnchor.root.height == 507 and changedPanelAnchor.panel.height == 507
    and changedPanelAnchor.panel:GetPoint() == "TOPLEFT" and changedPanelAnchor.pointWrites == 0,
    "Foreign panel anchoring caused continued height growth or was overwritten during cleanup")
changedPanelAnchor.panel.GetPoint = nativePanelAnchor; changedPanelAnchor:Refresh(); changedPanelAnchor:Clearance()
local changedDividerAnchor = FooterFixture()
changedDividerAnchor.divider.points[1][5] = 230 -- A native/other owner changes an already cached region.
changedDividerAnchor:Refresh()
assert(changedDividerAnchor.root.height == 507 and changedDividerAnchor.panel.height == 507
    and changedDividerAnchor.divider.points[1][5] == 230 and changedDividerAnchor.divider.writes == 0,
    "Cached divider reanchoring was ignored or overwritten while retaining our footer height")
local followingRect
local staleRect = FooterFixture(function(f)
    followingRect = f.divider.GetScaledRect
    local left, bottom, width, height = followingRect(f.divider)
    f.divider.GetScaledRect = function() return left, bottom, width, height end
end)
assert(staleRect.root.height == 507 and staleRect.panel.height == 507 and not staleRect.colors.driver:IsShown(),
    "Finite geometry that refused to follow native heights left accumulating growth or an active reflow driver")
staleRect.divider.GetScaledRect = followingRect; staleRect:Refresh(); staleRect:Clearance()

local function BagLabel(fixture, boxBottom)
    local label = {}
    function label:IsForbidden() return false end
    function label:GetObjectType() return "FontString" end
    function label:GetParent() return fixture.root end
    function label:IsVisible() return fixture.root:IsVisible() end
    function label:GetScaledRect()
        local _, bottom = fixture.root:GetScaledRect()
        return 0, bottom + boxBottom * fixture.rootScale, 120 * fixture.rootScale, 40 * fixture.rootScale
    end
    function label:GetStringHeight() return 10 end
    function label:GetEffectiveScale() return fixture.rootScale end
    function label:GetJustifyV() return "MIDDLE" end
    fixture.root.BagText = label
    fixture.root.regions[#fixture.root.regions + 1] = label
    return label
end

-- An explicit geometry snapshot must never run painting/discovery ownership or
-- read item/money content, even when the snapshot reports an unavailable gate.
local function CopySettings(value)
    if type(value) ~= "table" then return value end
    local copy = {}; for key, entry in pairs(value) do copy[key] = CopySettings(entry) end; return copy
end
local function SameSettings(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return left == right end
    for key, value in pairs(left) do if not SameSettings(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function DebugSnapshot(fixture)
    local lines, attemptedWrites = {}, 0
    local function forbidden() attemptedWrites = attemptedWrites + 1; error("diagnostic attempted mutation/content access") end
    local settings, ledger, footer = CopySettings(fixture.addon.db), fixture.colors.bankDivider, fixture.colors.bankFooter
    local anchorY, writes = fixture.divider.points[1][5], fixture.divider.writes
    local ledgerFields = ledger and { ledger.currentY, ledger.attemptY, ledger.abandoned, ledger.y, ledger.regions }
    local footerFields = {}
    for key, value in pairs(footer or {}) do footerFields[key] = value end
    local rootHeight, panelHeight = fixture.root.height, fixture.panel.height
    local framesBefore, texturesBefore = allocations.frames, allocations.textures
    local oldPrint, oldCreate, oldHook = fixture.addon.Print, CreateFrame, hooksecurefunc
    local oldItemInfo, oldSetPoint, oldReport = C_Container.GetContainerItemInfo, fixture.divider.SetPoint, fixture.addon.ReportOnce
    local oldRootHeight, oldPanelHeight = fixture.root.SetHeight, fixture.panel.SetHeight
    local methods = {}
    for _, name in ipairs({ "Refresh", "FindBankDivider", "RestoreBankFooter", "UpdateBankFooter", "BankFooterLayoutGenerated", "WatchContainer", "EnsureDriver" }) do
        methods[name], fixture.colors[name] = fixture.colors[name], forbidden
    end
    fixture.addon.Print = function(_, message) lines[#lines + 1] = message end
    CreateFrame, hooksecurefunc, C_Container.GetContainerItemInfo = forbidden, forbidden, forbidden
    fixture.divider.SetPoint, fixture.addon.ReportOnce = forbidden, forbidden
    fixture.root.SetHeight, fixture.panel.SetHeight = forbidden, forbidden
    local succeeded, errorValue = pcall(fixture.colors.PrintBankDebug, fixture.colors)
    CreateFrame, hooksecurefunc, C_Container.GetContainerItemInfo = oldCreate, oldHook, oldItemInfo
    fixture.divider.SetPoint, fixture.addon.ReportOnce, fixture.addon.Print = oldSetPoint, oldReport, oldPrint
    fixture.root.SetHeight, fixture.panel.SetHeight = oldRootHeight, oldPanelHeight
    for name, callback in pairs(methods) do fixture.colors[name] = callback end
    assert(succeeded and attemptedWrites == 0, "Bank debug invoked a mutating path or item data API")
    assert(SameSettings(settings, fixture.addon.db), "Read-only bank debug changed a saved preference")
    assert(fixture.colors.bankDivider == ledger and fixture.divider.points[1][5] == anchorY and fixture.divider.writes == writes,
        "Read-only bank debug acquired/replaced divider ownership or changed its native anchor")
    if ledger then
        assert(ledger.currentY == ledgerFields[1] and ledger.attemptY == ledgerFields[2]
            and ledger.abandoned == ledgerFields[3] and ledger.y == ledgerFields[4] and ledger.regions == ledgerFields[5],
            "Read-only bank debug changed the native-anchor ledger")
    end
    assert(fixture.colors.bankFooter == footer and fixture.root.height == rootHeight and fixture.panel.height == panelHeight,
        "Read-only bank debug changed the height ledger or native window size")
    for key, value in pairs(footerFields) do assert(footer[key] == value, "Bank debug changed a footer ownership field") end
    for key, value in pairs(footer or {}) do assert(footerFields[key] == value, "Bank debug added a footer ownership field") end
    assert(allocations.frames == framesBefore and allocations.textures == texturesBefore,
        "Explicit bank debug allocated native UI resources")
    assert(#lines >= 12 and #lines <= 15, "Bank debug output escaped its bounded fifteen-line geometry summary")
    local text = table.concat(lines, "\n")
    assert(not text:find("unexpected probe failure", 1, true), "Bank debug failed instead of reporting a useful gate")
    assert(not text:find("table:", 1, true) and not text:find("userdata:", 1, true), "Bank debug formatted a frame/object reference")
    for _, line in ipairs(lines) do assert(#line <= 600, "Bank debug emitted an unbounded geometry line") end
    return text
end
local function Contains(text, expected)
    assert(text:find(expected, 1, true), "Missing client evidence field: " .. expected)
end
local debugClear = FooterFixture()
debugClear.addon.version = "test-client"
local evidence = DebugSnapshot(debugClear)
Contains(evidence, "core=test-client"); Contains(evidence, "candidates=1"); Contains(evidence, "ownerEq=true")
Contains(evidence, "lowestBottom=413.867"); Contains(evidence, "gate=already-sized")
for _ = 1, 20 do DebugSnapshot(debugClear) end
local debugBlocked = FooterFixture(function(f) f.locked.bottom = 80.5 end)
Contains(DebugSnapshot(debugBlocked), "gate=native-footer-overlap")
local debugNilAnchor = FooterFixture()
debugNilAnchor.divider.GetPoint = function() return "BOTTOM", nil, nil, 0, 220 end
evidence = DebugSnapshot(debugNilAnchor)
Contains(evidence, "relative=nil ownerEq=false"); Contains(evidence, "relativePoint=nil x=0 y=220")
Contains(evidence, "gate=anchor-contract")
local debugRejected = FooterFixture()
debugRejected.root.regions[1].GetAtlas = function() error("read unavailable") end
evidence = DebugSnapshot(debugRejected)
Contains(evidence, "firstReject=region1:atlas=throw"); Contains(evidence, "divider index=2")
local debugMissingAtlas = FooterFixture()
debugMissingAtlas.divider.atlas = "arrow-line-client-atlas"
evidence = DebugSnapshot(debugMissingAtlas)
Contains(evidence, "regionMap "); Contains(evidence, "arrow-line-client-atlas"); Contains(evidence, "gate=divider-candidates=0")
local debugRegionMap = FooterFixture()
debugRegionMap.divider.atlas = "arrow-line-client-atlas"
for index = 1, 18 do
    local texture = NativeLayer("BACKGROUND", 0)
    texture.parent, texture.atlas = debugRegionMap.root, "native-other-atlas" .. index
    debugRegionMap.root.regions[#debugRegionMap.root.regions + 1] = texture
end
evidence = DebugSnapshot(debugRegionMap)
Contains(evidence, "regionMap+ "); Contains(evidence, "truncated")
local debugCached = FooterFixture()
debugCached.root.GetRegions = function() error("live comparison unavailable") end
evidence = DebugSnapshot(debugCached)
Contains(evidence, "returned=throw source=cached"); Contains(evidence, "gate=already-sized")
local debugWidth = FooterFixture()
local cost = BagLabel(debugWidth, 60)
debugWidth.root.BagText, debugWidth.root.BagCost = nil, cost
cost.GetScaledRect = function() return 0, 50, 0, 12 end
cost.GetStringWidth = function() return 31 end
evidence = DebugSnapshot(debugWidth)
Contains(evidence, "BagCost visible=true rect=(0,50,0,12)/width<=0 textH=10 textW=31")
Contains(evidence, "gate=measurement-unavailable")
local debugDenied, forbiddenPanelReads = FooterFixture(), 0
debugDenied.panel.denied = true
debugDenied.panel.EnumerateValidItems = function() forbiddenPanelReads = forbiddenPanelReads + 1; error("denied panel was read") end
Contains(DebugSnapshot(debugDenied), "gate=panel-access")
assert(forbiddenPanelReads == 0, "Bank debug enumerated an inaccessible native panel")
local debugScale = FooterFixture()
debugScale.divider.scale = 0.5
evidence = DebugSnapshot(debugScale)
Contains(evidence, "ownScale=0.5"); Contains(evidence, "gate=eligible")
local debugSecret = FooterFixture()
debugSecret.divider.GetScaledRect = function() return 0, secret, 37, 37 end
Contains(DebugSnapshot(debugSecret), "scaled=secret")
local debugHuge = FooterFixture()
debugHuge.divider.GetScaledRect = function() return 1e300, 1e300, 1e300, 1e300 end
Contains(DebugSnapshot(debugHuge), "1e+300")
local function CheckBankSizeTrace()
    local oldStack = debugstack
    local stackReads = 0
    debugstack = function()
        stackReads = stackReads + 1
        return '[string "@Interface/AddOns/ForTheHoard/Colors.lua"]:1\n[string "@Interface/AddOns/FixtureSizer/Bank.lua"]:72: in function PRIVATE_TEXT'
    end
    local function Dump(f)
        local lines, oldPrint = {}, f.addon.Print
        f.addon.Print = function(_, line) lines[#lines + 1] = line end
        f.colors:PrintBankTrace()
        f.addon.Print = oldPrint
        assert(#lines <= 37, "Sizing trace exceeded its bounded session output")
        local text = table.concat(lines, "\n")
        assert(not text:find("PRIVATE_TEXT", 1, true) and not text:find("table:", 1, true),
            "Sizing trace exposed raw stack text or a native object")
        return text
    end
    -- Normal play must neither attach the sizing observer nor read geometry
    -- for a diagnostic which the player has never requested.
    local quiet = FooterFixture()
    assert(quiet.colors.bankSizeTrace == nil and stackReads == 0, "Bank tracing was active by default")
    quiet.addon.Print = function(_, text) assert(text:find("banktrace start", 1, true)) end
    quiet.root.GetHeight = function() error("disabled trace read height") end
    quiet.root.GetRect = function() error("disabled trace read rect") end
    quiet.root.IsVisible = function() error("disabled trace read visibility") end
    quiet.colors:EnsureBankSizeTrace()
    quiet.colors:RecordBankSize(quiet.root, "bank", "SetHeight", 507)
    quiet.colors:PrintBankTrace()
    assert(quiet.colors.bankSizeTrace == nil and stackReads == 0, "Disabled diagnostic performed native capture work")
    local function TraceFixture(beforeInitialize)
        local f = FooterFixture(beforeInitialize)
        function f.addon:Print() end
        f.colors:StartBankTrace()
        return f
    end
    local nativeShow
    local pre = TraceFixture(function(f)
        f.root:Hide()
        nativeShow = function()
            f.root:SetSize(560, 507); f.panel:SetSize(480, 507)
            f.root:SetHeight(493.0625); f.panel:SetHeight(493.0625)
        end
        f.root:SetScript("OnShow", nativeShow)
    end)
    local trace = pre.colors.bankSizeTrace
    assert(trace and not trace.active and #trace.pending == 1, "Hidden late attachment did not arm bounded pre-show capture")
    pre.root:SetSize(560, 507); pre.panel:SetSize(480, 507)
    pre.root:SetHeight(493.0625); pre.panel:SetHeight(493.0625)
    local firstPending = trace.pending[1]
    pre.root:Show()
    assert(trace.active and trace.session == 1 and not trace.partial and trace.events[1] == firstPending,
        "Appended OnShow erased sizing performed before/during the original native OnShow")
    assert(pre.root:GetScript("OnShow") == nativeShow, "Trace replaced the native show script")
    local sawHidden, sawTransition = false, false
    for _, entry in ipairs(trace.events) do
        if entry.visible == false then sawHidden = true end
        if entry.root == 493.0625 and entry.caller == "Interface/AddOns/FixtureSizer/Bank.lua:72" then sawTransition = true end
    end
    assert(sawHidden and sawTransition, "The pre-show507-to493 transition lost its size or safe caller hint")
    local retained, session = trace.events, trace.session
    pre.root:Hide(); pre.root:SetHeight(507)
    assert(not trace.active and trace.events == retained and #trace.pending > 0,
        "Closing discarded history or failed to stage next-open sizing separately")
    Contains(Dump(pre), "session=" .. session)
    pre.root:Show()
    assert(trace.session == session + 1 and trace.events ~= retained, "Reopen failed to commit its pre-show session")
    local rootHooks = trace.targets[pre.root]
    local showHooks, sizeHooks = #pre.root.scriptHooks.OnShow, #pre.root.scriptHooks.OnSizeChanged
    local frozen, frozenCount, frozenDropped = trace.events, #trace.events, trace.dropped
    pre.colors:StopBankTrace()
    local visible = pre.root.IsVisible
    pre.root.IsVisible = function() error("stopped diagnostic read visibility") end
    local stoppedStack = stackReads
    for _ = 1, 50 do
        rootHooks.callbacks.SetHeight(pre.root, 507)
        rootHooks.callbacks.OnHide(pre.root)
        pre.colors:EnsureBankSizeTrace()
    end
    assert(trace.events == frozen and #trace.events == frozenCount and trace.dropped == frozenDropped
        and stackReads == stoppedStack, "Stopped capture continued reading or changing its retained history")
    pre.root.IsVisible = visible
    Contains(Dump(pre), "enabled=false")
    for _ = 1, 3 do pre.colors:StartBankTrace(); pre.colors:StopBankTrace() end
    pre.colors:StartBankTrace()
    assert(trace.targets[pre.root] == rootHooks and #pre.root.scriptHooks.OnShow == showHooks
        and #pre.root.scriptHooks.OnSizeChanged == sizeHooks and trace.session == 1
        and #trace.events == 1 and trace.dropped == 0,
        "Rearming failed to reset capture or duplicated retained native hooks")

    local observed = TraceFixture()
    local observer = observed.colors.bankSizeTrace
    local callbacks = observer.targets[observed.root].callbacks
    assert(observer.partial, "Attaching while already visible must disclose partial history")
    local settings = CopySettings(observed.addon.db)
    local beforeFrames, beforeTextures = allocations.frames, allocations.textures
    local heights, nested = 0, false
    local originalHeight, originalRect, originalScaled = observed.root.GetHeight, observed.root.GetRect, observed.root.GetScaledRect
    observed.root.GetHeight = function(self, explicit)
        if observer.busy then
            assert(explicit == true, "A sizing callback requested calculated geometry")
            heights = heights + 1
            if not nested then nested = true; callbacks.OnSizeChanged(self, 560, 520) end
        end
        return originalHeight(self, explicit)
    end
    observed.root.GetRect = function(self, ...) assert(not observer.busy, "A sizing callback materialized GetRect"); return originalRect(self, ...) end
    observed.root.GetScaledRect = function(self, ...) assert(not observer.busy, "A sizing callback materialized scaled geometry"); return originalScaled(self, ...) end
    local oldRequest = observed.colors.RequestRefresh
    observed.colors.RequestRefresh = function() error("observer requested redraw") end
    local count = #observer.events
    callbacks.SetWidth(observed.root, 560)
    assert(#observer.events == count + 1 and heights == 1, "Reentrant observer callbacks escaped the capture guard")
    observed.colors.bankFooter.writing = true
    callbacks.OnSizeChanged(observed.root, secret, secret)
    observed.colors.bankFooter.writing = nil
    local last = observer.events[#observer.events]
    assert(last.own and last.first == "secret" and last.second == "secret", "Secret event arguments or own-writing context were misreported")
    local heightAtCap, stackAtCap
    for _ = 1, 100 do
        callbacks.SetHeight(observed.root, 520)
        if #observer.events == 32 and not heightAtCap then heightAtCap, stackAtCap = heights, stackReads end
    end
    assert(#observer.events == 32 and observer.dropped > 0 and heights == heightAtCap and stackReads == stackAtCap,
        "Full trace kept reading heights/stacks or grew its event storage")
    observed.colors.RequestRefresh = oldRequest
    assert(SameSettings(settings, observed.addon.db) and allocations.frames == beforeFrames and allocations.textures == beforeTextures,
        "Observer changed preferences or allocated native resources")
    Contains(Dump(observed), "stored=32")

    local fullPre = TraceFixture(function(f) f.root:Hide() end)
    local pending = fullPre.colors.bankSizeTrace
    for _ = 1, 100 do pending.targets[fullPre.root].callbacks.SetHeight(fullPre.root, 507) end
    assert(#pending.pending == 16 and pending.pendingDropped > 0, "Pre-show capture did not stop at its reserved budget")
    fullPre.root:Show()
    assert(#pending.events < 32 and pending.preDropped > 0, "Pre-show capture starved all visible-event capacity")
    Contains(Dump(fullPre), "preDropped=")

    local demand = TraceFixture()
    local demandTrace, fired = demand.colors.bankSizeTrace, false
    local oldRect = demand.root.GetRect
    demand.root.GetRect = function(self)
        if not fired then fired = true; self:Fire("OnSizeChanged", self.width, 493.0625) end
        return oldRect(self)
    end
    count = #demandTrace.events
    local text = Dump(demand)
    assert(#demandTrace.events == count + 1 and demandTrace.events[#demandTrace.events].demand == true,
        "Getter-induced sizing lacked its demand-observation marker")
    Contains(text, "stored=" .. #demandTrace.events); Contains(text, "dump=true")
    debugstack = function() return secret end
    demandTrace.targets[demand.root].callbacks.SetHeight(demand.root, 507)
    assert(demandTrace.events[#demandTrace.events].caller == "secret", "Restricted stacks were formatted")
    debugstack = function() error("restricted trace") end
    demandTrace.targets[demand.root].callbacks.SetHeight(demand.root, 507)
    assert(demandTrace.events[#demandTrace.events].caller == "throw", "Throwing stacks interrupted native sizing")
    debugstack = function() return '[string "...ace/AddOns/FixtureSizer/Short.lua"]:99: in function PRIVATE_TEXT' end
    demandTrace.targets[demand.root].callbacks.SetHeight(demand.root, 507)
    assert(demandTrace.events[#demandTrace.events].caller == "hint:Short.lua:99",
        "A truncated recognized source frame lost its bounded basename hint")

    local savedHook, target, blocked = hooksecurefunc, nil, true
    hooksecurefunc = function(object, name, callback)
        if object == target and name == "SetWidth" and blocked then error("injected observer hook failure") end
        return savedHook(object, name, callback)
    end
    local retry = TraceFixture(function(f) target = f.root end)
    local state = retry.colors.bankSizeTrace.targets[retry.root]
    assert(state.status.SetWidth == "throw", "Failed method observation falsely reported coverage")
    blocked = false; retry.colors:EnsureBankSizeTrace(); hooksecurefunc = savedHook
    count = #retry.colors.bankSizeTrace.events
    for _ = 1, 20 do retry.colors:EnsureBankSizeTrace() end
    retry.root:SetWidth(560)
    assert(state.methods.SetWidth and #retry.colors.bankSizeTrace.events == count + 1,
        "Method retry failed or repeated discovery duplicated the observer")
    for _, unknownReturn in ipairs({ "nil", "other" }) do
        local uncertainCalls = 0
        local uncertain = TraceFixture(function(f)
            local hook = f.root.HookScript
            f.root.HookScript = function(self, name, callback)
                local result = hook(self, name, callback)
                if name == "OnSizeChanged" then
                    uncertainCalls = uncertainCalls + 1
                    if unknownReturn == "other" then return "uncertain" end
                    return nil
                end
                return result
            end
        end)
        for _ = 1, 20 do uncertain.colors:EnsureBankSizeTrace() end
        assert(uncertainCalls == 1, "Off-contract HookScript return caused duplicate observer callbacks")
        Contains(Dump(uncertain), "OnSizeChanged:unknown")
    end
    debugstack = oldStack
end
CheckBankSizeTrace()
BankFrame, ContainerFrameCombinedBags = oldBank, oldCombined
print("bank colors: native identities, pool/page reuse, visibility, allocation bounds and transaction isolation passed")
