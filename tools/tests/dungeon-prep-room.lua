-- From the project root: lua5.1 tools/tests/dungeon-prep-room.lua
local search, fallen, otherPrep, mainQuest = 95772, 95795, 95646, 169
local active, ready, turned, log = {}, {}, {}, {}
local level, now, offered = 24, 100, search
local handlers, accepted = {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return level end
function UnitXP() return 0 end
function UnitXPMax() return 36300 end
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
  C = {IsOnQuest=function(q) return active[q] end, IsReady=function(q) return ready[q] end,
       IsTurnedIn=function(q) return turned[q] end, LogQuestIDs=function() return log end,
       XPBuff=function() return false end, Position=function() end, ZoneTexts=function() end,
       Bind=function() end, Objectives=function() end},
  db = {skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}},
  UI = {Get=function(k) return k == "optional" or k == "dPre" or k == "auto" end},
  L = setmetatable({}, {__index=function(_, key) return key end}),
  msg = function() end,
  try = function(_, f, ...) return f(...) end,
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua", "Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local st = assert(E.byId["02-19"])
local lastState
for i = 1, math.huge do
  local key = debug.getupvalue(handlers.OnUpdate, i)
  if key == "lastState" then lastState = i; break end
  if not key then break end
end
assert(lastState, "inject the same route state that Core's regular refresh would supply")

local function fillLog(held)
  log = {}
  for k = 1, held do log[k] = 100000 + k end
end
local function row(state, q, action)
  for i, step in ipairs(state.steps) do
    if step.s.t == action and step.s.q == q then return step, i end
  end
  error("missing " .. action .. " " .. q)
end
local function tryAccept(q, state)
  offered = q
  debug.setupvalue(handlers.OnUpdate, lastState, state)
  local count = #accepted
  handlers.OnEvent(nil, "QUEST_DETAIL")
  return #accepted > count
end

for _, held in ipairs({0, 35, 37, 38, 39, 40}) do
  fillLog(held)
  local state = E.Locate(st)
  local step, index = row(state, search, "accept")
  assert((not state.na[index]) == E.PreRoom(st))
  assert((step.defer == true) == (not E.PreRoom(st)))
  assert(tryAccept(search, state) == E.PreRoom(st))
  now = now + 4
end
fillLog(38)
assert(not tryAccept(search, nil), "a pending refresh must not bypass the actual log limit")
fillLog(0)
assert(tryAccept(search, nil))
now = now + 4

local maxHeld = 0
for held = 0, 40 do
  fillLog(held)
  if E.PreRoom(st) then maxHeld = held else break end
end
assert(maxHeld > 0 and maxHeld < 37, "future mainline work retains reserved slots")
fillLog(maxHeld - 1)
local state = E.Locate(st)
assert(E.PreRoom(st, 1) and not E.PreRoom(st, 2))
assert(tryAccept(search, state))
assert(tryAccept(otherPrep, state))
assert(not tryAccept(search, state), "two pending clicks already consumed the available room")
now = now + 4

level = 27
fillLog(39)
assert(tryAccept(mainQuest, E.Locate(st)), "regular mainline has its reserved place")
active[fallen], ready[fallen], turned[search], log[40] = true, true, true, fallen
local full = E.Locate(st)
local _, returnIndex = row(full, fallen, "turnin")
assert(E.LogFull() and not full.na[returnIndex] and not full.wait[returnIndex])
print("Authored dungeon prep honors capacity in route and actual quest-detail callbacks")

-- Franclorn offers the second Dark Iron Legacy immediately after the first turn-in.
do
  level, now = 48, now + 4
  function UnitName() return "弗蘭克羅恩·鑄鐵" end
  wipe(active)
  wipe(ready)
  wipe(turned)
  local gorge = E.byId["04-45"]
  -- The fullest log that still has exactly one prep slot left (depends on the mainline accepts ahead).
  local held = 0
  repeat held = held + 1; fillLog(held) until not E.PreRoom(gorge, 1) or held == 40
  fillLog(held)
  local state = E.Locate(gorge)
  assert(E.PreRoom(gorge) and not E.PreRoom(gorge, 1))
  assert(tryAccept(3801, state))
  now = now + 0.31
  handlers.OnEvent(nil, "QUEST_TURNED_IN", 999998)
  assert(not tryAccept(3802, state), "unrelated turn-ins still reserve the pending slot")
  handlers.OnEvent(nil, "QUEST_TURNED_IN", 3801)
  assert(tryAccept(3802, state), "the confirmed handoff releases only its own pending slot")
  fillLog(40)
  assert(not tryAccept(3802, state))
