-- The normal Duskwood delivery needs the issued comb and a ready journal.
local active, ready, turned, callbacks = {}, {}, {[149]=true}, {}
local combCount, shown, arrow = 0
local function noop() end
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human","Human",1 end
function UnitClass() return "Priest","PRIEST" end
function UnitLevel() return 26 end
function UnitXP() return 18772 end
function UnitXPMax() return 36400 end
function GetTime() return 100 end
function GetItemCount(item) return item==1518 and combCount or 0 end
function CreateFrame()
  return {RegisterEvent=noop, SetScript=function(_,event,callback) callbacks[event]=callback end}
end
function wipe(t) for key in pairs(t) do t[key]=nil end end
SlashCmdList, MetroGuideDB = {}, {}
C_QuestLog = {
  IsOnQuest=function(quest) return active[quest] end,
  IsComplete=function(quest) return ready[quest] end,
  IsQuestFlaggedCompleted=function(quest) return turned[quest] end,
  GetQuestObjectives=function(quest)
    if quest==154 and active[quest] then
      return {{text="Ghost Hair Comb",numFulfilled=combCount,numRequired=1,finished=combCount>0}}
    end
  end,
}
local ns={
  db={skip={},mark={},latch={},pin={},dNo={},dDismiss={},carry={},notNow={},fpNodes={},optNote={},skipNote={}},
  UI={Get=noop,Visible=function() return true end,Render=function(view) shown=view.state end,SetHidden=noop,AuberdineChoice=noop},
  N={Set=function(map,x,y) arrow={map,x,y} end,Clear=function() arrow=nil end,Forget=noop},
  T={Update=noop}, I={Update=noop}, P={Update=noop,Clear=noop},
}
assert(loadfile("addon/ShengLeveling/Compat.lua"))("ShengLeveling",ns)
ns.C.Position=function() return 1431,81.99,59.09 end
ns.C.ZoneTexts=function() return "", "暮色森林" end
ns.C.XPBuff=function() return false end
for _,file in ipairs({"Data/RouteA.lua","Engine.lua","Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/"..file))("ShengLeveling",ns)
end
ns.E.Build()
ns.E.built = true
local station=ns.E.byId["02-17"]
local accept, delivery, follow
for _,row in ipairs(station.list) do
  local step=row.s
  if step.q==154 and step.t=="accept" then accept=row
  elseif step.q==154 and step.t=="turnin" then delivery=row
  elseif step.q==157 then follow=row
  elseif step.q~=69 or step.t~="turnin" then ns.db.mark[row.key]=true end
end
assert(accept.key=="a:154" and accept.s.x==81.99 and accept.s.y==59.09)
assert(delivery.key=="t:154" and delivery.s.when.bag.item==1518 and delivery.s.providedVisit==1518)
assert(follow.key=="a:157" and ns.Route.quests[157].ps[1]==154)
ns.db.station=station.id
active[69],ready[69],turned[68]=true,true,true
local function event(name)
  callbacks.OnEvent(nil,name)
  callbacks.OnUpdate(nil,.51)
end
local function expect(key, action, map, x, y)
  local row=assert(shown and shown.cur and shown.steps[shown.cur])
  assert(row.key==key and row.s.t==action, "unexpected current step "..row.key.." "..row.s.t)
  assert(arrow and arrow[1]==map and arrow[2]==x and arrow[3]==y)
end
local function expectSubsequentWork()
  expect("t:69","turnin",1429,43.8,65.8)
end
local function expectEva(action)
  expect("t:154",action,1431,75.79,45.32)
end

event("PLAYER_ENTERING_WORLD")
event("QUEST_LOG_UPDATE")
expect("a:154","accept",1431,81.99,59.09)
combCount=1
event("BAG_UPDATE_DELAYED")
expect("a:154","accept",1431,81.99,59.09)
combCount=0
active[154], ready[154]=true,true
ns.db.pin[station.id]={key=delivery.key,wasDone=true}
event("QUEST_LOG_UPDATE")
expectSubsequentWork()
assert(ns.db.pin[station.id].key==delivery.key)

combCount=1
event("BAG_UPDATE_DELAYED")
expectEva("turnin")
combCount=0
event("BAG_UPDATE_DELAYED")
expectSubsequentWork()

ready[154],combCount=false,1
event("BAG_UPDATE_DELAYED")
expectEva("do")
ready[154]=true
event("QUEST_LOG_UPDATE")
expectEva("turnin")

ns.db.pin[station.id]=nil
ns.E.ToggleSkip(delivery.key)
event("QUEST_LOG_UPDATE")
expectSubsequentWork()
assert(ns.db.skip[follow.key]==delivery.key)
ns.E.ToggleSkip(delivery.key)
ns.db.mark[delivery.key]=true
event("QUEST_LOG_UPDATE")
expectSubsequentWork()
ns.db.mark[delivery.key]=nil

turned[154],active[154],combCount=true,nil,0
event("QUEST_LOG_UPDATE")
expect("a:157","accept",1431,75.79,45.32)
print("Duskwood comb: live bag and journal events preserve the old delivery key and keep 157 gated")
