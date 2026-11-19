-- The Horde hand-in keeps the original Torta point and travel key.
local active, turned, ready = {}, {}, {}
local optional, level = false, 42
function UnitFactionGroup() return "Horde" end
function UnitClass() return "Mage", "MAGE" end
function UnitRace() return "Undead","Scourge",5 end
function UnitLevel() return level end
function UnitXPMax() return 95000 end
function UnitXP() return 0 end
function GetItemCount() return 0 end
function wipe(t) for k in pairs(t) do t[k]=nil end end
local L=setmetatable({}, {__index=function(_,key) return key end})
local ns={C={},db={skip={},mark={},latch={},notNow={},pin={},carry={},dNo={},fpNodes={}}, UI={Get=function(k) return k=="optional" and optional or k=="dPre" end},L=L}
local C=ns.C
C.IsOnQuest=function(q)return active[q] end
C.IsReady=function(q)return ready[q] end
C.IsTurnedIn=function(q)return turned[q] end
C.XPBuff=function()return false end
C.Position=function()return nil end
C.LogQuestIDs=function()return {} end
for _,file in ipairs({"Data/Route.lua","Engine.lua"}) do assert(loadfile("addon/ShengLeveling/"..file))("",ns) end
local E=ns.E
E.Build()
level=47
local station=E.byId["04-33"]
C.Bind=function() end
C.GreenRange=function() return 8 end
C.ZoneTexts=function() end
local physicalMap=1446
C.Position=function() return physicalMap,66.58,25.67 end
local failed, objectives
C.IsFailed=function(q) return q==1560 and failed end
C.Objectives=function(q) return q==1560 and objectives end
local travelKey="04-33#travel:回加基森交任務。帶著圖加走回去，不用爐石；順路再取好味道和昆蟲研究。"
local travel
for _, row in ipairs(station.list) do
  if row.s.t=="turnin" and row.s.q==1560 then break end
  if row.s.q and row.s.q~=1560 then turned[row.s.q]=true end
  if row.key==travelKey then travel=row end
  if not row.s.q then ns.db.mark[row.key]=true end
end
assert(travel and travel.s.text:find("回加基森交任務",1,true) and not travel.s.text:find("圖加",1,true))
local function rows()
 local view=E.Locate(station)
 local found={}
 for i,w in ipairs(view.steps) do
   if w.s.q==1560 then
     found[w.s.t]={na=view.na[i],done=view.done[i],current=view.cur==i,step=w}
   end
 end
 assert(found.accept.step.key=="a:1560" and found.turnin.step.key=="t:1560")
 assert(found.accept.step.s.opt and found["do"].step.s.opt and found.turnin.step.s.opt)
 assert(not found["do"].step.s.x and not found["do"].step.s.more)
 assert(found.turnin.step.s.map==1446 and found.turnin.step.s.x==66.58 and found.turnin.step.s.y==25.67)
 return found
end
for _,enable in ipairs({false,true}) do
 optional=enable
 for _,kind in ipairs({"unheld","unfinished","empty","stale","false-ready","failed","failed-ready","ready","turned"}) do
  active[1560]=kind~="unheld" and kind~="turned"
  ready[1560]=kind=="ready" or kind=="failed-ready" or kind=="false-ready"
  turned[1560]=kind=="turned"
  failed=kind=="failed" or kind=="failed-ready"
  objectives=kind=="empty" and {} or kind=="stale" and {{done=true,have=1,need=1}} or kind=="false-ready" and {{done=false,have=0,need=1}} or nil
  ns.db.pin[station.id]=nil
  local r=rows()
  if kind=="unheld" then
    assert(r.accept.na==not enable and r["do"].na and r.turnin.na)
  elseif kind=="failed" or kind=="failed-ready" then
    assert(r.accept.na and r["do"].na and r.turnin.na and not r.turnin.current)
    ns.db.pin[station.id]={key="t:1560",wasDone=false}
    assert(not rows().turnin.current, "old turn-in pin cannot force failed escort")
  elseif kind=="false-ready" then
    assert(r.turnin.na and not r.turnin.current and not r["do"].done)
    ns.db.pin[station.id]={key="t:1560",wasDone=true}
    assert(rows()["do"].current, "an incomplete objective keeps the escort active")
  elseif kind=="ready" then
    assert(r["do"].done and not r.turnin.na and r.turnin.current)
    ns.db.pin[station.id]={key="t:1560",wasDone=true}
    physicalMap=1454
    assert(not rows().turnin.current and ns.db.pin[station.id].key=="t:1560")
    physicalMap=1446
    assert(rows().turnin.current, "returning to Tanaris restores the legitimate hand-in")
  elseif kind=="turned" then
    assert(r["do"].na and r.turnin.na and r.turnin.done)
  else
    assert(not r["do"].na and not r["do"].done and r["do"].current and r.turnin.na)
    ns.db.pin[station.id]={key="t:1560",wasDone=true}
    assert(not rows().turnin.current, "old turn-in pin cannot force unfinished escort")
  end
 end
end
optional,failed=true,false
active[1560],ready[1560],turned[1560]=nil,nil,nil
ns.db.pin[station.id]=nil
for _,key in ipairs({"a:1560","d:1560","t:1560"}) do ns.db.skip[key]=true end
local r=rows()
assert(r.accept.na and r["do"].na and r.turnin.na)
print("Explicit skip preserves the usual Gadgetzan return")
