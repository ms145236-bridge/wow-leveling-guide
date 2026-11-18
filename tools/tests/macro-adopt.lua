-- From the repository root: lua5.1 tools/tests/macro-adopt.lua
-- 插件巨集的認領：舊版留下的「任務目標／任務物品」（插件內容）要接手改寫，不另建 SLV 巨集；
-- 有紀錄但內容被同步改過時照名稱認；玩家自己寫的同名巨集不動；已經多建的 SLV 巨集也接手，不再多建。
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
local MG = { msg = function(s) msgs[#msgs + 1] = s end }
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

-- 1. 舊版留下、沒有紀錄的插件巨集：接手改寫，不另建
reset({ { name = "任務目標", body = "/cleartarget\n/run MGTP()" }, { name = "任務物品", body = "/use item:2589" } })
local i, n = MG.Macro.Write("target", "任務目標", "ICON", "/tar 狼\n/run MGTP()", true)
check(i == 1 and n == "任務目標" and macros[1].body == "/tar 狼\n/run MGTP()", "舊目標巨集被接手改寫")
i, n = MG.Macro.Write("item", "任務物品", "ICON", "/use item:5056", true)
check(i == 2 and n == "任務物品" and macros[2].body == "/use item:5056", "舊物品巨集被接手改寫")
check(#macros == 2 and #msgs == 0, "沒有另建 SLV 巨集、沒有提示")

-- 2. 有紀錄但內容被伺服器同步改回舊內容：照名稱認，不另建
reset({ { name = "任務目標", body = "/run MGTP()" } })
MetroGuideDB.macros = { target = { name = "任務目標", body = "/tar 舊\n/run MGTP()", want = "x" } }
i = MG.Macro.Write("target", "任務目標", "ICON", "/tar 新\n/run MGTP()", true)
check(i == 1 and #macros == 1 and macros[1].body == "/tar 新\n/run MGTP()", "紀錄內容不同仍照名稱認領")

-- 3. 玩家自己寫的同名巨集：不動，另建 SLV 巨集並提示一次
reset({ { name = "任務目標", body = "/cast 治療術" } })
i, n = MG.Macro.Write("target", "任務目標", "ICON", "/run MGTP()", true)
check(macros[1].body == "/cast 治療術", "玩家同名巨集內容沒被改")
check(n == "SLV 任務目標" and #macros == 2 and #msgs == 1, "另建 SLV 任務目標並提示")

-- 4. 之前已經多建了 SLV 巨集、紀錄遺失：接手預設名那個，不再建第三個
reset({ { name = "任務目標", body = "/run MGTP()" }, { name = "SLV 任務目標", body = "/run MGTP()" } })
i, n = MG.Macro.Write("target", "任務目標", "ICON", "/tar 狼\n/run MGTP()", true)
check(n == "任務目標" and #macros == 2 and #msgs == 0, "接手預設名，不再多建")

-- 5. 第二次呼叫（同一次登入）不再提示、不再建
i, n = MG.Macro.Write("target", "任務目標", "ICON", "/tar 熊\n/run MGTP()", true)
check(n == "任務目標" and #macros == 2 and #msgs == 0, "重複呼叫穩定")

if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("macro-adopt: all passed")
