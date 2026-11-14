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
local frozenElement = nil
local lastDispatchAt = 0
local currentVX, currentVY, currentVZ = 0, 0, 0

local rewindRender

local function now()
    return getTickCount()
end

local function captureSample()
    local vehicle = getPedOccupiedVehicle(localPlayer)
    local target = vehicle or localPlayer
    if not isElement(target) then
        return
    end

    local x, y, z = getElementPosition(target)
    local rx, ry, rz = getElementRotation(target)
    local vx, vy, vz = getElementVelocity(target)

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
end

local function stopRewind()
    if not active then
        return
    end

    active = false
    removeEventHandler('onClientRender', root, rewindRender)

    if isElement(frozenElement) then
        setElementFrozen(frozenElement, false)
        setElementVelocity(frozenElement, currentVX, currentVY, currentVZ)
    end

    frozenElement = nil
    resetSamples()

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
    frozenElement = getPedOccupiedVehicle(localPlayer) or localPlayer

    setElementFrozen(frozenElement, true)
    setElementVelocity(frozenElement, 0, 0, 0)

    addEventHandler('onClientRender', root, rewindRender)

    if RST.dispatch then
        RST.dispatch('rewind', { active = true, progress = 0, seconds = 0 })
    end
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
        stopRewind()
        return
    end

    local targetTime = samples[#samples].t - elapsed
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
