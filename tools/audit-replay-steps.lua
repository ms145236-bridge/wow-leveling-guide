-- Emit route metadata for the hand-in audit without loading the live client.
local faction = arg[1]
assert(faction == "Alliance" or faction == "Horde")
function UnitFactionGroup() return faction end
local ns = {}
local file = faction == "Alliance" and "RouteA.lua" or "Route.lua"
assert(loadfile("addon/ShengLeveling/Data/" .. file))("", ns)
for _, station in ipairs(ns.Route.stations) do
  for index, step in ipairs(station.steps or {}) do
    if step.t == "buy" then
      print(station.id, index, "buy", 0, step.item or 0, step.n or 1, 0, 0)
    elseif step.q and (step.t == "accept" or step.t == "turnin") then
      local when = step.when or {}
      local bag = when.bag or {}
      print(station.id, index, step.t, step.q, bag.item or 0, bag.count or 0, when.readyQuest or 0, step.hold and 1 or 0)
    end
  end
end
