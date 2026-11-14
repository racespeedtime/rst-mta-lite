--[[
    rst_ui / server/mapmanager.lua

    真实 mtavault 地图资源加载器。
    - 一次只保留一个 map resource 实例（MTA map 资源是全局单例）
    - 当前房间使用 dimension 0，与 .map 里的 dimension="0" 对齐
    - 地图自带的 vehicle 会移除，避免与 rst 的 raceVehicle 重复；
      racepickup / marker / object 保留
]]

MapManager = {}

local config = RST.config
local currentResource
local currentMapId

local function stopCurrent()
    if currentResource and getResourceState(currentResource) == 'running' then
        stopResource(currentResource)
    end
    currentResource = nil
    currentMapId = nil
end

function MapManager.currentMapId()
    return currentMapId
end

function MapManager.load(mapId)
    local map = config.maps[mapId]
    if not map then
        return false, '地图配置不存在'
    end
    if not map.resource then
        return false, '地图没有绑定资源'
    end

    local resource = getResourceFromName(map.resource)
    if not resource then
        return false, ('地图资源未安装：%s'):format(tostring(map.resource))
    end

    if currentMapId == mapId and getResourceState(resource) == 'running' then
        return true
    end

    stopCurrent()

    if getResourceState(resource) == 'running' then
        stopResource(resource)
    end

    local ok, err = startResource(resource)
    if not ok then
        outputServerLog(
            ('[MAP] failed to start %s: %s'):format(tostring(map.resource), tostring(err))
        )
        return false, '地图资源启动失败'
    end

    currentResource = resource
    currentMapId = mapId

    -- 地图自带车辆会与玩家赛车重复；只清理未打 rst 标记的车辆
    for _, vehicle in ipairs(getElementsByType('vehicle')) do
        if not getElementData(vehicle, 'rst:raceVehicle') then
            destroyElement(vehicle)
        end
    end

    outputServerLog(('[MAP] loaded %s (%s)'):format(tostring(map.name), tostring(map.resource)))
    return true
end

function MapManager.stop()
    stopCurrent()
end

addEventHandler('onResourceStop', resourceRoot, function()
    MapManager.stop()
end)
