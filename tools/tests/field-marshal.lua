-- From the repository root: lua5.1 tools/tests/field-marshal.lua
-- Alliance chain in 大河林地 (03-37): 94885 starts from a drop, 94887 needs it turned in, 94892 follows 94887.
-- The later steps must stay out of the way until the drop chain is done, without hiding 94892 from players who unlocked it.
local active, ready, turned, optional = {}, {}, {}, false
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 44 end
function UnitXPMax() return 117500 end
function UnitXP() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={} }
local ns = { C={}, db=db, L={} }
ns.UI = { Get=function(key) return key == "optional" and optional end }
ns.C.IsOnQuest = function(q) return active[q] end
ns.C.IsReady = function(q) return ready[q] end
ns.C.IsTurnedIn = function(q) return turned[q] end
ns.C.XPBuff = function() return false end
ns.C.Position = function() return 2548, 50, 50 end
ns.C.ZoneTexts = function() end
ns.C.Bind = function() end
ns.C.LogQuestIDs = function() local out = {} for q in pairs(active) do out[#out + 1] = q end return out end
ns.C.Objectives = function() end
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local st = assert(E.byId["03-37"])

local function applicable()
  local state = E.Locate(st)
  local on = {}
  for i, step in ipairs(state.steps) do
    local s = step.s
    if (s.q == 94887 or s.q == 94892) and not state.na[i] then on[s.t .. s.q] = true end
  end
  return on, state
end

local function reset(o)
  active, ready, turned, optional = {}, {}, {}, o
  wipe(db.skip); wipe(db.mark); wipe(db.latch)
end

-- 1. No drop, optional quests on or off: the whole follow-up chain is skipped, nothing stalls on 94887.
for _, o in ipairs({true, false}) do
  reset(o)
  local on, state = applicable()
  assert(not on.accept94887 and not on.turnin94887 and not on.accept94892 and not on.turnin94892,
    "follow-ups must be skipped without the drop (optional=" .. tostring(o) .. ")")
  local cur = state.cur and state.steps[state.cur].s
  assert(not cur or (cur.q ~= 94887 and cur.q ~= 94892), "current step must not wait on 94887/94892")
end

-- 2. 94885 turned in (optional on or off): 94887 and its follow-up 94892 are offered.
for _, o in ipairs({true, false}) do
  reset(o)
  turned[94885] = true
  local on = applicable()
  assert(on.accept94887 and on.turnin94887, "94887 must be offered after turning in 94885 (optional=" .. tostring(o) .. ")")
  assert(on.accept94892 and on.turnin94892, "94892 must follow 94887 (optional=" .. tostring(o) .. ")")
end

-- 3. 94887 already turned in elsewhere: 94892 stays reachable.
reset(false)
turned[94885], turned[94887] = true, true
local on = applicable()
assert(on.accept94892 and on.turnin94892, "94892 must stay reachable after 94887")
print("Field Marshal chain: no drop skips 94887/94892, unlocked players keep 94887 and 94892")
