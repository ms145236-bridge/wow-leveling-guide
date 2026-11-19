-- The A12 hand-in is a detour only warranted by a live quest and its issued parcel.
local active, ready, turned, bags, callbacks = {}, {}, {}, {}, {}
local shown, arrow
local function noop() end
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Night Elf", "NightElf", 4 end
function UnitClass() return "Hunter", "HUNTER" end
function UnitLevel() return 17 end
function UnitXP() return 15092 end
function UnitXPMax() return 18500 end
function GetTime() return 100 end
function GetItemCount(item) return bags[item] or 0 end
function CreateFrame()
  return {RegisterEvent=noop, SetScript=function(_, event, callback) callbacks[event]=callback end}
end
function wipe(t) for key in pairs(t) do t[key]=nil end end
SlashCmdList, MetroGuideDB = {}, {}
local ns={
  db={skip={}, mark={}, latch={}, pin={}, dNo={}, dDismiss={}, carry={}, notNow={}, fpNodes={}, optNote={}, skipNote={}},
  C={
    Position=function() return 1432,46.05,13.61 end,
    ZoneTexts=function() return "", "洛克莫丹" end,
    Bind=noop,
    IsOnQuest=function(q) return active[q] end,
    IsReady=function(q) return ready[q] end,
    IsTurnedIn=function(q) return turned[q] end,
    Objectives=function() return {} end,
    LogQuestIDs=function() return {} end,
    XPBuff=function() return false end,
    GreenRange=function() return 8 end,
  },
  UI={Get=noop, Visible=function() return true end, Render=function(view) shown=view.state end, SetHidden=noop, AuberdineChoice=noop},
  N={Set=function(map,x,y) arrow={map,x,y} end, Clear=function() arrow=nil end, Forget=noop},
  T={Update=noop}, I={Update=noop}, P={Update=noop,Clear=noop},
  L=setmetatable({}, {__index=function(_,key) return key end}),
  Clean=function(s) return s end,
  try=function(_,f,...) return f(...) end,
}
for _, file in ipairs({"Data/RouteA.lua","Engine.lua","Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/"..file))("ShengLeveling",ns)
end
ns.E.Build()
ns.E.built = true
local st, earlier = ns.E.byId["02-12"], ns.E.byId["01-9"]
local parcel
for _, step in ipairs(earlier.list) do
  if step.s.t=="turnin" and step.s.q==353 then
    assert(step.key=="t:353" and not step.s.when, "normal early tower visit is unchanged")
  end
end
for _, step in ipairs(st.list) do
  if step.s.q==353 and step.s.t=="turnin" then parcel=step
  elseif not (step.s.q==2038 and step.s.t=="turnin") then ns.db.mark[step.key]=true end
end
assert(parcel and parcel.key=="t:353" and parcel.s.when.bag.item==2806 and parcel.s.providedVisit==2806)
ns.db.station=st.id
local function event(name)
  callbacks.OnEvent(nil,name)
  callbacks.OnUpdate(nil,.51)
end
local function expect(q, action, map, x, y)
  local row=assert(shown and shown.cur and shown.steps[shown.cur])
  assert(row.s.q==q and row.s.t==action, "unexpected current hand-in")
  assert(arrow and arrow[1]==map and arrow[2]==x and arrow[3]==y)
end
local function expectBingles()
  expect(2038,"turnin",1432,63.56,47.92)
end
local function expectTower(action)
  expect(353,action,1432,24.76,18.40)
end
active[2038], ready[2038] = true, true
event("PLAYER_ENTERING_WORLD")
event("QUEST_LOG_UPDATE")
expectBingles()
active[353], ready[353] = true, true
ns.db.pin[st.id]={key=parcel.key, wasDone=true}
event("QUEST_LOG_UPDATE")
expectBingles()
assert(ns.db.pin[st.id].key==parcel.key, "empty bags suspend a saved pin")
bags[2806] = 1
event("BAG_UPDATE_DELAYED")
expectTower("turnin")
bags[2806] = 0
event("BAG_UPDATE_DELAYED")
expectBingles()
ready[353], bags[2806] = false, 1
event("BAG_UPDATE_DELAYED")
expectTower("do")
ready[353] = true
event("QUEST_LOG_UPDATE")
expectTower("turnin")
active[353], turned[353], bags[2806] = nil, true, 0
ns.db.pin[st.id]=nil
event("QUEST_LOG_UPDATE")
expectBingles()
turned[353], active[353], ready[353], bags[2806] = nil, true, true, 1
ns.db.skip[parcel.key] = true
event("QUEST_LOG_UPDATE")
expectBingles()
ns.db.skip[parcel.key] = nil
ns.db.mark[parcel.key] = true
event("QUEST_LOG_UPDATE")
expectBingles()
print("Loch Modan parcel: actual bag events restore the same saved hand-in and suppress empty-bag navigation")
