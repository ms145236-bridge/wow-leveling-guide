-- Run from the repository root. Each row represents one station and one quest
-- recognized by its instance-zone index. The summary counts unique quest IDs.
local faction = arg[1]
assert(faction == "Alliance" or faction == "Horde",
  "usage: lua5.1 tools/audit-dungeon-coverage.lua Alliance|Horde")
function UnitFactionGroup() return faction end

local ns = {}
local file = faction == "Alliance" and "RouteA" or "Route"
assert(loadfile("addon/ShengLeveling/Data/" .. file .. ".lua"))("ShengLeveling", ns)
local route = ns.Route
local pickups = {}
for _, station in ipairs(route.stations) do
  for i, step in ipairs(station.steps) do
    if step.t == "accept" and step.q then
      local list = pickups[step.q] or {}
      list[#list + 1] = string.format("%s/%s/%d", station.id, step.ph or "main", i)
      pickups[step.q] = list
    end
  end
end

print("faction\tstation\tdungeon\tquest_id\taccept_station_phase_step\tsteps_in_this_station")
local seen, empty = {}, {}
local stationCount, questCount, missingCount = 0, 0, 0
for _, station in ipairs(route.stations) do
  if station.dungeon then
    stationCount = stationCount + 1
    if not station.dq or #station.dq == 0 then
      empty[#empty + 1] = station.id .. " " .. station.name
    end
    local actions = {}
    for i, step in ipairs(station.steps) do
      if step.q then
        local list = actions[step.q] or {}
        list[#list + 1] = string.format("%s/%s/%d", step.ph or "-", step.t, i)
        actions[step.q] = list
      end
    end
    for _, q in ipairs(station.dq or {}) do
      if not seen[q] then
        seen[q] = true
        questCount = questCount + 1
        if not pickups[q] then missingCount = missingCount + 1 end
      end
      print(table.concat({faction, station.id, station.name, q,
        table.concat(pickups[q] or {}, ","), table.concat(actions[q] or {}, ",")}, "\t"))
    end
  end
end
io.stderr:write(string.format("%s: stations=%d recognized=%d without_accept=%d\n",
  faction, stationCount, questCount, missingCount))
if #empty > 0 then
  io.stderr:write("Stations without recognized zone IDs: ", table.concat(empty, ", "), "\n")
end
