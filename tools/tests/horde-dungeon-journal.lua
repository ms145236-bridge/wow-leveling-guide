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
