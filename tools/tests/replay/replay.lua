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
local chosen,ran,picked={},{},{}
for _,n in ipairs(selected) do chosen["05-d"..n]=true end
local classQuest={[95036]=true,[95042]=true,[95111]=true,[95125]=true,[95126]=true,[8257]=true,[93030]=true,[99187]=true}
local events = assert(io.open(arg[3], "w"))
-- Compare the same loot scenario on both releases. These two hand-ins consume world drops.
local drops = arg[9] == "both" and {[8244]=1,[10593]=1} or {}
-- "items:8623,8704" supplies held world drops so explicit held-item entries can be checked.
for id in (arg[9] or ""):match("^items:(.*)$") and arg[9]:sub(7):gmatch("%d+") or function() end do drops[tonumber(id)]=1 end
local collect = {[2521]=8244,[3501]=10593}
-- Without explicit scenario arguments (arg 10 a number, or arg 11+), the character completes the authored
-- gathering work: route-listed cloth, farmed and hand-in materials, the rift capture with the scroll and coffer
-- beside the trainer, and the blade materials from the selected dungeons. Class lines then stay covered by
-- the mandatory-step check in check.py. Scenario runs keep the explicit no-drop assumption.
local standard = tonumber(arg[10]) == nil and arg[11] == nil
-- Explicit successful Tooga escort scenario. The default route assumes no encounter.
local toogaComplete = arg[22] == "tooga-complete"
-- Provide cloth only in an explicitly supplied replay. The normal itinerary makes no drop assumption.
local suppliedLinen = tonumber(arg[10]) or 0
if suppliedLinen > 0 then drops[2589] = suppliedLinen end
-- Optional explicit successful interactions/drop scenarios. Simply visiting a dungeon supplies nothing.
local weaponLoot = {}
for id in (arg[11] or ""):gmatch("%d+") do weaponLoot[tonumber(id)] = true end
if standard then for _, id in ipairs({267454,6994,267361,6995}) do weaponLoot[id] = true end end
if party and weaponLoot[268484] then classQuest[95140] = true end
local bladeItems = {267454,6994,267361,272448}
local function hasBladeItems()
  for _, id in ipairs(bladeItems) do if not drops[id] then return false end end
  return true
end
-- Optional observed capture result, encoded as scroll count/chest count/filled coffers looted.
local riftScroll, riftChest, riftFilled = (arg[13] or ""):match("^(%d+)/(%d+)/(%d+)$")
if riftScroll then
  drops[7308], drops[7247], drops[7292] = tonumber(riftScroll), tonumber(riftChest), tonumber(riftFilled)
end
local chargedGems = tonumber(arg[14]) or 0
if chargedGems > 0 then drops[7249] = chargedGems end
-- Optional observed book and silk; the standard route assumes neither source was looted.
local book, silk = (arg[16] or ""):match("^(%d+)/(%d+)$")
book, silk = tonumber(book), tonumber(silk)
-- 94 and its follow-up issue their own glyph. Optional loss/unsynced scenarios are per issuance.
local glyphScenario = tonumber(arg[18]) or 3
local glyphReady = tonumber(arg[19]) or 3
-- Successful named kills normally include looting the quest trophy. Pass a list to model lost or omitted loot.
local trophy = {[34]=3631,[126]=3614,[180]=3632}
local pendants, champions = (arg[21] or "10/15"):match("^(%d+)/(%d+)$")
pendants, champions = math.min(10,assert(tonumber(pendants))),math.min(15,assert(tonumber(champions)))
local championKills = 0
local trophyDrops = {}
for id in (arg[20] or "3631,3614,3632"):gmatch("%d+") do trophyDrops[tonumber(id)] = true end
local function glyphFlag(q,mask)
  return math.floor(mask / (q == 94 and 1 or 2)) % 2 == 1
