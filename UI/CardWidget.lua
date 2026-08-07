local ADDON_NAME, ns = ...

local CARD_W, CARD_H = 110, 150

local BACKDROP = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 14,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local Card = {}

function Card:SetFaceDown()
  self.faceUp = false
  self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  self.icon:SetVertexColor(0.6, 0.6, 0.6)
  self.nameText:SetText("|cff888888WoWTCG|r")
  self.typeText:SetText("")
  self.flavorText:SetText("")
  self.countText:SetText("")
  self.newBadge:Hide()
  self:SetBackdropBorderColor(0.45, 0.45, 0.45)
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
  local color = ns.RARITY_COLORS[card.rarity]
  if opts.silhouette then
    self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    self.icon:SetVertexColor(0.25, 0.25, 0.25)
    -- unowned Epic+ names stay hidden to preserve the chase
    self.nameText:SetText(card.rarity >= 5 and "|cff555555???|r"
      or ("|cff777777" .. card.name .. "|r"))
    self.typeText:SetText("|cff555555" .. ns.RARITY_NAMES[card.rarity] .. "|r")
    self.flavorText:SetText("")
    self.countText:SetText("")
    self.newBadge:Hide()
    self:SetBackdropBorderColor(0.3, 0.3, 0.3)
  else
    self.icon:SetTexture(card.icon)
    self.icon:SetVertexColor(1, 1, 1)
    self.nameText:SetText(ns.ColorName(card))
    self.typeText:SetText(string.format("%s %s", ns.RARITY_NAMES[card.rarity], card.type))
    self.flavorText:SetText("|cff9f9f9f" .. (card.flavor or "") .. "|r")
    self.countText:SetText((opts.count and opts.count > 1) and ("x" .. opts.count) or "")
    if opts.isNew then self.newBadge:Show() else self.newBadge:Hide() end
    self:SetBackdropBorderColor(color.r, color.g, color.b)
  end
end

-- Width-squash flip: face swaps at the halfway point.
function Card:Flip(opts, onRevealed)
  local total, half, elapsed, swapped = 0.25, 0.125, 0, false
  self:SetScript("OnUpdate", function(widget, dt)
    elapsed = elapsed + dt
    local t = math.min(elapsed / total, 1)
    widget:SetWidth(math.max(CARD_W * math.abs(math.cos(t * math.pi)), 1))
    if not swapped and elapsed >= half then
      swapped = true
      widget:SetCard(widget.card, opts)
    end
    if t >= 1 then
      widget:SetScript("OnUpdate", nil)
      widget:SetWidth(CARD_W)
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
  if self.tooltipExtra then
    GameTooltip:AddLine(self.tooltipExtra, 0.5, 1, 0.5)
  end
  GameTooltip:Show()
end

function ns.CreateCardWidget(parent)
  local f = CreateFrame("Button", nil, parent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(CARD_W, CARD_H)
  f:SetBackdrop(BACKDROP)
  f:SetBackdropColor(0.07, 0.07, 0.10, 0.95)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(64, 64)
  f.icon:SetPoint("TOP", 0, -16)

  f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.nameText:SetPoint("TOP", f.icon, "BOTTOM", 0, -6)
  f.nameText:SetWidth(CARD_W - 12)

  f.typeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.typeText:SetPoint("TOP", f.nameText, "BOTTOM", 0, -2)

  f.flavorText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.flavorText:SetPoint("BOTTOM", 0, 10)
  f.flavorText:SetWidth(CARD_W - 16)

  f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.countText:SetPoint("BOTTOMRIGHT", -6, 6)

  f.newBadge = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.newBadge:SetPoint("TOPLEFT", 6, -5)
  f.newBadge:SetText("|cff00ff88NEW|r")
  f.newBadge:Hide()

  for name, method in pairs(Card) do f[name] = method end
  f:SetScript("OnEnter", OnEnter)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end
