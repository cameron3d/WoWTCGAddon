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
