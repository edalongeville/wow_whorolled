local _, ns = ...
local RC, L = ns.RC, ns.L

local STATE_LABEL = {
  need = L.NEED, greed = L.GREED, transmog = L.TRANSMOG, pass = L.PASS, pending = L.PENDING,
}
local STATE_COLOR = {
  need = "|cff1eff00", greed = "|cffffd100", transmog = "|cffff80ff", pass = "|cff9d9d9d", pending = "|cff666666",
}
local STATE_SEQ = { "need", "transmog", "greed", "pass", "pending" }
local WIN_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"
-- The game's own roll button icons (no icon for transmog: its colored label is used)
local STATE_ICON = {
  need = "|TInterface\\Buttons\\UI-GroupLoot-Dice-Up:14:14|t",
  greed = "|TInterface\\Buttons\\UI-GroupLoot-Coin-Up:14:14|t",
  pass = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14|t",
}
ns.STATE_ICON = STATE_ICON

local function Colored(name, class)
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  local c = class and colors and colors[class]
  local short = ns.ShortName(name)
  if c then
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), short)
  end
  return short
end

local function SortedRolls(d)
  local t = {}
  for i, r in ipairs(d.rolls) do t[i] = r end
  table.sort(t, function(a, b)
    local wa, wb = a.winner and true or false, b.winner and true or false
    if wa ~= wb then return wa end
    local sa = ns.STATE_ORDER[a.state or "pending"] or 9
    local sb = ns.STATE_ORDER[b.state or "pending"] or 9
    if sa ~= sb then return sa < sb end
    local ra, rb = a.roll or -1, b.roll or -1
    if ra ~= rb then return ra > rb end
    return (a.name or "") < (b.name or "")
  end)
  return t
end

local function ApplyBackdrop(f)
  if not f.SetBackdrop then return end
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropColor(0, 0, 0, 0.85)
  f:SetBackdropBorderColor(0.5, 0.5, 0.5)
end

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

