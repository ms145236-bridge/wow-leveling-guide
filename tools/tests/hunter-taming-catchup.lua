-- From the repository root: lua5.1 tools/tests/hunter-taming-catchup.lua
-- 人類獵人第11站補接馴服野獸（沒撿到被啃過的書、第2站還不到 10 級的人）：
-- 段落排在「經閃金鎮過橋進西部荒野」那步之前，接取只在艾爾文森林（【在地辦理：1429】）才出現，沒有另加「回到路線」；
-- 過橋到西部荒野後不再指回約瑟芬，已接的照常做、交；第2站已經做完整條的人看不到。
local chain = {94792, 94863, 94864, 94793}
local level, map, x, y = 14, nil, nil, nil
local active, ready, turned = {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Hunter", "HUNTER" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return level end
function UnitXP() return 0 end
function UnitXPMax() return 14400 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {
  C = {IsOnQuest=function(q) return active[q] end, IsReady=function(q) return ready[q] end,
       IsTurnedIn=function(q) return turned[q] end,
       LogQuestIDs=function() local out = {} for q in pairs(active) do out[#out + 1] = q end return out end,
       Position=function() return map, x, y end, XPBuff=function() return false end,
       ZoneTexts=function() end, Bind=function() end, Objectives=function() end},
  UI = {Get=function() return false end},
  L = setmetatable({}, {__index=function(_, k) return k end}),
  db = {skip={}, mark={}, latch={}, notNow={}, pin={}, fpNodes={}, carry={}, dNo={}, station="02-11"},
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local st = assert(E.byId["02-11"])
local catchup, bridge, travel = {}, nil, nil
for i, w in ipairs(st.list) do
  local s = w.s
  if s.q and s.when and s.when.race then
    for _, q in ipairs(chain) do if s.q == q then catchup[#catchup + 1] = {i = i, w = w} end end
  end
  if s.t == "travel" and (s.text or ""):find("經閃金鎮過橋進西部荒野，再沿大道往南到哨兵嶺") then travel = i end
  if s.t == "accept" and s.q == 109 then bridge = i end
  assert(not s.back or s.map ~= 1429, "no return step back to the bridge")
end
assert(#catchup == 11 and travel == catchup[#catchup].i + 1 and bridge, "catch-up section right before the Goldshire leg")
-- Everything on the station before the catch-up is done (Stormwind visit); this is where the hunter is now.
local function reset()
  wipe(active); wipe(ready); wipe(turned); wipe(ns.db.skip); wipe(ns.db.mark)
  for i = 1, catchup[1].i - 1 do ns.db.mark[st.list[i].key] = true end
end
local function current()
  local state = E.Locate(st)
  return state.cur and state.steps[state.cur] or nil, state
end
local function tamingCurrent()
  local cur = current()
  for _, q in ipairs(chain) do if cur and cur.s.q == q then return cur end end
end

-- 0. 還在暴風城：先照主線往西走，不先指向約瑟芬
reset()
map, x, y = 1453, 71.3, 72.3
assert(not tamingCurrent() and current().s.t == "travel", "Stormwind: the Goldshire leg comes first")

-- 1. 閃金鎮（艾爾文森林）：補接出現，接了以後一路做到 94793
reset()
map, x, y = 1429, 42.11, 65.93
local cur = assert(current())
assert(cur.s.q == 94792 and cur.s.t == "accept", "Goldshire: catch-up accept is the current step")
active[94792] = true
assert(current().s.q == 94792 and current().s.t == "do")
active[94792], turned[94792] = nil, true
local follow = current()
assert(follow.s.q == 94863 and follow.s.t == "accept", "Goldshire: the next taming accept follows")

-- 2. 過橋到西部荒野（哨兵嶺），109 已交：不指回約瑟芬
for _, done in ipairs({false, true}) do
  reset()
  if done then turned[109] = true; ns.db.mark[st.list[bridge].key] = true end
  map, x, y = 1436, 56.33, 47.52
  assert(not tamingCurrent(), "Westfall: no taming accept points back to Goldshire")
  for _, c in ipairs(catchup) do
    if c.w.s.t == "accept" then assert(not E.Applies(c.w.s.when), "Westfall: catch-up accept hidden") end
  end
  -- 已經接了 94863 才離開：做、交照常（任務還在日誌裡）
  turned[94792], active[94863] = true, true
  local work = assert(tamingCurrent(), "accepted taming work keeps its guidance")
  assert(work.s.q == 94863 and work.s.t ~= "accept")
  active[94863], turned[94863] = nil, true
  assert(not tamingCurrent(), "Westfall: 94864 accept does not point back alone")
end

-- 3. 第2站已經做完整條：補接段落都不出現
reset()
for _, q in ipairs(chain) do turned[q] = true end
map, x, y = 1429, 42.11, 65.93
assert(not tamingCurrent(), "chain done at station 2: nothing shown")
print("Human hunter taming catch-up: Goldshire only, not after crossing into Westfall, skipped when done at station 2")
