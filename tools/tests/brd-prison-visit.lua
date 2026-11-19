-- Confirm the actual BRD instance list, optional acceptance and ready handoffs.
local faction=assert(arg[1])
local ally=faction=="Alliance"
assert(ally or faction=="Horde")
local level, slots, map, x, y, offered, presses, group=59,39,nil,nil,nil,nil,0,false
local active, done, ready, handlers={}, {}, {}, {}
function UnitFactionGroup() return faction end
function UnitRace() return ally and "Human" or "Scourge",ally and "Human" or "Scourge",ally and 1 or 5 end
function UnitClass() return ally and "Priest" or "Paladin",ally and "PRIEST" or "PALADIN" end
function UnitLevel() return level end
function IsInGroup() return group end
function IsShiftKeyDown() return false end
function GetTime() return 30 end
function GetNumQuestLogEntries() return slots,slots end
function GetQuestID() return offered end
function AcceptQuest() presses=presses+1 end
function CreateFrame() return {RegisterEvent=function() end,SetScript=function(_,k,f) handlers[k]=f end} end
function wipe(t) for k in pairs(t) do t[k]=nil end end
SlashCmdList={}
local options={auto=true,optional=true,dPre=true}
local ns={
 db={skip={},mark={},notNow={},dNo={},latch={},pin={},fpNodes={}},
 UI={Get=function(k) return options[k] end},
 C={IsOnQuest=function(q)return active[q] end,IsReady=function(q)return ready[q] end,
    IsTurnedIn=function(q)return done[q] end,Position=function()return map,x,y end,
    LogQuestIDs=function()return {} end,Objectives=function()end, ZoneTexts=function()end},
 L=setmetatable({}, {__index=function(_,k)return k end}),msg=function()end,
 try=function(_,f,...)return f(...)end,
}
for _,file in ipairs({ally and "Data/RouteA.lua" or "Data/Route.lua","Engine.lua","Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/"..file))("ShengLeveling",ns)
end
local E=ns.E
E.Build()
local station,wings=E.DungeonByInstance(230)
assert(station)
local function inside(q)
  local state=E.InstanceState(station,wings)
  for _,step in ipairs(state and state.steps or {}) do
    if step.s.q==q then return step.s end
  end
end
local function row(q,t)
  for _,d in ipairs(wings or {station}) do
    for _,step in ipairs(d.list) do if step.s.q==q and step.s.t==t then return step.s,d end end
  end
end
local function claim(q)
  offered=q
  local before=presses
  handlers.OnEvent(nil,"QUEST_DETAIL")
  return before<presses
end
local function nextIs(st,inDungeon,s)
  local n=E.DungeonNext(st,inDungeon)
  return n and n.step and n.step.s==s
end
if ally then
  for _,info in ipairs({{4341,4342,50},{4241,4242,48}}) do
    local p,q,min=unpack(info)
    local pick,st=row(q,"accept")
    assert(pick and pick.npc==row(p,"turnin").npc)
    active[p],ready[p]=true,true
    assert(not inside(q) and not claim(q))
    active[p],ready[p],done[p]=nil,nil,true
    level=min-1; assert(not inside(q))
    level=min; slots=40; assert(not inside(q) and not claim(q))
    slots=39; options.optional=false; assert(not claim(q))
    options.optional=true; assert(inside(q)==pick)
    ns.db.skip["a:"..q]=true; assert(not inside(q) and not claim(q)); ns.db.skip["a:"..q]=nil
    group=true
    if q==4342 then assert(not claim(q)) else assert(claim(q)) end
    active[q]=true; slots=40
    if q==4342 then
      assert(inside(q)==row(q,"do"))
      ready[q]=true; assert(inside(q)==row(q,"turnin"))
    else
      assert(not inside(q))
      local handoff=row(q,"turnin")
      map,x,y=handoff.map,handoff.x,handoff.y
      assert(not E.Applies(handoff.when))
      ready[q]=true; assert(E.Applies(handoff.when) and nextIs(st,false,handoff))
      assert(not nextIs(st,true,handoff))
      for _,pos in ipairs({{1453,84.74,69.02},{1428,20,30},{}}) do
        map,x,y=unpack(pos)
        assert(not E.Applies(handoff.when) and not nextIs(st,false,handoff))
      end
    end
    active[q],ready[q],done[q]=nil,nil,true
    assert(not inside(q))
  end
else
  local pickup,st=row(3981,"accept")
  assert(pickup and not row(3982,"accept") and not row(4001,"turnin"))
  level=48
  map,x,y=pickup.map,pickup.x,pickup.y
  active[3906],ready[3906]=true,true; assert(not E.Applies(pickup.when) and not claim(3981))
  active[3906],ready[3906],done[3906]=nil,nil,true
  assert(E.Applies(pickup.when))
  level=47
  assert(not nextIs(st,false,pickup))
  level=48
  ns.db.skip["a:3981"]=true; assert(not E.Applies(pickup.when) and not claim(3981))
  ns.db.skip["a:3981"]=nil
  options.optional=false; assert(not claim(3981))
  options.optional=true
  map,x,y=1427,32.13,94.70
  assert(not E.Applies(pickup.when) and not nextIs(st,false,pickup) and not claim(3981))
  map,x,y=nil,nil,nil; assert(not E.Applies(pickup.when))
  map,x,y=pickup.map,pickup.x,pickup.y
  slots=40; assert(not E.Applies(pickup.when) and not claim(3981))
  slots=39; group=true; assert(claim(3981))
  active[3981]=true
  assert(inside(3981)==row(3981,"do"))
  ready[3981]=true; assert(inside(3981)==row(3981,"turnin"))
  assert(not nextIs(st,false,pickup))
  active[3981],ready[3981],done[3981]=nil,nil,true
  assert(not inside(3981))
end
print(faction.." BRD prison: native prerequisites, real journal space, pickups and handoffs passed")
