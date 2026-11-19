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

-- On the return visit to Un'Goro, finish the volcano before starting Ringo's
-- escort. The hive and the western turn-in stay outside the escort sequence.
local craterReturn = alliance["04-52"]
-- Torwa is an optional stop for characters without U'cha's Pelt. Druids
-- still have their own quests there. The return to Gadgetzan uses the next
-- eligible destination so a walker can go straight to the quest giver.
local uchaIndex, ucha = find(craterReturn, "turnin", 4301)
assert(ucha.when.onQuestAny[1] == 4301 and ucha.when.readyQuest == 4301)
assert(ucha.when.bag.item == 11476 and ucha.when.bag.count == 1)
local druidEnd = find(craterReturn, "turnin", 9053)
assert(uchaIndex < find(craterReturn, "accept", 9052) and druidEnd > uchaIndex)
local exit = craterReturn[druidEnd + 1]
assert(exit.t == "travel" and exit.sameMapPreview and not exit.x and not exit.when)
assert(exit.key0 == "托爾瓦旁沒有飛行點：從他身後的坡道出安戈洛環形山進塔納利斯，往東北跑到加基森。")
assert(exit.text:find("馬紹爾營地", 1, true) and exit.text:find("東南坡", 1, true))
assert(find(craterReturn, "turnin", 4504) == druidEnd + 2)
assert(find(craterReturn, "turnin", 4496) < find(craterReturn, "turnin", 4502))
local summit = find(craterReturn, "do", 974)
local ringo = find(craterReturn, "turnin", 4492)
local home = find(craterReturn, "turnin", 4491)
assert(find(craterReturn, "do", 4502) < summit and summit+1 == ringo)
assert(home == ringo+3 and craterReturn[ringo+1].q == 4491)
local east = find(craterReturn, "do", 4287)
local hive, gland = find(craterReturn, "do", 4496)
local west = find(craterReturn, "do", 4288)
local report = find(craterReturn, "turnin", 974)
assert(home < east and east < hive and hive < west)
assert(gland.opt and gland.map == 1449 and gland.x==51.46 and #gland.more==1)
assert(gland.when.missingBag.item==11837)
local soil=craterReturn[hive+1]
assert(soil.sameObjective and soil.q==4496 and soil.opt and soil.when.bag.item==11837)
assert(soil.when.missingBag.item==11018 and soil.when.missingBag.count==5 and #soil.more==2)
assert(west+1 == report and report+1 == find(craterReturn, "accept", 980))
assert(report < find(craterReturn, "turnin", 4285))

local crater = alliance["04-48"]
local food
for i, s in ipairs(crater) do
  if s.when and s.when.missingBag and s.when.missingBag.item == 11113 then food = i end
end
assert(food and crater[food].map == 1449 and crater[food].when.onQuestAny[1] == 3881)
assert(find(crater, "accept", 3881) < food and food < find(crater, "do", 3883))
assert(find(crater, "do", 3883) < find(crater, "do", 3881))
assert(find(crater, "do", 3882) < find(crater, "turnin", 3882))
local craterGates = {}
for _, step in ipairs(crater) do
  if step.t == "level" then craterGates[step.lv] = step end
end
assert(craterGates[50] and not craterGates[50].chooseGrindSpot)
assert(craterGates[51] and craterGates[51].chooseGrindSpot and not craterGates[51].x)
assert(allianceMeta["04-49"].lv[1] == 51)
local gorge = horde["04-34"]
assert(find(gorge, "turnin", 3442) < find(gorge, "accept", 3443))
assert(find(gorge, "accept", 3443) < find(gorge, "do", 7729))

-- Keep the level gate after the underground kills and before the guarded plans.
local allianceGorge = alliance["04-45"]
local dinosaurs = find(allianceGorge, "do", 7727)
local plans, planStep = find(allianceGorge, "do", 7722)
local levelGate = allianceGorge[dinosaurs + 1]
assert(levelGate.t == "level" and levelGate.lv == 48 and levelGate.desc and levelGate.chooseGrindSpot)
assert(dinosaurs + 1 < plans and planStep.desc and allianceGorge[plans - 1].t == "note")

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
local inventory={}
carried = 4496
function GetItemCount(id) return inventory[id] or 0 end
for _, items in ipairs({{0,0,true,false},{0,5,true,false},{1,0,false,true},{1,4,false,true},{1,5,false,false}}) do
  inventory[11837],inventory[11018]=items[1],items[2]
  assert(ns.E.Applies(gland.when)==items[3] and ns.E.Applies(soil.when)==items[4])
end
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
