# WoWTCG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A WoW Classic/Anniversary addon where gameplay earns Pack Points spent on 5-card packs of collectible WoW-themed cards across 6 rarity tiers, with a reveal UI, a collection binder, dusting, and chat flexing.

**Architecture:** Modular vanilla Lua (no external libraries), one file per concern, shared addon namespace via the `local ADDON_NAME, ns = ...` vararg. Pure-logic modules (PackSystem, PointsEngine, ChatFlex) are unit-tested outside the game against a WoW API stub; UI modules are load-tested under the stub and QA'd in game.

**Tech Stack:** Lua (WoW 5.1 dialect, tests run on the installed Lua 5.4 with shims), WoW Classic Era 1.15.x client API, git.

**Repo root:** `C:\Users\camer\Desktop\WoWTCG` (repo root IS the addon folder — it drops into `Interface\AddOns\WoWTCG`). All test commands run from the repo root: `lua tests/run.lua`. The machine's interpreter is Lua 5.4.6 at `lua`; the stub in Task 1 shims `unpack`, `math.atan2`, and `bit.band` so the same code runs on 5.1 (WoW) and 5.4 (tests).

**Spec:** `docs/superpowers/specs/2026-08-07-wowtcg-design.md` — read it first.

**Conventions for every task:**
- Addon source files ALL start with `local ADDON_NAME, ns = ...` (WoW passes these; the test loader passes `("WoWTCG", ns)`).
- Commit after each task with the message given in the task. Never batch commits across tasks.
- `lua tests/run.lua` must exit 0 (all tests pass, missing test files are skipped) at the end of every task.

---

### Task 1: Test harness (testkit + WoW API stub + runner)

**Files:**
- Create: `tests/testkit.lua`
- Create: `tests/wow_api_stub.lua`
- Create: `tests/run.lua`

- [ ] **Step 1: Write `tests/testkit.lua`**

```lua
-- Tiny test framework. Usage: T.test(name, fn); assertions T.eq/T.ok.
local T = { passed = 0, failed = 0 }

function T.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    T.passed = T.passed + 1
    print("PASS  " .. name)
  else
    T.failed = T.failed + 1
    print("FAIL  " .. name .. "\n      " .. tostring(err))
  end
end

function T.eq(got, want, msg)
  if got ~= want then
    error((msg or "eq") .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
  end
end

function T.ok(v, msg)
  if not v then error(msg or "expected truthy", 2) end
end

function T.finish()
  print(string.format("== %d passed, %d failed ==", T.passed, T.failed))
  return T.failed == 0 and 0 or 1
end

return T
```

- [ ] **Step 2: Write `tests/wow_api_stub.lua`**

```lua
-- Minimal WoW Classic API stub so WoWTCG logic runs under plain Lua 5.1/5.4.
local Stub = {}

-- Lua 5.1 / 5.4 compatibility shims
_G.unpack = _G.unpack or table.unpack
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

Stub.frames = {}       -- every frame ever created
Stub.messages = {}     -- DEFAULT_CHAT_FRAME:AddMessage captures
Stub.chatSent = {}     -- SendChatMessage captures {msg=, chan=}
Stub.sounds = {}       -- PlaySound captures
Stub.chatFilters = {}  -- ChatFrame_AddMessageEventFilter captures {event=, fn=}
Stub.hooks = {}        -- hooksecurefunc captures [name] = fn
Stub.timers = {}       -- C_Timer.After captures {delay=, fn=}
Stub.combatLog = {}    -- payload returned by CombatLogGetCurrentEventInfo

local function noop() end

-- Textures / FontStrings: capture SetText/GetText, no-op everything else.
local regionMT = {
  __index = function(t, k)
    if k == "SetText" then return function(self, text) self._text = text end end
    if k == "GetText" then return function(self) return self._text end end
    return noop
  end,
}
local function newRegion() return setmetatable({}, regionMT) end

local frameMethods = {}
local frameMT = { __index = function(t, k) return frameMethods[k] or noop end }

function frameMethods:RegisterEvent(e) self._events[e] = true end
function frameMethods:UnregisterEvent(e) self._events[e] = nil end
function frameMethods:SetScript(handler, fn) self._scripts[handler] = fn end
function frameMethods:GetScript(handler) return self._scripts[handler] end
function frameMethods:Show() self._shown = true end
function frameMethods:Hide() self._shown = false end
function frameMethods:IsShown() return self._shown end
function frameMethods:GetName() return self._name end
function frameMethods:CreateTexture() return newRegion() end
function frameMethods:CreateFontString() return newRegion() end
function frameMethods:GetCenter() return 0, 0 end
function frameMethods:GetEffectiveScale() return 1 end

local function newFrame(ftype, name, parent, template)
  local f = setmetatable({
    _type = ftype or "Frame", _name = name, _parent = parent,
    _template = template, _events = {}, _scripts = {}, _shown = false,
  }, frameMT)
  table.insert(Stub.frames, f)
  if name then _G[name] = f end
  return f
end

-- Fire an event at every frame registered for it.
function Stub.FireEvent(event, ...)
  for _, f in ipairs(Stub.frames) do
    if f._events[event] and f._scripts.OnEvent then
      f._scripts.OnEvent(f, event, ...)
    end
  end
end

function Stub.ResetCaptures()
  Stub.messages, Stub.chatSent, Stub.sounds = {}, {}, {}
end

-- Load an addon file the way WoW does: chunk receives (addonName, namespace).
function Stub.LoadAddonFile(path, ns)
  local chunk, err = loadfile(path)
  assert(chunk, err)
  return chunk("WoWTCG", ns)
end

function Stub.FreshDB(ns)
  _G.WoWTCG_DB = nil
  return ns.InitDB()
end

function Stub.install()
  _G.CreateFrame = function(ftype, name, parent, template)
    return newFrame(ftype, name, parent, template)
  end
  _G.UIParent = newFrame("Frame", "UIParent")
  _G.Minimap = newFrame("Frame", "Minimap")
  _G.GameTooltip = newFrame("GameTooltip", "GameTooltip")
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(Stub.messages, msg) end }
  _G.SlashCmdList = {}
  _G.UISpecialFrames = {}
  _G.StaticPopupDialogs = {}
  _G.StaticPopup_Show = function(which)  -- auto-accept in tests
    local d = StaticPopupDialogs[which]
    if d and d.OnAccept then d.OnAccept() end
  end
  _G.SendChatMessage = function(msg, chan) table.insert(Stub.chatSent, { msg = msg, chan = chan }) end
  _G.PlaySound = function(id) table.insert(Stub.sounds, id) end
  _G.ChatFrame_AddMessageEventFilter = function(event, fn)
    table.insert(Stub.chatFilters, { event = event, fn = fn })
  end
  _G.hooksecurefunc = function(name, fn) Stub.hooks[name] = fn end
  _G.CombatLogGetCurrentEventInfo = function() return unpack(Stub.combatLog) end
  _G.C_Timer = { After = function(delay, fn) table.insert(Stub.timers, { delay = delay, fn = fn }) end }
  _G.GetTime = os.clock
  _G.GetCursorPosition = function() return 0, 0 end
  _G.UnitName = function() return "Tester" end
  _G.UnitGUID = function() return "Player-0000-000001" end
  _G.UnitLevel = function() return 60 end
  _G.tinsert = table.insert
  _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  _G.strsplit = function(delim, s)
    local parts = {}
    for piece in (s .. delim):gmatch("(.-)" .. delim:gsub("%p", "%%%1")) do
      parts[#parts + 1] = piece
    end
    return unpack(parts)
  end
  _G.bit = _G.bit or {
    band = function(a, b)
      local r, p = 0, 1
      while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
      end
      return r
    end,
  }
  _G.COMBATLOG_OBJECT_AFFILIATION_MINE = 0x00000001
  _G.ERR_ZONE_EXPLORED = "Discovered %s"
  _G.ERR_ZONE_EXPLORED_XP = "Discovered %s: %d experience gained"
  _G.BackdropTemplateMixin = {}
  _G.SOUNDKIT = { IG_MAINMENU_OPEN = 850, LEVEL_UP = 888 }
end

return Stub
```

