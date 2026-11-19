-- Exercise the actual HUD and dungeon tab against the two generated routes.
local faction, level, inside, money = "Alliance", 28, true, 0
local active, ready, turned, bags = {}, {}, {}, {}
local displayed, instanceID = nil, 90
function UnitFactionGroup() return faction end
function UnitRace()
  if faction == "Alliance" then return "Dwarf", "Dwarf", 3 end
  return "Troll", "Troll", 8
end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return level end
function GetMoney() return money end
function GetItemCount(id) return bags[id] or 0 end
function IsInInstance() return inside, inside and "party" or "none" end
function GetInstanceInfo() return "Gnomeregan", nil, nil, nil, nil, nil, nil, instanceID end
function GetQuestLogIndexByID(q) return active[q] and q or 0 end
function GetQuestLogTitle(q) return nil, nil, nil, nil, nil, ready[q] and 1 or 0 end
function IsQuestFlaggedCompleted(q) return turned[q] end
function GetNumQuestLeaderBoards() return 1 end
function GetQuestLogLeaderBoard(q) return "Clean the ring", "event", ready[q] or false end
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
function wipe(t) for k in pairs(t) do t[k] = nil end end
SlashCmdList = {}

local function upvalue(fn, name, replace)
  for i = 1, 40 do
    local key, value = debug.getupvalue(fn, i)
    if key == name then
      if replace ~= nil then debug.setupvalue(fn, i, replace) end
      return value
    end
  end
  error("missing " .. name)
end

local function loadRoute(data)
  local function nop() end
  local ns = {
    L=setmetatable({}, {__index=function(_, key) return key end}),
    db={skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, dDismiss={}, fpNodes={}},
    N={Clear=nop}, P={Clear=nop}, T={Update=nop}, I={Update=nop},
    try=function(_, f, ...) return f(...) end,
  }
  for _, file in ipairs({"Compat.lua", data, "Engine.lua", "UI.lua", "Core.lua"}) do
    assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
  end
  ns.E.Build()
  ns.UI.Get = function(k) return k == "dungeonOnly" end
  ns.UI.Render = function(p) displayed = p.state end
  ns.UI.SetHidden = function(hidden) if hidden then displayed = nil end end
  local render = upvalue(upvalue(ns.Refresh, "refresh"), "instanceView")
  local buildItems = upvalue(ns.UI.ScrollToDungeon, "buildItems")
  upvalue(buildItems, "tab", "dg")
  return ns, render, buildItems
end

local function row(list, q, action)
  for _, entry in ipairs(list or {}) do
    if entry.s.q == q and (not action or entry.s.t == action) then return entry end
  end
end

