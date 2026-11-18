-- Run from the repository root with Lua 5.1.
function UnitFactionGroup() return "Horde" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitRace() return "Orc", "Orc", 2 end
local level = 53
function UnitLevel() return level end
function wipe(t) for k in pairs(t) do t[k] = nil end end

local journal, completed, turned = {}, {}, {}
local ns = {
  db = {skip={}, mark={}, latch={}, dNo={}},
  C = {
    IsOnQuest = function(q) return journal[q] end,
    IsReady = function(q) return completed[q] end,
    IsTurnedIn = function(q) return turned[q] end,
    Objectives = function() end,
  },
  UI = {Get=function() return false end},
  L = setmetatable({}, {__index=function(_, key) return key end})
}
for _, file in ipairs({"Data/Route.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local prison = E.byId["05-d22"]
local function inside(quest, stations)
  local state = E.InstanceState(prison, stations)
  for _, step in ipairs(state and state.steps or {}) do
    if step.s.q == quest then return step.s end
  end
end

assert(not inside(96335))
journal[96335] = true
local key = assert(inside(96335))
assert(key.t == "do" and key.ph == "in" and key.hint and not key.map)
completed[96335] = true
assert(not inside(96335))
journal[96335] = nil

assert(not inside(95483))
journal[96369], completed[96369] = true, true
assert(inside(96369).t == "turnin")
journal[96369], completed[96369], turned[96369] = nil, nil, true
assert(inside(95483).t == "accept")
journal[95483] = true
assert(not inside(95483))
-- The recommended-level player still has unselected side quests in the prison.
for _, q in ipairs({95283, 95284, 95285, 95309, 95454}) do turned[q] = true end
for _, ready in ipairs({false, true}) do
  completed[95483] = ready
  assert(not inside(95483))
  local nextStep = E.DungeonNext(prison, false)
  assert(nextStep.kind == "post")
  local step = nextStep.step.s
  assert(step.exitPriority and step.q == 95483 and step.map == 1454)
  assert(step.t == (ready and "turnin" or "do"))
end
level = 60
completed[95483] = false
local _, status, revisit = E.DungeonStatus(prison)
assert(status == "revisit" and revisit.s.q == 95483 and revisit.s.t == "do")

-- A region-only record may supplement an incomplete authored list. An explicit
-- in-instance objective in a sibling wing takes precedence over a delivery flag.
completed[95483] = nil
local sibling = {list={}, dq={95483, 97049}}
journal[97049] = true
assert(inside(97049, {prison, sibling}).t == "do")
assert(not inside(95483, {prison, sibling}))
sibling.list[1] = {s={t="do", ph="in", q=95483, hint="Sibling objective"}}
assert(inside(95483, {prison, sibling}) == sibling.list[1].s)
print("Alcaz key, in-prison pickup, outside delivery and shared-wing fallbacks passed")
