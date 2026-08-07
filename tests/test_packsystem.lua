local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)
Stub.LoadAddonFile("Data/Cards.lua", ns)
Stub.LoadAddonFile("PackSystem.lua", ns)
local PS = ns.PackSystem

-- Deterministic RNG for tests. Uses high bits (low LCG bits are weak).
local function lcg(seed)
  local s = seed
  return function(n)
    s = (s * 1103515245 + 12345) % 2147483648
    return (math.floor(s / 65536) % n) + 1
  end
end

-- Always returns min(v, n): pins rarity rolls while staying in range for card picks.
local function fixedRoll(v)
  return function(n) return math.min(v, n) end
end

local function bestOf(cards)
  local best = 0
  for _, c in ipairs(cards) do best = math.max(best, c.rarity) end
  return best
end

T.test("RollRarity matches weights over 100k rolls", function()
  ns.rng = lcg(42)
  local counts = { 0, 0, 0, 0, 0, 0 }
  local N = 100000
  for _ = 1, N do
    local r = PS.RollRarity()
    counts[r] = counts[r] + 1
  end
  ns.rng = nil
  for r = 1, 6 do
    local pct = counts[r] / N * 100
    T.ok(math.abs(pct - ns.RARITY_WEIGHTS[r]) < 1.5,
      string.format("rarity %d: got %.2f%%, want %d%%", r, pct, ns.RARITY_WEIGHTS[r]))
  end
end)

T.test("pack floor guarantees at least one Uncommon+", function()
  ns.rng = fixedRoll(10)  -- always rolls Junk
  local db = Stub.FreshDB(ns)
  local cards = PS.RollPack(db)
  ns.rng = nil
  T.eq(#cards, 5)
  T.ok(bestOf(cards) >= 3, "floored pack must contain an Uncommon+")
end)

T.test("epic pity forces Epic+ on the 10th barren pack and resets", function()
  ns.rng = fixedRoll(30)  -- always rolls Common
  local db = Stub.FreshDB(ns)
  for i = 1, 9 do
    T.ok(bestOf(PS.RollPack(db)) < 5, "unexpected Epic before pity, pack " .. i)
  end
  T.eq(db.pity.epic, 9)
  T.ok(bestOf(PS.RollPack(db)) >= 5, "10th pack must contain Epic+")
  T.eq(db.pity.epic, 0, "epic pity must reset")
  ns.rng = nil
end)

T.test("legendary pity forces a Legendary on the 40th pack and resets", function()
  ns.rng = fixedRoll(30)
  local db = Stub.FreshDB(ns)
  for i = 1, 39 do
    local cards = PS.RollPack(db)
    for _, c in ipairs(cards) do
      T.ok(c.rarity < 6, "unexpected Legendary at pack " .. i)
    end
  end
  T.eq(db.pity.legendary, 39)
  T.eq(bestOf(PS.RollPack(db)), 6, "40th pack must contain a Legendary")
  T.eq(db.pity.legendary, 0)
  ns.rng = nil
end)

T.test("BuyPack requires 100 points", function()
  local db = Stub.FreshDB(ns)
  db.points = 99
  T.eq(PS.BuyPack(db), false)
  db.points = 150
  T.eq(PS.BuyPack(db), true)
  T.eq(db.points, 50)
  T.eq(db.packs, 1)
end)

T.test("OpenPack consumes a pack and fills the collection", function()
  ns.rng = lcg(7)
  local db = Stub.FreshDB(ns)
  T.eq(PS.OpenPack(db), nil, "opening with zero packs must fail")
  db.packs = 1
  local results = PS.OpenPack(db)
  ns.rng = nil
  T.eq(#results, 5)
  T.eq(db.packs, 0)
  T.eq(db.stats.packsOpened, 1)
  for _, r in ipairs(results) do
    T.ok(db.collection[r.card.id] >= 1, "card not in collection")
    T.ok(r.count >= 1)
  end
end)

T.test("first pull is new, repeat pull is a dupe with a count", function()
  local db = Stub.FreshDB(ns)
  db.packs = 2
  ns.rng = fixedRoll(1)  -- same cards every pack
  local first = PS.OpenPack(db)
  local second = PS.OpenPack(db)
  ns.rng = nil
  T.eq(first[1].isNew, true)
  T.eq(second[1].isNew, false)
  T.ok(second[1].count > 1, "dupe must have count > 1")
end)

T.test("DustCard: never the last copy, value by rarity", function()
  local db = Stub.FreshDB(ns)
  local card = ns.CardsByRarity[6][1]
  db.collection[card.id] = 1
  T.eq(PS.DustCard(db, card.id), false, "cannot dust the last copy")
  db.collection[card.id] = 3
  local ok, value = PS.DustCard(db, card.id)
  T.eq(ok, true)
  T.eq(value, 150)
  T.eq(db.collection[card.id], 2)
  T.eq(db.points, 150)
end)

T.test("DustAllDupes leaves one of each and sums values", function()
  local db = Stub.FreshDB(ns)
  local c1 = ns.CardsByRarity[1][1]
  local c6 = ns.CardsByRarity[6][1]
  db.collection[c1.id] = 4   -- 3 junk dupes  -> 3 points
  db.collection[c6.id] = 2   -- 1 legendary dupe -> 150 points
  T.eq(PS.DustAllDupes(db), 153)
  T.eq(db.collection[c1.id], 1)
  T.eq(db.collection[c6.id], 1)
  T.eq(db.points, 153)
end)

T.test("forceLegendary debug flag guarantees a Legendary once", function()
  ns.rng = fixedRoll(30)
  local db = Stub.FreshDB(ns)
  ns.forceLegendary = true
  T.eq(bestOf(PS.RollPack(db)), 6)
  T.ok(not ns.forceLegendary, "flag must clear after use")
  ns.rng = nil
end)

T.test("CompletionStats counts owned per rarity", function()
  local db = Stub.FreshDB(ns)
  db.collection[ns.CardsByRarity[2][1].id] = 1
  db.collection[ns.CardsByRarity[2][2].id] = 3
  local owned, total, byRarity = PS.CompletionStats(db)
  T.eq(owned, 2)
  T.eq(total, 300)
  T.eq(byRarity[2].owned, 2)
  T.eq(byRarity[2].total, 90)
end)
