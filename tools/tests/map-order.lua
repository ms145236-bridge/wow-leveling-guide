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
  return stations, metadata, ns.Route.quests
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

local horde, hordeMeta, hordeQuests = route("Horde")
-- Finish both XP-paying hand-ins before the level-58 pickup. A level-57 player
-- can gain the last XP at Bor after taking Larksbane's follow-up on the spot.
local silithus = horde["04-56"]
local fragments, larksbane = find(silithus, "turnin", 8284)
local deserter, tablet = find(silithus, "accept", 8285)
local texts = find(silithus, "turnin", 8318)
assert(deserter == fragments + 1 and larksbane.npc == tablet.npc)
assert(larksbane.map == tablet.map and larksbane.x == tablet.x and larksbane.y == tablet.y)
assert(texts == deserter + 1 and find(silithus, "accept", 8304) == texts + 1)
assert(hordeQuests[8285].ps[1] == 8284 and hordeQuests[8304].min == 58)
assert(not find(silithus, "accept", 8306))

local camp = horde["01-3"]
local hunt, questgiver = find(camp, "accept", 750)
assert(find(camp, "turnin", 747) + 1 == hunt)
local delivery = find(camp, "accept", 1656)
for quest, class in pairs({[3091]="WARRIOR", [3092]="HUNTER", [3093]="SHAMAN", [3094]="DRUID"}) do
  local pickup, note = find(camp, "accept", quest)
  local turnin, trainer = find(camp, "turnin", quest)
  assert(hunt < pickup and pickup < turnin and turnin < delivery)
  assert(note.npc == questgiver.npc and note.x == questgiver.x and note.y == questgiver.y)
  assert(hordeQuests[quest].races == 32 and hordeQuests[quest].ps[1] == 747)
  assert(note.when.class[1] == class)
  assert(trainer.when.class[1] == class)
  for i = hunt + 1, pickup - 1 do
    local condition = camp[i].when
    assert(condition and condition.class and condition.class[1] ~= class)
  end
end
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

-- Leave the vulture objective at the northeast of the Flats, turn in on the
-- eastern side first, and finish at Kravel before the conditional Ratchet trip.
local flats = horde["03-17"]
local prev = find(flats, "do", 1176)
for _, pair in ipairs({
  {"turnin", 1176}, {"accept", 1178}, {"turnin", 1175}, {"turnin", 1105},
  {"turnin", 1104}, {"accept", 1106}, {"turnin", 1110}, {"accept", 1111}
}) do
  local i, step = find(flats, pair[1], pair[2])
  assert(i == prev + 1 and step.map == 1441)
  if pair[2] == 1111 or pair[2] == 1178 then assert(step.opt) end
  prev = i
end
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

local crater = alliance["04-48"]
local food
for i, s in ipairs(crater) do
  if s.when and s.when.missingBag and s.when.missingBag.item == 11113 then food = i end
end
assert(food and crater[food].map == 1449 and crater[food].when.onQuestAny[1] == 3881)
assert(find(crater, "accept", 3881) < food and food < find(crater, "do", 3883))
assert(find(crater, "do", 3883) < find(crater, "do", 3881))
assert(find(crater, "do", 3882) < find(crater, "turnin", 3882))
assert(allianceMeta["04-49"].lv[1] == 51)
local gorge = horde["04-34"]
assert(find(gorge, "turnin", 3442) < find(gorge, "accept", 3443))
assert(find(gorge, "accept", 3443) < find(gorge, "do", 7729))
local lands = horde["04-36"]
for q, item in pairs({[2521]=8244, [3501]=10593}) do
  for _, verb in ipairs({"accept", "do", "turnin"}) do
    local _, s = find(lands, verb, q)
    assert(s.when.bag.item == item and s.when.bag.count == 1)
  end
end
assert(find(lands, "accept", 8423) < find(lands, "accept", 2583))
assert(find(lands, "turnin", 8423) < find(lands, "turnin", 2621))
assert(find(lands, "turnin", 2784) < find(lands, "accept", 2621))
assert(find(lands, "turnin", 2621) < find(lands, "accept", 2622))
assert(lands[#lands].t == "fly" and lands[#lands].to == "藏寶海灣")

-- Exercise the instance UI with just the player's own quest in the journal.
local carried, ready
local ns = { C = {
  IsOnQuest = function(q) return q == carried end,
  IsReady = function() return ready end
} }
assert(loadfile("addon/ShengLeveling/Engine.lua"))("ShengLeveling", ns)
local temple = {list={}}
for _, s in ipairs(horde["05-d23"]) do table.insert(temple.list, {s=s}) end
for _, q in ipairs({8425, 8232, 8413, 8253, 8422, 8236, 9053, 8257}) do
  carried, ready = q, false
  local state = assert(ns.E.InstanceState(temple))
  assert(#state.steps == 1)
  local s = state.steps[1].s
  assert(s.ph == "in" and s.q == q and s.hint and not s.map)
  ready = true
  assert(not ns.E.InstanceState(temple))
end
print("Un'Goro supplies, Searing Gorge, Blasted Lands and Horde temple objectives passed")

-- Complete the monolith before starting the escort. Both operations happen in the same ruins.
local feralas = alliance["04-50"]
local shay = find(feralas, "turnin", 2844)
assert(find(feralas, "accept", 2942) + 1 == shay)
assert(shay + 1 == find(feralas, "accept", 2845))
assert(shay + 2 == find(feralas, "do", 2845))
assert(find(feralas, "turnin", 2879) == find(feralas, "do", 2879) + 1)
local zephras = alliance["01-7"]
local lorian = find(zephras, "accept", 92464)
local leylines = find(zephras, "accept", 92597)
for _, q in ipairs({92481, 92485, 92532, 92482, 92483, 92484}) do
  local idx, profession = find(zephras, "accept", q)
  assert(idx > lorian and idx < leylines and profession.when.class)
end
for _, port in ipairs({alliance["03-37"], horde["03-28"]}) do
  local dockmaster = find(port, "turnin", 95119)
  assert(find(port, "accept", 95123) == dockmaster + 1)
  assert(find(port, "accept", 95122) == dockmaster + 2)
end
assert(find(alliance["01-1"], "accept", 91745) + 1 == find(alliance["01-1"], "accept", 5623))
assert(find(alliance["03-34"], "accept", 193) == find(alliance["03-34"], "turnin", 192) + 1)
assert(find(alliance["03-34"], "accept", 607) == find(alliance["03-34"], "turnin", 606) + 1)
assert(find(alliance["05-d7"], "turnin", 2930) == find(alliance["05-d7"], "turnin", 2931) + 1)
