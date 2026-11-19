-- Check the real selected-dungeon HUD and the independent dungeon card.
local active, turned, bags = {}, {}, {}
local ready, objective
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human", "Human", 1 end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return 31 end
function UnitXP() return 0 end
function UnitXPMax() return 1 end
function GetItemCount(id) return bags[id] or 0 end
function wipe(t) for key in pairs(t) do t[key] = nil end end

local ns = {
  db = { skip = {}, mark = {}, latch = {}, notNow = {}, pin = {}, carry = {}, dNo = {}, fpNodes = {} },
  L = setmetatable({}, { __index = function(_, key) return key end }),
  UI = { Get = function(key) return key == "optional" or key == "dPre" end },
  C = {
    IsOnQuest = function(q) return active[q] end,
    IsReady = function(q) return q == 2930 and ready end,
    IsTurnedIn = function(q) return turned[q] end,
    Objectives = function(q) return q == 2930 and objective or nil end,
    Position = function() return 1455, 69.83, 48.10 end,
    LogQuestIDs = function() return {} end,
    XPBuff = function() return false end,
    Bind = function() end,
    ZoneTexts = function() end,
  },
}
for _, file in ipairs({ "Data/RouteA.lua", "Engine.lua" }) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local dungeon = E.byId["05-d7"]

local function breadcrumbAvailable()
  local state = E.Locate(dungeon)
  for index, row in ipairs(state.steps) do
    if row.key == "a:2931" then return not state.na[index] end
  end
  error("2931 is missing")
end

assert(breadcrumbAvailable())
active[2930] = true
assert(not breadcrumbAvailable())
active[2930], turned[2930] = nil, true
assert(not breadcrumbAvailable())
active[2931] = true
assert(breadcrumbAvailable())
active[2931], turned[2930] = nil, nil

local work
for _, row in ipairs(dungeon.list) do
  if row.s.q ~= 2930 then ns.db.skip[row.key] = true end
  if row.key == "d:2930" then work = row.s end
end
assert(work and work.ph == "in" and not work.map and not work.spot and work.hint:find("3005%-D"))

local function check(label, shouldTurnIn)
  local state = E.Locate(dungeon)
  local hud = state.cur and state.steps[state.cur]
  local tab = E.DungeonNext(dungeon, false)
  local inside = E.InstanceState(dungeon)
  assert((hud and hud.key == "t:2930" or false) == shouldTurnIn, label .. ": selected route")
  assert((tab and tab.step and tab.step.key == "t:2930" or false) == shouldTurnIn, label .. ": dungeon card")
  assert((inside and inside.steps[1].key == "d:2930" or false) == (active[2930] and not shouldTurnIn or false),
    label .. ": in-instance objective")
  if shouldTurnIn then
    assert(hud.s.map == 1455 and hud.s.x == 69.83 and hud.s.y == 48.10)
  end
end

bags[9316], ready = 1, true
check("unaccepted with card", false)
active[2930], bags[9316], ready = true, nil, false
ns.db.pin[dungeon.id] = { key = "t:2930", wasDone = true }
check("old saved pin with empty bags", false)
assert(ns.db.pin[dungeon.id].key == "t:2930")
bags[9279], bags[9280], bags[9282], bags[9281], ready = 1, 1, 1, 1, true
check("all four intermediate cards and stale ready flag", false)
bags[9316], ready = 1, false
check("prismatic card before journal ready", false)
ready, objective = true, { { have = 0, need = 1, done = false } }
check("prismatic card with contradictory journal", false)
objective = { { have = 1, need = 1, done = true } }
check("prismatic card and journal ready", true)
bags[9316] = nil
check("prismatic card removed", false)
print("Data Rescue: original breadcrumb, old pin, in-instance work, physical card and journal readiness")

-- The actual dungeon suppresses the old Ironforge pin, including while the
-- client reports the instance flag without its ID.
local physical, instanceID = true, 90
function IsInInstance() return physical, physical and "party" or "none" end
function GetInstanceInfo() return nil, nil, nil, nil, nil, nil, nil, instanceID end
ns.C.Position = function()
  if physical then return 1426, 0, 0 end
  return 1455, 69.83, 48.10
end
ns.db.station = dungeon.id

local function outdoors(label, shouldTurnIn)
  local state = E.Locate(dungeon)
  local hud = state.cur and state.steps[state.cur]
  local _, matches = E.DungeonByInstance(instanceID)
  local inside = physical and matches[1] == dungeon
  -- The dungeon tab waits for the native ID before asking for a next step.
  local waiting = physical and (not instanceID or instanceID == 0)
  local tab = not waiting and E.DungeonNext(dungeon, inside)
  assert((hud and hud.key == "t:2930" or false) == shouldTurnIn, label .. ": selected route")
  assert((tab and tab.step and tab.step.key == "t:2930" or false) == shouldTurnIn, label .. ": dungeon card")
end

ns.db.pin[dungeon.id] = { key = "t:2930", wasDone = true }
bags[9316] = 1
outdoors("real instance 90 with card and native ready", false)
assert(ns.db.pin[dungeon.id].key == "t:2930")
instanceID = 0
outdoors("instance entry while ID is loading", false)
instanceID = nil
outdoors("instance entry before an ID is available", false)
instanceID = 90
bags[9316], bags[9279], ready = nil, 1, false
outdoors("white or intermediate card inside", false)
bags[9316], ready, active[2930] = 1, true, nil
outdoors("unaccepted with final card inside", false)

physical, instanceID = false, 0
outdoors("unaccepted with final card after leaving", false)
active[2930], ready = true, false
outdoors("carrying the card outdoors before ready", false)
ready = true
outdoors("ready hand-in has left the instance", true)
print("Data Rescue: outdoor hand-in stays dormant inside instance 90 and during entry")
