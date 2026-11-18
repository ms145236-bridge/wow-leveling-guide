-- From the repository root: lua5.1 tools/tests/camping-auto.lua
-- 紮營入門指南（任選專業）的自動接交與「接不到」：任一組的任務不自動選、不自動接（不論 NPC 列表排第幾個、可跳過開不開），
-- 玩家自己接了以後交件照常自動；NPC 只給組裡其中一個（不是第一個）不算接不到，組裡一個都沒給才算。
local active, turned, optional, auto = {}, {}, true, true
local now, npcName, detailId = 100, "山姆‧薩沙帕里拉", nil
local avail, picked, accepted, completed = {}, {}, {}, 0
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 7 end
function UnitXPMax() return 4500 end
function UnitXP() return 0 end
function UnitName() return npcName end
function GetTime() return now end
function IsShiftKeyDown() return false end
function IsInGroup() return false end
function UnitQuestTrivialLevelRange() return 8 end
function GetQuestID() return detailId end
function AcceptQuest() accepted[#accepted + 1] = detailId end
function IsQuestCompletable() return true end
function CompleteQuest() completed = completed + 1 end
function GetNumAvailableQuests() return #avail end
function SelectAvailableQuest(i) picked[#picked + 1] = avail[i] end
function GetNumActiveQuests() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
SlashCmdList = {}
MetroGuideDB = { questieNoted=true }
C_GossipInfo = {
  GetActiveQuests = function() return {} end,
  GetAvailableQuests = function() local out = {} for _, q in ipairs(avail) do out[#out + 1] = { questID=q } end return out end,
  SelectAvailableQuest = function(q) picked[#picked + 1] = q end,
}
local scripts = {}
function CreateFrame()
  return { SetScript=function(_, k, fn) scripts[k] = fn end, RegisterEvent=function() end, RegisterUnitEvent=function() end }
end
local db = { skip={}, mark={}, latch={}, notNow={}, pin={}, carry={}, dNo={}, fpNodes={}, drop={}, optNote={}, skipNote={}, station="01-2" }
local noop = function() end
local ns = { C={}, db=db, L=setmetatable({}, { __index=function(_, k) return k end }), uiZh=true, gameZh=true }
ns.UI = { Get=function(key) if key == "optional" then return optional elseif key == "auto" then return auto end end, Visible=function() return false end }
ns.N = { Set=noop, Clear=noop, Forget=noop }
ns.T, ns.I, ns.P = { Update=noop }, { Update=noop }, { Update=noop }
ns.msg, ns.Clean = noop, function(s) return s end
ns.try = function(_, fn, ...) return fn(...) end
ns.C.IsOnQuest = function(q) return active[q] end
ns.C.IsReady = function() return false end
ns.C.IsTurnedIn = function(q) return turned[q] end
ns.C.XPBuff = function() return false end
ns.C.Position = function() return 1429, 44.9, 63.36 end
ns.C.ZoneTexts = function() end
ns.C.Bind = function() end
ns.C.LogQuestIDs = function() local out = {} for q in pairs(active) do out[#out + 1] = q end return out end
ns.C.Objectives = function() return { { done=false } } end
for _, f in ipairs({ "Data/RouteA.lua", "Engine.lua", "Core.lua" }) do
  assert(loadfile("addon/ShengLeveling/" .. f))("ShengLeveling", ns)
end
function GetAvailableTitle(i) local q = ns.Route.quests[avail[i]] return q.nG or q.n end -- 每個專業的標題不同（紮營入門指南：採礦）
local function fire(event, ...) scripts.OnEvent(nil, event, ...) end
fire("PLAYER_ENTERING_WORLD")
fire("QUEST_LOG_UPDATE")

local CAMP = { 97924, 97915, 97916, 97917, 97918, 97920, 97921, 97922, 97923, 97925 }
-- 前面的步驟都做完：目前步驟是紮營入門指南（任一組）的接
local function reset(opt, on)
  wipe(active); wipe(turned); wipe(db.notNow); wipe(db.skip); wipe(picked); wipe(accepted); completed = 0
  optional, detailId, avail = opt, nil, {}
  for _, q in ipairs({ 96627, 95998, 96604, 96626 }) do turned[q] = true end
  for _, q in ipairs(on or {}) do active[q] = true end
  now = now + 10 -- 每一輪都過了 3 秒的保護期
  ns.Refresh(true) -- 重算一次（lastState、任一組的 s.q）
end

-- 必改 1：NPC 列出整組（剝皮排第一）→ 對話選單不選、直接跳任務內容也不接；可跳過開、關都一樣
for _, opt in ipairs({ true, false }) do
  reset(opt)
  avail = { unpack(CAMP) }
  fire("GOSSIP_SHOW")
  assert(#picked == 0, "對話選單不能自動選任一組（optional=" .. tostring(opt) .. "）：" .. tostring(picked[1]))
  fire("QUEST_GREETING")
  assert(#picked == 0, "任務招呼不能自動選任一組（optional=" .. tostring(opt) .. "）")
  for _, q in ipairs(CAMP) do
    now = now + 10
    detailId = q
    fire("QUEST_DETAIL")
  end
  assert(#accepted == 0, "直接打開任務內容也不能自動接（optional=" .. tostring(opt) .. "）：" .. tostring(accepted[1]))
end

-- 一般任務照常自動接：威廉·匹斯特的 60
reset(true)
npcName, detailId = "威廉·匹斯特", 60
fire("QUEST_DETAIL")
assert(accepted[1] == 60, "一般任務要照常自動接")
npcName = "山姆‧薩沙帕里拉"

-- 玩家自己接了採礦：交件照常自動
reset(true, { 97923 })
detailId = 97923
fire("QUEST_PROGRESS")
assert(completed == 1, "接了採礦以後，交件要照常自動")

-- 必改 2：釘在原本的接取步（a:97924），自動關、NPC 只給採礦 → 不寫接不到
auto = false
reset(true)
avail = { 97923 }
fire("GOSSIP_SHOW")
assert(not db.notNow["a:97924"], "對話選單只給採礦，不能寫接不到")
now = now + 10
detailId = 97923
fire("QUEST_DETAIL")
assert(not db.notNow["a:97924"], "直接打開採礦的任務內容，不能寫接不到")
now = now + 10
fire("QUEST_GREETING")
assert(not db.notNow["a:97924"], "任務招呼只給採礦，不能寫接不到")
-- 組裡一個都沒給才算接不到
reset(true)
avail = { 60 }
fire("GOSSIP_SHOW")
assert(db.notNow["a:97924"], "對話選單整組都沒給，要寫接不到")
reset(true)
detailId = 60
fire("QUEST_DETAIL")
assert(db.notNow["a:97924"], "直接打開的是別的任務，要寫接不到")
print("Camping 101 auto: never auto-picks a profession, turn-in still auto, offered when any member is offered")
