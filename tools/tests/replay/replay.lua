-- Run from the project root. See check.py for the combinations and arguments.
local race,factor=arg[1],assert(tonumber(arg[2]))
local faction,class,branch=arg[6],arg[7],arg[8] or "default"
local alliance=faction=="Alliance"
local raceID=assert(({Human=1,Orc=2,Dwarf=3,NightElf=4,Scourge=5,Tauren=6,Gnome=7,Troll=8,Skyborne=alliance and 33 or 34})[race])
local initialBind=({Human="北郡修道院",Orc="試煉谷",Dwarf="安威瑪",NightElf="奧達希爾",Scourge="喪鐘鎮",Tauren="納拉其營地",Gnome="安威瑪",Troll="試煉谷",Skyborne="坦德爾林地"})[race]
local mode=arg[4] or "raw"
local allDungeons = mode=="allparty" or mode=="allparty-window"
assert(mode=="raw" or mode=="solo" or mode=="party" or mode=="early" or allDungeons)
local party=(mode=="party" or mode=="early" or allDungeons)
local instanceFraction=tonumber(arg[5] or 0)
assert(instanceFraction>=0 and instanceFraction<=1)
local selected = alliance and {3,4,5,7,8,9,10,11,13,14} or {1,3,5,6,8,11,14,17,18,21,23,24,33}
local chosen,ran,materials={},{},{}
for _,n in ipairs(selected) do chosen["05-d"..n]=true end
local classQuest={[95036]=true,[95042]=true,[95111]=true,[95125]=true,[95126]=true,[8257]=true,[93030]=true,[99187]=true}
local events = assert(io.open(arg[3], "w"))
-- Compare the same loot scenario on both releases. These two hand-ins consume world drops.
local drops = arg[9] == "both" and {[8244]=1,[10593]=1} or {}
local collect = {[2521]=8244,[3501]=10593}
function GetItemCount(id) return drops[id] or 0 end
local level, bar, open, bind = 1, 0, 0, initialBind
local have, turned, worked, maxXP = {}, {}, {}, {}
for line in io.lines("route-alliance/xp-table.md") do
  local lv,xp = line:match("^| (%d+) | (%d+) |")
  if lv then maxXP[tonumber(lv)]=tonumber(xp) end
end
function UnitFactionGroup() return faction end
function UnitRace() return race,race,raceID end
function UnitClass() return class,class end
function UnitLevel() return level end
function UnitXP() return bar end
function UnitXPMax() return maxXP[level] or 0 end
function wipe(t) for k in pairs(t) do t[k]=nil end end
local db={skip={},drop={},fpNodes={},notNow={},pin={},mark={},latch={},carry={},dNo={}}
local ns={db=db, L=setmetatable({}, {__index=function(_,k) return k end}), UI={Get=function() return false end}, C={}}
function ns.C.IsTurnedIn(q) return turned[q] end
function ns.C.IsOnQuest(q) return have[q] end
function ns.C.IsReady(q) return worked[q] end
function ns.C.Objectives() end
function ns.C.XPBuff() return false end
local data=alliance and "Data/RouteA.lua" or "Data/Route.lua"
for _,file in ipairs({data, "Engine.lua"}) do assert(loadfile("addon/ShengLeveling/"..file))("",ns) end
local E=ns.E
E.Build()
local instanceWork,selectedWork={},{}
for _,d in ipairs(E.dungeons) do
  if allDungeons then chosen[d.id]=true end
  for _,step in ipairs(d.list) do
    local s=step.s
    if s.q and s.ph=="in" and s.t=="do" and E.Applies(s.when,true) then
      instanceWork[s.q]=true
      if chosen[d.id] then selectedWork[s.q]=true end
    end
  end
