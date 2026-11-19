-- Reuse one running map and the same player position as the envelope moves in and out of bags.
local settings = { arrow=true, mapSteps=2, miniSteps=2, pinSize=18, miniPinSize=16, pinMergeX=1, pinAlpha=100 }
local ns = { E={}, C={Position=function() return 1417,44.3,92.9 end}, UI={Get=function(k) return settings[k] end} }
local widgets = {}
local function unused() end
setmetatable(widgets, {__index=function() return unused end})
function CreateFrame() return setmetatable({}, {__index=widgets}) end
widgets.CreateTexture, widgets.CreateFontString = CreateFrame, CreateFrame
UIParent = {GetEffectiveScale=function() return 1 end}
local redraws, world, mini = 0, {}, {}
local pins = {
  RemoveAllWorldMapIcons=function() redraws=redraws+1; world={} end,
  RemoveAllMinimapIcons=function() mini={} end,
  AddWorldMapIconMap=function(_, _, _, _, x, y) world[x..","..y]=true end,
  AddMinimapIconMap=function(_, _, _, _, x, y) mini[x..","..y]=true end,
}
function LibStub() return pins end
assert(loadfile("addon/ShengLeveling/Map.lua"))("ShengLeveling",ns)
local pickup = {s={t="accept",q=637,pickupItem=4433}}
local other = {s={t="turnin",q=633,map=1417,x=49,y=20}}
local st = {st={id="03-23"}, cur=1, done={}, na={}, num={1,2}}
for _, steps in ipairs({{pickup,other}, {other,pickup}}) do
  st.steps = steps
  for _, inBag in ipairs({false,true,false,true}) do
    if inBag then pickup.s.map,pickup.s.x,pickup.s.y=nil,nil,nil
    else pickup.s.map,pickup.s.x,pickup.s.y=1417,44.3,92.9 end
    ns.P.Update(st)
    assert((world["0.443,0.929"] or false)==not inBag)
    assert((mini["0.443,0.929"] or false)==not inBag)
    assert(world["0.49,0.2"] and mini["0.49,0.2"])
    local before = redraws
    ns.P.Update(st)
    assert(redraws==before, "stationary targets should reuse map pins")
  end
end
print("Portable item pins follow the bag state on both maps and stay cached when stationary")
