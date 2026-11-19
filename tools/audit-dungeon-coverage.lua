-- Run from the repository root. The default report counts unique IDs from the
-- instance-zone index. The optional report uses authored in-instance actions
-- at unmapped stations only and has a separate denominator.
local faction = arg[1]
local mode = arg[2]
assert((faction == "Alliance" or faction == "Horde") and
  (not mode or mode == "--authored-unmapped") and not arg[3],
  "usage: lua5.1 tools/audit-dungeon-coverage.lua Alliance|Horde [--authored-unmapped]")
local authored = mode == "--authored-unmapped"
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

print("faction\tstation\tdungeon\tquest_id\taccept_station_phase_step\tsteps_in_this_station" ..
  (authored and "\tcoverage_source" or ""))
local seen, mappedEmpty, unmapped = {}, {}, {}
local stationCount, authoredCount, questCount, missingCount = 0, 0, 0, 0
for _, station in ipairs(route.stations) do
  if station.dungeon then
    stationCount = stationCount + 1
    if not station.dq then
      unmapped[#unmapped + 1] = station.id .. " " .. station.name
    elseif #station.dq == 0 then
      mappedEmpty[#mappedEmpty + 1] = station.id .. " " .. station.name
    end
    local actions, inside, insideSeen = {}, {}, {}
    for i, step in ipairs(station.steps) do
      if step.q then
        local list = actions[step.q] or {}
        list[#list + 1] = string.format("%s/%s/%d", step.ph or "-", step.t, i)
        actions[step.q] = list
        if authored and not station.dq and step.ph == "in" and not insideSeen[step.q] and
            (step.t == "accept" or step.t == "do" or step.t == "turnin") then
          insideSeen[step.q] = true
          inside[#inside + 1] = step.q
        end
      end
    end
    if #inside > 0 then authoredCount = authoredCount + 1 end
    for _, q in ipairs((authored and inside) or station.dq or {}) do
      if not seen[q] then
        seen[q] = true
        questCount = questCount + 1
        if not pickups[q] then missingCount = missingCount + 1 end
      end
      local row = {faction, station.id, station.name, q,
        table.concat(pickups[q] or {}, ","), table.concat(actions[q] or {}, ",")}
      if authored then row[#row + 1] = "authored_in_instance" end
      print(table.concat(row, "\t"))
    end
  end
end
if authored then
  io.stderr:write(string.format("%s: unmapped_stations=%d with_authored_actions=%d authored=%d without_accept=%d\n",
    faction, #unmapped, authoredCount, questCount, missingCount))
else
  io.stderr:write(string.format("%s: stations=%d recognized=%d without_accept=%d\n",
    faction, stationCount, questCount, missingCount))
  if #mappedEmpty > 0 then
    io.stderr:write("Mapped stations without faction quests: ", table.concat(mappedEmpty, ", "), "\n")
  end
  if #unmapped > 0 then
    io.stderr:write("Stations without a mapped quest zone: ", table.concat(unmapped, ", "), "\n")
  end
end
