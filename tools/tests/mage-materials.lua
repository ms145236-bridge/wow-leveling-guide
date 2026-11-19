-- A single saved do-row covers both required items; each has its own count and source.
local race, mask, class = "Scourge", 5, "MAGE"
local ready, bag, objectives, on = false, {}, {}, {}
function UnitFactionGroup() return "Horde" end
function UnitRace() return race,race,mask end
function UnitClass() return class,class end
function UnitLevel() return 15 end
function GetItemCount(i) return bag[i] or 0 end
function wipe(t) for k in pairs(t) do t[k]=nil end end
local ns = {
  Macro={default={target="target"}},
  db={skip={},mark={},latch={}},
  C={IsReady=function() return ready end, Objectives=function() return objectives end,
     IsTurnedIn=function() return false end, IsOnQuest=function(q) return on[q] end},
  L=setmetatable({}, {__index=function(_,k) return k end}),
}
for _,f in ipairs({"Data/Route.lua","Engine.lua","Target.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. f))("ShengLeveling",ns)
end
ns.E.Build()
local E = ns.E
local s, t
for _,v in ipairs(E.byId["02-9"].list) do
  if v.s.q==1961 and v.s.t=="do" then s=v end
  if v.s.q==1961 and v.s.t=="turnin" then t=v end
end
assert(s.key=="d:1961" and t.key=="t:1961")
assert(s.s.map==1421 and s.s.x==56.69 and #s.s.more==1 and s.s.more[1][2]==59.65)
on[1961]=true
for _,cloth in ipairs({0,9,10,11}) do for _,gems in ipairs({0,5,6,7}) do
  for _,flag in ipairs({false,true}) do
    ready,bag[2589],bag[7293]=flag,cloth,gems
    local enough=cloth>=10 and gems>=6
    assert(E.QuickDone(s)==(enough and ready))
    assert(E.Applies(t.s.when)==(enough and ready))
    local targets=ns.T.Targets({cur=1,steps={s}})
    if gems>=6 then assert(#targets==0) else
      table.sort(targets)
      assert(#targets==2 and table.concat(targets,","):find("達拉然學徒",1,true) and table.concat(targets,","):find("達拉然保衛者",1,true))
    end
  end
end end
objectives={{done=false,have=5,need=6}}
assert(not E.Applies(t.s.when))
on[1961]=nil
assert(not E.Applies(t.s.when))
print("Mage material quantities, source pins, journal readiness, work targets and saved keys pass")
