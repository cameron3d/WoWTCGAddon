local ADDON_NAME, ns = ...

local CARD_W, CARD_H = 130, 180

local WHITE = "Interface\\Buttons\\WHITE8X8"
local STAR  = "Interface\\Cooldown\\star4"

local BACKDROP = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 14,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Design tokens (README: design_handoff_wowtcg_ui)
local GOLD      = { 1.00, 0.82, 0.00 }   -- #ffd100
local ANTIQUE   = { 0.79, 0.64, 0.29 }   -- #c9a24b
local TAN       = { 0.73, 0.63, 0.42 }   -- #b9a06a
local FLAVOR    = { 0.55, 0.52, 0.47 }   -- #8d8577
local BODY_HI   = { 0.14, 0.11, 0.07 }   -- #241b11
local BODY_LO   = { 0.08, 0.06, 0.04 }   -- #140f09
local BACK_HI   = { 0.17, 0.11, 0.06 }   -- #2b1d0f
local BACK_LO   = { 0.09, 0.06, 0.04 }   -- #17100a
local RING_GOLD = { 0.42, 0.35, 0.21 }   -- #6b5a36
local SIL_BODY  = { 0.10, 0.08, 0.06 }   -- #191410
local SIL_EDGE  = { 0.23, 0.21, 0.18 }   -- #3a352d
local SIL_NAME  = { 0.42, 0.38, 0.33 }   -- #6a6255
local SIL_EPIC  = { 0.33, 0.25, 0.42 }   -- #54406a
local SIL_TYPE  = { 0.35, 0.32, 0.26 }   -- #5a5142
local SIL_QMARK = { 0.29, 0.27, 0.22 }   -- #4a4438

local function ShowAll(list) for _, r in ipairs(list) do r:Show() end end
local function HideAll(list) for _, r in ipairs(list) do r:Hide() end end

local function ColorTex(parent, layer, sub, r, g, b, a)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  t:SetColorTexture(r, g, b, a or 1)
  return t
end

-- Four 1px strips forming a rectangular ring, `inset` px inside the frame edge.
local function Ring(parent, layer, sub, inset, thickness, r, g, b, a)
  local strips = {}
  for i = 1, 4 do strips[i] = ColorTex(parent, layer, sub, r, g, b, a) end
  strips[1]:SetPoint("TOPLEFT", inset, -inset)
  strips[1]:SetPoint("TOPRIGHT", -inset, -inset)
  strips[1]:SetHeight(thickness)
  strips[2]:SetPoint("BOTTOMLEFT", inset, inset)
  strips[2]:SetPoint("BOTTOMRIGHT", -inset, inset)
  strips[2]:SetHeight(thickness)
  strips[3]:SetPoint("TOPLEFT", inset, -inset)
  strips[3]:SetPoint("BOTTOMLEFT", inset, inset)
  strips[3]:SetWidth(thickness)
  strips[4]:SetPoint("TOPRIGHT", -inset, -inset)
  strips[4]:SetPoint("BOTTOMRIGHT", -inset, inset)
  strips[4]:SetWidth(thickness)
  return strips
end

local function SetRingColor(strips, r, g, b, a)
  for _, s in ipairs(strips) do s:SetColorTexture(r, g, b, a or 1) end
end

-- star4 reads as a four-point diamond. (SetRotation only rotates texture
-- coordinates, so it is a visual no-op on solid-color textures — a rotated
-- WHITE8X8 square is NOT an option here.)
local function Diamond(parent, layer, sub, size, r, g, b, a)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  t:SetTexture(STAR)
  t:SetVertexColor(r, g, b)
  t:SetAlpha(a or 1)
  t:SetSize(size * 1.6, size * 1.6)
  return t
end

