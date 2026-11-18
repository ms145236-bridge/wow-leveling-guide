-- From the repository root: lua5.1 tools/tests/carry-later.lua
-- 跳站時，身上還沒交、但路線後面的站還會交的任務（例：416 逮補狗頭人在 02-12 交），不帶到新站要人補做；
-- 後面沒有再出現的任務（例：224 保衛國王的領土）照舊帶過去補。
local active, ready, turned, items, objs = {}, {}, {}, {}, {}
local me = { class = "PRIEST", lv = 12 }
function UnitFactionGroup() return "Alliance" end
function UnitClass() return me.class, me.class end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return me.lv end
function GetItemCount(id) return items[id] or 0 end
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
ns.C.Objectives = function(q) return objs[q] end
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
-- 存檔沒被顯示刪掉
assert(#db.carry["02-10"] == 2, "display must not delete saved carry entries")

-- 建議：直接從 01-9 跳過 416 交的 02-12 到 02-13，416 只帶一次；剛好落在 02-12 則不帶
wipe(active); wipe(ready); active[416], ready[416] = true, true
db.station = "01-9"
local function count(list, q) local c = 0 for _, x in ipairs(list) do if x == q then c = c + 1 end end return c end
assert(count(E.JumpPlan(E.byId["02-13"]), 416) == 1, "416 carried once when jumping past 02-12")
assert(count(E.JumpPlan(E.byId["02-12"]), 416) == 0, "416 not carried when landing on 02-12")
-- 舊存檔裡已經重複的只顯示一次
db.station = "02-13"
local function nCarry(saved)
  db.carry["02-13"] = saved
  local c = 0
  for _, step in ipairs(E.Locate(E.byId["02-13"]).steps) do if step.carry and step.s.q == 416 then c = c + 1 end end
  return c
end
local once = nCarry({ 416 })
assert(once > 0 and nCarry({ 416, 416 }) == once, "duplicate saved carry shown once")
print("carry-later: all passed")

-- 全路線掃描：每個橫跨兩個以上主線站的任務，在它前一站與後一站之間跳站時，身上有它、且後一站做得了剩下的事
-- （可交 → 後一站有「交」；未完成 → 後一站有「做」），就不該被帶到中間的站
local n, bad = 0, {}
for _, st in ipairs(E.stations) do
  if not st.dungeon then
    local seenQ = {}
    for _, step in ipairs(st.list) do
      local q = step.s.q
      if q and not seenQ[q] and E.Applies(step.s.when) then
        seenQ[q] = true
        -- 找下一個也有 q 的主線站
        for k = st.index + 2, #E.stations do
          local o = E.stations[k]
          local has = {}
          for _, s2 in ipairs(o.list) do if s2.s.q == q and E.Applies(s2.s.when) then has[s2.s.t] = true end end
          if next(has) then
            local mid = E.stations[st.index + 1]
            db.station = st.id
            for _, isReady in ipairs({ true, false }) do
              if has[isReady and "turnin" or "do"] and mid and not mid.dungeon then
                wipe(active); wipe(ready); active[q] = true; ready[q] = isReady or nil
                n = n + 1
                for _, x in ipairs(E.JumpPlan(mid)) do if x == q then bad[#bad + 1] = q .. " " .. st.id .. "->" .. mid.id end end
              end
            end
            break
          end
        end
      end
    end
  end
end
assert(#bad == 0, "carried although a later station handles it: " .. table.concat(bad, ", "))
print("carry-later sweep: " .. n .. " cross-station cases, none carried")

-- 在後面的站塞假步驟（改原始路線資料再重建）；回傳還原函式
local function inject(id, step)
  for _, st in ipairs(ns.Route.stations) do
    if st.id == id then
      table.insert(st.steps, step)
      E.Build()
      return function() table.remove(st.steps); E.Build() end
    end
  end
end
-- 必改 1：224 只在 01-9 接／做／交；後面 02-11 多一個重複的「接」，接不了已經在身上的任務，照樣要帶、離站照樣提醒
local undo = inject("02-11", { t = "accept", q = 224, map = 1432, x = 22.1, y = 73.1 })
wipe(active); wipe(ready); db.carry = {}
active[224], ready[224] = true, true
db.station = "01-9"
assert(count(E.JumpPlan(E.byId["02-10"]), 224) == 1, "ready 224: a later accept cannot turn it in, carry it")
local warned = false
for _, w in ipairs(E.Leaving(E.Locate(E.byId["01-9"]))) do if w.q == 224 then warned = true end end
assert(warned, "leaving 01-9 with ready 224 must warn: the only turn-in is here")
ready[224] = nil
assert(count(E.JumpPlan(E.byId["02-10"]), 224) == 1, "unfinished 224: a later accept cannot do it, carry it")
active[224] = nil
assert(count(E.JumpPlan(E.byId["02-10"]), 224) == 0, "224 not taken yet: the later accept takes over")
undo()
-- 必改 1：角色升級。戰士身上有可交的 1791，04-44 才交（lvMin 40）；39 級與 40 級從 03-38 跳 03-39 都不帶
me.class = "WARRIOR"; E.Build()
wipe(active); wipe(ready); active[1791], ready[1791] = true, true
db.station = "03-38"
for _, lv in ipairs({ 39, 40 }) do
  me.lv = lv
  assert(count(E.JumpPlan(E.byId["03-39"]), 1791) == 0, "1791 turned in at 04-44 (lv 46-47): not carried at level " .. lv)
end
me.class, me.lv = "PRIEST", 12; E.Build()
-- 必改 2：後面的「交」要物品；有物品時存檔的補做只是不顯示，物品丟了要再顯示
undo = inject("02-11", { t = "turnin", q = 224, map = 1432, x = 22.07, y = 73.13, when = { bag = { item = 99999, count = 1 } } })
wipe(active); wipe(ready); active[224], ready[224] = true, true
db.carry = { ["02-10"] = { 224 } }
db.station = "02-10"
local function shows(q) for _, step in ipairs(E.Locate(E.byId["02-10"]).steps) do if step.carry and step.s.q == q then return true end end end
items[99999] = 1
assert(not shows(224), "with the item, 02-11 turns 224 in: hidden")
assert(db.carry["02-10"][1] == 224, "hidden carry stays saved")
items[99999] = nil
assert(shows(224), "item lost: the saved carry of 224 shows again")
undo()
-- 本站有同任務但只有重複的「接」：存檔的補做要照樣展開「交」
undo = inject("02-10", { t = "accept", q = 224, map = 1432, x = 22.1, y = 73.1 })
wipe(active); wipe(ready); active[224], ready[224] = true, true
db.carry = { ["02-10"] = { 224 } }
db.station = "02-10"
local turnIn = false
for _, step in ipairs(E.Locate(E.byId["02-10"]).steps) do if step.carry and step.s.q == 224 and step.s.t == "turnin" then turnIn = true end end
assert(turnIn, "02-10 only re-offers 224: the carried turn-in still shows")
undo()
-- 必改 1（第二輪）：416 坑道鼠耳朵只在 01-9 收集，02-12 只有「交」。0/12 跳 02-10 要帶、離站要提醒；12/12 交給 02-12
wipe(active); wipe(ready); db.carry = {}
active[416] = true
db.station = "01-9"
local function warns(q) for _, w in ipairs(E.Leaving(E.Locate(E.byId["01-9"]))) do if w.q == q then return true end end end
objs[416] = { { text = "坑道鼠耳朵", have = 0, need = 12, done = false } }
assert(count(E.JumpPlan(E.byId["02-10"]), 416) == 1, "416 at 0/12: 02-12 only turns in, carry it")
assert(warns(416), "416 at 0/12: warn on leaving 01-9")
objs[416] = { { text = "坑道鼠耳朵", have = 12, need = 12, done = true } }
assert(count(E.JumpPlan(E.byId["02-10"]), 416) == 0, "416 at 12/12: 02-12 turns it in")
assert(not warns(416), "416 at 12/12: no warning")
objs[416] = nil
print("carry-later: only-later-accept, level-up, item-lost, same-station accept and 416 0/12 vs 12/12 cases passed")
