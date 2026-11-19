-- Zul’Farrak’s optional Mulgore pickup requires selecting the run on the real plateau.
-- Pickups require the player's actual selected run. A logged delivery can be
-- handed in on a later visit even after switching back to the main route.
local held,ready,turned,bag,log = {},{},{},{},{}
local level,map,x,y,sub,guid,now,offered = 55,1412,33.42,22.59,"plateau",nil,100,nil
local used, inside = 0, false
C_QuestLog = {
  GetMaxNumQuestsCanAccept = function() return 40 end,
  GetNumQuestLogEntries = function() return used, used end,
}
function IsInInstance() return inside end
local options={dPre=true,optional=true,auto=true,dungeonHint=true}
function UnitLevel() return level end
function UnitFactionGroup() return "Horde" end
function UnitRace() return "Scourge","Scourge",5 end
function UnitClass() return "Paladin","PALADIN" end
function UnitGUID(unit) return unit=="npc" and guid or nil end
function GetItemCount(id) return bag[id] or 0 end
function GetQuestID() return offered end
function UnitXP() return 0 end
function UnitXPMax() return 100000 end
function GetTime() return now end
function IsShiftKeyDown() return false end
local callbacks, accepts = {},0
function AcceptQuest() accepts=accepts+1 end
function CreateFrame() return {RegisterEvent=function() end,SetScript=function(_,e,f) callbacks[e]=f end} end
function wipe(t) for k in pairs(t) do t[k]=nil end end
SlashCmdList={}
local ns={C={IsOnQuest=function(q) return held[q] end,IsReady=function(q) return ready[q] end,
  IsTurnedIn=function(q)return turned[q]end,Objectives=function()end,Position=function()return map,x,y end,
  AreaName=function(id) if id==17045 then return "plateau" end end,
  ZoneTexts=function()return sub,"Mulgore",sub end,LogQuestIDs=function()return log end,
  Bind=function()end,XPBuff=function()return false end},
  db={skip={},mark={},latch={},dNo={},dDismiss={},pin={},carry={},notNow={}},
  UI={Get=function(k)return options[k] end},L=setmetatable({},{__index=function(_,k)return k end}),
  msg=function()end,try=function(_,f,...)return f(...)end}
local renderState
local function noop() end
ns.UI.Visible = function() return true end
ns.UI.Render = function(row) renderState = row.state end
ns.UI.AuberdineChoice = noop
ns.UI.SetHidden = noop
ns.N = { Set = noop, Clear = noop, Forget = noop }
ns.T = { Update = noop }
ns.I = { Update = noop }
ns.P = { Update = noop, Clear = noop }
ns.Clean = function(text) return text end
MetroGuideDB = {}
ns.db.optNote, ns.db.skipNote = {}, {}

for _,f in ipairs({"Data/Route.lua","Engine.lua","Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/"..f))("ShengLeveling",ns)
end
local E=ns.E
E.Build()
local function nextIs(d,id,act)
  local step=E.DungeonNext(d,false)
  return step and step.step and step.step.s.q==id and step.step.s.t==act and step.kind==(act=="accept" and "pre" or "post")
end
local function isInside(d,id)
  local state=E.InstanceState(d)
  for _,row in ipairs(state and state.steps or {}) do if row.s.q==id then return row.s end end
end
local function offeredByClient(q)
  now,offered=now+4,q
  local before=accepts
  callbacks.OnEvent(nil,"QUEST_DETAIL")
  return accepts~=before
