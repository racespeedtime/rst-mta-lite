--[[
    rst_ui / server/main.lua

    职责：
    - 玩家会话（未登录 / 游客 / 正式账号）
    - 处理浏览器发来的 action，推送给对应玩家完整 UI 状态
    - 串联账号（accounts.lua）、房间与回合（rooms.lua）
]]

Sessions = {}

local testVehicles = {}

local config = RST.config
local thisResource = getThisResource()

local function now()
    return getRealTime().timestamp
end

local function notify(player, text)
    if isElement(player) then
        triggerClientEvent(player, 'rst:ui:notice', player, tostring(text))
    end
end

local function broadcastChat(payload)
    local json = toJSON(payload)
    for _, target in ipairs(getElementsByType('player')) do
        local session = Sessions[target]
        if session and session.authed then
            triggerClientEvent(target, 'rst:ui:chat', target, json)
        end
    end
end

local function initSession(player)
    Sessions[player] = {
        authed = false,
        guest = false,
        roomId = nil,
        mode = nil,
        mapId = nil,
        mapEnteredAt = nil,
        lastAuthAt = 0,
        lastChatAt = 0,
    }
end

local function settleSessions()
    for player, session in pairs(Sessions) do
        if not isElement(player) then
            Sessions[player] = nil
        else
            local room, mode = Rooms.playerRoom(player)
            if room then
                session.roomId = room.id
                session.mode = mode

                -- 进入新地图（换图 / 中途加入）时重置个人本图计时
                if session.mapId ~= room.mapId or not session.mapEnteredAt then
                    session.mapId = room.mapId
                    session.mapEnteredAt = now()
                end
            else
                session.roomId = nil
                session.mode = nil
                session.mapId = nil
                session.mapEnteredAt = nil
            end
        end
    end
end

