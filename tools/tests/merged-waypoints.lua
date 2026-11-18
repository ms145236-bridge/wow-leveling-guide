-- From the repository root: lua5.1 tools/tests/merged-waypoints.lua
-- Merged waypoint chains (one travel step with via points) and boat steps that carry the dock coordinate:
-- old saves keep their progress, a player standing at a later point continues from there,
-- new characters walk the points in order, and a boat already taken never points back to the dock.
local race, raceID, level = "Dwarf", 3, 10
local active, turnedIn, position = {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Mage", "MAGE" end
function UnitRace() return race, race, raceID end
function UnitLevel() return level end
function UnitXPMax() return 7600 end
function UnitXP() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}, start="Dwarf/Gnome" }
local ns = { C={}, db=db, UI={Get=function() return false end}, L={} }
ns.C.IsOnQuest = function(q) return active[q] end
ns.C.IsReady = function() return false end
ns.C.IsTurnedIn = function(q) return turnedIn[q] end
ns.C.XPBuff = function() return false end
ns.C.Position = function() return unpack(position) end
ns.C.ZoneTexts = function() end
ns.C.Bind = function() end
ns.C.LogQuestIDs = function() return {} end
ns.C.Objectives = function() end
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
local function reset()
  for _, t in ipairs({db.skip, db.mark, db.latch, db.pin, active, turnedIn}) do wipe(t) end
end

-- 丹莫洛翻山（01-9）：四個點合成一步，舊鍵是最後一點
local function climbSetup()
  E.Build()
  local st = E.byId["01-9"]
  local at
  for i, step in ipairs(st.list) do
    if step.s.via and step.s.skey == "goto:沿路跑到這個點。@83,50" then at = i; break end
  end
  assert(at, "climb step missing")
  -- 遊戲裡用世界座標 50 碼（丹莫洛約 1%）判斷到達；測試沒有 C_Map，改用 0.5% 半徑，免得相鄰的山稜點互相算到
  st.list[at].s.r = 0.5
  -- 前面的任務都交了：輪到翻山
  for i = 1, at - 1 do db.mark[st.list[i].key] = true end
  return st, st.list[at]
end
local function cur(st)
  local state = E.Locate(st)
  return state.steps[assert(state.cur)]
end

