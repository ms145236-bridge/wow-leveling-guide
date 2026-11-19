-- 遊戲內記錄：任務接交 NPC 與座標、目標進度位置、真實經驗表、飛行點、爐石、副本、事件參數；
-- NPC 列出的可接任務、路線持物條件物品的掉落、搭船／飛艇的上下船點與換地圖前後位置。
-- 存 MetroGuideRecDB（帳號共用）。每筆一行：鍵欄位 \t@\t 時間 \t 等級 \t 其他欄位。同鍵只記一次；最多 MAX 筆，滿了丟最舊的。
-- 不讀秘密值：UnitGUID/UnitName 是秘密值就整欄留空。離線用 tools/import-rec.mjs 讀。
local ADDON, MG = ...
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

-- Compare a quest pickup to its hand-in in the same character session.
-- Keeping starts in memory avoids mixing alts or counting time spent logged out.
local timedQuests = { [3881] = true, [7729] = true, [2581] = true }
local starts = {}
function Rec.ResetTimings() wipe(starts) end

local function startTiming(id)
  if timedQuests[id] then
    starts[id] = { clock = GetTime(), wall = time(), level = UnitLevel("player"),
      grouped = IsInGroup and IsInGroup() }
  end
end

local function finishTiming(id)
  local start = starts[id]
  if not start then return end
  starts[id] = nil
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  local group = start.grouped or (IsInGroup and IsInGroup())
  local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
  add("timing", { id, start.wall, UnitFactionGroup("player"), race, class },
    math.floor(GetTime() - start.clock + 0.5), start.level, group and 1 or 0,
    version or "", MG.Route and MG.Route.built or "")
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