---------------------------------------------------------------------------
-- A bar under each roll frame (the game's frame itself is left as it is):
--  1. the roll appears:      "5 joueurs choisissent"
--  2. players choose:        <need> 2  <greed> 1  <pass> 1
--  3. the roll is decided:   "Garzak gagne 87 <need>" (or "tout le monde a passé")
--  4. it goes away a few seconds later (option "resultTime").
-- The bar is not a child of the roll frame: when the game hides the roll frame (you chose, or
-- the roll ended), the bar stays where it was until the result has been shown.
-- A click on the bar shows, to its right, who chose what.
---------------------------------------------------------------------------
local ROW_H = 14
local PAD = 6
local LIST_W = 176
local MAX_ROWS = 25     -- detail list: past that, the rest is summed up as "+N"
local BAR_H = 20
local SAFETY_HIDE = 120 -- a bar whose roll never gets a result goes away after this
local bars = {}         -- [rollFrame] = bar, reused for each roll the frame shows
local hooked = {}       -- [rollFrame] = true

local function NewLine(p)
  local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetJustifyH("LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

local function ChoiceIcon(s)
  return STATE_ICON[s] or (STATE_COLOR[s] .. STATE_LABEL[s] .. "|r")
end

local function ChoiceText(r)
  local txt = ChoiceIcon(r.state or "pending")
  if r.roll then txt = txt .. " |cffffffff" .. r.roll .. "|r" end
  return txt
end

local function GroupSize()
  local n = GetNumGroupMembers()
  return (type(n) == "number" and n > 0) and n or 1
end

-- The detail list: everyone, winner first, then by choice and roll.
local function GetRow(p, i)
  local row = p.rows[i]
  if not row then
    row = {}
    row.name = NewLine(p)
    row.name:SetWidth(LIST_W - 2 * PAD - 52)
    row.choice = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.choice:SetJustifyH("RIGHT")
    p.rows[i] = row
  end
  return row
end

local function FillList(p, d)
  local entries = {}
  local pending = 0
  for _, r in ipairs(d and SortedRolls(d) or {}) do
    if (r.state or "pending") == "pending" then
      pending = pending + 1
    else
      entries[#entries + 1] = { (r.winner and (WIN_ICON .. " ") or "") .. Colored(r.name, r.class), ChoiceText(r), 1 }
    end
  end
  if pending > 0 then
    entries[#entries + 1] = { "|cff888888" .. L.PENDING .. " : " .. pending .. "|r", "", pending }
  elseif #entries == 0 then
    entries[1] = { "|cff888888" .. L.WAITING_CHOICES .. "|r", "", 0 }
  end
  if #entries > MAX_ROWS then
    local hidden = 0
    for k = #entries, MAX_ROWS, -1 do
      hidden = hidden + entries[k][3]
      entries[k] = nil
    end
    entries[MAX_ROWS] = { "|cff888888+" .. hidden .. "|r", "", hidden }
  end
  for k, e in ipairs(entries) do
    local row = GetRow(p, k)
    local y = -PAD - 1 - (k - 1) * ROW_H
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + 2, y)
    row.choice:ClearAllPoints()
    row.choice:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD - 2, y)
    row.name:SetText(e[1])
    row.choice:SetText(e[2])
    row.name:Show()
    row.choice:Show()
  end
  for k = #entries + 1, #p.rows do
    p.rows[k].name:Hide()
    p.rows[k].choice:Hide()
  end
  p:SetHeight(2 * PAD + 2 + #entries * ROW_H)
  p.shownEntries = #entries -- for the tests
end

-- What the bar says, by phase.
local function BarText(d)
  local counts, winner, chosen = {}, nil, false
  for _, r in ipairs(d and d.rolls or {}) do
    local s = r.state or "pending"
    counts[s] = (counts[s] or 0) + 1
    if s ~= "pending" then chosen = true end
    if r.winner then winner = r end
  end
  if d and d.winner then
    local name, class, roll, state = d.winner, nil, nil, nil
    if winner then class, roll, state = winner.class, winner.roll, winner.state end
    local text = roll and L.WINS:format(Colored(name, class), roll) or L.WINS_NO_ROLL:format(Colored(name, class))
    return WIN_ICON .. " " .. text .. (state and STATE_ICON[state] and (" " .. STATE_ICON[state]) or "")
  end
  if d and d.allPassed then
    return "|cff9d9d9d" .. L.ALL_PASSED_BAR .. "|r"
  end
  if chosen then
    local parts = {}
    for _, s in ipairs({ "need", "transmog", "greed", "pass" }) do
      if s ~= "transmog" or counts[s] then
        parts[#parts + 1] = ChoiceIcon(s) .. " " .. (counts[s] or 0)
      end
    end
    return table.concat(parts, "    ")
  end
  local n = counts.pending or GroupSize()
  return n == 1 and L.CHOOSING_ONE or L.CHOOSING:format(n)
end
ns.BarText = BarText -- for the tests

local function CreateBar()
  local b = CreateFrame("Button", nil, UIParent, BACKDROP_TEMPLATE)
  b:SetHeight(BAR_H)
  ApplyBackdrop(b)
  b:RegisterForClicks("LeftButtonUp")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", b, "LEFT", PAD, 0)
  b.text:SetPoint("RIGHT", b, "RIGHT", -PAD, 0)
  b.text:SetJustifyH("CENTER")
  if b.text.SetWordWrap then b.text:SetWordWrap(false) end

  local list = CreateFrame("Frame", nil, b, BACKDROP_TEMPLATE)
  list:SetWidth(LIST_W)
  list:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 2, 0)
  list:SetFrameStrata("DIALOG")
  ApplyBackdrop(list)
  list.rows = {}
  list:Hide()
  b.list = list

  b:SetScript("OnClick", function(self)
    if self.list:IsShown() then
      self.list:Hide()
    else
      FillList(self.list, self.drop)
      self.list:Show()
    end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.BAR_TOOLTIP)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

local function HideBar(bar)
  bar:Hide()
  bar.list:Hide()
end

-- Hide the bar after delay seconds, unless it has moved on to another roll by then.
local function ScheduleHide(bar, delay)
  bar.hideToken = (bar.hideToken or 0) + 1
  local token, d = bar.hideToken, bar.drop
  C_Timer.After(delay, function()
    if bar.hideToken == token and bar.drop == d then HideBar(bar) end
  end)
end

local function Finished(d)
  return d ~= nil and (d.winner ~= nil or d.allPassed == true)
end

local function UpdateBar(bar)
  local d = bar.drop
  bar.text:SetText(BarText(d))
  bar:Show()
  if bar.list:IsShown() then FillList(bar.list, d) end
  if Finished(d) and not bar.finished then
    bar.finished = true
    ScheduleHide(bar, WhoRolledDB.settings.resultTime)
  end
end

local function Attach(bar, f)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
  bar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
  bar.attached = f
end

-- The roll frame went away: the bar stays where it is, on its own.
local function Detach(bar)
  local left, top, width = bar:GetLeft(), bar:GetTop(), bar:GetWidth()
  if left and top then
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    if width then bar:SetWidth(width) end
  end
  bar.attached = nil
end

local function OnRollFrameHidden(f)
  local bar = bars[f]
  if not bar or not bar:IsShown() then return end
  Detach(bar)
  if not Finished(bar.drop) then ScheduleHide(bar, SAFETY_HIDE) end
end

-- f shows the roll d (nil while no data has arrived for it).
function ns.UpdateRollFrame(f, d)
  if not hooked[f] then
    f:HookScript("OnHide", function() OnRollFrameHidden(f) end)
    hooked[f] = true
  end
  local bar = bars[f]
  if not WhoRolledDB.settings.attach then
    if bar then HideBar(bar) end
    return
  end
  if not bar then
    bar = CreateBar()
    bars[f] = bar
  end
  if bar.drop ~= d or not bar:IsShown() then
    -- a new roll in this frame: start over
    bar.drop, bar.finished = d, nil
    bar.hideToken = (bar.hideToken or 0) + 1
    bar.list:Hide()
  end
  if f:IsShown() then Attach(bar, f) end
  UpdateBar(bar)
end
ns.bars = bars -- for the tests

function ns.HideAllBars()
  for _, bar in pairs(bars) do HideBar(bar) end
end

-- A roll changed: update the bars showing it, even when their roll frame is gone.
function ns.UpdateBarsFor(d)
  for _, bar in pairs(bars) do
    if bar.drop == d and bar:IsShown() then UpdateBar(bar) end
  end
end

-- The game's open roll windows. Forever keeps them in GroupLootContainer.rollFrames; older
-- clients have GroupLootFrame1..4. Both are checked.
local function RollWindows()
  local list, seen = {}, {}
  local function add(f)
    if type(f) == "table" and f.HookScript and not seen[f] then
      seen[f] = true
      list[#list + 1] = f
    end
  end
  for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do add(_G["GroupLootFrame" .. i]) end
  local holder = _G.GroupLootContainer
  if holder and type(holder.rollFrames) == "table" then
    for _, f in pairs(holder.rollFrames) do add(f) end
  end
  return list
end

local containerHooked = false
local showHooked = {}
function ns.RefreshRollFrames()
  ns.ApplyRollPosition()
  if not containerHooked and type(_G.GroupLootContainer_Update) == "function" then
    hooksecurefunc("GroupLootContainer_Update", ns.RefreshRollFramesSoon)
    containerHooked = true
  end
  for _, f in ipairs(RollWindows()) do
    if not showHooked[f] then
      f:HookScript("OnShow", ns.RefreshRollFramesSoon)
      showHooked[f] = true
    end
    local ok, id = pcall(function() return f.rollID end)
    if ok and id and f:IsShown() then ns.UpdateRollFrame(f, RC:DropForRoll(id)) end
  end
end

function ns.RefreshRollFramesSoon()
  C_Timer.After(0, ns.RefreshRollFrames)
end

---------------------------------------------------------------------------
-- Moving the roll frames: a draggable anchor (/whorolled move). The game's
-- loot roll container (or the first roll frame on clients without one) is
-- pinned to it, and the panels follow because they hang off the roll frames.
---------------------------------------------------------------------------
local anchor
local pinning = false

local function RollRoot()
  return _G.GroupLootContainer or _G.GroupLootFrame1
end

local function CreateAnchor()
  anchor = CreateFrame("Frame", "WhoRolledRollAnchor", UIParent, BACKDROP_TEMPLATE)
  anchor:SetSize(280, 44)
  anchor:SetFrameStrata("DIALOG")
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  anchor:EnableMouse(true)
  anchor:RegisterForDrag("LeftButton")
  ApplyBackdrop(anchor)
  if anchor.SetBackdropColor then anchor:SetBackdropColor(0.1, 0.4, 0.1, 0.8) end
  anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  anchor.text:SetPoint("CENTER")
  anchor.text:SetText(L.MOVE_LABEL)
  -- close button = lock, so nothing has to be typed
  local close = CreateFrame("Button", nil, anchor, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() ns.ToggleMove() end)
  anchor:SetScript("OnDragStart", anchor.StartMoving)
  anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    WhoRolledDB.settings.rollPos = { point, relPoint, x, y }
    ns.ApplyRollPosition()
  end)
  anchor:Hide()
end

local function PlaceAnchor()
  if not anchor then CreateAnchor() end
  anchor:ClearAllPoints()
  local pos = WhoRolledDB.settings.rollPos
  if pos then
    anchor:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    anchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
  end
end

local function Pin(frame)
  if pinning then return end
  pinning = true
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
  pinning = false
end

local hookedRoot
function ns.ApplyRollPosition()
  if not WhoRolledDB.settings.rollPos then return end
  PlaceAnchor()
  local root = RollRoot()
  if not root then return end
  if hookedRoot ~= root and hooksecurefunc then
    -- the game re-positions the container; put it back on our anchor each time
    hooksecurefunc(root, "SetPoint", function(frame)
      if WhoRolledDB.settings.rollPos and not pinning then Pin(frame) end
    end)
    hookedRoot = root
  end
  Pin(root)
end

function ns.IsMoving()
  return anchor ~= nil and anchor:IsShown()
end

function ns.ToggleMove()
  PlaceAnchor()
  if anchor:IsShown() then
    anchor:Hide()
    ns.Print(L.MOVE_LOCKED)
  else
    anchor:Show()
    ns.Print(L.MOVE_UNLOCKED)
  end
end

function ns.ResetRollPosition()
  WhoRolledDB.settings.rollPos = nil
  if anchor then anchor:Hide() end
  ns.Print(L.MOVE_RESET)
end

---------------------------------------------------------------------------
-- History window
---------------------------------------------------------------------------
local win, smf

local function DropLines(d)
  local head = "|cff888888" .. date("%H:%M", d.time) .. "|r " .. (d.link or "?")
  if d.winner then
    local class
    for _, r in ipairs(d.rolls) do if r.name == d.winner then class = r.class end end
    head = head .. "  " .. WIN_ICON .. " " .. Colored(d.winner, class)
  elseif d.allPassed then
    head = head .. "  |cff9d9d9d" .. L.ALL_PASSED .. "|r"
  end
  if d.encounterName then head = head .. "  |cff888888(" .. d.encounterName .. ")|r" end

  local groups = {}
  for _, r in ipairs(SortedRolls(d)) do
    local s = r.state or "pending"
    groups[s] = groups[s] or {}
    local g = groups[s]
    g[#g + 1] = Colored(r.name, r.class) .. (r.roll and (" " .. r.roll) or "")
  end
  local parts = {}
  for _, s in ipairs(STATE_SEQ) do
    if groups[s] then
      parts[#parts + 1] = STATE_COLOR[s] .. STATE_LABEL[s] .. "|r : " .. table.concat(groups[s], ", ")
    end
  end
  return head, #parts > 0 and ("     " .. table.concat(parts, "    ")) or nil
end

function ns.RenderHistory()
  if not (win and win:IsShown()) then return end
  smf:Clear()
  local h = WhoRolledDB.history
  if #h == 0 then
    smf:AddMessage("|cff888888" .. L.HISTORY_EMPTY .. "|r")
    return
  end
  for i = math.max(1, #h - 150), #h do
    local head, detail = DropLines(h[i])
    smf:AddMessage(head)
    if detail then smf:AddMessage(detail) end
  end
  smf:ScrollToBottom()
end

local function CreateHistory()
  win = CreateFrame("Frame", "WhoRolledHistoryFrame", UIParent, "BasicFrameTemplateWithInset")
  win:SetSize(520, 340)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:SetMovable(true)
  win:SetResizable(true)
  win:EnableMouse(true)
  win:SetClampedToScreen(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetScript("OnShow", ns.RenderHistory)
  tinsert(UISpecialFrames, "WhoRolledHistoryFrame") -- close with Escape

  local title = win.TitleText or win.title
  if not title then
    title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
  end
  title:SetText(L.HISTORY_TITLE)

  smf = CreateFrame("ScrollingMessageFrame", nil, win)
  smf:SetPoint("TOPLEFT", 12, -32)
  smf:SetPoint("BOTTOMRIGHT", -12, 12)
  smf:SetFontObject(GameFontHighlightSmall)
  smf:SetJustifyH("LEFT")
  smf:SetFading(false)
  smf:SetMaxLines(1000)
  smf:SetHyperlinksEnabled(true)
  smf:EnableMouseWheel(true)
  smf:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  smf:SetScript("OnHyperlinkEnter", function(self, link)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
  end)
  smf:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
    SetItemRef(link, text, button, self) -- shift-click links the item in chat
  end)

  -- Resize grip
  local grip = CreateFrame("Button", nil, win)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing(); ns.RenderHistory() end)

  win:Hide()
end

function ns.ToggleHistory()
  if not win then CreateHistory() end
  win:SetShown(not win:IsShown())
end

---------------------------------------------------------------------------
-- Change notifications from Core
---------------------------------------------------------------------------
local testFrames = {} -- pool of fake roll frames, each with .drop

function ns.OnDropChanged(d)
  ns.RefreshRollFrames()
  ns.UpdateBarsFor(d)
  if d.test then
    for _, f in ipairs(testFrames) do
      if f.drop == d and f:IsShown() then ns.UpdateRollFrame(f, d) end
    end
  end
  ns.RenderHistory()
end

---------------------------------------------------------------------------
-- Test mode: fake roll frames that fill up over a few seconds
---------------------------------------------------------------------------
ns.MAX_TEST_ROLLS = 10
-- { item ID, name used when the client has not cached the item yet, quality colour }
local TEST_ITEMS = {
  { 6948, L.ITEM_HEARTHSTONE, "ffffffff" },
  { 4306, L.ITEM_SILK, "ffffffff" },
  { 2589, L.ITEM_LINEN, "ffffffff" },
  { 765, L.ITEM_SILVERLEAF, "ffffffff" },
  { 2770, L.ITEM_COPPER_ORE, "ffffffff" },
  { 118, L.ITEM_MINOR_HEALING, "ffffffff" },
  { 2447, L.ITEM_PEACEBLOOM, "ffffffff" },
  { 4338, L.ITEM_MAGEWEAVE, "ffffffff" },
  { 159, L.ITEM_SPRING_WATER, "ffffffff" },
  { 117, L.ITEM_TOUGH_JERKY, "ffffffff" },
}
local TEST_DURATION = 15 -- seconds to choose, like a real roll's timer
local TEST_LINGER = 5    -- seconds a finished test roll stays on screen

-- The game's roll window on the Forever client: its size, how far apart it stacks them
-- (GroupLootContainer.reservedSize), and its art (the loot toast texture, the roll button atlases;
-- older files when an atlas is missing).
local WIN_W, WIN_H = 277, 67
local SLOT_H = 100
local TOAST = "Interface\\LootFrame\\LootToast"
local GOLD_EDGE = "loottoast-itemborder-gold"
local ROLL_BUTTONS = { -- choice, atlas, fallback file, label, x, y
  { "need", "lootroll-toast-icon-need", "Interface\\Buttons\\UI-GroupLoot-Dice", L.NEED, 202, -7 },
  { "greed", "lootroll-toast-icon-greed", "Interface\\Buttons\\UI-GroupLoot-Coin", L.GREED, 202, -34 },
  { "pass", "lootroll-toast-icon-pass", "Interface\\Buttons\\UI-GroupLoot-Pass", L.PASS, 240, -5 },
}

local function HasAtlas(name)
  if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
  local ok, info = pcall(C_Texture.GetAtlasInfo, name)
  return ok and info ~= nil
end

local function SetArt(tex, atlas, file)
  if atlas and HasAtlas(atlas) then tex:SetAtlas(atlas) else tex:SetTexture(file) end
end

-- Item link for a test roll. The global GetItemInfo errors on the Forever client, so C_Item is
-- tried first and every call is protected; a built link is the fallback.
local function TestItemLink(item)
  local getters = { C_Item and C_Item.GetItemInfo, GetItemInfo }
  for i = 1, 2 do
    local get = getters[i]
    if get then
      local ok, _, link = pcall(get, item[1])
      if ok and link then return link end
    end
  end
  return ("|c%s|Hitem:%d::::::::1:::::::|h[%s]|h|r"):format(item[3], item[1], item[2])
end

local function TestItemIcon(itemID)
  local getters = { C_Item and C_Item.GetItemIconByID, GetItemIcon }
  for i = 1, 2 do
    local get = getters[i]
    if get then
      local ok, icon = pcall(get, itemID)
      if ok and icon then return icon end
    end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local TestChoose -- defined below

local function ItemQuality(itemID)
  local get = C_Item and C_Item.GetItemQualityByID
  if get then
    local ok, q = pcall(get, itemID)
    if ok and type(q) == "number" then return q end
  end
  return 1
end

-- A test roll window, drawn like the game's own with the game's art (the game's real windows
-- are never touched). Its Need / Greed / Pass buttons play the test.
local function GetTestFrame(i)
  local f = testFrames[i]
  if f then return f end
  f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(WIN_W, WIN_H)
  f:SetFrameStrata("MEDIUM")
  f:SetFrameLevel(20)

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(TOAST)
  bg:SetTexCoord(0.28222656, 0.55273438, 0.30859375, 0.57031250)
  bg:SetAllPoints(f)
  f.border = f:CreateTexture(nil, "BORDER")
  f.border:SetTexture(TOAST)
  f.border:SetTexCoord(0.00097656, 0.28027344, 0.43750000, 0.73437500)
  f.border:SetSize(WIN_W + 9, WIN_H + 9)
  f.border:SetPoint("CENTER", f, "CENTER", 0, 0)

  -- the item: tooltip on hover, shift-click links it
  local icon = CreateFrame("Button", nil, f)
  icon:SetSize(34, 34)
  icon:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -11)
  f.iconTex = icon:CreateTexture(nil, "ARTWORK")
  f.iconTex:SetAllPoints(icon)
  f.iconBorder = icon:CreateTexture(nil, "OVERLAY")
  f.iconBorder:SetSize(42, 42)
  f.iconBorder:SetPoint("CENTER", icon, "CENTER", 0, -2)
  icon:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, f.link)
    GameTooltip:Show()
  end)
  icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
  icon:SetScript("OnClick", function(self, button)
    if f.link then SetItemRef(f.link, f.link, button, self) end
  end)
  f.icon = icon

  f.name = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  f.name:SetSize(125, 30)
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 60, -15)
  f.name:SetJustifyH("LEFT")
  if f.name.SetJustifyV then f.name:SetJustifyV("MIDDLE") end

  f.buttons = {}
  for k, b in ipairs(ROLL_BUTTONS) do
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(32, 32)
    btn:SetPoint("TOPLEFT", f, "TOPLEFT", b[5], b[6])
    btn:SetFrameLevel(f:GetFrameLevel() + 5)
    btn.art = btn:CreateTexture(nil, "ARTWORK")
    btn.art:SetAllPoints(btn)
    SetArt(btn.art, b[2] .. "-up", b[3] .. "-Up")
    local glow = btn:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(btn)
    SetArt(glow, b[2] .. "-up", b[3] .. "-Up")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.5)
    btn.choice = b[1]
    btn:SetScript("OnClick", function() TestChoose(f, b[1]) end)
    btn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(b[4])
      GameTooltip:AddLine(L.TEST_TOOLTIP, 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.buttons[k] = btn
  end

  -- the timer, tucked under the window's art like the game's
  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetSize(190, 8)
  bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 3, 2)
  bar:SetFrameLevel(19)
  bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
  bar:SetStatusBarColor(1, 1, 0)
  bar:SetMinMaxValues(0, 1)
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints(bar)
  barBg:SetColorTexture(0, 0, 0)
  f.bar = bar

  -- so a test roll is never mistaken for a real one
  local tag = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  tag:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 4)
  tag:SetText(L.TEST_TAG)

  f:SetScript("OnUpdate", function(self)
    if not self.deadline then return end
    local left = self.deadline - GetTime()
    self.bar:SetValue(math.max(0, left / TEST_DURATION))
    if left <= 0 then ns.TestTimeout(self) end
  end)

  testFrames[i] = f
  return f
