-- From the project root: lua5.1 tools/tests/dungeon-prep-room.lua
local search, fallen, otherPrep, mainQuest = 95772, 95795, 95646, 169
local active, ready, turned, log = {}, {}, {}, {}
local level, now, offered = 24, 100, search
local handlers, accepted = {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return level end
function UnitXP() return 0 end
function UnitXPMax() return 36300 end
function GetTime() return now end
function GetQuestID() return offered end
function IsShiftKeyDown() return false end
function AcceptQuest() accepted[#accepted + 1] = offered end
function CreateFrame()
  return {RegisterEvent=function() end, SetScript=function(_, event, handler) handlers[event] = handler end}
end
function wipe(t) for k in pairs(t) do t[k] = nil end end
SlashCmdList = {}

local ns = {
  C = {IsOnQuest=function(q) return active[q] end, IsReady=function(q) return ready[q] end,
       IsTurnedIn=function(q) return turned[q] end, LogQuestIDs=function() return log end,
       XPBuff=function() return false end, Position=function() end, ZoneTexts=function() end,
       Bind=function() end, Objectives=function() end},
  db = {skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}},
  UI = {Get=function(k) return k == "optional" or k == "dPre" or k == "auto" end},
  L = setmetatable({}, {__index=function(_, key) return key end}),
  msg = function() end,
  try = function(_, f, ...) return f(...) end,
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua", "Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local st = assert(E.byId["02-19"])
local lastState
for i = 1, math.huge do
  local key = debug.getupvalue(handlers.OnUpdate, i)
  if key == "lastState" then lastState = i; break end
  if not key then break end
end
assert(lastState, "inject the same route state that Core's regular refresh would supply")

local function fillLog(held)
  log = {}
  for k = 1, held do log[k] = 100000 + k end
end
local function row(state, q, action)
  for i, step in ipairs(state.steps) do
    if step.s.t == action and step.s.q == q then return step, i end
  end
  error("missing " .. action .. " " .. q)
end
local function tryAccept(q, state)
  offered = q
  debug.setupvalue(handlers.OnUpdate, lastState, state)
  local count = #accepted
  handlers.OnEvent(nil, "QUEST_DETAIL")
  return #accepted > count
end

for _, held in ipairs({0, 35, 37, 38, 39, 40}) do
  fillLog(held)
  local state = E.Locate(st)
  local step, index = row(state, search, "accept")
  assert((not state.na[index]) == E.PreRoom(st))
  assert((step.defer == true) == (not E.PreRoom(st)))
  assert(tryAccept(search, state) == E.PreRoom(st))
  now = now + 4
end
fillLog(38)
assert(not tryAccept(search, nil), "a pending refresh must not bypass the actual log limit")
fillLog(0)
assert(tryAccept(search, nil))
now = now + 4

local maxHeld = 0
for held = 0, 40 do
  fillLog(held)
  if E.PreRoom(st) then maxHeld = held else break end
end
assert(maxHeld > 0 and maxHeld < 37, "future mainline work retains reserved slots")
fillLog(maxHeld - 1)
local state = E.Locate(st)
assert(E.PreRoom(st, 1) and not E.PreRoom(st, 2))
assert(tryAccept(search, state))
assert(tryAccept(otherPrep, state))
assert(not tryAccept(search, state), "two pending clicks already consumed the available room")
now = now + 4

level = 27
fillLog(39)
assert(tryAccept(mainQuest, E.Locate(st)), "regular mainline has its reserved place")
active[fallen], ready[fallen], turned[search], log[40] = true, true, true, fallen
local full = E.Locate(st)
local _, returnIndex = row(full, fallen, "turnin")
assert(E.LogFull() and not full.na[returnIndex] and not full.wait[returnIndex])
print("Authored dungeon prep honors capacity in route and actual quest-detail callbacks")
