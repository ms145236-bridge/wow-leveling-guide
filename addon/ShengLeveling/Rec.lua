-- 遊戲內記錄：任務接交 NPC 與座標、目標進度位置、真實經驗表、飛行點、爐石、副本、事件參數。
-- 存 MetroGuideRecDB（帳號共用）。每筆一行：鍵欄位 \t@\t 時間 \t 等級 \t 其他欄位。同鍵只記一次；最多 MAX 筆，滿了丟最舊的。
-- 不讀秘密值：UnitGUID/UnitName 是秘密值就整欄留空。離線用 tools/import-rec.mjs 讀。
local _, MG = ...
local C, UI = MG.C, MG.UI
local Rec = {}
MG.Rec = Rec

local MAX = 5000
local SEP = "\t@\t"
local db, seen = nil, {}
local prev = {} -- 任務 → 各目標上次進度
local objPending = false
local npcCache = {} -- 任務 → 對話框當下的 NPC（接受／交件事件時 NPC 視窗可能已關）

local function on() return UI.Get("rec") end
local function secret(v) return issecretvalue and issecretvalue(v) end
local function field(v)
  if v == nil or secret(v) then return "" end
  return (tostring(v):gsub("[\t\r\n]", " "))
end
local function num(v) return v and string.format("%.2f", v) or "" end
local function pos()
  local map, x, y = C.Position()
  return field(map), num(x), num(y)
end
local function npc()
  local guid, name = UnitGUID and UnitGUID("npc"), UnitName and UnitName("npc")
  if secret(guid) then guid = nil end
  local kind, id
  if guid then kind, id = tostring(guid):match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)") end
  return { name = field(name), id = id or "", kind = kind or "" }
end

-- keys：決定「同一筆」的欄位；其餘參數照存。欄位可能是 nil，用 maxn／select 數，不能用 ipairs。
local function add(kind, keys, ...)
  local k = { kind }
  for i = 1, table.maxn(keys) do k[i + 1] = field(keys[i]) end
  local key = table.concat(k, "\t")
  if seen[key] then return end
  local rest = { time(), UnitLevel("player") }
  for i = 1, select("#", ...) do rest[i + 2] = field((select(i, ...))) end
  local log = db.log
  log[#log + 1] = key .. SEP .. table.concat(rest, "\t")
  seen[key] = true
  while #log > MAX do
    local old = table.remove(log, 1)
    local s = old:find(SEP, 1, true)
    if s then seen[old:sub(1, s - 1)] = nil end
  end
end

-- 事件參數形狀（每種事件、每種型別組合記一次，順便留一組實際值）
local function shape(event, ...)
  local types, vals = {}, {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    types[i] = secret(v) and "secret" or type(v)
    vals[i] = secret(v) and "secret" or tostring(v)
  end
  add("args", { event, table.concat(types, ",") }, table.concat(vals, ","))
end

local function quest(kind, id, title, who)
  if not id or id == 0 then return end
  who = who or npc()
  local map, x, y = pos()
  add(kind, { id, who.id ~= "" and who.id or who.name }, title or C.Title(id), who.name, who.kind, map, x, y)
  return who
end

local function objAdvance(id, i, have, need, text)
  local map, x, y = pos()
  add("obj", { id, i, have, map, x ~= "" and math.floor(tonumber(x)) or "", y ~= "" and math.floor(tonumber(y)) or "" }, need, text, x, y)
end
-- 每個任務第一次讀到時只記基準（不算推進），之後數量變多就記一筆
local function objectives()
  for _, id in ipairs(C.LogQuestIDs() or {}) do
    local list = C.Objectives(id) or {}
    local was = prev[id]
    prev[id] = {}
    for i, o in ipairs(list) do
      local have = not secret(o.have) and o.have or nil
      prev[id][i] = have
      if was and was[i] and have and have > was[i] then objAdvance(id, i, have, o.need, o.text) end
    end
  end
end
-- 畫面上方的「怪名已殺死：3/10」：用文字對回日誌裡的任務目標
local function infoMessage(msg)
  if type(msg) ~= "string" or secret(msg) then return end
  local text, have, need = msg:match("^(.-)%s*:%s*(%d+)%s*/%s*(%d+)")
  if not text or text == "" then
    -- 中文冒號是多位元組，Lua 5.1 的字元集吃不下：再用純文字找一次
    local cut = msg:find("：", 1, true)
    if not cut then return end
    text = msg:sub(1, cut - 1)
    have, need = msg:sub(cut + 3):match("(%d+)%s*/%s*(%d+)")
    if not have then return end
  end
  for _, id in ipairs(C.LogQuestIDs() or {}) do
    for i, o in ipairs(C.Objectives(id) or {}) do
      if o.text and o.text ~= "" and (o.text == text or text:find(o.text, 1, true) or o.text:find(text, 1, true)) then
        objAdvance(id, i, tonumber(have), tonumber(need), o.text)
        return
      end
    end
  end
end

local function taxi()
  local who = npc()
  local map, x, y = pos()
  add("fp", { who.id ~= "" and who.id or who.name }, who.name, map, x, y)
  local tm = GetTaxiMapID and GetTaxiMapID()
  if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and tm then
    for _, n in ipairs(C_TaxiMap.GetAllTaxiNodes(tm) or {}) do
      local p = n.position
      local name = not secret(n.name) and n.name or ""
      if not name:find("^zzOLD") then add("taxi", { tm, n.nodeID, name, n.state }, p and num(p.x * 100), p and num(p.y * 100)) end
    end
  elseif NumTaxiNodes then
    for i = 1, NumTaxiNodes() do
      local px, py = TaxiNodePosition(i)
      local name = TaxiNodeName(i) or ""
      if not name:find("^zzOLD") then add("taxi", { tm or "", i, name, TaxiNodeGetType(i) }, num(px and px * 100), num(py and py * 100)) end
    end
  end
end

local function bind(src)
  local name = GetBindLocation and GetBindLocation()
  if not name then return end
  local map, x, y = "", "", ""
  if src == "bound" then map, x, y = pos() end
  add("bind", { name, src }, map, x, y)
end

local function instance()
  if not (IsInInstance and GetInstanceInfo) or not IsInInstance() then return end
  local name, kind, diff, _, _, _, _, id = GetInstanceInfo()
  add("inst", { id }, name, kind, diff)
end

local function xp() add("xp", { UnitLevel("player"), UnitXPMax("player") }) end

local SHAPE = { QUEST_ACCEPTED = true, QUEST_TURNED_IN = true, QUEST_DETAIL = true, QUEST_COMPLETE = true, QUEST_REMOVED = true, PLAYER_LEVEL_UP = true, TAXIMAP_OPENED = true, HEARTHSTONE_BOUND = true }
local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "TAXIMAP_OPENED", "HEARTHSTONE_BOUND", "ZONE_CHANGED_NEW_AREA", "QUEST_WATCH_UPDATE", "UI_INFO_MESSAGE" }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, ...)
  if not MG.db then return end -- 存檔變數要等 ADDON_LOADED 之後才在
  if not db then
    MetroGuideRecDB = MetroGuideRecDB or { v = 1, log = {} }
    db = MetroGuideRecDB
    for _, line in ipairs(db.log) do
      local s = line:find(SEP, 1, true)
      if s then seen[line:sub(1, s - 1)] = true end
    end
  end
  if not on() then return end
  if SHAPE[event] then MG.try("記錄", shape, event, ...) end
  MG.try("記錄", function(...)
    if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
      local id = GetQuestID and GetQuestID()
      local title = GetTitleText and GetTitleText()
      npcCache[id or 0] = quest(event == "QUEST_DETAIL" and "detail" or "complete", id, title)
    elseif event == "QUEST_ACCEPTED" then
      local n = select("#", ...)
      local id = n > 0 and select(n, ...) -- 經典式 (logIndex, questID)；新式 (questID)
      quest("accept", id, nil, npcCache[id])
    elseif event == "QUEST_TURNED_IN" then
      local id, gain, money = ...
      local who = npcCache[id] or npc()
      local map, x, y = pos()
      add("turnin", { id, who.id ~= "" and who.id or who.name }, C.Title(id), who.name, who.kind, map, x, y, gain, money)
      npcCache[id], prev[id] = nil, nil
      -- 交件時身上全部增益＋實得÷預期，用來找出經驗增益是哪個法術（tools/import-rec.mjs 比對）
      local expect = MG.E.QuestXP(id, UnitLevel("player") or 0)
      local list = {}
      for _, a in ipairs(C.Auras()) do list[#list + 1] = (a.name or "") .. "#" .. tostring(a.id or "") end
      add("auras", { id }, type(gain) == "number" and expect > 0 and string.format("%.4f", gain / expect) or "", table.concat(list, ";"))
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" then
      -- 一幀內多次只算一次
      if not objPending then
        objPending = true
        local run = function() objPending = false; MG.try("記錄", objectives) end
        if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
      end
    elseif event == "UI_INFO_MESSAGE" then infoMessage(select(2, ...))
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then xp()
    elseif event == "TAXIMAP_OPENED" then taxi()
    elseif event == "HEARTHSTONE_BOUND" then bind("bound")
    elseif event == "PLAYER_ENTERING_WORLD" then xp(); bind("login"); instance()
    elseif event == "ZONE_CHANGED_NEW_AREA" then instance()
    end
  end, ...)
end)

