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
-- Panel shown to the right of each Blizzard roll frame
---------------------------------------------------------------------------
local ROW_H = 14
local PAD = 6
local COLLAPSED_W = 124 -- icons and counts only
local EXPANDED_W = 176 -- names, icon and roll
local MAX_ROWS = 25 -- expanded list: past that, the rest is summed up as "+N"
local panels = {}   -- [rollFrame] = panel
local hooked = {}   -- [rollFrame] = true

-- The panel to the right of a roll frame. Normally it is only the list shown while a roll
-- button is hovered (see the counts on the buttons below). On a roll frame whose buttons are
-- not found, it is a summary instead, with two states:
--  collapsed: exactly as tall as its roll frame (stacked rolls never overlap), with the number
--             of players per choice, the winner or how many are still choosing, and a hint;
--  expanded:  the full list of players in one column, drawn above the other rolls.
-- A click switches between them.
local FillPanel

local function NewLine(p)
  local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetJustifyH("LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

local function CreatePanel(parent)
  local p = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
  p:SetWidth(COLLAPSED_W)
  ApplyBackdrop(p)
  p:EnableMouse(true)
  p:RegisterForClicks("LeftButtonUp")
  p.expanded = WhoRolledDB.settings.expanded and true or false
  p.rows = {}
  p.summary = {}
  for k = 1, 3 do
    local fs = NewLine(p)
    fs:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + 2, -PAD - 1 - (k - 1) * ROW_H)
    fs:SetWidth(COLLAPSED_W - 2 * PAD - 4)
    p.summary[k] = fs
  end
  p:SetScript("OnClick", function(self)
    self.expanded = not self.expanded
    FillPanel(self, self.drop)
  end)
  return p
end

local function GetRow(p, i)
  local row = p.rows[i]
  if not row then
    row = {}
    row.name = NewLine(p)
    row.name:SetWidth(EXPANDED_W - 2 * PAD - 52)
    row.choice = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.choice:SetJustifyH("RIGHT")
    p.rows[i] = row
  end
  return row
end

-- Lines that fit in the roll frame's height (at least 1).
local function LinesThatFit(p)
  local parent = p:GetParent()
  local h = parent and parent.GetHeight and parent:GetHeight()
  if type(h) ~= "number" or h <= 0 then h = 60 end
  return math.max(1, math.floor((h - 2 * PAD) / ROW_H))
end
ns.LinesThatFit = LinesThatFit

local function ChoiceIcon(s)
  return STATE_ICON[s] or (STATE_COLOR[s] .. STATE_LABEL[s] .. "|r")
end

local function ChoiceText(r)
  local txt = ChoiceIcon(r.state or "pending")
  if r.roll then txt = txt .. " |cffffffff" .. r.roll .. "|r" end
  return txt
end

