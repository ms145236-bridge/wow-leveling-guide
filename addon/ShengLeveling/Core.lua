-- 事件、節流重算、slash、自動接交任務、/slv probe。
local ADDON, MG = ...
local E, C, N, UI = MG.E, MG.C, MG.N, MG.UI
local L = MG.L
local R = MG.Route or { stations = {}, quests = {} }

local DEFAULTS = { notNow = {}, fpSeen = {}, fpSkip = {}, grindSkip = {}, dNo = {}, dDismiss = {}, mark = {}, pin = {}, skip = {}, skipNote = {}, optNote = {}, latch = {}, drop = {}, carry = {}, shown = true } -- 其餘設定的預設在 UI.lua 的設定表
local f = CreateFrame("Frame")
local registered = {} -- 事件 → 是否註冊成功（probe 用）
local trace = {} -- 事件參數紀錄（probe 用）
local dirty, ready, since, tick, started = false, false, 0, 0, nil
local logSeen, skipSync = false, 0 -- 登入後連帶略過重算過了沒：1＝等不到 QUEST_LOG_UPDATE 先算過、2＝任務日誌到了以後算過
local lastState
local visitChecks, priorVisit = {}, {}

-- ── 重算 ────────────────────────────────────────────────────────────────────
-- 副本裡：只列這個副本的任務（一次全列），不顯示主線、箭頭、地圖標點；對不到就整個隱藏。出副本後回主線並重新對齊。
local inInstance, enterLevel = false, nil
local lastArrowKey
local lastDetour
local lastPos
local onTaxi = false -- 失去控制時是不是在鳥上（下鳥才算「飛」完成）
local function instanceView()
  if not (IsInInstance and GetInstanceInfo) then return false end
  local inside, kind = IsInInstance()
  if not (inside and (kind == "party" or kind == "raid") and UI.Get("dungeonOnly")) then return false end
  if not inInstance then inInstance, enterLevel = true, UnitLevel("player") end
  local id = select(8, GetInstanceInfo())
  E.DeferOutdoorHandoff(E.byId[MG.db.station], id)
  local d, all = E.DungeonByInstance(id)
  local ist = d and E.InstanceState(d, all)
  lastState = ist
  N.Clear()
  MG.try("地圖標點", MG.P.Clear)
  if ist then
    UI.SetHidden(false)
    UI.Render({ state = ist })
  else
    UI.SetHidden(true)
  end
  MG.try("目標按鈕", MG.T.Update, ist)
  MG.try("任務物品", MG.I.Update, ist)
  return true
end