end
local visitMap, visitX, visitY
local manaGems = tonumber(arg[12]) or 0
if manaGems > 0 then drops[7293] = manaGems end
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
local ns={db=db, L=setmetatable({}, {__index=function(_,k) return k end}), UI={Get=function(key) return arg[10]=="optional" and (key=="optional" or key=="dPre") end}, C={}}
function ns.C.IsTurnedIn(q) return turned[q] end
function ns.C.IsOnQuest(q) return have[q] end
-- Quests with no objective step anywhere on the route are ready once accepted.
local hasDo = {}
function ns.C.Position() return visitMap, visitX, visitY end
function ns.C.IsReady(q)
  if q == 91 then return have[q] and GetItemCount(1075) >= 10 end
  if q == 128 then return have[q] and championKills >= 15 end
  if q == 94 or q == 248 then return have[q] and glyphFlag(q,glyphReady) end
  if q == 1938 or q == 1940 then return have[q] and (standard or arg[17] == "ready") end
  if q == 1921 then return have[q] and (standard or arg[15] == "ready") end
  return worked[q] or (have[q] and not hasDo[q]) or false
end
function ns.C.Objectives(q)
  if q==128 and have[q] then return {{have=championKills,need=15,done=championKills>=15}} end
end
function ns.C.LogQuestIDs()
  local ids = {}
  for q, on in pairs(have) do if on then ids[#ids+1] = q end end
  return ids
end
function ns.C.XPBuff() return false end
local data=alliance and "Data/RouteA.lua" or "Data/Route.lua"
for _,file in ipairs({data, "Engine.lua"}) do assert(loadfile("addon/ShengLeveling/"..file))("",ns) end
local E=ns.E
E.Build()
for _,group in ipairs({E.stations,E.dungeons}) do for _,st in ipairs(group) do for _,step in ipairs(st.list) do if step.s.t=="do" and step.s.q then hasDo[step.s.q]=true end end end end
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
-- Quest objects picked up when the recorded in-instance interaction is performed.
local instanceObjects = {[1050]=5536, [5848]=14679}
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
  -- This optional scenario starts with a real trainer visit and native acceptance during A18.
  if st.id == "02-18" and book and level >= 26 and class == "MAGE" and (race == "Human" or race == "Gnome") and open < 40 then
    have[1938] = true
    open = open + 1
    peak = math.max(peak, open)
    log("accepted", {q=1938}, "optional trainer visit")
  end
  local toogaX, toogaY
  refresh()
  for _,step in ipairs(st.list) do
    local s=step.s
    local q,i=s.q,ns.Route.quests[s.q]
    if branch=="coast" and st.id=="01-6" and s.t=="boat" and s.to=="暴風城" then
      db.auberdineChoice="coast";log("coast-branch",s);break
    end
    if s.opt and s.t=="accept" then refresh() end
    if toogaComplete and q == 1560 then
      toogaX, toogaY = s.x or toogaX, s.y or toogaY
      visitMap, visitX, visitY = 1446, toogaX, toogaY
    elseif st.id == "02-19" or st.id == "03-22" then
      -- Advance only at explicit itinerary legs; optional working rows do not change location.
      if s.t == "hearth" and s.bind == "暴風城" then visitMap, visitX, visitY = 1453, nil, nil
      elseif s.t == "fly" and s.to == "夜色鎮" then visitMap, visitX, visitY = 1431, nil, nil
      elseif not s.when and s.map then visitMap, visitX, visitY = s.map, s.x, s.y end
      -- A positive fixture explicitly follows the city hand-off at its authored recipient.
      if book and s.when and s.when.workMap == 1453 and visitMap == 1453 and s.x then
        visitX, visitY = s.x, s.y
      end
    elseif st.id == "02-11" then
      -- The Westfall leg walks Stormwind -> Goldshire -> bridge; rows with coordinates are visited where authored,
      -- so Elwynn-only catch-up rows (workMap 1429) apply on that walk and nowhere else.
      if s.map then visitMap, visitX, visitY = s.map, s.x, s.y end
    else visitMap, visitX, visitY = nil, nil, nil end
    if book and have[q] and s.t == "do" and s.map == visitMap then
      -- Supplied observations, never an automatic drop merely for arriving at the map.
      if q == 1938 and book > 0 then drops[7266] = book end
      if q == 1940 and silk > 0 then drops[7267] = silk end
    end
    -- A worked quest holds the items its hand-in asks for (Stratholme's 20 plagued flesh, 5 holy water).
    if standard and s.t=="turnin" and worked[q] and s.when and s.when.bag then
      local needs = {s.when.bag}
      for _, need in ipairs(s.when.additionalBags or {}) do needs[#needs+1] = need end
      for _, need in ipairs(needs) do
        if GetItemCount(need.item) < need.count then drops[need.item] = need.count; log("material",s,need.item) end
      end
    end
    local observedToogaPickup = q==1560 and s.t=="accept" and toogaComplete
    if not observedToogaPickup and not E.Applies(s.when) then
      if s.when and s.when.class and E.Applies(s.when,true) and (s.t=="accept" or s.t=="travel") then log("class-low",s,s.when.lvMin)
      elseif s.t=="accept" and q then log("not-applicable",s) end -- Lets check.py tell another branch's prereq from a missing one.
    elseif collect[q] and not drops[collect[q]] then log("no-drop",s)
    elseif s.q==95042 and not have[95036] then log("missing-parent",s,95036)
    elseif not observedToogaPickup and E.OptOut(s) and not (party and (isRun or classQuest[q] or (s.when and s.when.class and selectedWork[q]))) then
      if s.t=="accept" and q then log("optional-off",s) end
    elseif s.t=="fp" and s.node then db.fpNodes[s.node]=true;log("learn-fp",s,s.node)
    elseif s.t=="boat" then log("boat",s,(s.from or "?").." → "..(s.to or "?"))
    elseif s.t=="fly" and s.to and db.fpNodes[s.to] then log("known-flight",s,s.to)
    elseif s.t=="buy" and s.pick then
      -- Quest-object pickups: the item lands in the bag only while the linked quest is in the log.
      if s.fq and have[s.fq] and (drops[s.item] or 0)==0 then
        drops[s.item]=1;picked[s.fq]=picked[s.fq] or {};table.insert(picked[s.fq],s.item);log("picked",s,s.item)
      end
    elseif s.t=="travel" or s.t=="goto" then log("route-waypoint",s,s.text or s.desc or "")
    elseif s.t=="fly" and s.to and not db.fpNodes[s.to] then stats.flight=stats.flight+1;log("unrecorded-flight",s,s.to.." "..(s.desc or ""))
    elseif s.t=="bind" then bind=s.bind or bind;log("bind",s,bind)
    elseif s.t=="hearth" and s.bind and bind~=s.bind then stats.hearth=stats.hearth+1;log("hearth-check",s,bind.." → "..s.bind)
    elseif s.t=="hearth" and bind==s.bind then log("hearth-match",s,bind)
    elseif s.t=="level" and (not s.opt or isRun) then
      while level<s.lv do grant("grind",maxXP[level]-bar,s) end
    elseif s.t=="accept" and not have[q] and not turned[q] then
      local why,detail=unavailable(q,i)
      -- Explicit held-item conditions were already checked by E.Applies; other conditional entries stay unmodelled.
      if not why and i.cond and not (s.when and s.when.bag) and not observedToogaPickup then why="conditional" end
      if not why and level<math.max(i.min or 0,s.pickLv or 0) then why,detail="low",math.max(i.min or 0,s.pickLv or 0) end
      -- Authored mainline dungeon prep waits while the log lacks the 3-slot reserve (Engine deferAuthoredPrep).
      if not why and not isRun and s.when and s.when.dungeonPrep and not E.PreRoom(st) then why="prep-deferred" end
      if not why and open>=40 then why="full" end
      if why then log(why,s,detail);if stats[why] then stats[why]=stats[why]+1 end
      else
        have[q]=true;open=open+1;peak=math.max(peak,open);log("accepted",s)
        -- Hand-in-only deliveries (1921's cloth and rift gems) are gathered along the way.
        for _, need in ipairs(standard and i.deliveryItems or {}) do
          if GetItemCount(need.item) < need.count then drops[need.item] = need.count; log("material",s,need.item) end
        end
        if q==94 or q==248 then
          drops[1083] = glyphFlag(q,glyphScenario) and 1 or nil
        elseif i.providedVisit then
          -- The quest giver supplies this item when the quest is accepted.
          drops[i.providedVisit] = 1
        end
        if q==95036 and weaponLoot[267454] then drops[267454]=1;log("material",s,267454) end
        -- The authored pickup opens the fixed underwater container. Opening its envelope accepts
        -- 637 and the game issues the letter for delivery. A skipped or failed pickup issues nothing.
        if q==637 and s.pickupItem==4433 then drops[4432]=1; worked[q]=true end
      end
    elseif s.t=="do" and have[q] and not worked[q] then
      -- These two quests explicitly require instance materials or a boss for these roles.
      for _, need in pairs(standard and {i.supply or false, i.farmMaterial or false} or {}) do
        if need and GetItemCount(need.item) < need.count then drops[need.item] = need.count; log("material",s,need.item) end
      end
      if standard and i.riftTools then drops[7308], drops[7247], drops[7292] = 1, 1, 3; log("material",s,7292) end
      if q==2930 and GetItemCount(9316)<1 then log("missing-material",s,9316)
      elseif q==1938 and GetItemCount(7266)<1 then log("missing-material",s,7266)
      elseif i.riftTools and E.RiftPhase() ~= "journal" then log("missing-capture",s,E.RiftPhase())
      elseif i.supply and GetItemCount(i.supply.item) < i.supply.count then log("missing-material",s,i.supply.item)
      elseif i.farmMaterial and GetItemCount(i.farmMaterial.item) < i.farmMaterial.count then log("missing-material",s,i.farmMaterial.item)
      elseif q==95036 and (st.id=="05-d5" or st.id=="05-d6") then
        local item = st.id=="05-d5" and 6994 or 267361
        if isRun and weaponLoot[item] and (item~=6994 or drops[267454]) then
          drops[item]=1;log("material",s,item)
        else log("pending-material",s,item) end
      elseif q==95036 and not hasBladeItems() then log("pending-material",s)
      elseif q==95042 and not weaponLoot[6995] then log("pending-material",s,6995)
      elseif q==95140 and not drops[268484] then log("pending-material",s,268484)
      elseif q==templeQuest and st.id~=templeStation then log("await-temple",s)
      elseif instanceWork[q] and not isRun and q~=95036 and q~=95042 then log("await-instance",s)
      elseif q==99187 and st.id~="05-d33" then log("await-instance",s)
      else
        if (i.hard or 0)>=level+3 or i.soloElite then stats.hard=stats.hard+1;log("difficulty",s,(i.hard or 0)..(i.soloElite and " elite" or "")) end
        local xp=(s.ph=="in" or st.temple) and 0 or E.KillXP(q,level)*factor
        if i.farmMaterial then xp=0 end -- Already-held supplies do not grant simulated kill XP.
        if s.ph=="in" and instanceObjects[q] then drops[instanceObjects[q]]=1 end
        if q==95042 then drops[6995]=1;log("material",s,6995) end
        if q==91 then drops[1075]=pendants end
        if q==128 then xp=xp*champions/15;championKills=champions end
        if trophyDrops[trophy[q]] then drops[trophy[q]] = 1 end
        if i.requiredLoot and q ~= 91 and q ~= 2930 and not trophy[q] then drops[i.requiredLoot] = 1 end
        worked[q]=true;log("worked",s,math.floor(xp));grant("combat",xp,s)
      end
    elseif s.t=="turnin" and have[q] and (not s.hold or worked[q]) and (not (q==95036 or q==95042 or q==templeQuest or q==99187 or instanceWork[q]) or worked[q]) then
      local xp=E.QuestXP(q,level)
      if i.providedVisit then drops[i.providedVisit]=nil end
      if i.requiredLoot then drops[i.requiredLoot]=nil end
      if q==1938 then drops[7266]=nil end
      if q==95036 then for _, item in ipairs(bladeItems) do drops[item]=nil end end
      if q==95042 and drops[6995] then drops[6995]=nil; drops[272448]=1 end
      if i.deliveryItems then
        for _, need in ipairs(i.deliveryItems) do drops[need.item] = drops[need.item] - need.count end
      end
      if i.riftTools then
        drops[7292] = drops[7292] - 3; drops[7308] = drops[7308] - 1; drops[7247] = drops[7247] - 1
      end
      if i.farmMaterial then drops[i.farmMaterial.item]=drops[i.farmMaterial.item]-i.farmMaterial.count end
      if i.supply then drops[i.supply.item] = drops[i.supply.item] - i.supply.count end
      if q == 95126 then drops[268484] = 1 end
      if q == 95140 then drops[268484] = nil end
      if q==637 then drops[4432]=nil end
      if collect[q] then drops[collect[q]]=nil end
      for _,item in ipairs(picked[q] or {}) do drops[item]=nil end
      picked[q]=nil
      if instanceObjects[q] then drops[instanceObjects[q]]=nil end
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
