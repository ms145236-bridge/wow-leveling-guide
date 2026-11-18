-- Run from the repository root against the generated Alliance data.
function UnitFactionGroup() return "Alliance" end
local ns = {}
assert(loadfile("addon/ShengLeveling/Data/RouteA.lua"))("ShengLeveling", ns)
local phases = {}
for _, station in ipairs(ns.Route.stations) do
  if station.id == "05-d8" then
    for _, step in ipairs(station.steps) do
      if step.q == 96800 then
        assert(step.opt and not phases[step.ph])
        phases[step.ph] = step
      end
    end
  end
end
assert(phases.pre.t == "accept" and phases.pre.map == 1416 and phases.pre.pickLv == 30)
assert(phases["in"].t == "do" and not phases["in"].map)
assert(phases.post.t == "turnin" and phases.post.map == phases.pre.map)
assert(phases.post.when.bag.item == 273169 and phases.post.when.bag.count == 1)
assert(phases.post.when.onQuestAny[1] == 96800)
print("Scarlet Monastery book pickup, in-instance objective and conditional return passed")

-- A later group can finish the remaining wings after the Desolace/Southshore handoff.
local active, bossCount = false, 0
function UnitRace() return "Human", "Human", 1 end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return 47 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
ns.db = {skip={}, mark={}, latch={}, dNo={}}
ns.C = {
  IsOnQuest=function(q) return q == 1053 and active end,
  IsReady=function(q) return q == 1053 and active and bossCount == 4 end,
  IsTurnedIn=function() return false end,
  Objectives=function(q)
    if q == 1053 and active then
      local objectives = {}
      for i = 1, 4 do objectives[i] = {done = i <= bossCount} end
      return objectives
    end
  end,
}
ns.L = setmetatable({}, {__index=function(_, key) return key end})
ns.UI = {Get=function() return false end}
assert(loadfile("addon/ShengLeveling/Engine.lua"))("ShengLeveling", ns)
local E = ns.E
E.Build()
local monastery = E.byId["05-d8"]
assert(not E.DungeonNext(monastery, false))
active = true
for n = 0, 3 do
  bossCount = n
  assert(E.DungeonNext(monastery, false).kind == "ent")
  local nextStep = E.DungeonNext(monastery, true)
  assert(nextStep.kind == "in" and nextStep.step.s.q == 1053)
end
-- The dungeon hint names the unfinished quest instead of counting prerequisites.
ns.db.dDismiss = {}
ns.UI.Get = function(key) return key == "dungeonHint" end
for _, d in ipairs(E.dungeons) do if d ~= monastery then ns.db.dNo[d.id] = true end end
local hinted, hint = E.DungeonPrompt()
assert(hinted == monastery and hint == E.QName(1053), "revisit hint should name quest 1053")
ns.UI.Get = function() return false end
bossCount = 4
local turn = E.DungeonNext(monastery, false)
assert(turn.kind == "post" and turn.step.s.q == 1053 and turn.step.s.map == 1424)
ns.db.dNo[monastery.id] = true
assert(not E.DungeonNext(monastery, false))

local function index(station, verb, quest)
  for i, step in ipairs(E.byId[station].list) do
    if step.s.t == verb and step.s.q == quest then return i end
  end
end
assert(index("03-38", "accept", 1052) == index("03-38", "turnin", 261) + 1)
assert(index("04-44", "accept", 1053) == index("04-44", "turnin", 1052) + 1)
assert(index("04-53", "turnin", 1053))
print("Scarlet campaign covers its late handoff and separate wing visits")
