local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)

T.test("DeepFill fills missing keys and preserves existing", function()
  local dst = { a = 1, sub = { x = 5 } }
  ns.DeepFill(dst, { a = 9, b = 2, sub = { x = 0, y = 3 } })
  T.eq(dst.a, 1); T.eq(dst.b, 2); T.eq(dst.sub.x, 5); T.eq(dst.sub.y, 3)
end)

T.test("InitDB creates defaults", function()
  local db = Stub.FreshDB(ns)
  T.eq(db.points, 0); T.eq(db.packs, 0); T.eq(db.version, 1)
  T.eq(db.settings.announceChannel, "OFF")
  T.eq(db.settings.announceMinRarity, 5)
  T.eq(db.pity.epic, 0); T.eq(db.pity.legendary, 0)
end)

T.test("InitDB preserves existing values and backfills the rest", function()
  _G.WoWTCG_DB = { points = 42, settings = { announceChannel = "GUILD" } }
  local db = ns.InitDB()
  T.eq(db.points, 42)
  T.eq(db.settings.announceChannel, "GUILD")
  T.eq(db.settings.sounds, true)
end)

T.test("AddPoints accumulates and tracks reasons", function()
  local db = Stub.FreshDB(ns)
  ns.AddPoints(25, "QUEST"); ns.AddPoints(2, "KILL"); ns.AddPoints(25, "QUEST")
  T.eq(db.points, 52)
  T.eq(db.stats.totalPoints, 52)
  T.eq(db.stats.byReason.QUEST, 50)
  T.eq(db.stats.byReason.KILL, 2)
end)

T.test("AddPoints ignores nil, zero, and negative amounts", function()
  local db = Stub.FreshDB(ns)
  ns.AddPoints(nil, "X"); ns.AddPoints(0, "X"); ns.AddPoints(-5, "X")
  T.eq(db.points, 0)
end)

T.test("rarity tables cover all six tiers", function()
  T.eq(#ns.RARITY_NAMES, 6)
  T.eq(ns.RARITY_COLORS[6].hex, "ff8000")
  T.eq(ns.DUST_VALUES[6], 150)
end)
