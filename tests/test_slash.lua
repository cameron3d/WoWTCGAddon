local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)
Stub.LoadAddonFile("Data/Cards.lua", ns)
Stub.LoadAddonFile("PackSystem.lua", ns)

local toggled = 0
ns.CollectionUI = { Toggle = function() toggled = toggled + 1 end, Refresh = function() end }
ns.PackUI = { Open = function() end }

T.test("/tcg with no args toggles the collection", function()
  Stub.FreshDB(ns)
  ns.HandleSlash("")
  T.eq(toggled, 1)
end)

T.test("/tcg buy fails when broke, works at 100 points", function()
  local db = Stub.FreshDB(ns)
  ns.HandleSlash("buy")
  T.eq(db.packs, 0)
  db.points = 100
  ns.HandleSlash("buy")
  T.eq(db.packs, 1)
  T.eq(db.points, 0)
end)

T.test("/tcg debug points grants points", function()
  local db = Stub.FreshDB(ns)
  ns.HandleSlash("debug points 250")
  T.eq(db.points, 250)
end)

T.test("/tcg debug pack grants a pack, legendary sets the flag", function()
  local db = Stub.FreshDB(ns)
  ns.HandleSlash("debug pack")
  T.eq(db.packs, 1)
  ns.HandleSlash("debug legendary")
  T.eq(ns.forceLegendary, true)
  ns.forceLegendary = nil
end)

T.test("/tcg config announce validates channels", function()
  local db = Stub.FreshDB(ns)
  ns.HandleSlash("config announce guild")
  T.eq(db.settings.announceChannel, "GUILD")
  ns.HandleSlash("config announce bogus")
  T.eq(db.settings.announceChannel, "GUILD", "invalid channel must not stick")
  ns.HandleSlash("config minrarity 4")
  T.eq(db.settings.announceMinRarity, 4)
  ns.HandleSlash("config sounds off")
  T.eq(db.settings.sounds, false)
end)

T.test("/tcg debug wipe resets the DB (stub auto-accepts the popup)", function()
  local db = Stub.FreshDB(ns)
  db.points = 500
  db.collection[100] = 3
  ns.HandleSlash("debug wipe")
  T.eq(WoWTCG_DB.points, 0)
  T.eq(next(WoWTCG_DB.collection), nil)
end)

T.test("slash command is registered", function()
  T.eq(SLASH_WOWTCG1, "/tcg")
  T.ok(type(SlashCmdList["WOWTCG"]) == "function")
end)

T.test("minimap button builds without error", function()
  Stub.FreshDB(ns)
  ns.SetupMinimapButton()
  T.ok(_G.WoWTCGMinimapButton ~= nil)
end)