-- NPC 這次列出哪些可接任務（沒列也記一次）：前置、種族職業限制是不是真的。讀到秘密值就整筆不記
local function offers(event)
  local who = npc()
  local list = {}
  if event == "GOSSIP_SHOW" then
    local G = C_GossipInfo
    for _, q in ipairs(G and G.GetAvailableQuests and G.GetAvailableQuests() or {}) do
      if secret(q.questID) then return end
      list[#list + 1] = q.questID
    end
    table.sort(list)
  else -- QUEST_GREETING 只給標題
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
      local title = GetAvailableTitle(i)
      if title == nil or secret(title) then return end
      list[#list + 1] = field(title)
    end
  end
  local map, x, y = pos()
  add("offer", { who.id ~= "" and who.id or who.name, table.concat(list, ";") }, who.name, who.kind, map, x, y)
end

-- 路線用「背包有某物品」判斷的物品：從屍體撿到、第一次進背包時，記是哪種怪（怪物 ID）、這種怪撿到第幾隻才拿到、在哪裡。
-- 來源認撿屍視窗的 GetLootSourceInfo（屍體 GUID），不認目標；同一具屍體重開只算一次。
-- 讀不到來源就記「來源未確認」（怪物 ID、次數留空）。撿屍視窗裡沒真的拿走這件、或記錄關過，就不記
local watch, had, kills, base, corpses, slots, taken = nil, nil, {}, {}, {}, nil, {}
local function watchItems()
  if watch then return watch end
  watch = {}
  for _, list in ipairs({ MG.Route.stations or {}, MG.Route.dungeons or {} }) do
    for _, st in ipairs(list) do
      for _, s in ipairs(st.steps or {}) do
        local bag = s.when and s.when.bag
        if bag and bag.item then watch[bag.item] = s.q or watch[bag.item] or "" end
      end
    end
  end
  return watch
end
local function lootReset()
  had, slots = nil, nil
  wipe(kills); wipe(base); wipe(corpses); wipe(taken)
end
local function bagBase()
  had = {}
  for id in pairs(watchItems()) do had[id] = MG.E.ItemCount(id) end
end
-- 每具屍體第一次打開時就定好它是這種怪上次掉落之後的第幾隻（corpses[GUID]），之後分幾次拿也用同一個數。
-- 一格只認得出一具屍體才算來源；有兩具以上（就算同種怪）、或任何一個來源讀不到／是秘密值，就當來源未確認
local function looted()
  slots = {}
  for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
    local link = GetLootSlotLink and GetLootSlotLink(i)
    local id = link and not secret(link) and tonumber(link:match("item:(%d+)"))
    local src = GetLootSourceInfo and { GetLootSourceInfo(i) } or {} -- 回傳 GUID, 數量, GUID, 數量…：整串都要留
    local one, known = nil, #src > 0
    for k = 1, #src, 2 do
      local guid = src[k]
      local mob = guid ~= nil and not secret(guid) and tostring(guid):match("^Creature%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
      if not mob then known = false
      else
        if not corpses[guid] then
          kills[mob] = (kills[mob] or 0) + 1
          corpses[guid] = { mob = mob, serial = kills[mob], n = kills[mob] - (base[mob] or 0) }
        end
        if one then known = false end
        one = guid
      end
    end
    slots[i] = { id = id, corpse = known and one and corpses[one] or nil }
  end
end
local function slotCleared(i)
  local s = slots and slots[i]
  if s and s.id and watchItems()[s.id] then taken[s.id] = { corpse = s.corpse, at = GetTime() } end
end
local function bagItems()
  if not had then bagBase(); return end
  for id, q in pairs(watchItems()) do
    local n = MG.E.ItemCount(id)
    local t = taken[id]
    if n > had[id] and had[id] == 0 and t and GetTime() - t.at < 10 then
      local c, map, x, y = t.corpse, pos()
      add("loot", { id, c and c.mob or "", c and c.n or "", map, x ~= "" and math.floor(tonumber(x)) or "", y ~= "" and math.floor(tonumber(y)) or "" }, q, x, y)
      if c then base[c.mob] = math.max(base[c.mob] or 0, c.serial) end
    end
    if n > 0 then taken[id] = nil end
    had[id] = n
  end
end

-- 船、飛艇、電梯：自己沒在走、也不在鳥上，位置卻在變＝被載著走。記上船前站的點與停下來的點；換地圖時記讀取畫面前後的位置。
-- 航行中跳下（掉落）就作廢這一趟；航行中自己走動過，停下的點只算候選（可能是走上岸後停下）
local last, anchor, carried, ride, from = nil, nil, 0, nil, nil
local function sample()
  local map, x, y = C.Position()
  if not x then last = nil; return end
  local d = last and last.map == map and math.sqrt((x - last.x) ^ 2 + (y - last.y) ^ 2)
  local moving, falling = IsPlayerMoving and IsPlayerMoving(), IsFalling and IsFalling()
  local still = not moving and not falling and not (UnitOnTaxi and UnitOnTaxi("player"))
  if falling and ride then ride = nil end
  if d and d > 0.15 and still then
    carried = carried + 1
    if carried == 2 and not ride and anchor then
      ride = { walked = false }
      add("board", { anchor.map, math.floor(anchor.x), math.floor(anchor.y) }, num(anchor.x), num(anchor.y))
    end
  else
    carried = 0
    if ride and moving then ride.walked = true end
    if ride and d and d < 0.02 and still then
      add("stop", { map, math.floor(x), math.floor(y) }, num(x), num(y), ride.walked and 1 or 0)
      ride = nil
    end
    anchor = { map = map, x = x, y = y }
  end
  last = { map = map, x = x, y = y }
end

local SHAPE = { QUEST_ACCEPTED = true, QUEST_TURNED_IN = true, QUEST_DETAIL = true, QUEST_COMPLETE = true, QUEST_REMOVED = true, PLAYER_LEVEL_UP = true, TAXIMAP_OPENED = true, HEARTHSTONE_BOUND = true }
local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "TAXIMAP_OPENED", "HEARTHSTONE_BOUND", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "QUEST_WATCH_UPDATE", "UI_INFO_MESSAGE", "GOSSIP_SHOW", "QUEST_GREETING", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "BAG_UPDATE_DELAYED", "LOADING_SCREEN_ENABLED" }) do
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
    if C_Timer and C_Timer.NewTicker then
      C_Timer.NewTicker(2, function()
        if on() then MG.try("記錄", sample) elseif had then lootReset(); ride = nil end -- 從設定關掉時不一定有事件：在這裡清掉
      end)
    end
  end
  if not on() then lootReset(); ride = nil; return end -- 關著時背包、船上的事都不知道：重開時重新對齊
  if not had then bagBase() end
  if event == "GROUP_ROSTER_UPDATE" then
    if IsInGroup and IsInGroup() then
      for _, start in pairs(starts) do start.grouped = true end
    end
    return
  end
  if SHAPE[event] then MG.try("記錄", shape, event, ...) end
  MG.try("記錄", function(...)
    if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
      local id = GetQuestID and GetQuestID()
      if secret(id) then return end
      local title = GetTitleText and GetTitleText()
      npcCache[id or 0] = quest(event == "QUEST_DETAIL" and "detail" or "complete", id, title)
    elseif event == "QUEST_ACCEPTED" then
      local n = select("#", ...)
      local id = n > 0 and select(n, ...) -- 經典式 (logIndex, questID)；新式 (questID)
      if secret(id) then return end
      startTiming(id)
      quest("accept", id, nil, npcCache[id])
    elseif event == "QUEST_TURNED_IN" then
      local id, gain, money = ...
      if secret(id) then return end
      finishTiming(id)
      if secret(gain) then gain = nil end
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
    elseif event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then offers(event)
    elseif event == "LOOT_OPENED" then looted()
    elseif event == "LOOT_SLOT_CLEARED" then slotCleared(...)
    elseif event == "LOOT_CLOSED" then slots = nil
    elseif event == "BAG_UPDATE_DELAYED" then bagItems()
    elseif event == "LOADING_SCREEN_ENABLED" then
      local map, x, y = C.Position()
      from = x and { map = map, x = x, y = y } or nil
    elseif event == "PLAYER_ENTERING_WORLD" then
      local login, reload = ...
      if from and not login and not reload then
        local map, x, y = pos()
        add("load", { from.map, math.floor(from.x), math.floor(from.y), map }, num(from.x), num(from.y), x, y)
      end
      from, last, carried = nil, nil, 0
      xp(); bind("login"); instance()
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
  if arg == "on" or arg == "off" then UI.Set("rec", arg == "on"); lootReset() end
  local n = db and #db.log or 0
  if arg == "export" then
    local out = { "#MGREC1 " .. n .. MG.L[" 筆｜存檔："] .. MG.L[PATH] .. MG.L["（登出或 /reload 後寫入）"] }
    for _, line in ipairs(db and db.log or {}) do out[#out + 1] = (line:gsub("|", "||")) end
    UI.ShowReport(table.concat(out, "\n"), MG.L["遊戲內記錄：Ctrl+A 全選、Ctrl+C 複製，貼回給開發者"])
    return
  end
  if arg == "clear" and db then db.log, seen, prev = {}, {}, {}; Rec.ResetTimings(); n = 0 end
  MG.msg(MG.L["遊戲內記錄：%s，%d 筆。/slv rec on|off｜export 匯出｜clear 清空｜存檔 %s"]:format(UI.Get("rec") and MG.L["開"] or MG.L["關"], n, MG.L[PATH]))
end
