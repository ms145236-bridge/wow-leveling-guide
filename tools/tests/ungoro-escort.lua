-- An escort stays live between objective updates, and a failed encounter must
-- not advertise the starting cave or the hand-in as its next waypoint.
local A = "addon/ShengLeveling/"
local active, turned, bag = {}, {}, {}
local journalState, objectives
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human", "Human", 1 end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return 53 end
function UnitXP() return 0 end
function UnitXPMax() return 100000 end
function GetItemCount(q) return bag[q] or 0 end
function GetQuestLogIndexByID(q) return active[q] and 1 or 0 end
function GetQuestLogTitle() return "Escort", 53, 1, false, false, journalState end
function GetNumQuestLeaderBoards() return objectives end
function GetQuestLogLeaderBoard() return "Escort", "event", journalState == 1 end
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
function wipe(t) for k in pairs(t) do t[k] = nil end end

local ns = {L=setmetatable({}, {__index=function(_,key) return key end}),
  UI={Get=function(key) return key == "optional" end},
  db={skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}}}
assert(loadfile(A .. "Compat.lua"))("ShengLeveling",ns)
ns.C.IsTurnedIn = function(q) return turned[q] end
ns.C.LogQuestIDs = function() local ids={}; for q in pairs(active) do ids[#ids+1]=q end; return ids end
ns.C.Position = function() return 1449,47,31 end
ns.C.ZoneTexts = function() end
ns.C.Bind = function() end
ns.C.XPBuff = function() return false end
assert(loadfile(A .. "Data/RouteA.lua"))("ShengLeveling",ns)
assert(loadfile(A .. "Engine.lua"))("ShengLeveling",ns)
local E = ns.E
E.Build()
local st = E.byId["04-52"]
local function isolate(q)
  wipe(active); wipe(turned); wipe(ns.db.mark); wipe(ns.db.skip)
  active[q] = true
  for _,w in ipairs(st.list) do
    if w.s.q ~= q then ns.db.mark[w.key] = true end
  end
end
local function action()
  local state=E.Locate(st)
  return state.cur and state.steps[state.cur]
end
for _,q in ipairs({4491,4245}) do
  isolate(q)
  turned[q==4491 and 4492 or 4244] = true
  for _,count in ipairs({0,1}) do
    objectives, journalState = count, 0
    local current = assert(action())
    assert(current.key == "d:" .. q and current.s.t == "do" and not current.s.x)
    journalState = -1
    current = assert(action())
    assert(current.key == "d:" .. q and current.s.t == "note" and current.s.text:find("重接"))
    assert(not current.s.x and not current.s.more)
    E.ToggleSkip(current.key)
    assert(not action())
    E.ToggleSkip(current.key)
    journalState = 1
    current = assert(action())
    assert(current.key == "t:" .. q and current.s.map == 1449)
  end
  active[q], journalState = nil, 0
  assert(action().key == "a:" .. q)
end
-- Bag contents can change before or after the quest-completion flag.
for _,q in ipairs({4496,4301}) do
  isolate(q); turned[q==4301 and 4289 or 4495] = true
  for _,ready in ipairs({false,true}) do
    journalState = ready and 1 or 0
    for _,n in ipairs({0,1,2}) do
      bag[11476],bag[11837],bag[11018] = n==2 and 1 or 0,n>=1 and 1 or 0,n==2 and 5 or 4
      local row = action()
      if n < 2 then
        assert(row and row.key == "d:" .. q)
      elseif ready then
        assert(row and row.key == "t:" .. q)
      else
        assert(not row)
      end
    end
  end
end
print("Two Un'Goro escorts require confirmed success; gathering and handoffs follow physical materials")