end

-- Shows the item on a test window: icon, and the name in its quality colour.
local function ShowTestItem(f, item, link)
  f.link = link
  f.iconTex:SetTexture(TestItemIcon(item[1]))
  local q = ItemQuality(item[1])
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  local name = link:match("|h%[(.-)%]|h") or item[2]
  f.name:SetText(name)
  if c then f.name:SetTextColor(c.r, c.g, c.b) end
  -- the game's window keeps its gold frame whatever the item: the art is left untinted, and
  -- the icon gets the gold edge (the quality one, or none, when the client lacks it)
  local atlas = HasAtlas(GOLD_EDGE) and GOLD_EDGE or (LOOT_BORDER_BY_QUALITY and LOOT_BORDER_BY_QUALITY[q])
  if atlas and HasAtlas(atlas) then
    f.iconBorder:SetAtlas(atlas)
    f.iconBorder:Show()
  else
    f.iconBorder:Hide()
  end
end
ns.testFrames = testFrames -- for the tests

local function SetButtonsEnabled(f, enabled)
  for _, btn in ipairs(f.buttons) do
    if enabled then btn:Enable() else btn:Disable() end
    if btn.art.SetDesaturated then btn.art:SetDesaturated(not enabled) end
    btn.art:SetAlpha(enabled and 1 or 0.5)
  end
