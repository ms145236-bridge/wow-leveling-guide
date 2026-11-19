-- 引擎：條件過濾、每步 done（遊戲狀態的純函式）、locate、漏掉清單、站完成度、超等建議。
-- 進度不存：只存 pin/skip/latch/drop/carry 這些查不到的東西（MG.db）。
local _, MG = ...
local C = MG.C
local L = MG.L
local R = MG.Route or { stations = {}, quests = {} }
local E = {}
MG.E = E

-- 路線資料換語言（ADDON_LOADED 時呼叫一次，語言設定讀到之後）。Route.lua 是中文底稿；Data\Route_<locale>.lua 依站 ID＋步驟序號、任務 ID 對上。
-- 顯示用欄位跟介面語言；選取目標（tgt、tgo、objs）和要跟遊戲文字比對的名字（nG、npcG、mobG）跟客戶端語言。
-- 說明文字（desc、站的提醒、練怪說明、危險說明…）用翻譯；沒有翻譯的非中文介面拿掉不顯示。
-- 站名、鳥點的 nameA／shortA／nodeA 裡的 {a:地區ID}：換成遊戲的地區名（客戶端語言）；有一個查不到就整個不用（改用不含城鎮的 name）
local function areas(t)
  if not t then return nil end
  local ok = true
  t = t:gsub("{a:(%d+)}", function(id)
    local n = C.AreaName(tonumber(id))
    if not n then ok = false end
    return n or ""
  end)
  return ok and t or nil
end
function E.Localize()
  -- 每個語系的路線資料是一個函式（呼叫才建表）：只建介面和客戶端要用的，其餘連同 MG.RouteL 丟掉
  local RL = MG.RouteL or {}
  MG.RouteL = nil
  local function get(loc)
    local v = RL[loc]
    if type(v) == "function" then v = v(); RL[loc] = v end
    return v
  end
  local D = not MG.uiZh and (get(MG.uiLoc) or get("enUS")) or nil
  local G = not MG.gameZh and (get(MG.gameLoc) or (MG.gameLoc == "esMX" and get("esES")) or get("enUS")) or nil
  local en = not MG.uiZh
  local P = MG.Pad -- /slv lang stress：顯示文字加長（平常原樣）
  if not en and not G then return end
  local none = {}
  -- 說明文字裡的 {s:站ID}（建置時沒有站名的站）：換成遊戲裡顯示的站名
  if D then
    local names = {}
    for _, st in ipairs(R.stations) do
      local ds = D.stations[st.id] or none
      names[st.id] = areas(ds.nameA) or ds.name or (st.map and C.MapName(st.map))
    end
    local function fill(t)
      for k, v in pairs(t) do
        if type(v) == "table" then fill(v)
        elseif type(v) == "string" and v:find("{s:", 1, true) then t[k] = (v:gsub("{s:([%w%-]+)}", function(id) return names[id] or id end)) end
      end
    end
    fill(D)
  end
  for _, st in ipairs(R.stations) do
    local ds, gs = D and D.stations[st.id] or none, G and G.stations[st.id] or none
    for i, s in ipairs(st.steps) do
      s.key0 = s.key0 or tostring(s.node or s.bind or s.to or s.text or s.lv or "") -- 存檔用的步驟鍵不跟語言變
      s.bindK = s.bind -- 爐石地點（中文）：zhTW 客戶端比對 GetBindLocation／區域名用，非中文介面的 bind 換成翻譯地名
      local d, g = ds.steps and ds.steps[i] or none, gs.steps and gs.steps[i] or none
      s.componentNpcG = G and g.componentNpc or s.componentNpc
      if en then s.componentNpc = d.componentNpc end
      s.npcG = s.npc
      if G then
        s.npcG, s.tgt = g.npc or s.npc, g.tgt; s.npcObj = g.npcObj
        s.bindG = areas(g.bindA) or g.bind -- 爐石地點的客戶端語言名（比對 GetBindLocation、區域名用）；沒有就 nil，只靠綁定事件
      end
      if en then
        s.nodeK = s.node -- 鳥點中文名：飛行步驟的 to 用它對到鳥點（Core 的未開點提醒）
        s.npc, s.hint, s.text, s.node, s.preText, s.star = P(d.npc), P(d.hint), P(d.text), P(areas(d.nodeA) or d.node), P(d.preText), d.star
        s.npcObj = d.npcObj
        s.desc, s.spot, s.bind = P(d.desc), P(d.spot), P(areas(d.bindA) or d.bind) -- bind：爐石地點的介面語言名（build 從鳥點／地區名對照來；沒有就 nil，標題改用 hm 地圖名）
        s.toL, s.fromL = P(areas(d.toA) or d.to), P(areas(d.fromA) or d.from) -- to／from 留中文（判斷用），顯示用 toL／fromL
        s.tagL = d.tag -- tag 本身是判斷用（怪多、副本前置鏈），顯示用 tagL
      end
    end
    for i, g in ipairs(st.grind or none) do
      g.mobG = G and (gs.grind and gs.grind[i] and gs.grind[i].mob) or g.mob
      if en then
        local dg = ds.grind and ds.grind[i] or none
        g.mob, g.note = P(dg.mob or "?"), P(dg.note)
      end
    end
    for i, p in ipairs(st.supply or none) do
      p.npcG = G and (gs.supply and gs.supply[i] and gs.supply[i].npc) or p.npc
      if en then p.npc = P(ds.supply and ds.supply[i] and ds.supply[i].npc) end
    end
    if en then
      local nameA = areas(ds.nameA)
      st.name = P(nameA or ds.name or (st.map and C.MapName(st.map)) or st.id)
      -- 短站名（建置時產生，清單與站名列用；全名在滑鼠提示）
      st.short, st.tips, st.pickup, st.pickupS, st.alt = P(nameA and areas(ds.shortA) or ds.short), ds.tips or {}, P(ds.pickup), ds.pickupS, nil
      if st.entrance then st.entrance = ds.entrance or "" end
      for i, x in ipairs(st.danger or none) do x.text = P(ds.danger and ds.danger[i]) end
    end
  end
  for id, q in pairs(R.quests) do
    local d, g = D and D.quests[id] or none, G and G.quests[id] or none
    q.nG = q.n
    if G then q.nG, q.zt, q.tgo, q.objs = g.n or q.n, nil, g.tgo, g.objs end
    if en then q.n, q.d, q.star = P(d.n or q.n), P(d.d), d.star end
  end
  if en then
    for id, k in pairs(R.keep or none) do
      local d = D.keep and D.keep[id] or none
      k.n, k.use = d.n, d.use or (not k.q and L["之後的任務會用到"] or nil)
    end
    for id, o in pairs(R.offroute or none) do o.why = P(D.offroute and D.offroute[id] and D.offroute[id].why) end
  end
end
-- 任務名：遊戲給的（和介面同語言時）＞路線資料
function E.QName(q)
  return (MG.sameLang and C.Title(q)) or (R.quests[q] and R.quests[q].n) or (L["任務 "] .. q)
end
E.session = {} -- 本次登入收到 QUEST_TURNED_IN 的任務
E.stations = {} -- 適用本角色的站（依路線順序）
E.dungeons = {} -- 副本站（依建議等級排序；不在主線）
E.byId = {}

local QUEST = { accept = true, ["do"] = true, turnin = true }
local SOFT = { ["goto"] = true, fp = true, fly = true, boat = true, travel = true, hearth = true }
local localVisitFrom = {} -- 只在原定回訪點補做的任務，不將早站步驟搬來異地。
local questSt = {} -- 任務 → 有它步驟的站（主線站與副本，Build 時建）
local anyQ = {} -- 任一組（s.any）裡的任務：沒接的不算站的進度（Build 時建）
local dunQ = {} -- 副本站裡有步驟的任務（副本前置、副本任務；Build 時建）
E.QUEST, E.SOFT = QUEST, SOFT

-- 鳥點名 → 該鳥點的地圖與座標（搭船、飛行的目的地判斷用）
local nodeMap
function E.NodeMap(node)
  if not nodeMap then
    nodeMap = {}
    for _, st in ipairs(R.stations) do
      for _, s in ipairs(st.steps) do
        if s.t == "fp" and s.map and (s.nodeK or s.node) then nodeMap[s.nodeK or s.node] = s end
      end
    end
  end
  local s = node and nodeMap[node]
  if s then return s.map, s.x, s.y end
end

