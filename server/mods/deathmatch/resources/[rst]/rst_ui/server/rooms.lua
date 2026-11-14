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

local function now()
    return getRealTime().timestamp
end

local function contains(list, player)
    for i = 1, #list do
        if list[i] == player then
            return true
        end
    end
    return false
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

local function spawnPlayerInRoom(player, room, countdown)
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

    if freezeTimers[player] then
        killTimer(freezeTimers[player])
        freezeTimers[player] = nil
    end

    local function setFrozen(state)
        if isElement(player) then
            setElementFrozen(player, state)
        end
        local car = raceVehicles[player]
        if isElement(car) then
            setElementFrozen(car, state)
        end
    end

    -- 进入回合的玩家先冻结，播完 3-2-1-GO 再允许移动
    if countdown and (config.spawnCountdown or 0) > 0 then
        setFrozen(true)
        triggerClientEvent(player, 'rst:ui:countdown', player, toJSON({
            seconds = config.spawnCountdown,
        }))

        freezeTimers[player] = setTimer(function()
            freezeTimers[player] = nil
            setFrozen(false)
        end, math.floor(config.spawnCountdown * 1000) + 250, 1)
    else
        setFrozen(false)
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

    -- 新回合开始，观战者转为玩家一起出生
    for _, player in ipairs(room.spectators) do
        room.players[#room.players + 1] = player
    end
    room.spectators = {}

    for _, player in ipairs(room.players) do
        if isElement(player) then
            spawnPlayerInRoom(player, room, true)
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
            recentMaps = {},
            lastVoteAt = 0,
        }
    end

    setTimer(Rooms.tick, 1000, 0)
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
    if room.vote or (room.active and #room.players > 0) then
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
    if freezeTimers[player] then
        killTimer(freezeTimers[player])
        freezeTimers[player] = nil
        if isElement(player) then
            setElementFrozen(player, false)
        end
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
            if #room.players == 0 then
                room.active = false
                room.roundEnds = 0
                room.vote = nil
            end
            stateChanged()
        end
    end
end

function Rooms.tick()
    local time = now()

    for _, room in pairs(rooms) do
        if room.vote then
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
    if not room.active then
        return false, '当前没有进行中的比赛'
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
    if not room or not room.active then
        return
    end

    setTimer(function()
        if not isElement(player) then
            return
        end

        local currentRoom = Rooms.playerRoom(player)
        if currentRoom == room and room.active then
            spawnPlayerInRoom(player, room, false)
        end
    end, config.respawnDelay, 1)
end