local function verify(data, returnQuest, city, x, y, npc, otherWork)
  local ns, render, buildItems = loadRoute(data)
  local d = assert(ns.E.DungeonByInstance(90))
  local function update()
    displayed = nil
    assert(render())
    return displayed and displayed.steps
  end
  local function nextFromTab(state)
    ns.UI.dOpen = d.id
    upvalue(buildItems, "state", state)
    buildItems()
    for _, item in ipairs(upvalue(buildItems, "items")) do
      if item.kind == "dnext" and item.d == d then return item.nx.step end
    end
  end

  local pickup, machine = row(d.list, 2945, "accept"), row(d.list, 2945, "turnin")
  local followup, handoff = row(d.list, returnQuest, "accept"), row(d.list, returnQuest, "turnin")
  assert(pickup.key == "a:2945" and machine.key == "t:2945")
  assert(not pickup.s.map and not pickup.s.x and pickup.s.when.bag.item == 9326)
  assert(followup.key == "a:" .. returnQuest and followup.s.ph == "in" and not followup.s.outsideObjective)
  assert(handoff.key == "t:" .. returnQuest and handoff.s.ph == "post" and handoff.s.outsideObjective)
  assert(handoff.s.map == city and handoff.s.x == x and handoff.s.y == y and handoff.s.npc == npc)

  for _, item in ipairs({0, 9362, 9326}) do
    bags = {[item]=1}
    assert((row(update(), 2945, "accept") ~= nil) == (item == 9326))
    assert(not row(displayed and displayed.steps, returnQuest))
  end
  level = 27
  assert(not row(update(), 2945))
  level, bags, active[2945] = 28, {}, true
  for _, amount in ipairs({299, 300}) do
    money = amount
    for _, complete in ipairs({false, true}) do
      ready[2945] = complete
      local current = assert(row(update(), 2945))
      assert(current.s.t == ((complete and amount >= 300) and "turnin" or "do"))
    end
  end
  -- At the cleaner, finish this machine before leaving to find Kernobee.
  -- Do not pre-skip unrelated tasks to make the ring chain appear first.
  level, money, ready[2945] = 35, 300, true
  assert(nextFromTab({instance=true, st=d}).s == machine.s)
  active[2945], ready[2945], turned[2945] = nil, nil, true
  assert(row(update(), returnQuest, "accept").key == followup.key)
  assert(nextFromTab({instance=true, st=d}).s == followup.s)
  for _, step in ipairs(d.list) do
    if step.s.q and step.s.q ~= returnQuest then ns.db.skip[step.key] = true end
  end
  level = 31
  local offer = assert(nextFromTab(displayed))
  assert(offer.key == followup.key and offer.s.ph == "in")

  active[returnQuest] = true
  for _, lv in ipairs({31, 59}) do
    level = lv
    for _, item in ipairs({0, 9326, 9362}) do
      bags = {[item]=1}
      for _, complete in ipairs({false, true}) do
        ready[returnQuest], inside = complete, true
        assert(not row(update(), returnQuest))
        local nextStep = nextFromTab(displayed or {instance=true, st=d})
        assert(not nextStep or nextStep.s.q ~= returnQuest)
        inside = false
        local outsideStep = nextFromTab({st=d})
        assert((outsideStep == handoff) == (complete and item == 9362))
      end
    end
  end
  inside, active[otherWork] = true, true
  for _, step in ipairs(d.list) do
    if step.s.q == otherWork then ns.db.skip[step.key] = nil end
  end
  assert(row(update(), otherWork))
  local current = assert(nextFromTab(displayed))
  assert(current.s.q == otherWork and current.s.ph == "in")

  -- The tab still knows the physical instance with the dedicated HUD disabled.
  active[otherWork] = nil
  ns.UI.Get = function() return false end
  assert(not render())
  local hiddenReturn = nextFromTab({st=d})
  assert(not hiddenReturn or hiddenReturn.s.q ~= returnQuest)

  ns.UI.dPhase[d.id] = "post"
  for _, focused in ipairs({false, true}) do
    ns.UI.Get = function(key) return focused and key == "dungeonOnly" end
    for _, location in ipairs({
      {inside=true}, {inside=true, id=0}, {inside=true, id=90},
      {inside=true, id=36, preview=true}, {inside=true, id=89123, preview=true},
      {inside=false, preview=true}, {inside=false, id=0, preview=true}
    }) do
      inside, instanceID = location.inside, location.id
      local nextStep = nextFromTab({st=d})
      local hasAction, hasPhase, hasReturn = false, false, false
      for _, item in ipairs(upvalue(buildItems, "items")) do
        if item.d == d then
          if item.kind == "dnext" then hasAction = true end
          if item.kind == "dphase" and item.phase == "post" then hasPhase = true end
          if item.kind == "dqi" and item.q == returnQuest then hasReturn = true end
        end
      end
      assert(hasPhase and hasReturn, "destination details remain available while loading")
      if location.preview then
        assert(nextStep == handoff, "an explicit preview still offers the city hand-in")
      elseif location.id == 90 then
        assert(not nextStep or nextStep ~= handoff, "the hand-in is outside Gnomeregan")
      else
        assert(not hasAction, "wait for the physical instance ID before guiding the player")
      end
    end
  end
  -- Keep outdoor errands out of synthetic journal work. Real machine work
  -- stays in the dungeon phase even without an authored step or coordinates.
  inside, instanceID, level = true, 90, 35
  active[returnQuest], ready[returnQuest] = true, true
  local preQuests = faction == "Alliance" and {2927,2923,2925,2931} or {2842,2843}
  for _,q in ipairs(preQuests) do
    active[q], ready[q], turned[q] = true, false, nil
    assert(not row(update(), q))
    local next = nextFromTab({instance=true, st=d})
    assert(not next or next.s.q ~= q)
    active[q], turned[q] = nil, true
  end
  active[2951] = true
  ns.UI.dPhase[d.id] = nil
  local next = assert(nextFromTab({instance=true, st=d}))
  assert(next.s.q == 2951 and not next.s.ph)
  for _,item in ipairs(upvalue(buildItems, "items")) do
    if item.kind == "dphase" and item.d == d then assert(item.phase == "in") end
  end
  -- Ready to hand in at the actual NPC, with dungeon work still left.
  inside, active[otherWork] = false,true
  for _,w in ipairs(d.list) do if w.s.q == otherWork then ns.db.skip[w.key] = nil end end
  local position = {}
  local originalPosition = ns.C.Position
  ns.C.Position = function() return unpack(position) end
  for _,pt in ipairs({{}, {city}, {1426,x,y}, {city,x+1,y}, {city,x+0.5,y}}) do
    position = pt
    local result = ns.E.DungeonNext(d, false)
    local atNPC = pt[1] == city and pt[2] == x + 0.5
    assert((result and result.step == handoff or false) == atNPC)
  end
  -- At the actual NPC, stale ready or the dirty ring cannot drive the Next action.
  -- The player may still open the post phase and inspect the city destination.
  ns.UI.dPhase[d.id] = "post"
  for _, count in ipairs({0, 1, 2}) do
    bags = {[9326]=1, [9362]=count}
    assert((nextFromTab({st=d}) == handoff) == (count > 0))
    local canPreview = false
    for _, item in ipairs(upvalue(buildItems, "items")) do
      if item.kind == "dqi" and item.d == d and item.q == returnQuest then canPreview = true end
    end
    assert(canPreview)
  end
  ns.db.skip[handoff.key] = true
  local result = ns.E.DungeonNext(d, false)
  assert(not result or result.step ~= handoff)
  ns.db.skip[handoff.key] = nil
  ns.C.Position = originalPosition
  active[otherWork] = nil
  active[2951] = nil
  -- Leaving the instance can update IsInInstance before the old HUD/map ID.
  level = 59
  inside, instanceID, active[returnQuest], ready[returnQuest] = false, 90, true, true
  assert(nextFromTab({instance=true, st=d}) == handoff)
  inside, instanceID = true, 90
