local level, held, ready, completed = 20, nil, false, false
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human", "Human", 1 end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return level end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {
  db = {skip={},mark={},latch={},notNow={},dNo={},fpNodes={}},
  L = setmetatable({}, {__index=function(_, k) return k end}),
  UI = {Get=function() return false end},
  C = {
    IsOnQuest = function(q) return q == held end,
    IsReady = function() return ready end,
    IsTurnedIn = function() return completed end,
    Objectives = function() end,
    LogQuestIDs = function() return held and {held} or {} end,
  },
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("", ns)
end
local E = ns.E
E.Build()
local mayEnter = assert(loadfile("tools/tests/replay/dungeon-entry.lua"))()
local ruins = E.byId["05-d2"]
assert(ruins.lv[1] == 15 and ruins.lv[2] == 20)
for _, n in ipairs({14,20,21,23,24}) do
  level = n
  local window = n >= 15 and n <= 20
  assert(mayEnter(E, ruins, level, "allparty-window") == window)
  assert(mayEnter(E, ruins, level, "party") == window)
  assert(mayEnter(E, ruins, level, "early") == window)
  assert(mayEnter(E, ruins, level, "allparty") == (n >= 15 and n <= 23))
end
level, held = 24, 95195
local _, status, work = E.DungeonStatus(ruins)
assert(status == "revisit" and work.s.ph == "in")
assert(mayEnter(E, ruins, level, "allparty") and not mayEnter(E, ruins, level, "allparty-window"))
level, held, ready = 60, 1053, true
local scarlet = E.byId["05-d8"]
local _, returnStatus, handoff = E.DungeonStatus(scarlet)
assert(returnStatus == "revisit" and handoff.s.ph == "post")
assert(not mayEnter(E, scarlet, level, "allparty"))
held, completed = nil, true
assert(not mayEnter(E, ruins, level, "allparty"))
level, completed = 20, false
assert(E.DungeonNext(ruins, false).kind == "ent")
for _, mode in ipairs({"allparty", "allparty-window", "party", "early"}) do
  ns.db.dNo[ruins.id] = true
  assert(not mayEnter(E, ruins, level, mode, ns.db.dNo[ruins.id]))
  assert(not E.DungeonNext(ruins, false))
end
ns.db.dNo[ruins.id] = nil
level = 21
assert(E.DungeonNext(ruins, false).kind == "ent")
print("Replay separates the recommended range from the panel's valid entries and in-dungeon revisits")
