-- Exercise the eight Alliance cards and the live subzone selection of shared instances.
local subzone, active, turned, bags = "", {}, {}, {}
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human", "Human", 1 end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return 60 end
function GetLocale() return "enUS" end
function GetSubZoneText() return subzone end
function GetItemCount(id) return bags[id] or 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end

local ns = {
  C = {
    IsOnQuest=function(q) return active[q] end,
    IsReady=function() return false end,
    IsTurnedIn=function(q) return turned[q] end,
    Objectives=function() return {} end,
    Position=function() end,
  },
  db={skip={}, mark={}, latch={}, dNo={}, pin={}, carry={}, preset={}, notNow={}},
  L=setmetatable({}, {__index=function(_, key) return key end}),
  UI={Get=function(key) return key == "dPre" or key == "optional" end},
}
for _, path in ipairs({"Data/RouteA.lua", "Data/Wings.lua", "Engine.lua"}) do
  assert(loadfile("addon/ShengLeveling/" .. path))("ShengLeveling", ns)
end

local cards, E = {}, ns.E
E.Build()
for _, d in ipairs(E.dungeons) do cards[d.name] = d end
for name, anchor in pairs({
  ["厄運之槌 東區"]="04-50", ["厄運之槌 西區"]="04-50", ["厄運之槌 北區"]="04-50",
  ["黑石塔下層"]="04-54", ["黑石塔上層"]="04-54", ["通靈學院"]="04-55",
  ["塑造者殿堂"]="04-52", ["黑喉要塞"]="04-48",
}) do
  assert(cards[name] and cards[name].pickAt == anchor, name)
end
assert(cards["斯坦索姆"].id == "05-d13")

for _, wing in ipairs({"東區", "西區", "北區"}) do
  assert(cards["厄運之槌 " .. wing].after == "04-54", wing)
end

for card, expected in pairs({
  ["黑石塔下層"] = {[5081] = "給麥克斯韋爾的消息"},
  ["黑石塔上層"] = {[5127] = "羅拉克斯的故事", [6502] = "巨龍之眼"},
  ["黑喉要塞"] = {[92065] = "Blackmaw Counter-Offensive"},
}) do
  for _, row in ipairs(cards[card].list) do
    local s = row.s
    if s.t == "accept" and expected[s.q] then
      assert(s.preText == expected[s.q], card .. " prerequisite " .. s.q)
      expected[s.q] = nil
    end
  end
  assert(next(expected) == nil, "missing prerequisite text for " .. card)
end


local function selectWing(id, room, name)
  subzone = room
  local d, all = E.DungeonByInstance(id)
  assert(d == cards[name], room)
  return d, all
end

local function objective(d, all, id)
  local hud = E.InstanceState(d, all)
  for _, row in ipairs(hud and hud.steps or {}) do
    if row.s.q == id then return row.s end
  end
end

active[4701], active[4764] = true, true
local lower, spire = selectWing(229, "Hordemar City", "黑石塔下層")
assert(objective(lower, spire, 4701) and not objective(lower, spire, 4764))
assert(objective(lower, spire, 5001).t == "accept")
local upper = selectWing(229, "The Rookery", "黑石塔上層")
assert(objective(upper, spire, 4764) and not objective(upper, spire, 4701))
assert(not objective(upper, spire, 5001))
bags[12780] = 1
assert(objective(lower, spire, 5089) == nil, "the item offer must stay hidden outdoors")

active[7488], active[7461], active[7703] = true, true, true
local east, dire = selectWing(429, "Warpwood Quarter", "厄運之槌 東區")
assert(objective(east, dire, 7488) and not objective(east, dire, 7461))
local west = selectWing(429, "Capital Gardens", "厄運之槌 西區")
assert(objective(west, dire, 7461) and objective(west, dire, 7703))
assert(not objective(west, dire, 7488))
local north = selectWing(429, "Gordok Commons", "厄運之槌 北區")
bags[3829] = 1
assert(not objective(north, dire, 1193))
bags[15994] = 1
assert(objective(north, dire, 1193).t == "accept")
assert(not objective(north, dire, 7461))

-- Horde cards and Wings.lua still use the original shared room tables.
function UnitFactionGroup() return "Horde" end
local horde = {}
assert(loadfile("addon/ShengLeveling/Data/Route.lua"))("ShengLeveling", horde)
local namesById = {}
for _, st in ipairs(horde.Route.stations) do namesById[st.id] = st.name end
for id, name in pairs({
  ["05-d25"] = "黑石塔下層", ["05-d34"] = "黑石塔上層",
  ["05-d28"] = "厄運之槌 東區", ["05-d29"] = "厄運之槌 西區", ["05-d30"] = "厄運之槌 北區",
}) do
  assert(namesById[id] == name and ns.Wings[id].enUS[1], "wing table mismatch: " .. id)
end
print("Alliance endgame dungeon cards, faction anchors and shared wing objectives passed")
