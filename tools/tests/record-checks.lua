-- 遊戲內記錄的實測項目：NPC 列出的任務、持物條件物品掉落、上下船點與讀取畫面前後位置。
local handler, tick, enabled = nil, nil, true
local map, x, y, moving, target, bag = 1429, 48.0, 36.0, false, nil, {}
local available = {}
function CreateFrame()
  return {RegisterEvent=function() end, SetScript=function(_, _, fn) handler = fn end}
end
C_Timer = {NewTicker=function(_, fn) tick = fn end}
C_GossipInfo = {GetAvailableQuests=function() return available end}
function time() return 1700000000 end
function GetTime() return 0 end
function UnitLevel() return 2 end
function UnitXPMax() return 400 end
function UnitGUID(u) return u == "npc" and "Creature-0-1-2-3-951-0000" or nil end
function UnitName(u) if u == "npc" then return "Brother" end return target end
function UnitExists(u) return u == "target" and target ~= nil end
function UnitIsDead() return true end
function IsPlayerMoving() return moving end
function UnitOnTaxi() return false end
function IsFalling() return false end
function GetBindLocation() return nil end
function IsInInstance() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {db={}, UI={Get=function() return enabled end},
  Route={stations={{steps={{t="accept", q=91741, when={bag={item=247834, count=1}}}, {t="accept", q=7}}}},
    dungeons={{steps={{t="do", q=2930, when={bag={item=9280, count=1}}}}}}},
  C={Title=function() return "Quest" end, Position=function() return map, x, y end, Auras=function() return {} end},
  E={QuestXP=function() return 0 end, ItemCount=function(id) return bag[id] or 0 end},
  try=function(_, fn, ...) return fn(...) end}
assert(loadfile("addon/ShengLeveling/Rec.lua"))("ShengLeveling", ns)
local function fire(event, ...) handler(nil, event, ...) end
local function find(prefix)
  local out = {}
  for _, line in ipairs(MetroGuideRecDB.log) do
    if line:sub(1, #prefix) == prefix then out[#out + 1] = line end
  end
  return out
end

fire("PLAYER_ENTERING_WORLD", true, false)
assert(tick, "記錄開始時要有取樣計時器")
-- 背包本來就有的不算掉落
bag[9280] = 1
fire("BAG_UPDATE_DELAYED")
target = "Kobold"
for _ = 1, 3 do fire("LOOT_OPENED") end
bag[247834] = 1
fire("BAG_UPDATE_DELAYED")
local loot = find("loot\t")
assert(#loot == 1, "只記剛進背包的持物條件物品")
assert(loot[1]:find("^loot\t247834\tKobold\t3\t1429\t48\t36\t@\t"), loot[1])
assert(loot[1]:find("\t91741\t48.00\t36.00$"), loot[1])
-- 撿屍計數在記錄後歸零
fire("LOOT_OPENED")
bag[247834] = 0
fire("BAG_UPDATE_DELAYED")
bag[247834] = 1
fire("BAG_UPDATE_DELAYED")
assert(find("loot\t247834\tKobold\t1\t")[1], "第二次掉落從上次之後重新數")

-- NPC 列出的任務：排序後一行；沒有任務也記一次
available = {{questID=98240}, {questID=1838}}
fire("GOSSIP_SHOW")
assert(find("offer\t951\t1838;98240\t@\t")[1], "GOSSIP_SHOW 要記任務 ID")
available = {}
fire("GOSSIP_SHOW")
assert(find("offer\t951\t\t@\t")[1], "沒列任務也要記")
GetNumAvailableQuests = function() return 1 end
GetAvailableTitle = function() return "Brutal Armor" end
fire("QUEST_GREETING")
assert(find("offer\t951\tBrutal Armor\t@\t")[1], "QUEST_GREETING 記標題")
-- 秘密值不記
issecretvalue = function(v) return v == "secret" end
available = {{questID="secret"}}
local before = #MetroGuideRecDB.log
fire("GOSSIP_SHOW")
assert(#MetroGuideRecDB.log == before)
issecretvalue = nil

-- 站在碼頭（沒動），船開了：自己沒走位置卻在變
map, x, y = 1437, 4.50, 57.20
tick(); tick()
x = 4.20; tick()
x = 3.90; tick()
assert(find("board\t1437\t4\t57\t@\t")[1], "記上船前的位置")
x = 3.60; tick()
assert(#find("board\t") == 1, "同一趟只記一次")
-- 讀取畫面前後
fire("LOADING_SCREEN_ENABLED")
map, x, y = 1445, 70.0, 50.0
fire("PLAYER_ENTERING_WORLD", false, false)
assert(find("load\t1437\t3\t57\t1445\t@\t")[1], "換地圖時記讀取前後")
-- 船靠岸停住
tick()
x = 71.0; tick()
x = 72.0; tick()
tick()
assert(find("stop\t1445\t72\t50\t@\t")[1], "記船停下的點")
-- 自己走路不算被載
moving = true
x = 75.0; tick()
x = 78.0; tick()
x = 81.0; tick()
assert(#find("board\t") == 1)
-- 登入、重載不算換地圖
fire("LOADING_SCREEN_ENABLED")
fire("PLAYER_ENTERING_WORLD", false, true)
assert(#find("load\t") == 1)
-- 關掉記錄就不記
enabled = false
available = {{questID=5}}
fire("GOSSIP_SHOW")
assert(not find("offer\t951\t5\t")[1])
if arg[1] then
  local out = assert(io.open(arg[1], "w"))
  for _, line in ipairs(MetroGuideRecDB.log) do out:write(line, "\n") end
  out:close()
end
print("Recorder keeps NPC offers, start-item loot counts, boarding points and load-screen positions")
