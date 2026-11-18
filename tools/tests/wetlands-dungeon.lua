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
assert(#targets == 3 and targets[1].q == 95646 and targets[2].q == 98815)
assert(targets[3].q == 95647 and #targets[3].chain == 0)
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

-- At A21 both prerequisite turn-ins are already on the main route. The dungeon
-- preparation overlay offers the follow-ups during those visits if enabled.
local a21 = E.byId["02-21"]
local settings = {dPre=true, optional=true}
local bags = {}
function GetItemCount(id) return bags[id] or 0 end
function UnitXPMax() return 21500 end
function UnitXP() return 0 end
ns.UI.Get = function(key) return settings[key] end
ns.C.XPBuff = function() return false end
ns.C.Position = function() end
ns.C.ZoneTexts = function() end
ns.C.Bind = function() end
ns.C.LogQuestIDs = function() return {} end
ns.C.Objectives = function() end
local function offer(state, q)
  for i, wrapper in ipairs(state.steps) do
    if wrapper.s.t == "accept" and wrapper.s.q == q then return i end
  end
end
for _, case in ipairs({{95646,275,270180,1},{98815,484,284845,4}}) do
  local q, pre, item, needed = unpack(case)
  turned[pre] = true
  local pickup = assert(step(d, "accept", q))
  assert(pickup.opt and pickup.pickLv == 24 and ns.Route.quests[q].ps[1] == pre)
  local state = E.Locate(a21)
  local at = assert(offer(state, q))
  local handIn
  for i = 1, at - 1 do
    local s = state.steps[i].s
    if s.q == pre and s.t == "turnin" and s.npc == pickup.npc then handIn = i end
  end
  assert(handIn and not state.na[at])
  -- James is visited twice. The overlay attaches to his last scheduled visit.
  assert(state.steps[at - 1].s.npc == pickup.npc)
  settings.optional = false
  state = E.Locate(a21)
  assert(state.na[assert(offer(state, q))])
  settings.optional = true
  ns.db.dNo[d.id] = true
  assert(not offer(E.Locate(a21), q))
  ns.db.dNo[d.id] = nil
  settings.dPre = false
  assert(not offer(E.Locate(a21), q))
  settings.dPre = true

  local goal = assert(step(d, "do", q))
  local ret = assert(step(d, "turnin", q))
  assert(not goal.map and not E.Applies(ret.when))
  active[q] = true
  assert(inside("do", q))
  bags[item] = needed - 1
  assert(not E.Applies(ret.when))
  bags[item], ready[q] = needed, true
  assert(E.Applies(ret.when) and not inside("do", q))
  active[q], bags[item], ready[q] = nil, nil, nil
end
print("Wetlands same-NPC optional pickups, skips and item turn-ins passed")
