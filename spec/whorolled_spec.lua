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

  it("runs the test roll to a winner", function()
    env.SlashCmdList.WHOROLLED("test")
    H.runTimers()
    local d = env.WhoRolledDB.history[1]
    assert.is_true(d.test)
    assert.are.equal("Dorn", d.winner)
  end)

  it("opens the history window and renders lines", function()
    ns.RC:NewDrop("k", LINK)
    env.SlashCmdList.WHOROLLED("")
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
