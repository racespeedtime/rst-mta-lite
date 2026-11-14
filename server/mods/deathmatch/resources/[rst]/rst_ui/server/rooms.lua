--[[
    rst_ui / server/rooms.lua

    两个 DeathMatch 房间：
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

local function spawnPlayerInRoom(player, room, countdown)
    local map = config.maps[room.mapId]
    if not map or not isElement(player) then
        return
    end

    local x = map.x + math.random(-3, 3)
    local y = map.y + math.random(-3, 3)
    local z = map.z + 1.0

    spawnPlayer(player, x, y, z, map.rot + math.random(-15, 15))
    setElementDimension(player, room.dimension)
    setElementHealth(player, 100)
    setPedArmor(player, 50)
    takeAllWeapons(player)
    giveWeapon(player, config.weapon, config.ammo, true)

    if freezeTimers[player] then
        killTimer(freezeTimers[player])
        freezeTimers[player] = nil
    end

    -- 进入回合的玩家先冻结，播完 3-2-1-GO 再允许移动
    if countdown and (config.spawnCountdown or 0) > 0 then
        setElementFrozen(player, true)
        triggerClientEvent(player, 'rst:ui:countdown', player, toJSON({
            seconds = config.spawnCountdown,
        }))

        freezeTimers[player] = setTimer(function()
            freezeTimers[player] = nil
            if isElement(player) then
                setElementFrozen(player, false)
            end
        end, math.floor(config.spawnCountdown * 1000) + 250, 1)
    else
        setElementFrozen(player, false)
    end
end

local function startRound(room, forcedMapId)
    room.mapId = forcedMapId or pickMap(room)
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
            Rooms.startVote(room)
        end
    end

    stateChanged()
end

function Rooms.startVote(room)
    if not room then
        return false, '舞台不存在'
    end
    if room.vote then
        return false, '当前已经有投票了'
    end
    if not room.active then
        return false, '当前没有进行中的回合'
    end
    if #room.players == 0 and #room.spectators == 0 then
        return false, '舞台里没有玩家'
    end

    local pool = {}
    for _, mapId in ipairs(config.mapPool) do
        if mapId ~= room.mapId then
            pool[#pool + 1] = mapId
        end
    end
    if #pool == 0 then
        for _, mapId in ipairs(config.mapPool) do
            pool[#pool + 1] = mapId
        end
    end

    local options = {}
    while #options < 3 and #pool > 0 do
        local index = math.random(#pool)
        local mapId = table.remove(pool, index)
        options[#options + 1] = { id = mapId, name = config.maps[mapId].name }
    end

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

    local winner
    local best = -1
    for _, option in ipairs(vote.options) do
        local count = counts[option.id] or 0
        if count > best then
            best = count
            winner = option.id
        end
    end

    if not winner then
        winner = vote.options[math.random(#vote.options)].id
    end

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
