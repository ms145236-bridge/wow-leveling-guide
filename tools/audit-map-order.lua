-- Run from the repository root with Lua 5.1. Output is TSV; map distances use
-- map percentages, not walk times. Review prerequisites and terrain before editing.
local faction = assert(arg[1], "usage: lua tools/audit-map-order.lua Alliance|Horde")
assert(faction == "Alliance" or faction == "Horde", "unknown faction")
function UnitFactionGroup() return faction end
local ns = {}
local file = faction == "Alliance" and "RouteA" or "Route"
assert(loadfile("addon/ShengLeveling/Data/" .. file .. ".lua"))("ShengLeveling", ns)

print("station\tname\tmap\tnpc\tfirst_step\treturn_step\treturn_quest\tmax_xy_gap\tintervening_work")
for _, station in ipairs(ns.Route.stations) do
  local visits, segmentMap = {}, nil
  for i, s in ipairs(station.steps) do
    -- Movement instructions, missing positions and map changes break a segment.
    if (s.t ~= "accept" and s.t ~= "do" and s.t ~= "turnin") or not (s.map and s.x and s.y) then
      visits, segmentMap = {}, nil
    else
      if segmentMap ~= s.map then visits, segmentMap = {}, s.map end
      if s.npc and (s.t == "accept" or s.t == "turnin") then
        local location = string.format("%s@%.4f,%.4f", s.npc, s.x, s.y)
        local previous = visits[location]
        if previous and previous < i - 1 then
          local greatest, work = 0, false
          for k = previous + 1, i - 1 do
            local other = station.steps[k]
            local dx, dy = other.x - s.x, other.y - s.y
            greatest = math.max(greatest, dx * dx + dy * dy)
            if other.t == "do" then work = true end
          end
          if greatest > 0 then
            print(table.concat({station.id, station.name, s.map, s.npc, previous, i,
              s.q, string.format("%.2f", math.sqrt(greatest)), work and "yes" or "no"}, "\t"))
          end
        end
        visits[location] = i
      end
    end
  end
end
