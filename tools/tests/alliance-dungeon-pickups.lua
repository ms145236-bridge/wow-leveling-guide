-- From the repository root: lua5.1 tools/tests/alliance-dungeon-pickups.lua
-- 聯盟補的副本（1.13.52 起）：空日誌進本，本內任務 NPC 的接取要出現在 HUD
local level, bag = 35, {}
local active, ready, turned = {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human", "Human", 1 end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return level end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function GetItemCount(id) return bag[id] or 0 end
local ns = {
  C={
    IsOnQuest=function(q) return active[q] end,
    IsReady=function(q) return ready[q] end,
    Objectives=function() return nil end,
    IsTurnedIn=function(q) return turned[q] end,
  },
  L=setmetatable({}, {__index=function(_, key) return key end}),
  UI={Get=function() return false end},
  db={skip={}, mark={}, latch={}, dNo={}},
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local function dungeon(name)
  for _, st in ipairs(E.dungeons) do if st.name == name then return st end end
  error("missing dungeon " .. name)
end
local function accepts(d)
  local out, state = {}, E.InstanceState(d)
  for _, row in ipairs(state and state.steps or {}) do
    if row.s.t == "accept" then out[row.s.q] = true end
  end
  return out
end

-- 剃刀沼澤：赫爾拉斯、威利克斯都在本內接
local rfk = accepts(dungeon("剃刀沼澤"))
assert(rfk[1142] and rfk[1144], "Razorfen Kraul in-instance pickups show with an empty log")
print("Alliance in-instance dungeon pickups show with an empty quest log")
