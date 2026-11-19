-- From the repository root: lua5.1 tools/tests/fp-hide-known.lua
-- 飛過去的鳥點已經開過：不再列出「開鳥點」步驟；還沒開就照常列出，開了之後就從清單消失（不卡在這步）。
local active, turnedQ, pos = {}, {}, { 1432, 33.9, 51 }
local who = { "Alliance", "Dwarf", 3 }
function UnitFactionGroup() return who[1] end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitRace() return who[2], who[2], who[3] end
function UnitLevel() return 17 end
function UnitXPMax() return 8800 end
function UnitXP() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, drop={}, fpNodes={}, start="Dwarf", station="02-12" }
local function load(route)
  local ns = { C={}, db=db, L={} }
  ns.UI = { Get=function() return false end }
  ns.C.IsOnQuest = function(q) return active[q] end
  ns.C.IsReady = function() return false end
  ns.C.IsTurnedIn = function(q) return turnedQ[q] or false end
  ns.C.XPBuff = function() return false end
  ns.C.Position = function() return pos[1], pos[2], pos[3] end
  ns.C.ZoneTexts = function() end
  ns.C.Bind = function() end
  ns.C.LogQuestIDs = function() local out = {} for q in pairs(active) do out[#out + 1] = q end return out end
  ns.C.Objectives = function() end
  ns.C.GreenRange = function() return 8 end
  for _, file in ipairs({route, "Engine.lua"}) do
    assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
  end
  ns.E.Build()
  return ns.E
end
local fails = 0
local function check(cond, what)
  if not cond then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end
end
local function at(state, t, key)
  for i, step in ipairs(state.steps) do if step.s.t == t and (step.s.node or step.s.to) == key then return i end end
end

-- 聯盟洛克莫丹（02-12）、荒蕪之地卡加斯（部落 03-25）：前一步「飛」只在已開時出現，後面的「鳥」只在沒開時出現
for _, c in ipairs({
  { "Alliance", "Dwarf", 3, "Dwarf", "Data/RouteA.lua", "02-12", "塞爾薩瑪", { 1432, 33.9, 51 }, { "鐵爐堡" } },
  { "Horde", "Orc", 2, "Orc", "Data/Route.lua", "03-25", "卡加斯", { 1418, 3.99, 44.78 }, {} },
}) do
  who[1], who[2], who[3], db.start, db.station = c[1], c[2], c[3], c[4], c[6]
  local E = load(c[5])
  local st = assert(E.byId[c[6]])
  local node = c[7]
  local function reset(known)
    wipe(active); wipe(turnedQ); wipe(db.fpNodes); wipe(db.latch); wipe(db.mark); wipe(db.skip)
    pos[1], pos[2], pos[3] = c[8][1], c[8][2], c[8][3]
    for _, n in ipairs(c[9]) do db.fpNodes[n] = true end
    if known then db.fpNodes[node] = true end
  end
  reset(true)
  local state = E.Locate(st)
  local fp, fly = at(state, "fp", node), at(state, "fly", node)
  check(fp and state.na[fp], c[6] .. " " .. node .. " 已開：不列開鳥點")
  check(fly and not state.na[fly], c[6] .. " " .. node .. " 已開：列出飛過去")
  check(state.cur ~= fp, c[6] .. " " .. node .. " 已開：目前步驟不是開鳥點")
  reset(false)
  state = E.Locate(st)
  check(not state.na[fp] and not state.done[fp], c[6] .. " " .. node .. " 沒開：列出開鳥點、沒打勾")
  check(state.na[fly], c[6] .. " " .. node .. " 沒開：不列飛過去")
  check(state.cur == fp, c[6] .. " " .. node .. " 沒開、人在鳥點：目前就是開鳥點")
  -- 跟飛行管理員開了點（Core 記進 fpNodes）：這步完成後不擋路，目前步驟往下走
  db.fpNodes[node] = true
  state = E.Locate(st)
  check(state.na[fp] and state.cur ~= fp and state.cur ~= nil, c[6] .. " " .. node .. " 剛開：往下一步")
end

if fails > 0 then error(fails .. " failures") end
print("fp-hide-known: all ok")
