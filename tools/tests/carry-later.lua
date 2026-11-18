-- From the repository root: lua5.1 tools/tests/carry-later.lua
-- 跳站時，身上還沒交、但路線後面的站還會交的任務（例：416 逮補狗頭人在 02-12 交），不帶到新站要人補做；
-- 後面沒有再出現的任務（例：224 保衛國王的領土）照舊帶過去補。
local active, ready, turned = {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 12 end
function UnitXPMax() return 8800 end
function UnitXP() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, drop={}, fpNodes={}, start="Human", station="01-9" }
local ns = { C={}, db=db, L={} }
ns.UI = { Get=function() return false end }
ns.C.IsOnQuest = function(q) return active[q] end
ns.C.IsReady = function(q) return ready[q] end
ns.C.IsTurnedIn = function(q) return turned[q] end
ns.C.XPBuff = function() return false end
ns.C.Position = function() return 1439, 36, 45 end
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
local target = assert(E.byId["02-10"])
active[416], ready[416] = true, true
active[224] = true
local carry = E.JumpPlan(target)
local has = {}
for _, q in ipairs(carry) do has[q] = true end
assert(not has[416], "416 is turned in at 02-12 later: must not be carried to 02-10")
assert(has[224], "224 has no later station: still carried")
-- 舊存檔已經帶進來的 416 也不再顯示
db.carry["02-10"] = { 416, 224 }
db.station = "02-10"
local state = E.Locate(target)
local shown = {}
for _, step in ipairs(state.steps) do if step.carry then shown[step.s.q] = true end end
assert(not shown[416], "saved carry of 416 must be hidden at 02-10")
assert(shown[224], "saved carry of 224 still shown")
print("carry-later: all passed")
