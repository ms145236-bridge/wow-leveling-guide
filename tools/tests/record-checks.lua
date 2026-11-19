-- 遊戲內記錄的實測項目：NPC 列出的任務、持物條件物品掉落、上下船點與讀取畫面前後位置。
local handler, tick, enabled, now = nil, nil, true, 0
local map, x, y, moving, falling, target, bag, lootSlots = 1429, 48.0, 36.0, false, false, nil, {}, {}
local available = {}
function CreateFrame()
  return {RegisterEvent=function() end, SetScript=function(_, _, fn) handler = fn end}
end
C_Timer = {NewTicker=function(_, fn) tick = fn end}
C_GossipInfo = {GetAvailableQuests=function() return available end}
function time() return 1700000000 end
function GetTime() return now end
function UnitLevel() return 2 end
function UnitXPMax() return 400 end
function UnitGUID(u) return u == "npc" and "Creature-0-1-2-3-951-0000" or nil end
function UnitName(u) if u == "npc" then return "Brother" end return target end
function UnitExists(u) return u == "target" and target ~= nil end
function UnitIsDead() return true end
function IsPlayerMoving() return moving end
function UnitOnTaxi() return false end
function IsFalling() return falling end
function GetBindLocation() return nil end
function IsInInstance() return false end
-- 撿屍視窗：每格 {物品 ID, 來源屍體 GUID}
function GetNumLootItems() return #lootSlots end
function GetLootSlotLink(i) return lootSlots[i] and lootSlots[i][1] and ("|Hitem:" .. lootSlots[i][1] .. "::|h[x]|h") end
local function sources(i)
  local s = lootSlots[i]
  if not s then return end
  if s[3] then return s[2], 1, s[3], 1 end
  return s[2], 1
