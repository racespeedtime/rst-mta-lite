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
        registered = nil,
        roomId = nil,
        mode = nil,
        mapId = nil,
        mapEnteredAt = nil,
        mapEnteredAtMs = nil,
        lastAuthAt = 0,
        lastChatAt = 0,
        lastScoreboardAt = 0,
        fps = 0,
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
                    session.mapEnteredAtMs = RST.nowMs()
                end
            else
                session.roomId = nil
                session.mode = nil
                session.mapId = nil
                session.mapEnteredAt = nil
                session.mapEnteredAtMs = nil
            end
        end
    end
end

local function buildState(player, session)
    local state = {
        phase = 'auth',
        serverName = getServerName() or 'rst-mta-lite',
        mapPoolSize = MapRegistry.count(),
        mapPoolEmpty = MapRegistry.count() == 0,
        me = {
            name = getPlayerName(player) or 'player',
            guest = session.guest == true,
            registered = session.registered,
        },
    }

    if session.authed then
        if session.roomId then
            local room = Rooms.get(session.roomId)
            if room then
                state.phase = 'playing'
                state.mode = room.mode
                state.competitiveMode = room.competitiveMode or 'solo'
                state.room = Rooms.summary(room)
                state.room.mode = session.mode or 'playing'
                state.me.mode = session.mode or 'playing'
                state.me.team = room.teamOf[player]
                state.vote = Rooms.voteState(room, player)
                state.modeVote = Rooms.modeVoteState(room, player)
                state.ready = Rooms.readyState(room, player)
                state.competition = Rooms.competitionState(room, player)
                state.raceResult = Rooms.raceResultState(room, player)
                local best = Records.getBest(player, room.mapId)
                state.personalBestMs = best
                state.personalBest = best and math.floor(best / 1000) or nil
                state.lives = room.mode == 'competitive' and room.lives[player] or nil
                state.ob = room.ob[player] == true
                state.watchers = Rooms.watchCount(room, player)
                state.me.finished = room.finished[player] ~= nil
                state.raceFinal = room.raceFinal == true

                local map = MapRegistry.details(room.mapId)
                if map then
                    local start = (map.spawnpoints or {})[1]
                    if start then
                        start = { x = start.x, y = start.y, z = start.z }
                    end
                    local hunter = map.finishes and map.finishes[1]
                    if hunter then
                        hunter = { x = hunter.x, y = hunter.y, z = hunter.z }
                    end

                    local names = {}
                    local dimension = getElementDimension(player)
                    -- 只列当前参赛者；观战者/纯 OB 不作为跟随目标
                    for _, other in ipairs(room.players) do
                        if other ~= player
                            and isElement(other)
                            and getElementDimension(other) == dimension
                            and getElementHealth(other) > 0
                        then
                            names[#names + 1] = getPlayerName(other) or '?'
                        end
                    end
                    table.sort(names)

                    state.spectate = {
                        start = start,
                        hunter = hunter,
                        players = names,
                    }
                end

                local cooldownLeft = 0
                if (room.lastVoteAt or 0) > 0 then
                    cooldownLeft = math.max(
                        0,
                        (config.voteCooldown or 0) - (now() - room.lastVoteAt)
                    )
                end
                state.canStartVote = MapRegistry.count() > 0
                    and (room.vote == nil)
                    and (room.modeVote == nil)
                    and room.active
                    and not room.waiting
                    and not (room.startingUntil and RST.nowMs() < room.startingUntil)
                    and not room.raceFinal
                    and (room.raceEndsAt or 0) <= 0
                    and (room.resultsUntil or 0) <= 0
                    and cooldownLeft <= 0
                state.voteCooldown = math.floor(cooldownLeft)

                local isCompetitivePlayer = false
                if room.mode == 'competitive' then
                    for _, member in ipairs(room.players) do
                        if member == player then
                            isCompetitivePlayer = true
                            break
                        end
                    end
                end
                state.canStartRestartVote = state.canStartVote and isCompetitivePlayer

                local startCooldownLeft = 0
                if (room.lastStartVoteAt or 0) > 0 then
                    startCooldownLeft = math.max(
                        0,
                        (config.startVoteCooldown or 0) - (now() - room.lastStartVoteAt)
                    )
                end
                state.startVoteCooldown = math.floor(startCooldownLeft)
                state.canStartStartVote = room.mode == 'competitive'
                    and room.waiting
                    and room.vote == nil
                    and room.modeVote == nil
                    and isCompetitivePlayer
                    and (state.ready.total or 0) > 0
                    and (state.ready.ready or 0) >= (state.ready.total or 0)
                    and state.ready.balanced ~= false
                    and room.mapId ~= nil
                    and startCooldownLeft <= 0

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
                    and not (room.startingUntil and RST.nowMs() < room.startingUntil)
                    and not room.raceFinal
                    and (room.raceEndsAt or 0) <= 0
                    and (room.resultsUntil or 0) <= 0
                    and modeCooldownLeft <= 0
                state.modeVoteCooldown = math.floor(modeCooldownLeft)
            end
        end

        state.mapTime = session.mapEnteredAt and math.max(0, now() - session.mapEnteredAt) or 0
    state.mapTimeMs = session.mapEnteredAtMs and math.max(0, RST.nowMs() - session.mapEnteredAtMs) or 0

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

local function joinDefaultRoom(player, session)
    if session.roomId then
        return true
    end
    local def = config.rooms[1]
    if not def then
        notify(player, '服务器没有配置舞台')
        return false
    end
    local mode, _, err = Rooms.join(player, def.id)
    if not mode then
        notify(player, err or '加入比赛失败')
        return false
    end
    session.roomId = def.id
    session.mode = mode
    return true
end

actions['auth:check'] = function(player, session)
    if session.authed then
        return
    end
    Accounts.exists(getPlayerName(player), function(exists)
        if not guardSession(player, session) then
            return
        end
        session.registered = exists == true
        pushState(player)
    end)
end

actions['auth:guest'] = function(player, session)
    if session.authed then
        return
    end

    -- 昵称已经注册时必须登录，不能绕过账号直接游客进入
    Accounts.exists(getPlayerName(player), function(exists)
        if not guardSession(player, session) then
            return
        end
        if exists then
            session.registered = true
            notify(player, '该昵称已注册，请登录')
            pushState(player)
            return
        end

        session.registered = false
        session.authed = true
        session.guest = true
        outputServerLog('[AUTH] guest ' .. tostring(getPlayerName(player)))
        if joinDefaultRoom(player, session) then
            notify(player, '游客模式进入成功')
        end
        pushState(player)
    end)
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
        notify(player, '操作太快，请稍后再试')
        return
    end
    session.lastAuthAt = now()

    local username = getPlayerName(player)
    Accounts.exists(username, function(exists)
        if not guardSession(player, session) then
            return
        end
        if exists then
            session.registered = true
            notify(player, '账号已存在，请直接登录')
            pushState(player)
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
            session.registered = true
            outputServerLog('[AUTH] register ' .. tostring(username))
            if joinDefaultRoom(player, session) then
                notify(player, '注册成功，已自动登录')
            end
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
        notify(player, '操作太快，请稍后再试')
        return
    end
    session.lastAuthAt = now()

    local username = getPlayerName(player)
    Accounts.exists(username, function(exists)
        if not guardSession(player, session) then
            return
        end
        if not exists then
            session.registered = false
            notify(player, '账号不存在，请先注册')
            pushState(player)
            return
        end

        session.registered = true
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
            session.registered = true
            outputServerLog(('[AUTH] login %s'):format(tostring(username)))
            if joinDefaultRoom(player, session) then
                notify(player, '登录成功')
            end
            pushState(player)
        end)
    end)
end

actions['stage:join'] = function(player, session)
    if not session.authed or session.roomId then
        return
    end
    if joinDefaultRoom(player, session) then
        notify(player, '已进入比赛')
    end
    pushState(player)
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

actions['startvote:start'] = function(player, session)
    if not session.roomId then
        return
    end

    local room = Rooms.get(session.roomId)
    if not room then
        return
    end

    local ok, err = Rooms.startStartVote(player)
    if not ok then
        notify(player, err)
    else
        notify(player, '已发起开局投票')
    end
    broadcastState()
end

actions['vote:restart'] = function(player, session)
    if not session.roomId then
        return
    end

    local room = Rooms.get(session.roomId)
    if not room then
        return
    end

    local ok, err = Rooms.startRestartVote(player)
    if not ok then
        notify(player, err)
    else
        notify(player, '已发起重开投票')
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

actions['vote:abstain'] = function(player, session)
    if not session.roomId then
        return
    end

    local room = Rooms.get(session.roomId)
    if not room then
        return
    end

    local ok, err = Rooms.abstain(room, player)
    if not ok then
        notify(player, err or '弃权失败')
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

    local ok, err = Rooms.startModeVote(room, player)
    if not ok then
        notify(player, err)
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

actions['team:select'] = function(player, session, data)
    if not session.roomId then
        return
    end

    local ok, err = Rooms.selectTeam(player, tostring(data.team or ''))
    if not ok then
        notify(player, err or '选择队伍失败')
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

actions['respawn'] = function(player, session)
    if not session.roomId then
        return
    end

    local ok, err = Rooms.respawn(player)
    if not ok then
        notify(player, err or '重生失败')
    end
    broadcastState()
end

actions['maps:page'] = function(player, session, data)
    if not session.authed then
        return
    end
    local payload = MapRegistry.page(data.page, data.pageSize, data.search, data.sort, data.order, data.dateFrom, data.dateTo)
    payload.requestId = data.requestId
    triggerClientEvent(player, 'rst:ui:maps', player, toJSON(payload))
end

-- 地图池里点开某张图：按需解析这张图的 .map 和外部元数据
actions['maps:detail'] = function(player, session, data)
    if not session.authed then
        return
    end
    local mapId = tostring(data.mapId or '')
    local detail = MapRegistry.detail(mapId)
    if CoverCache then
        detail = CoverCache.prepare(player, detail, data.requestId)
    end
    triggerClientEvent(player, 'rst:ui:mapdetail', player, toJSON({
        requestId = data.requestId,
        mapId = mapId,
        detail = detail,
    }))
end

-- 地图池里点名一张图，发起换图投票（这张图会作为候选之一，并标注提名者）
actions['maps:vote'] = function(player, session, data)
    if not session.authed then
        return
    end
    local room = session.roomId and Rooms.get(session.roomId)
    if not room then
        notify(player, '请先进入舞台')
        return
    end

    local mapId = tostring(data.mapId or '')
    local map = MapRegistry.peek(mapId)
    local ok, err = Rooms.startVote(room, 'manual', mapId, player)
    if not ok then
        notify(player, err or '发起投票失败')
    elseif room.vote then
        -- 只有一名参赛者时提名票会直接出结果，这时不再提示“已发起”
        notify(player, ('已发起换图投票：%s'):format(tostring(map and map.name or mapId)))
    end
    broadcastState()
end

actions['records:page'] = function(player, session, data)
    if not session.authed then
        return
    end

    local room = session.roomId and Rooms.get(session.roomId)
    if not room or not room.mapId then
        return
    end

    local map = MapRegistry.peek(room.mapId)
    local payload = Records.leaderboard(room.mapId, data.page, data.pageSize)
    payload.mapId = room.mapId
    payload.mapName = map and map.name or room.mapId
    payload.mapAuthor = map and map.author or ''
    payload.requestId = data.requestId
    triggerClientEvent(player, 'rst:ui:records', player, toJSON(payload))
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

    -- CEF 聊天拦截了原生 chatbox，所以 / 开头统一按指令处理
    if text:sub(1, 1) == '/' then
        local commandLine = text:sub(2):gsub('^%s+', ''):gsub('%s+$', '')
        local command, args = commandLine:match('^(%S+)%s*(.*)$')
        if not command or #command == 0 then
            notify(player, '请输入指令，例如 /help')
            return
        end

        local time = now()
        if time - (session.lastChatAt or 0) < 1 then
            notify(player, '操作太快，请稍后再试')
            return
        end
        session.lastChatAt = time

        local ok = executeCommandHandler(command:lower(), player, args or '')
        if not ok then
            notify(player, '未知指令：/' .. command .. '。可用 /help 查看')
        end
        return
    end

    -- 按 UTF-8 字符数限制，避免中文被按字节截断
    local charCount = 0
    for i = 1, #text do
        local byte = text:byte(i)
        if byte < 0x80 or byte >= 0xC0 then
            charCount = charCount + 1
        end
    end
    if charCount > 160 then
        local kept, count = 0, 0
        for i = 1, #text do
            local byte = text:byte(i)
            if byte < 0x80 or byte >= 0xC0 then
                count = count + 1
                if count > 160 then
                    kept = i - 1
                    break
                end
            end
        end
        if kept > 0 then
            text = text:sub(1, kept)
        end
    end

    local time = now()
    if time - (session.lastChatAt or 0) < 1 then
        return
    end
    session.lastChatAt = time

    local name = getPlayerName(player) or 'player'
    local room = session.roomId and Rooms.get(session.roomId)
    local team = room and room.teamOf[player] or nil
    outputServerLog('[CHAT] ' .. name .. ': ' .. text)
    broadcastChat({
        kind = 'player',
        name = name,
        team = team,
        text = text,
        time = time,
    })
end

-- 原生 chatbox 只负责输入；消息取消原生广播，统一进 CEF 聊天记录
addEventHandler('onPlayerChat', root, function(message, messageType)
    local player = source
    local session = Sessions[player]
    if not session or not session.authed then
        cancelEvent()
        return
    end

    local text = tostring(message or '')
    if messageType ~= 0 then
        cancelEvent()
        return
    end

    -- 指令交给 MTA 原生 command handler，不在这里取消
    if text:sub(1, 1) == '/' then
        return
    end

    text = text:gsub('[\r\n\t]', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    if #text == 0 then
        cancelEvent()
        return
    end

    local charCount = 0
    for i = 1, #text do
        local byte = text:byte(i)
        if byte < 0x80 or byte >= 0xC0 then
            charCount = charCount + 1
        end
    end
    if charCount > 160 then
        local kept, count = 0, 0
        for i = 1, #text do
            local byte = text:byte(i)
            if byte < 0x80 or byte >= 0xC0 then
                count = count + 1
                if count > 160 then
                    kept = i - 1
                    break
                end
            end
        end
        if kept > 0 then
            text = text:sub(1, kept)
        end
    end

    -- 聊天限速：两条之间至少 minInterval，另外 burstWindow 内最多 burstLimit 条
    local nowMs = RST.nowMs()
    local minInterval = config.chatMinIntervalMs or 900
    local burstWindow = config.chatBurstWindowMs or 10000
    local burstLimit = config.chatBurstLimit or 6

    if nowMs - (session.lastChatAtMs or 0) < minInterval then
        cancelEvent()
        if nowMs - (session.lastChatWarnAtMs or 0) > 1500 then
            session.lastChatWarnAtMs = nowMs
            notify(player, '说话太快了，稍等一下再发')
        end
        return
    end

    local cutoff = nowMs - burstWindow
    local recent = session.chatTimes or {}
    local kept = {}
    for _, at in ipairs(recent) do
        if at > cutoff then
            kept[#kept + 1] = at
        end
    end

    if #kept >= burstLimit then
        cancelEvent()
        session.chatTimes = kept
        if nowMs - (session.lastChatWarnAtMs or 0) > 1500 then
            session.lastChatWarnAtMs = nowMs
            notify(player, ('发言太频繁，%d 秒内最多 %d 条'):format(math.ceil(burstWindow / 1000), burstLimit))
        end
        return
    end

    kept[#kept + 1] = nowMs
    session.chatTimes = kept
    session.lastChatAtMs = nowMs

    local time = now()

    cancelEvent()
    local name = getPlayerName(player) or 'player'
    local room = session.roomId and Rooms.get(session.roomId)
    local team = room and room.teamOf[player] or nil
    outputServerLog('[CHAT] ' .. name .. ': ' .. text)
    broadcastChat({
        kind = 'player',
        name = name,
        team = team,
        text = text,
        time = time,
    })
end)

addEvent('rst:ui:action', true)addEventHandler('rst:ui:action', root, function(json)
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

-- 客户端上报 FPS；MTA 服务端没有直接读取玩家 FPS 的接口
addEvent('rst:scoreboard:fps', true)
addEventHandler('rst:scoreboard:fps', root, function(fps)
    local player = client or source
    local session = Sessions[player]
    if not session then
        return
    end
    fps = tonumber(fps)
    if not fps then
        return
    end
    session.fps = math.max(0, math.min(1000, math.floor(fps)))
end)

local function listHas(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

local function scoreboardStatus(player, session)
    if not session or not session.authed then
        return '未登录', 'auth'
    end
    if not session.roomId then
        return '大厅', 'lobby'
    end
    local room = Rooms.get(session.roomId)
    if not room then
        return '大厅', 'lobby'
    end

    if room.vote or room.modeVote then
        return '投票中', 'vote'
    end
    if listHas(room.spectators, player) then
        if room.ob[player] then
            return '纯观战', 'spectate'
        end
        if room.mode == 'competitive' and room.lives[player] == 0 then
            return '淘汰观战', 'out'
        end
        return '观战', 'spectate'
    end
    if listHas(room.players, player) then
        if room.waiting then
            return '准备中', 'ready'
        end
        if room.mode == 'training' then
            return '训练中', 'training'
        end
        if room.finished[player] then
            return '已完赛', 'finished'
        end
        if isElement(player) and getElementHealth(player) <= 0 then
            return '死亡', 'dead'
        end
        return '存活', 'alive'
    end
    return '大厅', 'lobby'
end

addEvent('rst:scoreboard:request', true)
addEventHandler('rst:scoreboard:request', root, function()
    local player = client or source
    local session = Sessions[player]
    if not isElement(player) or not session then
        return
    end

    local time = now()
    if time - (session.lastScoreboardAt or 0) < 0.5 then
        return
    end
    session.lastScoreboardAt = time

    local entries = {}
    for _, target in ipairs(getElementsByType('player')) do
        local targetSession = Sessions[target]
        local status, statusKey = scoreboardStatus(target, targetSession)
        entries[#entries + 1] = {
            id = getElementID(target) or 0,
            name = getPlayerName(target) or '?',
            status = status,
            statusKey = statusKey,
            fps = targetSession and targetSession.fps or 0,
            ping = getPlayerPing(target) or 0,
            me = target == player,
        }
    end
    table.sort(entries, function(a, b)
        return a.id < b.id
    end)

    triggerClientEvent(player, 'rst:scoreboard:data', player, toJSON({
        players = entries,
        count = #entries,
        serverName = getServerName() or 'rst-mta-lite',
    }))
end)

-- 客户端完成一次 rewind 后扣命
addEvent('rst:spectate:watch', true)
addEventHandler('rst:spectate:watch', root, function(target)
    local player = client or source
    if not isElement(player) then
        return
    end
    Rooms.setSpectateTarget(player, target)
end)

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
        outputServerLog(('[REWIND] 未扣命 player=%s mode=%s active=%s waiting=%s lives=%s finished=%s'):format(
            tostring(getPlayerName(player)), tostring(room.mode), tostring(room.active), tostring(room.waiting),
            tostring(room.lives[player]), tostring(room.finished[player] ~= nil)
        ))
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

-- 客户端 rewind 结束时同步载具血量，避免客户端回放后又被服务端旧血量覆盖
addEvent('rst:rewind:health', true)
addEventHandler('rst:rewind:health', root, function(health)
    local player = client or source
    if not isElement(player) then
        return
    end

    local room = Rooms.playerRoom(player)
    if not room or not room.active then
        return
    end

    local vehicle = getPedOccupiedVehicle(player)
    if not vehicle then
        return
    end

    health = tonumber(health)
    if not health then
        return
    end
    health = math.max(1, math.min(1000, health))
    setElementHealth(vehicle, health)
end)

-- ---------------------------------------------------------------------------
-- 生命周期
-- ---------------------------------------------------------------------------

addEventHandler('onResourceStart', resourceRoot, function()
    Accounts.init()
    MapStats.init()
    Records.init()
    MapMeta.init()
    -- 地图投票/自动选图都依赖 math.random；显式播种，避免每次启动同一序列
    math.randomseed(os.time() + getTickCount())
    MapRegistry.init()
    -- 服务端统一限制所有玩家最高 60 FPS
    pcall(setFPSLimit, 60)
    outputServerLog('[PERF] fps limit=60')
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

addCommandHandler('help', function(player)
    notify(player, '可用指令：/car [模型] · /help')
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

    local room = Rooms.playerRoom(player)
    if room and room.mode == 'competitive' then
        notify(player, '竞技模式不能生成测试车辆')
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
    setElementData(vehicle, 'rst:testVehicle', true)
    testVehicles[player] = vehicle

    notify(player, '已生成测试车辆，按 F 上车')
end)

addEventHandler('onResourceStop', resourceRoot, function()
    for _, player in ipairs(getElementsByType('player')) do
        if isElement(player) then
            setElementFrozen(player, false)
            pcall(setPlayerNametagColor, player, false)
        end
    end
end)
