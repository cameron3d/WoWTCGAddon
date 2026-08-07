local ADDON_NAME, ns = ...

ns.VERSION = "0.1.0"

ns.RARITY_NAMES  = { "Junk", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
ns.RARITY_COLORS = {
  { r = 0.62, g = 0.62, b = 0.62, hex = "9d9d9d" },  -- 1 Junk
  { r = 1.00, g = 1.00, b = 1.00, hex = "ffffff" },  -- 2 Common
  { r = 0.12, g = 1.00, b = 0.00, hex = "1eff00" },  -- 3 Uncommon
  { r = 0.00, g = 0.44, b = 0.87, hex = "0070dd" },  -- 4 Rare
  { r = 0.64, g = 0.21, b = 0.93, hex = "a335ee" },  -- 5 Epic
  { r = 1.00, g = 0.50, b = 0.00, hex = "ff8000" },  -- 6 Legendary
}

ns.PACK_COST   = 100
ns.PACK_SIZE   = 5
ns.DUST_VALUES = { 1, 2, 5, 15, 40, 150 }

ns.POINT_VALUES = {
  KILL = 2, QUEST = 25, HONOR = 5, BOSS = 50, EXPLORE = 10, LEVEL = 100,
}

ns.DEFAULTS = {
  version = 1,
  points = 0,
  packs = 0,
  collection = {},
  pity = { epic = 0, legendary = 0 },
  stats = { packsOpened = 0, totalPoints = 0, dusted = 0, byReason = {} },
  settings = {
    announceChannel = "OFF",   -- OFF | GUILD | PARTY | SAY | EMOTE
    announceMinRarity = 5,
    sounds = true,
    minimap = { angle = 200 },
  },
}

function ns.DeepFill(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      ns.DeepFill(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

function ns.InitDB()
  WoWTCG_DB = WoWTCG_DB or {}
  ns.DeepFill(WoWTCG_DB, ns.DEFAULTS)
  ns.db = WoWTCG_DB
  return ns.db
end

function ns.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WoWTCG|r: " .. tostring(msg))
end

function ns.NotifyPointsChanged()
  if ns.OnPointsChanged then ns.OnPointsChanged() end
end

function ns.AddPoints(amount, reason)
  if type(amount) ~= "number" or amount <= 0 or not ns.db then return end
  local db = ns.db
  db.points = db.points + amount
  db.stats.totalPoints = db.stats.totalPoints + amount
  if reason then
    db.stats.byReason[reason] = (db.stats.byReason[reason] or 0) + amount
  end
  ns.NotifyPointsChanged()
end

function ns.ColorName(card)
  return string.format("|cff%s%s|r", ns.RARITY_COLORS[card.rarity].hex, card.name)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
  if addonName ~= ADDON_NAME then return end
  self:UnregisterEvent("ADDON_LOADED")
  ns.InitDB()
  if ns.PointsEngine then ns.PointsEngine.Register() end
  if ns.ChatFlex then ns.ChatFlex.Init() end
  if ns.SetupMinimapButton then ns.SetupMinimapButton() end
  ns.Print("loaded — /tcg to open your collection (v" .. ns.VERSION .. ")")
end)
