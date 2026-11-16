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
local pageReady = false
local pendingDispatches = {}
local screenW, screenH = guiGetScreenSize()

local phase = 'auth'
local mode = 'playing'
local menuOpen = false
local chatOpen = false
local mapDetailsOpen = false
local mapPoolOpen = false
local recordsOpen = false
local scoreboardOpen = false
local scoreboardTimer = nil
local helpOpen = false
local voteActive = false
local voteForced = false
local voteUiOpen = false
local modeVoteActive = false
local modeVoteUiOpen = false
local readyWaiting = false
local interactive = false
local setSpawnControlLock
local cachedState = nil
local spectateName = ''
local countdownTimer = nil
local countdownVehicle = nil
local controlLocked = false
local cursorAlways = false
local freeCursor = false
local hudHidden = false
local chatSuppressed = false
local chatVisible = true
local radarVisible = true
local crosshairVisible = true
local nametagsVisible = true
local devtoolsOpen = false
local lastCursorToggleAt = 0

RST = {
    phase = phase,
    mode = mode,
    interactive = false,
    menuOpen = false,
    chatOpen = false,
    helpOpen = false,
    voteActive = false,
    voteForced = false,
    voteUiOpen = false,
    modeVoteActive = false,
    modeVoteUiOpen = false,
    countdownActive = false,
    readyWaiting = false,
    rewindLives = nil,
    finished = false,
    raceFinal = false,
    gameMode = 'training',
    mapId = nil,
    roomId = nil,
    warpBusy = false,
    warpHolding = false,
}

-- 解除飞机 / 直升机 / 喷气背包的默认高度上限。
-- 地图 resource 启动后可能会重新设置，所以地图开始时再应用一次。
local FLIGHT_MAX_HEIGHT = 100000

local function applyFlightHeightLimits()
    pcall(setAircraftMaxHeight, FLIGHT_MAX_HEIGHT)
    pcall(setJetpackMaxHeight, FLIGHT_MAX_HEIGHT)
end

applyFlightHeightLimits()

addEventHandler('onClientResourceStart', root, function(started)
    if started == resourceRoot then
        return
    end
    -- 地图启动后可能重新设置高度上限，延迟再恢复一次
    setTimer(applyFlightHeightLimits, 100, 1)
end)

function RST.isGameplayActive()
    return RST.phase == 'playing'
        and RST.mode == 'playing'
        and not RST.interactive
        and not RST.voteActive
        and not RST.countdownActive
        and not RST.readyWaiting
        and not RST.finished
        and not RST.raceFinal
end

function RST.canRewind()
    return RST.isGameplayActive()
        and not RST.warpBusy
        and not RST.warpHolding
        and getElementHealth(localPlayer) > 0
        and (RST.rewindLives == nil or RST.rewindLives > 0)
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

-- 确保其他玩家头顶名字可见；仅影响当前客户端
local function applyPlayerNametags()
    for _, player in ipairs(getElementsByType('player')) do
        pcall(setPlayerNametagShowing, player, nametagsVisible)
    end
end

local function applyVisibility()
    local nativeChatVisible = not hudHidden and chatVisible and not chatSuppressed
    pcall(showChat, nativeChatVisible, not nativeChatVisible)
    pcall(setPlayerHudComponentVisible, 'radar', not hudHidden and radarVisible)
    pcall(setPlayerHudComponentVisible, 'crosshair', not hudHidden and crosshairVisible)
    applyPlayerNametags()
end

-- 关闭速度/加速度引起的原生动态模糊
local function disableMotionBlur()
    pcall(setBlurLevel, 0)
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

    local code = ('window.rst && window.rst.%s(%s)'):format(name, table.concat(args, ','))
    return executeBrowserJavascript(browser, code)
end