-- Hue [0,1) -> saturated r,g,b for the legendary rainbow wash.
local function HueRGB(h)
  local i = math.floor(h * 6) % 6
  local f = h * 6 - math.floor(h * 6)
  if i == 0 then return 1, f, 0 end
  if i == 1 then return 1 - f, 1, 0 end
  if i == 2 then return 0, 1, f end
  if i == 3 then return 0, 1 - f, 1 end
  if i == 4 then return f, 0, 1 end
  return 1, 0, 1 - f
end

---------------------------------------------------------------------------
-- Card effects. Foil copies (any rarity) carry the foil signature: shine
-- sweep + shimmer border. Epic+ additionally get glow pulse + sparkles,
-- Legendary the rainbow wash. One OnUpdate driver per widget on a child
-- frame, so it never collides with the Flip animation's OnUpdate on the
-- button itself.
---------------------------------------------------------------------------

local BURST_STARS = 6

local function FX_OnUpdate(fx, dt)
  local f = fx.owner
  local t = fx.t + (dt or 0.016)
  fx.t = t
  local rarity = fx.rarity or 0

  -- Foil signature: shine sweep (faster for higher rarity) + shimmer border.
  if fx.foil then
    local period = (rarity >= 6 and 2.8) or (rarity >= 5 and 3.3) or 3.8
    local cycle = t % period
    local dur = 0.7
    if cycle < dur then
      local x = -CARD_W * 0.75 + (CARD_W * 1.5) * (cycle / dur)
      for _, seg in ipairs(f.shine) do
        seg:ClearAllPoints()
        seg:SetPoint("CENTER", f, "CENTER", x + seg.dx, seg.dy)
        seg:Show()
      end
    else
      for _, seg in ipairs(f.shine) do seg:Hide() end
    end
    local sh = 0.4 + 0.3 * (1 + math.sin(t * (2 * math.pi / 2.1) + 1.3))
    for _, s in ipairs(f.shimmer) do s:SetAlpha(sh) end
  end

  if rarity >= 5 then
    -- Glow pulse 0.3 -> 0.85 over ~2.2s.
    f.glow:SetAlpha(0.3 + 0.275 * (1 + math.sin(t * (2 * math.pi / 2.2))))
    -- Corner sparkles on staggered loops.
    local a1 = math.max(0, math.sin(t * (2 * math.pi / 1.9)))
    local a2 = math.max(0, math.sin(t * (2 * math.pi / 2.5) + 2.1))
    f.sparkle1:SetAlpha(a1 * 0.9)
    f.sparkle2:SetAlpha(a2 * 0.8)
    f.sparkle1:SetSize(10 + 6 * a1, 10 + 6 * a1)
    f.sparkle2:SetSize(7 + 5 * a2, 7 + 5 * a2)
  end

  -- Legendary rainbow wash: slow hue cycle, low alpha, ADD blend.
  if rarity >= 6 then
    local r, g, b = HueRGB((t / 6) % 1)
    f.wash:SetVertexColor(r, g, b)
  end

  -- Sparkle burst fired at the end of a legendary flip.
  if fx.burstT then
    fx.burstT = fx.burstT + (dt or 0.016)
    local k = fx.burstT / 0.6
    if k >= 1 then
      fx.burstT = nil
      for _, s in ipairs(f.burst) do s:Hide() end
    else
      local radius = 12 + 68 * k
      for i, s in ipairs(f.burst) do
        local ang = (i / BURST_STARS) * 2 * math.pi + 0.4
        s:ClearAllPoints()
        s:SetPoint("CENTER", f, "CENTER", radius * math.cos(ang), radius * math.sin(ang))
        s:SetAlpha((1 - k) * 0.9)
        s:SetSize(16 * (1 - 0.5 * k), 16 * (1 - 0.5 * k))
        s:Show()
      end
    end
  end
end

local function StopFX(f)
  f.fxFrame:SetScript("OnUpdate", nil)
  f.fxFrame.rarity = 0
  f.fxFrame.foil = nil
  f.fxFrame.burstT = nil
  for _, seg in ipairs(f.shine) do seg:Hide() end
  f.glow:Hide()
  f.wash:Hide()
  f.sparkle1:Hide()
  f.sparkle2:Hide()
  HideAll(f.shimmer)
  HideAll(f.burst)
