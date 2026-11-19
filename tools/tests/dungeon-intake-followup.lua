-- Optional Nethergarde chain and the shared Sunken Temple quest.
local faction = arg[1] or "Alliance"
local alliance = faction == "Alliance"
local level, now, offered, pressed = 53, 100, 0, 0
local map, x, y, taxi, inParty, instance
local log, turned, active, ready, bags, handlers = {}, {}, {}, {}, {}, {}
local settings = {dPre=true, optional=true, auto=true, detourOn=true, detourDist=8}
function UnitFactionGroup() return faction end
function UnitRace()
  if alliance then return "Human", "Human", 1 end
  return "Undead", "Scourge", 5
end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return level end
function UnitOnTaxi() return taxi end
function UnitXP() return 0 end
function UnitXPMax() return 180000 end
function GetItemCount(id) return bags[id] or 0 end
function GetTime() return now end
function GetQuestID() return offered end
function IsShiftKeyDown() return false end
function AcceptQuest() pressed = pressed + 1 end
function IsInInstance() return inParty, inParty and "party" or "none" end
function GetInstanceInfo() return nil, nil, nil, nil, nil, nil, nil, instance end
function CreateFrame()
  return {RegisterEvent=function() end, SetScript=function(_, key, f) handlers[key]=f end}
end
function wipe(value) for key in pairs(value) do value[key]=nil end end
SlashCmdList = {}

