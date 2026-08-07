local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)
Stub.LoadAddonFile("PointsEngine.lua", ns)
local PE = ns.PointsEngine

PE.Register()

local function fresh()
  Stub.ResetCaptures()
  return Stub.FreshDB(ns)
end

T.test("PatternFromFormat converts %s and %d and anchors", function()
  local p = PE.PatternFromFormat("Discovered %s: %d experience gained")
  T.ok(("Discovered Elwynn Forest: 25 experience gained"):find(p) ~= nil, "should match")
  T.ok(("Random message"):find(p) == nil, "should not match")
  local p2 = PE.PatternFromFormat("Discovered %s")
  T.ok(("Discovered Westfall"):find(p2) ~= nil)
end)

T.test("quest turn-in awards 25", function()
  local db = fresh()
  Stub.FireEvent("QUEST_TURNED_IN", 123, 4500, 50)
  T.eq(db.points, 25)
  T.eq(db.stats.byReason.QUEST, 25)
end)

T.test("own PARTY_KILL awards 2; others' kills and other subevents award 0", function()
  local db = fresh()
  Stub.combatLog = { 0, "PARTY_KILL", false, "Player-1", "Tester", 0x511, 0, "Creature-1", "Hogger", 0x10a48, 0 }
  Stub.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
  T.eq(db.points, 2)
  Stub.combatLog = { 0, "PARTY_KILL", false, "Player-2", "Buddy", 0x512, 0, "Creature-1", "Hogger", 0x10a48, 0 }
  Stub.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
  T.eq(db.points, 2, "party member kill must not award")
  Stub.combatLog = { 0, "SPELL_DAMAGE", false, "Player-1", "Tester", 0x511, 0, "Creature-1", "Hogger", 0x10a48, 0 }
  Stub.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
  T.eq(db.points, 2, "non-kill subevent must not award")
end)

T.test("honor gain awards 5", function()
  local db = fresh()
  Stub.FireEvent("CHAT_MSG_COMBAT_HONOR_GAIN",
    "Enemy dies, honorable kill Rank: Grunt (Estimated Honor Points: 12)")
  T.eq(db.points, 5)
end)

T.test("boss kill awards 50 only on success", function()
  local db = fresh()
  Stub.FireEvent("ENCOUNTER_END", 663, "Lucifron", 9, 40, 0)
  T.eq(db.points, 0, "wipe must not award")
  Stub.FireEvent("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
  T.eq(db.points, 50)
end)

T.test("exploration awards 10 for discovery messages only", function()
  local db = fresh()
  Stub.FireEvent("UI_INFO_MESSAGE", 42, "Discovered Westfall")
  T.eq(db.points, 10)
  Stub.FireEvent("UI_INFO_MESSAGE", 43, "Your equipment is damaged")
  T.eq(db.points, 10, "non-discovery message must not award")
end)

T.test("level up awards 100", function()
  local db = fresh()
  Stub.FireEvent("PLAYER_LEVEL_UP", 23)
  T.eq(db.points, 100)
end)

T.test("events are harmless before InitDB", function()
  local saved = ns.db
  ns.db = nil
  Stub.FireEvent("QUEST_TURNED_IN", 1, 0, 0)  -- must not error
  ns.db = saved
  T.ok(true)
end)
