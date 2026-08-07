local Stub = require("wow_api_stub")
local T = require("testkit")

T.test("CardWidget loads and handles all display modes under the stub", function()
  local ns = {}
  Stub.LoadAddonFile("Core.lua", ns)
  Stub.LoadAddonFile("Data/Cards.lua", ns)
  Stub.LoadAddonFile("UI/CardWidget.lua", ns)
  Stub.FreshDB(ns)
  T.ok(type(ns.CreateCardWidget) == "function", "CreateCardWidget missing")
  local w = ns.CreateCardWidget(UIParent)
  w:SetCard(ns.CARDS[1], {})
  w:SetCard(ns.CARDS[1], { count = 3, isNew = true })
  w:SetCard(ns.CARDS[1], { faceDown = true })
  w:SetCard(ns.CARDS[1], { silhouette = true })
  T.ok(true)
end)

T.test("PackOpening loads and opens a pack under the stub", function()
  local ns = {}
  Stub.LoadAddonFile("Core.lua", ns)
  Stub.LoadAddonFile("Data/Cards.lua", ns)
  Stub.LoadAddonFile("PackSystem.lua", ns)
  Stub.LoadAddonFile("ChatFlex.lua", ns)
  Stub.LoadAddonFile("UI/CardWidget.lua", ns)
  Stub.LoadAddonFile("UI/PackOpening.lua", ns)
  local db = Stub.FreshDB(ns)
  T.ok(type(ns.PackUI.Open) == "function", "PackUI.Open missing")
  ns.PackUI.Open()          -- zero packs: prints error, no crash
  db.packs = 1
  ns.rng = function(n) return math.min(30, n) end
  ns.PackUI.Open()
  ns.rng = nil
  T.eq(db.packs, 0, "pack should be consumed")
  ns.PackUI.RevealAll()     -- reveal-all path must not error
  T.ok(true)
end)