local ns = {
  C = {
    IsOnQuest=function(q) return active[q] end, IsReady=function(q) return ready[q] end,
    IsTurnedIn=function(q) return turned[q] end, Objectives=function() return {} end,
    ZoneTexts=function() end, Bind=function() end, XPBuff=function() return false end,
    GreenRange=function() return 8 end, LogQuestIDs=function() return log end,
    Position=function() return map, x, y end,
  },
  db={skip={},mark={},latch={},notNow={},pin={},carry={},dNo={},fpNodes={}},
  UI={Get=function(k) return settings[k] end},
  L=setmetatable({}, {__index=function(_,k) return k end}),
  msg=function() end, try=function(_,f,...) return f(...) end,
}
local route = alliance and "Data/RouteA.lua" or "Data/Route.lua"
for _, file in ipairs({route, "Engine.lua", "Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local temple = E.byId[alliance and "05-d14" or "05-d23"]
local function questStep(rows, action, q)
  for i, row in ipairs(rows or {}) do
    if row.s.q == q and (not action or row.s.t == action) then return row.s, i end
  end
end
local function instanceStep(d, q)
  local state = E.InstanceState(d)
  return state and questStep(state.steps,nil,q)
end
local function autoAccept(q)
  offered = q
  local before = pressed
  handlers.OnEvent(nil, "QUEST_DETAIL")
  return pressed > before
end
local function nextQuest(d, inside)
  local nextRow = E.DungeonNext(d, inside)
  return nextRow and nextRow.step and nextRow.step.s
end
local function detour()
  E.Detour({steps={}})
  now = now + 4
  return E.Detour({steps={}})
end
local function doneOthers(d, q)
  for _, row in ipairs(d.list) do
    if row.s.q and row.s.q ~= q then turned[row.s.q] = true end
  end
end

if alliance then
  local nethergarde, zul = E.byId["04-45"], E.byId["05-d10"]
  local offer, i = questStep(nethergarde.list, "accept", 2991)
  local previous, j = questStep(nethergarde.list, "turnin", 2990)
  assert(i == j + 1 and offer.npc == previous.npc and offer.x == previous.x)
  assert(not questStep(zul.list, "accept", 2991))
  map, x, y = 1419, 66.90, 19.47
  assert(not E.Applies(offer.when) and not autoAccept(2991), "no real prior handoff")
  ns.db.mark["t:2990"] = true
  assert(not E.Applies(offer.when) and not autoAccept(2991), "manual check is not a handoff")
  turned[2990] = true
  assert(E.Applies(offer.when))
  for _, key in ipairs({"dPre", "optional"}) do
    settings[key] = false
    assert(not E.Applies(offer.when) and not autoAccept(2991))
    settings[key] = true
  end
  ns.db.dNo[zul.id] = true
  assert(not autoAccept(2991))
  ns.db.dNo[zul.id] = nil
  for _, here in ipairs({{1446,66.90,19.47}, {1419,60,20}, {1419}, {}}) do
    map, x, y = unpack(here)
    assert(not E.Applies(offer.when) and not autoAccept(2991))
  end
  map, x, y, taxi = 1419, 66.90, 19.47, true
  assert(not autoAccept(2991), "flyover is not a visit")
  taxi = false
  level = 39
  assert(not E.Applies(offer.when))
  level = 53
  for index = 1, 40 do log[index] = 100000 + index end
  assert(not autoAccept(2991), "full journal")
  log = {}
  assert(autoAccept(2991), "native offer at the original giver")

  doneOthers(zul, 2991)
  level = 59
  local exit = questStep(zul.list, "turnin", 2991)
  active[2991], ready[2991] = true, false
  map, x, y = 1446, 51.41, 28.75
  assert(instanceStep(zul,2991).t == "do" and not E.Applies(exit.when))
  ready[2991], bags[9471] = true, 1
  assert(not E.Applies(exit.when) and nextQuest(zul,false) ~= exit and not detour())
  map, x, y = 1419, 66.90, 19.47
  bags[9471] = 0
  assert(not E.Applies(exit.when) and not detour(), "ready bit without the real medallion")
  bags[9471] = 1
  assert(E.Applies(exit.when) and nextQuest(zul,false) == exit and detour().s == exit)
  active[2991], turned[2991] = nil, true
  assert(not detour(), "finished on an older save")
end

doneOthers(temple, 3373)
level, map, x, y = 48, 220, nil, nil
local pickup = questStep(temple.list, "accept", 3373)
local work = questStep(temple.list, "do", 3373)
local font = questStep(temple.list, "turnin", 3373)
assert(pickup.manualAccept and not pickup.map and not work.map and not font.map)
for _, row in ipairs(temple.list) do
  if row.s.q == 3373 then assert(row.key == row.s.t:sub(1,1) .. ":3373") end
end
bags[10454], instance = 1, 109
assert(not E.Applies(pickup.when) and not instanceStep(temple,3373), "outdoors even with the same map and stale instance ID")
inParty, instance = true, 90
assert(not E.Applies(pickup.when) and not instanceStep(temple,3373), "wrong instance")
instance, bags[10454] = 109, 0
assert(not instanceStep(temple,3373) and nextQuest(temple,true) ~= pickup, "empty bag at entrance")
bags[10455] = 1
assert(not instanceStep(temple,3373), "the chained reward cannot start the quest")
bags[10454], level = 1, 47
assert(not instanceStep(temple,3373))
level, settings.optional = 48, false
assert(not instanceStep(temple,3373) and nextQuest(temple,true) ~= pickup)
settings.optional = true
ns.db.skip["a:3373"] = true
assert(not instanceStep(temple,3373) and nextQuest(temple,true) ~= pickup, "honor the saved skip key")
ns.db.skip["a:3373"] = nil
ns.db.dNo[temple.id] = true
assert(not instanceStep(temple,3373) and nextQuest(temple,true) ~= pickup)
ns.db.dNo[temple.id] = nil
for index = 1, 40 do log[index] = 100000 + index end
assert(not instanceStep(temple,3373) and nextQuest(temple,true) ~= pickup)
log = {}
assert(instanceStep(temple,3373) == pickup and nextQuest(temple,true) == pickup)
assert(not autoAccept(3373), "leave the item quest accept button to the player")

active[3373], bags[10454] = true, 0
level = 55
assert(instanceStep(temple,3373) == work and nextQuest(temple,true) ~= font, "empty objective list is not native readiness")
ready[3373], instance = true, 90
assert(not instanceStep(temple,3373) and nextQuest(temple,true) ~= font)
instance, inParty = 109, false
assert(not instanceStep(temple,3373) and nextQuest(temple,false) ~= font)
inParty = true
assert(instanceStep(temple,3373) == font and nextQuest(temple,true) == font, "native ready handoff does not require the consumed starter")
active[3373], turned[3373], bags[10454] = nil, true, 1
assert(not instanceStep(temple,3373), "do not restart a completed quest")

print(faction .. " dungeon intake: local handoff and real Temple readiness checked")
