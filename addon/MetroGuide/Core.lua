-- 事件、節流重算、slash、自動接交任務、/metro probe。
local ADDON, MG = ...
local E, C, N, UI = MG.E, MG.C, MG.N, MG.UI
local R = MG.Route or { stations = {}, quests = {} }

local DEFAULTS = { dNo = {}, dDismiss = {}, mark = {}, pin = {}, skip = {}, latch = {}, drop = {}, carry = {}, shown = true } -- 其餘設定的預設在 UI.lua 的設定表
local f = CreateFrame("Frame")
local registered = {} -- 事件 → 是否註冊成功（probe 用）
local trace = {} -- 事件參數紀錄（probe 用）
local dirty, ready, since, tick, started = false, false, 0, 0, nil
local lastState

-- ── 重算 ────────────────────────────────────────────────────────────────────
-- 副本裡：只列這個副本的任務（一次全列），不顯示主線、箭頭、地圖標點；對不到就整個隱藏。出副本後回主線並重新對齊。
local inInstance, enterLevel = false, nil
local function instanceView()
  if not (IsInInstance and GetInstanceInfo) then return false end
  local inside, kind = IsInInstance()
  if not (inside and (kind == "party" or kind == "raid") and UI.Get("dungeonOnly")) then return false end
  if not inInstance then inInstance, enterLevel = true, UnitLevel("player") end
  local id = select(8, GetInstanceInfo())
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
  return true
end

local function refresh()
  if instanceView() then return end
  if inInstance then
    -- 剛出副本：在跑副本流程或升級了 → 重新對齊主線（等級超過時會出現跳站建議）
    inInstance = false
    UI.SetHidden(false)
    local cur = MG.db.station and E.byId[MG.db.station]
    if (cur and cur.dungeon) or (UnitLevel("player") or 0) > (enterLevel or 99) then
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
    MG.db.station = nil
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
  lastState = state
  local nextSt = st and E.Next(st)
  UI.Render({ state = state, sug = E.Suggest(st), nextSt = nextSt })
  MG.try("地圖標點", MG.P.Update, state)
  MG.try("目標按鈕", MG.T.Update, state)
  -- 箭頭：目前步驟的座標；本站完成時指向下一站第一個有座標的步驟
  local s = state and state.cur and state.steps[state.cur].s
  if state and not state.cur and nextSt then
    for _, step in ipairs(nextSt.list) do
      if step.s.x and E.Applies(step.s.when) then s = step.s; break end
    end
  end
  if s and s.x then N.Set(s.map, s.x, s.y, E.Title(s)) else N.Clear() end
end

function MG.Refresh(now)
  if now then
    dirty = false
    if ready and started then MG.try("重算", refresh) end
  else
    dirty = true
  end
end

f:SetScript("OnUpdate", function(_, dt)
  since = since + dt
  tick = tick + dt
  if not ready and started and GetTime() - started > 3 then ready = true; dirty = true end -- 等不到 QUEST_LOG_UPDATE 也開始
  if dirty and since >= 0.1 then
    since = 0
    MG.Refresh(true)
  end
  -- 到達型步驟：每 0.5 秒檢查一次
  if tick >= 0.5 then
    tick = 0
    local cur = lastState and lastState.cur and lastState.steps[lastState.cur].s
    if cur and cur.t == "goto" then dirty = true end
  end
end)

-- 目前步驟是某類型時記一筆（到達、開鳥點、下飛行、換區搭船）
local function latchCurrent(t)
  local cur = lastState and lastState.cur and lastState.steps[lastState.cur]
  if cur and cur.s.t == t then MG.db.latch[cur.key] = true end
end

-- ── 自動接交任務（設定預設開；按住 Shift 暫停） ─────────────────────────────
local nameToQuest
local function routeQuestByTitle(title)
  if not nameToQuest then
    nameToQuest = {}
    for id, q in pairs(R.quests) do if q.n then nameToQuest[q.n] = id end end
  end
  return title and nameToQuest[title]
end
local function autoOn() return UI.Get("auto") and not IsShiftKeyDown() end
local optQ = {} -- 接任務那步標了「可跳過」的任務
for _, st in ipairs(R.stations) do
  for _, s in ipairs(st.steps) do if s.t == "accept" and s.opt then optQ[s.q] = true end end
end
-- 路線上的任務；可跳過的只在設定開啟或已在日誌時算
local function inRoute(id)
  return id and id > 0 and R.quests[id] ~= nil and not (optQ[id] and not UI.Get("optional") and not C.IsOnQuest(id))
end

local AUTO = {}
function AUTO.QUEST_DETAIL()
  local id = GetQuestID and GetQuestID()
  if inRoute(id) then AcceptQuest() end
