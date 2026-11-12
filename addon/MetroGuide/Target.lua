-- 選取目標按鈕：步驟列上的準星（也可綁快捷鍵）。按一下：
--   1. 把附近（看得到敵方名條的）所有任務怪標上不同的團隊標記（不搶別人已用的標記）
--   2. 選取一隻：巨集依序 /targetexact [noexists] 名字，第一個找得到的勝出（遊戲會挑最近的同名怪）；每按一次換一個名字排第一
-- 選取用安全按鈕＋巨集文字，只能在戰鬥外更新巨集；標記不受保護，在按下後的一般處理裡做。
local _, MG = ...
local C = MG.C
local T = {}
MG.T = T
T.MARKS = { "星星", "圓圈", "鑽石", "三角", "月亮", "方塊", "叉叉", "骷髏" }
local MARK_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 } -- 骷髏、叉叉、方塊、月亮、三角、鑽石、圓圈、星星

BINDING_HEADER_METROGUIDE = "地鐵升級"
_G["BINDING_NAME_CLICK MetroGuideTargetButton:LeftButton"] = "選取任務目標"

local btn, pending, rot, names, key, hinted = nil, false, 0, {}, "", false

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

-- 巨集：先全部用完整名稱（/targetexact），再用部分比對（/target）當備援；
-- 超過 255 字元時先丟備援、再丟排在後面的名字
local LIMIT = 255
local function macro()
  local order, n = {}, #names
  for k = 0, n - 1 do order[#order + 1] = names[(rot + k) % n + 1] end
  local lines, size = { "/cleartarget" }, #"/cleartarget"
  local function add(line)
    if size + 1 + #line > LIMIT then return false end
    lines[#lines + 1] = line
    size = size + 1 + #line
    return true
  end
  for _, name in ipairs(order) do if not add("/targetexact [noexists] " .. name) then break end end
  for _, name in ipairs(order) do if not add("/target [noexists] " .. name) then break end end
  return table.concat(lines, "\n")
end

function T.Apply()
  if not btn then return end
  if InCombatLockdown() then pending = true; return end
  pending = false
  btn:SetAttribute("type", "macro")
  btn:SetAttribute("macrotext", #names > 0 and macro() or "")
  btn:SetShown(T.visible and MetroGuideFrame and MetroGuideFrame:IsShown() or false)
end

function T.Update(state)
  if not btn then return end
  local list = T.Targets(state)
  T.visible = MG.UI.Get("showTarget") and #list > 0
  local k = table.concat(list, "|") .. tostring(T.visible) .. tostring(MetroGuideFrame and MetroGuideFrame:IsShown())
  if k == key and not pending then return end
  if table.concat(list, "|") ~= table.concat(names, "|") then rot = 0 end
  names, key = list, k
  T.Apply()
end

-- 標記：附近名條上的任務怪，各給一個沒人用的標記（從設定的起始標記開始，照骷髏→叉叉→方塊…的順序）
function T.Mark()
  if #names == 0 or not SetRaidTarget then return end
  if IsInRaid and IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return end -- 沒權限就不標
  if not hinted and GetCVar and GetCVar("nameplateShowEnemies") ~= "1" then
    hinted = true
    MG.msg("要開啟「敵方名條」（V 鍵）才標得到附近的任務怪；目前只會標記選到的目標。")
  end
  local want = {}
  for _, n in ipairs(names) do want[n] = true end
  local units, used = {}, {}
  local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
  for _, plate in ipairs(plates) do
    local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if u then units[#units + 1] = u end
  end
  units[#units + 1] = "target"
  for _, u in ipairs(units) do
    local idx = UnitExists(u) and GetRaidTargetIndex(u)
    if idx then used[idx] = true end
  end
  -- 起始標記在順序中的位置
  local start = 1
  for k, m in ipairs(MARK_ORDER) do if m == MG.UI.Get("markIcon") then start = k end end
  local function nextMark()
    for k = 0, #MARK_ORDER - 1 do
      local m = MARK_ORDER[(start - 1 + k) % #MARK_ORDER + 1]
      if not used[m] then used[m] = true; return m end
    end
  end
  local done = {}
  for _, u in ipairs(units) do
    if UnitExists(u) and want[UnitName(u)] and not UnitIsDead(u) and not (UnitIsTapDenied and UnitIsTapDenied(u))
      and not GetRaidTargetIndex(u) and not done[UnitGUID(u) or u] then
      local m = nextMark()
      if not m then break end
      SetRaidTarget(u, m)
      done[UnitGUID(u) or u] = true
    end
  end
end

-- 「按下就施放」設定開著時，動作發生在按下；否則在放開
local function keyDown() return GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") or false end
local lastAct = 0
function T.Acts(down)
  if (down and true or false) ~= keyDown() then return false end
  local now = GetTime()
  if now - lastAct < 0.25 then return false end
  lastAct = now
  return true
end
T.stats = { pre = 0, preDown = 0, post = 0, postDown = 0, acted = 0 }

-- 動作條巨集：/click 這顆按鈕。按下就施放開著時要加第三個參數，讓 /click 送「按下」
local MACRO, OLD_MACRO = "任務目標", "地鐵目標"
local function macroBody() return "/click MetroGuideTargetButton LeftButton 1\n/click MetroGuideTargetButton LeftButton" end
-- 舊名「地鐵目標」的巨集原地改名（保留它在快捷列上的位置），不另建第二個
local function renameOld()
  local old = GetMacroIndexByName(OLD_MACRO)
  if old and old > 0 and (GetMacroIndexByName(MACRO) or 0) == 0 then
    EditMacro(old, MACRO, "Ability_Hunter_SniperShot", macroBody())
  end
end
function T.MakeMacro()
  if InCombatLockdown() then MG.msg("戰鬥中不能建立巨集，脫離戰鬥再試。"); return end
  renameOld()
  local index = GetMacroIndexByName(MACRO)
  if index and index > 0 then
    EditMacro(index, MACRO, "Ability_Hunter_SniperShot", macroBody())
  else
    local account = GetNumMacros()
    if account >= (MAX_ACCOUNT_MACROS or 36) then MG.msg("帳號巨集已滿，請先刪掉一個再按「建立巨集」。"); return end
    index = CreateMacro(MACRO, "Ability_Hunter_SniperShot", macroBody(), nil)
  end
  if index and index > 0 then
    PickupMacro(index)
    MG.msg("巨集「" .. MACRO .. "」已拿在滑鼠上，放到動作條即可。")
  end
end
-- 遊戲的「按下就施放」設定改了：已有的巨集跟著改
function T.SyncMacro()
  if InCombatLockdown() or not GetMacroIndexByName then return end
  renameOld()
  local index = GetMacroIndexByName and GetMacroIndexByName(MACRO)
  if index and index > 0 then EditMacro(index, MACRO, "Ability_Hunter_SniperShot", macroBody()) end
end

-- 自動建立：設定開著、還沒有這個巨集、帳號巨集還有空位 → 默默建立（不拿到滑鼠上），第一次在聊天框說一聲
local autoPending = false
function T.AutoMacro()
  if not GetMacroIndexByName then return end
  if InCombatLockdown() then autoPending = true; return end
  autoPending = false
  renameOld() -- 改名不受「自動建立」設定影響
  if not MG.UI.Get("autoMacro") then return end
  local index = GetMacroIndexByName(MACRO)
  if index and index > 0 then T.SyncMacro(); return end
  if GetNumMacros() >= (MAX_ACCOUNT_MACROS or 36) then return end
  index = CreateMacro(MACRO, "Ability_Hunter_SniperShot", macroBody(), nil)
  if index and index > 0 and not MetroGuideDB.macroNoted then
    MetroGuideDB.macroNoted = true
    MG.msg("已建立巨集『" .. MACRO .. "』，可在巨集視窗（/macro）拖到快捷列")
  end
end

function T.Diag()
  local L = {}
  local index = GetMacroIndexByName and GetMacroIndexByName(MACRO) or 0
  local body = index > 0 and select(3, GetMacroInfo(index)) or nil
  local old = GetMacroIndexByName and GetMacroIndexByName(OLD_MACRO) or 0
  L[#L + 1] = "巨集「" .. MACRO .. "」格位 " .. index .. "（舊名格位 " .. old .. "）內容：" .. (body and body:gsub("\n", " | ") or "無")
  L[#L + 1] = "ActionButtonUseKeyDown：" .. tostring(GetCVar and GetCVar("ActionButtonUseKeyDown"))
  if btn then
    L[#L + 1] = ("按鈕 %s 顯示 %s 可見 %s｜type=%s｜註冊點擊 AnyUp+AnyDown"):format(tostring((btn:GetName())), tostring((btn:IsShown())), tostring((btn:IsVisible())),
      tostring((btn:GetAttribute("type"))))
    L[#L + 1] = "巨集文字：" .. tostring((btn:GetAttribute("macrotext"))):gsub("\n", " | ")
  else
    L[#L + 1] = "按鈕：沒有建立"
  end
  L[#L + 1] = ("點擊次數 PreClick %d（按下 %d）PostClick %d（按下 %d）實際處理 %d"):format(T.stats.pre, T.stats.preDown, T.stats.post, T.stats.postDown, T.stats.acted)
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
  -- 放開時（巨集已選好目標）：標記附近任務怪＋目標，再輪換下次優先的名字
  btn:HookScript("PreClick", function(_, _, down)
    T.stats.pre = T.stats.pre + 1
    if down then T.stats.preDown = T.stats.preDown + 1 end
  end)
  btn:HookScript("PostClick", function(_, _, down)
    T.stats.post = T.stats.post + 1
    if down then T.stats.postDown = T.stats.postDown + 1 end
    if not T.Acts(down) then return end -- 一次按鍵只處理一次（按下或放開，看遊戲設定）
    T.stats.acted = T.stats.acted + 1
    MG.try("標記", T.Mark)
    rot = rot + 1
    T.Apply()
  end)
  btn:Hide()
  local f = CreateFrame("Frame")
  pcall(f.RegisterEvent, f, "PLAYER_REGEN_ENABLED")
  pcall(f.RegisterEvent, f, "CVAR_UPDATE")
  pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_ENTERING_WORLD" then
      MG.try("目標巨集", T.AutoMacro)
    elseif event == "CVAR_UPDATE" then
      if name == "ActionButtonUseKeyDown" or name == "ACTION_BUTTON_USE_KEY_DOWN" then MG.try("目標巨集", T.SyncMacro) end
    else
      if pending then MG.try("目標按鈕", T.Apply) end
      if autoPending then MG.try("目標巨集", T.AutoMacro) end
    end
  end)
  C.impl.Target = "SecureActionButtonTemplate"
end