end

local function StartFX(f, rarity, foil)
  StopFX(f)
  if not foil and rarity < 5 then return end
  local fx = f.fxFrame
  fx.t = 0
  fx.rarity = rarity
  fx.foil = foil and true or nil
  local c = ns.RARITY_COLORS[rarity]
  if foil then
    SetRingColor(f.shimmer, c.r, c.g, c.b, 1)
    ShowAll(f.shimmer)
  end
  if rarity >= 5 then
    f.glow:SetVertexColor(c.r, c.g, c.b)
    f.glow:Show()
    f.sparkle1:Show()
    f.sparkle2:Show()
  end
  if rarity >= 6 then f.wash:Show() end
  fx:SetScript("OnUpdate", FX_OnUpdate)
end

---------------------------------------------------------------------------
-- Card methods
---------------------------------------------------------------------------

local Card = {}

function Card:SetFaceDown()
  -- Cancel any in-flight flip so a hidden/interrupted animation can't
  -- resume against a new card with stale opts.
  self:SetScript("OnUpdate", nil)
  self:SetWidth(CARD_W)
  self.faceUp = false
  self:SetAlpha(1)
  StopFX(self)
  HideAll(self.face)
  self.qMark:Hide()
  self.newBadge:Hide()
  ShowAll(self.back)
  self:SetBackdropColor(0.35, 0.28, 0.18, 1)
  self:SetBackdropBorderColor(RING_GOLD[1], RING_GOLD[2], RING_GOLD[3])
end

function Card:SetCard(card, opts)
  opts = opts or {}
  self.card = card
  self.opts = opts
  if opts.faceDown then
    self:SetFaceDown()
    return
  end
  self.faceUp = true
  HideAll(self.back)
  ShowAll(self.face)
  local color = ns.RARITY_COLORS[card.rarity]

  if opts.silhouette then
    StopFX(self)
    self:SetAlpha(0.85)
    self:SetBackdropColor(0.30, 0.26, 0.20, 1)
    self.bodyTop:SetColorTexture(SIL_BODY[1], SIL_BODY[2], SIL_BODY[3], 0.85)
    self.bodyBottom:SetColorTexture(0.05, 0.04, 0.03, 0.85)
    self:SetBackdropBorderColor(SIL_EDGE[1], SIL_EDGE[2], SIL_EDGE[3])
    self.icon:Hide()
    self.artPlate:SetColorTexture(0.05, 0.04, 0.03, 0.9)
    SetRingColor(self.artLine, SIL_EDGE[1], SIL_EDGE[2], SIL_EDGE[3], 0.6)
    self.qMark:Show()
    -- Locked cards are anonymous: no name, no type, at every rarity.
    local epicPlus = card.rarity >= 5
    self.nameText:SetText("? ? ?")
    if epicPlus then
      self.nameText:SetTextColor(SIL_EPIC[1], SIL_EPIC[2], SIL_EPIC[3])
    else
      self.nameText:SetTextColor(SIL_NAME[1], SIL_NAME[2], SIL_NAME[3])
    end
    self.divDiamond:SetVertexColor(SIL_TYPE[1], SIL_TYPE[2], SIL_TYPE[3])
    self.divDiamond:SetAlpha(0.8)
    self.typeText:SetText(string.upper(ns.RARITY_NAMES[card.rarity]) .. " ???")
    self.typeText:SetTextColor(SIL_TYPE[1], SIL_TYPE[2], SIL_TYPE[3])
    self.flavorText:SetText(epicPlus and "Undiscovered" or "Not yet collected")
    self.flavorText:SetTextColor(SIL_NAME[1], SIL_NAME[2], SIL_NAME[3], 0.9)
    self.countText:SetText("")
    self.newBadge:Hide()
  else
    self:SetAlpha(1)
    self:SetBackdropColor(0.55, 0.42, 0.28, 1)
    self.bodyTop:SetColorTexture(BODY_HI[1], BODY_HI[2], BODY_HI[3], 0.55)
    self.bodyBottom:SetColorTexture(BODY_LO[1], BODY_LO[2], BODY_LO[3], 0.7)
    self:SetBackdropBorderColor(color.r, color.g, color.b)
    self.qMark:Hide()
    self.icon:Show()
    self.icon:SetTexture(card.icon)
    self.icon:SetVertexColor(1, 1, 1)
    self.artPlate:SetColorTexture(0, 0, 0, 1)
    SetRingColor(self.artLine, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.3)
    self.nameText:SetText(card.name)
    self.nameText:SetTextColor(color.r, color.g, color.b)
    self.divDiamond:SetVertexColor(color.r, color.g, color.b)
    self.divDiamond:SetAlpha(1)
    self.typeText:SetText(string.upper(ns.RARITY_NAMES[card.rarity] .. " " .. card.type))
    self.typeText:SetTextColor(TAN[1], TAN[2], TAN[3])
    self.flavorText:SetText(card.flavor or "")
    self.flavorText:SetTextColor(FLAVOR[1], FLAVOR[2], FLAVOR[3])
    self.countText:SetText((opts.count and opts.count > 1) and ("x" .. opts.count) or "")
    if opts.isNew then self.newBadge:Show() else self.newBadge:Hide() end
    StartFX(self, card.rarity, opts.foil)
  end
