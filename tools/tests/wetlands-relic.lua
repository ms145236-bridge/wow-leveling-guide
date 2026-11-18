-- From the project root: lua5.1 tools/tests/wetlands-relic.lua
local active, ready, turned, bags = {}, {}, {[95647]=true, [95809]=true}, {}
local level, optional, class = 26, true, "PRIEST"
function UnitFactionGroup() return "Alliance" end
function UnitClass() return class, class end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return level end
function UnitXP() return 0 end
function UnitXPMax() return 36300 end
function GetItemCount(id) return bags[id] or 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {
  C = {
    IsOnQuest=function(q) return active[q] end,
    IsReady=function(q) return ready[q] end,
    IsTurnedIn=function(q) return turned[q] end,
    XPBuff=function() return false end,
    Position=function() end,
    ZoneTexts=function() end,
    Bind=function() end,
    LogQuestIDs=function() local ids = {} for q in pairs(active) do ids[#ids + 1] = q end return ids end,
    Objectives=function() end,
  },
  db = {skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}},
  UI = {Get=function(k) return k == "optional" and optional end},
  L = setmetatable({}, {__index=function(_, key) return key end}),
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local dungeon = assert(E.byId["05-d6"])
local relic, prism = 95810, 98824
assert(E.DungeonDone(dungeon), "the relic must never become a required dungeon task")
assert(ns.Route.quests[prism].ps[1] == relic)
assert(ns.Route.keep[270865].q == relic and ns.Route.keep[287959].q == prism)

local function dungeonStep(inside, action, quest)
  local next = E.DungeonNext(dungeon, inside)
  return next and next.step and next.step.s.t == action and next.step.s.q == quest and next
end

local function inside(action, quest)
  local state = E.InstanceState(dungeon)
  for _, wrapper in ipairs(state and state.steps or {}) do
    if wrapper.s.t == action and wrapper.s.q == quest then return wrapper.s end
  end
end

local function world(station, action, quest)
  local state = E.Locate(assert(E.byId[station]))
  for i, wrapper in ipairs(state.steps) do
    local s = wrapper.s
    if s.t == action and s.q == quest then return not state.na[i] and not state.wait[i] and not state.done[i], s, i end
  end
  error("missing " .. action .. " " .. quest .. " at " .. station)
end

for _, wrong in ipairs({{}, {[270866]=1}, {[287959]=1}, {[270866]=1, [287959]=1}}) do
  bags = wrong
  assert(not inside("accept", relic) and not E.DungeonNext(dungeon, false))
  assert(not world("03-23", "accept", relic) and not world("03-23", "turnin", relic))
end

bags, level = {[270865]=1}, 23
assert(not inside("accept", relic) and not E.DungeonNext(dungeon, false))
level = 30
local drop = assert(inside("accept", relic))
assert(not drop.map and drop.outsideObjective and drop.when.bag.item == 270865)
local outside = assert(dungeonStep(false, "accept", relic))
assert(outside.kind == "post" and outside.step.s.ph == "post" and not outside.step.s.map)
assert(world("03-23", "accept", relic))
assert(not world("03-23", "accept", prism), "loot must not unlock the successor")

active[relic], bags, optional = true, {}, false
assert(not inside("do", relic) and not E.DungeonNext(dungeon, false))
ready[relic] = true
assert(not world("03-23", "turnin", relic) and not E.DungeonNext(dungeon, false))
bags[270865], ready[relic] = 1, false
assert(not world("03-23", "turnin", relic), "the player's log must also confirm readiness")
ready[relic] = true
assert(dungeonStep(false, "turnin", relic).kind == "post")
local originalLog = ns.C.LogQuestIDs
ns.C.LogQuestIDs = function()
  local log = {relic}
  for i = 2, 40 do log[i] = 100000 + i end
  return log
end
assert(E.LogFull() and not E.PreRoom(E.byId["03-23"]))
local applicable, report, index = world("03-23", "turnin", relic)
local _, nextQuest, nextIndex = world("03-23", "accept", prism)
assert(applicable and report.map == 1437 and report.x == 38.81 and report.y == 52.39)
assert(nextQuest.npc == report.npc and nextIndex == index + 1)
ns.C.LogQuestIDs = originalLog

turned[relic], active[relic], ready[relic], bags = true, nil, nil, {}
assert(dungeonStep(false, "accept", prism).kind == "post")
assert(world("03-23", "accept", prism))
active[prism] = true
assert(not world("03-27", "turnin", prism))
ready[prism] = true
assert(dungeonStep(false, "turnin", prism).kind == "post")
ns.db.dNo[dungeon.id] = true
local hall, address, i = world("03-27", "turnin", prism)
local _, _, nearby = world("03-27", "turnin", 514)
assert(hall and i + 1 == nearby and address.map == 1455 and address.x == 69.93 and address.y == 18.55)
class = "WARLOCK"
E.Build()
local _, _, hallOrder = world("03-27", "turnin", prism)
local _, _, classOrder = world("03-27", "accept", 1798)
assert(hallOrder < classOrder, "report before the Warlock's cross-continent side trip")
assert(world("04-45", "turnin", prism) and world("04-52", "turnin", prism))
bags[287959] = 1
assert(world("03-27", "turnin", prism))
turned[prism], active[prism] = true, nil
assert(not world("03-27", "turnin", prism))
print("Wetlands relic: exact drop, outside Whelgar handoff and on-route Ironforge return")

-- A late revisit can still have a genuine in-dungeon objective in parallel.
level, optional = 58, false
local search, fallen = 95772, 95795
active, ready, turned, bags = {[search]=true}, {[search]=true}, {[95647]=true, [95809]=true}, {}
ns.db.dNo[dungeon.id] = nil
assert(E.DungeonDone(dungeon))
assert(E.DungeonNext(dungeon, false).kind == "ent", "Songblade still has an in-dungeon handoff")
assert(inside("turnin", search))
bags[270865] = 1
assert(dungeonStep(false, "accept", relic).kind == "post")
assert(inside("accept", relic) and inside("turnin", search))
active[relic], ready[relic] = true, true
assert(E.DungeonNext(dungeon, false).kind == "ent", "only the unfinished Songblade handoff needs a revisit")
active[search], ready[search], turned[search] = nil, nil, true
assert(dungeonStep(false, "turnin", relic).kind == "post")
assert(inside("accept", fallen) and not inside("do", relic))
active[fallen], ready[fallen] = true, true
assert(not inside("do", fallen))
active[relic], ready[relic], turned[relic], bags = nil, nil, true, {}
assert(dungeonStep(false, "accept", prism).kind == "post")
active[prism], ready[prism] = true, true
assert(dungeonStep(false, "turnin", fallen).kind == "post")
active[fallen], ready[fallen], turned[fallen] = nil, nil, true
level = 60
assert(dungeonStep(false, "turnin", prism).kind == "post")
assert(world("04-45", "turnin", prism) and world("04-52", "turnin", prism))
print("A cleared excavation preserves late Songblade revisits and outside relic handoffs at levels 58–60")
