-- 94 and 248 each issue a glyph. The native object interaction confirms the handoff.
local p, bag, log, turned, objectives = {}, {}, {}, {}, {}
local race, raw, riding = "Human", false, false
function UnitFactionGroup() return "Alliance" end
function UnitRace() return race,race,({Human=1,Gnome=7})[race] end
function UnitClass() return "Mage","MAGE" end
function UnitLevel() return 27 end
function UnitOnTaxi() return riding end
function GetItemCount(item) return bag[item] or 0 end
function wipe(t) for key in pairs(t) do t[key]=nil end end
local ns={db={}, C={Position=function() return unpack(p) end, IsOnQuest=function(q) return log[q] end,
  IsReady=function() return raw end, Objectives=function() return objectives end, IsTurnedIn=function(q) return turned[q] end}}
for _,file in ipairs({"Data/RouteA.lua","Engine.lua"}) do assert(loadfile("addon/ShengLeveling/"..file))("",ns) end
local E=ns.E
local function stationRows()
  E.Build()
  local rows={}
  for _,step in ipairs(E.byId["02-19"].list) do
    if step.s.q==94 or step.s.q==248 then assert(not rows[step.key]);rows[step.key]=step.s end
  end
  return rows
end
local rows=stationRows()
assert(E.Applies(rows["a:94"].when))
race="Gnome";rows=stationRows()
assert(not E.Applies(rows["a:94"].when))
p={1429,65.22,69.71};assert(E.Applies(rows["a:94"].when))
riding=true;assert(not E.Applies(rows["a:94"].when));riding=false
assert(rows["t:94"].x==79.4 and rows["d:248"].x==58.16 and rows["t:248"].y==49.84)
for _,q in ipairs({94,248}) do
  log[q]=true
  raw=false;objectives={}
  assert(not E.Ready(q) and not E.Applies(rows["t:"..q].when))
  raw=true
  for _,n in ipairs({0,1}) do
    bag[1083]=n;assert(E.Applies(rows["t:"..q].when))
  end
  if q==94 then
    assert(not E.Applies(rows["a:248"].when));turned[94]=true;assert(E.Applies(rows["a:248"].when))
  end
  log[q]=nil
end
print("Stonewatch local pickup, separate objects and native handoffs verified")
