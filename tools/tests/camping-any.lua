-- From the repository root: lua5.1 tools/tests/camping-any.lua
-- 紮營入門指南（任選專業）：營地 NPC 給全部專業的版本，路線只寫一步「接｜任一組」，交的那幾步依玩家實際接的專業找訓練師。
-- 沒接：交的步驟都不出現、不算漏掉；接剝皮→剝皮訓練師；接採礦→採礦訓練師；已交→接取與交件都算完成。
local function load(file, faction, race, raceId, level)
  local active, turned, optional = {}, {}, true
  _G.UnitFactionGroup = function() return faction end
  _G.UnitClass = function() return "Warrior", "WARRIOR" end
  _G.UnitRace = function() return race, race, raceId end
  _G.UnitLevel = function() return level end
  _G.UnitXPMax = function() return 4500 end
  _G.UnitXP = function() return 0 end
  _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={} }
  local ns = { C={}, db=db, L=setmetatable({}, { __index=function(_, k) return k end }), uiZh=true, gameZh=true }
  ns.UI = { Get=function(key) return key == "optional" and optional end }
  ns.C.IsOnQuest = function(q) return active[q] end
  ns.C.IsReady = function() return false end
  ns.C.IsTurnedIn = function(q) return turned[q] end
  ns.C.XPBuff = function() return false end
  ns.C.Position = function() return 1429, 44, 64 end
  ns.C.ZoneTexts = function() end
  ns.C.Bind = function() end
  ns.C.LogQuestIDs = function() local out = {} for q in pairs(active) do out[#out + 1] = q end return out end
  ns.C.Objectives = function() return { { done=false } } end
  for _, f in ipairs({ file, "Engine.lua" }) do
    assert(loadfile("addon/ShengLeveling/" .. f))("ShengLeveling", ns)
  end
  ns.E.Build()
  local function reset(on, done, opt)
    wipe(active); wipe(turned); wipe(db.skip); wipe(db.mark); wipe(db.latch)
    optional = opt ~= false
    for q in pairs({ [95998]=1, [96604]=1 }) do turned[q] = true end -- 戶外真好（前置）已交
    for _, q in ipairs(on or {}) do active[q] = true end
    for _, q in ipairs(done or {}) do turned[q] = true end
  end
  return ns.E, reset
end

-- 一站裡的任一組接取步、和它那組任務的交件步（含別站：Locate 會把在日誌的任務帶過來，這裡逐站找）
local function camp(E, ids)
  local group = {}
  for _, q in ipairs(ids) do group[q] = true end
  local out = { accept={}, turnin={} }
  for _, st in ipairs(E.stations) do
    local state = E.Locate(st)
    for i, step in ipairs(state.steps) do
      local s = step.s
      if s.any and group[s.any[1]] then out.accept[#out.accept + 1] = { s=s, na=state.na[i], done=state.done[i], title=E.Title(s) } end
      if s.t == "turnin" and group[s.q] then out.turnin[s.q] = { s=s, na=state.na[i], done=state.done[i], st=st.id } end
      for _, m in ipairs(state.missed) do assert(not group[m.q], "任一組的任務不能算漏掉：" .. m.q) end
    end
  end
  return out
end

local function shown(c)
  local list = {}
  for q, t in pairs(c.turnin) do if not t.na then list[#list + 1] = q end end
  table.sort(list)
  return list
end

-- 聯盟（人類，艾爾文森林）
local E, reset = load("Data/RouteA.lua", "Alliance", "Human", 1, 7)
local ELWYNN = { 97924, 97915, 97916, 97917, 97918, 97920, 97921, 97922, 97923, 97925 }

-- 1. 沒接：接取步出現（可跳過開著）、標題是任選專業；交件全部不出現
reset()
local c = camp(E, ELWYNN)
assert(#c.accept == 1, "艾爾文要有一步任一組的接")
assert(not c.accept[1].na and not c.accept[1].done, "可跳過開著時，沒接要列出接取步")
assert(c.accept[1].title == "紮營入門指南（任選專業）", "接取步標題：" .. tostring(c.accept[1].title))
assert(#shown(c) == 0, "沒接任何一個，交的步驟不能出現：" .. table.concat(shown(c), ","))
-- 可跳過關著：整組不出現，也不擋目前步驟
reset(nil, nil, false)
c = camp(E, ELWYNN)
assert(c.accept[1].na and #shown(c) == 0, "可跳過關著時整組不出現")

-- 2. 接剝皮：接取算完成；只出現剝皮的交件，指向海倫尼·派特斯金納
reset({ 97924 })
c = camp(E, ELWYNN)
assert(c.accept[1].done, "接了剝皮，接取步要算完成")
assert(#shown(c) == 1 and shown(c)[1] == 97924, "只顯示剝皮的交件：" .. table.concat(shown(c), ","))
assert(c.turnin[97924].s.npc == "海倫尼·派特斯金納" and c.turnin[97924].s.map == 1429, "剝皮交給海倫尼·派特斯金納")

-- 3. 接採礦：交件指向暴風城的吉爾曼·石手
reset({ 97923 })
c = camp(E, ELWYNN)
assert(c.accept[1].done, "接了採礦，接取步要算完成")
assert(#shown(c) == 1 and shown(c)[1] == 97923, "只顯示採礦的交件：" .. table.concat(shown(c), ","))
assert(c.turnin[97923].s.npc == "吉爾曼·石手" and c.turnin[97923].s.map == 1453, "採礦交給暴風城的吉爾曼·石手")

-- 4. 已交：接取與交件都算完成
reset(nil, { 97924 })
c = camp(E, ELWYNN)
assert(c.accept[1].done, "交過剝皮，接取步要算完成")
assert(c.turnin[97924].done and not c.turnin[97924].na, "交過的那一步打勾")
assert(#shown(c) == 1, "其他專業的交件不出現")

-- 5. 站的進度：沒接的專業不算進總數，接了一個只多一件
local elwynn = E.byId["01-2"]
reset()
local _, base = E.Progress(elwynn)
reset({ 97923 })
local _, withOne = E.Progress(elwynn)
assert(withOne == base + 1, ("進度總數：沒接 %d，接採礦 %d"):format(base, withOne))

-- 6. 鍵固定：接哪個專業，接取步的存檔鍵都是第一個 ID（舊存檔的 a:97924 照樣對得上）
for _, st in ipairs(E.stations) do
  for _, step in ipairs(st.list) do
    if step.s.any and step.s.any[1] == 97924 then assert(step.key == "a:97924", "接取步鍵：" .. step.key) end
  end
end

-- 部落（獸人，杜洛塔）：接採礦→剃刀嶺的克魯恩；接剝皮→奧格瑪的蘇爾德
E, reset = load("Data/Route.lua", "Horde", "Orc", 2, 7)
local DUROTAR = { 97908, 96102, 97899, 97900, 97901, 97902, 97903, 97904, 97905, 97906, 97907 }
reset()
c = camp(E, DUROTAR)
assert(#c.accept == 1 and #shown(c) == 0, "杜洛塔沒接時交件不出現")
reset({ 97907 })
c = camp(E, DUROTAR)
assert(#shown(c) == 1 and c.turnin[97907].s.npc == "克魯恩" and c.turnin[97907].s.map == 1411, "採礦交給剃刀嶺的克魯恩")
reset({ 97908 })
c = camp(E, DUROTAR)
assert(#shown(c) == 1 and c.turnin[97908].s.npc == "蘇爾德" and c.turnin[97908].s.map == 1454, "剝皮交給奧格瑪的蘇爾德")
print("Camping 101 any profession: hidden until taken, turn-in follows the profession taken, done after turn-in")
