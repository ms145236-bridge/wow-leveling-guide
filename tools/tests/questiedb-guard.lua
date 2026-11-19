-- From the repository root: lua5.1 tools/tests/questiedb-guard.lua
-- 用建置時的 QuestieDB 快照（tools/questiedb-snapshot.tsv）核對 Data，CI 不需要 QuestieDB：
-- 1. 只能由物品起始、起始物品由 2 種以上的怪隨機掉落的任務，接取步要有【可跳過】加【掉落才接】類標籤或持物條件，
--    否則沒掉就停在這一步（單一首領掉落、地上物件、NPC 給的物品不算）。
-- 2. 路線【前置：… ID】標籤加的前置，要是 QuestieDB 的前置（或它的互斥替代）；不是的話，同任務的步驟說明要寫到
--    這個前置（任務名或 ID），否則任務可能永遠不出現。
-- 刻意的例外列在 tools/tests/questiedb-exceptions.tsv，要寫理由。
local function split(line, sep)
  local out, from = {}, 1
  while true do
    local at = line:find(sep, from, true)
    out[#out + 1] = line:sub(from, (at or 0) - 1)
    if not at then return out end
    from = at + #sep
  end
end
local function ids(text)
  local out = {}
  for id in (text or ""):gmatch("%d+") do out[#out + 1] = tonumber(id) end
  return out
end
local function rows(path)
  local out = {}
  for line in io.lines(path) do
    line = line:gsub("\r$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then out[#out + 1] = split(line, "\t") end
  end
  return out
end

local snap, built = { Horde = {}, Alliance = {} }, {}
for _, c in ipairs(rows("tools/questiedb-snapshot.tsv")) do
  if c[3] == "（QuestieDB 沒有這個任務）" then snap[c[1]][tonumber(c[2])] = { pre = {}, ex = {} }
  else
    local start = split(c[11], ";")
    local itemOnly = start[1] == "" and start[2] == "" and start[3] ~= ""
    snap[c[1]][tonumber(c[2])] = { pre = ids(c[7] .. "," .. c[8]), ex = ids(c[9]), items = itemOnly and ids(start[3]), randomDrop = itemOnly and tonumber(c[12]) >= 2 and tonumber(c[12]) }
  end
end
for _, c in ipairs(rows("tools/questiedb-version.txt")) do built[c[1]] = c[3] end
local allow = {}
for _, c in ipairs(rows("tools/tests/questiedb-exceptions.tsv")) do
  assert(c[#c] ~= "" and #c >= 3, "例外要寫理由：" .. table.concat(c, "\t"))
  allow[c[1] .. ":" .. c[2] .. (c[1] == "前置" and ":" .. c[3] or "")] = true
end

local problems, used = {}, {}
local function report(key, text)
  if allow[key] then used[key] = true else problems[#problems + 1] = text end
end
for _, faction in ipairs({ "Horde", "Alliance" }) do
  function UnitFactionGroup() return faction end
  local ns = {}
  assert(loadfile("addon/ShengLeveling/Data/" .. (faction == "Alliance" and "RouteA.lua" or "Route.lua")))("ShengLeveling", ns)
  local route, db = ns.Route, snap[faction]
  assert(route.built == built[faction], faction .. "：Data 和 QuestieDB 快照不是同一次建置（重跑 node tools/build.mjs）")
  local notes = {}
  for _, st in ipairs(route.stations) do
    for _, s in ipairs(st.steps) do
      if s.q and s.desc then notes[s.q] = (notes[s.q] or "") .. s.desc end
      local q = s.t == "accept" and not s.any and s.q
      local bag = q and db[q] and db[q].items and s.when and s.when.bag
      if bag then
        local starts = false
        for _, item in ipairs(db[q].items) do starts = starts or item == bag.item end
        if not starts then report("持物:" .. q, ("%s %s 接 %d %s：持物條件 %d 不是起始物品（%s）"):format(faction, st.id, q, route.quests[q].n or "", bag.item, table.concat(db[q].items, ","))) end
      end
      if q and db[q] and db[q].randomDrop and not (s.opt and (route.quests[q].cond or (s.when and s.when.bag))) then
        report("掉落起始:" .. q, ("%s %s 接 %d %s：起始物品由 %d 種怪隨機掉落，要加【掉落才接】【可跳過】或持物條件"):format(faction, st.id, q, route.quests[q].n or "", db[q].randomDrop))
      end
    end
  end
  for q, e in pairs(route.quests) do
    -- 路線任務和 Data 前置都要有快照列（QuestieDB 沒有的也有一列標記），缺列表示快照不完整
    for _, list in ipairs({ { q }, e.pg or {}, e.ps or {} }) do
      for _, p in ipairs(list) do
        if not db[p] then problems[#problems + 1] = ("%s 快照缺任務 %d（重跑 node tools/build.mjs）"):format(faction, p) end
      end
    end
    local row = db[q]
    if row and (e.pg or e.ps) then
      local ok = {}
      for _, p in ipairs(row.pre) do
        ok[p] = true
        for _, x in ipairs(db[p] and db[p].ex or {}) do ok[x] = true end
      end
      for _, list in ipairs({ e.pg or {}, e.ps or {} }) do
        for _, p in ipairs(list) do
          local name = route.quests[p] and route.quests[p].n
          local noted = notes[q] and (notes[q]:find(tostring(p), 1, true) or (name and notes[q]:find(name, 1, true)))
          if not ok[p] and not noted then report("前置:" .. q .. ":" .. p, ("%s %d %s：路線的前置 %d 不在 QuestieDB 的前置裡（前置：%s）"):format(faction, q, e.n or "", p, table.concat(row.pre, ",") ~= "" and table.concat(row.pre, ",") or "無")) end
        end
      end
    end
  end
end
table.sort(problems)
for key in pairs(allow) do if not used[key] then print("例外已不需要：" .. key) end end
if #problems > 0 then
  io.stderr:write("QuestieDB 檢查失敗（修路線，或在 tools/tests/questiedb-exceptions.tsv 加一列並寫理由）：\n" .. table.concat(problems, "\n") .. "\n")
  os.exit(1)
end
print("QuestieDB guard: item-started accepts and route prereq tags match the snapshot")
