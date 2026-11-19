-- Exercise the generated Alliance route with a live journal, bags and wing labels.
local settings = {dPre=true, optional=true, auto=true}
local active, ready, turned, bag = {}, {}, {}, {}
local inside, instance, subzone, minimap = false, 0, "", ""
local map, x, y = 1423, 71.66, 49.94
local used, pending, souls = 25, 0, 0
local offered, speaking, handler, accepts
accepts = 0
function GetTime() return 100 end
function UnitName() return speaking end
function GetQuestID() return offered end
function IsShiftKeyDown() return false end
function AcceptQuest() accepts = accepts + 1 end
function CreateFrame()
  return {RegisterEvent=function() end, SetScript=function(_, key, f) if key == "OnEvent" then handler = f end end}
end
SlashCmdList = {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 59 end
function UnitXP() return 0 end
function UnitXPMax() return 209800 end
function GetItemCount(id) return bag[id] or 0 end
function IsInInstance() return inside end
function GetInstanceInfo() return nil,nil,nil,nil,nil,nil,nil,instance end
function GetSubZoneText() return subzone end
function GetMinimapZoneText() return minimap end
function GetLocale() return "enUS" end
function GetNumQuestLogEntries() return used, used end
function wipe(t) for k in pairs(t) do t[k]=nil end end
local ns = {
  db={skip={}, mark={}, latch={}, dNo={}, pin={}, carry={}, preset={}, notNow={}},
  L=setmetatable({}, {__index=function(_, key) return key end}),
  UI={Get=function(k) return settings[k] end},
  try=function(_, f, ...) return f(...) end,
  C={
    Position=function() return map, x, y end,
    IsOnQuest=function(q) return active[q] end,
    IsReady=function(q) return q == 5282 and souls == 15 or ready[q] end,
    IsTurnedIn=function(q) return turned[q] end,
    Objectives=function(q) return {{done=q == 5282 and souls == 15 or ready[q] or false}} end,
    LogQuestIDs=function() return {} end,
    Bind=function() end,
    ZoneTexts=function() end,
    GreenRange=function() return 8 end,
    XPBuff=function() return false end,
  }
}
for _, path in ipairs({"Data/RouteA.lua", "Data/Wings.lua", "Engine.lua", "Core.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. path))("ShengLeveling", ns)
end
ns.PendingAccepts = function() return pending end
local E, R = ns.E, ns.Route
E.Build()
local d = assert(E.byId["05-d13"])
local function row(st, q, verb, phase)
  for _, wrapper in ipairs(st.list) do
    local s = wrapper.s
    if s.q == q and s.t == verb and (not phase or s.ph == phase) then return wrapper end
  end
  error("missing " .. q .. " " .. verb)
end
local function hud(q)
  local state = E.InstanceState(d)
  for _, wrapper in ipairs(state and state.steps or {}) do
    if wrapper.s.q == q then return wrapper.s end
  end
end
local function nextStep()
  local result = E.DungeonNext(d, inside)
  return result and result.step and result.step.s
end

local function visible(st, step)
  local state = E.Locate(st)
  for i, candidate in ipairs(state.steps) do
    if candidate.s == step and not (state.na[i] or state.wait[i] or state.done[i]) then return true end
  end
  return false
end

local agent = row(d, 5213, "accept", "post")
local earlyAgent = row(E.byId["04-59"], 5213, "accept")
local proof = row(d, 5262, "turnin", "post").s
local follow = row(d, 5263, "accept", "post").s
local egan = row(d, 5282, "turnin", "post").s
local head = row(d, 5262, "accept", "in")
local headOutside = row(d, 5262, "accept", "post")
assert(agent.key == earlyAgent.key and head.key == "a:5262" and headOutside.key == "a:5262~2")
assert(R.quests[5213].ps[1] == 5212 and R.quests[5282].ps[1] == 5281)
assert(R.quests[5262].ps[1] == 5251 and R.quests[5263].ps[1] == 5262)
assert(not R.quests[5281] and R.offroute[5281], "Egan's route stays opt-in")

active[5212], ready[5212], bag[13174] = true, true, 20
assert(not E.Applies(agent.s.when) and not E.Applies(earlyAgent.s.when))
turned[5212], active[5212] = true, nil
assert(E.Applies(agent.s.when) and E.Applies(earlyAgent.s.when) and nextStep()==agent.s)
offered, speaking = 5213, agent.s.npc
for _, st in ipairs({"04-59", d.id}) do
  ns.db.station = st
  ns.db.notNow[agent.key] = true
  handler(nil, "QUEST_DETAIL")
  assert(not ns.db.notNow[agent.key] and accepts == 0, "both stops clear stale offers without auto-accepting")
end
local main = E.byId["04-59"]
ns.db.station = main.id
E.RunDungeon(d)
assert(ns.db.dungeonFrom == main.id and E.PreRoom(main))
assert(nextStep()==agent.s and visible(d, agent.s))
for _, count in ipairs({38, 39, 40}) do
  used = count
  assert(not E.PreRoom(main))
  assert(nextStep()~=agent.s and not visible(d, agent.s))
  assert(not visible(main, earlyAgent.s), "the main route still defers an unaccepted follow-up")
  ns.db.station = main.id
  assert(nextStep()~=agent.s, "viewing the dungeon tab keeps the current main route's reserve")
  ns.db.station = d.id
end
active[5213], ready[5213], bag[13176] = true, true, 1
local agentReturn = row(d, 5213, "turnin", "post").s
assert(nextStep() == agentReturn and visible(d, agentReturn))
active[5213], ready[5213], bag[13176] = nil, nil, nil
ns.db.dungeonFrom = nil
used, pending = 37, 0
assert(nextStep()==agent.s and visible(d, agent.s), "an older save without a main station retains the standard three-slot floor")
pending = 1
assert(nextStep()~=agent.s and not visible(d, agent.s))
used, pending, ns.db.skip[agent.key] = 25, 0, true
assert(not E.Applies(agent.s.when))
ns.db.skip[agent.key], ns.db.mark[agent.key] = nil, true
assert(not E.Applies(agent.s.when))
ns.db.mark[agent.key] = nil
settings.optional = false
assert(not E.Applies(agent.s.when))
settings.optional, ns.db.dNo[d.id] = true, true
assert(not E.Applies(earlyAgent.s.when) and not nextStep())
ns.db.dNo[d.id], map = nil, 1453
assert(not E.Applies(agent.s.when))
map, x, y = 1423, 71.63, 50.09
turned[5213] = true

inside, instance = true, 329
subzone = ns.Wings["05-d26"].enUS[1]
assert(not hud(5262))
bag[13251] = 1
assert(not hud(5262))
bag[13250] = 1
assert(not hud(5262), "the head does not satisfy the archivist prerequisite")
turned[5251] = true
assert(hud(5262)==head.s and nextStep()~=headOutside.s)
inside, instance = false, 0
assert(nextStep()==headOutside.s and visible(d, headOutside.s))
assert(headOutside.s.when.reserveDungeonPrep and not headOutside.s.when.manualPickup and not head.s.when.reserveDungeonPrep)
ns.db.dungeonFrom = main.id
for _, count in ipairs({38, 39, 40}) do
  used = count
  assert(nextStep()~=headOutside.s and not visible(d, headOutside.s))
end
ns.db.dungeonFrom = nil
used, pending = 37, 1
assert(nextStep()~=headOutside.s and not visible(d, headOutside.s))
pending = 0
assert(nextStep()==headOutside.s and visible(d, headOutside.s))
used = 25
ns.db.skip[head.key] = true
assert(nextStep()~=headOutside.s)
ns.db.skip[head.key], inside, instance = nil, true, 329
used = 40
assert(not hud(5262))
used, settings.optional = 39, false
assert(not hud(5262))
settings.optional, ns.db.dNo[d.id] = true, true
assert(not hud(5262) and not nextStep())
ns.db.dNo[d.id] = nil
instance = 109
assert(not hud(5262))
instance = 329
active[5262], ready[5262], bag[13250] = true, true, nil
assert(not hud(5262) and not E.Applies(proof.when) and not E.Applies(follow.when))
inside, instance = false, 0
bag[13250], settings.optional, used = 1, false, 40
assert(nextStep() == proof and visible(d, proof), "the old head can be delivered with a full log and optional quests off")
inside, instance = true, 329
assert(nextStep() ~= proof, "the Duke is outside")
inside, instance, settings.optional = false, 0, true
active[5262], turned[5262], used = nil, true, 25
assert(nextStep() == follow)
ns.db.dungeonFrom = main.id
for _, count in ipairs({38, 39, 40}) do
  used = count
  assert(nextStep() ~= follow and not visible(d, follow))
end
used = 25
x,y = 69.93,53.72
assert(not E.Applies(follow.when), "an unaccepted wing follow-up cannot send the player across town")
x,y = 71.63,50.09
active[5263], ready[5263], bag[13251] = true, true, nil
local baronReturn = row(d,5263,"turnin","post").s
assert(not E.Applies(baronReturn.when))
bag[13251] = 1
used = 40
assert(nextStep()==baronReturn and visible(d, baronReturn), "full logs still allow a ready hand-in")
used = 25
ready[5263] = false
turned[5213], active[5213], active[5282] = nil, true, true

inside, instance, settings.optional = true, 329, false
assert(not hud(5213) and not hud(5263) and hud(5282))
subzone = ns.Wings["05-d27"].enUS[1]
assert(hud(5213) and hud(5263) and hud(5282))
subzone, minimap = "", ""
assert(hud(5213) and not hud(5213).map and hud(5282))
for _, id in ipairs({5213,5263}) do assert(not nextStep() or nextStep().q ~= id) end
subzone, minimap = ns.Wings["05-d26"].enUS[1], ns.Wings["05-d27"].enUS[1]
for _, id in ipairs({5213,5263}) do assert(not nextStep() or nextStep().q ~= id) end
subzone, minimap, souls = ns.Wings["05-d27"].enUS[1], "", 14
bag[13289] = 1
assert(hud(5282) and not E.Applies(egan.when))
inside, instance = false, 0
map,x,y = 1423,11.36,26.60
assert(not E.Applies(egan.when))
souls, bag[13289] = 15, nil
assert(nextStep()==egan and not hud(5282))
x,y = 5.16,35.57
assert(not E.Applies(egan.when) and nextStep()~=egan)
print("Alliance Stratholme follow-ups: real prerequisites, items, capacity, side contact and wing filtering passed")
