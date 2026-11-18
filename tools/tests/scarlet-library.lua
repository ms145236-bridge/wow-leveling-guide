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
