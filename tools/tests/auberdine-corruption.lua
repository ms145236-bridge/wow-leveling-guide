local faction,race,id,class="Alliance","Dwarf",3,"PRIEST"
local level,map,x,y=17,1453,36.24,67.61
local active,turned,ready,log={}, {}, {}, {}
local now,offer,press=100,3765,0
local optional=true
function UnitFactionGroup() return faction end
function UnitClass() return class,class end
function UnitRace() return race,race,id end
function UnitLevel() return level end
function UnitSex() return 2 end
function UnitXP() return 0 end
function UnitXPMax() return 70000 end
function GetTime() return now end
function GetQuestID() return offer end
function AcceptQuest() press=press+1 end
function IsShiftKeyDown() return false end
function wipe(t) for k in pairs(t) do t[k]=nil end end
local h={}
function CreateFrame() return {RegisterEvent=function() end,SetScript=function(_,k,v) h[k]=v end} end
SlashCmdList={}
local ns={
 C={IsOnQuest=function(q) return active[q] end,IsTurnedIn=function(q) return turned[q] end,IsReady=function(q) return ready[q] end,
 Position=function() return map,x,y end,ZoneTexts=function() end,Bind=function() end,Objectives=function() return {{done=false}} end,
 LogQuestIDs=function() return log end,XPBuff=function() return false end},
 db={skip={},mark={},latch={},notNow={},pin={},carry={},dNo={},fpNodes={}},
 UI={Get=function(k) return k=="auto" or k=="optional" and optional end},msg=function() end,
 L=setmetatable({}, {__index=function(_,k)return k end}),try=function(_,fn,...)return fn(...) end}
for _,f in ipairs({faction=="Alliance" and "Data/RouteA.lua" or "Data/Route.lua","Engine.lua","Core.lua"}) do
 assert(loadfile("addon/ShengLeveling/"..f))("ShengLeveling",ns)
end

local E=ns.E;E.Build()
local q=3765
local function row(station,kind)
  local st=assert(E.byId[station])
  for _,w in ipairs(st.list) do if w.s.t==kind and w.s.q==q then return st,w end end
  error("missing "..station.." "..kind)
end
local early,earlyAccept=row("02-12","accept")
local earlyPort,earlyTurn=row("02-13","turnin")
local late,lateAccept=row("02-15","accept")
local landing,lateTurn=row("02-16","turnin")
assert(earlyAccept.key==lateAccept.key and earlyTurn.key==lateTurn.key)
local function visible(st,w,skip,mark)
  ns.db.station=st.id;wipe(ns.db.skip);wipe(ns.db.mark);wipe(ns.db.latch)
  for _,other in ipairs(st.list) do if other.key~=w.key then ns.db.skip[other.key]=true end end
  if skip then ns.db.skip[w.key]=true end
  if mark then ns.db.mark[w.key]=true end
  local state=E.Locate(st)
  return state.cur and state.steps[state.cur].key==w.key or false
end
local function auto(st,id)
  ns.db.station=st.id;offer=id;now=now+5
  local count=press
  h.OnEvent(nil,"QUEST_DETAIL")
  return press>count
end
local function loadLog(n)
  wipe(log)
  for i=1,n do log[i]=910000+i end
end
level=17;map,x,y=1453,36.24,67.61
assert(not visible(early,earlyAccept) and not visible(late,lateAccept))
level=18;optional=false;assert(visible(early,earlyAccept) and auto(early,q));optional=true
level=23
for _,room in ipairs({0,39,40}) do
  loadLog(room); assert(visible(late,lateAccept)==(room<40))
  assert(not auto(late,q),"late pickup stays manual")
end
loadLog(0)
assert(not visible(late,lateAccept,true));assert(not visible(late,lateAccept,false,true))
ns.db.notNow[earlyAccept.key]=true;assert(not visible(late,lateAccept));wipe(ns.db.notNow)
optional=false;E.Fill[q]=true; assert(not visible(late,lateAccept) and not auto(late,q));optional=true;E.Fill[q]=nil
for _,point in ipairs({{1439,38.33,43.04},{1453,21.8,56.8},{1453},{}}) do
  map,x,y=unpack(point);assert(not visible(late,lateAccept) and not auto(late,q))