end
local hordeTemple = {WARRIOR=8425, HUNTER=8232, SHAMAN=8413, MAGE=8253, WARLOCK=8422, ROGUE=8236, DRUID=9053, PRIEST=8257}
local templeQuest = (alliance and {MAGE=8253, PRIEST=8257, HUNTER=8232} or hordeTemple)[class]
local templeStation = alliance and "05-d14" or "05-d23"
if templeQuest then classQuest[templeQuest]=true end
local function unavailable(q,i)
  if i.races and math.floor(i.races/2^(raceID-1))%2==0 then return "race" end
  for _,p in ipairs(i.ex or {}) do if have[p] or turned[p] then return "exclusive",p end end
  for _,p in ipairs(i.fol or {}) do if have[p] or turned[p] then return "superseded",p end end
  for _,p in ipairs(i.pg or {}) do if not turned[p] then return "prereq",p end end
  if i.ps and #i.ps>0 then
    for _,p in ipairs(i.ps) do if turned[p] then return end end
    return "prereq",table.concat(i.ps,"/")
  end
end
local function run(st, isRun)
  local parent = st.main or st
  local function refresh() E.FillPlan(parent) end
  local entry,entryBar,peak=level,bar,open
  local granted={turnin=0,combat=0,grind=0,topup=0}
  local stats={low=0,full=0,prereq=0,hard=0,flight=0,hearth=0,hand=0}
  local function log(k,s,detail)
    local q=s.q
    local i=ns.Route.quests[q] or {}
    events:write(table.concat({st.id,level,bar,k,q or "",i.n or "",s.when and s.when.class and "class" or "",tostring(detail or ""),s.opt and "opt" or ""},"\t"),"\n")
  end
  local function grant(k,n,s)
    n=math.floor(n)
    while level<60 and n>0 do
      local part=math.min(maxXP[level]-bar,n)
      granted[k],bar,n=granted[k]+part,bar+part,n-part
      if bar==maxXP[level] then level,bar=level+1,0;log("level",s,k);refresh() end
    end
  end
  refresh()
  for _,step in ipairs(st.list) do
    local s=step.s
    local q,i=s.q,ns.Route.quests[s.q]
    if branch=="coast" and st.id=="01-6" and s.t=="boat" and s.to=="暴風城" then
      db.auberdineChoice="coast";log("coast-branch",s);break
    end
    if s.opt and s.t=="accept" then refresh() end
    if not E.Applies(s.when) then
      if s.when and s.when.class and E.Applies(s.when,true) and (s.t=="accept" or s.t=="travel") then log("class-low",s,s.when.lvMin) end
    elseif collect[q] and not drops[collect[q]] then log("no-drop",s)
    elseif s.q==95042 and not have[95036] then log("missing-parent",s,95036)
    elseif E.OptOut(s) and not (party and (isRun or classQuest[q] or (s.when and s.when.class and selectedWork[q]))) then
      if s.t=="accept" and s.when and s.when.class then log("optional-off",s) end
    elseif s.t=="fp" and s.node then db.fpNodes[s.node]=true;log("learn-fp",s,s.node)
    elseif s.t=="boat" then log("boat",s,(s.from or "?").." → "..(s.to or "?"))
    elseif s.t=="fly" and s.to and db.fpNodes[s.to] then log("known-flight",s,s.to)
    elseif s.t=="travel" or s.t=="goto" then log("route-waypoint",s,s.text or s.desc or "")
    elseif s.t=="fly" and s.to and not db.fpNodes[s.to] then stats.flight=stats.flight+1;log("unrecorded-flight",s,s.to.." "..(s.desc or ""))
    elseif s.t=="bind" then bind=s.bind or bind;log("bind",s,bind)
    elseif s.t=="hearth" and s.bind and bind~=s.bind then stats.hearth=stats.hearth+1;log("hearth-check",s,bind.." → "..s.bind)
    elseif s.t=="hearth" and bind==s.bind then log("hearth-match",s,bind)
    elseif s.t=="level" and (not s.opt or isRun) then
      while level<s.lv do grant("grind",maxXP[level]-bar,s) end
    elseif s.t=="accept" and not have[q] and not turned[q] then
      local why,detail=unavailable(q,i)
      if not why and i.cond then why="conditional" end
      if not why and level<math.max(i.min or 0,s.pickLv or 0) then why,detail="low",math.max(i.min or 0,s.pickLv or 0) end
      if not why and open>=40 then why="full" end
      if why then log(why,s,detail);if stats[why] then stats[why]=stats[why]+1 end
      else have[q]=true;open=open+1;peak=math.max(peak,open);log("accepted",s) end
    elseif s.t=="do" and have[q] and not worked[q] then
      -- These two quests explicitly require instance materials or a boss for these roles.
      if q==95036 and (st.id=="05-d5" or st.id=="05-d6") then
        materials[st.id]=true;log("material",s,st.name)
      elseif q==95036 and not (materials["05-d5"] and materials["05-d6"] and turned[95042]) then log("pending-material",s)
      elseif q==templeQuest and st.id~=templeStation then log("await-temple",s)
      elseif instanceWork[q] and not isRun and q~=95036 and q~=95042 then log("await-instance",s)
      elseif q==99187 and st.id~="05-d33" then log("await-instance",s)
      else
        if (i.hard or 0)>=level+3 or i.soloElite then stats.hard=stats.hard+1;log("difficulty",s,(i.hard or 0)..(i.soloElite and " elite" or "")) end
        local xp=(s.ph=="in" or st.temple) and 0 or E.KillXP(q,level)*factor
        worked[q]=true;log("worked",s,math.floor(xp));grant("combat",xp,s)
      end
    elseif s.t=="turnin" and have[q] and (not s.hold or worked[q]) and (not (q==95036 or q==templeQuest or q==99187 or instanceWork[q]) or worked[q]) then
      local xp=E.QuestXP(q,level)
      if collect[q] then drops[collect[q]]=nil end
      turned[q],have[q]=true,nil;open=open-1;stats.hand=stats.hand+1
      log("turned",s,math.floor(xp));grant("turnin",xp,s)
    elseif not q and s.when and s.when.class and (s.t=="travel" or s.t=="fly") then log("class-travel",s,s.text or s.desc or s.to) end
  end
  local bonus = 0
  if isRun and level<60 and instanceFraction>0 then
    bonus=math.floor(maxXP[level]*instanceFraction)
    grant("combat",bonus,{})
  end
  print(table.concat({race,factor,st.id,st.name,st.lv[1],st.lv[2],entry,entryBar,level,bar,granted.turnin,granted.combat,granted.grind,stats.hand,peak,open,stats.full,stats.low,stats.prereq,stats.hard,stats.flight,stats.hearth,mode,bonus or 0},"\t"))
