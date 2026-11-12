-- 選取任務目標：步驟列的準星按鈕（可綁快捷鍵）和動作條巨集「任務目標」用同一段巨集文字：
--   /cleartarget、每個名字 /targetexact [noexists]、再 /target [noexists] 當備援、/tm 標記選到的那隻、/run MGTP()（記錄按下）
-- 這個客戶端的限制：SetRaidTarget 是受保護函式；目標相關 API（GetRaidTargetIndex 等）回傳「秘密值」，插件不能比較。
-- 所以插件只寫巨集文字，不讀目標狀態：標記、選取都由遊戲執行巨集完成。
-- 巨集文字只能在戰鬥外更新（按鈕屬性與 EditMacro 都是），戰鬥中有變動就等脫離戰鬥。
local _, MG = ...
local C = MG.C
local T = {}
MG.T = T
T.MARKS = { "星星", "圓圈", "鑽石", "三角", "月亮", "方塊", "叉叉", "骷髏" }

BINDING_HEADER_METROGUIDE = "地鐵升級"
_G["BINDING_NAME_CLICK MetroGuideTargetButton:LeftButton"] = "選取任務目標"

local btn, pending, rot, names, key = nil, false, 0, {}, ""
local stepKey = "" -- 目前步驟（換步驟時名單和輪換重來）
T.stats = { presses = 0, targetChanged = 0, lastPress = 0, lastTarget = -1 }

