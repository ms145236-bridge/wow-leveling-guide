-- From the repository root: lua5.1 tools/tests/fp-step.lua
-- 開鳥點只看真的開了沒（飛行地圖／對話開點），不會被後面的進度帶過、也不會因為已到下一站就打勾。
local active, turnedQ, pos = {}, {}, { 1439, 36.6, 44.5 }
local who = { "Alliance", "Human", 1 }
function UnitFactionGroup() return who[1] end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return who[2], who[2], who[3] end
function UnitLevel() return 12 end
function UnitXPMax() return 8800 end
function UnitXP() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, drop={}, fpNodes={}, start="Human", station="02-10" }
local function load(route)
local ns = { C={}, db=db, L={} }
ns.UI = { Get=function() return false end }
ns.C.IsOnQuest = function(q) return active[q] end
ns.C.IsReady = function() return false end
ns.C.IsTurnedIn = function(q) return turnedQ[q] or false end
ns.C.XPBuff = function() return false end
ns.C.Position = function() return pos[1], pos[2], pos[3] end
ns.C.ZoneTexts = function() end
ns.C.Bind = function() end
ns.C.LogQuestIDs = function() local out = {} for q in pairs(active) do out[#out + 1] = q end return out end
ns.C.Objectives = function() end
ns.C.GreenRange = function() return 8 end
for _, file in ipairs({route, "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
ns.E.Build()
return ns.E
end
local E = load("Data/RouteA.lua")
local fails = 0
local function check(cond, what)
  if not cond then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end
end
local function reset(t, a, b) wipe(active); wipe(turnedQ); wipe(db.fpNodes); wipe(db.latch); wipe(db.mark); wipe(db.skip); pos[1], pos[2], pos[3] = t, a, b end
local function fpAt(state, node)
  for i, step in ipairs(state.steps) do if step.s.t == "fp" and step.s.node == node then return i end end
end
local function curT(state) local s = state.cur and state.steps[state.cur].s return s and (s.t .. " " .. tostring(s.q or s.node or "")) or "nil" end
local function missedFp(state)
  for _, m in ipairs(state.missed) do if state.steps[m.i].s.t == "fp" then return true end end
  return false
end

-- 奧伯丁（02-10）：人在碼頭、已接 963；只交 983、再交 3524、真的開點三種狀態
local st = assert(E.byId["02-10"])
for _, c in ipairs({ { "接 983/3524/963", {983, 3524, 963}, {} }, { "只交 983", {3524, 963}, {983} }, { "交 983 和 3524", {963, 1001, 4681}, {983, 3524} } }) do
  reset(1439, 36.6, 44.5)
  for _, q in ipairs(c[2]) do active[q] = true end
  for _, q in ipairs(c[3]) do turnedQ[q] = true end
  local state = E.Locate(st)
  local i = fpAt(state, "奧伯丁")
  check(state.cur == i and not state.done[i], "奧伯丁 " .. c[1] .. "：鳥點沒開就是目前步驟（目前 " .. curT(state) .. "）")
  check(not missedFp(state), "奧伯丁 " .. c[1] .. "：不進漏掉清單")
  db.fpNodes["奧伯丁"] = true
  state = E.Locate(st)
  check(state.done[i] and state.cur ~= i, "奧伯丁 " .. c[1] .. "：開了就算完成（目前 " .. curT(state) .. "）")
end

-- 站尾鳥點：本站任務都交完、人已在下一站的地圖 → 不打勾、不拉回去（本站完成好換站）；人還在本站 → 輪到鳥點
-- 本站別的鳥點都開了，只看這一個
local function allTurned(s, node)
  for _, step in ipairs(s.list) do
    if step.s.q then turnedQ[step.s.q] = true end
    if step.s.t == "fp" and step.s.node ~= node then db.fpNodes[step.s.node] = true end
  end
end
for _, c in ipairs({ { "01-2", "鐵爐堡", 1455, 55, 48 }, { "02-13", "魯瑟蘭村", 1438, 58, 90 } }) do
  local s = assert(E.byId[c[1]])
  local nxt = assert(E.Next(s))
  reset(nxt.map, 50, 50)
  allTurned(s, c[2])
  local state = E.Locate(s)
  local i = fpAt(state, c[2])
  check(not state.done[i] and not state.autoDone[i], c[1] .. " " .. c[2] .. "：人在下一站地圖、沒開點 → 不打勾")
  check(state.complete and not state.cur, c[1] .. " " .. c[2] .. "：不拉回去，本站完成（目前 " .. curT(state) .. "）")
  reset(c[3], c[4], c[5])
  allTurned(s, c[2])
  state = E.Locate(s)
  for j = 1, i - 1 do if state.tails[j] and state.steps[j].s.t == "travel" then db.mark[state.steps[j].key] = true end end -- 前面的站尾交通（搭地鐵）玩家已勾
  state = E.Locate(s)
  check(state.cur == i and not state.complete, c[1] .. " " .. c[2] .. "：人還在本站 → 輪到開鳥點（目前 " .. curT(state) .. "）")
  db.fpNodes[c[2]] = true
  state = E.Locate(s)
  check(state.done[i], c[1] .. " " .. c[2] .. "：開了就打勾")
end

-- 鳥點和下一站同一張地圖：人就站在鳥點旁，還是要帶去開點，不能當成已離站
local function sameMap(id, node, m, px, py)
  local s = assert(E.byId[id])
  check(E.Next(s).map == m, id .. " 下一站也在地圖 " .. m)
  reset(m, px, py)
  allTurned(s, node)
  local state = E.Locate(s)
  local i = fpAt(state, node)
  for j = 1, i - 1 do if state.tails[j] and not state.done[j] and state.steps[j].s.t ~= "fp" then db.mark[state.steps[j].key] = true end end
  state = E.Locate(s)
  check(state.cur == i and not state.done[i] and not state.complete, id .. " " .. node .. "：站在鳥點旁、和下一站同地圖 → 輪到開鳥點（目前 " .. curT(state) .. "）")
  db.fpNodes[node] = true
  state = E.Locate(s)
  check(state.done[i] and state.cur ~= i, id .. " " .. node .. "：開了才打勾（目前 " .. curT(state) .. "）")
end
sameMap("03-32", "塞拉摩", 1445, 67, 51)

-- 一般站尾交通：人到了下一站的地圖就算到了
local s12 = E.byId["01-2"]
reset(E.Next(s12).map, 50, 50)
allTurned(s12, "")
db.fpNodes["鐵爐堡"] = true
local state = E.Locate(s12)
local tr
for i, step in ipairs(state.steps) do if step.s.t == "travel" and state.tails[i] then tr = i end end
check(tr and state.done[tr], "01-2 站尾交通：到了下一站地圖就算到了")

-- 部落：獸人 01-2 站在十字路口飛行管理員旁，下一站 02-8 也在貧瘠之地
who[1], who[2], who[3] = "Horde", "Orc", 2
db.start = "Orc"
E = load("Data/Route.lua")
sameMap("01-2", "十字路口", 1413, 51.5, 30.34)
if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("fp-step: all passed")
