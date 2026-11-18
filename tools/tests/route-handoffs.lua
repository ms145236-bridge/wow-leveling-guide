-- From the repository root: lua5.1 tools/tests/route-handoffs.lua
-- Use the shipped Alliance data, with a different journal and flight map for each case.
local race, raceID, level = "Human", 1, 10
local active, completed, position = {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Mage", "MAGE" end
function UnitRace() return race, race, raceID end
function UnitLevel() return level end
function UnitXPMax() return 7600 end
function UnitXP() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={} }
local ns = { C={}, db=db, UI={Get=function() return false end}, L=setmetatable({}, {__index=function(_, key) return key end}) }
ns.C.IsOnQuest = function(q) return active[q] end
ns.C.IsReady = function(q) return completed[q] end
ns.C.IsTurnedIn = function() return false end
ns.C.XPBuff = function() return false end
ns.C.Position = function() return unpack(position) end
ns.C.ZoneTexts = function() end
ns.C.Bind = function() end
ns.C.LogQuestIDs = function() return {} end
ns.C.Objectives = function() end -- Some clients expose completion before refreshing objective counters.
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
for name, id in pairs({Human=1, Dwarf=3, Gnome=7, NightElf=4, Skyborne=33}) do
  race, raceID = name, id
  for _, start in ipairs({"Human", "Dwarf/Gnome", "NightElf", "Skyborne"}) do
    db.start = start
    E.Build()
    local loch = E.byId["01-9"]
    assert((loch ~= nil) == (start ~= "Skyborne"))
    if start == "NightElf" then
      db.auberdineChoice = "coast"
      assert(E.Next(E.byId["01-6"]).id == "02-10")
      db.auberdineChoice = "east"
      assert(E.Next(E.byId["01-6"]).id == "01-9")
      db.auberdineChoice = nil
    end
    if loch then
      local viaIronforge = name == "Dwarf" or name == "Gnome" or start == "Dwarf/Gnome"
      local hearths, earlyTurnins = {}, 0
      for _, step in ipairs(loch.list) do
        local s = step.s
        if E.Applies(s.when) then
          if s.t == "hearth" then hearths[s.bind] = true end
          if s.t == "turnin" and s.q == 416 then assert(s.hold); earlyTurnins = earlyTurnins + 1 end
          if s.q == 6387 then assert(name == "Dwarf" or name == "Gnome") end
        end
      end
      assert((hearths["塞爾薩瑪"] == true) == viaIronforge)
      assert((hearths["暴風城"] == true) ~= viaIronforge)
      assert(earlyTurnins == (viaIronforge and 1 or 0))
    end
  end
