--[[
    rst_ui / client/pickups.lua

    原生 race 地图没有 race 资源，<racepickup> 不会被 MTA 核心自动实例化。
    这里按 race 资源的做法：客户端创建自定义模型 object + colshape，
    命中后由本地立即反馈，并通知服务端做权威同步和重生。
]]

local MODELS = {
    nitro = 2221,
    repair = 2222,
    vehiclechange = 2223,
}

local objects = {}
local colshapes = {}
local pickupById = {}
local currentMapId = nil
local pickupStartTick = getTickCount()

local function loadModels()
    for pickupType, model in pairs(MODELS) do
        local dff = engineLoadDFF('pickups/' .. pickupType .. '.dff')
        local txd = engineLoadTXD('pickups/' .. pickupType .. '.txd')
        if txd then
            engineImportTXD(txd, model)
        else
            outputDebugString('[pickups] txd load failed: ' .. pickupType, 1)
        end
        if dff then
            engineReplaceModel(dff, model)
        else
            outputDebugString('[pickups] dff load failed: ' .. pickupType, 1)
        end
        if engineSetModelLODDistance then
            pcall(engineSetModelLODDistance, model, 60)
        end
    end
end

local function clearPickups()
    for _, shape in pairs(colshapes) do
        if isElement(shape) then
            destroyElement(shape)
        end
    end
    for _, object in pairs(objects) do
        if isElement(object) then
            destroyElement(object)
        end
    end
    objects = {}
    colshapes = {}
    pickupById = {}
end

local function applyPickupVisibility(pickup, visible)
    pickup.visible = visible == true
    if isElement(pickup.object) then
        setElementAlpha(pickup.object, pickup.visible and (pickup.alpha or 255) or 0)
    end
end

local function createPickups(payload)
    clearPickups()

    if type(payload) ~= 'table' or not payload.mapId or type(payload.pickups) ~= 'table' then
        currentMapId = nil
        return
    end

    currentMapId = payload.mapId
    pickupStartTick = getTickCount()
    local dimension = tonumber(payload.dimension) or 0
    local created = 0

    for _, pickup in ipairs(payload.pickups) do
        local model = MODELS[pickup.type]
        if model then
            local object = createObject(model, pickup.x, pickup.y, pickup.z, 0, 0, pickup.rotZ or 0)
            if object then
                setElementCollisionsEnabled(object, false)
                setElementDimension(object, dimension)
                setElementInterior(object, pickup.interior or 0)

                local shape = createColSphere(pickup.x, pickup.y, pickup.z, 3.5)
                setElementDimension(shape, dimension)
                setElementInterior(shape, pickup.interior or 0)

                local entry = {
                    id = tostring(pickup.id),
                    type = pickup.type,
                    vehicle = tonumber(pickup.vehicle),
                    x = pickup.x,
                    y = pickup.y,
                    z = pickup.z,
                    alpha = tonumber(pickup.alpha) or 255,
                    respawn = tonumber(pickup.respawn) or 0,
                    object = object,
                    shape = shape,
                }
                objects[entry.id] = object
                colshapes[entry.id] = shape
                pickupById[entry.id] = entry
                applyPickupVisibility(entry, pickup.visible == true)
                created = created + 1
            end
        end
    end

    outputDebugString(('[pickups] map=%s created=%d'):format(tostring(payload.mapId), created), 1)
end

local function applyLocalEffect(pickup, vehicle)
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
    end
end

addEventHandler('onClientResourceStart', resourceRoot, function()
    loadModels()
end)

addEventHandler('onClientResourceStop', resourceRoot, function()
    clearPickups()
end)

addEventHandler('onClientColShapeHit', root, function(element)
    if element ~= getPedOccupiedVehicle(localPlayer) then
        return
    end

    local pickup = nil
    for _, entry in pairs(pickupById) do
        if entry.shape == source then
            pickup = entry
            break
        end
    end
    if not pickup or not pickup.visible then
        return
    end

    if pickup.type == 'vehiclechange' and pickup.vehicle == getElementModel(element) then
        return
    end

    applyLocalEffect(pickup, element)
    -- 官方 race：respawn 为 0 的 pickup 是永久可重复拾取，不隐藏
    if (pickup.respawn or 0) >= 50 then
        applyPickupVisibility(pickup, false)
    end
    triggerServerEvent('rst:pickups:hit', localPlayer, pickup.id)
    pcall(playSoundFrontEnd, 46)
end)

addEventHandler('onClientRender', root, function()
    local angle = math.fmod((getTickCount() - pickupStartTick) * 360 / 2000, 360)
    for _, entry in pairs(pickupById) do
        if entry.visible and isElement(entry.object) then
            setElementRotation(entry.object, 0, 0, angle)
        end
    end
end)

addEvent('rst:pickups:sync', true)
addEventHandler('rst:pickups:sync', root, function(json)
    local data = fromJSON(json or '')
    if type(data) ~= 'table' then
        return
    end
    createPickups(data)
end)

addEvent('rst:pickups:state', true)
addEventHandler('rst:pickups:state', root, function(json)
    local data = fromJSON(json or '')
    if type(data) ~= 'table' then
        return
    end

    local pickup = pickupById[tostring(data.id or '')]
    if pickup then
        applyPickupVisibility(pickup, data.visible == true)
    end
end)

addEventHandler('rst:ui:state', root, function(json)
    local state = fromJSON(json or '')
    if type(state) ~= 'table' then
        return
    end

    if state.phase ~= 'playing' or type(state.room) ~= 'table' or not state.room.mapId then
        if state.phase ~= 'playing' then
            clearPickups()
            currentMapId = nil
        end
        return
    end

    if currentMapId ~= state.room.mapId then
        currentMapId = state.room.mapId
        triggerServerEvent('rst:pickups:request', localPlayer)
    end
end)
