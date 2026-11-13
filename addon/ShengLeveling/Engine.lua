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
  for _, st in ipairs(R.stations) do
    local ds, gs = D and D.stations[st.id] or none, G and G.stations[st.id] or none
    for i, s in ipairs(st.steps) do
      s.key0 = tostring(s.node or s.bind or s.to or s.text or s.lv or "") -- 存檔用的步驟鍵不跟語言變
      local d, g = ds.steps and ds.steps[i] or none, gs.steps and gs.steps[i] or none
      s.npcG = s.npc
      if G then s.npcG, s.tgt = g.npc or s.npc, g.tgt; s.npcObj = g.npcObj end
      if en then
        s.npc, s.hint, s.text, s.node, s.preText, s.star = P(d.npc), P(d.hint), P(d.text), P(areas(d.nodeA) or d.node), P(d.preText), d.star
        s.npcObj = d.npcObj
        s.desc, s.bind, s.to, s.from = P(d.desc), nil, nil, nil
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
  for i, t in ipairs(R.trainers or none) do
    t.npcK, t.npcG = t.npc, G and G.trainers and G.trainers[i] and G.trainers[i].npc or t.npc
    if en then t.npc = P(D.trainers and D.trainers[i] and D.trainers[i].npc or t.npcG); t.place = nil end
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
E.trainSteps = {} -- 本職業的「學技能」步驟（Build 時插進建議站）

local QUEST = { accept = true, ["do"] = true, turnin = true }
local SOFT = { ["goto"] = true, fp = true, fly = true, boat = true, travel = true }
local questSt = {} -- 任務 → 有它步驟的站（主線站與副本，Build 時建）
E.QUEST, E.SOFT = QUEST, SOFT

