--[[
    rst_ui / server/rooms.lua

    两个 DeathMatch 竞速房间：
    - 每个房间独立 dimension，互不可见
    - 每张地图最多 30 分钟，时间到自动发起换图投票
    - 房间里有玩家时新玩家默认观战，空房则直接开新回合
    - 回合开始时观战者转为玩家并一起出生
]]

Rooms = {}

local config = RST.config
local rooms = {}
local stateChanged = function() end
local freezeTimers = {}
local raceVehicles = {}

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

local function allPlayersReady(room)
    if #room.players == 0 then
        return false
    end
    for _, player in ipairs(room.players) do
        if not room.ready[player] then
            return false
        end
    end
    return true
end

local function now()
    return getRealTime().timestamp
end

local function removePlayer(list, player)
    for i = #list, 1, -1 do
        if list[i] == player then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local function mapUsedByOtherRoom(room, mapId)
    for id, other in pairs(rooms) do
        if id ~= room.id and other.active and other.mapId == mapId then
            return true
        end
    end
    return false
end

local function pickMap(room)
    local candidates = {}

    for _, mapId in ipairs(config.mapPool) do
        if mapId ~= room.mapId and not mapUsedByOtherRoom(room, mapId) then
            candidates[#candidates + 1] = mapId
        end
    end

    if #candidates == 0 then
        for _, mapId in ipairs(config.mapPool) do
            if mapId ~= room.mapId then
                candidates[#candidates + 1] = mapId
            end
        end
    end

    if #candidates == 0 then
        candidates = config.mapPool
    end

    return candidates[math.random(#candidates)]
end

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

-- 随机图池：优先不包含最近玩过和当前地图
local function pickVoteOptions(room)
    local poolSize = math.max(1, config.votePoolSize or 3)
    local recent = {}
    for _, mapId in ipairs(room.recentMaps or {}) do
        recent[mapId] = true
    end

    local fresh, old = {}, {}
    for _, mapId in ipairs(config.mapPool) do
        if
            mapId ~= room.mapId
            and config.maps[mapId]
            and not mapUsedByOtherRoom(room, mapId)
        then
            if recent[mapId] then
                old[#old + 1] = mapId
            else
                fresh[#fresh + 1] = mapId
            end
        end
    end

    shuffle(fresh)
    shuffle(old)

    local selected = {}
    for _, list in ipairs({ fresh, old }) do
        for _, mapId in ipairs(list) do
            if #selected < poolSize then
                selected[#selected + 1] = mapId
            end
        end
    end

    -- 只有一张图时允许投票保留当前图
    if #selected == 0 and room.mapId and config.maps[room.mapId] then
        selected[1] = room.mapId
    end

    local options = {}
    for _, mapId in ipairs(selected) do
        local map = config.maps[mapId]
        options[#options + 1] = {
            id = mapId,
            name = map.name,
            author = map.author,
            popularity = MapStats.popularity(mapId),
            plays = MapStats.getPlays(mapId),
        }
    end

    return options
end

local function setPlayerFrozen(player, state)
    if isElement(player) then
        setElementFrozen(player, state)
    end
    local car = raceVehicles[player]
    if isElement(car) then
        setElementFrozen(car, state)
    end
end

local function clearFreezeTimer(player)
    if freezeTimers[player] then
        killTimer(freezeTimers[player])
        freezeTimers[player] = nil
    end
end

local function beginCountdownFor(player, seconds)
    clearFreezeTimer(player)
    setPlayerFrozen(player, true)

    seconds = seconds or config.spawnCountdown or 0
    if seconds <= 0 then
        setPlayerFrozen(player, false)
        return
    end

    triggerClientEvent(player, 'rst:ui:countdown', player, toJSON({
        seconds = seconds,
    }))

    freezeTimers[player] = setTimer(function()
        freezeTimers[player] = nil
        setPlayerFrozen(player, false)
    end, math.floor(seconds * 1000) + 250, 1)
end

-- 竞速车辆之间关闭碰撞由客户端统一处理（setElementCollidableWith 是客户端碰撞状态）
local function spawnPlayerInRoom(player, room, countdown, waiting)
    local map = config.maps[room.mapId]
    if not map or not isElement(player) then
        return
    end

    -- 竞速出生：清理旧车并计算发车格位
    if isElement(raceVehicles[player]) then
        destroyElement(raceVehicles[player])
    end
    raceVehicles[player] = nil

    local index = 1
    for i, value in ipairs(room.players) do
        if value == player then
            index = i
            break
        end
    end
    local column = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    local x = map.x + (column == 0 and -3.5 or 3.5)
    local y = map.y - row * 7
    local z = map.z + 0.7
    local rot = map.rot + math.random(-5, 5)

    spawnPlayer(player, x, y, z, rot)
    setElementDimension(player, room.dimension)
    setElementHealth(player, 100)
    setPedArmor(player, 0)
    takeAllWeapons(player)

    local vehicle = createVehicle(map.vehicle or config.vehicle or 411, x, y, z, 0, 0, rot)
    if vehicle then
        setElementDimension(vehicle, room.dimension)
        setElementHealth(vehicle, 1000)
        if config.vehicleNitro then
            addVehicleUpgrade(vehicle, 1010)
        end
        setElementData(vehicle, 'rst:raceVehicle', true)
        warpPedIntoVehicle(player, vehicle, 0)
        raceVehicles[player] = vehicle
    end

    if waiting then
        clearFreezeTimer(player)
        setPlayerFrozen(player, true)
    elseif countdown then
        beginCountdownFor(player, config.spawnCountdown)
    else
        clearFreezeTimer(player)
        setPlayerFrozen(player, false)
    end
end

local function startRound(room, forcedMapId)
    if room.mapId then
        table.insert(room.recentMaps, 1, room.mapId)
        while #room.recentMaps > (config.recentMapLimit or 2) do
            table.remove(room.recentMaps)
        end
    end

    room.mapId = forcedMapId or pickMap(room)
    MapStats.recordPlay(room.mapId)
    room.active = true
    room.roundEnds = now() + config.roundSeconds
    room.vote = nil
    room.modeVote = nil
    room.ready = {}
    room.lives = {}
    room.mode = room.mode or config.defaultMode or 'training'
    room.waiting = room.mode == 'competitive'

    -- 新回合开始，普通观战者转为玩家；纯 OB 保持观战
    local stayingSpectators = {}
    for _, player in ipairs(room.spectators) do
        if room.ob[player] then
            stayingSpectators[#stayingSpectators + 1] = player
        else
            room.players[#room.players + 1] = player
            room.ob[player] = nil
        end
    end
    room.spectators = stayingSpectators

    for _, player in ipairs(room.players) do
        if isElement(player) then
            if room.mode == 'competitive' then
                room.ready[player] = false
                room.lives[player] = config.competitiveLives or 10
            end
            spawnPlayerInRoom(player, room, room.mode ~= 'competitive', room.mode == 'competitive')
        end
    end

    stateChanged()
end

function Rooms.init(onChanged)
    if onChanged then
        stateChanged = onChanged
    end

    for _, def in ipairs(config.rooms) do
        rooms[def.id] = {
            id = def.id,
            name = def.name,
            dimension = def.dimension,
            mapId = nil,
            active = false,
            roundEnds = 0,
            players = {},
            spectators = {},
            vote = nil,
            modeVote = nil,
            mode = config.defaultMode or 'training',
            waiting = false,
            ready = {},
            lives = {},
            ob = {},
            recentMaps = {},
            lastVoteAt = 0,
            lastModeVoteAt = 0,
        }
    end

    setTimer(Rooms.tick, 1000, 0)
end

function Rooms.beginCountdown(room)
    if not room or not room.waiting then
        return
    end

    room.waiting = false
    room.ready = {}
    local seconds = config.competitiveCountdown or 5
    for _, player in ipairs(room.players) do
        if isElement(player) then
            beginCountdownFor(player, seconds)
        end
    end
    stateChanged()
end

function Rooms.setReady(player)
    local room = Rooms.playerRoom(player)
    if not room or room.mode ~= 'competitive' then
        return false, '当前不是竞技模式'
    end
    if not room.active or not room.waiting then
        return false, '当前不需要准备'
    end
    if not contains(room.players, player) then
        return false, '观战者不能准备'
    end
    if room.ready[player] then
        return true
    end

    room.ready[player] = true
    if allPlayersReady(room) then
        Rooms.beginCountdown(room)
    else
        stateChanged()
    end
    return true
end

function Rooms.readyState(room, player)
    if not room or not room.waiting then
        return { waiting = false }
    end

    local ready = 0
    for _, p in ipairs(room.players) do
        if room.ready[p] then
            ready = ready + 1
        end
    end

    return {
        waiting = true,
        ready = ready,
        total = #room.players,
        me = room.ready[player] == true,
        canReady = contains(room.players, player),
    }
end

function Rooms.competitionState(room, player)
    if not room or room.mode ~= 'competitive' then
        return nil
    end

    local map = room.mapId and config.maps[room.mapId]
    local finish = map and map.finish
    local startX = map and map.x
    local startY = map and map.y
    local startZ = map and map.z
    local hasStart = startX and startY and startZ

    -- 有终点按到终点距离升序；没有终点按远离起点距离降序；都没有才按命数
    local ranking = 'lives'
    if finish then
        ranking = 'finish'
    elseif hasStart then
        ranking = 'progress'
    end

    local entries = {}

    for _, p in ipairs(room.players) do
        local distance
        if isElement(p) and (finish or hasStart) then
            local x, y, z = getElementPosition(p)
            local tx = finish and finish.x or startX
            local ty = finish and finish.y or startY
            local tz = finish and finish.z or startZ
            local dx, dy, dz = x - tx, y - ty, z - tz
            distance = math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) + 0.5)
        end

        entries[#entries + 1] = {
            name = getPlayerName(p) or '?',
            lives = room.lives[p] or 0,
            alive = true,
            me = p == player,
            distance = distance,
        }
    end

    for _, p in ipairs(room.spectators) do
        if room.lives[p] ~= nil then
            entries[#entries + 1] = {
                name = getPlayerName(p) or '?',
                lives = room.lives[p] or 0,
                alive = false,
                me = p == player,
                distance = nil,
            }
        end
    end

    table.sort(entries, function(a, b)
        if a.alive ~= b.alive then
            return a.alive
        end
        if ranking == 'finish' then
            local ad = a.distance or math.huge
            local bd = b.distance or math.huge
            if ad ~= bd then
                return ad < bd
            end
        elseif ranking == 'progress' then
            local ad = a.distance or -math.huge
            local bd = b.distance or -math.huge
            if ad ~= bd then
                return ad > bd
            end
        end
        if a.lives ~= b.lives then
            return a.lives > b.lives
        end
        return a.name < b.name
    end)

    for index, entry in ipairs(entries) do
        entry.rank = index
    end

    return {
        mode = 'competitive',
        alive = #room.players,
        total = #entries,
        waiting = room.waiting == true,
        finish = finish ~= nil,
        ranking = ranking,
        players = entries,
    }
end

function Rooms.eliminate(player, room)
    room = room or Rooms.playerRoom(player)
    if not room then
        return
    end

    local index
    for i, p in ipairs(room.players) do
        if p == player then
            index = i
            break
        end
    end
    if not index then
        return
    end

    table.remove(room.players, index)
    if not contains(room.spectators, player) then
        room.spectators[#room.spectators + 1] = player
    end

    room.ready[player] = nil
    clearFreezeTimer(player)
    if isElement(raceVehicles[player]) then
        destroyElement(raceVehicles[player])
    end
    raceVehicles[player] = nil
    if isElement(player) then
        setElementFrozen(player, false)
    end

    if #room.players == 0 then
        room.active = false
        room.roundEnds = 0
        room.waiting = false
    end

    stateChanged()
end

function Rooms.consumeLife(player)
    local room = Rooms.playerRoom(player)
    if not room or room.mode ~= 'competitive' then
        return false
    end
    if not room.active or room.waiting or not contains(room.players, player) then
        return false
    end

    local lives = room.lives[player]
    if type(lives) ~= 'number' or lives <= 0 then
        return false
    end

    lives = lives - 1
    room.lives[player] = lives
    local eliminated = lives <= 0

    if eliminated then
        Rooms.eliminate(player, room)
    else
        stateChanged()
    end

    return true, lives, eliminated
end

-- 主动选择纯 OB：本回合不参赛，后续回合也保持观战
function Rooms.becomeSpectator(player)
    local room = Rooms.playerRoom(player)
    if not room then
        return false, '不在舞台里'
    end

    if contains(room.spectators, player) then
        room.ob[player] = true
        room.lives[player] = nil
        room.ready[player] = nil
        stateChanged()
        return true
    end

    local index
    for i, p in ipairs(room.players) do
        if p == player then
            index = i
            break
        end
    end
    if not index then
        return false, '不在参赛列表中'
    end

    table.remove(room.players, index)
    if not contains(room.spectators, player) then
        room.spectators[#room.spectators + 1] = player
    end

    room.ob[player] = true
    room.lives[player] = nil
    room.ready[player] = nil

    clearFreezeTimer(player)
    if isElement(raceVehicles[player]) then
        destroyElement(raceVehicles[player])
    end
    raceVehicles[player] = nil
    if isElement(player) then
        setElementFrozen(player, false)
    end

    if #room.players == 0 then
        room.active = false
        room.roundEnds = 0
        room.waiting = false
    elseif room.waiting and allPlayersReady(room) then
        Rooms.beginCountdown(room)
    end

    stateChanged()
    return true
end

-- 从纯 OB 返回比赛：准备阶段立即上车，其他阶段下回合自动参赛
function Rooms.returnToRace(player)
    local room = Rooms.playerRoom(player)
    if not room then
        return false, '不在舞台里'
    end

    if contains(room.players, player) then
        room.ob[player] = nil
        stateChanged()
        return true, 'playing'
    end
    if not contains(room.spectators, player) then
        return false, '不在观战列表中'
    end

    room.ob[player] = nil

    if not room.active and not room.vote and not room.modeVote and #room.players == 0 then
        removePlayer(room.spectators, player)
        room.players[#room.players + 1] = player
        startRound(room)
        return true, 'started'
    end

    if room.active and room.waiting and room.mode == 'competitive' then
        removePlayer(room.spectators, player)
        room.players[#room.players + 1] = player
        room.ready[player] = false
        room.lives[player] = config.competitiveLives or 10
        spawnPlayerInRoom(player, room, false, true)
        stateChanged()
        return true, 'ready'
    end

    stateChanged()
    return true, 'next-round'
end

function Rooms.all()
    return rooms
end

function Rooms.get(id)
    return rooms[id]
end

function Rooms.playerRoom(player)
    for _, room in pairs(rooms) do
        if contains(room.players, player) then
            return room, 'playing'
        end
        if contains(room.spectators, player) then
            return room, 'spectating'
        end
    end
    return nil, nil
end

function Rooms.join(player, roomId)
    local room = rooms[roomId]
    if not room then
        return nil, nil
    end

    Rooms.leave(player)
    setElementDimension(player, room.dimension)

    -- 投票 / 回合进行中：加入者为观战
    if room.vote or room.modeVote or (room.active and #room.players > 0) then
        room.spectators[#room.spectators + 1] = player
        stateChanged()
        return 'spectating', room
    end

    -- 空房或上一回合已结束：直接开新回合，加入者参战
    room.players[#room.players + 1] = player
    startRound(room)
    return 'playing', room
end

function Rooms.leave(player)
    clearFreezeTimer(player)
    if isElement(player) then
        setElementFrozen(player, false)
    end

    if isElement(raceVehicles[player]) then
        destroyElement(raceVehicles[player])
    end
    raceVehicles[player] = nil

    for _, room in pairs(rooms) do
        local removed = removePlayer(room.players, player)
        if removePlayer(room.spectators, player) then
            removed = true
        end

        if removed then
            room.ready[player] = nil
            room.lives[player] = nil
            room.ob[player] = nil

            if #room.players == 0 then
                room.active = false
                room.roundEnds = 0
                room.vote = nil
                room.modeVote = nil
                room.waiting = false
                room.ready = {}

                -- 只有完全空房才重置模式和纯 OB 标记；只剩观战者时保留偏好
                if #room.spectators == 0 then
                    room.lives = {}
                    room.ob = {}
                    room.mode = config.defaultMode or 'training'
                    room.lastVoteAt = 0
                    room.lastModeVoteAt = 0
                end
            elseif room.waiting and allPlayersReady(room) then
                Rooms.beginCountdown(room)
            end
            stateChanged()
        end
    end
end

function Rooms.tick()
    local time = now()

    for _, room in pairs(rooms) do
        if room.modeVote then
            if time >= room.modeVote.endsAt then
                Rooms.finishModeVote(room)
            end
        elseif room.vote then
            if time >= room.vote.endsAt then
                Rooms.finishVote(room)
            end
        elseif room.active and #room.players > 0 and time >= room.roundEnds then
            Rooms.startVote(room, 'auto')
        end
    end

    stateChanged()
end

function Rooms.startVote(room, reason)
    reason = reason or 'manual'

    if not room then
        return false, '舞台不存在'
    end
    if room.vote then
        return false, '当前已经有投票了'
    end
    if room.modeVote then
        return false, '当前正在进行模式投票'
    end
    if not room.active then
        return false, '当前没有进行中的比赛'
    end
    if room.waiting then
        return false, '等待玩家准备中，无法发起投票'
    end
    if #room.players == 0 and #room.spectators == 0 then
        return false, '舞台里没有玩家'
    end

    if reason ~= 'auto' and (config.voteCooldown or 0) > 0 then
        local last = room.lastVoteAt or 0
        if last > 0 then
            local remaining = (config.voteCooldown or 0) - (now() - last)
            if remaining > 0 then
                return false, ('投票冷却中，还需 %d 秒'):format(math.ceil(remaining))
            end
        end
    end

    local options = pickVoteOptions(room)
    if #options == 0 then
        return false, '没有可投票的地图'
    end

    room.lastVoteAt = now()
    room.active = false
    room.roundEnds = 0
    room.vote = {
        options = options,
        votes = {},
        endsAt = now() + config.voteSeconds,
    }

    stateChanged()
    return true
end

function Rooms.castVote(room, player, mapId)
    if not room or not room.vote then
        return false, '当前没有投票'
    end

    local valid = false
    for _, option in ipairs(room.vote.options) do
        if option.id == mapId then
            valid = true
            break
        end
    end

    if not valid then
        return false, '无效的选项'
    end
    if room.vote.votes[player] then
        return false, '你已经投过票了'
    end

    room.vote.votes[player] = mapId
    stateChanged()

    if Rooms.allVoted(room) then
        Rooms.finishVote(room)
    end

    return true
end

function Rooms.allVoted(room)
    if not room.vote then
        return false
    end

    local voted = 0
    for _, player in ipairs(room.players) do
        if room.vote.votes[player] then
            voted = voted + 1
        end
    end
    for _, player in ipairs(room.spectators) do
        if room.vote.votes[player] then
            voted = voted + 1
        end
    end

    local eligible = #room.players + #room.spectators
    return eligible > 0 and voted >= eligible
end

function Rooms.finishVote(room)
    if not room or not room.vote then
        return
    end

    local vote = room.vote
    local counts = {}
    for _, mapId in pairs(vote.votes) do
        counts[mapId] = (counts[mapId] or 0) + 1
    end

    -- 规则：票数最多 → 流行度更高 → 随机
    local bestCount = -1
    local bestPopularity = -1
    local tied = {}

    for _, option in ipairs(vote.options) do
        local count = counts[option.id] or 0
        local popularity = option.popularity or 0

        if count > bestCount or (count == bestCount and popularity > bestPopularity) then
            bestCount = count
            bestPopularity = popularity
            tied = { option.id }
        elseif count == bestCount and popularity == bestPopularity then
            tied[#tied + 1] = option.id
        end
    end

    local winner = tied[math.random(#tied)] or vote.options[1].id

    room.vote = nil
    startRound(room, winner)
    stateChanged()
end

local MODE_NAMES = {
    training = '训练模式',
    competitive = '竞技模式',
}

function Rooms.startModeVote(room)
    if not room then
        return false, '舞台不存在'
    end
    if room.vote or room.modeVote then
        return false, '当前已经有投票了'
    end
    if not room.active then
        return false, '当前没有进行中的比赛'
    end
    if room.waiting then
        return false, '等待玩家准备中，无法发起模式投票'
    end
    if #room.players == 0 and #room.spectators == 0 then
        return false, '舞台里没有玩家'
    end

    local cooldown = config.modeVoteCooldown or 0
    local last = room.lastModeVoteAt or 0
    if cooldown > 0 and last > 0 then
        local remaining = cooldown - (now() - last)
        if remaining > 0 then
            return false, ('模式投票冷却中，还需 %d 秒'):format(math.ceil(remaining))
        end
    end

    local lives = config.competitiveLives or 10
    local options = {
        {
            id = 'training',
            name = MODE_NAMES.training,
            description = '无限 rewind，自由练习',
        },
        {
            id = 'competitive',
            name = MODE_NAMES.competitive,
            description = ('每人 %d 条命，每次 rewind 消耗 1 条'):format(lives),
        },
    }

    room.lastModeVoteAt = now()
    room.active = false
    room.roundEnds = 0
    room.modeVote = {
        options = options,
        votes = {},
        endsAt = now() + (config.modeVoteSeconds or 20),
    }

    stateChanged()
    return true
end

function Rooms.castModeVote(room, player, modeId)
    if not room or not room.modeVote then
        return false, '当前没有模式投票'
    end

    local valid = false
    for _, option in ipairs(room.modeVote.options) do
        if option.id == modeId then
            valid = true
            break
        end
    end
    if not valid then
        return false, '无效的模式选项'
    end
    if room.modeVote.votes[player] then
        return false, '你已经投过票了'
    end

    room.modeVote.votes[player] = modeId
    stateChanged()

    if Rooms.allModeVoted(room) then
        Rooms.finishModeVote(room)
    end
    return true
end

function Rooms.allModeVoted(room)
    if not room.modeVote then
        return false
    end

    local voted = 0
    for _, player in ipairs(room.players) do
        if room.modeVote.votes[player] then
            voted = voted + 1
        end
    end
    for _, player in ipairs(room.spectators) do
        if room.modeVote.votes[player] then
            voted = voted + 1
        end
    end

    local eligible = #room.players + #room.spectators
    return eligible > 0 and voted >= eligible
end

function Rooms.finishModeVote(room)
    if not room or not room.modeVote then
        return
    end

    local vote = room.modeVote
    local counts = {}
    for _, modeId in pairs(vote.votes) do
        counts[modeId] = (counts[modeId] or 0) + 1
    end

    local bestCount = -1
    local tied = {}
    for _, option in ipairs(vote.options) do
        local count = counts[option.id] or 0
        if count > bestCount then
            bestCount = count
            tied = { option.id }
        elseif count == bestCount then
            tied[#tied + 1] = option.id
        end
    end

    -- 平票或没人投票时保持当前模式
    local winner
    if bestCount <= 0 or contains(tied, room.mode) then
        winner = room.mode
    else
        winner = tied[math.random(#tied)]
    end

    room.modeVote = nil
    room.mode = winner
    startRound(room, room.mapId)
    stateChanged()
end

function Rooms.modeVoteState(room, player)
    if not room or not room.modeVote then
        return nil
    end

    local counts = {}
    for _, modeId in pairs(room.modeVote.votes) do
        counts[modeId] = (counts[modeId] or 0) + 1
    end

    local options = {}
    for _, option in ipairs(room.modeVote.options) do
        options[#options + 1] = {
            id = option.id,
            name = option.name,
            description = option.description,
            votes = counts[option.id] or 0,
        }
    end

    return {
        active = true,
        timeLeft = math.max(0, room.modeVote.endsAt - now()),
        currentMode = room.mode,
        options = options,
        mine = room.modeVote.votes[player],
    }
end

function Rooms.summary(room)
    local map = room.mapId and config.maps[room.mapId]
    return {
        id = room.id,
        name = room.name,
        mapName = map and map.name or '等待开始',
        author = map and map.author or '未知作者',
        players = #room.players,
        spectators = #room.spectators,
        active = room.active,
        timeLeft = room.active and math.max(0, room.roundEnds - now()) or 0,
        voteActive = room.vote ~= nil,
        gameMode = room.mode,
        waiting = room.waiting == true,
    }
end

function Rooms.voteState(room, player)
    if not room or not room.vote then
        return nil
    end

    local counts = {}
    for _, mapId in pairs(room.vote.votes) do
        counts[mapId] = (counts[mapId] or 0) + 1
    end

    local options = {}
    for _, option in ipairs(room.vote.options) do
        local map = config.maps[option.id]
        options[#options + 1] = {
            id = option.id,
            name = option.name,
            author = map and map.author or '未知作者',
            popularity = MapStats.popularity(option.id),
            plays = MapStats.getPlays(option.id),
            votes = counts[option.id] or 0,
        }
    end

    return {
        active = true,
        timeLeft = math.max(0, room.vote.endsAt - now()),
        options = options,
        mine = room.vote.votes[player],
    }
end

function Rooms.handleDeath(player)
    local room = Rooms.playerRoom(player)
    if not room or not room.active or not contains(room.players, player) then
        return
    end

    setTimer(function()
        if not isElement(player) then
            return
        end

        local currentRoom = Rooms.playerRoom(player)
        if currentRoom == room and room.active and contains(room.players, player) then
            spawnPlayerInRoom(player, room, false)
        end
    end, config.respawnDelay, 1)
end
