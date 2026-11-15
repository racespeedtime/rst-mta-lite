--[[
    rst_ui / client/warp.lua

    训练模式快速传送点：
    - 短按左 Alt：保存当前位置
    - 长按左 Alt：回到最近一次保存的位置
    - F2 → 训练：回到任意点 / 删除 / 回到最近
    - 回到传送点后冻结 500ms，和倒带松开后的处理一致
    - 与倒带互斥
]]

local HOLD_MS = 400
local FREEZE_MS = 500
local MAX_WARPS = 20

local warps = {}
local nextId = 1
local holding = false
local longTriggered = false
local holdTimer = nil
local freezeTimer = nil
local frozenElement = nil

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

local function freezeAfterWarp(element)
    if not isElement(element) then
        return
    end

    RST.stopWarp()
    frozenElement = element
    RST.warpBusy = true
    pcall(setElementFrozen, element, true)
    pcall(setElementVelocity, element, 0, 0, 0)

    freezeTimer = setTimer(function()
        freezeTimer = nil
        if isElement(frozenElement) then
            pcall(setElementFrozen, frozenElement, false)
            pcall(setElementVelocity, frozenElement, 0, 0, 0)
        end
        frozenElement = nil
        RST.warpBusy = false
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
        if RST.gameMode ~= 'training' then
            toast('只有训练模式可以传送')
        elseif RST.isRewindBusy and RST.isRewindBusy() then
            toast('倒带进行中，不能传送')
        end
        return false
    end

    local vehicle = getPedOccupiedVehicle(localPlayer)
    local target = vehicle or localPlayer
    if not isElement(target) then
        return false
    end

    setElementPosition(target, warp.x, warp.y, warp.z)
    setElementRotation(target, warp.rx, warp.ry, warp.rz)
    setElementVelocity(target, 0, 0, 0)
    if vehicle then
        pcall(setElementRotation, localPlayer, warp.rx, warp.ry, warp.rz)
        pcall(setCameraTarget, target)
    end
    freezeAfterWarp(target)
    return true
end

function RST.saveWarp()
    if not canWarp() then
        if RST.gameMode ~= 'training' then
            toast('只有训练模式可以保存传送点')
        end
        return false
    end
    if not RST.mapId then
        toast('当前没有可用地图')
        return false
    end

    local vehicle = getPedOccupiedVehicle(localPlayer)
    local target = vehicle or localPlayer
    local x, y, z = getElementPosition(target)
    local rx, ry, rz = getElementRotation(target)

    warps[#warps + 1] = {
        id = nextId,
        mapId = RST.mapId,
        x = x,
        y = y,
        z = z,
        rx = rx,
        ry = ry,
        rz = rz,
        at = os.time(),
        vehicle = vehicle and getElementModel(vehicle) or 0,
    }
    nextId = nextId + 1

    while #warps > MAX_WARPS do
        table.remove(warps, 1)
    end

    syncWarps()
    toast(('已保存传送点 #%d'):format(warps[#warps].id))
    return true
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
    RST.stopWarp()
    syncWarps()
end

-- 短按保存；按住达到阈值直接回到最近一个点
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
            RST.saveWarp()
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
    holdTimer = setTimer(function()
        holdTimer = nil
        if not holding or not canWarp() then
            return
        end
        longTriggered = true
        RST.goLatestWarp()
    end, HOLD_MS, 1)
end)

addEventHandler('onClientPlayerWasted', localPlayer, function()
    holding = false
    RST.warpHolding = false
    if holdTimer then
        killTimer(holdTimer)
        holdTimer = nil
    end
    RST.stopWarp()
end)

addEventHandler('rst:ui:ready', root, function()
    syncWarps()
end)
