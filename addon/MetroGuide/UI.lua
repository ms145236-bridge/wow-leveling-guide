-- 介面：目前步驟列、建議鈕、展開面板（步驟／路線）、右鍵選單、檢查報告視窗。只讀引擎結果，操作只送意圖。
local _, MG = ...
local E, C = MG.E, MG.C
local UI = {}
MG.UI = UI

local FONT = STANDARD_TEXT_FONT or "Fonts\\bLEI00D.ttf"
local BG = { 0.055, 0.059, 0.071, 0.88 }
local EDGE = { 0.165, 0.176, 0.204 }
local TEXT = { 0.91, 0.894, 0.847 }
local DIM = { 0.545, 0.561, 0.596 }
local FAINT = { 0.333, 0.349, 0.384 }
local GOLD = { 0.851, 0.698, 0.373 }
local AMBER = { 0.878, 0.569, 0.227 }
local GREEN = { 0.435, 0.749, 0.451 }
local ROW_H, MAX_ROWS = 20, 30

-- 設定表：設定頁、右鍵選單、套用都讀這裡。acct＝帳號共用（其餘每角色）。預設值＝原本的樣子。
local SPEC = {
  { section = "步驟列" },
  { key = "barScale", label = "縮放", min = 70, max = 150, step = 5, def = 100, unit = "%" },
  { key = "barWidth", label = "寬度", min = 240, max = 480, step = 10, def = 300 },
  { key = "barAlpha", label = "背景透明度", min = 0, max = 100, step = 5, def = 88, unit = "%" },
  { key = "barOpacity", label = "整體透明度（含文字）", min = 0, max = 100, step = 5, def = 100, unit = "%" },
  { key = "fadeOn", label = "滑鼠不在上面或戰鬥中時淡出", def = false },
  { key = "fadeAlpha", label = "淡出時透明度", min = 0, max = 100, step = 5, def = 40, unit = "%" },
  { key = "fontSize", label = "字體大小", min = 11, max = 20, step = 1, def = 15 },
  { key = "objRows", label = "最多顯示目標行數", min = 1, max = 5, step = 1, def = 5 },
  { key = "groupOn", label = "同時顯示附近任務", def = true },
  { key = "groupMax", label = "最多同時顯示", min = 1, max = 5, step = 1, def = 3 },
  { key = "groupDist", label = "附近距離（地圖 %）", min = 2, max = 20, step = 1, def = 8 },
  { key = "showCount", label = "顯示剩餘步數", def = false },
  { key = "showLevel", label = "顯示任務等級", def = false },
  { key = "locked", label = "鎖定位置", def = false, menu = true },
  { button = "重設位置", run = function() MG.db.pos = nil end },
  { section = "提示框" },
  { key = "tipScale", label = "大小", min = 70, max = 150, step = 5, def = 100, unit = "%", acct = true, tip = true },
  { key = "tipX", label = "水平位置", min = -300, max = 300, step = 5, def = 0, acct = true, tip = true },
  { key = "tipY", label = "垂直位置", min = -300, max = 300, step = 5, def = 0, acct = true, tip = true },
  { key = "tipAlpha", label = "背景透明度", min = 0, max = 100, step = 5, def = 100, unit = "%", acct = true, tip = true },
  { key = "tipDesc", label = "顯示說明行", def = true, acct = true, tip = true },
  { section = "展開清單" },
  { key = "listAlpha", label = "背景透明度", min = 0, max = 100, step = 5, def = 88, unit = "%" },
  { key = "listRows", label = "高度（行數）", min = 8, max = MAX_ROWS, step = 1, def = 18 },
  { key = "showDone", label = "顯示已完成步驟", def = true },
  { key = "showNum", label = "顯示步驟編號", def = true },
  { section = "地圖標點" },
  { key = "pinSize", label = "世界地圖標點大小", min = 14, max = 40, step = 1, def = 24 },
  { key = "miniPinSize", label = "小地圖標點大小", min = 10, max = 30, step = 1, def = 15 },
  { key = "miniSteps", label = "小地圖顯示幾步", min = 0, max = 5, step = 1, def = 3 },
  { key = "pinAlpha", label = "標點透明度", min = 30, max = 100, step = 5, def = 100, unit = "%" },
  { key = "pinMergeX", label = "合併距離（標點大小倍數）", min = 0, max = 3, step = 0.1, def = 1.1 },
  { section = "導航與任務" },
  { key = "arrow", label = "箭頭與地圖標點", def = true, menu = true },
  { key = "auto", label = "自動接交任務", def = true, menu = true },
  { key = "optional", label = "帶上可跳過的任務", def = false, menu = true },
  { start = true },
  { key = "showTarget", label = "顯示目標按鈕", def = true },
  { key = "markOn", label = "選取時標上團隊標記", def = true },
  { key = "markIcon", label = "標記圖示", def = 1, choices = { "星星", "圓圈", "鑽石", "三角", "月亮", "方塊", "叉叉", "骷髏" } },
  { key = "dPre", label = "順路接副本前置", def = true },
  { key = "dungeonHint", label = "提示副本", def = true },
  { key = "dungeonOnly", label = "副本中只顯示副本任務", def = true, hint = "在副本裡只列出這個副本的任務（一次全列），不顯示主線步驟、箭頭和地圖標點；對不到副本或沒有任務時整個隱藏，出副本後恢復。" },
  { key = "showItem", label = "顯示任務物品按鈕", def = true },
  { key = "itemPos", label = "任務物品位置", def = 1, choices = { "步驟列內", "左側", "右側" } },
  { key = "itemSize", label = "任務物品大小（左右側）", min = 20, max = 48, step = 2, def = 32 },
  { key = "itemMacro", label = "自動建立任務物品巨集", def = true, hint = "建立帳號巨集「任務物品」，內容自動改成使用目前步驟的任務物品（戰鬥中等脫離戰鬥再改）。" },
  { key = "minimap", label = "顯示小地圖按鈕", def = true },
  { key = "miniBtnAlpha", label = "小地圖按鈕透明度", min = 0, max = 100, step = 5, def = 100, unit = "%" },
  { key = "autoMacro", label = "自動建立目標巨集", def = true, hint = "登入時若沒有「任務目標」巨集就自動建立（帳號巨集有空位時）。刪掉後下次登入會再建立；關掉這項就不會。" },
  { button = "建立巨集", run = function() MG.T.MakeMacro() end },
  { button = "重新對齊", run = function() E.Realign() end },
  { section = "" },
  { button = "全部重設為預設", all = true },
}
local SPEC_BY = {}
for _, sp in ipairs(SPEC) do if sp.key then SPEC_BY[sp.key] = sp end end
local function store(sp) return sp.acct and MetroGuideDB or MG.db end
function UI.Get(key)
  local sp = SPEC_BY[key]
  local v = store(sp)[key]
  if v == nil then return sp.def end
  return v
end
function UI.Set(key, v) store(SPEC_BY[key])[key] = v end
function UI.Reset(key) UI.Set(key, nil) end
-- 存檔只留玩家改過的值（沒改過＝nil＝用目前的預設，之後改預設會跟著變）。
-- 設定版本 2：清掉舊版寫進去的預設值；「顯示剩餘步數」「顯示任務等級」一律回到新預設（關）。
local SETTINGS_VERSION = 2
function UI.InitDefaults()
  for _, db in ipairs({ MG.db, MetroGuideDB }) do
    if (db.settingsV or 0) < SETTINGS_VERSION then
      for _, sp in ipairs(SPEC) do
        if sp.key and store(sp) == db and db[sp.key] == sp.def then db[sp.key] = nil end
      end
      if db == MG.db then db.showCount, db.showLevel, db.scale = nil, nil, nil end
      db.settingsV = SETTINGS_VERSION
    end
  end
end
function UI.Rows() return UI.Get("listRows") end

local function text(parent, size, color, justify)
  local s = parent:CreateFontString(nil, "OVERLAY")
  s:SetFont(FONT, size, "")
  s:SetTextColor(color[1], color[2], color[3])
  s:SetJustifyH(justify or "LEFT")
  s:SetWordWrap(false)
  return s
end
local function paint(s, color) s:SetTextColor(color[1], color[2], color[3]) end

local function box(f, edge)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
  edge = edge or EDGE
  local function line(p1, p2, w, h)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(edge[1], edge[2], edge[3], 1)
    t:SetPoint(p1); t:SetPoint(p2)
    if w then t:SetWidth(w) else t:SetHeight(h) end
  end
  line("TOPLEFT", "TOPRIGHT", nil, 1); line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  line("TOPLEFT", "BOTTOMLEFT", 1); line("TOPRIGHT", "BOTTOMRIGHT", 1)
  return bg
end

local root, bar, chip, panel, menu, report, dhint
local rows, items = {}, {}
local scroll, tab, missOpen, lastCurKey = 0, "steps", false, nil
local state -- 最近一次 Render 的引擎結果

local BRONZE = { 0.427, 0.353, 0.184 }
-- state：nil＝空、"check"＝勾（color 指定顏色）、"dash"＝短線（手動未完成）
function UI.Checkbox(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  box(b, BRONZE)
  b.check = b:CreateTexture(nil, "ARTWORK")
  b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b.check:SetDesaturated(true)
  b.check:SetPoint("CENTER", 1, 0)
  b.check:SetSize(size + 4, size + 4)
  b.dash = b:CreateTexture(nil, "ARTWORK")
  b.dash:SetPoint("CENTER")
  b.dash:SetSize(size - 6, 2)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
  hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.15)
  function b:SetState(st, color)
    color = color or GOLD
    self.check:SetShown(st == "check")
    self.dash:SetShown(st == "dash")
    self.check:SetVertexColor(color[1], color[2], color[3])
    self.dash:SetColorTexture(color[1], color[2], color[3], 1)
  end
  b:SetState(nil)
  return b
end

-- 插件風格按鈕：深底、銅金框、金字
local function goldButton(parent, label, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 22)
  box(b, BRONZE)
  b.label = text(b, 13, GOLD, "CENTER")
  b.label:SetPoint("CENTER", 0, 0)
  b.label:SetText(label)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
  hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
  return b
end

local function savePos()
  MG.db.pos = { x = root:GetLeft(), y = root:GetTop() }