-- 箭頭要指的點（主座標＋more 各群）：玩家所在地圖上最近的一群；這張地圖上沒有就指主座標（沒有主座標就是第一群）。
-- 換群要比目前那群近 2.5 格以上（或不到 6 成距離）並維持 2 秒，走在兩群中間不會來回跳；換步驟、換地圖就直接挑最近的；任務進度變了不用等 2 秒（距離門檻照舊）
local arrowStep -- 箭頭目前指的步驟（位置檢查時重挑點用）
local function navPoint(s)
  local map, x, y = C.Position()
  local prog = ""
  for _, o in ipairs(s.q and C.Objectives(s.q) or {}) do prog = prog .. tostring(o.have) .. tostring(o.done) .. "," end
  local pick = MG.navPick
  if not (pick and pick.s == s and pick.map == map) then pick = { s = s, map = map, prog = prog } end
  local progressed = pick.prog ~= prog -- 任務進度變了：夠近的那群不用等 2 秒就換（差一點點的不換，邊打邊移動時箭頭不會在兩群之間跳）
  pick.prog = prog
  MG.navPick = pick
  local pts = { s.x and { s.map, s.x, s.y } or nil }
  for _, p in ipairs(s.more or {}) do pts[#pts + 1] = p end
  local function far(p) return math.sqrt((p[2] - x) ^ 2 + (p[3] - y) ^ 2) end
  local function same(a, b) return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
  local best, bd
  for _, p in ipairs(x and y and pts or {}) do
    if p[1] == map and (not bd or far(p) < bd) then best, bd = p, far(p) end
  end
  local cur = pick.p and pick.p[1] == map and pick.p
  local nextP = cur
  if not best then nextP, pick.cand = pts[1], nil
  elseif not cur then nextP, pick.cand = best, nil
  elseif same(best, cur) or not (far(cur) - bd >= 2.5 or bd < far(cur) * 0.6) then pick.cand = nil
  elseif progressed or (same(best, pick.cand) and GetTime() - pick.since >= 2) then nextP, pick.cand = best, nil
  elseif not same(best, pick.cand) then pick.cand, pick.since = best, GetTime() end
  if not same(nextP, pick.p) then pick.p = nextP end -- 同一點留原本的表（位置檢查用 ~= 判斷有沒有換）
  return pick.p
end

local function refresh()
  if instanceView() then return end
  if inInstance then
    -- 剛出副本：在跑副本流程或升級了 → 重新對齊主線（等級超過時會出現跳站建議）
    inInstance = false
    UI.SetHidden(false)
    -- 出副本：臨時航點（副本分頁設的入口等）收回，箭頭回到目前步驟
    MG.wpOverride, MG.grindActive = nil, nil
    N.Forget()
    local cur = MG.db.station and E.byId[MG.db.station]
    if not (cur and MG.db.deferredHandoffRun == cur.id and E.OutdoorHandoff(cur)) and ((cur and cur.dungeon) or (UnitLevel("player") or 0) > (enterLevel or 99)) then
      MG.db.deferredHandoffRun = nil
      MG.db.station = MG.db.dungeonFrom
      MG.db.dungeonFrom = nil
      if MG.db.station and E.byId[MG.db.station] then
        local got, total = E.Progress(E.byId[MG.db.station])
        if got >= total then MG.db.station = nil end
      end
    end
  end
  local st = E.Current()
  local state = st and E.Locate(st)
  -- 副本流程做完（出本後交完）→ 回主線
  if st and st.dungeon and state and state.complete then
    MG.db.station = MG.db.deferredHandoffRun == st.id and MG.db.dungeonFrom or nil
    MG.db.deferredHandoffRun = nil
    MG.db.dungeonFrom = nil
    st = E.Current()
    state = st and E.Locate(st)
  end
  -- 本站完成且已進入下一站的地圖 → 自動換站
  if state and state.complete then
    local nxt = E.Next(st)
    if nxt and state.map and state.map == nxt.map then
      E.Select(nxt)
      st, state = nxt, E.Locate(nxt)
    end
  end
  local previous = lastState and lastState.cur and lastState.steps[lastState.cur]
  local current = state and state.cur and state.steps[state.cur]
  if previous and previous.s.chooseGrindSpot and (not current or current.key ~= previous.key) and MG.grindActive then
    MG.grindActive = nil
    if MG.wpOverride and MG.wpOverride.grind then MG.wpOverride = nil end
  end
  lastState = state
  -- 手動略過的任務本身或後面有副本任務、好獎勵：聊天框提一次；可跳過沒開的整站合成一句
  for _, step in ipairs(state and state.steps or {}) do
    local s = step.s
    local text = s.q and MG.db.skip[step.key] and E.Applies(s.when) and E.SkipNotice(s.q)
    if text then MG.msg(text) end
  end
  local optText = state and state.st and E.OptNotice(state)
  if optText then MG.msg(optText) end
  local nextSt = st and E.Next(st)
  if UI.Visible() then
    UI.Render({ state = state, sug = E.Suggest(st), nextSt = nextSt })
    UI.AuberdineChoice(state)
  end -- 步驟列關著就不畫（打開時會重算）
  MG.try("目標按鈕", MG.T.Update, state)
  MG.try("任務物品", MG.I.Update, state)
  -- 箭頭：目前步驟的座標；本站完成時指向下一站第一個有座標的步驟
  local s = state and state.cur and state.steps[state.cur].s
  -- 本站完成，或目前是站尾交通但沒有座標 → 指向下一站第一個有座標的步驟
  if state and not state.pendingExit and nextSt and (not state.cur or (state.tails and state.tails[state.cur] and not (s and s.x))) then
    for _, step in ipairs(nextSt.list) do
      if step.s.x and E.Applies(step.s.when) then s = step.s; break end
    end
  elseif state and state.cur and s and not s.x and not s.q and not s.chooseGrindSpot and not (s.localTransfer or s.classTransfer) then
    -- 沒座標的交通、提醒：指向本站後面第一個還沒完成、有座標的步驟（走到就算到了，見 E.Locate）
    local _, target = E.SoftTargets(state.steps, state.done, state.na, state.cur)
    if s.sameMapPreview then
      local map, x, y = C.Position()
      if target and x and y and target.map == map then s = target end
    else
      s = target or s
    end
  end
  local curKey = state and state.cur and state.steps[state.cur].key
  if curKey ~= lastArrowKey then
    if MG.wpOverride then dirty = true end -- 步驟列的「原本 … 返回」要跟著收
    MG.wpOverride = nil; lastArrowKey = curKey
  end
  -- 臨時航點（不是目前步驟）：走到了（keep 的除外，例如練怪點）或目的達成（done）就收回
  local o = MG.wpOverride
  if o then
    local map, x, y = C.Position()
    local reached = not o.keep and map == o.map and x and y and math.abs(x - o.x) + math.abs(y - o.y) < 0.6
    if reached or (o.done and o.done()) then
      if o.grind then MG.grindActive = nil end
      MG.wpOverride, o = nil, nil
      N.Forget()
      dirty = true -- 步驟列的「原本 … 返回」要跟著收
    end
  end
  arrowStep = nil
  if o then N.Set(o.map, o.x, o.y, o.name)
  elseif s and s.via and state.cur and state.steps[state.cur].s == s then
    local p = E.ViaTarget(state.steps[state.cur]) -- 好幾個座標的交通：指向下一個還沒走到的點
    N.Set(p[1], p[2], p[3], MG.Clean(E.Title(s, true)))
  elseif s and (s.x or s.more) then
    arrowStep = s
    local p = navPoint(s)
    N.Set(p[1], p[2], p[3], MG.Clean(E.Title(s, true)))
  else N.Clear() end
  MG.try("地圖標點", MG.P.Update, state) -- 箭頭挑好群之後才畫（目前步驟的實心點跟著箭頭）
end

function MG.Refresh(now)
  if now then
    dirty = false
    if ready and started then
      -- 登入：存檔裡的連帶略過照現在的任務狀態重算一次（舊版留下的、沒開插件時交掉前置的）。任務日誌到了才算數；
      -- 等不到（3 秒）先算一次，之後日誌真的到了再算一次
      local want = logSeen and 2 or 1
      if skipSync < want then
        skipSync = want
        if next(MG.db.skip) then E.RecomputeSkip() end
      end
      MG.C.memo = {}
      MG.try("重算", refresh)
      MG.C.memo = nil
    end
  else
    dirty = true
  end
end

f:SetScript("OnUpdate", function(_, dt)
  since = since + dt
  tick = tick + dt
  if not ready and started and GetTime() - started > 3 then ready = true; dirty = true end -- 等不到 QUEST_LOG_UPDATE 也開始
  if dirty and since >= 0.25 then
    since = 0
    MG.Refresh(true)
  end
  -- 到達型步驟：每 0.5 秒檢查一次
  if tick >= 0.5 then
    tick = 0
    -- 沒移動而且沒有等待中的順路提醒就不用重看。和上次檢查時的位置比（不是上一次取樣）：慢慢走的小位移會累積到門檻。
    -- 門檻 0.2%；目前是到達型步驟或有臨時航點時 0.02%（大地圖上走路 0.5 秒不到 0.05%，停在到達範圍邊上也要看得到）
    local map, x, y = C.Position()
    local checks = lastState and not lastState.instance and lastState.st and visitChecks[lastState.st.id]
    if checks then
      for _, when in ipairs(checks) do
        local applies = E.Applies(when)
        if priorVisit[when] ~= applies then priorVisit[when], dirty = applies, true end
      end
    end
    local at = lastState and lastState.cur and lastState.steps[lastState.cur].s
    local soft = at and (not at.x or at.t == "boat") and E.SOFT[at.t] and not lastState.instance and not (lastState.tails and lastState.tails[lastState.cur]) -- 沒座標的交通：走到後面步驟附近算到
    local arrive = MG.wpOverride or soft or (at and (at.t == "goto" or (at.t == "travel" and at.x) or at.t == "hearth"))
    local moved = not (lastPos and map == lastPos[1] and x and lastPos[2] and math.abs(x - lastPos[2]) + math.abs(y - lastPos[3]) < (arrive and 0.02 or 0.2))
    if moved then lastPos = { map, x, y } end
    -- 箭頭指的是好幾群點的步驟：走動時（或等著換群時）重挑點，換了就重畫箭頭與標點
    local pick = MG.navPick
    if arrowStep and arrowStep.more and (moved or (pick and pick.cand)) then
      local old = pick and pick.s == arrowStep and pick.p
      MG.try("箭頭選點", navPoint, arrowStep)
      if MG.navPick.p ~= old then dirty = true end
    end
    if moved or E.DetourPending() then
      MG.C.memo = {}
      MG.try("位置檢查", function()
      local cur = lastState and lastState.cur and lastState.steps[lastState.cur].s
      if cur and (cur.t == "goto" or (cur.t == "travel" and cur.x) or cur.t == "hearth") then dirty = true end -- 爐石：走到下一步附近也算到（E.Locate）
      if soft and x and E.SoftNear(cur, E.SoftTargets(lastState.steps, lastState.done, lastState.na, lastState.cur), map, x, y) then dirty = true end
      if MG.wpOverride then dirty = true end -- 臨時航點：走到了要收回
      -- 順路提醒、附近危險、沒開的飛行點：位置一變就要重看，結果有變才重畫
      local danger, fp = E.Nearby(lastState and not lastState.instance and lastState.st)
      local d = tostring((E.Detour(lastState))) .. tostring(danger) .. tostring(fp)
      if d ~= lastDetour then lastDetour = d; dirty = true end
      end)
      if moved and lastState and not lastState.instance then MG.try("地圖標點", MG.P.Update, lastState) end -- 走進／走出順路點的顯示範圍（簽章沒變就不重畫）
      MG.C.memo = nil
    end
  end
end)

local HEARTH_SPELL = { [8690] = true, [556] = true } -- 爐石、星界傳送（薩滿）
local hearthAt -- 爐石施法成功的時間（等換區）
-- 目前步驟是某類型時記一筆（到達、開鳥點、下飛行、換區搭船、爐石到了）
local function latchCurrent(t)
  local cur = lastState and lastState.cur and lastState.steps[lastState.cur]
  if cur and cur.s.t == t then MG.db.latch[cur.key] = true end
end
-- 飛／船的目的地、出發地（鳥點中文名）在哪張地圖：路線上有這個鳥點才查得到
local mapOf = function(node) return E.NodeMap(node) end

-- ── 自動接交任務（設定預設開；按住 Shift 暫停） ─────────────────────────────
-- 同名任務很多（例如「馴服野獸」有 10 個 ID），所以標題對到的是 ID 清單
local nameToQuest
local function routeQuestsByTitle(title)
  if not nameToQuest then
    nameToQuest = {}
    local function put(name, id)
      local list = nameToQuest[name] or {}
      list[#list + 1] = id
      nameToQuest[name] = list
    end
    for id, q in pairs(R.quests) do
      local n = q.nG or q.n -- 客戶端語言的任務名（遊戲給的標題是這個語言）
      if n then put(n, id) end
      if q.zt and q.zt ~= n then put(q.zt, id) end -- 遊戲內 zhTW 名（和路線寫的名字不同時）
    end
  end
  return title and nameToQuest[title] or {}
end
local function autoOn() return UI.Get("auto") and not IsShiftKeyDown() end
local accQ = {} -- 任務 → 路線上每個「接」步驟 { when, opt, d＝所屬副本前置 ID, at＝主線站 ID }
local manualFrom = {} -- A later manual pickup must not inherit its earlier station's automatic accept.
local localRecovery = {}
local anyG = {} -- 任一組（例如紮營入門指南任選專業）的每個任務 → 組的第一個 ID（略過鍵 a:第一個）
for _, st in ipairs(R.stations) do
  for _, s in ipairs(st.steps) do
    if s.when and (s.when.workMap or s.when.localVisit or (s.q and (R.quests[s.q] or {}).providedVisit) or (s.when.readyQuest and ((R.quests[s.q] or {}).deliveryItems or s.afterWork))) then
      visitChecks[st.id] = visitChecks[st.id] or {}
      table.insert(visitChecks[st.id], s.when)
    end
    if s.t == "accept" and s.q then
      if s.when and s.when.localRaces then localRecovery[s.q] = s.when end
      for _, q in ipairs(s.any or { s.q }) do -- 任一組：每個成員都記同一筆（同一個可跳過、略過狀態）
        local l = accQ[q] or {}
        accQ[q] = l
        l[#l + 1] = { when = s.when, opt = s.opt, d = st.dungeon and st.id or (s.when and s.when.dungeonPrep), at = not st.dungeon and st.id or nil, manual = s.manualAccept }
        if s.when and s.when.manualPickup then manualFrom[q] = { station = st.id, step = s } end
        if s.any then anyG[q] = s.any[1] end
      end
    end
  end
end
-- 路線上的任務，和引擎的判斷一致：在日誌裡的都算（交任務）；手動略過的不自動接。
-- 其餘要有一個本角色適用的「接」步驟算數：可跳過的要設定有開或被補經驗補回，副本段的要那個副本沒選不打；路線上只有做／交的照舊算
local autoQ = {} -- 最近三秒自動接取，記錄當次接受後預期的日誌數量

local function releaseAutoSlot(id)
  local rec = autoQ[id]
  if not rec then return end
  autoQ[id] = nil
  if GetTime() - rec.at >= 3 then return end
  -- 後接任務的預期數量含這一格。已知移除的任務只回收一次。
  for _, later in pairs(autoQ) do
    if later.at >= rec.at and later.slot > rec.slot then later.slot = later.slot - 1 end
  end
end

function MG.PendingAccepts(used, visible)
  local listed, pending, now = {}, 0, GetTime()
  for _, q in ipairs(visible) do listed[q] = true end
  for q, rec in pairs(autoQ) do
    if now - rec.at >= 3 then autoQ[q] = nil
    elseif not listed[q] and not (used >= rec.slot and (rec.confirmed or C.IsOnQuest(q))) then pending = pending + 1 end
  end
  return pending, listed
end
local function inRoute(id, forAccept)
  if not (id and not (issecretvalue and issecretvalue(id)) and id > 0 and R.quests[id] ~= nil) then return false end
  if C.IsOnQuest(id) then return not forAccept end
  if MG.db.skip["a:" .. (anyG[id] or id)] then return false end
  local start = manualFrom[id] and E.byId[manualFrom[id].station]
  if start then
    local visit = E.byId[MG.db.station] or (lastState and lastState.st)
    if not visit or not visit.index or visit.index >= start.index then return false end
  end
  local optional = UI.Get("optional") or E.Fill[id]
  -- 日誌快滿先不接的副本前置：NPC 給了也不自動接。用這一刻的日誌算（和步驟列的「之後」同一個判斷），不看上次畫好的清單
  local pre, authored = false, false
  for _, a in ipairs(accQ[id] or {}) do
    if a.d and not MG.db.dNo[a.d] then
      pre = true
      authored = authored or a.at ~= nil
    end
  end
  local st = pre and lastState and not lastState.instance and lastState.st
  local main = st and not st.dungeon and st
  local pending, nextSlot, free = 0, nil, nil
  if forAccept or main or authored then
    local used, visible
    free, used, visible = E.QuestLogSpace()
    local listed
    pending, listed = MG.PendingAccepts(used, visible)
    if forAccept and (listed[id] or autoQ[id] or free <= pending) then return false end
    nextSlot = used + pending + 1
  end
  local tight = (main or authored) and not E.PreRoom(main, pending, free)
  for _, a in ipairs(accQ[id] or {}) do
    local when = a.when
    if when and when.lvMin and not when.canStart then -- 普通 NPC 已給的任務不看等級；明列條件的物品起始任務仍須符合。
      when = {}
      for k, v in pairs(a.when) do when[k] = v end
      when.lvMin = nil
    end
    if not a.manual and E.Applies(when) and (not a.opt or optional) then
      if a.d then
        if not MG.db.dNo[a.d] and not tight then return true, nextSlot end
      elseif not tight or not main or (E.byId[a.at] and E.byId[a.at].index <= main.index) then
        return true, nextSlot -- 主線的接。快滿時的副本前置：主線這一站或之前就排了才接，排在後面站的走到再接
      end
    end
  end
  return not accQ[id], nextSlot
end

-- 安全網：打開目前「接」步驟的 NPC，卻沒有這個任務可接 → 先跳過（升級或交任務後再看）。
-- 只直接跳出任務內容（沒有先開對話選單）才看 QUEST_DETAIL，避免自動接交選了別的任務時誤判。
local function speakingTo(s)
  local name = UnitName and UnitName("npc")
  return name and not (issecretvalue and issecretvalue(name)) and (name == (s.npcG or s.npc) or name == s.tgt)
end
local function restoreManualOffer(id)
  local visit = manualFrom[id]
  if not visit or MG.db.station ~= visit.station then return end
  local key = "a:" .. id
  local db = MG.db
  if not db.notNow[key] or db.skip[key] or db.mark[key] ~= nil or C.IsOnQuest(id) or E.Turned(id) then return end
  if E.Applies(visit.step.when) and speakingTo(visit.step) then
    db.notNow[key] = nil
  end
end
local lastMenu, lastAccept = 0, 0
local function notOffered(event)
  local now = GetTime()
  local recent = (event == "QUEST_DETAIL" and now - lastMenu < 3) or now - lastAccept < 3
  if event ~= "QUEST_DETAIL" then lastMenu = now end
  if recent and not next(MG.db.notNow) then return end -- 剛接任務時 NPC 選單會重刷，日誌還沒更新，不判斷
  local ids = {} -- NPC 這次給的任務
  if event == "QUEST_DETAIL" then
    local id = GetQuestID and GetQuestID()
    if not id or (issecretvalue and issecretvalue(id)) then return end
    ids[1] = id
  elseif event == "GOSSIP_SHOW" then
    local G = C_GossipInfo
    if not (G and G.GetAvailableQuests) then return end
    for _, q in ipairs(G.GetAvailableQuests() or {}) do
      if issecretvalue and issecretvalue(q.questID) then return end
      ids[#ids + 1] = q.questID
    end
    -- 第一頁只有對話選項（例如索維克要先點對話才列任務）：還看不出給不給，不判斷
    if #ids == 0 and G.GetOptions and #(G.GetOptions() or {}) > 0 then return end
  else
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
      for _, id in ipairs(routeQuestsByTitle(GetAvailableTitle(i))) do ids[#ids + 1] = id end
    end
  end
  if event ~= "QUEST_GREETING" then
    for _,id in ipairs(ids) do
      restoreManualOffer(id)
      local w = localRecovery[id]
      local key = "a:"..id
      if w and MG.db.notNow[key] and not MG.db.skip[key] and not MG.db.mark[key]
        and not C.IsOnQuest(id) and not E.Turned(id) and E.Applies(w) and E.Applies({nearPoint=w.nearPoint}) then
        MG.db.notNow[key] = nil
      end
    end
  end
  if recent then return end
  -- 任一組：NPC 給了組裡任何一個，整組的「接不到」就收回（不必是目前步驟；含 1.13.15 只認剝皮時留下的 a:97924）
  for _, id in ipairs(ids) do if anyG[id] then MG.db.notNow["a:" .. anyG[id]] = nil end end
  -- NPC 現在給了：之前自動記下的「接不到」收回，不論記在哪一站、鍵有沒有 ~2 後綴（手動略過記在 skip，不動）
  local offered = {}
  for _, id in ipairs(ids) do offered[id] = true end
  for key in pairs(MG.db.notNow) do
    local q = tonumber(tostring(key):match("^a:(%d+)"))
    if q and offered[q] and not manualFrom[q] and not localRecovery[q] then MG.db.notNow[key] = nil end
  end
  local cur = lastState and lastState.cur and lastState.steps[lastState.cur]
  local s = cur and cur.s
  if not (s and s.t == "accept" and s.q) or C.IsOnQuest(s.q) or E.Turned(s.q) then return end
  if not speakingTo(s) then return end
  local want = {}
  for _, q in ipairs(s.any or { s.q }) do want[q] = true end -- 任一組：NPC 給其中任何一個都算有給
  for _, id in ipairs(ids) do if want[id] then return end end
  MG.db.notNow[cur.key] = true -- 清單右欄會寫「接不到」
end

-- 自動接：灰名（太低等）的任務不接，除非就是這一站路線上要接的（例如回低等區交任務時，NPC 身上的舊任務）
local function wantAccept(id)
  if not E.UngoroTrainerOffer(id) then return false end
  if anyG[id] then return false end -- 任一組（任選專業）：玩家自己挑，不自動選、不自動接；接了以後交件照常自動
  -- inRoute also serves turn-ins and accepts logged quests. An item-start offer
  -- may outlive the journal update; do not press Accept again for that quest.
  if C.IsOnQuest(id) then
    for _, source in ipairs(accQ[id] or {}) do
      if source.when and source.when.canStart == id then return false end
    end
  end
  local lv, q = UnitLevel("player") or 1, R.quests[id]
  local range = (UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player")) or (GetQuestGreenRange and GetQuestGreenRange()) or 8
  if not (q and q.lvl) or q.lvl >= lv - range then return true end
  for _, step in ipairs(lastState and not lastState.instance and lastState.steps or {}) do
    if step.s.t == "accept" and step.s.q == id then return true end
  end
  return false
end
local AUTO = {}
local function plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
function AUTO.QUEST_DETAIL()
  local id = GetQuestID and GetQuestID()
  if not plain(id) then return end
  local allowed, nextSlot = inRoute(id, true)
  if not allowed or not wantAccept(id) then return end
  -- 護送、觸發事件的任務（一人接，隊友跳確認框一起開始）：組隊時讓玩家自己按，確認大家準備好
  if R.quests[id].pa and IsInGroup and IsInGroup() then
    MG.msg(L["組隊中：這個任務會讓隊友一起開始，準備好再自己按接受"])
    return
  end
  autoQ[id] = {at=GetTime(), slot=nextSlot}
  AcceptQuest()
end
function AUTO.QUEST_PROGRESS()
  local id = GetQuestID and GetQuestID()
  if inRoute(id) and IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
end
function AUTO.QUEST_COMPLETE()
  local id = GetQuestID and GetQuestID()
  if not inRoute(id) then return end
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n <= 1 then GetQuestReward(n) else MG.msg(L["有 %d 個獎勵可選，請自己挑"]:format(n)) end
end
function AUTO.GOSSIP_SHOW()
  local G = C_GossipInfo
  if not G then return end
  for _, q in ipairs(G.GetActiveQuests and G.GetActiveQuests() or {}) do
    if plain(q.questID) and q.isComplete and inRoute(q.questID) then G.SelectActiveQuest(q.questID); return end
  end
  for _, q in ipairs(G.GetAvailableQuests and G.GetAvailableQuests() or {}) do
    if plain(q.questID) and inRoute(q.questID, true) and wantAccept(q.questID) then G.SelectAvailableQuest(q.questID); return end
  end
end
function AUTO.QUEST_GREETING()
  for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
    for _, id in ipairs(routeQuestsByTitle(GetActiveTitle(i))) do
      if C.IsOnQuest(id) and E.Ready(id) then SelectActiveQuest(i); return end
    end
  end
  for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
    -- 只是打開任務內容；真正接不接由 QUEST_DETAIL 用遊戲給的 ID 判斷，選到同名的別環也不會接錯
    for _, id in ipairs(routeQuestsByTitle(GetAvailableTitle(i))) do
      if inRoute(id, true) and wantAccept(id) and not E.Turned(id) and not C.IsOnQuest(id) then SelectAvailableQuest(i); return end
    end
  end
end

-- ── 事件 ────────────────────────────────────────────────────────────────────
local EVENTS = {
  "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE",
  "BAG_UPDATE_DELAYED", "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_GAINED", "PLAYER_CONTROL_LOST", "HEARTHSTONE_BOUND",
  "UNIT_SPELLCAST_SUCCEEDED", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "TAXIMAP_OPENED", "UI_INFO_MESSAGE", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING",
  "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED", "UPDATE_INVENTORY_DURABILITY",
}
for _, e in ipairs(EVENTS) do
  if (e == "UNIT_QUEST_LOG_CHANGED" or e == "UNIT_SPELLCAST_SUCCEEDED") and f.RegisterUnitEvent then registered[e] = pcall(f.RegisterUnitEvent, f, e, "player")
  else registered[e] = pcall(f.RegisterEvent, f, e) end
end

local function onEvent(_, event, ...)
  if event == "BAG_UPDATE_DELAYED" then
    local row = lastState and lastState.cur and lastState.steps[lastState.cur]
    if (row and row.s.q and (R.quests[row.s.q] or {}).riftTools)
      or (lastState and lastState.st and visitChecks[lastState.st.id]) then dirty = true end
    return
  end
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    MetroGuideCharDB = MetroGuideCharDB or {}
    for k, v in pairs(DEFAULTS) do
      if MetroGuideCharDB[k] == nil then MetroGuideCharDB[k] = type(v) == "table" and {} or v end
    end
    MG.db = MetroGuideCharDB
    MetroGuideDB = MetroGuideDB or {} -- 帳號共用：小地圖按鈕角度
    MetroGuideDB.angle = MetroGuideDB.angle or 200
    MG.SetLang(MetroGuideDB.lang) -- 介面語言（/slv lang，/reload 後生效）
    MG.try("語言", E.Localize)
    UI.InitDefaults()
    MG.try("介面", UI.Create)
    return
  end
  if not MG.db then return end
  -- 爐石回 X：施法成功後 60 秒內換了區域（傳送到了）才勾目前的「爐」步驟；看得出爐石綁在別的地方（zhTW 的綁點，或其他語言記下的 boundK，和 X 互不包含）就不勾
  if hearthAt and (event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS") then
    local cur = lastState and lastState.cur and lastState.steps[lastState.cur]
    local k, b = cur and (cur.s.bindK or cur.s.bind), MG.gameZh and C.Bind() or MG.db.boundK
    local other = k and b and b ~= "" and not (b:find(k, 1, true) or k:find(b, 1, true))
    if GetTime() - hearthAt <= 60 and not other then latchCurrent("hearth") end
    hearthAt = nil
  end
  -- 船／飛艇：目的地對得到鳥點（而且和出發地不同張地圖）→ 人到了那張地圖才勾，走路換到別區不算；對不到 → 照舊，換到別的地圖（離開碼頭那張）就勾
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
    local cur = lastState and lastState.cur and lastState.steps[lastState.cur]
    if cur and cur.s.t == "boat" and cur.s.ungoroExit ~= "ship" then
      local map = C.Position()
      local dest, dock = mapOf(cur.s.to), cur.s.map or mapOf(cur.s.from)
      if dest and map and dest ~= dock then
        if map == dest then MG.db.latch[cur.key] = true end
      elseif event == "ZONE_CHANGED_NEW_AREA" and (not cur.s.map or (map and map ~= cur.s.map)) then MG.db.latch[cur.key] = true end
    end
  end
  if event == "PLAYER_ENTERING_WORLD" then
    if not E.built then E.Build(); E.built = true end -- 每次登入建一次（換起點時 UI 會自己重建）
    N.Forget()
    started = started or GetTime()
    -- Questie 也開著：提醒一次它的任務怪圖示也會擠地圖（不動 Questie 的設定）
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if not MetroGuideDB.questieNoted and loaded and loaded("Questie") then
      MetroGuideDB.questieNoted = true
      MG.msg(L["Questie 的任務怪與目標圖示也會畫在地圖上；太擠可到 Questie 的地圖設定關閉。"])
    end
  elseif event == "QUEST_LOG_UPDATE" then
    ready = true
    logSeen = true
  elseif event == "QUEST_ACCEPTED" then
    local id = ...
    if select("#", ...) >= 2 then id = select(2, ...) end -- 舊式事件第一欄是日誌列號
    if plain(id) and autoQ[id] then autoQ[id].confirmed = true end
    local args = {}
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      args[i] = issecretvalue and issecretvalue(v) and "secret" or tostring(v)
    end
    trace.QUEST_ACCEPTED = table.concat(args, ", ")
    lastAccept = GetTime()
    wipe(MG.db.notNow) -- 接了任務：暫時接不到的重新看
  elseif event == "QUEST_REMOVED" then
    local id = ...
    if plain(id) and type(id) == "number" then releaseAutoSlot(id) end
  elseif event == "QUEST_TURNED_IN" then
    local id = ...
    if type(id) == "number" and not (issecretvalue and issecretvalue(id)) then
      releaseAutoSlot(id)
      E.session[id] = true
      wipe(MG.db.notNow) -- 交了任務：暫時接不到的重新看
      if next(MG.db.skip) then E.RecomputeSkip() end
      trace.QUEST_TURNED_IN = id .. L["，事件當下已標記完成："] .. tostring(C.IsTurnedIn(id))
    end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spell = ...
    if unit == "player" and not (issecretvalue and issecretvalue(spell)) and HEARTH_SPELL[spell] then hearthAt = GetTime() end
    return
  elseif event == "HEARTHSTONE_BOUND" then
    -- 綁爐石：本站哪一步的旅店（人在那步座標旁邊，或 GetBindLocation 對得上遊戲語言的地點名；目前這步是沒座標也沒地點名的綁爐石也算）就勾那步，不必是目前步驟。
    -- 記下綁的是哪間（boundK）：之後同一間的綁爐石步驟直接算過。本站對不到就找整條路線上人旁邊的旅店，都沒有＝綁在路線外，清掉；
    -- 讀不到位置時不動（綁點文字變了 E.Locate 會清，見 Engine 的 bindCheck）
    local map, x, y = C.Position()
    local b = C.Bind()
    local hit
    for i, step in ipairs(lastState and not lastState.instance and lastState.steps or {}) do
      local s, name = step.s, step.s.bindG or (MG.gameZh and (step.s.bindK or step.s.bind))
      if not hit and s.t == "bind" and ((s.x and map == s.map and x and (x - s.x) ^ 2 + (y - s.y) ^ 2 <= 25)
        or (b and b ~= "" and name and (b:find(name, 1, true) or name:find(b, 1, true))) or (i == lastState.cur and not s.x and not name)) then hit = step end
    end
    if hit then MG.db.latch[hit.key] = true end
    local inn = hit and hit.s
    for _, st in ipairs(not inn and x and R.stations or {}) do
      for _, s in ipairs(st.steps) do
        if not inn and s.t == "bind" and s.x and s.map == map and (x - s.x) ^ 2 + (y - s.y) ^ 2 <= 25 then inn = s end
      end
    end
    if inn then MG.db.boundK, MG.db.boundRaw = inn.bindK or inn.bind, false -- boundRaw＝false：下次重算記下這次的綁點文字
    elseif x then MG.db.boundK, MG.db.boundRaw = nil, nil end
  elseif event == "PLAYER_LEVEL_UP" then
    MG.db.sugHide = nil
    wipe(MG.db.notNow)
  elseif event == "UI_INFO_MESSAGE" then
    -- 跟飛行管理員說話就開了新鳥點（「發現新的飛行路線！」）：確定人就在目前這個鳥點才勾；認不出來留給打開飛行地圖時補勾
    local kind, text = ...
    if not MG.IsNewTaxiPath(kind, text) then return end
    local fp = lastState and lastState.cur and lastState.steps[lastState.cur].s
    if MG.AtFlightPoint(fp, C.Position()) then
      latchCurrent("fp")
      MG.db.fpNodes = MG.db.fpNodes or {}
      if fp.node then MG.db.fpNodes[fp.node] = true end
      if fp.nodeK then MG.db.fpNodes[fp.nodeK] = true end
    end
  elseif event == "TAXIMAP_OPENED" then
    -- 目前是「開鳥點」：人就在那個鳥點旁邊才勾（在別的城開飛行地圖不算；讀不到位置照舊勾）。那個鳥點已經在飛行地圖上的，下面會另外勾
    local fp, pm, px, py = lastState and lastState.cur and lastState.steps[lastState.cur].s, C.Position()
    if not (fp and fp.t == "fp" and fp.x and px) or (pm == fp.map and (px - fp.x) ^ 2 + (py - fp.y) ^ 2 <= 100) then latchCurrent("fp") end
    local name = UnitName("npc")
    if name and not (issecretvalue and issecretvalue(name)) then MG.db.fpSeen[name] = true end
    -- 飛行地圖列出所有開過的鳥點：對到路線的「開鳥點」步驟和飛行管理員，都記成開過。
    -- 先比位置（路線座標換算到飛行地圖上），再比名稱（步驟有寫鳥點名時）
    local known = {}
    local tm = GetTaxiMapID and GetTaxiMapID()
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and tm then
      for _, nd in ipairs(C_TaxiMap.GetAllTaxiNodes(tm) or {}) do
        local p = nd.position
        if nd.state ~= 2 and type(nd.name) == "string" and not (issecretvalue and issecretvalue(nd.name)) then known[#known + 1] = { name = nd.name, x = p and p.x, y = p and p.y } end
      end
    elseif NumTaxiNodes then
      for i = 1, NumTaxiNodes() do
        local kind = TaxiNodeGetType(i)
        local px, py = TaxiNodePosition(i)
        if kind == "CURRENT" or kind == "REACHABLE" then known[#known + 1] = { name = TaxiNodeName(i) or "", x = px, y = py } end
      end
    end
    local function onTaxiMap(m, px, py)
      if not (tm and C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
      local ok, cont, wp = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(px / 100, py / 100))
      if not (ok and wp) then return end
      local ok2, _, p = pcall(C_Map.GetMapPosFromWorldPos, cont, wp, tm)
      if ok2 and p then return p.x, p.y end
    end
    local function isKnown(m, px, py, node)
      local tx, ty = onTaxiMap(m, px, py)
      for _, k in ipairs(known) do
        if tx and k.x and (k.x - tx) ^ 2 + (k.y - ty) ^ 2 <= 0.0002 then return true end
        if node and k.name:find(node, 1, true) then return true end
      end
      return false
    end
    if #known > 0 then
      MG.db.fpNodes = MG.db.fpNodes or {}
      for _, st in ipairs(E.stations) do
        for _, step in ipairs(st.list) do
          local s = step.s
          if s.t == "fp" and s.x and isKnown(s.map, s.x, s.y, s.node) then
            MG.db.latch[step.key] = true
            if s.node then MG.db.fpNodes[s.node] = true end
            if s.nodeK then MG.db.fpNodes[s.nodeK] = true end -- 中文名：路線的「已開／未開鳥點」條件用
            for _, st2 in ipairs(E.stations) do -- 這個鳥點旁邊的飛行管理員
              for _, sp in ipairs(st2.supply or {}) do
                if sp.k == "飛行管理員" and sp.map == s.map and sp.x and (sp.x - s.x) ^ 2 + (sp.y - s.y) ^ 2 <= 9 then MG.db.fpSeen[sp.npcG or sp.npc] = true end
              end
            end
          end
        end
        for _, sp in ipairs(st.supply or {}) do
          local n = sp.npcG or sp.npc
          if sp.k == "飛行管理員" and n and sp.x and not MG.db.fpSeen[n] and isKnown(sp.map, sp.x, sp.y) then MG.db.fpSeen[n] = true end
        end
      end
    end
    -- 目前這步要飛的鳥點不在飛行地圖上（沒開過，或中間的鳥點沒開所以接不過去）：提醒先跑過去開
    local cur = lastState and lastState.cur and lastState.steps[lastState.cur]
    if #known > 0 and cur and cur.s.t == "fly" and cur.s.to then
      local dest
      for _, st in ipairs(E.stations) do
        for _, step in ipairs(st.list) do
          local s = step.s
          if not dest and s.t == "fp" and (s.nodeK or s.node) == cur.s.to and s.x then dest = s end
        end
      end
      if dest and not isKnown(dest.map, dest.x, dest.y, dest.node) then MG.msg(string.format(L["飛行地圖上沒有%s：還沒開過這個鳥點，或中間的鳥點沒開，要先跑過去開"], cur.s.toL or cur.s.to)) end
    end
    -- 名字可能和路線寫的不同（譯名、稱號）：人旁邊的飛行管理員也一律記成開過
    local map, x, y = C.Position()
    if map and x then
      for _, st in ipairs(E.stations) do
        for _, s in ipairs(st.supply or {}) do
          local n = s.npcG or s.npc
          if s.k == "飛行管理員" and n and s.map == map and s.x and (s.x - x) ^ 2 + (s.y - y) ^ 2 <= 4 then MG.db.fpSeen[n] = true end
        end
      end
    end
  elseif event == "PLAYER_CONTROL_LOST" then
    onTaxi = UnitOnTaxi and UnitOnTaxi("player") or false
    return
  elseif event == "PLAYER_CONTROL_GAINED" then
    if onTaxi then
      -- 目的地對得到鳥點時，降落在那個鳥點附近才勾（飛去別張地圖、同張地圖的另一個鳥點都不算）；對不到或讀不到位置照舊勾
      local cur = lastState and lastState.cur and lastState.steps[lastState.cur]
      local dest, dx, dy = mapOf(cur and cur.s.to)
      local map, x, y = C.Position()
      if cur and cur.s.ironReturn then
        local landing, lx, ly = mapOf(cur.s.to)
        if map == landing and lx and ly and x and y and (x - lx)^2 + (y - ly)^2 <= 2.25 then
          MG.db.latch[cur.key] = true
        end
      elseif cur and (cur.s.ungoroExit == "port" or cur.s.localTransfer) then
        if E.AtRutheranFlightMaster(map, x, y) then MG.db.latch[cur.key] = true end
      elseif not (dest and map) or (dest == map and not (dx and x and (x - dx) ^ 2 + (y - dy) ^ 2 > 100)) then
        latchCurrent("fly")
      end
      -- 下飛行：臨時航點收回，箭頭回到目前步驟
      MG.wpOverride = nil
      N.Forget()
    end
    onTaxi = false
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    N.Forget()
  elseif AUTO[event] then
    if event ~= "QUEST_PROGRESS" and event ~= "QUEST_COMPLETE" then MG.try("接不到檢查", notOffered, event); dirty = true end
    if autoOn() then MG.try("自動接交", AUTO[event]) end
    return
  end
  dirty = true
end
f:SetScript("OnEvent", function(...) MG.try(select(2, ...), onEvent, ...) end)

-- ── /slv probe ────────────────────────────────────────────────────────────
local function probe()
  local out = {}
  local function add(label, ...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring((select(i, ...)))
    end
    out[#out + 1] = L[label] .. " = " .. table.concat(parts, ", ")
  end
  local function try(label, fn)
    local res = (function(...) return { n = select("#", ...), ... } end)(pcall(fn))
    if res[1] then add(label, unpack(res, 2, res.n)) else out[#out + 1] = L[label] .. L[" = 錯誤："] .. tostring(res[2]) end
  end
  local QL = C_QuestLog or {}
  out[#out + 1] = L["== 阿聖練等幫手 probe "] .. (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "") .. L["｜路線 "] .. tostring(R.built) .. " =="
  try("locale, interface, build", function() local v, b, _, i = GetBuildInfo(); return GetLocale(), i, v, b end)
  add("ui locale, game locale, lang setting", MG.uiLoc, MG.gameLoc, MetroGuideDB.lang or "auto")
  out[#out + 1] = L["-- 相容層選用"]
  for k, v in pairs(C.impl) do out[#out + 1] = "  " .. k .. " → " .. L[v] end
  out[#out + 1] = L["  航點 → "] .. L[N.Method()]
  out[#out + 1] = L["-- 任務 API"]
  add("C_QuestLog.GetInfo/GetNumQuestLogEntries, GetQuestLogTitle/GetNumQuestLogEntries", QL.GetInfo ~= nil, QL.GetNumQuestLogEntries ~= nil, GetQuestLogTitle ~= nil, GetNumQuestLogEntries ~= nil)
  local log = C.LogQuestIDs() or {}
  add("日誌任務數, 前 5 個 ID", #log, table.concat({ log[1], log[2], log[3], log[4], log[5] }, " "))
  local qid = log[1]
  if qid then
    try("QID " .. qid .. " IsOnQuest, IsComplete, Title", function() return QL.IsOnQuest and QL.IsOnQuest(qid), QL.IsComplete and QL.IsComplete(qid), QL.GetTitleForQuestID and QL.GetTitleForQuestID(qid) end)
    try("SetSelectedQuest, GetQuestLogQuestText 存在", function() return QL.SetSelectedQuest ~= nil, GetQuestLogQuestText ~= nil end)
    try("任務文字（描述前 40 字 / 目標）", function() local d, o = C.QuestText(qid); return d and d:sub(1, 120), o end)
    local obj = C.Objectives(qid)
    if obj then for i, o in ipairs(obj) do out[#out + 1] = L["  目標 "] .. i .. " = " .. table.concat({ tostring(o.text), tostring(o.have), tostring(o.need), tostring(o.done) }, ", ") end else out[#out + 1] = L["  目標 = nil"] end
    if GetQuestLogTitle then try("GetQuestLogTitle(log index) 第 6 回傳", function() local i = C.LogIndex(qid); return i, i and select(6, GetQuestLogTitle(i)) end) end
  end
  local all = C.AllTurnedIn() or {}
  local n, anyDone = 0, nil
  for id in pairs(all) do n = n + 1; anyDone = anyDone or id end
  out[#out + 1] = L["已完成任務數（%s）"]:format(L[C.impl.AllTurnedIn]) .. " = " .. n -- 已翻好，不再過 add 的 L[]
  if anyDone then try("DONE " .. anyDone .. " IsQuestFlaggedCompleted(C_), 全域存在", function() return QL.IsQuestFlaggedCompleted and QL.IsQuestFlaggedCompleted(anyDone), IsQuestFlaggedCompleted ~= nil end) end
  add("GetQuestDifficultyLevel, GetTrivialRange, GetMaxNumQuestsCanAccept, GetQuestGreenRange", QL.GetQuestDifficultyLevel ~= nil, QL.GetTrivialRange ~= nil, QL.GetMaxNumQuestsCanAccept ~= nil, GetQuestGreenRange ~= nil)
  add("綠色範圍", C.GreenRange())
  out[#out + 1] = L["-- 地圖／航點"]
  try("BestMap, x, y", function() return C.Position() end)
  try("CanSetUserWaypointOnMap, SetSuperTrackedUserWaypoint, HasUserWaypoint", function() local m = C_Map.GetBestMapForUnit("player"); return m and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(m), C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint ~= nil, C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() end)
  try("WaypointUIAPI, 目前航點是我們的", function() local api = WaypointUIAPI and WaypointUIAPI.Navigation; return api ~= nil and api.NewUserNavigation ~= nil, api and api.IsUserNavigationFlagged and api.IsUserNavigationFlagged("MetroGuide") end)
  try("C_SuperTrack.IsSuperTrackingAnything", function() return C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything and C_SuperTrack.IsSuperTrackingAnything() end)
  out[#out + 1] = L["-- 角色／交通／函式庫"]
  try("UnitRace 第 3 回傳 raceID, 起點", function() return select(3, UnitRace("player")), E.StartKey(), MG.db.start end)
  try("UnitRace, UnitClass, UnitLevel, GetBindLocation", function() local r1, r2 = UnitRace("player"); local c1, c2 = UnitClass("player"); return r1, r2, c1, c2, UnitLevel("player"), C.Bind() end)
  try("QuestDB, NpcDB, HBD, HBD-Pins", function() return type(QuestDB), type(NpcDB), LibStub and LibStub("HereBeDragons-2.0", true) ~= nil, LibStub and LibStub("HereBeDragons-Pins-2.0", true) ~= nil end)
  try("WorldMapFrame.AddDataProvider, C_TaxiMap, UnitOnTaxi", function() return WorldMapFrame and WorldMapFrame.AddDataProvider ~= nil, C_TaxiMap ~= nil, UnitOnTaxi ~= nil end)
  out[#out + 1] = L["-- 任務日誌框"]
  try("QuestLogFrame, QuestMapFrame, QuestScrollFrame", function() return QuestLogFrame ~= nil, QuestMapFrame ~= nil, QuestScrollFrame ~= nil end)
  try("QuestMapLogTitleButton_OnEnter, QuestLogTitleButton_OnEnter, QuestLogTitle1", function() return QuestMapLogTitleButton_OnEnter ~= nil, QuestLogTitleButton_OnEnter ~= nil, QuestLogTitle1 ~= nil end)
  try("TooltipDataProcessor, Enum.TooltipDataType.Quest", function() return TooltipDataProcessor ~= nil, Enum and Enum.TooltipDataType and Enum.TooltipDataType.Quest end)
  try("GetQuestID, GetQuestLogIndexByID, C_GossipInfo, GetNumQuestChoices", function() return GetQuestID ~= nil, GetQuestLogIndexByID ~= nil, C_GossipInfo ~= nil, GetNumQuestChoices ~= nil end)
  out[#out + 1] = L["-- 事件註冊（false 的要拿掉）"]
  local bad = {}
  for _, e in ipairs(EVENTS) do if not registered[e] then bad[#bad + 1] = e end end
  out[#out + 1] = L["  失敗："] .. (#bad > 0 and table.concat(bad, " ") or L["無"])
  out[#out + 1] = L["  QUEST_ACCEPTED 參數："] .. (trace.QUEST_ACCEPTED or L["（本次登入尚未接任務）"])
  out[#out + 1] = L["  QUEST_TURNED_IN："] .. (trace.QUEST_TURNED_IN or L["（本次登入尚未交任務）"])
  out[#out + 1] = L["-- 引擎"]
  add("適用的站數 / 路線總站數", #E.stations, #R.stations)
  local ratio, n = MG.Rec.XPRatio()
  local buff = C.XPBuff()
  add("任務經驗 實得/路線（中位數, 筆數，只診斷）, 已知經驗增益", ratio and string.format("%.3f", ratio), n, buff and ((buff.name or "?") .. " " .. tostring(buff.id) .. L["（依%s）"]:format(L[buff.how])) or L["無"])
  local auras = {}
  for _, a in ipairs(C.Auras()) do auras[#auras + 1] = (a.name or "?") .. " " .. tostring(a.id or "?") end
  out[#out + 1] = L["  身上的增益："] .. (#auras > 0 and table.concat(auras, " | ") or L["無"])
  local off = 0
  for _ in pairs(R.offroute or {}) do off = off + 1 end
  add("路線外判定", off)
  local st = lastState and lastState.st
  if st then
    local s = lastState.cur and lastState.steps[lastState.cur]
    add("目前站, 地圖, 進度", st.id .. " " .. st.name, st.map, (function() local g, t = E.Progress(st); return g .. "/" .. t end)())
    add("目前步驟, 自動位置, 漏掉", s and (s.key .. " " .. E.Title(s.s)) or L["本站完成"], tostring(lastState.auto), #lastState.missed)
  else
    out[#out + 1] = L["  沒有目前站"]
  end
  add("地圖標點 世界地圖, 小地圖, HBD-Pins", MG.P.count and MG.P.count.world, MG.P.count and MG.P.count.minimap, LibStub and LibStub("HereBeDragons-Pins-2.0", true) ~= nil)
  out[#out + 1] = L["-- 任務目標巨集／按鈕"]
  for _, line in ipairs(MG.try("目標診斷", MG.T.Diag) or {}) do out[#out + 1] = "  " .. line end
  out[#out + 1] = L["-- 任務物品"]
  for _, line in ipairs(MG.try("物品診斷", MG.I.Diag) or {}) do out[#out + 1] = "  " .. line end
  out[#out + 1] = L["-- 地圖標點（請先打開世界地圖再打 /slv probe）"]
  for _, line in ipairs(MG.try("地圖診斷", MG.P.Diag) or {}) do out[#out + 1] = "  " .. line end
  if not MG.uiZh then
    -- 非中文介面：漏網的中文字串（顯示時已拿掉）和缺的翻譯
    local leaks, miss = {}, {}
    for s in pairs(MG.leaks) do leaks[#leaks + 1] = s end
    for k in pairs(MG.missingL) do miss[#miss + 1] = k end
    out[#out + 1] = "-- CJK leaks (" .. #leaks .. ") / missing translations (" .. #miss .. ")"
    -- 中文字改寫成位元組跳脫（報告整份會過 MG.Clean，英文客戶端也顯示不了中文）
    for _, s in ipairs(leaks) do out[#out + 1] = "  leak: " .. s:gsub("[\128-\255]", function(c) return "\\" .. c:byte() end) end
    for _, s in ipairs(miss) do out[#out + 1] = "  missing: " .. s:gsub("[\128-\255]", function(c) return "\\" .. c:byte() end) end
  end
  do
    local inside, kind
    if IsInInstance then inside, kind = IsInInstance() end
    local iid = GetInstanceInfo and select(8, GetInstanceInfo())
    local d = E.DungeonByInstance(iid)
    local pd, miss = E.DungeonPrompt()
    add("副本 數量, 在副本, 類型, instanceID, 對到", #E.dungeons, inside, kind, iid, d and d.name or L["無"])
    add("副本提示", pd and (pd.name .. (miss and ("  " .. miss) or "")) or L["無"])
  end
  local fi = lastState and lastState.fillInfo
  if fi then
    local names = {}
    for _, q in ipairs(fi.added) do names[#names + 1] = q .. " " .. ((R.quests[q] and R.quests[q].n) or "") end
    add("經驗 任務, 打怪, 休息加成, 合計, 需要", math.floor(fi.questXP), math.floor(fi.killXP), math.floor(fi.rested), math.floor(fi.projected), math.floor(fi.need))
    add("補經驗 補回", #names > 0 and table.concat(names, L["、"]) or L["無"])
  end
  add("設定 箭頭, 自動接交, 帶上可跳過, 鎖定, 縮放, 寬度, 小地圖按鈕", UI.Get("arrow"), UI.Get("auto"), UI.Get("optional"), UI.Get("locked"), UI.Get("barScale"), UI.Get("barWidth"), UI.Get("minimap"))
  add("提示框 大小, 水平, 垂直；滑桿", UI.Get("tipScale"), UI.Get("tipX"), UI.Get("tipY"), C.impl.Slider)
  UI.ShowReport(MG.Clean(table.concat(out, "\n")))
end

SLASH_METROGUIDE1 = "/slv"
SLASH_METROGUIDE2 = "/lv" -- 舊指令保留
SLASH_METROGUIDE3 = "/metro"
SlashCmdList.METROGUIDE = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not MG.db then return end
  if msg == "probe" then MG.try("probe", probe)
  elseif msg == "realign" or msg == "reset" then E.Realign(); MG.Refresh(true) -- reset 是舊名
  elseif msg == "config" then UI.OpenOptions()
  elseif msg == "macro" then MG.try("目標巨集", MG.T.MakeMacro)
  elseif msg == "minimap" then UI.Set("minimap", true); UI.ApplySettings()
  elseif msg:match("^lang") then
    -- 介面語言預覽：語言代碼（MG.LANGS）／auto（跟客戶端）／stress（英文加長約 35%，檢查版面）。選目標、比對遊戲文字仍跟客戶端語言
    local v = msg:match("^lang%s+(%a+)")
    if v == "auto" or v == "stress" or MG.LANGS[v] then
      MetroGuideDB.lang = v ~= "auto" and v or nil
      MG.msg(L["介面語言設為 %s，/reload 後生效"]:format(v))
    else
      MG.msg(L["介面語言：%s（/slv lang auto｜en｜zh｜zhCN｜deDE｜frFR｜esES｜esMX｜ruRU｜koKR｜ptBR，/reload 後生效）"]:format(MetroGuideDB.lang or "auto"))
    end
  elseif msg:sub(1, 3) == "rec" then MG.Rec.Slash(msg:sub(4))
  elseif msg == "" then UI.Toggle()
  else
    MG.msg(L["/slv 開關｜config 設定｜realign 重新對齊｜probe 檢查報告"])
    MG.msg(L["/slv macro 目標巨集｜minimap 小地圖按鈕｜rec 遊戲內記錄｜lang 介面語言"])
  end
end
