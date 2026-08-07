local ADDON_NAME, ns = ...

local PackSystem = {}
ns.PackSystem = PackSystem

ns.RARITY_WEIGHTS = { 20, 45, 20, 10, 4, 1 }  -- percent per tier; sums to 100
ns.PITY_EPIC      = 10
ns.PITY_LEGENDARY = 40

-- Tests override ns.rng with a deterministic function.
local function rng(n)
  return (ns.rng or math.random)(n)
end

function PackSystem.RollRarity()
  local roll, acc = rng(100), 0
  for rarity = 1, 6 do
    acc = acc + ns.RARITY_WEIGHTS[rarity]
    if roll <= acc then return rarity end
  end
  return 1
end

function PackSystem.PickCard(rarity)
  local pool = ns.CardsByRarity[rarity]
  while (not pool or #pool == 0) and rarity > 1 do
    rarity = rarity - 1
    pool = ns.CardsByRarity[rarity]
  end
  return pool[rng(#pool)]
end

local function Best(rarities)
  local b = 0
  for i = 1, #rarities do if rarities[i] > b then b = rarities[i] end end
  return b
end

local function LowestSlot(rarities)
  local slot, lo = 1, rarities[1]
  for i = 2, #rarities do
    if rarities[i] < lo then slot, lo = i, rarities[i] end
  end
  return slot
end

function PackSystem.RollPack(db)
  db = db or ns.db
  local rarities = {}
  for i = 1, ns.PACK_SIZE do rarities[i] = PackSystem.RollRarity() end

  -- floor: every pack contains at least one Uncommon+
  if Best(rarities) < 3 then rarities[LowestSlot(rarities)] = 3 end

  db.pity.epic = db.pity.epic + 1
  db.pity.legendary = db.pity.legendary + 1

  if ns.forceLegendary then
    rarities[LowestSlot(rarities)] = 6
    ns.forceLegendary = nil
  end
  if db.pity.legendary >= ns.PITY_LEGENDARY and Best(rarities) < 6 then
    rarities[LowestSlot(rarities)] = 6
  end
  if db.pity.epic >= ns.PITY_EPIC and Best(rarities) < 5 then
    rarities[LowestSlot(rarities)] = 5
  end
  if Best(rarities) >= 6 then db.pity.legendary = 0 end
  if Best(rarities) >= 5 then db.pity.epic = 0 end

  local cards = {}
  for i = 1, ns.PACK_SIZE do cards[i] = PackSystem.PickCard(rarities[i]) end
  return cards
end

function PackSystem.BuyPack(db)
  db = db or ns.db
  if db.points < ns.PACK_COST then
    return false, string.format("not enough Pack Points (%d/%d)", db.points, ns.PACK_COST)
  end
  db.points = db.points - ns.PACK_COST
  db.packs = db.packs + 1
  ns.NotifyPointsChanged()
  return true
end

function PackSystem.OpenPack(db)
  db = db or ns.db
  if db.packs < 1 then return nil, "no unopened packs — /tcg buy" end
  db.packs = db.packs - 1
  local cards = PackSystem.RollPack(db)
  local results = {}
  for i, card in ipairs(cards) do
    local owned = db.collection[card.id] or 0
    db.collection[card.id] = owned + 1
    -- Any card, any rarity, can roll as a foil copy.
    local isFoil = ns.forceFoil or rng(ns.FOIL_CHANCE) == 1
    if isFoil then db.foils[card.id] = (db.foils[card.id] or 0) + 1 end
    results[i] = { card = card, isNew = owned == 0, count = owned + 1, isFoil = isFoil }
  end
  ns.forceFoil = nil
  db.stats.packsOpened = db.stats.packsOpened + 1
  ns.NotifyPointsChanged()
  return results
end

function PackSystem.DustCard(db, cardID)
  db = db or ns.db
  local count = db.collection[cardID] or 0
  if count < 2 then return false, "no duplicate to dust" end
  local card = ns.CardsById[cardID]
  if not card then return false, "unknown card" end
  local value = ns.DUST_VALUES[card.rarity]
  db.collection[cardID] = count - 1
  -- Non-foil spares dust first; the ledger only shrinks once every
  -- remaining copy is foil.
  if db.foils and (db.foils[cardID] or 0) > db.collection[cardID] then
    db.foils[cardID] = db.collection[cardID]
  end
  db.points = db.points + value
  db.stats.dusted = db.stats.dusted + value
  ns.NotifyPointsChanged()
  return true, value
end

function PackSystem.DustAllDupes(db)
  db = db or ns.db
  local total = 0
  for cardID, count in pairs(db.collection) do
    if count > 1 then
      local card = ns.CardsById[cardID]
      if card then
        total = total + ns.DUST_VALUES[card.rarity] * (count - 1)
        db.collection[cardID] = 1
        if db.foils and (db.foils[cardID] or 0) > 1 then db.foils[cardID] = 1 end
      end
    end
  end
  if total > 0 then
    db.points = db.points + total
    db.stats.dusted = db.stats.dusted + total
    ns.NotifyPointsChanged()
  end
  return total
end

function PackSystem.CompletionStats(db)
  db = db or ns.db
  local ownedTotal = 0
  local byRarity = {}
  for r = 1, 6 do byRarity[r] = { owned = 0, total = #ns.CardsByRarity[r] } end
  for _, card in ipairs(ns.CARDS) do
    if (db.collection[card.id] or 0) > 0 then
      ownedTotal = ownedTotal + 1
      byRarity[card.rarity].owned = byRarity[card.rarity].owned + 1
    end
  end
  return ownedTotal, #ns.CARDS, byRarity
end
