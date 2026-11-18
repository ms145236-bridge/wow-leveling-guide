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

-- 文字改寫的單點步驟沿用舊鍵：舊勾選、略過都還在
reset()
level = 50
race, raceID, db.start = "Human", 1, nil
E.Build()
local found = 0
for _, s0 in pairs(E.byId) do
  for _, step in ipairs(s0.list) do
    if step.s.skey and not step.s.vkeys then
      found = found + 1
      assert(step.key == s0.id .. "#" .. step.s.skey, step.key)
    end
  end
end
assert(found > 0)

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
print("merged-waypoints ok")
