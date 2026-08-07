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
ns.FOIL_CHANCE = 20   -- every pulled card is foil 1 time in 20, any rarity

ns.POINT_VALUES = {
  KILL = 2, QUEST = 25, HONOR = 5, BOSS = 50, EXPLORE = 10, LEVEL = 100,
}

ns.DEFAULTS = {
  version = 1,
  points = 0,
  packs = 0,
  collection = {},
  foils = {},        -- [cardId] = number of owned copies that are foil
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

local function ChannelValid(c)
  return c == "OFF" or c == "GUILD" or c == "PARTY" or c == "SAY" or c == "EMOTE"
end

function ns.HandleConfig(rest)
  local db = ns.db
  local opt, val = rest:match("^(%S*)%s*(.-)$")
  opt = opt:lower()
  if opt == "announce" then
    val = val:upper()
    if ChannelValid(val) then
      db.settings.announceChannel = val
      ns.Print("announce channel: " .. val)
    else
      ns.Print("usage: /tcg config announce OFF | GUILD | PARTY | SAY | EMOTE")
    end
  elseif opt == "minrarity" then
    local n = tonumber(val)
    if n and n >= 1 and n <= 6 then
      db.settings.announceMinRarity = n
      ns.Print("announce minimum rarity: " .. ns.RARITY_NAMES[n])
    else
      ns.Print("usage: /tcg config minrarity 1-6")
    end
  elseif opt == "sounds" then
    db.settings.sounds = (val:lower() ~= "off")
    ns.Print("sounds: " .. (db.settings.sounds and "on" or "off"))
  else
    ns.Print(string.format("announce=%s  minrarity=%d  sounds=%s",
      db.settings.announceChannel, db.settings.announceMinRarity,
      db.settings.sounds and "on" or "off"))
    ns.Print("options: announce <channel>, minrarity <1-6>, sounds on|off")
  end
end

function ns.HandleDebug(rest)
  local db = ns.db
  local sub, arg = rest:match("^(%S*)%s*(.-)$")
  sub = sub:lower()
  if sub == "points" then
    ns.AddPoints(tonumber(arg) or 100, "DEBUG")
    ns.Print("points: " .. db.points)
  elseif sub == "pack" then
    db.packs = db.packs + 1
    ns.Print("free pack granted (" .. db.packs .. " unopened)")
  elseif sub == "legendary" then
    ns.forceLegendary = true
    ns.Print("next pack will contain a Legendary")
  elseif sub == "foil" then
    ns.forceFoil = true
    ns.Print("next pack will be all foils")
  elseif sub == "resetpity" then
    db.pity.epic, db.pity.legendary = 0, 0
    ns.Print("pity counters reset")
  elseif sub == "wipe" then
    StaticPopup_Show("WOWTCG_WIPE")
  else
    ns.Print("debug: points <n> | pack | legendary | foil | resetpity | wipe")
  end
end

StaticPopupDialogs["WOWTCG_WIPE"] = {
  text = "Erase ALL WoWTCG data (collection, points, stats)?",
  button1 = "Wipe it",
  button2 = "Cancel",
  OnAccept = function()
    wipe(WoWTCG_DB)
    ns.InitDB()
    ns.Print("data wiped")
    if ns.CollectionUI then ns.CollectionUI.Refresh() end
  end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

function ns.HandleSlash(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then
    ns.CollectionUI.Toggle()
  elseif cmd == "open" then
    ns.PackUI.Open()
  elseif cmd == "buy" then
    local ok, err = ns.PackSystem.BuyPack()
    if ok then
      ns.Print(string.format("pack purchased — %d unopened, %d points left",
        ns.db.packs, ns.db.points))
    else
      ns.Print(err)
    end
  elseif cmd == "points" then
    ns.Print(string.format("%d Pack Points, %d unopened pack(s)", ns.db.points, ns.db.packs))
  elseif cmd == "config" then
    ns.HandleConfig(rest)
  elseif cmd == "debug" then
    ns.HandleDebug(rest)
  else
    ns.Print("commands: /tcg | open | buy | points | config | debug")
  end
end

SLASH_WOWTCG1 = "/tcg"
SLASH_WOWTCG2 = "/wowtcg"
SlashCmdList["WOWTCG"] = ns.HandleSlash

function ns.SetupMinimapButton()
  if WoWTCGMinimapButton then return end
  local btn = CreateFrame("Button", "WoWTCGMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp")
  btn:RegisterForDrag("LeftButton")

  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Note_02")
  icon:SetPoint("CENTER", -1, 1)

  local function UpdatePosition()
    local angle = math.rad(ns.db.settings.minimap.angle or 200)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
  end

  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = UIParent:GetEffectiveScale()
      ns.db.settings.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      UpdatePosition()
    end)
  end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  btn:SetScript("OnClick", function() ns.CollectionUI.Toggle() end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("WoWTCG")
    GameTooltip:AddLine("Click: open collection", 1, 1, 1)
    GameTooltip:AddLine("Drag: move button", 1, 1, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  UpdatePosition()
end
