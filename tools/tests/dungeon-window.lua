-- 副本前置順路接取：從接取錨點站到副本插入站，每一步排進第一個順路的主線站（1.13.50）
local function load(faction, race)
  function UnitFactionGroup() return faction end
  function UnitClass() return "Warrior", "WARRIOR" end
  function UnitRace() return race, race, 0 end
  function UnitLevel() return 60 end
  function UnitXP() return 0 end
  function UnitXPMax() return 10000 end
  function GetTime() return 100 end
  function wipe(t) for k in pairs(t) do t[k] = nil end end
  local ns = {
    C = {IsOnQuest=function() return false end, IsReady=function() return false end,
         IsTurnedIn=function() return false end, LogQuestIDs=function() return {} end,
         XPBuff=function() return false end, Position=function() end, ZoneTexts=function() end,
         Bind=function() end, Objectives=function() end},
    db = {skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, dDismiss={}, fpNodes={}},
    UI = {Get=function(k) return k == "optional" or k == "dPre" end},
    L = setmetatable({}, {__index=function(_, key) return key end}),
    msg = function() end, try = function(_, f, ...) return f(...) end,
  }
  for _, file in ipairs({faction == "Horde" and "Data/Route.lua" or "Data/RouteA.lua", "Engine.lua"}) do
    assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
  end
  ns.E.Build()
  -- 每站顯示的步驟；inserted[任務 .. 動作] = 第一個插入它的站
  local rows, inserted = {}, {}
  for _, st in ipairs(ns.E.stations) do
    ns.db.station = st.id
    rows[st.id] = ns.E.Locate(st).steps
    for i, w in ipairs(rows[st.id]) do
      local key = w.dungeon and w.s.q and (w.dungeon.id .. ":" .. w.s.t .. ":" .. w.s.q)
      if key and not inserted[key] then inserted[key] = { st = st.id, i = i } end
    end
  end
  return rows, inserted
end
local function index(list, t, q, dungeon)
  for i, w in ipairs(list) do
    if w.s.t == t and w.s.q == q and (dungeon == nil or (w.dungeon and w.dungeon.id) == dungeon) then return i end
  end
end

-- 聯盟
local rows, at = load("Alliance", "Human")
-- 領主大廳：01-9 錨點不在人類路線，第11站回鐵爐堡時接 96394、96403
assert(at["05-d1:accept:96394"] and at["05-d1:accept:96394"].st == "02-11", "Hall of Thanes 96394 joins the Ironforge visit")
assert(at["05-d1:accept:96403"] and at["05-d1:accept:96403"].st == "02-11")
-- 諾莫瑞根：03-23 到鐵爐堡時接 2924
assert(at["05-d7:accept:2924"] and at["05-d7:accept:2924"].st == "03-23", "Gnomeregan 2924 joins the Ironforge visit")
-- 同站主線交前置：704 排在主線交 739 之後
local s35 = rows["03-35"]
assert(index(s35, "accept", 704, "05-d9") > index(s35, "turnin", 739), "704 waits for the mainline 739 hand-in")
-- 前置要到菲拉斯做（「做」沒座標）：3527 不提早插
assert(not at["05-d10:accept:3527"], "3527 needs 3520 done in Feralas first")
-- 深淵中的知識：第13到20站都沒經過鐵爐堡，留在副本頁
assert(not at["05-d5:accept:971"], "971 stays on the dungeon card")
-- 死亡礦坑（1.13.49）照舊：交 155 後接 166、214
local s14 = rows["02-14"]
assert(index(s14, "accept", 166, "05-d3") > index(s14, "turnin", 155))

-- 部落
rows, at = load("Horde", "Orc")
-- 黑暗深淵：第14站佐拉姆海岸交 824 後接 6563、6921
local h14 = rows["02-14"]
assert(at["05-d8:accept:6563"] and at["05-d8:accept:6563"].st == "02-14")
assert(index(h14, "accept", 6563, "05-d8") > index(h14, "turnin", 824))
-- 黑石深淵：3907／7201／3981 等主線第42站交 3906 才接，不再第34站提早插
for _, q in ipairs({3907, 7201, 3981}) do
  assert(at["05-d24:accept:" .. q] and at["05-d24:accept:" .. q].st == "04-42", "BRD " .. q .. " waits for 3906")
  assert(index(rows["04-42"], "accept", q, "05-d24") > index(rows["04-42"], "turnin", 3906))
