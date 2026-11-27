-- Tests for WhoRolled (run from the repo root: busted --lua=lua5.1 spec).
local H = dofile("spec/helpers.lua")

local LINK = "|cff0070dd|Hitem:1234::|h[Épée]|h|r"

local function rollsByName(d)
  local t = {}
  for _, r in ipairs(d.rolls) do t[r.name] = r end
  return t
end

describe("format string compiler", function()
  local ns
  before_each(function() ns = H.load() end)

  it("matches a French loot line and returns arguments in order", function()
    local c = ns.Compile("%s a choisi Besoin pour : %s")
    local a = ns.Match(c, "Niwok Stormfury a choisi Besoin pour : " .. LINK)
    assert.are.equal("Niwok Stormfury", a[1])
    assert.are.equal(LINK, a[2])
  end)

  it("handles %d and positional arguments", function()
    local c = ns.Compile("Jet de Besoin - %d pour %s par %s")
    local a = ns.Match(c, "Jet de Besoin - 77 pour " .. LINK .. " par Zed")
    assert.are.same({ "77", LINK, "Zed" }, a)
    local p = ns.Match(ns.Compile("%2$s pour %1$s"), "B pour A")
    assert.are.equal("A", p[1])
    assert.are.equal("B", p[2])
  end)

  it("escapes magic characters and rejects other lines", function()
    local c = ns.Compile("Gagné (100%%) : %s.")
    assert.is_nil(ns.Match(c, "Autre chose"))
    assert.is_nil(ns.Match(ns.Compile("%s a passé pour : %s"), "Panda reçoit le butin : " .. LINK))
  end)
end)

