local ADDON_NAME, ns = ...

local Pack = {}
ns.PackUI = Pack

local CARD_W_SPACING = 126
local SOUND_OPEN = (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN) or 850
local SOUND_EPIC = (SOUNDKIT and SOUNDKIT.LEVEL_UP) or 888

local frame

local function BuildFrame()
  frame = CreateFrame("Frame", "WoWTCGPackFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(680, 320)
  frame:SetPoint("CENTER", 0, 80)
  frame:SetFrameStrata("DIALOG")
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
  frame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then Pack.RevealAll() end
  end)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOP", 0, -18)
  frame.title:SetText("Pack Opening")

  frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.hint:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)
  frame.hint:SetText("Left-click a card to reveal it — right-click to reveal all")

  frame.cards = {}
  for i = 1, ns.PACK_SIZE do
    local w = ns.CreateCardWidget(frame)
    w:SetPoint("LEFT", frame, "LEFT", 30 + (i - 1) * CARD_W_SPACING, 10)
    w:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    w:SetScript("OnClick", function(widget, button)
      if button == "RightButton" then Pack.RevealAll() else Pack.Reveal(widget) end
    end)
    frame.cards[i] = w
  end

  frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.summary:SetPoint("BOTTOM", 0, 44)

  frame.doneBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.doneBtn:SetSize(100, 22)
  frame.doneBtn:SetPoint("BOTTOM", -60, 16)
  frame.doneBtn:SetText("Done")
  frame.doneBtn:SetScript("OnClick", function() frame:Hide() end)

  frame.againBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.againBtn:SetSize(120, 22)
  frame.againBtn:SetPoint("BOTTOM", 60, 16)
  frame.againBtn:SetText("Open Another")
  frame.againBtn:SetScript("OnClick", function()
    if ns.db.packs == 0 then
      local ok, err = ns.PackSystem.BuyPack()
      if not ok then ns.Print(err) return end
    end
    Pack.Open()
  end)

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
  frame.summary:SetText("")
  frame.doneBtn:Hide()
  frame.againBtn:Hide()
  frame:Show()
  if ns.db.settings.sounds then pcall(PlaySound, SOUND_OPEN) end
end

function Pack.Reveal(widget)
  if widget.revealed or not widget.result then return end
  widget.revealed = true
  Pack.revealedCount = Pack.revealedCount + 1
  local r = widget.result
  widget:Flip({ count = r.count, isNew = r.isNew }, function(w)
    if w.card.rarity >= 5 and ns.db.settings.sounds then pcall(PlaySound, SOUND_EPIC) end
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
  local newCount, best = 0, 1
  for _, r in ipairs(Pack.results) do
    if r.isNew then newCount = newCount + 1 end
    if r.card.rarity > best then best = r.card.rarity end
  end
  frame.summary:SetText(string.format("%d new — best pull: |cff%s%s|r",
    newCount, ns.RARITY_COLORS[best].hex, ns.RARITY_NAMES[best]))
  frame.doneBtn:Show()
  frame.againBtn:Show()
  ns.ChatFlex.MaybeAnnounce(Pack.results)
  if ns.CollectionUI then ns.CollectionUI.Refresh() end
end
