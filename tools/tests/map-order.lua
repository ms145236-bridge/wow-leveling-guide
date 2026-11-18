-- From the repository root: lua5.1 tools/tests/map-order.lua
local function route(side)
  function UnitFactionGroup() return side end
  local ns, stations = {}, {}
  local file = side == "Alliance" and "RouteA" or "Route"
  assert(loadfile("addon/ShengLeveling/Data/" .. file .. ".lua"))("ShengLeveling", ns)
  for _, station in ipairs(ns.Route.stations) do stations[station.id] = station.steps end
  return stations
end

local function find(steps, verb, id)
  for i, step in ipairs(steps) do
    if step.t == verb and step.q == id then return i, step end
  end
end

local alliance = route("Alliance")
local island = alliance["01-8"]
local mossIndex, moss = find(island, "do", 94485)
assert(moss.map == 2521 and mossIndex < find(island, "do", 94486))
assert(find(island, "do", 92741) < find(island, "turnin", 94485))
assert(find(island, "turnin", 94485) + 1 == find(island, "turnin", 94487))
assert(find(island, "turnin", 94487) + 1 == find(island, "turnin", 94486))
assert(not find(alliance["04-48"], "turnin", 8257))
for _, station in ipairs({"04-49", "04-51"}) do
  local i, blood = find(alliance[station], "turnin", 8257)
  assert(blood.hold and blood.opt and blood.when.class[1] == "PRIEST")
  assert(blood.npc == alliance[station][i - 1].npc)
end

local horde = route("Horde")
for _, check in ipairs({
  {"03-17", 1718, 30, "WARRIOR"}, {"03-17", 1719, 30, "WARRIOR"},
  {"03-25", 97022, 40, "PALADIN"}, {"03-25", 94971, 40, "PALADIN"},
  {"04-30", 3631, 40, "WARLOCK"}
}) do
  local _, step = find(horde[check[1]], "accept", check[2])
  assert(step.when.lvMin == check[3] and step.when.class[1] == check[4])
  if check[4] == "PALADIN" then assert(step.when.race[1] == "Scourge") end
end
assert(find(horde["04-34"], "turnin", 3631))
local hasFlight
for _, s in ipairs(horde["03-17"]) do
  if s.t == "travel" and s.when and s.when.onQuestAny then
    if table.concat(s.when.onQuestAny, ",") == "1178,1111,1718,1719" then hasFlight = not s.opt end
  end
end
assert(hasFlight)
print("Same-map gathering, Felwood hand-ins and Horde class revisits passed")
