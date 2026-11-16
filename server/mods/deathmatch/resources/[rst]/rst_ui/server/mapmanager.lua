--[[
    rst_ui / server/mapmanager.lua

    同一时间只跑一张地图：
    - 地图库里的图：先由 MapStore 装进运行槽位 rst_map，再启动槽位
    - 手动安装的原生 map resource：直接 start / stop
    地图维度由 .map 决定；地图自带 vehicle 会移除，racepickup / object / marker 保留。
]]

MapManager = {}

local config = RST.config
local currentResource
local currentMapId
local currentSource
local currentPickups = {}
local pickupState = {}
local pickupTimers = {}
local loadSeq = 0  -- 每次换图自增，异步装载回来时用它判断请求是否已被取代

local function clearPickupTimers()
    for _, timer in pairs(pickupTimers) do
        if isTimer(timer) then
            killTimer(timer)
        end
    end
    pickupTimers = {}
end

local function resetPickups(map)
    clearPickupTimers()
    currentPickups = map and map.pickups or {}
    pickupState = {}
    for _, pickup in ipairs(currentPickups) do
        pickupState[pickup.id] = { visible = true }
    end
end

local function broadcastPickups()
    for _, player in ipairs(getElementsByType('player')) do
        MapManager.sendPickups(player)
    end
end

local function applyMapSettings(settings)
    settings = type(settings) == 'table' and settings or {}

    -- 对齐官方 mapmanager 的默认值，避免换图后残留上一张图的时间/重力状态
    local timeValue = type(settings.time) == 'string' and settings.time or '12:00'
    local hour, minute = timeValue:match('^(%d+):(%d+)$')
    pcall(setTime, tonumber(hour) or 12, tonumber(minute) or 0)

    pcall(setWeather, tonumber(settings.weather) or 0)
    pcall(setGravity, tonumber(settings.gravity) or 0.008)
    pcall(setGameSpeed, tonumber(settings.gamespeed) or 1)
    pcall(setWaveHeight, tonumber(settings.waveheight) or 0)
    pcall(setCloudsEnabled, true)
    pcall(setVehicleWeaponsEnabled, true)

    -- 官方 mapmanager：locked_time=true 时把一分钟拉长到 2147483647ms，实际冻结时间
    local locked = settings.locked_time == true or settings.locked_time == 'true'
    pcall(setMinuteDuration, locked and 2147483647 or 1000)

    if settings.clouds ~= nil then
        pcall(setCloudsEnabled, settings.clouds == true or settings.clouds == 'true')
    end
    if settings.vehicleweapons ~= nil then
        pcall(setVehicleWeaponsEnabled, settings.vehicleweapons == true or settings.vehicleweapons == 'true')
    end
end

local function pickupPayload(player)
    if not currentMapId then
        return nil
    end
    local map = MapRegistry.details(currentMapId)
    if not map then
        return nil
    end

    local list = {}
    for _, pickup in ipairs(currentPickups) do
        local state = pickupState[pickup.id]
        list[#list + 1] = {
            id = pickup.id,
            type = pickup.type,
            vehicle = pickup.vehicle,
            x = pickup.x,
            y = pickup.y,
            z = pickup.z,
            rotZ = pickup.rotZ,
            respawn = pickup.respawn,
            interior = pickup.interior,
            alpha = pickup.alpha,
            visible = state == nil or state.visible ~= false,
        }
    end

    return {
        mapId = currentMapId,
        dimension = map.dimension or 0,
        pickups = list,
    }
end

local function broadcastPickupState(id, visible)
    local payload = {
        id = id,
        visible = visible == true,
    }
    for _, player in ipairs(getElementsByType('player')) do
        triggerClientEvent(player, 'rst:pickups:state', player, toJSON(payload))
    end
end

function MapManager.sendPickups(player)
    local payload = pickupPayload(player)
    if payload then
        triggerClientEvent(player, 'rst:pickups:sync', player, toJSON(payload))
    end
end

function MapManager.hitPickup(player, pickupId)
    if not currentMapId or not isElement(player) then
        return
    end
    local room = Rooms.playerRoom(player)
    if not room or room.mapId ~= currentMapId then
        return
    end

    local pickup
    for _, value in ipairs(currentPickups) do
        if value.id == pickupId then
            pickup = value
            break
        end
    end
    if not pickup then
        return
    end

    local state = pickupState[pickup.id]
    if state and state.visible == false then
        return
    end

    local vehicle = getPedOccupiedVehicle(player)
    if not vehicle then
        return
    end

    local x, y, z = getElementPosition(vehicle)
    local dx, dy, dz = x - pickup.x, y - pickup.y, z - pickup.z
    if dx * dx + dy * dy + dz * dz > 30 * 30 then
        return
    end

    -- 官方 race 只有 respawn >= 50ms 才卸载/重生；0 表示永久可重复拾取
    local respawn = tonumber(pickup.respawn) or 0

    if pickup.type == 'nitro' then
        pcall(addVehicleUpgrade, vehicle, 1010)
    elseif pickup.type == 'repair' then
        pcall(fixVehicle, vehicle)
    elseif pickup.type == 'vehiclechange' and pickup.vehicle then
        if getElementModel(vehicle) ~= pickup.vehicle then
            pcall(removeVehicleUpgrade, vehicle, 1010)
            local health = getElementHealth(vehicle)
            pcall(setElementModel, vehicle, pickup.vehicle)
            setElementHealth(vehicle, health)
        end
        if pickup.vehicle == 425 and Rooms and Rooms.hunterFinish then
            Rooms.hunterFinish(player)
        end
    end

    if respawn >= 50 then
        pickupState[pickup.id] = { visible = false }
        broadcastPickupState(pickup.id, false)

        pickupTimers[pickup.id] = setTimer(function()
            pickupTimers[pickup.id] = nil
            local current = pickupState[pickup.id]
            if current then
                current.visible = true
            end
            broadcastPickupState(pickup.id, true)
        end, respawn, 1)
    end