end
function AUTO.QUEST_PROGRESS()
  local id = GetQuestID and GetQuestID()
  if inRoute(id) and IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
end
function AUTO.QUEST_COMPLETE()
  local id = GetQuestID and GetQuestID()
  if not inRoute(id) then return end
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n <= 1 then GetQuestReward(n) else MG.msg("有 " .. n .. " 個獎勵可選，請自己挑") end
end
function AUTO.GOSSIP_SHOW()
  local G = C_GossipInfo
  if not G then return end
  for _, q in ipairs(G.GetActiveQuests and G.GetActiveQuests() or {}) do
    if q.isComplete and inRoute(q.questID) then G.SelectActiveQuest(q.questID); return end
  end
  for _, q in ipairs(G.GetAvailableQuests and G.GetAvailableQuests() or {}) do
    if inRoute(q.questID) then G.SelectAvailableQuest(q.questID); return end
  end
end
function AUTO.QUEST_GREETING()
  for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
    local id = routeQuestByTitle(GetActiveTitle(i))
    if id and C.IsOnQuest(id) and E.Ready(id) then SelectActiveQuest(i); return end
  end
  for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
    local id = routeQuestByTitle(GetAvailableTitle(i))
    if id and not E.Turned(id) then SelectAvailableQuest(i); return end
  end
end

-- ── 事件 ────────────────────────────────────────────────────────────────────
local EVENTS = {
  "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE",
  "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_GAINED", "HEARTHSTONE_BOUND",
  "TAXIMAP_OPENED", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING",
  "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED",
}
for _, e in ipairs(EVENTS) do registered[e] = pcall(f.RegisterEvent, f, e) end

