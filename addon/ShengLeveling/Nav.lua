-- 航點：WaypointUI → 原生使用者航點 → 無。只在目標變了才換；玩家自己放的點不搶。
local _, MG = ...
local N = {}
MG.N = N
local FLAG = "MetroGuide"
local last -- 目前我們放的點 "map:x:y"
local force -- 玩家點了步驟列：這次連別人放的點也蓋掉

local function wpui()
  local api = WaypointUIAPI and WaypointUIAPI.Navigation
  return api and type(api.NewUserNavigation) == "function" and api or nil
end

-- 現在地圖上的使用者航點是不是我們的（沒有航點也算可覆蓋）
local function free()
  if not (C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return true end
  local api = wpui()
  if api and api.IsUserNavigationFlagged and api.IsUserNavigationFlagged(FLAG) then return true end
  local p = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
  local mine = MG.db.wp -- 我們上次放的點（存檔，/reload 後仍認得）
  if p and mine and p.uiMapID == mine.map and p.position then
    local x, y = p.position:GetXY()
    if math.abs(x * 100 - mine.x) < 0.2 and math.abs(y * 100 - mine.y) < 0.2 then return true end
  end
  return false
end

function N.Method()
  if wpui() then return "WaypointUI" end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then return "原生航點" end
  return "無"
end

local function set(map, x, y, name)
  local key = map .. ":" .. x .. ":" .. y
  if key == last then return end
  if not force and not free() then return end -- 玩家自己放了點：等它清掉（每次重算會再試）
  force = nil
  local api = wpui()
  if api then
    api.NewUserNavigation({ name = name, mapID = map, x = x, y = y, flags = FLAG, suppressAudio = true })
  elseif N.Method() == "原生航點" then
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then return end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  else
    return
  end
  MG.db.wp = { map = map, x = x, y = y }
  last = key
end

local function clear()
  if not last then return end
  last = nil
  if not free() then MG.db.wp = nil; return end
  local api = wpui()
  if api and api.ClearUserNavigation then api.ClearUserNavigation()
  elseif C_Map and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
  MG.db.wp = nil
end

function N.Set(map, x, y, name)
  if not MG.UI.Get("arrow") or not (map and x and y) then return N.Clear() end
  MG.try("航點", set, map, x, y, name)
end
function N.Clear() MG.try("航點", clear) end
function N.Forget(takeOver) last = nil; force = takeOver or nil end -- 下次重算強制重放（例如 /reload 後）