end
-- 安全按鈕（目標、任務物品）不能錨在會變大小的步驟列上，否則戰鬥中步驟列一變高就會被遊戲擋。
-- 改錨在這個固定底座：掛在 UIParent，戰鬥外才跟著步驟列的位置、縮放、寬度對齊。
local holder
function UI.Holder()
  if not holder then
    holder = CreateFrame("Frame", "MetroGuideSecureHolder", UIParent)
    holder:SetSize(300, 44)
  end
  return holder
end
function UI.PlaceHolder()
  if not holder or not root then return end
  if InCombatLockdown() then UI.holderPending = true; return end
  UI.holderPending = false
  holder:SetScale(root:GetScale())
  holder:SetFrameStrata(root:GetFrameStrata())
  holder:SetWidth(UI.Get("barWidth"))
  holder:ClearAllPoints()
  local l, t = root:GetLeft(), root:GetTop()
  if l and t then
    holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
  else
    -- 剛載入還沒排版：先放預設位置，下一格再對齊（不要錨在步驟列上）
    holder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -240)
    UI.holderTries = (UI.holderTries or 0) + 1
    if C_Timer and C_Timer.After and UI.holderTries <= 10 then C_Timer.After(0.2, UI.PlaceHolder) end
  end
end

function UI.ApplySettings()
  if InCombatLockdown() then UI.settingsPending = true end -- 位置、縮放之後再對齊底座
  root:SetScale(UI.Get("barScale") / 100)
  local w, a, fsz = UI.Get("barWidth"), UI.Get("barAlpha") / 100, UI.Get("fontSize")
  bar:SetWidth(w)
  bar.bg:SetColorTexture(BG[1], BG[2], BG[3], a)
  panel.bg:SetColorTexture(BG[1], BG[2], BG[3], UI.Get("listAlpha") / 100)
  bar.title:SetFont(FONT, fsz, "")
  for _, f in ipairs({ bar.l2, bar.l3, unpack(bar.objs) }) do f:SetFont(FONT, fsz - 2, "") end
  panel:SetHeight(34 + UI.Rows() * ROW_H + 8)
  root:ClearAllPoints()
  local p = MG.db.pos
  if p and p.x and p.y then root:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
  else root:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -240) end
  root:SetShown(MG.db.shown ~= false)
  if UI.PlaceMinimap then UI.PlaceMinimap() end
  if UI.RefreshOptions then UI.RefreshOptions() end
  UI.PlaceHolder()
end

-- ── 設定（右鍵選單、設定頁共用） ─────────────────────────────────────────
local function settingLabel(sp) return (UI.Get(sp.key) and "√ " or "   ") .. sp.label end
local function toggleSetting(sp) UI.Set(sp.key, not UI.Get(sp.key)) end

