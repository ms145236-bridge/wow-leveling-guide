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
assert(#targets == 4 and targets[1].q == 95646 and targets[2].q == 98815)
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
-- Unstarted Un'Goro collection tasks reserve a slot on their actual pickup
-- visit. Quests already held still consume a real journal slot at Menethil.
do
  turned[275], turned[484] = true, true
  for held = 0, 2 do
    local log = {}
    for i = 1, held do
      local q = ({4301,4496})[i]
      active[q], log[i] = true, q
    end
    ns.C.LogQuestIDs = function() return log end
    for i = 0, 6 do -- up to 8 held: both sides of the 7-slot threshold
      if i > 0 then log[#log + 1] = 900000 + i end
      local state = E.Locate(a21)
      for _, q in ipairs({95646,98815}) do
        -- The Gnomeregan accepts ahead carry dungeon-prep tags, so they no longer count as mainline growth.
        assert((not state.na[assert(offer(state, q))]) == (#log < 7))
      end
    end
    active[4301],active[4496] = nil,nil
  end
  turned[275],turned[484] = nil,nil
  ns.C.LogQuestIDs = function() return {} end
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

-- The first Wetlands visit comes before a normally leveled character can pick
-- up Songblade Search in Lakeshire. Its checklist row never orders a detour.
local search, need = 95772, assert(step(d, "need", 95772))
assert(need.opt and need.ph == "pre" and not step(d, "accept", search))
assert(not offer(E.Locate(a21), search))
assert(not step(E.byId["02-14"], "accept", search))
assert(not step(E.byId["02-15"], "accept", search))
local redridge = E.byId["02-19"]
local take, i = step(redridge, "accept", search)
assert(take.opt and take.map == 1433 and take.when.lvMin == 24)
assert(redridge.list[i-2].s.q == 126 and redridge.list[i+1].s.q == 169)
assert(targets[4].q == search)
function UnitLevel() return 23 end
assert(not E.Applies(take.when))
function UnitLevel() return 24 end
assert(E.Applies(take.when))
local atRedridge = E.Locate(redridge)
assert(not atRedridge.na[assert(offer(atRedridge, search))])
settings.optional = false
assert(not E.Applies(take.when))
atRedridge = E.Locate(redridge)
assert(atRedridge.na[assert(offer(atRedridge,search))])
settings.optional, settings.dPre = true, false
assert(not E.Applies(take.when))
settings.dPre, ns.db.dNo[d.id] = true, true
assert(not E.Applies(take.when))
ns.db.dNo[d.id] = nil

local fallen = 95795
local talk, handoff = step(d,"turnin",search), step(d,"accept",fallen)
assert(talk.ph == "in" and not talk.map and handoff.ph == "in" and not handoff.map)
assert(talk.npc == handoff.npc and ns.Route.quests[fallen].ps[1] == search)
assert(not inside("do",search) and not inside("accept",fallen))
active[search] = true
assert(inside("do",search) and not inside("accept",fallen))
ready[search] = true
assert(inside("turnin",search) and not inside("accept",fallen))
-- A character who cleared the normal dungeon before visiting Redridge must
-- still be guided back for a journal-ready handoff located inside the dungeon.
assert(E.DungeonDone(d))
local label, state, revisit = E.DungeonStatus(d)
assert(state == "revisit" and revisit.s == talk)
assert(E.DungeonNext(d,false).kind == "ent")
assert(E.DungeonNext(d,true).step.s == talk)
active[search], ready[search], turned[search] = nil,nil,true
assert(inside("accept",fallen))
local back = assert(step(d,"turnin",fallen))
assert(back.ph == "post" and back.opt and back.map == take.map and back.npc == take.npc)
local pathBack, idx = step(E.byId["03-31"],"turnin",fallen)
assert(idx == 2 and pathBack.npc == take.npc and not E.Applies(pathBack.when))
local earlyReturn = assert(step(redridge, "turnin", fallen))
local returns = {earlyReturn, pathBack, back}
for _, row in ipairs(returns) do assert(not E.Applies(row.when)) end
active[fallen] = true
assert(handoff.outsideObjective)
for _, objectives in ipairs({function() end, function() return {} end}) do
  ns.C.Objectives = objectives
  assert(not inside("do", fallen) and not inside("accept", fallen))
  for _, row in ipairs(returns) do assert(not E.Applies(row.when)) end
end
ready[fallen] = true
for _, row in ipairs(returns) do assert(E.Applies(row.when)) end
assert(not inside("do",fallen) and not inside("accept",fallen))
active[fallen], ready[fallen], turned[fallen] = nil, nil, true
for _, row in ipairs(returns) do assert(not E.Applies(row.when)) end
print("Wetlands Songblade first visit, level-24 group preparation, in-instance handoff and Lakeshire return passed")

-- The level-55 Stratholme rows must not reserve slots at level 26. Actual
-- accepted quests, mandatory future steps and pending accept clicks still count.
settings.optional, settings.dPre = true, true
function UnitLevel() return 26 end
local _, requiredIndex = step(E.byId["03-23"], "accept", 299)
local _, prepIndex = step(E.byId["04-56"], "accept", 5212)
local required = E.byId["03-23"].list[requiredIndex]
local prep = E.byId["04-56"].list[prepIndex]
assert(not required.s.opt and prep.s.when.dungeonPrep)
local savedStations = E.stations
local plan = {index=1, list={required, prep}}
E.stations = {plan}
local journal = {}
ns.C.LogQuestIDs = function() return journal end
for free = 0, 5 do
  journal = {}
  for slot = 1, 40 - free do journal[slot] = 100000 + slot end
  for pending = 0, 2 do
    assert(E.PreRoom(plan, pending) == (free - pending - 1 >= 3))
  end
end
assert(E.PreRoom(plan, 1))
active[5212] = true
journal[#journal + 1] = 5212
assert(E.PreRoom(plan) and not E.PreRoom(plan, 1))
active[5212], journal[#journal] = nil, nil
E.stations = savedStations
print("Dungeon-prep log capacity preserves real, mandatory and pending slots")
