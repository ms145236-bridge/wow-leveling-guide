-- From the project root: lua5.1 tools/tests/mainline-prep-detail.lua
-- 主線上的副本前置接取（1.13.36：奧格瑪 Nogg 的設備之戰 2841，05-d15 諾莫瑞根）：
-- 主卡還沒刷新時，NPC 直接跳出任務內容（QUEST_DETAIL）也要用存檔的站算預留；選「不打」不接。
local quest, prep = 2841, "05-d15"
local active, log = {}, {}
local now, offered = 100, quest
local handlers, accepted = {}, {}
local settings = {optional=true, dPre=true, auto=true}
function UnitFactionGroup() return "Horde" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitRace() return "Orc", "Orc", 2 end
function UnitLevel() return 36 end
function UnitXP() return 0 end
function UnitXPMax() return 67100 end
function GetTime() return now end
function GetQuestID() return offered end
function IsShiftKeyDown() return false end
function AcceptQuest() accepted[#accepted + 1] = offered end
function CreateFrame()
  return {RegisterEvent=function() end, SetScript=function(_, event, handler) handlers[event] = handler end}
end
function wipe(t) for k in pairs(t) do t[k] = nil end end
SlashCmdList = {}

local ns = {
  C = {IsOnQuest=function(q) return active[q] end, IsReady=function() return false end,
       IsTurnedIn=function() return false end, LogQuestIDs=function() return log end,
       XPBuff=function() return false end, Position=function() end, ZoneTexts=function() end,
       Bind=function() end, Objectives=function() end},
  db = {skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}, station="03-18"},
  UI = {Get=function(k) return settings[k] or false end},
  L = setmetatable({}, {__index=function(_, key) return key end}),
  msg = function() end,
  try = function(_, f, ...) return f(...) end,
}
for _, file in ipairs({"Data/Route.lua", "Engine.lua", "Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local st = assert(E.byId["03-18"])
local step
for _, w in ipairs(st.list) do if w.s.t == "accept" and w.s.q == quest then step = w.s end end
assert(step and step.when and step.when.dungeonPrep == prep, "2841 的主線接取是 05-d15 的副本前置")

local function fillLog(held)
  log = {}
  for k = 1, held do log[k] = 100000 + k end
end
local function tryAccept()
  local count = #accepted
  handlers.OnEvent(nil, "QUEST_DETAIL")
  now = now + 4
  return #accepted > count
end

-- 主卡沒有刷新過（lastState 是 nil）：預留照存檔的站算
local blocked = 0
for held = 0, 39 do
  fillLog(held)
  local room = E.PreRoom(st)
  assert(tryAccept() == room, ("日誌 %d 格：自動接取要和主線預留一致"):format(held))
  if not room then blocked = blocked + 1 end
end
assert(blocked > 0, "日誌快滿時會擋")
for _, held in ipairs({34, 35, 36, 37}) do
  fillLog(held)
  assert(not E.PreRoom(st) and not tryAccept(), ("日誌 %d 格不接副本前置"):format(held))
end

fillLog(0)
ns.db.dNo[prep] = true
assert(not tryAccept(), "選「不打」不接")
ns.db.dNo[prep] = nil
assert(tryAccept(), "空日誌、沒選不打才接")
-- 主卡刷新成副本卡（設諾莫瑞根為目標）時，用出發的主線站算預留；回到主線後用主線卡
local upvalue
for i = 1, math.huge do
  local key = debug.getupvalue(handlers.OnUpdate, i)
  if key == "lastState" then upvalue = i; break end
  if not key then break end
end
assert(upvalue, "inject the state Core's regular refresh supplies")
local gnomeregan = assert(E.byId[prep])
E.RunDungeon(gnomeregan)
assert(ns.db.station == prep and ns.db.dungeonFrom == "03-18")
debug.setupvalue(handlers.OnUpdate, upvalue, {st = gnomeregan, steps = {}})
for held = 0, 39 do
  fillLog(held)
  assert(tryAccept() == E.PreRoom(st), ("副本卡、日誌 %d 格：用出發站 03-18 的預留"):format(held))
end
for _, held in ipairs({34, 35, 36, 37}) do
  fillLog(held)
  assert(not tryAccept(), ("副本卡、日誌 %d 格不接副本前置"):format(held))
end
ns.db.station, ns.db.dungeonFrom = "03-18", nil
debug.setupvalue(handlers.OnUpdate, upvalue, E.Locate(st))
for held = 0, 39 do
  fillLog(held)
  assert(tryAccept() == E.PreRoom(st), ("回到主線卡、日誌 %d 格：預留一致"):format(held))
end
print("Mainline dungeon prep: QUEST_DETAIL keeps the main-station reservation before the first refresh, on the dungeon card and back on the main card")