end
local d, q, min, item, giver = E.byId["05-d21"], 96775, 42, 277112, 264074
map,x,y,sub,guid,level=1412,33.42,22.59,"plateau",nil,min
ns.db.station="05-d33" -- Blackmaw’s plateau giver is near Mazu’kon
assert(not nextIs(d,q,"accept") and not offeredByClient(q))
level=46
local prompt = E.DungeonPrompt()
assert(prompt and ns.db.station == "05-d33")
E.RunDungeon(d)
ns.db.dungeonFrom=nil -- older save without a remembered mainline station
level=min-1
assert(not nextIs(d,q,"accept") and not offeredByClient(q))
level=min
assert(nextIs(d,q,"accept") and offeredByClient(q))
local view=E.Locate(E.Current())
assert(view.cur and view.steps[view.cur].s.q==q, "selected dungeon must lead with the nearby giver")
inside = true
assert(not nextIs(d,q,"accept") and not offeredByClient(q))
inside = false
options.optional=false
assert(not nextIs(d,q,"accept"))
options.optional,options.dPre=true,false
assert(not nextIs(d,q,"accept"))
options.dPre=true
ns.db.dNo[d.id]=true
assert(not nextIs(d,q,"accept"))
ns.db.dNo[d.id]=nil
sub="foothill"
assert(not nextIs(d,q,"accept") and not offeredByClient(q))
guid="Creature-0-11-1-7-"..giver.."-00001"
assert(nextIs(d,q,"accept"))
guid="Creature-0-11-1-7-99999-00001"
assert(not nextIs(d,q,"accept"))
guid,sub,map=nil,"plateau",1456 -- Thunder Bluff is a separate map
assert(not nextIs(d,q,"accept"))
map,x,y=1412,48,60
assert(not nextIs(d,q,"accept"))
x,y=33.42,22.59
used = 39
assert(not nextIs(d,q,"accept") and not offeredByClient(q))
used = 40
assert(not nextIs(d,q,"accept") and not offeredByClient(q))
used = 38
assert(not nextIs(d,q,"accept"))
used = 37
assert(nextIs(d,q,"accept"))
ns.db.dungeonFrom = "04-42"
assert(not E.PreRoom(E.byId["04-42"]) and not nextIs(d,q,"accept") and not offeredByClient(q))
assert(not isInside(d,q))
used = 0
x,y = 32.5,20.66
held[q],ns.db.station,options.optional=true,"04-42",false
assert(isInside(d,q).spot)
local activeInside = E.DungeonNext(d, true)
assert(activeInside and activeInside.kind == "in" and activeInside.step.s.q == q)
map=1456
local carried
for _,target in ipairs(E.DungeonTargets(d)) do if target.q==q then carried=true end end
assert(carried and not nextIs(d,q,"accept"))
map=1412
for _,done in ipairs({false,true}) do for _,count in ipairs({0,1}) do
  ready[q],bag[item]=done,count
  assert((nextIs(d,q,"turnin") or false)==(done and count==1))
end end
x,y=33.42,22.59
assert(not nextIs(d,q,"turnin"))
x,y=32.5,20.66
sub=nil
assert(not nextIs(d,q,"turnin"))
inside = true
assert(not nextIs(d,q,"turnin"))
inside = false
guid="Creature-0-11-1-7-"..giver.."-00001"
assert(nextIs(d,q,"turnin"))
held[q],turned[q]=nil,true
assert(not nextIs(d,q,"turnin"))
options.optional=true
-- Exercise the rendered HUD when only the location evidence or bag count changes.
local function renderEvent(event)
  callbacks.OnEvent(nil, event)
  callbacks.OnUpdate(nil, 0.51)
end
local function tickVisit()
  callbacks.OnUpdate(nil, 0.51) -- Detect changed evidence without an event or position update.
  callbacks.OnUpdate(nil, 0.51) -- Render the dirty HUD.
end
local function shows(verb)
  local cur = renderState and renderState.cur and renderState.steps[renderState.cur].s
  return cur and cur.t == verb and cur.q == q or false
end

map, x, y, sub, guid = 1412, 32.50, 20.66, "plateau", nil
held[q], turned[q], ready[q], bag[item] = nil, nil, nil, nil
ns.db.station = "04-42"
renderEvent("PLAYER_ENTERING_WORLD")
renderEvent("QUEST_LOG_UPDATE")
assert(not shows("accept"), "the main route must not offer this dungeon pickup")

E.RunDungeon(d)
ns.db.dungeonFrom = nil
sub = nil
renderEvent("ZONE_CHANGED")
assert(not shows("accept"))
sub = "plateau"
tickVisit()
assert(shows("accept"))
sub = nil -- Same map and coordinates, different floor.
tickVisit()
assert(not shows("accept"))
guid = "Creature-0-11-1-7-" .. giver .. "-00001"
renderEvent("GOSSIP_SHOW")
assert(shows("accept"))
guid = nil -- Closing the conversation also removes the only proof of the right floor.
tickVisit()
assert(not shows("accept"), "a stale HUD must not keep showing the unavailable pickup")

sub = "plateau"
x = 29.40
tickVisit()
assert(not shows("accept"))
x = 32.50
tickVisit()
assert(shows("accept"))

for _, row in ipairs(d.list) do
  if row.s.q and row.s.q ~= q and row.s.q ~= 2846 then turned[row.s.q] = true end
end
-- Keep a normal later turn-in open so the selected run still owns the HUD.
held[2846], ready[2846], log[2] = true, true, 2846
held[q], ready[q], log[1], options.optional = true, true, q, false
renderEvent("QUEST_LOG_UPDATE")
assert(not shows("turnin"))
bag[item] = 1
renderEvent("BAG_UPDATE_DELAYED")
assert(shows("turnin"))
bag[item] = nil
renderEvent("BAG_UPDATE_DELAYED")
assert(not shows("turnin"))
print("96775: selected dungeon, level, plateau or NPC, journal room, saved quest, nearby turn-in and HUD refresh")
