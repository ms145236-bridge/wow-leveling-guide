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
local ns = {}
ns.db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}, start="NightElf", station="01-6" }
MetroGuideDB = {}
ns.C = { IsOnQuest=function(q) return onQuest[q] end, IsReady=function() return false end, IsTurnedIn=function() return false end,
  Position=function() return 1439, 36, 45 end, ZoneTexts=function() end, Bind=function() end, LogQuestIDs=function() return {} end,
  Objectives=function() end, XPBuff=function() return false end, MapName=function() return "" end }
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
UI.AuberdineChoice(state)
assert(popup() and popup():IsShown(), "dialog opens on arrival")
-- Esc: hide without running either button.
popup():Hide()
assert(ns.db.auberdineChoice == nil)
assert(UI.AuberdineCanRechoose(state), "Esc leaves a menu entry to choose again")

-- Saved "east" from an earlier session (cold start): the entry is offered without a prompt this session.
assert(loadfile("addon/ShengLeveling/UI.lua"))("ShengLeveling", ns) -- reload resets session flags
UI = ns.UI; ns.UI.Get = function() return false end
ns.db.auberdineChoice = "east"
assert(UI.AuberdineCanRechoose(state), "saved east can be changed after a reload")
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
print("Auberdine choice: menu reopen after Esc or saved east, Esc keeps the saved choice, coast moves to 02-10")
