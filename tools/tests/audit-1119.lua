-- From the repository root: lua5.1 tools/tests/audit-1119.lua
-- 1.13.23 稽核修正：掉落起始任務只在持有起始物品時出現、護送與 5083 只有日誌可交才指回交件人、
-- 4489／5652 已接者的交件、血色 1048 的等級狀態與分翼提示、影牙 1013／1014／1098 綁副本、1150 回多恩的路標。
local function boot(faction, race, raceID, class)
  local env = { level = 1, active = {}, ready = {}, turned = {}, bags = {} }
  function UnitFactionGroup() return faction end
  function UnitRace() return race, race, raceID end
  function UnitClass() return class, class end
  function UnitLevel() return env.level end
  function GetItemCount(id) return env.bags[id] or 0 end
  function wipe(t) for k in pairs(t) do t[k] = nil end end
  local ns = {
    C = {
      IsOnQuest = function(q) return env.active[q] end,
      IsReady = function(q) return env.ready[q] end,
      Objectives = function() return {} end,
      IsTurnedIn = function(q) return env.turned[q] end,
    },
    L = setmetatable({}, { __index = function(_, key) return key end }),
    UI = { Get = function(key) return key == "optional" or key == "dPre" end },
    db = { skip = {}, mark = {}, latch = {}, dNo = {} },
  }
  local data = faction == "Alliance" and "Data/RouteA.lua" or "Data/Route.lua"
  for _, file in ipairs({ data, "Engine.lua" }) do assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns) end
  ns.E.Build()
  return ns, env
end
local function rawStep(ns, station, verb, quest)
  for _, st in ipairs(ns.Route.stations) do
    if st.id == station then
      for _, s in ipairs(st.steps) do if s.t == verb and s.q == quest then return s end end
    end
  end
end
local cur
local function stepOf(E, station, verb, quest)
  for _, step in ipairs(E.byId[station] and E.byId[station].list or {}) do
    if step.s.t == verb and step.s.q == quest then return step.s end
  end
  return assert(rawStep(cur, station, verb, quest), station .. " " .. verb .. " " .. quest .. " missing")
end

-- ── 聯盟 ──
local ns, env = boot("Alliance", "Human", 1, "WARRIOR")
cur = ns
local E = ns.E
local function dropStart(station, quest, item, wrong)
  local s = stepOf(E, station, "accept", quest)
  assert(s.opt and not s.map, quest .. "：掉落起始的接取不放固定座標")
  assert(s.when.bag.item == item and s.when.bag.count == 1)
  env.bags = {}
  assert(not E.Applies(s.when), quest .. "：空袋不顯示接取")
  env.bags = { [wrong] = 1 }
  assert(not E.Applies(s.when), quest .. "：別的物品不算")
  env.bags = { [item] = 1 }
  assert(E.Applies(s.when), quest .. "：持有起始物品才顯示接取")
  env.bags = {}
end
dropStart("04-43", 351, 8623, 8704)
dropStart("04-44", 485, 8704, 8623)
dropStart("04-53", 5083, 12771, 8623)
-- 護送：可選、真的有護送步驟與正確地圖；只有日誌可交才指回藏寶海灣
for _, e in ipairs({ { 648, "04-43", 1446 }, { 836, "04-44", 1425 } }) do
  local q, station, map = e[1], e[2], e[3]
  assert(stepOf(E, station, "accept", q).opt, q .. "：可選前置不能被寵物任務升成必做")
  local escort = stepOf(E, station, "do", q)
  assert(escort.opt and escort.map == map and escort.more[1][1] == map, q .. "：護送目的地在同一張地圖")
  local hand = stepOf(E, "04-46", "turnin", q)
  assert(hand.opt and hand.when.readyQuest == q)
  env.active[q] = true
  assert(not E.Applies(hand.when), q .. "：已接、未完成或失敗時不指回藏寶海灣")
  env.ready[q] = true
  assert(E.Applies(hand.when), q .. "：可交才指回藏寶海灣")
