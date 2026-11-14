--[[
    rst_ui / client/main.lua

    职责：
    - 全屏 CEF 浏览器（local 模式）+ dxDrawImage 渲染 + 输入注入
    - 登录 / 选择舞台 / 游戏 HUD 的状态机与交互开关
    - 浏览器 ↔ Lua ↔ 服务端 的消息转发
    - 观战相机
]]

local UI_URL = 'http://mta/local/ui/index.html'

local browser
local browserReady = false
local screenW, screenH = guiGetScreenSize()

local phase = 'auth'
local mode = 'playing'
local menuOpen = false
local chatOpen = false
local helpOpen = false
local voteActive = false
local interactive = false
local cachedState = nil
local spectateTarget = nil
local spectateName = ''
local spectateTimer = nil
local countdownTimer = nil

RST = {
    phase = phase,
    mode = mode,
    interactive = false,
    menuOpen = false,
    chatOpen = false,
    helpOpen = false,
    voteActive = false,
    countdownActive = false,
}

function RST.isGameplayActive()
    return RST.phase == 'playing'
        and RST.mode == 'playing'
        and not RST.interactive
        and not RST.voteActive
        and not RST.countdownActive
end

function RST.canRewind()
    return RST.isGameplayActive()
        and getElementHealth(localPlayer) > 0
        and not isChatBoxInputActive()
        and not isConsoleActive()
        and not isMTAWindowActive()
end

-- ---------------------------------------------------------------------------
-- 原生 HUD
-- ---------------------------------------------------------------------------

-- 血量 / 护甲 / 武器 / 金钱等改用 CEF 自绘，保留雷达和准星
local NATIVE_HUD_HIDDEN = {
    'health',
    'armour',
    'weapon',
    'ammo',
    'money',
    'wanted',
    'area_name',
    'clock',
    'vehicle_name',
    'breath',
}

local function setNativeHudVisible(visible)
    for _, component in ipairs(NATIVE_HUD_HIDDEN) do
        setPlayerHudComponentVisible(component, visible)
    end
end

-- ---------------------------------------------------------------------------
-- 与页面通信
-- ---------------------------------------------------------------------------

