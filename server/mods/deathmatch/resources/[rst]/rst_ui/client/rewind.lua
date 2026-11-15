--[[
    rst_ui / client/rewind.lua

    长按 Y：回放最近 8 秒的位置 / 朝向 / 速度（类似《地平线》rewind）。
    - 只有正常游玩状态（非菜单、非观战、非死亡）才记录和触发
    - 回放时冻结玩家（或载具），按 1x 速度倒放
    - 松开 Y 后从回放点继续，速度也会恢复
]]

local HISTORY_SECONDS = 8
local SAMPLE_INTERVAL_MS = 50
local HOLD_DELAY_MS = 250

local samples = {}
local lastSampleAt = 0
local lastVehicle = nil
local holding = false
local holdTimer = nil
local active = false
local activatedAt = 0
local currentSampleTime = nil
local captureSample
local frozenElement = nil
local lastDispatchAt = 0
local currentVX, currentVY, currentVZ = 0, 0, 0
local currentNitroLevel, currentNitroCount, currentNitroActive
local appliedNitroLevel, appliedNitroCount
local currentHealth, appliedHealth

local rewindRender

local function now()
    return getTickCount()
end

local function applyNitroState(vehicle, level, count)
    if not isElement(vehicle) or getElementType(vehicle) ~= 'vehicle' then
        return
    end

    if type(level) == 'number' then
        level = math.max(0, math.min(1, level))
        if appliedNitroLevel == nil or math.abs(level - appliedNitroLevel) > 0.005 then
            pcall(setVehicleNitroLevel, vehicle, level)
            appliedNitroLevel = level
        end
    end

    if type(count) == 'number' and count ~= appliedNitroCount then
        pcall(setVehicleNitroCount, vehicle, count)
        appliedNitroCount = count
    end
end

local function applyHealthState(vehicle, health)
    if not isElement(vehicle) or getElementType(vehicle) ~= 'vehicle' then
        return
    end
    if type(health) ~= 'number' then
        return
    end

    health = math.max(1, math.min(1000, health))
    if appliedHealth == nil or math.abs(health - appliedHealth) >= 1 then
        pcall(setElementHealth, vehicle, health)
        appliedHealth = health
    end
end

captureSample = function()
    local vehicle = getPedOccupiedVehicle(localPlayer)
    local target = vehicle or localPlayer
    if not isElement(target) then
        return
    end

    local x, y, z = getElementPosition(target)
    local rx, ry, rz = getElementRotation(target)
    local vx, vy, vz = getElementVelocity(target)

    local nitroLevel, nitroCount, nitroActive
    local health
    if vehicle and isElement(vehicle) then
        nitroLevel = getVehicleNitroLevel(vehicle)
        nitroCount = getVehicleNitroCount(vehicle)
        nitroActive = isVehicleNitroActivated(vehicle)
        health = getElementHealth(vehicle)
    end

    samples[#samples + 1] = {
        t = now(),
        x = x,
        y = y,
        z = z,
        rx = rx,
        ry = ry,
        rz = rz,
        vx = vx,
        vy = vy,
        vz = vz,
        nitroLevel = nitroLevel,
        nitroCount = nitroCount,
        nitroActive = nitroActive,
        health = health,
    }

    local cutoff = now() - HISTORY_SECONDS * 1000
    while #samples > 1 and samples[1].t < cutoff do
        table.remove(samples, 1)
    end
end

local function resetSamples()
    samples = {}
    lastVehicle = nil
    lastSampleAt = 0
    currentSampleTime = nil
end