end
map,x,y=1453,36.24,67.61;turned[q]=true;assert(not visible(late,lateAccept));turned[q]=nil
active[1275]=true;assert(not visible(late,lateAccept));active[1275]=nil
active[q]=true;assert(not visible(late,lateAccept))
map,x,y=1439,38.84,43.42
loadLog(40);optional=false
assert(not visible(landing,lateTurn))
ready[q]=true
assert(visible(earlyPort,earlyTurn) and visible(landing,lateTurn))
active[1275]=true;assert(visible(landing,lateTurn));active[1275]=nil
assert(not visible(landing,lateTurn,true) and not visible(landing,lateTurn,false,true))
map,x,y=1440,26.60,36.70;assert(not visible(landing,lateTurn))
map,x,y=1439,38.84,43.42;active[q]=nil;assert(not visible(landing,lateTurn))
-- Use actual event callbacks with the same cached state normal HUD refresh supplies.
local npc,offers,selected=earlyAccept.s.npc,{},0
function UnitName() return npc end
C_GossipInfo={
  GetAvailableQuests=function() return offers end, GetActiveQuests=function() return {} end,
  SelectAvailableQuest=function(id) if id==q then selected=selected+1 end end,
}
function GetNumAvailableQuests() return #offers end
function GetAvailableTitle() return ns.Route.quests[q].n end
local stateSlot
for i=1,100 do
  local name=debug.getupvalue(h.OnUpdate,i)
  if not name then break end
  if name=="lastState" then stateSlot=i; break end
end
assert(stateSlot)
local function focus(st,w)
  visible(st,w)
  debug.setupvalue(h.OnUpdate,stateSlot,E.Locate(st))
end
local key=earlyAccept.key
local function fire(event)
  now=now+5;h.OnEvent(nil,event)
end
level=17;map,x,y=1453,36.24,67.61;optional=true
wipe(turned);wipe(active);wipe(ready);wipe(ns.db.notNow);loadLog(0)
focus(early,earlyAccept);fire("GOSSIP_SHOW");assert(not ns.db.notNow[key])
level=18;focus(early,earlyAccept);fire("GOSSIP_SHOW");assert(ns.db.notNow[key])
focus(late,lateAccept)
local before=press
offers={{questID=q}};offer=q
fire("QUEST_GREETING");assert(ns.db.notNow[key],"title-only greeting is ambiguous")
npc="Another giver";fire("GOSSIP_SHOW");assert(ns.db.notNow[key])
npc=lateAccept.s.npc;offers={{questID=1275}};fire("GOSSIP_SHOW");assert(ns.db.notNow[key])
offers={{questID=q}}
optional=false;fire("GOSSIP_SHOW");assert(ns.db.notNow[key]);optional=true
loadLog(40);fire("GOSSIP_SHOW");assert(ns.db.notNow[key]);loadLog(39)
x,y=21.8,56.8;fire("GOSSIP_SHOW");assert(ns.db.notNow[key]);x,y=36.24,67.61
ns.db.skip[key]=true;fire("GOSSIP_SHOW");assert(ns.db.notNow[key] and ns.db.skip[key]);ns.db.skip[key]=nil
ns.db.mark[key]=true;fire("QUEST_DETAIL");assert(ns.db.notNow[key] and ns.db.mark[key]);ns.db.mark[key]=nil
ns.db.station=landing.id;fire("GOSSIP_SHOW");assert(ns.db.notNow[key]);ns.db.station=late.id
fire("GOSSIP_SHOW");assert(not ns.db.notNow[key] and visible(late,lateAccept))
-- A legacy title-only greeting followed immediately by the real native detail is enough.
ns.db.notNow[key]=true;fire("QUEST_GREETING");assert(ns.db.notNow[key])
h.OnEvent(nil,"QUEST_DETAIL");assert(not ns.db.notNow[key] and visible(late,lateAccept))
assert(press==before and selected==0,"recovering the hint must not click anything")
-- A confirmed unrelated autoaccept isn't necessarily in the published count yet.
function GetItemCount(id) return id == 2874 and 1 or 0 end
loadLog(39)
offer = 373
fire("QUEST_DETAIL")
offer, offers = q, {{questID=q}}
ns.db.notNow[key] = true
h.OnEvent(nil, "GOSSIP_SHOW")
assert(ns.db.notNow[key] and not E.Applies(lateAccept.s.when))
now = now + 4
h.OnEvent(nil, "GOSSIP_SHOW")
assert(not ns.db.notNow[key] and E.Applies(lateAccept.s.when))
for _, modern in ipairs({false,true}) do
  local count = function() return 0,40 end -- all quest headers collapsed
  if modern then C_QuestLog = {GetNumQuestLogEntries=count} else GetNumQuestLogEntries=count end
  loadLog(0)
  assert(not E.Applies(lateAccept.s.when))
  C_QuestLog, GetNumQuestLogEntries = nil,nil
end
print("3765 initial offer, later manual visit, log capacity, both ports, late-ready handoff and saved decisions passed")