end

-- Width-squash flip: face swaps at the narrowest point. Legendary gets a
-- longer suspense flip (~0.9s) with a hold before the swap, then a burst.
function Card:Flip(opts, onRevealed)
  self:SetScript("OnUpdate", nil)
  self:SetWidth(CARD_W)
  local legendary = self.card and self.card.rarity >= 6
    and not (opts and opts.silhouette)
  local hold = legendary and 0.3 or 0
  local total = legendary and 0.9 or 0.25
  local squash = (total - hold) / 2
  local elapsed, swapped = 0, false
  self:SetScript("OnUpdate", function(widget, dt)
    elapsed = elapsed + dt
    local w
    if elapsed < squash then
      w = math.cos((elapsed / squash) * (math.pi / 2))
    elseif elapsed < squash + hold then
      w = 0
    else
      w = math.sin(math.min((elapsed - squash - hold) / squash, 1) * (math.pi / 2))
    end
    if not swapped and elapsed >= squash + hold then
      swapped = true
      widget:SetCard(widget.card, opts)
    end
    widget:SetWidth(math.max(CARD_W * math.abs(w), 1))
    if elapsed >= total then
      widget:SetScript("OnUpdate", nil)
      widget:SetWidth(CARD_W)
      if legendary then
        widget.fxFrame.burstT = 0
      end
      if onRevealed then onRevealed(widget) end
    end
  end)
end