end

level = 27
UnitName = nil

-- Ordinary quests do not need the dungeon-prep reserve, but still occupy a slot.
-- Both menu paths must keep an outstanding turn-in accessible at capacity.
local secondQuest = 150
local selected, turnins, rewards = {}, 0, 0
function GetNumActiveQuests() return 0 end
function GetNumAvailableQuests() return 2 end
function GetAvailableTitle(i) return ns.Route.quests[i == 1 and mainQuest or secondQuest].n end
function SelectAvailableQuest(i) selected[#selected+1] = i end
C_GossipInfo = {
  GetAvailableQuests = function() return {{questID=mainQuest},{questID=secondQuest}} end,
  SelectAvailableQuest = function(q) selected[#selected+1] = q end,
}
function IsQuestCompletable() return true end
function CompleteQuest() turnins = turnins + 1 end
function GetNumQuestChoices() return 1 end
function GetQuestReward() rewards = rewards + 1 end
local function event(kind, ...) handlers.OnEvent(nil, kind, ...) end
local function resetOffers(n)
  wipe(active)
  wipe(selected)
  now = now + 4
  fillLog(n)
end
resetOffers(40)
assert(not tryAccept(mainQuest, nil))
event("GOSSIP_SHOW"); event("QUEST_GREETING")
assert(#selected == 0)
active[mainQuest] = true
event("QUEST_PROGRESS"); event("QUEST_COMPLETE")
assert(turnins == 1 and rewards == 1)
active[mainQuest] = nil
C_QuestLog = {GetNumQuestLogEntries = function() return 4, 40 end} -- three folded zones
resetOffers(2)
assert(not tryAccept(mainQuest, nil))
C_QuestLog.GetNumQuestLogEntries = function() return 43, 39 end
resetOffers(39)
event("GOSSIP_SHOW"); event("QUEST_GREETING")
assert(selected[1] == mainQuest and selected[2] == 1)
assert(tryAccept(mainQuest, nil))
event("GOSSIP_SHOW"); event("QUEST_GREETING")
assert(#selected == 2 and not tryAccept(secondQuest, nil)) -- last slot still pending
assert(not tryAccept(mainQuest, nil))
active[mainQuest] = true
C_QuestLog.GetNumQuestLogEntries = function() return 44, 40 end
assert(not tryAccept(secondQuest, nil))
resetOffers(38)
C_QuestLog.GetNumQuestLogEntries = function() return 42, 38 end
assert(tryAccept(mainQuest, nil) and not tryAccept(mainQuest, nil) and tryAccept(secondQuest, nil))
resetOffers(39)
C_QuestLog.GetNumQuestLogEntries = function() return 44, 39 end
assert(tryAccept(mainQuest, nil))
active[mainQuest], log[40] = true, mainQuest
event("QUEST_ACCEPTED", 40, mainQuest)
assert(E.LogFull() and not tryAccept(secondQuest, nil), "the enumerated fortieth quest is already in the log")
resetOffers(38)
C_QuestLog.GetNumQuestLogEntries = function() return 42, 38 end
assert(tryAccept(secondQuest, nil) and tryAccept(mainQuest, nil))
active[mainQuest], log[39] = true, mainQuest
event("QUEST_ACCEPTED", 39, mainQuest)
now = now + 0.2
active[mainQuest], log[39] = nil, nil
event("QUEST_REMOVED", 987654)
assert(not tryAccept(mainQuest, nil), "removal of a different quest must not clear pending accepts")
event("QUEST_REMOVED", mainQuest)
assert(tryAccept(mainQuest, nil), "a confirmed abandonment permits immediate re-acceptance")
assert(not tryAccept(secondQuest, nil), "the other pending acceptance still occupies its slot")
resetOffers(2)
C_QuestLog.GetNumQuestLogEntries = function() return 4, 39 end
assert(tryAccept(mainQuest, nil))
active[mainQuest] = true
event("QUEST_ACCEPTED", mainQuest)
assert(not tryAccept(secondQuest, nil), "a folded list can confirm ownership before updating its total")
resetOffers(38)
C_QuestLog.GetNumQuestLogEntries = function() return 42, 38 end
assert(tryAccept(mainQuest, nil))
log[39] = mainQuest
C_QuestLog.GetNumQuestLogEntries = function() return 43, 39 end
event("QUEST_ACCEPTED", 39, mainQuest)
assert(not tryAccept(mainQuest, nil) and tryAccept(secondQuest, nil), "the visible ID already accounts for its own slot")
resetOffers(2)
C_QuestLog.GetNumQuestLogEntries = function() return 4, 38 end
assert(tryAccept(mainQuest, nil))
event("QUEST_ACCEPTED", mainQuest)
C_QuestLog.GetNumQuestLogEntries = function() return 4, 39 end
assert(not tryAccept(mainQuest, nil) and tryAccept(secondQuest, nil), "counted folded acceptance frees the reservation but not a duplicate offer")
resetOffers(2)
C_QuestLog.GetNumQuestLogEntries = function() return 4, 38 end
assert(tryAccept(mainQuest, nil) and tryAccept(secondQuest, nil))
event("QUEST_ACCEPTED", mainQuest)
event("QUEST_ACCEPTED", secondQuest)
active[secondQuest] = true
C_QuestLog.GetNumQuestLogEntries = function() return 4, 39 end
event("QUEST_REMOVED", 987654)
assert(not tryAccept(115, nil), "an unrelated removal cannot release either reservation")
event("QUEST_REMOVED", mainQuest)
assert(tryAccept(mainQuest, nil), "the later confirmed quest now occupies the 39th slot")
event("QUEST_REMOVED", secondQuest)
event("QUEST_TURNED_IN", secondQuest)
assert(not tryAccept(mainQuest, nil), "a second removal notification must leave other offers alone")
resetOffers(0)
C_QuestLog.GetNumQuestLogEntries = function() return 0 end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 0 end
local readList = ns.C.LogQuestIDs
ns.C.LogQuestIDs = function() return nil end
assert(tryAccept(mainQuest, nil), "unavailable counts must not report a full journal")
ns.C.LogQuestIDs = readList
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end
resetOffers(25)
assert(not tryAccept(mainQuest, nil))
resetOffers(24)
assert(tryAccept(mainQuest, nil))
print("Ordinary, pending and folded-log auto-accept limits preserve active turn-ins")

C_QuestLog = nil
ns.C.LogQuestIDs = function() return log end
now = now + 4

-- An optional item offer and a stale item dialog must respect the current
-- journal even when the cursor still points at the previous frame.
local scale, torwa = 87494, 4291
function UnitName() return nil end -- An item dialog has no NPC target.
GetItemCount = function(item) return item == 280459 and 1 or 0 end
level, active[torwa], ready[torwa] = 49, true, true
fillLog(39)
log[1] = torwa
local torwaState = E.Locate(E.byId["04-48"])
assert(tryAccept(scale, torwaState))
now = now + 4
log[40] = 100040
assert(not tryAccept(scale, torwaState))
log[2], active[scale], ready[scale] = scale, true, false
assert(not tryAccept(scale, torwaState))
log[2], active[scale], turned[scale], log[40] = 100002, nil, true, nil
assert(not tryAccept(scale, torwaState))

-- The same quest ID has two valid city trainers. A stale or unidentified
-- dialog must not press Accept, and an ordinary manual accept still works.
ns.db.station, level = "04-48", 51
local trainerName, cityMap = "喬舒修士", 1453
UnitName = function(unit) return unit == "npc" and trainerName end
ns.C.Position = function() return cityMap, 49.50, 45.21 end
UnitClass = function() return "Priest", "PRIEST" end
E.Build()
fillLog(39)
assert(tryAccept(8254, nil))
trainerName = "其它牧師訓練師"
assert(not tryAccept(8254, nil))
now = now + 4 -- independent native offer at the other city
trainerName, cityMap = "高階牧師洛漢", 1455
assert(tryAccept(8254, nil))
fillLog(40)
assert(not tryAccept(8254, nil))
fillLog(39)
active[8254] = true
assert(not tryAccept(8254, nil))
active[8254], turned[8254] = nil, true
assert(not tryAccept(8254, nil))
now = now + 4 -- separate player, new quest log
UnitClass = function() return "Mage", "MAGE" end
E.Build()
cityMap, trainerName = 1455, "丁克"
assert(tryAccept(8250, nil))
trainerName = nil
assert(not tryAccept(8250, nil))
now = now + 4
cityMap, trainerName = 1453, "瑪姬諾·仲馬"
assert(tryAccept(8250, nil))
ns.UI.Get = function(k) return k == "auto" end
assert(not tryAccept(8250, nil))
