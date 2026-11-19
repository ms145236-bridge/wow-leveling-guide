-- From the repository root: lua5.1 tools/tests/desolace-legacy.lua
-- 1.13.47 把聯盟 03-38 從 43 級的淒涼之地改成 35–37 級的新站（千針石林之後）。
-- 更新前的存檔：停在舊 03-38（40 級以上）的接第39站；已選第39站但還在淒涼之地的先爐藏寶海灣；
-- 舊第37站已坐船到棘齒城的先搭回藏寶海灣。新角色照新站走。
local active, turned = {}, {}
local me = { lv = 43 }
local position = { 1443, 64.7, 10.4 }
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "PRIEST", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return me.lv end
function GetItemCount() return 0 end
function UnitXPMax() return 100000 end
function UnitXP() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, drop={}, fpNodes={}, start="Human", station="03-38" }
local ns = { C={}, db=db, L={} }
ns.UI = { Get=function() return false end }
ns.C.IsOnQuest = function(q) return active[q] end
ns.C.IsReady = function() return false end
ns.C.IsTurnedIn = function(q) return turned[q] end
ns.C.XPBuff = function() return false end
ns.C.Position = function() return unpack(position) end
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
assert(E.byId["03-38"].lv[2] == 37 and E.Next(E.byId["03-38"]).id == "03-30", "03-38 is the 35–37 Desolace stop before Arathi")

-- 舊存檔：43 級停在 03-38 → 接第39站，只搬一次
assert(E.Current().id == "03-39" and db.station == "03-39" and db.desolace3537 == true)
db.station = "03-38"
assert(E.Current().id == "03-38", "the move happens once per save")

-- 新角色：36 級在新站，看過等級就記下，之後就算過了 40 也不搬
db.station, db.desolace3537, me.lv = "03-38", nil, 36
assert(E.Current().id == "03-38" and db.desolace3537 == true)
me.lv = 41
assert(E.Current().id == "03-38")

-- 還沒讀到等級（登入瞬間）不記號
db.station, db.desolace3537, me.lv = "03-38", nil, 1
E.Current()
assert(db.desolace3537 == nil)

-- 第39站開頭：還在淒涼之地 → 爐藏寶海灣；在棘齒城 → 搭船回藏寶海灣；已在藏寶海灣 → 直接接任務
me.lv = 43
local st = E.byId["03-39"]
local function current() -- 每個位置只看一次：走到碼頭範圍內，船的步驟就算完成
  local state = E.Locate(st)
  return state.steps[assert(state.cur)].s
end
position = { 1443, 64.7, 10.4 }
local s = current()
assert(s.t == "hearth" and s.bind == "藏寶海灣")
position = { 1413, 62.5, 35.5 }
s = current()
assert(s.t == "boat" and s.to == "藏寶海灣")
position = { 1434, 27.1, 77.2 }
s = current()
assert(s.t == "accept", "in Booty Bay the stop starts with its pickups")
-- 舊第38站從棘齒城飛石爪峰出發、人還在石爪山脈：先回藏寶海灣
position = { 1442, 36.45, 7.07 }
s = current()
assert(s.t == "travel" and s.text:find("石爪峰", 1, true), "Stonetalon start: hearth or fly back to Ratchet")
-- 新路線照常走：已在藏寶海灣接了 621，後來坐船到棘齒城，不會被返程的船拉回去
active[621] = true
position = { 1413, 62.5, 35.5 }
s = current()
assert(not (s.t == "boat" and s.to == "藏寶海灣") and s.t ~= "travel", "Ratchet later in the stop: no return boat")
active[621] = nil

-- 舊第38站去打副本（奧達曼），回主線時接第39站；目前的副本和進度不動
db.station, db.dungeonFrom, db.desolace3537, me.lv = "05-d9", "03-38", nil, 43
assert(E.Current().id == "05-d9" and db.dungeonFrom == "03-39" and db.desolace3537 == true)
db.station, db.dungeonFrom = db.dungeonFrom, nil -- UI「回主線」
assert(E.Current().id == "03-39")
-- 36 級從新第38站去打副本的不動
db.station, db.dungeonFrom, db.desolace3537, me.lv = "05-d9", "03-38", nil, 36
E.Current()
assert(db.dungeonFrom == "03-38")
print("Desolace 35–37 move: old saves continue at 03-39, Desolace and Ratchet returns, new characters stay")
