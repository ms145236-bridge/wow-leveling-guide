-- 地圖標點：目前站剩下的步驟在世界地圖上畫編號標點，小地圖只畫目前步驟與後 2 步。
-- 用 HereBeDragons-Pins（Questie 已載入）；沒有就不畫。不動 Questie 的東西。
-- 靠得很近的點合成一個，標最小的號碼，滑過列出全部步驟。
local _, MG = ...
local E = MG.E
local P = {}
MG.P = P
local REF = "MetroGuide"
-- 標點 v2（PIN-SPEC.md）：外形＝動詞（色盲輔助），色面用 SetVertexColor 染色，金框疊在上面，目前步驟加光暈
local MEDIA = "Interface\\AddOns\\ShengLeveling\\Media\\"
local SHAPE = { accept = "circle", ["do"] = "square", turnin = "diamond" }
local COLOR = { accept = { 0.95, 0.73, 0.06 }, ["do"] = { 0.91, 0.39, 0.10 }, turnin = { 0.18, 0.68, 0.31 } }
local GREY = { 0.55, 0.59, 0.66 }
local pool, used = {}, 0
local sig, state
P.count = { world = 0, minimap = 0 }
P.diag = {}

local function hbd()
  return LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

local function layer(b, draw, sub)
  local t = b:CreateTexture(nil, draw, nil, sub)
  t:SetPoint("CENTER")
  if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
  return t
end