end

addEvent('rst:pickups:request', true)
addEventHandler('rst:pickups:request', root, function()
    local player = client or source
    if isElement(player) then
        MapManager.sendPickups(player)
    end
end)

addEvent('rst:pickups:hit', true)
addEventHandler('rst:pickups:hit', root, function(pickupId)
    local player = client or source
    if isElement(player) then
        MapManager.hitPickup(player, tostring(pickupId))
    end
end)

local function stopCurrent()
    clearPickupTimers()
    currentPickups = {}
    pickupState = {}

    if currentResource and getResourceState(currentResource) == 'running' then
        stopResource(currentResource)
    end
    currentResource = nil
    currentMapId = nil
    currentSource = nil

    for _, player in ipairs(getElementsByType('player')) do
        triggerClientEvent(player, 'rst:pickups:sync', player, toJSON({ mapId = nil, pickups = {} }))
    end
end

function MapManager.currentMapId()
    return currentMapId
end

function MapManager.currentSource()
    return currentSource
end

local function applyLoadedMap(mapId, map, resource)
    currentResource = resource
    currentMapId = mapId
    currentSource = map.source

    resetPickups(map)
    applyMapSettings(map.settings)

    -- 地图自带车辆会与玩家赛车重复；只清理未打 rst 标记的车辆
    for _, vehicle in ipairs(getElementsByType('vehicle')) do
        if not getElementData(vehicle, 'rst:raceVehicle') then
            destroyElement(vehicle)
        end
    end

    outputServerLog(('[MAP] loaded %s (%s) pickups=%d'):format(
        tostring(map.name), tostring(resource and getResourceName(resource) or mapId), #currentPickups
    ))
    broadcastPickups()
end

-- 加载地图。onDone(ok, err) 在资源真正就绪后回调；
-- 地图已在槽位里时是同步回调，其它情况（首次装载）会在复制 + refresh 之后回调。
function MapManager.load(mapId, onDone)
    onDone = type(onDone) == 'function' and onDone or function() end

    local map = MapRegistry.details(mapId)
    if not map then
        onDone(false, '地图资源未发现')
        return false
    end

    if currentMapId == mapId and currentResource and getResourceState(currentResource) == 'running' then
        -- 同一张图重开也要重置 pickup 状态，避免上一回合的隐藏/计时器残留
        resetPickups(map)
        broadcastPickups()
        onDone(true)
        return true
    end

    -- 新一轮换图：让还在路上的旧装载失效
    loadSeq = loadSeq + 1
    local seq = loadSeq

    if map.source == 'resource' then
        -- 手动安装的原生 map resource：沿用原来的直接启动
        local resource = getResourceFromName(map.resource)
        if not resource then
            onDone(false, ('地图资源未安装：%s'):format(tostring(map.resource)))
            return false
        end

        stopCurrent()
        triggerClientEvent(root, 'rst:ui:custommodel', root)

        local ok, err = startResource(resource)
        if not ok then
            outputServerLog(('[MAP] failed to start %s: %s'):format(tostring(map.resource), tostring(err)))
            onDone(false, '地图资源启动失败')
            return false
        end

        applyLoadedMap(mapId, map, resource)
        onDone(true)
        return true
    end

    -- 地图库：先停掉当前图，再装进运行槽位后启动
    stopCurrent()

    MapStore.install(mapId, function(ok, err)
        if seq ~= loadSeq then
            onDone(false, '已发起新的换图请求')
            return
        end
        if not ok then
            outputServerLog(('[MAP] failed to install %s: %s'):format(tostring(mapId), tostring(err)))
            onDone(false, err or '地图装载失败')
            return
        end

        local resource = getResourceFromName(MapStore.slotName)
        if not resource then
            onDone(false, '地图槽位不存在')
            return
        end

        -- 先恢复服务器默认 Infernus；地图客户端脚本随后加载并可覆盖 411
        triggerClientEvent(root, 'rst:ui:custommodel', root)

        local started, startErr = startResource(resource)
        if not started then
            outputServerLog(('[MAP] failed to start slot for %s: %s'):format(tostring(mapId), tostring(startErr)))
            onDone(false, '地图资源启动失败')
            return
        end

        applyLoadedMap(mapId, map, resource)
        onDone(true)
    end)

    return true
end

function MapManager.stop()
    stopCurrent()
    if MapStore then
        MapStore.stop()
    end
end

addEventHandler('onResourceStop', resourceRoot, function()
    MapManager.stop()
end)
