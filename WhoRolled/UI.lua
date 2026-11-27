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
local panels = {}   -- [rollFrame] = panel
local hooked = {}   -- [rollFrame] = true

local function CreatePanel(parent)
  local p = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
  p:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
  p:SetWidth(200)
  ApplyBackdrop(p)
  p.rows = {}
  return p
end

local function GetRow(p, i)
  local row = p.rows[i]
  if not row then
    local y = -7 - (i - 1) * ROW_H
    row = {}
    row.name = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", p, "TOPLEFT", 8, y)
    row.name:SetWidth(110)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.choice = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.choice:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, y)
    row.choice:SetJustifyH("RIGHT")
    p.rows[i] = row
  end
  return row
end

local function FillPanel(p, d)
  local n, pending = 0, 0
  if d then
    for _, r in ipairs(SortedRolls(d)) do
      local s = r.state or "pending"
      if s == "pending" then
        pending = pending + 1
      else
        n = n + 1
        local row = GetRow(p, n)
        row.name:SetText((r.winner and (WIN_ICON .. " ") or "") .. Colored(r.name, r.class))
        local txt = STATE_COLOR[s] .. STATE_LABEL[s] .. "|r"
        if r.roll then txt = txt .. "  |cffffffff" .. r.roll .. "|r" end
        row.choice:SetText(txt)
      end
    end
  end
  if pending > 0 or n == 0 then
    n = n + 1
    local row = GetRow(p, n)
    if pending > 0 then
      row.name:SetText("|cff888888" .. L.PENDING .. " : " .. pending .. "|r")
    else
      row.name:SetText("|cff888888" .. L.WAITING_CHOICES .. "|r")
    end
    row.choice:SetText("")
  end
  for i, row in ipairs(p.rows) do
    if i <= n then row.name:Show(); row.choice:Show() else row.name:Hide(); row.choice:Hide() end
  end
  p:SetHeight(14 + n * ROW_H)
  p:Show()
end

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
  anchor:SetSize(260, 40)
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
local testFrame, testPanel

function ns.OnDropChanged(d)
  ns.RefreshRollFrames()
  if d.test and testFrame and testFrame:IsShown() then FillPanel(testPanel, d) end
  ns.RenderHistory()
end

---------------------------------------------------------------------------
-- Test mode: a fake roll frame that fills up over a few seconds
---------------------------------------------------------------------------
-- Item link of the Hearthstone for the test roll. The global GetItemInfo errors on the Forever
-- client, so C_Item is tried first and every call is protected; a built link is the fallback.
local function TestItemLink()
  local getters = { C_Item and C_Item.GetItemInfo, GetItemInfo }
  for i = 1, 2 do
    local get = getters[i]
    if get then
      local ok, _, link = pcall(get, 6948)
      if ok and link then return link end
    end
  end
  return "|cffffffff|Hitem:6948::::::::1:::::::|h[Hearthstone]|h|r"
end

function ns.RunTest()
  local link = TestItemLink()

  if not testFrame then
    testFrame = CreateFrame("Frame", nil, UIParent, BACKDROP_TEMPLATE)
    testFrame:SetSize(240, 60)
    ApplyBackdrop(testFrame)
    testFrame.text = testFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    testFrame.text:SetPoint("CENTER")
    testPanel = CreatePanel(testFrame)
  end
  -- show the test roll where real rolls will appear
  testFrame:ClearAllPoints()
  if WhoRolledDB.settings.rollPos then
    PlaceAnchor()
    testFrame:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
  else
    testFrame:SetPoint("CENTER", 0, 180)
  end
  testFrame.text:SetText("TEST  " .. link)
  testFrame:Show()

  local d = RC:NewDrop("test:" .. time() .. ":" .. math.random(100000), link)
  d.test = true
  d.encounterName = "Test"

  local me, myClass = UnitName("player"), select(2, UnitClass("player"))
  local cast = {
    { me, myClass }, { "Arwyn", "PALADIN" }, { "Brogar", "WARRIOR" }, { "Célia", "PRIEST" }, { "Dorn", "HUNTER" },
  }
  for _, c in ipairs(cast) do RC:SetRoll(d, c[1], c[2], "pending") end
  ns.OnDropChanged(d)

  local steps = {
    { 1.0, function() RC:SetRoll(d, "Arwyn", nil, "need") end },
    { 1.6, function() RC:SetRoll(d, me, nil, "greed") end },
    { 2.2, function() RC:SetRoll(d, "Célia", nil, "pass") end },
    { 2.8, function() RC:SetRoll(d, "Brogar", nil, "pass") end },
    { 3.4, function() RC:SetRoll(d, "Dorn", nil, "need") end },
    { 4.4, function()
      RC:SetRoll(d, "Arwyn", nil, nil, 72)
      RC:SetRoll(d, "Dorn", nil, nil, 88, true)
      d.winner = "Dorn"
    end },
  }
  for _, s in ipairs(steps) do
    C_Timer.After(s[1], function() s[2](); ns.OnDropChanged(d) end)
  end
  C_Timer.After(12, function() testFrame:Hide() end)
end