- [ ] **Step 3: Write `tests/run.lua`**

```lua
-- Run all WoWTCG tests. Usage (from repo root): lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local Stub = require("wow_api_stub")
Stub.install()

local T = require("testkit")

local files = {
  "test_core", "test_cards", "test_packsystem",
  "test_pointsengine", "test_chatflex", "test_slash", "test_ui_load",
}

for _, f in ipairs(files) do
  local fh = io.open("tests/" .. f .. ".lua", "r")
  if fh then
    fh:close()
    require(f)
  else
    print("skip  " .. f .. " (not written yet)")
  end
end

os.exit(T.finish())
```

- [ ] **Step 4: Run the harness**

Run (from `C:\Users\camer\Desktop\WoWTCG`): `lua tests/run.lua`
Expected: seven `skip` lines, then `== 0 passed, 0 failed ==`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add tests
git commit -m "Add pure-Lua test harness with WoW API stub"
```

---

### Task 2: TOC + Core.lua (constants, DB, points)

**Files:**
- Create: `WoWTCG.toc`
- Create: `Core.lua`
- Create: `tests/test_core.lua`

- [ ] **Step 1: Write the failing test `tests/test_core.lua`**

```lua
local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)

T.test("DeepFill fills missing keys and preserves existing", function()
  local dst = { a = 1, sub = { x = 5 } }
  ns.DeepFill(dst, { a = 9, b = 2, sub = { x = 0, y = 3 } })
  T.eq(dst.a, 1); T.eq(dst.b, 2); T.eq(dst.sub.x, 5); T.eq(dst.sub.y, 3)
end)

T.test("InitDB creates defaults", function()
  local db = Stub.FreshDB(ns)
  T.eq(db.points, 0); T.eq(db.packs, 0); T.eq(db.version, 1)
  T.eq(db.settings.announceChannel, "OFF")
  T.eq(db.settings.announceMinRarity, 5)
  T.eq(db.pity.epic, 0); T.eq(db.pity.legendary, 0)
end)

T.test("InitDB preserves existing values and backfills the rest", function()
  _G.WoWTCG_DB = { points = 42, settings = { announceChannel = "GUILD" } }
  local db = ns.InitDB()
  T.eq(db.points, 42)
  T.eq(db.settings.announceChannel, "GUILD")
  T.eq(db.settings.sounds, true)
end)

T.test("AddPoints accumulates and tracks reasons", function()
  local db = Stub.FreshDB(ns)
  ns.AddPoints(25, "QUEST"); ns.AddPoints(2, "KILL"); ns.AddPoints(25, "QUEST")
  T.eq(db.points, 52)
  T.eq(db.stats.totalPoints, 52)
  T.eq(db.stats.byReason.QUEST, 50)
  T.eq(db.stats.byReason.KILL, 2)
end)

T.test("AddPoints ignores nil, zero, and negative amounts", function()
  local db = Stub.FreshDB(ns)
  ns.AddPoints(nil, "X"); ns.AddPoints(0, "X"); ns.AddPoints(-5, "X")
  T.eq(db.points, 0)
end)

