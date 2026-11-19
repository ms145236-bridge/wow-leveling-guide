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
-- Check the actual navigation cursor with the item absent, present, accepted,
-- and acquired after leaving Torwa. Keep the ordinary 4291 turn-in save key.
do
  local crater = E.byId["04-48"]
  local visit = {id="torwa-visit", lv=crater.lv, index=crater.index, list={}}
  for _, step in ipairs(crater.list) do
    local q, t = step.s.q, step.s.t
    if q == 87494 or (q == 4291 and t == "turnin") then
      visit.list[#visit.list + 1] = step
    end
    assert(not (q == 4284 and t == "turnin")) -- A late crystal set must not recall the player.
  end
  local offer, delivery, anchor = unpack(visit.list)
  assert(#visit.list == 3 and offer.s.t == "accept" and delivery.s.t == "turnin")
  assert(anchor.key == "t:4291" and anchor.note.when.withTurnin == 4291)
  assert(anchor.s.x == delivery.s.x and anchor.s.y == delivery.s.y)
  assert(ns.Route.quests[87494].min == 45 and ns.Route.quests[87494].xp == 5650)

  local oldLevel, oldItem, oldUI, oldTurned = level, GetItemCount, ns.UI.Get, ns.C.IsTurnedIn
  local owned, optional = false, false
  level, active[4291], completed[4291] = 49, true, true
  GetItemCount = function(id) return (id == 280459 and owned) and 1 or 0 end
  ns.UI.Get = function(k) return k == "optional" and optional end
  local function target()
    local state = E.Locate(visit)
    return state.cur and state.steps[state.cur]
  end
  assert(target() == anchor and not E.Applies(anchor.note.when))
  owned = true
  assert(target() == anchor and E.Applies(anchor.note.when)) -- The same mandatory card shows the item hint.
  optional = true
  assert(target() == offer)
  local oldLog = ns.C.LogQuestIDs
  local journal = {4291}
  for i = 2, 39 do journal[i] = 990000 + i end
  ns.C.LogQuestIDs = function() return journal end
  assert(target() == offer and E.Applies(anchor.note.when))
  journal[40] = 990040
  for _, showOptional in ipairs({false, true}) do
    optional = showOptional
    assert(target() == anchor and not E.Applies(anchor.note.when))
  end
  active[87494], completed[87494], journal[2] = true, false, 87494
  assert(target() == anchor and not E.Applies(anchor.note.when))
  completed[87494] = true
  assert(target() == delivery and not E.Applies(anchor.note.when))
  ns.C.LogQuestIDs = oldLog
  completed[87494] = false
  assert(target() == anchor and not E.Applies(anchor.note.when))
  active[87494], completed[87494] = nil, nil
  E.session[87494] = true
  assert(target() == anchor and not E.Applies(anchor.note.when))
  E.session[87494] = nil
  ns.C.IsTurnedIn = function(q) return q == 87494 end
  assert(target() == anchor and not E.Applies(anchor.note.when))
  ns.C.IsTurnedIn = oldTurned
  level = 44
  assert(not E.Applies(offer.s.when) and not E.Applies(anchor.note.when))
  level = 49
  active[87494], completed[87494], optional = true, true, false
  assert(target() == delivery)
  db.pin[visit.id] = {key="t:4291", wasDone=false}
  assert(target() == anchor) -- A saved pin still addresses the same row with the scale in the bag.
  db.pin[visit.id] = nil
  db.skip["t:4291"] = true
  assert(not target() and not E.Applies(anchor.note.when))
  db.skip["t:4291"], db.mark["t:4291"] = nil, true
  assert(not target() and not E.Applies(delivery.s.when))
  db.mark["t:4291"] = nil
  ns.C.IsTurnedIn = function(q) return q == 4291 end
  assert(not target() and not E.Applies(offer.s.when)) -- Old ready and journal flags may lag behind a confirmed turn-in.
  ns.C.IsTurnedIn = oldTurned
  assert(target() == delivery)
  completed[4291] = false
  assert(not E.Applies(delivery.s.when)) -- Torwa's required quest is not ready yet.
  completed[4291], completed[87494] = true, false
  assert(not E.Applies(delivery.s.when))
  completed[87494], owned = true, false
  assert(target() == anchor and not E.Applies(anchor.note.when)) -- A stale completion flag cannot replace the scale.
  active[4291], completed[4291], owned = nil, nil, true
  ns.C.IsTurnedIn = function(q) return q == 4291 end
  assert(not target()) -- A ready scale dropped at the northern camp causes no return trip.
  ns.C.IsTurnedIn = function(q) return q == 87494 end
  active[4291], completed[4291], active[87494], completed[87494], owned = true, true, nil, nil, false
  assert(target() == anchor and not E.Applies(anchor.note.when))
  active[4291], completed[4291] = nil, nil
  level, GetItemCount, ns.UI.Get, ns.C.IsTurnedIn = oldLevel, oldItem, oldUI, oldTurned
end

-- Players who pinned or marked the quest before the material-aware route keep
-- the same action when they loot a gland, lose it, or still need more soil.
do
  local crater = E.byId["04-52"]
  local key = "d:4496"
  local oldLevel, oldItem, oldUI = level, GetItemCount, ns.UI.Get
  local gland, soil = 0, 0
  level, active[4496] = 53, true
  GetItemCount = function(id)
    if id == 11837 then return gland end
    if id == 11018 then return soil end
    return 0
  end
  ns.UI.Get = function(k) return k == "optional" end
  local function objective()
    local state = E.Locate(crater)
    local index
    for i, step in ipairs(state.steps) do
      if step.s.q == 4496 and step.s.t == "do" then
        assert(not index and step.key == key)
        index = i
      end
    end
    assert(index)
    local open = not (state.done[index] or state.na[index] or state.wait[index])
    return open and state.steps[index].s, state.cur == index
  end
  db.pin[crater.id] = {key=key, wasDone=false}
  local bugs, pinned = objective()
  assert(pinned and bugs.map == 1449 and bugs.x == 51.46 and bugs.more[1][2] == 48.25)
  gland, soil = 1, 4
  local ground, stillPinned = objective()
  assert(stillPinned and db.pin[crater.id].key == key and ground.map == 1449 and ground.x == 52.49)
  assert(#ground.more == 2 and ground.more[1][2] == 40.75 and ground.more[2][2] == 28.01)
  gland = 0
  assert(objective() == bugs)
  db.pin[crater.id] = nil
  E.SetMark(key, true)
  gland = 1
  assert(not objective())
  E.SetMark(key, nil)
  db.skip[key] = true
  assert(not objective())
  db.skip[key] = nil
  soil = 5
  assert(not objective())
  completed[4496] = true
  assert(not objective())
  active[4496], completed[4496] = nil, nil
  level, GetItemCount, ns.UI.Get = oldLevel, oldItem, oldUI
end

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
      local priorInstance, priorInfo = IsInInstance, GetInstanceInfo
      IsInInstance = function() return true, "party" end
      GetInstanceInfo = function() return nil,nil,nil,nil,nil,nil,nil,case[1] end
      assert(not E.DungeonNext(dungeon, true), "outdoor prerequisite alone gives no indoor reminder")
      active[case[3]] = true
      local indoors = assert(E.DungeonNext(dungeon, true))
      assert(indoors.kind == "in" and indoors.step.s.q == case[3])
      active[case[3]] = nil
      IsInInstance, GetInstanceInfo = priorInstance, priorInfo
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
  ns.C.IsTurnedIn = function(q) return q ~= 3042 end
  ns.C.Objectives = function(q)
    if q == 3042 then return {{have=20, need=20, done=true}} end
  end
  completed[3042] = true
  for _, visitLevel in ipairs({45, 59}) do
    level = visitLevel
    assert(not E.InstanceState(zf) and not E.DungeonNext(zf, true))
    local city = assert(E.DungeonNext(zf, false)).step.s
    assert(city.t == "turnin" and city.q == 3042 and city.map == 1446)
  end
  completed[3042] = nil
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
-- 1.13.47：淒涼之地改在 35–37 級；沒接鐵爐堡 1453 的角色看不到尋物公司 1458、1454，第一件是瓦拉里爾 1437
assert(current().t == "accept" and current().q == 1437)
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

-- The envelope is underwater. Its projected position on the bridge cannot
-- prove the envelope was looted or that its quest was accepted.
do
  local wetlands = E.byId["03-23"]
  local explosives, letter, report
  for i, step in ipairs(wetlands.list) do
    local w = step.s
    assert(not (w.t == "goto" and w.map == 1417 and w.x == 44.3 and w.y == 92.9))
    if w.q == 633 and w.t == "do" then explosives = i end
    if w.q == 637 and w.t == "accept" then letter = i end
    if w.q == 633 and w.t == "turnin" then report = i end
  end
  assert(explosives < letter and letter < report)
  local pickup = wetlands.list[letter]
  assert(pickup.s.map == 1417 and pickup.note and pickup.s.desc)
  position = {1417, 44.3, 92.9}
  local water = E.Locate(wetlands)
  local function pickupDone(state)
    for i, step in ipairs(state.steps) do
      if step.key == pickup.key then return state.done[i] end
    end
  end
  assert(pickupDone(water) == false)
  position = {1455, 63.5, 67.3}
  local originalCount = E.ItemCount
  for _, item in ipairs({4432, 4433, 0}) do
    E.ItemCount = function(id) return id == item and 1 or 0 end
    local state = E.Locate(wetlands)
    local found
    for _, step in ipairs(state.steps) do if step.key == "a:637" then
      assert(not found, "a:637 must remain one saved step")
      found = step
    end end
    assert(found and not pickupDone(state))
    if item == 4433 then
      assert(not found.s.map and not found.s.x and found.note.text == found.s.desc)
      assert(found.s.desc == "右鍵背包裡的浸水的信封接任務。")
    else
      assert(found.s.map == 1417 and found.note and found.s.x == 44.3)
    end
  end
  E.ItemCount = originalCount
  active[637] = true
  assert(pickupDone(E.Locate(wetlands)))
  active[637] = nil
  position = {}
end

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

-- Both quests visit the platform, but its plan and the elite's head are independent.
do
  level = 48
  race, raceID, db.start = "Human", 1, "Human"
  E.Build()
  local byKey = {}
  for _, step in ipairs(E.byId["04-45"].list) do byKey[step.key] = step end
  local bag, objectives = {}, {}
  C_Item.GetItemCount = function(id) return bag[id] or 0 end
  ns.C.Objectives = function(id) return objectives[id] end
  for q, item in pairs({[7701]=18946, [7722]=18922}) do
    local work, hand = byKey["d:" .. q], byKey["t:" .. q]
    active[q], completed[q] = true, true
    local other = item == 18946 and 18922 or 18946
    bag[item], bag[other] = 0, 1
    assert(not E.QuickDone(work) and not E.Applies(hand.s.when))
    bag[item], completed[q] = 1, false
    assert(E.QuickDone(work) and not E.Applies(hand.s.when))
    completed[q], objectives[q] = true, {{done=false, have=0, need=1}}
    assert(not E.Applies(hand.s.when))
    objectives[q] = {{done=true, have=1, need=1}}
    assert(E.Applies(hand.s.when))
  end
  local dragons = byKey["d:7727"]
  active[7727], completed[7727], objectives[7727] = true, false, {}
  assert(not E.QuickDone(dragons))
  completed[7727], objectives[7727] = true, {{done=false, have=19, need=20}}
  assert(not E.QuickDone(dragons) and not E.Applies(byKey["t:7727"].s.when))
  objectives[7727] = {{done=true, have=20, need=20}}
  assert(E.QuickDone(dragons) and E.Applies(byKey["t:7727"].s.when))
end

-- At an identified Kalimdor hub the player's actual eastern errand decides
-- the next leg. Old transit keys still address the same itinerary.
do
  local oldClass, oldZone, oldItems = UnitClass, ns.C.ZoneTexts, ns.UI.Get
  local q, desired, place, parentZone = 8254, false, nil, nil
  UnitClass = function() return "Priest", "PRIEST" end
  ns.C.ZoneTexts = function() return place, parentZone end
  ns.UI.Get = function(k) return k=="optional" and desired end
  level = 51
  E.Build()
  local s = E.byId["04-48"]
  for _, w in ipairs(s.list) do
    if w.s.ungoroExit then break end
    db.mark[w.key] = true
  end
  active[3661], completed[3661] = true, true
  local function nextLeg()
    local state = E.Locate(s)
    return state.steps[assert(state.cur)]
  end
  position = {1449, 45.23, 5.83}
  assert(nextLeg().s.classTransfer and nextLeg().s.text:find("加基森"))
  active[q] = true
  local camp = nextLeg()
  assert(camp.key == "04-48#fly:魯瑟蘭村" and camp.s.localTransfer and camp.s.text:find("加基森"))
  active[q] = nil
  db.skip["a:8254"] = true
  assert(nextLeg().key == camp.key and nextLeg().s.localTransfer)
  db.skip["a:8254"] = nil
  db.notNow["a:8254"] = true
  position, place = {1439,32.3,44.1}, "奧伯丁"
  assert(nextLeg().key == camp.key and nextLeg().s.text:find("北碼頭"))
  assert(not db.latch["04-48#boat:奧伯丁"])
  position = {1439,33.7,42.1} -- Between the flight master and the north pier.
  assert(nextLeg().s.text:find("北碼頭"))
  for _, reported in ipairs({"霧海", ""}) do
    place = reported
    assert(nextLeg().s.text:find("先確認所在位置"))
  end
  position, place = {1438,54.8,97.2}, "魯瑟蘭村"
  assert(nextLeg().s.text:find("先確認所在位置"))
  position, place = {1438,55.5,92.05}, nil
  assert(nextLeg().s.text:find("先確認所在位置"))
  position, place = {1438,55.5,92.05}, "魯瑟蘭村"
  assert(nextLeg().s.q == 3661)
  position, place, parentZone = {1438,58.4,94.02}, "魯瑟蘭村", "黑海岸"
  assert(not E.AtRutheranFlightMaster(unpack(position)))
  assert(nextLeg().s.text:find("先確認所在位置"))
  parentZone = "泰達希爾"
  assert(E.AtRutheranFlightMaster(unpack(position)))
  parentZone = nil
  position, place = {1439,33.7,42.1}, "奧伯丁"
  for _, step in ipairs(s.list) do
    local leg = step.s
    if (leg.map == 1438 or leg.map == 1457) and (leg.t == "accept" or leg.t == "turnin") then
      db.skip[step.key] = true
    end
  end
  assert(not nextLeg().s.localTransfer)
  local oldLog, oldTurned = ns.C.LogQuestIDs, ns.C.IsTurnedIn
  local ids = {}
  for i=1,39 do ids[i] = 100000+i end
  ns.C.LogQuestIDs = function() return ids end
  ns.C.IsTurnedIn = function(qid) return qid == 2944 or oldTurned(qid) end
  db.skip["a:2943"] = nil
  assert(nextLeg().s.localTransfer, "one space for the available island follow-up")
  ids[40] = 100040
  local fullStep = nextLeg().s
  assert(not fullStep.localTransfer and fullStep.q ~= 2943 and fullStep.ungoroExit ~= "islandPortal")
  db.skip["t:3661"] = nil
  assert(nextLeg().s.localTransfer, "a held ready hand-in still warrants the island visit at 40/40")
  ns.C.LogQuestIDs, ns.C.IsTurnedIn = oldLog, oldTurned
  db.notNow["a:8254"] = nil
  UnitClass, ns.C.ZoneTexts, ns.UI.Get = oldClass, oldZone, oldItems
end

do
  local role, bind, place, city, showOptional = "PRIEST", nil, "馬紹爾營地", "安戈洛環形山", false
  UnitClass = function() return role, role end
  ns.C.Bind = function() return bind end
  ns.C.ZoneTexts = function() return place, city, place end
  ns.UI.Get = function(k) return k == "optional" and showOptional end
  ns.C.IsTurnedIn = function() return false end
  ns.C.LogQuestIDs = function() return {} end
  level = 51
  wipe(db.mark); wipe(db.skip); wipe(db.notNow); wipe(db.latch); wipe(db.pin)
  wipe(active); wipe(completed); wipe(E.session)
  E.Build()
  local s = E.byId["04-48"]
  for _,w in ipairs(s.list) do
    if w.s.ungoroExit then break end
    db.mark[w.key] = true
  end
  local function action()
    local state = E.Locate(s)
    return state.steps[assert(state.cur)]
  end
  assert(ns.Route.quests[8250].n == "法師公會" and ns.Route.quests[8254].n == "幫助塞納里奧")
  position = {1449,45.23,5.83}
  bind, db.boundK, db.boundRaw = "未辨識的旅店", "鐵爐堡", nil
  assert(action().s.text:find("加基森"))
  local hearthKey = action().key
  db.latch[hearthKey] = true
  assert(action().key == hearthKey and action().s.classTransfer and db.latch[hearthKey])
  db.mark[hearthKey] = true
  assert(action().key ~= hearthKey and db.mark[hearthKey])
  db.mark[hearthKey], db.skip[hearthKey] = nil, true
  assert(action().key ~= hearthKey and db.skip[hearthKey])
  db.skip[hearthKey], db.latch[hearthKey] = nil, nil
  E.Build()
  assert(action().s.classTransfer and db.boundRaw == bind) -- Old cache has already learned the wrong inn.
  bind = "鐵爐堡"
  assert(action().s.t == "hearth")
  bind, place, city, position = nil, "奧伯丁", "黑海岸", {1439,30.5,40.9}
  assert(action().s.text:find("30.5，40.9", 1, true))
  place, city, position = "暴風港", "暴風城", {1453,21.8,56.9}
  assert(action().s.text:find("靠穩後下船"))
  place, position = "聖光大教堂", {1453,49.50,45.21}
  local pickup = action()
  assert(pickup.key == "a:8254" and pickup.s.npc == "喬舒修士" and pickup.s.tgt == pickup.s.npc)
  active[8254] = true
  assert(action().s.text:find("21.8，56.9", 1, true))
  role, showOptional, place, city, position = "MAGE", true, "秘法區", "鐵爐堡", {1455,27.16,8.57}
  E.Build(); s=E.byId["04-48"]
  pickup = action()
  assert(pickup.key == "a:8250" and pickup.s.npc == "丁克")
  active[8250] = true
  local leg = action()
  assert(leg.key == "04-48#fly:米奈希爾港" and leg.s.ironReturn)
  assert(leg.s.map == 1455 and leg.s.x == 55.5 and leg.s.y == 47.8 and leg.note.text:find("礦道地鐵"))
  position = {1455,55.5,47.8}
  assert(action().s.ironReturn and not db.latch[leg.key])
  active[8250] = nil
  showOptional = false
  assert(action().key ~= "a:8250")
end

-- The old travel text was part of every saved skip, check, arrival and pin key.
local oldLordaeronKey = "05-d2#travel:遠程選做：入口在幽暗城上方的羅德隆廢墟，要穿過部落地區。從奧伯丁搭往米奈希爾港的船在南海鎮下船並開飛行點，往北經希爾斯布萊德丘陵、銀松森林走到提里斯法林地；出本後用爐石回暴風城，接回 「赤脊山 第一次」。"
local function lordaeronTravel()
  for _, step in ipairs(E.byId["05-d2"].list) do
    if step.s.t == "travel" and step.s.ph == "pre" then return step end
  end
end
local chineseTravel = assert(lordaeronTravel())
assert(chineseTravel.key == oldLordaeronKey)
assert(chineseTravel.s.text:find("先到米奈希爾港，再循北線到南海鎮下船", 1, true))
ns.uiZh, ns.uiLoc, ns.gameZh = false, "enUS", true
ns.Pad = function(text) return text end
ns.C.AreaName = function() end
ns.C.MapName = function() end
assert(loadfile("addon/ShengLeveling/Data/RouteA_enUS.lua"))("ShengLeveling", ns)
E.Localize()
E.Build()
local englishTravel = assert(lordaeronTravel())
assert(englishTravel.key == oldLordaeronKey)
assert(englishTravel.s.text:find("first to Menethil Harbor", 1, true))
print("Lordaeron travel keeps its original saved key before and after localization")
