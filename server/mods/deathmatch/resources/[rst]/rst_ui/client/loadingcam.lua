--[[
    rst_ui / client/loadingcam.lua

    登录 / 选图 / 换图装载时的电影镜头：
    - 玩家还没进入比赛（auth / stage）或服务端正在装载地图时启用
    - 相机沿随机三次贝塞尔曲线在 GTA:SA 世界范围内缓慢飞行
    - 不显示出生点，也不影响玩家操作；装载结束自动交还相机
]]

-- 每个客户端每次进服都换一组随机序列，避免所有人/每次连接看到同一条路线
math.randomseed((getTickCount() + (getRealTime().timestamp or 0)) % 2147483647)

local ANCHORS = {
    { x = 1544, y = -1675, z = 120 },  -- Los Santos
    { x = 2480, y = -1666, z = 110 },  -- LS 海滩
    { x = -2000, y = 500, z = 130 },   -- San Fierro
    { x = -1200, y = -500, z = 120 },  -- 乡村
    { x = 2000, y = 1500, z = 140 },   -- Las Venturas
    { x = 1000, y = 500, z = 120 },    -- 中部
    { x = 0, y = 0, z = 160 },         -- 地图中心
    { x = 2400, y = 1000, z = 130 },   -- LV 东侧
    { x = -500, y = 1600, z = 120 },   -- 北部
    { x = 600, y = -1200, z = 110 },   -- 南部
}

local active = false
local loading = false
local transferBoxVisible = false
local startedAt = 0
local duration = 1
local p0, p1, p2, p3
local pollTimer

local function now()
    return getTickCount()
end

local function randomAnchor()
    return ANCHORS[math.random(#ANCHORS)]
end

local function distanceSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local function cubic(t, a, b, c, d)
    local u = 1 - t
    local u2, t2 = u * u, t * t
    return {
        x = u2 * u * a.x + 3 * u2 * t * b.x + 3 * u * t2 * c.x + t2 * t * d.x,
        y = u2 * u * a.y + 3 * u2 * t * b.y + 3 * u * t2 * c.y + t2 * t * d.y,
        z = u2 * u * a.z + 3 * u2 * t * b.z + 3 * u * t2 * c.z + t2 * t * d.z,
    }
end

local function newPath(from)
    p0 = from or randomAnchor()
    repeat
        p1 = randomAnchor()
    until distanceSq(p0, p1) > 250 * 250
    repeat
        p2 = randomAnchor()
    until distanceSq(p1, p2) > 250 * 250
    repeat
        p3 = randomAnchor()
    until distanceSq(p2, p3) > 250 * 250 and distanceSq(p0, p3) > 300 * 300
    startedAt = now()
    duration = 18000 + math.random(0, 9000)
end

local function render()
    if not active then
        return
    end

    local t = (now() - startedAt) / duration
    if t >= 1 then
        newPath(p3)
        t = 0
    end
    t = math.max(0, math.min(1, t))

    local position = cubic(t, p0, p1, p2, p3)
    -- 镜头看向曲线前方一点，并略微向下俯视
    local look = cubic(math.min(1, t + 0.08), p0, p1, p2, p3)
    look.z = look.z - 45

    setCameraMatrix(position.x, position.y, position.z, look.x, look.y, look.z)
end

local function shouldRun()
    if loading or transferBoxVisible then
        return true
    end
    return RST.phase ~= 'playing'
end

local function startCamera()
    if active then
        return
    end
    active = true
    newPath(nil)
    addEventHandler('onClientRender', root, render)
    render()
end

local function stopCamera()
    if not active then
        return
    end
    active = false
    removeEventHandler('onClientRender', root, render)
    if isElement(localPlayer) then
        pcall(setCameraTarget, localPlayer)
    end
end

local function refresh()
    if shouldRun() then
        startCamera()
    else
        stopCamera()
    end
end

-- 资源下载期间也显示运镜；box 隐藏且比赛已开始时自动收回
addEventHandler('onClientTransferBoxVisibilityChange', root, function(visible)
    transferBoxVisible = visible == true
    refresh()
end)

addEvent('rst:ui:loading', true)
addEventHandler('rst:ui:loading', root, function(state)
    loading = state == true
    refresh()
end)

addEventHandler('onClientResourceStart', resourceRoot, function()
    if pollTimer then
        killTimer(pollTimer)
    end
    pollTimer = setTimer(refresh, 500, 0)
    refresh()
end)

addEventHandler('onClientResourceStop', resourceRoot, function()
    if pollTimer then
        killTimer(pollTimer)
        pollTimer = nil
    end
    stopCamera()
end)

addEventHandler('onClientPlayerWasted', localPlayer, function()
    stopCamera()
end)
