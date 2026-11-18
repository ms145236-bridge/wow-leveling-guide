-- From the repository root: lua5.1 tools/tests/macro-adopt.lua
-- 插件巨集的認領：舊版留下、內容是插件完整格式的巨集要接手改寫，不再每次另建 SLV 巨集；
-- 玩家改過或自己寫的同名巨集一律不動；同名多格時不動；伺服器同步改回舊內容時要重寫。
local macros = {}
function GetMacroInfo(i) local m = macros[i]; if m then return m.name, m.icon, m.body end end
function GetNumMacros() return #macros, 0 end
function CreateMacro(name, icon, body) macros[#macros + 1] = { name = name, icon = icon, body = body }; return #macros end
function EditMacro(i, name, icon, body) macros[i] = { name = name, icon = icon, body = body }; return i end
function InCombatLockdown() return false end
function GetLocale() return "zhTW" end
-- Compat.lua 載入時會建事件框架；這裡只要能呼叫任何方法
local anyMeta = {}
anyMeta.__index = function() return function() return setmetatable({}, anyMeta) end end
function CreateFrame() return setmetatable({}, anyMeta) end
local msgs = {}
local MG = {}
MetroGuideDB = {}
local chunk = assert(loadfile("addon/ShengLeveling/Compat.lua"))
chunk("ShengLeveling", MG)
MG.L = setmetatable({}, { __index = function(_, k) return k end })
MG.msg = function(s) msgs[#msgs + 1] = s end

local fails = 0
local function check(cond, what)
  if not cond then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end
end
local function reset(list) macros = {}; for i, m in ipairs(list) do macros[i] = m end; MetroGuideDB = {}; msgs = {} end
local T1 = "/cleartarget\n/targetexact [noexists] 狼\n/cleartarget [dead]\n/run MGTP()"
local T2 = "/cleartarget\n/targetexact [noexists] 熊\n/cleartarget [dead]\n/tm [@target,exists,nodead,nogroup] 8\n/run MGTP()"
local T3 = "/cleartarget\n/tar [noexists] 黑鰭\n/cleartarget [dead]\n/run MGTP()"
local EMPTY = '/run ShengLv_Msg("目前步驟沒有要選的目標")'

-- 1. 舊版留下、沒有紀錄、插件完整格式的目標巨集：接手改寫，不另建
reset({ { name = "任務目標", body = T1 } })
local i, n = MG.Macro.Write("target", "任務目標", "ICON", T2, true)
check(i == 1 and n == "任務目標" and macros[1].body == T2 and #macros == 1 and #msgs == 0, "舊目標巨集被接手改寫")

-- 2. 沒有紀錄的單行 /use item:數字：無法證明是插件的，不接手，另建備用名
reset({ { name = "任務物品", body = "/use item:2589" } })
i, n = MG.Macro.Write("item", "任務物品", "ICON", "/use item:5056", true)
check(macros[1].body == "/use item:2589" and n == "SLV 任務物品", "無紀錄單行物品巨集不接手")
-- 之後同一筆紀錄穩定，不再多建
i, n = MG.Macro.Write("item", "任務物品", "ICON", "/use item:5057", true)
check(n == "SLV 任務物品" and #macros == 2 and macros[2].body == "/use item:5057", "備用名之後穩定改寫")

-- 3. 沒有紀錄、插件提示句格式的物品巨集：接手
reset({ { name = "任務物品", body = '/run ShengLv_Msg("目前步驟沒有任務物品")' } })
i, n = MG.Macro.Write("item", "任務物品", "ICON", "/use item:5056", true)
check(i == 1 and n == "任務物品" and #macros == 1, "插件提示句格式的物品巨集被接手")

-- 4. 有紀錄、伺服器同步改回舊內容：仍是插件格式就認，且要重寫（want 失效）
reset({ { name = "任務目標", body = T1 } })
MetroGuideDB.macros = { target = { name = "任務目標", body = T2, want = T3 } }
i = MG.Macro.Write("target", "任務目標", "ICON", T3, true)
check(i == 1 and #macros == 1 and macros[1].body == T3, "同步改回舊內容時重寫成目前內容")

-- 5. 有紀錄、玩家把巨集改成自己的內容：不動，另建備用名
reset({ { name = "任務目標", body = "/cast 治療術" } })
MetroGuideDB.macros = { target = { name = "任務目標", body = T1, want = T1 } }
i, n = MG.Macro.Write("target", "任務目標", "ICON", T2, true)
check(macros[1].body == "/cast 治療術" and n == "SLV 任務目標" and #msgs == 1, "玩家改成治療術的巨集不被覆寫")

-- 6. 含 MGTP() 但多了玩家自己命令的多行巨集：不算插件的
reset({ { name = "任務目標", body = "/cast 治療術\n/run MGTP()" } })
i, n = MG.Macro.Write("target", "任務目標", "ICON", T2, true)
check(macros[1].body == "/cast 治療術\n/run MGTP()" and n == "SLV 任務目標", "自訂多行巨集不被接手")

-- 7. 同名、同內容兩格：分不出來，什麼都不動
reset({ { name = "任務目標", body = T1 }, { name = "任務目標", body = T1 } })
i = MG.Macro.Write("target", "任務目標", "ICON", T2, true)
check(i == nil and #macros == 2 and macros[1].body == T1 and macros[2].body == T1, "同名兩格時不動")

-- 8. 之前多建了 SLV 巨集、紀錄遺失：接手預設名那一格，不再建
reset({ { name = "任務目標", body = EMPTY }, { name = "SLV 任務目標", body = T1 }, { name = "SLV 任務目標 2", body = T1 } })
i, n = MG.Macro.Write("target", "任務目標", "ICON", T2, true)
check(n == "任務目標" and #macros == 3 and #msgs == 0, "接手預設名，不再多建")
i, n = MG.Macro.Write("target", "任務目標", "ICON", T3, true)
check(n == "任務目標" and #macros == 3 and macros[1].body == T3, "重複呼叫穩定")

if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("macro-adopt: all passed")