local function Collapsed(p, d)
  local parent = p:GetParent()
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
  p:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 2, 0)
  if p.SetFrameStrata and parent.GetFrameStrata then p:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM") end
  p:SetWidth(COLLAPSED_W)
  for _, row in ipairs(p.rows) do row.name:Hide(); row.choice:Hide() end

  -- line 1: players per choice; line 2: winner, else who is still choosing; line 3: hint
  local counts, winner = {}, nil
  for _, r in ipairs(d and d.rolls or {}) do
    local s = r.state or "pending"
    counts[s] = (counts[s] or 0) + 1
    if r.winner then winner = r end
  end
  local parts = {}
  for _, s in ipairs(STATE_SEQ) do
    if s ~= "pending" and counts[s] then
      parts[#parts + 1] = ChoiceIcon(s) .. " " .. counts[s]
    end
  end
  local line1 = #parts > 0 and table.concat(parts, "  ") or ("|cff888888" .. L.WAITING_CHOICES .. "|r")
  local line2
  if winner then
    line2 = WIN_ICON .. " " .. Colored(winner.name, winner.class) .. (winner.roll and (" " .. winner.roll) or "")
  elseif d and d.allPassed then
    line2 = "|cff9d9d9d" .. L.ALL_PASSED .. "|r"
  elseif counts.pending then
    line2 = "|cff888888" .. L.PENDING .. " : " .. counts.pending .. "|r"
  end
  local lines = { line1, line2, "|cff888888" .. L.CLICK_DETAILS .. "|r" }
  if not line2 then lines = { line1, lines[3] } end

  local fit = LinesThatFit(p)
  for k = 1, 3 do
    local fs = p.summary[k]
    if lines[k] and k <= fit then
      fs:SetText(lines[k])
      fs:Show()
    else
      fs:Hide()
    end
  end
  p.shownLines = math.min(#lines, fit) -- for the tests
end

-- filter: a choice ("need", "greed", ...) to list only the players who made it (hover on a roll
-- button), or nil for everyone (click on the summary panel).
local function Expanded(p, d, filter)
  local parent = p:GetParent()
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
  if p.SetFrameStrata then p:SetFrameStrata("DIALOG") end -- above the other rolls
  p:SetWidth(EXPANDED_W)
  for _, fs in ipairs(p.summary) do fs:Hide() end

  local header
  if filter then
    header = ChoiceIcon(filter) .. " " .. STATE_COLOR[filter] .. STATE_LABEL[filter] .. "|r"
  else
    header = "|cff888888" .. L.CLICK_HIDE .. "|r"
  end
  local entries = { { header, "", 0 } }
  local pending = 0
  for _, r in ipairs(d and SortedRolls(d) or {}) do
    local s = r.state or "pending"
    if s == "pending" then
      pending = pending + 1
    elseif not filter or s == filter then
      entries[#entries + 1] = { (r.winner and (WIN_ICON .. " ") or "") .. Colored(r.name, r.class), ChoiceText(r), 1 }
    end
  end
  if filter then
    if #entries == 1 then entries[2] = { "|cff888888" .. L.NOBODY .. "|r", "", 0 } end
  elseif pending > 0 then
    entries[#entries + 1] = { "|cff888888" .. L.PENDING .. " : " .. pending .. "|r", "", pending }
  elseif #entries == 1 then
    entries[2] = { "|cff888888" .. L.WAITING_CHOICES .. "|r", "", 0 }
  end
  if #entries > MAX_ROWS then
    local hidden = 0
    for k = #entries, MAX_ROWS, -1 do
      hidden = hidden + entries[k][3]
      entries[k] = nil
    end
    entries[MAX_ROWS] = { "|cff888888+" .. hidden .. "|r", "", hidden }
  end

  for i, e in ipairs(entries) do
    local row = GetRow(p, i)
    local y = -PAD - 1 - (i - 1) * ROW_H
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + 2, y)
    row.choice:ClearAllPoints()
    row.choice:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD - 2, y)
    row.name:SetText(e[1])
    row.choice:SetText(e[2])
    row.name:Show()
    row.choice:Show()
  end
  for i = #entries + 1, #p.rows do
    p.rows[i].name:Hide()
    p.rows[i].choice:Hide()
  end
  p:SetHeight(2 * PAD + 2 + #entries * ROW_H)
  p.shownEntries = #entries -- for the tests
end

FillPanel = function(p, d)
  if d ~= p.drop then p.expanded = false end -- a new roll in a reused roll frame starts collapsed
  p.drop = d
  p:EnableMouse(true)
  if p.expanded then Expanded(p, d) else Collapsed(p, d) end
  p:Show()
end
ns.CreatePanel, ns.FillPanel = CreatePanel, FillPanel -- for the tests

---------------------------------------------------------------------------
-- Counts on the roll frame's own Need / Greed / Pass buttons; hovering a button
-- shows who made that choice in a list to the right of the roll frame. When the
-- buttons cannot be found (an unknown roll frame), the summary panel is used.
---------------------------------------------------------------------------
-- Keys of the buttons on the game's roll frames: fields on Retail-style frames, global
-- "<frame name><key>" on Classic-style ones (where Need is "RollButton").
local BUTTON_KEYS = {
  need = { "NeedButton", "RollButton" },
  greed = { "GreedButton" },
  pass = { "PassButton" },
  transmog = { "TransmogButton" },
}
local buttonCache = {} -- [rollFrame] = { [state] = button } or false
local badges = {}      -- [button] = count font string
local hoverHooked = {} -- [button] = true
local hovered = {}     -- [rollFrame] = state under the mouse
local frameDrop = {}   -- [rollFrame] = drop shown

local function FindRollButtons(f)
  if f.whoRolledButtons then return f.whoRolledButtons end -- our test frames
  if buttonCache[f] ~= nil then return buttonCache[f] or nil end
  local name = f.GetName and f:GetName()
  local found, any = {}, false
  for state, keys in pairs(BUTTON_KEYS) do
    for _, key in ipairs(keys) do
      local b = f[key]
      if type(b) ~= "table" and name then b = _G[name .. key] end
      if type(b) == "table" and b.HookScript then
        found[state] = b
        any = true
        break
      end
    end
  end
  buttonCache[f] = any and found or false
  return any and found or nil
end

local function ShowHoverList(f)
  local p = panels[f] or CreatePanel(f)
  panels[f] = p
  p.drop = frameDrop[f]
  p:EnableMouse(false) -- a list to read, nothing to click
  Expanded(p, frameDrop[f], hovered[f])
  p:Show()
end

local function HookButton(f, state, b)
  if hoverHooked[b] then return end
  b:HookScript("OnEnter", function()
    hovered[f] = state
    if frameDrop[f] and WhoRolledDB.settings.attach then ShowHoverList(f) end
  end)
  b:HookScript("OnLeave", function()
    hovered[f] = nil
    if panels[f] and FindRollButtons(f) then panels[f]:Hide() end
  end)
  hoverHooked[b] = true
end

function ns.UpdateRollFrame(f, d)
  local buttons = FindRollButtons(f)
  local on = WhoRolledDB.settings.attach and d ~= nil
  if not buttons then
    if on then
      panels[f] = panels[f] or CreatePanel(f)
      FillPanel(panels[f], d)
    elseif panels[f] then
      panels[f]:Hide()
    end
    return
  end

  frameDrop[f] = d
  local counts = {}
  for _, r in ipairs(d and d.rolls or {}) do
    local s = r.state or "pending"
    counts[s] = (counts[s] or 0) + 1
  end
  for state, b in pairs(buttons) do
    local fs = badges[b]
    if not fs then
      fs = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
      fs:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -2)
      badges[b] = fs
    end
    HookButton(f, state, b)
    local n = on and counts[state] or 0
    fs:SetText(n > 0 and tostring(n) or "")
  end
  if on and hovered[f] then
    ShowHoverList(f)
  elseif panels[f] then
    panels[f]:Hide()
  end
end
ns.badges = badges -- for the tests

function ns.RefreshRollFrames()
  ns.ApplyRollPosition()
  for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
    local f = _G["GroupLootFrame" .. i]
    if f then
      if not hooked[f] then
        f:HookScript("OnShow", ns.RefreshRollFramesSoon)
        hooked[f] = true
      end
      if f:IsShown() and f.rollID then
        ns.UpdateRollFrame(f, RC:DropForRoll(f.rollID))
      elseif panels[f] then
        panels[f]:Hide()
      end
    end
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
local TEST_FRAME_GAP = 4
local TEST_DURATION = 15 -- seconds to choose, like a real roll's timer
local TEST_LINGER = 5    -- seconds a finished test roll stays on screen

local ROLL_BUTTONS = {
  { "need", "Interface\\Buttons\\UI-GroupLoot-Dice", L.NEED },
  { "greed", "Interface\\Buttons\\UI-GroupLoot-Coin", L.GREED },
  { "pass", "Interface\\Buttons\\UI-GroupLoot-Pass", L.PASS },
}

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

-- Same size as the game's roll frames when the client has them, so the panels look as they will
local function TestFrameSize()
  local real = _G.GroupLootFrame1
  if real and real.GetSize then
    local ok, w, h = pcall(real.GetSize, real)
    if ok and type(w) == "number" and type(h) == "number" and w > 100 and h > 30 then return w, h end
  end
  return 256, 64
end

local TestChoose -- defined below

-- A test roll is the game's own roll frame when possible: a new frame from the template the
-- game's rolls are made from (GroupLootFrameTemplate), with the template's scripts switched off
-- (they would ask the server about a roll that does not exist) and its buttons wired to the test.
-- The game's GroupLootFrame1-4 are never touched. When the template is missing or its parts
-- cannot be found, a look-alike frame is built instead.
local LOOT_TEMPLATE = "GroupLootFrameTemplate"

local function TooltipText(text)
  return function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text)
    GameTooltip:Show()
  end
end

local function HideTooltip() GameTooltip:Hide() end

local function WireIcon(f, icon)
  icon:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, f.link)
    GameTooltip:Show()
  end)
  icon:SetScript("OnLeave", HideTooltip)
  icon:SetScript("OnClick", function(self, button)
    if f.link then SetItemRef(f.link, f.link, button, self) end
  end)
