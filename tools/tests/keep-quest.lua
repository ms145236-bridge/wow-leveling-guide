-- Use shipped route data and the same keep-item selection as the tooltip.
local class, race, raceID
function UnitFactionGroup() return "Horde" end
function UnitClass() return class, class end
function UnitRace() return race, race, raceID end
function UnitLevel() return 12 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local done, log = {}, {}
local ns = {
  db = {skip={}, mark={}, latch={}},
  C = {
    IsOnQuest=function(q) return log[q] end,
    IsTurnedIn=function(q) return done[q] end,
  },
  L=setmetatable({}, {__index=function(_, key) return key end}),
}
for _, f in ipairs({"Data/Route.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. f))("ShengLeveling", ns)
end
local E = ns.E
local function character(c, r, id)
  class, race, raceID = c, r, id
  wipe(done)
  wipe(log)
  E.Build()
end
local function keep(itemID)
  return E.KeepQuest(assert(ns.Route.keep[itemID]))
end

character("PALADIN", "Scourge", 5)
assert(keep(2589) == 94434, "Linen is needed for Redemption, not the Mage quest")
assert(keep(268484) == 95140, "Keep the Moonsilver Blade for Old Fire-Eye")
done[94434] = true
assert(not keep(2589))
log[95140] = true
assert(keep(268484) == 95140)
done[95140] = true
assert(not keep(268484))

character("MAGE", "Scourge", 5)
assert(keep(2589) == 1961)
assert(not keep(268484))
done[1961] = true
assert(not keep(2589))

character("WARRIOR", "Orc", 2)
assert(not keep(2589) and not keep(268484))
-- One item can still be needed for a later quest after its first use.
assert(keep(3575) == 94974)
log[1838] = true
assert(keep(3575) == 1838)
log[1838] = nil
done[94974] = true
assert(keep(3575) == 1838)
done[1838] = true
assert(not keep(3575))
character("PALADIN", "Scourge", 5)
local q, quantity = keep(2589)
assert(q == 94434 and quantity == 10)
q, quantity = keep(268484)
assert(q == 95140 and quantity == 1)
character("WARRIOR", "Orc", 2)
q, quantity = keep(3575)
assert(q == 94974 and quantity == 12)
log[1838] = true
q, quantity = keep(3575)
assert(q == 1838 and quantity == 10)
print("Keep-item hints select the applicable outstanding quest and its quantity")

character("WARRIOR", "Orc", 2)
log[94974], log[1838] = true, true
local _, total, uses = keep(3575)
assert(total == 22 and #uses == 2 and uses[1].q ~= uses[2].q)
done[94974] = true
assert(select(2, keep(3575)) == 10)

character("PALADIN", "Scourge", 5)
local bag, equipped, raw, objectives = {}, nil, false, {}
function UnitLevel() return 26 end
function GetItemCount(id) return bag[id] or 0 end
function GetInventoryItemID(_, slot) if slot == 16 then return equipped end end
function ns.C.IsReady() return raw end
function ns.C.Objectives() return objectives end
local function row(st, q, t)
  for _, step in ipairs(E.byId[st].list) do
    if step.s.q == q and step.s.t == t then return step end
  end
  error(st .. "/" .. q .. "/" .. t)
end
local q = 95036
log[q], raw = true, true
local materials = {267454,6994,267361,272448}
for mask=0,15 do
  for i,id in ipairs(materials) do bag[id] = math.floor(mask / 2^(i-1)) % 2 end
  bag[6995]=1
  for _, st in ipairs({"02-14","05-d5"}) do
    assert(E.Applies(row(st,q,"turnin").s.when) == (mask==15))
  end
  for _, pair in ipairs({{"05-d5",6994},{"05-d6",267361}}) do
    local s = row(pair[1],q,"do").s
    assert(not s.map and not s.x and E.Applies(s.when) == (bag[pair[2]]==0))
  end
end
objectives={{done=false,have=0,need=1}}
assert(not E.Ready(q))
objectives={}
raw=false
assert(not E.Ready(q))
log[94434], raw=true,true
for _,n in ipairs({0,9,10,12}) do bag[2589]=n;assert(E.Ready(94434)==(n>=10)) end
log[95140]=true
assert(not E.Ready(95140))
bag[268484]=1
assert(E.Ready(95140))
bag[268484],equipped=nil,268484
assert(E.Ready(95140))
objectives={{done=false,have=0,need=1}}
assert(not E.Ready(95140))
print("Cloth, both sword slots, four distinct components and the reported quest objectives govern hand-ins")
-- The BFD alternative keeps the existing key and has no outdoor target pin.
wipe(bag); wipe(log); wipe(done)
log[95042]=true
local bfd=E.byId["05-d8"]
for _,step in ipairs(bfd.list) do if step.s.q~=95042 then ns.db.skip[step.key]=true end end
ns.db.dNo={}
function IsInInstance() return true end
function GetInstanceInfo() return nil,nil,nil,nil,nil,nil,nil,48 end
local inside = assert(E.DungeonNext(bfd,false))
assert(inside.kind=="in" and inside.step.key=="d:95042" and not inside.step.s.map)
assert(inside.step.s.componentNpc=="黑澗深淵海巫")
bag[6995]=1
raw,objectives=true,{}
local nx=E.DungeonNext(bfd,true)
assert(not nx or not nx.step or nx.step.s.q ~= 95042)
function IsInInstance() return false end
nx=assert(E.DungeonNext(bfd,true))
assert(nx.step.s.t=="turnin" and nx.step.s.q==95042 and nx.step.s.map==1440)
-- The normal route HUD uses Locate when the instance-only HUD is disabled.
ns.UI = {Get=function() return false end}
ns.C.Position=function() return 1440,11.84,34.47 end
ns.C.Bind=function() end
ns.C.ZoneTexts=function() end
ns.C.LogQuestIDs=function() return {95042} end
ns.C.XPBuff=function() return false end
for _,k in ipairs({"notNow","carry","fpNodes","pin","drop","grindSkip"}) do ns.db[k]={} end
function UnitXP() return 0 end
function UnitXPMax() return 10000 end
function GetTime() return 1 end
local function testHandoff(st, q)
  local step = row(st.id,q,"turnin")
  for _,inside in ipairs({false,true,false}) do
    function IsInInstance() return inside end
    local state=E.Locate(st)
    local found
    for i,w in ipairs(state.steps) do
      if w.key==step.key then found=true;assert((state.na[i] and true or false)==inside) end
    end
    assert(found)
  end
end
ns.db.station=bfd.id
testHandoff(bfd,95042)
testHandoff(E.byId["02-14"],95042)
ns.db.dungeonFrom="02-14"
ns.db.deferredHandoffRun=nil
assert(E.DeferOutdoorHandoff(bfd,48)==95042 and ns.db.deferredHandoffRun==bfd.id)
E.RunDungeon(bfd)
assert(not ns.db.deferredHandoffRun)
log[95042]=nil
assert(not E.DeferOutdoorHandoff(bfd,48) and not ns.db.deferredHandoffRun)