local function callJs(name, ...)
    if not browser or not browserReady then
        return false
    end

    local args = {}
    for i = 1, select('#', ...) do
        local value = select(i, ...)
        if type(value) == 'string' then
            args[#args + 1] = string.format('%q', value)
        else
            args[#args + 1] = tostring(value)
        end
    end

    return executeBrowserJavascript(
        browser,
        ('window.rst && window.rst.%s(%s)'):format(name, table.concat(args, ','))
    )
end

local function dispatch(name, payload)
    return callJs('dispatch', name, toJSON(payload or {}))
end

local function dispatchRaw(name, json)
    return callJs('dispatch', name, json or '{}')
end

RST.dispatch = dispatch

-- ---------------------------------------------------------------------------
-- 音效
-- ---------------------------------------------------------------------------

local SOUND_FILES = {
    click = 'sounds/click.wav',
    confirm = 'sounds/confirm.wav',
}

local lastSound

local function playUiSound(name)
    local path = SOUND_FILES[name]
    if not path then
        return
    end

    if lastSound and isElement(lastSound) then
        destroyElement(lastSound)
        lastSound = nil
    end

    local sound = playSound(path, false)
    if sound then
        setSoundVolume(sound, 0.55)
        lastSound = sound
    end
end

-- ---------------------------------------------------------------------------
-- 输入 / 交互状态
-- ---------------------------------------------------------------------------

local function setInteractive(enabled)
    enabled = enabled == true
    if enabled == interactive then
        return
    end

    if not enabled and RST.stopRewind then
        RST.stopRewind()
    end

    interactive = enabled
    RST.interactive = enabled

    showCursor(enabled)
    guiSetInputEnabled(enabled)
    toggleAllControls(not enabled, true, false)

    if browserReady then
        if enabled then
            focusBrowser(browser)
        else
            focusBrowser(nil)
        end
    end
end

local function applyInteractive()
    setInteractive(phase ~= 'playing' or menuOpen or chatOpen or helpOpen or voteActive)
end

-- ---------------------------------------------------------------------------
-- 观战相机
-- ---------------------------------------------------------------------------

local function setSpectateName(name)
    name = name or ''
    if spectateName == name then
        return
    end
    spectateName = name
    dispatch('spectate', { name = name })
end

local function stopSpectate()
    if spectateTimer then
        killTimer(spectateTimer)
        spectateTimer = nil
    end
    spectateTarget = nil
    setSpectateName('')
end

local function getSpectatePlayers()
    local dimension = getElementDimension(localPlayer)
    local players = {}

    for _, player in ipairs(getElementsByType('player')) do
        if
            player ~= localPlayer
            and getElementDimension(player) == dimension
            and getElementHealth(player) > 0
        then
            players[#players + 1] = player
        end
    end

    -- 固定排序，保证左右键循环顺序稳定
    table.sort(players, function(a, b)
        return (getPlayerName(a) or '') < (getPlayerName(b) or '')
    end)

    return players
end

local function setSpectateTarget(target)
    spectateTarget = target
    if isElement(target) then
        setCameraTarget(target)
        setSpectateName(getPlayerName(target) or '')
    else
        setSpectateName('')
    end
end

local function updateSpectateTarget()
    if mode ~= 'spectating' or phase ~= 'playing' then
        return
    end

    local players = getSpectatePlayers()
    if #players == 0 then
        spectateTarget = nil
        setSpectateName('')
        return
    end

    local valid = false
    if spectateTarget and isElement(spectateTarget) then
        for _, player in ipairs(players) do
            if player == spectateTarget then
                valid = true
                break
            end
        end
    end

    if not valid then
        spectateTarget = players[1]
    end

    setCameraTarget(spectateTarget)
    setSpectateName(getPlayerName(spectateTarget) or '')
end

local function startSpectate()
    updateSpectateTarget()

    if not spectateTimer then
        spectateTimer = setTimer(function()
            if phase ~= 'playing' or mode ~= 'spectating' then
                stopSpectate()
                return
            end
            updateSpectateTarget()
        end, 2000, 0)
    end
end

local function switchSpectate(direction)
    if mode ~= 'spectating' or phase ~= 'playing' then
        return
    end

    local players = getSpectatePlayers()
    if #players == 0 then
        return
    end

    local current = 0
    for index, player in ipairs(players) do
        if player == spectateTarget then
            current = index
            break
        end
    end

    local targetIndex
    if current == 0 then
        targetIndex = direction > 0 and 1 or #players
    else
        targetIndex = current + direction
        if targetIndex > #players then
            targetIndex = 1
        elseif targetIndex < 1 then
            targetIndex = #players
        end
    end

    setSpectateTarget(players[targetIndex])
end

-- ---------------------------------------------------------------------------
-- 状态机
-- ---------------------------------------------------------------------------

local function applyState(state)
    local previousPhase = phase
    local previousVote = voteActive

    phase = state.phase or 'auth'
    mode = (state.me and state.me.mode) or 'playing'
    voteActive = type(state.vote) == 'table' and state.vote.active == true

    RST.phase = phase
    RST.mode = mode
    RST.voteActive = voteActive

    if phase ~= 'playing' and menuOpen then
        menuOpen = false
        RST.menuOpen = false
        dispatch('menu', { open = false })
    end

    if chatOpen and (phase ~= 'playing' or voteActive) then
        chatOpen = false
        RST.chatOpen = false
        dispatch('chat', { open = false })
    end

    if helpOpen and (phase ~= 'playing' or voteActive) then
        helpOpen = false
        RST.helpOpen = false
        dispatch('help', { open = false })
    end

    if phase ~= 'playing' and RST.countdownActive then
        RST.countdownActive = false
        if countdownTimer then
            killTimer(countdownTimer)
            countdownTimer = nil
        end
        dispatch('countdown', { active = false })
    end

    if phase == 'playing' and mode == 'spectating' then
        startSpectate()
    else
        stopSpectate()
    end

    applyInteractive()

    if phase == 'playing' and mode == 'playing' and getElementHealth(localPlayer) > 0 then
        setCameraTarget(localPlayer)
        fadeCamera(true)
    end

    if previousPhase ~= phase or (not previousVote and voteActive) then
        playUiSound('confirm')
    end
end

local function setChatOpen(open)
    open = open == true
    if open == chatOpen then
        return
    end
    if open and (phase ~= 'playing' or menuOpen or voteActive) then
        return
    end

    chatOpen = open
    RST.chatOpen = open
    dispatch('chat', { open = open })
    applyInteractive()
    playUiSound('click')
end

local function setHelpOpen(open)
    open = open == true
    if open == helpOpen then
        return
    end
    if open and (phase ~= 'playing' or voteActive) then
        return
    end

    helpOpen = open
    RST.helpOpen = open
    dispatch('help', { open = open })
    applyInteractive()
    playUiSound('click')
end

local function setMenuOpen(open)
    open = open == true
    if open == menuOpen then
        return
    end
    if open and phase ~= 'playing' then
        return
    end
    if open and chatOpen then
        setChatOpen(false)
    end
    if open and helpOpen then
        setHelpOpen(false)
    end

    menuOpen = open
    RST.menuOpen = open
    dispatch('menu', { open = open })
    applyInteractive()
    playUiSound('click')
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

local function render()
    if not browserReady then
        return
    end

    local width, height = guiGetScreenSize()
    if width > 0 and height > 0 and (width ~= screenW or height ~= screenH) then
        screenW, screenH = width, height
        resizeBrowser(browser, screenW, screenH)
    end

    if RST.isRewinding and RST.isRewinding() then
        dxDrawRectangle(0, 0, screenW, screenH, tocolor(70, 140, 255, 45))
    end

    dxDrawImage(0, 0, screenW, screenH, browser, 0, 0, 0, tocolor(255, 255, 255, 255), false)
end

-- ---------------------------------------------------------------------------
-- 浏览器生命周期
-- ---------------------------------------------------------------------------

local function onBrowserCreated()
    if source ~= browser then
        return
    end

    browserReady = true
    loadBrowserURL(browser, UI_URL)
    addEventHandler('onClientRender', root, render)
    setInteractive(true)
    -- 状态可能在浏览器创建前就已到达，这里补一次聚焦，保证登录框能输入
    if interactive then
        focusBrowser(browser)
    end
end

local function onBrowserLoadingFailed(url, errorCode, errorDescription)
    outputDebugString(
        ('rst_ui: 页面加载失败 %s (%s: %s)'):format(
            tostring(url),
            tostring(errorCode),
            tostring(errorDescription)
        ),
        1
    )
end

local function createUiBrowser()
    screenW, screenH = guiGetScreenSize()
    browser = createBrowser(screenW, screenH, true, true)
    if not browser then
        outputDebugString('rst_ui: createBrowser 失败', 1)
        return
    end

    addEventHandler('onClientBrowserCreated', browser, onBrowserCreated)
    addEventHandler('onClientBrowserLoadingFailed', browser, onBrowserLoadingFailed)
end

-- ---------------------------------------------------------------------------
-- 输入转发
-- ---------------------------------------------------------------------------

addEventHandler('onClientCursorMove', root, function(_, _, absoluteX, absoluteY)
    if interactive and browserReady then
        injectBrowserMouseMove(browser, absoluteX, absoluteY)
    end
end)

addEventHandler('onClientClick', root, function(button, state, absoluteX, absoluteY)
    if not interactive or not browserReady then
        return
    end

    injectBrowserMouseMove(browser, absoluteX, absoluteY)
    if state == 'down' then
        injectBrowserMouseDown(browser, button)
    else
        injectBrowserMouseUp(browser, button)
    end
end)

addEventHandler('onClientMouseWheel', root, function(delta)
    if interactive and browserReady and type(delta) == 'number' then
        injectBrowserMouseWheel(browser, delta)
    end
end)

-- ---------------------------------------------------------------------------
-- 页面事件
-- ---------------------------------------------------------------------------

addEvent('rst:ui:ready', false)
addEvent('rst:ui:action', false)
addEvent('rst:ui:state', true)
addEvent('rst:ui:notice', true)
addEvent('rst:ui:chat', true)
addEvent('rst:ui:countdown', true)

addEventHandler('rst:ui:ready', root, function()
    if cachedState then
        dispatchRaw('state', cachedState)
    end
    triggerServerEvent('rst:ui:requestState', localPlayer)
    applyInteractive()
    if interactive and browserReady then
        focusBrowser(browser)
    end
end)

addEventHandler('rst:ui:action', root, function(json)
    local data = fromJSON(json or '')
    if type(data) ~= 'table' or type(data.action) ~= 'string' then
        return
    end

    if data.action == 'sound' then
        playUiSound(tostring(data.name or 'click'))
    elseif data.action == 'menu:close' then
        setMenuOpen(false)
    elseif data.action == 'chat:close' then
        setChatOpen(false)
    elseif data.action == 'help:open' then
        setHelpOpen(true)
    elseif data.action == 'help:close' then
        setHelpOpen(false)
    elseif data.action == 'devtools' then
        if browser then
            toggleBrowserDevTools(browser)
        end
    else
        triggerServerEvent('rst:ui:action', localPlayer, json)
    end
end)

addEventHandler('rst:ui:state', root, function(json)
    if type(json) ~= 'string' then
        return
    end

    cachedState = json
    local state = fromJSON(json)
    if type(state) == 'table' then
        applyState(state)
    end
    dispatchRaw('state', json)
end)

addEventHandler('rst:ui:notice', root, function(text)
    if type(text) == 'string' then
        dispatch('toast', { text = text })
    end
end)

addEventHandler('rst:ui:chat', root, function(json)
    local data = fromJSON(json or '')
    if type(data) == 'table' then
        dispatch('chatMessage', data)
    end
end)

addEventHandler('rst:ui:countdown', root, function(json)
    local data = fromJSON(json or '')
    local seconds = tonumber(data and data.seconds) or 3
    if seconds <= 0 then
        return
    end

    if countdownTimer then
        killTimer(countdownTimer)
        countdownTimer = nil
    end

    RST.countdownActive = true
    dispatch('countdown', { active = true, duration = seconds })

    countdownTimer = setTimer(function()
        countdownTimer = nil
        RST.countdownActive = false
    end, math.floor(seconds * 1000) + 50, 1)
end)

-- 拦截所有原生聊天输出，改由 CEF 渲染
addEventHandler('onClientChatMessage', root, function(text, r, g, b, messageType)
    if type(text) ~= 'string' then
        return
    end

    cancelEvent()

    local cleaned = text:gsub('#%x%x%x%x%x%x', '')
    if #cleaned == 0 then
        return
    end

    dispatch('chatMessage', {
        kind = 'native',
        text = cleaned,
        time = getRealTime().timestamp,
        color = {
            r = math.floor(tonumber(r) or 255),
            g = math.floor(tonumber(g) or 255),
            b = math.floor(tonumber(b) or 255),
        },
        nativeType = tonumber(messageType) or 0,
    })
end)

-- ---------------------------------------------------------------------------
-- 本地玩家状态
-- ---------------------------------------------------------------------------

addEventHandler('onClientPlayerSpawn', localPlayer, function()
    if phase == 'playing' and mode == 'playing' then
        stopSpectate()
        setCameraTarget(localPlayer)
        fadeCamera(true)
        if RST.resetRewind then
            RST.resetRewind()
        end
    end
    setNativeHudVisible(false)
end)

addEventHandler('onClientPlayerWasted', localPlayer, function()
    if RST.stopRewind then
        RST.stopRewind()
    end

    if countdownTimer then
        killTimer(countdownTimer)
        countdownTimer = nil
    end
    if RST.countdownActive then
        RST.countdownActive = false
        dispatch('countdown', { active = false })
    end

    setChatOpen(false)
    setHelpOpen(false)
end)

-- 测试车辆 / 竞速车辆：补满氮气
addEventHandler('onClientPlayerVehicleEnter', localPlayer, function(vehicle)
    if getElementData(vehicle, 'rst:testVehicle') or getElementData(vehicle, 'rst:raceVehicle') then
        setVehicleNitroCount(vehicle, 101)
        setVehicleNitroLevel(vehicle, 1)
    end
end)

-- ---------------------------------------------------------------------------
-- 载具仪表盘数据（10Hz）
-- ---------------------------------------------------------------------------

local vehicleShown = false

setTimer(function()
    if not browserReady then
        return
    end

    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not vehicle or not isElement(vehicle) then
        if vehicleShown then
            vehicleShown = false
            dispatch('vehicle', { active = false })
        end
        return
    end

    local vx, vy, vz = getElementVelocity(vehicle)
    local speed = math.floor(math.sqrt(vx * vx + vy * vy + vz * vz) * 180 + 0.5)

    local health = tonumber(getElementHealth(vehicle)) or 0
    local healthPercent = math.floor(math.max(0, math.min(100, health / 10)))

    local gear = 0
    if getVehicleCurrentGear then
        local ok, value = pcall(getVehicleCurrentGear, vehicle)
        if ok and tonumber(value) then
            gear = math.floor(tonumber(value))
        end
    end

    local hasNitro = false
    local nitroPercent = 0
    local nitroLevel = getVehicleNitroLevel(vehicle)
    if type(nitroLevel) == 'number' then
        hasNitro = true
        nitroPercent = math.floor(math.max(0, math.min(1, nitroLevel)) * 100)
    end

    local nitroCount = 0
    local nitroInfinite = false
    local count = getVehicleNitroCount(vehicle)
    if type(count) == 'number' and count > 0 then
        if count >= 101 then
            nitroInfinite = true
        else
            nitroCount = count
        end
    end

    local nitroActive = false
    if isVehicleNitroActivated then
        nitroActive = isVehicleNitroActivated(vehicle) == true
    end

    local nitroRecharging = false
    if isVehicleNitroRecharging then
        nitroRecharging = isVehicleNitroRecharging(vehicle) == true
    end

    vehicleShown = true
    dispatch('vehicle', {
        active = true,
        name = getVehicleNameFromModel(getElementModel(vehicle)) or '车辆',
        speed = speed,
        gear = gear,
        healthPercent = healthPercent,
        nitroPercent = nitroPercent,
        nitroCount = nitroCount,
        nitroInfinite = nitroInfinite,
        nitroActive = nitroActive,
        nitroRecharging = nitroRecharging,
        hasNitro = hasNitro,
    })
end, 100, 0)

-- ---------------------------------------------------------------------------
-- 入口 / 退出
-- ---------------------------------------------------------------------------

bindKey('F2', 'down', function()
    if phase ~= 'playing' then
        return
    end
    setMenuOpen(not menuOpen)
end)

bindKey('T', 'down', function()
    if chatOpen then
        return
    end
    if phase ~= 'playing' or menuOpen or voteActive or helpOpen then
        return
    end
    setChatOpen(true)
end)

-- 观战：左键下一位、右键上一位
bindKey('mouse1', 'down', function()
    if phase ~= 'playing' or mode ~= 'spectating' or interactive then
        return
    end
    switchSpectate(1)
end)

bindKey('mouse2', 'down', function()
    if phase ~= 'playing' or mode ~= 'spectating' or interactive then
        return
    end
    switchSpectate(-1)
end)

bindKey('F1', 'down', function()
    if phase ~= 'playing' then
        return
    end
    if helpOpen then
        setHelpOpen(false)
        return
    end
    if menuOpen then
        setMenuOpen(false)
    end
    if chatOpen then
        setChatOpen(false)
    end
    setHelpOpen(true)
end)

addCommandHandler('ui', function()
    if phase ~= 'playing' then
        outputChatBox('rst: 选择舞台之后才能打开菜单')
        return
    end
    setMenuOpen(not menuOpen)
end)

addEventHandler('onClientResourceStop', resourceRoot, function()
    if RST.stopRewind then
        RST.stopRewind()
    end

    if chatOpen then
        chatOpen = false
        dispatch('chat', { open = false })
    end

    if helpOpen then
        helpOpen = false
        dispatch('help', { open = false })
    end

    if countdownTimer then
        killTimer(countdownTimer)
        countdownTimer = nil
    end

    stopSpectate()
    showCursor(false)
    guiSetInputEnabled(false)
    toggleAllControls(true, true, false)
    showChat(true, false)
    setNativeHudVisible(true)

    if browser and isElement(browser) then
        destroyElement(browser)
    end
    removeEventHandler('onClientRender', root, render)
end)

-- 用 CEF 聊天替代原生聊天：隐藏原生聊天并屏蔽原生输入
showChat(false, true)

-- 隐藏原生血条 / 武器等 HUD，保留雷达和准星
setNativeHudVisible(false)

createUiBrowser()
