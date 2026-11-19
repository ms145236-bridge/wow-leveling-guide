-- The three identical-looking corpses and an exploration event must keep one saved quest step.
local active, ready, turned, bag, objectives = {}, {}, {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 59 end
function UnitXP() return 0 end
function UnitXPMax() return 209800 end
function GetItemCount(id) return bag[id] or 0 end
function wipe(t) for key in pairs(t) do t[key] = nil end end
local ns = {
  Macro={default={target="Target"}},
  C={IsOnQuest=function(q) return active[q] end, IsReady=function(q) return ready[q] end,
     IsTurnedIn=function(q) return turned[q] end, LogQuestIDs=function() return {6185} end,
     Position=function() return 1423,22.49,63.58 end, XPBuff=function() return false end,
     ZoneTexts=function() end, Bind=function() end, Objectives=function(q) return objectives[q] end},
  UI={Get=function(k) return k == "optional" end}, L=setmetatable({}, {__index=function(_,k) return k end}),
  db={skip={},mark={},latch={},notNow={},pin={},fpNodes={},carry={},dNo={}},
}
for _,file in ipairs({"Data/RouteA.lua","Engine.lua","Target.lua"}) do
  assert(loadfile("addon/ShengLeveling/"..file))("ShengLeveling",ns)
end
local E, q = ns.E, 6185
E.Build()
local field, camp = E.byId["04-56"], E.byId["04-59"]
local function isolate(st, key)
  wipe(ns.db.skip)
  local count = 0
  for _,row in ipairs(st.list) do
    if row.key == key then count = count + 1 else ns.db.skip[row.key] = true end
  end
  assert(count == 1)
  ns.db.station = st.id
end
local function current(st)
  local state = E.Locate(st)
  return state.cur and state.steps[state.cur], state
end
isolate(field, "d:6185")
active[q], turned[6184] = true, true
local coords = {[16001]={22.79,63.72}, [16002]={24.28,63.65}, [16003]={24.28,68.11}}
for mask = 0, 6 do
  local expected = {}
  for id = 16001, 16003 do
    bag[id] = math.floor(mask / 2^(id-16001)) % 2
    if bag[id] == 0 then expected[table.concat(coords[id], ",")] = true end
  end
  ready[q] = true -- stale; may not remove a missing corpse
  local row, state = current(field)
  assert(row.key == "d:6185" and row.s.map == 1423)
  local function consume(x,y)
    local k = x..","..y
    assert(expected[k]); expected[k] = nil
  end
  consume(row.s.x,row.s.y)
  for _,pt in ipairs(row.s.more or {}) do consume(pt[2],pt[3]) end
  assert(not next(expected))
  ns.T.Targets(state); assert(ns.T.objNote)
end
for id = 16001,16003 do bag[id] = 1 end
for loc, labels in pairs(ns.Route.quests[q].survey.labels) do
  ns.gameLoc = loc
  objectives[q] = {{text=labels.badges[2],done=true}, {text=labels.event,done=false,need=1,have=0},
                   {text=labels.badges[3],done=true}, {text=labels.badges[1],done=true}}
  local row, state = current(field)
  assert(row.key == "d:6185" and row.s.x == 22.49 and row.s.y == 63.58 and row.note.text)
  ns.T.Targets(state); assert(not ns.T.objNote)
  assert(not ns.db.latch[row.key]) -- even at the event coordinate
  isolate(camp, "t:6185"); assert(not current(camp))
  objectives[q][2].done, objectives[q][2].have = true, 1
  assert(current(camp).key == "t:6185")
  bag[16002] = 0; assert(not current(camp)); bag[16002] = 1
  objectives[q][1].done = false; assert(not current(camp)); objectives[q][1].done = true
  isolate(field, "d:6185"); assert(not current(field))
  ready[q] = false
  objectives[q] = {}
  row = current(field); assert(row.key == "d:6185" and not row.s.x)
  objectives[q] = {{text=labels.event,done=false}}
  assert(not current(field).s.x)
  ready[q] = true
end
ready[q] = false
ns.db.pin[field.id] = {key="d:6185",wasDone=false}
assert(current(field).key == "d:6185")
ns.db.mark["d:6185"] = true; assert(not current(field))
ns.db.mark["d:6185"], ns.db.skip["d:6185"] = nil,true; assert(not current(field))
print("Eastern Plagues: missing corpse coordinates, ten localized event labels, stationary transition, macro targets, saved step and hand-off passed")