-- 目前步驟要找的名字：做＝還沒完成的目標的怪（掉落物就是掉它的怪）；接／交＝NPC（物件、物品不算）
local function mobsOf(q, out, seen)
  local per = (MG.Route.quests[q] or {}).tgo or {}
  local obj = C.IsOnQuest(q) and C.Objectives(q)
  for k, list in ipairs(per) do
    if not (obj and #obj == #per and obj[k].done) then
      for _, n in ipairs(list) do if not seen[n] then seen[n] = true; out[#out + 1] = n end end
    end
  end
end
function T.Targets(state)
  local step = state and state.cur and state.steps[state.cur]
  if not step then return {} end
  local s = step.s
  local out, seen = {}, {}
  if s.t == "do" and s.q then
    mobsOf(s.q, out, seen)
  elseif (s.t == "accept" or s.t == "turnin") and (s.tgt or s.npc) and not (s.npc or ""):find("^物件") and not (s.npc or ""):find("^物品") then
    -- 用建置時從 QuestieDB 取的遊戲名（tgt）；沒有才用路線上的名字，去掉引號類符號
    local n = s.tgt
    if not n then
      n = s.npc
      for _, mark in ipairs({ "『", "』", "「", "」", "《", "》" }) do n = n:gsub(mark, "") end -- 逐個去（不能用字元集，會切壞 UTF-8）
    end
    out[1] = n; seen[n] = true
  end
  -- 同組（附近一起做）的「做」步驟的怪也算進來
  for _, i in ipairs(state.group or {}) do
    local g = state.steps[i].s
    if g.t == "do" and g.q then mobsOf(g.q, out, seen) end
  end
  return out
end

function T.Shown(state)
  return MG.UI.Get("showTarget") and #T.Targets(state) > 0
end

-- /tm 對已有同一標記的目標會「取消」：同一步驟按過後 20 秒內不加 /tm（只靠自己記錄，不讀目標）
local MARK_HOLD = 20
local markedAt, markedStep = 0, ""
local function markLine()
  if not MG.UI.Get("markOn") then return nil end
  if markedStep == stepKey and GetTime() - markedAt < MARK_HOLD then return nil end
  return "/tm [@target,exists,nodead] " .. MG.UI.Get("markIcon")
end

-- 巨集文字（255 字元內）：先全部完整名稱，再部分比對當備援；超過時先丟備援、再丟後面的名字。標記與記錄那兩行一定保留。
local LIMIT = 255
local PRESS_LINE = "/run MGTP()"
local function macro()
  if #names == 0 then return "" end
  local order, n = {}, #names
  for k = 0, n - 1 do order[#order + 1] = names[(rot + k) % n + 1] end
  local lines, size = { "/cleartarget" }, #"/cleartarget"
  local mark = markLine()
  size = size + 1 + #PRESS_LINE + (mark and (1 + #mark) or 0)
  local function add(line)
    if size + 1 + #line > LIMIT then return false end
    lines[#lines + 1] = line
    size = size + 1 + #line
    return true
  end
  for _, name in ipairs(order) do if not add("/targetexact [noexists] " .. name) then break end end
  for _, name in ipairs(order) do if not add("/target [noexists] " .. name) then break end end
  if mark then lines[#lines + 1] = mark end
  lines[#lines + 1] = PRESS_LINE
  return table.concat(lines, "\n")
end
T.MacroText = macro

-- 動作條巨集「任務目標」：內容就是同一段巨集文字（不經過 /click）
local MACRO, OLD_MACRO = "任務目標", "地鐵目標"
local ICON = "Ability_Hunter_SniperShot"
local EMPTY = "/run print(\"地鐵升級：目前步驟沒有要選的目標\")"
local function macroBody()
  local text = macro()
  return text ~= "" and text or EMPTY
end
-- 舊名「地鐵目標」的巨集原地改名（保留它在快捷列上的位置），不另建第二個
local function renameOld()
  local old = GetMacroIndexByName(OLD_MACRO)
  if old and old > 0 and (GetMacroIndexByName(MACRO) or 0) == 0 then
    EditMacro(old, MACRO, ICON, macroBody())
  end
end
local lastBody
function T.SyncMacro()
  if not GetMacroIndexByName or InCombatLockdown() then return false end
  renameOld()
  local index = GetMacroIndexByName(MACRO)
  if index and index > 0 then
    local body = macroBody()
    if body ~= lastBody then EditMacro(index, MACRO, ICON, body); lastBody = body end
  end
  return true
end

function T.MakeMacro()
  if InCombatLockdown() then MG.msg("戰鬥中不能建立巨集，脫離戰鬥再試。"); return end
  renameOld()
  local index = GetMacroIndexByName(MACRO)
  if index and index > 0 then
    lastBody = nil
    T.SyncMacro()
  else
    if GetNumMacros() >= (MAX_ACCOUNT_MACROS or 36) then MG.msg("帳號巨集已滿，請先刪掉一個再按「建立巨集」。"); return end
    index = CreateMacro(MACRO, ICON, macroBody(), nil)
  end
  if index and index > 0 then
    PickupMacro(index)
    MG.msg("巨集「" .. MACRO .. "」已拿在滑鼠上，放到動作條即可。")
  end
end

-- 自動建立：設定開著、還沒有這個巨集、帳號巨集還有空位 → 默默建立（不拿到滑鼠上），第一次在聊天框說一聲
function T.AutoMacro()
  if not GetMacroIndexByName then return end
  if InCombatLockdown() then pending = true; return end
  renameOld() -- 改名不受「自動建立」設定影響
  local index = GetMacroIndexByName(MACRO)
  if index and index > 0 then lastBody = nil; T.SyncMacro(); return end
  if not MG.UI.Get("autoMacro") then return end
  if GetNumMacros() >= (MAX_ACCOUNT_MACROS or 36) then return end
  index = CreateMacro(MACRO, ICON, macroBody(), nil)
  if index and index > 0 and not MetroGuideDB.macroNoted then
    MetroGuideDB.macroNoted = true
    MG.msg("已建立巨集『" .. MACRO .. "』，可在巨集視窗（/macro）拖到快捷列")
  end
end

-- 把巨集文字寫到按鈕和動作條巨集（戰鬥外）
function T.Apply()
  if not btn then return end
  if InCombatLockdown() then pending = true; return end
  pending = false
  btn:SetAttribute("type", "macro")
  btn:SetAttribute("macrotext", macro())
  btn:SetShown(T.visible and MetroGuideFrame and MetroGuideFrame:IsShown() or false)
  MG.try("目標巨集", T.SyncMacro)
end

function T.Update(state)
  if not btn then return end
  local list = T.Targets(state)
  local step = state and state.cur and state.steps[state.cur]
  local sk = step and step.key or ""
  T.visible = MG.UI.Get("showTarget") and #list > 0
  local k = sk .. "|" .. table.concat(list, "|") .. tostring(T.visible) .. tostring(MetroGuideFrame and MetroGuideFrame:IsShown()) .. tostring(MG.UI.Get("markOn")) .. MG.UI.Get("markIcon")
  if k == key and not pending then return end
  if sk ~= stepKey or table.concat(list, "|") ~= table.concat(names, "|") then rot = 0 end
  stepKey = sk
  names, key = list, k
  T.Apply()
end

-- 巨集最後一行 /run MGTP()：記錄「按了一次」→ 輪換下次優先的名字、這一步暫時不再加 /tm（避免取消標記），20 秒後恢復
function MGTP()
  T.stats.presses = T.stats.presses + 1
  T.stats.lastPress = GetTime()
  -- 巨集前面幾行剛換過目標（同一瞬間）→ 算一次成功
  if GetTime() - T.stats.lastTarget < 0.5 then T.stats.targetChanged = T.stats.targetChanged + 1 end
  markedAt, markedStep = GetTime(), stepKey
  rot = rot + 1
  key = "" -- 下次 Update 一定重寫
  T.Apply()
  if C_Timer and C_Timer.After then C_Timer.After(MARK_HOLD + 0.5, function() key = ""; T.Apply() end) end
end

function T.Diag()
  local L = {}
  local index = GetMacroIndexByName and GetMacroIndexByName(MACRO) or 0
  local body = index > 0 and GetMacroInfo and select(3, GetMacroInfo(index)) or nil
  local old = GetMacroIndexByName and GetMacroIndexByName(OLD_MACRO) or 0
  L[#L + 1] = "巨集「" .. MACRO .. "」格位 " .. index .. "（舊名格位 " .. old .. "）內容：" .. (body and body:gsub("\n", " | ") or "無")
  L[#L + 1] = "ActionButtonUseKeyDown：" .. tostring(GetCVar and GetCVar("ActionButtonUseKeyDown")) .. "｜issecretvalue：" .. tostring(issecretvalue ~= nil)
  if btn then
    L[#L + 1] = ("按鈕 顯示 %s 可見 %s｜type=%s"):format(tostring((btn:IsShown())), tostring((btn:IsVisible())), tostring((btn:GetAttribute("type"))))
    L[#L + 1] = "按鈕巨集文字：" .. tostring((btn:GetAttribute("macrotext"))):gsub("\n", " | ")
  else
    L[#L + 1] = "按鈕：沒有建立"
  end
  L[#L + 1] = ("按下次數 %d｜按下後 0.5 秒內換了目標 %d 次"):format(T.stats.presses, T.stats.targetChanged)
  L[#L + 1] = "被遊戲擋下：" .. tostring(T.blocked or "無") .. "｜最後錯誤：" .. tostring(MG.lastError or "無")
  L[#L + 1] = "目前目標名單：" .. (#names > 0 and table.concat(names, "、") or "無")
  return L
end

function T.Create(bar)
  btn = CreateFrame("Button", "MetroGuideTargetButton", UIParent, "SecureActionButtonTemplate")
  btn:SetSize(20, 20)
  btn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -28, -5)
  btn:SetFrameStrata(bar:GetFrameStrata())
  btn:SetFrameLevel((bar:GetFrameLevel() or 1) + 5)
  btn:RegisterForClicks("AnyUp", "AnyDown")
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("CENTER")
  icon:SetSize(18, 18)
  icon:SetTexture("Interface\\Cursor\\Crosshairs")
  btn:SetAlpha(0.6)
  btn:HookScript("OnEnter", function(self)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("選取任務目標")
    if #names > 0 then GameTooltip:AddLine(table.concat(names, "、"), 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
  end)
  btn:HookScript("OnLeave", function(self) self:SetAlpha(0.6); GameTooltip:Hide() end)
  btn:Hide()
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED", "PLAYER_TARGET_CHANGED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(_, event, name, ...)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
      if name == "MetroGuide" and not T.blocked then
        T.blocked = (...) or "?"
        MG.msg("遊戲擋下了插件的動作（" .. tostring(T.blocked) .. "），請用 /metro probe 回報。")
      end
    elseif event == "PLAYER_TARGET_CHANGED" then
      T.stats.lastTarget = GetTime() -- 只記時間，不讀目標（目標的資料可能是秘密值）
    elseif event == "PLAYER_ENTERING_WORLD" then
      MG.try("目標巨集", T.AutoMacro)
    elseif pending then
      MG.try("目標按鈕", T.Apply)
      MG.try("目標巨集", T.AutoMacro)
    end
  end)
  C.impl.Target = "SecureActionButtonTemplate"
end
