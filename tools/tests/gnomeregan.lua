-- From the repository root: lua5.1 tools/tests/gnomeregan.lua
local level, ring, copper = 31, 0, 299
local active, ready, turned = {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Dwarf", "Dwarf", 3 end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return level end
function GetMoney() return copper end
function GetItemCount(id) return id == 9326 and ring or 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local ns = {
  C={
    IsOnQuest=function(q) return active[q] end,
    IsReady=function(q) return ready[q] end,
    Objectives=function() return {} end,
    IsTurnedIn=function(q) return turned[q] end,
  },
  L=setmetatable({}, {__index=function(_, key) return key end}),
  UI={Get=function() return false end},
  db={skip={}, mark={}, latch={}, dNo={}},
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", ns)
end
local E = ns.E
E.Build()
local gnomeregan = assert(E.DungeonByInstance(90))

local function shown(quest)
  for _, step in ipairs((E.InstanceState(gnomeregan) or {}).steps or {}) do
    if step.s.q == quest then return step.s end
  end
end

-- A visible optional escort begins in the dungeon without a made-up outdoor pin.
level = 23
assert(not shown(2904))
level = 24
local escort = assert(shown(2904))
assert(escort.t == "accept" and escort.opt and escort.ph == "in" and not escort.map)
active[2904] = true
assert(shown(2904).t == "do")
local handoff
for _, step in ipairs(E.byId["03-26"].list) do
  if step.s.t == "turnin" and step.s.q == 2904 then handoff = step.s end
end
assert(handoff and handoff.map == 1434 and not E.Applies(handoff.when))
ready[2904] = true
assert(not shown(2904) and E.Applies(handoff.when))
active[2904] = nil
assert(not E.Applies(handoff.when))

-- The ring is a separate optional pickup, with no profession requirement.
level = 27
ring = 1
assert(not shown(2945))
level = 28
ring = 0
assert(not shown(2945) and not shown(2947))
ring = 1
assert(shown(2945).t == "accept" and not shown(2947))
active[2945], ring = true, 0
assert(shown(2945).t == "do")
ready[2945] = true
assert(shown(2945).t == "do" and shown(2945).spot)
copper = 300
assert(shown(2945).t == "turnin" and not shown(2947))
active[2945], turned[2945] = nil, true
assert(shown(2947).t == "accept" and not shown(2945))
active[2947], ready[2947] = true, true
assert(not shown(2947))
local ringReturn
for _, step in ipairs(gnomeregan.list) do
  if step.s.t == "turnin" and step.s.q == 2947 then ringReturn = step.s end
end
assert(ringReturn and ringReturn.ph == "post" and ringReturn.opt and ringReturn.map == 1455 and E.Applies(ringReturn.when))
print("Gnomeregan escort, item-start ring, machine follow-up and on-route hand-ins passed")