end

local function WireButton(f, btn, choice, label)
  btn.choice = choice
  btn:SetScript("OnClick", function() TestChoose(f, choice) end)
  btn:SetScript("OnEnter", TooltipText(label))
  btn:SetScript("OnLeave", HideTooltip)
end

local function BuildFromTemplate(i)
  local name = "WhoRolledTestRoll" .. i
  local ok, f = pcall(CreateFrame, "Frame", name, UIParent, LOOT_TEMPLATE)
  if not ok or type(f) ~= "table" then return nil end
  f:Hide()
  -- parts are fields on Retail-style templates, "<name><suffix>" globals on Classic-style ones
  local function part(key, suffix)
    local v = f[key]
    if type(v) ~= "table" then v = _G[name .. (suffix or key)] end
    return type(v) == "table" and v or nil
  end
  local iconFrame = part("IconFrame")
  local iconTex = iconFrame and type(iconFrame.Icon) == "table" and iconFrame.Icon or _G[name .. "IconFrameIcon"]
  local nameText = part("Name")
  local timer = part("Timer")
  local need = part("NeedButton") or part("RollButton")
  local greed, pass = part("GreedButton"), part("PassButton")
  if not (iconFrame and iconTex and nameText and timer and need and greed and pass) then
    ns.Debug("test roll: " .. LOOT_TEMPLATE .. " parts not found, using a look-alike")
    return nil
  end

  -- switch the template's own logic off
  if f.UnregisterAllEvents then f:UnregisterAllEvents() end
  for _, script in ipairs({ "OnEvent", "OnShow", "OnHide", "OnUpdate" }) do pcall(f.SetScript, f, script, nil) end
  pcall(timer.SetScript, timer, "OnUpdate", nil)
  for _, key in ipairs({ "DisenchantButton", "TransmogButton" }) do
    local b = part(key)
    if b then b:Hide() end
  end

  WireIcon(f, iconFrame)
  WireButton(f, need, "need", L.NEED)
  WireButton(f, greed, "greed", L.GREED)
  WireButton(f, pass, "pass", L.PASS)
  for _, b in ipairs({ need, greed, pass }) do b:Show() end
  if nameText.SetVertexColor then nameText:SetVertexColor(1, 1, 1) end -- the colour comes from the text
  timer:SetMinMaxValues(0, 1)
  local tag = timer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  tag:SetPoint("CENTER")
  tag:SetText(L.TEST_TAG) -- so a test roll is never mistaken for a real one

  f.icon, f.iconTex, f.name, f.bar = iconFrame, iconTex, nameText, timer
  f.buttons = { need, greed, pass }
  f.fromTemplate = true
  return f