end
race, raceID, db.start, level = "Human", 1, nil, 43
E.Build()
-- The 16 November Forever hotfix moved Vale Screechers to the Isle of Dread.
-- The island is verified, but no individual post-hotfix spawn is confirmed.
do
  local coast = E.byId["03-41"].list
  local function find(steps, verb, quest)
    for i, step in ipairs(steps) do
      if step.s.t == verb and step.s.q == quest then return i, step end
    end
  end
  assert(find(E.byId["03-40"].list, "accept", 3520))
  assert(find(E.byId["04-43"].list, "turnin", 3520))
  local islandBoss = find(coast, "do", 2870)
  local spiritsIndex, spirits = find(coast, "do", 3520)
  local wreck = find(coast, "turnin", 4125)
  local pickup = find(coast, "accept", 4127)
  assert(islandBoss + 1 == spiritsIndex and spiritsIndex + 1 == wreck and wreck + 1 == pickup)
  local _, earlyGroup = find(E.byId["05-d10"].list, "do", 3520)
  local temple = E.DungeonByInstance(109)
  local _, templeSpirits = find(temple.list, "do", 3520)
  local workCount = 0
  for _, station in ipairs(ns.Route.stations) do
    for _, step in ipairs(station.steps) do
      if step.q == 3520 and step.t == "do" then
        workCount = workCount + 1
        assert(not step.x and not step.y and not step.more)
        assert(step.desc == spirits.s.desc)
        if station.dungeon then assert(step.ph == "pre" and step.outsideObjective) end
      end
    end
  end
  assert(workCount == 3 and spirits.s.desc:find("恐怖之島海岸", 1, true))
  assert(spirits.s.desc:find("葉基亞的樹枝", 1, true))
  local _, relic = find(coast, "do", 2870)
  local _, courierReturn = find(coast, "turnin", 4125)
  local _, wreckOffer = find(coast, "accept", 4127)
  local oldTurned = ns.C.IsTurnedIn
  active[3520] = true
  for _, clearedCave in ipairs({false, true}) do
    for _, clearedWreck in ipairs({false, true}) do
      ns.C.IsTurnedIn = function(q)
        return (q == 2870 and clearedCave) or ((q == 4125 or q == 4127) and clearedWreck)
      end
      assert(E.QuickDone(relic) == clearedCave)
      assert(E.QuickDone(courierReturn) == clearedWreck and E.QuickDone(wreckOffer) == clearedWreck)
      assert(not E.QuickDone(spirits))
      completed[3520] = true
      assert(E.QuickDone(spirits) and E.QuickDone(earlyGroup) and E.QuickDone(templeSpirits))
      completed[3520] = nil
    end
  end
  ns.C.IsTurnedIn = oldTurned
  for _, case in ipairs({{209,3527}, {109,3446}}) do
    local dungeon, all = E.DungeonByInstance(case[1])
    for _, journal in ipairs({{}, {3527}, {3446}, {3527,3446}}) do
      for _, quest in ipairs(journal) do active[quest] = true end
      local found = false
      local state = E.InstanceState(dungeon, all)
      for _, w in ipairs(state and state.steps or {}) do
        assert(w.s.q ~= 3520, "outdoor spirits cannot be collected inside either dungeon")
        if w.s.q == case[2] then found = true end
      end
      assert(found == (active[case[2]] == true))
      for _, quest in ipairs(journal) do active[quest] = nil end
    end
  end
  -- The catalogue-only objectives have no explicit in-phase row in these guides.
  -- An outdoor prerequisite may be the next stop before entering, but never inside.
  local islandObjectives = ns.C.Objectives
  local spiritsCollected
  ns.C.Objectives = function(q)
    if q == 3520 then return {{have=spiritsCollected, need=3, done=spiritsCollected==3}} end
  end
  db.skip["a:2864"] = "a:2864"
  ns.C.IsTurnedIn = function(q) return q == 3445 or q == 3444 or q == 3446 or q == 3447 end
  for _, case in ipairs({{209, 45, 3042}, {109, 52, 1475}, {109, 52, 3373}}) do
    local dungeon = E.DungeonByInstance(case[1])
    level = case[2]
    for _, progress in ipairs({{"accept", 0}, {"do", 1}, {"turnin", 3}}) do
      spiritsCollected = progress[2]
      active[3520] = spiritsCollected > 0 or nil
      completed[3520] = spiritsCollected == 3 or nil
      local outdoors = assert(E.DungeonNext(dungeon, false))
      assert(outdoors.kind == "pre" and outdoors.step.s.q == 3520 and outdoors.step.s.t == progress[1])
      assert(not E.DungeonNext(dungeon, true), "outdoor prerequisite alone gives no indoor reminder")
      active[case[3]] = true
      local indoors = assert(E.DungeonNext(dungeon, true))
      assert(indoors.kind == "in" and indoors.step.s.q == case[3])
      active[case[3]] = nil
    end
  end
  level, db.skip["a:2864"], active[3520], completed[3520] = 43, nil, nil, nil
  ns.C.IsTurnedIn, ns.C.Objectives = oldTurned, islandObjectives
end

