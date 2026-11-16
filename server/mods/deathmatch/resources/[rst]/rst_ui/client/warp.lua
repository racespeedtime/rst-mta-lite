--[[
    rst_ui / client/warp.lua

    训练模式快速传送点：
    - 双击左 Alt：保存第一下按下时的位置
    - 长按左 Alt：回到最近一次保存的位置
    - F2 → 训练：回到任意点 / 删除 / 回到最近
    - 回到传送点后冻结 500ms，和倒带松开后的处理一致
    - 与倒带互斥
]]

local HOLD_MS = 400
local DOUBLE_TAP_MS = 350
local FREEZE_MS = 500
local MAX_WARPS = 20

local warps = {}
local nextId = 1
local holding = false
local longTriggered = false
local holdTimer = nil
local freezeTimer = nil
local frozenElement = nil
local warpSeq = 0
local lastTapAt = 0
local saveWindowTimer = nil
local pendingWarp = nil

local function clearPendingWarp()
    pendingWarp = nil
    lastTapAt = 0
    if saveWindowTimer then
        killTimer(saveWindowTimer)
        saveWindowTimer = nil
    end
end

local function toast(text)
    if RST.dispatch then
        RST.dispatch('toast', { text = text })
    end
end

local function syncWarps()
    local items = {}
    for index = #warps, 1, -1 do
        local warp = warps[index]
        items[#items + 1] = {
            id = warp.id,
            index = index,
            x = warp.x,
            y = warp.y,
            z = warp.z,
            rx = warp.rx,
            ry = warp.ry,
            rz = warp.rz,
            at = warp.at,
            vehicle = warp.vehicle,
        }
    end
    if RST.dispatch then
        RST.dispatch('warps', { items = items })
    end
end

local function canWarp()
    if RST.phase ~= 'playing' or RST.mode ~= 'playing' then
        return false
    end
    if RST.loading then
        return false
    end
    if RST.gameMode ~= 'training' then
        return false
    end
    if RST.warpBusy then
        return false
    end
    if RST.isRewindBusy and RST.isRewindBusy() then
        return false
    end
    if not RST.isGameplayActive() then
        return false
    end
    if isChatBoxInputActive() or isConsoleActive() or isMTAWindowActive() then
        return false
    end
    return isElement(localPlayer) and getElementHealth(localPlayer) > 0
end

local function explainWarpBlocked(action)
    if RST.loading then
        toast('地图装载中，不能' .. action)
    elseif RST.phase ~= 'playing' or RST.mode ~= 'playing' then
        toast('当前不在比赛中')
    elseif RST.gameMode ~= 'training' then
        toast('只有训练模式可以' .. action)
    elseif RST.readyWaiting then
        toast('比赛还没开始，不能' .. action)
    elseif RST.countdownActive then
        toast('出发倒计时中，不能' .. action)
    elseif RST.isRewindBusy and RST.isRewindBusy() then
        toast('倒带进行中，不能' .. action)
    elseif RST.warpBusy then
        toast('正在传送，稍后再试')
    end
end

local function readAngularVelocity(element)
    if not element or not isElement(element) or not getElementAngularVelocity then
        return 0, 0, 0
    end
    local ok, x, y, z = pcall(getElementAngularVelocity, element)
    if not ok then
        return 0, 0, 0
    end
    return x or 0, y or 0, z or 0
end

local function applyAngularVelocity(element, x, y, z)
    if element and isElement(element) and setElementAngularVelocity then
        pcall(setElementAngularVelocity, element, x or 0, y or 0, z or 0)
    end
end

local function readMatrix(element)
    if not element or not isElement(element) or not getElementMatrix then
        return nil
    end
    local ok, matrix = pcall(getElementMatrix, element)
    return ok and matrix or nil
end

local function hasNitroUpgrade(vehicle)
    if not isElement(vehicle) or getElementType(vehicle) ~= 'vehicle' then
        return false
    end
    for _, upgrade in ipairs(getVehicleUpgrades(vehicle) or {}) do
        if tonumber(upgrade) == 1010 then
            return true
        end
    end
    return false
end

