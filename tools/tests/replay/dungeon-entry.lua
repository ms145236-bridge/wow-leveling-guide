-- The caller checks chosen dungeons, route anchors, and previous visits.
return function(E, dungeon, level, mode, disabled)
  if disabled or level < dungeon.lv[1] then return false end
  if mode ~= "allparty" then return level <= dungeon.lv[2] end

  local _, status, step = E.DungeonStatus(dungeon)
  if status == "revisit" then
    -- The player may return for an active objective inside. An outdoor delivery
    -- or a nearby pickup alone does not justify simulating a whole dungeon run.
    return step.s.ph == "in"
  end
  return status ~= "past" and status ~= "low"
end