local function getPin()
  used = used + 1
  local b = pool[used]
  if not b then
    b = CreateFrame("Button", nil, UIParent)
    b.glow = layer(b, "BACKGROUND", 0)
    b.glow:SetTexture(MEDIA .. "pin_glow")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(1, 0.85, 0.4, 0.9)
    b.base = layer(b, "ARTWORK", 0)
    b.rim = layer(b, "ARTWORK", 1)
    b.num = b:CreateFontString(nil, "OVERLAY")
    b.num:SetPoint("CENTER", 0, 0)
    b.num:SetWordWrap(false)
    b.num:SetJustifyH("CENTER")
    b.num:SetShadowOffset(0, 0)
    b:SetScript("OnEnter", function(self)
      local first = self.group[1]
      local nums = {}
      for _, g in ipairs(self.group) do nums[#nums + 1] = g.n end
      MG.UI.StepTooltip(self, first.step.s, "第 " .. table.concat(nums, "、") .. " 步｜")
      for k = 2, #self.group do
        local s = self.group[k].step.s
        MG.UI.TipLine(self.group[k].n .. "  " .. (E.VERB[s.t] or "") .. " " .. E.Title(s))
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
      if state then E.PinIndex(state, self.group[1].i); MG.Refresh(true) end
    end)
    pool[used] = b
  end
  return b
end

-- group：{ {step, i, n, cur}... }（依號碼排序）；S＝標點尺寸（點擊範圍），貼圖 S×4/3
local function style(b, group, S)
  local lead, cur = group[1], false
  for _, g in ipairs(group) do if g.cur then lead, cur = g, true end end
  local t = lead.step.s.t
  local c = COLOR[t] or GREY
  local shape = SHAPE[t] or "circle"
  local size = S * 4 / 3
  b.group = group
  b:SetSize(S, S)
  for _, tex in ipairs({ b.glow, b.base, b.rim }) do tex:SetSize(size, size) end
  b.glow:SetShown(cur)
  b.base:SetTexture(MEDIA .. "pin_" .. shape .. "_base")
  b.base:SetVertexColor(c[1], c[2], c[3])
  b.rim:SetTexture(MEDIA .. "pin_" .. shape .. "_rim")
  if cur then b.rim:SetVertexColor(1, 1, 1) else b.rim:SetVertexColor(0.90, 0.86, 0.80) end
  local label = group[1].n .. (#group > 1 and "+" or "")
  local short = S >= 30 and 15 or S >= 24 and 12 or S >= 20 and 11 or S >= 18 and 10 or 9
  local long = S >= 30 and 12 or S >= 24 and 10 or S >= 18 and 9 or 8
  local font = NumberFontNormal and NumberFontNormal:GetFont() or STANDARD_TEXT_FONT
  b.num:SetFont(font, #label >= 3 and long or short, "OUTLINE")
  b.num:SetSize(S + 12, S)
  b.num:SetText(label)
  b.num:SetTextColor(1, 0.97, 0.90)
end

-- 一步的所有座標（「做」可能有多個怪點）
local function points(s)
  local out = {}
  if s.x then out[1] = { s.map, s.x, s.y } end
  for _, p in ipairs(s.more or {}) do out[#out + 1] = p end
  return out
end

function P.Clear()
  local pins = hbd()
  if pins then pins:RemoveAllWorldMapIcons(REF); pins:RemoveAllMinimapIcons(REF) end
  for k = 1, used do pool[k]:Hide() end
  used, sig = 0, nil
  P.count.world, P.count.minimap = 0, 0
end

-- ── 畫面比例 ──
-- HereBeDragons 的地圖標點用 SetScalingLimits(1, 1.0, 1.2)：標點相對畫布放大 1/畫布縮放，夾在 1.0–1.2 之間。
-- 回傳：地圖 1% 的螢幕像素、標點 1 單位的螢幕像素、畫布有效縮放、畫布縮放
local function scales()
  local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
  local cw = canvas and canvas:GetWidth() or 0
  local ce = canvas and canvas:GetEffectiveScale() or 1
  if cw < 100 then cw, ce = 1002, UIParent:GetEffectiveScale() or 1 end
  local cs = WorldMapFrame and WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
  local pinScale = math.min(1.2, math.max(1.0, 1 / (cs > 0 and cs or 1)))
  return cw * ce / 100, ce * pinScale, ce, cs
end

-- ── 最上層：比地圖上其他標點的最高層級再高；另外用比地圖高一階的 strata 保底 ──
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
local function maxOtherLevel()
  local top, mine = 0, {}
  for k = 1, used do if pool[k].world and pool[k]:GetParent() then mine[pool[k]:GetParent()] = true end end
  if WorldMapFrame and WorldMapFrame.EnumerateAllPins then
    for pin in WorldMapFrame:EnumerateAllPins() do
      if not mine[pin] and pin:IsShown() then top = math.max(top, pin:GetFrameLevel()) end
    end
  end
  return top
end
function P.Raise()
  if not WorldMapFrame then return end
  local strata = WorldMapFrame:GetFrameStrata()
  for k, name in ipairs(STRATA) do if name == strata then strata = STRATA[math.min(k + 1, #STRATA)]; break end end
  local level = math.min(maxOtherLevel() + 10, 9000)
  for k = 1, used do
    local b = pool[k]
    if b.world then
      b:SetFrameStrata(strata)
      b:SetFrameLevel(level)
    end
  end
end

local function raiseMini(b)
  local parent = b:GetParent()
  if parent then b:SetFrameLevel(parent:GetFrameLevel() + 50) end
end

-- 世界地圖最上層的層級名稱；這版客戶端沒有就用預設
local function levelManager()
  if not WorldMapFrame then return nil end
  if WorldMapFrame.GetPinFrameLevelsManager then return WorldMapFrame:GetPinFrameLevelsManager() end
  return WorldMapFrame.pinFrameLevelsManager
end
function P.TopLevel()
  local mgr = levelManager()
  local defs = mgr and mgr.definitions
  if type(defs) == "table" and defs.PIN_FRAME_LEVEL_TOPMOST then return "PIN_FRAME_LEVEL_TOPMOST" end
  return nil
end

function P.Update(st, force)
  state = st
  local pins = hbd()
  if not pins or not st or not MG.UI.Get("arrow") then
    if sig then P.Clear() end
    return
  end
  local UI = MG.UI
  -- 合併距離：畫面像素（標點大小 × 倍數），換成地圖百分比；不分步驟、不分動詞
  local pxPerPct, pe = scales()
  local size = UI.Get("pinSize")
  local shown = size * 4 / 3 -- 貼圖實際大小（含金框）
  local near = UI.Get("pinMergeX") * shown * pe / pxPerPct
  local far = 3 * shown * pe / pxPerPct -- 同一步的多個座標：在這距離內只畫一個
  P.diag.thresholdPx, P.diag.pxPerPct, P.diag.pinScale = UI.Get("pinMergeX") * shown * pe, pxPerPct, pe
  local parts = { st.st.id, tostring(st.cur), size, UI.Get("miniPinSize"), UI.Get("miniSteps"), UI.Get("pinAlpha"), math.floor(near * 100) }
  for i in ipairs(st.steps) do if not st.done[i] and not st.na[i] then parts[#parts + 1] = i end end
  local key = table.concat(parts, ",")
  if key == sig and not force then return end
  P.Clear()
  sig = key

  -- 收集各點：只畫有相對編號的步驟（目前步驟＝1，之後還沒做的），近的合併
  local groups, mini = {}, {}
  for i, step in ipairs(st.steps) do
    local n = st.num[i]
    if n then
      local cur = i == st.cur
      local entry = { step = step, i = i, n = n, cur = cur, at = {} }
      for _, p in ipairs(points(step.s)) do
        local dup = false
        for _, q in ipairs(entry.at) do
          if q[1] == p[1] and (q[2] - p[2]) ^ 2 + (q[3] - p[3]) ^ 2 < far * far then dup = true; break end
        end
        if not dup then
          entry.at[#entry.at + 1] = p
          local hit
          for _, g in ipairs(groups) do
            if g.map == p[1] and (g.x - p[2]) ^ 2 + (g.y - p[3]) ^ 2 < near * near then hit = g; break end
          end
          if not hit then
            hit = { map = p[1], x = p[2], y = p[3], has = {} }
            groups[#groups + 1] = hit
          end
          if not hit.has[entry] then hit.has[entry] = true; hit[#hit + 1] = entry end
        end
      end
      if (cur or (st.cur and i > st.cur)) and #mini < UI.Get("miniSteps") and step.s.x then mini[#mini + 1] = entry end
    end
  end

  local showFlag = HBD_PINS_WORLDMAP_SHOW_PARENT or 1
  for _, g in ipairs(groups) do
    local b = getPin()
    b.world = true
    local cur = false
    for _, e in ipairs(g) do if e.cur then cur = true end end
    local travel = not cur and not SHAPE[g[1].step.s.t]
    style(b, g, size + (cur and 6 or travel and -4 or 0)); b:SetAlpha(UI.Get("pinAlpha") / 100)
    pins:AddWorldMapIconMap(REF, b, g.map, g.x / 100, g.y / 100, showFlag, P.TopLevel())
    P.count.world = P.count.world + 1
  end
  P.Raise()
  -- 小地圖：目前步驟與後 2 步（各取第一個座標）
  for _, e in ipairs(mini) do
    local b = getPin()
    b.world = false
    style(b, { e }, UI.Get("miniPinSize") + (e.cur and 3 or 0)); b:SetAlpha(UI.Get("pinAlpha") / 100)
    pins:AddMinimapIconMap(REF, b, e.step.s.map, e.step.s.x / 100, e.step.s.y / 100, false, e.cur)
    raiseMini(b)
    P.count.minimap = P.count.minimap + 1
  end
end

-- 地圖換區、縮放、重整後：依新的畫面比例重新合併，再把層級拉到最上面（等這一幀其他提供者畫完）
local pending = false
local function reflow()
  if pending then return end
  pending = true
  local run = function()
    pending = false
    MG.try("地圖標點", function() if state then P.Update(state) end; P.Raise() end)
  end
  if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end
if WorldMapFrame then
  for _, m in ipairs({ "OnMapChanged", "OnCanvasScaleChanged", "RefreshAllDataProviders" }) do
    if type(WorldMapFrame[m]) == "function" then hooksecurefunc(WorldMapFrame, m, reflow) end
  end
  WorldMapFrame:HookScript("OnShow", reflow)
end

-- /slv probe 用
function P.Diag()
  local L = {}
  local mgr = levelManager()
  local names = {}
  if mgr and type(mgr.definitions) == "table" then for k in pairs(mgr.definitions) do names[#names + 1] = k end end
  table.sort(names)
  L[#L + 1] = "地圖層級種類（" .. #names .. "）：" .. (#names > 0 and table.concat(names, " ") or "讀不到")
  L[#L + 1] = "PIN_FRAME_LEVEL_TOPMOST：" .. tostring(P.TopLevel() ~= nil) .. "｜地圖 strata：" .. tostring(WorldMapFrame and WorldMapFrame:GetFrameStrata())
  local first
  for k = 1, used do if pool[k].world then first = pool[k]; break end end
  if first then
    local parent = first:GetParent()
    L[#L + 1] = ("我們的標點 strata/level：%s / %s｜父框架 level：%s｜其他標點最高 level：%s"):format(
      tostring((first:GetFrameStrata())), tostring((first:GetFrameLevel())), tostring(parent and (parent:GetFrameLevel())), tostring((maxOtherLevel())))
  else
    L[#L + 1] = "我們的標點：目前沒有"
  end
  local _, _, ce, cs = scales()
  L[#L + 1] = ("合併門檻 %.1f px｜地圖 1%% = %.1f px｜畫布有效 scale %.2f｜畫布縮放 %.2f｜標點 scale %.2f"):format(P.diag.thresholdPx or 0, P.diag.pxPerPct or 0, ce or 0, cs or 0, P.diag.pinScale or 0)
  -- 我們的標點之間最近的距離（地圖開著時才量得到）
  local best, pair
  for k = 1, used do
    local a = pool[k]
    local ax, ay
    if a.world and a:IsVisible() then ax, ay = a:GetCenter() end
    if ax then
      for j = k + 1, used do
        local b = pool[j]
        local bx, by
        if b.world and b:IsVisible() then bx, by = b:GetCenter() end
        if bx then
          local e = a:GetEffectiveScale()
          local d = math.sqrt(((ax - bx) * e) ^ 2 + ((ay - by) * e) ^ 2)
          if not best or d < best then best, pair = d, tostring(a.num:GetText()) .. " 和 " .. tostring(b.num:GetText()) end
        end
      end
    end
  end
  L[#L + 1] = best and ("最近的兩個標點：%s，相距 %.1f px"):format(pair, best) or "最近的兩個標點：地圖沒開，量不到"
  return L
end
