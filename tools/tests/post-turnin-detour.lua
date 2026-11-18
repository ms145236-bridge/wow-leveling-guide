-- From the project root: lua5.1 tools/tests/post-turnin-detour.lua
local faction, quest, ready, bag = "Alliance", nil, true, {}
local now, map, x, y = 0, nil, nil, nil
local enabled = true
function UnitFactionGroup() return faction end
function UnitRace()
  if faction == "Alliance" then return "Human", "Human", 1 end
  return "Undead", "Scourge", 5
end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return 60 end
function GetTime() return now end
function GetItemCount(item) return bag[item] or 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end

local function loadRoute(data)
  local ns = {
    C = {Position=function() return map, x, y end, IsOnQuest=function(q) return quest == q end,
         IsReady=function(q) return quest == q and ready end, IsTurnedIn=function() return false end,
         LogQuestIDs=function() return {quest} end, Objectives=function() end, ZoneTexts=function() end,
         Bind=function() end},
    db = {skip={}, mark={}, latch={}, dNo={}, notNow={}, pin={}, carry={}, fpNodes={}},
    UI = {Get=function(k) if k == "detourOn" then return enabled elseif k == "detourDist" then return 20 end end},
    L = setmetatable({}, {__index=function(_, k) return k end}),
  }
  for _, file in ipairs({data, "Engine.lua"}) do
    assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
  end
  ns.E.Build()
  return ns.E, ns.Route.quests
end

local empty = {steps={}}
local function reminder(E, state)
  state = state or empty
  E.Detour(state)
  now = now + 4
  return E.Detour(state)
end

local function check(E, target, item, needed)
  quest, ready, bag, map = target, true, {}, nil
  for _, d in ipairs(E.dungeons) do
    for _, step in ipairs(d.list) do
      local s = step.s
      if s.ph == "post" and s.t == "turnin" and s.q == quest then map, x, y = s.map, s.x, s.y end
    end
  end
  assert(map and x and y)
  assert(not reminder(E), "empty bag must not show quest " .. quest)
  bag[item] = needed - 1
  assert(not reminder(E), "missing one item must not show quest " .. quest)
  bag[item] = needed
  ready = false
  assert(not reminder(E), "quest log must confirm readiness")
  ready = true
  assert(reminder(E).s.q == quest)
  bag[item] = needed - 1
  assert(not reminder(E), "using an item must remove the nearby reminder")
end

local E, quests = loadRoute("Data/RouteA.lua")
check(E, 1050, 5536, 1)
check(E, 5848, 14679, 1)

-- Unconditional dialogue turn-ins still appear with an empty bag, and both user controls still work.
quest, ready, bag = 95809, true, {}
map, x, y = 1437, 11.88, 58.82
local talk = assert(reminder(E))
assert(talk.s.q == quest)
enabled = false
assert(not reminder(E))
enabled = true
E.DetourNo(talk.key)
assert(not reminder(E))
now = now + 115
assert(not E.Detour(empty))
now = now + 1
assert(reminder(E).s.q == quest)

-- Core can keep the previous Locate state until its next throttled update.
quest, ready, bag = 7791, true, {[2592]=60}
map, x, y = 1453, 53.90, 81.70
local state = E.Locate(assert(E.byId["03-22"]))
state.cur = nil
local row = assert(reminder(E, state))
assert(state.steps[row].s.q == quest and not state.na[row])
bag[2592] = 59
assert(not state.na[row], "the cached route still predates the bag update")
local after = reminder(E, state)
assert(not after or state.steps[after].s.q ~= quest)

-- These routes are added on top of the shared fix. Verify their live conditions when present.
if quests[95810] then
  check(E, 95810, 270865, 1)
  quest, ready, bag = 98824, true, {}
  map, x, y = 1455, 69.93, 18.55
  assert(reminder(E).s.q == quest, "the follow-up uses the quest log after consuming the first relic")
end
if quests[5212] then
  local supplies = {{5212, 13174, 20}, {5214, 13172, 1}, {5243, 13180, 5}}
  for _, row in ipairs(supplies) do check(E, unpack(row)) end
  faction = "Horde"
  E = loadRoute("Data/Route.lua")
  for _, row in ipairs(supplies) do check(E, unpack(row)) end
end
print("Nearby dungeon turn-ins use live quest conditions and material counts")