end

local function BuildLookalike()
  local w, h = TestFrameSize()
  local f = CreateFrame("Frame", nil, UIParent, BACKDROP_TEMPLATE)
  f:SetSize(w, h)
  f:SetFrameStrata("MEDIUM")
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
      tile = true, tileSize = 32, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end

  local size = math.min(40, h - 20)
  local icon = CreateFrame("Button", nil, f)
  icon:SetSize(size, size)
  icon:SetPoint("LEFT", f, "LEFT", 10, 0)
  local iconTex = icon:CreateTexture(nil, "ARTWORK")
  iconTex:SetAllPoints(icon)
  WireIcon(f, icon)
  f.icon, f.iconTex = icon, iconTex

  f.buttons = {}
  for k, b in ipairs(ROLL_BUTTONS) do
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(26, 26)
    btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10 - (#ROLL_BUTTONS - k) * 28, -8)
    btn:SetNormalTexture(b[2] .. "-Up")
    btn:SetPushedTexture(b[2] .. "-Down")
    btn:SetHighlightTexture(b[2] .. "-Highlight")
    WireButton(f, btn, b[1], b[3])
    f.buttons[k] = btn
  end

  f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
  f.name:SetPoint("RIGHT", f.buttons[1], "LEFT", -6, 0)
  f.name:SetJustifyH("LEFT")
  if f.name.SetWordWrap then f.name:SetWordWrap(false) end

  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 0)
  bar:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  bar:SetHeight(10)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(1, 0.82, 0)
  bar:SetMinMaxValues(0, 1)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  bg:SetColorTexture(0, 0, 0, 0.6)
  local tag = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  tag:SetPoint("CENTER")
  tag:SetText(L.TEST_TAG)
  f.bar = bar
  return f
end

local function GetTestFrame(i)
  local f = testFrames[i]
  if f then return f end
  f = BuildFromTemplate(i) or BuildLookalike()

  f:SetScript("OnUpdate", function(self)
    if not self.deadline then return end
    local left = self.deadline - GetTime()
    self.bar:SetValue(math.max(0, left / TEST_DURATION))
    if left <= 0 then ns.TestTimeout(self) end
  end)

  -- the same counts and hover lists as on the game's roll frames
  f.whoRolledButtons = {}
  for _, btn in ipairs(f.buttons) do f.whoRolledButtons[btn.choice] = btn end
  testFrames[i] = f
  return f
end
ns.testFrames = testFrames -- for the tests

local function SetButtonsEnabled(f, enabled)
  for _, btn in ipairs(f.buttons) do
    if enabled then btn:Enable() else btn:Disable() end
    local tex = btn.GetNormalTexture and btn:GetNormalTexture()
    if tex and tex.SetDesaturated then tex:SetDesaturated(not enabled) end
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
    local _, h = f:GetSize()
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", base, "BOTTOM", 0, baseY + (i - 1) * ((h or 64) + TEST_FRAME_GAP))
    f.link = link
    f.iconTex:SetTexture(TestItemIcon(item[1]))
    local color, name = link:match("^|c(%x+)|H.-|h%[(.-)%]|h")
    f.name:SetText(("|c%s%s|r"):format(color or "ffffffff", name or item[2]))

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
