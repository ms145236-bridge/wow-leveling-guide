-- Check the shipped Deadmines route, including the optional preparation chain.
function UnitFactionGroup() return "Alliance" end
local ns = {}
assert(loadfile("addon/ShengLeveling/Data/RouteA.lua"))("ShengLeveling", ns)
local dungeon
for _, station in ipairs(ns.Route.stations) do
  if station.id == "05-d3" then dungeon = station end
end
-- 166、214 要 155 交了才接（赤脊山第一次回西部荒野）；暴風城的三件排在最後回城時接
assert(dungeon and dungeon.pickAt == "02-14")

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
local function acceptIndex(quest) return (step("pre", "accept", quest)) end
assert(acceptIndex(166) < acceptIndex(2040) and acceptIndex(214) < acceptIndex(2040), "Sentinel Hill pickups come before the Stormwind ones")
assert(acceptIndex(92753) < acceptIndex(2040) and acceptIndex(92753) < acceptIndex(167) and acceptIndex(92753) < acceptIndex(168))
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
-- 主線上看得到：西部荒野那站不再留暴風城的三件；赤脊山第一次交完護送 155 後接 166、214，回暴風城接 2040、167、168
local turned, active = {}, {}
function UnitClass() return "Priest", "PRIEST" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 21 end
function UnitXP() return 0 end
function UnitXPMax() return 10000 end
function GetTime() return 100 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local live = {
  C = {IsOnQuest=function(q) return active[q] end, IsReady=function() return false end,
       IsTurnedIn=function(q) return turned[q] end, LogQuestIDs=function() return {} end,
       Position=function() end, ZoneTexts=function() end, XPBuff=function() return false end, Objectives=function() end, Bind=function() end},
  db = {skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, dDismiss={}, fpNodes={}},
  UI = {Get=function(k) return k == "dPre" end},
  L = setmetatable({}, {__index=function(_, key) return key end}),
}
for _, file in ipairs({"Data/RouteA.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. file))("ShengLeveling", live)
end
local E = live.E
E.Build()
local function rows(id)
  live.db.station = id
  local found = {}
  for i, row in ipairs(E.Locate(E.byId[id]).steps) do
    if row.dungeon and row.dungeon.id == "05-d3" and row.s.t == "accept" then found[row.s.q] = i end
    if not row.dungeon and row.s.q == 155 and row.s.t == "turnin" then found.escort = i end
    if not row.dungeon and row.s.t == "hearth" then found.hearth = i end
  end
  return found
end
local westfall = rows("02-11")
assert(not westfall[2040] and not westfall[167] and not westfall[168], "Westfall no longer ends on Stormwind dungeon pickups")
local redridge = rows("02-14")
assert(redridge.escort and redridge[166] and redridge[214], "Sentinel Hill pickups appear on the main route")
assert(redridge[166] > redridge.escort and redridge[214] > redridge.escort, "166 and 214 follow the 155 hand-in")
for _, q in ipairs({2040, 167, 168}) do
  assert(redridge[q] and redridge[q] > redridge.hearth, "Stormwind pickup after the hearth: " .. q)
end
print("Deadmines pickups follow the escort hand-in and the last Stormwind return")
