local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)
Stub.LoadAddonFile("Data/Cards.lua", ns)

local EXPECTED = { [1] = 40, [2] = 90, [3] = 80, [4] = 55, [5] = 25, [6] = 10 }

T.test("card count is 300 with the exact rarity distribution", function()
  T.eq(#ns.CARDS, 300, "total cards")
  local counts = { 0, 0, 0, 0, 0, 0 }
  for _, c in ipairs(ns.CARDS) do counts[c.rarity] = counts[c.rarity] + 1 end
  for r = 1, 6 do T.eq(counts[r], EXPECTED[r], "rarity " .. r .. " count") end
end)

T.test("every card is well-formed with a unique id", function()
  local seen = {}
  for _, c in ipairs(ns.CARDS) do
    T.ok(type(c.id) == "number", "id must be a number")
    T.ok(not seen[c.id], "duplicate id " .. tostring(c.id))
    seen[c.id] = true
    T.ok(type(c.name) == "string" and #c.name > 0, "name for id " .. tostring(c.id))
    T.ok(c.rarity >= 1 and c.rarity <= 6, "rarity for id " .. tostring(c.id))
    T.ok(c.type == "SPELL" or c.type == "NPC" or c.type == "ITEM", "type for id " .. tostring(c.id))
    T.ok(type(c.icon) == "string" and c.icon:find("^Interface\\Icons\\") ~= nil,
      "icon path for id " .. tostring(c.id))
    T.ok(type(c.flavor) == "string" and #c.flavor > 0, "flavor for id " .. tostring(c.id))
  end
end)

T.test("lookup indexes are consistent", function()
  local n = 0
  for r = 1, 6 do n = n + #ns.CardsByRarity[r] end
  T.eq(n, #ns.CARDS, "CardsByRarity total")
  for _, c in ipairs(ns.CARDS) do
    T.eq(ns.CardsById[c.id], c, "CardsById for " .. tostring(c.id))
  end
end)

T.test("every tier contains all three card types", function()
  for r = 1, 6 do
    local types = {}
    for _, c in ipairs(ns.CardsByRarity[r]) do types[c.type] = true end
    T.ok(types.SPELL and types.NPC and types.ITEM, "tier " .. r .. " is missing a type")
  end
end)

T.test("card names are unique", function()
  local seen = {}
  for _, c in ipairs(ns.CARDS) do
    T.ok(not seen[c.name], "duplicate name " .. c.name)
    seen[c.name] = true
  end
end)
