-- Check the shipped Deadmines route, including the optional preparation chain.
function UnitFactionGroup() return "Alliance" end
local ns = {}
assert(loadfile("addon/ShengLeveling/Data/RouteA.lua"))("ShengLeveling", ns)
local dungeon
for _, station in ipairs(ns.Route.stations) do
  if station.id == "05-d3" then dungeon = station end
end
assert(dungeon and dungeon.pickAt == "02-11")

local function step(phase, action, quest)
  for index, s in ipairs(dungeon.steps) do
    if s.ph == phase and s.t == action and s.q == quest then return index, s end
  end
  error(("Missing Deadmines %s %s %d"):format(phase, action, quest))
end

local function joinedBefore(previous, quest)
  local first = step("pre", "accept", quest)
  for _, id in ipairs(previous) do
    assert(step("pre", "turnin", id) < first, ("Quest %d must precede %d"):format(id, quest))
  end
end
joinedBefore({92742, 92744}, 92745)
joinedBefore({92745}, 92747)
joinedBefore({92747}, 92748)
joinedBefore({92748}, 92749)
joinedBefore({92748}, 92750)
joinedBefore({92750}, 92751)
joinedBefore({92749, 92751}, 92752)
joinedBefore({92752}, 92753)

local _, dynamite = step("pre", "turnin", 92749)
assert(dynamite.when.bag.item == 4358 and dynamite.when.bag.count == 10)
local forgeIndex, forge = step("in", "do", 92753)
assert(not forge.map and forgeIndex < step("in", "do", 166))
local _, pickup = step("pre", "accept", 92753)
local turnIndex, exit = step("post", "turnin", 92753)
assert(pickup.map == 1436 and pickup.x == 52.48 and pickup.y == 52.97)
assert(exit.map == 1436 and exit.x == 38.68 and exit.y == 83.7)
assert(turnIndex < step("post", "accept", 92819))
assert(step("post", "accept", 92819) < step("post", "do", 92819))
assert(step("post", "do", 92819) < step("post", "turnin", 92819))
assert(step("post", "turnin", 92819) < step("post", "turnin", 166))

local letterIndex, letter = step("in", "accept", 373)
assert(letterIndex > step("in", "do", 166))
assert(letter.when.bag.item == 2874 and letter.when.bag.count == 1 and not letter.map)
assert(step("post", "turnin", 373) < step("post", "accept", 389))
assert(step("post", "accept", 389) < step("post", "turnin", 389))
print("Deadmines prerequisites, forge, exit detonator, and Edwin's letter checked")
