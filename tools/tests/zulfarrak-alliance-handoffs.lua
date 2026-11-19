-- Run from the project root with Lua 5.1. Exercise the generated route, Engine and native Core callback.
local active, ready, turned, log, handlers = {}, {}, {}, {}, {}
local level, now, offered, calls, optional, point = 40, 100, nil, 0, true, {}
local class, physical, items = "PRIEST", false, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return class, class end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return level end
function UnitXP() return 0 end
function UnitXPMax() return 36300 end
function GetTime() return now end
function IsInInstance() return physical, physical and "party" or "none" end
function GetInstanceInfo() return "Zul'Farrak", nil, nil, nil, nil, nil, nil, physical and 209 or 0 end
function GetItemCount(id) return items[id] or 0 end
function GetQuestID() return offered end
function IsShiftKeyDown() return false end
function AcceptQuest() calls = calls + 1 end
function CreateFrame() return {RegisterEvent=function() end, SetScript=function(_, name, fn) handlers[name] = fn end} end
function wipe(t) for k in pairs(t) do t[k] = nil end end
SlashCmdList = {}
local ns = {
  C = {
    IsOnQuest=function(q) return active[q] end, IsReady=function(q) return ready[q] end,
    IsTurnedIn=function(q) return turned[q] end, LogQuestIDs=function() return log end,
    XPBuff=function() return false end, Position=function() return unpack(point) end,
    ZoneTexts=function() end, Bind=function() end, Objectives=function() end
  },
  db = {skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}},
  UI = {Get=function(k) return k == "optional" and optional or k == "auto" or k == "dPre" end},
  L = setmetatable({}, {__index=function(_, key) return key end}),
  msg = function() end,
  try = function(_, f, ...) return f(...) end
}
for _, filename in ipairs({"Data/RouteA.lua", "Engine.lua", "Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. filename))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local zf = E.byId["05-d10"]
local lastState
for i=1,99 do
  local key = debug.getupvalue(handlers.OnUpdate, i)
  if key == "lastState" then lastState = i; break end
  if not key then break end
end
assert(lastState)
for _, q in ipairs({2864,3527,2865,2768,3042}) do active[q] = true end
turned[3520] = true
local function fillLog(size)
  wipe(log)
  for q in pairs(active) do log[#log+1] = q end
  for i=#log+1,size do log[i] = 100000+i end
end
local function witness(quest, station, loc, lv, size, enabled, native)
  level, optional, point = lv, enabled, loc
  ns.db.station = station
  fillLog(size)
  local view = E.Locate(E.byId[station])
  local allowed
  for index, step in ipairs(view.steps) do
    if step.s.q == quest and step.s.t == "accept" then allowed = not view.na[index] and not view.wait[index] end
  end
  local nextStep = E.DungeonNext(zf, false)
  local nextQuest = nextStep and nextStep.step and nextStep.step.s.q
  local clicked = "-"
  if native then
    offered = quest
    debug.setupvalue(handlers.OnUpdate, lastState, nil)
    local before = calls
    now = now + 4
    handlers.OnEvent(nil, "QUEST_DETAIL")
    clicked = tostring(calls > before)
  end
  return allowed, nextQuest, clicked
end

local gahz, crown = 2770, 2846
local wizzle, fizz = {1441,78.14,77.12}, {1441,78.06,77.13}
local tabetha, theramore = {1445,46.06,57.09}, {1445,67,51}
local function pickup(q, station, loc, lv, size, enabled, expectMain, expectNext)
  local main, nextQuest, auto = witness(q, station, loc, lv, size, enabled, true)
  assert(main == expectMain and (nextQuest == q) == expectNext,
    ("pickup %d at %s, level %d, %d used, optional %s"):format(q, station, lv, size, tostring(enabled)))
  assert(auto == "false", "the native quest window must remain manual")
end
pickup(gahz, "03-32", fizz, 39, 6, true, false, false)
pickup(gahz, "03-32", fizz, 40, 6, true, true, true)
pickup(gahz, "04-47", wizzle, 49, 6, true, true, true)
for _, station in ipairs({"03-32", "04-47"}) do
  for _, used in ipairs({39,40}) do pickup(gahz, station, wizzle, 49, used, true, false, false) end
  pickup(gahz, station, wizzle, 49, 6, false, false, false)
end
pickup(crown, "03-32", theramore, 40, 6, true, nil, false)
for _, className in ipairs({"MAGE", "WARLOCK", "PRIEST"}) do
  class = className
  pickup(crown, "03-32", tabetha, 39, 6, true, nil, false)
  pickup(crown, "03-32", tabetha, 40, 6, true, nil, true) -- No 2861 prerequisite.
  for _, used in ipairs({39,40}) do pickup(crown, "03-32", tabetha, 40, used, true, nil, false) end
  pickup(crown, "03-32", tabetha, 40, 6, false, nil, false)
end

local function routeStep(station, quest, verb)
  local view = E.Locate(station)
  for i, row in ipairs(view.steps) do
    if row.s.q == quest and row.s.t == verb then return view, i, row end
  end
  error("Missing authored step " .. quest .. "/" .. verb)
end

for _, check in ipairs({{gahz,8707,wizzle}, {crown,9234,tabetha}}) do
  local q, item, near = unpack(check)
  active[q], optional, physical, point = true, false, true, {1446,38.7,20.1}
  fillLog(40)
  local hasWork
  for _, row in ipairs(assert(E.InstanceState(zf)).steps) do
    if row.s.q == q then hasWork = row.s.t == "do" and row.s.hint ~= nil end
  end
  assert(hasWork, "held work must stay in the correct dungeon even with a full journal and optional off")
  ready[q], items[item] = true, 1
  local view, i = routeStep(zf,q,"turnin")
  assert(view.na[i])
  physical, point = false, near
  view, i = routeStep(zf,q,"turnin")
  assert(not view.na[i], "ready local hand-in still applies with optional off and full journal")
  items[item] = nil
  view, i = routeStep(zf,q,"turnin")
  assert(view.na[i], "journal readiness alone cannot provide the turn-in item")
  items[item],ready[q] = 1,false
  view, i = routeStep(zf,q,"turnin")
  assert(view.na[i], "holding a turn-in item alone does not make it ready")
  ready[q] = true
  view, i = routeStep(zf,q,"turnin")
  E.PinIndex(view,i)
  point = theramore
  view, i = routeStep(zf,q,"turnin")
  assert(view.na[i] and view.cur ~= i, "a saved dungeon pin must not send the player back to a distant NPC")
  if q == gahz then
    point = wizzle
    view, i = routeStep(E.byId["04-47"],q,"turnin")
    assert(not view.na[i], "A47 can hand in a completed first run while already at the raceway")
  end
  active[q],ready[q],items[item] = nil,nil,nil
end

print("Alliance Zul'Farrak: raceway level and distance, Tabetha, reserved slots, manual quest detail, held objectives and saved pins")
