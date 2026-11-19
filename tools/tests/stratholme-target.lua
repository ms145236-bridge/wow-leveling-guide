-- Compare the actual instance target against the Forever NPC 11058 tooltip in the game locale.
local names = {
  enUS="Ezra Grimm", deDE="Ezra Grimm", frFR="Ezra Grimm", esES="Ezra Grimm", esMX="Ezra Grimm",
  zhTW="艾茲拉‧格里姆", zhCN="艾兹拉·格里姆", koKR="에즈라 그림", ptBR="Ezra Carranca", ruRU="Эзра Гримм",
}
local faction, active, ready
function UnitFactionGroup() return faction end
function UnitRace() if faction == "Alliance" then return "Human","Human",1 end return "Troll","Troll",8 end
function UnitClass() return "Priest","PRIEST" end
function UnitLevel() return 59 end
function wipe(t) for key in pairs(t) do t[key] = nil end end

for _, side in ipairs({"Alliance", "Horde"}) do
  faction = side
  local prefix = "addon/ShengLeveling/Data/Route" .. (side == "Alliance" and "A" or "")
  for game, expected in pairs(names) do
    local ui = game == "zhTW" and "enUS" or "zhTW"
    local ns = {
      gameLoc=game, gameZh=game=="zhTW", uiLoc=ui, uiZh=ui=="zhTW",
      Pad=function(text) return text end, L={}, Macro={default={target="SLV"}},
      C={IsOnQuest=function(q) return q==5214 and active end, IsTurnedIn=function() return false end,
        IsReady=function(q) return q==5214 and ready end, Objectives=function() return {{done=ready}} end,
        Position=function() end, ZoneTexts=function() end, AreaName=function() end, MapName=function() end},
      UI={Get=function() return true end}, db={skip={},mark={},latch={},dNo={},notNow={},pin={}},
    }
    assert(loadfile(prefix..".lua"))("",ns)
    for _, loc in ipairs({game, ui}) do
      if loc~="zhTW" then assert(loadfile(prefix.."_"..loc..".lua"))("",ns) end
    end
    for _, name in ipairs({"Engine","Target"}) do assert(loadfile("addon/ShengLeveling/"..name..".lua"))("",ns) end
    local E = ns.E
    E.Localize()
    E.Build()
    local dungeon, wings = E.DungeonByInstance(329)
    local function target()
      local state = E.InstanceState(dungeon,wings)
      for i,w in ipairs(state and state.steps or {}) do
        if w.s.q==5214 and w.s.t=="do" then
          local targets = ns.T.Targets({cur=i,steps=state.steps})
          assert(#targets==1)
          return targets[1]
        end
      end
    end
    active,ready=true,false
    assert(target()==expected,side.." "..game)
    ready=true
    assert(target()==nil)
    active,ready=false,false
    assert(target()==nil)
  end
end
print("Stratholme 5214 game-locale targets and journal controls passed for both factions")