end
-- 主線進本前本來就會帶的不提早插（克羅多克 94744 在第28站）
assert(not at["05-d19:accept:94744"])
-- 要打精英的「做」留給有隊伍的人（哀嚎洞穴 瘋狂的馬格利什）
assert(not at["05-d4:do:959"], "elite objective stays group content")
-- 怒焰裂谷：骷髏石的掉落不順路，交 5726 之後的步驟不提早插
assert(at["05-d1:accept:5726"] and not at["05-d1:turnin:5726"] and not at["05-d1:accept:5728"])
-- 通靈學院：火羽山在安戈洛，交 5802 不在亡靈壁壘提早插
assert(not at["05-d32:turnin:5802"] and not at["05-d32:accept:5511"])
-- 錨點站（亡靈新手區）不在獸人路線：羅德隆廢墟改在插入站（第9站）幽暗城接
assert(at["05-d3:accept:92421"] and at["05-d3:accept:92421"].st == "02-9")
print("Dungeon prerequisites are placed on the way from the anchor to the dungeon")

-- 等級與日誌狀態在兩次順路之間變了（Astra 審查 #46）：前面的站排過但沒真的接，之後順路的站再排；已交的前置看遊戲狀態
do
  local lv, turnedQ, onQ = 49, {}, {}
  function UnitFactionGroup() return "Horde" end
  function UnitClass() return "Warrior", "WARRIOR" end
  function UnitRace() return "Orc", "Orc", 2 end
  function UnitLevel() return lv end
  function UnitXP() return 0 end
  function UnitXPMax() return 10000 end
  function GetTime() return 100 end
  function wipe(t) for k in pairs(t) do t[k] = nil end end
  local ns = {
    C = {IsOnQuest=function(q) return onQ[q] end, IsReady=function() return false end,
         IsTurnedIn=function(q) return turnedQ[q] end, LogQuestIDs=function() return {} end,
         XPBuff=function() return false end, Position=function() end, ZoneTexts=function() end,
         Bind=function() end, Objectives=function() end},
    db = {skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, dDismiss={}, fpNodes={}},
    UI = {Get=function(k) return k == "optional" or k == "dPre" end},
    L = setmetatable({}, {__index=function(_, key) return key end}),
    msg = function() end, try = function(_, f, ...) return f(...) end,
  }
  for _, file in ipairs({"Data/Route.lua", "Engine.lua"}) do
    assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
  end
  local E = ns.E
  E.Build()
  local function shown(id, t, q)
    ns.db.station = id
    local state = E.Locate(E.byId[id])
    return index(state.steps, t, q, "05-d24") or index(state.steps, t, q, "05-d28")
  end
  -- 49 級經卡加斯（04-34）接不到 4134（50 級），53 級回卡加斯（04-42）要再提示
  assert(not shown("04-34", "accept", 4134), "4134 needs level 50")
  lv = 53
  assert(shown("04-42", "accept", 4134), "4134 shows again at the next Kargath visit")
  -- 04-34 已接（例如之前日誌預留延後、這次才接）：04-42 不重複
  onQ[4134] = true
  assert(not shown("04-42", "accept", 4134), "an accepted pickup is not repeated")
  onQ[4134] = nil
  -- 菲拉斯：52 級到莫沙徹（04-39）接不到 7441／7489，55 級回莫沙徹（04-48）再提示
  lv = 52
  assert(not shown("04-39", "accept", 7441) and not shown("04-39", "accept", 7489), "7441/7489 need level 54")
  lv = 55
  assert(shown("04-48", "accept", 7441) and shown("04-48", "accept", 7489), "7441/7489 show at the next Camp Mojache visit")
  -- 自己已交 3906 的 49 級：04-34 卡加斯就接 3907／7201，不等主線第42站
  lv, turnedQ[3906] = 49, true
  assert(shown("04-34", "accept", 3907) and shown("04-34", "accept", 7201), "turned-in 3906 unlocks 3907/7201 at 04-34")
  print("Dungeon prerequisites follow level and quest-log changes between visits")
end