end

-- the best need wins, else the best greed, else everyone passed
local function Resolve(f)
  local d = f.drop
  if f.resolved then return end
  f.resolved = true
  f.deadline = nil
  SetButtonsEnabled(f, false)
  local best
  for _, want in ipairs({ "need", "greed" }) do
    for _, r in ipairs(d.rolls) do
      if r.state == want then
        r.roll = math.random(1, 100)
        if not best or r.roll > best.roll then best = r end
      end
    end
    if best then break end
  end
  if best then
    best.winner = true
    d.winner = best.name
  else
    d.allPassed = true
  end
  ns.OnDropChanged(d)
  C_Timer.After(TEST_LINGER, function()
    if f.drop == d then f:Hide() end
  end)
end

local function ResolveIfDone(f)
  for _, r in ipairs(f.drop.rolls) do
    if (r.state or "pending") == "pending" then return end
  end
  Resolve(f)
end

-- Your choice on a test roll: the buttons work like the real ones.
TestChoose = function(f, choice)
  if f.resolved or f.mine then return end
  f.mine = choice
  SetButtonsEnabled(f, false)
  RC:SetRoll(f.drop, UnitName("player"), nil, choice)
  ns.OnDropChanged(f.drop)
  ResolveIfDone(f)
end
ns.TestChoose = TestChoose

