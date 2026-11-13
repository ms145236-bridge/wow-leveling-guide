-- 任務物品按鈕：目前步驟（含附近一起做的步驟）的任務若有可使用的物品，在步驟列旁顯示可點的物品按鈕（最多 3 個）。
-- 來源：任務日誌的特殊物品（GetQuestLogSpecialItemInfo），以及建置時從 QuestieDB 帶入的任務物品（背包裡有才顯示）。
-- 按鈕是安全按鈕（type = item），屬性與顯示只在戰鬥外改；動作條巨集「任務物品」內容是 /use item:ID，也只在戰鬥外改寫。
local _, MG = ...
local C = MG.C
local L = MG.L
local I = {}
MG.I = I

_G["BINDING_NAME_CLICK MetroGuideItemButton1:LeftButton"] = MG.gameCJK and "使用任務物品" or "Use quest item"

local MAX = 3
local buttons, pending, items, key = {}, false, {}, ""
I.count = 0

local function itemCount(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
  return GetItemCount and GetItemCount(id) or 0
end
local function itemIcon(id)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
  return GetItemIcon and GetItemIcon(id)
end

-- 一個任務可用的物品 ID 清單
local function questItems(q, out, seen)
  if not (q and C.IsOnQuest(q)) then return end
  local idx = C.LogIndex(q)
  if idx and GetQuestLogSpecialItemInfo then
    local link = MG.try("任務物品", GetQuestLogSpecialItemInfo, idx)
    local id = link and tonumber(tostring(link):match("item:(%d+)"))
    if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
  end
  for _, id in ipairs((MG.Route.quests[q] or {}).items or {}) do
    -- 背包裡有、而且是可以「使用」的物品（信件之類不算）
    local spell = (C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(id)) or (GetItemSpell and GetItemSpell(id))
    if not seen[id] and spell and itemCount(id) > 0 then seen[id] = true; out[#out + 1] = id end
  end
end

function I.Items(state)
  local out, seen = {}, {}
  local step = state and state.cur and state.steps[state.cur]
  if step and step.s.q then questItems(step.s.q, out, seen) end
  for _, i in ipairs(state and state.group or {}) do questItems(state.steps[i].s.q, out, seen) end
  while #out > MAX do table.remove(out) end
  return out
end

-- 步驟列內：圖示大小跟著字體；外側：自訂大小，直排在步驟列左／右
function I.InsideWidth()
  if MG.UI.Get("itemPos") ~= 1 or not MG.UI.Get("showItem") then return 0 end
  return I.count * (MG.UI.Get("fontSize") + 7)
end

local function layout(bar)
  local pos, inside = MG.UI.Get("itemPos"), MG.UI.Get("itemPos") == 1
  local size = inside and (MG.UI.Get("fontSize") + 5) or MG.UI.Get("itemSize")
  for k, b in ipairs(buttons) do
    b:SetSize(size, size)
    b:ClearAllPoints()
    if inside then
      local gapRight = 32 + ((MG.T and MG.T.visible) and 22 or 0)
      b:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -gapRight - (k - 1) * (size + 2), -10)
    elseif pos == 2 then
      b:SetPoint("TOPRIGHT", bar, "TOPLEFT", -4, -(k - 1) * (size + 4))
    else
      b:SetPoint("TOPLEFT", bar, "TOPRIGHT", 4, -(k - 1) * (size + 4))
    end
  end
end

-- 動作條巨集「任務物品」：/use 第一個物品
local MACRO, ICON = MG.gameCJK and "任務物品" or "Quest Item", "INV_Misc_Bag_08" -- 巨集名跟客戶端語言
local lastBody
local triedCreate = false
local function macroBody()
  return items[1] and ("/use item:" .. items[1]) or ("/run ShengLv_Msg(\"" .. L["目前步驟沒有任務物品"] .. "\")")
end
function I.SyncMacro()
  if not GetMacroIndexByName or InCombatLockdown() or not MG.UI.Get("itemMacro") then return end
  local index = GetMacroIndexByName(MACRO)
  local body = macroBody()
  if index and index > 0 then
    if body ~= lastBody then EditMacro(index, MACRO, ICON, body); lastBody = body end
  elseif not triedCreate and GetNumMacros() < (MAX_ACCOUNT_MACROS or 36) then
    CreateMacro(MACRO, ICON, body, nil)
    lastBody = body
  end
  triedCreate = true
end

function I.Apply()
  if #buttons == 0 then return end
  if InCombatLockdown() then pending = true; return end
  pending = false
  layout(I.bar)
  local show = MG.UI.Get("showItem") and MetroGuideFrame and MetroGuideFrame:IsShown()
  for k, b in ipairs(buttons) do
    local id = items[k]
    b.itemID = id
    b:SetAttribute("type", "item")
    b:SetAttribute("item", id and ("item:" .. id) or nil)
    if id then
      b.icon:SetTexture(itemIcon(id))
      local n = itemCount(id)
      b.count:SetText(n > 1 and n or "")
    end
    b:SetShown(show and id ~= nil or false)
  end
  I.count = show and #items or 0
  MG.try("任務物品巨集", I.SyncMacro)
end

function I.Update(state)
  if #buttons == 0 then return end
  local list = I.Items(state)
  local k = table.concat(list, ",") .. tostring(MG.UI.Get("showItem")) .. MG.UI.Get("itemPos") .. MG.UI.Get("itemSize") .. MG.UI.Get("fontSize")
    .. tostring(MetroGuideFrame and MetroGuideFrame:IsShown()) .. tostring(MG.T and MG.T.visible)
  -- 冷卻與數量每次都更新（不受保護）
  for i, b in ipairs(buttons) do
    local id = list[i]
    if id and b.cd and C_Container and C_Container.GetItemCooldown then
      local start, dur = C_Container.GetItemCooldown(id)
      if start and dur then b.cd:SetCooldown(start, dur) end
    end
  end
  if k == key and not pending then return end
  items, key = list, k
  I.Apply()
end

function I.Create(bar)
  I.bar = bar
  for k = 1, MAX do
    local b = CreateFrame("Button", "MetroGuideItemButton" .. k, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetFrameStrata(bar:GetFrameStrata())
    b:SetFrameLevel((bar:GetFrameLevel() or 1) + 20)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT or (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if ok and cd then cd:SetAllPoints(); b.cd = cd end
    b:HookScript("OnEnter", function(self)
      if not self.itemID then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
      GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    buttons[k] = b
  end
  local f = CreateFrame("Frame")
  pcall(f.RegisterEvent, f, "PLAYER_REGEN_ENABLED")
  pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
  f:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then key = ""; MG.Refresh() elseif pending then MG.try("任務物品", I.Apply) end
  end)
  C.impl.Item = GetQuestLogSpecialItemInfo and "GetQuestLogSpecialItemInfo" or "只有 QuestieDB 任務物品"
end

function I.Diag()
  local out = {}
  out[#out + 1] = "GetQuestLogSpecialItemInfo: " .. tostring(GetQuestLogSpecialItemInfo ~= nil) .. L["｜目前物品："] .. (#items > 0 and table.concat(items, ", ") or L["無"])
  local shown = {}
  for k, b in ipairs(buttons) do shown[#shown + 1] = k .. "=" .. tostring((b:IsShown())) .. "/" .. tostring((b:GetAttribute("item"))) end
  out[#out + 1] = L["按鈕："] .. table.concat(shown, "  ")
  local index = GetMacroIndexByName and GetMacroIndexByName(MACRO) or 0
  local body = index > 0 and GetMacroInfo and select(3, GetMacroInfo(index)) or nil
  out[#out + 1] = L["巨集「%s」格位 %d："]:format(MACRO, index) .. tostring(body)
  return out
end