describe("C_LootHistory source", function()
  local ns, env
  before_each(function()
    ns, env = H.load({
      rollLinks = { [7] = LINK },
      lootHistory = {
        GetSortedInfoForDrop = function()
          return {
            itemHyperlink = LINK,
            rollInfos = {
              { playerName = "Panda", playerClass = "MAGE", state = 3, roll = 40 },
              { playerName = "Niwok", playerClass = "WARRIOR", state = 0, roll = 91, isWinner = true },
              { playerName = "Zed", playerClass = "ROGUE", state = 4 },
            },
            winner = { playerName = "Niwok" },
          }
        end,
        GetInfoForEncounter = function() return { encounterName = "Boss" } end,
      },
    })
  end)

  it("ties the drop to the roll frame and reads every choice", function()
    H.fire("START_LOOT_ROLL", 7, 60)
    H.fire("LOOT_HISTORY_UPDATE_DROP", 100, 3)
    local d = ns.RC:DropForRoll(7)
    assert.is_truthy(d)
    assert.are.equal("Boss", d.encounterName)
    assert.are.equal("Niwok", d.winner)
    local r = rollsByName(d)
    assert.are.equal("greed", r.Panda.state)
    assert.are.equal(40, r.Panda.roll)
    assert.are.equal("need", r.Niwok.state)
    assert.is_true(r.Niwok.winner)
    assert.are.equal("pending", r.Zed.state)
    assert.are.equal(1, #env.WhoRolledDB.history)
  end)

  it("links a drop that arrived before its roll frame", function()
    local get = env.C_LootHistory.GetSortedInfoForDrop
    env.C_LootHistory.GetSortedInfoForDrop = function(...)
      local info = get(...)
      info.winner = nil -- the roll is still open
      info.rollInfos[2].isWinner = nil
      return info
    end
    H.fire("LOOT_HISTORY_UPDATE_DROP", 100, 3)
    H.fire("START_LOOT_ROLL", 7, 60)
    assert.is_truthy(ns.RC:DropForRoll(7))
  end)

  it("does not duplicate a drop on repeated updates", function()
    H.fire("LOOT_HISTORY_UPDATE_DROP", 100, 3)
    H.fire("LOOT_HISTORY_UPDATE_DROP", 100, 3)
    assert.are.equal(1, #env.WhoRolledDB.history)
    assert.are.equal(3, #env.WhoRolledDB.history[1].rolls)
  end)

  it("ignores loot chat while the API is the source", function()
    H.fire("CHAT_MSG_LOOT", "Zed a passé pour : " .. LINK)
    assert.are.equal(0, #env.WhoRolledDB.history)
  end)
end)

describe("chat source", function()
  local ns, env
  before_each(function()
    ns, env = H.load({ rollLinks = { [8] = LINK } }) -- no C_LootHistory: chat is used
  end)

  it("builds a drop from French loot messages", function()
    H.fire("START_LOOT_ROLL", 8, 60)
    for _, m in ipairs({
      "Vous avez choisi Besoin pour : " .. LINK,
      "Niwok Stormfury a choisi Cupidité pour : " .. LINK,
      "Zed a passé automatiquement pour : " .. LINK .. " car il ne peut pas ramasser cet objet.",
      "Jet de Besoin - 77 pour " .. LINK .. " par Panda",
    }) do
      H.fire("CHAT_MSG_LOOT", m)
    end
    H.fire("CANCEL_LOOT_ROLL", 8)
    H.fire("CHAT_MSG_LOOT", "Vous avez gagné : " .. LINK) -- arrives after the roll ended

    local d = ns.RC:DropForRoll(8)
    assert.are.equal(1, #env.WhoRolledDB.history)
    assert.are.equal("Panda", d.winner)
    local r = rollsByName(d)
    assert.are.equal("need", r.Panda.state)
    assert.are.equal(77, r.Panda.roll)
    assert.are.equal("MAGE", r.Panda.class)
    assert.are.equal("greed", r["Niwok Stormfury"].state)
    assert.are.equal("pass", r.Zed.state)
  end)

  it("marks everyone passed", function()
    H.fire("START_LOOT_ROLL", 8, 60)
    H.fire("CHAT_MSG_LOOT", "Tout le monde a passé pour : " .. LINK)
    assert.is_true(ns.RC:DropForRoll(8).allPassed)
  end)

  it("survives GetLootRollItemLink erroring", function()
    env.GetLootRollItemLink = function() error("attempt to call a nil value") end
    assert.has_no.errors(function() H.fire("START_LOOT_ROLL", 9, 60) end)
  end)

  it("ignores ordinary loot lines", function()
    H.fire("CHAT_MSG_LOOT", "Panda reçoit le butin : " .. LINK)
    assert.are.equal(0, #env.WhoRolledDB.history)
  end)
end)

describe("history and commands", function()
  local ns, env
  before_each(function() ns, env = H.load() end)

  it("keeps at most maxHistory drops", function()
    env.WhoRolledDB.settings.maxHistory = 3
    for i = 1, 5 do ns.RC:NewDrop("k" .. i, LINK) end
    assert.are.equal(3, #env.WhoRolledDB.history)
    assert.is_nil(ns.RC.index.k1)
    assert.is_truthy(ns.RC.index.k5)
  end)

  it("waits for your choice, then picks a winner", function()
    env.SlashCmdList.WHOROLLED("test")
    H.runTimers() -- the other players choose
    local d = env.WhoRolledDB.history[1]
    local f = ns.testFrames[1]
    assert.is_true(d.test)
    assert.is_nil(d.winner) -- you have not chosen yet
    f.buttons[1]._scripts.OnClick(f.buttons[1]) -- Need
    local r = rollsByName(d)
    assert.are.equal("need", r.Panda.state)
    assert.is_truthy(d.winner)
    assert.is_true(r[d.winner].winner)
    assert.are.equal("need", r[d.winner].state)
  end)

  it("ignores a second click", function()
    env.SlashCmdList.WHOROLLED("test")
    local f = ns.testFrames[1]
    ns.TestChoose(f, "greed")
    ns.TestChoose(f, "need")
    assert.are.equal("greed", rollsByName(f.drop).Panda.state)
  end)

  it("passes for you when the timer runs out", function()
    env.SlashCmdList.WHOROLLED("test")
    H.runTimers()
    local f = ns.testFrames[1]
    f.deadline = env.GetTime() - 1
    f._scripts.OnUpdate(f)
    local d = f.drop
    assert.are.equal("pass", rollsByName(d).Panda.state)
    assert.are.equal("Célia", d.winner) -- the only need on the first test roll
  end)

  it("runs several test rolls at once", function()
    env.SlashCmdList.WHOROLLED("test 5")
    H.runTimers()
    for i = 1, 5 do ns.TestTimeout(ns.testFrames[i]) end
    local h = env.WhoRolledDB.history
    assert.are.equal(5, #h)
    local items = {}
    for _, d in ipairs(h) do
      assert.is_true(d.test)
      assert.is_true(d.winner ~= nil or d.allPassed == true)
      items[d.itemID] = true
    end
    local n = 0
    for _ in pairs(items) do n = n + 1 end
    assert.are.equal(5, n) -- a different item on each roll
    assert.is_true(h[3].allPassed)
    assert.are.equal("greed", rollsByName(h[2])[h[2].winner].state)
  end)

  it("hides the finished test rolls after a while", function()
    env.SlashCmdList.WHOROLLED("test")
    local f = ns.testFrames[1]
    ns.TestChoose(f, "pass")
    H.runTimers() -- others choose, then the linger timer
    H.runTimers()
    assert.is_false(f:IsShown())
  end)

  it("clamps the number of test rolls", function()
    env.SlashCmdList.WHOROLLED("test 50")
    assert.are.equal(10, #env.WhoRolledDB.history)
    env.SlashCmdList.WHOROLLED("clear")
    env.SlashCmdList.WHOROLLED("test abc")
    assert.are.equal(1, #env.WhoRolledDB.history)
  end)

  it("runs the test roll when GetItemInfo errors (Forever client)", function()
    env.GetItemInfo = function() error("attempt to call a nil value") end
    assert.has_no.errors(function() env.SlashCmdList.WHOROLLED("test") end)
    assert.matches("item:6948", env.WhoRolledDB.history[1].link, 1, true)
  end)

  it("uses C_Item.GetItemInfo when present", function()
    local real = "|cffffffff|Hitem:6948:real|h[Pierre de foyer]|h|r"
    env.C_Item = { GetItemInfo = function() return "Pierre de foyer", real end }
    env.SlashCmdList.WHOROLLED("test")
    assert.are.equal(real, env.WhoRolledDB.history[1].link)
  end)

  it("opens the history window and renders lines", function()
    ns.RC:NewDrop("k", LINK)
    env.SlashCmdList.WHOROLLED("history")
    assert.is_true(env.WhoRolledHistoryFrame:IsShown())
    assert.has_no.errors(function() ns.RenderHistory() end)
  end)

  it("switches source and clears", function()
    env.SlashCmdList.WHOROLLED("source chat")
    assert.are.equal("chat", env.WhoRolledDB.settings.source)
    ns.RC:NewDrop("k", LINK)
    env.SlashCmdList.WHOROLLED("clear")
    assert.are.equal(0, #env.WhoRolledDB.history)
    assert.has_no.errors(function() env.SlashCmdList.WHOROLLED("status") end)
    assert.has_no.errors(function() env.SlashCmdList.WHOROLLED("help") end)
  end)
end)

describe("moving the roll frames", function()
  local ns, env
  before_each(function() ns, env = H.load() end)

  local function dragAnchorTo(x, y)
    local a = env.WhoRolledRollAnchor
    a:ClearAllPoints()
    a:SetPoint("CENTER", env.UIParent, "CENTER", x, y)
    a._scripts.OnDragStop(a)
  end

  it("leaves the game's position alone until moved", function()
    ns.RefreshRollFrames()
    assert.is_false(env.GroupLootContainer._points)
    assert.is_nil(env.WhoRolledDB.settings.rollPos)
  end)

  it("saves the dragged position and pins the container to the anchor", function()
    env.SlashCmdList.WHOROLLED("move")
    assert.is_true(env.WhoRolledRollAnchor:IsShown())
    dragAnchorTo(120, -80)
    assert.are.same({ "CENTER", "CENTER", 120, -80 }, env.WhoRolledDB.settings.rollPos)
    local point, rel = env.GroupLootContainer:GetPoint(1)
    assert.are.equal("BOTTOM", point)
    assert.are.equal(env.WhoRolledRollAnchor, rel)
    env.SlashCmdList.WHOROLLED("move")
    assert.is_false(env.WhoRolledRollAnchor:IsShown())
  end)

  it("puts the container back when the game moves it", function()
    env.SlashCmdList.WHOROLLED("move")
    dragAnchorTo(0, 0)
    env.GroupLootContainer:ClearAllPoints()
    env.GroupLootContainer:SetPoint("BOTTOM", env.UIParent, "BOTTOM", 0, 152)
    local _, rel = env.GroupLootContainer:GetPoint(1)
    assert.are.equal(env.WhoRolledRollAnchor, rel)
    assert.are.equal(1, #env.GroupLootContainer._points)
  end)

  it("moves the first roll frame on clients without a container", function()
    ns, env = H.load({ noContainer = true })
    env.GroupLootFrame1 = env.CreateFrame("Frame", "GroupLootFrame1")
    env.SlashCmdList.WHOROLLED("move")
    dragAnchorTo(10, 10)
    local _, rel = env.GroupLootFrame1:GetPoint(1)
    assert.are.equal(env.WhoRolledRollAnchor, rel)
  end)

  it("forgets the position on reset", function()
    env.SlashCmdList.WHOROLLED("move")
    dragAnchorTo(0, 0)
    env.SlashCmdList.WHOROLLED("reset")
    assert.is_nil(env.WhoRolledDB.settings.rollPos)
  end)
end)

describe("options panel", function()
  local ns, env
  before_each(function() ns, env = H.load() end)

  -- checkboxes in creation order: attach, auto, api, chat, debug
  local function boxes() return H.widgets("UICheckButtonTemplate") end
  local function click(cb, checked)
    cb:SetChecked(checked)
    cb._scripts.OnClick(cb)
  end

  it("registers a WhoRolled category and opens it from the add-on menu", function()
    assert.are.equal("WhoRolled", H.category.name)
    env.WhoRolled_OnAddonCompartmentClick("WhoRolled", "LeftButton")
    assert.are.equal(42, H.opened)
  end)

  it("opens the history on a right click in the add-on menu", function()
    env.WhoRolled_OnAddonCompartmentClick("WhoRolled", "RightButton")
    assert.is_nil(H.opened)
    assert.is_true(env.WhoRolledHistoryFrame:IsShown())
  end)

  it("/whorolled opens the options", function()
    env.SlashCmdList.WHOROLLED("")
    assert.are.equal(42, H.opened)
  end)

  it("shows the saved settings when opened", function()
    env.WhoRolledDB.settings.attach = false
    env.WhoRolledDB.settings.source = "chat"
    ns.OpenOptions()
    local b = boxes()
    assert.are.equal(5, #b)
    assert.is_false(b[1]:GetChecked())
    assert.is_false(b[2]:GetChecked())
    assert.is_true(b[4]:GetChecked())
  end)

  it("changes settings from the checkboxes", function()
    ns.OpenOptions()
    local b = boxes()
    click(b[1], false)
    assert.is_false(env.WhoRolledDB.settings.attach)
    click(b[3], true)
    assert.are.equal("api", env.WhoRolledDB.settings.source)
    assert.is_false(b[2]:GetChecked()) -- radio behaviour
    click(b[5], true)
    assert.is_true(env.WhoRolledDB.settings.debug)
  end)

  it("trims the history from the slider", function()
    for i = 1, 120 do ns.RC:NewDrop("k" .. i, LINK) end
    ns.OpenOptions()
    local slider = H.widgets("OptionsSliderTemplate")[2] -- 1: result time, 2: history
    slider:SetValue(52) -- snapped to 50
    assert.are.equal(50, env.WhoRolledDB.settings.maxHistory)
    assert.are.equal(50, #env.WhoRolledDB.history)
  end)

  it("sets how long the result stays", function()
    ns.OpenOptions()
    local slider = H.widgets("OptionsSliderTemplate")[1]
    slider:SetValue(25.4)
    assert.are.equal(25, env.WhoRolledDB.settings.resultTime)
  end)

  it("move button unlocks then locks the anchor", function()
    ns.OpenOptions()
    local move = H.widgets("UIPanelButtonTemplate")[1]
    move._scripts.OnClick(move)
    assert.is_true(ns.IsMoving())
    move._scripts.OnClick(move)
    assert.is_false(ns.IsMoving())
  end)

  it("test buttons play one and five rolls", function()
    ns.OpenOptions()
    -- buttons in creation order: move, reset position, test, test x5, history, clear
    local b = H.widgets("UIPanelButtonTemplate")
    assert.are.equal("Jet de test x5", b[4]:GetText())
    b[3]._scripts.OnClick(b[3])
    assert.are.equal(1, #env.WhoRolledDB.history)
    b[4]._scripts.OnClick(b[4])
    assert.are.equal(6, #env.WhoRolledDB.history)
  end)

  it("says so when the client has no Settings panel", function()
    ns, env = H.load({ noSettings = true })
    env.SlashCmdList.WHOROLLED("")
    assert.is_nil(H.opened)
    assert.matches("options", H.printed[#H.printed])
  end)
end)

describe("test roll window", function()
  it("test 5 shows a common, uncommon, rare and epic item, then a crafting material", function()
    local ns, env = H.load()
    env.SlashCmdList.WHOROLLED("test 5")
    local ids = {}
    for i = 1, 5 do ids[i] = tonumber(ns.testFrames[i].link:match("item:(%d+)")) end
    assert.are.same({ 6948, 1121, 6504, 18832 }, { ids[1], ids[2], ids[3], ids[4] })
    local crafts = { [2770] = true, [2589] = true, [4306] = true, [4338] = true, [765] = true, [2447] = true }
    assert.is_true(crafts[ids[5]])
    assert.matches("^|cffa3", ns.testFrames[4].link) -- epic purple when the game has no item info
  end)

  it("is drawn at the game's roll window size, with playable Need / Greed / Pass buttons", function()
    local ns, env = H.load()
    env.SlashCmdList.WHOROLLED("test")
    local f = ns.testFrames[1]
    local w, h = f:GetSize()
    assert.are.same({ 277, 67 }, { w, h })
    assert.are.equal(3, #f.buttons)
    H.runTimers()
    local need = f.buttons[1]
    assert.has_no.errors(function() need._scripts.OnClick(need) end) -- no real roll
    assert.are.equal("need", rollsByName(f.drop).Panda.state)
    assert.is_truthy(f.drop.winner)
    assert.matches("gagne", ns.bars[f].text:GetText(), 1, true)
  end)
end)

describe("bar under each roll", function()
  local ns, env
  before_each(function() ns, env = H.load() end)

  local function bar(i) return ns.bars[ns.testFrames[i or 1]] end

  it("says how many players are choosing when the roll appears", function()
    env.SlashCmdList.WHOROLLED("test")
    assert.are.equal("5 joueurs choisissent", bar().text:GetText())
    local _, rel, relPoint = bar():GetPoint(1)
    assert.are.equal(ns.testFrames[1], rel)
    assert.are.equal("BOTTOMLEFT", relPoint)
  end)

  it("uses the group size before any data arrived", function()
    env.GetNumGroupMembers = function() return 3 end
    local f = env.CreateFrame("Frame")
    ns.UpdateRollFrame(f, nil)
    assert.are.equal("3 joueurs choisissent", ns.bars[f].text:GetText())
    env.GetNumGroupMembers = function() return 0 end
    ns.UpdateRollFrame(f, nil)
    assert.are.equal("1 joueur choisit", ns.bars[f].text:GetText())
  end)

  it("counts the choices with the roll icons", function()
    env.SlashCmdList.WHOROLLED("test")
    H.runTimers() -- roll 1: Arwyn pass, Brogar pass, Célia need, Dorn greed
    local text = bar().text:GetText()
    assert.matches(ns.STATE_ICON.need .. " 1", text, 1, true)
    assert.matches(ns.STATE_ICON.greed .. " 1", text, 1, true)
    assert.matches(ns.STATE_ICON.pass .. " 2", text, 1, true)
  end)

  it("shows the winner, their roll and their choice", function()
    env.SlashCmdList.WHOROLLED("test")
    H.runTimers()
    ns.TestChoose(ns.testFrames[1], "pass")
    local d = ns.testFrames[1].drop
    local text = bar().text:GetText()
    assert.matches("Célia", text, 1, true)
    assert.matches("gagne " .. rollsByName(d)["Célia"].roll, text, 1, true)
    assert.matches(ns.STATE_ICON.need, text, 1, true)
  end)

  it("says when everyone passed", function()
    env.SlashCmdList.WHOROLLED("test 3")
    H.runTimers()
    ns.TestChoose(ns.testFrames[3], "pass")
    assert.matches("Tout le monde a passé", bar(3).text:GetText(), 1, true)
  end)

  it("stays when the roll frame goes away, and hides after the result time", function()
    env.WhoRolledDB.settings.resultTime = 7
    env.SlashCmdList.WHOROLLED("test")
    local f = ns.testFrames[1]
    f:Hide()
    f._scripts.OnHide(f) -- the game hides the roll frame when you choose
    assert.is_true(bar():IsShown())
    assert.are.equal(env.UIParent, select(2, bar():GetPoint(1))) -- detached, in place
    H.timers = {}
    ns.TestChoose(f, "pass") -- others have not chosen yet
    for _, c in ipairs({ "Arwyn", "Brogar", "Célia", "Dorn" }) do ns.RC:SetRoll(f.drop, c, nil, "pass") end
    ns.TestTimeout(f) -- result: everyone passed
    local delays = {}
    for _, t in ipairs(H.timers) do delays[t[1]] = true end
    assert.is_true(delays[7])
    H.runTimers()
    assert.is_false(bar():IsShown())
  end)

  it("shows who chose what on click, and hides it on a second click", function()
    env.SlashCmdList.WHOROLLED("test")
    H.runTimers()
    local b = bar()
    b._scripts.OnClick(b)
    assert.is_true(b.list:IsShown())
    assert.are.equal(5, b.list.shownEntries) -- 4 players + you still choosing
    b._scripts.OnClick(b)
    assert.is_false(b.list:IsShown())
  end)

  it("keeps the detail list up to date while open", function()
    env.SlashCmdList.WHOROLLED("test")
    local b = bar()
    b._scripts.OnClick(b)
    assert.are.equal(1, b.list.shownEntries) -- everyone still choosing
    H.runTimers()
    assert.are.equal(5, b.list.shownEntries)
  end)

  it("leaves room for the bar between stacked test rolls", function()
    env.SlashCmdList.WHOROLLED("test 2")
    local y1 = select(5, ns.testFrames[1]:GetPoint(1))
    local y2 = select(5, ns.testFrames[2]:GetPoint(1))
    local _, h = ns.testFrames[1]:GetSize()
    assert.is_true(y2 - y1 >= h + 22) -- frame + bar, no overlap
    assert.are.equal(100, y2 - y1) -- the game's own slot height
  end)

  it("goes away when turned off", function()
    env.SlashCmdList.WHOROLLED("test")
    env.SlashCmdList.WHOROLLED("attach")
    assert.is_false(bar():IsShown())
  end)

  it("shows under the game's roll frames", function()
    local frame = env.CreateFrame("Frame", "GroupLootFrame1")
    frame.rollID = 7
    env.GetLootRollItemLink = function() return LINK end
    env.WhoRolledDB.settings.source = "chat"
    H.fire("START_LOOT_ROLL", 7, 60)
    ns.RefreshRollFrames()
    H.fire("CHAT_MSG_LOOT", "Zed a passé pour : " .. LINK)
    assert.matches(ns.STATE_ICON.pass .. " 1", ns.bars[frame].text:GetText(), 1, true)
  end)

  it("shows under Forever's roll windows (GroupLootContainer.rollFrames)", function()
    local frame = env.CreateFrame("Frame")
    frame.rollID = 8
    env.GroupLootContainer.rollFrames = { frame }
    env.GroupLootContainer_Update = function() end
    env.GetLootRollItemLink = function() return LINK end
    env.WhoRolledDB.settings.source = "chat"
    H.fire("START_LOOT_ROLL", 8, 60)
    ns.RefreshRollFrames()
    assert.is_function(H.globalHooks.GroupLootContainer_Update)
    H.fire("CHAT_MSG_LOOT", "Zed a passé pour : " .. LINK)
    assert.matches(ns.STATE_ICON.pass .. " 1", ns.bars[frame].text:GetText(), 1, true)
  end)
end)
