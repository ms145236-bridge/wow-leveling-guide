-- From the repository root: lua5.1 tools/tests/auberdine-choice.lua
-- Night elf at Auberdine (station 01-6, map 1439): the coast/east choice can be reopened from the menu,
-- also after a reload with "east" saved, and Esc on the reopened dialog keeps the saved choice.
local stub
local function makeStub()
  local t = {}
  return setmetatable(t, {
    __index = function() return stub end,
    __call = function() return stub end,
    __add = function() return 0 end, __sub = function() return 0 end, __mul = function() return 0 end,
    __div = function() return 0 end, __unm = function() return 0 end, __concat = function() return "" end,
    __lt = function() return false end, __le = function() return false end,
  })
end
stub = makeStub()
-- Frames: every method call works and returns the stub; scripts and fields set on a frame are kept.
local frames = {}
local frameMeta = {}
frameMeta.__index = function(f, k)
  if k == "Show" then return function(self) rawset(self, "_shown", true) end end
  if k == "Hide" then return function(self) rawset(self, "_shown", false) end end
  if k == "IsShown" then return function(self) return rawget(self, "_shown") == true end end
  if k == "SetScript" then return function(self, ev, fn) rawset(self, "_on" .. ev, fn) end end
  if k == "GetStringHeight" or k == "GetStringWidth" or k == "GetWidth" or k == "GetHeight" then return function() return 10 end end
  return function() return CreateFrame() end
end
function CreateFrame(_, name)
  local f = setmetatable({}, frameMeta)
  if name then frames[name] = f; _G[name] = f end
  return f
end
UIParent, UISpecialFrames = CreateFrame(), {}
STANDARD_TEXT_FONT = "font"
function InCombatLockdown() return false end
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "NightElf", "NightElf", 4 end
function UnitClass() return "Hunter", "HUNTER" end
function UnitLevel() return 11 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function hooksecurefunc() end
GetLocale = function() return "zhTW" end
local onQuest = { [6343] = true }
local map, x, y = 1439, 36.77, 44.28
local town, coast = "Auberdine", "Darkshore"
local sub, zone, mini = town, coast, town
local flying = false
function UnitOnTaxi() return flying end
local ns = {}
ns.db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}, start="NightElf", station="01-6" }
MetroGuideDB = {}
ns.C = { IsOnQuest=function(q) return onQuest[q] end, IsReady=function() return false end, IsTurnedIn=function() return false end,
  Position=function() return map, x, y end, ZoneTexts=function() return sub, zone, mini end, Bind=function() end, LogQuestIDs=function() return {} end,
  Objectives=function() end, XPBuff=function() return false end, MapName=function(id) if id == 1439 then return coast end end,
  AreaName=function(id) if id == 442 then return town end end }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.Refresh = function() end
ns.msg = function() end
ns.Clean = function(s) return s end
ns.try = function(_, f, ...) return f(...) end
assert(loadfile("addon/ShengLeveling/Data/RouteA.lua"))("ShengLeveling", ns)
assert(loadfile("addon/ShengLeveling/Engine.lua"))("ShengLeveling", ns)
local ok, err = pcall(assert(loadfile("addon/ShengLeveling/UI.lua")), "ShengLeveling", ns)
assert(ok, "UI.lua should load against the stub API: " .. tostring(err))
local E, UI = ns.E, ns.UI
ns.UI.Get = function() return false end
E.Build()
local st = assert(E.byId["01-6"])
local state = { st = st, map = 1439, steps = { { s = { t = "accept", q = 6343 } } }, cur = 1 }
local popup = function() return frames.MetroGuideConfirmPopup end

-- Fresh session, nothing saved: no menu entry until the dialog has been offered.
assert(not UI.AuberdineCanRechoose(state))
local function expectNoPrompt(why)
  UI.AuberdineChoice(state)
  assert(not popup() or not popup():IsShown(), why)
  assert(not ns.db.auberdineChoice and ns.db.station == "01-6", why)
