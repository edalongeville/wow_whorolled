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
local PANEL_W = 240
local MAX_ROWS = 25 -- expanded list: past that, the rest is summed up as "+N"
local panels = {}   -- [rollFrame] = panel
local hooked = {}   -- [rollFrame] = true

-- A panel has two states:
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
  p:SetWidth(PANEL_W)
  ApplyBackdrop(p)
  p:EnableMouse(true)
  p:RegisterForClicks("LeftButtonUp")
  p.expanded = WhoRolledDB.settings.expanded and true or false
  p.rows = {}
  p.summary = {}
  for k = 1, 3 do
    local fs = NewLine(p)
    fs:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + 2, -PAD - 1 - (k - 1) * ROW_H)
    fs:SetWidth(PANEL_W - 2 * PAD - 4)
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
    row.name:SetWidth(PANEL_W - 90)
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

local function ChoiceText(r)
  local s = r.state or "pending"
  local txt = STATE_COLOR[s] .. STATE_LABEL[s] .. "|r"
  if r.roll then txt = txt .. "  |cffffffff" .. r.roll .. "|r" end
  return txt
end

local function Collapsed(p, d)
  local parent = p:GetParent()
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
  p:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 2, 0)
  if p.SetFrameStrata and parent.GetFrameStrata then p:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM") end
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
      parts[#parts + 1] = STATE_COLOR[s] .. STATE_LABEL[s] .. " " .. counts[s] .. "|r"
    end
  end
  local line1 = #parts > 0 and table.concat(parts, "  ") or ("|cff888888" .. L.WAITING_CHOICES .. "|r")
  local line2
  if winner then
    line2 = WIN_ICON .. " " .. Colored(winner.name, winner.class) .. "  " .. ChoiceText(winner)
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

local function Expanded(p, d)
  local parent = p:GetParent()
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
  if p.SetFrameStrata then p:SetFrameStrata("DIALOG") end -- above the other rolls
  for _, fs in ipairs(p.summary) do fs:Hide() end

  local entries = { { "|cff888888" .. L.CLICK_HIDE .. "|r", "", 0 } }
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
  if d ~= p.drop then
    -- a new roll in a reused roll frame starts in the default state
    p.expanded = WhoRolledDB.settings.expanded and true or false
  end
  p.drop = d
  if p.expanded then Expanded(p, d) else Collapsed(p, d) end
  p:Show()
end
ns.CreatePanel, ns.FillPanel = CreatePanel, FillPanel -- for the tests

function ns.RefreshRollFrames()
  ns.ApplyRollPosition()
  for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
    local f = _G["GroupLootFrame" .. i]
    if f then
      if not hooked[f] then
        f:HookScript("OnShow", ns.RefreshRollFramesSoon)
        hooked[f] = true
      end
      if f:IsShown() and f.rollID and WhoRolledDB.settings.attach then
        panels[f] = panels[f] or CreatePanel(f)
        FillPanel(panels[f], RC:DropForRoll(f.rollID))
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
local testFrames = {} -- pool of fake roll frames, each with .panel and .drop

function ns.OnDropChanged(d)
  ns.RefreshRollFrames()
  if d.test then
    for _, f in ipairs(testFrames) do
      if f.drop == d and f:IsShown() then FillPanel(f.panel, d) end
    end
  end
  ns.RenderHistory()
end

---------------------------------------------------------------------------
-- Test mode: fake roll frames that fill up over a few seconds
---------------------------------------------------------------------------
ns.MAX_TEST_ROLLS = 10
local TEST_ITEMS = {
  { 6948, "Hearthstone", "ffffffff" },
  { 4306, "Silk Cloth", "ffffffff" },
  { 2589, "Linen Cloth", "ffffffff" },
  { 765, "Silverleaf", "ffffffff" },
  { 2770, "Copper Ore", "ffffffff" },
  { 118, "Minor Healing Potion", "ffffffff" },
  { 2447, "Peacebloom", "ffffffff" },
  { 4338, "Mageweave Cloth", "ffffffff" },
  { 159, "Refreshing Spring Water", "ffffffff" },
  { 117, "Tough Jerky", "ffffffff" },
}
local TEST_FRAME_H, TEST_FRAME_GAP = 60, 8

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

local function GetTestFrame(i)
  local f = testFrames[i]
  if not f then
    f = CreateFrame("Frame", nil, UIParent, BACKDROP_TEMPLATE)
    f:SetSize(240, TEST_FRAME_H)
    ApplyBackdrop(f)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("CENTER")
    f.panel = CreatePanel(f)
    testFrames[i] = f
  end
  return f
end

-- Who chooses what on fake roll n: varied from one roll to the next, with a winner, a tie of
-- greeds or everyone passing now and then.
local CAST = { { "Arwyn", "PALADIN" }, { "Brogar", "WARRIOR" }, { "Célia", "PRIEST" }, { "Dorn", "HUNTER" } }
local CHOICES = {
  { "need", "pass", "pass", "need", "greed" },
  { "greed", "greed", "pass", "greed", "pass" },
  { "pass", "pass", "pass", "pass", "pass" },
  { "need", "greed", "need", "pass", "need" },
}

local testRun = 0

function ns.RunTest(count)
  count = math.max(1, math.min(ns.MAX_TEST_ROLLS, math.floor(tonumber(count) or 1)))
  testRun = testRun + 1
  local run = testRun

  for _, f in ipairs(testFrames) do f:Hide() end

  local me, myClass = UnitName("player"), select(2, UnitClass("player"))
  local players = { { me, myClass } }
  for _, c in ipairs(CAST) do players[#players + 1] = c end

  -- stack the fake frames upwards from where real rolls appear
  local base, basePoint, baseX, baseY
  if WhoRolledDB.settings.rollPos then
    PlaceAnchor()
    base, basePoint, baseX, baseY = anchor, "BOTTOM", 0, 0
  else
    base, basePoint, baseX, baseY = UIParent, "BOTTOM", 0, 200
  end

  for i = 1, count do
    local f = GetTestFrame(i)
    local link = TestItemLink(TEST_ITEMS[(i - 1) % #TEST_ITEMS + 1])
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", base, basePoint, baseX, baseY + (i - 1) * (TEST_FRAME_H + TEST_FRAME_GAP))
    f.text:SetText("TEST " .. i .. "  " .. link)

    local d = RC:NewDrop("test:" .. run .. ":" .. i .. ":" .. time(), link)
    d.test = true
    d.encounterName = "Test"
    f.drop = d
    for _, p in ipairs(players) do RC:SetRoll(d, p[1], p[2], "pending") end
    f:Show()
    ns.OnDropChanged(d)

    local choices = CHOICES[(i - 1) % #CHOICES + 1]
    local delay = 0.3 * (i - 1) -- rolls start one after the other
    for j, p in ipairs(players) do
      C_Timer.After(delay + 0.6 * j, function()
        RC:SetRoll(d, p[1], nil, choices[j])
        ns.OnDropChanged(d)
      end)
    end

    C_Timer.After(delay + 0.6 * #players + 1, function()
      -- the best need wins, else the best greed, else everyone passed
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
    end)
  end

  C_Timer.After(0.3 * count + 0.6 * #players + 8, function()
    if run ~= testRun then return end -- a newer test owns the frames
    for _, f in ipairs(testFrames) do f:Hide() end
  end)
end