-- 回放结束后不能把历史全部丢掉。保留回放点之前的历史，并把时间轴平移到当前时刻，
-- 否则连续使用时每次都从 0 开始重新攒 8 秒。
local function preserveHistory(endpoint)
    if not endpoint then
        resetSamples()
        return
    end

    local nowTick = now()
    local offset = nowTick - endpoint
    local kept = {}
    for _, sample in ipairs(samples) do
        if sample.t <= endpoint + 1 then
            sample.t = sample.t + offset
            kept[#kept + 1] = sample
        end
    end
    samples = kept

    -- 把当前真实状态补成新的历史末端
    lastSampleAt = 0
    captureSample()
    lastSampleAt = now()
end

local function stopRewind()
    if not active then
        return
    end

    active = false
    removeEventHandler('onClientRender', root, rewindRender)

    if isElement(frozenElement) then
        applyNitroState(frozenElement, currentNitroLevel, currentNitroCount)
        if getElementType(frozenElement) == 'vehicle' then
            pcall(setVehicleNitroActivated, frozenElement, currentNitroActive == true)
            applyHealthState(frozenElement, currentHealth)
            if type(currentHealth) == 'number' then
                triggerServerEvent('rst:rewind:health', localPlayer, currentHealth)
            end
        end
        setElementFrozen(frozenElement, false)
        setElementVelocity(frozenElement, currentVX, currentVY, currentVZ)

        if getElementType(frozenElement) == 'vehicle' then
            pcall(setCameraTarget, frozenElement)
        else
            pcall(setCameraTarget, localPlayer)
        end
    end

    frozenElement = nil
    appliedNitroLevel = nil
    appliedNitroCount = nil
    appliedHealth = nil
    preserveHistory(currentSampleTime)
    currentSampleTime = nil

    if RST.dispatch then
        RST.dispatch('rewind', { active = false, progress = 0, seconds = 0 })
    end
end

RST.stopRewind = stopRewind

function RST.resetRewind()
    if active then
        stopRewind()
    end
    resetSamples()
end

function RST.isRewinding()
    return active
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerpAngle(a, b, t)
    local delta = (b - a + 180) % 360 - 180
    return a + delta * t
end

local function startRewind()
    if active or #samples < 8 then
        return
    end
    if not RST.canRewind() then
        return
    end

    if RST.rewindLives ~= nil then
        if RST.rewindLives <= 0 then
            return
        end
        RST.rewindLives = RST.rewindLives - 1
        triggerServerEvent('rst:rewind:use')
    end

    active = true
    activatedAt = now()
    lastDispatchAt = 0
    currentVX, currentVY, currentVZ = 0, 0, 0
    appliedNitroLevel = nil
    appliedNitroCount = nil
    appliedHealth = nil

    local latest = samples[#samples]
    currentNitroLevel = latest.nitroLevel
    currentNitroCount = latest.nitroCount
    currentNitroActive = latest.nitroActive
    currentHealth = latest.health
    currentSampleTime = latest.t

    frozenElement = getPedOccupiedVehicle(localPlayer) or localPlayer

    -- 回放期间关掉正在喷的氮气，否则历史 level 会被当前喷射持续覆盖
    if isElement(frozenElement) and getElementType(frozenElement) == 'vehicle' then
        pcall(setVehicleNitroActivated, frozenElement, false)
    end

    applyNitroState(frozenElement, currentNitroLevel, currentNitroCount)
    applyHealthState(frozenElement, currentHealth)
    setElementFrozen(frozenElement, true)
    setElementVelocity(frozenElement, 0, 0, 0)

    addEventHandler('onClientRender', root, rewindRender)

    if RST.dispatch then
        RST.dispatch('rewind', { active = true, progress = 0, seconds = 0 })
    end
end

local function applyRewindCamera(element)
    if not isElement(element) then
        return
    end

    local x, y, z = getElementPosition(element)
    local _, _, rz = getElementRotation(element)
    local yaw = math.rad(rz or 0)
    -- GTA 的 rz=0 朝 +Y；不能用数学上的 cos/sin 直接当车头方向
    local fx, fy = -math.sin(yaw), math.cos(yaw)
    local isVehicle = getElementType(element) == 'vehicle'

    local speed = math.sqrt(
        (currentVX or 0) * (currentVX or 0)
        + (currentVY or 0) * (currentVY or 0)
        + (currentVZ or 0) * (currentVZ or 0)
    ) * 180
    local ratio = math.max(0, math.min(1, speed / 220))

    local fov = 70
    if getCameraFieldOfView then
        local mode = isVehicle and 'vehicle' or 'player'
        fov = tonumber(getCameraFieldOfView(mode)) or fov
        if isVehicle then
            local maxFov = tonumber(getCameraFieldOfView('vehicle_max')) or fov
            fov = fov + (maxFov - fov) * ratio
        end
    end

    local distance, height, lookAhead, aimHeight
    if isVehicle then
        -- 接近默认追车镜头：静止稍近，高速自动拉远
        distance = 6.2 + 2.2 * ratio
        height = 2.2 + 0.4 * ratio
        lookAhead = 1.2 + 0.8 * ratio
        aimHeight = 1.0
    else
        distance = 3.2
        height = 1.5
        lookAhead = 0.4
        aimHeight = 0.6
    end

    -- 始终在载具/角色正后方；FOV 跟随默认动态镜头，避免回放看起来被放大
    setCameraMatrix(
        x - fx * distance,
        y - fy * distance,
        z + height,
        x + fx * lookAhead,
        y + fy * lookAhead,
        z + aimHeight,
        fov
    )
end

rewindRender = function()
    if not active then
        return
    end

    if not isElement(frozenElement) then
        stopRewind()
        return
    end

    local span = samples[#samples].t - samples[1].t
    if span <= 0 then
        stopRewind()
        return
    end

    local elapsed = now() - activatedAt
    if elapsed >= span then
        local first = samples[1]
        setElementPosition(frozenElement, first.x, first.y, first.z)
        setElementRotation(frozenElement, first.rx, first.ry, first.rz)
        currentVX, currentVY, currentVZ = first.vx, first.vy, first.vz
        currentNitroLevel = first.nitroLevel
        currentNitroCount = first.nitroCount
        currentNitroActive = first.nitroActive
        currentHealth = first.health
        currentSampleTime = first.t
        applyNitroState(frozenElement, currentNitroLevel, currentNitroCount)
        applyHealthState(frozenElement, currentHealth)
        stopRewind()
        return
    end

    local targetTime = samples[#samples].t - elapsed
    currentSampleTime = targetTime
    local index = #samples
    while index > 1 and samples[index].t > targetTime do
        index = index - 1
    end

    local a = samples[index]
    local b = samples[math.min(index + 1, #samples)]
    local frameSpan = b.t - a.t
    local alpha = frameSpan > 0 and (targetTime - a.t) / frameSpan or 0
    alpha = math.max(0, math.min(1, alpha))

    setElementPosition(
        frozenElement,
        lerp(a.x, b.x, alpha),
        lerp(a.y, b.y, alpha),
        lerp(a.z, b.z, alpha)
    )
    setElementRotation(
        frozenElement,
        lerpAngle(a.rx, b.rx, alpha),
        lerpAngle(a.ry, b.ry, alpha),
        lerpAngle(a.rz, b.rz, alpha)
    )

    currentVX = lerp(a.vx, b.vx, alpha)
    currentVY = lerp(a.vy, b.vy, alpha)
    currentVZ = lerp(a.vz, b.vz, alpha)

    if type(a.nitroLevel) == 'number' and type(b.nitroLevel) == 'number' then
        currentNitroLevel = lerp(a.nitroLevel, b.nitroLevel, alpha)
    elseif type(a.nitroLevel) == 'number' then
        currentNitroLevel = a.nitroLevel
    else
        currentNitroLevel = nil
    end
    currentNitroCount = type(b.nitroCount) == 'number' and b.nitroCount or a.nitroCount
    if type(b.nitroActive) == 'boolean' then
        currentNitroActive = b.nitroActive
    elseif type(a.nitroActive) == 'boolean' then
        currentNitroActive = a.nitroActive
    else
        currentNitroActive = false
    end

    if type(a.health) == 'number' and type(b.health) == 'number' then
        currentHealth = lerp(a.health, b.health, alpha)
    elseif type(a.health) == 'number' then
        currentHealth = a.health
    elseif type(b.health) == 'number' then
        currentHealth = b.health
    else
        currentHealth = nil
    end

    applyNitroState(frozenElement, currentNitroLevel, currentNitroCount)
    applyHealthState(frozenElement, currentHealth)
    applyRewindCamera(frozenElement)

    if RST.dispatch and now() - lastDispatchAt >= 100 then
        lastDispatchAt = now()
        RST.dispatch('rewind', {
            active = true,
            progress = math.max(0, math.min(1, elapsed / span)),
            seconds = math.max(0, (span - elapsed) / 1000),
        })
    end
end

-- 录制
addEventHandler('onClientPreRender', root, function()
    if active then
        return
    end

    if not RST.isGameplayActive() then
        resetSamples()
        return
    end

    local vehicle = getPedOccupiedVehicle(localPlayer)
    if vehicle ~= lastVehicle then
        resetSamples()
        lastVehicle = vehicle
    end

    if now() - lastSampleAt >= SAMPLE_INTERVAL_MS then
        lastSampleAt = now()
        captureSample()
    end
end)

-- 长按 Y
bindKey('Y', 'down', function()
    if holding or active then
        return
    end
    if not RST.canRewind() then
        return
    end

    holding = true
    holdTimer = setTimer(function()
        holdTimer = nil
        startRewind()
    end, HOLD_DELAY_MS, 1)
end)

bindKey('Y', 'up', function()
    holding = false
    if holdTimer then
        killTimer(holdTimer)
        holdTimer = nil
    end
    if active then
        stopRewind()
    end
end)

addEventHandler('onClientPlayerWasted', localPlayer, function()
    if active then
        stopRewind()
    end
    resetSamples()
end)
