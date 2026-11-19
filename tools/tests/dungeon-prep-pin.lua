-- From the project root: lua5.1 tools/tests/dungeon-prep-pin.lua
-- A pinned dungeon-prep accept is suspended (not followed, not dropped) while the
-- prep is off or the dungeon is set to "skip", and comes back when re-enabled.
local active, turned, log = {}, {}, {}
local level = 24
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return level end
function UnitXP() return 0 end
function UnitXPMax() return 36300 end
function GetTime() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local settings = {optional=true, dPre=true}
local ns = {
  C = {IsOnQuest=function(q) return active[q] end, IsReady=function() return false end,
       IsTurnedIn=function(q) return turned[q] end, LogQuestIDs=function() return log end,
       XPBuff=function() return false end, Position=function() end, ZoneTexts=function() end,
       Bind=function() end, Objectives=function() end},
  db = {skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}},
  UI = {Get=function(k) return settings[k] end},
  L = setmetatable({}, {__index=function(_, key) return key end}),
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local function index(state, q, t)
  for i, step in ipairs(state.steps) do
    if step.s.q == q and step.s.t == t then return i end
  end
  error("missing " .. t .. " " .. q)
end
local function byKey(state, key)
  for i, step in ipairs(state.steps) do if step.key == key then return i end end
end
local function check(stationId, dungeon, q, oldPin)
  local st = assert(E.byId[stationId])
  local state = E.Locate(st)
  local i = index(state, q, "accept")
  assert(not state.na[i], q .. " is offered while the prep is on")
  if oldPin then ns.db.pin[st.id] = {key=state.steps[i].key} else E.PinIndex(state, i) end
  local key = ns.db.pin[st.id].key
  state = E.Locate(st)
  assert(state.cur == i, q .. " pin is followed")
  for _, off in ipairs({function() ns.db.dNo[dungeon] = true end, function() settings.dPre = false end}) do
    off()
    state = E.Locate(st)
    local at = byKey(state, key)
    assert(not at or state.na[at], q .. " does not apply")
    assert(not state.cur or state.steps[state.cur].key ~= key, q .. " pin is suspended while the prep does not apply")
    assert(ns.db.pin[st.id] and ns.db.pin[st.id].key == key, q .. " keeps the original pinned key")
    ns.db.dNo[dungeon], settings.dPre = nil, true
    state = E.Locate(st)
    assert(state.cur == byKey(state, key), q .. " pin resumes once the prep applies again")
  end
  -- Already accepted: the accept row is done, so the pin is released as before.
  active[q] = true
  state = E.Locate(st)
  assert(state.cur ~= byKey(state, key) and not ns.db.pin[st.id], q .. " accepted releases the pin")
  active[q] = nil
  ns.db.pin[st.id] = nil
end
check("02-15", "05-d4", 386)
level = 30
for _, q in ipairs({2928, 2922, 2929}) do check("03-23", "05-d7", q, true) end
check("03-23", "05-d7", 2930)
-- Suspended while the mainline moves on: the old auto anchor no longer matches on resume.
do
  local st = E.byId["03-23"]
  local state = E.Locate(st)
  local tink = byKey(state, state.steps[state.auto].key)
  assert(state.steps[tink].s.q == 2923 and state.steps[tink].s.t == "accept", "the mainline anchor starts at the 2923 accept")
  E.PinIndex(state, index(state, 2930, "accept"))
  local key = ns.db.pin[st.id].key
  settings.dPre = false
  state = E.Locate(st)
  assert(state.steps[state.cur].key ~= key and ns.db.pin[st.id].key == key)
  active[2923] = true
  state = E.Locate(st)
  assert(state.steps[state.auto].s.q ~= 2923, "accepting 2923 moves the mainline anchor")
  settings.dPre = true
  state = E.Locate(st)
  assert(state.steps[state.cur].key == key and ns.db.pin[st.id].key == key, "the 2930 pin resumes after the anchor moved")
  state = E.Locate(st)
  assert(state.steps[state.cur].key == key, "the resumed pin stays on the next refresh")
  active[2930] = true
  state = E.Locate(st)
  assert(not ns.db.pin[st.id] and state.steps[state.cur].key ~= key, "accepting 2930 releases the pin")
  active[2923], active[2930] = nil, nil
end

-- A full log temporarily defers the prep accept; the pin waits and returns when a slot frees up.
do
  local st = E.byId["03-23"]
  local state = E.Locate(st)
  E.PinIndex(state, index(state, 2930, "accept"))
  local key = ns.db.pin[st.id].key
  for k = 1, 39 do log[k] = 100000 + k end
  state = E.Locate(st)
  local at = byKey(state, key)
  assert(state.steps[at].defer and state.steps[state.cur].key ~= key and ns.db.pin[st.id].key == key, "capacity defer suspends the pin")
  wipe(log)
  state = E.Locate(st)
  assert(state.steps[state.cur].key == key and ns.db.pin[st.id].key == key, "a freed slot resumes the pin")
  ns.db.pin[st.id] = nil
end
print("Pinned dungeon-prep accepts suspend while the prep is off or skipped, and resume when re-enabled")