-- 新角色：照順序走，箭頭一點一點往前，走到最後一點才完成
reset()
local st, climb = climbSetup()
assert(climb.key == "01-9#goto:沿路跑到這個點。@83,50", climb.key)
position = {1426, 70, 50}
assert(cur(st) == climb)
local pts = { { climb.s.map, climb.s.x, climb.s.y } }
for _, p in ipairs(climb.s.via) do pts[#pts + 1] = p end
assert(#pts == 4)
for k = 1, 4 do
  local t = E.ViaTarget(climb)
  assert(t[2] == pts[k][2] and t[3] == pts[k][3], "arrow should point at point " .. k)
  position = { pts[k][1], pts[k][2], pts[k][3] }
  local c = cur(st)
  if k < 4 then assert(c == climb, "still climbing after point " .. k) else assert(c ~= climb and c.s.q == 224, "accept 224 after the last point") end
end

-- 舊存檔：四個舊單點都走過（最後一點有勾）→ 合併後的那步已完成，不拉回第一點
reset()
st, climb = climbSetup()
db.latch["01-9#goto:沿路跑到這個點。@79,50"] = true
db.latch["01-9#goto:沿路跑到這個點。@80,50"] = true
db.latch["01-9#goto:沿路跑到這個點。@82,50"] = true
db.latch["01-9#goto:沿路跑到這個點。@83,50"] = true
E.Build()
position = {1426, 70, 50}
assert(cur(st).s.q == 224, "old save with the chain done should be past it")
-- 舊存檔只走到第二點：接著指第三點
reset()
st, climb = climbSetup()
db.latch["01-9#goto:沿路跑到這個點。@79,50"] = true
db.mark["01-9#goto:沿路跑到這個點。@80,50"] = true
E.Build()
st, climb = E.byId["01-9"], nil
for _, step in ipairs(st.list) do if step.s.skey == "goto:沿路跑到這個點。@83,50" then climb = step end end
position = {1426, 70, 50}
assert(cur(st) == climb)
assert(E.ViaTarget(climb)[2] == pts[3][2], "old save at point 2 continues at point 3")
-- 舊存檔略過最後一點：照樣略過
reset()
st, climb = climbSetup()
db.skip["01-9#goto:沿路跑到這個點。@83,50"] = true
position = {1426, 70, 50}
assert(cur(st).s.q == 224, "old skip carries over")

-- 矮人已經翻過山、站在洛克莫丹的巡山人旁（新存檔）：可以接 224，不拉回丹莫洛第一點
reset()
st, climb = climbSetup()
position = {1432, 22.1, 73.1}
assert(cur(st).s.q == 224, "standing at the mountaineer should skip the climb")
-- 從山稜尾端進來（最後一點）：直接算翻過了
reset()
st, climb = climbSetup()
position = { pts[4][1], pts[4][2], pts[4][3] }
assert(cur(st).s.q == 224, "entering at the end of the ridge finishes the climb")

-- 安戈洛蟲巢（04-48）：從洞口進去採樣；人已經在洞裡（第二點）就不拉回洞口
local function chainSetup(id, skey)
  E.Build()
  local s0 = E.byId[id]
  for i, step in ipairs(s0.list) do
    if step.s.skey == skey then
      for j = 1, i - 1 do db.mark[s0.list[j].key] = true end
      return s0, step
    end
  end
  error(id .. " chain missing")
end
race, raceID, db.start, level = "Human", 1, nil, 52
reset()
local hive, inside = chainSetup("04-48", "goto:沿路跑到這個點。@49,85")
position = {1449, 55, 75}
assert(cur(hive) == inside, "hive entrance is the current step")
assert(E.ViaTarget(inside)[2] == inside.s.x, "arrow at the entrance first")
position = { inside.s.via[1][1], inside.s.via[1][2], inside.s.via[1][3] }
assert(cur(hive) ~= inside, "already inside the hive: the chain is done")
race, raceID, db.start, level = "Dwarf", 3, "Dwarf/Gnome", 10

-- 舊鍵回歸：下面這些是改版前 main（f08c041）實際建出的 Data/RouteA.lua 裡、這次改寫或合併的步驟的存檔鍵
-- （lua5.1 的 %.0f 進位，例如 30.5 → 30）。每一個都要對到現在某一步的鍵或它的舊鍵，存檔才不會掉
reset()
level = 50
race, raceID, db.start = "Human", 1, nil
E.Build()
local OLD_KEYS = {
  "01-3#goto:沿路跑到這個點。@26,68",
  "01-5#goto:沿路跑到這個點。@58,42",
  "01-8#buy:閃光的小珠",
  "01-8#buy:夜色蟲",
  "01-9#goto:沿路跑到這個點。@83,50",
  "01-9#goto:沿路跑到這個點。@79,50",
  "01-9#goto:沿路跑到這個點。@80,50",
  "01-9#goto:沿路跑到這個點。@82,50",
  "02-13#goto:沿路跑到這個點。@51,25~2",
  "02-13#goto:沿路跑到這個點。@51,25",
  "02-21#goto:沿路跑到這個點。@34,41",
  "02-20#goto:沿路跑到這個點。@44,50",
  "02-20#goto:沿路跑到這個點。@47,52",
  "02-20#goto:沿路跑到這個點。@47,49",
  "02-20#travel:穿過山洞進石爪山脈。",
  "02-20#goto:沿路跑到這個點。@42,71",
  "03-22#goto:沿路跑到這個點。@56,53",
  "03-23#goto:沿路跑到這個點。@32,51",
  "03-23#goto:沿路跑到這個點。@32,49",
  "03-23#goto:沿路跑到這個點。@31,49",
  "03-28#goto:沿路跑到這個點。@54,33",
  "03-28#goto:沿路跑到這個點。@64,44",
  "03-29#goto:沿路跑到這個點。@32,24",
  "03-32#goto:沿路跑到這個點。@51,29",
  "03-33#goto:沿路跑到這個點。@60,41",
  "03-34#goto:沿路跑到這個點。@30,54",
  "03-41#goto:沿路跑到這個點。@72,64",
  "03-41#goto:沿路跑到這個點。@73,64",
  "04-43#goto:沿路跑到這個點。@56,72",
  "04-43#goto:沿路跑到這個點。@55,70",
  "04-43#goto:沿路跑到這個點。@54,73",
  "04-44#goto:沿路跑到這個點。@85,32",
  "04-44#goto:沿路跑到這個點。@47,78",
  "04-47#goto:沿路跑到這個點。@27,57",
  "04-48#goto:沿路跑到這個點。@49,85",
  "04-48#goto:沿路跑到這個點。@50,79",
  "04-49#goto:沿路跑到這個點。@66,3",
  "04-55#goto:沿路跑到這個點。@65,87",
}
local known = {}
for _, s0 in ipairs(ns.Route.stations) do
  for _, s in ipairs(s0.steps) do
    if s.skey then known[s0.id .. "#" .. s.skey] = true end
    for _, a in ipairs(s.akeys or {}) do known[s0.id .. "#" .. a] = true end
    for _, g in ipairs(s.vkeys or {}) do for _, a in ipairs(g) do known[s0.id .. "#" .. a] = true end end
  end
end
for _, k in ipairs(OLD_KEYS) do assert(known[k], "old save key not carried over: " .. k) end
for _, s0 in pairs(E.byId) do
  for _, step in ipairs(s0.list) do
    if step.s.skey then assert(step.key == s0.id .. "#" .. step.s.skey, step.key) end
  end
end
-- 黑海岸瀑布（02-13）兩個舊點合成一點：任一個舊點有勾都算到
reset()
db.latch["02-13#goto:沿路跑到這個點。@51,25"] = true
E.Build()
for _, step in ipairs(E.byId["02-13"].list) do
  if step.s.skey == "goto:沿路跑到這個點。@51,25~2" then assert(db.latch[step.key], "02-13 first old point carries over") end
end
-- 迷霧谷（03-34）：舊鍵是 @30,54
reset()
db.skip["03-34#goto:沿路跑到這個點。@30,54"] = true
E.Build()
local mist
for _, step in ipairs(E.byId["03-34"].list) do if step.s.skey then mist = step end end
assert(mist.key == "03-34#goto:沿路跑到這個點。@30,54" and db.skip[mist.key], "Mistvale old skip carries over")

-- 搭船：碼頭座標放在船那步，沒有另一個「到碼頭」的步驟；船的鍵和以前一樣
local boats = 0
for _, s0 in pairs(E.byId) do
  for i, step in ipairs(s0.list) do
    local s = step.s
    if s.t == "boat" then
      assert(not step.key:find("@", 1, true), "boat key must not change: " .. step.key)
      local prev = s0.list[i - 1]
      assert(not (prev and prev.s.t == "travel" and s.x and prev.s.x == s.x and prev.s.y == s.y), "separate dock step before " .. step.key)
      if s.x then boats = boats + 1 end
    end
  end
end
assert(boats >= 2, "boat steps with a dock coordinate")
-- 02-20 第一步就是船：舊存檔已搭過（船那步有勾）→ 不指回暴風城港口
reset()
active[994] = true
E.Build()
local ash = E.byId["02-20"]
assert(ash.list[1].s.t == "boat" and ash.list[1].key == "02-20#boat:奧伯丁")
position = {1453, 60, 60}
assert(cur(ash) == ash.list[1] and ash.list[1].s.map == 1453, "not yet boarded: arrow to the Stormwind dock")
db.latch["02-20#boat:奧伯丁"] = true
assert(cur(ash) ~= ash.list[1], "boat already taken")
-- 沒勾但人已經在奧伯丁要交 994 的地方：船那步算過了
db.latch["02-20#boat:奧伯丁"] = nil
position = {1439, 39.37, 43.48}
assert(cur(ash) ~= ash.list[1], "already across: no pointing back to the dock")
-- 南海鎮那班（04-53）：改從暴風城上船也行，箭頭的候選點有暴風城港口
local hills = E.byId["04-53"]
local alt
for _, step in ipairs(hills and hills.list or {}) do
  if step.s.t == "boat" and step.s.map == 1424 then alt = step.s end
end
assert(alt and alt.more and alt.more[1][1] == 1453, "Southshore boat lists the Stormwind dock as an alternative")

-- 下船後才登入（船那步沒勾、994 還沒接）：人在奧伯丁，不指回暴風城港口
reset()
E.Build()
ash = E.byId["02-20"]
position = {1439, 45, 60}
assert(cur(ash) ~= ash.list[1], "logged in at Auberdine: boat counts as taken")
-- 還在暴風城等船：照舊指暴風城碼頭
reset()
E.Build()
position = {1453, 21.8, 56.8}
assert(cur(ash) == ash.list[1], "waiting at the Stormwind dock")
-- 南海鎮那班：在南海鎮或暴風城等船都還是船那步；到了黑海岸就算搭過
local function boatOf(s0)
  for i, step in ipairs(s0.list) do if step.s.t == "boat" and step.s.map == 1424 then return i, step end end
end
reset()
E.Build()
hills = E.byId["04-53"]
local bi, boat = boatOf(hills)
for i = 1, bi - 1 do db.mark[hills.list[i].key] = true end
position = {1424, 50.7, 70.5}
assert(cur(hills) == boat, "waiting at Southshore")
position = {1453, 21.8, 56.8}
assert(cur(hills) == boat, "waiting at Stormwind harbor (alternative)")
position = {1439, 45, 60}
assert(cur(hills) ~= boat, "arrived in Darkshore from either port")

-- 舊版釘選：釘在翻山第二點 → 釘到合併後那步，箭頭指第二點（走過的進度不變）
race, raceID, db.start, level = "Dwarf", 3, "Dwarf/Gnome", 10
reset()
st, climb = climbSetup()
db.pin["01-9"] = { key = "01-9#goto:沿路跑到這個點。@80,50", wasDone = false, auto = "01-9#goto:沿路跑到這個點。@79,50" }
E.Build()
st = E.byId["01-9"]
for _, step in ipairs(st.list) do if step.s.skey == "goto:沿路跑到這個點。@83,50" then climb = step end end
position = {1426, 70, 50}
assert(cur(st) == climb, "pinned merged step is current")
assert(db.pin["01-9"] and db.pin["01-9"].key == climb.key and db.pin["01-9"].via == 2, "old pin moved to the merged step")
assert(E.ViaTarget(climb)[2] == pts[2][2], "arrow at the pinned point 2")
assert(not db.latch[climb.key .. "@1"], "pinning does not count as walking")
-- 釘在最後一點（鍵沒變）：箭頭指最後一點，不是第一點
reset()
st, climb = climbSetup()
db.pin["01-9"] = { key = climb.key, wasDone = false, auto = "01-9#goto:沿路跑到這個點。@79,50" }
E.Build()
st = E.byId["01-9"]
for _, step in ipairs(st.list) do if step.s.skey == "goto:沿路跑到這個點。@83,50" then climb = step end end
assert(cur(st) == climb)
assert(E.ViaTarget(climb)[2] == pts[4][2], "arrow at the pinned last point")
-- 新版釘選（via = false）不會被當成舊釘選
reset()
st, climb = climbSetup()
db.pin["01-9"] = { key = climb.key, wasDone = false, auto = "", via = false }
E.Build()
assert(db.pin["01-9"].via == false)

-- 舊版釘在第 1／2／3 點、釘的時候還沒走到：走到那一點就放開（和舊版走到那個單點一樣），回到正常進度
for v = 1, 3 do
  reset()
  st, climb = climbSetup()
  local oldKey = ({ "01-9#goto:沿路跑到這個點。@79,50", "01-9#goto:沿路跑到這個點。@80,50", "01-9#goto:沿路跑到這個點。@82,50" })[v]
  db.pin["01-9"] = { key = oldKey, wasDone = false, auto = "01-9#goto:沿路跑到這個點。@79,50" }
  E.Build()
  st = E.byId["01-9"]
  for _, step in ipairs(st.list) do if step.s.skey == "goto:沿路跑到這個點。@83,50" then climb = step end end
  position = {1426, 70, 50}
  assert(cur(st) == climb and db.pin["01-9"].via == v)
  assert(E.ViaTarget(climb)[2] == pts[v][2], "arrow at pinned point " .. v)
  position = { pts[v][1], pts[v][2], pts[v][3] }
  cur(st)
  assert(db.pin["01-9"] == nil, "pin released on reaching pinned point " .. v)
  assert(E.ViaTarget(climb)[2] == pts[v + 1][2], "after release the arrow follows normal progress")
end
-- 舊版釘在已走過的第 1 點（重看）：不放開，箭頭一直指那點
reset()
st, climb = climbSetup()
db.latch["01-9#goto:沿路跑到這個點。@79,50"] = true
db.pin["01-9"] = { key = "01-9#goto:沿路跑到這個點。@79,50", wasDone = true, auto = "01-9#goto:沿路跑到這個點。@80,50" }
E.Build()
st = E.byId["01-9"]
for _, step in ipairs(st.list) do if step.s.skey == "goto:沿路跑到這個點。@83,50" then climb = step end end
position = {1426, 70, 50}
assert(cur(st) == climb and db.pin["01-9"], "re-view pin kept")
assert(E.ViaTarget(climb)[2] == pts[1][2], "re-view pin points at the walked point")

-- 舊版手動略過（真的 E.ToggleSkip）：升級後是新鍵上的手動略過，重算不會清掉；取消後重登不會被舊值蓋回
race, raceID, db.start, level = "Human", 1, nil, 20
reset()
E.Build()
local fallOld = "02-13#goto:沿路跑到這個點。@51,25"
E.ToggleSkip(fallOld)
assert(db.skip[fallOld] == fallOld)
E.Build()
local fall
for _, step in ipairs(E.byId["02-13"].list) do if step.s.skey == "goto:沿路跑到這個點。@51,25~2" then fall = step end end
assert(db.skip[fall.key] == fall.key and db.skip[fallOld] == nil, "manual skip root moved to the new key")
E.RecomputeSkip()
assert(db.skip[fall.key] == fall.key, "manual skip survives RecomputeSkip on login")
E.ToggleSkip(fall.key)
assert(db.skip[fall.key] == nil)
E.Build(); E.RecomputeSkip()
assert(db.skip[fall.key] == nil, "un-skip survives relog")
-- 舊勾選：搬到新鍵後取消勾選，重登不會被舊值蓋回
reset()
db.mark[fallOld] = true
E.Build()
assert(db.mark[fall.key] == true and db.mark[fallOld] == nil)
E.SetMark(fall.key, nil)
E.Build()
assert(db.mark[fall.key] == nil, "un-tick survives relog")
race, raceID, db.start, level = "Dwarf", 3, "Dwarf/Gnome", 10

-- 換區載入中：只有地圖、還沒座標，不報錯也不亂判
reset()
st, climb = climbSetup()
position = {1432}
assert(cur(st) == climb, "no coordinates yet: stay on the climb")
position = {1432, 22.1, 73.1}
assert(cur(st).s.q == 224)
print("merged-waypoints ok")