end
-- Count only XP explicitly represented by the objectives. All instance trash XP is
-- deliberately left unpriced. Top-ups are the residual supplied at a station boundary.
local mayEnter = assert(loadfile("tools/tests/replay/dungeon-entry.lua"))()
local anchorsSeen={}
local st=E.stations[1]
while st do
  run(st,false)
  anchorsSeen[st.id]=true
  if party then
    for _,d in ipairs(E.dungeons) do
      local timely=anchorsSeen[d.after] or (mode=="early" and not alliance and d.id=="05-d33" and have[99187] and level>=55)
      if chosen[d.id] and timely and not ran[d.id] and mayEnter(E,d,level,mode,db.dNo[d.id]) then
        ran[d.id]=true;d.main=st;run(d,true)
      end
    end
  end
  if mode~="raw" then
    local nextSt=E.Next(st)
    local target=nextSt and nextSt.lv[1] or 60
    if level<target then
      local before,total=level,0
      while level<target do total=total+maxXP[level]-bar;level,bar=level+1,0 end
      events:write(table.concat({st.id,before,0,"boundary-xp","","","",total,""},"\t"),"\n")
      print(table.concat({race,factor,st.id.."-xp",st.name.."（補至下一站門檻）",target,target,before,"",level,bar,0,0,total,0,open,open,0,0,0,0,0,0,mode,0},"\t"))
    end
  end
  st=E.Next(st)
end
events:close()