local function OnEnter(self)
  if not (self.card and self.faceUp) or (self.opts and self.opts.silhouette) then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(ns.ColorName(self.card))
  GameTooltip:AddLine(ns.RARITY_NAMES[self.card.rarity] .. " " .. self.card.type, 1, 1, 1)
  if self.card.flavor then
    GameTooltip:AddLine('"' .. self.card.flavor .. '"', 0.8, 0.8, 0.6, true)
  end
  if self.opts and self.opts.foil then
    local n = self.opts.foilCount
    GameTooltip:AddLine((n and n > 1) and ("Foil x" .. n) or "Foil", 1, 0.85, 0.4)
  end
  if self.tooltipExtra then
    GameTooltip:AddLine(self.tooltipExtra, 0.5, 1, 0.5)
  end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function BuildFace(f)
  local face = {}

  f.bodyTop = ColorTex(f, "BACKGROUND", 1, BODY_HI[1], BODY_HI[2], BODY_HI[3], 0.55)
  f.bodyTop:SetPoint("TOPLEFT", 3, -3)
  f.bodyTop:SetPoint("BOTTOMRIGHT", -3, 3)
  face[#face + 1] = f.bodyTop

  f.bodyBottom = ColorTex(f, "BACKGROUND", 2, BODY_LO[1], BODY_LO[2], BODY_LO[3], 0.7)
  f.bodyBottom:SetPoint("BOTTOMLEFT", 3, 3)
  f.bodyBottom:SetPoint("BOTTOMRIGHT", -3, 3)
  f.bodyBottom:SetHeight(CARD_H * 0.45)
  face[#face + 1] = f.bodyBottom

  -- 1px inner black outline for the "double ring" read.
  f.innerRing = Ring(f, "ARTWORK", -8, 2, 1, 0, 0, 0, 0.9)
  for _, s in ipairs(f.innerRing) do face[#face + 1] = s end

  -- Art box: black plate, letterboxed icon, faint gold inner line.
  f.artPlate = ColorTex(f, "ARTWORK", -2, 0, 0, 0, 1)
  f.artPlate:SetSize(104, 74)
  f.artPlate:SetPoint("TOP", 0, -10)
  face[#face + 1] = f.artPlate

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(100, 70)
  f.icon:SetPoint("TOP", 0, -12)
  f.icon:SetTexCoord(0.07, 0.93, 0.2, 0.8)
  face[#face + 1] = f.icon

  f.artLine = {}
  local edges = {
    { "TOPLEFT", "TOPRIGHT", nil, 1 },       -- top
    { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, -- bottom
    { "TOPLEFT", "BOTTOMLEFT", 1, nil },     -- left
    { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },   -- right
  }
  for _, e in ipairs(edges) do
    local s = ColorTex(f, "ARTWORK", 1, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.3)
    s:SetPoint(e[1], f.icon, e[1], 0, 0)
    s:SetPoint(e[2], f.icon, e[2], 0, 0)
    if e[3] then s:SetWidth(e[3]) else s:SetHeight(e[4]) end
    f.artLine[#f.artLine + 1] = s
    face[#face + 1] = s
  end

  f.qMark = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  f.qMark:SetPoint("CENTER", f.artPlate, "CENTER", 0, 0)
  f.qMark:SetText("?")
  f.qMark:SetTextColor(SIL_QMARK[1], SIL_QMARK[2], SIL_QMARK[3])
  f.qMark:Hide()

  f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.nameText:SetPoint("TOP", f.icon, "BOTTOM", 0, -8)
  f.nameText:SetWidth(CARD_W - 16)
  face[#face + 1] = f.nameText

  -- Divider: rarity diamond flanked by thin gold lines.
  f.divDiamond = Diamond(f, "ARTWORK", 2, 6, 1, 1, 1, 1)
  f.divDiamond:SetPoint("TOP", f.nameText, "BOTTOM", 0, -4)
  face[#face + 1] = f.divDiamond

  f.divL = ColorTex(f, "ARTWORK", 2, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.45)
  f.divL:SetSize(32, 1)
  f.divL:SetPoint("RIGHT", f.divDiamond, "LEFT", -6, 0)
  face[#face + 1] = f.divL

  f.divR = ColorTex(f, "ARTWORK", 2, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.45)
  f.divR:SetSize(32, 1)
  f.divR:SetPoint("LEFT", f.divDiamond, "RIGHT", 6, 0)
  face[#face + 1] = f.divR

  f.typeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.typeText:SetPoint("TOP", f.divDiamond, "BOTTOM", 0, -5)
  f.typeText:SetWidth(CARD_W - 16)
  face[#face + 1] = f.typeText

  f.flavorText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.flavorText:SetPoint("BOTTOM", 0, 12)
  f.flavorText:SetWidth(CARD_W - 20)
  face[#face + 1] = f.flavorText

  f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.countText:SetPoint("BOTTOMRIGHT", -7, 7)
  face[#face + 1] = f.countText

  f.face = face
end

local function BuildBack(f)
  local back = {}
  local function add(r) back[#back + 1] = r return r end

  local base = add(ColorTex(f, "BACKGROUND", 3, BACK_LO[1], BACK_LO[2], BACK_LO[3], 1))
  base:SetPoint("TOPLEFT", 3, -3)
  base:SetPoint("BOTTOMRIGHT", -3, 3)

  local center = add(ColorTex(f, "BACKGROUND", 4, BACK_HI[1], BACK_HI[2], BACK_HI[3], 1))
  center:SetPoint("TOPLEFT", 14, -18)
  center:SetPoint("BOTTOMRIGHT", -14, 18)

  -- Soft radial sheen to fake the radial leather gradient.
  local sheen = add(f:CreateTexture(nil, "BACKGROUND", nil, 5))
  sheen:SetTexture(STAR)
  sheen:SetBlendMode("ADD")
  sheen:SetVertexColor(ANTIQUE[1], ANTIQUE[2], ANTIQUE[3])
  sheen:SetAlpha(0.10)
  sheen:SetSize(CARD_W * 0.95, CARD_W * 0.95)
  sheen:SetPoint("CENTER")

  -- Two inset gold pinstripe rectangles.
  for _, s in ipairs(Ring(f, "ARTWORK", -6, 8, 1, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.5)) do add(s) end
  for _, s in ipairs(Ring(f, "ARTWORK", -6, 13, 1, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.22)) do add(s) end

  -- Four L-shaped corner brackets (two 2px strips each).
  local corners = {
    { "TOPLEFT", 10, -10, 1, -1 },
    { "TOPRIGHT", -10, -10, -1, -1 },
    { "BOTTOMLEFT", 10, 10, 1, 1 },
    { "BOTTOMRIGHT", -10, 10, -1, 1 },
  }
  for _, c in ipairs(corners) do
    local h = add(ColorTex(f, "ARTWORK", -5, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 1))
    h:SetSize(13, 2)
    h:SetPoint(c[1], c[2], c[3])
    local v = add(ColorTex(f, "ARTWORK", -5, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 1))
    v:SetSize(2, 13)
    v:SetPoint(c[1], c[2], c[3])
  end

  -- Centered gold diamond with a soft glow, three small diamonds beneath.
  local glow = add(f:CreateTexture(nil, "ARTWORK", nil, -5))
  glow:SetTexture(STAR)
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(ANTIQUE[1], ANTIQUE[2], ANTIQUE[3])
  glow:SetAlpha(0.35)
  glow:SetSize(44, 44)
  glow:SetPoint("CENTER", 0, 10)

  local dia = add(Diamond(f, "ARTWORK", -4, 22, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 1))
  dia:SetPoint("CENTER", 0, 10)

  for i = -1, 1 do
    local d = add(Diamond(f, "ARTWORK", -4, 5, ANTIQUE[1], ANTIQUE[2], ANTIQUE[3], 0.45))
    d:SetPoint("CENTER", i * 13, -18)
  end

  HideAll(back)
  f.back = back
end

local function BuildFX(f)
  -- Clipped child frame so the shine sweep stays inside the card border.
  f.fxFrame = CreateFrame("Frame", nil, f)
  f.fxFrame:SetPoint("TOPLEFT", 3, -3)
  f.fxFrame:SetPoint("BOTTOMRIGHT", -3, 3)
  f.fxFrame:SetClipsChildren(true)
  f.fxFrame.owner = f
  f.fxFrame.t = 0

  -- Diagonal shine strip faked with stacked, horizontally offset segments
  -- (rotating a solid-color texture is a no-op), clipped by fxFrame.
  f.shine = {}
  for i = 1, 6 do
    local seg = f.fxFrame:CreateTexture(nil, "OVERLAY", nil, 5)
    seg:SetColorTexture(1, 1, 1, 1)
    seg:SetBlendMode("ADD")
    seg:SetAlpha(0.14)
    seg:SetSize(24, 46)
    seg.dx = (i - 3.5) * -14
    seg.dy = (i - 3.5) * 44
    seg:Hide()
    f.shine[i] = seg
  end

  -- Edge glow behind the card (Epic+), rarity-colored.
  f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  f.glow:SetTexture(STAR)
  f.glow:SetBlendMode("ADD")
  f.glow:SetSize(CARD_W * 1.55, CARD_H * 1.25)
  f.glow:SetPoint("CENTER")
  f.glow:Hide()

  -- Shimmer border: thin outline just outside the card edge.
  f.shimmer = Ring(f, "OVERLAY", 7, -1, 1, 1, 1, 1, 1)
  HideAll(f.shimmer)

  -- Two corner sparkles on staggered loops.
  f.sparkle1 = f:CreateTexture(nil, "OVERLAY", nil, 7)
  f.sparkle1:SetTexture(STAR)
  f.sparkle1:SetBlendMode("ADD")
  f.sparkle1:SetSize(14, 14)
  f.sparkle1:SetPoint("TOPRIGHT", -8, -8)
  f.sparkle1:Hide()

  f.sparkle2 = f:CreateTexture(nil, "OVERLAY", nil, 7)
  f.sparkle2:SetTexture(STAR)
  f.sparkle2:SetBlendMode("ADD")
  f.sparkle2:SetSize(10, 10)
  f.sparkle2:SetPoint("BOTTOMLEFT", 10, 24)
  f.sparkle2:Hide()

  -- Legendary rainbow wash.
  f.wash = f:CreateTexture(nil, "OVERLAY", nil, 6)
  f.wash:SetColorTexture(1, 1, 1, 1)
  f.wash:SetBlendMode("ADD")
  f.wash:SetAlpha(0.12)
  f.wash:SetPoint("TOPLEFT", 3, -3)
  f.wash:SetPoint("BOTTOMRIGHT", -3, 3)
  f.wash:Hide()

  -- Burst stars for the legendary reveal.
  f.burst = {}
  for i = 1, BURST_STARS do
    local s = f:CreateTexture(nil, "OVERLAY", nil, 7)
    s:SetTexture(STAR)
    s:SetBlendMode("ADD")
    s:SetVertexColor(1, 0.85, 0.4)
    s:SetSize(16, 16)
    s:Hide()
    f.burst[i] = s
  end
end

local function BuildNewBadge(f)
  -- Green plate overhanging the top-left corner.
  local b = CreateFrame("Frame", nil, f)
  b:SetSize(38, 16)
  b:SetPoint("TOPLEFT", -8, 6)

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0.14, 0.36, 0.12, 1)      -- #2f7a2a -> #1d4d1a read
  bg:SetAllPoints()

  local top = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  top:SetColorTexture(0.18, 0.48, 0.16, 1)
  top:SetPoint("TOPLEFT")
  top:SetPoint("TOPRIGHT")
  top:SetHeight(8)

  Ring(b, "ARTWORK", 0, 0, 1, 0.27, 0.72, 0.24, 1)   -- #45b83e

  local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  txt:SetPoint("CENTER", 0, 0)
  txt:SetText("NEW")
  txt:SetTextColor(0.71, 1, 0.67)                    -- #b6ffab
  b.text = txt

  b:Hide()
  f.newBadge = b
end

function ns.CreateCardWidget(parent)
  local f = CreateFrame("Button", nil, parent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(CARD_W, CARD_H)
  f:SetBackdrop(BACKDROP)
  f:SetBackdropColor(0.55, 0.42, 0.28, 1)

  BuildFace(f)
  BuildBack(f)
  BuildFX(f)
  BuildNewBadge(f)

  for name, method in pairs(Card) do f[name] = method end
  f:SetScript("OnEnter", OnEnter)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end