-- Tran'rek is a city conversation even if the client has not refreshed its counters.
do
  local zf = E.DungeonByInstance(209)
  local outside = assert(E.DungeonNext(zf, false)).step.s
  assert(outside.q == 2864 and outside.t == "accept" and outside.map == 1434)
  local originalTurned, originalObjectives = ns.C.IsTurnedIn, ns.C.Objectives
  ns.C.IsTurnedIn = function(q) return q == 3520 or q == 3527 or q == 2865 or q == 2768 end
  active[2864], active[3042] = true, true
  for _, visitLevel in ipairs({45, 59}) do
    level = visitLevel
    for _, cityState in ipairs({"unknown", "emptyObjectives", "ready"}) do
      completed[2864] = cityState == "ready"
      ns.C.Objectives = function(q) if q == 2864 and cityState == "emptyObjectives" then return {} end end
      local hud = assert(E.InstanceState(zf))
      assert(#hud.steps == 1 and hud.steps[1].s.q == 3042)
      local panel = assert(E.DungeonNext(zf, true))
      assert(panel.kind == "in" and panel.step.s.q == 3042)
      if cityState ~= "unknown" then
        local handoff = assert(E.DungeonNext(zf, false)).step.s
        assert(handoff.q == 2864 and handoff.t == "turnin" and handoff.map == 1446)
      end
      active[3042] = nil
      assert(not E.InstanceState(zf) and not E.DungeonNext(zf, true))
      active[3042] = true
    end
  end
  active[2864], completed[2864] = nil, nil
  ns.C.Objectives = function(q)
    if q == 3042 then return {{have=1, need=20, done=false}} end
  end
  for _, cityHandedIn in ipairs({false, true}) do
    ns.C.IsTurnedIn = function(q) return q == 2864 and cityHandedIn end
    for _, visitLevel in ipairs({45, 59}) do
      level = visitLevel
      assert(E.InstanceState(zf).steps[1].s.q == 3042)
      local current = assert(E.DungeonNext(zf, true))
      assert(current.kind == "in" and current.step.s.q == 3042)
      active[3042] = nil
      assert(not E.InstanceState(zf) and not E.DungeonNext(zf, true))
      active[3042] = true
    end
  end
  assert(ns.Route.quests[2864].xp == 390)
  level, active[2864], active[3042], completed[2864] = 43, nil, nil, nil
  ns.C.IsTurnedIn, ns.C.Objectives = originalTurned, originalObjectives
end

local st = E.byId["03-38"]
local function current()
  local state = E.Locate(st)
  return state.steps[assert(state.cur)].s
end
position = {1413, 62.5, 35.5}
assert(current().to == "石爪峰")
db.fpNodes["尼耶爾前哨站"] = true
assert(current().to == "尼耶爾前哨站")
position = {1443, 64.7, 10.4}
assert(current().t == "accept" and current().q == 261)
assert(ns.Route.quests[313].mob[1][2] == 8)
local jetsteam = ns.Route.quests[317].mob
assert(jetsteam[1][2] == 4 and jetsteam[2][2] == 2)
local ribs = ns.Route.quests[384]
assert(ribs.mob[1][2] == 6 and ribs.mob[2][1] == 0 and #ribs.tgo[2] == 0)
local ale = ns.Route.quests[319]
assert(ale.hard == 8 and not ale.soloElite and ale.xp + ns.Route.quests[320].xp == 1410)
assert(ns.Route.quests[320].ps[1] == 319)
race, raceID, level = "Dwarf", 3, 7
E.Build()
local kharanos = E.byId["01-4"]
for _,step in ipairs(kharanos.list) do
  local q = step.s.q
  if q and q ~= 319 and q ~= 320 then E.session[q] = true end
end
E.FillPlan(kharanos)
assert(E.Fill[319])
level = 9
E.FillPlan(kharanos)
assert(not E.Fill[319])
local state = E.Locate(kharanos)
for i,step in ipairs(state.steps) do
  if step.s.q == 320 then assert(state.na[i]) end
end
wipe(E.session)
local last = E.stations[#E.stations]
level = 60
assert(E.FillPlan(last).need == 0)
active[416], level = true, 10
assert(E.KillXP(416, level) > 0)
completed[416] = true
assert(E.KillXP(416, level) == 0)
-- An 11-minimum quest cannot pay the XP needed to reach 11.
local check = {id="fixture", lv={10,10}, list={}, index=#E.stations}
for _,t in ipairs({"accept","turnin"}) do
  check.list[#check.list+1] = {key=t, s={t=t, q=3524}}
end
assert(ns.Route.quests[3524].min == 11)
assert(E.FillPlan(check).questXP == 0)
-- At the very end of the route only the explicit three-slot reserve remains.
local afterLast = {index=#E.stations+1}
local journal = {}
ns.C.LogQuestIDs = function() return journal end
for n = 1, 40 do
  journal[n] = n
  if n >= 36 then
    assert(E.PreRoom(afterLast) == (n <= 37))
    assert(E.PreRoom(afterLast, 1) == (n <= 36))
    assert(E.LogFull() == (n == 40))
  end
end
while #journal > 37 do table.remove(journal) end
assert(E.PreRoom(afterLast))
print("All 20 Alliance origin combinations, conditional transport, quest handoffs and XP boundaries passed")

-- A mage standing below the Azshara cliff can have the same map position as
-- Xylem. The outstanding Sanath waypoint must take precedence over proximity.
level, race, raceID = 52, "Human", 1
E.Build()
local approach, pickup
for _,step in ipairs(E.byId["04-48"].list) do
  local s=step.s
  if s.t=="goto" and s.map==1447 and s.when and s.when.class and s.when.class[1]=="MAGE" then approach=step end
  if s.t=="accept" and s.q==8251 then pickup=step end
end
assert(approach and pickup)
position={pickup.s.map,pickup.s.x,pickup.s.y}
local options={detourOn=true,detourDist=5,groupOn=true,groupMax=4,groupDist=12}
ns.UI.Get=function(k) return options[k] end
local seconds=0
function GetTime() return seconds end
local probe={cur=1,steps={approach,pickup},done={},na={},wait={},inGroup={}}
assert(not E.Detour(probe))
seconds=4
assert(not E.Detour(probe))
local earlier={key="earlier",s={t="do",q=7,map=1447,x=60,y=40}}
probe.steps={earlier,approach,pickup}
assert(not E.Detour(probe))
probe.done[2]=true
assert(not E.Detour(probe))
seconds=8
assert(E.Detour(probe)==3)
-- Exercise the real nearby-group entry point with an outstanding waypoint,
-- then mark the waypoint complete and check that adjacent pickups group again.
wipe(active);wipe(completed);wipe(journal)
active[7],active[33]=true,true
local here={key="d:7",s={t="do",q=7,map=1447,x=30,y=40}}
local nearby={key="d:33",s={t="do",q=33,map=1447,x=30,y=40}}
local segment={id="terrain-fixture",lv={50,52},index=#E.stations,list={here,approach,nearby}}
position={1447,35,40}
local grouped=E.Locate(segment)
assert(grouped.cur==1 and not grouped.inGroup[3])
db.mark[approach.key]=true
grouped=E.Locate(segment)
assert(grouped.cur==1 and grouped.inGroup[3])
print("Terrain waypoint proximity and grouping checks passed")

local food = {onQuestAny={3881}, missingBag={item=11113, count=1}}
local count = 0
C_Item = {GetItemCount=function(id) return id == 11113 and count or 0 end}
active[3881] = nil
assert(not E.Applies(food))
active[3881] = true
assert(E.Applies(food))
count = 1
assert(not E.Applies(food))
assert(E.Applies({bag={item=11113, count=1}}))
print("Supply waypoint follows quest log and carried item")

-- A player can unlock the tablets before a first run or later at the Searing Gorge hand-in.
local uldaman = E.byId["05-d9"]
local advisorReturns = 0
local carryingTablet = false
C_Item.GetItemCount = function(id) return carryingTablet and id == 5824 and 1 or 0 end
wipe(active)
wipe(completed)
assert(ns.Route.quests[1139].ps[1] == 762)
for _, step in ipairs(uldaman.list) do
  local s = step.s
  if s.q == 1139 then
    assert(s.opt)
    if s.t == "accept" then assert(s.ph == "pre") end
    if s.t == "turnin" then
      assert(s.ph == "post" and s.map == 1455)
      carryingTablet = false
      assert(not E.Applies(s.when))
      carryingTablet = true
      assert(E.Applies(s.when))
      advisorReturns = advisorReturns + 1
    end
  end
end
assert(advisorReturns == 2)
assert(not E.InstanceState(uldaman))
active[1139] = true
local tablet = E.InstanceState(uldaman).steps[1].s
assert(tablet.q == 1139 and tablet.t == "do" and tablet.ph == "in" and not tablet.map)
completed[1139] = true
assert(not E.InstanceState(uldaman))
local foundLateOffer = false
for i, step in ipairs(E.byId["04-45"].list) do
  if step.s.q == 1139 then
    local previous = E.byId["04-45"].list[i - 1].s
    assert(step.s.t == "accept" and step.s.opt and previous.t == "turnin" and previous.q == 762)
    assert(step.s.npc == previous.npc)
    foundLateOffer = true
  end
end
assert(foundLateOffer)
print("Uldaman tablets checked for initial and repeat visits")

-- A party can still pick up Dark Iron Legacy early. The scheduled visit belongs
-- between the return to the Eastern Kingdoms and the Burning Steppes chapter.
local depths = E.byId["05-d11"]
assert(depths.after == "04-52" and depths.pickAt == "04-45")
assert(E.Next(E.byId[depths.after]).id == "04-54")
local anchor = E.byId[depths.after].list
local ship, lastHandIn
for _, step in ipairs(anchor) do
  local s = step.s
  if s.t == "boat" then ship = s end
  if s.t == "turnin" then lastHandIn = s end
end
assert(ship.from == "奧伯丁" and ship.to == "米奈希爾港" and lastHandIn.map == 1455)
for _, step in ipairs(depths.list) do
  assert(step.s.t ~= "fly" and step.s.t ~= "hearth", "BRD must not impose a fixed departure or return transit")
end
wipe(active)
wipe(completed)
wipe(db.fpNodes)
level = 52
local early = E.DungeonNext(depths, false)
assert(early and early.step.s.q == 3801 and early.step.s.t == "accept")
ns.C.IsTurnedIn = function(q) return q == 3801 end
active[3802] = true
local objective = E.DungeonNext(depths, true)
assert(objective and objective.step.s.ph == "in" and objective.step.s.t == "do" and objective.step.s.q == 3802)
completed[3802] = true
local monument = E.DungeonNext(depths, true)
assert(monument and monument.step.s.ph == "in" and monument.step.s.t == "turnin" and monument.step.s.q == 3802)
active[3802] = nil
ns.C.IsTurnedIn = function(q) return q == 3801 or q == 3802 end
local _, status = E.DungeonStatus(depths)
assert(status == "past")
assert(not E.DungeonNext(depths, false))
print("Blackrock Depths reaches the Eastern Kingdoms by boat, retains early pickup and finishes inside")