end
x, y, sub, mini = 41, 85, "Grove of the Ancients", "Grove of the Ancients"
expectNoPrompt("a carried 6343 in southern Darkshore is not an arrival")
sub, mini = town, town
expectNoPrompt("a stale town name disagrees with the southern position")
x, y, sub, mini = nil, nil, town, town
expectNoPrompt("map and area without a position are still loading")
x, y, flying = 36.77, 44.28, true
expectNoPrompt("flying over the town cannot open the arrival choice")
flying, zone = false, "Teldrassil"
expectNoPrompt("old parent zone at the new harbor must settle")
zone, mini = coast, "The Veiled Sea"
expectNoPrompt("conflicting minimap at the landing")
mini = town
UI.AuberdineChoice(state)
assert(popup() and popup():IsShown())
x, y, sub, mini = 41, 85, "Grove of the Ancients", "Grove of the Ancients"
rawget(popup().ok, "_onOnClick")()
assert(ns.db.auberdineChoice == nil and ns.db.station == "01-6", "moving away before confirming cannot select the coast")
x, y, sub, zone, mini = 36.77, 44.28, nil, nil, nil
UI.AuberdineChoice(state)
assert(popup() and popup():IsShown(), "Laird's confirmed position works when native area text is unavailable")
-- Esc: hide without running either button.
popup():Hide()
assert(ns.db.auberdineChoice == nil)
assert(UI.AuberdineCanRechoose(state), "Esc leaves a menu entry to choose again")

-- Saved "east" from an earlier session (cold start): the entry is offered without a prompt this session.
assert(loadfile("addon/ShengLeveling/UI.lua"))("ShengLeveling", ns) -- reload resets session flags
UI = ns.UI; ns.UI.Get = function() return false end
ns.db.auberdineChoice = "east"
-- Native town names also cover the walk between the local handoff and the ship.
x, y, sub, zone, mini = 33.7, 42.1, town, coast, town
assert(UI.AuberdineCanRechoose(state), "saved east can be changed after a reload")
-- A stale menu or loading screen cannot change the saved east route.
map, x, y = 1438, nil, nil
assert(not UI.AuberdineCanRechoose(state))
UI.AuberdineRechoose(state)
assert(not popup():IsShown() and ns.db.auberdineChoice == "east")
map, x, y = 1439, 33.7, 42.1
-- Reopen and press Esc: the saved choice stays.
UI.AuberdineRechoose(state)
assert(popup():IsShown())
popup():Hide()
assert(ns.db.auberdineChoice == "east", "Esc on the reopened dialog keeps east")
-- Reopen and confirm coast: switch to Darkshore 02-10.
local selected
E.Select = function(st2) selected = st2; ns.db.station = st2.id end
UI.AuberdineRechoose(state)
assert(rawget(popup().ok, "_onOnClick"), "ok button has a click handler")
rawget(popup().ok, "_onOnClick")()
assert(ns.db.auberdineChoice == "coast" and selected and selected.id == "02-10", "confirming coast moves to 02-10")
assert(not UI.AuberdineCanRechoose(state), "no entry once coast is chosen")
-- Away from Auberdine: no entry.
ns.db.auberdineChoice = "east"; ns.db.station = "01-6"
assert(not UI.AuberdineCanRechoose({ st = st, map = 1438 }))
ns.db.auberdineChoice = nil
onQuest[6343] = nil
state.steps[1].s = { t = "boat", to = "暴風城" }
assert(loadfile("addon/ShengLeveling/UI.lua"))("ShengLeveling", ns)
UI = ns.UI
UI.AuberdineChoice(state)
assert(popup():IsShown(), "the Stormwind boarding step still offers both routes")
map, x, y = 1438, nil, nil
rawget(popup().no, "_onOnClick")()
assert(ns.db.auberdineChoice == nil and ns.db.station == "01-6", "clicking east after a map change cannot save the choice")
map, x, y = 1439, 33.7, 42.1
UI.AuberdineChoice(state)
rawget(popup().no, "_onOnClick")()
assert(ns.db.auberdineChoice == "east" and ns.db.station == "01-6", "choosing east keeps the Stormwind route")
print("Auberdine choice: menu reopen after Esc or saved east, Esc keeps the saved choice, coast moves to 02-10")
