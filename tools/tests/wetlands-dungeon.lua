-- Exercise the shipped Alliance route with a journal that never took the Ashenvale breadcrumb.
local active, ready, turned = {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 26 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {
  C = {
    IsOnQuest = function(q) return active[q] end,
    IsReady = function(q) return ready[q] end,
    IsTurnedIn = function(q) return turned[q] end,
  },
  db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={} },
  UI = { Get=function() return false end },
  L = {},
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local d = E.byId["05-d6"]
assert(d.pickAt == "02-21")
local function step(st, t, q)
  for i, wrapper in ipairs(st.list) do
    if wrapper.s.t == t and wrapper.s.q == q then return wrapper.s, i end
  end
end
local breadcrumb = assert(step(d, "turnin", 95737))
assert(breadcrumb.ph == "pre" and not E.Applies(breadcrumb.when))
assert(not step(d, "accept", 95737))
assert(step(E.byId["02-21"], "turnin", 95737))
local pickup, a = step(d, "accept", 95647)
local use, b = step(d, "do", 95647)
local meet, c = step(d, "turnin", 95647)
local followup, e = step(d, "accept", 95809)
local finish, f = step(d, "turnin", 95809)
assert(a < b and b < c and c < e and e < f)
assert(pickup.ph == "pre" and pickup.pickLv == 24 and pickup.map == 1437)
assert(use.ph == "in" and meet.ph == "in" and followup.ph == "in")
assert(not use.map and not meet.map and not followup.map)
assert(finish.ph == "post" and finish.map == pickup.map and finish.npc == pickup.npc)
local targets = E.DungeonTargets(d)
assert(#targets == 1 and targets[1].q == 95647 and #targets[1].chain == 0)
local q = ns.Route.quests[95647]
assert(#(q.ps or {}) == 0 and #(q.pg or {}) == 0)
assert(ns.Route.quests[95809].ps[1] == 95647)
local function inside(t, id)
  local state = E.InstanceState(d)
  if state then
    for _, wrapper in ipairs(state.steps) do
      if wrapper.s.t == t and wrapper.s.q == id then return true end
    end
  end
  return false
end
assert(not inside("accept", 95809))
active[95647] = true
assert(inside("do", 95647) and not inside("accept", 95809))
ready[95647] = true
assert(inside("turnin", 95647))
active[95647], ready[95647], turned[95647] = nil, nil, true
assert(not E.DungeonDone(d))
assert(inside("accept", 95809))
active[95809] = true
assert(not inside("accept", 95809) and not E.DungeonDone(d))
active[95809], turned[95809] = nil, true
assert(not inside("accept", 95809) and E.DungeonDone(d))
print("Wetlands excavation prep, in-instance follow-up and harbor return passed")
