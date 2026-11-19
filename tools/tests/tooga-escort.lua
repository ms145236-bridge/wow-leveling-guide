-- Tooga's escort observes native journal state and never sends failed players back to the coast.
local active, turned, callbacks = {}, {}, {}
local nativeReady, nativeFailed, objective, shown, arrow, auto
local map, x, y, length, optional = 1446,66.99,22.36,0,false
local function noop() end
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Night Elf", "NightElf", 4 end
function UnitClass() return "Hunter", "HUNTER" end
function UnitLevel() return 46 end
function UnitXP() return 17660 end
function UnitXPMax() return 125000 end
function GetTime() return 100 end
function GetLocale() return "zhTW" end
function GetItemCount() return 0 end
function GetQuestID() return 1560 end
function IsShiftKeyDown() return false end
function AcceptQuest() error("the optional Tooga escort must be accepted manually at A43") end
function GetNumQuestLogEntries() return length,length end
function CreateFrame()
  return {RegisterEvent=noop, SetScript=function(_, event, callback) callbacks[event]=callback end}
end
function wipe(t) for key in pairs(t) do t[key]=nil end end
SlashCmdList, MetroGuideDB = {}, {}
C_QuestLog = {
  IsOnQuest=function(q) return active[q] end,
  IsComplete=function(q) return q==97530 or (q==1560 and nativeReady) end,
  IsFailed=function(q) return q==1560 and nativeFailed or false end,
  IsQuestFlaggedCompleted=function(q) return turned[q] end,
  GetQuestObjectives=function(q)
    if q~=1560 or objective==nil then return nil end
    return {{text="Lead Tooga to Torta", numFulfilled=objective and 1 or 0, numRequired=1, finished=objective}}
  end,
}
if arg[1]=="legacy" then
  C_QuestLog.IsComplete, C_QuestLog.IsFailed, C_QuestLog.GetQuestObjectives = nil,nil,nil
  function GetQuestLogIndexByID(q) return active[q] and q or 0 end
  function GetQuestLogTitle(index)
    local state = index==97530 and 1 or nativeFailed and -1 or nativeReady and 1 or 0
    return "", 46, "", false, false, state
  end
  function GetNumQuestLeaderBoards(index) return index==1560 and objective~=nil and 1 or 0 end
  function GetQuestLogLeaderBoard()
    return objective and "Lead Tooga to Torta: 1/1" or "Lead Tooga to Torta: 0/1", "event", objective
  end
end
local ns={
  db={skip={}, mark={}, latch={}, pin={}, dNo={}, dDismiss={}, carry={}, notNow={}, fpNodes={}, optNote={}, skipNote={}},
  UI={Get=function(key) return (key=="optional" and optional) or (key=="auto" and auto) end, Visible=function() return true end,
    Render=function(view) shown=view.state end, SetHidden=noop, AuberdineChoice=noop},
  N={Set=function(m,xx,yy) arrow={m,xx,yy} end, Clear=function() arrow=nil end, Forget=noop},
  T={Update=noop}, I={Update=noop}, P={Update=noop, Clear=noop},
}
assert(loadfile("addon/ShengLeveling/Compat.lua"))("ShengLeveling",ns)
ns.C.Position=function() return map,x,y end
ns.C.ZoneTexts=function() return "", "塔納利斯" end
ns.C.XPBuff=function() return false end
ns.C.LogQuestIDs=function() return {} end
ns.try=function(_, f, ...) return f(...) end
for _, file in ipairs({"Data/RouteA.lua","Engine.lua","Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/"..file))("ShengLeveling",ns)
end
ns.E.Build()
ns.E.built = true
local st=ns.E.byId["04-43"]
local accept, work, delivery, following, acceptIndex
for index, row in ipairs(st.list) do
  if row.s.q==1560 then
    if row.s.t=="accept" then accept,acceptIndex=row,index
    elseif row.s.t=="do" then work=row
    elseif row.s.t=="turnin" then delivery=row end
  elseif row.s.q==97530 and row.s.t=="turnin" then following=row
  else ns.db.mark[row.key]=true end
end
assert(accept.key=="a:1560" and delivery.key=="t:1560" and work.key=="d:1560")
assert(not work.s.x and not work.s.more and following.note and not following.note.x)
ns.db.station=st.id
active[97530]=true
local function event(name)
  callbacks.OnEvent(nil,name)
  callbacks.OnUpdate(nil,.51)
end
local function expect(q, stepType, hasArrow)
  local row=assert(shown and shown.cur and shown.steps[shown.cur])
  assert(row.s.q==q and row.s.t==stepType, string.format("expected %d %s, got %s %s",q,stepType,tostring(row.s.q),row.s.t))
  assert((arrow~=nil)==hasArrow)
end
event("PLAYER_ENTERING_WORLD")
event("QUEST_LOG_UPDATE")
expect(97530,"turnin",true)
optional=true
event("QUEST_LOG_UPDATE")
expect(97530,"turnin",true)
x,y=29.80,65.20
length=40
event("QUEST_LOG_UPDATE")
expect(97530,"turnin",true)
length=39
x,y=66.99,22.36
event("QUEST_LOG_UPDATE")
assert(shown.na[acceptIndex])
x,y=29.80,65.20
callbacks.OnUpdate(nil,.51)
callbacks.OnUpdate(nil,.51)
assert(ns.E.Applies(accept.s.when) and not shown.na[acceptIndex])
auto=true
event("QUEST_DETAIL")
auto=false
x,y=66.99,22.36
callbacks.OnUpdate(nil,.51)
callbacks.OnUpdate(nil,.51)
assert(shown.na[acceptIndex])
active[1560], optional = true,false
x,y=66.99,22.36
event("QUEST_LOG_UPDATE")
expect(1560,"do",false)
ns.db.pin[st.id]={key=delivery.key, wasDone=true}
nativeReady,objective=true,false
event("QUEST_LOG_UPDATE")
expect(1560,"do",false)
assert(ns.db.pin[st.id].key==delivery.key)
nativeFailed=true
event("QUEST_LOG_UPDATE")
expect(97530,"turnin",true)
assert(ns.E.Applies(following.note.when))
assert(arrow[2]~=66.58, "failed escort may continue without a new trip to Torta")
ns.db.pin[st.id]={key=work.key, wasDone=true}
event("QUEST_LOG_UPDATE")
expect(97530,"turnin",true)
ns.db.pin[st.id]=nil
nativeFailed,nativeReady,objective=false,false,true
event("QUEST_LOG_UPDATE")
expect(1560,"do",false)
nativeReady=true
event("QUEST_LOG_UPDATE")
expect(1560,"turnin",true)
assert(arrow[1]==1446 and arrow[2]==66.58 and arrow[3]==25.67)
objective=nil
event("QUEST_LOG_UPDATE")
expect(1560,"turnin",true)
ns.db.pin[st.id]=nil
ns.db.skip[delivery.key]=true
event("QUEST_LOG_UPDATE")
expect(97530,"turnin",true)
ns.db.skip[delivery.key]=nil
ns.db.mark[delivery.key]=true
event("QUEST_LOG_UPDATE")
expect(97530,"turnin",true)
ns.db.mark[delivery.key]=nil
active[1560],turned[1560]=nil,true
event("QUEST_LOG_UPDATE")
expect(97530,"turnin",true)
print("Tooga ("..(arg[1] or "modern").."): journal events, optional pickup, absent/failed escort, saved keys and success passed")
