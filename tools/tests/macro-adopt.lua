-- From the repository root: lua5.1 tools/tests/macro-adopt.lua
-- 插件巨集固定叫「SLV 任務物品」「SLV 任務目標」（業主 11/18 決定）：有這個名稱就改寫，沒有才建；不碰其他名稱的巨集。
local macros = {}
function GetMacroInfo(i) local m = macros[i]; if m then return m.name, m.icon, m.body end end
function GetNumMacros() return #macros, 0 end
function CreateMacro(name, icon, body) macros[#macros + 1] = { name = name, icon = icon, body = body }; return #macros end
function EditMacro(i, name, icon, body) macros[i] = { name = name, icon = icon, body = body }; return i end
function InCombatLockdown() return false end
function GetLocale() return "zhTW" end
local anyMeta = {}
anyMeta.__index = function() return function() return setmetatable({}, anyMeta) end end
function CreateFrame() return setmetatable({}, anyMeta) end
local MG = {}
MetroGuideDB = {}
assert(loadfile("addon/ShengLeveling/Compat.lua"))("ShengLeveling", MG)
local said = {}
MG.msg = function(s) said[#said + 1] = s end

local fails = 0
local function check(cond, what)
  if not cond then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end
end
local function reset(list) macros = {}; for i, m in ipairs(list) do macros[i] = m end end

-- 1. 沒有 SLV 巨集：新建，不碰舊的「任務物品」
reset({ { name = "任務物品", body = "/use item:2589" } })
local i, n = MG.Macro.Write("item", "任務物品", "ICON", "/use item:5056", true)
check(n == "SLV 任務物品" and #macros == 2 and macros[1].body == "/use item:2589", "新建 SLV 任務物品，舊巨集不動")
-- 2. 第二次：改寫同一格，不再多建
i, n = MG.Macro.Write("item", "任務物品", "ICON", "/use item:6000", true)
check(i == 2 and #macros == 2 and macros[2].body == "/use item:6000", "改寫同一格")
-- 3. 已有 SLV 任務目標（任何內容）：直接改寫
reset({ { name = "SLV 任務目標", body = "/cast 治療術" } })
i, n = MG.Macro.Write("target", "任務目標", "ICON", "/run MGTP()", true)
check(i == 1 and macros[1].body == "/run MGTP()" and #macros == 1, "同名直接改寫")
-- 4. create = false 且沒有：不建
reset({})
i = MG.Macro.Write("target", "任務目標", "ICON", "/run MGTP()", false)
check(i == nil and #macros == 0, "沒要求建立時不建")
-- 5. 內容一樣不重寫
reset({ { name = "SLV 任務目標", body = "/run MGTP()" } })
local edits = 0
local oldEdit = EditMacro
EditMacro = function(...) edits = edits + 1; return oldEdit(...) end
MG.Macro.Write("target", "任務目標", "ICON", "/run MGTP()", true)
check(edits == 0, "內容相同不呼叫 EditMacro")
-- 6. 帳號巨集滿了
reset({})
for k = 1, 120 do macros[k] = { name = "x" .. k, body = "" } end
i, n = MG.Macro.Write("item", "任務物品", "ICON", "/use item:1", true)
check(i == nil and n == "full", "滿了回 full")

-- 7. 舊版玩家（必改 1）：帳號裡有舊「任務目標」（已拖在快捷列）、舊旗標 macroNoted 已讀 → 新建時提醒一次拖回原快捷格
said = {}
MetroGuideDB = { macroNoted = true }
reset({ { name = "任務目標", body = "/run MGTP()" } })
i, n = MG.Macro.Write("target", "任務目標", "ICON", "/run MGTP()", true)
check(n == "SLV 任務目標" and #said == 1 and said[1]:find("SLV 任務目標", 1, true) and said[1]:find("拖回原快捷格", 1, true), "舊玩家（舊旗標已讀）也收到拖回提示")
check(MetroGuideDB.macroMoved.target == true and macros[1].name == "任務目標", "記下新旗標、舊巨集不動")
-- 8. 只提醒一次：刪掉新巨集再建，不再說
macros[2] = nil
MG.Macro.Write("target", "任務目標", "ICON", "/run MGTP()", true)
check(#said == 1, "拖回提示只出一次")
-- 9. 物品巨集各自提醒一次；新玩家（沒有舊巨集）不提醒
macros[#macros + 1] = { name = "任務物品", body = "/use item:1" }
MG.Macro.Write("item", "任務物品", "ICON", "/use item:2", true)
check(#said == 2 and said[2]:find("SLV 任務物品", 1, true), "物品巨集也提醒一次")
said = {}; MetroGuideDB = {}
reset({})
MG.Macro.Write("target", "任務目標", "ICON", "/run MGTP()", true)
check(#said == 0, "新玩家沒有舊巨集不提醒")
-- 10. 設定說明和診斷用的完整名稱
check(MG.Macro.Name("item") == "SLV 任務物品" and MG.Macro.Name("target") == "SLV 任務目標" and MG.Macro.Name("x") == nil, "完整巨集名")
check(("建立「{target}」巨集"):gsub("{(%a+)}", MG.Macro.Name) == "建立「SLV 任務目標」巨集", "設定說明換成完整名稱")

if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("macro-adopt: all passed")