T.test("rarity tables cover all six tiers", function()
  T.eq(#ns.RARITY_NAMES, 6)
  T.eq(ns.RARITY_COLORS[6].hex, "ff8000")
  T.eq(ns.DUST_VALUES[6], 150)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: crash loading test_core (`Core.lua` missing / attempt to call nil). Non-zero exit.

- [ ] **Step 3: Write `WoWTCG.toc`**

Note: lists files created in later tasks — that's fine, the addon is only installed once all exist. Backslashes are the TOC path convention.

```
## Interface: 11507
## Title: WoWTCG
## Notes: Collect cards by playing the game. Type /tcg to open your collection.
## Author: Cameron
## Version: 0.1.0
## SavedVariables: WoWTCG_DB

Core.lua
Data\Cards.lua
PointsEngine.lua
PackSystem.lua
ChatFlex.lua
UI\CardWidget.lua
UI\PackOpening.lua
UI\Collection.lua
```

- [ ] **Step 4: Write `Core.lua`**

```lua
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
```

- [ ] **Step 5: Run to verify pass**

Run: `lua tests/run.lua`
Expected: 6 PASS lines from test_core, `0 failed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add WoWTCG.toc Core.lua tests/test_core.lua
git commit -m "Add TOC and Core: constants, SavedVariables, Pack Points"
```

---

### Task 3: Card database (~300 curated cards)

**Files:**
- Create: `Data/Cards.lua`
- Create: `tests/test_cards.lua`

- [ ] **Step 1: Write the failing test `tests/test_cards.lua`**

```lua
local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)
Stub.LoadAddonFile("Data/Cards.lua", ns)

local EXPECTED = { [1] = 40, [2] = 90, [3] = 80, [4] = 55, [5] = 25, [6] = 10 }

T.test("card count is 300 with the exact rarity distribution", function()
  T.eq(#ns.CARDS, 300, "total cards")
  local counts = { 0, 0, 0, 0, 0, 0 }
  for _, c in ipairs(ns.CARDS) do counts[c.rarity] = counts[c.rarity] + 1 end
  for r = 1, 6 do T.eq(counts[r], EXPECTED[r], "rarity " .. r .. " count") end
end)

T.test("every card is well-formed with a unique id", function()
  local seen = {}
  for _, c in ipairs(ns.CARDS) do
    T.ok(type(c.id) == "number", "id must be a number")
    T.ok(not seen[c.id], "duplicate id " .. tostring(c.id))
    seen[c.id] = true
    T.ok(type(c.name) == "string" and #c.name > 0, "name for id " .. tostring(c.id))
    T.ok(c.rarity >= 1 and c.rarity <= 6, "rarity for id " .. tostring(c.id))
    T.ok(c.type == "SPELL" or c.type == "NPC" or c.type == "ITEM", "type for id " .. tostring(c.id))
    T.ok(type(c.icon) == "string" and c.icon:find("^Interface\\Icons\\") ~= nil,
      "icon path for id " .. tostring(c.id))
    T.ok(type(c.flavor) == "string" and #c.flavor > 0, "flavor for id " .. tostring(c.id))
  end
end)

T.test("lookup indexes are consistent", function()
  local n = 0
  for r = 1, 6 do n = n + #ns.CardsByRarity[r] end
  T.eq(n, #ns.CARDS, "CardsByRarity total")
  for _, c in ipairs(ns.CARDS) do
    T.eq(ns.CardsById[c.id], c, "CardsById for " .. tostring(c.id))
  end
end)

T.test("every tier contains all three card types", function()
  for r = 1, 6 do
    local types = {}
    for _, c in ipairs(ns.CardsByRarity[r]) do types[c.type] = true end
    T.ok(types.SPELL and types.NPC and types.ITEM, "tier " .. r .. " is missing a type")
  end
end)

T.test("card names are unique", function()
  local seen = {}
  for _, c in ipairs(ns.CARDS) do
    T.ok(not seen[c.name], "duplicate name " .. c.name)
    seen[c.name] = true
  end
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: crash loading test_cards (Data/Cards.lua missing).

- [ ] **Step 3: Write `Data/Cards.lua`**

File skeleton (the `...` in the middle is where the full 300-card set goes — this is a
**data-authoring step**, see the authoring brief below; it is complete when the tests
in Step 1 pass):

```lua
local ADDON_NAME, ns = ...

-- WoWTCG card set "Classic Vol. 1".
-- rarity: 1 Junk, 2 Common, 3 Uncommon, 4 Rare, 5 Epic, 6 Legendary
-- type:   SPELL | NPC | ITEM
-- id ranges (convention only): 100-299 spells, 300-499 NPCs, 500-699 items.
-- IDs are permanent — never reuse or renumber (they live in players' SavedVariables).
ns.CARDS = {
  -- ... 300 cards ...
}

ns.CardsById = {}
ns.CardsByRarity = { {}, {}, {}, {}, {}, {} }
for _, card in ipairs(ns.CARDS) do
  ns.CardsById[card.id] = card
  table.insert(ns.CardsByRarity[card.rarity], card)
end
```

**Authoring brief for the 300 cards** — exact requirements (enforced by tests):
- Exactly 40 Junk, 90 Common, 80 Uncommon, 55 Rare, 25 Epic, 10 Legendary.
- Every tier includes at least one SPELL, one NPC, and one ITEM.
- Unique ids, unique names, non-empty flavor on every card.
- Icons must be `Interface\\Icons\\<name>` (double backslash in Lua source).

Tone and content guidance (not test-enforced, but required for quality):
- **Junk:** literal vendor trash and gray-quality jokes — Broken Fang, Ruined Pelt,
  Murloc Fin, Soggy Bread, a lost Defias bandana; NPCs like a common sewer rat or
  Stormwind street urchin; spells like a fizzled cantrip.
- **Common:** everyday Classic staples — Fireball, Frostbolt, Charge, a Stormwind
  Guard, Linen Bandage, Minor Healing Potion, boars/wolves/kobolds ("You no take candle!").
- **Uncommon:** class-defining spells (Polymorph, Execute, Ambush), notable-but-minor
  NPCs (Hogger deserves at least Uncommon — pick your spots), green-quality gear.
- **Rare:** dungeon bosses (Van Cleef, Herod, Thermaplugg), iconic CDs (Lay on Hands,
  Divine Shield), blue gear, rare spawns (the Ghost Saber, Time-Lost Proto no — keep
  it Classic-only).
- **Epic:** raid lieutenants (Majordomo, Ebonroc), epic mounts, epic weapons
  (Ashkandi-tier), pinnacle spells (Power Infusion, Soulstone Resurrection).
- **Legendary (exactly 10):** the Classic pantheon. Required inclusions: Ragnaros,
  Onyxia, Thunderfury Blessed Blade of the Windseeker, Sulfuras Hand of Ragnaros.
  Fill the rest from: Nefarian, C'Thun, Kel'Thuzad, Hakkar, Azuregos, Kazzak,
  a legendary-feel SPELL (e.g. Divine Intervention), Atiesh. Keep at least one
  SPELL, one NPC, one ITEM in the tier.
- Flavor text: one short sentence, lore-aware, lightly funny. No lorem ipsum.
- Everything must be WoW Classic (1.12-era) content only — no Outland, no Northrend.

**Icon safety:** if you are not CERTAIN an icon path exists in the 1.15 Classic
client, use one of these known-good paths instead (all verified Classic icons):

```
Spell_Fire_FlameBolt, Spell_Fire_FireBolt02, Spell_Fire_Fireball02, Spell_Fire_Immolation,
Spell_Fire_SelfDestruct, Spell_Fire_Volcano, Spell_Frost_FrostBolt02, Spell_Frost_FrostNova,
Spell_Frost_IceStorm, Spell_Frost_FrostArmor02, Spell_Nature_Lightning, Spell_Nature_ChainLightning,
Spell_Nature_HealingTouch, Spell_Nature_Rejuvenation, Spell_Nature_Regenerate, Spell_Nature_Polymorph,
Spell_Nature_EarthBind, Spell_Holy_HolyBolt, Spell_Holy_FlashHeal, Spell_Holy_GreaterHeal,
Spell_Holy_PowerWordShield, Spell_Holy_SealOfMight, Spell_Holy_Resurrection, Spell_Shadow_ShadowBolt,
Spell_Shadow_ShadowWordPain, Spell_Shadow_Possession, Spell_Shadow_RaiseDead, Spell_Shadow_SummonImp,
Spell_Shadow_SummonVoidWalker, Spell_Shadow_DeathCoil, Spell_Arcane_Blink,
Ability_Warrior_Charge, Ability_Warrior_BattleShout, Ability_Warrior_Sunder, Ability_Warrior_ShieldWall,
Ability_Rogue_Ambush, Ability_Rogue_Eviscerate, Ability_Rogue_Sprint, Ability_BackStab, Ability_Stealth,
Ability_Kick, Ability_Defend, Ability_ShootWand, Ability_Marksmanship, Ability_Whirlwind,
Ability_Druid_CatForm, Ability_Racial_BearForm, Ability_Mount_PinkTiger, Ability_Mount_WhiteTiger,
Ability_Mount_RidingHorse, Ability_Mount_Undeadhorse, Ability_Mount_MountainRam, Ability_Mount_Raptor,
Ability_Mount_Kodo, Ability_Creature_Cursed_02,
INV_Sword_04, INV_Sword_25, INV_Sword_39, INV_Hammer_Unique_Sulfuras, INV_Mace_01, INV_Axe_09,
INV_Axe_12, INV_Staff_13, INV_Shield_05, INV_Chest_Cloth_17, INV_Shirt_White_01, INV_Boots_05,
INV_Gauntlets_04, INV_Misc_Coin_01, INV_Misc_Coin_02, INV_Misc_Coin_06, INV_Misc_Gem_Pearl_03,
INV_Misc_Gem_Ruby_02, INV_Misc_Gem_Sapphire_02, INV_Misc_Rune_01, INV_Misc_Key_03, INV_Misc_Bag_08,
INV_Misc_Food_01, INV_Misc_Food_11, INV_Misc_Food_15, INV_Drink_05, INV_Potion_51, INV_Potion_52,
INV_Potion_54, INV_Fishingpole_02, INV_Misc_Fish_02, INV_Scroll_01, INV_Scroll_02, INV_Misc_Book_01,
INV_Misc_Book_07, INV_Misc_Book_09, INV_Misc_Note_01, INV_Misc_Note_02, INV_Misc_Map_01,
INV_Misc_Flower_02, INV_Misc_Herb_03, INV_Misc_Dust_02, INV_Misc_Pelt_Wolf_01, INV_Feather_02,
INV_Misc_Bone_01, INV_Misc_Bone_HumanSkull_01, INV_Misc_MonsterClaw_01, INV_Misc_MonsterClaw_04,
INV_Misc_MonsterFang_01, INV_Misc_MonsterScales_02, INV_Misc_Head_Dragon_01, INV_Misc_Bomb_04,
INV_Misc_Bomb_05, INV_Musket_03, INV_Jewelry_Ring_03, INV_Misc_QuestionMark
```

Example cards showing the exact format and tone (include these verbatim as the
start of the set — they count toward the totals):

```lua
  -- === SPELLS (100-299) ===
  { id = 100, name = "Fireball", type = "SPELL", rarity = 2, icon = "Interface\\Icons\\Spell_Fire_FlameBolt", flavor = "The classic. Accept no substitutes." },
  { id = 101, name = "Frostbolt", type = "SPELL", rarity = 2, icon = "Interface\\Icons\\Spell_Frost_FrostBolt02", flavor = "Slows them down. Permanently, if you're lucky." },
  { id = 102, name = "Charge", type = "SPELL", rarity = 2, icon = "Interface\\Icons\\Ability_Warrior_Charge", flavor = "The warrior solution to every problem, including doors." },
  { id = 103, name = "Polymorph", type = "SPELL", rarity = 3, icon = "Interface\\Icons\\Spell_Nature_Polymorph", flavor = "Baa. Please do not kill the sheep." },
  { id = 104, name = "Execute", type = "SPELL", rarity = 3, icon = "Interface\\Icons\\Ability_Rogue_Eviscerate", flavor = "For when 20% is close enough to zero." },
  { id = 105, name = "Lay on Hands", type = "SPELL", rarity = 4, icon = "Interface\\Icons\\Spell_Holy_GreaterHeal", flavor = "Once an hour, a paladin remembers they can do this." },
  { id = 106, name = "Power Infusion", type = "SPELL", rarity = 5, icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", flavor = "The mage will ask for this every cooldown. Every one." },
  { id = 107, name = "Divine Intervention", type = "SPELL", rarity = 6, icon = "Interface\\Icons\\Spell_Holy_Resurrection", flavor = "The paladin dies so the wipe doesn't have to." },
  { id = 108, name = "Fizzle", type = "SPELL", rarity = 1, icon = "Interface\\Icons\\Spell_Fire_SelfDestruct", flavor = "Your spell failed. Your dignity, too." },
  { id = 109, name = "Hearthstone", type = "SPELL", rarity = 3, icon = "Interface\\Icons\\INV_Misc_Rune_01", flavor = "Home is where the innkeeper is." },
  -- === NPCS (300-499) ===
  { id = 300, name = "Stormwind Guard", type = "NPC", rarity = 2, icon = "Interface\\Icons\\Ability_Defend", flavor = "Can direct you to the bank, the auction house, and your death in Westfall." },
  { id = 301, name = "Kobold Miner", type = "NPC", rarity = 2, icon = "Interface\\Icons\\INV_Misc_Coin_02", flavor = "You no take candle!" },
  { id = 302, name = "Murloc", type = "NPC", rarity = 2, icon = "Interface\\Icons\\INV_Misc_Fish_02", flavor = "Mrglglglgl. You already know what that sound means." },
  { id = 303, name = "Hogger", type = "NPC", rarity = 3, icon = "Interface\\Icons\\INV_Misc_MonsterClaw_01", flavor = "Elwynn Forest's first raid boss." },
  { id = 304, name = "Edwin VanCleef", type = "NPC", rarity = 4, icon = "Interface\\Icons\\Ability_Rogue_Ambush", flavor = "The labor dispute that ended in forty dead adventurers a day." },
  { id = 305, name = "Majordomo Executus", type = "NPC", rarity = 5, icon = "Interface\\Icons\\Spell_Fire_Volcano", flavor = "The only boss polite enough to announce his own boss." },
  { id = 306, name = "Ragnaros", type = "NPC", rarity = 6, icon = "Interface\\Icons\\Spell_Fire_Volcano", flavor = "TOO SOON! You have awakened him TOO SOON, Executus!" },
  { id = 307, name = "Onyxia", type = "NPC", rarity = 6, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", flavor = "Handle the whelps. MANY whelps. Fifty DKP minus." },
  { id = 308, name = "Sewer Rat", type = "NPC", rarity = 1, icon = "Interface\\Icons\\INV_Misc_MonsterFang_01", flavor = "Undercity's most reliable resident." },
  -- === ITEMS (500-699) ===
  { id = 500, name = "Broken Fang", type = "ITEM", rarity = 1, icon = "Interface\\Icons\\INV_Misc_Bone_01", flavor = "Worth four copper to exactly one vendor." },
  { id = 501, name = "Soggy Bread", type = "ITEM", rarity = 1, icon = "Interface\\Icons\\INV_Misc_Food_11", flavor = "It was bread once. Technically it still is." },
  { id = 502, name = "Linen Bandage", type = "ITEM", rarity = 2, icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", flavor = "First aid for people who refuse to bring a healer." },
  { id = 503, name = "Minor Healing Potion", type = "ITEM", rarity = 2, icon = "Interface\\Icons\\INV_Potion_51", flavor = "Emergency red juice. Save it for a real emergency. You won't." },
  { id = 504, name = "Deadman's Hand", type = "ITEM", rarity = 4, icon = "Interface\\Icons\\INV_Jewelry_Ring_03", flavor = "Dealt from the bottom of the Scarlet Monastery." },
  { id = 505, name = "Sulfuras, Hand of Ragnaros", type = "ITEM", rarity = 6, icon = "Interface\\Icons\\INV_Hammer_Unique_Sulfuras", flavor = "Forty-five people, months of work, one very happy tank." },
  { id = 506, name = "Thunderfury, Blessed Blade of the Windseeker", type = "ITEM", rarity = 6, icon = "Interface\\Icons\\INV_Sword_39", flavor = "Did someone say...?" },
```

- [ ] **Step 4: Run to verify pass**

Run: `lua tests/run.lua`
Expected: all card tests PASS (counts exact, ids/names unique), exit 0.

- [ ] **Step 5: Commit**

```bash
git add Data/Cards.lua tests/test_cards.lua
git commit -m "Add Classic Vol. 1 card set: 300 curated cards across 6 tiers"
```

---

### Task 4: PackSystem (rolls, floor, pity, dusting)

**Files:**
- Create: `PackSystem.lua`
- Create: `tests/test_packsystem.lua`

- [ ] **Step 1: Write the failing test `tests/test_packsystem.lua`**

```lua
local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)
Stub.LoadAddonFile("Data/Cards.lua", ns)
Stub.LoadAddonFile("PackSystem.lua", ns)
local PS = ns.PackSystem

-- Deterministic RNG for tests. Uses high bits (low LCG bits are weak).
local function lcg(seed)
  local s = seed
  return function(n)
    s = (s * 1103515245 + 12345) % 2147483648
    return (math.floor(s / 65536) % n) + 1
  end
end

-- Always returns min(v, n): pins rarity rolls while staying in range for card picks.
local function fixedRoll(v)
  return function(n) return math.min(v, n) end
end

local function bestOf(cards)
  local best = 0
  for _, c in ipairs(cards) do best = math.max(best, c.rarity) end
  return best
end

T.test("RollRarity matches weights over 100k rolls", function()
  ns.rng = lcg(42)
  local counts = { 0, 0, 0, 0, 0, 0 }
  local N = 100000
  for _ = 1, N do
    local r = PS.RollRarity()
    counts[r] = counts[r] + 1
  end
  ns.rng = nil
  for r = 1, 6 do
    local pct = counts[r] / N * 100
    T.ok(math.abs(pct - ns.RARITY_WEIGHTS[r]) < 1.5,
      string.format("rarity %d: got %.2f%%, want %d%%", r, pct, ns.RARITY_WEIGHTS[r]))
  end
end)

T.test("pack floor guarantees at least one Uncommon+", function()
  ns.rng = fixedRoll(10)  -- always rolls Junk
  local db = Stub.FreshDB(ns)
  local cards = PS.RollPack(db)
  ns.rng = nil
  T.eq(#cards, 5)
  T.ok(bestOf(cards) >= 3, "floored pack must contain an Uncommon+")
end)

T.test("epic pity forces Epic+ on the 10th barren pack and resets", function()
  ns.rng = fixedRoll(30)  -- always rolls Common
  local db = Stub.FreshDB(ns)
  for i = 1, 9 do
    T.ok(bestOf(PS.RollPack(db)) < 5, "unexpected Epic before pity, pack " .. i)
  end
  T.eq(db.pity.epic, 9)
  T.ok(bestOf(PS.RollPack(db)) >= 5, "10th pack must contain Epic+")
  T.eq(db.pity.epic, 0, "epic pity must reset")
  ns.rng = nil
end)

T.test("legendary pity forces a Legendary on the 40th pack and resets", function()
  ns.rng = fixedRoll(30)
  local db = Stub.FreshDB(ns)
  for i = 1, 39 do
    local cards = PS.RollPack(db)
    for _, c in ipairs(cards) do
      T.ok(c.rarity < 6, "unexpected Legendary at pack " .. i)
    end
  end
  T.eq(db.pity.legendary, 39)
  T.eq(bestOf(PS.RollPack(db)), 6, "40th pack must contain a Legendary")
  T.eq(db.pity.legendary, 0)
  ns.rng = nil
end)

T.test("BuyPack requires 100 points", function()
  local db = Stub.FreshDB(ns)
  db.points = 99
  T.eq(PS.BuyPack(db), false)
  db.points = 150
  T.eq(PS.BuyPack(db), true)
  T.eq(db.points, 50)
  T.eq(db.packs, 1)
end)

T.test("OpenPack consumes a pack and fills the collection", function()
  ns.rng = lcg(7)
  local db = Stub.FreshDB(ns)
  T.eq(PS.OpenPack(db), nil, "opening with zero packs must fail")
  db.packs = 1
  local results = PS.OpenPack(db)
  ns.rng = nil
  T.eq(#results, 5)
  T.eq(db.packs, 0)
  T.eq(db.stats.packsOpened, 1)
  for _, r in ipairs(results) do
    T.ok(db.collection[r.card.id] >= 1, "card not in collection")
    T.ok(r.count >= 1)
  end
end)

T.test("first pull is new, repeat pull is a dupe with a count", function()
  local db = Stub.FreshDB(ns)
  db.packs = 2
  ns.rng = fixedRoll(1)  -- same cards every pack
  local first = PS.OpenPack(db)
  local second = PS.OpenPack(db)
  ns.rng = nil
  T.eq(first[1].isNew, true)
  T.eq(second[1].isNew, false)
  T.ok(second[1].count > 1, "dupe must have count > 1")
end)

T.test("DustCard: never the last copy, value by rarity", function()
  local db = Stub.FreshDB(ns)
  local card = ns.CardsByRarity[6][1]
  db.collection[card.id] = 1
  T.eq(PS.DustCard(db, card.id), false, "cannot dust the last copy")
  db.collection[card.id] = 3
  local ok, value = PS.DustCard(db, card.id)
  T.eq(ok, true)
  T.eq(value, 150)
  T.eq(db.collection[card.id], 2)
  T.eq(db.points, 150)
end)

T.test("DustAllDupes leaves one of each and sums values", function()
  local db = Stub.FreshDB(ns)
  local c1 = ns.CardsByRarity[1][1]
  local c6 = ns.CardsByRarity[6][1]
  db.collection[c1.id] = 4   -- 3 junk dupes  -> 3 points
  db.collection[c6.id] = 2   -- 1 legendary dupe -> 150 points
  T.eq(PS.DustAllDupes(db), 153)
  T.eq(db.collection[c1.id], 1)
  T.eq(db.collection[c6.id], 1)
  T.eq(db.points, 153)
end)

T.test("forceLegendary debug flag guarantees a Legendary once", function()
  ns.rng = fixedRoll(30)
  local db = Stub.FreshDB(ns)
  ns.forceLegendary = true
  T.eq(bestOf(PS.RollPack(db)), 6)
  T.ok(not ns.forceLegendary, "flag must clear after use")
  ns.rng = nil
end)

T.test("CompletionStats counts owned per rarity", function()
  local db = Stub.FreshDB(ns)
  db.collection[ns.CardsByRarity[2][1].id] = 1
  db.collection[ns.CardsByRarity[2][2].id] = 3
  local owned, total, byRarity = PS.CompletionStats(db)
  T.eq(owned, 2)
  T.eq(total, 300)
  T.eq(byRarity[2].owned, 2)
  T.eq(byRarity[2].total, 90)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: crash loading test_packsystem (PackSystem.lua missing).

- [ ] **Step 3: Write `PackSystem.lua`**

```lua
local ADDON_NAME, ns = ...

local PackSystem = {}
ns.PackSystem = PackSystem

ns.RARITY_WEIGHTS = { 20, 45, 20, 10, 4, 1 }  -- percent per tier; sums to 100
ns.PITY_EPIC      = 10
ns.PITY_LEGENDARY = 40

-- Tests override ns.rng with a deterministic function.
local function rng(n)
  return (ns.rng or math.random)(n)
end

function PackSystem.RollRarity()
  local roll, acc = rng(100), 0
  for rarity = 1, 6 do
    acc = acc + ns.RARITY_WEIGHTS[rarity]
    if roll <= acc then return rarity end
  end
  return 1
end

function PackSystem.PickCard(rarity)
  local pool = ns.CardsByRarity[rarity]
  while (not pool or #pool == 0) and rarity > 1 do
    rarity = rarity - 1
    pool = ns.CardsByRarity[rarity]
  end
  return pool[rng(#pool)]
end

local function Best(rarities)
  local b = 0
  for i = 1, #rarities do if rarities[i] > b then b = rarities[i] end end
  return b
end

local function LowestSlot(rarities)
  local slot, lo = 1, rarities[1]
  for i = 2, #rarities do
    if rarities[i] < lo then slot, lo = i, rarities[i] end
  end
  return slot
end

function PackSystem.RollPack(db)
  db = db or ns.db
  local rarities = {}
  for i = 1, ns.PACK_SIZE do rarities[i] = PackSystem.RollRarity() end

  -- floor: every pack contains at least one Uncommon+
  if Best(rarities) < 3 then rarities[LowestSlot(rarities)] = 3 end

  db.pity.epic = db.pity.epic + 1
  db.pity.legendary = db.pity.legendary + 1

  if ns.forceLegendary then
    rarities[LowestSlot(rarities)] = 6
    ns.forceLegendary = nil
  end
  if db.pity.legendary >= ns.PITY_LEGENDARY and Best(rarities) < 6 then
    rarities[LowestSlot(rarities)] = 6
  end
  if db.pity.epic >= ns.PITY_EPIC and Best(rarities) < 5 then
    rarities[LowestSlot(rarities)] = 5
  end
  if Best(rarities) >= 6 then db.pity.legendary = 0 end
  if Best(rarities) >= 5 then db.pity.epic = 0 end

  local cards = {}
  for i = 1, ns.PACK_SIZE do cards[i] = PackSystem.PickCard(rarities[i]) end
  return cards
end

function PackSystem.BuyPack(db)
  db = db or ns.db
  if db.points < ns.PACK_COST then
    return false, string.format("not enough Pack Points (%d/%d)", db.points, ns.PACK_COST)
  end
  db.points = db.points - ns.PACK_COST
  db.packs = db.packs + 1
  ns.NotifyPointsChanged()
  return true
end

function PackSystem.OpenPack(db)
  db = db or ns.db
  if db.packs < 1 then return nil, "no unopened packs — /tcg buy" end
  db.packs = db.packs - 1
  local cards = PackSystem.RollPack(db)
  local results = {}
  for i, card in ipairs(cards) do
    local owned = db.collection[card.id] or 0
    db.collection[card.id] = owned + 1
    results[i] = { card = card, isNew = owned == 0, count = owned + 1 }
  end
  db.stats.packsOpened = db.stats.packsOpened + 1
  ns.NotifyPointsChanged()
  return results
end

function PackSystem.DustCard(db, cardID)
  db = db or ns.db
  local count = db.collection[cardID] or 0
  if count < 2 then return false, "no duplicate to dust" end
  local card = ns.CardsById[cardID]
  if not card then return false, "unknown card" end
  local value = ns.DUST_VALUES[card.rarity]
  db.collection[cardID] = count - 1
  db.points = db.points + value
  db.stats.dusted = db.stats.dusted + value
  ns.NotifyPointsChanged()
  return true, value
end

function PackSystem.DustAllDupes(db)
  db = db or ns.db
  local total = 0
  for cardID, count in pairs(db.collection) do
    if count > 1 then
      local card = ns.CardsById[cardID]
      if card then
        total = total + ns.DUST_VALUES[card.rarity] * (count - 1)
        db.collection[cardID] = 1
      end
    end
  end
  if total > 0 then
    db.points = db.points + total
    db.stats.dusted = db.stats.dusted + total
    ns.NotifyPointsChanged()
  end
  return total
end

function PackSystem.CompletionStats(db)
  db = db or ns.db
  local ownedTotal = 0
  local byRarity = {}
  for r = 1, 6 do byRarity[r] = { owned = 0, total = #ns.CardsByRarity[r] } end
  for _, card in ipairs(ns.CARDS) do
    if (db.collection[card.id] or 0) > 0 then
      ownedTotal = ownedTotal + 1
      byRarity[card.rarity].owned = byRarity[card.rarity].owned + 1
    end
  end
  return ownedTotal, #ns.CARDS, byRarity
end
```

- [ ] **Step 4: Run to verify pass**

Run: `lua tests/run.lua`
Expected: all packsystem tests PASS, exit 0. (The 100k-roll test takes a moment.)

- [ ] **Step 5: Commit**

```bash
git add PackSystem.lua tests/test_packsystem.lua
git commit -m "Add PackSystem: weighted rolls, pack floor, pity, dusting"
```

---

### Task 5: PointsEngine (gameplay events → points)

**Files:**
- Create: `PointsEngine.lua`
- Create: `tests/test_pointsengine.lua`

- [ ] **Step 1: Write the failing test `tests/test_pointsengine.lua`**

```lua
local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)
Stub.LoadAddonFile("PointsEngine.lua", ns)
local PE = ns.PointsEngine

PE.Register()

local function fresh()
  Stub.ResetCaptures()
  return Stub.FreshDB(ns)
end

T.test("PatternFromFormat converts %s and %d and anchors", function()
  local p = PE.PatternFromFormat("Discovered %s: %d experience gained")
  T.ok(("Discovered Elwynn Forest: 25 experience gained"):find(p) ~= nil, "should match")
  T.ok(("Random message"):find(p) == nil, "should not match")
  local p2 = PE.PatternFromFormat("Discovered %s")
  T.ok(("Discovered Westfall"):find(p2) ~= nil)
end)

T.test("quest turn-in awards 25", function()
  local db = fresh()
  Stub.FireEvent("QUEST_TURNED_IN", 123, 4500, 50)
  T.eq(db.points, 25)
  T.eq(db.stats.byReason.QUEST, 25)
end)

T.test("own PARTY_KILL awards 2; others' kills and other subevents award 0", function()
  local db = fresh()
  Stub.combatLog = { 0, "PARTY_KILL", false, "Player-1", "Tester", 0x511, 0, "Creature-1", "Hogger", 0x10a48, 0 }
  Stub.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
  T.eq(db.points, 2)
  Stub.combatLog = { 0, "PARTY_KILL", false, "Player-2", "Buddy", 0x512, 0, "Creature-1", "Hogger", 0x10a48, 0 }
  Stub.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
  T.eq(db.points, 2, "party member kill must not award")
  Stub.combatLog = { 0, "SPELL_DAMAGE", false, "Player-1", "Tester", 0x511, 0, "Creature-1", "Hogger", 0x10a48, 0 }
  Stub.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
  T.eq(db.points, 2, "non-kill subevent must not award")
end)

T.test("honor gain awards 5", function()
  local db = fresh()
  Stub.FireEvent("CHAT_MSG_COMBAT_HONOR_GAIN",
    "Enemy dies, honorable kill Rank: Grunt (Estimated Honor Points: 12)")
  T.eq(db.points, 5)
end)

T.test("boss kill awards 50 only on success", function()
  local db = fresh()
  Stub.FireEvent("ENCOUNTER_END", 663, "Lucifron", 9, 40, 0)
  T.eq(db.points, 0, "wipe must not award")
  Stub.FireEvent("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
  T.eq(db.points, 50)
end)

T.test("exploration awards 10 for discovery messages only", function()
  local db = fresh()
  Stub.FireEvent("UI_INFO_MESSAGE", 42, "Discovered Westfall")
  T.eq(db.points, 10)
  Stub.FireEvent("UI_INFO_MESSAGE", 43, "Your equipment is damaged")
  T.eq(db.points, 10, "non-discovery message must not award")
end)

T.test("level up awards 100", function()
  local db = fresh()
  Stub.FireEvent("PLAYER_LEVEL_UP", 23)
  T.eq(db.points, 100)
end)

T.test("events are harmless before InitDB", function()
  local saved = ns.db
  ns.db = nil
  Stub.FireEvent("QUEST_TURNED_IN", 1, 0, 0)  -- must not error
  ns.db = saved
  T.ok(true)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: crash loading test_pointsengine (PointsEngine.lua missing).

- [ ] **Step 3: Write `PointsEngine.lua`**

```lua
local ADDON_NAME, ns = ...

local PE = {}
ns.PointsEngine = PE

local AFFIL_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001

-- Convert a WoW format string ("Discovered %s") into an anchored Lua pattern.
function PE.PatternFromFormat(fmt)
  local p = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  p = p:gsub("%%%%s", "(.+)")
  p = p:gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$"
end

local explorePatterns
local function ExplorePatterns()
  if explorePatterns then return explorePatterns end
  explorePatterns = {}
  local fmts = { ERR_ZONE_EXPLORED, ERR_ZONE_EXPLORED_XP }
  for i = 1, 2 do
    if type(fmts[i]) == "string" then
      explorePatterns[#explorePatterns + 1] = PE.PatternFromFormat(fmts[i])
    end
  end
  if #explorePatterns == 0 then explorePatterns[1] = "^Discovered " end
  return explorePatterns
end

function PE.IsExploreMessage(msg)
  for _, pat in ipairs(ExplorePatterns()) do
    if msg:find(pat) then return true end
  end
  return false
end

function PE.OnEvent(event, ...)
  if not ns.db then return end
  local P = ns.POINT_VALUES
  if event == "QUEST_TURNED_IN" then
    ns.AddPoints(P.QUEST, "QUEST")
    ns.Print(string.format("+%d Pack Points (quest) — %d total", P.QUEST, ns.db.points))
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, subevent, _, _, _, srcFlags = CombatLogGetCurrentEventInfo()
    if subevent == "PARTY_KILL" and type(srcFlags) == "number"
        and bit.band(srcFlags, AFFIL_MINE) > 0 then
      ns.AddPoints(P.KILL, "KILL")   -- silent: kills are frequent
    end
  elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
    ns.AddPoints(P.HONOR, "HONOR")   -- silent: busy in battlegrounds
  elseif event == "ENCOUNTER_END" then
    local _, encounterName, _, _, success = ...
    if success == 1 then
      ns.AddPoints(P.BOSS, "BOSS")
      ns.Print(string.format("+%d Pack Points (%s defeated) — %d total",
        P.BOSS, tostring(encounterName), ns.db.points))
    end
  elseif event == "UI_INFO_MESSAGE" then
    local _, msg = ...
    if type(msg) == "string" and PE.IsExploreMessage(msg) then
      ns.AddPoints(P.EXPLORE, "EXPLORE")
      ns.Print(string.format("+%d Pack Points (exploration) — %d total", P.EXPLORE, ns.db.points))
    end
  elseif event == "PLAYER_LEVEL_UP" then
    ns.AddPoints(P.LEVEL, "LEVEL")
    ns.Print(string.format("+%d Pack Points (level up!) — %d total", P.LEVEL, ns.db.points))
  end
end

PE.EVENTS = {
  "QUEST_TURNED_IN", "COMBAT_LOG_EVENT_UNFILTERED", "CHAT_MSG_COMBAT_HONOR_GAIN",
  "ENCOUNTER_END", "UI_INFO_MESSAGE", "PLAYER_LEVEL_UP",
}

function PE.Register()
  if PE.frame then return end
  local f = CreateFrame("Frame")
  PE.frame = f
  for _, e in ipairs(PE.EVENTS) do f:RegisterEvent(e) end
  f:SetScript("OnEvent", function(_, event, ...) PE.OnEvent(event, ...) end)
end
```

- [ ] **Step 4: Run to verify pass**

Run: `lua tests/run.lua`
Expected: all pointsengine tests PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add PointsEngine.lua tests/test_pointsengine.lua
git commit -m "Add PointsEngine: quests, kills, honor, bosses, exploration, levels"
```

---

### Task 6: ChatFlex (announcements + chat card links)

**Files:**
- Create: `ChatFlex.lua`
- Create: `tests/test_chatflex.lua`

- [ ] **Step 1: Write the failing test `tests/test_chatflex.lua`**

```lua
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
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: crash loading test_chatflex (ChatFlex.lua missing).

- [ ] **Step 3: Write `ChatFlex.lua`**

```lua
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
```

- [ ] **Step 4: Run to verify pass**

Run: `lua tests/run.lua`
Expected: all chatflex tests PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add ChatFlex.lua tests/test_chatflex.lua
git commit -m "Add ChatFlex: pull announcements and clickable chat card links"
```

---

### Task 7: UI/CardWidget (shared card frame)

**Files:**
- Create: `UI/CardWidget.lua`
- Create: `tests/test_ui_load.lua`

- [ ] **Step 1: Write the failing test `tests/test_ui_load.lua`**

(This file grows in Tasks 8 and 9 — at this task it only loads CardWidget.)

```lua
local Stub = require("wow_api_stub")
local T = require("testkit")

T.test("CardWidget loads and handles all display modes under the stub", function()
  local ns = {}
  Stub.LoadAddonFile("Core.lua", ns)
  Stub.LoadAddonFile("Data/Cards.lua", ns)
  Stub.LoadAddonFile("UI/CardWidget.lua", ns)
  Stub.FreshDB(ns)
  T.ok(type(ns.CreateCardWidget) == "function", "CreateCardWidget missing")
  local w = ns.CreateCardWidget(UIParent)
  w:SetCard(ns.CARDS[1], {})
  w:SetCard(ns.CARDS[1], { count = 3, isNew = true })
  w:SetCard(ns.CARDS[1], { faceDown = true })
  w:SetCard(ns.CARDS[1], { silhouette = true })
  T.ok(true)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: FAIL — CardWidget.lua missing.

- [ ] **Step 3: Write `UI/CardWidget.lua`**

```lua
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
```

- [ ] **Step 4: Run to verify pass**

Run: `lua tests/run.lua`
Expected: ui_load test PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add UI/CardWidget.lua tests/test_ui_load.lua
git commit -m "Add CardWidget: rarity-bordered card frame with flip animation"
```

---

### Task 8: UI/PackOpening (5-card reveal screen)

**Files:**
- Create: `UI/PackOpening.lua`
- Modify: `tests/test_ui_load.lua`

- [ ] **Step 1: Extend `tests/test_ui_load.lua`** — append this test at the end:

```lua
T.test("PackOpening loads and opens a pack under the stub", function()
  local ns = {}
  Stub.LoadAddonFile("Core.lua", ns)
  Stub.LoadAddonFile("Data/Cards.lua", ns)
  Stub.LoadAddonFile("PackSystem.lua", ns)
  Stub.LoadAddonFile("ChatFlex.lua", ns)
  Stub.LoadAddonFile("UI/CardWidget.lua", ns)
  Stub.LoadAddonFile("UI/PackOpening.lua", ns)
  local db = Stub.FreshDB(ns)
  T.ok(type(ns.PackUI.Open) == "function", "PackUI.Open missing")
  ns.PackUI.Open()          -- zero packs: prints error, no crash
  db.packs = 1
  ns.rng = function(n) return math.min(30, n) end
  ns.PackUI.Open()
  ns.rng = nil
  T.eq(db.packs, 0, "pack should be consumed")
  ns.PackUI.RevealAll()     -- reveal-all path must not error
  T.ok(true)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: FAIL — PackOpening.lua missing.

- [ ] **Step 3: Write `UI/PackOpening.lua`**

Note: `Flip` uses an OnUpdate handler which never runs under the stub, so the
stub-side test only exercises Open/RevealAll paths, not the reveal callbacks —
in-game QA covers those.

```lua
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
```

- [ ] **Step 4: Run to verify pass**

Run: `lua tests/run.lua`
Expected: both ui_load tests PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add UI/PackOpening.lua tests/test_ui_load.lua
git commit -m "Add pack opening UI: click-to-flip reveal with summary"
```

---

### Task 9: UI/Collection (binder browser + preview + dust)

**Files:**
- Create: `UI/Collection.lua`
- Modify: `tests/test_ui_load.lua`

- [ ] **Step 1: Extend `tests/test_ui_load.lua`** — append this test at the end:

```lua
T.test("Collection loads, toggles, filters, and previews under the stub", function()
  local ns = {}
  Stub.LoadAddonFile("Core.lua", ns)
  Stub.LoadAddonFile("Data/Cards.lua", ns)
  Stub.LoadAddonFile("PackSystem.lua", ns)
  Stub.LoadAddonFile("ChatFlex.lua", ns)
  Stub.LoadAddonFile("UI/CardWidget.lua", ns)
  Stub.LoadAddonFile("UI/PackOpening.lua", ns)
  Stub.LoadAddonFile("UI/Collection.lua", ns)
  local db = Stub.FreshDB(ns)
  local UI = ns.CollectionUI
  T.ok(type(UI.Toggle) == "function", "Toggle missing")
  UI.Toggle()   -- builds and shows
  UI.Toggle()   -- hides
  UI.Toggle()   -- shows again
  -- filters
  UI.filters.rarity = 6
  T.ok(#UI.FilteredCards() == 10, "rarity filter should isolate the 10 legendaries")
  UI.filters.rarity = 0
  UI.filters.owned = "OWNED"
  T.ok(#UI.FilteredCards() == 0, "empty collection owns nothing")
  db.collection[ns.CARDS[1].id] = 1
  T.ok(#UI.FilteredCards() == 1)
  UI.filters.owned = "ALL"
  -- search must not leak unowned Epic+ names
  local legendary = ns.CardsByRarity[6][1]
  UI.filters.search = legendary.name:lower()
  local found = false
  for _, c in ipairs(UI.FilteredCards()) do
    if c.id == legendary.id then found = true end
  end
  T.ok(not found, "unowned legendary must not appear in search")
  UI.filters.search = ""
  UI.Refresh()
  UI.ShowPreview(ns.CARDS[1])
  T.ok(true)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: FAIL — Collection.lua missing.

- [ ] **Step 3: Write `UI/Collection.lua`**

```lua
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
```

- [ ] **Step 4: Run to verify pass**

Run: `lua tests/run.lua`
Expected: all three ui_load tests PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add UI/Collection.lua tests/test_ui_load.lua
git commit -m "Add collection binder: filters, search, paging, preview, dusting"
```

---

### Task 10: Slash commands, debug tools, minimap button

**Files:**
- Modify: `Core.lua` (append at end of file)
- Create: `tests/test_slash.lua`

- [ ] **Step 1: Write the failing test `tests/test_slash.lua`**

```lua
local Stub = require("wow_api_stub")
local T = require("testkit")

local ns = {}
Stub.LoadAddonFile("Core.lua", ns)
Stub.LoadAddonFile("Data/Cards.lua", ns)
Stub.LoadAddonFile("PackSystem.lua", ns)

local toggled = 0
ns.CollectionUI = { Toggle = function() toggled = toggled + 1 end, Refresh = function() end }
ns.PackUI = { Open = function() end }

T.test("/tcg with no args toggles the collection", function()
  Stub.FreshDB(ns)
  ns.HandleSlash("")
  T.eq(toggled, 1)
end)

T.test("/tcg buy fails when broke, works at 100 points", function()
  local db = Stub.FreshDB(ns)
  ns.HandleSlash("buy")
  T.eq(db.packs, 0)
  db.points = 100
  ns.HandleSlash("buy")
  T.eq(db.packs, 1)
  T.eq(db.points, 0)
end)

T.test("/tcg debug points grants points", function()
  local db = Stub.FreshDB(ns)
  ns.HandleSlash("debug points 250")
  T.eq(db.points, 250)
end)

T.test("/tcg debug pack grants a pack, legendary sets the flag", function()
  local db = Stub.FreshDB(ns)
  ns.HandleSlash("debug pack")
  T.eq(db.packs, 1)
  ns.HandleSlash("debug legendary")
  T.eq(ns.forceLegendary, true)
  ns.forceLegendary = nil
end)

T.test("/tcg config announce validates channels", function()
  local db = Stub.FreshDB(ns)
  ns.HandleSlash("config announce guild")
  T.eq(db.settings.announceChannel, "GUILD")
  ns.HandleSlash("config announce bogus")
  T.eq(db.settings.announceChannel, "GUILD", "invalid channel must not stick")
  ns.HandleSlash("config minrarity 4")
  T.eq(db.settings.announceMinRarity, 4)
  ns.HandleSlash("config sounds off")
  T.eq(db.settings.sounds, false)
end)

T.test("/tcg debug wipe resets the DB (stub auto-accepts the popup)", function()
  local db = Stub.FreshDB(ns)
  db.points = 500
  db.collection[100] = 3
  ns.HandleSlash("debug wipe")
  T.eq(WoWTCG_DB.points, 0)
  T.eq(next(WoWTCG_DB.collection), nil)
end)

T.test("slash command is registered", function()
  T.eq(SLASH_WOWTCG1, "/tcg")
  T.ok(type(SlashCmdList["WOWTCG"]) == "function")
end)

T.test("minimap button builds without error", function()
  Stub.FreshDB(ns)
  ns.SetupMinimapButton()
  T.ok(_G.WoWTCGMinimapButton ~= nil)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua`
Expected: FAIL — `ns.HandleSlash` is nil.

- [ ] **Step 3: Append to `Core.lua`** (after the `initFrame` block; keep everything already there):

```lua
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
  elseif sub == "resetpity" then
    db.pity.epic, db.pity.legendary = 0, 0
    ns.Print("pity counters reset")
  elseif sub == "wipe" then
    StaticPopup_Show("WOWTCG_WIPE")
  else
    ns.Print("debug: points <n> | pack | legendary | resetpity | wipe")
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
```

- [ ] **Step 4: Run to verify pass**

Run: `lua tests/run.lua`
Expected: all slash tests PASS, full suite green, exit 0.

- [ ] **Step 5: Commit**

```bash
git add Core.lua tests/test_slash.lua
git commit -m "Add slash commands, debug tools, and minimap button"
```

---

### Task 11: README, final verification, packaging

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

```markdown
# WoWTCG

A collectible card game inside WoW Classic / Anniversary. Playing the game earns
**Pack Points**; 100 points buys a 5-card pack. Open packs, chase Legendaries,
fill your binder, dust your dupes, and flex your pulls in guild chat.

## Install

Copy this folder into your AddOns directory so the path is:

    World of Warcraft/_classic_era_/Interface/AddOns/WoWTCG/WoWTCG.toc

The folder must be named `WoWTCG`. If the game client is newer than the
`## Interface:` number in the TOC, enable "Load out of date AddOns".

## Earning Pack Points

| Activity        | Points |
|-----------------|--------|
| Mob kill        | 2      |
| Quest turn-in   | 25     |
| Honorable kill  | 5      |
| Boss kill       | 50     |
| Zone explored   | 10     |
| Level up        | 100    |

A pack costs **100 points** and contains 5 cards. Every pack holds at least one
Uncommon+; pity guarantees an Epic+ at 10 barren packs and a Legendary by 40.
Duplicates can be dusted for points: 1/2/5/15/40/150 by rarity.

## Commands

    /tcg                  toggle the collection binder
    /tcg open             open a pack
    /tcg buy              buy a pack (100 points)
    /tcg points           show your balance
    /tcg config           show settings; options:
    /tcg config announce OFF|GUILD|PARTY|SAY|EMOTE
    /tcg config minrarity 1-6
    /tcg config sounds on|off
    /tcg debug            testing helpers (grant points/packs, force legendary, wipe)

Left-click cards in the pack screen to flip them one at a time; right-click to
reveal all. In the binder: left-click a card to preview it, right-click to dust
a duplicate. Collection and points are shared account-wide across characters.

## Development

Pure-logic modules are unit-tested outside the game:

    lua tests/run.lua

Card data lives in `Data/Cards.lua` ("Classic Vol. 1", 300 cards). Card ids are
permanent — never reuse or renumber them.
```

- [ ] **Step 2: Full verification**

Run: `lua tests/run.lua`
Expected: entire suite passes, exit 0.

Run: `git status --short`
Expected: only `README.md` untracked; working tree otherwise clean.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add README with install, economy, and command reference"
```

- [ ] **Step 4: In-game QA checklist** (manual, requires the game client — record results in the session, not the repo):

1. Copy the repo folder to `Interface/AddOns/WoWTCG`, launch Classic Era/Anniversary.
2. `/tcg` opens the binder; drag it; Escape closes it.
3. `/tcg debug points 500`, buy + open packs; flip cards one at a time; right-click reveals all.
4. `/tcg debug legendary` then open a pack — Legendary appears with orange border and sound.
5. Kill a mob, turn in a quest — chat shows the points; binder header updates.
6. `/tcg config announce SAY`, pull an Epic+ — announcement text appears with the token; clicking a rewritten link (needs a second addon user, or whisper yourself) opens the preview.
7. Dust a dupe via right-click; Dust Dupes button with confirmation.
8. Minimap button: click toggles, drag repositions, position survives `/reload`.
9. `/reload` — collection, points, pity, and minimap position persist.

---

## Execution notes

- Tasks are strictly sequential (each builds on the last); one commit per task.
- If `lua tests/run.lua` fails at any step in a way the task's code doesn't explain,
  STOP and debug with the superpowers:systematic-debugging skill — do not paper over
  a failing assertion by weakening the test.
- Task 3's card authoring is the only creative-volume step; everything else is
  verbatim from this plan.
```
