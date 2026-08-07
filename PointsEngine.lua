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
