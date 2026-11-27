-- Stubbed WoW API, enough to load the addon files and drive them through events.
-- load_addon(opts) returns ns (the addon namespace), the frame stub registry and helpers.
local M = {}

local function newFrame(name)
  local f = {
    _scripts = {}, _events = {}, _shown = true, _name = name, _points = false, _setPointHooks = false,
    _parent = false, _height = false, _width = false,
  }
  return setmetatable(f, {
    __index = function(_, k)
      local m = M.FrameMethods[k]
      if m ~= nil then return m or nil end -- false: a field the frame doesn't have
      return function() end -- any other widget method is a no-op
    end,
  })
end

M.FrameMethods = {
  RegisterEvent = function(self, e) M.registry[e] = self end,
  UnregisterEvent = function(self, e) if M.registry[e] == self then M.registry[e] = nil end end,
  SetScript = function(self, n, fn) self._scripts[n] = fn end,
  HookScript = function(self, n, fn) self._scripts[n] = fn end,
  GetScript = function(self, n) return self._scripts[n] end,
  Show = function(self) self._shown = true end,
  Hide = function(self) self._shown = false end,
  SetShown = function(self, v) self._shown = v and true or false end,
  IsShown = function(self) return self._shown end,
  SetText = function(self, t) self._text = t end,
  GetText = function(self) return self._text end,
  SetChecked = function(self, v) self._checked = v and true or false end,
  GetChecked = function(self) return self._checked end,
  SetValue = function(self, v)
    self._value = v
    if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end
  end,
  GetValue = function(self) return self._value end,
  GetParent = function(self) return self._parent end,
  SetHeight = function(self, h) self._height = h end,
  GetHeight = function(self) return self._height end,
  SetSize = function(self, w, h) self._width, self._height = w, h end,
  CreateFontString = function() return newFrame() end,
  ClearAllPoints = function(self) self._points = {} end,
  SetPoint = function(self, ...)
    self._points = self._points or {}
    table.insert(self._points, { ... })
    for _, fn in ipairs(self._setPointHooks or {}) do fn(self, ...) end
  end,
  GetPoint = function(self, i)
    local p = self._points and self._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
  end,
  AddMessage = function(self, msg) self._lines = self._lines or {}; table.insert(self._lines, msg) end,
  Clear = function(self) self._lines = {} end,
  -- fields, not methods: absent on our stub frames
  TitleText = false,
  title = false,
}

function M.load(opts)
  opts = opts or {}
  M.registry = {}
  M.printed = {}
  M.timers = {}
  local env = {
    -- Lua / WoW std
    time = os.time, date = os.date, wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    tinsert = table.insert,
    print = function(...)
      local t = { ... }
      for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
      table.insert(M.printed, table.concat(t, " "))
    end,
    -- frames
    CreateFrame = function(kind, name, parent, template)
      local f = newFrame(name)
      f._parent = parent
      table.insert(M.created, { kind = kind, template = template, frame = f })
      f._shown = name ~= "WhoRolledHistoryFrame"
      if name then M.env[name] = f end -- named frames are globals, as in the game
      return f
    end,
    UIParent = newFrame("UIParent"),
    GroupLootContainer = (not opts.noContainer) and newFrame("GroupLootContainer") or nil,
    hooksecurefunc = function(frame, method, fn)
      assert(method == "SetPoint", "only SetPoint hooks are stubbed")
      frame._setPointHooks = frame._setPointHooks or {}
      table.insert(frame._setPointHooks, fn)
    end,
    GameTooltip = newFrame("GameTooltip"),
    UISpecialFrames = {},
    Settings = opts.noSettings and {} or {
      RegisterCanvasLayoutCategory = function(panel, name)
        local cat = { panel = panel, name = name, GetID = function() return 42 end }
        M.category = cat
        return cat
      end,
      RegisterAddOnCategory = function() end,
      OpenToCategory = function(id) M.opened = id; M.category.panel._scripts.OnShow(M.category.panel) end,
    },
    C_Timer = { After = function(sec, fn) table.insert(M.timers, { sec, fn }) end },
    -- game
    GetLocale = function() return opts.locale or "frFR" end,
    GetTime = function() return os.clock() end,
    GetBuildInfo = function() return "1.60.1", "12345", "Nov 2026", 16001 end,
    UnitName = function(u) if u == "player" then return "Panda" end end,
    UnitClass = function() return "Mage", "MAGE" end,
    IsInRaid = function() return false end,
    GetNumGroupMembers = function() return 0 end,
    GetItemInfo = function() return nil end,
    GetLootRollItemLink = function(id) return opts.rollLinks and opts.rollLinks[id] end,
    RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } },
    SlashCmdList = {},
    NEED = "Besoin", GREED = "Cupidité", PASS = "Passer",
    -- frFR loot strings
    LOOT_ROLL_NEED = "%s a choisi Besoin pour : %s",
    LOOT_ROLL_GREED = "%s a choisi Cupidité pour : %s",
    LOOT_ROLL_PASSED = "%s a passé pour : %s",
    LOOT_ROLL_PASSED_AUTO = "%s a passé automatiquement pour : %s car il ne peut pas ramasser cet objet.",
    LOOT_ROLL_NEED_SELF = "Vous avez choisi Besoin pour : %s",
    LOOT_ROLL_ROLLED_NEED = "Jet de Besoin - %d pour %s par %s",
    LOOT_ROLL_ROLLED_GREED = "Jet de Cupidité - %d pour %s par %s",
    LOOT_ROLL_WON = "%s a gagné : %s",
    LOOT_ROLL_YOU_WON = "Vous avez gagné : %s",
    LOOT_ROLL_ALL_PASSED = "Tout le monde a passé pour : %s",
    Enum = opts.noEnum and {} or {
      EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 },
    },
    C_LootHistory = opts.lootHistory,
  }
  env._G = env
  setmetatable(env, { __index = _G })

  local ns = {}
  M.category, M.opened = nil, nil
  M.created = {}
  for _, file in ipairs({ "Locales.lua", "Core.lua", "UI.lua", "Options.lua" }) do
    local chunk = assert(loadfile("WhoRolled/" .. file))
    setfenv(chunk, env)
    chunk("WhoRolled", ns)
  end
  M.env = env
  M.fire("ADDON_LOADED", "WhoRolled")
  M.fire("PLAYER_LOGIN")
  return ns, env
end

-- Frames created with a template, in creation order (the options widgets).
function M.widgets(template)
  local t = {}
  for _, c in ipairs(M.created) do
    if c.template == template then t[#t + 1] = c.frame end
  end
  return t
end

function M.fire(event, ...)
  local f = M.registry[event]
  if f then f._scripts.OnEvent(f, event, ...) end
end

function M.runTimers()
  local t = M.timers
  M.timers = {}
  table.sort(t, function(a, b) return a[1] < b[1] end)
  for _, x in ipairs(t) do x[2]() end
end

return M
