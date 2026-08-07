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

-- Layout: content column sits right of the spine.
local FRAME_W, FRAME_H = 520, 884
local CONTENT_X = 58          -- left edge of content column
local CONTENT_W = FRAME_W - CONTENT_X - 32
local CARD_W, CARD_H = 130, 180
local GRID_GAP = 16
local BAR_W = CONTENT_W - 100

local WHITE = "Interface\\Buttons\\WHITE8X8"
local STAR  = "Interface\\Cooldown\\star4"

local GOLD    = { 1.00, 0.82, 0.00 }   -- #ffd100
local ANTIQUE = { 0.79, 0.64, 0.29 }   -- #c9a24b
local TAN     = { 0.73, 0.63, 0.42 }   -- #b9a06a
local FLAVOR  = { 0.55, 0.52, 0.47 }   -- #8d8577
local RING    = { 0.42, 0.35, 0.21 }   -- #6b5a36

local function ColorTex(parent, layer, sub, r, g, b, a)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  t:SetColorTexture(r, g, b, a or 1)
  return t
end

local function Comma(n)
  local s, k = tostring(math.floor(n or 0)), 1
  while k > 0 do s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") end
  return s
end

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
      if count == 0 then
        matches = false   -- locked cards are anonymous; names must not be searchable
      else
        matches = card.name:lower():find(q, 1, true) ~= nil
      end
    end
    if matches then list[#list + 1] = card end
  end
  return list
end

-- Restyle a UIPanelButtonTemplate button as a colored plate (guards are for
-- the test stub, where Get* methods return nil).
local function StylePlate(btn, r, g, b, textR, textG, textB)
  btn:SetNormalTexture(WHITE)
  btn:SetPushedTexture(WHITE)
  btn:SetHighlightTexture(WHITE)
  btn:SetDisabledTexture(WHITE)
  local n = btn.GetNormalTexture and btn:GetNormalTexture()
  if n then n:SetVertexColor(r, g, b, 1) end
  local p = btn.GetPushedTexture and btn:GetPushedTexture()
  if p then p:SetVertexColor(r * 0.6, g * 0.6, b * 0.6, 1) end
  local h = btn.GetHighlightTexture and btn:GetHighlightTexture()
  if h then
    h:SetVertexColor(1, 1, 1, 1)
    h:SetAlpha(0.1)
    h:SetBlendMode("ADD")
  end
  local d = btn.GetDisabledTexture and btn:GetDisabledTexture()
  if d then d:SetVertexColor(r * 0.4, g * 0.4, b * 0.4, 1) end
  local ring = { ColorTex(btn, "BORDER", 1, 0, 0, 0, 0.9), ColorTex(btn, "BORDER", 1, 0, 0, 0, 0.9),
                 ColorTex(btn, "BORDER", 1, 0, 0, 0, 0.9), ColorTex(btn, "BORDER", 1, 0, 0, 0, 0.9) }
  ring[1]:SetPoint("TOPLEFT") ring[1]:SetPoint("TOPRIGHT") ring[1]:SetHeight(1)
  ring[2]:SetPoint("BOTTOMLEFT") ring[2]:SetPoint("BOTTOMRIGHT") ring[2]:SetHeight(1)
  ring[3]:SetPoint("TOPLEFT") ring[3]:SetPoint("BOTTOMLEFT") ring[3]:SetWidth(1)
  ring[4]:SetPoint("TOPRIGHT") ring[4]:SetPoint("BOTTOMRIGHT") ring[4]:SetWidth(1)
  local hi = ColorTex(btn, "BORDER", 2, 1, 1, 1, 0.12)
  hi:SetPoint("TOPLEFT", 1, -1)
  hi:SetPoint("TOPRIGHT", -1, -1)
  hi:SetHeight(1)
  local fs = btn.GetFontString and btn:GetFontString()
  if fs then fs:SetTextColor(textR, textG, textB) end
end

local function StyleBronze(btn) StylePlate(btn, 0.29, 0.23, 0.11, 0.91, 0.86, 0.75) end
local function StyleRed(btn)    StylePlate(btn, 0.42, 0.09, 0.09, 1, 0.85, 0.75) end
local function StyleGold(btn)   StylePlate(btn, 0.42, 0.32, 0.10, 1, 0.94, 0.75) end

local function MakeButton(parent, width, label, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

-- Inset dark panel with a faint gold inner line.
local function InsetPanel(parent, alpha)
  local p = CreateFrame("Frame", nil, parent)
  local bg = p:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0, 0, 0, alpha)
  bg:SetAllPoints()
  local ring = { ColorTex(p, "BORDER", 0, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.3),
                 ColorTex(p, "BORDER", 0, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.3),
                 ColorTex(p, "BORDER", 0, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.3),
                 ColorTex(p, "BORDER", 0, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.3) }
  ring[1]:SetPoint("TOPLEFT", 1, -1) ring[1]:SetPoint("TOPRIGHT", -1, -1) ring[1]:SetHeight(1)
  ring[2]:SetPoint("BOTTOMLEFT", 1, 1) ring[2]:SetPoint("BOTTOMRIGHT", -1, 1) ring[2]:SetHeight(1)
  ring[3]:SetPoint("TOPLEFT", 1, -1) ring[3]:SetPoint("BOTTOMLEFT", 1, 1) ring[3]:SetWidth(1)
  ring[4]:SetPoint("TOPRIGHT", -1, -1) ring[4]:SetPoint("BOTTOMRIGHT", -1, 1) ring[4]:SetWidth(1)
  -- Inner shadow read: darker strip along the top.
  local sh = ColorTex(p, "BORDER", 1, 0, 0, 0, 0.35)
  sh:SetPoint("TOPLEFT", 2, -2)
  sh:SetPoint("TOPRIGHT", -2, -2)
  sh:SetHeight(3)
  return p
end

local function CycleValue(values, current)
  for i, v in ipairs(values) do
    if v == current then return values[i % #values + 1] end
  end
  return values[1]
end

local function FilterLabel(label, value)
  return string.format("|cffb9a06a%s:|r |cffffd100%s|r", label, value)
end

function UI.CycleRarity()
  UI.filters.rarity = CycleValue(RARITY_FILTERS, UI.filters.rarity)
  frame.rarityBtn:SetText(FilterLabel("Rarity",
    UI.filters.rarity == 0 and "All" or ns.RARITY_NAMES[UI.filters.rarity]))
  UI.page = 1
  UI.RefreshGrid()
end

function UI.CycleType()
  UI.filters.ctype = CycleValue(TYPE_FILTERS, UI.filters.ctype)
  frame.typeBtn:SetText(FilterLabel("Type", TYPE_LABELS[UI.filters.ctype]))
  UI.page = 1
  UI.RefreshGrid()
end

function UI.CycleOwned()
  UI.filters.owned = CycleValue(OWNED_FILTERS, UI.filters.owned)
  frame.ownedBtn:SetText(FilterLabel("Show", OWNED_LABELS[UI.filters.owned]))
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

local function BuildSpine()
  -- Leather spine: 6px vertical strip near the left edge, plus rivets.
  local spine = ColorTex(frame, "BORDER", 0, 0.13, 0.08, 0.04, 1)
  spine:SetPoint("TOPLEFT", 14, -12)
  spine:SetPoint("BOTTOMLEFT", 14, 12)
  spine:SetWidth(6)
  local spineHi = ColorTex(frame, "BORDER", 1, RING[1], RING[2], RING[3], 0.9)
  spineHi:SetPoint("TOPLEFT", 16, -12)
  spineHi:SetPoint("BOTTOMLEFT", 16, 12)
  spineHi:SetWidth(2)
  -- Rivets: star4 blobs read as round studs (rotating solid-color squares
  -- is a visual no-op, so layered diamonds are not an option).
  for i = 0, 3 do
    local y = -68 - i * 56
    local shadow = frame:CreateTexture(nil, "ARTWORK", nil, 0)
    shadow:SetTexture(STAR)
    shadow:SetVertexColor(0.05, 0.03, 0.01)
    shadow:SetSize(18, 18)
    shadow:SetPoint("CENTER", frame, "TOPLEFT", 18, y - 1)
    local rivet = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    rivet:SetTexture(STAR)
    rivet:SetVertexColor(ANTIQUE[1], ANTIQUE[2], ANTIQUE[3])
    rivet:SetSize(14, 14)
    rivet:SetPoint("CENTER", frame, "TOPLEFT", 17, y)
  end
end

local function BuildStatPlate()
  local plate = InsetPanel(frame, 0.42)
  plate:SetPoint("TOPLEFT", CONTENT_X, -64)
  plate:SetSize(CONTENT_W, 104)
  frame.statPlate = plate

  -- Row 1: coin, points, packs line, buy/open buttons.
  local coin = plate:CreateTexture(nil, "ARTWORK")
  coin:SetSize(16, 16)
  coin:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  coin:SetPoint("TOPLEFT", 12, -12)

  frame.pointsValue = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.pointsValue:SetPoint("LEFT", coin, "RIGHT", 6, 0)
  frame.pointsValue:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

  frame.pointsLabel = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.pointsLabel:SetPoint("LEFT", frame.pointsValue, "RIGHT", 4, -1)
  frame.pointsLabel:SetText("Points")
  frame.pointsLabel:SetTextColor(TAN[1], TAN[2], TAN[3])

  frame.packsText = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.packsText:SetPoint("LEFT", frame.pointsLabel, "RIGHT", 12, 0)

  frame.openBtn = MakeButton(plate, 88, "Open Pack", function() ns.PackUI.Open() end)
  frame.openBtn:SetPoint("TOPRIGHT", -8, -10)
  frame.openBtn:SetHeight(24)
  StyleGold(frame.openBtn)

  frame.buyBtn = MakeButton(plate, 104, string.format("Buy Pack · %d", ns.PACK_COST), function()
    local ok, err = ns.PackSystem.BuyPack()
    if not ok then ns.Print(err) end
    UI.Refresh()
  end)
  frame.buyBtn:SetPoint("RIGHT", frame.openBtn, "LEFT", -6, 0)
  frame.buyBtn:SetHeight(24)
  StyleRed(frame.buyBtn)

  -- Bound the packs line so long values truncate instead of running
  -- underneath the Buy Pack button.
  frame.packsText:SetPoint("RIGHT", frame.buyBtn, "LEFT", -8, 0)
  frame.packsText:SetJustifyH("LEFT")
  frame.packsText:SetWordWrap(false)

  -- Row 2: completion bar + total.
  local trough = ColorTex(plate, "ARTWORK", 0, 0, 0, 0, 0.6)
  trough:SetPoint("TOPLEFT", 12, -46)
  trough:SetSize(BAR_W, 8)
  frame.barFill = ColorTex(plate, "ARTWORK", 1, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 1)
  frame.barFill:SetPoint("TOPLEFT", trough, "TOPLEFT", 0, 0)
  frame.barFill:SetSize(1, 8)
  frame.barFillHi = ColorTex(plate, "ARTWORK", 2, GOLD[1], GOLD[2], GOLD[3], 0.55)
  frame.barFillHi:SetPoint("TOPLEFT", trough, "TOPLEFT", 0, 0)
  frame.barFillHi:SetSize(1, 4)

  frame.compText = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.compText:SetPoint("TOPRIGHT", -10, -42)

  -- Row 3: per-rarity pips + dust dupes link.
  frame.pips = {}
  for r = 1, 6 do
    local c = ns.RARITY_COLORS[r]
    if r >= 5 then
      local glow = plate:CreateTexture(nil, "ARTWORK", nil, 0)
      glow:SetTexture(STAR)
      glow:SetVertexColor(c.r, c.g, c.b)
      glow:SetAlpha(0.35)
      glow:SetSize(22, 22)
      glow:SetPoint("CENTER", plate, "TOPLEFT", 17 + (r - 1) * 54, -78)
    end
    local pip = plate:CreateTexture(nil, "ARTWORK", nil, 1)
    pip:SetTexture(STAR)
    pip:SetVertexColor(c.r, c.g, c.b)
    pip:SetSize(13, 13)
    pip:SetPoint("CENTER", plate, "TOPLEFT", 17 + (r - 1) * 54, -78)
    local count = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("LEFT", pip, "RIGHT", 2, 0)
    count:SetTextColor(c.r, c.g, c.b)
    frame.pips[r] = count
  end

  frame.dustBtn = CreateFrame("Button", nil, plate)
  frame.dustBtn:SetSize(110, 16)
  frame.dustBtn:SetPoint("BOTTOMRIGHT", -10, 8)
  frame.dustText = frame.dustBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.dustText:SetPoint("RIGHT")
  frame.dustText:SetTextColor(ANTIQUE[1], ANTIQUE[2], ANTIQUE[3])
  frame.dustLine = ColorTex(frame.dustBtn, "OVERLAY", 0, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.6)
  frame.dustLine:SetPoint("BOTTOMRIGHT", 0, -1)
  frame.dustLine:SetSize(90, 1)
  frame.dustBtn:SetScript("OnClick", function() StaticPopup_Show("WOWTCG_DUSTALL") end)
end

local function BuildFilterStrip()
  local strip = InsetPanel(frame, 0.30)
  strip:SetPoint("TOPLEFT", CONTENT_X, -178)
  strip:SetSize(CONTENT_W, 36)
  frame.filterStrip = strip

  frame.rarityBtn = MakeButton(strip, 100, FilterLabel("Rarity", "All"), UI.CycleRarity)
  frame.rarityBtn:SetPoint("LEFT", 8, 0)
  StyleBronze(frame.rarityBtn)
  frame.typeBtn = MakeButton(strip, 88, FilterLabel("Type", "All"), UI.CycleType)
  frame.typeBtn:SetPoint("LEFT", frame.rarityBtn, "RIGHT", 4, 0)
  StyleBronze(frame.typeBtn)
  frame.ownedBtn = MakeButton(strip, 96, FilterLabel("Show", "All"), UI.CycleOwned)
  frame.ownedBtn:SetPoint("LEFT", frame.typeBtn, "RIGHT", 4, 0)
  StyleBronze(frame.ownedBtn)

  frame.searchBox = CreateFrame("EditBox", "WoWTCGSearchBox", strip, "InputBoxTemplate")
  frame.searchBox:SetSize(112, 18)
  frame.searchBox:SetPoint("RIGHT", -8, 0)
  frame.searchBox:SetAutoFocus(false)
  frame.searchPlaceholder = frame.searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.searchPlaceholder:SetPoint("LEFT", 2, 0)
  frame.searchPlaceholder:SetText("Search cards...")
  frame.searchBox:SetScript("OnTextChanged", function(box)
    local text = box:GetText() or ""
    UI.filters.search = text
    if text == "" then frame.searchPlaceholder:Show() else frame.searchPlaceholder:Hide() end
    UI.page = 1
    UI.RefreshGrid()
  end)
  frame.searchBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
end

local function BuildFrame()
  frame = CreateFrame("Frame", "WoWTCGCollectionFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(FRAME_W, FRAME_H)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  -- The 884-unit binder can exceed the 768-unit UI space at high UI scale;
  -- keep it reachable by clamping and shrinking to fit. (GetHeight returns
  -- nil under the test stub, hence the guard.)
  frame:SetClampedToScreen(true)
  local screenH = UIParent.GetHeight and UIParent:GetHeight()
  if screenH and screenH > 0 and FRAME_H > screenH - 16 then
    frame:SetScale((screenH - 16) / FRAME_H)
  end
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:SetBackdropColor(0.45, 0.30, 0.18, 1)   -- dark leather brown
  frame:SetBackdropBorderColor(RING[1], RING[2], RING[3])
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  -- Darken the dialog background toward the leather read.
  local shade = ColorTex(frame, "BACKGROUND", 1, 0.10, 0.06, 0.02, 0.75)
  shade:SetPoint("TOPLEFT", 4, -4)
  shade:SetPoint("BOTTOMRIGHT", -4, 4)

  -- Inset gold pinstripe, 7px in.
  local function stripe(p1, p2, w, h)
    local t = ColorTex(frame, "BORDER", 2, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.35)
    t:SetPoint(unpack(p1))
    t:SetPoint(unpack(p2))
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
  end
  stripe({ "TOPLEFT", 7, -7 }, { "TOPRIGHT", -7, -7 }, nil, 1)
  stripe({ "BOTTOMLEFT", 7, 7 }, { "BOTTOMRIGHT", -7, 7 }, nil, 1)
  stripe({ "TOPLEFT", 7, -7 }, { "BOTTOMLEFT", 7, 7 }, 1, nil)
  stripe({ "TOPRIGHT", -7, -7 }, { "BOTTOMRIGHT", -7, 7 }, 1, nil)

  BuildSpine()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", CONTENT_X, -30)
  frame.title:SetText("Collection")
  frame.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

  frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.subtitle:SetPoint("BOTTOMLEFT", frame.title, "BOTTOMRIGHT", 10, 2)
  frame.subtitle:SetText("CLASSIC VOL. 1")
  frame.subtitle:SetTextColor(ANTIQUE[1], ANTIQUE[2], ANTIQUE[3])

  frame.closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.closeBtn:SetPoint("TOPRIGHT", -8, -8)
  local cn = frame.closeBtn.GetNormalTexture and frame.closeBtn:GetNormalTexture()
  if cn then cn:SetVertexColor(1, 0.5, 0.45) end

  BuildStatPlate()
  BuildFilterStrip()

  frame.cards = {}
  local gridX = CONTENT_X + math.floor((CONTENT_W - (CARD_W * 3 + GRID_GAP * 2)) / 2)
  for i = 1, PAGE_SIZE do
    local w = ns.CreateCardWidget(frame)
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    w:SetPoint("TOPLEFT", gridX + col * (CARD_W + GRID_GAP), -232 - row * (CARD_H + GRID_GAP))
    w:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    w:SetScript("OnClick", function(widget, button) UI.CardClicked(widget, button) end)
    frame.cards[i] = w
  end

  frame.prevBtn = MakeButton(frame, 34, "<", function()
    UI.page = UI.page - 1
    UI.RefreshGrid()
  end)
  frame.prevBtn:SetPoint("BOTTOMLEFT", CONTENT_X, 32)
  StyleBronze(frame.prevBtn)

  frame.nextBtn = MakeButton(frame, 34, ">", function()
    UI.page = UI.page + 1
    UI.RefreshGrid()
  end)
  frame.nextBtn:SetPoint("BOTTOMRIGHT", -32, 32)
  StyleBronze(frame.nextBtn)

  frame.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.pageText:SetPoint("BOTTOM", (CONTENT_X - 32) / 2, 36)

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
        local foils = (ns.db.foils and ns.db.foils[card.id]) or 0
        w:SetCard(card, { count = count, foil = foils > 0, foilCount = foils })
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
  frame.pageText:SetText(string.format(
    "|cffb9a06aPage |cffffd100%d|r|cffb9a06a / %d  —  %d cards|r", UI.page, pages, #list))
  if UI.page <= 1 then frame.prevBtn:Disable() else frame.prevBtn:Enable() end
  if UI.page >= pages then frame.nextBtn:Disable() else frame.nextBtn:Enable() end
end

function UI.RefreshHeader()
  if not frame then return end
  local db = ns.db
  frame.pointsValue:SetText(Comma(db.points))
  frame.packsText:SetText(string.format(
    "|cffe8dcc0%d|r |cff8d8577sealed  ·|r  |cffe8dcc0%d|r |cff8d8577opened|r",
    db.packs, db.stats.packsOpened))

  local owned, total, byRarity = ns.PackSystem.CompletionStats()
  local fillW = math.max(1, math.floor(BAR_W * owned / math.max(1, total)))
  frame.barFill:SetWidth(fillW)
  frame.barFillHi:SetWidth(fillW)
  frame.compText:SetText(string.format("|cffffd100%d|r|cffb9a06a/%d|r", owned, total))
  for r = 1, 6 do
    frame.pips[r]:SetText(string.format("%d/%d", byRarity[r].owned, byRarity[r].total))
  end

  local dust = 0
  for _, card in ipairs(ns.CARDS) do
    local count = db.collection[card.id] or 0
    if count > 1 then dust = dust + (count - 1) * ns.DUST_VALUES[card.rarity] end
  end
  frame.dustText:SetText(string.format("Dust dupes (+%d)", dust))
  local tw = frame.dustText.GetStringWidth and frame.dustText:GetStringWidth()
  local linkW = (tw and tw > 0) and tw or 90
  frame.dustLine:SetWidth(linkW)
  -- Fit the hit rect to the visible link so it can't swallow clicks
  -- meant for the legendary pip counter to its left.
  frame.dustBtn:SetWidth(linkW + 6)
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
    previewFrame:SetSize(250, 320)
    previewFrame:SetPoint("CENTER", 0, 120)
    previewFrame:SetFrameStrata("TOOLTIP")
    previewFrame.widget = ns.CreateCardWidget(previewFrame)
    previewFrame.widget:SetPoint("CENTER")
    previewFrame.widget:SetScale(1.6)
    previewFrame.widget:SetScript("OnClick", function() previewFrame:Hide() end)
    tinsert(UISpecialFrames, "WoWTCGPreviewFrame")
  end
  local count = ns.db.collection[card.id] or 0
  local foils = (ns.db.foils and ns.db.foils[card.id]) or 0
  previewFrame.widget:SetCard(card, { count = count, foil = foils > 0, foilCount = foils })
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
