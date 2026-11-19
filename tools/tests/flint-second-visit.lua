-- Check the live A59 station row with the same journal, inventory and position APIs used by the HUD.
local level, map, x, y, optional = 59, 1422, 43.42, 84.83, false
local active, ready, turned, log = {}, {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return level end
function UnitXP() return 0 end
function UnitXPMax() return 209800 end
function wipe(t) for key in pairs(t) do t[key]=nil end end
local ns = {
  C={IsOnQuest=function(q) return active[q] end, IsReady=function(q) return ready[q] end,
     IsTurnedIn=function(q) return turned[q] end, LogQuestIDs=function() return log end,
     Position=function() return map,x,y end, XPBuff=function() return false end,
     ZoneTexts=function() end, Bind=function() end, Objectives=function() end},
  UI={Get=function(key) return key=="optional" and optional end},
  L=setmetatable({}, {__index=function(_,k) return k end}),
  db={skip={},mark={},latch={},notNow={},pin={},fpNodes={},carry={},dNo={}},
}
for _,file in ipairs({"Data/RouteA.lua","Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/"..file))("ShengLeveling",ns)
end
local E=ns.E
E.Build()
local q=6184
local function row(st,qid,verb)
  for i,w in ipairs(st.list) do if w.s.q==qid and w.s.t==verb then return i,w end end
end
local city,early,late=E.byId["04-54"],E.byId["04-55"],E.byId["04-59"]
-- 6183 moved to the A59 Stormwind visit (after this Chillwind visit), so 6184 has no route accept.
assert(not row(city,q,"accept"))
local _,original = row(early,q,"turnin")
local i,handoff = row(late,q,"turnin")
assert(original.key=="t:6184" and handoff.key==original.key)
assert(late.list[i-1].s.q==5223 and late.list[i+1].s.q==6185)
assert(row(late,6389,"turnin") > i and not row(late,q,"accept"))
local emma = row(late,5048,"turnin")
assert(row(late,6182,"accept") > emma and row(late,6183,"accept") > row(late,6182,"accept") and row(late,6182,"accept") > i)
assert(not original.s.when or not original.s.when.nearPoint)
-- Isolate the moment just after Nathaniel's turn-in; all other rows keep their old keys.
ns.db.station=late.id
for _,w in ipairs(late.list) do if w~=handoff then ns.db.skip[w.key]=true end end
local function shown()
  local state=E.Locate(late)
  return state.cur and state.steps[state.cur].key==handoff.key or false
end
for _,lv in ipairs({59,60}) do
  level=lv
  for _,on in ipairs({false,true}) do
    optional=on
    for _,held in ipairs({39,40}) do
      wipe(log)
      for k=1,held do log[k]=100000+k end
      for _,inLog in ipairs({false,true}) do
        active[q]=inLog; log[1]=inLog and q or 100001
        for _,complete in ipairs({false,true}) do
          ready[q]=complete
          for _,p in ipairs({{1422,43.42,84.83,true},{1422,43.61,84.51,true},{1422,43.00,84.50,true},{1422,45,84,false},
                             {1453,80.21,38.35,false},{1422,nil,nil,false},{nil,nil,nil,false}}) do
            map,x,y=p[1],p[2],p[3]
            assert(shown()==(p[4] and inLog and complete), "unexpected second-visit hand-in")
          end
        end
      end
    end
  end
end
map,x,y=1422,43.61,84.51; optional=false
active[q],ready[q]=true,true
ns.db.skip["a:6184"]=true;assert(shown(),"a player who later picked up the quest can deliver it")
ns.db.skip[handoff.key]=true;assert(not shown());ns.db.skip[handoff.key]=nil
ns.db.mark[handoff.key]=true;assert(not shown());ns.db.mark[handoff.key]=nil
-- An earlier carried copy cannot restore the distant A55 waypoint after jumping.
ns.db.carry[late.id] = {q}
map,x,y = 1453,78.31,70.74
assert(not shown())
UnitOnTaxi = function() return true end
map,x,y = 1422,43.61,84.51
assert(not shown())
UnitOnTaxi = nil
assert(shown())
turned[q]=true; active[q]=nil;assert(not shown())
print("Flint: second Chillwind visit requires the live quest, turn-in readiness and proximity; prior decisions and adjacent routes passed")
