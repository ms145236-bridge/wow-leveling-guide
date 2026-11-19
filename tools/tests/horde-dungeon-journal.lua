-- Run against the shipped Horde route, using the live instance checklist logic.
function UnitFactionGroup() return "Horde" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitRace() return "Orc", "Orc", 2 end
function UnitLevel() return 60 end
function wipe(t) for k in pairs(t) do t[k] = nil end end

local journal, ready = {}, {}
local ns = {
  db = {skip={}, mark={}, latch={}, dNo={}},
  C = {
    IsOnQuest=function(q) return journal[q] end,
    IsReady=function(q) return ready[q] end,
    IsTurnedIn=function() return false end,
    Objectives=function() end,
  },
  UI = {Get=function() return false end},
  L = setmetatable({}, {__index=function(_, key) return key end}),
}
for _, file in ipairs({"Data/Route.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local mines = assert(E.byId["05-d5"])
local hold = assert(E.byId["05-d33"])
local function action(dungeon, id)
  local state = E.InstanceState(dungeon)
  for _, step in ipairs(state and state.steps or {}) do
    if step.s.q == id then return step.s end
  end
end

-- Only the character holding the fortune quest gets the chest hint. Keep
-- the chest actionable when the log reports that the quest is ready to turn in.
assert(not action(mines, 7938))
journal[7938] = true
local fortune = assert(action(mines, 7938), "Missing Deadmines fortune")
assert(fortune.t == "do" and fortune.spot and not fortune.map)
ready[7938] = true
local chest = assert(action(mines, 7938))
assert(chest.t == "turnin" and chest.npc and not chest.map)
local _, status, revisit = E.DungeonStatus(mines)
assert(status == "revisit" and revisit.s == chest, "A ready inside turn-in must not fold as past")
assert(E.DungeonNext(mines, true).step.s == chest)
assert(E.DungeonNext(mines, false).kind == "ent")
-- Some historic in-phase turn-ins carry an outdoor map marker.
chest.map = 1436
assert(select(2, E.DungeonStatus(mines)) == "past")
chest.map = nil
assert(not action(hold, 7938))

for _, id in ipairs({92065, 92066}) do
  assert(not action(hold, id))
  journal[id] = true
  local goal = assert(action(hold, id), "Missing Blackmaw objective " .. id)
  assert(goal.t == "do" and goal.ph == "in" and goal.hint and not goal.map)
  assert(not action(mines, id))
  ready[id] = true
  assert(not action(hold, id), "Outdoor return listed inside Blackmaw Hold")
end
journal[96246] = true
assert(not action(hold, 96246))
-- No quest acquisition or travel is advertised from these journal-only additions.
for _, dungeon in ipairs({mines, hold}) do
  for _, step in ipairs(dungeon.list) do
    local s = step.s
    if s.q == 7938 or s.q == 92065 or s.q == 92066 then
      assert(s.ph == "in" and s.t ~= "accept")
    end
  end
end
print("Horde Deadmines fortune and Blackmaw journal objectives passed")

-- The Horde route still uses its own Feralas field locations. Neither the
-- spirit collection nor its Steamwheedle Port handoffs take place in a dungeon.
local turned = {}
ns.C.IsTurnedIn = function(q) return turned[q] end
ns.C.Objectives = function(q)
  if q == 3520 then return {{have=ready[q] and 3 or 1, need=3, done=ready[q] or false}} end
end
for _, case in ipairs({{209, 45, 3042}, {109, 52, 3446}}) do
  local dungeon = E.DungeonByInstance(case[1])
  UnitLevel = function() return case[2] end
  wipe(turned)
  wipe(journal)
  wipe(ready)
  -- Represent the normal visit after the preceding preparation in this guide.
  for _, step in ipairs(dungeon.list) do
    if step.s.q == 3520 then break end
    if step.s.q then turned[step.s.q] = true end
  end
  for _, verb in ipairs({"accept", "do", "turnin"}) do
    journal[3520] = verb ~= "accept"
    ready[3520] = verb == "turnin"
    local outside = assert(E.DungeonNext(dungeon, false)).step.s
    assert(outside.q == 3520 and outside.t == verb and outside.outsideObjective)
    assert(outside.map == (verb == "do" and 1444 or 1446))
    local inside = E.DungeonNext(dungeon, true)
    assert(not action(dungeon, 3520) and not (inside and inside.step and inside.step.s.q == 3520))
    local q = case[3]
    turned[q], journal[q] = nil, true
    assert(action(dungeon, q) and E.DungeonNext(dungeon, true).step.s.q == q)
    journal[q], turned[q] = nil, true
  end
end
print("Horde 3520 preparation stays outdoors while ZF and Temple journal objectives stay available")

local zf = E.DungeonByInstance(209)
wipe(journal)
wipe(ready)
ns.C.IsTurnedIn = function(q) return q ~= 3042 end
journal[3042] = true
for _, lv in ipairs({45, 59}) do
  UnitLevel = function() return lv end
  ready[3042] = false
  assert(action(zf, 3042).t == "do" and E.DungeonNext(zf, true).step.s.q == 3042)
  ready[3042] = true
  assert(not action(zf, 3042) and not E.DungeonNext(zf, true))
  local city = assert(E.DungeonNext(zf, false)).step.s
  assert(city.t == "turnin" and city.q == 3042 and city.map == 1446)
end
