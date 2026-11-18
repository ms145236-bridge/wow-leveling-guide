-- From the repository root: lua5.1 tools/tests/map-order.lua
local function route(side)
  function UnitFactionGroup() return side end
  local ns, stations, metadata = {}, {}, {}
  local file = side == "Alliance" and "RouteA" or "Route"
  assert(loadfile("addon/ShengLeveling/Data/" .. file .. ".lua"))("ShengLeveling", ns)
  for _, station in ipairs(ns.Route.stations) do
    stations[station.id] = station.steps
    metadata[station.id] = station
  end
  return stations, metadata
end

local function find(steps, verb, id)
  for i, step in ipairs(steps) do
    if step.t == verb and step.q == id then return i, step end
  end
end

local alliance, allianceMeta = route("Alliance")
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

local horde, hordeMeta = route("Horde")
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
local _, ingredients = find(island, "do", 92553)
assert(ingredients.map == 2521 and find(island, "do", 92553) < find(island, "turnin", 92553))
assert(find(island, "do", 92516) < find(island, "turnin", 92553))
local mine = alliance["01-9"]
assert(find(mine, "do", 432) + 1 == find(mine, "do", 433))
assert(find(mine, "do", 433) < find(mine, "turnin", 432))
local crater = horde["04-41"]
assert(find(crater, "do", 3883) < find(crater, "turnin", 3884))
assert(find(crater, "turnin", 3884) + 1 == find(crater, "turnin", 3881))

local temple = allianceMeta["05-d14"]
assert(temple.after == "04-49" and temple.inst[1] == 109)
for quest, class in pairs({[8253]="MAGE", [8257]="PRIEST", [8232]="HUNTER"}) do
  for verb, phase in pairs({accept="pre", ["do"]="in", turnin="post"}) do
    local _, step = find(temple.steps, verb, quest)
    assert(step.ph == phase and step.when.class[1] == class)
  end
end
local allianceCity = {[1453]=true, [1455]=true, [1457]=true}
for _, id in ipairs({8151, 8254}) do
  local _, trainer = find(temple.steps, "accept", id)
  assert(allianceCity[trainer.map] and trainer.npc and trainer.tgt)
end
for _, id in ipairs({3446, 3447, 3528}) do
  local _, step = find(temple.steps, "do", id)
  assert(step.ph == "in")
end
for _, steps in ipairs({alliance["03-24"], horde["02-12"]}) do
  local _, letter = find(steps, "accept", 6681)
  assert(letter and not letter.map and not letter.tgt)
end
local hold = hordeMeta["05-d33"]
assert(hold.pickAt == "04-38" and hold.after == "04-47" and hold.inst[1] == 2974)
local _, relic = find(hold.steps, "do", 99187)
assert(relic.ph == "in" and relic.when.class[1] == "PALADIN" and relic.when.race[1] == "Scourge")
print("Dungeon scheduling, class phases and Alliance-friendly quest trainers passed")
print("Same-map gathering, Felwood hand-ins and Horde class revisits passed")