local function onEvent(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    MetroGuideCharDB = MetroGuideCharDB or {}
    for k, v in pairs(DEFAULTS) do
      if MetroGuideCharDB[k] == nil then MetroGuideCharDB[k] = type(v) == "table" and {} or v end
    end
    MG.db = MetroGuideCharDB
    MetroGuideDB = MetroGuideDB or {} -- 帳號共用：小地圖按鈕角度
    MetroGuideDB.angle = MetroGuideDB.angle or 200
    UI.InitDefaults()
    MG.try("介面", UI.Create)
    return
  end
  if not MG.db then return end
  if event == "PLAYER_ENTERING_WORLD" then
    E.Build()
    N.Forget()
    started = started or GetTime()
  elseif event == "QUEST_LOG_UPDATE" then
    ready = true
  elseif event == "QUEST_ACCEPTED" then
    local args = {}
    for i = 1, select("#", ...) do args[i] = tostring((select(i, ...))) end
    trace.QUEST_ACCEPTED = table.concat(args, ", ")
  elseif event == "QUEST_TURNED_IN" then
    local id = ...
    if type(id) == "number" then
      E.session[id] = true
      trace.QUEST_TURNED_IN = id .. "，事件當下已標記完成：" .. tostring(C.IsTurnedIn(id))
    end
  elseif event == "PLAYER_LEVEL_UP" then
    MG.db.sugHide = nil
  elseif event == "TAXIMAP_OPENED" then latchCurrent("fp"); latchCurrent("travel")
  elseif event == "PLAYER_CONTROL_GAINED" then latchCurrent("fly")
  elseif event == "ZONE_CHANGED_NEW_AREA" then latchCurrent("boat"); N.Forget()
  elseif AUTO[event] then
    if autoOn() then MG.try("自動接交", AUTO[event]) end
    return
  end
  dirty = true
end
f:SetScript("OnEvent", function(...) MG.try(select(2, ...), onEvent, ...) end)

-- ── /metro probe ────────────────────────────────────────────────────────────
local function probe()
  local L = {}
  local function add(label, ...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring((select(i, ...)))
    end
    L[#L + 1] = label .. " = " .. table.concat(parts, ", ")
  end
  local function try(label, fn)
    local res = (function(...) return { n = select("#", ...), ... } end)(pcall(fn))
    if res[1] then add(label, unpack(res, 2, res.n)) else L[#L + 1] = label .. " = 錯誤：" .. tostring(res[2]) end
  end
  local QL = C_QuestLog or {}
  L[#L + 1] = "== 地鐵升級 probe " .. (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "") .. "｜路線 " .. tostring(R.built) .. " =="
  try("locale, interface, build", function() local v, b, _, i = GetBuildInfo(); return GetLocale(), i, v, b end)
  L[#L + 1] = "-- 相容層選用"
  for k, v in pairs(C.impl) do L[#L + 1] = "  " .. k .. " → " .. v end
  L[#L + 1] = "  航點 → " .. N.Method()
  L[#L + 1] = "-- 任務 API"
  add("C_QuestLog.GetInfo/GetNumQuestLogEntries, GetQuestLogTitle/GetNumQuestLogEntries", QL.GetInfo ~= nil, QL.GetNumQuestLogEntries ~= nil, GetQuestLogTitle ~= nil, GetNumQuestLogEntries ~= nil)
  local log = C.LogQuestIDs() or {}
  add("日誌任務數, 前 5 個 ID", #log, table.concat({ log[1], log[2], log[3], log[4], log[5] }, " "))
  local qid = log[1]
  if qid then
    try("QID " .. qid .. " IsOnQuest, IsComplete, Title", function() return QL.IsOnQuest and QL.IsOnQuest(qid), QL.IsComplete and QL.IsComplete(qid), QL.GetTitleForQuestID and QL.GetTitleForQuestID(qid) end)
    try("SetSelectedQuest, GetQuestLogQuestText 存在", function() return QL.SetSelectedQuest ~= nil, GetQuestLogQuestText ~= nil end)
    try("任務文字（描述前 40 字 / 目標）", function() local d, o = C.QuestText(qid); return d and d:sub(1, 120), o end)
    local obj = C.Objectives(qid)
    if obj then for i, o in ipairs(obj) do add("  目標 " .. i, o.text, o.have, o.need, o.done) end else L[#L + 1] = "  目標 = nil" end
    if GetQuestLogTitle then try("GetQuestLogTitle(log index) 第 6 回傳", function() local i = C.LogIndex(qid); return i, i and select(6, GetQuestLogTitle(i)) end) end
  end
  local all = C.AllTurnedIn() or {}
  local n, anyDone = 0, nil
  for id in pairs(all) do n = n + 1; anyDone = anyDone or id end
  add("已完成任務數（" .. C.impl.AllTurnedIn .. "）", n)
  if anyDone then try("DONE " .. anyDone .. " IsQuestFlaggedCompleted(C_), 全域存在", function() return QL.IsQuestFlaggedCompleted and QL.IsQuestFlaggedCompleted(anyDone), IsQuestFlaggedCompleted ~= nil end) end
  add("GetQuestDifficultyLevel, GetTrivialRange, GetMaxNumQuestsCanAccept, GetQuestGreenRange", QL.GetQuestDifficultyLevel ~= nil, QL.GetTrivialRange ~= nil, QL.GetMaxNumQuestsCanAccept ~= nil, GetQuestGreenRange ~= nil)
  add("綠色範圍", C.GreenRange())
  L[#L + 1] = "-- 地圖／航點"
  try("BestMap, x, y", function() return C.Position() end)
  try("CanSetUserWaypointOnMap, SetSuperTrackedUserWaypoint, HasUserWaypoint", function() local m = C_Map.GetBestMapForUnit("player"); return C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(m), C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint ~= nil, C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() end)
  try("WaypointUIAPI, 目前航點是我們的", function() local api = WaypointUIAPI and WaypointUIAPI.Navigation; return api ~= nil and api.NewUserNavigation ~= nil, api and api.IsUserNavigationFlagged and api.IsUserNavigationFlagged("MetroGuide") end)
  try("C_SuperTrack.IsSuperTrackingAnything", function() return C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything and C_SuperTrack.IsSuperTrackingAnything() end)
  L[#L + 1] = "-- 角色／交通／函式庫"
  try("UnitRace 第 3 回傳 raceID, 起點", function() return select(3, UnitRace("player")), E.StartKey(), MG.db.start end)
  try("UnitRace, UnitClass, UnitLevel, GetBindLocation", function() local r1, r2 = UnitRace("player"); local c1, c2 = UnitClass("player"); return r1, r2, c1, c2, UnitLevel("player"), C.Bind() end)
  try("QuestDB, NpcDB, HBD, HBD-Pins", function() return type(QuestDB), type(NpcDB), LibStub and LibStub("HereBeDragons-2.0", true) ~= nil, LibStub and LibStub("HereBeDragons-Pins-2.0", true) ~= nil end)
  try("WorldMapFrame.AddDataProvider, C_TaxiMap, UnitOnTaxi", function() return WorldMapFrame and WorldMapFrame.AddDataProvider ~= nil, C_TaxiMap ~= nil, UnitOnTaxi ~= nil end)
  L[#L + 1] = "-- 任務日誌框"
  try("QuestLogFrame, QuestMapFrame, QuestScrollFrame", function() return QuestLogFrame ~= nil, QuestMapFrame ~= nil, QuestScrollFrame ~= nil end)
  try("QuestMapLogTitleButton_OnEnter, QuestLogTitleButton_OnEnter, QuestLogTitle1", function() return QuestMapLogTitleButton_OnEnter ~= nil, QuestLogTitleButton_OnEnter ~= nil, QuestLogTitle1 ~= nil end)
  try("TooltipDataProcessor, Enum.TooltipDataType.Quest", function() return TooltipDataProcessor ~= nil, Enum and Enum.TooltipDataType and Enum.TooltipDataType.Quest end)
  try("GetQuestID, GetQuestLogIndexByID, C_GossipInfo, GetNumQuestChoices", function() return GetQuestID ~= nil, GetQuestLogIndexByID ~= nil, C_GossipInfo ~= nil, GetNumQuestChoices ~= nil end)
  L[#L + 1] = "-- 事件註冊（false 的要拿掉）"
  local bad = {}
  for _, e in ipairs(EVENTS) do if not registered[e] then bad[#bad + 1] = e end end
  L[#L + 1] = "  失敗：" .. (#bad > 0 and table.concat(bad, " ") or "無")
  L[#L + 1] = "  QUEST_ACCEPTED 參數：" .. (trace.QUEST_ACCEPTED or "（本次登入尚未接任務）")
  L[#L + 1] = "  QUEST_TURNED_IN：" .. (trace.QUEST_TURNED_IN or "（本次登入尚未交任務）")
  L[#L + 1] = "-- 引擎"
  add("適用的站數 / 路線總站數", #E.stations, #R.stations)
  local st = lastState and lastState.st
  if st then
    local s = lastState.cur and lastState.steps[lastState.cur]
    add("目前站, 地圖, 進度", st.id .. " " .. st.name, st.map, (function() local g, t = E.Progress(st); return g .. "/" .. t end)())
    add("目前步驟, 自動位置, 漏掉", s and (s.key .. " " .. E.Title(s.s)) or "本站完成", tostring(lastState.auto), #lastState.missed)
  else
    L[#L + 1] = "  沒有目前站"
  end
  add("地圖標點 世界地圖, 小地圖, HBD-Pins", MG.P.count and MG.P.count.world, MG.P.count and MG.P.count.minimap, LibStub and LibStub("HereBeDragons-Pins-2.0", true) ~= nil)
  L[#L + 1] = "-- 任務目標巨集／按鈕"
  for _, line in ipairs(MG.try("目標診斷", MG.T.Diag) or {}) do L[#L + 1] = "  " .. line end
  L[#L + 1] = "-- 地圖標點（請先打開世界地圖再打 /metro probe）"
  for _, line in ipairs(MG.try("地圖診斷", MG.P.Diag) or {}) do L[#L + 1] = "  " .. line end
  do
    local inside, kind
    if IsInInstance then inside, kind = IsInInstance() end
    local iid = GetInstanceInfo and select(8, GetInstanceInfo())
    local d = E.DungeonByInstance(iid)
    local pd, miss = E.DungeonPrompt()
    add("副本 數量, 在副本, 類型, instanceID, 對到", #E.dungeons, inside, kind, iid, d and d.name or "無")
    add("副本提示", pd and (pd.name .. (miss and ("  " .. miss) or "")) or "無")
  end
  local fi = lastState and lastState.fillInfo
  if fi then
    local names = {}
    for _, q in ipairs(fi.added) do names[#names + 1] = q .. " " .. ((R.quests[q] and R.quests[q].n) or "") end
    add("經驗 任務, 打怪, 休息加成, 合計, 需要", math.floor(fi.questXP), math.floor(fi.killXP), math.floor(fi.rested), math.floor(fi.projected), math.floor(fi.need))
    add("補經驗 補回", #names > 0 and table.concat(names, "、") or "無")
  end
  add("設定 箭頭, 自動接交, 帶上可跳過, 鎖定, 縮放, 寬度, 小地圖按鈕", UI.Get("arrow"), UI.Get("auto"), UI.Get("optional"), UI.Get("locked"), UI.Get("barScale"), UI.Get("barWidth"), UI.Get("minimap"))
  add("提示框 大小, 水平, 垂直；滑桿", UI.Get("tipScale"), UI.Get("tipX"), UI.Get("tipY"), C.impl.Slider)
  UI.ShowReport(table.concat(L, "\n"))
end

SLASH_METROGUIDE1 = "/metro"
SlashCmdList.METROGUIDE = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not MG.db then return end
  if msg == "probe" then MG.try("probe", probe)
  elseif msg == "reset" then E.Realign(); MG.Refresh(true)
  elseif msg == "config" then UI.OpenOptions()
  elseif msg == "macro" then MG.try("目標巨集", MG.T.MakeMacro)
  elseif msg == "minimap" then UI.Set("minimap", true); UI.ApplySettings()
  elseif msg == "" then UI.Toggle()
  else MG.msg("/metro 開關｜/metro probe 檢查報告｜/metro reset 重新對齊｜/metro config 設定｜/metro macro 建立目標巨集｜/metro minimap 顯示小地圖按鈕") end
end