function Rec.XPRatio()
  local r = {}
  for _, line in ipairs(db and db.log or {}) do
    if line:find("^turnin\t") then
      local key, rest = line:match("^(.-)\t@\t(.*)$")
      local id = tonumber((key or ""):match("^turnin\t(%d+)"))
      local f = {}
      for v in ((rest or "") .. "\t"):gmatch("(.-)\t") do f[#f + 1] = v end
      local lv, gain = tonumber(f[2]), tonumber(f[9])
      local info = id and MG.Route.quests[id]
      if info and info.xp and info.xp > 0 and gain and gain > 0 and lv and lv - (info.lvl or lv) <= 5 then r[#r + 1] = gain / info.xp end
    end
  end
  table.sort(r)
  return r[math.floor((#r + 1) / 2)], #r
end

local PATH = "WTF\\Account\\<帳號>\\SavedVariables\\ShengLeveling.lua"
function Rec.Slash(arg)
  arg = arg:gsub("^%s+", "")
  if arg == "on" or arg == "off" then UI.Set("rec", arg == "on") end
  local n = db and #db.log or 0
  if arg == "export" then
    local L = { "#MGREC1 " .. n .. " 筆｜存檔：" .. PATH .. "（登出或 /reload 後寫入）" }
    for _, line in ipairs(db and db.log or {}) do L[#L + 1] = (line:gsub("|", "||")) end
    UI.ShowReport(table.concat(L, "\n"), "遊戲內記錄：Ctrl+A 全選、Ctrl+C 複製，貼回給開發者")
    return
  end
  if arg == "clear" and db then db.log, seen, prev = {}, {}, {}; n = 0 end
  MG.msg("遊戲內記錄：" .. (UI.Get("rec") and "開" or "關") .. "，" .. n .. " 筆。/slv rec on|off｜export 匯出｜clear 清空｜存檔 " .. PATH)
end