end
GetLootSourceInfo = sources
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
local function kobold(n) return "Creature-0-1-2-3-6-" .. n end
-- 打開一具屍體：items 是這具屍體掉的物品；take＝全部拿走（觸發 LOOT_SLOT_CLEARED 與背包變化）
local function loot(guid, items, take)
  lootSlots = {}
  for _, id in ipairs(items or {}) do lootSlots[#lootSlots + 1] = { id, guid } end
  if #lootSlots == 0 then lootSlots[1] = { 2589, guid } end -- 一般掉落（亞麻布）
  fire("LOOT_OPENED")
  if take then
    for i, s in ipairs(lootSlots) do fire("LOOT_SLOT_CLEARED", i); bag[s[1]] = (bag[s[1]] or 0) + 1 end
  end
  fire("LOOT_CLOSED")
  if take then fire("BAG_UPDATE_DELAYED") end
end
local function drop(id) bag[id] = 0; fire("BAG_UPDATE_DELAYED") end

-- 登入時背包已有的不算；登入後第一個背包事件就是第一隻掉的也要記
bag[9280] = 1
fire("PLAYER_ENTERING_WORLD", true, false)
assert(tick, "記錄開始時要有取樣計時器")
loot(kobold(1), {247834}, true)
local rows = find("loot\t")
assert(#rows == 1, "登入後第一隻掉的要記，背包原有的不算")
assert(rows[1]:find("^loot\t247834\t6\t1\t1429\t48\t36\t@\t"), rows[1])
assert(rows[1]:find("\t91741\t48.00\t36.00$"), rows[1])
-- 第 3 隻才掉：前兩隻沒掉
drop(247834)
loot(kobold(2), nil, true); loot(kobold(3), nil, true); loot(kobold(4), {247834}, true)
assert(find("loot\t247834\t6\t3\t")[1], "從上次掉落之後重新數")
-- 同一次撿屍有兩件監看物品：兩筆都是同一個次數
drop(247834); drop(9280)
loot(kobold(5), nil, true); loot(kobold(6), {247834, 9280}, true)
assert(find("loot\t247834\t6\t2\t")[1] and find("loot\t9280\t6\t2\t")[1], "同次兩件不可出現第 0 次")
-- 重現 1：選著 A、撿的是 B：認屍體不認目標
drop(247834)
target = "Wolf"
loot("Creature-0-1-2-3-299-7", {247834}, true)
assert(find("loot\t247834\t299\t1\t")[1], "來源要認屍體 GUID")
target = nil
-- 重現 2：同一具屍體開關三次只算一隻
drop(247834)
x = 50.0
loot(kobold(8)); loot(kobold(8)); loot(kobold(8), {247834}, true)
assert(find("loot\t247834\t6\t1\t1429\t50\t")[1], "同一具屍體重開只算一次")
assert(not find("loot\t247834\t6\t3\t1429\t50\t")[1])
-- 重現 3：視窗有這件但沒拿就關掉，關記錄再開，之後背包才有：不記
drop(247834)
local before = #find("loot\t")
loot(kobold(9), {247834})
enabled = false; tick(); enabled = true
bag[247834] = 1
fire("BAG_UPDATE_DELAYED")
assert(#find("loot\t") == before, "關掉的視窗不能算來源")
-- 不是從屍體來的（沒有拿走的格子）不算
drop(247834)
bag[247834] = 1
fire("BAG_UPDATE_DELAYED")
assert(#find("loot\t") == before)
-- 讀不到來源：記「來源未確認」，怪物 ID 和次數留空
drop(247834)
GetLootSourceInfo = nil
loot(nil, {247834}, true)
assert(find("loot\t247834\t\t\t1429\t")[1], "沒來源就留空")
GetLootSourceInfo = sources
-- 一格有兩具屍體（同種怪也一樣）、或第二個來源是秘密值：來源未確認
local function multi(second, px)
  drop(247834)
  x = px
  lootSlots = { { 247834, kobold(20 + px), second } }
  fire("LOOT_OPENED"); fire("LOOT_SLOT_CLEARED", 1); bag[247834] = 1; fire("LOOT_CLOSED"); fire("BAG_UPDATE_DELAYED")
  assert(find("loot\t247834\t\t\t1429\t" .. px .. "\t")[1], "多來源要留空：" .. tostring(second))
end
multi(kobold(40), 60)
issecretvalue = function(v) return v == "secret" end
multi("secret", 61)
issecretvalue = nil
-- 同一具屍體兩件監看物品分兩次拿：兩筆都是同一個次數
x = 69
drop(247834); loot(kobold(49), {247834}, true) -- 先掉一次，次數從這裡重新數
drop(247834); drop(9280)
x = 70
loot(kobold(50), nil, true)
lootSlots = { { 247834, kobold(51) }, { 9280, kobold(51) } }
fire("LOOT_OPENED")
fire("LOOT_SLOT_CLEARED", 1); bag[247834] = 1; fire("BAG_UPDATE_DELAYED")
fire("LOOT_SLOT_CLEARED", 2); bag[9280] = 1; fire("BAG_UPDATE_DELAYED")
fire("LOOT_CLOSED")
assert(find("loot\t247834\t6\t2\t1429\t70\t")[1], "第一批")
assert(find("loot\t9280\t6\t2\t1429\t70\t")[1], "分兩批拿也要同一個次數")
-- 掉落之後重新數
drop(247834)
loot(kobold(52), {247834}, true)
assert(find("loot\t247834\t6\t1\t1429\t70\t")[1], "掉落後從 1 重新數")
x = 48.0

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
-- 秘密值不記（任務 ID、標題）
issecretvalue = function(v) return v == "secret" end
available = {{questID="secret"}}
local before = #MetroGuideRecDB.log
fire("GOSSIP_SHOW")
GetAvailableTitle = function() return "secret" end
fire("QUEST_GREETING")
assert(#MetroGuideRecDB.log == before, "秘密值整筆不記")
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
assert(find("stop\t1445\t72\t50\t@\t")[1]:find("\t72.00\t50.00\t0$"), "記船停下的點")
-- 自己走路不算被載
moving = true
x = 75.0; tick()
x = 78.0; tick()
x = 81.0; tick()
assert(#find("board\t") == 1)
moving = false
-- 跳船上岸：這一趟作廢，走到岸上停下不算停靠
map, x, y = 1437, 4.50, 57.20
tick(); tick()
x = 4.20; tick()
x = 3.90; tick()
falling = true; x = 7.00; tick()
falling, moving = false, true; x = 10.00; tick()
moving = false; tick()
assert(not find("stop\t1437\t10\t")[1], "跳船後走到的點不是停靠點")
-- 航行中自己走動過：停下的點標成候選
map, x, y = 1445, 20.0, 20.0
tick(); tick()
x = 20.5; tick()
x = 21.0; tick()
moving = true; x = 22.0; tick()
moving = false; x = 22.5; tick()
tick()
assert(find("stop\t1445\t22\t20\t@\t")[1]:find("\t1$"), "走動過的停點要標候選")
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
