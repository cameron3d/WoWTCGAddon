local ADDON_NAME, ns = ...

local Pack = {}
ns.PackUI = Pack

local CARD_W, CARD_H = 130, 180
local CARD_GAP = 18
local FAN_LIFT = { 0, 8, 12, 8, 0 }   -- shallow arc, center highest
local SOUND_OPEN = (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN) or 850
local SOUND_EPIC = (SOUNDKIT and SOUNDKIT.LEVEL_UP) or 888

local WHITE = "Interface\\Buttons\\WHITE8X8"

local GOLD    = { 1.00, 0.82, 0.00 }   -- #ffd100
local ANTIQUE = { 0.79, 0.64, 0.29 }   -- #c9a24b
local FLAVOR  = { 0.55, 0.52, 0.47 }   -- #8d8577
local RING    = { 0.42, 0.35, 0.21 }   -- #6b5a36

local frame, flashFrame

local function ColorTex(parent, layer, sub, r, g, b, a)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  t:SetColorTexture(r, g, b, a or 1)
  return t
end

-- Restyle a UIPanelButtonTemplate button as a dark lacquered plate.
-- All Get* results are guarded: under the test stub they return nil.
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
  -- 1px black ring + light inner top highlight for the lacquered read.
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

local function StyleRedPlate(btn)
  StylePlate(btn, 0.42, 0.09, 0.09, 1, 0.85, 0.75)   -- #8a1a1a plate, #ffd9c0 text
end

-- Full-screen edge glow flash for a legendary reveal: ADD-blend strips along
-- each screen edge, fading out over ~1.5s.
local function EnsureFlash()
  if flashFrame then return flashFrame end
  flashFrame = CreateFrame("Frame", nil, UIParent)
  flashFrame:SetAllPoints(UIParent)
  flashFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  local function edge(point1, point2, w, h, alpha)
    local t = flashFrame:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 0.5, 0, alpha)
    t:SetBlendMode("ADD")
    t:SetPoint(point1)
    t:SetPoint(point2)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    return t
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 90, 1)         -- outer bands
  edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 90, 1)
  edge("TOPLEFT", "BOTTOMLEFT", 90, nil, 1)
  edge("TOPRIGHT", "BOTTOMRIGHT", 90, nil, 1)
  -- Softer inner falloff bands.
  local softTop = flashFrame:CreateTexture(nil, "OVERLAY")
  softTop:SetColorTexture(1, 0.5, 0, 0.4)
  softTop:SetBlendMode("ADD")
  softTop:SetPoint("TOPLEFT", 0, -90)
  softTop:SetPoint("TOPRIGHT", 0, -90)
  softTop:SetHeight(60)
  local softBottom = flashFrame:CreateTexture(nil, "OVERLAY")
  softBottom:SetColorTexture(1, 0.5, 0, 0.4)
  softBottom:SetBlendMode("ADD")
  softBottom:SetPoint("BOTTOMLEFT", 0, 90)
  softBottom:SetPoint("BOTTOMRIGHT", 0, 90)
  softBottom:SetHeight(60)
  flashFrame:Hide()
  return flashFrame
end

function Pack.ScreenFlash()
  local fl = EnsureFlash()
  fl.elapsed = 0
  fl:SetAlpha(0.28)
  fl:Show()
  fl:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    local k = self.elapsed / 1.5
    if k >= 1 then
      self:SetScript("OnUpdate", nil)
      self:Hide()
    else
      self:SetAlpha(0.28 * (1 - k))
    end
  end)
end