-- Time is up: like a real roll, no choice means pass.
function ns.TestTimeout(f)
  if f.resolved then return end
  if not f.mine then
    f.mine = "pass"
    RC:SetRoll(f.drop, UnitName("player"), nil, "pass")
  end
  Resolve(f)
end

-- What the other players choose on fake roll n: varied from one roll to the next, so a need win,
-- a greed win and everyone passing all show up.
local CAST = { { "Arwyn", "PALADIN" }, { "Brogar", "WARRIOR" }, { "Célia", "PRIEST" }, { "Dorn", "HUNTER" } }
local CHOICES = {
  { "pass", "pass", "need", "greed" },
  { "greed", "pass", "greed", "pass" },
  { "pass", "pass", "pass", "pass" },
  { "greed", "need", "pass", "need" },
}

local testRun = 0

function ns.RunTest(count)
  count = math.max(1, math.min(ns.MAX_TEST_ROLLS, math.floor(tonumber(count) or 1)))
  testRun = testRun + 1
  local run = testRun

  for _, f in ipairs(testFrames) do f:Hide() end

  local me, myClass = UnitName("player"), select(2, UnitClass("player"))

  -- stack the fake rolls upwards from where real rolls appear
  local base, baseY
  if WhoRolledDB.settings.rollPos then
    PlaceAnchor()
    base, baseY = anchor, 0
  else
    base, baseY = UIParent, 200
  end

  for i = 1, count do
    local f = GetTestFrame(i)
    local item = TEST_ITEMS[(i - 1) % #TEST_ITEMS + 1]
    local link = TestItemLink(item)
    -- stacked like the game's: one slot of SLOT_H each, room for the bar in between
    f:ClearAllPoints()
    f:SetPoint("CENTER", base, "BOTTOM", 0, baseY + SLOT_H * (i - 0.5))
    ShowTestItem(f, item, link)

    local d = RC:NewDrop("test:" .. run .. ":" .. i .. ":" .. time(), link)
    d.test = true
    d.encounterName = "Test"
    f.drop, f.mine, f.resolved = d, nil, nil
    RC:SetRoll(d, me, myClass, "pending")
    for _, c in ipairs(CAST) do RC:SetRoll(d, c[1], c[2], "pending") end
    SetButtonsEnabled(f, true)
    local delay = 0.3 * (i - 1) -- rolls start one after the other
    f.deadline = GetTime() + delay + TEST_DURATION
    f.bar:SetValue(1)
    f:Show()
    ns.OnDropChanged(d)

    local choices = CHOICES[(i - 1) % #CHOICES + 1]
    for j, c in ipairs(CAST) do
      C_Timer.After(delay + 0.6 * j, function()
        if f.drop ~= d or f.resolved then return end -- a newer test took the frame
        RC:SetRoll(d, c[1], nil, choices[j])
        ns.OnDropChanged(d)
        ResolveIfDone(f)
      end)
    end
  end
  return run
end
