--[[
    rst_ui / client/bikelock.lua

    比赛进行中把本地玩家“粘”在摩托 / 自行车上，避免撞墙、落地时被甩飞。
    MTA 的 setPedCanBeKnockedOffBike 是客户端函数，只能锁自己；
    服务端 rooms.lua 的 150ms 检查会兜底把已经落地的人塞回赛车。
]]

local APPLY_INTERVAL_MS = 750

local function applyBikeLock()
    if not isElement(localPlayer) then
        return
    end
    if RST.phase ~= 'playing' then
        return
    end

    local vehicle = getPedOccupiedVehicle(localPlayer)
    if vehicle and isElement(vehicle) then
        setPedCanBeKnockedOffBike(localPlayer, false)
    end
end

addEventHandler('onClientVehicleEnter', root, function(ped)
    if ped == localPlayer then
        applyBikeLock()
    end
end)

addEventHandler('onClientResourceStart', resourceRoot, function()
    applyBikeLock()
    setTimer(applyBikeLock, APPLY_INTERVAL_MS, 0)
end)

-- 换车、重生、观战回来都重新锁一次
addEventHandler('onClientPlayerSpawn', localPlayer, function()
    applyBikeLock()
end)
