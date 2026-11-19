-- Exercise the same saved work step for both city investigations.
local faction = assert(arg[1])
local alliance = faction == "Alliance"
local q, station = alliance and 1920 or 1960, alliance and "02-14" or "02-9"
local bag, uses, ready, objectives, log = {}, 10, false, {}, true
function UnitFactionGroup() return faction end
function UnitRace() return alliance and "Human" or "Troll", alliance and "Human" or "Troll", alliance and 1 or 8 end
function UnitClass() return "Mage", "MAGE" end
function UnitLevel() return 16 end
function GetItemCount(id, _, charges)
  if charges and id == 7247 then return uses end
  return bag[id] or 0
end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {db={skip={}, mark={}, latch={}}, C={
  IsOnQuest=function(id) return log and id == q end, IsTurnedIn=function() return false end,
  IsReady=function() return ready end, Objectives=function() return objectives end,
}, Macro={default={item="item",target="target"}}, L=setmetatable({}, {__index=function(_,k) return k end})}
for _,f in ipairs({alliance and "Data/RouteA.lua" or "Data/Route.lua", "Engine.lua", "Item.lua", "Target.lua"}) do
  assert(loadfile("addon/ShengLeveling/"..f))("",ns)
end
local E=ns.E
E.Build()
local work, hand
for _,row in ipairs(assert(E.byId[station]).list) do
  if row.s.t=="do" and row.s.q==q then work=row end
  if row.s.t=="turnin" and row.s.q==q then hand=row end
end
assert(work.key=="d:"..q and hand.key=="t:"..q)
assert(work.s.x==(alliance and 51.30 or 53.29))
local state={cur=1,steps={work}}
for _,filled in ipairs({0,2,3,4}) do for scroll=0,1 do for chest=0,1 do
  bag[7292],bag[7308],bag[7247]=filled,scroll,chest
  for _,num in ipairs({0,1,10}) do for _,flag in ipairs({false,true}) do
    uses,ready=num,flag
    local enough=filled>=3 and chest==1 and scroll==1
    assert(E.Applies(hand.s.when)==(enough and ready) and E.QuickDone(work)==(enough and ready))
    local capture=not enough and chest==1 and scroll==1 and num>0
    assert((E.RiftPhase()=="capture")==capture)
    assert(table.concat(ns.I.Items(state),",")==(capture and "7308,7247" or ""))
    assert(#ns.T.Targets(state)==(capture and 1 or 0))
  end end
end end end
bag[7292],bag[7308],bag[7247],uses,ready=3,1,1,0,true
objectives={{have=2,need=3,done=false}}
assert(not E.QuickDone(work) and not E.Applies(hand.s.when))
objectives={};log=false
assert(not E.Applies(hand.s.when))
print(faction.." mage capture tools, charges, actual filled coffers, native journal and saved keys pass")
