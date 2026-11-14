-- 介面：目前步驟列、建議鈕、展開面板（步驟／路線）、右鍵選單、檢查報告視窗。只讀引擎結果，操作只送意圖。
local _, MG = ...
local E, C = MG.E, MG.C
local L = MG.L
local UI = {}
MG.UI = UI

-- 客戶端的標準字型（中文客戶端是中文字型；英文客戶端沒有中文字，所以顯示的字串一律過 MG.Clean）
local FONT = STANDARD_TEXT_FONT or (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"
local BG = { 0.055, 0.059, 0.071, 0.88 }
local EDGE = { 0.165, 0.176, 0.204 }
local TEXT = { 0.91, 0.894, 0.847 }
local DIM = { 0.545, 0.561, 0.596 }
local FAINT = { 0.333, 0.349, 0.384 }
local GOLD = { 0.851, 0.698, 0.373 }
local AMBER = { 0.878, 0.569, 0.227 }
local GREEN = { 0.435, 0.749, 0.451 }
local EDGE2 = { 0.263, 0.282, 0.325 } -- 步驟列內分隔線、動詞方框
local BRONZE = { 0.427, 0.353, 0.184 } -- 可按的東西
local RED = { 0.851, 0.380, 0.310 } -- 只給「危險」
local ROW_H, MAX_ROWS = 20, 30
-- 字串內上色：|cffrrggbb
local function hex(c) return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end

-- 設定表：設定頁、右鍵選單、套用都讀這裡。acct＝帳號共用（其餘每角色）。預設值＝原本的樣子。
local SPEC = {
  { section = "步驟列" },
  { key = "barScale", label = "縮放", min = 70, max = 150, step = 5, def = 100, unit = "%" },
  { key = "barWidth", label = "寬度", min = 240, max = 480, step = 10, def = 300 },
  { key = "fadeOn", label = "滑鼠不在上面或戰鬥中時淡出", def = false, hint = "滑鼠移開或進入戰鬥時，步驟列變淡；滑鼠移上去就恢復。" },
  { key = "fontSize", label = "字體大小", min = 11, max = 20, step = 1, def = 15 },
  { key = "groupOn", label = "同時顯示附近任務", def = true, hint = "接下來幾步裡地點相近的任務一起列出，順手一起做。" },
  { key = "groupMax", label = "最多同時顯示", min = 1, max = 5, step = 1, def = 3, hint = "一起列出的任務最多幾個（含目前這步）。" },
  { key = "locked", label = "鎖定位置", def = false, menu = true },
  { button = "重設位置", run = function() MG.db.pos = nil end },
  { section = "展開清單" },
  { key = "listWidth", label = "寬度", min = 280, max = 600, step = 10, def = 320 },
  { key = "showDone", label = "顯示已完成步驟", def = true },
  { section = "地圖標點" },
  { key = "pinSize", label = "世界地圖標點大小", min = 14, max = 40, step = 1, def = 24 },
  { section = "提醒" },
  { key = "trainOn", label = "學技能", def = true, hint = "到了職業訓練師有新技能的等級時，在路線中插入「去學技能」步驟。" },
  { key = "supplyOn", label = "修裝與飛行點", def = true, hint = "耐久低時提醒修裝；經過還沒開的飛行管理員時提醒。" },
  { key = "dangerOn", label = "危險", def = true, hint = "走近容易拉到一堆怪的地點時，在步驟列下方提醒怎麼應對。" },
  { key = "detourOn", label = "順路", def = true, hint = "附近有比目前步驟近很多、現在就能接、做或交的任務時，提醒你順路處理。" },
  { key = "keepOn", label = "別賣的物品", def = true, hint = "背包物品的滑鼠提示加一行之後任務會用到。" },
  { key = "dungeonHint", label = "可以下副本", def = true, hint = "等級到了副本建議等級時，提示可以去哪個副本，以及前置還差多少。" },
  { section = "目標與物品" },
  { key = "showTarget", label = "顯示目標按鈕", def = true, hint = "步驟列上的準星按鈕：點一下選取這步要找的怪或 NPC，也能綁快捷鍵。" },
  { key = "markOn", label = "選取時標上團隊標記", def = true, hint = "用目標按鈕或巨集選到目標時，順便標上團隊標記。" },
  { key = "showItem", label = "顯示任務物品按鈕", def = true, hint = "目前任務有可使用的物品時，在步驟列旁顯示物品按鈕，點了就使用。" },
  { button = "建立巨集", run = function() MG.T.MakeMacro() end, hint = "建立「任務目標」巨集並拿在滑鼠上，放到快捷列就能一鍵選取目標。" },
  { section = "副本" },
  { key = "dPre", label = "順路接副本前置", def = true, hint = "把副本的前置任務排進主線，在附近的站順路接、做、交。" },
  { key = "dungeonOnly", label = "副本中只顯示副本任務", def = true, hint = "在副本裡只列出這個副本的任務（一次全列），不顯示主線步驟、箭頭和地圖標點；對不到副本或沒有任務時整個隱藏，出副本後恢復。" },
  { section = "其他" },
  { key = "arrow", label = "箭頭與地圖標點", def = true, menu = true, hint = "顯示指向目前步驟的箭頭，以及世界地圖和小地圖上的路線標點。" },
  { key = "auto", label = "自動接交任務", def = true, menu = true, hint = "和 NPC 對話時自動接、交路線上的任務。按住 Shift 可暫停。" },
  { key = "optional", label = "帶上可跳過的任務", def = false, menu = true, hint = "路線也帶上標為可跳過的任務；已接的不論開關都會列出。" },
  { start = true, hint = "選擇從哪個新手區開始的路線，預設是你種族的那條。" },
  { lang = true, label = "介面語言" },
  { key = "minimap", label = "顯示小地圖按鈕", def = true },
  { button = "重新對齊", run = function() E.Realign() end, hint = "依目前的等級和任務重新找所在的站，並清掉這站的手動勾選。" },
  { section = "進階", fold = true },
  { sub = "步驟列" },
  { key = "barAlpha", label = "背景透明度", min = 0, max = 100, step = 5, def = 88, unit = "%" },
  { key = "barOpacity", label = "整體透明度", hint = "包含文字。", min = 0, max = 100, step = 5, def = 100, unit = "%" },
  { key = "fadeAlpha", label = "淡出時透明度", min = 0, max = 100, step = 5, def = 40, unit = "%" },
  { key = "objRows", label = "最多顯示目標行數", min = 1, max = 5, step = 1, def = 5 },
  { key = "showCount", label = "顯示剩餘步數", def = false, hint = "步驟列右上角顯示這一站還剩幾步。" },
  { key = "showLevel", label = "顯示任務等級", def = false },
  { key = "groupDist", label = "附近距離", hint = "以地圖寬度的 % 計。", min = 2, max = 20, step = 1, def = 8 },
  { sub = "提示框" },
  { key = "tipScale", label = "大小", min = 70, max = 150, step = 5, def = 100, unit = "%", acct = true, tip = true },
  { key = "tipX", label = "水平位置", min = -300, max = 300, step = 5, def = 0, acct = true, tip = true, hint = "步驟提示框相對步驟列和清單的偏移。" },
  { key = "tipY", label = "垂直位置", min = -300, max = 300, step = 5, def = 0, acct = true, tip = true, hint = "步驟提示框相對步驟列和清單的偏移。" },
  { key = "tipAlpha", label = "背景透明度", min = 0, max = 100, step = 5, def = 100, unit = "%", acct = true, tip = true },
  { key = "tipDesc", label = "顯示說明行", def = true, acct = true, tip = true, hint = "步驟提示框最後加上這步的補充說明。" },
  { sub = "展開清單" },
  { key = "listAlpha", label = "背景透明度", min = 0, max = 100, step = 5, def = 88, unit = "%" },
  { key = "listRows", label = "高度（行數）", min = 8, max = MAX_ROWS, step = 1, def = 18 },
  { key = "showNum", label = "顯示步驟編號", def = true },
  { sub = "地圖標點" },
  { key = "miniPinSize", label = "小地圖標點大小", min = 10, max = 30, step = 1, def = 15 },
  { key = "miniSteps", label = "小地圖顯示幾步", min = 0, max = 5, step = 1, def = 3, hint = "小地圖標出從目前這步起的幾個位置；0 不標。" },
  { key = "pinAlpha", label = "標點透明度", min = 30, max = 100, step = 5, def = 100, unit = "%" },
  { key = "pinMergeX", label = "合併距離", hint = "標點大小的幾倍內合成一個。", min = 0, max = 3, step = 0.1, def = 1.1 },
  { sub = "提醒" },
  { key = "detourDist", label = "順路距離", min = 1, max = 8, step = 0.5, def = 3, hint = "以地圖寬度的 % 計。" },
  { sub = "目標與物品" },
  { key = "markIcon", label = "標記圖示", def = 1, choices = { "星星", "圓圈", "鑽石", "三角", "月亮", "方塊", "叉叉", "骷髏" } },
  { key = "itemPos", label = "任務物品位置", def = 1, choices = { "步驟列內", "左側", "右側" } },
  { key = "itemSize", label = "任務物品大小", min = 20, max = 48, step = 2, def = 32, hint = "放在左側或右側時的大小。" },
  { key = "itemMacro", label = "自動建立任務物品巨集", def = true, hint = "建立帳號巨集「任務物品」，內容自動改成使用目前步驟的任務物品（戰鬥中等脫離戰鬥再改）。" },
  { key = "autoMacro", label = "自動建立目標巨集", def = true, hint = "登入時若沒有「任務目標」巨集就自動建立（帳號巨集有空位時）。刪掉後下次登入會再建立；關掉這項就不會。" },
  { sub = "其他" },
  { key = "miniBtnAlpha", label = "小地圖按鈕透明度", min = 0, max = 100, step = 5, def = 100, unit = "%" },
  { key = "rec", label = "遊戲內記錄", def = true, acct = true, hint = "記下任務 NPC 與座標、經驗表、飛行點，用來修正路線。/slv rec export 匯出。" },
  { section = "" },
  { button = "全部重設為預設", all = true },
}
local SPEC_BY = {}
for _, sp in ipairs(SPEC) do if sp.key then SPEC_BY[sp.key] = sp end end
local function store(sp) return sp.acct and MetroGuideDB or MG.db end
-- 字較長的介面語言：步驟列、清單的預設寬加大，平常任務名、站名不用截斷（只改預設；玩家調過的值照用）
local LOCALE_DEF = {
  deDE = { barWidth = 330, listWidth = 420 },
  frFR = { barWidth = 310, listWidth = 370 },
  esES = { barWidth = 310, listWidth = 380 },
  esMX = { barWidth = 310, listWidth = 390 },
  ruRU = { barWidth = 350, listWidth = 450 },
  ptBR = { barWidth = 310, listWidth = 380 },
}
function UI.Get(key)
  local sp = SPEC_BY[key]
  local v = store(sp)[key]
  if v == nil then return LOCALE_DEF[MG.uiLoc] and LOCALE_DEF[MG.uiLoc][key] or sp.def end
  if sp.choices and type(v) ~= "number" then return sp.def end -- 舊版設定頁把選項畫成勾選框，可能存了 true/false
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

-- 站名（短名＋淡色的第幾次）；完整名字在滑鼠提示
function UI.StName(st)
  return (st.short or st.name or "") .. (st.visit and (hex(DIM) .. "(" .. st.visit .. ")|r") or "")
end
-- 文字被截斷了嗎（被截才需要滑鼠提示）
local function truncated(fs)
  if fs.IsTruncated then return fs:IsTruncated() end
  return fs:GetStringWidth() > fs:GetWidth() + 0.5
end

-- 字串一律過 MG.Clean（非中文介面不會漏出中文字）
local function clean(fs)
  local set = fs.SetText
  fs.SetText = function(self, t) return set(self, MG.Clean(t)) end
  return fs
end
UI.Clean = clean
local function addLine(t, r, g, b, wrap) GameTooltip:AddLine(MG.Clean(t), r, g, b, wrap) end
-- 量字寬（按鈕、欄寬依實際字串）
local measure
local function textWidth(t, size)
  if not measure then measure = UIParent:CreateFontString(nil, "OVERLAY"); measure:Hide() end
  measure:SetFont(FONT, size, "")
  measure:SetText(MG.Clean(t))
  return math.ceil(measure:GetStringWidth() or 0)
end
UI.TextWidth = textWidth
-- 清單動詞欄寬：中文固定 18；其他語言量最長的動詞
local verbW
function UI.VerbWidth()
  if MG.uiZh then return 18 end
  if not verbW then
    verbW = 18
    for _, t in ipairs({ "accept", "do", "turnin", "goto", "fp", "hearth", "fly", "boat", "level", "travel", "need", "train" }) do verbW = math.max(verbW, textWidth(E.VERB[t] or "", 13) + 2) end
    for _, v in ipairs({ L["打"], L["去"] }) do verbW = math.max(verbW, textWidth(v, 13) + 2) end -- 練怪列、副本入口列也用這欄
  end
  return verbW
end
local function text(parent, size, color, justify)
  local s = clean(parent:CreateFontString(nil, "OVERLAY"))
  s:SetFont(FONT, size, "")
  s:SetTextColor(color[1], color[2], color[3])
  s:SetJustifyH(justify or "LEFT")
  s:SetWordWrap(false)
  return s
end
-- 會換行的字：最多 n 行；中文沒有空白也要能斷行
local function wrapLines(fs, n)
  fs:SetWordWrap(true)
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
  if fs.SetMaxLines then fs:SetMaxLines(n) end
end
-- 臨時航點（不是目前步驟）：tab＝從清單哪個分頁設的（換到別的分頁就收回）；keep＝走到了也不收（練怪點）；done()＝目的達成就收回
-- 收回時箭頭回到目前步驟；手動收回只走提示列「前往 … 返回」（點步驟列只開關清單）
function UI.SetOverride(o) MG.wpOverride = o; MG.Refresh(true) end
function UI.ClearOverride()
  MG.wpOverride, MG.grindActive = nil, nil
  MG.N.Forget(true)
  MG.Refresh(true)
end
local function clearTabOverride(t)
  local o = MG.wpOverride
  if o and o.tab and o.tab ~= t then UI.ClearOverride() end
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

local root, bar, panel, menu, report, more
local hints = {} -- 提示列（同一個元件，最多顯示 2 條）
local rows, items = {}, {}
local scroll, tab, missOpen, lastCurKey = 0, "steps", false, nil
local impOpen, preOpen, preSeen = false, false, nil
local state -- 最近一次 Render 的引擎結果

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
  for _, f in ipairs({ bar.l2, bar.l2n, bar.l3, unpack(bar.objs) }) do f:SetFont(FONT, fsz - 2, "") end
  for _, f in ipairs(bar.objN) do f:SetFont(FONT, fsz - 2, "") end
  bar.verb:SetFont(FONT, fsz - 3, ""); bar.lv:SetFont(FONT, fsz - 3, "")
  for _, h in ipairs(hints) do
    for _, f in ipairs({ h.tag, h.label, h.act.label, h.x.label }) do f:SetFont(FONT, fsz - 2, "") end
    h.sub:SetFont(FONT, fsz - 3, "")
  end
  local lw = UI.Get("listWidth")
  panel:SetWidth(lw)
  for _, row in ipairs(rows) do row:SetWidth(lw - 2); row.para:SetWidth(lw - 2 - 28 - 12) end
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
local function toggleSetting(sp) UI.Set(sp.key, not UI.Get(sp.key)) end

local showMenu
-- 介面語言：跟隨客戶端，或客戶端字型顯示得出來的語言（中文、韓文、俄文字型以外都是拉丁字母；英文到處都能顯示）
local SCRIPT = { zhTW = "zh", zhCN = "zh", koKR = "ko", ruRU = "ru" }
local function langOpts()
  local all = { { nil, L["跟隨客戶端"] }, { "zh", "繁體中文", "zhTW" }, { "zhcn", "简体中文", "zhCN" }, { "en", "English", "enUS" }, { "dede", "Deutsch", "deDE" },
    { "frfr", "Français", "frFR" }, { "eses", "Español (EU)", "esES" }, { "esmx", "Español (AL)", "esMX" }, { "ptbr", "Português (BR)", "ptBR" },
    { "ruru", "Русский", "ruRU" }, { "kokr", "한국어", "koKR" } }
  local cur = MetroGuideDB.lang and MG.LANGS[MetroGuideDB.lang:lower()]
  local out = {}
  for _, o in ipairs(all) do
    if not o[3] or o[3] == "enUS" or (SCRIPT[o[3]] or "latin") == (SCRIPT[MG.gameLoc] or "latin") then
      out[#out + 1] = { code = o[1], name = o[2], on = o[3] == cur }
    end
  end
  if not cur then out[1].on = true end
  return out
end

local function openMenu(anchor)
  if menu:IsShown() then menu:Hide(); return end
  local entries = {}
  local cur = state and state.cur and state.steps[state.cur]
  if cur then entries[#entries + 1] = { L["略過這步"], function() E.ToggleSkip(cur.key) end } end
  if cur and cur.s.share == 1 and cur.s.q and C.IsOnQuest(cur.s.q) and IsInGroup and IsInGroup() then
    entries[#entries + 1] = { L["分享這個任務"], function() C.ShareQuest(cur.s.q) end }
  end
  entries[#entries + 1] = { L["重新對齊"], function() E.Realign() end }
  for _, sp in ipairs(SPEC) do
    if sp.menu then entries[#entries + 1] = { L[sp.label], function() toggleSetting(sp) end, UI.Get(sp.key) } end
  end
  entries[#entries + 1] = { L["設定"], function() UI.OpenOptions() end }
  showMenu(anchor, entries)
end

-- 選單：entries = { { 文字, 動作, 勾選狀態（nil＝沒有勾選框） } }；from＝設定頁的按鈕時開在按鈕下方
function showMenu(anchor, entries, below)
  -- 選單寬度跟著最長的字
  local mw = 150
  for _, e in ipairs(entries) do mw = math.max(mw, textWidth(e[1], 13) + 26 + 12) end
  for i, e in ipairs(entries) do
    local b = menu.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetHeight(22)
      b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 22)
      b.label = text(b, 13, TEXT)
      b.label:SetPoint("LEFT", 26, 0)
      b.cb = UI.Checkbox(b, 13)
      b.cb:SetPoint("LEFT", 6, 0)
      b.cb:EnableMouse(false)
      local hl = b:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
      menu.buttons[i] = b
    end
    b.label:SetText(e[1])
    b:SetWidth(mw)
    b.cb:SetShown(e[3] ~= nil)
    b.cb:SetState(e[3] and "check" or nil)
    b:SetScript("OnClick", function() menu:Hide(); e[2](); UI.ApplySettings(); MG.Refresh(true) end)
    b:Show()
  end
  for i = #entries + 1, #menu.buttons do menu.buttons[i]:Hide() end
  menu:SetHeight(12 + #entries * 22)
  menu:SetWidth(mw + 12)
  menu:ClearAllPoints()
  if below then menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  elseif anchor == bar then menu:SetPoint("TOPLEFT", bar, "TOPRIGHT", 4, 0)
  else menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0) end
  menu:Show()
end

-- ── 步驟提示（步驟列、清單、地圖標點共用） ────────────────────────────────
-- 提示框：大小（只在我們顯示時改，關閉時還原）
local tipScaled, tipOld
local function tipRestore()
  if tipScaled then GameTooltip:SetScale(tipOld); C.TooltipAlpha(GameTooltip, nil); tipScaled = false end
end
local function tipScale()
  if not tipScaled then
    if not tipOld then
      GameTooltip:HookScript("OnHide", tipRestore)
      if hooksecurefunc then hooksecurefunc(GameTooltip, "SetOwner", tipRestore) end
    end
    tipOld = GameTooltip:GetScale()
  end
  GameTooltip:SetScale((tipOld or 1) * UI.Get("tipScale") / 100)
  C.TooltipAlpha(GameTooltip, UI.Get("tipAlpha") / 100)
  tipScaled = true
end

-- 一般提示框：金色標題＋內文／補充（顏色、大小、透明度統一）
local function tipOpen(owner, title, anchor)
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  tipScale()
  addLine(title, GOLD[1], GOLD[2], GOLD[3])
end
UI.TipOpen = tipOpen
local function tipLine(t, c, wrap) c = c or TEXT; addLine(t, c[1], c[2], c[3], wrap) end
UI.TipLine = tipLine
-- 站的完整資訊提示：全名、地區、等級、進度
local function stationTip(owner, st, extra)
  tipOpen(owner, st.name or "")
  local got, total = E.Progress(st)
  local zone = st.map and C.MapName(st.map)
  tipLine((zone and (zone .. "  ") or "") .. st.lv[1] .. "-" .. st.lv[2] .. (total > 0 and ("  " .. got .. "/" .. total) or ""), DIM)
  for _, l in ipairs(extra or {}) do tipLine(l, AMBER, true) end
  GameTooltip:Show()
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
  addLine((prefix or "") .. E.VerbTitle(s), GOLD[1], GOLD[2], GOLD[3])
  if s.npc then addLine(s.npc, TEXT[1], TEXT[2], TEXT[3]) end
  if s.t == "travel" and s.text then addLine(s.text, TEXT[1], TEXT[2], TEXT[3], true) end
  if s.q then
    local same = MG.sameLang -- 任務日誌的文字是客戶端語言：和介面同語言才用
    local objText
    if same then objText = select(2, C.QuestText(s.q)) end
    local info = MG.Route.quests[s.q]
    local body = objText and objText ~= "" and objText or (info and info.d) or s.hint
    if body then addLine(body, DIM[1], DIM[2], DIM[3], true) end
    for _, o in ipairs(C.Objectives(s.q) or {}) do
      if o.need then
        local c = o.done and GREEN or TEXT
        addLine((same and o.text or L["目標"]) .. "  " .. (o.have or 0) .. "/" .. o.need, c[1], c[2], c[3])
      end
    end
  end
  if s.pickLv or s.recLv or s.share then
    local bits = {}
    if s.pickLv then bits[#bits + 1] = L["%d 級可接"]:format(s.pickLv) end
    if s.recLv then bits[#bits + 1] = L["建議 %d 級"]:format(s.recLv) end
    if s.share == 1 then bits[#bits + 1] = L["可共享"] elseif s.share == 0 then bits[#bits + 1] = L["不可共享"] elseif s.share == 2 then bits[#bits + 1] = L["共享未確認"] end
    addLine(table.concat(bits, "  "), DIM[1], DIM[2], DIM[3])
  end
  if s.preText then addLine(L["前置 "] .. s.preText, DIM[1], DIM[2], DIM[3], true) end
  local star = E.StarFor(s.q, s)
  if star then addLine("★ " .. star, GOLD[1], GOLD[2], GOLD[3], true) end
  if s.desc and UI.Get("tipDesc") then addLine(s.desc, TEXT[1], TEXT[2], TEXT[3], true) end
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
  return L["無"]
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
    -- 少了前置（到站時自動展開一次）
    local pre = E.MissingPre(state.st)
    if #pre > 0 then
      if preSeen ~= state.st.id then preSeen, preOpen = state.st.id, true end
      items[#items + 1] = { kind = "prehead", n = #pre }
      if preOpen then for _, m in ipairs(pre) do items[#items + 1] = { kind = "pre", m = m } end end
    end
    -- 離站前：還有會影響後續的任務
    local leave = UI.Leaving(state)
    if #leave > 0 then
      items[#items + 1] = { kind = "imphead", n = #leave }
      if impOpen then for _, m in ipairs(leave) do items[#items + 1] = { kind = "imp", m = m } end end
    end
    if #state.missed > 0 then
      items[#items + 1] = { kind = "misshead" }
      if missOpen then
        for _, m in ipairs(state.missed) do items[#items + 1] = { kind = "miss", m = m } end
      end
    end
    for i, step in ipairs(state.steps) do
      local hideDone = not UI.Get("showDone") and state.done[i] and i ~= state.cur
      if (not state.na[i] or MG.db.skip[step.key] or step.defer or MG.db.notNow[step.key]) and not hideDone then items[#items + 1] = { kind = "step", i = i, step = step } end
    end
    local grind = state.st and state.st.grind
    if grind and #grind > 0 then
      items[#items + 1] = { kind = "ghead", n = #grind }
      if UI.grindOpen then for _, g in ipairs(grind) do items[#items + 1] = { kind = "grind", g = g } end end
    end
    local sup, dan = E.SupplyFor(state.st), state.st.danger or {}
    if #sup + #dan > 0 then
      items[#items + 1] = { kind = "shead", n = #sup + #dan }
      if UI.supOpen then
        for _, d in ipairs(dan) do items[#items + 1] = { kind = "spot", p = d, label = L["危險 "] .. (d.text or L["危險區域"]), warn = true } end
        for _, s in ipairs(sup) do items[#items + 1] = { kind = "spot", p = s, label = L[s.k] .. (s.npc and (" " .. s.npc) or "") } end
      end
    end
  elseif tab == "dg" then
    -- 副本分頁 v2（DUNGEON-TAB-SPEC.md）
    UI.dPhase, UI.dChain, UI.dMore = UI.dPhase or {}, UI.dChain or {}, UI.dMore or {}
    -- 已過的副本收成最上面一列「▸ 已過 N」（正在跑或展開中的不收）
    local function folded(d) return select(2, E.DungeonStatus(d)) == "past" and UI.dOpen ~= d.id and not (state.st == d) end
    local past = 0
    for _, d in ipairs(E.dungeons) do if folded(d) then past = past + 1 end end
    if past > 0 then items[#items + 1] = { kind = "dpast", n = past } end
    for _, d in ipairs(E.dungeons) do
      if not folded(d) or UI.dPastOpen then items[#items + 1] = { kind = "dg", d = d } end
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
            if tip.k == "動線" then
              -- 「→」是多位元組字，用純文字搜尋切開，不能放進樣式字元類別
              local n, rest = 0, tip.text
              while rest do
                local a, b = rest:find("→", 1, true)
                local part = strtrim(a and rest:sub(1, a - 1) or rest)
                rest = b and rest:sub(b + 1)
                if part ~= "" then n = n + 1; items[#items + 1] = { kind = "dtext", text = n .. ". " .. part } end
              end
            elseif tip.k == "取捨" then
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
  row.mini:Hide()
  row.name:SetFont(FONT, 13, "")
  local top = it.kind == "dnext"
  local function at(f, x, w)
    f:ClearAllPoints()
    if top then f:SetPoint("TOPLEFT", x, -6) else f:SetPoint("LEFT", x, 0) end
    if w then f:SetWidth(w) end
  end
  -- 動詞欄寬：中文一個字 18；其他語言量最長的動詞
  local vw = UI.VerbWidth()
  at(row.ck, 8, 14); at(row.box, 9); at(row.no, 24, 20); at(row.verb, 48, vw)
  row.prog:ClearAllPoints()
  if top then row.prog:SetPoint("TOPRIGHT", -12, -7) else row.prog:SetPoint("RIGHT", -12, 0) end
  -- 右欄最小寬（對齊用）；有字才佔位，實際寬在最後照字量
  local PROG_W = { shead = 1, spot = 70, prehead = 1, pre = 1, imphead = 1, imp = 120, step = 1, miss = 120, misshead = 1, station = 44, start = 1, ghead = 1, grind = 70, dg = 62, dtext = 1, dhead = 1, dnext = 84, dphase = 1, dq = 96, dch = 90, dqi = 50, dent = 70, dact = 1, dpast = 1 }
  row.prog:SetWidth(PROG_W[it.kind] or 64)
  -- 沒有動詞欄的列：名稱從 28 開始
  local NAME_X = { dtext = 28, dhead = 28, dg = 26, dq = 28, dent = 28, dphase = 28, dact = 28, prehead = 28, imphead = 28, misshead = 28, shead = 28, ghead = 28, dpast = 28, pre = 28, imp = 28, miss = 28, spot = 28, station = 28, start = 28 }
  row.name:ClearAllPoints()
  if top then row.name:SetPoint("TOPLEFT", 52 + vw, -5) else row.name:SetPoint("LEFT", NAME_X[it.kind] or (52 + vw), 0) end
  row.name:SetPoint("RIGHT", (it.kind == "dg" or it.kind == "station") and row.lvt or row.prog, "LEFT", -6, 0)
  row.box:Hide(); row.ck:Show()
  -- 收合標題：箭頭（和副本列同一個圖）
  local HEAD = { prehead = { L["少了前置"], preOpen, AMBER }, imphead = { L["影響後續"], impOpen, AMBER }, misshead = { L["漏掉"], missOpen, AMBER },
    ghead = { L["練怪地點"], UI.grindOpen, DIM }, shead = { L["補給"], UI.supOpen, DIM }, dpast = { L["已過"], UI.dPastOpen, DIM } }
  -- 影響後續的短說明（右欄）：下一站或後面幾個接不到
  local function impShort(imp)
    local nx = E.Next(state.st)
    local onlyNext = true
    for _, x in ipairs(imp) do if x.st ~= nx then onlyNext = false end end
    return L[onlyNext and "下一站 %d 個接不到" or "後面 %d 個接不到"]:format(#imp)
  end
  local head = HEAD[it.kind]
  if head then
    row.ck:SetText("")
    row.arrow:Show(); row.arrow:SetRotation(head[2] and -math.pi / 2 or 0); row.arrow:SetVertexColor(head[3][1], head[3][2], head[3][3])
    row.name:SetText(head[1] .. " " .. (it.n or #state.missed)); paint(row.name, head[3])
  elseif it.kind == "pre" then
    local m = it.m
    row.name:SetText(E.Title({ t = "accept", q = m.p }) .. " → " .. E.Title({ t = "accept", q = m.q })); paint(row.name, DIM)
    if m.can then row.mini.label:SetText(L["補做"]); row.mini:SetWidth(row.mini.label:GetStringWidth() + 12); row.mini.m = m; row.mini:Show(); row.name:SetPoint("RIGHT", row.mini, "LEFT", -6, 0) end
  elseif it.kind == "imp" then
    row.name:SetText(E.Title({ t = "accept", q = it.m.q })); paint(row.name, TEXT)
    row.prog:SetText(impShort(it.m.imp)); paint(row.prog, AMBER)
  elseif it.kind == "miss" then
    local q = it.m.q
    local imp = E.Impact(q, state.st)
    row.name:SetText(E.QName(q)); paint(row.name, TEXT)
    if #imp > 0 then row.prog:SetText(impShort(imp)); paint(row.prog, AMBER) end
  elseif it.kind == "step" then
    local i, s = it.i, it.step.s
    local skipped = MG.db.skip[it.step.key]
    local mark = MG.db.mark[it.step.key]
    row.ck:Hide(); row.box:Show()
    row.no:SetText(UI.Get("showNum") and state.num[i] or ""); paint(row.no, DIM)
    -- 勾選框：自動完成＝綠勾、手動完成＝金勾、手動未完成＝空框加琥珀短線
    if mark == false then row.box:SetState("dash", AMBER)
    elseif state.done[i] and not state.na[i] and not (state.passed and state.passed[i]) then row.box:SetState("check", mark and GOLD or GREEN)
    else row.box:SetState(nil) end
    row.verb:SetText(E.Verb(s))
    row.name:SetText((E.StarFor(s.q, s) and (hex(GOLD) .. "★|r ") or "") .. E.Title(s))
    -- 狀態一律放右欄（灰）；目前步驟的進度優先
    local status
    if skipped then status = L["略過"]
    elseif MG.db.notNow[it.step.key] then status = L["接不到"]
    elseif it.step.defer then status = L["之後"]
    elseif not state.done[i] then
      if it.step.carry then status = L["補做"]
      elseif s.q and state.fill[s.q] then status = L["補經驗"]
      elseif it.step.dungeon then status = L["副本"] end
    end
    if status then row.prog:SetText(status); paint(row.prog, skipped and FAINT or DIM) end
    if state.inGroup[i] then row.strip:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45); row.strip:Show() end
    if i == state.cur then
      row.cur:Show(); row.strip:Show()
      if s.t == "do" and s.q then
        local obj = C.Objectives(s.q) or {}
        if #obj > 1 then
          local d = 0
          for _, o in ipairs(obj) do if o.done then d = d + 1 end end
          row.prog:SetText(d .. "/" .. #obj); paint(row.prog, TEXT)
        end
        for _, o in ipairs(#obj == 1 and obj or {}) do
          if not o.done and o.need then row.prog:SetText(o.have .. "/" .. o.need); paint(row.prog, TEXT); break end
        end
      end
    elseif skipped then
      paint(row.name, FAINT); paint(row.verb, FAINT)
    elseif state.done[i] then
      paint(row.name, FAINT); paint(row.verb, FAINT)
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
    if MG.db.dNo[d.id] then label = L["不打"] end
    row.prog:SetText(label)
    paint(row.prog, (kind == "past" or kind == "low" or MG.db.dNo[d.id]) and FAINT or (label == L["可以去"] and GREEN) or (kind == "pick" and AMBER) or GOLD)
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
        title = L["%s入口"]:format(d.name)
        row.verb:SetText(L["去"])
        right = ent.coord
        sub = ent.zone .. (ent.door ~= "" and ("  " .. ent.door) or "")
      else
        row.box:Show(); row.ck:Hide()
        row.box:SetState(nil)
        row.verb:SetText(E.Verb(s))
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
      { "pre", L["前置 "] .. (got >= total and hex(GREEN) .. got .. "/" .. total .. "|r" or (got .. "/" .. total)) },
      { "in", L["副本內 "] .. count("in") },
      { "post", L["出本交 "] .. count("post") },
    }
    row.name:SetText("")
    row.bgx:Show()
    -- 分頁依字寬排；一列放不下就換到下一列（列跟著變高）
    local rowW, x, line = UI.Get("listWidth") - 2, 22, 0
    for k, b in ipairs(row.tabs) do
      b.phase = labels[k][1]
      b.label:SetText(labels[k][2])
      local on = it.phase == labels[k][1]
      b.label:SetTextColor(unpack(on and TEXT or DIM))
      b.under:SetShown(on)
      local bw = math.ceil(b.label:GetStringWidth() or 0) + 12
      b:SetWidth(bw)
      if x > 22 and x + bw > rowW - 10 then x, line = 22, line + 1 end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", x, -1 - line * 20)
      x = x + bw + 4
      b:Show()
    end
    row:SetHeight(22 + line * 20)
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
    if low then row.prog:SetText(L["%d 級"]:format(s.pickLv))
    elseif chainN > 0 and chainDone < chainN then row.prog:SetText(L["鏈 "] .. chainDone .. "/" .. chainN .. (UI.dChain[t.q] and " -" or " +"))
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
      row.ck:SetText(""); row.box:Show(); row.box:SetState("check", GREEN); row.box:ClearAllPoints(); row.box:SetPoint("LEFT", 54, 0)
      row.name:SetText(name); paint(row.name, FAINT)
    elseif C.IsOnQuest(q) or (it.isNext) then
      row.ck:SetText("→"); paint(row.ck, GOLD); row.name:SetText(name); paint(row.name, GOLD)
      local obj = C.IsOnQuest(q) and C.Objectives(q) or {}
      local prog = ""
      for _, o in ipairs(obj) do if not o.done and o.need then prog = L["做 "] .. o.have .. "/" .. o.need; break end end
      row.prog:SetText(prog ~= "" and prog or (C.IsOnQuest(q) and L["交"] or L["接"]))
    else
      row.ck:SetText("‧"); paint(row.ck, DIM); row.name:SetText(name); paint(row.name, DIM)
      row.prog:SetText(C.MapName(step.s.map) or "")
    end
    if not allDone then row.ck:ClearAllPoints(); row.ck:SetPoint("LEFT", 54, 0) end
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
    row.verb:SetText(E.Verb(s))
    row.name:SetText(s.q and E.Title({ q = s.q, t = "accept" }) or (s.text or s.hint or "")); paint(row.name, cur and TEXT or FAINT)
    if s.q and C.IsOnQuest(s.q) then
      local obj = C.Objectives(s.q) or {}
      for _, o in ipairs(obj) do if o.need then row.prog:SetText((o.have or 0) .. "/" .. o.need); break end end
    end
  elseif it.kind == "dent" then
    local ent = UI.Entrance(it.d)
    row.bgx:Show()
    row.icon:Show()
    -- 座標獨立放右欄（不會被截）；區域＋分區門是可截的文字（滑鼠提示看全文）
    row.name:SetText(ent.zone .. (ent.door ~= "" and ("  " .. ent.door) or "")); paint(row.name, DIM)
    row.prog:SetText(ent.coord); paint(row.prog, DIM)
  elseif it.kind == "dact" then
    local d = it.d
    row.bgx:Show()
    row.name:SetText("")
    local running = state and state.st == d
    local _, kind = E.DungeonStatus(d)
    local inactive = kind == "past" or MG.db.dNo[d.id]
    local b1, b2, b3 = row.acts[1], row.acts[2], row.acts[3]
    b1:SetShown(not inactive or running)
    b1.label:SetText(running and L["回主線"] or L["設為目標"])
    b1.label:SetTextColor(unpack(running and TEXT or GOLD))
    b1.fill:SetShown(not running)
    b1:SetWidth(b1.label:GetStringWidth() + 28)
    b1.act = running and "back" or "run"
    b2.label:SetText(L["詳細"]); b2.label:SetTextColor(unpack(UI.dMore[d.id] and TEXT or DIM)); b2.act = "more"
    b2.arrow:SetRotation(UI.dMore[d.id] and -math.pi / 2 or 0); b2.arrow:SetVertexColor(unpack(UI.dMore[d.id] and TEXT or DIM))
    b3.label:SetText(MG.db.dNo[d.id] and L["要打"] or L["不打"]); b3.label:SetTextColor(unpack(DIM)); b3.act = "no"
    -- 按鈕依字寬（「詳細」接在「不打」左邊）
    b3:SetWidth(math.max(56, b3.label:GetStringWidth() + 16))
    b2:SetWidth(math.max(56, b2.label:GetStringWidth() + 26))
    -- 三顆一列放不下（英文、窄清單）：第一顆獨立放上一行，不互相重疊
    local stack = b1:IsShown() and 26 + b1:GetWidth() + 8 + b2:GetWidth() - 2 + b3:GetWidth() + 10 > UI.Get("listWidth") - 2
    b1:ClearAllPoints(); b3:ClearAllPoints()
    if stack then b1:SetPoint("TOPLEFT", 26, -3); b3:SetPoint("BOTTOMRIGHT", -10, 3)
    else b1:SetPoint("LEFT", 26, 0); b3:SetPoint("RIGHT", -10, 0) end
    b2:ClearAllPoints(); b2:SetPoint("RIGHT", b3, "LEFT", 2, 0)
    for _, b in ipairs(row.acts) do b.d = d end
    b2:Show(); b3:Show()
    row:SetHeight(stack and 52 or 26)
  elseif it.kind == "dtext" then
    row.name:SetText("")
    row.bgx:Show()
    row.para:SetFont(FONT, 12, "")
    row.para:SetText((it.text:gsub("「(.-)」", hex(GOLD) .. "%1|r"))); paint(row.para, DIM); row.para:Show()
    row:SetHeight(math.max(ROW_H, (row.para:GetStringHeight() or 14) + 6))
  elseif it.kind == "dhead" then
    row.name:SetText(it.text); paint(row.name, GOLD)
  elseif it.kind == "shead" then
    row.ck:SetText(UI.supOpen and "-" or "+"); paint(row.ck, DIM)
    row.name:SetText(L["補給"] .. " " .. it.n); paint(row.name, DIM)
  elseif it.kind == "spot" then
    row.name:SetText(it.label); paint(row.name, it.warn and RED or TEXT)
    row.prog:SetText(string.format("%.1f, %.1f", it.p.x, it.p.y))
  elseif it.kind == "ghead" then
    row.ck:SetText(UI.grindOpen and "-" or "+"); paint(row.ck, DIM)
    row.name:SetText(L["練怪地點"] .. " " .. it.n); paint(row.name, DIM)
  elseif it.kind == "grind" then
    local g = it.g
    local active = MG.grindActive == g
    row.verb:SetText(L["打"]); paint(row.verb, active and GOLD or DIM)
    row.name:SetText(g.mob .. " " .. g.lv[1] .. "-" .. g.lv[2]); paint(row.name, active and GOLD or TEXT)
    row.prog:SetText(string.format("%.1f, %.1f", g.x, g.y))
  elseif it.kind == "start" then
    row.ck:SetText(it.on and "●" or "○"); paint(row.ck, it.on and GOLD or DIM)
    row.name:SetText(L["起點："] .. it.s.name); paint(row.name, it.on and TEXT or DIM)
  elseif it.kind == "station" then
    local st = it.st
    local got, total = E.Progress(st)
    local lv = UnitLevel("player") or 1
    row.name:SetText(UI.StName(st) .. (st.test and L["（測試）"] or ""))
    row.lvt:SetText(st.lv[1] .. "-" .. st.lv[2]); row.lvt:Show()
    paint(row.lvt, (lv >= st.lv[1] and lv <= st.lv[2]) and GOLD or FAINT)
    row.prog:SetText(got .. "/" .. total)
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
  -- 右欄放得下實際的字（英文較寬）；空的不佔位；最多列寬 45%，再長就截斷（滑鼠提示看全文）
  local tw = (row.prog:GetText() or "") ~= "" and math.ceil(row.prog:GetStringWidth() or 0) + 2 or 0
  row.prog:SetWidth(tw > 0 and math.min(math.max(PROG_W[it.kind] or 64, tw), math.floor((UI.Get("listWidth") - 2) * 0.45)) or 1)
  row:Show()
end

local function drawPanel()
  if not panel:IsShown() then return end
  buildItems()
  -- 捲動上限＝最後一列剛好貼底：從最後一列往回量，量到放不下為止（副本分頁幾種列高度不一，要實際填過才知道）
  local full = UI.Rows() * ROW_H
  local maxScroll, fit = #items, 0
  local TALL = { dnext = true, dphase = true, dact = true, dtext = true }
  while maxScroll > 0 do
    local h = ROW_H
    if TALL[items[maxScroll].kind] then fillRow(rows[1], items[maxScroll]); h = rows[1]:GetHeight() or ROW_H end
    if fit + h > full then break end
    fit, maxScroll = fit + h, maxScroll - 1
  end
  if maxScroll == #items and maxScroll > 0 then maxScroll = maxScroll - 1 end -- 最後一列本身就比一頁高
  if scroll > maxScroll then scroll = maxScroll end
  -- 清單高度＝內容高度（最少 6 行，最多設定的行數）
  local listH = maxScroll > 0 and full or math.max(6 * ROW_H, math.min(full, fit))
  panel:SetHeight(34 + listH + 8)
  local y, room = -34, listH
  local shown, curShown = 0, false
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
        shown = shown + 1
        if it.kind == "step" and state and it.i == state.cur then curShown = true end
      end
    else
      row:Hide()
    end
  end
  -- 右緣 2 px 捲動條（內容不滿一頁不畫）
  panel.sbar:SetShown(maxScroll > 0)
  if maxScroll > 0 then
    local th = math.max(12, math.floor(listH * shown / #items))
    panel.sbar:ClearAllPoints()
    panel.sbar:SetPoint("TOPRIGHT", -2, -34 - math.floor((listH - th) * scroll / maxScroll))
    panel.sbar:SetHeight(th)
  end
  panel.tabSteps.label:SetTextColor(unpack(tab == "steps" and TEXT or DIM))
  panel.tabMap.label:SetTextColor(unpack(tab == "map" and TEXT or DIM))
  panel.tabSteps.under:SetShown(tab == "steps")
  panel.tabMap.under:SetShown(tab == "map")
  panel.tabDg.label:SetTextColor(unpack(tab == "dg" and TEXT or DIM))
  panel.tabDg.under:SetShown(tab == "dg")
  -- 右上角：文字可截（有滑鼠提示）；站的等級範圍獨立一欄（不會被截）
  local st = state and state.st
  local full, short, lvText = "", nil, ""
  if tab == "steps" and state and state.total > 0 then
    full = L["剩 %d 步"]:format(state.total)
  elseif tab == "dg" then
    local n, lv = 0, UnitLevel("player") or 1
    for _, d in ipairs(E.dungeons) do
      local _, kind = E.DungeonStatus(d)
      if kind ~= "past" and kind ~= "low" and lv >= d.lv[1] - 2 and not MG.db.dNo[d.id] then n = n + 1 end
    end
    full, short = L["%d 級可去 %d 本"]:format(lv, n), L["%d 級：%d 本"]:format(lv, n)
  elseif st then
    full, lvText = UI.StName(st), st.lv[1] .. "-" .. st.lv[2]
  end
  panel.stationLv:SetText(lvText)
  panel.stationLv:SetWidth(lvText ~= "" and math.ceil(panel.stationLv:GetStringWidth() or 0) + 2 or 1)
  panel.station:SetPoint("RIGHT", panel.stationLv, "LEFT", lvText ~= "" and -6 or 0, 0)
  panel.station.full, panel.station.isSt, panel.station.short = full, lvText ~= "", false
  panel.station:SetText(full)
  if short and truncated(panel.station) then panel.station:SetText(short); panel.station.short = true end
  -- 目前步驟捲出畫面：「剩 N 步」變金色，點了捲回
  panel.station.back = tab == "steps" and state and state.cur and not curShown or false
  paint(panel.station, panel.station.back and GOLD or DIM)
end

local function scrollToCur()
  buildItems()
  if tab == "dg" then
    -- 副本：正在跑的那本，否則第一本還沒過、沒標「不打」的；上一列是「已過 N」就連它一起露出
    local target
    for k, it in ipairs(items) do
      if it.kind == "dg" and state.st == it.d then target = k; break end
    end
    if not target then
      for k, it in ipairs(items) do
        if it.kind == "dg" and select(2, E.DungeonStatus(it.d)) ~= "past" and not MG.db.dNo[it.d.id] then target = k; break end
      end
    end
    if target then
      scroll = target - 1
      if items[scroll] and items[scroll].kind == "dpast" then scroll = scroll - 1 end
    end
    return
  end
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
  local door = (d.entrance or ""):match("（(.-)）") or (not MG.uiZh and (d.entrance or ""):match("%((.-)%)")) or ""
  local zone = C.MapName(d.map) or ((d.entrance or ""):match("^(%S+)") or "")
  return { x = x, y = y, coord = x and string.format("%.1f, %.1f", x, y) or "", zone = zone, door = door }
end
-- 「要離站」：本站做完、輪到站尾交通，或目前是交通／爐石而後面只剩被跳過的任務（同任務前面有沒做的步驟）
local MOVE = { travel = true, fly = true, boat = true, hearth = true }
function UI.Leaving(S)
  if not S or S.instance or not S.steps then return {} end
  local i = S.cur
  if i and not (S.tails and S.tails[i]) then
    if not MOVE[S.steps[i].s.t] then return {} end
    local behind = {}
    for k = 1, i - 1 do
      local q = S.steps[k].s.q
      if q and not S.done[k] and not S.na[k] then behind[q] = true end
    end
    for j = i + 1, #S.steps do
      local q = S.steps[j].s.q
      if q and not S.done[j] and not S.na[j] and not behind[q] then return {} end
    end
  end
  return E.Leaving(S)
end
-- 練怪點：走到了不收（在那裡打），升過這個點的等級就收回
function UI.GoGrind(g)
  MG.grindActive = g
  UI.SetOverride({ map = g.map, x = g.x, y = g.y, name = MG.Clean(L["打 "] .. g.mob), keep = true, grind = true,
    done = function() return (UnitLevel("player") or 1) > g.lv[2] end })
end
-- 副本分頁設的點：換回步驟／路線分頁、收起這本副本、出副本、走到了都收回
function UI.WaypointStep(s)
  if s and s.x then UI.SetOverride({ map = s.map, x = s.x, y = s.y, name = MG.Clean(E.Title(s)), tab = "dg" }) end
end
function UI.WaypointEntrance(d)
  local ent = UI.Entrance(d)
  if ent.x then UI.SetOverride({ map = d.map, x = ent.x, y = ent.y, name = MG.Clean(L["%s入口"]:format(d.name)), tab = "dg" }) end
end
function UI.DungeonAction(act, d)
  if act == "run" then E.RunDungeon(d); tab = "steps"; scroll = 0; lastCurKey = nil; MG.wpOverride = nil; MG.N.Forget(true)
  elseif act == "back" then MG.db.station = MG.db.dungeonFrom; MG.db.dungeonFrom = nil; lastCurKey = nil; MG.wpOverride = nil; MG.N.Forget(true)
  elseif act == "more" then UI.dMore[d.id] = not UI.dMore[d.id] or nil; UI.ScrollToDungeon(d)
  elseif act == "no" then MG.db.dNo[d.id] = not MG.db.dNo[d.id] or nil; UI.dOpen = nil; clearTabOverride() end
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
  clearTabOverride(t) -- 離開設點的分頁（例如副本分頁）：箭頭回到目前步驟
  tab = t
  scroll = 0
  if state then scrollToCur() end
  drawPanel()
end

local function onRowClick(row, button)
  local it = row.it
  if not it then return end
  if it.kind == "prehead" then preOpen = not preOpen
  elseif it.kind == "imphead" then impOpen = not impOpen
  elseif it.kind == "imp" then
    if button == "RightButton" then E.ToggleSkip(state.steps[it.m.i].key) else E.PinIndex(state, it.m.i) end
  elseif it.kind == "misshead" then missOpen = not missOpen
  elseif it.kind == "miss" then E.PinIndex(state, it.m.i)
  elseif it.kind == "step" then
    if button == "RightButton" then E.ToggleSkip(it.step.key) else E.PinIndex(state, it.i) end
  elseif it.kind == "shead" then
    UI.supOpen = not UI.supOpen
  elseif it.kind == "spot" then
    MG.wpOverride = { map = it.p.map, x = it.p.x, y = it.p.y, name = MG.Clean(it.label) } -- 走到了就收回
  elseif it.kind == "ghead" then
    UI.grindOpen = not UI.grindOpen
  elseif it.kind == "dpast" then
    UI.dPastOpen = not UI.dPastOpen
  elseif it.kind == "grind" then
    UI.GoGrind(it.g)
  elseif it.kind == "dg" then
    local d = it.d
    if UI.dOpen == d.id then UI.dOpen = nil; UI.dPhase[d.id] = nil; clearTabOverride() else UI.dOpen = d.id end
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
  local vb = box(bar.verbBox, EDGE2)
  vb:SetColorTexture(0, 0, 0, 0)
  bar.verb = text(bar.verbBox, 12, GOLD, "CENTER")
  bar.verb:SetPoint("CENTER", 0, 0)
  bar.lv = text(bar, 12, DIM, "RIGHT")
  bar.lv:SetPoint("TOPRIGHT", -32, -13)
  -- 右上角齒輪：開設定頁
  local gear = CreateFrame("Button", nil, bar)
  gear:SetSize(20, 20) -- 點擊範圍（和目標鈕一樣大、同一行）
  gear:SetPoint("TOPRIGHT", -6, -9)
  gear.icon = gear:CreateTexture(nil, "ARTWORK")
  gear.icon:SetSize(16, 16)
  gear.icon:SetPoint("CENTER")
  C.GearIcon(gear.icon, 16)
  gear:SetAlpha(0.3) -- 亮度在步驟列的 OnUpdate 依滑鼠位置調
  gear:SetScript("OnEnter", function(self)
    tipOpen(self, L["設定"], "ANCHOR_TOP")
    GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
  gear:SetScript("OnClick", function() UI.OpenOptions() end)
  -- 標題最多兩行（寬度在 Render 照右側元件算）
  bar.title = text(bar, 15, TEXT)
  bar.title:SetPoint("TOPLEFT", 40, -12)
  wrapLines(bar.title, 2)
  bar.l2 = text(bar, 13, DIM)
  bar.l2:SetPoint("TOPLEFT", 40, -34)
  -- 目標的數字（3/8）各自一欄：右對齊、量寬，文字截斷時數字還在
  bar.l2n = text(bar, 13, TEXT, "RIGHT")
  bar.objs, bar.objN = {}, {}
  for k = 1, 5 do bar.objs[k] = text(bar, 13, TEXT); bar.objN[k] = text(bar, 13, TEXT, "RIGHT") end
  bar.extra, bar.extraN, bar.divs = {}, {}, {}
  for k = 1, 40 do
    bar.extra[k] = text(bar, 13, TEXT); bar.extra[k]:Hide()
    bar.extraN[k] = text(bar, 13, TEXT, "RIGHT"); bar.extraN[k]:Hide()
  end
  for k = 1, 4 do
    local d = bar:CreateTexture(nil, "ARTWORK")
    d:SetColorTexture(EDGE2[1], EDGE2[2], EDGE2[3], 1)
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
    -- 只開關清單；臨時航點只由提示列的「返回」收回。沒有臨時航點時順便重放目前步驟的航點（玩家手動清掉的會補回）
    if not MG.wpOverride then MG.N.Forget(true); MG.Refresh(true) end
    panel:SetShown(not panel:IsShown())
    if panel:IsShown() and state then scrollToCur() end
    drawPanel()
  end)
  bar:SetScript("OnEnter", function(self)
    local cur = state and state.cur and state.steps[state.cur]
    if cur then
      UI.StepTooltip(self, cur.s, nil, true)
      -- 附近一起做的任務（步驟列上可能被截）：完整標題與目標
      local same = MG.sameLang
      for _, i in ipairs(state.group or {}) do
        local s = state.steps[i].s
        addLine(" ", 1, 1, 1)
        addLine(E.VerbTitle(s), TEXT[1], TEXT[2], TEXT[3], true)
        if s.t == "do" and s.q then
          for _, o in ipairs(C.Objectives(s.q) or {}) do
            if o.need then addLine((same and o.text or L["目標"]) .. "  " .. (o.have or 0) .. "/" .. o.need, DIM[1], DIM[2], DIM[3], true) end
          end
        elseif s.npc then addLine(s.npc, DIM[1], DIM[2], DIM[3], true) end
      end
      GameTooltip:Show()
    elseif state and state.st and E.Next(state.st) then stationTip(self, E.Next(state.st)) end
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Shift＋滾輪換步驟；沒按 Shift 時不接滾輪（滾輪照常拉鏡頭）
  local wheelOn, gearA = false, 0.3
  bar:EnableMouseWheel(false)
  bar:SetScript("OnMouseWheel", function(_, delta)
    if IsShiftKeyDown() and state and state.st then E.Move(state, delta > 0 and -1 or 1); MG.Refresh(true) end
  end)
  -- 步驟切換：0.15 秒淡入；完成：綠光一閃
  local fade, flash = 1, 0
  bar:SetScript("OnUpdate", function(_, dt)
    local alpha = UI.Get("barOpacity") / 100
    if UI.Get("fadeOn") and (InCombatLockdown() or not root:IsMouseOver()) then alpha = UI.Get("fadeAlpha") / 100 end
    if root:GetAlpha() ~= alpha then root:SetAlpha(alpha) end
    local shift = IsShiftKeyDown()
    -- 步驟列掛著安全按鈕：戰鬥中不能改滑鼠設定，等脫離戰鬥再切
    if shift ~= wheelOn and not InCombatLockdown() then wheelOn = shift; bar:EnableMouseWheel(shift) end
    -- 齒輪少用：平常 30%，滑鼠在步驟列上 70%，指著齒輪 100%
    local ga = gear:IsMouseOver() and 1 or (bar:IsMouseOver() and 0.7 or 0.3)
    if ga ~= gearA then gearA = ga; gear:SetAlpha(ga) end
    if fade < 1 then fade = math.min(1, fade + dt / 0.15); bar.title:SetAlpha(fade); bar.l2:SetAlpha(fade); bar.l3:SetAlpha(fade); bar.verb:SetAlpha(fade) end
    if flash > 0 then flash = math.max(0, flash - dt / 0.35); bar.flash:SetAlpha(flash) end
  end)
  function UI.Animate(done) fade = 0; if done then flash = 1 end end

  -- 提示：┃標籤 內容 補充        [動作] ×（色條＋標籤同色；動作與 × 固定在右側，沒有就留空）
  local function hintRow()
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(300, 24)
    box(f)
    f.strip = f:CreateTexture(nil, "ARTWORK")
    f.strip:SetPoint("TOPLEFT", 1, -1); f.strip:SetPoint("BOTTOMLEFT", 1, 1); f.strip:SetWidth(3)
    f.tag = text(f, 13, GOLD)
    f.tag:SetPoint("LEFT", 10, 0)
    f.label = text(f, 13, TEXT)
    f.label:SetPoint("LEFT", f.tag, "RIGHT", 8, 0)
    wrapLines(f.label, 2) -- 太長就換到第二行（最多兩行），列跟著變高
    f.sub = text(f, 12, DIM) -- 補充（等級範圍、前置數量）：位置與寬度在 Render 量
    f.sub:SetPoint("LEFT", f.label, "RIGHT", 6, 0)
    f.act = goldButton(f, "", 28)
    f.act:SetHeight(18); f.act:SetPoint("RIGHT", -24, 0)
    f.act:SetScript("OnClick", function() if f.h and f.h.act then f.h.act() end end)
    f.x = CreateFrame("Button", nil, f)
    f.x:SetSize(20, 20); f.x:SetPoint("RIGHT", -2, 0)
    f.x.label = text(f.x, 13, DIM, "CENTER"); f.x.label:SetPoint("CENTER"); f.x.label:SetText("×")
    f.x:SetScript("OnClick", function() if f.h and f.h.close then f.h.close(); MG.Refresh(true) end end)
    -- 滑鼠移上去看完整內容（太長換行後還放不下、或只顯示了第一句時）
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
      local h = self.h
      if not h then return end
      if h.tip then h.tip(self); return end
      local full = h.full or h.text
      local sub = h.sub ~= "" and h.sub or nil
      if not full or (full == h.text and not truncated(self.label) and not (sub and truncated(self.sub))) then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 0, 0)
      GameTooltip:SetText(MG.Clean(h.tag), h.color[1], h.color[2], h.color[3])
      addLine(full, 1, 1, 1, true)
      if sub then addLine(sub, DIM[1], DIM[2], DIM[3], true) end
      GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
  end
  for k = 1, 9 do hints[k] = hintRow() end
  more = CreateFrame("Button", nil, root)
  more:SetSize(60, 16)
  more.label = text(more, 11, DIM)
  more.label:SetPoint("LEFT", 2, 0)
  more:SetScript("OnClick", function() UI.hintsAll = true; MG.Refresh(true) end)
  more:Hide()

  -- 保留物品：背包物品提示加「別賣」
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
      MG.try("保留物品提示", function()
        local keep = MG.Route.keep
        if tip ~= GameTooltip or not keep or not UI.Get("keepOn") then return end
        local id = data and data.id
        if not id or (issecretvalue and issecretvalue(id)) then return end
        local k = keep[id]
        if not k or (k.q and E.Turned(k.q)) then return end
        local st = k.q and E.QuestStation(k.q)
        local line = k.q and (L["別賣："] .. E.Title({ t = "accept", q = k.q }) .. (st and L["（%s）"]:format(UI.StName(st)) or "") .. L["會用到"]) or (k.use and (k.use:find("^別賣") and k.use or (L["別賣："] .. k.use)))
        if line then tip:AddLine(MG.Clean(line), AMBER[1], AMBER[2], AMBER[3], true) end
      end)
    end)
  end

  panel = CreateFrame("Frame", nil, root)
  panel:SetSize(320, 34 + 18 * ROW_H + 8)
  panel.bg = box(panel)
  local function tabButton(label, prev, t)
    local b = CreateFrame("Button", nil, panel)
    b.label = text(b, 14, DIM, "CENTER")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(L[label])
    b:SetSize(math.max(56, math.ceil(b.label:GetStringWidth() or 0) + 16), 30) -- 依字寬
    if prev then b:SetPoint("TOPLEFT", prev, "TOPRIGHT", 0, 0) else b:SetPoint("TOPLEFT", 6, 0) end
    b.under = b:CreateTexture(nil, "ARTWORK")
    b.under:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    b.under:SetPoint("BOTTOMLEFT", 8, 0); b.under:SetPoint("BOTTOMRIGHT", -8, 0); b.under:SetHeight(2)
    b:SetScript("OnClick", function() setTab(t) end)
    return b
  end
  panel.tabSteps = tabButton("步驟", nil, "steps")
  panel.tabMap = tabButton("路線", panel.tabSteps, "map")
  panel.tabDg = tabButton("副本", panel.tabMap, "dg")
  local st = CreateFrame("Button", nil, panel)
  st:SetHeight(30)
  st:SetPoint("TOPLEFT", panel.tabDg, "TOPRIGHT", 6, 0)
  st:SetPoint("TOPRIGHT", -8, 0)
  panel.stationLv = text(st, 12, DIM, "RIGHT")
  panel.stationLv:SetPoint("TOPRIGHT"); panel.stationLv:SetPoint("BOTTOMRIGHT")
  panel.station = text(st, 12, DIM, "RIGHT")
  panel.station:SetPoint("TOPLEFT"); panel.station:SetPoint("BOTTOMLEFT")
  panel.station:SetPoint("RIGHT", panel.stationLv, "LEFT", 0, 0)
  st:SetScript("OnClick", function()
    if panel.station.back then scrollToCur(); drawPanel() else setTab("map") end
  end)
  st:SetScript("OnEnter", function(self)
    local s = panel.station
    if s.isSt then
      if state and state.st and (truncated(s) or state.st.short) then stationTip(self, state.st) end
    elseif s.full and s.full ~= "" and (s.short or truncated(s)) then
      tipOpen(self, s.full); GameTooltip:Show()
    end
  end)
  st:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.sbar = panel:CreateTexture(nil, "OVERLAY")
  panel.sbar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
  panel.sbar:SetWidth(2)
  panel.sbar:Hide()
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
    row.box:SetHitRectInsets(-4, -4, -4, -4) -- 點擊範圍約 21×21，外觀不變（旁邊整列是「改做這一步」）
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
      if not (it and it.kind == "step") then return end
      local i, key = it.i, it.step.key
      if button == "RightButton" then E.SetMark(key, nil)
      else
        local want = not state.done[i]
        if want == state.autoDone[i] then E.SetMark(key, nil) else E.SetMark(key, want) end
      end
      MG.Refresh(true)
    end)
    row.no = text(row, 11, DIM, "RIGHT")
    row.no:SetPoint("LEFT", 24, 0); row.no:SetWidth(20)
    row.verb = text(row, 13, GOLD, "CENTER")
    row.verb:SetPoint("LEFT", 48, 0); row.verb:SetWidth(UI.VerbWidth())
    row.prog = text(row, 12, DIM, "RIGHT")
    row.lvt = text(row, 12, FAINT, "RIGHT")
    row.lvt:SetPoint("RIGHT", row.prog, "LEFT", -4, 0)
    row.lvt:SetText("00-00"); row.lvt:SetWidth(math.ceil((row.lvt:GetStringWidth() or 34) + 4)); row.lvt:SetText(""); row.lvt:Hide()
    row.prog:SetPoint("RIGHT", -12, 0)
    row.para = clean(row:CreateFontString(nil, "OVERLAY"))
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
    row.icon:SetTexture("Interface\\AddOns\\ShengLeveling\\Media\\pin_circle_base"); row.icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3]); row.icon:Hide()
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
      elseif k == 2 then
        b:SetPoint("RIGHT", -64, 0)
        b.arrow = b:CreateTexture(nil, "ARTWORK")
        b.arrow:SetSize(10, 10); b.arrow:SetPoint("LEFT", b.label, "RIGHT", 2, 0)
        b.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
      else b:SetPoint("RIGHT", -10, 0) end
      b:SetScript("OnClick", function(self) UI.DungeonAction(self.act, self.d) end)
      b:Hide()
      row.acts[k] = b
    end
    -- 列內小鈕（補做）
    row.mini = goldButton(row, "", 40)
    row.mini:SetHeight(18); row.mini:SetPoint("RIGHT", -10, 0)
    row.mini:SetScript("OnClick", function(self) if self.m and state then E.MakeUp(state.st, self.m.p); MG.Refresh(true) end end)
    row.mini:Hide()
    row.name = text(row, 13, TEXT)
    row.name:SetPoint("LEFT", 70, 0)
    row.name:SetPoint("RIGHT", row.prog, "LEFT", -6, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", onRowClick)
    row:SetScript("OnEnter", function(self)
      local it = self.it
      if it and it.kind == "step" then UI.StepTooltip(self, it.step.s, nil, true)
      elseif it and it.kind == "dnext" and it.nx.step then UI.StepTooltip(self, it.nx.step.s, nil, true)
      elseif it and it.kind == "dq" then UI.StepTooltip(self, it.t.step.s, nil, true)
      elseif it and it.kind == "dqi" and it.step then UI.StepTooltip(self, it.step.s, nil, true)
      elseif it and it.kind == "dch" then UI.StepTooltip(self, it.steps[1].s, nil, true)
      elseif it and it.kind == "pre" then
        local m = it.m
        tipOpen(self, E.Title({ t = "accept", q = m.p }))
        tipLine(L["在 %s 接；沒做的話這裡的「%s」不能做"]:format(m.pst.name, E.Title({ t = "accept", q = m.q })), TEXT, true)
        if not m.can then tipLine(L["現在接不到（等級或前置不足）"], DIM) end
        GameTooltip:Show()
      elseif it and (it.kind == "imp" or it.kind == "miss") then
        local q = it.m.q
        local imp = it.kind == "imp" and it.m.imp or E.Impact(q, state.st)
        if it.kind == "miss" then UI.StepTooltip(self, state.steps[it.m.i].s, nil, true) else tipOpen(self, E.Title({ t = "accept", q = q })) end
        if #imp > 0 then tipLine(E.ImpactText(imp, state.st), AMBER, true) end
        GameTooltip:Show()
      elseif it and it.kind == "station" then
        local extra = {}
        for _, m in ipairs(E.MissingPre(it.st)) do extra[#extra + 1] = L["少了前置：%s（在 %s 接）→ 這裡的 %s 不能做"]:format(E.Title({ t = "accept", q = m.p }), m.pst.name, E.Title({ t = "accept", q = m.q })) end
        if #extra > 0 or truncated(self.name) or it.st.short then stationTip(self, it.st, extra) end
      elseif it and (truncated(self.name) or truncated(self.prog) or (self.sub:IsShown() and truncated(self.sub))) then
        -- 被截的列：名稱、右欄、副行都放進提示
        tipOpen(self, self.name:GetText() or "")
        if (self.prog:GetText() or "") ~= "" then tipLine(self.prog:GetText(), DIM, true) end
        if self.sub:IsShown() and (self.sub:GetText() or "") ~= "" then tipLine(self.sub:GetText(), DIM, true) end
        GameTooltip:Show()
      elseif it and it.kind == "grind" and it.g.note then
        tipOpen(self, it.g.mob); tipLine(it.g.note, TEXT, true); GameTooltip:Show() end
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

  menu = CreateFrame("Frame", "MetroGuideMenu", UIParent)
  menu:SetSize(162, 100)
  menu:SetFrameStrata("FULLSCREEN_DIALOG") -- 設定頁上的語言選單也要蓋得過
  box(menu)
  menu.buttons = {}
  menu:Hide()
  -- 關選單：Esc（UISpecialFrames）、點選單以外的地方、步驟列隱藏
  table.insert(UISpecialFrames, "MetroGuideMenu")
  pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
  menu:SetScript("OnEvent", function()
    if menu:IsShown() and not menu:IsMouseOver() and not bar:IsMouseOver() then menu:Hide() end -- 步驟列上的右鍵自己會開關
  end)
  root:HookScript("OnHide", function() menu:Hide() end)

  MG.try("小地圖按鈕", UI.CreateMinimap)
  -- 任務日誌（L）滑鼠提示：路線位置或路線外判定
  if QuestMapLogTitleButton_OnEnter and hooksecurefunc then
    hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(self)
      MG.try("任務日誌提示", function()
        local q = self.questID
        if not q or q == 0 then return end
        local where, v, why = E.QuestNote(q)
        addLine(where, GOLD[1], GOLD[2], GOLD[3])
        if v then
          local col = v == "值得做" and GREEN or (v == "可放掉" and DIM or AMBER)
          addLine(L[v] .. (why and (L["："] .. why) or ""), col[1], col[2], col[3], true)
        end
        GameTooltip:Show()
      end)
    end)
  end
  MG.try("設定頁", UI.CreateOptions)
  UI.Holder()
  MG.try("目標按鈕", MG.T.Create, holder)
  MG.try("任務物品", MG.I.Create, holder)
  local regen = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do pcall(regen.RegisterEvent, regen, e) end
  regen:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_ENABLED" or UI.holderPending or UI.settingsPending then UI.settingsPending = false; UI.holderTries = 0; UI.PlaceHolder() end
  end)
  root:HookScript("OnShow", function() UI.holderTries = 0; UI.PlaceHolder() end)
  UI.ApplySettings()
end

-- ── 小地圖按鈕 ──────────────────────────────────────────────────────────────
local mini
function UI.PlaceMinimap()
  if not mini then return end
  local a = math.rad(MetroGuideDB.angle or 200)
  local r = (Minimap:GetWidth() or 140) / 2 + 5 -- 系列統一：31 px、半徑 +5；預設角度 練等 200／專業 225／治療 250
  mini:ClearAllPoints()
  mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  mini:SetShown(UI.Get("minimap"))
  mini:SetAlpha(UI.Get("miniBtnAlpha") / 100)
end

function UI.CreateMinimap()
  if not Minimap then return end
  mini = CreateFrame("Button", "MetroGuideMinimapButton", Minimap)
  mini:SetSize(31, 31)
  mini:SetFrameStrata("MEDIUM")
  mini:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
  local bg = mini:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 7, -5); bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetVertexColor(BG[1], BG[2], BG[3], 1)
  local icon = mini:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 6, -5); icon:SetSize(21, 21)
  icon:SetTexture("Interface\\AddOns\\ShengLeveling\\Media\\Logo")
  icon:SetTexCoord(0.1, 0.9, 0.1, 0.9) -- 裁掉外框，圓形按鈕裡只留主體
  mini.icon, mini.Icon = icon, icon -- 小地圖按鈕收納插件會找這個欄位當圖示
  local ring = mini:CreateTexture(nil, "OVERLAY")
  ring:SetPoint("TOPLEFT"); ring:SetSize(53, 53)
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mini:RegisterForDrag("LeftButton")
  mini:SetScript("OnClick", function(self, button)
    if button == "RightButton" then UI.OpenOptions() else UI.Toggle() end
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
    tipOpen(self, L["阿聖練等幫手"], "ANCHOR_LEFT")
    tipLine(L["左鍵：開啟／關閉"], TEXT)
    tipLine(L["右鍵：設定"], TEXT)
    local st = state and state.st
    local cur = state and state.cur and state.steps[state.cur]
    tipLine(st and ((st.name or "") .. "  " .. st.lv[1] .. "-" .. st.lv[2]) or L["沒有路線"], TEXT)
    if st then addLine(cur and E.VerbTitle(cur.s) or L["本站完成"], DIM[1], DIM[2], DIM[3]) end
    GameTooltip:Show()
  end)
  mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ── 設定頁（選項 → 插件） ───────────────────────────────────────────────────
local options
-- 拖滑桿時在步驟列旁顯示一個範例提示框
function UI.PreviewTip()
  local cur = state and state.cur and state.steps[state.cur]
  UI.StepTooltip(bar, cur and cur.s or { t = "do", text = L["範例"], desc = L["這是說明行"] }, nil, true)
end

-- 版面：左邊標籤欄、控制欄（勾選框／滑桿／按鈕同一個 x）、數值欄與「重設」貼著內容右緣。
-- 寬度一律在顯示時照遊戲給的面板寬（options:GetWidth()）重排：標籤欄最多佔 45%，太長的標籤換行（列跟著變高），
-- 不會把右側元件推出面板；說明一律在滑鼠提示裡。
local COL_LABEL, ROW = 28, 26

function UI.CreateOptions()
  options = CreateFrame("Frame", "MetroGuideOptions", UIParent)
  options:Hide()
  local sf = CreateFrame("ScrollFrame", nil, options)
  sf:SetPoint("TOPLEFT", 0, -6); sf:SetPoint("BOTTOMRIGHT", -6, 6)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(560, 100)
  sf:SetScrollChild(content)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40)))
  end)
  local head = text(content, 18, GOLD)
  head:SetPoint("TOPLEFT", 16, -10)
  head:SetText(L["阿聖練等幫手"])
  options.widgets = {}
  local syncing = false
  local function changed(sp)
    UI.ApplySettings(); MG.Refresh(true)
    if sp and sp.tip then UI.PreviewTip() end
  end
  local lines = {} -- 依序的每一列，layout() 照面板寬排
  local lw, valueW = 0, textWidth("-000%", 13) + 4 -- 最長標籤、最寬數值
  -- 整列說明：滑鼠移到標籤或控制項上，標題＝標籤，內文＝說明
  local function explain(title, hint, ...)
    if not hint then return end
    local function show(self) tipOpen(self, title); tipLine(L[hint], TEXT, true); GameTooltip:Show() end
    local function hide() GameTooltip:Hide() end
    for _, f in ipairs({ ... }) do f:HookScript("OnEnter", show); f:HookScript("OnLeave", hide) end
  end
  local hits, layout = {}, nil -- 標籤 → 說明用的透明框；layout 在下面定義
  local function label(t, hint)
    local l = text(content, 13, TEXT)
    wrapLines(l, 3)
    l:SetText(L[t])
    lw = math.max(lw, textWidth(L[t], 13))
    if hint then -- 文字本身收不到滑鼠：蓋一層透明框
      local hit = CreateFrame("Frame", nil, content)
      hit:SetAllPoints(l); hit:EnableMouse(true)
      explain(L[t], hint, hit)
      hits[l] = hit
    end
    return l
  end
  local actions
  local section = { keys = {} }
  -- 一區結束：該區的動作按鈕排成一列（放不下就換行）
  local function flush()
    if actions and #actions > 0 then
      local btns = {}
      for _, sp in ipairs(actions) do
        local btn = goldButton(content, L[sp.button], math.max(120, textWidth(L[sp.button], 13) + 20))
        btn:SetScript("OnClick", function()
          if sp.all then
            for _, other in ipairs(SPEC) do if other.key then UI.Reset(other.key) end end
            MG.db.pos = nil
          else
            sp.run()
          end
          changed(); UI.RefreshOptions()
        end)
        explain(L[sp.button], sp.hint, btn)
        btns[#btns + 1] = btn
      end
      lines[#lines + 1] = { kind = "actions", btns = btns }
    end
    actions = {}
  end
  for _, sp in ipairs(SPEC) do
    if sp.section then
      flush()
      section = { keys = {} }
      local e = { kind = "section" }
      if sp.section ~= "" then
        e.h = text(content, 14, GOLD)
        e.h:SetText(L[sp.section])
        e.line = content:CreateTexture(nil, "ARTWORK")
        e.line:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.8)
        local sec = section
        e.reset = goldButton(content, L["重設"], math.max(52, textWidth(L["重設"], 13) + 16))
        e.reset:SetHeight(18)
        e.reset:SetScript("OnClick", function()
          for _, k in ipairs(sec.keys) do UI.Reset(k) end
          changed(); UI.RefreshOptions()
        end)
        if sp.fold then -- 摺疊區：點標題開合，開合記在帳號存檔
          e.fold = CreateFrame("Button", nil, content)
          e.fold:SetHeight(22)
          e.icon = e.fold:CreateTexture(nil, "ARTWORK")
          e.icon:SetSize(14, 14); e.icon:SetPoint("LEFT", 0, 0)
          e.fold:SetScript("OnClick", function() MetroGuideDB.advOpen = not MetroGuideDB.advOpen or nil; layout() end)
        end
      end
      lines[#lines + 1] = e
    elseif sp.sub then
      local e = { kind = "sub", h = text(content, 12, GOLD) }
      e.h:SetText(L[sp.sub])
      lines[#lines + 1] = e
    elseif sp.min then
      section.keys[#section.keys + 1] = sp.key
      local v = text(content, 13, DIM)
      for _, x in ipairs({ sp.min, sp.max, sp.def }) do valueW = math.max(valueW, textWidth(x .. (sp.unit or ""), 13) + 4) end
      local slider = C.Slider(content, sp.min, sp.max, sp.step, UI.Get(sp.key), function(val)
        if syncing then return end
        UI.Set(sp.key, val)
        v:SetText(val .. (sp.unit or ""))
        changed(sp)
      end)
      explain(L[sp.label], sp.hint, slider, slider.kind == "minimal" and slider.Slider or nil)
      options.widgets[#options.widgets + 1] = { refresh = function()
        syncing = true; C.SliderSet(slider, UI.Get(sp.key)); syncing = false
        v:SetText(UI.Get(sp.key) .. (sp.unit or ""))
      end }
      lines[#lines + 1] = { kind = "slider", label = label(sp.label, sp.hint), ctrl = slider, value = v, dy = 4 }
    elseif sp.key and not sp.choices then
      section.keys[#section.keys + 1] = sp.key
      local cb = UI.Checkbox(content, 16)
      cb:SetScript("OnClick", function() toggleSetting(sp); changed(sp); UI.RefreshOptions() end)
      explain(L[sp.label], sp.hint, cb)
      options.widgets[#options.widgets + 1] = { refresh = function() cb:SetState(UI.Get(sp.key) and "check" or nil) end }
      lines[#lines + 1] = { kind = "check", label = label(sp.label, sp.hint), ctrl = cb, dy = 4 }
    elseif sp.choices then
      section.keys[#section.keys + 1] = sp.key
      local cw = 160
      for _, c in ipairs(sp.choices) do cw = math.max(cw, textWidth(L[c], 13) + 20) end
      local btn = goldButton(content, "", cw)
      btn:SetScript("OnClick", function() UI.Set(sp.key, UI.Get(sp.key) % #sp.choices + 1); changed(sp); UI.RefreshOptions() end)
      explain(L[sp.label], sp.hint, btn)
      options.widgets[#options.widgets + 1] = { refresh = function() btn.label:SetText(L[sp.choices[UI.Get(sp.key)] or ""]) end }
      lines[#lines + 1] = { kind = "button", label = label(sp.label, sp.hint), ctrl = btn, want = cw, dy = 2 }
    elseif sp.start then
      local sw = 160
      for _, s in ipairs(E.Starts()) do sw = math.max(sw, textWidth(s.name, 13) + 20) end
      local btn = goldButton(content, "", sw)
      btn:SetScript("OnClick", function() cycleStart(); changed(); UI.RefreshOptions() end)
      explain(L["起點"], sp.hint, btn)
      options.widgets[#options.widgets + 1] = { refresh = function() btn.label:SetText(startLabel()) end }
      lines[#lines + 1] = { kind = "button", label = label("起點", sp.hint), ctrl = btn, want = sw, dy = 2 }
    elseif sp.lang then
      -- 語言在載入時決定：選好後要 /reload（插件不能自己重新載入，會被遊戲擋下）
      local opts = langOpts()
      local lw2 = 160
      for _, o in ipairs(opts) do lw2 = math.max(lw2, textWidth(o.name, 13) + 20) end
      local btn = goldButton(content, "", lw2)
      btn:SetScript("OnClick", function(self)
        local es = {}
        for _, o in ipairs(langOpts()) do es[#es + 1] = { o.name, function() if not o.on then MetroGuideDB.lang = o.code; MG.msg(L["介面語言設為 %s，/reload 後生效"]:format(o.name)); UI.RefreshOptions() end end, o.on } end
        showMenu(self, es, true)
      end)
      options.widgets[#options.widgets + 1] = { refresh = function()
        for _, o in ipairs(langOpts()) do if o.on then btn.label:SetText(o.name) end end
      end }
      lines[#lines + 1] = { kind = "button", label = label(sp.label), ctrl = btn, want = lw2, dy = 2 }
    elseif sp.button then
      actions[#actions + 1] = sp
    end
  end
  flush()
  -- 摺疊區裡的列（到下一個區塊為止）
  local inFold = false
  for _, e in ipairs(lines) do
    if e.kind == "section" then inFold = e.fold ~= nil
    elseif inFold then e.adv = true end
  end
  function layout()
    local open = MetroGuideDB.advOpen
    local W = options:GetWidth() or 0
    if W < 300 then W = 600 end -- 還沒拿到面板寬（建立時）：先照常見寬度排，顯示時再照實際寬重排
    local R = W - 6 - 16 -- 內容右緣：ScrollFrame 右邊留 6，再留 16 邊距
    local valueX = R - valueW
    local labelW = math.min(math.max(lw, 176), math.floor((R - COL_LABEL) * 0.45))
    local ctrlX = COL_LABEL + labelW + 16
    head:SetWidth(R - 16)
    local y = -44
    for _, e in ipairs(lines) do
      local shown = not e.adv or open
      for _, r in pairs({ e.h, e.label, hits[e.label], e.ctrl, e.value }) do r:SetShown(shown) end
      for _, b in ipairs(e.btns or {}) do b:SetShown(shown) end
      if not shown then -- 收起的列不佔位置
      elseif e.kind == "section" then
        y = y - 12
        if e.h then
          local x = e.fold and 16 + 18 or 16
          e.reset:ClearAllPoints(); e.reset:SetPoint("TOPRIGHT", content, "TOPLEFT", R, y + 1)
          e.h:ClearAllPoints(); e.h:SetPoint("TOPLEFT", x, y); e.h:SetWidth(math.max(1, R - x - e.reset:GetWidth() - 8))
          e.line:ClearAllPoints(); e.line:SetPoint("TOPLEFT", 16, y - 20); e.line:SetSize(R - 16, 1)
          if e.fold then
            e.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            e.fold:ClearAllPoints(); e.fold:SetPoint("TOPLEFT", 16, y + 3); e.fold:SetWidth(math.max(1, R - 16 - e.reset:GetWidth() - 8))
          end
          y = y - 28
        end
      elseif e.kind == "sub" then
        y = y - 6
        e.h:ClearAllPoints(); e.h:SetPoint("TOPLEFT", 16, y); e.h:SetWidth(R - 16)
        y = y - 20
      elseif e.kind == "actions" then
        local x = COL_LABEL
        for _, b in ipairs(e.btns) do
          if x > COL_LABEL and x + b:GetWidth() > R then x, y = COL_LABEL, y - ROW end
          b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, y - 2)
          x = x + b:GetWidth() + 8
        end
        y = y - ROW - 4
      else
        e.label:ClearAllPoints(); e.label:SetPoint("TOPLEFT", COL_LABEL, y - 5)
        e.label:SetWidth(labelW); e.label:SetText(e.label:GetText()) -- 改寬後重設文字，行高才會照新寬算
        e.ctrl:ClearAllPoints(); e.ctrl:SetPoint("TOPLEFT", ctrlX, y - e.dy)
        if e.kind == "slider" then
          e.ctrl:SetWidth(math.max(60, valueX - 8 - ctrlX))
          e.value:ClearAllPoints(); e.value:SetPoint("TOPLEFT", valueX, y - 5); e.value:SetWidth(valueW)
        elseif e.want then
          local bw = math.min(e.want, R - ctrlX)
          e.ctrl:SetWidth(bw); e.ctrl.label:SetWidth(bw - 8)
        end
        y = y - math.max(ROW, math.ceil(e.label:GetStringHeight() or 0) + 10)
      end
    end
    content:SetSize(R + 16, -y + 20)
  end
  layout()
  options:SetScript("OnShow", function() layout(); UI.RefreshOptions() end)
  options:SetScript("OnSizeChanged", function(self) if self:IsShown() then layout() end end)
  options:SetScript("OnHide", function() if GameTooltip:GetOwner() == bar then GameTooltip:Hide() end end)
  C.RegisterOptions(options, MG.Clean(L["阿聖練等幫手"]))
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

-- 目標：只有一項時回傳一行文字與數字；多項時回傳 header 與每項 { text, num, done }（未完成在前）。數字（3/8）另外放，排版時獨立一欄
local function objectiveLines(q)
  local obj = C.Objectives(q)
  if not obj or #obj == 0 then return nil end
  local function count(o) return o.need and ((o.have or 0) .. "/" .. o.need) or nil end
  local same = MG.sameLang -- 目標文字是客戶端語言：和介面不同語言（預覽）時只顯示「目標 n/m」
  if #obj == 1 then
    local o = obj[1]
    return (o.text ~= "" and same and o.text or L["目標"]), nil, nil, count(o)
  end
  -- 共同動詞與共同字首（例：殺死 怨怒… → 欺詐者、喚魔者）
  local texts = {}
  for i, o in ipairs(obj) do texts[i] = same and o.text or "" end
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
    lines[#lines + 1] = { text = (o.done and "√ " or "") .. (texts[i] ~= "" and texts[i] or L["目標"]), num = count(o), done = o.done, i = i }
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
  local objList, l2num
  local strip = GOLD
  if not state then
    title = L["這個角色沒有路線"]
  elseif state.cur then
    local step = state.steps[state.cur]
    local s = step.s
    local info = s.q and MG.Route.quests[s.q]
    verb = E.Verb(s)
    title = E.Title(s)
    if state.tails and state.tails[state.cur] then title = L["前往下一站："] .. title end
    if E.StarFor(s.q, s) then title = hex(GOLD) .. "★|r " .. title end
    right = UI.Get("showLevel") and info and info.lvl and tostring(info.lvl) or ""
    if s.t == "accept" or s.t == "turnin" then l2 = s.npc
    elseif s.t == "do" then
      local one, header, lines, num = objectiveLines(s.q)
      if lines then l2, objList = header, lines else l2, l2num = one or s.hint, one and num end
    elseif s.t == "level" then l2 = L["目前 %d 級"]:format(lv)
    elseif s.t == "hearth" then l2 = L["找旅店老闆"]
    elseif s.t == "fp" then l2 = L["找飛行管理員"]
    elseif s.t == "travel" then l2 = s.text and select(2, E.Clause(s.text)) end
    if s.t == "turnin" and C.IsOnQuest(s.q) and E.Ready(s.q) then titleColor = GREEN end
    if info and info.min and lv < info.min then
      l3, l3warn = L["差 %d 級"]:format(info.min - lv), true
    elseif step.defer then
      l3, l3warn = L["之後再接"], true
    elseif step.dungeon then
      l3 = L["副本 "] .. step.dungeon.name
    elseif state.instance and s.spot then
      l3 = s.spot -- 副本內交：交給誰在哪
    elseif s.q and state.fill[s.q] then
      l3 = L["補經驗"]
    elseif step.note then
      l3 = step.note
    elseif s.tag and (MG.uiZh or s.tagL) then
      l3 = MG.uiZh and s.tag or s.tagL -- tag 是中文判斷用；其他語言顯示 tagL
    elseif step.carry then
      l3 = L["補做 "] .. UI.StName(step.st)
    elseif lv < state.st.lv[1] then
      l3, l3warn = L["建議 %d 級"]:format(state.st.lv[1]), true
    end
    if state.cur ~= state.auto then strip = DIM end
  else
    local nxt = S.nextSt
    verb = "→"
    title = nxt and L["前往 %s"]:format(UI.StName(nxt)) or L["路線已走完"]
    right = nxt and (nxt.lv[1] .. "-" .. nxt.lv[2]) or ""
    l2 = state.tail
    for _, tip in ipairs(state.st.tips or {}) do
      if tip.k == "交通" and not l2 then l2 = table.concat(UI.Sentences(tip.s, { tip.text }), "，") end
    end
    if #state.missed > 0 then l3, l3warn = L["漏掉 %d 個任務"]:format(#state.missed), true end
  end

  bar.verb:SetText(verb)
  bar.verbBox:SetShown(verb ~= "")
  -- 動詞框依字寬（中文一個字 20×20）；標題與下面各行跟著框的右邊
  local vbw = MG.uiZh and 20 or math.max(20, math.ceil(bar.verb:GetStringWidth() or 0) + 8)
  bar.verbBox:SetWidth(vbw)
  local x0 = 12 + vbw + 8
  local barW = UI.Get("barWidth")
  local avail = barW - x0 - 10 -- 標題以下各行的寬
  if UI.Get("showCount") and state and state.cur then
    right = L["剩 "] .. state.total .. (right ~= "" and ("   " .. right) or "")
  end
  bar.lv:SetText(right)
  local gap = ((MG.T and MG.T.Shown(state)) and 22 or 0) + (MG.I and MG.I.InsideWidth() or 0)
  bar.lv:SetPoint("TOPRIGHT", -32 - gap, -13)
  -- 標題：寬度先定（右邊讓出等級／目標鈕），最多兩行；下面各行跟著標題的實際高度往下
  bar.title:ClearAllPoints()
  bar.title:SetPoint("TOPLEFT", x0, -12)
  bar.title:SetWidth(math.max(1, barW - x0 - (right ~= "" and (36 + math.ceil(bar.lv:GetStringWidth() or 0)) or 32) - gap))
  bar.title:SetText(title)
  paint(bar.title, titleColor)
  bar.l3:SetText(l3 or "")
  paint(bar.l3, l3warn and AMBER or GOLD)
  bar.strip:SetColorTexture(strip[1], strip[2], strip[3], 1)
  local y = math.min(-34, -12 - math.ceil(bar.title:GetStringHeight() or 0) - 6)
  local fsz = UI.Get("fontSize")
  -- 文字＋數字：數字（3/8）獨立一欄（右對齊、量寬，不會被截），文字用剩下的寬度（截斷時滑鼠提示有全文）
  local function place(fs, nfs, x, w, t, num)
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", x, y)
    local nw = 0
    nfs:SetText(num or "")
    if num then
      nw = math.ceil(nfs:GetStringWidth() or 0) + 2
      nfs:ClearAllPoints(); nfs:SetPoint("TOPLEFT", x + w - nw, y); nfs:SetWidth(nw); nfs:Show()
    else
      nfs:Hide()
    end
    fs:SetWidth(math.max(1, w - (num and nw + 6 or 0)))
    fs:SetText(t)
  end
  -- 4 項以上排兩欄；有任何一項在半欄放不下（含數字）就退回單欄
  local function colsFor(list, n)
    if n < 4 then return 1 end
    local half = math.floor(avail / 2) - 6
    for j = 1, n do
      local o = list[j]
      if textWidth(o.text, fsz - 2) + (o.num and textWidth(o.num, fsz - 2) + 8 or 0) > half then return 1 end
    end
    return 2
  end
  bar.l2:SetShown(l2 ~= nil)
  if l2 then place(bar.l2, bar.l2n, x0, avail, l2, l2num); y = y - 18 else bar.l2n:Hide() end
  -- 多目標：最多 objRows 行（多的話最後一行「…還有 n 項」）
  local shown = {}
  if objList then
    local maxRows = UI.Get("objRows")
    for k, o in ipairs(objList) do
      if #objList > maxRows and k == maxRows then shown[k] = { text = L["…還有 %d 項"]:format(#objList - maxRows + 1) }; break end
      shown[k] = o
      if k == maxRows then break end
    end
  end
  local cols = colsFor(shown, #shown)
  local colW = math.floor(avail / cols)
  for k = 1, #bar.objs do
    local fs, o = bar.objs[k], shown[k]
    if o then
      local row, col = math.floor((k - 1) / cols), (k - 1) % cols
      local yy = y
      y = y - row * 18
      place(fs, bar.objN[k], x0 + col * colW, colW - 6, o.text, o.num)
      y = yy
      paint(fs, o.done and FAINT or TEXT); paint(bar.objN[k], o.done and FAINT or TEXT)
      fs:Show()
    else
      fs:Hide(); bar.objN[k]:Hide()
    end
  end
  if #shown > 0 then y = y - math.ceil(#shown / cols) * 18 end
  if l3 then bar.l3:SetPoint("TOPLEFT", x0, y); y = y - 18 end
  -- 附近可一起做的步驟：每步一個小區塊（分隔線＋動詞任務名＋目標）；完整內容在步驟列的滑鼠提示
  local used = 0
  local function line(t, color, x, w, num)
    used = used + 1
    local f, nf = bar.extra[used], bar.extraN[used]
    if not f then return end
    f:SetFont(FONT, fsz - 2, ""); nf:SetFont(FONT, fsz - 2, "")
    place(f, nf, x or x0, w or avail, t, num)
    paint(f, color); paint(nf, color)
    f:Show()
  end
  for k, i in ipairs(state and state.group or {}) do
    local s = state.steps[i].s
    local d = bar.divs[k]
    if d then
      d:ClearAllPoints()
      d:SetPoint("TOPLEFT", x0, y - 2); d:SetPoint("TOPRIGHT", -10, y - 2)
      d:Show()
    end
    y = y - 6
    local v = E.Verb(s)
    line(v ~= "" and (hex(GOLD) .. v .. "|r " .. E.Title(s)) or E.Title(s), TEXT) -- 動詞金色（和清單、主標題一致）
    y = y - 18
    if s.t == "do" and s.q then
      local one, header, lines, num = objectiveLines(s.q)
      if lines then
        if header then line(header, DIM); y = y - 18 end
        local maxRows = UI.Get("objRows")
        local n = math.min(#lines, maxRows)
        local disp = {}
        for j = 1, n do
          disp[j] = (#lines > maxRows and j == maxRows) and { text = L["…還有 %d 項"]:format(#lines - maxRows + 1) } or lines[j]
        end
        local gc = colsFor(disp, n)
        local gw = math.floor(avail / gc)
        for j = 1, n do
          local o = disp[j]
          local r, c = math.floor((j - 1) / gc), (j - 1) % gc
          local yy = y
          y = y - r * 18
          line(o.text, o.done and FAINT or DIM, x0 + c * gw, gw - 6, o.num)
          y = yy
        end
        y = y - math.ceil(n / gc) * 18
      elseif one or s.hint then
        line(one or s.hint, DIM, nil, nil, one and num); y = y - 18
      end
    elseif s.npc then
      line(s.npc, DIM); y = y - 18
    end
  end
  for k = used + 1, #bar.extra do bar.extra[k]:Hide(); bar.extraN[k]:Hide() end
  for k = #(state and state.group or {}) + 1, #bar.divs do bar.divs[k]:Hide() end
  bar:SetHeight(math.max(44, -y + 6))

  local key = state and state.st.id .. ":" .. tostring(state.cur and state.steps[state.cur].key)
  if key ~= lastCurKey then
    if lastCurKey then UI.Animate(state ~= nil and state.cur == state.auto) end
    lastCurKey = key
    UI.hintsAll = false -- 換步驟：提示收回成 2 條
    if panel:IsShown() and state and tab ~= "dg" then scrollToCur() end -- 副本分頁只在打開時捲
  end

  -- 提示：安全 ＞ 走了就來不及 ＞ 人在附近 ＞ 隨時能做。副本中全部不顯示
  local H = {}
  local st = state and not state.instance and state.st
  -- 臨時航點：走到了或 done() 成立（修好裝、開了飛行點）就收回
  local function goTo(p, name, done) UI.SetOverride({ map = p.map, x = p.x, y = p.y, name = name, done = done }) end
  local function pin(i) return function() E.PinIndex(state, i); MG.wpOverride, MG.grindActive = nil, nil; MG.Refresh(true) end end
  local g
  if st then
    local danger, fp = E.Nearby(st)
    if danger then H[#H + 1] = { tag = L["危險"], color = RED, text = danger.text and (E.Clause(danger.text)) or L["危險區域"], full = danger.text } end
    -- 臨時航點（修裝、飛行點、練怪、副本分頁、補給的「去」）：寫箭頭現在指去哪，「返回」收回
    -- 只是清單改做別步：寫原本那步，「返回」回到原本那步。兩者同時成立只顯示「前往」
    local pinned = state.cur and state.auto and state.cur ~= state.auto and MG.db.pin[st.id]
    local o = MG.wpOverride
    if o then
      H[#H + 1] = { tag = L["前往"], color = GOLD, actLabel = L["返回"], text = o.name or string.format("%.1f, %.1f", o.x, o.y),
        act = function() UI.ClearOverride() end }
    elseif pinned then
      H[#H + 1] = { tag = L["原本"], color = GOLD, actLabel = L["返回"], text = E.VerbTitle(state.steps[state.auto].s),
        act = function() MG.db.pin[st.id] = nil; UI.ClearOverride() end }
    end
    local leave = UI.Leaving(state)
    if #leave > 0 then
      H[#H + 1] = { tag = L["離開前"], color = AMBER, text = L["還有 %d 個任務"]:format(#leave), actLabel = L["看"],
        act = function() impOpen = true; panel:Show(); setTab("steps"); scroll = 0; drawPanel() end }
    end
    local low = UI.Get("supplyOn") and E.Durability()
    if low and low < 0.3 then
      local map, x, y = C.Position()
      local best, repair
      for _, p in ipairs(st.supply or {}) do
        if p.k == "修理" then
          local d = (p.map == map and x) and math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2) or 999
          if not best or d < best then best, repair = d, p end
        end
      end
      H[#H + 1] = { tag = L["修裝"], color = AMBER, text = repair and (repair.npc or L["修理"]) or (L["耐久 "] .. math.floor(low * 100) .. "%"),
        sub = repair and best < 10 and L["附近"] or nil, actLabel = repair and L["去"] or nil, act = repair and function() goTo(repair, MG.Clean(repair.npc or L["修理"]), function() return (E.Durability() or 1) >= 0.3 end) end or nil }
    end
    if S.sug and db.sugHide ~= lv then
      local sug = S.sug
      H[#H + 1] = { tag = L["下一站"], color = GOLD, text = UI.StName(sug), sub = sug.lv[1] .. "-" .. sug.lv[2], actLabel = L["去"],
        act = function() E.Jump(sug); lastCurKey = nil; MG.Refresh(true) end, close = function() MG.db.sugHide = UnitLevel("player") end,
        -- 按「去」之前就看得到：跳過去會順路補哪些、可放掉幾個
        tip = function(owner)
          local carry, dropN = E.JumpPlan(sug)
          tipOpen(owner, sug.name or "", "ANCHOR_BOTTOMLEFT")
          tipLine(sug.lv[1] .. "-" .. sug.lv[2], DIM)
          if #carry > 0 then
            local names = {}
            for _, q in ipairs(carry) do names[#names + 1] = E.QName(q) end
            tipLine(L["順路補 %d 個"]:format(#carry) .. L["："] .. table.concat(names, L["、"]), TEXT, true)
          end
          if dropN > 0 then tipLine(L["可放掉 %d 個"]:format(dropN), DIM) end
          GameTooltip:Show()
        end }
    elseif not state.cur and S.nextSt then
      local nx = S.nextSt
      H[#H + 1] = { tag = L["下一站"], color = GOLD, text = UI.StName(nx), sub = nx.lv[1] .. "-" .. nx.lv[2], actLabel = L["去"],
        act = function() E.Select(nx); lastCurKey = nil; MG.Refresh(true) end }
    end
    local vi = E.Detour(state)
    if vi then
      local ext = type(vi) == "table" and vi -- 出本交的副本任務：不在本站，「去」設臨時航點
      local vs = ext and vi.s or state.steps[vi].s
      H[#H + 1] = { tag = L["順路"], color = GOLD, text = (vs.t ~= "do" and vs.npc and not vs.npcObj and not vs.npc:find("物品", 1, true)) and (E.Verb(vs) .. " " .. vs.npc) or E.VerbTitle(vs),
        actLabel = L["去"], act = ext and function() -- 交任務的人通常就在附近：航點留到任務交掉（或按返回），不因為走到了就收
          UI.SetOverride({ map = vs.map, x = vs.x, y = vs.y, name = MG.Clean(vs.npc or E.Title(vs)), keep = true, done = function() return not C.IsOnQuest(vs.q) end })
        end or pin(vi),
        close = function() E.DetourNo(ext and vi.key or state.steps[vi].key) end }
    end
    if fp then
      H[#H + 1] = { tag = L["飛行點"], color = GOLD, text = fp.npc or L["飛行管理員"], actLabel = L["去"], act = function() goTo(fp, MG.Clean(fp.npc or L["飛行管理員"]), function() return MG.db.fpSeen[fp.npcG or fp.npc] end) end,
        close = function() MG.db.fpSkip[fp.npcG or fp.npc] = true end }
    end
    if state.train then
      local ts = state.steps[state.train]
      H[#H + 1] = { tag = L["學技能"], color = GOLD, text = ts.s.npc, sub = L["%d 級"]:format(ts.s.lv), actLabel = L["去"], act = pin(state.train),
        close = function() MG.db.latch[ts.key] = true end }
    end
    g = E.GrindSuggest(st, state.fillInfo)
    if g then
      local zone = C.MapName(g.map)
      H[#H + 1] = { tag = L["練等"], color = GOLD, text = g.mob, sub = g.lv[1] .. "-" .. g.lv[2] .. (zone and (" " .. zone) or ""), actLabel = L["去"],
        act = function() UI.GoGrind(g) end, close = function() MG.db.grindSkip[st.id] = UnitLevel("player"); MG.grindActive = nil end }
    end
    if not st.dungeon then
      local d, missing = E.DungeonPrompt()
      if d then
        H[#H + 1] = { tag = L["副本"], color = GOLD, text = d.name, sub = d.lv[1] .. "-" .. d.lv[2] .. (missing and (" " .. missing) or ""), actLabel = L["看"],
          act = function()
            UI.dOpen = d.id
            panel:Show(); setTab("dg")
            for k, it in ipairs(items) do if it.kind == "dg" and it.d == d then scroll = math.max(0, k - 1) end end
            drawPanel()
          end,
          close = function() MG.db.dDismiss[d.id] = true end }
      end
    end
  end
  if not g then MG.grindActive = nil end
  local w = UI.Get("barWidth")
  local showN = (UI.hintsAll or #H <= 2) and #H or 2
  local above = bar
  for k, f in ipairs(hints) do
    local h = k <= showN and H[k] or false
    f.h = h
    if h then
      f:SetWidth(w)
      f.strip:SetColorTexture(h.color[1], h.color[2], h.color[3], 1)
      f.tag:SetText(h.tag); paint(f.tag, h.color)
      f.label:SetText(h.text or "")
      -- 右側保留：動作鈕實際寬度＋× 鈕
      f.act.label:SetText(h.actLabel or "")
      local aw = math.max(28, math.ceil(f.act.label:GetStringWidth() or 0) + 12)
      f.act:SetWidth(aw)
      local reserve = 32 + aw
      local room = w - 10 - (f.tag:GetStringWidth() or 0) - 8 - reserve
      -- 補充（等級範圍、前置數量）先量：不超過列寬 40% 就排在主文字右邊（從主文字的寬扣掉）；太長就放到第二行
      f.sub:SetText(h.sub or "")
      local sw = (h.sub or "") ~= "" and math.ceil(f.sub:GetStringWidth() or 0) + 2 or 0
      local inline = sw <= w * 0.4
      if inline and sw > 0 then room = room - sw - 6 end
      f.label:SetWidth(math.max(1, math.min((f.label.GetUnboundedStringWidth and f.label:GetUnboundedStringWidth() or f.label:GetStringWidth() or 0) + 2, room)))
      f.label:SetText(h.text or "") -- 改寬後重設文字，行高才會照新寬算
      f.tag:ClearAllPoints(); f.label:ClearAllPoints(); f.sub:ClearAllPoints()
      if inline then
        f.tag:SetPoint("LEFT", 10, 0)
        f.label:SetPoint("LEFT", f.tag, "RIGHT", 8, 0)
        f.sub:SetPoint("LEFT", f.label, "RIGHT", 6, 0); f.sub:SetWidth(math.max(1, sw))
        f:SetHeight(math.max(24, math.ceil(f.label:GetStringHeight() or 0) + 10))
      else
        f.tag:SetPoint("TOPLEFT", 10, -6)
        f.label:SetPoint("TOPLEFT", f.tag, "TOPRIGHT", 8, 0)
        f.sub:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -2); f.sub:SetWidth(math.max(1, room))
        f:SetHeight(math.ceil(f.label:GetStringHeight() or 0) + math.ceil(f.sub:GetStringHeight() or 0) + 14)
      end
      f.act:SetShown(h.act ~= nil)
      f.x:SetShown(h.close ~= nil)
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -2)
      above = f
    end
    f:SetShown(h and true or false)
  end
  if #H > showN then
    more.label:SetText("▾ +" .. (#H - showN))
    more:SetWidth((more.label:GetStringWidth() or 30) + 8)
    more:ClearAllPoints()
    more:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -2)
    above = more
  end
  more:SetShown(#H > showN)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -6)
  drawPanel()
end

function UI.SetHidden(hidden)
  root:SetShown(not hidden and MG.db.shown ~= false)
end

function UI.Visible() return root ~= nil and root:IsShown() end
function UI.Toggle()
  MG.db.shown = not root:IsShown()
  root:SetShown(MG.db.shown)
  UI.holderTries = 0
  UI.PlaceHolder()
  MG.Refresh(true) -- 目標按鈕跟著顯示／隱藏（戰鬥中會等脫離戰鬥）
end

-- ── 檢查報告（可複製） ──────────────────────────────────────────────────────
function UI.ShowReport(body, title)
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
    -- 關閉鈕照字寬；標題夾在左邊和關閉鈕之間，最多兩行，內文區跟著標題高度往下
    local close = CreateFrame("Button", nil, report)
    close.label = text(close, 13, GOLD, "CENTER"); close.label:SetPoint("CENTER"); close.label:SetText(L["關閉"])
    close:SetSize(math.max(48, math.ceil(close.label:GetStringWidth() or 0) + 16), 22); close:SetPoint("TOPRIGHT", -8, -6)
    close:SetScript("OnClick", function() report:Hide() end)
    local head = text(report, 13, DIM)
    head:SetPoint("TOPLEFT", 12, -10)
    head:SetWidth(600 - 12 - close:GetWidth() - 8 - 8)
    wrapLines(head, 2)
    report.head = head
    local sf = CreateFrame("ScrollFrame", nil, report)
    report.sf = sf
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
  report.head:SetText(title or L["阿聖練等幫手 檢查報告：Ctrl+A 全選、Ctrl+C 複製，貼回給開發者"])
  report.sf:ClearAllPoints()
  report.sf:SetPoint("TOPLEFT", 12, math.min(-34, -10 - math.ceil(report.head:GetStringHeight() or 0) - 8)); report.sf:SetPoint("BOTTOMRIGHT", -12, 12)
  report.eb:SetText(body)
  report:Show()
  report.eb:SetFocus()
  report.eb:HighlightText()
end
