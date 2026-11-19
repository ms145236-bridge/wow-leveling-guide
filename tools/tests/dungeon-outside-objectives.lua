-- The raw instance index includes conversations that happen outside the instance.
local faction, held, ready, currentInstance
function IsInInstance() return currentInstance ~= nil end
function GetInstanceInfo() return nil, nil, nil, nil, nil, nil, nil, currentInstance end
function UnitFactionGroup() return faction end
function UnitRace() return faction == "Horde" and "Orc" or "Human", faction == "Horde" and "Orc" or "Human", faction == "Horde" and 2 or 1 end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitLevel() return 49 end
function wipe(t) for k in pairs(t) do t[k] = nil end end

local function loadRoute(side)
  faction, held, ready = side, {}, {}
  local ns = {
    C = {IsOnQuest=function(q) return held[q] end, IsReady=function(q) return ready[q] end,
         IsTurnedIn=function() return false end, Position=function() return 1446, 51.6, 26.8 end},
    db = {skip={}, mark={}, latch={}, dNo={}, pin={}, carry={}, notNow={}, fpNodes={}},
    UI = {Get=function() return false end},
    L = setmetatable({}, {__index=function(_, key) return key end}),
  }
  local file = side == "Horde" and "Route" or "RouteA"
  for _, path in ipairs({"Data/" .. file .. ".lua", "Engine.lua"}) do
    assert(loadfile("addon/ShengLeveling/" .. path))("ShengLeveling", ns)
  end
  ns.E.Build()
  return ns
end

local function journalStep(E, station, q, all)
  local state = E.InstanceState(station, all)
  for _, row in ipairs(state and state.steps or {}) do
    if row.s.q == q then return row.s end
  end
end

local H = loadRoute("Horde")
local zul = assert(H.E.byId["05-d21"])
local indexed = false
for _, q in ipairs(zul.dq) do if q == 2864 then indexed = true end end
assert(indexed and H.Route.offroute[2864] and not H.Route.quests[2864])
assert(not journalStep(H.E, zul, 2864))
held[2864], held[96775], held[96776], held[97197] = true, true, true, true
assert(not journalStep(H.E, zul, 2864), "held Tran'rek is a conversation in Gadgetzan")
assert(journalStep(H.E, zul, 96775).t == "do")
assert(journalStep(H.E, H.E.byId["05-d20"], 96776).t == "do")
assert(journalStep(H.E, H.E.byId["05-d24"], 97197).t == "do")

local function checkIndexedOutside(E, instance, excluded, inDungeon)
  currentInstance = instance
  local station, all = E.DungeonByInstance(instance)
  assert(station and #all > 0)
  for _, q in ipairs(excluded) do
    local indexed = false
    for _, wing in ipairs(all) do
      for _, id in ipairs(wing.dq or {}) do if q == id then indexed = true end end
    end
    assert(indexed, "quest stays in the complete index: " .. q)
    assert(not journalStep(E, station, q, all), "unheld quest: " .. q)
    held[q] = true
  end
  held[inDungeon] = true
  for _, q in ipairs(excluded) do
    assert(not journalStep(E, station, q, all), "held quest with an outdoor objective: " .. q)
  end
  assert(journalStep(E, station, inDungeon, all), "held quest with an instance objective: " .. inDungeon)
  currentInstance = nil
end

checkIndexedOutside(H.E, 109, {8733}, 3373)
checkIndexedOutside(H.E, 230, {4002, 4133}, 4003)

local A = loadRoute("Alliance")
zul = assert(A.E.byId["05-d10"])
held[2864], ready[2864] = true, true
assert(not journalStep(A.E, zul, 2864))
local handoff = A.E.DungeonNext(zul, false)
assert(handoff.kind == "post" and handoff.step.s.q == 2864 and handoff.step.s.map == 1446)
checkIndexedOutside(A.E, 109, {8733}, 3373)
print("Outdoor indexed quests stay out of the HUD; genuine instance work and Alliance hand-in remain")
