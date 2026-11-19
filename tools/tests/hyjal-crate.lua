-- A58 only points to the crate hand-in while the live shipment is still deliverable.
local active, ready, failed, turned, callbacks = {}, {}, {}, {[92008]=true}, {}
local count, shown, arrow = 0
local crateObjective
local map, x, y = 2482, 58.7, 74.5
local function noop() end
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human","Human",1 end
function UnitClass() return "Priest","PRIEST" end
function UnitLevel() return 56 end
function UnitXP() return 90923 end
function UnitXPMax() return 180800 end
function GetTime() return 100 end
function GetItemCount(item) return item==250725 and count or 0 end
function CreateFrame()
  return {RegisterEvent=noop, SetScript=function(_,event,callback) callbacks[event]=callback end}
end
function wipe(t) for key in pairs(t) do t[key]=nil end end
SlashCmdList, MetroGuideDB = {}, {}
C_QuestLog = {
  IsOnQuest=function(quest) return active[quest] end,
  IsComplete=function(quest) return ready[quest] end,
  IsFailed=function(quest) return failed[quest] end,
  IsQuestFlaggedCompleted=function(quest) return turned[quest] end,
  GetQuestObjectives=function(quest)
    if quest==92009 and crateObjective~=nil then
      return {{text="Shipment delivered",numFulfilled=crateObjective and 1 or 0,numRequired=1,finished=crateObjective}}
    end
  end,
}
local ns={
  db={skip={},mark={},latch={},pin={},dNo={},dDismiss={},carry={},notNow={},fpNodes={},optNote={},skipNote={}},
  UI={Get=noop,Visible=function() return true end,Render=function(view) shown=view.state end,SetHidden=noop,AuberdineChoice=noop},
  N={Set=function(m,px,py) arrow={m,px,py} end,Clear=function() arrow=nil end,Forget=noop},
  T={Update=noop}, I={Update=noop}, P={Update=noop,Clear=noop},
}
assert(loadfile("addon/ShengLeveling/Compat.lua"))("ShengLeveling",ns)
ns.C.Position=function() return map,x,y end
ns.C.ZoneTexts=function() return "", "海加爾山" end
ns.C.XPBuff=function() return false end
for _,file in ipairs({"Data/RouteA.lua","Engine.lua","Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/"..file))("ShengLeveling",ns)
end
ns.E.Build()
ns.E.built = true
local station=ns.E.byId["04-58"]
local delivery
for _,row in ipairs(station.list) do
  local q=row.s.q
  if q==92009 and row.s.t=="turnin" then delivery=row
  elseif q==92009 then assert(row.key=="d:92009")
  elseif q~=92594 and q~=92011 and q~=93773 then ns.db.mark[row.key]=true end
end
assert(delivery.key=="t:92009" and delivery.s.when.bag.item==250725)
ns.db.station=station.id
active[92594],ready[92594],active[93773],ready[93773]=true,true,true,true
local function event(name)
  callbacks.OnEvent(nil,name)
  callbacks.OnUpdate(nil,.51)
end
local function expect(key, m, px, py)
  local row=assert(shown and shown.cur and shown.steps[shown.cur])
  assert(row.key==key,"expected "..key..", got "..row.key)
  assert(arrow and arrow[1]==m and arrow[2]==px and arrow[3]==py)
end
local function expectWorkshop(key)
  expect(key,2482,60.1,61.2)
end

event("PLAYER_ENTERING_WORLD")
event("QUEST_LOG_UPDATE")
expectWorkshop("t:92594")
-- A loose crate and a stale native-ready bit cannot create a hand-in.
count,ready[92009]=1,true
event("BAG_UPDATE_DELAYED")
expectWorkshop("t:92594")
count,active[92009]=0,true
ns.db.pin[station.id]={key=delivery.key,wasDone=true}
event("QUEST_LOG_UPDATE")
expectWorkshop("t:92594")
assert(ns.db.pin[station.id].key==delivery.key)
-- An intact crate keeps the workshop visit available before the native ready bit.
count,ready[92009],crateObjective=1,false,false
event("BAG_UPDATE_DELAYED")
expectWorkshop("d:92009")
assert(ns.db.pin[station.id].key==delivery.key)
map,x,y=2482,60.1,61.2
ready[92009]=true
event("QUEST_LOG_UPDATE")
expectWorkshop("d:92009")
crateObjective=true
event("QUEST_LOG_UPDATE")
expectWorkshop("t:92009")
failed[92009]=true
event("QUEST_LOG_UPDATE")
expectWorkshop("t:92594")
failed[92009]=false
event("QUEST_LOG_UPDATE")
expectWorkshop("t:92009")
count=0
event("BAG_UPDATE_DELAYED")
expectWorkshop("t:92594")
active[92594],turned[92594]=nil,true
event("QUEST_LOG_UPDATE")
expect("t:93773",2482,73.3,81.9)

ns.db.pin[station.id]=nil
count=1
ns.E.ToggleSkip(delivery.key)
event("QUEST_LOG_UPDATE")
expect("t:93773",2482,73.3,81.9)
ns.E.ToggleSkip(delivery.key)
event("QUEST_LOG_UPDATE")
expectWorkshop("t:92009")
active[92009],turned[92009],count=nil,true,0
event("QUEST_LOG_UPDATE")
expectWorkshop("a:92011")
print("Hyjal crate: intact delivery, empty and failed states, saved pin, workshop coexistence and real hand-off passed")
