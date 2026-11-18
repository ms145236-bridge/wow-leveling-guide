-- From the repository root: lua5.1 tools/tests/fp-step.lua
-- 開鳥點步驟不會因為後面接了別的任務就被帶過：奧伯丁（02-10）先接了 963 永志不渝，「鳥｜奧伯丁」仍要輪到。
local active = {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 12 end
function UnitXPMax() return 8800 end
function UnitXP() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, drop={}, fpNodes={}, start="Human", station="02-10" }
local ns = { C={}, db=db, L={} }
ns.UI = { Get=function() return false end }
ns.C.IsOnQuest = function(q) return active[q] end
ns.C.IsReady = function() return false end
ns.C.IsTurnedIn = function() return false end
ns.C.XPBuff = function() return false end
ns.C.Position = function() return 1439, 36.6, 44.5 end
ns.C.ZoneTexts = function() end
ns.C.Bind = function() end
ns.C.LogQuestIDs = function() local out = {} for q in pairs(active) do out[#out + 1] = q end return out end
ns.C.Objectives = function() end
ns.C.GreenRange = function() return 8 end
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local st = assert(E.byId["02-10"])
active[983], active[3524], active[963] = true, true, true
local state = E.Locate(st)
local cur = state.cur and state.steps[state.cur].s
assert(cur and cur.t == "fp", "fp step must be current, got " .. tostring(cur and (cur.t .. " " .. tostring(cur.q))))
db.fpNodes["奧伯丁"] = true
state = E.Locate(st)
cur = state.cur and state.steps[state.cur].s
assert(cur and cur.t ~= "fp", "known flight point is done")
print("fp-step: not passed by later accepts; done once known")
