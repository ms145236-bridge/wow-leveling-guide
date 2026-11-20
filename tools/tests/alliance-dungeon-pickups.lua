-- From the repository root: lua5.1 tools/tests/alliance-dungeon-pickups.lua
-- 聯盟補的副本（1.13.52 起）：空日誌進本，本內任務 NPC 的接取要出現在 HUD
local level, bag, optionalOn = 35, {}, false
local active, ready, turned = {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human", "Human", 1 end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return level end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function GetItemCount(id) return bag[id] or 0 end
local instance
function GetInstanceInfo() return nil, nil, nil, nil, nil, nil, nil, instance end
function IsInInstance() return instance ~= nil end
local ns = {
  C={
    IsOnQuest=function(q) return active[q] end,
    IsReady=function(q) return ready[q] end,
    Objectives=function() return nil end,
    IsTurnedIn=function(q) return turned[q] end,
    LogQuestIDs=function() local t = {} for q in pairs(active) do t[#t + 1] = q end return t end,
  },
  L=setmetatable({}, {__index=function(_, key) return key end}),
  UI={Get=function(k) return k == "optional" and optionalOn end},
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
local function rows(d)
  local out, state = {}, E.InstanceState(d)
  for _, row in ipairs(state and state.steps or {}) do out[row.s.t .. ":" .. tostring(row.s.q)] = true end
  return out
end
-- 剃刀高地、瑪拉頓：貝尼斯特拉茲與札爾塔的靈魂在本內接
level = 45
assert(accepts(dungeon("剃刀高地"))[3523], "Razorfen Downs: Belnistrasz pickup")
level = 50
assert(accepts(dungeon("瑪拉頓"))[7066], "Maraudon: Seed of Life pickup")
-- 克羅多克模具：身上有鑄模才出現
level = 42
local kd = dungeon("克羅多克要塞")
instance = 3039
assert(not accepts(kd)[94980], "no mould, no pickup")
bag[267138], optionalOn = 1, true
assert(accepts(kd)[94980], "mould in bags shows the pickup")
bag[267138], instance, optionalOn = nil, nil, false
-- 本外完成：日誌裡未完成也不列成本內的「做」
level = 45
active[6626] = true
assert(not rows(dungeon("剃刀高地"))["do:6626"], "A Host of Evil is done outside")
active[6626] = nil
level = 50
active[7070] = true
assert(not rows(dungeon("瑪拉頓"))["do:7070"], "Shadowshard Fragments are outside")
active[7070] = nil
local alcaz = dungeon("奧卡茲監獄")
for _, q in ipairs({95198, 95263, 95264}) do
  active[q] = true
  assert(not rows(alcaz)["do:" .. q], "outside objective listed inside: " .. q)
  active[q] = nil
end
-- 噩耗：交紙條後在本內接（接取仍在本內顯示）
turned[95262] = true
assert(accepts(alcaz)[95263], "Somber News picked up from the note inside")
turned[95262] = nil
-- 被鐵鍊束縛的男人：本內接、拿鑰匙後在本內交（選做打開）
optionalOn = true
assert(accepts(alcaz)[96335], "Iron Chains pickup inside")
active[96335], ready[96335] = true, true
assert(rows(alcaz)["turnin:96335"], "Iron Chains hand-in inside")
active[96335], ready[96335] = nil, nil
print("Alliance in-instance dungeon pickups show with an empty quest log")