end

local function verifySavedReturn(data, q, city, x, y, otherQuest, oldAuto)
  active, ready, turned, bags = {[q]=true, [otherQuest]=true}, {[q]=true}, {[2945]=true}, {[9362]=1}
  inside, instanceID, level = false, 90, 35
  local ns = loadRoute(data)
  local E = ns.E
  local d = E.DungeonByInstance(90)
  ns.UI.Get = function(key) return key == "optional" end
  ns.C.Position = function()
    if inside then return 226, 43, 50 end
    return city, x, y
  end
  E.RunDungeon(d)
  local key = "t:" .. q
  -- Saved by the 1.13.21 engine when this outdoor turn-in was available.
  local pin = {key=key, wasDone=false, auto=oldAuto}
  ns.db.pin[d.id] = pin
  local function check(canHandIn)
    local st = E.Locate(d)
    local current = st.cur and st.steps[st.cur]
    assert((current and current.key == key or false) == canHandIn)
    assert(ns.db.pin[d.id] == pin and not ns.db.mark[key] and not ns.db.latch[key])
  end
  check(true)
  inside = true; check(false)
  inside = false; check(true)
  bags[9362] = nil; check(false) -- previous frame still reports ready
  bags[9362], ready[q] = 1, false; check(false)
  active[q], ready[q] = nil, true; check(false) -- offer or journal update still pending
  active[q] = true; check(true)
  active[q], ready[q], turned[q] = nil, nil, true
  E.Locate(d)
  assert(not ns.db.pin[d.id])
end

verify("Data/RouteA.lua", 2947, 1455, 36.38, 3.61, "塔瓦斯德·基瑟爾", 2928)
verifySavedReturn("Data/RouteA.lua", 2947, 1455, 36.38, 3.61, 2928, "a:2931")
faction, level, inside, money = "Horde", 28, true, 0
active, ready, turned, bags = {}, {}, {}, {}
verify("Data/Route.lua", 2949, 1454, 75.99, 25.41, "諾格", 2841)
verifySavedReturn("Data/Route.lua", 2949, 1454, 75.99, 25.41, 2841, "a:2904")
print("Gnomeregan ring: portable pickup, cleaner fee and two outside returns passed")
