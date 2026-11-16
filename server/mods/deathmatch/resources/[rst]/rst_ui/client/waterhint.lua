--[[
    rst_ui / client/waterhint.lua

    落水提示：玩家（或载具）泡在水里、整体速度不快时，显示「按住 R 重生」。
    - 训练和竞技模式都可用；竞技模式重生消耗 1 条命
    - 服务端会再校验一次是否真的在水里、速度是否够低
    - 在水里低速持续 0.8 秒才出现，避免溅水瞬间闪一下
    - 按住 R 0.8 秒触发重生，期间拦截 R 的默认动作
]]

local CHECK_INTERVAL_MS = 150
local SHOW_DELAY_MS = 800
local HOLD_MS = 800
local COOLDOWN_MS = 3000
local SPEED_THRESHOLD = 1.0
local TOAST_INTERVAL_MS = 6000

local timer = nil
local slowSince = nil
local active = false
local holdStartedAt = nil
local cooldownUntil = 0
local lastToastAt = 0
local rDown = false

local function now()
    return getTickCount()
end

local function targetElement()
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if vehicle and isElement(vehicle) then
        -- 乘客不做重生提示，避免把整辆车从水里拖出来
        if getVehicleOccupant(vehicle, 0) ~= localPlayer then
            return nil
        end
        return vehicle, vehicle
    end
    return localPlayer, nil
end

local function speedOf(element)
    local vx, vy, vz = getElementVelocity(element)
    return math.sqrt(vx * vx + vy * vy + vz * vz)
end

local function isInWater(element, vehicle)
    if vehicle and isElement(vehicle) then
        -- 载具里 isElementInWater(player) 经常是 false，必须查车
        return isElementInWater(vehicle) == true
    end
    return isElementInWater(element) == true
end

local function canHint()
    if not RST.isGameplayActive() then
        return false
    end
    if RST.gameMode ~= 'training' and RST.gameMode ~= 'competitive' then
        return false
    end
    if RST.rewindLives ~= nil and RST.rewindLives <= 0 then
        return false
    end
    if getElementHealth(localPlayer) <= 0 then
        return false
    end
    if RST.isRewinding and RST.isRewinding() then
        return false
    end
    return now() >= cooldownUntil
end

-- 用现成的 toast 提示，低速泡在水里时每 6 秒提醒一次
local function toastHint()
    local tick = now()
    if tick - lastToastAt < TOAST_INTERVAL_MS then
        return
    end
    lastToastAt = tick
    local text
    if RST.gameMode == 'competitive' then
        text = '落水了 · 按住 R 重生（消耗 1 条命）'
    else
        text = '落水了 · 按住 R 重生'
    end
    RST.dispatch('toast', { text = text })
end

local function stopHint()
    slowSince = nil
    holdStartedAt = nil
    active = false
end

local function triggerRespawn()
    stopHint()
    cooldownUntil = now() + COOLDOWN_MS
    rDown = false
    triggerServerEvent('rst:ui:action', localPlayer, toJSON({ action = 'respawn' }))
end

local function update()
    if not canHint() then
        stopHint()
        return
    end

    local element, vehicle = targetElement()
    if not element then
        stopHint()
        return
    end

    if not isInWater(element, vehicle) or speedOf(element) > SPEED_THRESHOLD then
        stopHint()
        return
    end

    slowSince = slowSince or now()
    if now() - slowSince < SHOW_DELAY_MS then
        return
    end

    active = true

    -- 提示出现时如果玩家已经按着 R，直接开始计入进度
    if not rDown and type(getKeyState) == 'function' then
        local ok, down = pcall(getKeyState, 'r')
        if ok and down == true then
            rDown = true
            holdStartedAt = holdStartedAt or now()
        end
    end

    if rDown then
        holdStartedAt = holdStartedAt or now()
        if now() - holdStartedAt >= HOLD_MS then
            triggerRespawn()
            return
        end
    else
        holdStartedAt = nil
    end

    toastHint()
end

addEventHandler('onClientResourceStart', resourceRoot, function()
    if timer then
        killTimer(timer)
    end
    timer = setTimer(update, CHECK_INTERVAL_MS, 0)
end)

addEventHandler('onClientResourceStop', resourceRoot, function()
    if timer then
        killTimer(timer)
        timer = nil
    end
    stopHint()
end)

addEventHandler('onClientKey', root, function(button, press)
    if tostring(button):lower() ~= 'r' then
        return
    end

    if not press then
        rDown = false
        holdStartedAt = nil
        return
    end

    if not active then
        return
    end
    if isChatBoxInputActive() or isConsoleActive() or isMTAWindowActive() then
        return
    end

    -- 提示出现时 R 由重生接管，避免触发游戏默认动作
    cancelEvent()
    rDown = true
    holdStartedAt = now()
end)

addEventHandler('onClientPlayerWasted', localPlayer, function()
    stopHint()
    rDown = false
    holdStartedAt = nil
end)
