-- Real route data and dungeon UI with a live journal and the two archive objectives.
local level, painting, paintingReady = 59, 0, false
local supplies, suppliesReady = {}, {}
local active, done, turned, settings = {}, {}, {}, {dPre=true, optional=true}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return level end
function GetItemCount(q) return q == 14679 and painting or supplies[q] or 0 end
function wipe(t) for k in pairs(t) do t[k]=nil end end
local function ready(q)
  if q == 5848 then return paintingReady end
  if suppliesReady[q] ~= nil then return suppliesReady[q] end
  return active[q] and done[1] and done[2]
end
local ns = {db={skip={},mark={},latch={},dNo={}},
  L=setmetatable({}, {__index=function(_, key) return key end}),
  UI={Get=function(k) return settings[k] end},
  C={IsOnQuest=function(q) return active[q] end,
     IsTurnedIn=function(q) return turned[q] end, IsReady=ready,
     Objectives=function(q)
       if q == 5251 then return {{done=done[1]}, {done=done[2]}} end
       if q == 5848 then return {{done=paintingReady}} end
     end}}
for _, path in ipairs({"Data/RouteA.lua","Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/"..path))("ShengLeveling",ns)
end
local E=ns.E
E.Build()
local d=assert(E.DungeonByInstance(329))
local function find(st,t,q)
  for i,w in ipairs(st.list) do if w.s.t==t and w.s.q==q then return w.s,i end end
end
local function inside(q)
  for _,w in ipairs((E.InstanceState(d) or {}).steps or {}) do if w.s.q==q then return w.s end end
end
local a56=E.byId["04-56"]
local npc, before=find(a56,"turnin",6030)
local pick, after=find(a56,"accept",5251)
assert(after==before+1 and npc.npc==pick.npc and npc.x==pick.x and npc.y==pick.y)
assert(pick.opt and E.Applies(pick.when) and pick.when.lvMin==55)
level=54
assert(not E.Applies(pick.when))
level=55
settings.dPre=false
assert(not E.Applies(pick.when))
settings.dPre,settings.optional=true,false
assert(not E.Applies(pick.when))
settings.optional,ns.db.dNo[d.id]=true,true
assert(not E.Applies(pick.when))
ns.db.dNo[d.id]=nil
local info=ns.Route.quests[5251]
assert(not (info.ps or {})[1] and not (info.pg or {})[1])
assert(find(d,"accept",5251).pickLv==55)
local burn=find(d,"do",5251)
local paint=find(d,"do",5848)
assert(not burn.map and not paint.map and burn.spot==paint.spot)
assert(burn.spot:find("加爾福特",1,true) and burn.spot:find("雙月",1,true) and burn.spot:find("沒人",1,true))
local deliver=find(d,"turnin",5251)
local earlyReturn=find(E.byId["04-59"],"turnin",5251)
assert(not E.Applies(deliver.when) and not E.Applies(earlyReturn.when))
active[5251]=true
assert(inside(5251)==burn and not inside(5848))
-- Neither a boss kill alone nor an archive interaction alone grants a turn-in.
for bits=0,3 do
  done[1],done[2]=bits%2==1,bits>=2
  assert(E.Applies(deliver.when)==(bits==3) and E.Applies(earlyReturn.when)==(bits==3))
end
-- A player without the painting quest immediately returns to the Duke when ready.
assert(not inside(5251) and E.DungeonNext(d,false).step.s==deliver)
done[2],active[5848]=false,true
assert(inside(5251)==burn and inside(5848)==paint)
painting,paintingReady=1,true
assert(inside(5251)==burn and not inside(5848))
done[2]=true
-- Return the painting first, then finish at the chapel next to the flight master.
local paintingReturn=find(d,"turnin",5848)
for _, sample in ipairs({{0,false},{1,false},{0,true},{1,true}}) do
  painting,paintingReady=sample[1],sample[2]
  local canDeliver=painting==1 and paintingReady
  assert(E.Applies(paintingReturn.when)==canDeliver)
  assert(E.DungeonNext(d,false).step.s==(canDeliver and paintingReturn or deliver))
end
active[5848]=nil
assert(not E.Applies(paintingReturn.when)) -- stale ready, quest item still in bags
active[5848],painting,turned[5848]=nil,0,true
assert(E.DungeonNext(d,false).step.s==deliver)
active[5251],turned[5251]=nil,true
assert(not E.Applies(earlyReturn.when) and not E.Applies(deliver.when))
print("Stratholme chapel pickup, independent archive/painting states and return order passed")

-- The three independent supply quests share a chapel, not their objective or item.
local chapel = E.byId["04-59"]
local supplyQuests = {{5212, 13174, 20}, {5243, 13180, 5}, {5214, 13172, 1}}
for _, quest in ipairs(supplyQuests) do
  local q, item, count = unpack(quest)
  local advancePickup = find(a56, "accept", q)
  local pickup = find(d, "accept", q)
  local objective = find(d, "do", q)
  local post = find(d, "turnin", q)
  local world = find(chapel, "turnin", q)
  local info = ns.Route.quests[q]
  assert(advancePickup.when.dungeonPrep == d.id and advancePickup.opt)
  assert(pickup.ph == "pre" and pickup.pickLv == 55 and pickup.npc == world.npc)
  assert(objective.ph == "in" and not objective.map and post.ph == "post")
  assert(not (info.ps or {})[1] and not (info.pg or {})[1])
  level = 54
  assert(not E.Applies(advancePickup.when))
  level = 55
  for _, key in ipairs({"dPre","optional"}) do
    settings[key] = false
    assert(not E.Applies(advancePickup.when))
    settings[key] = true
  end
  ns.db.dNo[d.id] = true
  assert(not E.Applies(advancePickup.when))
  ns.db.dNo[d.id] = nil
  assert(E.Applies(advancePickup.when))

  -- Include stale journal flags, a consumed vial, enough items without the
  -- quest and possession without a client-confirmed hand-in.
  for _, logged in ipairs({false,true}) do
    for _, isReady in ipairs({false,true}) do
      for _, number in ipairs({count-1,count}) do
        active[q], suppliesReady[q], supplies[item] = logged, isReady, number
        local valid = logged and isReady and number >= count
        assert(E.Applies(post.when) == valid and E.Applies(world.when) == valid)
        if valid then
          assert(E.DungeonNext(d,false).step.s == post)
          assert(not inside(q))
        elseif logged and not isReady then
          assert(inside(q) == objective)
        end
      end
    end
  end
  active[q], suppliesReady[q], supplies[item] = nil, nil, nil
end
-- Preserve the west-bank painting stop when both that and a chapel quest are ready.
active[5848], turned[5848], paintingReady, painting = true, nil, true, 1
active[5243], suppliesReady[5243], supplies[13180] = true, true, 5
assert(E.DungeonNext(d,false).step.s == paintingReturn)
active[5848], turned[5848], painting = nil, true, 0
assert(E.DungeonNext(d,false).step.s == find(d,"turnin",5243))
print("Stratholme chapel prep, independent material counts and west-bank priority passed")
