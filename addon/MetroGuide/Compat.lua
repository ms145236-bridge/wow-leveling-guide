-- 薄相容層：只有這裡碰版本差異。啟動時挑一次實作，之後每次呼叫都用 pcall 包住，錯誤只報一次。
local _, MG = ...
local C = {}
MG.C = C
C.impl = {} -- 挑到哪個實作（/metro probe 會印）

function MG.msg(s) DEFAULT_CHAT_FRAME:AddMessage("|cffd9b25f地鐵升級|r " .. tostring(s)) end

local reported = {}
local function after(where, ok, ...)
  if ok then return ... end
  local err = tostring((...))
  MG.lastError = where .. "：" .. err
  if not reported[err] then
    reported[err] = true
    MG.msg("|cffff7b7b" .. where .. " 出錯：|r" .. err)
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

-- 回 map, x, y（x/y 為 0–100）
pick("Position",
  "C_Map.GetPlayerMapPosition", fn(C_Map, "GetBestMapForUnit") and fn(C_Map, "GetPlayerMapPosition") and function()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return map end
    local x, y = pos:GetXY()
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
  if category and Settings and Settings.OpenToCategory then
    MG.try("設定頁", Settings.OpenToCategory, category.GetID and category:GetID() or category.ID)
  elseif InterfaceOptionsFrame_OpenToCategory then
    MG.try("設定頁", InterfaceOptionsFrame_OpenToCategory, frame)
    MG.try("設定頁", InterfaceOptionsFrame_OpenToCategory, frame) -- 舊版第一次常開錯頁
  else
    frame:SetParent(UIParent); frame:SetSize(300, 340); frame:ClearAllPoints(); frame:SetPoint("CENTER"); frame:Show()
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

-- 地圖名（遊戲的 zhTW 地區名）
local mapNames = {}
function C.MapName(map)
  if not map then return nil end
  if mapNames[map] == nil then
    local info = C_Map and C_Map.GetMapInfo and MG.try("地圖名", C_Map.GetMapInfo, map)
    mapNames[map] = info and info.name or false
  end
  return mapNames[map] or nil
end
