local ADDON, ns = ...
local L = ns.L

local RC = CreateFrame("Frame")
ns.RC = RC

local DEFAULTS = {
  maxHistory = 200,
  debug = false,
  attach = true,
  source = "auto", -- "auto" | "api" | "chat"
}

-- Display order of choices (lower first)
ns.STATE_ORDER = { need = 1, transmog = 2, greed = 3, pass = 4, pending = 5 }

local function Print(...)
  print("|cff33ff99WhoRolled|r:", ...)
end
ns.Print = Print

local function Debug(...)
  if WhoRolledDB and WhoRolledDB.settings.debug then
    Print("|cff888888[debug]|r", ...)
  end
end
ns.Debug = Debug

local function ItemID(link)
  return link and tonumber(link:match("item:(%d+)"))
end
ns.ItemID = ItemID

local function ShortName(name)
  if not name then return "?" end
  if Ambiguate then return Ambiguate(name, "short") end
  return (name:match("^[^-]+")) or name
end
ns.ShortName = ShortName

-- Class of a group member by name (used when the data source doesn't give it)
local function ClassOf(name)
  if not name then return end
  local short = ShortName(name)
  if UnitName("player") == short then return (select(2, UnitClass("player"))) end
  local prefix = IsInRaid() and "raid" or "party"
  for i = 1, GetNumGroupMembers() do
    local unit = prefix .. i
    if UnitName(unit) == short then return (select(2, UnitClass(unit))) end
  end
end

---------------------------------------------------------------------------
-- Roll state mapping (C_LootHistory enum -> our state names)
---------------------------------------------------------------------------
local stateMap
local function BuildStateMap()
  local E = Enum and Enum.EncounterLootDropRollState
  if E then
    stateMap = {}
    if E.NeedMainSpec then stateMap[E.NeedMainSpec] = "need" end
    if E.NeedOffSpec then stateMap[E.NeedOffSpec] = "need" end
    if E.Transmog then stateMap[E.Transmog] = "transmog" end
    if E.Greed then stateMap[E.Greed] = "greed" end
    if E.NoRoll then stateMap[E.NoRoll] = "pending" end
    if E.Pass then stateMap[E.Pass] = "pass" end
  else
    -- Values used by the Retail client when the Enum table is absent
    stateMap = { [0] = "need", [1] = "need", [2] = "transmog", [3] = "greed", [4] = "pending", [5] = "pass" }
  end
end

---------------------------------------------------------------------------
-- Data model
--   WhoRolledDB.history = array of drops, oldest first
--   drop = { key, link, itemID, time, encounterName, winner, allPassed,
--            rolls = { { name, class, state, roll, winner }, ... } }
--   RC.active[rollID] = { link, itemID, start, dropKey, ended }
---------------------------------------------------------------------------
RC.index = {}
RC.active = {}

function RC:UseAPI()
  local s = WhoRolledDB.settings.source
  local has = C_LootHistory and C_LootHistory.GetSortedInfoForDrop and true or false
  if s == "api" then return has end
  if s == "chat" then return false end
  return has
end

function RC:UseChat()
  return not self:UseAPI()
end

function RC:NewDrop(key, link)
  local d = { key = key, link = link, itemID = ItemID(link), time = time(), rolls = {} }
  local h = WhoRolledDB.history
  h[#h + 1] = d
  while #h > WhoRolledDB.settings.maxHistory do
    local old = table.remove(h, 1)
    self.index[old.key] = nil
  end
  self.index[key] = d
  self:LinkActiveRoll(d)
  return d
end

-- Tie a new drop to the oldest active roll for the same item that has none yet
function RC:LinkActiveRoll(d)
  local best
  for rollID, a in pairs(self.active) do
    if not a.dropKey and a.itemID == d.itemID and (not best or a.start < self.active[best].start) then
      best = rollID
    end
  end
  if best then
    self.active[best].dropKey = d.key
    d.rollID = best
  end
end

-- A recent drop for this item that is not tied to a roll frame yet
function RC:FindUnlinkedDrop(itemID)
  local h = WhoRolledDB.history
  for i = #h, math.max(1, #h - 30), -1 do
    local d = h[i]
    if d.itemID == itemID and not d.rollID and not d.winner and not d.allPassed
      and not d.test and time() - d.time < 300 then
      return d
    end
  end
end

function RC:DropForRoll(rollID)
  local a = self.active[rollID]
  return a and a.dropKey and self.index[a.dropKey]
end

function RC:SetRoll(d, name, class, state, roll, winner)
  if not name then return end
  local r
  for _, x in ipairs(d.rolls) do
    if x.name == name then r = x break end
  end
  if not r then
    r = { name = name }
    d.rolls[#d.rolls + 1] = r
  end
  r.class = class or r.class or ClassOf(name)
  if state then r.state = state end
  if roll then r.roll = roll end
  if winner then r.winner = true end
end

function RC:Changed(d)
  if ns.OnDropChanged then ns.OnDropChanged(d) end
end

---------------------------------------------------------------------------
-- Source 1: C_LootHistory (preferred)
---------------------------------------------------------------------------
function RC:ReadDrop(encounterID, lootListID)
  if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
  local info = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)
  if not info or not info.itemHyperlink then return end

  local key = "api:" .. encounterID .. ":" .. lootListID
  local d = self.index[key] or self:NewDrop(key, info.itemHyperlink)

  if not d.encounterName and C_LootHistory.GetInfoForEncounter then
    local enc = C_LootHistory.GetInfoForEncounter(encounterID)
    d.encounterName = enc and enc.encounterName
  end

  for _, ri in ipairs(info.rollInfos or {}) do
    self:SetRoll(d, ri.playerName, ri.playerClass, stateMap[ri.state] or "pending", ri.roll, ri.isWinner)
  end
  if info.winner and info.winner.playerName then d.winner = info.winner.playerName end
  if info.allPassed then d.allPassed = true end

  Debug("drop", key, d.link, #d.rolls .. " rolls", d.winner or "")
  self:Changed(d)
end

function RC:ReadEncounter(encounterID)
  if not (C_LootHistory and C_LootHistory.GetSortedDropsForEncounter) then return end
  for _, drop in ipairs(C_LootHistory.GetSortedDropsForEncounter(encounterID) or {}) do
    if drop.lootListID then self:ReadDrop(encounterID, drop.lootListID) end
  end
end

---------------------------------------------------------------------------
-- Source 2: loot chat messages (fallback), using the client's own
-- localized strings so it works on a French client.
---------------------------------------------------------------------------

-- Turn a format string such as "%s a choisi Besoin pour : %s" or
-- "%2$s ... %1$s" into a Lua pattern plus argument order.
local function Compile(fmt)
  local order, n = {}, 0
  local p = fmt:gsub("%%(%d*)%$?([sd])", function(idx, kind)
    n = n + 1
    order[n] = tonumber(idx) or n
    return kind == "d" and "\001D" or "\001S"
  end)
  p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
  p = p:gsub("\001D", "(%%d+)"):gsub("\001S", "(.+)")
  return { pat = "^" .. p .. "$", order = order }
end
ns.Compile = Compile

local function Match(c, msg)
  local caps = { msg:match(c.pat) }
  if #caps == 0 then return end
  local out = {}
  for i, argIndex in ipairs(c.order) do out[argIndex] = caps[i] end
  return out
end
ns.Match = Match

-- Order matters: specific forms ("You ...", "automatically passed") first.
-- p = player arg, i = item arg, r = roll arg
local CHAT_DEFS = {
  { g = "LOOT_ROLL_YOU_WON", win = true, i = 1, me = true },
  { g = "LOOT_ROLL_NEED_SELF", state = "need", i = 1, me = true },
  { g = "LOOT_ROLL_GREED_SELF", state = "greed", i = 1, me = true },
  { g = "LOOT_ROLL_TRANSMOG_SELF", state = "transmog", i = 1, me = true },
  { g = "LOOT_ROLL_PASSED_SELF_AUTO", state = "pass", i = 1, me = true },
  { g = "LOOT_ROLL_PASSED_SELF", state = "pass", i = 1, me = true },
  { g = "LOOT_ROLL_PASSED_AUTO", state = "pass", p = 1, i = 2 },
  { g = "LOOT_ROLL_PASSED_AUTO_FEMALE", state = "pass", p = 1, i = 2 },
  { g = "LOOT_ROLL_ROLLED_NEED", state = "need", r = 1, i = 2, p = 3 },
  { g = "LOOT_ROLL_ROLLED_GREED", state = "greed", r = 1, i = 2, p = 3 },
  { g = "LOOT_ROLL_ROLLED_TRANSMOG", state = "transmog", r = 1, i = 2, p = 3 },
  { g = "LOOT_ROLL_ALL_PASSED", allPassed = true, i = 1 },
  { g = "LOOT_ROLL_NEED", state = "need", p = 1, i = 2 },
  { g = "LOOT_ROLL_GREED", state = "greed", p = 1, i = 2 },
  { g = "LOOT_ROLL_TRANSMOG", state = "transmog", p = 1, i = 2 },
  { g = "LOOT_ROLL_PASSED", state = "pass", p = 1, i = 2 },
  { g = "LOOT_ROLL_WON", win = true, p = 1, i = 2 },
}
ns.CHAT_DEFS = CHAT_DEFS

local chatPatterns = {}
local function BuildChatPatterns()
  wipe(chatPatterns)
  for _, def in ipairs(CHAT_DEFS) do
    local fmt = _G[def.g]
    if type(fmt) == "string" then
      def.c = Compile(fmt)
      chatPatterns[#chatPatterns + 1] = def
    end
  end
end

-- Pick the drop a chat line belongs to: the oldest unresolved active roll
-- for that item, else a recent unlinked drop, else a new drop.
function RC:DropForChat(itemID, link)
  local best
  for rollID, a in pairs(self.active) do
    if a.itemID == itemID then
      local d = a.dropKey and self.index[a.dropKey]
      if not (d and (d.winner or d.allPassed)) and (not best or a.start < self.active[best].start) then
        best = rollID
      end
    end
  end
  if best then
    local d = self:DropForRoll(best)
    return d or self:NewDrop("chat:" .. best .. ":" .. time(), link)
  end
  return self:FindUnlinkedDrop(itemID)
    or self:NewDrop("chat:" .. itemID .. ":" .. time() .. ":" .. math.random(100000), link)
end

function RC:OnChatLoot(msg)
  for _, def in ipairs(chatPatterns) do
    local a = Match(def.c, msg)
    if a then
      local link = a[def.i]
      local itemID = ItemID(link)
      if not itemID then return end
      local player = def.me and UnitName("player") or (def.p and a[def.p])
      local d = self:DropForChat(itemID, link)
      if def.allPassed then
        d.allPassed = true
      else
        self:SetRoll(d, player, nil, def.state, def.r and tonumber(a[def.r]), def.win)
        if def.win then d.winner = player end
      end
      Debug("chat", def.g, player or "", link)
      self:Changed(d)
      return
    end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnEvent(self, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    WhoRolledDB = WhoRolledDB or {}
    WhoRolledDB.history = WhoRolledDB.history or {}
    WhoRolledDB.settings = WhoRolledDB.settings or {}
    for k, v in pairs(DEFAULTS) do
      if WhoRolledDB.settings[k] == nil then WhoRolledDB.settings[k] = v end
    end
    for _, d in ipairs(WhoRolledDB.history) do
      d.rollID = nil -- roll IDs don't survive a reload
      self.index[d.key] = d
    end
    self:UnregisterEvent("ADDON_LOADED")

  elseif event == "PLAYER_LOGIN" then
    BuildStateMap()
    BuildChatPatterns()
    self:RegisterEvent("START_LOOT_ROLL")
    self:RegisterEvent("CANCEL_LOOT_ROLL")
    self:RegisterEvent("CHAT_MSG_LOOT")
    -- pcall: an event name unknown to the client would otherwise error
    pcall(self.RegisterEvent, self, "LOOT_HISTORY_UPDATE_DROP")
    pcall(self.RegisterEvent, self, "LOOT_HISTORY_UPDATE_ENCOUNTER")

  elseif event == "START_LOOT_ROLL" then
    local rollID = ...
    -- protected: some legacy globals error on the Forever client (GetItemInfo does)
    local ok, link = pcall(GetLootRollItemLink, rollID)
    if not ok then
      Debug("GetLootRollItemLink failed:", link)
      link = nil
    end
    local a = { link = link, itemID = ItemID(link), start = GetTime() }
    self.active[rollID] = a
    local d = a.itemID and self:FindUnlinkedDrop(a.itemID)
    if d then
      a.dropKey = d.key
      d.rollID = rollID
    end
    Debug(event, rollID, link or "?")
    if ns.RefreshRollFramesSoon then ns.RefreshRollFramesSoon() end

  elseif event == "CANCEL_LOOT_ROLL" then
    local rollID = ...
    local a = self.active[rollID]
    if a then
      a.ended = true
      -- keep it a little longer: the "won" message arrives after the roll ends
      C_Timer.After(60, function()
        if self.active[rollID] == a then self.active[rollID] = nil end
      end)
    end
    Debug(event, rollID)

  elseif event == "LOOT_HISTORY_UPDATE_DROP" then
    if self:UseAPI() then self:ReadDrop(...) end
    Debug(event, ...)

  elseif event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then
    if self:UseAPI() then self:ReadEncounter(...) end
    Debug(event, ...)

  elseif event == "CHAT_MSG_LOOT" then
    if self:UseChat() then self:OnChatLoot((...)) end
  end
end

RC:SetScript("OnEvent", OnEvent)
RC:RegisterEvent("ADDON_LOADED")
RC:RegisterEvent("PLAYER_LOGIN")

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_WHOROLLED1 = "/whorolled"
SLASH_WHOROLLED2 = "/wroll"
SlashCmdList.WHOROLLED = function(msg)
  local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  local s = WhoRolledDB.settings

  if cmd == "" then
    ns.ToggleHistory()
  elseif cmd == "test" then
    ns.RunTest()
  elseif cmd == "debug" then
    s.debug = not s.debug
    Print(L.DEBUG:format(s.debug and L.ON or L.OFF))
  elseif cmd == "attach" then
    s.attach = not s.attach
    Print(L.ATTACH:format(s.attach and L.ON or L.OFF))
    ns.RefreshRollFrames()
  elseif cmd == "clear" then
    wipe(WhoRolledDB.history)
    wipe(RC.index)
    Print(L.CLEARED)
    ns.RenderHistory()
  elseif cmd == "source" then
    if arg == "auto" or arg == "api" or arg == "chat" then s.source = arg end
    Print(L.SOURCE:format(s.source, RC:UseAPI() and "api" or "chat"))
  elseif cmd == "status" then
    local _, build, _, iface = GetBuildInfo()
    Print("build", build, "interface", iface)
    Print("C_LootHistory:", C_LootHistory and "yes" or "no",
      "| Enum.EncounterLootDropRollState:", (Enum and Enum.EncounterLootDropRollState) and "yes" or "no")
    Print(L.SOURCE:format(s.source, RC:UseAPI() and "api" or "chat"))
    local n = 0
    for _ in pairs(RC.active) do n = n + 1 end
    Print("active rolls:", n, "| history:", #WhoRolledDB.history, "| chat patterns:", #chatPatterns)
    if C_LootHistory and C_LootHistory.GetAllEncounterInfos then
      local encs = C_LootHistory.GetAllEncounterInfos() or {}
      Print("loot history encounters:", #encs)
    end
  else
    for _, line in ipairs(L.HELP) do Print(line) end
  end
end
