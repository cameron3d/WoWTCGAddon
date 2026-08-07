local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)
Stub.LoadAddonFile("Data/Cards.lua", ns)
Stub.LoadAddonFile("ChatFlex.lua", ns)
local CF = ns.ChatFlex

T.test("RewriteTokens builds a rarity-colored hyperlink", function()
  local card = ns.CARDS[1]
  local out = CF.RewriteTokens("I got [WoWTCG:" .. card.id .. "] today")
  T.ok(out:find("|HWoWTCG:card:" .. card.id .. "|h", 1, true) ~= nil, "link missing")
  T.ok(out:find(card.name, 1, true) ~= nil, "name missing")
  T.ok(out:find(ns.RARITY_COLORS[card.rarity].hex, 1, true) ~= nil, "color missing")
end)

T.test("unknown card ids are left untouched", function()
  local msg = "fake [WoWTCG:99999] token"
  T.eq(CF.RewriteTokens(msg), msg)
end)

T.test("Filter rewrites only messages containing tokens", function()
  local card = ns.CARDS[1]
  local handled, out, author = CF.Filter(nil, "CHAT_MSG_GUILD",
    "pulled [WoWTCG:" .. card.id .. "]!", "Sender")
  T.eq(handled, false)
  T.ok(out:find("|HWoWTCG:card:", 1, true) ~= nil)
  T.eq(author, "Sender")
  local _, plain = CF.Filter(nil, "CHAT_MSG_GUILD", "hello world", "Sender")
  T.eq(plain, "hello world")
end)

T.test("MaybeAnnounce respects min rarity and channel setting", function()
  local db = Stub.FreshDB(ns)
  Stub.ResetCaptures()
  local epicCard = ns.CardsByRarity[5][1]
  local commonCard = ns.CardsByRarity[2][1]
  CF.MaybeAnnounce({ { card = commonCard, isNew = true, count = 1 } })
  T.eq(#Stub.chatSent, 0, "common pull must not announce")
  CF.MaybeAnnounce({ { card = epicCard, isNew = true, count = 1 } })
  T.eq(#Stub.chatSent, 0, "channel OFF must not send")
  db.settings.announceChannel = "GUILD"
  CF.MaybeAnnounce({ { card = epicCard, isNew = true, count = 1 } })
  T.eq(#Stub.chatSent, 1)
  T.eq(Stub.chatSent[1].chan, "GUILD")
  T.ok(Stub.chatSent[1].msg:find("[WoWTCG:" .. epicCard.id .. "]", 1, true) ~= nil,
    "announcement must embed the token")
end)

T.test("Init registers filters for all chat events and hooks SetItemRef", function()
  Stub.chatFilters = {}
  CF.Init()
  T.eq(#Stub.chatFilters, #CF.CHAT_EVENTS)
  T.ok(Stub.hooks.SetItemRef ~= nil, "SetItemRef hook missing")
end)

T.test("OnHyperlink opens the card preview", function()
  local opened
  ns.CollectionUI = { ShowPreview = function(card) opened = card end }
  local card = ns.CARDS[1]
  CF.OnHyperlink("WoWTCG:card:" .. card.id)
  T.eq(opened, card)
  ns.CollectionUI = nil
end)