local function openMenu(anchor)
  if menu:IsShown() then menu:Hide(); return end
  local entries = {}
  local cur = state and state.cur and state.steps[state.cur]
  if cur then entries[#entries + 1] = { "略過這步", function() E.ToggleSkip(cur.key) end } end
  if cur and cur.s.share == 1 and cur.s.q and C.IsOnQuest(cur.s.q) and IsInGroup and IsInGroup() then
    entries[#entries + 1] = { "分享這個任務", function() C.ShareQuest(cur.s.q) end }
  end
  entries[#entries + 1] = { "重新對齊", function() E.Realign() end }
  for _, sp in ipairs(SPEC) do
    if sp.menu then entries[#entries + 1] = { settingLabel(sp), function() toggleSetting(sp) end } end
  end
  entries[#entries + 1] = { "   設定頁", function() UI.OpenOptions() end }
  for i, e in ipairs(entries) do
    local b = menu.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetSize(150, 22)
      b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 22)
      b.label = text(b, 13, TEXT)
      b.label:SetPoint("LEFT", 6, 0)
      local hl = b:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
      menu.buttons[i] = b
    end
    b.label:SetText(e[1])
    b:SetScript("OnClick", function() menu:Hide(); e[2](); UI.ApplySettings(); MG.Refresh(true) end)
    b:Show()
  end
  for i = #entries + 1, #menu.buttons do menu.buttons[i]:Hide() end
  menu:SetHeight(12 + #entries * 22)
  menu:ClearAllPoints()
  if anchor == bar then menu:SetPoint("TOPLEFT", bar, "TOPRIGHT", 4, 0)
  else menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0) end
  menu:Show()
end

-- ── 步驟提示（步驟列、清單、地圖標點共用） ────────────────────────────────
-- 提示框：大小（只在我們顯示時改，關閉時還原）
local tipScaled, tipOld
local function tipScale()
  if not tipScaled then
    if not tipOld then GameTooltip:HookScript("OnHide", function() if tipScaled then GameTooltip:SetScale(tipOld); C.TooltipAlpha(GameTooltip, nil); tipScaled = false end end) end
    tipOld = GameTooltip:GetScale()
  end
  GameTooltip:SetScale((tipOld or 1) * UI.Get("tipScale") / 100)
  C.TooltipAlpha(GameTooltip, UI.Get("tipAlpha") / 100)
  tipScaled = true
end

-- side = true（步驟列、清單）：貼著框架左或右邊（依螢幕位置；靠底部放上方），再加設定的偏移；地圖標點貼著標點
function UI.StepTooltip(owner, s, prefix, side)
  if side then
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    local dx, dy = UI.Get("tipX"), UI.Get("tipY")
    local right = (owner:GetCenter() or 0) > (UIParent:GetWidth() or 0) / 2
    if (owner:GetBottom() or 999) < 180 then
      GameTooltip:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", owner, right and "TOPRIGHT" or "TOPLEFT", dx, 4 + dy)
    elseif right then
      GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4 + dx, dy)
    else
      GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4 + dx, dy)
    end
  else
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  end
  tipScale()
  GameTooltip:AddLine((prefix or "") .. (E.VERB[s.t] or "") .. " " .. E.Title(s), GOLD[1], GOLD[2], GOLD[3])
  if s.npc then GameTooltip:AddLine(s.npc, TEXT[1], TEXT[2], TEXT[3]) end
  if s.t == "travel" then GameTooltip:AddLine(s.text, TEXT[1], TEXT[2], TEXT[3], true) end
  if s.q then
    local _, objText = C.QuestText(s.q)
    local info = MG.Route.quests[s.q]
    local body = objText and objText ~= "" and objText or (info and info.d) or s.hint
    if body then GameTooltip:AddLine(body, DIM[1], DIM[2], DIM[3], true) end
    for _, o in ipairs(C.Objectives(s.q) or {}) do
      if o.need then
        local c = o.done and GREEN or TEXT
        GameTooltip:AddLine(o.text .. "  " .. (o.have or 0) .. "/" .. o.need, c[1], c[2], c[3])
      end
    end
  end
  if s.pickLv or s.recLv or s.share then
    local bits = {}
    if s.pickLv then bits[#bits + 1] = "接取等級 " .. s.pickLv end
    if s.recLv then bits[#bits + 1] = "建議等級 " .. s.recLv end
    if s.share == 1 then bits[#bits + 1] = "可共享" elseif s.share == 0 then bits[#bits + 1] = "不可共享" elseif s.share == 2 then bits[#bits + 1] = "共享未確認" end
    GameTooltip:AddLine(table.concat(bits, "   "), DIM[1], DIM[2], DIM[3])
  end
  if s.preText then GameTooltip:AddLine("前置：" .. s.preText, DIM[1], DIM[2], DIM[3], true) end
  if s.desc and UI.Get("tipDesc") then GameTooltip:AddLine("說明：" .. s.desc, AMBER[1], AMBER[2], AMBER[3], true) end
  GameTooltip:Show()
end

-- 起點路線切換
local function setStart(key)
  MG.db.start = key
  MG.db.station = nil
  wipe(MG.db.pin)
  E.Build()
end
local function startLabel()
  local key = E.StartKey()
  for _, s in ipairs(E.Starts()) do if s.key == key then return s.name end end
  return "無"
end
local function cycleStart()
  local list, key = E.Starts(), E.StartKey()
  for i, s in ipairs(list) do
    if s.key == key then setStart(list[i % #list + 1].key); return end
  end
end

-- 建置時切好的句子（{文字, 條件}），只留適用本角色的（職業／種族）
function UI.Sentences(list, fallback)
  local out = {}
  if list then
    for _, x in ipairs(list) do if E.Applies(x[2]) then out[#out + 1] = x[1] end end
    return out
  end
  return fallback or {}
end

-- 段落：依「；」「。」切成條列，每條一段（由字串自己換行）
local function bullets(t)
  local out, from = {}, 1
  t = t .. "；"
  while true do
    local i, j = t:find("；", from, true)
    local k, l = t:find("。", from, true)
    if k and (not i or k < i) then i, j = k, l end
    if not i then break end
    local piece = t:sub(from, i - 1):gsub("^%s+", ""):gsub("%s+$", "")
    if piece ~= "" then out[#out + 1] = piece end
    from = j + 1
  end
  return out
end

-- ── 面板 ────────────────────────────────────────────────────────────────────
local function buildItems()
  wipe(items)
  if not state then return end
  if tab == "steps" then
    if #state.missed > 0 then
      items[#items + 1] = { kind = "misshead" }
      if missOpen then
        for _, m in ipairs(state.missed) do items[#items + 1] = { kind = "miss", m = m } end
      end
    end
    for i, step in ipairs(state.steps) do
      local hideDone = not UI.Get("showDone") and state.done[i] and i ~= state.cur
      if (not state.na[i] or MG.db.skip[step.key] or step.defer) and not hideDone then items[#items + 1] = { kind = "step", i = i, step = step } end
    end
  elseif tab == "dg" then
    -- 副本分頁 v2（DUNGEON-TAB-SPEC.md）
    UI.dPhase, UI.dChain, UI.dMore = UI.dPhase or {}, UI.dChain or {}, UI.dMore or {}
    for _, d in ipairs(E.dungeons) do
      items[#items + 1] = { kind = "dg", d = d }
      if UI.dOpen == d.id then
        local inside = false
        if state and state.instance then
          local _, all = E.DungeonByInstance(GetInstanceInfo and select(8, GetInstanceInfo()))
          for _, x in ipairs(all or {}) do if x == d then inside = true end end
        end
        local nx = E.DungeonNext(d, inside)
        if nx then items[#items + 1] = { kind = "dnext", d = d, nx = nx } end
        local phase = UI.dPhase[d.id] or (nx and (nx.kind == "ent" and "in" or (nx.step and nx.step.s.ph))) or "pre"
        items[#items + 1] = { kind = "dphase", d = d, phase = phase }
        if phase == "pre" then
          for _, t in ipairs(E.DungeonTargets(d)) do
            items[#items + 1] = { kind = "dq", d = d, t = t }
            if UI.dChain[t.q] and #t.chain > 0 then
              -- 鏈：一個任務一列，連續同名合併
              local k, nextSet = 1, false
              while k <= #t.chain do
                local step = t.chain[k]
                local name = E.Title({ q = step.s.q, t = "accept" })
                local n = 1
                while t.chain[k + n] and E.Title({ q = t.chain[k + n].s.q, t = "accept" }) == name do n = n + 1 end
                local group = { unpack(t.chain, k, k + n - 1) }
                local all = true
                for _, g in ipairs(group) do if not E.Turned(g.s.q) then all = false end end
                items[#items + 1] = { kind = "dch", d = d, steps = group, name = name, count = n, isNext = not all and not nextSet }
                if not all then nextSet = true end
                k = k + n
              end
            end
          end
        else
          local seen = {}
          for _, step in ipairs(d.list) do
            local s = step.s
            if s.ph == phase and s.t ~= "travel" and s.t ~= "need" and E.Applies(s.when) then
              local id = s.q or step.key
              if not seen[id] then seen[id] = true; items[#items + 1] = { kind = "dqi", d = d, q = s.q, phase = phase, first = step } end
            end
          end
        end
        if not (nx and nx.kind == "ent") and d.entrance then items[#items + 1] = { kind = "dent", d = d } end
        items[#items + 1] = { kind = "dact", d = d }
        if UI.dMore[d.id] then
          for _, t in ipairs(UI.Sentences(d.pickupS, bullets(d.pickup or ""))) do items[#items + 1] = { kind = "dtext", text = "‧ " .. t } end
          for _, tip in ipairs(d.tips or {}) do
            if tip.k == "取捨" then
              local list = UI.Sentences(tip.s, { tip.text })
              if #list > 0 then items[#items + 1] = { kind = "dtext", text = "‧ " .. table.concat(list, "，") } end
            elseif tip.k ~= "交通" then
              for _, t in ipairs(UI.Sentences(tip.s, bullets(tip.text))) do items[#items + 1] = { kind = "dtext", text = "‧ " .. t } end
            end
          end
        end
      end
    end
  else
    local key = E.StartKey()
    for _, s in ipairs(E.Starts()) do items[#items + 1] = { kind = "start", s = s, on = s.key == key } end
    for _, st in ipairs(E.stations) do items[#items + 1] = { kind = "station", st = st } end
  end
end

local function fillRow(row, it)
  row.it = it
  row.cur:Hide(); row.strip:Hide()
  row.strip:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  paint(row.name, TEXT); paint(row.verb, GOLD); paint(row.ck, GREEN); paint(row.prog, DIM)
  row.ck:SetText(""); row.verb:SetText(""); row.prog:SetText(""); row.no:SetText("")
  row.para:Hide(); row:SetHeight(ROW_H)
  row.bgx:Hide(); row.arrow:Hide(); row.lvt:Hide(); row.sub:Hide(); row.icon:Hide()
  for _, b in ipairs(row.tabs) do b:Hide() end
  for _, b in ipairs(row.acts) do b:Hide() end
  row.name:SetFont(FONT, 13, "")
  local top = it.kind == "dnext"
  local function at(f, x, w)
    f:ClearAllPoints()
    if top then f:SetPoint("TOPLEFT", x, -6) else f:SetPoint("LEFT", x, 0) end
    if w then f:SetWidth(w) end
  end
  at(row.ck, 8, 14); at(row.box, 9); at(row.no, 24, 20); at(row.verb, 48, 18)
  row.prog:ClearAllPoints()
  if top then row.prog:SetPoint("TOPRIGHT", -12, -7) else row.prog:SetPoint("RIGHT", -12, 0) end
  local PROG_W = { step = 64, miss = 1, misshead = 1, station = 92, start = 1, dg = 62, dtext = 1, dhead = 1, dnext = 84, dphase = 1, dq = 96, dch = 90, dqi = 50, dent = 110, dact = 1 }
  row.prog:SetWidth(PROG_W[it.kind] or 64)
  local NAME_X = { dtext = 28, dhead = 28, dg = 26, dq = 28, dent = 28, dphase = 28, dact = 28 }
  row.name:ClearAllPoints()
  if top then row.name:SetPoint("TOPLEFT", 70, -5) else row.name:SetPoint("LEFT", NAME_X[it.kind] or 70, 0) end
  row.name:SetPoint("RIGHT", it.kind == "dg" and row.lvt or row.prog, "LEFT", -6, 0)
  row.box:Hide(); row.ck:Show()
  if it.kind == "misshead" then
    row.ck:SetText(missOpen and "-" or "+"); paint(row.ck, AMBER)
    row.name:SetText("漏掉 " .. #state.missed); paint(row.name, AMBER)
  elseif it.kind == "miss" then
    local q = it.m.q
    row.no:SetText("漏"); paint(row.no, AMBER)
    row.name:SetText(C.Title(q) or (MG.Route.quests[q] and MG.Route.quests[q].n) or q); paint(row.name, AMBER)
  elseif it.kind == "step" then
    local i, s = it.i, it.step.s
    local skipped = MG.db.skip[it.step.key]
    local mark = MG.db.mark[it.step.key]
    row.ck:Hide(); row.box:Show()
    row.no:SetText(UI.Get("showNum") and state.num[i] or ""); paint(row.no, FAINT)
    -- 勾選框：自動完成＝綠勾、手動完成＝金勾、手動未完成＝空框加琥珀短線
    if mark == false then row.box:SetState("dash", AMBER)
    elseif state.done[i] and not state.na[i] and not (state.passed and state.passed[i]) then row.box:SetState("check", mark and GOLD or GREEN)
    else row.box:SetState(nil) end
    row.verb:SetText(E.VERB[s.t] or "")
    row.name:SetText(E.Title(s) .. (skipped and "（已略過）" or "") .. (it.step.defer and "（之後再接）" or ""))
    if it.step.dungeon and not state.done[i] and row.prog:GetText() == "" then row.prog:SetText(it.step.defer and "之後" or "副本前置"); paint(row.prog, AMBER) end
    if s.q and state.fill[s.q] and not state.done[i] then row.prog:SetText("補經驗"); paint(row.prog, GOLD) end
    if state.inGroup[i] then row.strip:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45); row.strip:Show() end
    if i == state.cur then
      row.cur:Show(); row.strip:Show()
      if s.t == "do" and s.q then
        local obj = C.Objectives(s.q) or {}
        if #obj > 1 then
          local d = 0
          for _, o in ipairs(obj) do if o.done then d = d + 1 end end
          row.prog:SetText(d .. "/" .. #obj .. " 項"); paint(row.prog, TEXT)
        end
        for _, o in ipairs(#obj == 1 and obj or {}) do
          if not o.done and o.need then row.prog:SetText(o.have .. "/" .. o.need); paint(row.prog, TEXT); break end
        end
      end
    elseif skipped then
      paint(row.name, FAINT); paint(row.verb, FAINT)
    elseif state.done[i] then
      paint(row.name, FAINT); paint(row.verb, FAINT)
    elseif it.step.carry then
      paint(row.verb, GOLD); row.name:SetText("+ " .. E.Title(s))
    end
  elseif it.kind == "dg" then
    local d = it.d
    local label, kind = E.DungeonStatus(d)
    local lv = UnitLevel("player") or 1
    local fit = lv >= d.lv[1] - 2 and lv <= d.lv[2] and kind ~= "past"
    local open = UI.dOpen == d.id
    row.ck:SetText("")
    row.arrow:Show(); row.arrow:SetRotation(open and -math.pi / 2 or 0); row.arrow:SetVertexColor(unpack(fit and GOLD or DIM))
    row.name:SetText(d.name); paint(row.name, (kind == "past" or MG.db.dNo[d.id]) and FAINT or (kind == "low" and DIM or TEXT))
    row.lvt:SetText(d.lv[1] .. "-" .. d.lv[2]); paint(row.lvt, open and DIM or FAINT); row.lvt:Show()
    if MG.db.dNo[d.id] then label = "不打" end
    row.prog:SetText(label)
    paint(row.prog, (kind == "past" or kind == "low" or MG.db.dNo[d.id]) and FAINT or (label == "可以去" and GREEN) or (kind == "pick" and AMBER) or GOLD)
    if state and state.st == d then row.cur:Show(); row.strip:Show() end
  elseif it.kind == "dnext" then
    local nx, d = it.nx, it.d
    row.bgx:Show()
    if nx.kind == "low" or nx.kind == "wait" then
      row.name:SetText(nx.title); paint(row.name, FAINT)
      row:SetHeight(26)
    else
      row.cur:Show(); row.strip:Show()
      local s = nx.step and nx.step.s
      local title, right, sub
      if nx.kind == "ent" then
        local ent = UI.Entrance(d)
        title = d.name .. "入口"
        row.verb:SetText("去")
        right = ent.coord
        sub = ent.zone .. (ent.door ~= "" and ("  " .. ent.door) or "")
      else
        row.box:Show(); row.ck:Hide()
        row.box:SetState(nil)
        row.verb:SetText(E.VERB[s.t] or "")
        title = E.Title(s)
        if nx.kind == "in" and s.q and C.IsOnQuest(s.q) then
          for _, o in ipairs(C.Objectives(s.q) or {}) do if not o.done and o.need then right = o.have .. "/" .. o.need; break end end
          sub = s.hint or s.text or ""
        else
          right = s.x and string.format("%.1f, %.1f", s.x, s.y) or ""
          sub = (C.MapName(s.map) or "") .. "  " .. ((s.t == "accept" or s.t == "turnin") and (s.npc or "") or (s.hint or s.text or ""))
        end
      end
      row.name:SetFont(FONT, 14, ""); row.name:SetText(title); paint(row.name, TEXT)
      row.prog:SetText(right or ""); paint(row.prog, DIM)
      row.sub:SetText(sub or ""); row.sub:Show()
      row:SetHeight(sub and sub ~= "" and 43 or 26)
    end
  elseif it.kind == "dphase" then
    local d = it.d
    local got, total = E.DungeonTargetCount(d)
    local function count(ph)
      local seen, n = {}, 0
      for _, step in ipairs(d.list) do
        local s = step.s
        if s.ph == ph and s.t ~= "travel" and s.t ~= "need" and E.Applies(s.when) and not seen[s.q or step.key] then seen[s.q or step.key] = true; n = n + 1 end
      end
      return n
    end
    local labels = {
      { "pre", "前置 " .. (got >= total and "|cff6fbf73" .. got .. "/" .. total .. "|r" or (got .. "/" .. total)) },
      { "in", "副本內 " .. count("in") },
      { "post", "出本交 " .. count("post") },
    }
    row.name:SetText("")
    row.bgx:Show()
    for k, b in ipairs(row.tabs) do
      b.phase = labels[k][1]
      b.label:SetText(labels[k][2])
      local on = it.phase == labels[k][1]
      b.label:SetTextColor(unpack(on and TEXT or DIM))
      b.under:SetShown(on)
      b:SetWidth(b.label:GetStringWidth() + 12)
      b:Show()
    end
    row:SetHeight(22)
  elseif it.kind == "dq" then
    local t = it.t
    local s = t.step.s
    local lv = UnitLevel("player") or 1
    local done = C.IsOnQuest(t.q) or E.Turned(t.q) or MG.db.mark[t.step.key] == true
    local low = s.pickLv and lv < s.pickLv
    row.bgx:Show()
    row.box:Show(); row.ck:Hide()
    row.box:SetState(done and "check" or nil, MG.db.mark[t.step.key] and GOLD or GREEN)
    row.name:SetText(E.Title({ q = t.q, t = "accept" })); paint(row.name, (done or low) and FAINT or TEXT)
    local chainDone, chainN = 0, #t.chain
    for _, step in ipairs(t.chain) do if E.Turned(step.s.q) then chainDone = chainDone + 1 end end
    if low then row.prog:SetText(s.pickLv .. " 級")
    elseif chainN > 0 and chainDone < chainN then row.prog:SetText("鏈 " .. chainDone .. "/" .. chainN .. (UI.dChain[t.q] and " -" or " +"))
    else row.prog:SetText(C.MapName(s.map) or "") end
  elseif it.kind == "dch" then
    local step = it.steps[1]
    local q = step.s.q
    row.bgx:Show()
    row.name:ClearAllPoints(); row.name:SetPoint("LEFT", 72, 0); row.name:SetPoint("RIGHT", row.prog, "LEFT", -6, 0)
    local name = it.name .. (it.count > 1 and (" ×" .. it.count) or "")
    local allDone = true
    for _, x in ipairs(it.steps) do if not E.Turned(x.s.q) then allDone = false end end
    if allDone then
      row.ck:SetText("√"); paint(row.ck, GREEN); row.name:SetText(name); paint(row.name, FAINT)
    elseif C.IsOnQuest(q) or (it.isNext) then
      row.ck:SetText("→"); paint(row.ck, GOLD); row.name:SetText(name); paint(row.name, GOLD)
      local obj = C.IsOnQuest(q) and C.Objectives(q) or {}
      local prog = ""
      for _, o in ipairs(obj) do if not o.done and o.need then prog = "做 " .. o.have .. "/" .. o.need; break end end
      row.prog:SetText(prog ~= "" and prog or (C.IsOnQuest(q) and "交" or "接"))
    else
      row.ck:SetText("‧"); paint(row.ck, DIM); row.name:SetText(name); paint(row.name, DIM)
      row.prog:SetText(C.MapName(step.s.map) or "")
    end
    row.ck:ClearAllPoints(); row.ck:SetPoint("LEFT", 54, 0)
  elseif it.kind == "dqi" then
    local d = it.d
    row.bgx:Show()
    -- 這一階段裡這個任務第一個沒完成的步驟
    local cur
    for _, step in ipairs(d.list) do
      if step.s.ph == it.phase and ((it.q and step.s.q == it.q) or (not it.q and step == it.first)) and not E.QuickDone(step) then cur = step; break end
    end
    local show = cur or it.first
    it.step = show
    local s = show.s
    row.box:Show(); row.ck:Hide()
    row.box:SetState(cur and nil or "check", MG.db.mark[show.key] and GOLD or GREEN)
    row.verb:SetText(E.VERB[s.t] or "")
    row.name:SetText(s.q and E.Title({ q = s.q, t = "accept" }) or (s.text or s.hint or "")); paint(row.name, cur and TEXT or FAINT)
    if s.q and C.IsOnQuest(s.q) then
      local obj = C.Objectives(s.q) or {}
      for _, o in ipairs(obj) do if o.need then row.prog:SetText((o.have or 0) .. "/" .. o.need); break end end
    end
  elseif it.kind == "dent" then
    local ent = UI.Entrance(it.d)
    row.bgx:Show()
    row.icon:Show()
    row.name:SetText(ent.zone .. "  " .. ent.coord); paint(row.name, DIM)
    row.prog:SetText(ent.door); paint(row.prog, DIM)
  elseif it.kind == "dact" then
    local d = it.d
    row.bgx:Show()
    row.name:SetText("")
    local running = state and state.st == d
    local _, kind = E.DungeonStatus(d)
    local inactive = kind == "past" or MG.db.dNo[d.id]
    local b1, b2, b3 = row.acts[1], row.acts[2], row.acts[3]
    b1:SetShown(not inactive or running)
    b1.label:SetText(running and "回主線" or "設為目標")
    b1.label:SetTextColor(unpack(running and TEXT or GOLD))
    b1.fill:SetShown(not running)
    b1:SetWidth(b1.label:GetStringWidth() + 28)
    b1.act = running and "back" or "run"
    b2.label:SetText(UI.dMore[d.id] and "詳細 -" or "詳細 +"); b2.label:SetTextColor(unpack(UI.dMore[d.id] and TEXT or DIM)); b2.act = "more"
    b3.label:SetText(MG.db.dNo[d.id] and "改回要打" or "不打"); b3.label:SetTextColor(unpack(FAINT)); b3.act = "no"
    for _, b in ipairs(row.acts) do b.d = d end
    b2:Show(); b3:Show()
    row:SetHeight(26)
  elseif it.kind == "dtext" then
    row.name:SetText("")
    row.bgx:Show()
    row.para:SetFont(FONT, 12, "")
    row.para:SetText((it.text:gsub("「(.-)」", "|cffd9b25f%1|r"))); paint(row.para, DIM); row.para:Show()
    row:SetHeight(math.max(ROW_H, (row.para:GetStringHeight() or 14) + 6))
  elseif it.kind == "dhead" then
    row.name:SetText(it.text); paint(row.name, GOLD)
  elseif it.kind == "start" then
    row.ck:SetText(it.on and "●" or "○"); paint(row.ck, it.on and GOLD or DIM)
    row.name:SetText("起點：" .. it.s.name); paint(row.name, it.on and TEXT or DIM)
  elseif it.kind == "station" then
    local st = it.st
    local got, total = E.Progress(st)
    local lv = UnitLevel("player") or 1
    row.name:SetText(st.name .. (st.test and "（測試）" or ""))
    row.prog:SetText(st.lv[1] .. "-" .. st.lv[2] .. "  " .. got .. "/" .. total)
    if lv >= st.lv[1] and lv <= st.lv[2] then paint(row.prog, GOLD) end
    if state and st == state.st then
      row.ck:SetText("◎"); paint(row.ck, GOLD); row.cur:Show(); row.strip:Show()
    elseif total > 0 and got >= total then
      row.ck:SetText("●"); paint(row.name, DIM)
    elseif MG.db.drop[st.id] then
      row.ck:SetText("○"); paint(row.ck, FAINT); paint(row.name, FAINT)
    else
      row.ck:SetText("○"); paint(row.ck, DIM)
    end
  end
  row:Show()
end

local function drawPanel()
  if not panel:IsShown() then return end
  buildItems()
  local maxScroll = math.max(0, #items - 1)
  if scroll > maxScroll then scroll = maxScroll end
  local y, room = -34, UI.Rows() * ROW_H
  for r = 1, MAX_ROWS do
    local it = items[scroll + r]
    local row = rows[r]
    if it and room > 0 then
      fillRow(row, it)
      local h = row:GetHeight() or ROW_H
      if h > room and r > 1 then row:Hide(); room = 0
      else
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 1, y)
        y, room = y - h, room - h
      end
    else
      row:Hide()
    end
  end
  panel.tabSteps.label:SetTextColor(unpack(tab == "steps" and TEXT or DIM))
  panel.tabMap.label:SetTextColor(unpack(tab == "map" and TEXT or DIM))
  panel.tabSteps.under:SetShown(tab == "steps")
  panel.tabMap.under:SetShown(tab == "map")
  panel.tabDg.label:SetTextColor(unpack(tab == "dg" and TEXT or DIM))
  panel.tabDg.under:SetShown(tab == "dg")
  local st = state and state.st
  if tab == "steps" and state and state.total > 0 then
    panel.station:SetText("剩 " .. state.total .. " 步")
  else
    if tab == "dg" then
      local n, lv = 0, UnitLevel("player") or 1
      for _, d in ipairs(E.dungeons) do
        local _, kind = E.DungeonStatus(d)
        if kind ~= "past" and kind ~= "low" and lv >= d.lv[1] - 2 and not MG.db.dNo[d.id] then n = n + 1 end
      end
      panel.station:SetText(lv .. " 級可去 " .. n .. " 本")
    else
      panel.station:SetText(st and (st.name .. "  " .. st.lv[1] .. "-" .. st.lv[2]) or "")
    end
  end
end

local function scrollToCur()
  buildItems()
  for k, it in ipairs(items) do
    if (tab == "steps" and it.kind == "step" and it.i == state.cur) or (tab == "map" and it.kind == "station" and it.st == state.st) then
      scroll = math.max(0, k - math.floor(UI.Rows() / 2))
      return
    end
  end
end

-- 入口：座標取「前往入口」那一步；地區用遊戲地圖名；分區門＝入口文字括號內
function UI.Entrance(d)
  local x, y
  for _, step in ipairs(d.list) do if step.s.t == "travel" and not step.s.ph and step.s.x then x, y = step.s.x, step.s.y; break end end
  local door = (d.entrance or ""):match("（(.-)）") or ""
  local zone = C.MapName(d.map) or ((d.entrance or ""):match("^(%S+)") or "")
  return { x = x, y = y, coord = x and string.format("%.1f, %.1f", x, y) or "", zone = zone, door = door }
end
function UI.WaypointStep(s)
  if s and s.x then MG.wpOverride = { map = s.map, x = s.x, y = s.y, name = E.Title(s) }; MG.Refresh(true) end
end
function UI.WaypointEntrance(d)
  local ent = UI.Entrance(d)
  if ent.x then MG.wpOverride = { map = d.map, x = ent.x, y = ent.y, name = d.name .. "入口" }; MG.Refresh(true) end
end
function UI.DungeonAction(act, d)
  if act == "run" then E.RunDungeon(d); tab = "steps"; scroll = 0; lastCurKey = nil
  elseif act == "back" then MG.db.station = MG.db.dungeonFrom; MG.db.dungeonFrom = nil; lastCurKey = nil
  elseif act == "more" then UI.dMore[d.id] = not UI.dMore[d.id] or nil; UI.ScrollToDungeon(d)
  elseif act == "no" then MG.db.dNo[d.id] = not MG.db.dNo[d.id] or nil; UI.dOpen = nil end
  MG.Refresh(true)
end
-- 展開區超出面板時，把這本副本的列捲到最上面
function UI.ScrollToDungeon(d)
  buildItems()
  local rowsFit = UI.Rows()
  for k, it in ipairs(items) do
    if it.kind == "dg" and it.d == d then
      local n = 0
      for j = k + 1, #items do if items[j].d == d and items[j].kind ~= "dg" then n = n + 1 else break end end
      if k - scroll + n > rowsFit or k <= scroll then scroll = k - 1 end
      return
    end
  end
end

local function setTab(t)
  tab = t
  scroll = 0
  if state then scrollToCur() end
  drawPanel()
end

local function onRowClick(row, button)
  local it = row.it
  if not it then return end
  if it.kind == "misshead" then missOpen = not missOpen
  elseif it.kind == "miss" then E.PinIndex(state, it.m.i)
  elseif it.kind == "step" then
    if button == "RightButton" then E.ToggleSkip(it.step.key) else E.PinIndex(state, it.i) end
  elseif it.kind == "dg" then
    local d = it.d
    if UI.dOpen == d.id then UI.dOpen = nil; UI.dPhase[d.id] = nil else UI.dOpen = d.id end
    UI.ScrollToDungeon(d)
  elseif it.kind == "dnext" then
    if it.nx.kind == "ent" then UI.WaypointEntrance(it.d)
    elseif it.nx.step then UI.WaypointStep(it.nx.step.s) end
  elseif it.kind == "dq" then
    local done = 0
    for _, step in ipairs(it.t.chain) do if E.Turned(step.s.q) then done = done + 1 end end
    if #it.t.chain > 0 and done < #it.t.chain then UI.dChain[it.t.q] = not UI.dChain[it.t.q] or nil
    else UI.WaypointStep(it.t.step.s) end
  elseif it.kind == "dch" then
    UI.WaypointStep(it.steps[1].s)
  elseif it.kind == "dqi" then
    if it.step then UI.WaypointStep(it.step.s) end
  elseif it.kind == "dent" then
    UI.WaypointEntrance(it.d)
  elseif it.kind == "start" then
    setStart(it.s.key)
  elseif it.kind == "station" then
    E.Select(it.st); tab = "steps"; scroll = 0; lastCurKey = nil
  end
  MG.Refresh(true)
end

-- ── 建立 ────────────────────────────────────────────────────────────────────
function UI.Create()
  root = CreateFrame("Frame", "MetroGuideFrame", UIParent)
  root:SetSize(320, 60)
  root:SetMovable(true)
  root:SetClampedToScreen(true)
  root:SetFrameStrata("MEDIUM")

  bar = CreateFrame("Button", nil, root)
  bar:SetSize(300, 44)
  bar:SetPoint("TOPLEFT")
  bar.bg = box(bar)
  bar.strip = bar:CreateTexture(nil, "ARTWORK")
  bar.strip:SetPoint("TOPLEFT"); bar.strip:SetPoint("BOTTOMLEFT"); bar.strip:SetWidth(3)
  bar.verbBox = CreateFrame("Frame", nil, bar)
  bar.verbBox:SetSize(20, 20)
  bar.verbBox:SetPoint("TOPLEFT", 12, -10)
  local vb = box(bar.verbBox, { 0.294, 0.31, 0.349 })
  vb:SetColorTexture(0, 0, 0, 0)
  bar.verb = text(bar.verbBox, 12, GOLD, "CENTER")
  bar.verb:SetPoint("CENTER", 0, 0)
  bar.lv = text(bar, 12, DIM, "RIGHT")
  bar.lv:SetPoint("TOPRIGHT", -32, -13)
  -- 右上角齒輪：開設定頁
  local gear = CreateFrame("Button", nil, bar)
  gear:SetSize(22, 22) -- 點擊範圍
  gear:SetPoint("TOPRIGHT", -5, -5)
  gear.icon = gear:CreateTexture(nil, "ARTWORK")
  gear.icon:SetSize(18, 18)
  gear.icon:SetPoint("CENTER")
  gear.icon:SetPoint("CENTER")
  C.GearIcon(gear.icon, 16)
  gear:SetAlpha(0.45)
  gear:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("設定")
    GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", function(self) self:SetAlpha(0.45); GameTooltip:Hide() end)
  gear:SetScript("OnClick", function() UI.OpenOptions() end)
  bar.title = text(bar, 15, TEXT)
  bar.title:SetPoint("TOPLEFT", 40, -12)
  bar.title:SetPoint("RIGHT", bar, "RIGHT", -32, 0)
  bar.l2 = text(bar, 13, DIM)
  bar.l2:SetPoint("TOPLEFT", 40, -34)
  bar.l2:SetPoint("RIGHT", -10, 0)
  bar.objs = {}
  for k = 1, 5 do bar.objs[k] = text(bar, 13, TEXT) end
  bar.extra, bar.divs = {}, {}
  for k = 1, 40 do bar.extra[k] = text(bar, 13, TEXT); bar.extra[k]:Hide() end
  for k = 1, 4 do
    local d = bar:CreateTexture(nil, "ARTWORK")
    d:SetColorTexture(EDGE[1] * 1.6, EDGE[2] * 1.6, EDGE[3] * 1.6, 1)
    d:SetHeight(1)
    d:Hide()
    bar.divs[k] = d
  end
  bar.l3 = text(bar, 13, GOLD)
  bar.l3:SetPoint("TOPLEFT", 40, -52)
  bar.l3:SetPoint("RIGHT", -10, 0)
  bar.flash = bar:CreateTexture(nil, "ARTWORK")
  bar.flash:SetAllPoints(); bar.flash:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.28); bar.flash:SetAlpha(0)

  bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() if not UI.Get("locked") and not InCombatLockdown() then root:StartMoving() end end)
  bar:SetScript("OnDragStop", function() root:StopMovingOrSizing(); savePos(); UI.PlaceHolder() end)
  bar:SetScript("OnClick", function(_, button)
    if button == "RightButton" then openMenu(bar); return end
    menu:Hide()
    panel:SetShown(not panel:IsShown())
    if panel:IsShown() and state then scrollToCur() end
    drawPanel()
  end)
  bar:SetScript("OnEnter", function(self)
    local cur = state and state.cur and state.steps[state.cur]
    if cur then UI.StepTooltip(self, cur.s, nil, true) end
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  bar:EnableMouseWheel(true)
  bar:SetScript("OnMouseWheel", function(_, delta)
    if state and state.st then E.Move(state, delta > 0 and -1 or 1); MG.Refresh(true) end
  end)
  -- 步驟切換：0.15 秒淡入；完成：綠光一閃
  local fade, flash = 1, 0
  bar:SetScript("OnUpdate", function(_, dt)
    local alpha = UI.Get("barOpacity") / 100
    if UI.Get("fadeOn") and (InCombatLockdown() or not root:IsMouseOver()) then alpha = UI.Get("fadeAlpha") / 100 end
    if root:GetAlpha() ~= alpha then root:SetAlpha(alpha) end
    if fade < 1 then fade = math.min(1, fade + dt / 0.15); bar.title:SetAlpha(fade); bar.l2:SetAlpha(fade); bar.l3:SetAlpha(fade); bar.verb:SetAlpha(fade) end
    if flash > 0 then flash = math.max(0, flash - dt / 0.35); bar.flash:SetAlpha(flash) end
  end)
  function UI.Animate(done) fade = 0; if done then flash = 1 end end

  chip = CreateFrame("Button", nil, root)
  chip:SetSize(200, 24)
  chip:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
  box(chip, { 0.427, 0.353, 0.184 })
  chip.label = text(chip, 13, GOLD, "CENTER")
  chip.label:SetPoint("CENTER")
  chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  chip:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if self.sug then MG.db.sugHide = UnitLevel("player") end
    elseif self.sug then E.Jump(self.sug)
    elseif self.next then E.Select(self.next) end
    lastCurKey = nil
    MG.Refresh(true)
  end)
  chip:Hide()

  -- 副本提示：「可以下 副本名（a–b）」＋缺什麼；點文字開副本分頁，× 不再提示這本
  dhint = CreateFrame("Button", nil, root)
  dhint:SetSize(300, 40)
  box(dhint, BRONZE)
  dhint.label = text(dhint, 13, GOLD)
  dhint.label:SetPoint("TOPLEFT", 10, -6)
  dhint.label:SetPoint("RIGHT", -26, 0)
  dhint.sub = text(dhint, 12, DIM)
  dhint.sub:SetPoint("TOPLEFT", 10, -23)
  dhint.sub:SetPoint("RIGHT", -26, 0)
  local x = CreateFrame("Button", nil, dhint)
  x:SetSize(20, 20); x:SetPoint("RIGHT", -2, 0)
  x.label = text(x, 13, DIM, "CENTER"); x.label:SetPoint("CENTER"); x.label:SetText("×")
  x:SetScript("OnClick", function() if dhint.d then MG.db.dDismiss[dhint.d.id] = true end; MG.Refresh(true) end)
  dhint:SetScript("OnClick", function(self)
    if not self.d then return end
    UI.dOpen = self.d.id
    panel:Show(); setTab("dg")
    for k, it in ipairs(items) do if it.kind == "dg" and it.d == self.d then scroll = math.max(0, k - 1) end end
    drawPanel()
  end)
  dhint:Hide()

  panel = CreateFrame("Frame", nil, root)
  panel:SetSize(320, 34 + 18 * ROW_H + 8)
  panel.bg = box(panel)
  local function tabButton(label, x, t)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(56, 30)
    b:SetPoint("TOPLEFT", x, 0)
    b.label = text(b, 14, DIM, "CENTER")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(label)
    b.under = b:CreateTexture(nil, "ARTWORK")
    b.under:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    b.under:SetPoint("BOTTOMLEFT", 8, 0); b.under:SetPoint("BOTTOMRIGHT", -8, 0); b.under:SetHeight(2)
    b:SetScript("OnClick", function() setTab(t) end)
    return b
  end
  panel.tabSteps = tabButton("步驟", 6, "steps")
  panel.tabMap = tabButton("路線", 62, "map")
  panel.tabDg = tabButton("副本", 118, "dg")
  local st = CreateFrame("Button", nil, panel)
  st:SetHeight(30)
  st:SetPoint("TOPLEFT", panel.tabDg, "TOPRIGHT", 6, 0)
  st:SetPoint("TOPRIGHT", -8, 0)
  panel.station = text(st, 12, DIM, "RIGHT")
  panel.station:SetAllPoints()
  st:SetScript("OnClick", function() setTab("map") end)
  local div = panel:CreateTexture(nil, "BORDER")
  div:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
  div:SetPoint("TOPLEFT", 1, -30); div:SetPoint("TOPRIGHT", -1, -30); div:SetHeight(1)
  for r = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(318, ROW_H)
    row:SetPoint("TOPLEFT", 1, -34 - (r - 1) * ROW_H)
    row.cur = row:CreateTexture(nil, "BACKGROUND")
    row.cur:SetAllPoints(); row.cur:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.09)
    row.strip = row:CreateTexture(nil, "ARTWORK")
    row.strip:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    row.strip:SetPoint("TOPLEFT"); row.strip:SetPoint("BOTTOMLEFT"); row.strip:SetWidth(3)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.04)
    row.ck = text(row, 12, GREEN, "CENTER")
    row.ck:SetPoint("LEFT", 8, 0); row.ck:SetWidth(14)
    -- 勾選框：左鍵切換手動勾選，右鍵回到自動
    row.box = UI.Checkbox(row, 13)
    row.box:SetPoint("LEFT", 9, 0)
    row.box:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.box:SetScript("OnClick", function(self, button)
      local it = row.it
      if it and (it.kind == "dnext" or it.kind == "dq" or it.kind == "dqi") then
        local step = it.kind == "dnext" and it.nx.step or (it.kind == "dq" and it.t.step) or it.step
        if step then
          if button == "RightButton" or MG.db.mark[step.key] ~= nil then E.SetMark(step.key, nil) else E.SetMark(step.key, true) end
        end
        MG.Refresh(true)
        return
      end
      if it and it.kind == "dstep" then
        local key = it.step.key
        if button == "RightButton" or MG.db.mark[key] ~= nil then E.SetMark(key, nil)
        else E.SetMark(key, not E.QuickDone(it.step)) end
        MG.Refresh(true)
        return
      end
      if not (it and it.kind == "step") then return end
      local i, key = it.i, it.step.key
      if button == "RightButton" then E.SetMark(key, nil)
      else
        local want = not state.done[i]
        if want == state.autoDone[i] then E.SetMark(key, nil) else E.SetMark(key, want) end
      end
      MG.Refresh(true)
    end)
    row.no = text(row, 11, FAINT, "RIGHT")
    row.no:SetPoint("LEFT", 24, 0); row.no:SetWidth(20)
    row.verb = text(row, 13, GOLD, "CENTER")
    row.verb:SetPoint("LEFT", 48, 0); row.verb:SetWidth(18)
    row.prog = text(row, 12, DIM, "RIGHT")
    row.lvt = text(row, 12, FAINT, "RIGHT")
    row.lvt:SetPoint("RIGHT", row.prog, "LEFT", -4, 0); row.lvt:SetWidth(38); row.lvt:Hide()
    row.prog:SetPoint("RIGHT", -12, 0)
    row.para = row:CreateFontString(nil, "OVERLAY")
    row.para:SetFont(FONT, 13, "")
    row.para:SetPoint("TOPLEFT", 28, -3)
    row.para:SetWidth(318 - 28 - 12)
    row.para:SetJustifyH("LEFT")
    row.para:SetWordWrap(true)
    if row.para.SetNonSpaceWrap then row.para:SetNonSpaceWrap(true) end -- 中文沒有空白也要能斷行
    if row.para.SetMaxLines then row.para:SetMaxLines(0) end
    row.para:Hide()
    row.bgx = row:CreateTexture(nil, "BACKGROUND")
    row.bgx:SetAllPoints(); row.bgx:SetColorTexture(1, 1, 1, 0.025); row.bgx:Hide()
    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetSize(12, 12); row.arrow:SetPoint("LEFT", 9, 0)
    row.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow"); row.arrow:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(12, 12); row.icon:SetPoint("LEFT", 10, 0)
    row.icon:SetTexture("Interface\\AddOns\\MetroGuide\\Media\\pin_circle_base"); row.icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3]); row.icon:Hide()
    row.sub = text(row, 12, DIM)
    row.sub:SetPoint("TOPLEFT", 50, -25); row.sub:SetPoint("RIGHT", -12, 0); row.sub:Hide()
    row.tabs = {}
    for k = 1, 3 do
      local b = CreateFrame("Button", nil, row)
      b:SetHeight(20)
      if k == 1 then b:SetPoint("LEFT", 22, 0) else b:SetPoint("LEFT", row.tabs[k - 1], "RIGHT", 4, 0) end
      b.label = text(b, 12, DIM, "CENTER"); b.label:SetPoint("CENTER", 0, 1)
      b.under = b:CreateTexture(nil, "ARTWORK"); b.under:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
      b.under:SetPoint("BOTTOMLEFT", 6, 1); b.under:SetPoint("BOTTOMRIGHT", -6, 1); b.under:SetHeight(1)
      b:SetScript("OnClick", function(self) local it = row.it; if it then UI.dPhase[it.d.id] = self.phase; drawPanel() end end)
      b:Hide()
      row.tabs[k] = b
    end
    row.acts = {}
    for k = 1, 3 do
      local b = CreateFrame("Button", nil, row)
      b:SetSize(56, 22)
      b.label = text(b, k == 1 and 13 or 12, DIM, "CENTER"); b.label:SetPoint("CENTER")
      if k == 1 then
        b:SetPoint("LEFT", 26, 0)
        box(b, GOLD)
        b.fill = b:CreateTexture(nil, "BACKGROUND", nil, 1); b.fill:SetAllPoints(); b.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)
      elseif k == 2 then b:SetPoint("RIGHT", -64, 0)
      else b:SetPoint("RIGHT", -10, 0) end
      b:SetScript("OnClick", function(self) UI.DungeonAction(self.act, self.d) end)
      b:Hide()
      row.acts[k] = b
    end
    row.name = text(row, 13, TEXT)
    row.name:SetPoint("LEFT", 70, 0)
    row.name:SetPoint("RIGHT", row.prog, "LEFT", -6, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", onRowClick)
    row:SetScript("OnEnter", function(self)
      local it = self.it
      if it and it.kind == "step" then UI.StepTooltip(self, it.step.s, nil, true)
      elseif it and it.kind == "miss" then UI.StepTooltip(self, state.steps[it.m.i].s, nil, true)
      elseif it and it.kind == "dstep" then UI.StepTooltip(self, it.step.s, nil, true)
      elseif it and it.kind == "dnext" and it.nx.step then UI.StepTooltip(self, it.nx.step.s, nil, true)
      elseif it and it.kind == "dq" then UI.StepTooltip(self, it.t.step.s, nil, true)
      elseif it and it.kind == "dqi" and it.step then UI.StepTooltip(self, it.step.s, nil, true)
      elseif it and it.kind == "dch" then UI.StepTooltip(self, it.steps[1].s, nil, true) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[r] = row
  end
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta)
    scroll = math.max(0, scroll - delta * 3)
    drawPanel()
  end)
  panel:Hide()

  menu = CreateFrame("Frame", nil, UIParent)
  menu:SetSize(162, 100)
  menu:SetFrameStrata("DIALOG")
  box(menu)
  menu.buttons = {}
  menu:Hide()

  MG.try("小地圖按鈕", UI.CreateMinimap)
  MG.try("設定頁", UI.CreateOptions)
  UI.Holder()
  MG.try("目標按鈕", MG.T.Create, holder)
  MG.try("任務物品", MG.I.Create, holder)
  local regen = CreateFrame("Frame")
  pcall(regen.RegisterEvent, regen, "PLAYER_REGEN_ENABLED")
  regen:SetScript("OnEvent", function() if UI.holderPending or UI.settingsPending then UI.settingsPending = false; UI.PlaceHolder() end end)
  UI.ApplySettings()
end

-- ── 小地圖按鈕 ──────────────────────────────────────────────────────────────
local mini
function UI.PlaceMinimap()
  if not mini then return end
  local a = math.rad(MetroGuideDB.angle or 200)
  local r = (Minimap:GetWidth() or 140) / 2 + 8
  mini:ClearAllPoints()
  mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  mini:SetShown(UI.Get("minimap"))
  mini:SetAlpha(UI.Get("miniBtnAlpha") / 100)
end

function UI.CreateMinimap()
  if not Minimap then return end
  mini = CreateFrame("Button", "MetroGuideMinimapButton", Minimap)
  mini:SetSize(28, 28)
  mini:SetFrameStrata("MEDIUM")
  mini:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
  local bg = mini:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("CENTER"); bg:SetSize(24, 24)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetVertexColor(BG[1], BG[2], BG[3], 1)
  local icon = mini:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("CENTER"); icon:SetSize(17, 17)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local ring = mini:CreateTexture(nil, "OVERLAY")
  ring:SetPoint("TOPLEFT"); ring:SetSize(48, 48)
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mini:RegisterForDrag("LeftButton")
  mini:SetScript("OnClick", function(self, button)
    if button == "RightButton" then openMenu(self) else UI.Toggle() end
  end)
  mini:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local sc = Minimap:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      MetroGuideDB.angle = math.deg((math.atan2 or math.atan)(cy / sc - my, cx / sc - mx))
      UI.PlaceMinimap()
    end)
  end)
  mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  mini:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("地鐵升級")
    local st = state and state.st
    local cur = state and state.cur and state.steps[state.cur]
    GameTooltip:AddLine(st and (st.name .. "  " .. st.lv[1] .. "-" .. st.lv[2]) or "沒有路線", 1, 1, 1)
    if st then GameTooltip:AddLine(cur and ((E.VERB[cur.s.t] or "") .. " " .. E.Title(cur.s)) or "本站完成", DIM[1], DIM[2], DIM[3]) end
    GameTooltip:Show()
  end)
  mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ── 設定頁（選項 → 插件） ───────────────────────────────────────────────────
local options
-- 拖滑桿時在步驟列旁顯示一個範例提示框
function UI.PreviewTip()
  local cur = state and state.cur and state.steps[state.cur]
  UI.StepTooltip(bar, cur and cur.s or { t = "do", text = "範例", desc = "這是說明行" }, nil, true)
end

-- 版面格線：標籤欄、控制欄（勾選框／滑桿／按鈕同一個 x）、數值欄
local COL_LABEL, COL_CTRL, COL_VALUE, ROW, PAGE_W = 28, 220, 432, 26, 520

function UI.CreateOptions()
  options = CreateFrame("Frame", "MetroGuideOptions", UIParent)
  options:Hide()
  local sf = CreateFrame("ScrollFrame", nil, options)
  sf:SetPoint("TOPLEFT", 0, -6); sf:SetPoint("BOTTOMRIGHT", -6, 6)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(PAGE_W + 40, 100)
  sf:SetScrollChild(content)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40)))
  end)
  local head = text(content, 18, GOLD)
  head:SetPoint("TOPLEFT", 16, -10)
  head:SetText("地鐵升級")
  options.widgets = {}
  local syncing = false
  local function changed(sp)
    UI.ApplySettings(); MG.Refresh(true)
    if sp and sp.tip then UI.PreviewTip() end
  end
  local function label(y, t)
    local l = text(content, 13, TEXT)
    l:SetPoint("TOPLEFT", COL_LABEL, y - 5)
    l:SetWidth(COL_CTRL - COL_LABEL - 8)
    l:SetText(t)
    return l
  end
  local y = -44
  local section, actions
  -- 一區結束：把該區的動作按鈕排成一列
  local function flush()
    if actions and #actions > 0 then
      for k, sp in ipairs(actions) do
        local btn = goldButton(content, sp.button, 120)
        btn:SetPoint("TOPLEFT", COL_LABEL + (k - 1) * 128, y - 2)
        btn:SetScript("OnClick", function()
          if sp.all then
            for _, other in ipairs(SPEC) do if other.key then UI.Reset(other.key) end end
            MG.db.pos = nil
          else
            sp.run()
          end
          changed(); UI.RefreshOptions()
        end)
      end
      y = y - ROW - 4
    end
    actions = {}
  end
  for _, sp in ipairs(SPEC) do
    if sp.section then
      flush()
      y = y - 12
      section = { keys = {} }
      if sp.section ~= "" then
        local h = text(content, 14, GOLD)
        h:SetPoint("TOPLEFT", 16, y)
        h:SetText(sp.section)
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.8)
        line:SetPoint("TOPLEFT", 16, y - 20); line:SetSize(PAGE_W, 1)
        local sec = section
        local r = goldButton(content, "重設", 52)
        r:SetHeight(18)
        r:SetPoint("TOPRIGHT", content, "TOPLEFT", 16 + PAGE_W, y + 1)
        r:SetScript("OnClick", function()
          for _, k in ipairs(sec.keys) do UI.Reset(k) end
          changed(); UI.RefreshOptions()
        end)
        y = y - 28
      end
    elseif sp.min then
      section.keys[#section.keys + 1] = sp.key
      label(y, sp.label)
      local v = text(content, 13, DIM)
      v:SetPoint("TOPLEFT", COL_VALUE, y - 5)
      local slider = C.Slider(content, sp.min, sp.max, sp.step, UI.Get(sp.key), function(val)
        if syncing then return end
        UI.Set(sp.key, val)
        v:SetText(val .. (sp.unit or ""))
        changed(sp)
      end)
      slider:SetPoint("TOPLEFT", COL_CTRL, y - 4)
      slider:SetWidth(COL_VALUE - COL_CTRL - 14)
      options.widgets[#options.widgets + 1] = { refresh = function()
        syncing = true; C.SliderSet(slider, UI.Get(sp.key)); syncing = false
        v:SetText(UI.Get(sp.key) .. (sp.unit or ""))
      end }
      y = y - ROW
    elseif sp.key then
      section.keys[#section.keys + 1] = sp.key
      label(y, sp.label)
      local cb = UI.Checkbox(content, 16)
      cb:SetPoint("TOPLEFT", COL_CTRL, y - 4)
      cb:SetScript("OnClick", function() toggleSetting(sp); changed(sp); UI.RefreshOptions() end)
      if sp.hint then
        cb:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:AddLine(sp.label)
          GameTooltip:AddLine(sp.hint, DIM[1], DIM[2], DIM[3], true)
          GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end
      options.widgets[#options.widgets + 1] = { refresh = function() cb:SetState(UI.Get(sp.key) and "check" or nil) end }
      y = y - ROW
    elseif sp.choices then
      section.keys[#section.keys + 1] = sp.key
      label(y, sp.label)
      local btn = goldButton(content, "", 160)
      btn:SetPoint("TOPLEFT", COL_CTRL, y - 2)
      btn:SetScript("OnClick", function() UI.Set(sp.key, UI.Get(sp.key) % #sp.choices + 1); changed(sp); UI.RefreshOptions() end)
      options.widgets[#options.widgets + 1] = { refresh = function() btn.label:SetText(sp.choices[UI.Get(sp.key)] or "") end }
      y = y - ROW
    elseif sp.start then
      label(y, "起點")
      local btn = goldButton(content, "", 160)
      btn:SetPoint("TOPLEFT", COL_CTRL, y - 2)
      btn:SetScript("OnClick", function() cycleStart(); changed(); UI.RefreshOptions() end)
      options.widgets[#options.widgets + 1] = { refresh = function() btn.label:SetText(startLabel()) end }
      y = y - ROW
    elseif sp.button then
      actions[#actions + 1] = sp
    end
  end
  flush()
  content:SetHeight(-y + 20)
  options:SetScript("OnShow", function() UI.RefreshOptions() end)
  options:SetScript("OnHide", function() if GameTooltip:GetOwner() == bar then GameTooltip:Hide() end end)
  C.RegisterOptions(options, "地鐵升級")
end

function UI.RefreshOptions()
  if not options then return end
  for _, w in ipairs(options.widgets) do w.refresh() end
end

function UI.OpenOptions() if options then C.OpenOptions(options) end end

-- ── 畫 ──────────────────────────────────────────────────────────────────────
-- UTF-8 逐字切
local function chars(t)
  local out = {}
  for ch in t:gmatch("[\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end
local VERBS = { "殺死", "殺掉", "擊殺", "擊敗", "收集", "取得", "拿到", "找到", "摧毀", "消滅" }

-- 目標：只有一項時回傳一行文字；多項時回傳 header 與每項 { text, done }（未完成在前）
local function objectiveLines(q)
  local obj = C.Objectives(q)
  if not obj or #obj == 0 then return nil end
  local function count(o) return o.need and ("  " .. (o.have or 0) .. "/" .. o.need) or "" end
  if #obj == 1 then
    local o = obj[1]
    return (o.text ~= "" and o.text or "目標") .. (o.need and ("  |cffe8e4d8" .. (o.have or 0) .. "/" .. o.need .. "|r") or "")
  end
  -- 共同動詞與共同字首（例：殺死 怨怒… → 欺詐者、喚魔者）
  local texts = {}
  for i, o in ipairs(obj) do texts[i] = o.text or "" end
  local verb
  for _, v in ipairs(VERBS) do
    local all = true
    for _, t in ipairs(texts) do if t:sub(1, #v) ~= v then all = false; break end end
    if all then verb = v; break end
  end
  if verb then for i, t in ipairs(texts) do texts[i] = t:sub(#verb + 1):gsub("^%s+", "") end end
  local first = chars(texts[1])
  local common = #first
  for k = 2, #texts do
    local c = chars(texts[k])
    local n = 0
    while n < common and n < #c and c[n + 1] == first[n + 1] do n = n + 1 end
    common = n
  end
  local shortest = math.huge
  for _, t in ipairs(texts) do shortest = math.min(shortest, #chars(t)) end
  if common < 2 or common >= shortest then common = 0 end -- 字首太短或吃掉整項就不拆
  local prefix = table.concat(first, "", 1, common)
  if common > 0 then for i, t in ipairs(texts) do texts[i] = t:sub(#prefix + 1) end end
  local header = (verb or "") .. ((verb and common > 0) and " " or "") .. prefix
  local lines = {}
  for i, o in ipairs(obj) do
    lines[#lines + 1] = { text = (o.done and "√ " or "") .. (texts[i] ~= "" and texts[i] or "目標") .. count(o), done = o.done, i = i }
  end
  table.sort(lines, function(x, y) if x.done ~= y.done then return not x.done end return x.i < y.i end)
  return nil, header ~= "" and (header .. "…") or nil, lines
end
UI.ObjectiveLines = objectiveLines

-- S = { state, sug, nextSt }
function UI.Render(S)
  state = S.state
  local db = MG.db
  local lv = UnitLevel("player") or 1
  local verb, title, right, l2, l3, l3warn, titleColor = "", "", "", nil, nil, false, TEXT
  local objList
  local strip = GOLD
  if not state then
    title = "這個角色沒有路線"
  elseif state.cur then
    local step = state.steps[state.cur]
    local s = step.s
    local info = s.q and MG.Route.quests[s.q]
    verb = E.VERB[s.t] or ""
    title = E.Title(s)
    if state.tails and state.tails[state.cur] then title = "前往下一站：" .. title end
    right = UI.Get("showLevel") and info and info.lvl and tostring(info.lvl) or ""
    if s.t == "accept" or s.t == "turnin" then l2 = s.npc
    elseif s.t == "do" then
      local one, header, lines = objectiveLines(s.q)
      if lines then l2, objList = header, lines else l2 = one or s.hint end
    elseif s.t == "level" then l2 = "目前 " .. lv .. " 級"
    elseif s.t == "hearth" then l2 = "找旅店老闆"
    elseif s.t == "fp" then l2 = "找飛行管理員"
    elseif s.t == "travel" then l2 = select(2, E.Clause(s.text)) end
    if s.t == "turnin" and C.IsOnQuest(s.q) and E.Ready(s.q) then titleColor = GREEN end
    if info and info.min and lv < info.min then
      l3, l3warn = "差 " .. (info.min - lv) .. " 級", true
    elseif step.defer then
      l3, l3warn = "之後再接（任務日誌快滿）", true
    elseif step.dungeon then
      l3 = "副本前置：" .. step.dungeon.name .. (s.share == 1 and "  可共享" or "")
    elseif s.q and state.fill[s.q] then
      l3 = "補經驗"
    elseif step.note then
      l3 = step.note
    elseif s.tag then
      l3 = s.tag
    elseif step.carry then
      l3 = "順路補（" .. step.st.name .. "）"
    elseif lv < state.st.lv[1] then
      l3, l3warn = "本站建議 " .. state.st.lv[1] .. " 級", true
    end
    if state.cur ~= state.auto then strip = DIM end
  else
    local nxt = S.nextSt
    verb = "→"
    title = nxt and ("前往 " .. nxt.name) or "路線已走完"
    right = nxt and (nxt.lv[1] .. "-" .. nxt.lv[2]) or ""
    l2 = state.tail
    for _, tip in ipairs(state.st.tips or {}) do
      if tip.k == "交通" and not l2 then l2 = table.concat(UI.Sentences(tip.s, { tip.text }), "，") end
    end
    if #state.missed > 0 then l3, l3warn = "漏掉 " .. #state.missed .. " 個任務（展開查看）", true end
  end

  bar.verb:SetText(verb)
  bar.verbBox:SetShown(verb ~= "")
  bar.title:SetText(title)
  paint(bar.title, titleColor)
  if UI.Get("showCount") and state and state.cur then
    right = "剩 " .. state.total .. (right ~= "" and ("   " .. right) or "")
  end
  bar.lv:SetText(right)
  local gap = ((MG.T and MG.T.Shown(state)) and 22 or 0) + (MG.I and MG.I.InsideWidth() or 0)
  bar.lv:SetPoint("TOPRIGHT", -32 - gap, -13)
  bar.title:SetPoint("RIGHT", bar, "RIGHT", (right ~= "" and -(36 + bar.lv:GetStringWidth()) or -32) - gap, 0)
  bar.l2:SetText(l2 or "")
  bar.l3:SetText(l3 or "")
  paint(bar.l3, l3warn and AMBER or GOLD)
  bar.strip:SetColorTexture(strip[1], strip[2], strip[3], 1)
  local y = -34
  if l2 then bar.l2:SetPoint("TOPLEFT", 40, y); y = y - 18 end
  -- 多目標：最多 5 行（多的話最後一行「…還有 n 項」）；4 項以上排兩欄
  local shown = {}
  if objList then
    for k, o in ipairs(objList) do
      local maxRows = UI.Get("objRows")
      if #objList > maxRows and k == maxRows then shown[k] = { text = "…還有 " .. (#objList - maxRows + 1) .. " 項" }; break end
      shown[k] = o
      if k == maxRows then break end
    end
  end
  local cols = #shown >= 4 and 2 or 1
  for k = 1, #bar.objs do
    local fs, o = bar.objs[k], shown[k]
    if o then
      local row, col = math.floor((k - 1) / cols), (k - 1) % cols
      fs:ClearAllPoints()
      local colW = math.floor((UI.Get("barWidth") - 50) / cols)
      fs:SetPoint("TOPLEFT", 40 + col * colW, y - row * 18)
      fs:SetWidth(colW - 6)
      fs:SetText(o.text)
      paint(fs, o.done and FAINT or TEXT)
      fs:Show()
    else
      fs:Hide()
    end
  end
  if #shown > 0 then y = y - math.ceil(#shown / cols) * 18 end
  if l3 then bar.l3:SetPoint("TOPLEFT", 40, y); y = y - 18 end
  -- 附近可一起做的步驟：每步一個小區塊（分隔線＋動詞任務名＋目標）
  local used = 0
  local fsz = UI.Get("fontSize")
  local function line(t, color, x, w)
    used = used + 1
    local f = bar.extra[used]
    if not f then return end
    f:SetFont(FONT, fsz - 2, "")
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", x or 40, y)
    f:SetWidth(w or (UI.Get("barWidth") - 50))
    f:SetText(t)
    paint(f, color)
    f:Show()
  end
  for k, i in ipairs(state and state.group or {}) do
    local s = state.steps[i].s
    local d = bar.divs[k]
    if d then
      d:ClearAllPoints()
      d:SetPoint("TOPLEFT", 40, y - 2); d:SetPoint("TOPRIGHT", -10, y - 2)
      d:Show()
    end
    y = y - 7
    line((E.VERB[s.t] or "") .. "  " .. E.Title(s), TEXT)
    y = y - 17
    if s.t == "do" and s.q then
      local one, header, lines = objectiveLines(s.q)
      if lines then
        if header then line(header, DIM); y = y - 16 end
        local maxRows = UI.Get("objRows")
        local n = math.min(#lines, maxRows)
        local cols = n >= 4 and 2 or 1
        local colW = math.floor((UI.Get("barWidth") - 50) / cols)
        for j = 1, n do
          local o = lines[j]
          local text = (#lines > maxRows and j == maxRows) and ("…還有 " .. (#lines - maxRows + 1) .. " 項") or o.text
          local r, c = math.floor((j - 1) / cols), (j - 1) % cols
          local yy = y
          y = y - r * 16
          line(text, o.done and FAINT or DIM, 40 + c * colW, colW - 6)
          y = yy
        end
        y = y - math.ceil(n / cols) * 16
      elseif one or s.hint then
        line(one or s.hint, DIM); y = y - 16
      end
    elseif s.npc then
      line(s.npc, DIM); y = y - 16
    end
  end
  for k = used + 1, #bar.extra do bar.extra[k]:Hide() end
  for k = #(state and state.group or {}) + 1, #bar.divs do bar.divs[k]:Hide() end
  bar:SetHeight(math.max(44, -y + 6))

  local key = state and state.st.id .. ":" .. tostring(state.cur and state.steps[state.cur].key)
  if key ~= lastCurKey then
    if lastCurKey then UI.Animate(state ~= nil and state.cur == state.auto) end
    lastCurKey = key
    if panel:IsShown() and state then scrollToCur() end
  end

  -- 建議鈕：超等建議優先，其次「本站完成 → 下一站」
  chip.sug, chip.next = nil, nil
  if S.sug and db.sugHide ~= lv then
    chip.sug = S.sug
    chip.label:SetText("→ " .. S.sug.name .. "  " .. S.sug.lv[1] .. "-" .. S.sug.lv[2])
  elseif state and not state.cur and S.nextSt then
    chip.next = S.nextSt
    chip.label:SetText("→ " .. S.nextSt.name .. "  " .. S.nextSt.lv[1] .. "-" .. S.nextSt.lv[2])
  end
  chip:SetShown(chip.sug ~= nil or chip.next ~= nil)
  if chip:IsShown() then chip:SetWidth(math.min(UI.Get("barWidth"), chip.label:GetStringWidth() + 28)) end
  panel:ClearAllPoints()
  -- 副本提示（不在副本流程中才顯示）
  local d, missing
  if not (state and (state.st.dungeon or state.instance)) then d, missing = E.DungeonPrompt() end
  dhint.d = d
  if d then
    dhint.label:SetText("可以下 " .. d.name .. "（" .. d.lv[1] .. "-" .. d.lv[2] .. "）")
    dhint.sub:SetText(missing or "")
    dhint:SetHeight(missing and 40 or 24)
    dhint:SetWidth(UI.Get("barWidth"))
    dhint:ClearAllPoints()
    dhint:SetPoint("TOPLEFT", chip:IsShown() and chip or bar, "BOTTOMLEFT", 0, -6)
  end
  dhint:SetShown(d ~= nil)
  local above = dhint:IsShown() and dhint or (chip:IsShown() and chip or bar)
  panel:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -6)
  drawPanel()
end

function UI.SetHidden(hidden)
  root:SetShown(not hidden and MG.db.shown ~= false)
end

function UI.Toggle()
  MG.db.shown = not root:IsShown()
  root:SetShown(MG.db.shown)
  MG.Refresh(true) -- 目標按鈕跟著顯示／隱藏（戰鬥中會等脫離戰鬥）
end

-- ── 檢查報告（可複製） ──────────────────────────────────────────────────────
function UI.ShowReport(body)
  if not report then
    report = CreateFrame("Frame", "MetroGuideReport", UIParent)
    report:SetSize(600, 440)
    report:SetPoint("CENTER")
    report:SetFrameStrata("DIALOG")
    report:EnableMouse(true)
    report:SetMovable(true)
    report:RegisterForDrag("LeftButton")
    report:SetScript("OnDragStart", report.StartMoving)
    report:SetScript("OnDragStop", report.StopMovingOrSizing)
    box(report)
    local head = text(report, 13, DIM)
    head:SetPoint("TOPLEFT", 12, -10)
    head:SetText("地鐵升級 檢查報告：Ctrl+A 全選、Ctrl+C 複製，貼回給開發者")
    local close = CreateFrame("Button", nil, report)
    close:SetSize(48, 22); close:SetPoint("TOPRIGHT", -8, -6)
    close.label = text(close, 13, GOLD, "CENTER"); close.label:SetPoint("CENTER"); close.label:SetText("關閉")
    close:SetScript("OnClick", function() report:Hide() end)
    local sf = CreateFrame("ScrollFrame", nil, report)
    sf:SetPoint("TOPLEFT", 12, -34); sf:SetPoint("BOTTOMRIGHT", -12, 12)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(FONT, 12, "")
    eb:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    eb:SetWidth(570)
    eb:SetScript("OnEscapePressed", function() report:Hide() end)
    sf:SetScrollChild(eb)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
      local v = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40))
      self:SetVerticalScroll(v)
    end)
    report.eb = eb
  end
  local _, lines = body:gsub("\n", "")
  report.eb:SetHeight((lines + 2) * 15)
  report.eb:SetText(body)
  report:Show()
  report.eb:SetFocus()
  report.eb:HighlightText()
end
