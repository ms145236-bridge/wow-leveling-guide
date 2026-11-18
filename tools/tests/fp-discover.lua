-- From the repository root: lua5.1 tools/tests/fp-discover.lua
-- 「發現新的飛行路線！」只在人確定就在目前那個鳥點旁時才算開了；讀不到位置或在別張地圖都不算。
function GetLocale() return "zhTW" end
function InCombatLockdown() return false end
local anyMeta = {}
anyMeta.__index = function() return function() return setmetatable({}, anyMeta) end end
function CreateFrame() return setmetatable({}, anyMeta) end
LE_GAME_ERR_NEWTAXIPATH, ERR_NEWTAXIPATH = 361, "發現新的飛行路線！"
local MG = {}
MetroGuideDB = {}
assert(loadfile("addon/ShengLeveling/Compat.lua"))("ShengLeveling", MG)

local fails = 0
local function check(cond, what)
  if not cond then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end
end
local fp = { t = "fp", node = "Thelsamar", nodeK = "塞爾薩瑪", map = 1432, x = 33.9, y = 51.0 }
check(MG.IsNewTaxiPath(361, nil), "類別對上")
check(MG.IsNewTaxiPath(nil, "發現新的飛行路線！"), "文字對上")
check(not MG.IsNewTaxiPath(1, "任務完成"), "其他系統提示不算")
check(MG.AtFlightPoint(fp, 1432, 34.5, 50.2), "同地圖、10 格內：算")
check(not MG.AtFlightPoint(fp, 1432, 50, 50), "同地圖、太遠：不算")
check(not MG.AtFlightPoint(fp, 1426, 34, 51), "別張地圖：不算")
check(not MG.AtFlightPoint(fp, 1426, nil, nil), "別張地圖、沒座標：不算")
check(not MG.AtFlightPoint(fp, nil, nil, nil), "位置未知：不算")
check(not MG.AtFlightPoint({ t = "go", map = 1432, x = 33.9, y = 51.0 }, 1432, 33.9, 51.0), "目前不是開鳥點：不算")
if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("fp-discover: all passed")
