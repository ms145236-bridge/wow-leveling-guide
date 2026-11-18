-- Feed real recorder event handlers a pickup and hand-in without a game client.
local eventHandler, now, grouped, enabled = nil, 1000, false, true
function CreateFrame()
  return {RegisterEvent=function() end, SetScript=function(_, _, fn) eventHandler = fn end}
end
function time() return 1700000000 + now end
function GetTime() return now end
function UnitLevel() return 50 end
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human" end
function IsInGroup() return grouped end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {db={}, Route={built="fixture"}, UI={Get=function() return enabled end},
  C={Title=function() return "Quest" end, Position=function() return 1449, 40, 12 end,
     Auras=function() return {} end}, E={QuestXP=function() return 0 end},
  try=function(_, fn, ...) return fn(...) end}
local function loadRecorder() assert(loadfile("addon/ShengLeveling/Rec.lua"))("ShengLeveling", ns) end
local function fire(event, ...) eventHandler(nil, event, ...) end
local function countTimings()
  local n = 0
  for _, line in ipairs(MetroGuideRecDB.log) do
    if line:match("^timing\t") then n = n + 1 end
  end
  return n
end
loadRecorder()
fire("QUEST_ACCEPTED", 4, 3881)
now = now + 60
grouped = true
fire("GROUP_ROSTER_UPDATE")
grouped = false
fire("QUEST_TURNED_IN", 3881, 100, 0)
assert(countTimings() == 1)
for _, line in ipairs(MetroGuideRecDB.log) do
  if line:match("^timing\t") then
    assert(line:find("Alliance\tHuman\tPRIEST\t@\t", 1, true))
    assert(line:find("\t60\t50\t1\t\tfixture", 1, true))
  end
end
fire("QUEST_TURNED_IN", 3881, 100, 0)
fire("QUEST_ACCEPTED", 7729)
ns.Rec.ResetTimings()
fire("QUEST_TURNED_IN", 7729, 100, 0)
fire("QUEST_ACCEPTED", 2581)
loadRecorder()
fire("QUEST_TURNED_IN", 2581, 100, 0)
enabled = false
fire("QUEST_ACCEPTED", 3881)
enabled = true
fire("QUEST_TURNED_IN", 3881, 100, 0)
assert(countTimings() == 1)
if arg[1] then
  local out = assert(io.open(arg[1], "w"))
  for _, line in ipairs(MetroGuideRecDB.log) do out:write(line, "\n") end
  out:close()
end
print("Timing records preserve the group flag and discard incomplete sessions")
