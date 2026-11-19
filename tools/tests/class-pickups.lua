-- From the repository root: lua5.1 tools/tests/class-pickups.lua
-- 1.13.25 部落職業線補接：撿任務物品的步驟要背包裡真的有才算完成，墜飾兩塊都在才合成，
-- 交件與回程只在可交、真的要走時出現。
local env = { level = 1, active = {}, ready = {}, turned = {}, bags = {}, pos = {} }
local class, race, raceID = "DRUID", "Tauren", 6
function UnitFactionGroup() return "Horde" end
function UnitRace() return race, race, raceID end
function UnitClass() return class, class end
function UnitLevel() return env.level end
function GetItemCount(id) return env.bags[id] or 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {
  C = {
    IsOnQuest = function(q) return env.active[q] end,
    IsReady = function(q) return env.ready[q] end,
    IsFailed = function() return false end,
    Objectives = function(q) return env.ready[q] and {} or { { done = false } } end,
    Position = function() return env.pos[1], env.pos[2], env.pos[3] end,
    Bind = function() end,
    ZoneTexts = function() end,
    XPBuff = function() return false end,
    LogQuestIDs = function() local out = {} for q in pairs(env.active) do out[#out + 1] = q end return out end,
    IsTurnedIn = function(q) return env.turned[q] end,
  },
  L = setmetatable({}, { __index = function(_, key) return key end }),
  UI = { Get = function(key) return key == "optional" end },
  db = { skip = {}, mark = {}, latch = {}, dNo = {}, carry = {}, notNow = {}, pin = {}, drop = {}, fpNodes = {} },
}
for _, file in ipairs({ "Data/Route.lua", "Engine.lua" }) do assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns) end
local E = ns.E
E.Build()
local function reset(lv, active, bags, ready)
  env.level, env.active, env.bags, env.ready, env.turned = lv, active or {}, bags or {}, ready or {}, {}
  for k in pairs(ns.db.latch) do ns.db.latch[k] = nil end
end
local function find(station, pred)
  local state = E.Locate(E.byId[station])
  for i, step in ipairs(state.steps) do if pred(step.s) then return state, i, step.s end end
  error(station .. ": step missing")
end
local function pickOf(station, item)
  return find(station, function(s) return s.t == "buy" and s.pick and s.item == item end)
end
local function current(station)
  local state = E.Locate(E.byId[station])
  return state.auto and state.steps[state.auto].s
end

-- ── 牛頭人德魯伊水棲形態 ──
-- 第10站剛接 30、還沒有墜飾：不跳回合成，也不催交 30
reset(22, { [30] = true })
local cur = current("02-10")
assert(not (cur and cur.q == 30), "02-10：剛接 30 時不輪到合成或交件")
local _, _, combine = find("02-14", function(s) return s.t == "do" and s.q == 30 end)
local _, _, hand = find("02-14", function(s) return s.t == "turnin" and s.q == 30 end)
for _, bags in ipairs({ {}, { [15882] = 1 }, { [15883] = 1 } }) do
  reset(28, { [30] = true }, bags)
  assert(not E.Applies(combine.when), "02-14：少一塊墜飾不合成")
  assert(not E.Applies(hand.when), "02-14：未合成不催交")
end
reset(28, { [30] = true }, { [15882] = 1, [15883] = 1 })
assert(E.Applies(combine.when), "02-14：兩塊都在才合成")
reset(28, { [30] = true }, {}, { [30] = true })
assert(E.Applies(hand.when), "02-14：已合成（墜飾已耗用）照樣能交 30")
-- 撿墜飾：走到沉船、背包空的不算完成；撿到才算；重載後也一樣
for _, case in ipairs({ { "02-12", 15882, 1421, 29.56, 29.2 }, { "02-14", 15883, 1413, 56.67, 8.32 }, { "02-9", 15882, 1421, 29.56, 29.2 } }) do
  reset(25, { [30] = true })
  env.pos = { case[3], case[4], case[5] }
  local state, i, s = pickOf(case[1], case[2])
  assert(E.Verb(s) == "撿" and s.fq == 30, case[1] .. "：撿墜飾的步驟")
  assert(not state.done[i], case[1] .. "：到點空袋不算完成")
  env.pos = {}
  state, i = pickOf(case[1], case[2])
  assert(not state.done[i], case[1] .. "：離點重載仍未完成")
  env.bags = { [case[2]] = 1 }
  state, i = pickOf(case[1], case[2])
  assert(state.done[i], case[1] .. "：撿到才完成")
  reset(25, {})
  state, i = pickOf(case[1], case[2])
  assert(state.na[i], case[1] .. "：沒接 30 不顯示")
end

-- ── 術士地獄獵犬 ──
class, race, raceID = "WARLOCK", "Orc", 2
E.Build()
for _, station in ipairs({ "03-22", "03-15" }) do
  reset(38, { [1803] = true })
  env.pos = { 1424, 27.78, 72.79 }
  local state, i, s = pickOf(station, 6931)
  assert(s.fq == 1803 and not state.done[i], station .. "：到書的位置、背包空不算完成")
  env.pos = {}
  state, i = pickOf(station, 6931)
  assert(not state.done[i], station .. "：重載後仍未完成")
  env.bags = { [6931] = 1 }
  state, i = pickOf(station, 6931)
  assert(state.done[i], station .. "：撿到書才完成")
end
local _, _, toUC = find("03-25", function(s) return s.t == "travel" and s.when and s.when.readyQuest == 1803 end)
reset(41, { [1803] = true })
assert(not E.Applies(toUC.when), "03-25：1803 未完成不飛幽暗城")
reset(41, { [1803] = true }, {}, { [1803] = true })
assert(E.Applies(toUC.when), "03-25：1803 可交才飛幽暗城")
local _, _, acc1805 = find("03-25", function(s) return s.t == "accept" and s.q == 1805 end)
assert(acc1805.opt, "03-25：1805 接取是可跳過")
local _, _, back = find("03-25", function(s) return s.t == "travel" and s.x and s.map == 1418 end)
assert(back.when.onQuestAny[1] == 1805 and math.abs(back.x - 3.99) < 0.01, "03-25：回卡加斯的交通有卡加斯到點座標")
local _, _, tn1805 = find("04-34", function(s) return s.t == "turnin" and s.q == 1805 end)
reset(47, { [1805] = true })
assert(not E.Applies(tn1805.when), "04-34：1805 未完成不催交")
reset(47, { [1805] = true }, {}, { [1805] = true })
assert(E.Applies(tn1805.when), "04-34：1805 可交")

-- ── 盜賊 80411 ──
class, race, raceID = "ROGUE", "Orc", 2
E.Build()
local _, _, tn80411 = find("04-44", function(s) return s.t == "turnin" and s.q == 80411 end)
reset(54, { [80411] = true })
assert(not E.Applies(tn80411.when), "04-44：80411 未完成不指回拉文霍德")
reset(54, { [80411] = true }, {}, { [80411] = true })
assert(E.Applies(tn80411.when), "04-44：80411 可交才回莊園")
print("class-pickups: all passed")