local function applyNitro(element, state)
    if not isElement(element) or getElementType(element) ~= 'vehicle' then
        return
    end
    if state.hasNitro == true then
        pcall(addVehicleUpgrade, element, 1010)
    elseif state.hasNitro == false then
        pcall(removeVehicleUpgrade, element, 1010)
    end
    if type(state.nitroLevel) == 'number' then
        pcall(setVehicleNitroLevel, element, math.max(0, math.min(1, state.nitroLevel)))
    end
    if type(state.nitroCount) == 'number' then
        pcall(setVehicleNitroCount, element, state.nitroCount)
    end
    if state.nitroActive ~= nil then
        pcall(setVehicleNitroActivated, element, state.nitroActive == true)
    end
end

local function syncWarpNitro(state)
    if state.hasNitro == nil then
        return
    end
    triggerServerEvent(
        'rst:warp:nitro',
        localPlayer,
        state.hasNitro == true,
        state.nitroLevel,
        state.nitroCount
    )
end

local function restoreMotion(element, state)
    if not isElement(element) then
        return
    end
    pcall(setElementVelocity, element, state.vx or 0, state.vy or 0, state.vz or 0)
    applyAngularVelocity(element, state.avx, state.avy, state.avz)
    applyNitro(element, state)
end

function RST.stopWarp()
    if freezeTimer then
        killTimer(freezeTimer)
        freezeTimer = nil
    end
    if isElement(frozenElement) then
        pcall(setElementFrozen, frozenElement, false)
    end
    frozenElement = nil
    RST.warpBusy = false
end

local function freezeAfterWarp(element, state)
    if not isElement(element) then
        return
    end

    RST.stopWarp()
    frozenElement = element
    RST.warpBusy = true
    pcall(setElementFrozen, element, true)
    pcall(setElementVelocity, element, 0, 0, 0)
    applyAngularVelocity(element, 0, 0, 0)
    if getElementType(element) == 'vehicle' then
        pcall(setVehicleNitroActivated, element, false)
    end

    freezeTimer = setTimer(function()
        freezeTimer = nil
        local element = frozenElement
        if isElement(element) then
            pcall(setElementFrozen, element, false)
            restoreMotion(element, state)
        end
        frozenElement = nil
        RST.warpBusy = false
        -- 冻结解除后重新挂一次相机，避免雷达/朝向停在固定视角
        if isElement(localPlayer) then
            pcall(setCameraTarget, localPlayer)
        end
    end, FREEZE_MS, 1)
end