-- ── 角色與條件 ──────────────────────────────────────────────────────────────
local me = {}
local raceMatch
local function inList(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
end
function raceMatch(list)
  for _, r in ipairs(list) do
    if r == me.race or r == me.raceL then return true end
    -- 永恆新種族的寫法不一（部落天裔／塑風者天裔精靈）→ 互相包含就算
    if me.raceL and me.raceL ~= "" and (r:find(me.raceL, 1, true) or me.raceL:find(r, 1, true)) then return true end
  end
end
function E.Applies(when)
  if not when then return true end
  if when.race and not raceMatch(when.race) then return false end
  if when.notRace and raceMatch(when.notRace) then return false end
  if when.class and not inList(when.class, me.class) then return false end
  if when.notClass and inList(when.notClass, me.class) then return false end
  if when.lvMin and (UnitLevel("player") or 0) < when.lvMin then return false end
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
  return math.floor(info.races / 2 ^ (me.raceID - 1)) % 2 == 1
end

function E.Build()
  me.raceL, me.race, me.raceID = UnitRace("player")
  me.class = select(2, UnitClass("player"))
  wipe(E.stations); wipe(E.byId); wipe(E.dungeons); wipe(questSt)
  local startKey = E.StartKey()
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
        if s.t == "note" then
          note = s.text
        else
          -- 鍵用內容：路線重建後存檔裡的勾選／略過／釘選不會跑到別步；同站重複的加 ~2、~3
          local base = QUEST[s.t] and (s.t:sub(1, 1) .. ":" .. s.q)
            or (st.id .. "#" .. s.t .. ":" .. (s.key0 or tostring(s.node or s.bind or s.to or s.text or s.lv or "")) .. (s.x and string.format("@%.0f,%.0f", s.x, s.y) or ""))
          local key, k = base, 2
          while usedKey[key] do key = base .. "~" .. k; k = k + 1 end
          usedKey[key] = true
          list[#list + 1] = { s = s, key = key, note = note, st = st }
          note = nil
        end
      end
      st.list = list
      for _, step in ipairs(list) do
        local q = step.s.q
        if q then
          local l = questSt[q] or {}
          questSt[q] = l
          if l[#l] ~= st then l[#l + 1] = st end
        end
      end
      if st.dungeon then
        E.dungeons[#E.dungeons + 1] = st
      else
        st.index = #E.stations + 1
        E.stations[st.index] = st
      end
      E.byId[st.id] = st
    end
  end
  table.sort(E.dungeons, function(a, b) return a.lv[1] < b.lv[1] or (a.lv[1] == b.lv[1] and a.lv[2] < b.lv[2]) end)
  -- 訓練師：本職業的「學」步驟插在建議站的站尾交通前
  wipe(E.trainSteps)
  for _, t in ipairs(R.trainers or {}) do
    local st
    for _, id in ipairs(t.st) do st = st or E.byId[id] end -- 候選站：取第一個本角色有的
    if t.c == me.class and st and not st.dungeon then
      local step = { s = { t = "train", npc = t.npc, tgt = t.npcG or t.npc, place = t.place, lv = t.lv, map = t.map, x = t.x, y = t.y }, key = "tr:" .. t.lv .. ":" .. (t.npcK or t.npc), st = st }
      local list, cut = st.list, #st.list
      while cut > 0 and SOFT[list[cut].s.t] do cut = cut - 1 end
      table.insert(list, cut + 1, step)
      E.trainSteps[#E.trainSteps + 1] = step
    end
  end
end
E.me = me

-- ── done ────────────────────────────────────────────────────────────────────
local function turned(q) return E.session[q] or C.IsTurnedIn(q) end
E.Turned = turned

-- 目標全部完成；日誌查不到目標（對話型任務）視為完成
local function ready(q)
  if C.IsReady(q) then return true end
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

-- 可跳過的步驟：設定沒開就不算路線，除非該任務已在任務日誌，或經驗不夠時被補回來（fill）
local fill = {}
local function optOut(s)
  return s.opt and not MG.UI.Get("optional") and not (s.q and (C.IsOnQuest(s.q) or fill[s.q])) or false
end
E.OptOut = optOut

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
  local obj = C.IsOnQuest(q) and C.Objectives(q)
  local total = 0
  for k, m in ipairs(info.mob) do
    local left = m[2]
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
  local target = nxt and nxt.lv[1] or (st.lv[2] + 1)
  local lv = UnitLevel("player") or 1
  if lv >= target then return info end
  local need = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
  for l = lv + 1, target - 1 do need = need + (XP_LEVEL[l] or 0) end
  need = math.max(0, need)
  info.need = need
  -- 必做任務（不是可跳過、還沒交）的預估經驗，與它們的座標（算繞路用）
  local projected, seen, spots, cands = 0, {}, {}, {}
  for _, step in ipairs(st.list) do
    local s, q = step.s, step.s.q
    if q and E.Applies(s.when) and raceOK(q) and not turned(q) then
      if not s.opt and not seen[q] then
        seen[q] = true
        info.questXP = info.questXP + questXP(q, lv)
        info.killXP = info.killXP + killXP(q, lv)
      end
      if s.opt and s.t == "accept" and not C.IsOnQuest(q) and lv >= ((R.quests[q] or {}).min or 0) and not cands[q] then
        cands[q] = { q = q, xp = questXP(q, lv) + killXP(q, lv), pts = {} }
      end
    end
    if s.x and not s.opt then spots[#spots + 1] = s end
  end
  for _, step in ipairs(st.list) do
    local c = step.s.q and cands[step.s.q]
    if c and step.s.x then c.pts[#c.pts + 1] = step.s end
  end
  -- 休息經驗：打怪經驗加倍，最多到休息池的量
  info.rested = math.min(info.killXP, GetXPExhaustion and GetXPExhaustion() or 0)
  projected = info.questXP + info.killXP + info.rested
  info.projected = projected
  if projected >= need then return info end
  local list = {}
  for _, c in pairs(cands) do
    local detour = 50
    for _, p in ipairs(c.pts) do
      for _, r in ipairs(spots) do
        if r.map == p.map then detour = math.min(detour, math.sqrt((r.x - p.x) ^ 2 + (r.y - p.y) ^ 2)) end
      end
    end
    c.score = c.xp / (1 + detour) * (E.StarFor(c.q) and 2 or 1)
    if c.xp > 0 then list[#list + 1] = c end
  end
  table.sort(list, function(a, b) return a.score > b.score end)
  -- 前置已完成，或前置也已被補回（任務鏈依序補）才能選
  local function eligible(q)
    if available(q) then return true end
    local qi = R.quests[q] or {}
    for _, p in ipairs(qi.pg or {}) do if not (turned(p) or fill[p]) then return false end end
    if qi.ps and #qi.ps > 0 then
      for _, p in ipairs(qi.ps) do if turned(p) or fill[p] then return true end end
      return false
    end
    return true
  end
  local picked = true
  while projected < need and picked do
    picked = false
    for _, c in ipairs(list) do
      if not fill[c.q] and eligible(c.q) then
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

-- 順路提醒：本站裡現在就能做（接得到、在日誌未完成、可交）、離玩家比目前步驟近很多的步驟。
-- 條件：同地圖、距離 ≤ 設定值、且 < 目前步驟距離的 25%；不在「附近一起做」裡；同一步連續 3 秒都成立才提示；略過後 2 分鐘不再提。
local detourKey, detourSince, detourNo = nil, 0, {}
function E.Detour(state)
  if not (state and state.cur and not state.instance and MG.UI.Get("detourOn")) then return end
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
  local cd = dist(state.steps[state.cur].s) or math.huge
  local best, bd
  for i, step in ipairs(state.steps) do
    local s, q = step.s, step.s.q
    if i ~= state.cur and q and not state.done[i] and not state.na[i] and not state.inGroup[i] and now - (detourNo[step.key] or -999) >= 120 then
      local onQ = C.IsOnQuest(q)
      local ok = (s.t == "accept" and not onQ and lv >= ((R.quests[q] or {}).min or 0))
        or (s.t == "do" and onQ and not ready(q)) or (s.t == "turnin" and onQ and ready(q))
      local d = ok and dist(s)
      if d and d <= lim and d < cd * 0.25 and (not bd or d < bd) then best, bd = i, d end
    end
  end
  local key = best and state.steps[best].key
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

local function stepDone(step, map, x, y)
  local s = step.s
  if MG.db.latch[step.key] then return true end
  local t, q = s.t, s.q
  if t == "accept" or t == "need" then return C.IsOnQuest(q) or turned(q)
  elseif t == "do" then return turned(q) or (C.IsOnQuest(q) and ready(q))
  elseif t == "turnin" then return turned(q)
  elseif t == "level" then return (UnitLevel("player") or 0) >= (s.lv or 0)
  elseif t == "hearth" then
    local b = C.Bind()
    return b ~= nil and s.bind ~= nil and (b == s.bind or b:find(s.bind, 1, true) ~= nil)
  elseif t == "goto" or (t == "travel" and s.x) then
    local here = map ~= nil and map == s.map and x ~= nil and s.x ~= nil and math.sqrt((x - s.x) ^ 2 + (y - s.y) ^ 2) <= (s.r or 3)
    if here then MG.db.latch[step.key] = true end
    return here
  end
  return false
end

-- 本站要顯示的步驟（跳站時帶來的「順路補」排在最前面）
local dungeonPreSteps
local function stepsOf(st)
  local carry = MG.db.carry[st.id]
  local pre = not st.dungeon and dungeonPreSteps(st)
  if (not carry or #carry == 0) and not pre then return st.list end
  local out = {}
  carry = carry or {}
  local here = {}
  for _, step in ipairs(st.list) do if step.s.q then here[step.s.q] = true end end
  for k = #carry, 1, -1 do if turned(carry[k]) then table.remove(carry, k) end end
  for _, q in ipairs(carry) do
    for _, other in ipairs(not here[q] and questSt[q] or {}) do
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
  for i = 1, cut do out[#out + 1] = list[i] end
  for _, step in ipairs(pre or {}) do out[#out + 1] = step end
  for i = cut + 1, #list do out[#out + 1] = list[i] end
  return out
end

local function gray(q)
  local info = R.quests[q]
  return info and info.lvl and info.lvl > 0 and (UnitLevel("player") or 0) - info.lvl > (C.GreenRange() or 8)
end
E.Gray = gray

-- ── locate ──────────────────────────────────────────────────────────────────
-- 回 { st, steps, done[], na[], cur, auto, missed = { {q, i}... }, complete }
function E.Locate(st)
  local db = MG.db
  local fillInfo = E.FillPlan(st)
  local steps = stepsOf(st)
  local n = #steps
  local map, x, y = C.Position()
  local done, na, autoDone = {}, {}, {}
  for i, step in ipairs(steps) do
    local s = step.s
    na[i] = step.defer or (s.q and db.notNow["a:" .. s.q] and not C.IsOnQuest(s.q)) or s.t == "need" or (s.t == "train" and (not MG.UI.Get("trainOn") or (UnitLevel("player") or 0) < s.lv)) or not E.Applies(s.when) or (s.q and not raceOK(s.q)) or db.skip[step.key] or optOut(s) or (s.q and (excluded(s.q) or not available(s.q))) or false
    local auto = stepDone(step, map, x, y)
    autoDone[i] = auto
    local mark = db.mark[step.key]
    if mark ~= nil and mark == auto then db.mark[step.key] = nil; mark = nil end
    done[i] = na[i] or (mark ~= nil and mark) or (mark == nil and auto)
  end
  -- 軟步驟（交通、到達、鳥點、飛行、船）：後面任一任務步驟已完成就算過了；
  -- 後面已沒有任務步驟的（往下一站的交通）不擋路，文字留給「前往下一站」顯示
  -- passed：被後面任務帶過的軟步驟（當作過了，但清單不打勾）；tails：站尾往下一站的交通（任務都做完才輪到它）
  local tail, tails, passed = nil, {}, {}
  local nxt = E.Next(st)
  for i, step in ipairs(steps) do
    if not done[i] and SOFT[step.s.t] then
      local later = false
      for j = i + 1, n do
        if steps[j].s.q and not na[j] then
          later = true
          if done[j] then done[i] = true; passed[i] = true; break end
        end
      end
      if not later then
        tails[i] = true
        tail = tail or step.s.text
        if nxt and map and map == nxt.map then done[i] = true end -- 已經到下一站的地圖
      end
    end
  end

  -- 由前往後找未完成；後面 8 個（別的任務的）任務步驟過半已完成 → 算漏掉
  local auto, missedIdx, missedQ = nil, {}, {}
  for i = 1, n do
    local q = steps[i].s.q
    if tails[i] or steps[i].s.t == "train" then
      -- 站尾交通先跳過，任務步驟都處理完才輪到；學技能只當提醒（步驟列下方），不擋路
    elseif not done[i] and q and missedQ[q] then
      missedIdx[#missedIdx + 1] = i -- 同一任務前面的步驟已漏掉（例如沒接就輪到交）
    elseif not done[i] and q and steps[i].s.t ~= "accept" and not (steps[i].s.tag and steps[i].s.tag:find("怪多", 1, true)) and C.IsOnQuest(q) then
      auto = i; break -- 任務還在日誌裡（例如做到一半）：不算漏掉，就是目前要做的；順路先做了後面的步驟也不會被跳過去。「怪多」的可跳過任務除外（順手打到也不拉回去）
    elseif not done[i] then
      local seen, d, j = 0, 0, i + 1
      while j <= n and seen < 8 do
        local s2 = steps[j].s
        if s2.q and s2.q ~= steps[i].s.q and not na[j] then
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
    for i = 1, n do if tails[i] and not done[i] and not na[i] then auto = i; break end end
  end

  -- 手動釘住的步驟：原本未完成、後來完成了就放掉；釘回自動位置也放掉
  local cur = auto
  local pin = db.pin[st.id]
  if pin then
    local found
    for i, step in ipairs(steps) do
      if step.key == pin.key then found = i; break end
    end
    if not found or (done[found] and not pin.wasDone) or found == auto or (pin.auto and (auto and steps[auto].key or "") ~= pin.auto) then
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
    if q and not seenQ[q] then
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
    for i = cur + 1, n do if not na[i] and not done[i] then total = total + 1; num[i] = total end end
  end
  -- 附近可一起做的步驟：目前步驟之後 8 步內，還沒做、已在日誌的「做」（或同地點的接／交），
  -- 座標靠近目前步驟（或已併入的步驟）；遇到交通、爐石、飛行、船就停
  local group, inGroup = {}, {}
  local UI = MG.UI
  local cs = cur and steps[cur].s
  if cur and UI.Get("groupOn") and cs.x then
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
        if s.t == "travel" or s.t == "hearth" or s.t == "fly" or s.t == "boat" or s.t == "fp" then break end
        local ok = (s.t == "do" and s.q and C.IsOnQuest(s.q)) or s.t == "accept" or (s.t == "turnin" and s.q and C.IsOnQuest(s.q) and ready(s.q))
        local p = ok and near(s)
        if p then
          group[#group + 1] = i
          inGroup[i] = true
          spots[#spots + 1] = p
        end
      end
    end
  end
  local train
  for i = 1, n do if steps[i].s.t == "train" and not done[i] and not na[i] and i ~= cur then train = train or i end end
  return { train = train, group = group, inGroup = inGroup, fill = fill, fillInfo = fillInfo, num = num, total = total, autoDone = autoDone, st = st, steps = steps, done = done, na = na, cur = cur, auto = auto, missed = missed, complete = auto == nil, map = map, tail = tail, tails = tails, passed = passed }
end

-- ── 站 ──────────────────────────────────────────────────────────────────────
-- 完成數／總數（以任務計）
function E.Progress(st)
  local total, got, seen = 0, 0, {}
  for _, step in ipairs(st.list) do
    local q = step.s.q
    if q and not seen[q] and E.Applies(step.s.when) and not optOut(step.s) and raceOK(q) then
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

-- 跳站：中間略過的站未交任務分「順路補」與「可放掉」
function E.Jump(target)
  local db = MG.db
  local from = E.Current()
  local carry, dropN = {}, 0
  if from and from.index and target.index > from.index then
    for k = from.index, target.index - 1 do
      local st = E.stations[k]
      local seen = {}
      for _, step in ipairs(st.list) do
        local q = step.s.q
        if q and not seen[q] and E.Applies(step.s.when) and not turned(q) then
          seen[q] = true
          local info = R.quests[q] or {}
          local onQ = C.IsOnQuest(q)
          if info.chain or info.keep or (onQ and not gray(q)) then carry[#carry + 1] = q else dropN = dropN + 1 end
        end
      end
      if k ~= from.index then db.drop[st.id] = true end
    end
  end
  db.carry[target.id] = #carry > 0 and carry or nil
  db.drop[target.id] = nil
  db.station = target.id
  db.pin[target.id] = nil
  if #carry > 0 or dropN > 0 then
    local names = {}
    for _, q in ipairs(carry) do names[#names + 1] = (R.quests[q] and R.quests[q].n) or tostring(q) end
    MG.msg(L["跳到 %s。順路補 %d 個%s；可放掉 %d 個"]:format(target.name, #carry, #names > 0 and (L["："] .. table.concat(names, L["、"])) or "", dropN))
  end
end

function E.Select(st)
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
  MG.db.pin[state.st.id] = { key = step.key, wasDone = state.done[i] and true or false, auto = state.auto and state.steps[state.auto].key or "" }
end

-- 略過（連帶）：略過「接」或「做」→ 這個任務的接／做／交 ＋ 後續任務的全部步驟；略過「交」→ 只連帶後續任務。
-- 存法：skip[key] = 起點的 key（起點自己也存自己），取消時把同一個起點的全部還原。
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
    if q and not seen[q] and not step.carry and not turned(q) and (skipped or not (state.done[i] or state.na[i])) then
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
  MG.msg(L["補做 %s：排在本站最前面，做完回原路線"]:format(questName(p)))
end

-- 開了本職業訓練師（不是專業技能訓練師）：等級已到的「學」步驟都算做完，不管是哪一位訓練師
function E.Trained()
  if IsTradeskillTrainer and IsTradeskillTrainer() then return end
  local lv = UnitLevel("player") or 0
  for _, step in ipairs(E.trainSteps) do
    if step.s.lv <= lv then MG.db.latch[step.key] = true end
  end
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
  return L["不在路線上"], "之後順路", L["順路再做"]
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

function E.ToggleSkip(key)
  local skip = MG.db.skip
  local root = skip[key]
  if root then
    if root == true then root = key end
    for k, v in pairs(skip) do if k == root or v == root then skip[k] = nil end end
    MG.msg(L["已取消略過"])
    return
  end
  local t, q = key:match("^(%a):(%d+)$")
  q = tonumber(q)
  skip[key] = key
  if not q then return end
  local names, later = { questName(q) }, {}
  local here = MG.db.station and E.byId[MG.db.station]
  if t ~= "t" then
    for _, p in ipairs({ "a", "d", "t" }) do if not skip[p .. ":" .. q] then skip[p .. ":" .. q] = key end end
  end
  -- 後續任務（遞迴）
  local seen, queue = { [q] = true }, { q }
  while #queue > 0 do
    local cur = table.remove(queue, 1)
    for _, f in ipairs((R.quests[cur] or {}).fol or {}) do
      if not seen[f] then
        seen[f] = true
        queue[#queue + 1] = f
        local o -- 後續任務在別站時標地名（本站的不標）
        for _, x in ipairs(questSt[f] or {}) do if x ~= here then o = o or x end end
        later[#later + 1] = questName(f) .. (o and L["（%s）"]:format(place(o, here)) or "")
        for _, p in ipairs({ "a", "d", "t" }) do if not skip[p .. ":" .. f] then skip[p .. ":" .. f] = key end end
      end
    end
  end
  local imp = here and E.Impact(q, here) or {}
  MG.msg(L["已略過："] .. names[1] .. (#later > 0 and (L["、後續 "] .. table.concat(later, L["、"])) or "") .. (#imp > 0 and (L["。"] .. E.ImpactText(imp, here)) or ""))
end

-- 手動勾選：val = true／false；nil＝回到自動
function E.SetMark(key, val) MG.db.mark[key] = val end

function E.Realign()
  wipe(MG.db.pin)
  -- 一併清掉目前站的手動勾選
  local old = MG.db.station and E.byId[MG.db.station]
  local n = 0
  for _, step in ipairs(old and old.list or {}) do
    if MG.db.mark[step.key] ~= nil then MG.db.mark[step.key] = nil; n = n + 1 end
  end
  if n > 0 then MG.msg(L["已清除 %d 個手動勾選"]:format(n)) end
  MG.db.station = nil
  local st = E.Current()
  if st then MG.msg(L["重新對齊："] .. st.name) end
end


-- ── 副本 ────────────────────────────────────────────────────────────────────
-- 副本站不在主線；它的前置（接／做／交）預設排進建議的主線站（pickAt），標「副本前置」。
-- 任務日誌快滿（可接 < 3）時，建議等級比玩家高 5 級以上的副本前置先不接（之後再接）；主線任務不受影響。
local function logFree()
  local max = C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or 25
  return (max or 25) - #(C.LogQuestIDs() or {})
end

-- 不經過 locate 的單步完成判定（副本分頁用；不動 fill）
function E.QuickDone(step)
  local m = MG.db.mark[step.key]
  if m ~= nil then return m end
  return stepDone(step) and true or false
end

function E.DungeonDone(d)
  for _, step in ipairs(d.list) do
    if step.s.ph == "post" and step.s.q and not turned(step.s.q) then return false end
  end
  return true
end

-- 前置任務：{ total, accepted }（接受或已交都算）
function E.DungeonPre(d)
  local total, got, seen = 0, 0, {}
  for _, step in ipairs(d.list) do
    local s = step.s
    if s.ph == "pre" and (s.t == "accept" or s.t == "need") and s.q and not seen[s.q] and E.Applies(s.when) then
      seen[s.q] = true
      total = total + 1
      if C.IsOnQuest(s.q) or turned(s.q) then got = got + 1 end
    end
  end
  return total, got
end

function E.DungeonStatus(d)
  local lv = UnitLevel("player") or 1
  if E.DungeonDone(d) or lv > d.lv[2] + 3 then return L["已過"], "past" end
  local minPick = d.lv[1]
  for _, step in ipairs(d.list) do if step.s.pickLv and step.s.pickLv < minPick then minPick = step.s.pickLv end end
  if lv < minPick then return L["%d 級"]:format(minPick), "low" end
  local total, got = E.DungeonPre(d)
  if total == 0 or got >= total then return lv >= d.lv[1] and L["可以去"] or L["%d 級再去"]:format(d.lv[1]), "ready" end
  local tg, tt = E.DungeonTargetCount(d)
  if got > 0 then return L["前置 "] .. tg .. "/" .. tt, "some" end
  -- 前置任務本身還有前置（任務鏈沒做）→ 先做前置鏈（見前置接取路線）
  for _, step in ipairs(d.list) do
    local st = step.s
    if st.ph == "pre" and st.t == "accept" and st.q and E.Applies(st.when) and available(st.q) then return L["前置可接"], "pick" end
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
  for _, d in ipairs(E.dungeons) do
    if d.pickAt == st.id and not MG.db.dNo[d.id] then
      local defer = d.lv[1] > lv + 4 and logFree() < 3
      for _, step in ipairs(d.list) do
        local s = step.s
        if s.ph == "pre" and s.t ~= "travel" and s.t ~= "need" and not have[step.key] and (not s.pickLv or lv >= s.pickLv) then
          have[step.key] = true
          out = out or {}
          out[#out + 1] = { s = s, key = step.key, st = d, dungeon = d, defer = defer and s.t == "accept" and not C.IsOnQuest(s.q) or nil }
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
      local _, kind = E.DungeonStatus(d)
      if kind ~= "past" then
        -- 前置鏈還沒做完：說還剩幾步；否則說前置還有幾個沒接
        local left = 0
        for _, step in ipairs(d.list) do
          local s = step.s
          if s.tag == "副本前置鏈" and E.Applies(s.when) and (not s.q or raceOK(s.q)) and not E.QuickDone(step) then left = left + 1 end
        end
        if left > 0 then return d, L["先做前置鏈（%d 步）"]:format(left) end
        local total, got = E.DungeonPre(d)
        return d, total > got and L["前置 %d/%d 未接"]:format(total - got, total) or nil
      end
    end
  end
end

-- 設為目標：步驟列改走這個副本的流程；打完（或離開副本）再回主線
function E.RunDungeon(d)
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
    local here = table.concat({ GetSubZoneText and GetSubZoneText() or "", GetMinimapZoneText and GetMinimapZoneText() or "", GetZoneText and GetZoneText() or "" }, " ")
    for k, d in ipairs(all) do
      local wing = tostring(d.name or ""):match("(%S+)$")
      if wing and wing ~= d.name and here:find(wing, 1, true) then
        table.remove(all, k); table.insert(all, 1, d); break
      end
    end
  end
  return all[1], all
end

-- 副本裡的步驟列：這個副本的任務（路線上的＋QuestieDB 屬於這個副本區域的），只列日誌中的，一次全列
function E.InstanceState(d, all)
  local steps, seen = {}, {}
  local function add(q)
    if q and not seen[q] and C.IsOnQuest(q) then
      seen[q] = true
      steps[#steps + 1] = { s = { t = "do", q = q }, key = "d:" .. q, st = d }
    end
  end
  for _, x in ipairs(all or { d }) do
    for _, step in ipairs(x.list or {}) do add(step.s.q) end
    for _, q in ipairs(x.dq or {}) do add(q) end
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
    if s.ph == "pre" and s.q and E.Applies(s.when) and raceOK(s.q) then
      if preTurn[s.q] then
        if not seenC[s.q] then seenC[s.q] = true; pending[#pending + 1] = step end
      elseif (s.t == "accept" or s.t == "need") and not seenT[s.q] then
        seenT[s.q] = true
        targets[#targets + 1] = { q = s.q, step = step, chain = pending }
        pending = {}
      end
    end
  end
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
  local _, kind = E.DungeonStatus(d)
  if kind == "past" or MG.db.dNo[d.id] then return nil end
  local lv = UnitLevel("player") or 1
  if kind == "low" then return { kind = "low", title = L["%d 級可接前置"]:format(minPickLv(d)) } end
  local function first(ph, extra)
    for _, step in ipairs(d.list) do
      local s = step.s
      if s.ph == ph and s.t ~= "travel" and s.t ~= "need" and E.Applies(s.when) and (not s.q or raceOK(s.q))
        and not E.QuickDone(step) and (not extra or extra(step)) then return step end
    end
  end
  if inside then
    local step = first("in")
    if step then return { kind = "in", step = step } end
  end
  local pre = first("pre", function(step)
    local s = step.s
    if s.pickLv and lv < s.pickLv then return false end
    if s.t == "accept" and s.q and not available(s.q) then return false end
    return true
  end)
  if pre then return { kind = "pre", step = pre } end
  if lv < d.lv[1] then return { kind = "wait", title = L["%d 級再去"]:format(d.lv[1]) } end
  if first("in") then return { kind = "ent" } end
  local post = first("post")
  if post then return { kind = "post", step = post } end
  return nil
end

-- 步驟的顯示文字
local VERB = setmetatable({}, { __index = function(_, t)
  local zh = ({ train = "學", accept = "接", ["do"] = "做", turnin = "交", ["goto"] = "到", fp = "鳥", hearth = "爐", fly = "飛", boat = "船", level = "練", travel = "行", need = "需" })[t]
  return zh and L[zh]
end })
E.VERB = VERB
-- 動詞：非中文介面的交通／前往步驟，說明本身已是祈使句（Leave…、Take…）就不再加「Go」
local IMPERATIVE = { Go = true, Leave = true, Take = true, Fly = true, Ride = true, Run = true, Head = true, Return = true, Enter = true, Use = true,
  Hearth = true, Travel = true, Follow = true, Swim = true, Walk = true, Cross = true, Board = true, Exit = true, Get = true, Continue = true, Back = true, From = true, At = true, After = true, If = true }
function E.Verb(s)
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
function E.Title(s)
  if s.t == "need" then return s.text or "" end
  if s.q then return E.QName(s.q) end
  -- 交通／到達沒有文字：只寫地點（動詞框已經是「去」）
  if s.t == "travel" then return s.text and (E.Clause(s.text)) or (s.map and where(s)) or L["交通"]
  elseif s.t == "goto" then return s.text or (s.map and where(s)) or L["前往"]
  elseif s.t == "fp" then return L["開鳥點："] .. (s.node or (s.map and C.MapName(s.map)) or "")
  elseif s.t == "hearth" then return L["綁爐石："] .. (s.bind or (s.map and C.MapName(s.map)) or "")
  elseif s.t == "fly" then return L["飛往 "] .. (s.to or "")
  elseif s.t == "boat" then return L["搭船／飛艇往 "] .. (s.to or "")
  elseif s.t == "level" then return L["練到 %s 級"]:format(s.lv or "?")
  elseif s.t == "train" then return L["去學技能："] .. (s.npc or "") .. (s.place and L["（%s）"]:format(s.place) or "") end
  return s.text or ""
end
