local _, ns = ...
local L = ns.L

-- Options page in the game's Settings panel (Options -> AddOns -> WhoRolled), also opened by
-- /whorolled and by the add-on menu by the minimap (WhoRolled_OnAddonCompartmentClick in Core.lua).
-- Built the same way as GroupChevron's: a canvas category with plain widgets.

local category
local controls = {} -- refreshed from the saved settings each time the page is shown
local refreshing = false

local function Version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if type(get) ~= "function" then return end
  local ok, v = pcall(get, "WhoRolled", "Version")
  return ok and v or nil
end

-- The Settings panel covers the middle of the screen: close it before showing something there.
local function CloseSettings()
  local panel = _G.SettingsPanel
  if panel and panel.IsShown and panel:IsShown() then
    if HideUIPanel then pcall(HideUIPanel, panel) else panel:Hide() end
  end
end

local function Refresh()
  refreshing = true
  local s = WhoRolledDB.settings
  for _, c in ipairs(controls) do c(s) end
  refreshing = false
end

local function Build()
  if type(Settings) ~= "table" or type(Settings.RegisterCanvasLayoutCategory) ~= "function"
    or type(Settings.RegisterAddOnCategory) ~= "function" then
    return
  end

  local panel = CreateFrame("Frame")
  panel.name = "WhoRolled"
  panel:SetScript("OnShow", Refresh)

  local y = -16
  local function Label(text, x, yy, template)
    local fs = panel:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, yy)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
  end

  local function Header(text)
    y = y - 16
    Label(text, 16, y, "GameFontNormal")
    y = y - 22
  end

  local function Checkbox(text, get, set)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    Label(text, 48, y - 6)
    cb:SetScript("OnClick", function(self)
      if not refreshing then set(self:GetChecked() and true or false) end
    end)
    controls[#controls + 1] = function(s) cb:SetChecked(get(s)) end
    y = y - 28
    return cb
  end

  local function Button(text, x, width, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width or 180, 24)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end

  local version = Version()
  Label("WhoRolled" .. (version and (" " .. version) or ""), 16, y, "GameFontNormalLarge")
  y = y - 26
  local intro = Label(L.OPT_INTRO, 16, y)
  intro:SetWidth(580)
  y = y - 36

  -- Display
  Header(L.OPT_DISPLAY)
  Checkbox(L.OPT_ATTACH, function(s) return s.attach end, ns.SetAttach)
  Checkbox(L.OPT_EXPANDED, function(s) return s.expanded end, ns.SetExpanded)
  y = y - 4
  local moveButton
  moveButton = Button(L.OPT_MOVE, 16, 200, function()
    if ns.IsMoving() then
      ns.ToggleMove() -- lock
      moveButton:SetText(L.OPT_MOVE)
    else
      CloseSettings()
      ns.ToggleMove()
    end
  end)
  Button(L.OPT_RESET_POS, 224, 160, function() ns.ResetRollPosition() end)
  controls[#controls + 1] = function()
    moveButton:SetText(ns.IsMoving() and L.OPT_LOCK or L.OPT_MOVE)
  end
  y = y - 30
  -- on their own row: four buttons do not fit the width of the Settings panel
  Button(L.OPT_TEST, 16, 200, function()
    CloseSettings()
    ns.RunTest(1)
  end)
  Button(L.OPT_TEST_5, 224, 160, function()
    CloseSettings()
    ns.RunTest(5)
  end)
  y = y - 32

  -- History
  Header(L.OPT_HISTORY)
  Button(L.OPT_OPEN_HISTORY, 16, 200, function()
    CloseSettings()
    ns.ToggleHistory()
  end)
  Button(L.OPT_CLEAR, 224, 160, function()
    if StaticPopup_Show and StaticPopupDialogs then
      StaticPopupDialogs.WHOROLLED_CLEAR = StaticPopupDialogs.WHOROLLED_CLEAR or {
        text = L.OPT_CLEAR_CONFIRM,
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function() ns.ClearHistory() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
      }
      StaticPopup_Show("WHOROLLED_CLEAR")
    else
      ns.ClearHistory()
    end
  end)
  y = y - 40

  Label(L.OPT_MAX_HISTORY, 16, y)
  local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", panel, "TOPLEFT", 160, y - 2)
  slider:SetWidth(220)
  slider:SetMinMaxValues(50, 500)
  slider:SetValueStep(50)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  for _, key in ipairs({ "Low", "High", "Text" }) do
    if type(slider[key]) == "table" and slider[key].SetText then slider[key]:SetText("") end
  end
  local value = Label("", 392, y)
  slider:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / 50 + 0.5) * 50
    value:SetText(v)
    if not refreshing and v ~= WhoRolledDB.settings.maxHistory then ns.SetMaxHistory(v) end
  end)
  controls[#controls + 1] = function(s)
    slider:SetValue(s.maxHistory)
    value:SetText(s.maxHistory)
  end
  y = y - 34

  -- Data source: three checkboxes acting as radio buttons
  Header(L.OPT_DATA)
  local sources = { { "auto", L.OPT_SOURCE_AUTO }, { "api", L.OPT_SOURCE_API }, { "chat", L.OPT_SOURCE_CHAT } }
  for _, src in ipairs(sources) do
    Checkbox(src[2], function(s) return s.source == src[1] end, function()
      ns.SetSource(src[1])
      Refresh()
    end)
  end
  local inUse = Label("", 48, y - 2, "GameFontDisableSmall")
  controls[#controls + 1] = function()
    inUse:SetText(L.OPT_IN_USE:format(ns.RC:UseAPI() and L.OPT_SOURCE_API or L.OPT_SOURCE_CHAT))
  end
  y = y - 24
  Checkbox(L.OPT_DEBUG, function(s) return s.debug end, ns.SetDebug)

  category = Settings.RegisterCanvasLayoutCategory(panel, "WhoRolled")
  Settings.RegisterAddOnCategory(category)
  ns.optionsPanel = panel
end

function ns.BuildOptions()
  if category then return end
  local ok, err = pcall(Build)
  if not ok then ns.Debug("options panel:", err) end
end

function ns.OpenOptions()
  if not category or type(Settings) ~= "table" or type(Settings.OpenToCategory) ~= "function" then
    ns.Print(L.OPT_UNAVAILABLE)
    return
  end
  local id = category.GetID and category:GetID()
  if id == nil or not pcall(Settings.OpenToCategory, id) then
    ns.Print(L.OPT_COMBAT)
  end
end