local function teleportTo(warp)
    if not warp then
        return false
    end
    if warp.mapId ~= RST.mapId then
        toast('传送点属于其他地图')
        return false
    end
    if not canWarp() then
        explainWarpBlocked('传送')
        return false
    end

    local vehicle = getPedOccupiedVehicle(localPlayer)
    local target = vehicle or localPlayer
    if not isElement(target) then
        return false
    end

    local state = warp.state or warp
    warpSeq = warpSeq + 1
    local seq = warpSeq

    -- 传送点保存时开的是什么车，回来就换回什么车。
    -- 客户端先本地换，服务端再同步一次；模型变化可能重置升级/血量，300ms 后补套状态。
    local savedModel = tonumber(warp.vehicle) or 0
    local modelChanged = vehicle and savedModel > 0 and getElementModel(vehicle) ~= savedModel
    if modelChanged then
        triggerServerEvent(
            'rst:warp:model',
            localPlayer,
            savedModel,
            state.hasNitro,
            state.nitroLevel,
            state.nitroCount
        )
        pcall(setElementModel, vehicle, savedModel)

        setTimer(function()
            if seq ~= warpSeq then
                return
            end
            if not isElement(vehicle) or getPedOccupiedVehicle(localPlayer) ~= vehicle then
                return
            end
            if getElementModel(vehicle) ~= savedModel then
                return
            end
            if state.healthKind == 'vehicle' and type(state.health) == 'number' then
                pcall(setElementHealth, vehicle, math.max(1, math.min(1000, state.health)))
            end
            if state.damage then
                RST.applyVehicleDamage(vehicle, state.damage)
            end
            applyNitro(vehicle, state)

            -- 服务端同步模型可能把相机/朝向重置；这里再补一次并重新挂上追车相机，
            -- 否则雷达会一直指北
            if state.matrix and type(setElementMatrix) == 'function' then
                pcall(setElementMatrix, vehicle, state.matrix)
            end
            pcall(setElementRotation, vehicle, warp.rx, warp.ry, warp.rz)
            pcall(setElementRotation, localPlayer, warp.rx, warp.ry, warp.rz)
            pcall(setCameraTarget, localPlayer)
        end, 300, 1)
    end

    -- 位置 + 朝向：有矩阵时一起恢复精确朝向，Euler 作为兜底
    if state.matrix and setElementMatrix then
        pcall(setElementMatrix, target, state.matrix)
    end
    setElementPosition(target, warp.x, warp.y, warp.z)
    setElementRotation(target, warp.rx, warp.ry, warp.rz)
    -- 和倒带结束时一样，相机目标必须是 localPlayer；指向载具会让雷达停住朝北
    pcall(setElementRotation, localPlayer, warp.rx, warp.ry, warp.rz)
    pcall(setCameraTarget, localPlayer)

    -- 载具/玩家血量、护甲、氮气
    if state.healthKind == 'vehicle' and vehicle then
        local health = math.max(1, math.min(1000, tonumber(state.health) or 1000))
        setElementHealth(vehicle, health)
        triggerServerEvent('rst:rewind:health', localPlayer, health)
    end
    if state.playerHealth then
        pcall(setElementHealth, localPlayer, math.max(1, math.min(100, state.playerHealth)))
    end
    if state.armor then
        pcall(setPedArmor, localPlayer, math.max(0, math.min(100, state.armor)))
    end
    if vehicle then
        applyNitro(vehicle, state)
        if not modelChanged then
            syncWarpNitro(state)
        end
        pcall(setVehicleNitroActivated, vehicle, false)
        if state.damage then
            RST.applyVehicleDamage(vehicle, state.damage)
        end
    end

    setElementVelocity(target, 0, 0, 0)
    freezeAfterWarp(target, state)
    return true
end

-- 真正记录“按下 Alt 那一刻”的状态；双击的第二次点击只负责触发保存。
local function captureWarpState()
    if not RST.mapId then
        return nil
    end

    local vehicle = getPedOccupiedVehicle(localPlayer)
    local target = vehicle or localPlayer
    local x, y, z = getElementPosition(target)
    local rx, ry, rz = getElementRotation(target)
    local vx, vy, vz = getElementVelocity(target)
    local avx, avy, avz = readAngularVelocity(target)
    local matrix = readMatrix(target)

    local nitroLevel, nitroCount, nitroActive
    local hasNitro = hasNitroUpgrade(vehicle)
    if vehicle then
        nitroLevel = getVehicleNitroLevel(vehicle)
        nitroCount = getVehicleNitroCount(vehicle)
        nitroActive = isVehicleNitroActivated(vehicle)
    end

    return {
        mapId = RST.mapId,
        x = x,
        y = y,
        z = z,
        rx = rx,
        ry = ry,
        rz = rz,
        at = os.time(),
        vehicle = vehicle and getElementModel(vehicle) or 0,
        state = {
            x = x,
            y = y,
            z = z,
            rx = rx,
            ry = ry,
            rz = rz,
            vx = vx,
            vy = vy,
            vz = vz,
            avx = avx,
            avy = avy,
            avz = avz,
            matrix = matrix,
            healthKind = vehicle and 'vehicle' or 'player',
            health = getElementHealth(target),
            playerHealth = getElementHealth(localPlayer),
            armor = getPedArmor(localPlayer) or 0,
            damage = vehicle and RST.captureVehicleDamage(vehicle) or nil,
            hasNitro = hasNitro,
            nitroLevel = nitroLevel,
            nitroCount = nitroCount,
            nitroActive = nitroActive,
        },
    }
end

