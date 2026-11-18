-- From the repository root: lua5.1 tools/tests/stockades.lua
local level, letter = 26, 0
local active, ready, turned = {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human", "Human", 1 end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return level end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function GetItemCount(id) return id == 2874 and letter or 0 end
local ns = {
  C={
    IsOnQuest=function(q) return active[q] end,
    IsReady=function(q) return ready[q] end,
    Objectives=function() return nil end,
    IsTurnedIn=function(q) return turned[q] end,
  },
  L=setmetatable({}, {__index=function(_, key) return key end}),
  UI={Get=function() return false end},
  db={skip={}, mark={}, latch={}, dNo={}},
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local mines, stockades = assert(E.byId["05-d3"]), assert(E.byId["05-d4"])
local function find(station, verb, quest, phase)
  for i, step in ipairs(station.list) do
    local s = step.s
    if s.t == verb and s.q == quest and (not phase or s.ph == phase) then return i, step end
  end
  error("missing quest " .. quest .. " " .. verb .. " in " .. station.id)
end

local _, bossLetter = find(mines, "accept", 373, "in")
assert(bossLetter.s.when.bag.item == 2874 and not bossLetter.s.map)
assert(E.InstanceState(mines) == nil)
letter, level = 1, 15
assert(E.InstanceState(mines) == nil)
level = 26
local shown = E.InstanceState(mines)
assert(#shown.steps == 1 and shown.steps[1].s == bossLetter.s)
ns.db.skip[bossLetter.key] = true
assert(E.InstanceState(mines) == nil)
ns.db.skip[bossLetter.key] = nil
active[373], ready[373] = true, true
assert(E.InstanceState(mines) == nil)
active[373], ready[373], letter = nil, nil, 0
local _, mainLetter = find(E.byId["02-14"], "accept", 373)
assert(mainLetter.s.when.bag.item == 2874 and not mainLetter.s.map)

assert(ns.Route.quests[389].ps[1] == 373 and ns.Route.quests[391].ps[1] == 389)
find(stockades, "need", 386, "pre")
local pickLetter = find(stockades, "accept", 373, "pre")
local returnLetter = find(stockades, "turnin", 373, "pre")
local pickBazil = find(stockades, "accept", 389, "pre")
local returnBazil = find(stockades, "turnin", 389, "pre")
local pickRiots = find(stockades, "accept", 391, "pre")
assert(pickLetter < returnLetter and returnLetter < pickBazil and pickBazil < returnBazil and returnBazil < pickRiots)

-- An otherwise prepared party can enter without the letter.
turned[377], turned[388], active[387] = true, true, true
assert(E.DungeonNext(stockades, false).kind == "ent")
local function pre(verb, q)
  local step = E.DungeonNext(stockades, false).step
  assert(step.s.t == verb and step.s.q == q)
end
letter = 1
pre("accept", 373)
active[373], ready[373], letter = true, true, 0
pre("turnin", 373)
turned[373], active[373] = true, nil
pre("accept", 389)
active[389], ready[389] = true, true
pre("turnin", 389)
turned[389], active[389] = true, nil
pre("accept", 391)

-- The Dan Modr quest is a later pickup and already appears in combat when on quest.
local wetlands = E.byId["03-23"]
local doneWar = find(wetlands, "turnin", 303)
local nextQuest, pickFury = find(wetlands, "accept", 378)
assert(nextQuest == doneWar + 1 and pickFury.s.opt and ns.Route.quests[378].ps[1] == 303)
find(stockades, "do", 378, "in")
local _, returnFury = find(stockades, "turnin", 378, "post")
assert(returnFury.s.map == 1437 and returnFury.s.when.onQuestAny[1] == 378)
turned[387], active[387] = true, nil
turned[373], turned[389] = nil, nil
assert(E.DungeonDone(stockades))
active[378] = true
assert(not E.DungeonDone(stockades))
shown = E.InstanceState(stockades)
assert(#shown.steps == 1 and shown.steps[1].s.q == 378 and shown.steps[1].s.ph == "in")
assert(E.DungeonNext(stockades, false).kind == "ent")
ready[378] = true
local handIn = E.DungeonNext(stockades, false)
assert(handIn.kind == "post" and handIn.step == returnFury)
print("Deadmines letter, Stockades preparation and optional Dan Modr revisit passed")