end
assert(stepOf(E, "04-46", "accept", 3721).opt and stepOf(E, "04-46", "turnin", 3721).opt)
local pet = ns.Route.quests[3721]
assert(#pet.pg == 3, "寵物任務仍要三筆實際交件")
-- 5083 沒有任務目標：日誌可交與否由身上的空火酒瓶決定（遊戲對無目標任務不一定回報完成）
local firewater = stepOf(E, "04-53", "turnin", 5083)
env.active[5083], env.bags = true, {}
assert(not E.Applies(firewater.when), "5083 已接、瓶子不在身上不顯示交件")
env.bags[12771] = 1
assert(E.Applies(firewater.when), "5083 帶著瓶子才顯示交件")
env.bags = {}
print("Alliance drop-started quests, escorts and Winterfall Firewater passed")

-- ── 部落 ──
ns, env = boot("Horde", "Troll", 8, "WARLOCK")
cur = ns
E = ns.E
dropStart("01-6", 361, 2839, 12771)
dropStart("04-47", 5083, 12771, 2839)
for _, verb in ipairs({ "turnin" }) do
  firewater = stepOf(E, "04-47", verb, 5083)
  env.active[5083], env.bags = true, {}
  assert(not E.Applies(firewater.when), "5083 " .. verb .. "：瓶子不在身上不指向多諾瓦")
  env.bags[12771] = 1
  assert(E.Applies(firewater.when))
end
env.bags = {}
-- 4489：已接幽暗城來源的術士在棘齒城同一 NPC 交，4490 照舊在後面
local list = E.byId["04-34"].list
local at = {}
for i, step in ipairs(list) do
  local s = step.s
  if s.q == 4489 and s.t == "turnin" then at.hand = i; at.when = s.when end
  if s.q == 4490 and s.t == "accept" then at.felsteed = i end
end
assert(at.hand and at.felsteed and at.hand < at.felsteed)
env.level = 48
assert(not E.Applies(at.when), "沒接 4489 不出現交件")
env.active[4489] = true
assert(E.Applies(at.when), "已接 4489 才出現交件")
assert(#ns.Route.quests[4490].ps >= 2, "4490 保留兩條來源擇一")
-- 5652：舊版已接的食人妖牧師仍可交
local hex = rawStep(ns, "01-1", "turnin", 5652) or rawStep(ns, "01-2", "turnin", 5652)
assert(hex and hex.when.onQuestAny[1] == 5652)
assert(not rawStep(ns, "01-2", "accept", 5652) and not rawStep(ns, "01-1", "accept", 5652), "不再強制接互斥的 5652")
-- 影牙：接取與本內工作綁 05-d6；已取證物的城內交件保留
for _, e in ipairs({ { "accept", 1013 }, { "accept", 1014 }, { "accept", 1098 }, { "do", 1013 }, { "do", 1014 }, { "do", 1098 } }) do
  assert(stepOf(E, "02-9", e[1], e[2]).when.dungeonPrep == "05-d6", e[1] .. " " .. e[2])
end
assert(not (stepOf(E, "02-9", "turnin", 1013).when or {}).dungeonPrep, "1013 城內交件保留")
env.level = 18
env.active[1013] = true
ns.db.dNo["05-d6"] = true
assert(not E.Applies(stepOf(E, "02-9", "do", 1013).when), "影牙不打：不帶回入口")
ns.db.dNo["05-d6"] = nil
assert(E.Applies(stepOf(E, "02-9", "do", 1013).when))
-- 1150：只有接了而且拿到爪子才帶去多恩
local detour
for _, step in ipairs(E.byId["02-13"].list) do
  if step.s.t == "travel" and step.s.when and step.s.when.onQuestAny and step.s.when.onQuestAny[1] == 1150 then detour = step.s end
end
assert(detour and detour.when.bag.item == 5843)
env.level = 27
assert(not E.Applies(detour.when), "跳過 1150 不被帶去多恩")
env.active[1150] = true
assert(not E.Applies(detour.when), "沒有爪子不被帶去多恩")
env.bags[5843] = 1
assert(E.Applies(detour.when))
env.bags = {}
-- 血色 1048：狀態與接取用同一個最低等級，分翼提示用各自的工作列
local library, armory, cathedral = E.byId["05-d11"], E.byId["05-d12"], E.byId["05-d13"]
env.active, env.ready, env.turned = {}, {}, {}
env.level = 32
local label, kind = E.DungeonStatus(armory)
assert(kind == "ready" and label:find("前置 33 級可接", 1, true) and label:find("可以去", 1, true), "32 級：可以進本，前置之後才接（" .. label .. "）")
env.level = 33
label, kind = E.DungeonStatus(armory)
assert(kind == "pick", "33 級：前置可接（" .. label .. "）")
env.active[1048] = true
local function hint(wing, all)
  for _, step in ipairs(E.InstanceState(wing, all).steps) do
    if step.s.q == 1048 then return step.s.hint or "" end
  end
end
local lib = hint(library, { library, armory, cathedral })
assert(lib:find("洛克希", 1, true) and not lib:find("莫格萊尼", 1, true), "圖書館提示洛克希，不是大教堂")
local arm = hint(armory, { armory, library, cathedral })
assert(arm:find("赫洛德", 1, true) and not arm:find("莫格萊尼", 1, true), "軍械庫提示赫洛德，不是大教堂")
assert(hint(cathedral, { cathedral, library, armory }):find("莫格萊尼", 1, true), "大教堂用雙王提示")
assert(stepOf(E, "05-d13", "turnin", 1048), "四名首領完成才在大教堂出本後交")
print("Horde 361/5083/4489/5652, Shadowfang, 1150 and Scarlet 1048 passed")
