-- Physical quest items, two independent robe chains, and the existing Redridge/Duskwood circuit.
local bag, active, turned, obj = {}, {}, {}, {}
local raw, riding, level, race = false, false, 26, "Human"
local p = {1433,73.77,47.61}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Mage","MAGE" end
function UnitRace() return race,race,({Human=1,Gnome=7,NightElf=4})[race] end
function UnitLevel() return level end
function UnitOnTaxi() return riding end
function GetItemCount(id) return bag[id] or 0 end
function wipe(t) for k in pairs(t) do t[k]=nil end end
local ns={db={}, C={Position=function() return unpack(p) end,
  IsOnQuest=function(q) return active[q] end,IsTurnedIn=function(q) return turned[q] end,
  IsReady=function() return raw end,Objectives=function() return obj end}}
for _,file in ipairs({"Data/RouteA.lua","Engine.lua"}) do assert(loadfile("addon/ShengLeveling/"..file))("",ns) end
local E=ns.E
E.Build()
local function row(st,key)
  for i,w in ipairs(E.byId[st].list) do if w.key==key then return w.s,i end end
  error("missing "..key)
end
local first,late="02-19","03-22"
local book,bi=row(first,"d:1938")
local _,anchor=row(first,"d:91");assert(bi==anchor+1)
local _,si=row(late,"d:1940");local _,spiders=row(late,"d:101");assert(si==spiders+1)
local _,firstRobe=row(first,"t:1941");local _,secondRobe=row(first,"t:1940");assert(firstRobe<secondRobe)
local localRobe,earlyRow=row(late,"t:1921")
local _,silkRow=row(late,"t:1940")
assert(localRobe.when.nearPoint and earlyRow<silkRow)
assert(book.map==1433 and book.x==73.77 and book.y==47.61)
active[1938]=true
assert(E.Applies(book.when))
for _,held in ipairs({0,1}) do for _,r in ipairs({false,true}) do
  raw=r;bag[7266]=held;p={1453,48.71,87.62}
  assert(E.Applies(row(first,"t:1938").when)==(held==1 and r))
end end
active[1938]=nil;turned[1938]=true;active[1940]=true
for _,sid in ipairs({first,late}) do
  local work,hand=row(sid,"d:1940"),row(sid,"t:1940")
  p={1431,30.11,51.19}
  assert(E.Applies(work.when) and not E.Applies(hand.when))
  for _,bad in ipairs({{}, {1431}, {1453,48.71,87.62}}) do p=bad;assert(not E.Applies(work.when)) end
  p={1431,30.11,51.19};riding=true;assert(not E.Applies(work.when));riding=false
  for _,count in ipairs({0,7,8,9}) do for _,r in ipairs({false,true}) do for _,stale in ipairs({false,true}) do
    p={1453,51.84,83.51};bag[3182]=8;bag[7267]=count;raw=r;obj=stale and {{done=false,have=7,need=8}} or {}
    assert(E.Applies(hand.when)==(count>=8 and r and not stale))
    assert(not E.Applies(row(sid,"a:1942").when))
  end end end
end
turned[1940]=true;assert(E.Applies(row(first,"a:1942").when));assert(not E.Applies(row(first,"t:1942").when))
active[1942]=true;assert(E.Applies(row(late,"t:1942").when))
print("Alliance mage tower book, real spider silk, local collection and reward chains verified")