local function appendWarp(warp)
    if type(warp) ~= 'table' then
        return false
    end
    if not warp.mapId or warp.mapId ~= RST.mapId then
        toast('地图已切换，传送点没有保存')
        return false
    end

    warp.id = nextId
    nextId = nextId + 1
    warps[#warps + 1] = warp

    while #warps > MAX_WARPS do
        table.remove(warps, 1)
    end

    syncWarps()
    toast(('已保存传送点 #%d'):format(warp.id))
    return true
end

function RST.saveWarp()
    if not canWarp() then
        explainWarpBlocked('保存传送点')
        return false
    end
    if not RST.mapId then
        toast('当前没有可用地图')
        return false
    end

    local saved = appendWarp(captureWarpState())
    -- F2 主动保存后，丢弃正在等待第二下 Alt 的旧快照
    clearPendingWarp()
    return saved
end

function RST.goWarp(id)
    id = tonumber(id)
    if not id then
        return false
    end
    local warp
    for _, item in ipairs(warps) do
        if item.id == id then
            warp = item
            break
        end
    end
    if not warp then
        toast('传送点不存在')
        return false
    end
    if teleportTo(warp) then
        toast(('已回到传送点 #%d'):format(id))
        return true
    end
    return false
end

function RST.goLatestWarp()
    if #warps == 0 then
        toast('还没有保存传送点')
        return false
    end
    return RST.goWarp(warps[#warps].id)
end

function RST.deleteWarp(id)
    id = tonumber(id)
    if not id then
        return false
    end
    for index, item in ipairs(warps) do
        if item.id == id then
            table.remove(warps, index)
            syncWarps()
            toast(('已删除传送点 #%d'):format(id))
            return true
        end
    end
    return false
end

function RST.clearWarps()
    warps = {}
    nextId = 1
    clearPendingWarp()
    RST.stopWarp()
    syncWarps()
end

-- 双击保存；按住达到阈值直接回到最近一个点
addEventHandler('onClientKey', root, function(button, press)
    if tostring(button):lower() ~= 'lalt' then
        return
    end

    if not press then
        if not holding then
            return
        end
        holding = false
        RST.warpHolding = false
        if holdTimer then
            killTimer(holdTimer)
            holdTimer = nil
        end
        if not longTriggered and canWarp() then
            local tick = getTickCount()
            if lastTapAt > 0 and tick - lastTapAt <= DOUBLE_TAP_MS then
                lastTapAt = 0
                if saveWindowTimer then
                    killTimer(saveWindowTimer)
                    saveWindowTimer = nil
                end
                local warp = pendingWarp or captureWarpState()
                pendingWarp = nil
                appendWarp(warp)
            else
                lastTapAt = tick
                if not pendingWarp then
                    pendingWarp = captureWarpState()
                end
                if saveWindowTimer then
                    killTimer(saveWindowTimer)
                end
                saveWindowTimer = setTimer(function()
                    lastTapAt = 0
                    pendingWarp = nil
                    saveWindowTimer = nil
                end, DOUBLE_TAP_MS, 1)
            end
        end
        longTriggered = false
        return
    end

    if holding or not canWarp() then
        return
    end

    -- 取消原生 Alt 菜单/组合键，Alt 在这里只用于传送点
    cancelEvent()
    holding = true
    RST.warpHolding = true
    longTriggered = false
    -- 第一下按下就抓状态；第二下只负责在窗口内触发保存
    if lastTapAt == 0 and not pendingWarp then
        pendingWarp = captureWarpState()
    end
    holdTimer = setTimer(function()
        holdTimer = nil
        if not holding or not canWarp() then
            return
        end
        longTriggered = true
        lastTapAt = 0
        pendingWarp = nil
        if saveWindowTimer then
            killTimer(saveWindowTimer)
            saveWindowTimer = nil
        end
        RST.goLatestWarp()
    end, HOLD_MS, 1)
end)

addEventHandler('onClientPlayerWasted', localPlayer, function()
    holding = false
    RST.warpHolding = false
    clearPendingWarp()
    if holdTimer then
        killTimer(holdTimer)
        holdTimer = nil
    end
    RST.stopWarp()
end)

addEventHandler('rst:ui:ready', root, function()
    syncWarps()
end)
