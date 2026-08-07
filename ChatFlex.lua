local ADDON_NAME, ns = ...

local CF = {}
ns.ChatFlex = CF

function CF.TokenFor(cardID)
  return "[WoWTCG:" .. cardID .. "]"
end

function CF.LinkFor(card)
  return string.format("|cff%s|HWoWTCG:card:%d|h[%s]|h|r",
    ns.RARITY_COLORS[card.rarity].hex, card.id, card.name)
end

function CF.RewriteTokens(text)
  return (text:gsub("%[WoWTCG:(%d+)%]", function(idStr)
    local card = ns.CardsById[tonumber(idStr)]
    if card then return CF.LinkFor(card) end
    -- returning nil leaves the token untouched
  end))
end

function CF.Filter(_, _, msg, ...)
  if type(msg) == "string" and msg:find("[WoWTCG:", 1, true) then
    return false, CF.RewriteTokens(msg), ...
  end
  return false, msg, ...
end

CF.CHAT_EVENTS = {
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
  "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE",
}

function CF.BestPull(results, minRarity)
  local best
  for _, r in ipairs(results) do
    if r.card.rarity >= minRarity and (not best or r.card.rarity > best.card.rarity) then
      best = r
    end
  end
  return best
end

function CF.MaybeAnnounce(results)
  local db = ns.db
  local best = CF.BestPull(results, db.settings.announceMinRarity)
  if not best then return end
  ns.Print(string.format("you pulled %s!", ns.ColorName(best.card)))
  local chan = db.settings.announceChannel
  if chan == "OFF" then return end
  local text = string.format("just pulled %s (%s) from a WoWTCG pack!",
    CF.TokenFor(best.card.id), ns.RARITY_NAMES[best.card.rarity])
  if chan ~= "EMOTE" then text = "I " .. text end
  SendChatMessage(text, chan)
end

function CF.OnHyperlink(link)
  local linkType, sub, idStr = strsplit(":", link)
  if linkType == "WoWTCG" and sub == "card" then
    local card = ns.CardsById[tonumber(idStr)]
    if card and ns.CollectionUI then
      ns.CollectionUI.ShowPreview(card)
    end
    return true
  end
end

function CF.Init()
  for _, event in ipairs(CF.CHAT_EVENTS) do
    ChatFrame_AddMessageEventFilter(event, CF.Filter)
  end
  hooksecurefunc("SetItemRef", function(link) CF.OnHyperlink(link) end)
end
