-- Keep objective confirmation, the issued letter and the level gate separate from travel.
local level, active, handed, nativeReady, objectives, items = 26, {}, {}, {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Mage", "MAGE" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return level end
function UnitXP() return 0 end
function UnitXPMax() return 50400 end
function GetItemCount(id) return items[id] or 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {
  C={IsOnQuest=function(q) return active[q] end, IsReady=function(q) return nativeReady[q] end,
     IsTurnedIn=function(q) return handed[q] end, LogQuestIDs=function() return {} end,
     Position=function() return 1417,48.80,88.00 end, XPBuff=function() return false end,
     ZoneTexts=function() end, Bind=function() end, Objectives=function(q) return objectives[q] end},
  UI={Get=function() return false end}, L=setmetatable({},{__index=function(_,k) return k end}),
  db={skip={},mark={},latch={},notNow={},pin={},fpNodes={},carry={},dNo={}},
}
for _,file in ipairs({"Data/RouteA.lua","Engine.lua"}) do assert(loadfile("addon/ShengLeveling/"..file))("",ns) end
local E = ns.E
E.Build()
local station = E.byId["03-23"]
ns.db.station = station.id
local function only(...)
  wipe(ns.db.skip)
  local allow = {}
  for _,key in ipairs({...}) do allow[key] = true end
  for _,row in ipairs(station.list) do ns.db.skip[row.key] = not allow[row.key] end
end
local function current()
  local state = E.Locate(station)
  return state.cur and state.steps[state.cur].key
end
for q = 631,634 do
  local key = "a:"..q
  only(key)
  local min = q == 634 and 28 or 26
  assert(ns.Route.quests[q].min == min)
  wipe(handed)
  if q > 631 then handed[q-1] = true end
  for lv=25,28 do
    level=lv
    assert((current()==key) == (lv>=min), key.." at level "..lv)
  end
  if q > 631 then handed[q-1]=nil; assert(current()~=key) end
end
level,active[633],handed[632] = 30,true,true
only("d:633","a:637","t:633")
for _,ready in ipairs({false,true}) do
  nativeReady[633]=ready
  for _,rows in ipairs({false, {}, {{done=false,have=0,need=1}}, {{done=true,have=1,need=1}}}) do
    objectives[633]=rows or nil
    local confirmed = ready and not (rows and rows[1] and not rows[1].done)
    assert(current() == (confirmed and "a:637" or "d:633"))
    only("t:633"); assert((current()=="t:633") == confirmed); only("d:633","a:637","t:633")
  end
end
only("t:637")
for _,item in ipairs({0,4432,4433}) do
  wipe(items); items[item]=1
  for _,known in ipairs({false,true}) do for _,ready in ipairs({false,true}) do
    active[637],nativeReady[637] = known,ready
    assert((current()=="t:637") == (known and ready))
  end end
end
print("Thandol Span: level and prerequisite gates, actual explosives interaction and native letter hand-in passed")
