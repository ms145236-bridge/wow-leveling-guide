-- Walk each hunt through a missed loot, a delayed journal flag, and the real handoff.
local log,bag,done,raw,obj={},{},{},false,{}
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human","Human",1 end
function UnitClass() return "Priest","PRIEST" end
function UnitLevel() return 27 end
function UnitXP() return 0 end
function UnitXPMax() return 30000 end
function GetItemCount(id) return bag[id] or 0 end
function wipe(t) for k in pairs(t) do t[k]=nil end end
local db={skip={},drop={},fpNodes={},notNow={},pin={},mark={},latch={},carry={},dNo={}}
local ns={db=db, UI={Get=function() return false end}, C={Position=function() return 1433,24.9,44.45 end,
  ZoneTexts=function() return "","","" end, XPBuff=function() return false end, Bind=function() return "" end, IsOnQuest=function(q) return log[q] end, IsTurnedIn=function(q) return done[q] end,
  IsReady=function() return raw end, Objectives=function()return obj end, LogQuestIDs=function()return {} end}}
ns.Macro={default={target="target"}}
ns.L=setmetatable({},{__index=function(_,k)return k end})
for _,f in ipairs({"Data/RouteA.lua","Engine.lua","Target.lua"}) do assert(loadfile("addon/ShengLeveling/"..f))("",ns) end
local E=ns.E; E.Build();local st=E.byId["02-19"]
for _,case in ipairs({{180,3632,75.10},{126,3614,22.60},{34,3631,10.60}}) do
  local q,item,x=unpack(case)
  wipe(log);wipe(done);wipe(bag);wipe(db.mark);done[124]=true;log[q]=true
  for _,row in ipairs(st.list) do if row.s.q~=q then db.mark[row.key]=true end end
  for _,owned in ipairs({0,1}) do for _,r in ipairs({false,true}) do for _,incomplete in ipairs({false,true}) do
    raw=r;obj=incomplete and {{have=0,need=1,done=false}} or {};bag[item]=owned
    local state=E.Locate(st)
    local current=assert(state.steps[state.cur])
    local ready=owned==1 and r and not incomplete
    assert(current.key==(ready and "t:" or "d:")..q, current.key)
    if owned==0 then assert(current.s.x==x and E.KillXP(q,27)>0)
    elseif not ready then assert(not current.s.x and current.s.farmDone and E.KillXP(q,27)==0) end
    assert(E.Ready(q)==ready)
    if owned==0 then
      obj={{done=true,have=1,need=1}}
      assert(ns.T.Targets(state)[1]==ns.Route.quests[q].tgo[1][1])
    elseif not ready then assert(#ns.T.Targets(state)==0) end
  end end end
end
-- Pendants can be gathered from multiple gnolls. Blackrock Champions have a separate kill counter.
local function current(q)
  local state=E.Locate(st)
  local row=assert(state.steps[state.cur])
  assert(row.s.q==q, row.key)
  return row,state
end
for _,q in ipairs({91,128}) do
  wipe(log);wipe(done);wipe(bag);wipe(db.mark);log[q]=true
  for _,row in ipairs(st.list) do if row.s.q~=q then db.mark[row.key]=true end end
  bag[3632]=1
  local count=q==91 and 10 or 15
  for _,held in ipairs({0,count-1,count}) do for _,r in ipairs({true,false}) do
    raw=r;bag[1075]=q==91 and held or 10
    obj={{have=held,need=count,done=held==count}}
    local row,state=current(q)
    if held<count then
      assert(row.key=="d:"..q and row.s.x and #ns.T.Targets(state)>0 and E.KillXP(q,27)>0)
      if q==91 then assert(row.s.more[2][2]==75.09) end
    elseif not raw then
      assert(row.key=="d:"..q and not row.s.x and #ns.T.Targets(state)==0)
    else assert(row.key=="t:"..q and E.Ready(q)) end
  end end
  obj={};raw=false;bag[1075]=0
  assert(current(q).key=="d:"..q)
end
print("Redridge trophies, pendant quantities and independent champion kills verified")