local function buildState(player, session)
    local state = {
        phase = 'auth',
        serverName = getServerName() or 'rst-mta-lite',
        mapPoolSize = #config.mapPool,
        mapPoolEmpty = #config.mapPool == 0,
        me = {
            name = getPlayerName(player) or 'player',
            guest = session.guest == true,
        },
    }

    if session.authed then
        if session.roomId then
            local room = Rooms.get(session.roomId)
            if room then
                state.phase = 'playing'
                state.mode = room.mode
                state.room = Rooms.summary(room)
                state.room.mode = session.mode or 'playing'
                state.vote = Rooms.voteState(room, player)
                state.modeVote = Rooms.modeVoteState(room, player)
                state.ready = Rooms.readyState(room, player)
                state.competition = Rooms.competitionState(room, player)
                state.lives = room.mode == 'competitive' and room.lives[player] or nil
                state.ob = room.ob[player] == true

                local cooldownLeft = 0
                if (room.lastVoteAt or 0) > 0 then
                    cooldownLeft = math.max(
                        0,
                        (config.voteCooldown or 0) - (now() - room.lastVoteAt)
                    )
                end
                state.canStartVote = #config.mapPool > 0
                    and (room.vote == nil)
                    and (room.modeVote == nil)
                    and room.active
                    and not room.waiting
                    and cooldownLeft <= 0
                state.voteCooldown = math.floor(cooldownLeft)

                local modeCooldownLeft = 0
                if (room.lastModeVoteAt or 0) > 0 then
                    modeCooldownLeft = math.max(
                        0,
                        (config.modeVoteCooldown or 0) - (now() - room.lastModeVoteAt)
                    )
                end
                state.canStartModeVote = (room.vote == nil)
                    and (room.modeVote == nil)
                    and room.active
                    and not room.waiting
                    and modeCooldownLeft <= 0
                state.modeVoteCooldown = math.floor(modeCooldownLeft)
            end
        end

        state.mapTime = session.mapEnteredAt and math.max(0, now() - session.mapEnteredAt) or 0

        if state.phase ~= 'playing' then
            state.phase = 'stage'
            state.rooms = {}
            for _, def in ipairs(config.rooms) do
                local room = Rooms.get(def.id)
                if room then
                    state.rooms[#state.rooms + 1] = Rooms.summary(room)
                end
            end
        end
    end

    return state
end

local function pushState(player)
    local session = Sessions[player]
    if not session or not isElement(player) then
        return
    end

    local json = toJSON(buildState(player, session))
    triggerClientEvent(player, 'rst:ui:state', player, json)
end

local function broadcastState()
    settleSessions()
    for _, player in ipairs(getElementsByType('player')) do
        pushState(player)
    end
end

local function guardSession(player, session)
    return isElement(player) and Sessions[player] == session
end

-- ---------------------------------------------------------------------------
-- action 处理（浏览器 → 客户端 Lua → 服务端）
-- ---------------------------------------------------------------------------

local actions = {}

actions['auth:guest'] = function(player, session)
    if session.authed then
        return
    end

    session.authed = true
    session.guest = true
    outputServerLog('[AUTH] guest ' .. tostring(getPlayerName(player)))
    notify(player, '游客模式进入成功')
    pushState(player)
end

actions['auth:register'] = function(player, session, data)
    if session.authed then
        return
    end

    local password = tostring(data.password or '')
    if #password < config.minPasswordLength then
        notify(player, ('密码至少 %d 位'):format(config.minPasswordLength))
        return
    end
    if #password > config.maxPasswordLength then
        notify(player, '密码太长')
        return
    end
    if tostring(data.confirmPassword or '') ~= password then
        notify(player, '两次密码不一致')
        return
    end
    if now() - (session.lastAuthAt or 0) < 1 then
        return
    end
    session.lastAuthAt = now()

    local username = getPlayerName(player)
    Accounts.exists(username, function(exists)
        if not guardSession(player, session) then
            return
        end
        if exists then
            notify(player, '账号已存在，请直接登录')
            return
        end

        Accounts.create(username, password, function(ok, err)
            if not guardSession(player, session) then
                return
            end
            if not ok then
                notify(player, err or '注册失败')
                return
            end

            session.authed = true
            session.guest = false
            outputServerLog('[AUTH] register ' .. tostring(username))
            notify(player, '注册成功，已自动登录')
            pushState(player)
        end)
    end)
end

actions['auth:login'] = function(player, session, data)
    if session.authed then
        return
    end

    local password = tostring(data.password or '')
    if #password == 0 then
        notify(player, '请输入密码')
        return
    end
    if now() - (session.lastAuthAt or 0) < 1 then
        return
    end
    session.lastAuthAt = now()

    local username = getPlayerName(player)
    Accounts.verify(username, password, function(ok, err)
        if not guardSession(player, session) then
            return
        end
        if not ok then
            outputServerLog(('[AUTH] login_failed %s'):format(tostring(username)))
            notify(player, err or '登录失败')
            return
        end

        session.authed = true
        session.guest = false
        outputServerLog(('[AUTH] login %s'):format(tostring(username)))
        notify(player, '登录成功')
        pushState(player)
    end)
end

actions['stage:select'] = function(player, session, data)
    if not session.authed or session.roomId then
        return
    end

    local room = Rooms.get(tostring(data.room or ''))
    if not room then
        notify(player, '舞台不存在')
        return
    end

    local mode = Rooms.join(player, room.id)
    if not mode then
        notify(player, '加入舞台失败')
        return
    end

    session.roomId = room.id
    session.mode = mode
    notify(player, mode == 'spectating' and '进入观战模式' or '已加入比赛')
    broadcastState()
end

actions['stage:refresh'] = function(player)
    pushState(player)
end

actions['stage:leave'] = function(player, session)
    if not session.roomId then
        return
    end

    Rooms.leave(player)
    session.roomId = nil
    session.mode = nil
    setElementDimension(player, 0)
    notify(player, '已离开舞台')
    broadcastState()
end

actions['vote:start'] = function(player, session)
    if not session.roomId then
        return
    end

    local room = Rooms.get(session.roomId)
    if not room then
        return
    end

    local ok, err = Rooms.startVote(room)
    if not ok then
        notify(player, err)
    else
        notify(player, '已发起换图投票')
    end
    broadcastState()
end

actions['vote:cast'] = function(player, session, data)
    if not session.roomId then
        return
    end

    local room = Rooms.get(session.roomId)
    if not room then
        return
    end

    local ok, err = Rooms.castVote(room, player, tostring(data.map or ''))
    if not ok then
        notify(player, err)
    end
    broadcastState()
end

actions['modevote:start'] = function(player, session)
    if not session.roomId then
        return
    end

    local room = Rooms.get(session.roomId)
    if not room then
        return
    end

    local ok, err = Rooms.startModeVote(room)
    if not ok then
        notify(player, err)
    else
        notify(player, '已发起模式投票')
    end
    broadcastState()
end

actions['modevote:cast'] = function(player, session, data)
    if not session.roomId then
        return
    end

    local room = Rooms.get(session.roomId)
    if not room then
        return
    end

    local ok, err = Rooms.castModeVote(room, player, tostring(data.mode or ''))
    if not ok then
        notify(player, err)
    end
    broadcastState()
end

actions['ready'] = function(player, session)
    if not session.roomId then
        return
    end

    local ok, err = Rooms.setReady(player)
    if not ok then
        notify(player, err)
    end
    broadcastState()
end

actions['ob:spectate'] = function(player, session)
    if not session.roomId then
        return
    end

    local ok, err = Rooms.becomeSpectator(player)
    if not ok then
        notify(player, err)
    else
        notify(player, '已切换为纯观战，下回合继续观战')
    end
    broadcastState()
end

actions['ob:race'] = function(player, session)
    if not session.roomId then
        return
    end

    local ok, result = Rooms.returnToRace(player)
    if not ok then
        notify(player, result)
    elseif result == 'ready' then
        notify(player, '已回到比赛，等待准备')
    elseif result == 'started' then
        notify(player, '已回到比赛，回合已开始')
    else
        notify(player, '已取消纯观战，下回合参赛')
    end
    broadcastState()
end

actions['chat:send'] = function(player, session, data)
    if not session.authed then
        return
    end

    local text = tostring(data.text or '')
    text = text:gsub('[\r\n\t]', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    if #text == 0 then
        return
    end
    if #text > 160 then
        text = text:sub(1, 160)
    end

    local time = now()
    if time - (session.lastChatAt or 0) < 1 then
        return
    end
    session.lastChatAt = time

    local name = getPlayerName(player) or 'player'
    outputServerLog('[CHAT] ' .. name .. ': ' .. text)
    broadcastChat({
        kind = 'player',
        name = name,
        text = text,
        time = time,
    })
end

addEvent('rst:ui:action', true)
addEventHandler('rst:ui:action', root, function(json)
    local player = client or source
    local session = Sessions[player]
    if not session or not isElement(player) then
        return
    end

    local data = fromJSON(json or '')
    if type(data) ~= 'table' or type(data.action) ~= 'string' then
        return
    end

    local handler = actions[data.action]
    if handler then
        handler(player, session, data)
    end
end)

addEvent('rst:ui:requestState', true)
addEventHandler('rst:ui:requestState', root, function()
    local player = client or source
    if not isElement(player) then
        return
    end

    if not Sessions[player] then
        initSession(player)
    end
    pushState(player)
end)

-- 客户端完成一次 rewind 后扣命
addEvent('rst:rewind:use', true)
addEventHandler('rst:rewind:use', root, function()
    local player = client or source
    if not isElement(player) then
        return
    end

    local room = Rooms.playerRoom(player)
    if not room then
        return
    end

    local ok, lives, eliminated = Rooms.consumeLife(player)
    if not ok then
        return
    end

    triggerClientEvent(player, 'rst:ui:lives', player, toJSON({
        lives = lives,
        eliminated = eliminated == true,
    }))
    if eliminated then
        notify(player, '命数耗尽，已进入观战')
    end
    broadcastState()
end)

-- ---------------------------------------------------------------------------
-- 生命周期
-- ---------------------------------------------------------------------------

addEventHandler('onResourceStart', resourceRoot, function()
    Accounts.init()
    MapStats.init()
    Rooms.init(broadcastState)

    for _, player in ipairs(getElementsByType('player')) do
        initSession(player)
        pushState(player)
    end
end)

addEventHandler('onPlayerResourceStart', root, function(startedResource)
    if startedResource ~= thisResource then
        return
    end

    if not Sessions[source] then
        initSession(source)
    end
    pushState(source)
end)

addEventHandler('onPlayerJoin', root, function()
    local name = getPlayerName(source)
    if name then
        broadcastChat({
            kind = 'system',
            text = name .. ' 加入了服务器',
            time = now(),
        })
    end
end)

addEventHandler('onPlayerQuit', root, function()
    local name = getPlayerName(source)

    if isElement(testVehicles[source]) then
        destroyElement(testVehicles[source])
        testVehicles[source] = nil
    end

    Rooms.leave(source)
    Sessions[source] = nil

    if name then
        broadcastChat({
            kind = 'system',
            text = name .. ' 离开了服务器',
            time = now(),
        })
    end

    broadcastState()
end)

addEventHandler('onPlayerWasted', root, function()
    Rooms.handleDeath(source)
end)

-- 测试用：生成一辆带氮气的 Infernus
addCommandHandler('car', function(player, _, modelArg)
    local session = Sessions[player]
    if not session or not session.authed then
        notify(player, '请先登录')
        return
    end
    if not session.roomId then
        notify(player, '进入舞台后才能生成测试车辆')
        return
    end

    if isElement(testVehicles[player]) then
        destroyElement(testVehicles[player])
        testVehicles[player] = nil
    end

    local model = tonumber(modelArg) or 411
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)

    local vehicle = createVehicle(model, x + 2.5, y + 2.5, z + 0.5, 0, 0, rz)
    if not vehicle then
        notify(player, '测试车辆生成失败：' .. tostring(model))
        return
    end

    setElementDimension(vehicle, getElementDimension(player))
    addVehicleUpgrade(vehicle, 1010)
    setElementData(vehicle, 'rst:testVehicle', true)
    testVehicles[player] = vehicle

    notify(player, '已生成测试车辆（带氮气），按 F 上车')
end)