local function dispatch(name, payload)
    local json = toJSON(payload or {})
    if not browserReady or not pageReady then
        pendingDispatches[#pendingDispatches + 1] = { name = name, json = json }
        if #pendingDispatches > 200 then
            table.remove(pendingDispatches, 1)
        end
        return true
    end
    return callJs('dispatch', name, json)
end

local function dispatchRaw(name, json)
    json = json or '{}'
    if not browserReady or not pageReady then
        if name ~= 'state' then
            pendingDispatches[#pendingDispatches + 1] = { name = name, json = json }
            if #pendingDispatches > 200 then
                table.remove(pendingDispatches, 1)
            end
        end
        return true
    end
    return callJs('dispatch', name, json)
end

local function flushPendingDispatches()
    if not browserReady or not pageReady or #pendingDispatches == 0 then
        return
    end
    local queued = pendingDispatches
    pendingDispatches = {}
    for _, item in ipairs(queued) do
        callJs('dispatch', item.name, item.json)
    end
end

RST.dispatch = dispatch

local function requestScoreboard()
    triggerServerEvent('rst:scoreboard:request', localPlayer)
end

local function closeScoreboard()
    if not scoreboardOpen then
        return
    end
    scoreboardOpen = false
    if scoreboardTimer then
        killTimer(scoreboardTimer)
        scoreboardTimer = nil
    end
    dispatch('scoreboard', { open = false })
end

local function openScoreboard()
    if scoreboardOpen or phase ~= 'playing' or menuOpen or voteForced or readyWaiting or helpOpen then
        return
    end
    scoreboardOpen = true
    dispatch('scoreboard', { open = true })
    requestScoreboard()
    scoreboardTimer = setTimer(function()
        if scoreboardOpen then
            requestScoreboard()
        end
    end, 1000, 0)
end

-- ---------------------------------------------------------------------------
-- 音效
-- ---------------------------------------------------------------------------

local SOUND_FILES = {
    click = 'sounds/click.wav',
    confirm = 'sounds/confirm.wav',
    countdown = 'sounds/countdown.wav',
    go = 'sounds/go.wav',
    finish = 'sounds/finish.wav',
    fail = 'sounds/fail.wav',
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

local function applyInputState(enabled)
    showCursor(enabled)
    guiSetInputEnabled(enabled)
    toggleAllControls(not enabled, true, false)

    if browserReady then
        if enabled and not chatOpen then
            focusBrowser(browser)
        else
            focusBrowser(nil)
        end
    end
end

local function setInteractive(enabled)
    enabled = enabled == true

    if enabled == interactive then
        -- 状态没有变化，也要把输入副作用重新落到当前帧。
        -- 例如观战结束时 stopSpectate() 会 showCursor(false)，随后 interactive 仍为 true，
        -- 只 return 会让菜单开着但鼠标不可见。
        applyInputState(enabled)
        return
    end

    if not enabled and RST.stopRewind then
        RST.stopRewind()
    end
    if enabled and RST.stopWarp then
        RST.stopWarp()
    end

    interactive = enabled
    RST.interactive = enabled
    applyInputState(enabled)
end

local function isForcedCursor()
    return phase ~= 'playing'
        or menuOpen
        or chatOpen
        or mapDetailsOpen
        or mapPoolOpen
        or recordsOpen
        or helpOpen
        or voteForced
        or voteUiOpen
        or modeVoteUiOpen
        or readyWaiting
end

local function updateCursor()
    local forced = isForcedCursor()
    if forced or RST.countdownActive then
        freeCursor = false
    end

    local optional = phase == 'playing' and not RST.countdownActive and not forced
    local visible = forced or (optional and (cursorAlways or freeCursor))

    setInteractive(visible)
    if controlLocked then
        setSpawnControlLock(true)
    end
    dispatch('cursor', {
        mode = cursorAlways and 'always' or 'auto',
        visible = visible,
        forced = forced,
        free = freeCursor,
    })
end

local function toggleCursorVisibility()
    local nowTick = getTickCount()
    if nowTick - lastCursorToggleAt < 200 then
        return
    end
    lastCursorToggleAt = nowTick

    if cursorAlways then
        cursorAlways = false
        freeCursor = false
    else
        freeCursor = not freeCursor
    end
    updateCursor()
end

local function applyInteractive()
    updateCursor()
end

-- 玩家自发投票：F3 打开 / 关闭投票面板；强制投票由 VoteView 自动接管，不走这里
local function setVoteUi(open)
    open = open == true
    if open and (not voteActive or voteForced) then
        open = false
    end
    if open == voteUiOpen then
        dispatch('voteui', { open = voteUiOpen })
        return
    end
    voteUiOpen = open
    RST.voteUiOpen = open
    dispatch('voteui', { open = open })
    applyInteractive()
end

-- 模式投票：和自发换图投票一样，F4 手动打开，不接管跑图
local function setModeVoteUi(open)
    open = open == true
    if open and not modeVoteActive then
        open = false
    end
    if open == modeVoteUiOpen then
        dispatch('modevoteui', { open = modeVoteUiOpen })
        return
    end
    modeVoteUiOpen = open
    RST.modeVoteUiOpen = open
    dispatch('modevoteui', { open = open })
    applyInteractive()
end

-- 倒计时/准备阶段双保险：服务端冻结之外，本地也锁输入和载具。
-- 服务端 freeze 偶尔会被载具同步覆盖，单靠服务端会出现倒计时能挪车。
setSpawnControlLock = function(locked)
    if not locked and not controlLocked then
        return
    end
    controlLocked = locked

    pcall(toggleAllControls, not locked, true, false)

    if locked then
        countdownVehicle = getPedOccupiedVehicle(localPlayer)
        if isElement(countdownVehicle) then
            setElementFrozen(countdownVehicle, true)
            setElementVelocity(countdownVehicle, 0, 0, 0)
        end
        if isElement(localPlayer) then
            setElementFrozen(localPlayer, true)
        end
    else
        if isElement(countdownVehicle) then
            setElementFrozen(countdownVehicle, false)
        end
        countdownVehicle = nil
        if isElement(localPlayer) then
            setElementFrozen(localPlayer, false)
        end
    end
end

-- ---------------------------------------------------------------------------
-- 观战自由视角 / 玩家车辆跟踪
-- ---------------------------------------------------------------------------

local freecamActive = false
local freecamX, freecamY, freecamZ = 0, 0, 0
local freecamYaw, freecamPitch = 0, 0
local freecamLastTick = 0
local freecamVehicle = nil
local trackingTarget = nil
local mouseRecentering = false
local mouseLookReady = false
local mouseResumeTimer = nil
local mouseLastX, mouseLastY = 0, 0
local armMouseLook

local function setSpectateName(name)
    name = name or ''
    if spectateName == name then
        return
    end
    spectateName = name
    dispatch('spectate', { name = name })
end

local function spectatePlayers()
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
    table.sort(players, function(a, b)
        return (getPlayerName(a) or '') < (getPlayerName(b) or '')
    end)
    return players
end

local function captureCamera()
    local px, py, pz, tx, ty, tz = getCameraMatrix()
    if not px or not tx then
        px, py, pz = getElementPosition(localPlayer)
        tx, ty, tz = px, py, pz + 1
    end

    freecamX, freecamY, freecamZ = px, py, pz + 2.5
    local dx, dy, dz = tx - px, ty - py, tz - freecamZ
    if math.abs(dx) + math.abs(dy) > 0.001 then
        freecamYaw = math.deg(math.atan2(dy, dx))
    else
        freecamYaw = 0
    end
    freecamPitch = math.max(-85, math.min(85, math.deg(math.atan2(dz, math.sqrt(dx * dx + dy * dy)))))
    freecamLastTick = getTickCount()
end

local function detachTracking()
    if not trackingTarget then
        return
    end
    trackingTarget = nil
    captureCamera()
    setSpectateName('自由视角')
    armMouseLook()
end

local function cycleSpectate(direction)
    if not freecamActive or interactive or chatOpen or menuOpen then
        return
    end

    local players = spectatePlayers()
    if #players == 0 then
        setSpectateName('等待其他玩家')
        return
    end

    local index = 0
    if trackingTarget then
        for i, player in ipairs(players) do
            if player == trackingTarget then
                index = i
                break
            end
        end
    end
    index = index + direction
    if index > #players then
        index = 1
    elseif index < 1 then
        index = #players
    end

    trackingTarget = players[index]
    local vehicle = getPedOccupiedVehicle(trackingTarget)
    setCameraTarget(vehicle or trackingTarget)
    setSpectateName((getPlayerName(trackingTarget) or '玩家') .. (vehicle and ' · 车辆' or ' · 角色'))
end

local function toggleSpectateView()
    if not freecamActive or interactive or chatOpen or menuOpen then
        return
    end
    if trackingTarget then
        detachTracking()
    else
        cycleSpectate(1)
    end
end

local function freecamPaused()
    return interactive
        or chatOpen
        or menuOpen
        or isMTAWindowActive()
        or isMainMenuActive()
        or isConsoleActive()
        or isChatBoxInputActive()
end

local function applyFreecamCamera()
    local yaw = math.rad(freecamYaw)
    local pitch = math.rad(freecamPitch)
    local fx = math.cos(pitch) * math.cos(yaw)
    local fy = math.cos(pitch) * math.sin(yaw)
    local fz = math.sin(pitch)
    setCameraMatrix(freecamX, freecamY, freecamZ, freecamX + fx * 8, freecamY + fy * 8, freecamZ + fz * 8)
end

armMouseLook = function()
    mouseLookReady = false
    mouseRecentering = true
    if mouseResumeTimer then
        killTimer(mouseResumeTimer)
        mouseResumeTimer = nil
    end

    local width, height = guiGetScreenSize()
    local cx, cy = width / 2, height / 2
    mouseLastX, mouseLastY = cx, cy
    setCursorPosition(cx, cy)
    mouseResumeTimer = setTimer(function()
        mouseResumeTimer = nil
        setCursorPosition(cx, cy)
        mouseLastX, mouseLastY = cx, cy
        mouseRecentering = false
        if freecamActive and not freecamPaused() then
            mouseLookReady = true
        end
    end, 150, 1)
end

local function onSpectateMouse(_, _, absoluteX, absoluteY)
    if not freecamActive or trackingTarget or freecamPaused() then
        return
    end
    if not mouseLookReady then
        return
    end

    if mouseRecentering then
        mouseLastX, mouseLastY = absoluteX, absoluteY
        mouseRecentering = false
        return
    end

    local dx, dy = absoluteX - mouseLastX, absoluteY - mouseLastY
    mouseLastX, mouseLastY = absoluteX, absoluteY
    if dx == 0 and dy == 0 then
        return
    end

    -- 鼠标向右应向右转，纵向只影响 pitch
    freecamYaw = freecamYaw - dx * 0.12
    freecamPitch = math.max(-85, math.min(85, freecamPitch - dy * 0.12))

    -- 不再每次事件都强制回中；只有接近屏幕边缘才回中，避免 30ms 节流造成低帧感
    local width, height = guiGetScreenSize()
    local margin = 48
    if absoluteX < margin or absoluteX > width - margin
        or absoluteY < margin or absoluteY > height - margin
    then
        local cx, cy = width / 2, height / 2
        setCursorPosition(cx, cy)
        mouseLastX, mouseLastY = cx, cy
        mouseRecentering = true
    end
end

local function freecamRender()
    if not freecamActive then
        return
    end

    if interactive or chatOpen or menuOpen or isMTAWindowActive() or isMainMenuActive() or isConsoleActive() then
        mouseLookReady = false
        mouseRecentering = false
        if mouseResumeTimer then
            killTimer(mouseResumeTimer)
            mouseResumeTimer = nil
        end
        -- 菜单期间保持当前镜头，避免原生相机被鼠标带着转
        if trackingTarget then
            local px, py, pz, tx, ty, tz = getCameraMatrix()
            if px and tx then
                setCameraMatrix(px, py, pz, tx, ty, tz)
            end
        else
            applyFreecamCamera()
        end
        setCursorAlpha(255)
        return
    end

    showCursor(true)
    setCursorAlpha(0)
    if not mouseLookReady and not mouseResumeTimer then
        armMouseLook()
    end

    if trackingTarget then
        if not isElement(trackingTarget) or getElementHealth(trackingTarget) <= 0 then
            detachTracking()
            return
        end

        if
            getKeyState('w')
            or getKeyState('a')
            or getKeyState('s')
            or getKeyState('d')
            or getKeyState('space')
            or getKeyState('lctrl')
        then
            detachTracking()
        else
            local vehicle = getPedOccupiedVehicle(trackingTarget)
            setCameraTarget(vehicle or trackingTarget)
            return
        end
    end

    local now = getTickCount()
    local dt = math.min(0.1, math.max(0, (now - freecamLastTick) / 1000))
    freecamLastTick = now

    local yaw = math.rad(freecamYaw)
    local pitch = math.rad(freecamPitch)
    local fx = math.cos(pitch) * math.cos(yaw)
    local fy = math.cos(pitch) * math.sin(yaw)
    local fz = math.sin(pitch)
    local rx, ry = -math.sin(yaw), math.cos(yaw)

    local speed = (getKeyState('lshift') and 55 or 24) * dt
    if getKeyState('w') then
        freecamX, freecamY, freecamZ = freecamX + fx * speed, freecamY + fy * speed, freecamZ + fz * speed
    end
    if getKeyState('s') then
        freecamX, freecamY, freecamZ = freecamX - fx * speed, freecamY - fy * speed, freecamZ - fz * speed
    end
    -- 屏幕右方向：修正 A/D 反向
    if getKeyState('a') then
        freecamX, freecamY = freecamX + rx * speed, freecamY + ry * speed
    end
    if getKeyState('d') then
        freecamX, freecamY = freecamX - rx * speed, freecamY - ry * speed
    end
    if getKeyState('space') then
        freecamZ = freecamZ + speed
    end
    if getKeyState('lctrl') then
        freecamZ = freecamZ - speed
    end

    applyFreecamCamera()
end

local function startSpectate()
    if freecamActive then
        return
    end

    freecamActive = true
    trackingTarget = nil
    mouseLookReady = false
    freecamVehicle = getPedOccupiedVehicle(localPlayer)
    captureCamera()

    local width, height = guiGetScreenSize()
    showCursor(true)
    setCursorAlpha(0)
    setCursorPosition(width / 2, height / 2)

    if isElement(localPlayer) then
        setElementAlpha(localPlayer, 0)
        setElementFrozen(localPlayer, true)
    end
    if isElement(freecamVehicle) then
        setElementAlpha(freecamVehicle, 0)
    end

    setSpectateName('自由视角')
    addEventHandler('onClientCursorMove', root, onSpectateMouse)
    addEventHandler('onClientRender', root, freecamRender)
    armMouseLook()
end

local function stopSpectate()
    if not freecamActive then
        return
    end

    freecamActive = false
    trackingTarget = nil
    mouseLookReady = false
    mouseRecentering = false
    if mouseResumeTimer then
        killTimer(mouseResumeTimer)
        mouseResumeTimer = nil
    end
    removeEventHandler('onClientCursorMove', root, onSpectateMouse)
    removeEventHandler('onClientRender', root, freecamRender)

    if isElement(freecamVehicle) then
        setElementAlpha(freecamVehicle, 255)
    end
    freecamVehicle = nil
    if isElement(localPlayer) then
        setElementAlpha(localPlayer, 255)
        setElementFrozen(localPlayer, false)
    end

    setSpectateName('')
    setCursorAlpha(255)
    showCursor(false)
end
-- ---------------------------------------------------------------------------
-- 状态机
-- ---------------------------------------------------------------------------

local function setChatSuppressed(suppressed)
    suppressed = suppressed == true
    if suppressed == chatSuppressed then
        return
    end

    chatSuppressed = suppressed
    applyVisibility()
    if suppressed and chatOpen then
        chatOpen = false
        RST.chatOpen = false
        dispatch('chat', { open = false })
        updateCursor()
    end
end

local function applyState(state)
    local previousPhase = phase
    local previousMode = mode
    local previousVote = voteActive
    local previousVoteUi = voteUiOpen
    local previousModeVote = modeVoteActive
    local previousModeVoteUi = modeVoteUiOpen

    local nextPhase = state.phase
    if nextPhase ~= 'auth' and nextPhase ~= 'stage' and nextPhase ~= 'playing' then
        outputDebugString('[rst_ui] invalid state.phase: ' .. tostring(nextPhase), 1)
        nextPhase = 'auth'
    end

    phase = nextPhase
    mode = (state.me and state.me.mode) or 'playing'
    local voteTable = type(state.vote) == 'table' and state.vote or nil
    local modeVoteTable = type(state.modeVote) == 'table' and state.modeVote or nil
    modeVoteActive = modeVoteTable ~= nil and modeVoteTable.active == true
    voteActive = (voteTable ~= nil and voteTable.active == true) or modeVoteActive
    -- 只有强制换图投票会自动全屏；模式投票和自发换图投票都按 F4 打开
    voteForced = voteTable ~= nil and voteTable.active == true and voteTable.forced ~= false
    if not voteActive or voteForced then
        voteUiOpen = false
    elseif voteTable ~= nil and voteTable.started == true and not previousVote then
        -- 自己发起的投票：直接打开面板，省得再按 F4
        voteUiOpen = true
    end

    if not modeVoteActive then
        modeVoteUiOpen = false
    elseif modeVoteTable.started == true and not previousModeVote then
        modeVoteUiOpen = true
    end

    readyWaiting = type(state.ready) == 'table'
        and state.ready.waiting == true

    RST.phase = phase
    RST.mode = mode
    RST.finished = state.me and state.me.finished == true or false
    RST.raceFinal = state.raceFinal == true
    RST.voteActive = voteActive
    RST.voteForced = voteForced
    RST.voteUiOpen = voteUiOpen
    RST.modeVoteActive = modeVoteActive
    RST.modeVoteUiOpen = modeVoteUiOpen
    RST.readyWaiting = readyWaiting
    RST.rewindLives = tonumber(state.lives)
    if previousVoteUi ~= voteUiOpen then
        dispatch('voteui', { open = voteUiOpen })
    end
    if previousModeVoteUi ~= modeVoteUiOpen then
        dispatch('modevoteui', { open = modeVoteUiOpen })
    end

    local previousMapId = RST.mapId
    local previousRoomId = RST.roomId
    local previousGameMode = RST.gameMode
    RST.gameMode = state.mode == 'competitive' and 'competitive'
        or (state.room and state.room.gameMode == 'competitive' and 'competitive' or 'training')
    RST.mapId = state.room and state.room.mapId or nil
    RST.roomId = state.room and state.room.id or nil
    if RST.clearWarps
        and (RST.mapId ~= previousMapId
            or RST.roomId ~= previousRoomId
            or RST.gameMode ~= previousGameMode)
    then
        RST.clearWarps()
    end

    disableMotionBlur()
    setChatSuppressed(phase ~= 'playing' or voteForced or readyWaiting)
    if (phase ~= 'playing' or voteForced or readyWaiting) and RST.stopWarp then
        RST.stopWarp()
    end
    if scoreboardOpen and (phase ~= 'playing' or voteForced or readyWaiting) then
        closeScoreboard()
    end

    if phase ~= 'playing' and menuOpen then
        menuOpen = false
        RST.menuOpen = false
        dispatch('menu', { open = false })
    end

    if chatOpen and (phase ~= 'playing' or voteForced or readyWaiting) then
        chatOpen = false
        RST.chatOpen = false
        dispatch('chat', { open = false })
    end

    if helpOpen and (phase ~= 'playing' or voteForced) then
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
        setSpawnControlLock(false)
        dispatch('countdown', { active = false })
    end

    if (phase ~= 'playing' or mode == 'spectating') and RST.stopRewind then
        RST.stopRewind()
    end

    if phase == 'playing' and mode == 'spectating' then
        startSpectate()
    else
        stopSpectate()
    end

    applyInteractive()
    setSpawnControlLock(
        phase == 'playing'
        and mode ~= 'spectating'
        and (readyWaiting or RST.countdownActive)
    )

    -- state 每秒推送；只在 phase/mode 真正切换时重置相机，避免把自由视角拉回车后
    if
        phase == 'playing'
        and mode == 'playing'
        and getElementHealth(localPlayer) > 0
        and (previousPhase ~= 'playing' or previousMode ~= 'playing')
    then
        setCameraTarget(localPlayer)
        fadeCamera(true)
    end

    if phase == 'playing' and RST.refreshGhosts then
        local ok, err = pcall(RST.refreshGhosts)
        if not ok then
            outputDebugString('[rst_ui] refreshGhosts failed: ' .. tostring(err), 1)
        end
    end

    if previousPhase ~= phase or (not previousVote and voteActive) then
        playUiSound('confirm')
    end
end
local function syncChatState()
    local active = isChatBoxInputActive() == true
    if active == chatOpen then
        return
    end

    chatOpen = active
    RST.chatOpen = active
    dispatch('chat', { open = active })

    if active then
        focusBrowser(nil)
        showCursor(true)
    elseif interactive then
        focusBrowser(browser)
    else
        focusBrowser(nil)
    end
    updateCursor()
end

local function setHelpOpen(open)    open = open == true
    if open == helpOpen then
        return
    end
    if open and (phase ~= 'playing' or voteForced) then
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
    if open and helpOpen then
        setHelpOpen(false)
    end
    if open and scoreboardOpen then
        closeScoreboard()
    end

    menuOpen = open
    RST.menuOpen = open
    dispatch('menu', { open = open })
    applyInteractive()
    playUiSound('click')
end

-- 统一关闭最上层弹窗：Esc / F1 / F2 / 清除缓存共用，避免每个键各自维护一套顺序
local function closeTopOverlay()
    if scoreboardOpen then
        closeScoreboard()
        return true
    end
    if voteUiOpen then
        setVoteUi(false)
        return true
    end
    if modeVoteUiOpen then
        setModeVoteUi(false)
        return true
    end
    if mapDetailsOpen then
        mapDetailsOpen = false
        dispatch('mapdetails', { open = false })
        applyInteractive()
        return true
    end
    if mapPoolOpen then
        mapPoolOpen = false
        dispatch('mappool', { open = false })
        applyInteractive()
        return true
    end
    if recordsOpen then
        recordsOpen = false
        dispatch('recordsmodal', { open = false })
        applyInteractive()
        return true
    end
    if helpOpen then
        setHelpOpen(false)
        return true
    end
    if menuOpen then
        setMenuOpen(false)
        return true
    end
    return false
end

local function closeAllOverlays()
    while closeTopOverlay() do end
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

local function applyUiScale()
    if not browser or not browserReady then
        return
    end

    executeBrowserJavascript(
        browser,
        ('window.rst && window.rst.setViewportSize && window.rst.setViewportSize(%d, %d)')
            :format(screenW, screenH)
    )
end

local function render()
    if not browserReady then
        return
    end

    local width, height = guiGetScreenSize()
    if width > 0 and height > 0 and (width ~= screenW or height ~= screenH) then
        screenW, screenH = width, height
        resizeBrowser(browser, screenW, screenH)
        applyUiScale()
    end

    syncChatState()

    -- CEF 有时会抢回键盘焦点；非交互状态下立即释放，bindKey 才能收到 F1/F2/T
    if not interactive and browser and isElement(browser) then
        local ok, focused = pcall(isBrowserFocused, browser)
        if ok and focused then
            focusBrowser(nil)
        end
    end

    if RST.isRewinding and RST.isRewinding() then
        dxDrawRectangle(0, 0, screenW, screenH, tocolor(70, 140, 255, 45))
    end

    -- 倒计时/准备阶段每帧压住载具，防止地图脚本或同步把 freeze 状态冲掉
    if controlLocked then
        local vehicle = getPedOccupiedVehicle(localPlayer)
        if isElement(vehicle) then
            setElementVelocity(vehicle, 0, 0, 0)
            if not isElementFrozen(vehicle) then
                setElementFrozen(vehicle, true)
            end
        end
        if isElement(localPlayer) and not isElementFrozen(localPlayer) then
            setElementFrozen(localPlayer, true)
        end
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
    applyInteractive()
    -- 状态可能在浏览器创建前就已到达，这里补一次聚焦，保证登录框能输入
    if interactive then
        focusBrowser(browser)
    end
end

local browserReloads = 0

local function onBrowserLoadingFailed(url, errorCode, errorDescription)
    pageReady = false
    outputDebugString(
        ('rst_ui: 页面加载失败 %s (%s: %s)'):format(
            tostring(url),
            tostring(errorCode),
            tostring(errorDescription)
        ),
        1
    )

    if browserReloads < 2 and browser and isElement(browser) then
        browserReloads = browserReloads + 1
        setTimer(function()
            if browser and isElement(browser) then
                pcall(reloadBrowserPage, browser)
            end
        end, 1000, 1)
        return
    end

    -- 页面彻底失败时回退原生输入/HUD，至少不要黑屏卡死
    setNativeHudVisible(true)
    showChat(true, false)
    showCursor(false)
    if isElement(localPlayer) then
        setElementFrozen(localPlayer, false)
    end
end

local function createUiBrowser()
    screenW, screenH = guiGetScreenSize()
    pcall(setPlayerHudComponentVisible, 'radar', true)
    pcall(setPlayerHudComponentVisible, 'crosshair', true)
    -- 第 4 个参数 = 透明浏览器；HTML body 也是透明，游戏画面才能透出
    browser = createBrowser(screenW, screenH, true, true)
    if not browser then
        outputDebugString('rst_ui: createBrowser 失败', 1)
        setNativeHudVisible(true)
        showChat(true, false)
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

local lastBrowserWheelAt = 0
local function injectBrowserWheel(delta)
    local nowTick = getTickCount()
    if nowTick - lastBrowserWheelAt < 40 then
        return
    end
    lastBrowserWheelAt = nowTick
    if not browser or not browserReady then
        return
    end

    -- 直接滚动 CEF 中当前打开的滚动容器，不依赖浏览器焦点/原生滚轮注入。
    local step = -math.floor(tonumber(delta) or 0) * 48
    executeBrowserJavascript(browser, ([[(function(){
        var step = %d;
        var selectors = [
            '.menu-panel',
            '.vote__options',
            '.competition__body',
            '.map-pool__list',
            '.records__table-wrap',
            '.help__panel'
        ];
        for (var i = 0; i < selectors.length; i++) {
            var element = document.querySelector(selectors[i]);
            if (element && element.scrollHeight > element.clientHeight + 1) {
                element.scrollTop += step;
                return;
            }
        }
    })()]]):format(step))
end

addEventHandler('onClientClick', root, function(button, state, absoluteX, absoluteY)
    if not interactive or not browserReady or chatOpen then
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
        injectBrowserWheel(delta)
    end
end)

-- 部分客户端会把一次滚轮同时上报成 up/down 两个方向；只取这一对里的第一个方向。
local lastWheelDirection = 0
local lastWheelEventAt = 0
local lastF2At = 0
local function handleWheelDirection(direction)
    local nowTick = getTickCount()
    if lastWheelDirection ~= 0
        and direction ~= lastWheelDirection
        and nowTick - lastWheelEventAt < 80
    then
        lastWheelEventAt = nowTick
        return
    end
    lastWheelDirection = direction
    lastWheelEventAt = nowTick
    injectBrowserWheel(direction)
end

local lastScoreboardWheelDirection = 0
local lastScoreboardWheelAt = 0
local function handleScoreboardWheel(direction)
    local nowTick = getTickCount()
    if lastScoreboardWheelDirection ~= 0
        and direction ~= lastScoreboardWheelDirection
        and nowTick - lastScoreboardWheelAt < 80
    then
        lastScoreboardWheelAt = nowTick
        return
    end
    lastScoreboardWheelDirection = direction
    lastScoreboardWheelAt = nowTick
    dispatch('scoreboardScroll', { delta = direction })
end

addEventHandler('onClientKey', root, function(button, press)
    if tostring(button):lower() ~= 'tab' then
        return
    end
    if press then
        if isChatBoxInputActive() or isConsoleActive() or isMTAWindowActive() then
            return
        end
        if phase ~= 'playing' or menuOpen or voteForced or readyWaiting or helpOpen then
            return
        end
        cancelEvent()
        openScoreboard()
    else
        closeScoreboard()
    end
end)

addEventHandler('onClientKey', root, function(button, press)
    if not press or tostring(button):lower() ~= 'escape' then
        return
    end
    if phase ~= 'playing' or isChatBoxInputActive() or isConsoleActive() or isMTAWindowActive() then
        return
    end

    if closeTopOverlay() then
        cancelEvent()
    end
end)

addEventHandler('onClientKey', root, function(button, press)
    if not press or tostring(button):lower() ~= 'f2' then
        return
    end
    if phase ~= 'playing' or isChatBoxInputActive() or isConsoleActive() or isMTAWindowActive() then
        return
    end
    local nowTick = getTickCount()
    if nowTick - lastF2At < 200 then
        return
    end
    lastF2At = nowTick
    cancelEvent()
    if voteForced then
        return
    end
    -- 有弹窗时先关弹窗（地图池 / 排行榜 / 帮助…），没有才打开菜单
    if closeTopOverlay() then
        return
    end
    setMenuOpen(true)
end)

-- F4：换图投票面板。玩家自发的投票不弹全屏，按 F4 才打开（F3 已经被自由鼠标占用）
addEventHandler('onClientKey', root, function(button, press)
    if not press or tostring(button):lower() ~= 'f4' then
        return
    end
    if phase ~= 'playing' or isChatBoxInputActive() or isConsoleActive() or isMTAWindowActive() then
        return
    end
    cancelEvent()
    if not voteActive then
        dispatch('toast', { text = '当前没有投票' })
        return
    end
    if voteForced then
        return
    end
    if modeVoteActive then
        setModeVoteUi(not modeVoteUiOpen)
    else
        setVoteUi(not voteUiOpen)
    end
end)

-- CEF 是 dxDrawImage 绘制的，不是 GUI 元素，onClientMouseWheel 在部分客户端不会触发；
-- 用 onClientKey 的滚轮事件补充。
addEventHandler('onClientKey', root, function(button, press)
    if scoreboardOpen then
        if press and button == 'mouse_wheel_up' then
            handleScoreboardWheel(1)
            cancelEvent()
        elseif press and button == 'mouse_wheel_down' then
            handleScoreboardWheel(-1)
            cancelEvent()
        end
        return
    end

    if not press or not interactive or not browserReady then
        return
    end
    if button == 'mouse_wheel_up' then
        handleWheelDirection(1)
        cancelEvent()
    elseif button == 'mouse_wheel_down' then
        handleWheelDirection(-1)
        cancelEvent()
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
addEvent('rst:ui:maps', true)
addEvent('rst:ui:mapdetail', true)
addEvent('rst:ui:records', true)
addEvent('rst:scoreboard:data', true)
addEvent('rst:ui:countdown', true)
addEvent('rst:ui:lives', true)

addEventHandler('rst:ui:ready', root, function()
    pageReady = true
    if type(cachedState) == 'string' and #cachedState > 2 then
        dispatchRaw('state', cachedState)
    end
    flushPendingDispatches()
    applyUiScale()
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
    elseif data.action == 'voteui' then
        setVoteUi(data.open == true)
    elseif data.action == 'modevoteui' then
        setModeVoteUi(data.open == true)
    elseif data.action == 'mapdetails' then
        mapDetailsOpen = data.open == true
        applyInteractive()
    elseif data.action == 'mappool' then
        mapPoolOpen = data.open == true
        applyInteractive()
    elseif data.action == 'recordsmodal' then
        recordsOpen = data.open == true
        applyInteractive()
    elseif data.action == 'nametags:set' then
        nametagsVisible = data.visible == true
        applyVisibility()
    elseif data.action == 'visibility:set' then
        local key = tostring(data.key or '')
        local visible = data.visible == true
        if key == 'chat' then
            chatVisible = visible
        elseif key == 'radar' then
            radarVisible = visible
        elseif key == 'crosshair' then
            crosshairVisible = visible
        elseif key == 'nametags' then
            nametagsVisible = visible
        end
        applyVisibility()
    elseif data.action == 'visibility:load' then
        hudHidden = false
        chatVisible = data.chat ~= false
        radarVisible = data.radar ~= false
        crosshairVisible = data.crosshair ~= false
        nametagsVisible = data.nametags ~= false
        applyVisibility()
    elseif data.action == 'visibility:master' then
        hudHidden = data.visible ~= true
        applyVisibility()
    elseif data.action == 'hud:toggle' then
        hudHidden = not hudHidden
        applyVisibility()
    elseif data.action == 'menu:close' then
        setMenuOpen(false)
    elseif data.action == 'menu:open' then
        setMenuOpen(true)
    elseif data.action == 'help:open' then
        setHelpOpen(true)
    elseif data.action == 'help:close' then
        setHelpOpen(false)
    elseif data.action == 'cursor:set' then
        cursorAlways = data.mode == 'always'
        freeCursor = false
        updateCursor()
    elseif data.action == 'cursor:toggle' then
        if phase == 'playing' and not isForcedCursor() and not RST.countdownActive then
            toggleCursorVisibility()
        end
    elseif data.action == 'cache:clear' then
        closeAllOverlays()
        pageReady = false

        local reloaded = false
        if browser and isElement(browser) then
            local ok, result = pcall(reloadBrowserPage, browser, true)
            reloaded = ok and result == true
        end

        if not reloaded then
            pageReady = true
            dispatch('toast', { text = '清除缓存失败，请重试' })
        else
            dispatch('toast', { text = '已清除浏览器缓存，界面重新加载' })
        end
    elseif data.action == 'devtools' then
        if browser then
            if not devtoolsOpen then
                pcall(setDevelopmentMode, true, true)
            end
            devtoolsOpen = not devtoolsOpen
            local ok = pcall(toggleBrowserDevTools, browser, devtoolsOpen)
            if not ok then
                outputDebugString('[rst_ui] toggleBrowserDevTools failed', 1)
            end
            if not devtoolsOpen then
                pcall(setDevelopmentMode, false, false)
            end
        end
    elseif data.action == 'warp:save' then
        if menuOpen then
            setMenuOpen(false)
        end
        if RST.saveWarp then
            RST.saveWarp()
        end
    elseif data.action == 'warp:latest' then
        if menuOpen then
            setMenuOpen(false)
        end
        if RST.goLatestWarp then
            RST.goLatestWarp()
        end
    elseif data.action == 'warp:go' then
        if menuOpen then
            setMenuOpen(false)
        end
        if RST.goWarp then
            RST.goWarp(tonumber(data.id))
        end
    elseif data.action == 'warp:delete' then
        if RST.deleteWarp then
            RST.deleteWarp(tonumber(data.id))
        end
    else
        triggerServerEvent('rst:ui:action', localPlayer, json)
    end
end)

addEventHandler('rst:ui:state', root, function(json)
    if type(json) ~= 'string' or #json < 2 then
        return
    end

    cachedState = json
    local state = fromJSON(json)
    if type(state) == 'table' then
        local ok, err = pcall(applyState, state)
        if not ok then
            outputDebugString('[rst_ui] applyState failed: ' .. tostring(err), 1)
        end
    end

    -- 即使客户端 Lua 状态处理出错，也先把状态送进 CEF，避免界面卡死在旧阶段
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

addEventHandler('rst:ui:maps', root, function(json)
    local data = fromJSON(json or '')
    if type(data) == 'table' then
        dispatch('mapsPage', data)
    end
end)

addEventHandler('rst:ui:mapdetail', root, function(json)
    local data = fromJSON(json or '')
    if type(data) == 'table' then
        dispatch('mapDetail', data)
    end
end)

addEventHandler('rst:ui:records', root, function(json)
    local data = fromJSON(json or '')
    if type(data) == 'table' then
        dispatch('recordsPage', data)
    end
end)

addEventHandler('rst:scoreboard:data', root, function(json)
    local data = fromJSON(json or '')
    if type(data) == 'table' and scoreboardOpen then
        dispatch('scoreboard', data)
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
    applyInteractive()
    setSpawnControlLock(true)

    countdownTimer = setTimer(function()
        countdownTimer = nil
        RST.countdownActive = false
        setSpawnControlLock(false)
        applyInteractive()
    end, math.floor(seconds * 1000) + 50, 1)
end)

addEventHandler('rst:ui:lives', root, function(json)
    local data = fromJSON(json or '')
    if type(data) == 'table' and data.lives ~= nil then
        RST.rewindLives = tonumber(data.lives)
    end
end)

-- 拦截所有原生聊天输出，改由 CEF 渲染
addEventHandler('onClientChatMessage', root, function(text, r, g, b, messageType)
    if type(text) ~= 'string' then
        return
    end

    -- 8 位 ARGB 先匹配，避免 #RRGGBBAA 只被吃掉前 6 位
    local cleaned = text:gsub('#%x%x%x%x%x%x%x%x', ''):gsub('#%x%x%x%x%x%x', '')
    if #cleaned == 0 then
        return
    end

    local delivered = dispatch('chatMessage', {
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
    if delivered then
        cancelEvent()
    end
end)

-- ---------------------------------------------------------------------------
-- 本地玩家状态
-- ---------------------------------------------------------------------------

addEventHandler('onClientElementStreamIn', root, function()
    if getElementType(source) == 'player' then
        pcall(setPlayerNametagShowing, source, nametagsVisible)
    end
end)

addEventHandler('onClientPlayerSpawn', localPlayer, function()
    disableMotionBlur()
    applyPlayerNametags()
    if not RST.countdownActive and not RST.readyWaiting then
        setSpawnControlLock(false)
    end
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
    if RST.stopWarp then
        RST.stopWarp()
    end

    if countdownTimer then
        killTimer(countdownTimer)
        countdownTimer = nil
    end
    if RST.countdownActive then
        RST.countdownActive = false
        dispatch('countdown', { active = false })
    end
    setSpawnControlLock(false)
    -- 服务端死亡计时器会重新生成；本地先解除倒计时/准备冻结
    countdownVehicle = nil
    if isElement(localPlayer) then
        setElementFrozen(localPlayer, false)
    end

    setHelpOpen(false)
end)

-- 进入测试车辆 / 竞速车辆：刷新 ghost，不额外补氮气
addEventHandler('onClientPlayerVehicleEnter', localPlayer, function(vehicle)
    if RST.refreshGhosts then
        RST.refreshGhosts()
    end
end)

addEventHandler('onClientPlayerVehicleExit', localPlayer, function()
    if RST.refreshGhosts then
        RST.refreshGhosts()
    end
end)

-- 其他竞速车辆半透明，配合服务端关闭碰撞做 ghost
local GHOST_ALPHA = 120

function RST.refreshGhosts()
    local own = getPedOccupiedVehicle(localPlayer)
    local racers = {}
    for _, vehicle in ipairs(getElementsByType('vehicle', root, true)) do
        if getElementData(vehicle, 'rst:raceVehicle') then
            racers[#racers + 1] = vehicle
            setElementAlpha(vehicle, vehicle == own and 255 or GHOST_ALPHA)
        end
    end

    -- 本地关闭竞速车之间的碰撞
    for i = 1, #racers do
        for j = i + 1, #racers do
            setElementCollidableWith(racers[i], racers[j], false)
            setElementCollidableWith(racers[j], racers[i], false)
        end
    end
end

addEventHandler('onClientElementStreamIn', root, function()
    if getElementType(source) == 'vehicle' and getElementData(source, 'rst:raceVehicle') then
        if RST.refreshGhosts then
            RST.refreshGhosts()
        end
    end
end)

addEventHandler('onClientElementStreamOut', root, function()
    if getElementType(source) == 'vehicle' then
        setElementAlpha(source, 255)
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

local function bindUiKey(key, handler)
    if not bindKey(key, 'down', handler) then
        outputDebugString('[rst_ui] bindKey failed: ' .. tostring(key), 1)
    end
end

bindUiKey('mouse1', function()
    cycleSpectate(1)
end)
bindUiKey('mouse2', function()
    cycleSpectate(-1)
end)
bindUiKey('V', function()
    toggleSpectateView()
end)

bindUiKey('F1', function()
    if phase ~= 'playing' or voteForced then
        return
    end
    if closeTopOverlay() then
        return
    end
    setHelpOpen(true)
end)

bindUiKey('F3', function()
    if phase ~= 'playing' or isForcedCursor() or RST.countdownActive then
        return
    end
    toggleCursorVisibility()
end)

addCommandHandler('ui', function()
    if phase ~= 'playing' then
        outputChatBox('rst: 选择舞台之后才能打开菜单')
        return
    end
    setMenuOpen(not menuOpen)
end)

-- 诊断：F8 控制台输入 uidiag，查看客户端状态 / 键位绑定 / CEF 焦点
addCommandHandler('uidiag', function()
    local focused = false
    if browserReady and browser and isElement(browser) then
        local ok, value = pcall(isBrowserFocused, browser)
        focused = ok and value == true or false
    end

    local function boundCount(key)
        local ok, handlers = pcall(getFunctionsBoundToKey, key, 'down')
        return ok and type(handlers) == 'table' and #handlers or -1
    end

    local line = ('[rst_ui] phase=%s mode=%s interactive=%s browserReady=%s focused=%s menu=%s chat=%s help=%s vote=%s ready=%s rewindLives=%s cursor=%s free=%s f1=%d f2=%d t=%d')
        :format(
            tostring(phase),
            tostring(mode),
            tostring(interactive),
            tostring(browserReady),
            tostring(focused),
            tostring(menuOpen),
            tostring(chatOpen),
            tostring(helpOpen),
            tostring(voteActive),
            tostring(RST.readyWaiting),
            tostring(RST.rewindLives),
            tostring(cursorAlways and 'always' or 'auto'),
            tostring(freeCursor),
            boundCount('f1'),
            boundCount('f2'),
            boundCount('t')
        )
    outputDebugString(line, 1)
end)

-- CEF 偶尔会在非交互状态下抢回键盘焦点，render 中会立即释放，保证 bindKey 正常触发
addEventHandler('onClientResourceStop', resourceRoot, function()
    if RST.stopRewind then
        RST.stopRewind()
    end
    if RST.stopWarp then
        RST.stopWarp()
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
    setSpawnControlLock(false)
    showCursor(false)
    guiSetInputEnabled(false)
    toggleAllControls(true, true, false)
    showChat(true, false)
    setNativeHudVisible(true)
    hudHidden = false
    pcall(setPlayerHudComponentVisible, 'radar', true)
    pcall(setPlayerHudComponentVisible, 'crosshair', true)
    if isElement(localPlayer) then
        setElementFrozen(localPlayer, false)
    end

    if browser and isElement(browser) then
        destroyElement(browser)
    end
    removeEventHandler('onClientRender', root, render)
end)

-- 原生 chatbox 只负责 MTA 默认输入，聊天记录由 CEF 渲染
showChat(true, false)

-- 上报本机 FPS 给计分板；用渲染帧计数，避免依赖客户端的 FPS 查询接口
local fpsFrames = 0
local fpsWindowStart = getTickCount()
addEventHandler('onClientRender', root, function()
    fpsFrames = fpsFrames + 1
end)

setTimer(function()
    if not isElement(localPlayer) then
        return
    end
    local nowTick = getTickCount()
    local elapsed = nowTick - fpsWindowStart
    local fps = elapsed > 0 and math.floor(fpsFrames * 1000 / elapsed) or 0
    fpsFrames = 0
    fpsWindowStart = nowTick
    triggerServerEvent('rst:scoreboard:fps', localPlayer, fps)
end, 2000, 0)

-- 进入服务器时恢复所有玩家头顶名字牌和界面显示设置
applyVisibility()
addEventHandler('onClientResourceStart', resourceRoot, applyVisibility)

-- 隐藏原生血条 / 武器等 HUD，保留雷达和准星
setNativeHudVisible(false)
disableMotionBlur()

createUiBrowser()