local function BuildFrame()
  frame = CreateFrame("Frame", "WoWTCGPackFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(860, 500)
  frame:SetPoint("CENTER", 0, 40)
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:SetBackdropColor(0.16, 0.11, 0.06, 0.97)   -- near-black warm
  frame:SetBackdropBorderColor(RING[1], RING[2], RING[3])
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then Pack.RevealAll() end
  end)

  -- Full-screen dimmer behind the modal. Mouse-transparent so it never
  -- steals clicks or Escape handling.
  frame.dimmer = CreateFrame("Frame", nil, frame)
  frame.dimmer:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
  frame.dimmer:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT")
  frame.dimmer:SetFrameStrata("HIGH")
  local dim = frame.dimmer:CreateTexture(nil, "BACKGROUND")
  dim:SetColorTexture(0, 0, 0, 0.62)
  dim:SetAllPoints()

  -- Inset gold pinstripe.
  local function stripe(p1, p2, w, h)
    local t = ColorTex(frame, "BORDER", 1, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.35)
    t:SetPoint(unpack(p1))
    t:SetPoint(unpack(p2))
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
  end
  stripe({ "TOPLEFT", 6, -6 }, { "TOPRIGHT", -6, -6 }, nil, 1)
  stripe({ "BOTTOMLEFT", 6, 6 }, { "BOTTOMRIGHT", -6, 6 }, nil, 1)
  stripe({ "TOPLEFT", 6, -6 }, { "BOTTOMLEFT", 6, 6 }, 1, nil)
  stripe({ "TOPRIGHT", -6, -6 }, { "BOTTOMRIGHT", -6, 6 }, 1, nil)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOP", 0, -24)
  frame.title:SetText("Pack Opening")
  frame.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

  local ruleL = ColorTex(frame, "OVERLAY", 0, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.5)
  ruleL:SetSize(60, 1)
  ruleL:SetPoint("RIGHT", frame.title, "LEFT", -14, 0)
  local ruleR = ColorTex(frame, "OVERLAY", 0, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.5)
  ruleR:SetSize(60, 1)
  ruleR:SetPoint("LEFT", frame.title, "RIGHT", 14, 0)

  frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.hint:SetPoint("TOP", frame.title, "BOTTOM", 0, -5)
  frame.hint:SetText("Left-click a card to reveal it — right-click to reveal all")
  frame.hint:SetTextColor(FLAVOR[1], FLAVOR[2], FLAVOR[3])

  -- Five cards in a shallow fan, center highest.
  frame.cards = {}
  local pitch = CARD_W + CARD_GAP
  for i = 1, ns.PACK_SIZE do
    local w = ns.CreateCardWidget(frame)
    w:SetPoint("CENTER", frame, "CENTER", (i - 3) * pitch, 26 + (FAN_LIFT[i] or 0))
    w:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    w:SetScript("OnClick", function(widget, button)
      if button == "RightButton" then Pack.RevealAll() else Pack.Reveal(widget) end
    end)
    frame.cards[i] = w
  end

  -- "BEST PULL" summary banner.
  frame.bestLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.bestLabel:SetPoint("BOTTOM", 0, 118)
  frame.bestLabel:SetText("B E S T   P U L L")
  frame.bestLabel:SetTextColor(ANTIQUE[1], ANTIQUE[2], ANTIQUE[3])

  frame.bestRuleL = ColorTex(frame, "OVERLAY", 0, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.45)
  frame.bestRuleL:SetSize(48, 1)
  frame.bestRuleL:SetPoint("RIGHT", frame.bestLabel, "LEFT", -12, 0)
  frame.bestRuleR = ColorTex(frame, "OVERLAY", 0, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.45)
  frame.bestRuleR:SetSize(48, 1)
  frame.bestRuleR:SetPoint("LEFT", frame.bestLabel, "RIGHT", 12, 0)

  frame.bestName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.bestName:SetPoint("TOP", frame.bestLabel, "BOTTOM", 0, -6)

  frame.newText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.newText:SetPoint("TOP", frame.bestName, "BOTTOM", 0, -4)
  frame.newText:SetTextColor(FLAVOR[1], FLAVOR[2], FLAVOR[3])

  frame.banner = { frame.bestLabel, frame.bestRuleL, frame.bestRuleR,
                   frame.bestName, frame.newText }

  frame.doneBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.doneBtn:SetSize(108, 26)
  frame.doneBtn:SetPoint("BOTTOM", -64, 22)
  frame.doneBtn:SetText("Done")
  frame.doneBtn:SetScript("OnClick", function() frame:Hide() end)
  StyleRedPlate(frame.doneBtn)

  frame.againBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.againBtn:SetSize(128, 26)
  frame.againBtn:SetPoint("BOTTOM", 64, 22)
  frame.againBtn:SetText("Open Another")
  frame.againBtn:SetScript("OnClick", function()
    if ns.db.packs == 0 then
      local ok, err = ns.PackSystem.BuyPack()
      if not ok then ns.Print(err) return end
    end
    Pack.Open()
  end)
  StyleRedPlate(frame.againBtn)

  tinsert(UISpecialFrames, "WoWTCGPackFrame")
end

function Pack.Open()
  local results, err = ns.PackSystem.OpenPack()
  if not results then
    if err then ns.Print(err) end
    return
  end
  if not frame then BuildFrame() end
  Pack.results = results
  Pack.revealedCount = 0
  Pack.summaryShown = false
  for i, w in ipairs(frame.cards) do
    w.result = results[i]
    w.revealed = false
    w:SetCard(results[i].card, { faceDown = true })
    w:Show()
  end
  for _, r in ipairs(frame.banner) do r:Hide() end
  frame.doneBtn:Hide()
  frame.againBtn:Hide()
  frame:Show()
  if ns.db.settings.sounds then pcall(PlaySound, SOUND_OPEN) end
end

function Pack.Reveal(widget)
  if widget.revealed or not widget.result then return end
  widget.revealed = true
  local r = widget.result
  widget:Flip({ count = r.count, isNew = r.isNew, foil = r.isFoil }, function(w)
    -- Count completed flips (not started ones): the legendary flip runs
    -- 0.9s vs 0.25s, and the summary must wait for the slowest reveal.
    Pack.revealedCount = Pack.revealedCount + 1
    if w.card.rarity >= 5 and ns.db.settings.sounds then pcall(PlaySound, SOUND_EPIC) end
    if w.card.rarity >= 6 then Pack.ScreenFlash() end
    if Pack.revealedCount >= ns.PACK_SIZE and not Pack.summaryShown then
      Pack.OnAllRevealed()
    end
  end)
end

function Pack.RevealAll()
  if not frame then return end
  for _, w in ipairs(frame.cards) do Pack.Reveal(w) end
end

function Pack.OnAllRevealed()
  Pack.summaryShown = true
  local newCount, bestCard = 0, nil
  for _, r in ipairs(Pack.results) do
    if r.isNew then newCount = newCount + 1 end
    if not bestCard or r.card.rarity > bestCard.rarity then bestCard = r.card end
  end
  local c = ns.RARITY_COLORS[bestCard.rarity]
  frame.bestName:SetText(bestCard.name .. " — " .. ns.RARITY_NAMES[bestCard.rarity])
  frame.bestName:SetTextColor(c.r, c.g, c.b)
  frame.newText:SetText(string.format("%d new card%s added to your binder",
    newCount, newCount == 1 and "" or "s"))
  for _, r in ipairs(frame.banner) do r:Show() end
  frame.doneBtn:Show()
  frame.againBtn:Show()
  ns.ChatFlex.MaybeAnnounce(Pack.results)
  if ns.CollectionUI then ns.CollectionUI.Refresh() end
end
