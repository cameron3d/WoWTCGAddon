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

T.test("Collection loads, toggles, filters, and previews under the stub", function()
  local ns = {}
  Stub.LoadAddonFile("Core.lua", ns)
  Stub.LoadAddonFile("Data/Cards.lua", ns)
  Stub.LoadAddonFile("PackSystem.lua", ns)
  Stub.LoadAddonFile("ChatFlex.lua", ns)
  Stub.LoadAddonFile("UI/CardWidget.lua", ns)
  Stub.LoadAddonFile("UI/PackOpening.lua", ns)
  Stub.LoadAddonFile("UI/Collection.lua", ns)
  local db = Stub.FreshDB(ns)
  local UI = ns.CollectionUI
  T.ok(type(UI.Toggle) == "function", "Toggle missing")
  UI.Toggle()   -- builds and shows
  UI.Toggle()   -- hides
  UI.Toggle()   -- shows again
  -- filters
  UI.filters.rarity = 6
  T.ok(#UI.FilteredCards() == 10, "rarity filter should isolate the 10 legendaries")
  UI.filters.rarity = 0
  UI.filters.owned = "OWNED"
  T.ok(#UI.FilteredCards() == 0, "empty collection owns nothing")
  db.collection[ns.CARDS[1].id] = 1
  T.ok(#UI.FilteredCards() == 1)
  UI.filters.owned = "ALL"
  -- search must not leak unowned Epic+ names
  local legendary = ns.CardsByRarity[6][1]
  UI.filters.search = legendary.name:lower()
  local found = false
  for _, c in ipairs(UI.FilteredCards()) do
    if c.id == legendary.id then found = true end
  end
  T.ok(not found, "unowned legendary must not appear in search")
  UI.filters.search = ""
  UI.Refresh()
  UI.ShowPreview(ns.CARDS[1])
  T.ok(true)
end)
