-- 薄相容層：只有這裡碰版本差異。啟動時挑一次實作，之後每次呼叫都用 pcall 包住，錯誤只報一次。
local _, MG = ...
local C = {}
MG.C = C
C.impl = {} -- 挑到哪個實作（/slv probe 會印）

-- ── 語系（只在這裡選）─────────────────────────────────────────────────────────
-- 兩種語言分開：介面語言 uiLoc（字串表 L、路線的顯示文字；/slv lang 可預覽，/reload 後生效）
-- 和客戶端語言 gameLoc（選取目標的名字、和遊戲文字比對的任務名／NPC 名，一律跟 GetLocale()）。
-- 繁中是底稿：L 的鍵就是繁中原文，查不到就回傳鍵；其他語言（含簡中）＝ Locales\<locale>.lua 一個檔＋ Data\Route_<locale>.lua。
local CJK = { zhTW = true, zhCN = true }
MG.Locales = MG.Locales or {}
MG.gameLoc = GetLocale and GetLocale() or "enUS"
MG.gameZh = MG.gameLoc == "zhTW" -- 客戶端就是底稿語言：遊戲裡的名字直接用 Route.lua 的
MG.gameCJK = CJK[MG.gameLoc] or false -- 客戶端字型有中文字
local strings
MG.missingL = {} -- 非中文介面卻查不到翻譯的鍵（/slv probe 會列出）
MG.L = setmetatable({}, { __index = function(_, k)
  local v = strings and strings[k]
  if v then return v end
  if strings and type(k) == "string" and k:find("[\227-\233]") then MG.missingL[k] = true end -- 只記中文鍵
  return k
end })
-- 壓力語言（/slv lang stress）：英文字串後面補約 35% 長度的填充字，用來檢查版面放不放得下
local FILL = " xxxx yyyyy zzz wwwwww xxx yyyy zzzzz wwww xxxxx yyy zzzz wwwww"
function MG.Pad(s)
  if not MG.stress or type(s) ~= "string" then return s end
  local n = math.ceil(#s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") * 0.35)
  if n < 2 then return s end
  local fill = FILL
  while #fill < n do fill = fill .. FILL end
  return s .. fill:sub(1, n)
end
-- /slv lang 接受的代碼（小寫比對）→ 語系
MG.LANGS = { en = "enUS", enus = "enUS", zh = "zhTW", zhtw = "zhTW", zhcn = "zhCN", dede = "deDE", frfr = "frFR", eses = "esES", esmx = "esMX", ruru = "ruRU", kokr = "koKR", ptbr = "ptBR" }
-- 沒有字串表的語系：esMX 用 esES，其餘用英文
local function resolve(loc)
  if loc == "zhTW" or MG.Locales[loc] then return loc end
  return loc == "esMX" and MG.Locales.esES and "esES" or "enUS"
end
-- pref：auto（跟客戶端）／語言代碼（MG.LANGS）／stress
function MG.SetLang(pref)
  pref = type(pref) == "string" and pref:lower() or "auto"
  MG.stress = pref == "stress"
  local loc = resolve(MG.stress and "enUS" or MG.LANGS[pref] or MG.gameLoc)
  MG.uiLoc, MG.uiZh, MG.uiCJK, MG.uiKo = loc, loc == "zhTW", CJK[loc] or false, loc == "koKR"
  MG.sameLang = loc == resolve(MG.gameLoc) -- 介面和客戶端同語言：遊戲給的文字（任務名、目標）可以直接顯示
  strings = not MG.uiZh and MG.Locales[loc] or nil
  if MG.stress and strings then
    local base = strings
    strings = setmetatable({}, { __index = function(t, k)
      local v = base[k]
      if v then v = MG.Pad(v); t[k] = v end
      return v
    end })
  end
end
MG.SetLang("auto")
local L = MG.L

-- 任何要顯示的字串都過這裡。介面語言顯示不了的字（非中文介面的中文字、非韓文介面的韓文字：字型沒有字，會變方框）拿掉並記下來（/slv probe 列出）；
-- 非中文介面的全形標點換半形；非中文客戶端的字型也缺 ★→●… 這些符號，換成字型有的。
local FULL = { ["（"] = " (", ["）"] = ")", ["："] = ": ", ["，"] = ", ", ["、"] = ", ", ["；"] = "; ", ["。"] = ". ", ["／"] = "/", ["｜"] = " | ", ["「"] = "\"", ["」"] = "\"", ["　"] = " " }
local SYM = { ["★"] = "*", ["→"] = "->", ["●"] = "\226\128\162", ["○"] = "o", ["◎"] = "\194\187", ["‧"] = "\226\128\162", ["√"] = "+", ["▾"] = "", ["┃"] = "|" }
MG.leaks = {} -- 原文 → true（最多 30 筆）
local leakN = 0
function MG.Clean(s)
  if type(s) ~= "string" or (MG.uiCJK and MG.gameCJK) or not s:find("[\226-\239]") then return s end
  local leaked = false
  local out = s:gsub("([\226-\239][\128-\191][\128-\191])", function(c)
    if not MG.uiCJK and FULL[c] then return FULL[c] end
    if not MG.gameCJK and SYM[c] then return SYM[c] end
    local b1, b2 = c:byte(1, 2)
    -- 中日韓漢字、標點、全形字（韓文介面留下韓文相容字母 U+3100–31BF）
    if (b1 >= 227 and b1 <= 233) or (b1 == 239 and (b2 == 188 or b2 == 189)) then
      if MG.uiCJK or (MG.uiKo and b1 == 227 and b2 >= 132 and b2 <= 134) then return nil end
      leaked = true; return ""
    end
    -- 韓文音節 U+AC00–D7AF
    if (b1 == 234 and b2 >= 176) or b1 == 235 or b1 == 236 or (b1 == 237 and b2 <= 158) then
      if MG.uiKo then return nil end
      leaked = true; return ""
    end
  end)
  if leaked and not MG.leaks[s] and leakN < 30 then MG.leaks[s] = true; leakN = leakN + 1 end
  return out
end

function MG.msg(s) DEFAULT_CHAT_FRAME:AddMessage(MG.Clean(L["|cff4fc3f7阿聖|r|cffd9b25f練等幫手|r "] .. tostring(s))) end
ShengLv_Msg = MG.msg -- 給巨集的 /run 用，開頭顏色跟系列一致

-- 換版本時清掉舊版本留下的錯誤紀錄（修好的錯誤不用留著）
do
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:SetScript("OnEvent", function(self, _, name)
    if name ~= "ShengLeveling" then return end
    self:UnregisterEvent("ADDON_LOADED")
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ver = meta and meta("ShengLeveling", "Version")
    if type(MetroGuideDB) == "table" and ver and type(MetroGuideDB.errors) == "table" and MetroGuideDB.errors.ver ~= ver then
      MetroGuideDB.errors = { ver = ver }
    elseif type(MetroGuideDB) == "table" and ver and MetroGuideDB.errors == nil then
      MetroGuideDB.errors = { ver = ver }
    end
  end)
end
local reported = {}
local function after(where, ok, ...)
  if ok then return ... end
  local err = tostring((...))
  MG.lastError = where .. "：" .. err
  -- 錯誤存進存檔（登出後開發者讀得到），同一種錯誤只記一筆、算次數，最多 50 種
  if type(MetroGuideDB) == "table" then
    local log = MetroGuideDB.errors or {}
    MetroGuideDB.errors = log
    local key = where .. "：" .. err
    if log[key] then log[key].n = log[key].n + 1; log[key].t = date("%m/%d %H:%M")
    elseif #(log.keys or {}) < 50 then
      log.keys = log.keys or {}
      log.keys[#log.keys + 1] = key
      log[key] = { n = 1, t = date("%m/%d %H:%M") }
    end
  end
  if not reported[err] then
    reported[err] = true
    MG.msg("|cffff7b7b" .. L[where] .. L[" 出錯：|r"] .. err)
  end
  return nil
end
-- 呼叫 fn，出錯回 nil（每種錯誤只在聊天框報一次）
function MG.try(where, fn, ...) return after(where, pcall(fn, ...)) end

local QL = C_QuestLog
local function fn(t, k) return type(t) == "table" and type(t[k]) == "function" and t[k] or nil end
-- 一次重算內重複查同一個任務的結果共用（C.memo 由 MG.Refresh／位置檢查開關）
local MEMO = { IsOnQuest = true, IsTurnedIn = true, IsReady = true, Objectives = true, Title = true, QuestLevel = true }
local function pick(name, ...)
  local list, n = { ... }, select("#", ...) -- 中間可能有 nil，不能用 #list
  for i = 1, n, 2 do
    if list[i + 1] then
      C.impl[name] = list[i]
      local f = list[i + 1]
      if MEMO[name] then
        C[name] = function(a)
          local m = C.memo
          if not m then return MG.try(name, f, a) end
          local k = name .. ":" .. tostring(a)
          local hit = m[k]
          if not hit then hit = { MG.try(name, f, a) }; m[k] = hit end
          return hit[1]
        end
      else
        C[name] = function(...) return MG.try(name, f, ...) end
      end
      return
    end
  end
  C.impl[name] = "無"
  C[name] = function() return nil end
end

-- 任務日誌列號（經典式 API 需要）
local function logIndex(id)
  local f = fn(QL, "GetLogIndexForQuestID")
  local i = f and f(id)
  if (not i or i <= 0) and GetQuestLogIndexByID then i = GetQuestLogIndexByID(id) end
  if i and i > 0 then return i end
end
C.LogIndex = function(id) return MG.try("LogIndex", logIndex, id) end

pick("IsOnQuest",
  "C_QuestLog.IsOnQuest", fn(QL, "IsOnQuest") and function(id) return QL.IsOnQuest(id) and true or false end,
  "GetQuestLogIndexByID", (GetQuestLogIndexByID or fn(QL, "GetLogIndexForQuestID")) and function(id) return logIndex(id) ~= nil end)

pick("IsTurnedIn",
  "C_QuestLog.IsQuestFlaggedCompleted", fn(QL, "IsQuestFlaggedCompleted") and function(id) return QL.IsQuestFlaggedCompleted(id) and true or false end,
  "IsQuestFlaggedCompleted", IsQuestFlaggedCompleted and function(id) return IsQuestFlaggedCompleted(id) and true or false end)

-- 回 { [id] = true }
pick("AllTurnedIn",
  "C_QuestLog.GetAllCompletedQuestIDs", fn(QL, "GetAllCompletedQuestIDs") and function()
    local out = {}
    for _, id in ipairs(QL.GetAllCompletedQuestIDs() or {}) do out[id] = true end
    return out
  end,
  "GetQuestsCompleted", GetQuestsCompleted and function()
    local out = {}
    for id in pairs(GetQuestsCompleted() or {}) do out[id] = true end
    return out
  end)

pick("IsReady",
  "C_QuestLog.IsComplete", fn(QL, "IsComplete") and function(id) return QL.IsComplete(id) and true or false end,
  "C_QuestLog.ReadyForTurnIn", fn(QL, "ReadyForTurnIn") and function(id) return QL.ReadyForTurnIn(id) and true or false end,
  "GetQuestLogTitle", GetQuestLogTitle and function(id)
    local i = logIndex(id)
    return i and select(6, GetQuestLogTitle(i)) == 1 or false
  end)

-- 回 { {text, have, need, done}, ... }；查不到回 nil
local function label(text)
  text = tostring(text or "")
  text = text:gsub("%s*%d+%s*/%s*%d+%s*", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub(":$", ""):gsub("：$", "")
  return text
end
pick("Objectives",
  "C_QuestLog.GetQuestObjectives", fn(QL, "GetQuestObjectives") and function(id)
    local list = QL.GetQuestObjectives(id)
    if not list then return nil end
    local out = {}
    for _, o in ipairs(list) do
      out[#out + 1] = { text = label(o.text), have = o.numFulfilled, need = o.numRequired, done = o.finished and true or false }
    end
    return out
  end,
  "GetQuestLogLeaderBoard", GetQuestLogLeaderBoard and function(id)
    local i = logIndex(id)
    if not i then return nil end
    local out = {}
    for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0) do
      local text, _, finished = GetQuestLogLeaderBoard(j, i)
      local have, need = tostring(text or ""):match("(%d+)%s*/%s*(%d+)")
      out[#out + 1] = { text = label(text), have = tonumber(have), need = tonumber(need), done = finished and true or false }
    end
    return out
  end)

pick("Title",
  "C_QuestLog.GetTitleForQuestID", fn(QL, "GetTitleForQuestID") and function(id) return QL.GetTitleForQuestID(id) end)

-- 任務等級（日誌中才有）
pick("QuestLevel",
  "C_QuestLog.GetInfo", fn(QL, "GetInfo") and function(id)
    local i = logIndex(id)
    local info = i and QL.GetInfo(i)
    return info and info.level
  end,
  "GetQuestLogTitle", GetQuestLogTitle and function(id)
    local i = logIndex(id)
    return i and (select(2, GetQuestLogTitle(i)))
  end)

-- 任務日誌中的任務 ID 清單
pick("LogQuestIDs",
  "C_QuestLog.GetInfo", fn(QL, "GetInfo") and fn(QL, "GetNumQuestLogEntries") and function()
    local out = {}
    for i = 1, QL.GetNumQuestLogEntries() do
      local info = QL.GetInfo(i)
      if info and not info.isHeader and info.questID and info.questID > 0 then out[#out + 1] = info.questID end
    end
    return out
  end,
  "GetQuestLogTitle", GetQuestLogTitle and GetNumQuestLogEntries and function()
    local out = {}
    for i = 1, GetNumQuestLogEntries() do
      local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
      if not isHeader and id and id > 0 then out[#out + 1] = id end
    end
    return out
  end)

-- 回 map, x, y（x/y 為 0–100）；副本或限制中讀到秘密值就當讀不到
pick("Position",
  "C_Map.GetPlayerMapPosition", fn(C_Map, "GetBestMapForUnit") and fn(C_Map, "GetPlayerMapPosition") and function()
    local map = C_Map.GetBestMapForUnit("player")
    if not map or (issecretvalue and issecretvalue(map)) then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return map end
    local x, y = pos:GetXY()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return map end
    return map, x and x * 100, y and y * 100
  end)

pick("Bind", "GetBindLocation", GetBindLocation and function() return GetBindLocation() end)

-- 任務綠色範圍（超過即灰）：GetQuestGreenRange → 估算
pick("GreenRange",
  "GetQuestGreenRange", GetQuestGreenRange and function() return GetQuestGreenRange() end,
  "估算", function()
    local lv = UnitLevel("player") or 1
    if lv <= 5 then return 5 elseif lv <= 39 then return 5 + math.floor(lv / 10) else return 1 + math.floor(lv / 5) end
  end)

-- 分享任務：選取後推送（要在隊伍中）
-- 玩家身上的增益：{ { name, id, dur }... }；秘密值的欄位留空
-- 戰鬥中（或其他限制啟動時）遊戲不讓插件讀增益，硬讀會報錯：那時沿用上次讀到的結果
local lastAuras = {}
local function auraLocked() return InCombatLockdown and InCombatLockdown() end
function C.Auras()
  if auraLocked() then return lastAuras end
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return lastAuras end
  local function plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) and v or nil end
  local ok, out = pcall(function()
    local list = {}
    for i = 1, 40 do
      local a = get("player", i, "HELPFUL")
      if not a then break end
      list[#list + 1] = { name = plain(a.name), id = plain(a.spellId), dur = plain(a.duration) }
    end
    return list
  end)
  if ok then lastAuras = out end
  return lastAuras
end
-- 任務經驗 +3% 的增益：主人確認名字是「充分休息」（和打怪的休息經驗不同）；法術 ID 從記錄報告找到後填進 XP_BUFFS
C.XP_BUFF_NAME = "充分休息" -- 名字開頭是這個就算
C.XP_BUFFS = { 429960 } -- Wowhead：充分休息追蹤光環（實際顯示的增益可能是相鄰 ID，記錄器會記下看到的 ID）
-- 有經驗增益就回傳 { name, id, how }（how＝「法術 ID」或「名稱」；一次重算內只查一次）
local lastXPBuff = false
function C.XPBuff()
  local m = C.memo
  if m and m.xpbuff ~= nil then return m.xpbuff or nil end
  if auraLocked() then return lastXPBuff or nil end -- 戰鬥中讀不到增益，用戰鬥前的結果
  local found = false
  local byId = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
  for _, id in ipairs(byId and C.XP_BUFFS or {}) do
    local ok, a = pcall(byId, id)
    if ok and a then found = { name = not (issecretvalue and issecretvalue(a.name)) and a.name or nil, id = id, how = "法術 ID" }; break end
  end
  if not found then
    for _, a in ipairs(C.Auras()) do
      if a.name and a.name:sub(1, #C.XP_BUFF_NAME) == C.XP_BUFF_NAME then found = { name = a.name, id = a.id, how = "名稱" }; break end
    end
  end
  if m then m.xpbuff = found end
  lastXPBuff = found
  return found or nil
end

function C.ShareQuest(q)
  local QL = C_QuestLog
  MG.try("分享", function()
    if QL and QL.SetSelectedQuest then QL.SetSelectedQuest(q) end
    if QuestLogPushQuest then QuestLogPushQuest() end
  end)
end

-- 設定頁：新版 Settings API → 舊版 InterfaceOptions → 直接顯示
local category
function C.RegisterOptions(frame, name)
  frame.name = name
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    category = Settings.RegisterCanvasLayoutCategory(frame, name)
    Settings.RegisterAddOnCategory(category)
    C.impl.Options = "Settings"
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(frame)
    C.impl.Options = "InterfaceOptions"
  else
    C.impl.Options = "無"
  end
end
function C.OpenOptions(frame)
  if InCombatLockdown and InCombatLockdown() then MG.msg(L["戰鬥中不能開設定，脫離戰鬥後再開。"]); return end
  if category and Settings and Settings.OpenToCategory then
    MG.try("設定頁", Settings.OpenToCategory, category.GetID and category:GetID() or category.ID)
  elseif InterfaceOptionsFrame_OpenToCategory then
    MG.try("設定頁", InterfaceOptionsFrame_OpenToCategory, frame)
    MG.try("設定頁", InterfaceOptionsFrame_OpenToCategory, frame) -- 舊版第一次常開錯頁
  else
    -- 沒有設定 API：直接顯示，大小夾在螢幕內（設定頁顯示時會照這個寬度排版）
    frame:SetParent(UIParent)
    frame:SetSize(math.min(640, (UIParent:GetWidth() or 680) - 40), math.min(560, (UIParent:GetHeight() or 600) - 40))
    frame:ClearAllPoints(); frame:SetPoint("CENTER"); frame:Show()
  end
end

-- 任務日誌的描述與目標文字（需在日誌中）：選取 → 讀 → 還原選取
function C.QuestText(id)
  local QL = C_QuestLog
  if not (QL and QL.SetSelectedQuest and GetQuestLogQuestText and C.IsOnQuest(id)) then return nil end
  return MG.try("任務文字", function()
    local old = QL.GetSelectedQuest and QL.GetSelectedQuest()
    QL.SetSelectedQuest(id)
    local desc, obj = GetQuestLogQuestText()
    if old and old ~= id then QL.SetSelectedQuest(old) end
    return desc, obj
  end)
end

-- 齒輪圖示：先試邊緣較緊的 WorldMap 齒輪；SetTexture 回報失敗再用 atlas，最後用舊選項按鈕（裁掉留白）
function C.GearIcon(tex, size)
  local ok, loaded = pcall(tex.SetTexture, tex, "Interface\\WorldMap\\Gear_64Grey")
  if ok and loaded then
    tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    tex:SetSize(size + 2, size + 2)
    C.impl.Gear = "Gear_64Grey"
    return
  end
  local atlas = "GM-icon-settings"
  if C_Texture and C_Texture.GetAtlasInfo and MG.try("圖示", C_Texture.GetAtlasInfo, atlas) and tex.SetAtlas then
    tex:SetAtlas(atlas)
    tex:SetSize(size + 4, size + 4)
    C.impl.Gear = "atlas " .. atlas
  else
    tex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    tex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    tex:SetSize(size + 2, size + 2)
    C.impl.Gear = "UI-OptionsButton"
  end
end

-- 滑桿：MinimalSliderWithSteppersTemplate → OptionsSliderTemplate → 自己畫
function C.Slider(parent, min, max, step, value, onChange)
  local function snap(v) return math.floor(v / step + 0.5) * step end
  local ok, f = pcall(CreateFrame, "Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
  if ok and f and f.Init and f.RegisterCallback and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Event then
    if pcall(f.Init, f, value, min, max, math.floor((max - min) / step + 0.5)) then
      f:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v) onChange(snap(v)) end, f)
      f:SetHeight(20)
      f.kind = "minimal"
      C.impl.Slider = "MinimalSliderWithSteppersTemplate"
      return f
    end
    f:Hide()
  end
  local s
  ok, s = pcall(CreateFrame, "Slider", nil, parent, "OptionsSliderTemplate")
  if ok and s then
    C.impl.Slider = "OptionsSliderTemplate"
    for _, k in ipairs({ "Low", "High", "Text" }) do if type(s[k]) == "table" and s[k].SetText then s[k]:SetText("") end end
  else
    s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(16)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.3, 0.3, 0.33, 1)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    C.impl.Slider = "自製"
  end
  s:SetMinMaxValues(min, max)
  s:SetValueStep(step)
  if s.SetObeyStepsOnDrag then s:SetObeyStepsOnDrag(true) end
  s:SetValue(value)
  s:SetScript("OnValueChanged", function(_, v) onChange(snap(v)) end)
  return s
end
function C.SliderSet(s, v)
  if s.kind == "minimal" then MG.try("滑桿", s.SetValue, s, v) else s:SetValue(v) end
end

-- 提示框背景透明度：只在我們顯示時改，a = nil 還原
local tipBgOld
function C.TooltipAlpha(tip, a)
  local ns = tip.NineSlice
  if type(ns) == "table" and ns.SetCenterColor and ns.GetCenterColor then
    if a == nil then
      if tipBgOld then ns:SetCenterColor(unpack(tipBgOld)); tipBgOld = nil end
      return
    end
    if a >= 1 and not tipBgOld then return end
    if not tipBgOld then tipBgOld = { ns:GetCenterColor() } end
    ns:SetCenterColor(tipBgOld[1], tipBgOld[2], tipBgOld[3], a)
  elseif tip.SetBackdropColor and tip.GetBackdropColor then
    if a == nil then
      if tipBgOld then tip:SetBackdropColor(unpack(tipBgOld)); tipBgOld = nil end
      return
    end
    if a >= 1 and not tipBgOld then return end
    if not tipBgOld then tipBgOld = { tip:GetBackdropColor() } end
    tip:SetBackdropColor(tipBgOld[1], tipBgOld[2], tipBgOld[3], a)
  end
end

-- 地圖名（遊戲客戶端語言的地區名）
local mapNames = {}
function C.MapName(map)
  if not map then return nil end
  if mapNames[map] == nil then
    local info = C_Map and C_Map.GetMapInfo and MG.try("地圖名", C_Map.GetMapInfo, map)
    mapNames[map] = info and info.name or false
  end
  return mapNames[map] or nil
end
-- 地區名（AreaTable ID，客戶端語言；城鎮、副本）
local areaNames = {}
function C.AreaName(id)
  if not id then return nil end
  if areaNames[id] == nil then
    local name = C_Map and C_Map.GetAreaInfo and MG.try("地區名", C_Map.GetAreaInfo, id)
    areaNames[id] = type(name) == "string" and name ~= "" and name or false
  end
  return areaNames[id] or nil
end
