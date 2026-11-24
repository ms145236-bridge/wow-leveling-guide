-- From the repository root: lua5.1 tools/tests/duskwood-fly-prereq.lua
-- 暮色森林第一次（02-17）：人在西部荒野、還沒飛回夜色鎮。早先接了插在站尾的副本前置「罪與罰」，
-- 不能讓「後面有已完成的接」把「飛 夜色鎮」當成已經過了（11/24 實測：飛這步被跳過，箭頭直接指 2 公里外的交任務）。
local active, turnedQ, pos = {}, {}, { 1436, 41.5, 66.7 }
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 26 end
function UnitXPMax() return 20000 end
function UnitXP() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, drop={}, fpNodes={}, start="Human", station="02-17" }
local ns = { C={}, db=db, L={} }
ns.UI = { Get=function(k) return k == "dPre" or k == "optional" end } -- 帶副本前置（預設開）
ns.C.IsOnQuest = function(q) return active[q] end
ns.C.IsReady = function(q) return active[q] or false end -- 日誌裡的都做完了，只差交
ns.C.IsTurnedIn = function(q) return turnedQ[q] or false end
ns.C.XPBuff = function() return false end
ns.C.Position = function() return pos[1], pos[2], pos[3] end
ns.C.ZoneTexts = function() end
ns.C.Bind = function() end
ns.C.LogQuestIDs = function() local out = {} for q in pairs(active) do out[#out + 1] = q end return out end
ns.C.Objectives = function() end
ns.C.GreenRange = function() return 8 end
for _, file in ipairs({ "Data/RouteA.lua", "Engine.lua" }) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local st = assert(E.byId["02-17"])
for _, n in ipairs({ "暴風城", "湖畔鎮", "哨兵嶺", "夜色鎮" }) do db.fpNodes[n] = true end

local fails = 0
local function check(cond, what)
  if not cond then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end
end

-- 走到「飛 夜色鎮」之前：前面交過的任務算交了，接了還沒交的在日誌裡
local state = E.Locate(st)
local fly
for i, step in ipairs(state.steps) do if step.s.t == "fly" and step.s.to == "夜色鎮" and i > 10 then fly = i; break end end
assert(fly, "找不到飛 夜色鎮")
local function walkTo()
  wipe(active); wipe(turnedQ)
  for i = 1, fly - 1 do
    local s = state.steps[i].s
    if s.q and s.t == "turnin" then turnedQ[s.q], active[s.q] = true, nil
    elseif s.q and s.t == "accept" and not turnedQ[s.q] then active[s.q] = true end
  end
end
local prereq
for i, step in ipairs(state.steps) do if step.s.t == "accept" and step.s.q == 377 then prereq = i end end
check(prereq and prereq > fly, "罪與罰的接排在飛之後（站尾的副本前置）")

walkTo()
state = E.Locate(st)
check(state.cur == fly, "沒接罪與罰：目前是飛夜色鎮")

walkTo()
active[377] = true
state = E.Locate(st)
check(state.cur == fly and not state.done[fly], "早先接了罪與罰：還是先飛夜色鎮，不跳過")

-- 已接罪與罰、飛到夜色鎮鳥點、還沒交 148：人到了就算飛過了
pos[1], pos[2], pos[3] = 1431, 77.49, 44.29
state = E.Locate(st)
check(state.done[fly] and state.cur > fly, "早接罪與罰、人到夜色鎮：飛這步算到了")
pos[1], pos[2], pos[3] = 1436, 41.5, 66.7
wipe(db.latch)

-- 交了下一步的任務（人已經飛過去做事了）：飛這步照舊算過了
turnedQ[148], active[148] = true, nil
state = E.Locate(st)
check(state.done[fly] and state.cur > fly, "交了來自夜色鎮的補給：飛這步算過了")

if fails > 0 then error(fails .. " failures") end
print("duskwood-fly-prereq: all ok")
