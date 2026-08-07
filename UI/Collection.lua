local ADDON_NAME, ns = ...

local UI = {}
ns.CollectionUI = UI

local PAGE_SIZE = 9
local frame, previewFrame

UI.filters = { rarity = 0, ctype = "ALL", owned = "ALL", search = "" }
UI.page = 1

local RARITY_FILTERS = { 0, 1, 2, 3, 4, 5, 6 }
local TYPE_FILTERS   = { "ALL", "SPELL", "NPC", "ITEM" }
local TYPE_LABELS    = { ALL = "All", SPELL = "Spell", NPC = "NPC", ITEM = "Item" }
local OWNED_FILTERS  = { "ALL", "OWNED", "MISSING" }
local OWNED_LABELS   = { ALL = "All", OWNED = "Owned", MISSING = "Missing" }

function UI.FilteredCards()
  local list, fl, db = {}, UI.filters, ns.db
  local q = fl.search:lower()
  for _, card in ipairs(ns.CARDS) do
    local count = db.collection[card.id] or 0
    local matches =
      (fl.rarity == 0 or card.rarity == fl.rarity)
      and (fl.ctype == "ALL" or card.type == fl.ctype)
      and (fl.owned == "ALL" or (fl.owned == "OWNED" and count > 0)
        or (fl.owned == "MISSING" and count == 0))
    if matches and q ~= "" then
      if count == 0 and card.rarity >= 5 then
        matches = false   -- hidden names must not be searchable
      else
        matches = card.name:lower():find(q, 1, true) ~= nil
      end
    end
    if matches then list[#list + 1] = card end
  end
  return list
end

local function MakeButton(parent, width, label, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function CycleValue(values, current)
  for i, v in ipairs(values) do
    if v == current then return values[i % #values + 1] end
  end
  return values[1]
end

function UI.CycleRarity()
  UI.filters.rarity = CycleValue(RARITY_FILTERS, UI.filters.rarity)
  frame.rarityBtn:SetText("Rarity: "
    .. (UI.filters.rarity == 0 and "All" or ns.RARITY_NAMES[UI.filters.rarity]))
  UI.page = 1
  UI.RefreshGrid()
end

function UI.CycleType()
  UI.filters.ctype = CycleValue(TYPE_FILTERS, UI.filters.ctype)
  frame.typeBtn:SetText("Type: " .. TYPE_LABELS[UI.filters.ctype])
  UI.page = 1
  UI.RefreshGrid()
end

function UI.CycleOwned()
  UI.filters.owned = CycleValue(OWNED_FILTERS, UI.filters.owned)
  frame.ownedBtn:SetText("Show: " .. OWNED_LABELS[UI.filters.owned])
  UI.page = 1
  UI.RefreshGrid()
end

function UI.CardClicked(widget, button)
  local card = widget.card
  if not card then return end
  local count = ns.db.collection[card.id] or 0
  if button == "RightButton" then
    if count > 1 then
      local ok, value = ns.PackSystem.DustCard(nil, card.id)
      if ok then
        ns.Print(string.format("dusted duplicate %s (+%d points)", ns.ColorName(card), value))
        UI.Refresh()
      end
    end
  elseif count > 0 then
    UI.ShowPreview(card)
  end
end

local function BuildFrame()
  frame = CreateFrame("Frame", "WoWTCGCollectionFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(440, 680)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOP", 0, -16)
  frame.title:SetText("WoWTCG Collection")

  frame.closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.closeBtn:SetPoint("TOPRIGHT", -6, -6)

  frame.pointsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.pointsText:SetPoint("TOPLEFT", 22, -42)

  frame.completionText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.completionText:SetPoint("TOPLEFT", 22, -60)

  frame.buyBtn = MakeButton(frame, 110, "Buy Pack (100)", function()
    local ok, err = ns.PackSystem.BuyPack()
    if not ok then ns.Print(err) end
    UI.Refresh()
  end)
  frame.buyBtn:SetPoint("TOPRIGHT", -24, -38)

  frame.openBtn = MakeButton(frame, 110, "Open Pack", function() ns.PackUI.Open() end)
  frame.openBtn:SetPoint("TOPRIGHT", -24, -62)

  frame.dustBtn = MakeButton(frame, 110, "Dust Dupes", function()
    StaticPopup_Show("WOWTCG_DUSTALL")
  end)
  frame.dustBtn:SetPoint("TOPRIGHT", -24, -86)

  frame.rarityBtn = MakeButton(frame, 100, "Rarity: All", UI.CycleRarity)
  frame.rarityBtn:SetPoint("TOPLEFT", 20, -86)
  frame.typeBtn = MakeButton(frame, 88, "Type: All", UI.CycleType)
  frame.typeBtn:SetPoint("LEFT", frame.rarityBtn, "RIGHT", 4, 0)
  frame.ownedBtn = MakeButton(frame, 96, "Show: All", UI.CycleOwned)
  frame.ownedBtn:SetPoint("LEFT", frame.typeBtn, "RIGHT", 4, 0)

  frame.searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.searchLabel:SetPoint("TOPLEFT", 22, -118)
  frame.searchLabel:SetText("Search:")

  frame.searchBox = CreateFrame("EditBox", "WoWTCGSearchBox", frame, "InputBoxTemplate")
  frame.searchBox:SetSize(150, 20)
  frame.searchBox:SetPoint("TOPLEFT", 80, -112)
  frame.searchBox:SetAutoFocus(false)
  frame.searchBox:SetScript("OnTextChanged", function(box)
    UI.filters.search = box:GetText() or ""
    UI.page = 1
    UI.RefreshGrid()
  end)
  frame.searchBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

  frame.cards = {}
  for i = 1, PAGE_SIZE do
    local w = ns.CreateCardWidget(frame)
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    w:SetPoint("TOPLEFT", 28 + col * 130, -142 - row * 158)
    w:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    w:SetScript("OnClick", function(widget, button) UI.CardClicked(widget, button) end)
    frame.cards[i] = w
  end

  frame.prevBtn = MakeButton(frame, 60, "<", function()
    UI.page = UI.page - 1
    UI.RefreshGrid()
  end)
  frame.prevBtn:SetPoint("BOTTOMLEFT", 24, 18)

  frame.nextBtn = MakeButton(frame, 60, ">", function()
    UI.page = UI.page + 1
    UI.RefreshGrid()
  end)
  frame.nextBtn:SetPoint("BOTTOMRIGHT", -24, 18)

  frame.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.pageText:SetPoint("BOTTOM", 0, 22)

  tinsert(UISpecialFrames, "WoWTCGCollectionFrame")
end

function UI.RefreshGrid()
  if not frame then return end
  local list = UI.FilteredCards()
  local pages = math.max(1, math.ceil(#list / PAGE_SIZE))
  if UI.page > pages then UI.page = pages end
  if UI.page < 1 then UI.page = 1 end
  local offset = (UI.page - 1) * PAGE_SIZE
  for i, w in ipairs(frame.cards) do
    local card = list[offset + i]
    if card then
      local count = ns.db.collection[card.id] or 0
      if count > 0 then
        w:SetCard(card, { count = count })
        w.tooltipExtra = count > 1
          and ("Right-click: dust a duplicate (+" .. ns.DUST_VALUES[card.rarity] .. ")")
          or nil
      else
        w:SetCard(card, { silhouette = true })
        w.tooltipExtra = nil
      end
      w:Show()
    else
      w:Hide()
    end
  end
  frame.pageText:SetText(string.format("Page %d / %d  —  %d cards", UI.page, pages, #list))
  if UI.page <= 1 then frame.prevBtn:Disable() else frame.prevBtn:Enable() end
  if UI.page >= pages then frame.nextBtn:Disable() else frame.nextBtn:Enable() end
end

function UI.RefreshHeader()
  if not frame then return end
  local db = ns.db
  frame.pointsText:SetText(string.format(
    "|cffffd100%d|r Pack Points   —   |cffffd100%d|r unopened pack(s)", db.points, db.packs))
  local owned, total, byRarity = ns.PackSystem.CompletionStats()
  local parts = {}
  for r = 1, 6 do
    parts[r] = string.format("|cff%s%d/%d|r",
      ns.RARITY_COLORS[r].hex, byRarity[r].owned, byRarity[r].total)
  end
  frame.completionText:SetText(string.format("Collected %d/%d   %s",
    owned, total, table.concat(parts, "  ")))
end

function UI.Refresh()
  if not frame or not frame:IsShown() then return end
  UI.RefreshHeader()
  UI.RefreshGrid()
end

function UI.Toggle()
  if not frame then BuildFrame() end
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    UI.RefreshHeader()
    UI.RefreshGrid()
  end
end

function UI.ShowPreview(card)
  if not previewFrame then
    previewFrame = CreateFrame("Frame", "WoWTCGPreviewFrame", UIParent)
    previewFrame:SetSize(200, 260)
    previewFrame:SetPoint("CENTER", 0, 120)
    previewFrame:SetFrameStrata("TOOLTIP")
    previewFrame.widget = ns.CreateCardWidget(previewFrame)
    previewFrame.widget:SetPoint("CENTER")
    previewFrame.widget:SetScale(1.6)
    previewFrame.widget:SetScript("OnClick", function() previewFrame:Hide() end)
    tinsert(UISpecialFrames, "WoWTCGPreviewFrame")
  end
  local count = ns.db.collection[card.id] or 0
  previewFrame.widget:SetCard(card, { count = count })
  previewFrame.widget.tooltipExtra = "Click to close"
  previewFrame:Show()
end

StaticPopupDialogs["WOWTCG_DUSTALL"] = {
  text = "Dust ALL duplicate cards into Pack Points?",
  button1 = "Dust them",
  button2 = "Cancel",
  OnAccept = function()
    local gained = ns.PackSystem.DustAllDupes()
    ns.Print(string.format("dusted duplicates for %d Pack Points", gained))
    UI.Refresh()
  end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

ns.OnPointsChanged = function() UI.Refresh() end
