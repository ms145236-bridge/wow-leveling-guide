-- Same tailor on A14 and the later A19 mage visit; Loch Modan is optional.
local bag, log, turned, objectives = {}, {}, {}, {}
local ready, riding, position = false, false, {1453,51.84,83.51}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Mage","MAGE" end
function UnitRace() return "Human","Human",1 end
function UnitLevel() return 27 end
function UnitOnTaxi() return riding end
function GetItemCount(id) return bag[id] or 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {db={},C={
  IsOnQuest=function(q) return log[q] end, IsTurnedIn=function(q) return turned[q] end,
  IsReady=function() return ready end, Objectives=function() return objectives end,
  Position=function() return unpack(position) end,
}}
for _, f in ipairs({"Data/RouteA.lua","Engine.lua"}) do assert(loadfile("addon/ShengLeveling/"..f))("",ns) end
local E=ns.E
E.Build()
local function row(st,key)
  for _,r in ipairs(st.list) do if r.key==key then return r.s end end
  error(key)
end
local first,late=E.byId["02-14"],E.byId["02-19"]
local hand,visit=row(first,"t:1921"),row(late,"t:1921")
assert(hand.desc:find("35.9,18.2",1,true) and not hand.desc:find("拍賣",1,true))
assert(not row(first,"a:1921").when.nearPoint and visit.when.nearPoint)
assert(row(first,"a:1941").when.turnedQuest==1921)
log[1921]=true
bag[7293]=10 -- Horde mana gems cannot replace the six charged rift gems.
for _,cloth in ipairs({0,9,10,12}) do for _,gems in ipairs({0,5,6,7}) do
  bag[2589],bag[7249]=cloth,gems
  for _,flag in ipairs({false,true}) do
    ready=flag
    for _,explicitlyIncomplete in ipairs({false,true}) do
      objectives=explicitlyIncomplete and {{done=false,have=5,need=6}} or {}
      local ok=cloth>=10 and gems>=6 and ready and not explicitlyIncomplete
      assert(E.Applies(hand.when)==ok and E.Applies(visit.when)==ok)
    end
  end
end end
ready=true;objectives={};bag[2589],bag[7249]=10,6
for _,where in ipairs({{1432,35.9,18.2},{1453,40,90},{}}) do
  position=where
  assert(not E.Applies(visit.when))
end
position={1453,51.84,83.51};riding=true
assert(not E.Applies(visit.when))
riding=false;log[1921]=nil
assert(not E.Applies(visit.when) and not E.Applies(row(late,"a:1941").when))
turned[1921]=true
assert(E.Applies(row(late,"a:1941").when))
assert(not E.Applies(row(late,"t:1941").when))
log[1941]=true
assert(E.Applies(row(late,"t:1941").when))
print("Alliance mage robe requires both materials, journal readiness and the local tailor on the later visit")