-- 沒座標的交通要比對的步驟：後面已打勾的到達／交通路標，加上第一個還沒完成、適用、有座標的步驟（第二個回傳值，箭頭指它）
function E.SoftTargets(steps, done, na, i)
  local out = {}
  local from = steps[i].s
  for j = i + 1, #steps do
    local sj = steps[j].s
    if sj.x and not na[j] then
      local destination = from.t == "fly" and sj.t == "fp" and from.to == (sj.nodeK or sj.node)
      if destination or not done[j] then out[#out + 1] = sj; return out, sj end
      if sj.t == "goto" or sj.t == "travel" then out[#out + 1] = sj end
    end
  end
  return out
end
-- 人在任一個比對步驟的任一群（主座標＋more）附近就算到；只查不寫。爐石也用同一個範圍：用了爐石由區域名、施法事件認（stepDone、Core），
-- 這裡只認「人已經走到下一步」；範圍放大的話，輪到時人離下一步不遠（例如北郡礦坑到修道院）就會直接當成到了、不提示爐石
function E.SoftNear(_, targets, map, x, y)
  if not (map and x and y) then return false end -- 載入中只有地圖、還沒有座標：等下一次更新
  local r = 3
  for _, sj in ipairs(targets) do
    if sj.map == map and math.sqrt((sj.x - x) ^ 2 + (sj.y - y) ^ 2) <= r then return true end
    for _, p in ipairs(sj.more or {}) do
      if p[1] == map and math.sqrt((p[2] - x) ^ 2 + (p[3] - y) ^ 2) <= r then return true end
    end
  end
  return false
end

-- ── 角色與條件 ──────────────────────────────────────────────────────────────
local me = { originRaces = {} }
local raceMatch
local function inList(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
end
-- 路線的種族條件是 UnitRace 第 2 個回傳值（不隨語言變，例如 Scourge）；天裔精靈建置時統一寫成 Skyborne（見 E.Build 的 me.sky）
function raceMatch(list)
  for _, r in ipairs(list) do
    if r == me.race or (r == "Skyborne" and me.sky) then return true end
  end
end
local function originMatch(list)
  for _, race in ipairs(list) do if me.originRaces[race] then return true end end
end
-- 日誌依客戶端語言逐項比對。空白、缺項及不認得的文字不能當作偵察已完成。
local function surveyProgress(q, survey)
  local labels = survey.labels[MG.gameLoc or (GetLocale and GetLocale()) or "enUS"]
  if not labels then return nil, false end
  local status, duplicate = {}, {}
  for _, objective in ipairs(C.Objectives(q) or {}) do
    local name = objective.text
    if name and name ~= "" then
      local done = objective.done == true
      if objective.need and objective.need > 0 and objective.have and objective.have < objective.need then done = false end
      if status[name] ~= nil then duplicate[name] = true end
      status[name] = done
    end
  end
  local event = status[labels.event]
  if duplicate[labels.event] then event = nil end
  local allBadges, incompleteBadge = true, false
  for _, name in ipairs(labels.badges) do
    if status[name] ~= true or duplicate[name] then allBadges = false end
    if status[name] == false then incompleteBadge = true end
  end
  return event, allBadges, incompleteBadge
end

local function hasWeapon(item)
  return E.ItemCount(item) > 0 or (GetInventoryItemID and GetInventoryItemID("player", 16) == item)
end

local function hasAll(items)
  for _, item in ipairs(items) do if E.ItemCount(item) < 1 then return false end end
  return true
end

-- Ordinary counts are physical items. The charge count only decides whether the box can catch another spawn.
function E.RiftPhase()
  if E.ItemCount(7308) < 1 then return "scroll" end
  if E.ItemCount(7247) < 1 then return "chest" end
  if E.ItemCount(7292) >= 3 then return "journal" end
  local count = C_Item and C_Item.GetItemCount or GetItemCount
  if count and count(7247, false, true) == 0 then return "chest" end
  return "capture"
end

local function hasQuantities(items)
  for _, need in ipairs(items) do
    if E.ItemCount(need.item) < need.count then return false end
  end
  return true
end

-- These counted hunts have a single native objective. Never infer kills from bags or coordinates.
local function huntCount(q, info)
  local objectives = C.Objectives(q)
  local o = objectives and #objectives == 1 and objectives[1]
  if o and o.need == info.killCount and type(o.have) == "number" then return o.have end
end
E.HuntCount = huntCount

local function journalReady(q)
  if not C.IsReady(q) then return false end
  local info = R.quests[q]
  if info and info.requiredLoot and E.ItemCount(info.requiredLoot) < (info.lootCount or 1) then return false end
  if info and info.combatWeapon and not hasWeapon(info.combatWeapon) then return false end
  if info and info.deliveryItems and not hasQuantities(info.deliveryItems) then return false end
  if info and info.riftTools and E.RiftPhase() ~= "journal" then return false end
  if info and info.supply and E.ItemCount(info.supply.item) < info.supply.count then return false end
  if info and info.farmMaterial and E.ItemCount(info.farmMaterial.item) < info.farmMaterial.count then return false end
  if info and info.requiredItems and not hasAll(info.requiredItems) then return false end
  if info and (info.confirmInteraction or info.requiredLoot or info.supply or info.requiredItems) then
    for _, o in ipairs(C.Objectives(q) or {}) do
      if o.done == false or (o.need and o.need > 0 and o.have and o.have < o.need) then return false end
    end
  end
  return true
end

local function turned(q) return E.session[q] or C.IsTurnedIn(q) end
local function inInstance(instanceID)
  if not (IsInInstance and GetInstanceInfo and IsInInstance()) then return false end
  local id = select(8, GetInstanceInfo())
  return not (issecretvalue and issecretvalue(id)) and id == instanceID
end

local function atHandoffArea(when)
  if IsInInstance and IsInInstance() then return false end
  local area = C.AreaName and C.AreaName(when.hubArea)
  if area and C.ZoneTexts then
    local sub, _, minimap = C.ZoneTexts()
    if sub == area or minimap == area then return true end
  end
  local guid = UnitGUID and UnitGUID("npc")
  if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return false end
  return tonumber(guid:match("^Creature%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")) == when.hubNpc
end

function E.Applies(when, anyLv, keepReady) -- 往後預估不看等級；指定交接仍核對日誌
  if not when then return true end
  if when.notOrigin and originMatch(when.notOrigin) then return false end
  local routeRaces = when.raceOrOrigin or when.neitherRaceNorOrigin
  if routeRaces then
    local matches = raceMatch(routeRaces) or originMatch(routeRaces)
    if (matches and true or false) ~= (when.raceOrOrigin ~= nil) then return false end
  end
  if when.race and not raceMatch(when.race) then return false end
  if when.notRace and raceMatch(when.notRace) then return false end
  if when.coastal ~= nil and when.coastal ~= (MG.db.auberdineChoice == "coast") then return false end
  if when.dungeonPrep and (not MG.UI.Get("dPre") or not MG.UI.Get("optional") or MG.db.dNo[when.dungeonPrep]) then return false end
  if when.hubArea then
    if not atHandoffArea(when) then return false end
    if when.dungeonPrep then
      if MG.db.station ~= when.dungeonPrep then return false end
      local free, used, visible = E.QuestLogSpace()
      local pending = MG.PendingAccepts and MG.PendingAccepts(used, visible) or 0
      if not E.PreRoom(E.byId[MG.db.dungeonFrom], pending, free) then return false end
    end
  end
  if when.readyQuest and (not anyLv or keepReady) then
    if not journalReady(when.readyQuest) then return false end
    local info = R.quests[when.readyQuest]
    if info and info.survey then
      for _, badge in ipairs(info.survey.badges) do if E.ItemCount(badge[1]) < 1 then return false end end
      local event, _, incompleteBadge = surveyProgress(when.readyQuest, info.survey)
      if event == false or incompleteBadge then return false end
    end
  end
  if when.turnedQuest and not E.Turned(when.turnedQuest) then return false end
  if when.instanceID and not inInstance(when.instanceID) then return false end
  if when.additionalBags and not hasQuantities(when.additionalBags) then return false end
  if when.workMap then
    if not C.Position or (UnitOnTaxi and UnitOnTaxi("player")) then return false end
    local map,x,y = C.Position()
    if map ~= when.workMap or not x or not y then return false end
  end
  if when.nearPoint and (not when.localRaces or raceMatch(when.localRaces)) then
    if not C.Position or (UnitOnTaxi and UnitOnTaxi("player")) then return false end
    local point = when.nearPoint
    local map, x, y = C.Position()
    local radius = when.hubArea and when.dungeonPrep and 3 or 0.8
    if map ~= point[1] or not x or not y or (x - point[2])^2 + (y - point[3])^2 > radius^2 then return false end
  end
  if when.withTurnin then
    local q = when.withTurnin
    local key = "t:" .. q
    if MG.db.skip[key] or MG.db.mark[key] or turned(q)
      or not C.IsOnQuest(q) or not C.IsReady(q) then return false end
  end
  if when.failedQuest and not anyLv and not (C.IsFailed and C.IsFailed(when.failedQuest)) then return false end
  if when.notFailedQuest and not anyLv and C.IsFailed and C.IsFailed(when.notFailedQuest) then return false end
  if when.money and (GetMoney and GetMoney() or 0) < when.money then return false end
  if when.bagOrWorn and not hasWeapon(when.bagOrWorn) then return false end
  if when.bag and E.ItemCount(when.bag.item) < when.bag.count then return false end
  if when.additionalBags then
    for _, requirement in ipairs(when.additionalBags) do
      if E.ItemCount(requirement.item) < requirement.count then return false end
    end
  end
  if when.missingBag and E.ItemCount(when.missingBag.item) >= when.missingBag.count then return false end
  if when.manualPickup or when.reserveDungeonPrep then
    if not MG.UI.Get("optional") then return false end
    local free, used, visible = E.QuestLogSpace()
    local pending = MG.PendingAccepts and MG.PendingAccepts(used, visible) or 0
    if when.manualPickup == "dungeon" or when.reserveDungeonPrep then
      local main = E.byId[MG.db.station]
      if not main or not main.index then main = E.byId[MG.db.dungeonFrom] end
      if not E.PreRoom(main and main.index and main or nil, pending, free) then return false end
    elseif free <= pending then
      return false
    end
  end
  if when.canStart then
    local q = when.canStart
    local key = "a:" .. q
    if C.IsOnQuest(q) or turned(q) or MG.db.skip[key] or MG.db.mark[key] or E.LogFull() then return false end
  end
  if when.onQuestAny then
    local on = false
    for _, id in ipairs(when.onQuestAny) do
      if C.IsOnQuest(id) then on = true; break end
    end
    if not on then return false end
  end
  if when.class and not inList(when.class, me.class) then return false end
  if when.notClass and inList(when.notClass, me.class) then return false end
  if when.lvMin and not anyLv and (UnitLevel("player") or 0) < when.lvMin then return false end
  -- 鳥點開了沒（fp＝開了才適用、noFp＝沒開才適用）：看飛行地圖記下的（Core 的 TAXIMAP_OPENED）；還沒開過飛行地圖當作沒開
  local node = when.fp or when.noFp
  if node and ((MG.db.fpNodes ~= nil and MG.db.fpNodes[node] == true) ~= (when.fp ~= nil)) then return false end
  return true
end

-- 登入後建一次：過濾站、給每步 key、把「註」併到下一步
-- 起點路線：{ key, name, first }（依路線順序）；自己的種族那條是預設
function E.Starts()
  local out, seen = {}, {}
  for _, st in ipairs(R.stations) do
    if st.start and not seen[st.start] then
      seen[st.start] = true
      out[#out + 1] = { key = st.start, name = st.name, native = raceMatch(st.when.race) and true or false }
    end
  end
  return out
end
function E.StartKey()
  if MG.db.start then
    for _, s in ipairs(E.Starts()) do if s.key == MG.db.start then return s.key end end
  end
  for _, s in ipairs(E.Starts()) do if s.native then return s.key end end
end

-- 任務的種族遮罩（QuestieDB requiredRaces）：本角色接不到就略過
local function raceOK(q)
  local info = R.quests[q]
  if not (info and info.races and me.raceID) then return true end
  return math.floor(info.races / 2 ^ (me.bit - 1)) % 2 == 1
end

-- 同一目標隨背包狀態換點。各處都讀同一個 step.s，箭頭、地圖、釘選與手動完成沿用原步驟鍵。
local objectiveLocations = { __index = function(step, field)
  if field == "s" then
    for _, location in ipairs(step.locations) do
      if E.Applies(location.when) then return location end
    end
    return step.locations[1] -- 全部不適用時，Locate 依原條件隱藏這一步。
  end
end }

function E.Build()
  me.raceL, me.race, me.raceID = UnitRace("player")
  -- QuestieDB 把天裔精靈記成第 33（聯盟）、34（部落）位；遊戲給的種族編號不一定是這兩個，照陣營對過去
  me.bit = me.raceID
  me.sky = (me.race and me.race:find("Sky") or me.raceL and me.raceL:find("天裔", 1, true)) and true or false
  if me.sky then me.bit = UnitFactionGroup("player") == "Alliance" and 33 or 34 end
  me.class = select(2, UnitClass("player"))
  wipe(E.stations); wipe(E.byId); wipe(E.dungeons); wipe(questSt); wipe(localVisitFrom); wipe(dunQ); wipe(anyQ)
  local startKey = E.StartKey()
  wipe(me.originRaces)
  for race in (startKey or ""):gmatch("[^/]+") do me.originRaces[race] = true end
  for _, st in ipairs(R.stations) do
    if st.dungeon or (st.start and st.start == startKey) or (not st.start and E.Applies(st.when)) then
      local list, note = {}, nil
      -- 走別族的起點：第一站前面補一步「前往」
      if st.start and not raceMatch(st.when.race) and not (E.stations[#E.stations] and E.stations[#E.stations].start == st.start) then
        local first
        for _, s in ipairs(st.steps) do if s.x then first = s; break end end
        list[1] = { s = { t = "travel", text = MG.uiZh and ("前往 " .. st.name) or st.name, map = first and first.map, x = first and first.x, y = first and first.y, r = 5 }, key = st.id .. "#0", st = st }
      end
      local usedKey = {}
      for _, s in ipairs(st.steps) do
        if s.ungoroExit == "camp" or s.ungoroExit == "port" then
          st.ungoroHints = st.ungoroHints or {}
          st.ungoroHints[s.ungoroExit] = s.desc
          -- The description belongs to the Kalimdor alternative, not to the
          -- original east-coast flight's tooltip. Keep the source for rebuilds.
          local flight = {}
          for key, value in pairs(s) do if key ~= "desc" then flight[key] = value end end
          s = flight
        end
        if s.t == "hearth" and s.ungoroExit == "east" then
          st.ungoroHearth = s
          note = note or {text=s.desc}
        end
        if s.t == "accept" and (s.ungoroExit == "east" or s.ungoroExit == "teacher") then
          st.ungoroTrainers = st.ungoroTrainers or {}
          local trainers = st.ungoroTrainers[s.q] or {}
          st.ungoroTrainers[s.q], trainers[s.map] = trainers, s
        end
        if s.t == "note" then
          if s.ungoroExit then st.ungoroHints[s.ungoroExit] = s.text else note = s end
        elseif s.sameObjective then
          local step = list[#list]
          if not step.locations then
            step.locations = { step.s }
            step.s = nil
            setmetatable(step, objectiveLocations)
          end
          step.locations[#step.locations + 1] = s
        elseif s.ungoroExit == "ironReturn" then
          st.ungoroIronReturn = s
        elseif s.ungoroExit ~= "teacher" then -- alternate trainers use the original accept key
          -- 鍵用內容：路線重建後存檔裡的勾選／略過／釘選不會跑到別步；同站重複的加 ~2、~3
          -- 改寫、合併過的步驟寫了舊鍵（skey）就沿用；船的座標是碼頭，加上去前的存檔沒有，不放進鍵
          local base = QUEST[s.t] and (s.t:sub(1, 1) .. ":" .. (s.any and s.any[1] or s.q)) -- 任一組的接：s.q 執行時會換成玩家接的那個，鍵固定用第一個
            or (s.skey and (st.id .. "#" .. s.skey))
            or (st.id .. "#" .. s.t .. ":" .. (s.key0 or tostring(s.node or s.bind or s.to or s.text or s.lv or "")) .. (s.x and s.t ~= "boat" and string.format("@%.0f,%.0f", s.x, s.y) or ""))
          local key, k = base, 2
          while usedKey[key] do key = base .. "~" .. k; k = k + 1 end
          usedKey[key] = true
          if s.skey then
            -- 合併、改寫前的舊存檔（舊鍵依座標點分組；最後一組是這步本身）：
            -- 途經點走過、勾過、略過 → 記成「@k」進度；這步本身的其他舊鍵 → 勾選／略過搬過來（手動略過的起點換成新鍵，
            -- 指向它的連帶值也跟著換）；搬完就刪掉舊值，之後在新鍵上的手動調整不會被舊值蓋回去。
            -- 舊版釘在其中一點 → 釘這步，箭頭指那一點（pin.via；釘選和走過的進度分開記）
            local db = MG.db
            local pin = db.pin and db.pin[st.id]
            local groups = {}
            for k, olds in ipairs(s.vkeys or {}) do groups[k] = olds end
            local n = #groups + 1
            groups[n] = s.akeys or {}
            for k, olds in ipairs((db.latch and db.mark and db.skip) and groups or {}) do -- 測試用的精簡存檔可能沒有這些表
              for _, old in ipairs(olds) do
                local ok = st.id .. "#" .. old
                local root = db.skip[ok]
                if k < n then
                  if db.latch[ok] or db.mark[ok] or root then db.latch[key .. "@" .. k] = true end
                else
                  if db.latch[key] == nil then db.latch[key] = db.latch[ok] end
                  if db.mark[key] == nil then db.mark[key] = db.mark[ok] end
                  if root and db.skip[key] == nil then db.skip[key] = (root == ok or root == true) and key or root end
                end
                if root then
                  for sk, v in pairs(db.skip) do if v == ok and sk ~= ok then db.skip[sk] = key end end
                end
                db.latch[ok], db.mark[ok], db.skip[ok] = nil, nil, nil
                if pin and pin.via == nil and pin.key == ok then pin.key, pin.via = key, s.via and k or false end
                if pin and pin.auto == ok then pin.auto = key end
              end
            end
            if pin and pin.via == nil and pin.key == key then pin.via = s.via and n or false end
          end
          list[#list + 1] = { s = s, key = key, note = note, st = st }
          note = nil
        end
      end
      st.list = list
      st.componentVisit = nil
      for _, step in ipairs(list) do
        if st.dungeon and (step.s.instanceMaterial or (step.s.ph == "in" and step.s.when and step.s.when.missingBag)) then st.componentVisit = true end
        local q = step.s.any and step.s.any[1] or step.s.q
        for _, id in ipairs(step.s.any or {}) do anyQ[id] = true end
        if q then
          local l = questSt[q] or {}
          questSt[q] = l
          if l[#l] ~= st then l[#l + 1] = st end
          if st.dungeon then dunQ[q] = true end
        end
      end
      if st.dungeon then
        E.dungeons[#E.dungeons + 1] = st
      else
        st.index = #E.stations + 1
        E.stations[st.index] = st
        for _, w in ipairs(st.list) do
          local s = w.s
          if s.q and s.opt and s.when and s.when.localVisit and not localVisitFrom[s.q] then
            localVisitFrom[s.q] = st.index
          end
        end
      end
      E.byId[st.id] = st
    end
  end
  table.sort(E.dungeons, function(a, b) return a.lv[1] < b.lv[1] or (a.lv[1] == b.lv[1] and a.lv[2] < b.lv[2]) end)
end
E.me = me

-- ── done ────────────────────────────────────────────────────────────────────
E.Turned = turned

local function isCleanedRingReturn(q)
  return q == 2947 or q == 2949
end

-- 目標全部完成；日誌查不到目標（對話型任務）視為完成
local function ready(q)
  if isCleanedRingReturn(q) then return C.IsOnQuest(q) and E.ItemCount(9362) > 0 and journalReady(q) end
  if R.quests[q] and (R.quests[q].supply or R.quests[q].confirmInteraction or R.quests[q].requiredLoot or R.quests[q].requiredItems) then return journalReady(q) end
  if C.IsReady(q) then return true end
  if C.IsFailed and C.IsFailed(q) then return false end -- 護送失敗：目標清單可能是空的，不能當成做完
  local obj = C.Objectives(q)
  if not obj then return false end
  if #obj == 0 then return true end
  for _, o in ipairs(obj) do if not o.done then return false end end
  return true
end
E.Ready = ready

local function excluded(q)
  local info = R.quests[q]
  if not (info and info.ex) then return false end
  for _, other in ipairs(info.ex) do
    if turned(other) or C.IsOnQuest(other) then return true end
  end
  return false
end

-- 前置沒做的任務接不到：還沒接、也沒交的話這步不適用（例如「有前置才接」的支線）
local function available(q)
  local info = R.quests[q]
  if not info or turned(q) or C.IsOnQuest(q) then return true end
  for _, p in ipairs(info.pg or {}) do if not turned(p) then return false end end
  if info.ps and #info.ps > 0 then
    for _, p in ipairs(info.ps) do if turned(p) then return true end end
    return false
  end
  return true
end

-- 後續任務已經接了或交了（例如沒做導引就直接接到主任務）：這個任務不用做了
local function superseded(q)
  if turned(q) or C.IsOnQuest(q) then return false end
  for _, f in ipairs((R.quests[q] or {}).fol or {}) do if turned(f) or C.IsOnQuest(f) then return true end end
  return false
end

-- 可跳過的步驟：設定沒開就不算路線，除非該任務已在任務日誌，或經驗不夠時被補回來（fill）
local fill = {}
local function optOut(s)
  return s.opt and not MG.UI.Get("optional") and not (s.q and (C.IsOnQuest(s.q) or fill[s.q])) or false
end
E.OptOut = optOut

-- 任一組的接（s.any，例如紮營入門指南任選專業）：s.q 換成玩家日誌裡的那個，其次已交的，都沒有就用第一個還能接的。
-- 接取步因此照一般任務判斷完成；交的那幾步各自是一般的交，沒接的不適用（本站的 acc 不算任一組）
local function pickAny(list)
  for _, step in ipairs(list) do
    local s = step.s
    if s.any then
      local pick
      for _, q in ipairs(s.any) do if C.IsOnQuest(q) then pick = q; break end end
      if not pick then for _, q in ipairs(s.any) do if turned(q) then pick = q; break end end end
      if not pick then for _, q in ipairs(s.any) do if raceOK(q) and not excluded(q) then pick = q; break end end end
      s.q = pick or s.any[1]
    end
  end
end

-- ── 經驗補足 ────────────────────────────────────────────────────────────────
-- 經典版每級所需經驗（升到下一級）；本級用 UnitXPMax
local XP_LEVEL = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
  25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
  95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }
-- 任務經驗（等級差衰減：高 6 級 80%、7 級 60%、8 級 40%、9 級 20%、10 級以上 10%）
local function questXP(q, lv)
  local info = R.quests[q]
  if not (info and info.xp) then return 0 end
  local d = lv - (info.lvl or lv)
  local f = d <= 5 and 1 or d == 6 and 0.8 or d == 7 and 0.6 or d == 8 and 0.4 or d == 9 and 0.2 or 0.1
  return info.xp * f * (C.XPBuff() and 1.03 or 1) -- 「充分休息」增益：任務經驗 +3%（Compat 的 C.XP_BUFF_NAME／C.XP_BUFFS）
end
E.QuestXP = questXP

-- 打怪經驗（經典版公式）：同級 等級×5+45；怪高 每級 +5%（最多 4 級）；怪低 ×(1 − 等級差 ÷ ZD)；精英 ×2
local DROP_RATE = 0.4 -- 掉落物沒資料時的預設掉率
local KILL_EXTRA = 0.15 -- 路上順手打的怪：任務怪經驗的 15%
local function zeroDiff(lv)
  if lv <= 7 then return 5 elseif lv <= 9 then return 6 elseif lv <= 11 then return 7 elseif lv <= 15 then return 8
  elseif lv <= 19 then return 9 elseif lv <= 29 then return 11 elseif lv <= 39 then return 12 elseif lv <= 44 then return 13
  elseif lv <= 49 then return 14 elseif lv <= 54 then return 15 else return 16 end
end
local function mobXP(mlv, lv, elite)
  if not mlv or mlv <= 0 then return 0 end
  local base = lv * 5 + 45
  local d = mlv - lv
  local x = d >= 0 and base * (1 + 0.05 * math.min(d, 4)) or math.max(0, base * (1 - (-d) / zeroDiff(lv)))
  return elite and x * 2 or x
end
-- 任務還要打的怪的經驗：在日誌中用遊戲的剩餘數量，否則用建置時從目標文字抓的數量
local function killXP(q, lv)
  local info = R.quests[q]
  if not (info and info.mob) or turned(q) then return 0 end
  local inLog = C.IsOnQuest(q)
  local lootLeft
  if info.requiredLoot and inLog then
    lootLeft = math.max(0,(info.lootCount or 1) - E.ItemCount(info.requiredLoot))
    if lootLeft == 0 then return 0 end
  end
  if info.farmMaterial and inLog then
    local mat = info.farmMaterial
    local left = math.max(0, mat.count-E.ItemCount(mat.item))
    for _, m in ipairs(info.mob) do
      if m[3]==2 then return left / (info.rate or DROP_RATE) * mobXP(m[1],lv,m[4]==1) * (1+KILL_EXTRA) end
    end
    return 0
  end
  local kills = inLog and info.killCount and huntCount(q, info)
  if inLog and not info.requiredLoot and not kills and C.IsReady(q) then return 0 end
  local obj = inLog and not info.requiredLoot and C.Objectives(q)
  local total = 0
  for k, m in ipairs(info.mob) do
    local left = lootLeft or m[2]
    if obj and #obj == #info.mob and obj[k].need then left = obj[k].need - (obj[k].have or 0) end
    if left > 0 then
      local kills = m[3] == 2 and left / (info.rate or DROP_RATE) or left
      total = total + kills * mobXP(m[1], lv, m[4] == 1)
    end
  end
  return total * (1 + KILL_EXTRA)
end
E.KillXP = killXP

-- 經驗不夠到下一站起始等級時，挑本站最划算的可跳過任務補回來（經驗 ÷ (1 + 繞路距離)），補到夠就停
-- 回傳 fill 集合與說明 { need, projected, added = {q...} }
function E.FillPlan(st)
  wipe(fill)
  local info = { need = 0, projected = 0, questXP = 0, killXP = 0, rested = 0, added = {} }
  if MG.UI.Get("optional") then return info end
  local nxt = E.Next(st)
  local target = math.min(60, nxt and nxt.lv[1] or (st.lv[2] + 1))
  local lv = UnitLevel("player") or 1
  if lv >= target then return info end
  local need = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
  for l = lv + 1, target - 1 do need = need + (XP_LEVEL[l] or 0) end
  need = math.max(0, need)
  info.need = need
  -- 必做任務（不是可跳過、還沒交）的預估經驗，與它們的座標（算繞路用）
  local projected, seen, spots, cands = 0, {}, {}, {}
  -- 本站有交的任務才算任務經驗、本站有做或交的才算打怪經驗（在別站交的，到下一站前拿不到）
  -- 組隊／精英任務（任一步標了）：單人不補
  -- 還沒接的任務：本站有「必做的接」才算必做（must）。接取是可跳過的（含條件入口）沒被補回就不算，別站才接得到的也不算
  local hand, work, group, must = {}, {}, {}, {}
  local solo = not (IsInGroup and IsInGroup())
  for _, step in ipairs(st.list) do
    local s = step.s
    local on = s.q and E.Applies(s.when) and not MG.db.skip[step.key] -- 手動略過的步驟不算（只略過「交」＝這站拿不到任務經驗）
    -- 同站有安排且仍打算做的工作，可以預估其後的交件。當下點交仍須通過日誌與實物條件。
    if s.afterWork and work[s.q] and not MG.db.skip[step.key] then on = true end
    if on and s.t == "turnin" then hand[s.q] = true end
    if on and (s.t == "do" or s.t == "turnin") then work[s.q] = true end
    if on and s.t == "accept" and not s.opt then
      local min = s.pickLv or (R.quests[s.q] or {}).min or 0
      if min < target then must[s.q] = true end -- 抵達目標等級後才可接的任務無法用來升到該級
    end
    if s.q and s.tag and (s.tag:find("隊伍", 1, true) or s.tag:find("組隊", 1, true) or s.tag:find("精英", 1, true)) then group[s.q] = true end
  end
  -- 互斥的任務（二選一）只算一個：已經算進來（必做／在日誌）或已補回的任務，它的互斥對象不再算、不再補
  local function clash(q)
    for _, other in ipairs((R.quests[q] or {}).ex or {}) do if seen[other] or fill[other] then return true end end
    return false
  end
  -- 前置已完成、是本站會做也會交的任務，或前置也已被補回（任務鏈依序補）才算得到（必做的也一樣：前置被略過、不在本站的不算）
  local function eligible(q)
    if available(q) then return true end
    local qi = R.quests[q] or {}
    for _, p in ipairs(qi.pg or {}) do if not (turned(p) or (hand[p] and (seen[p] or fill[p]))) then return false end end
    if qi.ps and #qi.ps > 0 then
      for _, p in ipairs(qi.ps) do if turned(p) or (hand[p] and (seen[p] or fill[p])) then return true end end
      return false
    end
    return true
  end
  for _, step in ipairs(st.list) do
    local s, q = step.s, step.s.q
    if q and E.Applies(s.when) and raceOK(q) and not turned(q) and not MG.db.skip[step.key] and not MG.db.skip["a:" .. q] and not excluded(q) and not superseded(q) then
      -- 已經接了的，和本站必接的
      if (C.IsOnQuest(q) or must[q]) and not seen[q] and not clash(q) and eligible(q) then
        seen[q] = true
        info.questXP = info.questXP + (hand[q] and questXP(q, lv) or 0)
        info.killXP = info.killXP + (work[q] and killXP(q, lv) or 0)
      end
      -- 條件入口（cond：要先有掉落物、材料、聲望或遇到人才接得到）還沒接的不補：插件看不到背包和聲望，補了會叫人去接不存在的任務
      -- 高階怪保護（hard＝要打的怪的等級上限）：比你高 3 級以上的不補
      local quest = R.quests[q] or {}
      if s.opt and s.t == "accept" and not C.IsOnQuest(q) and not quest.cond and (quest.hard or 0) - lv < 3 and not (solo and (group[q] or quest.soloElite)) and lv >= (s.pickLv or quest.min or 0) and not cands[q] then
        cands[q] = { q = q, xp = (hand[q] and questXP(q, lv) or 0) + (work[q] and killXP(q, lv) or 0), pts = {} }
      end
    end
    if s.x and not s.opt and E.Applies(s.when) and (not q or raceOK(q)) and not MG.db.skip[step.key] then spots[#spots + 1] = s end
  end
  for _, step in ipairs(st.list) do
    local c = step.s.q and cands[step.s.q]
    if c and step.s.x and E.Applies(step.s.when) and not MG.db.skip[step.key] then c.pts[#c.pts + 1] = step.s end
  end
  -- 休息經驗：打怪經驗加倍，最多到休息池的量
  info.rested = math.min(info.killXP, GetXPExhaustion and GetXPExhaustion() or 0)
  projected = info.questXP + info.killXP + info.rested
  info.projected = projected
  if projected >= need then return info end
  local list = {}
  for _, c in pairs(cands) do
    local detour = #c.pts == 0 and 50 or 0
    for _, p in ipairs(c.pts) do
      local nearest = 50
      for _, r in ipairs(spots) do
        if r.map == p.map then nearest = math.min(nearest, math.sqrt((r.x - p.x) ^ 2 + (r.y - p.y) ^ 2)) end
      end
      -- 接取點在主路旁，也要計入實際任務目標離主路多遠。
      detour = math.max(detour, nearest)
    end
    c.score = c.xp / (1 + detour) * (E.StarFor(c.q) and 2 or 1)
    if c.xp > 0 then list[#list + 1] = c end
  end
  table.sort(list, function(a, b) return a.score > b.score or (a.score == b.score and a.q < b.q) end)
  local picked = true
  while projected < need and picked do
    picked = false
    for _, c in ipairs(list) do
      if not fill[c.q] and not clash(c.q) and eligible(c.q) then
        fill[c.q] = true
        info.added[#info.added + 1] = c.q
        projected = projected + c.xp
        picked = true
        break
      end
    end
  end
  info.projected = projected
  return info
end
E.Fill = fill

-- ★ 好獎勵：本職業拿得到才算（沒寫職業＝全職業）
function E.StarFor(q, s)
  local star = (s and s.star) or (q and R.quests[q] and R.quests[q].star)
  if not star then return nil end
  if star[2] and not inList(star[2], me.class) then return nil end
  return star[1]
end

-- 山口、洞口、傳送人等路標，以及必經的交通步驟，把「附近」分成不同路段。
local function travelBoundary(s)
  return SOFT[s.t] or s.t == "bind"
end

-- 順路提醒（回傳步驟序號，或出本交的那一步）：本站裡現在就能做（接得到、在日誌未完成、可交）、離玩家比目前步驟近很多的步驟。
-- 條件：同地圖、距離 ≤ 設定值、且 < 目前步驟距離的 25%；不在「附近一起做」裡；同一步連續 3 秒都成立才提示；略過後 2 分鐘不再提。
local detourKey, detourSince, detourNo = nil, 0, {}
function E.Detour(state)
  if not (state and not state.instance and MG.UI.Get("detourOn")) then return end -- 本站做完（沒有目前步驟）時出本交的任務照樣提示
  local map, x, y = C.Position()
  if not (map and x) then return end
  local function dist(s)
    local best
    local pts = { s.x and { s.map, s.x, s.y } or nil }
    for _, p in ipairs(s.more or {}) do pts[#pts + 1] = p end
    for _, p in ipairs(pts) do
      if p[1] == map then
        local d = math.sqrt((p[2] - x) ^ 2 + (p[3] - y) ^ 2)
        if not best or d < best then best = d end
      end
    end
    return best
  end
  local now, lim, lv = GetTime(), MG.UI.Get("detourDist"), UnitLevel("player") or 0
  local cd = state.cur and dist(state.steps[state.cur].s) or math.huge
  local best, bd
  local first, last = 1, #state.steps
  if state.cur then
    for i = state.cur - 1, 1, -1 do
      if not state.done[i] and not state.na[i] and travelBoundary(state.steps[i].s) then first = i + 1; break end
    end
    for i = state.cur, last do
      if not state.done[i] and not state.na[i] and travelBoundary(state.steps[i].s) then last = i - 1; break end
    end
  end
  for i = first, last do
    local step = state.steps[i]
    local s, q = step.s, step.s.q
    if i ~= state.cur and q and not state.done[i] and not state.na[i] and not state.wait[i] and not state.inGroup[i]
        and E.Applies(s.when) and now - (detourNo[step.key] or -999) >= 120 then
      local onQ = C.IsOnQuest(q)
      local ok = (s.t == "accept" and not onQ and lv >= ((R.quests[q] or {}).min or 0))
        or (s.t == "do" and onQ and not ready(q)) or (s.t == "turnin" and onQ and ready(q))
      local d = ok and dist(s)
      if d and d <= lim and d < cd * 0.25 and (not bd or d < bd) then best, bd = i, d end
    end
  end
  -- 出本才交的副本任務（不在主線）：做完了、人走到交的人附近也提示；回傳那一步本身
  for _, dg in ipairs(E.dungeons) do
    for _, step in ipairs(dg.list) do
      local s, q = step.s, step.s.q
      if s.ph == "post" and s.t == "turnin" and q and C.IsOnQuest(q) and ready(q) and E.Applies(s.when)
          and now - (detourNo[step.key] or -999) >= 120 then
        local d = dist(s)
        -- 不在主線上，不比目前步驟近不近：人在附近就提示（交的人常就在下一步旁邊）
        if d and d <= lim and (not bd or d < bd) then best, bd = step, d end
      end
    end
  end
  local key = best and (type(best) == "table" and best.key or state.steps[best].key)
  if key ~= detourKey then detourKey, detourSince = key, now end
  if key and now - detourSince >= 3 then return best end
end
function E.DetourNo(key) detourNo[key] = GetTime() end
function E.DetourPending() return detourKey ~= nil end

-- 練怪地點建議：補完可跳過任務後經驗仍不夠到下一站，或等級低於本站範圍 → 挑本站一個不會灰的練怪點
-- 怪的等級最接近玩家（高最多 2 級）的優先
function E.GrindSuggest(st, fillInfo)
  if not (st and st.grind) or MG.db.grindSkip[st.id] == UnitLevel("player") then return nil end
  local lv = UnitLevel("player") or 1
  local short = fillInfo and fillInfo.need > 0 and fillInfo.projected < fillInfo.need
  if not short and lv >= st.lv[1] then return nil end
  local best, bestD
  for _, g in ipairs(st.grind) do
    local top = g.lv[2]
    if mobXP(top, lv, false) > 0 and g.lv[1] <= lv + 2 then
      local d = math.abs((g.lv[1] + g.lv[2]) / 2 - lv)
      if not best or d < bestD then best, bestD = g, d end
    end
  end
  return best
end

function E.ItemCount(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
  return GetItemCount and GetItemCount(id) or 0
end

-- 保留原進度鍵；只在本次顯示的步驟上替換尚未收集的遺體或已證實未完成的偵察點。
local function surveyStep(step, survey)
  local row, view = {}, {}
  for k, v in pairs(step) do row[k] = v end
  for k, v in pairs(step.s) do view[k] = v end
  row.s, row.note = view, {text = view.desc}
  view.map, view.x, view.y, view.more = nil, nil, nil, nil
  local remaining = {}
  for _, badge in ipairs(survey.badges) do
    if E.ItemCount(badge[1]) < 1 then
      remaining[#remaining + 1] = tostring(badge[1])
      if not view.x then view.map, view.x, view.y = badge[2], badge[3], badge[4]
      else
        view.more = view.more or {}
        view.more[#view.more + 1] = {badge[2], badge[3], badge[4]}
      end
    end
  end
  view.surveyState = table.concat(remaining, ",")
  if #remaining == 0 then
    local event, badgesComplete, incompleteBadge = surveyProgress(view.q, survey)
    view.surveyComplete = event ~= false and not incompleteBadge and C.IsReady(view.q)
    view.noObjectTarget = true
    if event == false and badgesComplete then
      view.map, view.x, view.y = unpack(survey.event)
      view.surveyState = "event"
    end
  end
  return row
end

local function stepDone(step, map, x, y)
  local s = step.s
  -- An old flight, boat or hearth arrival cannot complete a different leg shown on the same key.
  -- Manual marks and skips are applied independently in Locate.
  if not s.classTransfer and MG.db.latch[step.key] then return true end
  local t, q = s.t, s.q
  if t == "accept" or t == "need" then return C.IsOnQuest(q) or turned(q)
  elseif t == "do" and s.surveyState ~= nil then return turned(q) or s.surveyComplete
  elseif t == "do" then
    local info = R.quests[q]
    if s.strictReady or s.native then
      local nativeReady = info and info.confirmInteraction and journalReady or C.IsReady
      return turned(q) or (C.IsOnQuest(q) and nativeReady(q))
    end
    local need = s.when and s.when.onQuestAny and s.when.missingBag
    if need then return turned(q) or (C.IsOnQuest(q) and E.ItemCount(need.item) >= need.count) end
    if info and info.requiredItems and not (s.ph == "in") then
      return turned(q) or (C.IsOnQuest(q) and hasAll(info.requiredItems))
    end
    local supply = info and info.supply
    if supply then
      local farm = info.farmMaterial
      return turned(q) or (C.IsOnQuest(q) and E.ItemCount(supply.item) >= supply.count
        and (not farm or journalReady(q)))
    end
    if info and info.requiredLoot and info.lootFinishesWork then
      return turned(q) or (C.IsOnQuest(q) and E.ItemCount(info.requiredLoot) >= (info.lootCount or 1))
    end
    return turned(q) or (C.IsOnQuest(q) and ready(q))
  elseif t == "turnin" then return turned(q)
  elseif t == "buy" then return E.ItemCount(s.item) >= (s.n or 1) or (s.fq ~= nil and (turned(s.fq) or (C.IsOnQuest(s.fq) and ready(s.fq))))
  elseif t == "level" then return (UnitLevel("player") or 0) >= (s.lv or 0)
  elseif t == "hearth" or t == "bind" then
    local k = s.bindK or s.bind -- 中文地點
    -- 客戶端語言的地點名（GetBindLocation、區域名是這個語言）：zhTW 就是中文地點，其他語言是 Localize 給的 bindG；沒有就比不出來
    local name = s.bindG or (MG.gameZh and k) or nil
    local function same(z) return name ~= nil and z ~= nil and z ~= "" and (z == name or z:find(name, 1, true) ~= nil or name:find(z, 1, true) ~= nil) end
    if t == "bind" then
      -- 爐石現在就綁在這裡（名稱對得上：沒收到綁定事件、剛裝插件也認得）
      local b = C.Bind()
      if k and same(b) then
        MG.db.boundK, MG.db.boundRaw = k, b
        return true
      end
      -- 或綁定事件記下的就是這間（boundK；之後在別處改綁過的，bindCheck 已經清掉）
      return k ~= nil and MG.db.boundK == k
    end
    -- 爐石回 X：人已經在 X（用爐石換區時 Core 記 latch；走到下一步附近、後面任務做了也算過了，見 E.Locate）
    local sub, zone, mini = C.ZoneTexts()
    return same(sub) or same(zone) or same(mini)
  elseif t == "boat" then
    -- 人已經在目的地那張地圖（例如下船後才登入、沒收到換區事件）：算搭過了。出發港和目的地同一張地圖時看不出來，照舊
    local dest, dock = E.NodeMap(s.to), s.map or E.NodeMap(s.from)
    if map and dest and dest ~= dock and map == dest then
      MG.db.latch[step.key] = true
      return true
    end
    return false
  elseif t == "fp" then return MG.db.fpNodes ~= nil and (MG.db.fpNodes[s.nodeK or s.node] == true or MG.db.fpNodes[s.node] == true) -- 飛行地圖上已經有這個鳥點
  elseif t == "goto" or (t == "travel" and s.x) then
    if not (map and x and y) then return false end
    -- 好幾個座標（via）：依序走，走到最後一個才算到；路過第 k 點就記「@k」（箭頭改指下一點，見 E.ViaTarget）。
    -- 搭船、飛艇到別張地圖：那個點本來就是最後一點
    -- 到了沒：換成世界座標比碼數（到某處 25 碼、交通 50 碼）；步驟寫了 r（地圖 %）或換算不了就用地圖 %
    local function near(p)
      if not s.r and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local _, a = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x / 100, y / 100))
        local _, b = C_Map.GetWorldPosFromMapPos(p[1], CreateVector2D(p[2] / 100, p[3] / 100))
        if a and b then
          local ax, ay = a:GetXY()
          local bx, by = b:GetXY()
          return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) <= (t == "travel" and 50 or 25)
        end
      end
      return math.sqrt((x - p[2]) ^ 2 + (y - p[3]) ^ 2) <= (s.r or 3)
    end
    local n = 1 + (s.via and #s.via or 0)
    local k = 1
    for i = n - 1, 1, -1 do
      if MG.db.latch[step.key .. "@" .. i] then k = i + 1; break end
    end
    local p = k == 1 and { s.map, s.x, s.y } or s.via[k - 1]
    -- 已換地圖可從該圖的第一個點接回，同圖的路標仍依序走。
    while p[1] ~= map and k < n do
      k = k + 1
      p = s.via[k - 1]
    end
    if p[1] ~= map then return false end
    if k > 1 then MG.db.latch[step.key .. "@" .. (k - 1)] = true end
    -- 到了下一點或後面某一點（中途才開插件、從後段進來、點很近）：記最遠的那點，從那裡接著走，不拉回前面
    local at
    for j = n, k + 1, -1 do
      local q = s.via[j - 1]
      if q[1] == map and near(q) then at = j; break end
    end
    if not at and near(p) then at = k end
    if not at then return false end
    k = at
    local fin = k == n
    MG.db.latch[fin and step.key or (step.key .. "@" .. k)] = true
    return fin
  end
  return false
end

-- 好幾個座標的交通：已走到最遠的第幾點（0＝一點都還沒到）
function E.ViaWalked(step)
  for k = #step.s.via, 1, -1 do
    if MG.db.latch[step.key .. "@" .. k] then return k end
  end
  return 0
end
-- 好幾個座標的交通：下一個還沒走到的點 { map, x, y }
function E.ViaTarget(step)
  local s = step.s
  local walked = E.ViaWalked(step)
  -- 舊版釘在某一點（升級時搬過來的 pin.via）：還沒走到那點前箭頭指那點；釘的是已走過的點（重看）就一直指它
  local pin = step.st and MG.db.pin and MG.db.pin[step.st.id]
  local v = pin and pin.key == step.key and pin.via
  if v and (v > walked or pin.wasDone) then return v == 1 and { s.map, s.x, s.y } or s.via[v - 1] end
  return walked > 0 and s.via[walked] or { s.map, s.x, s.y }
end

-- 路線後面（第 idx 站含以後的主線站）會接手這個任務剩下的事：已接且目標都完成（或對話型）→ 後面要有「交」；
-- 已接還有目標沒完成 → 後面要有「做」（只有「交」的站不會帶人去收集）；還沒接 → 後面要有「接」。等級條件看那一站的等級上限（走到那站時的等級），種族／職業等其他條件照舊。這種不用帶過來補、離站也不用提醒
local function laterHas(q, idx)
  if not idx then return false end
  local origin = questSt[q] and questSt[q][1]
  local info = R.quests[q] or {}
  if origin and origin.index and idx > origin.index then
    if info.localVisit then return true end
    if info.localPickupRaces and raceMatch(info.localPickupRaces) and not C.IsOnQuest(q) then return true end
  end
  if localVisitFrom[q] and idx >= localVisitFrom[q] then return true end
  local need = not C.IsOnQuest(q) and "accept" or ready(q) and "turnin" or "do"
  local lv = UnitLevel("player") or 0
  for _, o in ipairs(questSt[q] or {}) do
    if not o.dungeon and o.index and o.index >= idx then
      for _, step in ipairs(o.list) do
        local s = step.s
        if s.q == q and s.t == need and E.Applies(s.when, true)
          and (not s.when or not s.when.lvMin or s.when.lvMin <= math.max(lv, o.lv[2])) then return true end
      end
    end
  end
  return false
end
-- 本站要顯示的步驟（跳站時帶來的「順路補」排在最前面）
local dungeonPreSteps
local CITY = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true } -- 暴風城、奧格瑪、鐵爐堡、雷霆崖、達納蘇斯、幽暗城
local function stepsOf(st)
  local carry = MG.db.carry[st.id]
  local pre = not st.dungeon and dungeonPreSteps(st)
  if (not carry or #carry == 0) and not pre then return st.list end
  local out = {}
  carry = carry or {}
  local here = {}
  for _, step in ipairs(st.list) do if step.s.q then here[step.s.q] = true end end
  -- 交掉的才從存檔刪；本站或後面站會接手的只在顯示時略過（之後條件變了，例如交任務要的物品丟了，還能再顯示）。重複的只顯示一次
  -- 本站有同任務但做不了剩下的事（例如只有重複的「接」）照樣展開；副本站沒有站序，照舊看本站有沒有這個任務
  for k = #carry, 1, -1 do if turned(carry[k]) then table.remove(carry, k) end end
  local shown = {}
  for _, q in ipairs(carry) do
    local hide = shown[q] or laterHas(q, st.index) or (not st.index and here[q])
    shown[q] = true
    for _, other in ipairs(not hide and questSt[q] or {}) do
      if other ~= st and not other.dungeon then
        for _, step in ipairs(other.list) do
          if step.s.q == q then out[#out + 1] = { s = step.s, key = step.key, note = step.note, st = other, carry = true } end
        end
      end
    end
  end
  local list = st.list
  local cut = #list
  while cut > 0 and SOFT[list[cut].s.t] do cut = cut - 1 end
  -- 副本前置排在本站同一張地圖上最近的那個主線步驟後面（本角色會走到的才算）；本站不到那張地圖的不排，留在副本頁進本前再接。
  -- 同一個副本的前置不往回排；前置鏈（接／做／交）有一步排不進來就整件不排
  local place, drop = {}, {}
  local last, lastD = 1, nil
  for k, step in ipairs(pre or {}) do
    local s = step.s
    if step.dungeon ~= lastD then last, lastD = 1, step.dungeon end
    local best, bd
    for i = last, s.x and cut or 0 do
      local m = list[i].s
      if m.x and m.map == s.map and E.Applies(m.when) and not optOut(m) then
        local d = (m.x - s.x) ^ 2 + (m.y - s.y) ^ 2
        if (CITY[s.map] or d <= 225) and (not bd or d <= bd) then best, bd = i, d end -- 野外超過 15 格不算順路；主城內不限
      end
    end
    if best then last, place[k] = best, best elseif s.q and s.tag == "副本前置鏈" then drop[s.q] = true end
  end
  local after = {}
  for k, step in ipairs(pre or {}) do
    local i = place[k]
    if i and not (step.s.tag == "副本前置鏈" and drop[step.s.q]) then after[i] = after[i] or {}; after[i][#after[i] + 1] = step end
  end
  for i = 1, cut do
    out[#out + 1] = list[i]
    for _, step in ipairs(after[i] or {}) do out[#out + 1] = step end
  end
  for i = cut + 1, #list do out[#out + 1] = list[i] end
  return out
end

local function deferAuthoredPrep(st, steps)
  local deferred
  for i, step in ipairs(steps) do
    local s = step.s
    if s.t == "accept" and s.when and s.when.dungeonPrep and not C.IsOnQuest(s.q) and not turned(s.q) and E.Applies(s.when) then
      if not deferred then
        if E.PreRoom(st) then return steps end
        deferred = {unpack(steps)}
      end
      local row = {}
      for k, v in pairs(step) do row[k] = v end
      row.defer = true
      deferred[i] = row
    end
  end
  return deferred or steps
end

local function gray(q)
  local info = R.quests[q]
  return info and info.lvl and info.lvl > 0 and (UnitLevel("player") or 0) - info.lvl > (C.GreenRange() or 8)
end
E.Gray = gray

-- 記下的綁點（boundK）還算不算數：boundRaw 是記的時候 GetBindLocation 的文字，文字變了＝之後在別處改綁過（插件沒開、沒收到事件）→ 清掉。
-- boundRaw＝false（剛收到綁定事件）：記下現在的文字。舊存檔沒有 boundRaw：現在的綁點對得上路線另一間旅店的名字才清，否則也記下現在的文字
local function bindCheck()
  local db = MG.db
  local b = db.boundK and C.Bind()
  if not b or b == "" then return end
  if db.boundRaw then
    if db.boundRaw ~= b then db.boundK, db.boundRaw = nil, nil end
    return
  end
  local function has(n) return n and (b == n or b:find(n, 1, true) or n:find(b, 1, true)) end
  local mine, other
  for _, x in ipairs(db.boundRaw == nil and R.stations or {}) do
    for _, s in ipairs(x.steps) do
      local k = s.t == "bind" and (s.bindK or s.bind)
      if k and has(s.bindG or (MG.gameZh and k)) then
        if k == db.boundK then mine = true else other = true end
      end
    end
  end
  if other and not mine then
    db.boundK = nil
  else
    db.boundRaw = b
  end
end

-- These two points are the Un'Goro flight master and the camp quest givers.
-- For ports we also reject an explicit different subzone (the sea shares the map).
local function nearPoint(x, y, px, py)
  return x and y and (x - px)^2 + (y - py)^2 <= 2.25
end

local function portArea(id, chinese)
  local sub, zone, mini = C.ZoneTexts()
  -- On a map transition the parent zone can still report the departure coast
  -- even after the subzone or minimap has changed to the destination port.
  if zone and zone ~= "" then
    local otherMap = id == 442 and 1438 or 1439
    local otherZone = C.MapName and C.MapName(otherMap)
    if not otherZone or otherZone == "" then otherZone = id == 442 and "泰達希爾" or "黑海岸" end
    if zone == otherZone then return false end
  end
  local expected = C.AreaName and C.AreaName(id)
  if not expected or expected == "" then expected = chinese end
  if sub and sub ~= "" and sub ~= expected then return false end
  if mini and mini ~= "" and mini ~= zone and mini ~= expected then return false end
  return sub == expected or mini == expected
end

function E.AtRutheranFlightMaster(map, x, y)
  return map == 1438 and nearPoint(x, y, 58.4, 94.02) and portArea(702, "魯瑟蘭村")
end

local function escortRecovery(steps)
  local patched
  for i, step in ipairs(steps) do
    local s = step.s
    if s.strictReady and C.IsFailed and C.IsOnQuest(s.q) and C.IsFailed(s.q) then
      patched = patched or {}
      patched[i] = { s = { t = "note", q = s.q, opt = s.opt, text = L["護送失敗。放棄後重接或略過。"] },
        key = step.key, st = step.st, carry = step.carry }
    end
  end
  if not patched then return steps end
  for i, step in ipairs(steps) do patched[i] = patched[i] or step end
  return patched
end

local function ungoroOrigin(map, x, y)
  if map == 1449 and (nearPoint(x, y, 45.23, 5.83) or nearPoint(x, y, 43.95, 7.14)) then return "camp" end
  if not map or (map == 1439 or map == 1438) and (not x or not y or x < 0 or y < 0 or x > 100 or y > 100) then return "wait" end
  if map == 1439 then
    if portArea(442, "奧伯丁") then return "port" end -- Still valid while walking between piers.
    return "wait" -- Darkshore also covers the sea. Wait for the port to be identifiable.
  end
  if map == 1438 then
    if E.AtRutheranFlightMaster(map, x, y) or (nearPoint(x, y, 55.5, 92.05) and portArea(702, "魯瑟蘭村")) then return "arrived" end
    return "wait" -- The boat and the pier at (54.8,97.2) report the same location.
  end
end

local function ungoroCityPickup()
  local q
  if me.class == "PRIEST" then q = 8254
  elseif me.class == "MAGE" and (MG.UI.Get("optional") or fill[8250]) then q = 8250 end
  if not q then return false end
  local key = "a:" .. q
  if not (C.IsOnQuest(q) or turned(q) or superseded(q) or MG.db.skip[key] or MG.db.mark[key] or MG.db.notNow[key]) then return q end
end

-- Opening a menu at a trainer confirms the player's choice. Unknown NPC/map
-- leaves the ordinary manual button available; held/finished quests are untouched.
function E.UngoroTrainerOffer(id)
  local st = E.byId[MG.db.station]
  local trainers = st and st.ungoroTrainers and st.ungoroTrainers[id]
  if not trainers then return true end
  if ungoroCityPickup() ~= id or E.LogFull() then return false end
  local map = C.Position()
  local trainer = map and trainers[map]
  local name = UnitName and UnitName("npc")
  return trainer and name and not (issecretvalue and issecretvalue(name)) and name == (trainer.npcG or trainer.npc)
end

local function boundToIronforge(st)
  local raw = C.Bind()
  if not raw or raw == "" then return false end
  -- Older versions could seed boundRaw from an unrelated inn on login.
  -- Compare with the actual game-language city name; never trust that cache here.
  return raw == st.ungoroHearth.bindG or raw == (C.MapName and C.MapName(1455)) or raw == "鐵爐堡"
end

-- A city map can include the incoming ship. Only a positively identified city
-- can supply a trainer; the harbor and incomplete location readings get text.
local function classCity(st, q, map, x, y)
  if map ~= 1453 and map ~= 1455 then return end
  if not q then
    local cityQuest = me.class == "PRIEST" and 8254 or me.class == "MAGE" and 8250
    if not cityQuest or not (C.IsOnQuest(cityQuest) or turned(cityQuest) or superseded(cityQuest)) then return end
  end
  if not x or not y then return q and "eastWait" or "wait" end
  local sub, zone, mini = C.ZoneTexts()
  local chinese = map == 1453 and "暴風城" or "鐵爐堡"
  local city = (C.MapName and C.MapName(map)) or chinese
  local region = (C.AreaName and C.AreaName(map == 1453 and 1519 or 1537)) or city
  local trainer = q and st.ungoroTrainers[q][map]
  local name = UnitName and UnitName("npc")
  local speaking = name and not (issecretvalue and issecretvalue(name)) and trainer and nearPoint(x,y,trainer.x,trainer.y) and name == (trainer.npcG or trainer.npc)
  local coast = (C.MapName and C.MapName(1439)) or "黑海岸"
  local auberdine = (C.AreaName and C.AreaName(442)) or "奧伯丁"
  if zone == coast or sub == coast or mini == coast or sub == auberdine or mini == auberdine then return q and "eastWait" or "wait" end
  if not speaking and (zone ~= city and zone ~= region and sub ~= city and mini ~= city) then return q and "eastWait" or "wait" end
  if map == 1453 then
    if not q then return "stormReturn" end
    local harbor = (C.AreaName and C.AreaName(17203)) or "暴風港"
    if not speaking and (sub == harbor or mini == harbor or nearPoint(x, y, 21.8, 56.9)) then return "stormDock" end
  end
  return q and "cityPickup" or "ironReturn"
end

local function eastItinerary(steps, st, stage, q, map)
  local out = {}
  for i, w in ipairs(steps) do
    local s = w.s
    if stage == "ironReturn" and s.ungoroExit == "camp" then
      -- The pin is the local departure desk. Only landing at Menethil completes the flight.
      local source = st.ungoroIronReturn
      out[i] = {s={t="fly", to=s.to, toL=s.toL, map=source.map, x=source.x, y=source.y,
        desc=source.text, classTransfer=true, ironReturn=true}, note=source, key=w.key, st=w.st}
    elseif not s.ungoroExit or s.ungoroExit == "islandPortal"
      or (stage == "ironReturn" and s.ungoroExit ~= "east") then out[i] = w
    elseif stage == "cityPickup" and s.t == "accept" and s.q == q then
      out[i] = {s=st.ungoroTrainers[q][map], key=w.key, note=w.note, st=w.st}
    elseif (s.t == "hearth" and st.ungoroHints[stage] and stage ~= "stormReturn")
      or (s.ungoroExit == "ship" and stage == "stormReturn") then
      out[i] = {s={t="travel", text=st.ungoroHints[stage], classTransfer=true}, key=w.key, st=w.st}
    else
      out[i] = {s=s, key=w.key, note=w.note, st=w.st, transferHidden=true}
    end
  end
  return out
end

-- Keep the original last flight key for pins and manual progress. Only its
-- current instruction changes; the serialized itinerary is never rewritten.
local function ungoroTransfer(steps, hint)
  local result = {}
  for i, step in ipairs(steps) do
    local s = step.s
    if s.ungoroExit == "port" and hint then
      result[i] = {key=step.key, st=step.st, s={t="travel", text=hint, to=s.to, localTransfer=true}}
    else
      result[i] = step
    end
  end
  return result
end

local function instanceMaterialAction(s)
  local item = R.keep[s.instanceMaterial]
  local hunt = item and (item.n .. " ×1")
  if hunt and s.componentNpc then hunt = s.componentNpc .. " / " .. hunt end
  return { t = "do", q = s.q, ph = "in", when = s.when, hint = hunt, componentNpc=s.componentNpc, componentNpcG=s.componentNpcG }
end

local function instanceZone()
  return { GetSubZoneText and GetSubZoneText() or "", GetMinimapZoneText and GetMinimapZoneText() or "" },
    GetLocale and GetLocale() or "zhTW"
end

local function inNamedWing(stationId, texts, loc)
  local names = MG.Wings and MG.Wings[stationId]
  for _, name in ipairs(names and (names[loc] or names.enUS) or {}) do
    for _, text in ipairs(texts) do if text ~= "" and text == name then return true end end
  end
  return false
end

local function stratholmeWing(d)
  if not inList(d.inst or {}, 329) then return end
  local texts, loc = instanceZone()
  local scarlet = inNamedWing("05-d26", texts, loc)
  local undead = inNamedWing("05-d27", texts, loc)
  if scarlet ~= undead then return scarlet and "scarlet" or "undead" end
end

-- In the active route HUD an outdoor contact is unavailable while the native client is inside,
-- even on the frame before its instance ID becomes known. Manual phase previews are separate.
local function worldContact(s)
  return s.outsideHandoff or (s.ph == "post" and (s.manualAccept or (s.when and s.when.manualPickup)))
    or (s.outsideObjective and s.ph == "pre")
end

-- A completed component awaiting its outdoor recipient keeps a deliberately selected run open.
function E.OutdoorHandoff(st)
  if not (st and st.dungeon and st.componentVisit) then return nil end
  for _, row in ipairs(st.list) do
    local s = row.s
    if s.t == "turnin" and worldContact(s) and C.IsOnQuest(s.q) and not turned(s.q)
        and not MG.db.skip[row.key] and not MG.db.mark[row.key] and E.Applies(s.when) then
      return s.q
    end
  end
end

-- Record only a selected side-run which really deferred its ready world handoff.
-- The station id survives a reload. Explicit station selection or cancellation clears it.
function E.DeferOutdoorHandoff(st, id)
  local q = E.OutdoorHandoff(st)
  if q and MG.db.station == st.id and MG.db.dungeonFrom and (not id or id == 0 or inList(st.inst or {}, id)) then
    MG.db.deferredHandoffRun = st.id
  end
  return q
end

-- ── locate ──────────────────────────────────────────────────────────────────
local function shallowCopy(source)
  local copy = {}
  for k, value in pairs(source) do copy[k] = value end
  return copy
end

-- 回 { st, steps, done[], na[], cur, auto, missed = { {q, i}... }, complete }
function E.Locate(st)
  local db = MG.db
  bindCheck()
  pickAny(st.list)
  local fillInfo = E.FillPlan(st)
  local steps = escortRecovery(stepsOf(st))
  pickAny(steps)
  if not st.dungeon then steps = deferAuthoredPrep(st, steps) end
  -- 同一工作和舊釘選仍有效，失去破盾武器時暫收精英的目標與地圖點。
  local adjusted
  local physical = IsInInstance and IsInInstance()
  local id = physical and GetInstanceInfo and select(8, GetInstanceInfo())
  local wing = id == 329 and st.dungeon and stratholmeWing(st)
  for i, step in ipairs(steps) do
    local s = step.s
    local info = s.t == "do" and s.q and R.quests[s.q]
    local weapon = info and info.combatWeapon
    local farm = info and info.farmMaterial
    local trophyHeld = info and info.requiredLoot and E.ItemCount(info.requiredLoot) >= (info.lootCount or 1)
    local killsDone = info and info.killCount and (huntCount(s.q, info) or 0) >= info.killCount
    local farmDone = trophyHeld or killsDone or (farm and E.ItemCount(farm.item) >= farm.count)
    local action
    if s.t == "turnin" and s.providedVisit and C.IsOnQuest(s.q) and not turned(s.q)
        and E.ItemCount(s.providedVisit) > 0 and not journalReady(s.q) then
      -- The object can be visited with the issued item; only the server can confirm the hand-in.
      action = {}
      for k,v in pairs(s) do action[k] = v end
      action.t, action.hint, action.when = "do", s.desc, {}
      for k,v in pairs(s.when) do if k ~= "readyQuest" then action.when[k] = v end end
    elseif info and info.riftTools then
      action = {}
      for k, v in pairs(s) do action[k] = v end
      action.riftPhase = E.RiftPhase()
      local p = info.riftTools[action.riftPhase]
      if p then action.map, action.x, action.y = p[1], p[2], p[3]
      elseif action.riftPhase == "journal" then action.map, action.x, action.y = nil, nil, nil end
    elseif farmDone or (weapon and not hasWeapon(weapon)) then
      action = {}
      for k, v in pairs(s) do action[k] = v end
      action.map, action.x, action.y, action.more = nil, nil, nil, nil
      action.missingWeapon = weapon and true or nil
      action.farmDone = farmDone
      action.awaitJournal = farm and farmDone and (not info.supply or E.ItemCount(info.supply.item) >= info.supply.count)
    elseif s.instanceMaterial and physical and inList(st.inst or {}, id) then
      action = instanceMaterialAction(s)
    end
    if action then
      adjusted = adjusted or {unpack(steps)}
      local row = {}
      for k, v in pairs(step) do row[k] = v end
      row.s = action
      adjusted[i] = row
    end
  end
  steps = adjusted or steps
  local surveySteps
  for i, step in ipairs(steps) do
    local q = step.s.q
    local survey = step.s.t == "do" and q and R.quests[q] and R.quests[q].survey
    if survey and C.IsOnQuest(q) then
      surveySteps = surveySteps or {unpack(steps)}
      surveySteps[i] = surveyStep(step, survey)
    end
  end
  steps = surveySteps or steps
  local n = #steps
  local map, x, y = C.Position()
  local done, na, autoDone, low = {}, {}, {}, {}
  local lv = UnitLevel("player") or 0
  local transfer, classNeedsSpace
  if st.ungoroHints and lv >= 51 then
    local q = ungoroCityPickup()
    local origin = ungoroOrigin(map, x, y)
    local stage = classCity(st, q, map, x, y)
    classNeedsSpace = q and E.LogFull()
    if classNeedsSpace and stage then stage = "eastWait" end
    if not stage and q and origin then
      if classNeedsSpace and (origin == "camp" or origin == "port") then
        transfer = origin -- Existing local turn-ins can free the needed slot.
      elseif classNeedsSpace or origin == "wait" then stage = "eastWait"
      elseif not boundToIronforge(st) then
        stage = origin == "camp" and "eastCamp" or origin == "port" and "eastPort" or "eastWait"
      end
    end
    if stage then steps = eastItinerary(steps, st, stage, q, map)
    elseif transfer or (not q and origin) then
      transfer = origin
      steps = ungoroTransfer(steps, st.ungoroHints[transfer])
    end
  end
  -- 本站有接取步驟的任務；沒有的（在之前的站接）不在日誌就不能做也不能交，不排進來
  local acc = {}
  local portableSteps
  -- 接取等級還不夠的任務（不在日誌、沒交過）：接、做、交都先列出來但不輪到它
  local lowQ = {}
  for i, step in ipairs(steps) do
    local s = step.s
    if s.pickupItem and E.ItemCount(s.pickupItem) > 0 then
      -- 拾取點只在物品尚未入袋時使用。沿用原步驟鍵，讓舊釘選和手動進度照常生效。
      portableSteps = portableSteps or shallowCopy(steps)
      local portable = shallowCopy(s)
      portable.map, portable.x, portable.y, portable.more = nil, nil, nil, nil
      local row = shallowCopy(step)
      row.s, row.note = portable, portable.desc and {text=portable.desc}
      portableSteps[i] = row
    end
    if s.t == "accept" and s.q then
      if E.Applies(s.when) and not optOut(s) and not step.defer and not s.any then acc[s.q] = true end -- 接取步驟本身不適用（種族、職業、可跳過沒開、日誌快滿先不接）就不算本站有接
      local need = s.pickLv or (R.quests[s.q] or {}).min -- 步驟沒寫接取等級就用任務資料的最低等級
      if need and lv < need and not C.IsOnQuest(s.q) and not turned(s.q) then lowQ[s.q] = need end
    end
  end
  steps = portableSteps or steps
  local lowLv = {}
  -- 「接不到」記在接取步驟的鍵上（同站同任務第二個接取點是 a:任務~2）：換成任務 ID，接、做、交一起收起來
  local notNowQ = {}
  for k in pairs(db.notNow) do
    local q = tonumber(k:match("^a:(%d+)"))
    if q then notNowQ[q] = true end
  end
  -- 前置還沒交，但本站前面排了它的「交」（會做到）：後續任務先列出來（wait），不輪到它，等前置交了才變成一般步驟
  -- turnAt[q]＝本站還沒做、適用的「交 q」在第幾步；off(j)＝那一步不算數（漏掉了、不在這一輪）
  local turnAt, wait = {}, {}
  local function planned(q, off)
    local info = R.quests[q]
    local function ok(p) return turned(p) or (turnAt[p] and not (off and off(turnAt[p]))) end
    for _, p in ipairs(info.pg or {}) do if not ok(p) then return false end end
    if info.ps and #info.ps > 0 then
      for _, p in ipairs(info.ps) do if ok(p) then return true end end
      return false
    end
    return true
  end
  local mainland = transfer == "camp" or transfer == "port"
  local fullOnMainland = mainland and E.LogFull()
  local localLeg, islandErrand
  local waitingRingReturn
  for i, step in ipairs(steps) do
    local s = step.s
    local open = not s.q or available(s.q)
    local wrongWing = s.wing and (id ~= 329 or (s.wing ~= "either" and s.wing ~= wing))
    na[i] = wrongWing or step.transferHidden or (transfer and s.ungoroExit ~= nil and s.ungoroExit ~= "islandPortal") or (physical and (worldContact(s) or s.instanceMaterial)) or ((s.t == "do" or s.t == "turnin") and s.q and not acc[s.q] and not C.IsOnQuest(s.q) and not turned(s.q)) or step.defer or (s.q and notNowQ[s.q] and not C.IsOnQuest(s.q)) or s.t == "need" or not E.Applies(s.when) or (s.q and not raceOK(s.q)) or db.skip[step.key] or optOut(s) or (s.q and (excluded(s.q) or superseded(s.q) or not (open or planned(s.q)))) or (s.fq and (excluded(s.fq) or not raceOK(s.fq) or turned(s.fq))) or false
    if s.t == "turnin" and s.outsideObjective and isCleanedRingReturn(s.q) and not turned(s.q)
        and (physical or not ready(s.q)) then
      na[i], waitingRingReturn = true, i
    end
    -- 只差等級（【N 級起】）的步驟：現在不能做，但清單照樣列出來（灰、寫幾級），免得以為這站快做完了
    if na[i] and s.when and s.when.lvMin and lv < s.when.lvMin and not turned(s.q or 0) and not db.skip[step.key] then
      local w = {}
      for k, v in pairs(s.when) do w[k] = v end
      w.lvMin = nil
      low[i] = E.Applies(w) and not (s.q and (not raceOK(s.q) or excluded(s.q))) and not optOut(s) or nil
      lowLv[i] = low[i] and s.when.lvMin
    elseif not na[i] and s.q and lowQ[s.q] and QUEST[s.t] then
      na[i], low[i], lowLv[i] = true, true, lowQ[s.q]
    end
    local auto = stepDone(step) -- 先讀既有進度，位置到達只在輪到該步時寫入
    autoDone[i] = auto
    local mark = db.mark[step.key]
    if mark ~= nil and mark == auto then db.mark[step.key] = nil; mark = nil end
    done[i] = na[i] or (mark ~= nil and mark) or (mark == nil and auto)
    wait[i] = not na[i] and not open or nil
    if s.t == "turnin" and s.q and not done[i] then turnAt[s.q] = i end
    if transfer then
      if s.localTransfer then
        localLeg = i
      elseif not done[i] and not wait[i] and (s.map == 1438 or s.map == 1457) then
        -- Use the route's own race, class, prerequisites, skips and current log.
        -- A quest already held for a later Azshara hand-in is not an island pickup.
        if s.t == "accept" and not C.IsOnQuest(s.q) and not turned(s.q) then
          if fullOnMainland then na[i], done[i] = true, true else islandErrand = true end
        elseif s.t == "turnin" and C.IsOnQuest(s.q) and ready(s.q) then
          islandErrand = true
        end
      end
    end
  end
  if localLeg and not islandErrand then
    if classNeedsSpace then
      steps[localLeg].s.text = st.ungoroHints.eastWait
    else
      na[localLeg], done[localLeg] = true, true
    end
    if mainland then
      for i, step in ipairs(steps) do
        if step.s.ungoroExit == "islandPortal" then na[i], done[i] = true, true end
      end
    end
  end
  -- 軟步驟（交通、到達、鳥點、飛行、船）：後面有本站接的任務步驟已完成、或任一任務已交，就算過了（別站帶來的任務「做」完成不算）；
  -- 後面已沒有任務步驟的（往下一站的交通）不擋路，文字留給「前往下一站」顯示
  -- passed：被後面任務帶過的軟步驟（當作過了，但清單不打勾）；tails：站尾往下一站的交通（任務都做完才輪到它）
  local tail, tails, passed, here, softLater, left = nil, {}, {}, {}, {}, {}
  for _, step in ipairs(steps) do if step.s.t == "accept" and not step.carry then here[step.s.q] = true end end
  local nxt = E.Next(st)
  for i, step in ipairs(steps) do
    if not done[i] and SOFT[step.s.t] and not step.s.classTransfer then -- 開鳥點不會被後面的進度帶過：要真的開了（飛行地圖／對話開點）才算
      local later = false
      for j = i + 1, n do
        -- 後面仍要綁爐石或補給，前往該處的路標就不是站尾交通。
        if not done[j] and not SOFT[steps[j].s.t] and not na[j] then later = true end
        if steps[j].s.q and not na[j] and not (step.s.localTransfer or step.s.classTransfer) then
          later = true
          if step.s.t ~= "fp" and done[j] and (steps[j].s.t == "turnin" or here[steps[j].s.q]) then done[i] = true; passed[i] = true; break end
        end
      end
      softLater[i] = not (step.s.localTransfer or step.s.classTransfer) and not done[i] and later and (not step.s.x or step.s.t == "boat") and map ~= nil and x ~= nil and y ~= nil -- 沒座標的交通（船的座標是碼頭）：輪到它時才看人到了沒（見下面）
      -- 已經到下一站的地圖：站尾交通算到了；鳥點沒開不打勾，只是不再拉回去（left）。
      -- 鳥點和下一站同一張地圖時，人在這張地圖上不代表已經離開，照樣帶去開點
      local onNext = nxt and map and map == nxt.map
      if step.s.t == "fp" then left[i] = onNext and step.s.map ~= map end
      if not later then
        tails[i] = true
        tail = tail or step.s.text
        if onNext and step.s.t ~= "fp" then done[i] = true end
      end
    end
  end

  -- 由前往後找未完成；後面 8 個（別的任務的）任務步驟過半已完成 → 算漏掉
  local auto, missedIdx, missedQ
  local roamQ = {} -- 順路任務還沒做完：它的交任務步驟也先不輪到
  for i = 1, n do if steps[i].s.roam and not done[i] and not na[i] then roamQ[steps[i].s.q or 0] = true end end
  local accAt = {} -- 還沒接的任務，它的「接」排在第幾步（副本前置的接插在站尾，主線的做／交可能排在它前面）
  for i = 1, n do if steps[i].s.t == "accept" and not done[i] and not na[i] then accAt[steps[i].s.q] = accAt[steps[i].s.q] or i end end
  local function arrive(i)
    local step = steps[i]
    if done[i] or db.mark[step.key] == false then return false end
    local s = step.s
    if s.x and (s.t == "goto" or s.t == "travel") then
      if not stepDone(step, map, x, y) then
        -- 好幾點的路標：人已經走到下一步那裡（例如翻過山站在洛克莫丹的巡山人旁）就算走完了
        if not (s.via and map and x and y and E.SoftNear(s, E.SoftTargets(steps, done, na, i), map, x, y)) then return false end
        db.latch[step.key] = true
      end
    elseif s.t == "boat" and stepDone(step, map, x, y) then
      -- 已在對岸（stepDone 記下了）
    elseif softLater[i] and E.SoftNear(s, E.SoftTargets(steps, done, na, i), map, x, y) then
      db.latch[step.key] = true
    else
      return false
    end
    done[i], autoDone[i] = true, true
    return true
  end
  repeat
    auto, missedIdx, missedQ = nil, {}, {}
    for i = 1, n do
      local q = steps[i].s.q
      if tails[i] or wait[i] or steps[i].s.roam or (q and steps[i].s.hold and not ready(q)) or (q and roamQ[q] and steps[i].s.t == "turnin") or (q and steps[i].s.t ~= "accept" and (accAt[q] or 0) > i and not C.IsOnQuest(q)) then
        -- 等前置的後續任務：不輪到它、也不算漏掉（前置的「交」排在它前面）
        -- 站尾交通先跳過，任務步驟都處理完才輪到
        -- 順路任務（怪散在整區）：不搶目前步驟，路上遇到就打；其他步驟都做完還沒完成才輪到
      elseif not done[i] and steps[i].s.t == "fp" then
        if not left[i] then auto = i; break end -- 開鳥點沒有任務可推斷：沒開就輪到它，不算漏掉；人已到下一站就不拉回去
      elseif not done[i] and q and missedQ[q] then
        missedIdx[#missedIdx + 1] = i -- 同一任務前面的步驟已漏掉（例如沒接就輪到交）
      elseif not done[i] and q and steps[i].s.t ~= "accept" and not (steps[i].s.tag and steps[i].s.tag:find("怪多", 1, true)) and C.IsOnQuest(q) then
        auto = i; break -- 任務還在日誌裡（例如做到一半）：不算漏掉，就是目前要做的；順路先做了後面的步驟也不會被跳過去。「怪多」的可跳過任務除外（順手打到也不拉回去）
      elseif not done[i] and steps[i].s.pick and steps[i].s.fq and C.IsOnQuest(steps[i].s.fq) then
        auto = i; break -- 撿任務物品：關聯任務還在日誌、東西還沒撿到，就是目前要做的；同站其他任務做完了也不算漏掉（手動略過照舊）
      elseif not done[i] and ((steps[i].s.t == "accept" and not steps[i].s.opt) or steps[i].s.t == "level" or steps[i].s.localTransfer or steps[i].s.classTransfer) then
        auto = i; break -- 必做的「接」和練等步驟：適用、還沒做就輪到它，不因為後面別的任務做過了就當成漏掉（那些可能是提前做副本前置時交掉的）
      elseif not done[i] then
        local seen, d, j = 0, 0, i + 1
        while j <= n and seen < 8 do
          local s2 = steps[j].s
          if s2.q and s2.q ~= steps[i].s.q and not na[j] and not wait[j] and not dunQ[s2.q] then -- 也是副本前置的任務不算（插進來的、主線裡同一件的都一樣）：提前做副本前置時就交掉了，不代表走過這一段
            seen = seen + 1
            if done[j] then d = d + 1 end
          end
          j = j + 1
        end
        if seen > 0 and d * 2 > seen then
          missedIdx[#missedIdx + 1] = i
          if q then missedQ[q] = true end
        else
          auto = i; break
        end
      end
    end
    if not auto then
      for i = 1, n do if steps[i].s.roam and not done[i] and not na[i] then auto = i; break end end
    end
    if not auto then
      for i = 1, n do if tails[i] and not done[i] and not na[i] and not left[i] then auto = i; break end end
    end
    local arrived = auto and arrive(auto)
  until not arrived
  -- 前置的「交」被判成漏掉：等它的後續任務照舊不適用（依序往後，整條鏈一起收）
  local missedAt = {}
  for _, i in ipairs(missedIdx) do missedAt[i] = true end
  for i = 1, n do
    local q = steps[i].s.q
    if wait[i] and not planned(q, function(j) return missedAt[j] end) then
      na[i], done[i], wait[i] = true, true, nil
      if turnAt[q] == i then turnAt[q] = nil end
    end
  end
  -- 手動釘住的步驟：原本未完成、後來完成了就放掉；釘回自動位置也放掉
  local cur = auto
  local pin = db.pin[st.id]
  if pin then
    local found
    for i, step in ipairs(steps) do
      if step.key == pin.key then found = i; break end
    end
    if found and not na[found] then arrive(found) end
    local pinned = found and steps[found].s
    -- 舊版釘在合併路標的某一點（pin.via）：就算剛好是目前這步也留著，箭頭先指那一點（E.ViaTarget）
    -- 釘的那一點走到了、或已走到更後面的點（沒走過才釘的）：和整步完成一樣放開
    local viaDone = found and pin.via and steps[found].s.via and E.ViaWalked(steps[found]) >= pin.via
    local waitingMaterials = pinned and pinned.t == "turnin" and R.quests[pinned.q] and (R.quests[pinned.q].farmMaterial or R.quests[pinned.q].riftTools or R.quests[pinned.q].deliveryItems)
      and C.IsOnQuest(pinned.q) and not journalReady(pinned.q)
    local pinInfo = pinned and pinned.q and R.quests[pinned.q]
    local visitQuest = pinInfo and (pinInfo.localVisit or pinInfo.providedVisit or pinInfo.requiredLoot or pinInfo.killCount)
    local unavailableVisit = pinned and pinned.when and ((pinned.when.workMap and not turned(pinned.q)) or pinned.when.localVisit or (visitQuest and not turned(pinned.q))) and not E.Applies(pinned.when)
    local unavailableHunt = pinInfo and (pinInfo.requiredLoot or pinInfo.killCount) and pinned.t == "do" and not turned(pinned.q)
      and (not C.IsOnQuest(pinned.q) or journalReady(pinned.q))
    local unavailableWingStep = pinned and pinned.wing and na[found]
    local leftLocalContact = pinned and st.dungeon and pinned.when and pinned.when.nearPoint and not E.Applies(pinned.when)
    local escortUnavailable = pinned and pinned.q and pinned.when and pinned.when.onQuestAny and pinned.when.notFailedQuest == pinned.q
      and not turned(pinned.q) and not E.Applies(pinned.when)
    -- 副本前置的接取：關了副本前置或這本選「不打」時先不跟，釘選保留，重新打開就回來（已接的照常放開）
    local prepOff = pinned and pinned.t == "accept" and pinned.when and pinned.when.dungeonPrep and not C.IsOnQuest(pinned.q) and not turned(pinned.q)
      and not E.Applies(pinned.when)
    if prepOff or (found and found == waitingRingReturn) or unavailableWingStep or leftLocalContact or escortUnavailable or unavailableHunt or unavailableVisit or waitingMaterials or (pinned and physical and (worldContact(pinned) or pinned.instanceMaterial)) then
      -- Leave the saved pin in place and use the available work until it becomes actionable.
    elseif pinned and pinned.t == "turnin" and pinned.outsideObjective and isCleanedRingReturn(pinned.q) and not done[found] then
      -- An unfinished ring return keeps its pin when a prerequisite elsewhere becomes available.
      cur = found
    elseif not found or ((done[found] or viaDone) and not pin.wasDone) or (found == auto and not pin.via) or (pin.auto and (auto and steps[auto].key or "") ~= pin.auto) then
      db.pin[st.id] = nil
    else
      cur = found
    end
  end

  -- 漏掉清單：以任務合併，只列還能做的
  local missed, seenQ, missedSet = {}, {}, {}
  for _, i in ipairs(missedIdx) do
    local q = steps[i].s.q
    if q then missedSet[q] = true end
  end
  for _, i in ipairs(missedIdx) do
    local q = steps[i].s.q
    if q and not seenQ[q] and not steps[i].s.any then -- 任一組的接是自選的，沒接不算漏掉
      seenQ[q] = true
      local info = R.quests[q] or {}
      local onQ = C.IsOnQuest(q)
      local ok = not turned(q) and (onQ or ((UnitLevel("player") or 0) >= (info.min or 0) and not gray(q)))
      if ok and not onQ then
        for _, p in ipairs(info.pg or {}) do if not turned(p) and not missedSet[p] then ok = false end end
        if info.ps and #info.ps > 0 then
          local any = false
          for _, p in ipairs(info.ps) do if turned(p) or missedSet[p] then any = true end end
          ok = ok and any
        end
      end
      if ok then missed[#missed + 1] = { q = q, i = i } end
    end
  end

  -- 相對編號：目前步驟＝1，之後還沒做的依序 2、3…；做完、不適用、漏掉的不編號。total＝剩幾步
  local num, total = {}, 0
  if cur then
    total = 1; num[cur] = 1
    -- 順路任務還沒打完：它的「交」先不編號、不上地圖（打完才排進去）
    for i = cur + 1, n do
      local s = steps[i].s
      if ((not na[i] and not done[i]) or low[i]) and not (s.t == "turnin" and s.q and roamQ[s.q]) then total = total + 1; num[i] = total end
    end
  end
  -- 附近可一起做的步驟：目前步驟之後 8 步內，還沒做、已在日誌的「做」（或同地點的接／交），
  -- 座標靠近目前步驟（或已併入的步驟）；遇到交通、爐石、飛行、船就停
  local group, inGroup = {}, {}
  local UI = MG.UI
  local cs = cur and steps[cur].s
  if cur and UI.Get("groupOn") and cs.x and not travelBoundary(cs) then
    local maxN, dist = UI.Get("groupMax") - 1, UI.Get("groupDist")
    -- 一個步驟的所有點（主座標＋目標點）
    local function ptsOf(s)
      local pts = { s.x and { s.map, s.x, s.y } or nil }
      for _, p in ipairs(s.more or {}) do pts[#pts + 1] = p end
      return pts
    end
    -- 錨點：目前步驟離玩家最近的那個點（目標點散在整區時，只看玩家要去的那一處）
    local function nearest(pts, m, px, py)
      local best, bd
      for _, p in ipairs(pts) do
        if p[1] == m then
          local d = (p[2] - px) ^ 2 + (p[3] - py) ^ 2
          if not bd or d < bd then best, bd = p, d end
        end
      end
      return best, bd
    end
    local spots = {}
    local anchor = (map and x and nearest(ptsOf(cs), map, x, y)) or { cs.map, cs.x, cs.y }
    spots[1] = anchor
    -- 候選步驟：取它離任一已選點最近的那個點，在距離內就併入，並把那個點加進來
    local function near(s)
      for _, q in ipairs(spots) do
        local p, d = nearest(ptsOf(s), q[1], q[2], q[3])
        if p and d <= dist * dist then return p end
      end
    end
    for i = cur + 1, n do
      if #group >= maxN or (num[i] and num[i] > 9) then break end
      local s = steps[i].s
      if not done[i] and not na[i] then
        if travelBoundary(s) then break end
        -- 等前置的「接」：前置的「交」就是目前步驟或已併進來（同一個人交了接著接）才併
        local ok = (s.t == "do" and s.q and C.IsOnQuest(s.q)) or (s.t == "accept" and (not wait[i] or planned(s.q, function(j) return j ~= cur and not inGroup[j] end))) or (s.t == "turnin" and s.q and C.IsOnQuest(s.q) and ready(s.q))
        local p = ok and near(s)
        if p then
          group[#group + 1] = i
          inGroup[i] = true
          spots[#spots + 1] = p
        end
      end
    end
  end
  -- 順路任務（已在日誌、還沒做完）常駐在上方框最下面，提醒路上遇到就打；不受「附近一起做」的距離與數量限制
  for i = 1, n do
    local s = steps[i].s
    if s.roam and i ~= cur and not inGroup[i] and not done[i] and not na[i] and s.q and C.IsOnQuest(s.q) then
      group[#group + 1] = i
      inGroup[i] = true
    end
  end
  local deferred = physical and E.DeferOutdoorHandoff(st, id)
  local pendingExit = not cur and deferred or nil
  return { pendingExit = pendingExit, roamQ = roamQ, group = group, inGroup = inGroup, fill = fill, fillInfo = fillInfo, num = num, total = total, autoDone = autoDone, st = st, steps = steps, done = done, na = na, wait = wait, low = low, lowLv = lowLv, cur = cur, auto = auto, missed = missed, complete = auto == nil and not pendingExit, map = map, tail = tail, tails = tails, passed = passed }
end

-- ── 站 ──────────────────────────────────────────────────────────────────────
-- 完成數／總數（以任務計）
function E.Progress(st)
  local total, got, seen = 0, 0, {}
  for _, step in ipairs(st.list) do
    local q = step.s.q
    if q and not seen[q] and E.Applies(step.s.when) and not optOut(step.s) and raceOK(q) and not superseded(q) and not (anyQ[q] and not C.IsOnQuest(q) and not turned(q)) then
      seen[q] = true
      total = total + 1
      local m = MG.db.mark["t:" .. q]
      if m == true or (m == nil and turned(q)) then got = got + 1 end
    end
  end
  return got, total
end

local function inLogCount(st, log)
  local n, seen = 0, {}
  for _, step in ipairs(st.list) do
    local q = step.s.q
    if q and log[q] and not seen[q] then seen[q] = true; n = n + 1 end
  end
  return n
end

-- 裝上或重新對齊時選站：日誌裡的任務 > 所在地圖 > 等級
function E.PickStation()
  local lv = UnitLevel("player") or 1
  local map = C.Position()
  local log = {}
  for _, q in ipairs(C.LogQuestIDs() or {}) do log[q] = true end
  local best, bestScore
  for _, st in ipairs(E.stations) do
    local got, total = E.Progress(st)
    if got < total then
      local score = inLogCount(st, log) * 3
      if map and st.map == map then score = score + 2 end
      if lv >= st.lv[1] and lv < st.lv[2] then score = score + 2
      elseif lv >= st.lv[1] - 2 and lv <= st.lv[2] + 2 then score = score + 1 end
      if lv > st.lv[2] + 4 then score = score - 3 end
      if not bestScore or score > bestScore then best, bestScore = st, score end
    end
  end
  if best and bestScore > 0 then return best end
  for _, st in ipairs(E.stations) do
    local got, total = E.Progress(st)
    if got < total and lv <= st.lv[2] then return st end
  end
  return best or E.stations[#E.stations]
end

function E.Current()
  local st = MG.db.station and E.byId[MG.db.station]
  if not st then
    st = E.PickStation()
    if st then MG.db.station = st.id end
  end
  return st
end

function E.Next(st)
  if st and st.id == "01-6" and st.start == "NightElf" and MG.db.auberdineChoice == "coast" then
    return E.byId["02-10"]
  end
  if st and st.dungeon then return nil end
  return st and E.stations[st.index + 1]
end

-- 超等建議：等級 > 本站上限時，路線上第一個等級合適且未完成的站
function E.Suggest(st)
  local lv = UnitLevel("player") or 1
  if not st or lv <= st.lv[2] then return nil end
  for _, other in ipairs(E.stations) do
    if other ~= st and lv >= other.lv[1] and lv <= other.lv[2] then
      local got, total = E.Progress(other)
      if got < total then return other end
    end
  end
end

-- 跳站：中間略過的站未交任務分「順路補」與「可放掉」。JumpPlan 只算不改（「下一站」提示列的滑鼠提示先給玩家看）
function E.JumpPlan(target)
  local from = E.Current()
  local carry, dropN = {}, 0
  if from and from.index and target.index > from.index then
    local seen = {} -- 整趟跳站一起去重（同一任務的接／交分在不同略過的站）
    local function add(q)
      if not seen[q] and not turned(q) and not laterHas(q, target.index) then
        seen[q] = true
        local info = R.quests[q] or {}
        if info.chain or info.keep or (C.IsOnQuest(q) and not gray(q)) then carry[#carry + 1] = q else dropN = dropN + 1 end
      end
    end
    -- 出發站之前帶來的補做也一起往下帶（連跳兩次時第一次帶來、還沒做完的不會掉）
    for _, q in ipairs(MG.db.carry[from.id] or {}) do add(q) end
    for k = from.index, target.index - 1 do
      for _, step in ipairs(E.stations[k].list) do
        if step.s.q and E.Applies(step.s.when) then add(step.s.q) end
      end
    end
  end
  return carry, dropN, from
end
function E.Jump(target)
  local db = MG.db
  db.deferredHandoffRun = nil
  local carry, _, from = E.JumpPlan(target)
  if from and from.index and target.index > from.index then
    for k = from.index + 1, target.index - 1 do db.drop[E.stations[k].id] = true end
  end
  db.carry[target.id] = #carry > 0 and carry or nil
  db.drop[target.id] = nil
  db.station = target.id
  db.pin[target.id] = nil
end

function E.Select(st)
  MG.db.deferredHandoffRun = nil
  MG.db.station = st.id
  MG.db.drop[st.id] = nil
end

-- 手動上一步/下一步（delta = -1 / 1）
function E.Move(state, delta)
  local i = (state.cur or #state.steps + 1) + delta
  while state.steps[i] and state.na[i] do i = i + delta end
  local step = state.steps[i]
  if not step then return end
  if i == state.auto then MG.db.pin[state.st.id] = nil
  else E.PinIndex(state, i) end
end

function E.PinIndex(state, i)
  local step = state.steps[i]
  if not step then return end
  MG.db.pin[state.st.id] = { key = step.key, wasDone = state.done[i] and true or false, auto = state.auto and state.steps[state.auto].key or "", via = false }
end

-- 略過（連帶）：略過「接」或「做」→ 這個任務的接／做／交 ＋ 後續任務的全部步驟；略過「交」→ 只連帶後續任務。
-- 存法：skip[key] = 起點的 key（起點自己也存自己＝手動略過）；連帶的每次切換重算（E.ToggleSkip）。
local function questName(q) return E.QName(q) end
-- ── 跨站提醒 ──────────────────────────────────────────────────────────────────
local function place(o, st)
  if o.dungeon then return L["%s 副本"]:format(o.name) end
  return o.name .. ((st and o ~= st and o.map == st.map) and L["，第二次來"] or "")
end
-- 這個任務（含後續鏈）在 st 之後的站或副本還有步驟 → { {q, st}... }，每站列一次
function E.Impact(q, st)
  local out, seen, seenSt, queue = {}, { [q] = true }, {}, { q }
  while #queue > 0 do
    local cur = table.remove(queue, 1)
    for _, o in ipairs(questSt[cur] or {}) do
      if o ~= st and not seenSt[o] and (o.dungeon or (o.index and st.index and o.index > st.index)) then
        seenSt[o] = true
        out[#out + 1] = { q = cur, st = o }
      end
    end
    for _, f in ipairs((R.quests[cur] or {}).fol or {}) do
      if not seen[f] then seen[f] = true; queue[#queue + 1] = f end
    end
  end
  return out
end
function E.ImpactText(imp, st)
  local parts = {}
  for k, x in ipairs(imp) do
    if k > 2 then parts[#parts] = parts[#parts] .. L[" 等 %d 處"]:format(#imp); break end
    parts[#parts + 1] = questName(x.q) .. L["（%s）"]:format(place(x.st, st))
  end
  return L["影響後續："] .. table.concat(parts, L["、"])
end
-- 離站前：本站還沒做完（或略過）的任務中，會影響後續站的
function E.Leaving(state)
  local out, seen = {}, {}
  if state.instance or state.st.dungeon then return out end
  for i, step in ipairs(state.steps) do
    local q = step.s.q
    local skipped = MG.db.skip[step.key]
    if q and not seen[q] and not step.carry and not turned(q) and (skipped or not (state.done[i] or state.na[i] or state.wait[i])) and not laterHas(q, state.st.index and state.st.index + 1) then
      seen[q] = true
      local imp = E.Impact(q, state.st)
      if #imp > 0 then out[#out + 1] = { i = i, q = q, imp = imp } end
    end
  end
  return out
end
-- 到站：因為前面站的前置沒做而接不到的本站任務 → { {q, p, pst, can}... }；can＝前置還接得到（可補做）
function E.MissingPre(st)
  local out, seen = {}, {}
  if st.dungeon or not st.index then return out end
  local lv = UnitLevel("player") or 0
  for _, step in ipairs(st.list) do
    local q = step.s.q
    if q and not seen[q] and not MG.db.skip[step.key] and E.Applies(step.s.when) and not available(q) then
      seen[q] = true
      local info = R.quests[q]
      local cands = {}
      for _, p in ipairs(info.pg or {}) do if not turned(p) then cands[#cands + 1] = p end end
      for _, p in ipairs(info.ps or {}) do cands[#cands + 1] = p end
      for _, p in ipairs(cands) do
        local here, earlier = false, nil
        for _, o in ipairs(questSt[p] or {}) do
          if o == st then here = true elseif o.index and o.index < st.index then earlier = earlier or o end
        end
        if earlier and not here then
          local pi = R.quests[p] or {}
          local can = not turned(p) and (C.IsOnQuest(p) or (lv >= (pi.min or 0) and not gray(p) and available(p) and not excluded(p)))
          out[#out + 1] = { q = q, p = p, pst = earlier, can = can or false }
          break
        end
      end
    end
  end
  return out
end
-- 補做：把前置任務帶進本站最前面（做完自動回原路線）
function E.MakeUp(st, p)
  local carry = MG.db.carry[st.id] or {}
  MG.db.carry[st.id] = carry
  for _, q in ipairs(carry) do if q == p then return end end
  carry[#carry + 1] = p
end

-- 任務日誌滑鼠提示：在路線上 → 哪一站第幾步；不在 → 06 的判定，否則規則（灰 → 可放掉；路線任務的前置 → 值得做；其餘 → 之後順路）
function E.QuestNote(q)
  for _, o in ipairs(questSt[q] or {}) do
    for i, step in ipairs(o.list) do
      if step.s.q == q then return o.dungeon and (L["路線："] .. L["%s 副本"]:format(o.name)) or (L["路線："] .. L["%s 第 %d 步"]:format(MG.UI.StName(o), i)) end
    end
  end
  local off = R.offroute and R.offroute[q]
  if off then return L["不在路線上"], off.v, off.why end
  local qlv = C.QuestLevel(q)
  if qlv and qlv > 0 and (UnitLevel("player") or 0) - qlv > (C.GreenRange() or 8) then return L["不在路線上"], "可放掉", L["等級已過"] end
  local f = R.feeds and R.feeds[q]
  if f then return L["不在路線上"], "值得做", L["接後續："] .. questName(f) end
  return L["不在路線上"], "之後順路"
end

-- 背包提示先找日誌中的用途，再看此角色尚未交付的後續任務。
function E.KeepQuest(item)
  if not item.uses then
    if item.q and not turned(item.q) then return item.q end
    return nil
  end
  local nextQuest, active, counted, total = nil, {}, {}, 0
  for _, use in ipairs(item.uses) do
    if not turned(use.q) and E.Applies(use.when, true) then
      nextQuest = nextQuest or use
      if C.IsOnQuest(use.q) and not counted[use.q] then
        active[#active + 1] = use
        counted[use.q] = true
        if total and use.count then total = total + use.count else total = nil end
      end
    end
  end
  if #active > 1 and total then return active[1].q, total, active end
  local use = active[1] or nextQuest
  if use then return use.q, use.count end
end

-- 任務出現的第一站（保留物品提示用）
function E.QuestStation(q) return questSt[q] and questSt[q][1] end
-- 補給：本站的（職業材料只給對的職業）
function E.SupplyFor(st)
  local out = {}
  for _, s in ipairs(st and st.supply or {}) do
    local ok = not s.c
    for _, c in ipairs(s.c or {}) do if c == me.class then ok = true end end
    if ok then out[#out + 1] = s end
  end
  return out
end
-- 位置類提示（同地圖、5% 內）：附近的危險、還沒開過的飛行點
function E.Nearby(st)
  local map, x, y = C.Position()
  if not (st and map and x) then return end
  local function near(p) return p.map == map and p.x and (p.x - x) ^ 2 + (p.y - y) ^ 2 <= 25 end
  local danger, fp
  if MG.UI.Get("dangerOn") then
    for _, d in ipairs(st.danger or {}) do if near(d) then danger = d; break end end
  end
  if MG.UI.Get("supplyOn") then
    for _, s in ipairs(st.supply or {}) do
      local n = s.npcG or s.npc -- 開鳥點時記的是遊戲裡的 NPC 名（客戶端語言）
      if s.k == "飛行管理員" and n and near(s) and not MG.db.fpSeen[n] and not MG.db.fpSkip[n] then fp = s; break end
    end
  end
  return danger, fp
end
-- 裝備耐久最低的比例（讀不到或是秘密值的格子不算）
function E.Durability()
  if not GetInventoryItemDurability then return end
  local low
  for slot = 1, 18 do
    local cur, max = GetInventoryItemDurability(slot)
    if cur and max and not (issecretvalue and (issecretvalue(cur) or issecretvalue(max))) and max > 0 then
      local r = cur / max
      if not low or r < low then low = r end
    end
  end
  return low
end

-- 存檔只有手動略過算數（skip[key] == key；舊存檔的 true 也算）；連帶略過（值＝起點的 key）每次切換都照目前的手動略過重算，
-- 所以「任一個前置」的任務：兩條前置都略過後只取消一條，後續會回來。
function E.ToggleSkip(key)
  local skip = MG.db.skip
  local root = skip[key]
  if root then skip[root == true and key or root] = nil else skip[key] = key end
  E.RecomputeSkip()
end
-- 交了任務、登入後任務日誌到了也重算（Core）：略過的前置後來還是做了，被連帶的後續要回來
function E.RecomputeSkip()
  local skip = MG.db.skip
  local roots = {}
  for k, v in pairs(skip) do
    if v == k or v == true then roots[#roots + 1] = k end
  end
  for k in pairs(skip) do skip[k] = nil end
  table.sort(roots)
  for _, k in ipairs(roots) do skip[k] = k end
  -- 一個任務的接／做／交全部略過：基本鍵之外，各站實際的步驟鍵（含 ~2、~3）也記
  local function mark(x, from)
    for _, p in ipairs({ "a", "d", "t" }) do if not skip[p .. ":" .. x] then skip[p .. ":" .. x] = from end end
    for _, st in ipairs(questSt[x] or {}) do
      for _, step in ipairs(st.list) do
        if step.s.q == x and QUEST[step.s.t] and not skip[step.key] then skip[step.key] = from end
      end
    end
  end
  -- 略過「接」或「做」→ 整個任務；略過「交」→ 只連帶後續。全部起點先標完再算後續
  local cut, rootQ, queue = {}, {}, {}
  for _, k in ipairs(roots) do
    local t, q = k:match("^(%a):(%d+)$")
    if not q then t, q = k:match("^(%a):(%d+)~%d+$") end -- 同站重複的步驟（a:任務~2）
    q = tonumber(q)
    if q then
      rootQ[q] = true
      queue[#queue + 1] = { q = q, from = k }
      if t ~= "t" then mark(q, k) end
    end
  end
  -- 後續任務（遞迴）：前置斷了才連帶。已經接了或交了的不動；「任一個前置」（ps）還有別條沒被略過的也不動；只靠 next 接過來的：來源還沒交才連帶
  local function gone(p) return not turned(p) and (cut[p] or rootQ[p] or skip["a:" .. p] or skip["t:" .. p]) and true or false end
  local n = 1
  while queue[n] do
    local cur, from = queue[n].q, queue[n].from
    n = n + 1
    for _, f in ipairs((R.quests[cur] or {}).fol or {}) do
      if not cut[f] and not turned(f) and not C.IsOnQuest(f) then
        local info = R.quests[f] or {}
        local listed, dead, alive = false, false, not (info.ps and #info.ps > 0)
        for _, p in ipairs(info.pg or {}) do
          if p == cur then listed = true end
          if gone(p) then dead = true end
        end
        for _, p in ipairs(info.ps or {}) do
          if p == cur then listed = true end
          if not gone(p) then alive = true end
        end
        if dead or not alive or (not listed and gone(cur)) then
          cut[f] = true
          queue[#queue + 1] = { q = f, from = from }
          mark(f, from)
        end
      end
    end
  end
end

-- 任務本身或後續是副本任務（沒選不打的）、有本職業的好獎勵 → { hit, why, chain }；整條鏈都不重要 → false（這次登入記著）
local weight = {}
local function weigh(q)
  if weight[q] ~= nil then return weight[q] end
  local seen, queue, k, hit, why = { [q] = true }, { q }, 1, nil, nil
  while queue[k] do
    local cur = queue[k]
    k = k + 1
    for _, o in ipairs(not why and not turned(cur) and raceOK(cur) and questSt[cur] or {}) do
      for _, step in ipairs(o.list) do
        local s = step.s
        if not why and s.q == cur and E.Applies(s.when) then
          local star = E.StarFor(cur, s)
          why = (o.dungeon and not MG.db.dNo[o.id] and (s.ph == "pre" and L["%s 副本前置"] or L["%s 副本"]):format(o.name)) or (star and L["獎勵：%s"]:format(star)) or nil
          hit = why and cur
        end
      end
    end
    for _, f in ipairs((R.quests[cur] or {}).fol or {}) do
      if not seen[f] then seen[f] = true; queue[#queue + 1] = f end
    end
  end
  weight[q] = why and { hit = hit, why = why, chain = queue } or false
  return weight[q]
end
-- 手動略過了重要任務：回一句提示；同一條鏈只提一次（存檔 skipNote）
function E.SkipNotice(q)
  local note = MG.db.skipNote
  local w = not note[q] and not turned(q) and raceOK(q) and weigh(q)
  if not w then return end
  for _, c in ipairs(w.chain) do note[c] = true end
  if w.hit == q then return L["略過了「%s」（%s）"]:format(questName(q), w.why) end
  return L["略過「%s」：之後的「%s」（%s）會接不到"]:format(questName(q), questName(w.hit), w.why)
end
-- 到站：可跳過沒開而沒排進來的重要任務，整站合成一句（最多列 3 個）；每站只提一次（存檔 optNote）
function E.OptNotice(state)
  local st = state.st
  if state.instance or st.dungeon or MG.db.optNote[st.id] then return end
  MG.db.optNote[st.id] = true
  local n, names, seen, said = 0, {}, {}, {}
  for _, step in ipairs(state.steps) do
    local s = step.s
    local w = s.q and not seen[s.q] and optOut(s) and not MG.db.skip[step.key] and E.Applies(s.when) and not turned(s.q) and raceOK(s.q) and weigh(s.q)
    if w then
      n = n + 1
      for _, c in ipairs(w.chain) do seen[c] = true end
      if not said[w.why] then said[w.why] = true; names[#names + 1] = w.why end
    end
  end
  if n == 0 then return end
  local list = table.concat(names, L["、"], 1, math.min(#names, 3))
  return L["本站有 %d 條重要任務沒排（%s）；設定開「帶上可跳過的任務」就會顯示"]:format(n, #names > 3 and L["%s等"]:format(list) or list)
end

-- 手動勾選：val = true／false；nil＝回到自動
function E.SetMark(key, val) MG.db.mark[key] = val end

function E.Realign()
  wipe(MG.db.pin)
  -- 一併清掉目前站的手動勾選
  local old = MG.db.station and E.byId[MG.db.station]
  for _, step in ipairs(old and old.list or {}) do MG.db.mark[step.key] = nil end
  MG.db.station = nil
  E.Current()
end


-- ── 副本 ────────────────────────────────────────────────────────────────────
-- 副本站不在主線；它的前置（接／做／交）預設排進建議的主線站（pickAt），標「副本前置」。
-- 副本前置不搶主線的日誌格：空格扣掉主線往後還會多占的格數後不到 3 格，還沒接的副本前置先不接（之後再接），不分副本等級；
-- 已接的照常做、交。只是這一刻先不接，不寫進存檔；有空格了會自己回來。主線任務不受影響。
function E.QuestLogSpace()
  local max = C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()
  if (issecretvalue and issecretvalue(max)) or type(max) ~= "number" or max <= 0 then max = 40 end -- 永恆任務日誌上限
  local entries = C_QuestLog and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries
  local used = entries and select(2, entries()) -- 首個回傳是畫面列數，第二個才含摺疊分類內的任務
  if (issecretvalue and issecretvalue(used)) or type(used) ~= "number" then used = 0 end
  -- 接受事件後，日誌已新增一列時，總數有時晚一更新才會跟上。
  local visible = C.LogQuestIDs() or {}
  used = math.max(used, #visible)
  return max - used, used, visible
end
function E.LogFull() return E.QuestLogSpace() <= 0 end

-- 主線往後還會多占幾格日誌：從這一站照步驟順序走到最後一站，數還沒接的「接」和之後的「交」，回傳比現在多出的最大值。
-- 「交」要是會做到的那一步才算騰出一格：不適用本角色、手動略過、手動勾掉的不算（任務還占著）；後面另有會做到的「交」就算在那裡。
-- 互斥的只算一個；補經驗補回來的可跳過任務估不到（留 3 格的餘裕）。每次用這一刻的日誌、略過、設定重算，不留到下一次
-- 主線列中的副本前置仍由玩家選擇，未接時不預留。接取後已由 logFree 計入。
local function mainGrowth(st)
  local state, n, peak = {}, 0, 0 -- state[q]：1＝預估會接著、2＝預估交掉了
  for i = st.index, #E.stations do
    local plannedWork = {}
    for _, step in ipairs(E.stations[i].list) do
      local s = step.s
      local q = s.q
      if s.t == "accept" and q and not (s.when and s.when.dungeonPrep) and (not s.reserveOnVisit or st.index == i)
          and not state[q] and not C.IsOnQuest(q)
          and not turned(q) and E.Applies(s.when, true) and not optOut(s) and raceOK(q) and not MG.db.skip[step.key] and not excluded(q) then
        local clash = false
        for _, o in ipairs((R.quests[q] or {}).ex or {}) do clash = clash or state[o] ~= nil end
        if not clash then
          state[q] = 1
          n = n + 1
          if n > peak then peak = n end
        end
      elseif s.t == "do" and q and (R.quests[q].requiredLoot or R.quests[q].killCount or (i == st.index and R.quests[q].confirmInteraction)) and (state[q] == 1 or C.IsOnQuest(q))
          and E.Applies(s.when, true) and not optOut(s) and not MG.db.skip[step.key] and not MG.db.mark[step.key] then
        plannedWork[q] = true
      elseif s.t == "turnin" and q and state[q] ~= 2 and (state[q] or C.IsOnQuest(q))
          and (E.Applies(s.when, true, s.afterWork or s.providedVisit) or (s.afterWork and plannedWork[q])
            -- This authored visit uses the item issued by the projected acceptance. Held quests still use live eligibility.
            or (s.providedVisit and state[q] == 1 and not optOut(s)))
          and not MG.db.skip[step.key] and MG.db.mark[step.key] ~= true then
        state[q] = 2
        n = n - 1
      end
    end
  end
  return peak
end
-- 這一刻還能不能再接副本前置：空格扣掉主線往後還會多占的格數，至少剩 3 格。步驟列的「之後」和自動接都問這裡（只查不寫）。
-- pending＝剛按了接受、日誌還沒更新的件數
function E.PreRoom(st, pending, free)
  return (free or E.QuestLogSpace()) - (pending or 0) - (st and mainGrowth(st) or 0) >= 3
end

-- 不經過 locate 的單步完成判定（副本分頁用；不動 fill）
function E.QuickDone(step)
  local m = MG.db.mark[step.key]
  if m ~= nil then return m end
  return stepDone(step) and true or false
end

-- 這本的任務都交了（出本交和副本內交；可跳過的、不適用本角色的不算）
function E.DungeonDone(d)
  local any = false
  for _, step in ipairs(d.list) do
    local s = step.s
    -- 「日誌可交」只決定下一步要不要指去交，不決定這本有哪些要交：交完後日誌不再回報可交，不能因此把任務從清單拿掉
    local w = s.when
    if w and w.readyQuest then
      w = {}
      for k, v in pairs(s.when) do if k ~= "readyQuest" then w[k] = v end end
    end
    if s.t == "turnin" and (s.ph == "post" or s.ph == "in") and s.q and not s.opt and E.Applies(w) and raceOK(s.q) then
      any = true
      if not turned(s.q) then return false end
    end
  end
  return any -- 沒有出本要交的任務（例如厄運之槌北區）就不算「已過」，交給等級判斷
end

-- 已接的順訪前置，離開發任地點後仍留在已備妥清單。
local function listedDungeonPrep(s)
  return (s.when and s.when.hubArea and C.IsOnQuest(s.q)) or E.Applies(s.when)
end

-- 前置任務：{ total, accepted }（接受或已交都算）
function E.DungeonPre(d)
  local total, got, seen = 0, 0, {}
  for _, step in ipairs(d.list) do
    local s = step.s
    if s.ph == "pre" and (s.t == "accept" or s.t == "need") and s.q and not seen[s.q] and listedDungeonPrep(s) then
      seen[s.q] = true
      total = total + 1
      if C.IsOnQuest(s.q) or turned(s.q) then got = got + 1 end
    end
  end
  return total, got
end

function E.DungeonStatus(d)
  local lv = UnitLevel("player") or 1
  local done = E.DungeonDone(d)
  if done or lv > d.lv[2] + 3 then
    -- A later wing or a return visit may still have an objective in the player's journal.
    for _, step in ipairs(d.list) do
      local s = step.s
      if s.q and C.IsOnQuest(s.q) and E.Applies(s.when) and raceOK(s.q)
          and not MG.db.skip[step.key] and not E.QuickDone(step) then
        if ((s.ph == "in" or s.exitPriority) and s.t == "do" and not s.wing and not ready(s.q))
            or (s.ph == "in" and s.t == "turnin" and not s.map and ready(s.q))
            or (s.ph == "post" and s.t == "turnin" and ready(s.q)) then
          return L["可以去"], "revisit", step
        end
      end
    end
    return done and L["已完成"] or L["已過"], "past"
  end
  local minPick = d.lv[1]
  for _, step in ipairs(d.list) do if step.s.pickLv and step.s.pickLv < minPick then minPick = step.s.pickLv end end
  if lv < minPick then return L["%d 級"]:format(minPick), "low" end
  local total, got = E.DungeonPre(d)
  if total == 0 or got >= total then return lv >= d.lv[1] and L["可以去"] or L["%d 級再去"]:format(d.lv[1]), "ready" end
  local tg, tt = E.DungeonTargetCount(d)
  if got > 0 then return L["前置 "] .. tg .. "/" .. tt, "some" end
  -- 前置任務本身還有前置（任務鏈沒做）→ 先做前置鏈（見前置接取路線）
  -- 前置接取和下一步用同一個最低等級：還不到時照樣可以進本，另寫前置幾級可接
  local later
  for _, step in ipairs(d.list) do
    local st = step.s
    if st.ph == "pre" and st.t == "accept" and st.q and E.Applies(st.when) and available(st.q) then
      local need = math.max(st.pickLv or 0, (R.quests[st.q] or {}).min or 0)
      if lv >= need then return L["前置可接"], "pick" end
      if not later or need < later then later = need end
    end
  end
  if later then
    return (lv >= d.lv[1] and L["可以去"] or L["%d 級再去"]:format(d.lv[1])) .. "・" .. L["前置 %d 級可接"]:format(later), "ready"
  end
  local tg, tt = E.DungeonTargetCount(d)
  return L["前置 "] .. tg .. "/" .. tt, "chain"
end

-- 插進主線站的副本前置步驟
function dungeonPreSteps(st)
  if not MG.UI.Get("dPre") then return nil end
  local out
  local lv = UnitLevel("player") or 1
  local have = {}
  for _, step in ipairs(st.list) do have[step.key] = true end -- 主線本來就有的步驟不重複插
  local room
  for _, d in ipairs(E.dungeons) do
    if d.pickAt == st.id and not MG.db.dNo[d.id] then
      if room == nil then room = E.PreRoom(st) end
      for _, step in ipairs(d.list) do
        local s = step.s
        if s.ph == "pre" and s.t ~= "travel" and s.t ~= "need" and not have[step.key] and (not s.pickLv or lv >= s.pickLv) then
          have[step.key] = true
          out = out or {}
          out[#out + 1] = { s = s, key = step.key, st = d, dungeon = d, defer = not room and s.t == "accept" and not C.IsOnQuest(s.q) and not turned(s.q) or nil }
        end
      end
    end
  end
  return out
end

-- 提示：等級到了建議等級下限、還沒打完、沒按掉、沒選不打 → 第一個
function E.DungeonPrompt()
  if not MG.UI.Get("dungeonHint") then return nil end
  local lv = UnitLevel("player") or 1
  -- 先挑等級落在建議範圍內、下限最高的（最合適的那本），沒有才挑超過一點的
  local list = {}
  for _, d in ipairs(E.dungeons) do list[#list + 1] = d end
  table.sort(list, function(a, b)
    local fa, fb = lv <= a.lv[2], lv <= b.lv[2]
    if fa ~= fb then return fa end
    return a.lv[1] > b.lv[1]
  end)
  for _, d in ipairs(list) do
    if lv >= d.lv[1] and not MG.db.dDismiss[d.id] and not MG.db.dNo[d.id] then
      local _, kind, revisit = E.DungeonStatus(d)
      -- 超過等級、只因日誌裡還有本副本任務而回訪：提示那個任務，不算前置
      if kind == "revisit" then return d, E.Title(revisit.s) end
      if kind ~= "past" then
        -- 前置鏈還沒做完：說還剩幾步；否則說前置還有幾個沒接
        local left = 0
        for _, step in ipairs(d.list) do
          local s = step.s
          if s.tag == "副本前置鏈" and E.Applies(s.when) and (not s.q or raceOK(s.q)) and not E.QuickDone(step) then left = left + 1 end
        end
        if left > 0 then return d, L["先做前置鏈（%d 步）"]:format(left) end
        local total, got = E.DungeonPre(d)
        return d, total > got and L["前置未接 %d／共 %d"]:format(total - got, total) or nil
      end
    end
  end
end

-- 設為目標：步驟列改走這個副本的流程；打完（或離開副本）再回主線
function E.RunDungeon(d)
  MG.db.deferredHandoffRun = nil
  local from = MG.db.station and E.byId[MG.db.station]
  if not (from and from.dungeon) then MG.db.dungeonFrom = MG.db.station end -- 已在副本流程中換副本：保留原本的主線站
  MG.db.station = d.id
end

-- 目前所在副本：GetInstanceInfo 的 instanceID 對到副本站
-- 同一個副本 ID 可能有好幾站（例如血色修道院四翼）：回傳第一個和全部
function E.DungeonByInstance(id)
  local all = {}
  for _, d in ipairs(E.dungeons) do
    for _, i in ipairs(d.inst or {}) do if i == id then all[#all + 1] = d; break end end
  end
  -- 同一個副本 ID 有好幾區（例如血色修道院：墓地、圖書館、軍械庫、大教堂）：用目前區域文字挑出所在的那一區
  if #all > 1 then
    -- 遊戲回傳的區域名（各語系）對照 Data\Wings.lua（客戶端 AreaTable 的各區房間名，例如軍械庫＝十字軍武器庫、勇士大廳…）
    local texts, loc = instanceZone()
    local pick
    for k, d in ipairs(all) do
      if inNamedWing(d.id, texts, loc) then pick = k; break end
    end
    -- 對照表沒有時退回比對路線站名的最後一個詞（例如「血色修道院 墓地」的「墓地」）
    if not pick then
      local here = table.concat(texts, " ")
      for k, d in ipairs(all) do
        local wing = tostring(d.name or ""):match("(%S+)$")
        if wing and wing ~= d.name and here:find(wing, 1, true) then pick = k; break end
      end
    end
    -- 還是認不出來：只有一區有日誌裡的任務時就選那一區
    if not pick and not (E.lastWing and E.lastWing[id]) then
      local only
      for k, d in ipairs(all) do
        local has = false
        for _, step in ipairs(d.list or {}) do if step.s.q and C.IsOnQuest(step.s.q) then has = true; break end end
        if has then if only then only = nil; break end; only = k end
      end
      pick = only
    end
    -- 走廊等沒有區域名的地方：沿用這個副本上一次認出的區
    E.lastWing = E.lastWing or {}
    if pick then E.lastWing[id] = all[pick].id
    else for k, d in ipairs(all) do if d.id == E.lastWing[id] then pick = k; break end end end
    if pick then local d = table.remove(all, pick); table.insert(all, 1, d) end
  end
  return all[1], all
end

-- 副本裡的步驟列：列出日誌中還沒完成的任務、可在副本內交件的任務，以及已撿到起始物品的任務。

function E.InstanceState(d, all)
  local steps, seen, inTurn, inDo, outsideObjective = {}, {}, {}, {}, {}
  local wing, otherWing = stratholmeWing(d), {}
  for _, x in ipairs(all or { d }) do
    for _, step in ipairs(x.list or {}) do
      if step.s.outsideObjective then outsideObjective[step.s.q] = true end
      if step.s.instanceMaterial then inDo[step.s.q] = instanceMaterialAction(step.s) end
      -- 有地圖座標的是在本外交（路線放在副本內段落而已）
      if step.s.ph == "in" and step.s.t == "turnin" and step.s.q and not step.s.map then inTurn[step.s.q] = step.s end
      if step.s.ph == "in" and step.s.t == "do" and step.s.q then
        local q, wanted = step.s.q, step.s.wing
        if wing and wanted and wanted ~= "either" and wanted ~= wing then otherWing[q] = true
        else inDo[q] = inDo[q] or step.s end
      end
    end
  end
  local function add(q)
    local info = q and R.quests[q]
    local nativeReady = inDo[q] and info and info.requiredLoot and journalReady or C.IsReady
    if q and not seen[q] and C.IsOnQuest(q) and (inTurn[q] or (inDo[q] and inDo[q].when and inDo[q].when.missingBag) or not nativeReady(q)) then
      local condition = inDo[q] and inDo[q].when
      if condition and condition.missingBag and not E.Applies(condition) then return end
      -- 本內可接的送信任務交由出本步驟引導。其他分翼有明列目標時仍顯示。
      if (outsideObjective[q] or otherWing[q]) and not inDo[q] and not inTurn[q] then return end
      local authored = inTurn[q] or inDo[q]
      local instanceID = authored and authored.when and authored.when.instanceID
      if instanceID and not inInstance(instanceID) then return end
      seen[q] = true
      -- 目標做完、在副本內交的：改成「交」步驟，第二行寫找誰交
      local canTurnIn = inTurn[q] and C.IsReady(q) and E.Applies(inTurn[q].when)
      steps[#steps + 1] = { s = canTurnIn and inTurn[q] or inDo[q] or { t = "do", q = q }, key = "d:" .. q, st = d }
    end
  end
  local function inPickup(s)
    if s.when and s.when.bag then return true end
    if s.map then return false end
    if s.instancePickup then return true end
    local info = R.quests[s.q] or {}
    for _, p in ipairs(info.pg or {}) do if inTurn[p] and turned(p) then return true end end
    for _, p in ipairs(info.ps or {}) do if inTurn[p] and turned(p) then return true end end
    return false
  end
  for _, x in ipairs(all or { d }) do
    for _, step in ipairs(x.list or {}) do
      local s, q = step.s, step.s.q
      if q and s.ph == "in" and s.t == "accept" and not seen[q] and inPickup(s) and E.Applies(s.when)
          and not E.QuickDone(step) and not MG.db.skip[step.key]
          and (not s.manualAccept or (not MG.db.dNo[x.id] and not optOut(s) and not E.LogFull()))
          and (UnitLevel("player") or 1) >= math.max(s.pickLv or 0, (R.quests[q] or {}).min or 0)
          and raceOK(q) and available(q) and not excluded(q) and not superseded(q) then
        seen[q] = true
        steps[#steps + 1] = { s = s, key = step.key, st = x }
      else
        add(q)
      end
    end
    -- Preserve the full index for lookup, but omit objectives that take place outside this instance.
    for _, q in ipairs(x.dq or {}) do
      if not x.outsideIndexed or not inList(x.outsideIndexed, q) then add(q) end
    end
  end
  if #steps == 0 then return nil end
  local done, na, num, group, inGroup = {}, {}, {}, {}, {}
  for i in ipairs(steps) do
    done[i], na[i], num[i] = false, false, i
    if i > 1 then group[#group + 1] = i; inGroup[i] = true end
  end
  return { instance = true, st = d, steps = steps, done = done, na = na, autoDone = {}, num = num, total = #steps, cur = 1, auto = 1,
    group = group, inGroup = inGroup, fill = {}, missed = {}, complete = false }
end


-- ── 副本分頁 v2 用 ────────────────────────────────────────────────────────────
-- 目標任務＝要帶進本的任務：pre 段的「接／需」，而且同一個任務在 pre 段沒有「交」。
-- 鏈＝pre 段裡會在進本前交掉的任務；歸給清單中排在它後面的第一個目標任務。
function E.DungeonTargets(d)
  local preTurn = {}
  for _, step in ipairs(d.list) do
    local s = step.s
    if s.ph == "pre" and s.t == "turnin" and s.q then preTurn[s.q] = true end
  end
  local targets, seenT, pending, seenC = {}, {}, {}, {}
  for _, step in ipairs(d.list) do
    local s = step.s
    if s.ph == "pre" and s.q and listedDungeonPrep(s) and raceOK(s.q) then
      if preTurn[s.q] then
        if not seenC[s.q] then seenC[s.q] = true; pending[#pending + 1] = step end
      elseif (s.t == "accept" or s.t == "need") and not seenT[s.q] then
        seenT[s.q] = true
        targets[#targets + 1] = { q = s.q, step = step, chain = pending }
        pending = {}
      end
    end
  end
  -- 後面已經沒有要帶進本的任務（例如剃刀高地門口的邪惡之地）：自己列一行
  for _, step in ipairs(pending) do targets[#targets + 1] = { q = step.s.q, step = step, chain = {} } end
  return targets
end

-- 目標任務已接數／總數（在日誌或已交都算）
function E.DungeonTargetCount(d)
  local list = E.DungeonTargets(d)
  local got = 0
  for _, t in ipairs(list) do if C.IsOnQuest(t.q) or turned(t.q) then got = got + 1 end end
  return got, #list
end

local function minPickLv(d)
  local m = d.lv[1]
  for _, step in ipairs(d.list) do if step.s.pickLv and step.s.pickLv < m then m = step.s.pickLv end end
  return m
end
E.MinPickLv = minPickLv

-- 下一步：{ kind = low/in/pre/wait/ent/post, step, title }；已過或不打回 nil
function E.DungeonNext(d, inside)
  if MG.db.dNo[d.id] then return nil end
  local lv = UnitLevel("player") or 1
  -- Only routes with a component that can actually be obtained in this instance need this distinction.
  local loading = false
  if d.componentVisit and IsInInstance then
    local physical = IsInInstance()
    if physical ~= nil then
      local id = GetInstanceInfo and select(8, GetInstanceInfo())
      loading = physical and (not id or id == 0)
      inside = physical and inList(d.inst or {}, id) or false
    end
  end
  local function external(s)
    return (inside or loading) and (worldContact(s) or s.instanceMaterial)
  end
  local wing = inside and stratholmeWing(d)
  local function wingApplies(s)
    return not s.wing or (inside and (s.wing == "either" or s.wing == wing))
  end
  local function canDo(s)
    if external(s) or not wingApplies(s) then return false end
    local q = s.q
    if not q then return true end
    if not raceOK(q) then return false end
    if s.t == "accept" then
      return (not s.manualAccept or (not optOut(s) and not E.LogFull())) and lv >= math.max(s.pickLv or 0, (R.quests[q] or {}).min or 0)
        and available(q) and not excluded(q) and not superseded(q)
    end
    if s.t == "turnin" then return C.IsOnQuest(q) and ready(q) end
    if s.t == "do" then return C.IsOnQuest(q) and not ready(q) end
    return true
  end
  local function first(ph, eligible)
    for _, step in ipairs(d.list) do
      local s = step.s
      if s.ph == ph and (not eligible or eligible(s)) and s.t ~= "travel" and s.t ~= "need" and E.Applies(s.when)
        and not MG.db.skip[step.key] and not E.QuickDone(step) and canDo(s) then return step end
    end
  end
  local function nextJournalStep()
    local state = E.InstanceState(d)
    for _, current in ipairs(state and state.steps or {}) do
      if wingApplies(current.s) and not MG.db.skip[current.key] and not E.QuickDone(current) then return { kind = "in", step = current } end
    end
  end
  -- 進本後優先顯示本內目標。前置或城市對話可能尚未完成，也可能已交過。
  if inside then
    local hasOutdoorWork = false
    for _, wrapper in ipairs(d.list) do
      local s = wrapper.s
      if s.ph == "pre" and s.t == "do" and s.outsideObjective then hasOutdoorWork = true end
      if s.ph == "post" and s.t == "turnin" and s.outsideObjective and C.IsOnQuest(s.q) then
        local step = first("in")
        if step then return { kind = "in", step = step } end
        return nextJournalStep()
      end
    end
    if hasOutdoorWork then
      local step = first("in")
      if step then return { kind = "in", step = step } end
      return nextJournalStep()
    end
  end
  -- On leaving, prioritize only authored handoffs whose live quest state allows them.
  if not inside then
    local handoff = first("post", function(s) return s.exitPriority end)
    if not handoff and C.Position and not (IsInInstance and IsInInstance()) then
      local map, x, y = C.Position()
      if map and x and y then
        handoff = first("post", function(s)
          return s.t == "turnin" and s.outsideObjective and s.map == map and s.x and s.y
            and (s.x - x)^2 + (s.y - y)^2 <= 0.8^2
        end)
      end
    end
    if handoff then return { kind = "post", step = handoff } end
    local turnin = first("post", function(s) return s.t == "turnin" and s.when and s.when.hubArea end)
    if turnin then return { kind = "post", step = turnin } end
    local pickup = first("pre", function(s) return s.t == "accept" and s.when and s.when.hubArea end)
    if pickup then return { kind = "pre", step = pickup } end
  end
  local function materialInInstance()
    if not inside or not d.componentVisit then return end
    for _, step in ipairs(d.list) do
      local s = step.s
      if s.instanceMaterial and C.IsOnQuest(s.q) and not turned(s.q) and E.Applies(s.when)
          and not MG.db.skip[step.key] and not E.QuickDone(step) then
        return {kind="in", step={s=instanceMaterialAction(s), key=step.key, st=d}}
      end
    end
  end
  local _, kind, revisit = E.DungeonStatus(d)
  if kind == "past" then
    local pickup = inside and first("in", function(s) return s.manualAccept or s.wing end)
    if pickup then return { kind = "in", step = pickup } end
    return materialInInstance()
  end
  if kind == "revisit" then
    if external(revisit.s) then return nil end
    if revisit.s.ph == "post" then return { kind = "post", step = revisit } end
    if inside then return { kind = "in", step = revisit } end
    return { kind = "ent" }
  end
  if kind == "low" then return { kind = "low", title = L["%d 級可接前置"]:format(minPickLv(d)) } end
  if inside then
    local step = first("in")
    if step then return { kind = "in", step = step } end
    local alternate = materialInInstance()
    if alternate then return alternate end
  end
  local pre = first("pre")
  if pre then return { kind = "pre", step = pre } end
  if lv < d.lv[1] then return { kind = "wait", title = L["%d 級再去"]:format(d.lv[1]) } end
  if first("in") then return { kind = "ent" } end
  local post = first("post")
  if post then return { kind = "post", step = post } end
  return nil
end

-- 步驟的顯示文字
local VERB = setmetatable({}, { __index = function(_, t)
  local zh = ({ accept = "接", ["do"] = "做", turnin = "交", ["goto"] = "到", fp = "鳥", hearth = "爐", bind = "綁", fly = "飛", boat = "船", level = "練", travel = "行", need = "需", buy = "買" })[t]
  return zh and L[zh]
end })
E.VERB = VERB
-- 動詞：非中文介面的交通／前往步驟，說明本身已是祈使句（Leave…、Take…）就不再加「Go」
local IMPERATIVE = { Go = true, Leave = true, Take = true, Fly = true, Ride = true, Run = true, Head = true, Return = true, Enter = true, Use = true,
  Hearth = true, Travel = true, Follow = true, Swim = true, Walk = true, Cross = true, Board = true, Exit = true, Get = true, Continue = true, Back = true, From = true, At = true, After = true, If = true }
function E.Verb(s)
  if s.roam and s.t == "do" then return L["順"] end -- 順路任務：路上遇到就打
  if s.pick then return L["撿"] end -- 撿任務物品：和「買」一樣看背包數量完成
  if not MG.uiZh and (s.t == "travel" or s.t == "goto") and IMPERATIVE[(E.Title(s) or ""):match("^(%a+)") or ""] then return "" end
  return VERB[s.t] or ""
end
-- 動詞＋標題（動詞空的時候不留前導空白）
function E.VerbTitle(s)
  local v = E.Verb(s)
  return v ~= "" and (v .. " " .. E.Title(s)) or E.Title(s)
end
-- 交通文字切成「第一句」與「其餘」（以全形逗號或句號；不能用 Lua 字元集，會切壞 UTF-8）
function E.Clause(text)
  text = text or ""
  local a = text:find("，", 1, true)
  local b = text:find("。", 1, true)
  local cut = a and b and math.min(a, b) or a or b
  if not cut and not MG.uiZh then
    -- 英文說明：第一句（到「. 」或「; 」），句尾的句點拿掉
    local e = text:find("[%.;] ")
    if not e then return (text:gsub("%.$", "")), nil end
    local rest = strtrim(text:sub(e + 2))
    return text:sub(1, e - 1), rest ~= "" and rest or nil
  end
  if not cut then return text, nil end
  local rest = text:sub(cut + 3)
  return text:sub(1, cut - 1), rest ~= "" and rest or nil
end

-- 沒有文字（非中文介面、路線只寫了中文）時：用地圖名＋座標
local function where(s)
  local zone = s.map and C.MapName(s.map)
  return (zone or "") .. (s.x and string.format(" %.0f, %.0f", s.x, s.y) or "")
end
-- 動詞框已經寫了動作，標題只留對象（飛｜奧格瑪）；full＝單獨顯示（箭頭）時的完整說法（飛往 奧格瑪）
function E.Title(s, full)
  if s.t == "need" then return s.text or "" end
  if s.any and s.text then return s.text end -- 任一組的接：「紮營入門指南（任選專業）」
  if s.q then return E.QName(s.q) end
  -- 交通／到達沒有文字：只寫地點（動詞框已經是「去」）
  if s.t == "travel" and s.back then return L["回到路線："] .. where(s) end -- 職業任務段落做完：回主線
  if s.t == "travel" then return s.text and (E.Clause(s.text)) or (s.map and where(s)) or L["交通"]
  elseif s.t == "goto" then return s.text or (s.map and where(s)) or L["前往"]
  elseif s.t == "buy" then return (s.text or "") .. ((s.n or 1) > 1 and (" ×" .. s.n) or "")
  elseif s.t == "fp" then return (full and L["開鳥點："] or "") .. (s.node or (s.map and C.MapName(s.map)) or "")
  elseif s.t == "hearth" then return (full and L["爐石回 "] or "") .. (s.bind or (s.hm and C.MapName(s.hm)) or "")
  elseif s.t == "bind" then return (full and L["綁爐石："] or "") .. (s.bind or (s.map and C.MapName(s.map)) or (s.hm and C.MapName(s.hm)) or "")
  elseif s.t == "fly" then return (full and L["飛往 "] or "") .. ((MG.uiZh and s.to or s.toL) or s.to or "")
  elseif s.t == "boat" then return (full and L["搭船／飛艇往 "] or "") .. ((MG.uiZh and s.to or s.toL) or s.to or "")
  elseif s.t == "level" then return L[full and "練到 %s 級" or "到 %s 級"]:format(s.lv or "?") end
  return s.text or ""
end
