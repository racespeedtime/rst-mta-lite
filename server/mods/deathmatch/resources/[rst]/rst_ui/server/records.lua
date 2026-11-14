--[[
    rst_ui / server/records.lua

    玩家在当前地图的个人最佳完赛成绩。
    按 serial + 地图 resource 持久化到 SQLite。
]]

Records = {}

local db
local cache = {}

local function cacheKey(serial, mapId)
    return serial .. '\0' .. mapId
end

function Records.init()
    cache = {}
    db = dbConnect('sqlite', ':/rst_ui_records.db')
    if not db then
        outputServerLog('[rst_ui] 无法连接个人纪录数据库')
        return false
    end

    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS records (
            serial TEXT NOT NULL,
            map_id TEXT NOT NULL,
            best_seconds INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (serial, map_id)
        )
    ]])
    return true
end

local function serialOf(player)
    if not isElement(player) then
        return nil
    end
    return getPlayerSerial(player)
end

function Records.getBest(player, mapId)
    if not db or type(mapId) ~= 'string' then
        return nil
    end

    local serial = serialOf(player)
    if not serial then
        return nil
    end

    local key = cacheKey(serial, mapId)
    if cache[key] ~= nil then
        return cache[key] or nil
    end

    local handle = dbQuery(
        db,
        'SELECT best_seconds FROM records WHERE serial = ? AND map_id = ? LIMIT 1',
        serial,
        mapId
    )
    if not handle then
        return nil
    end

    local rows = dbPoll(handle, -1)
    local row = rows and rows[1]
    local best = row and tonumber(row.best_seconds) or nil
    cache[key] = best or false
    return best
end

function Records.record(player, mapId, seconds)
    if not db or type(mapId) ~= 'string' then
        return nil
    end

    seconds = math.floor(tonumber(seconds) or 0)
    if seconds <= 0 then
        return nil
    end

    local serial = serialOf(player)
    if not serial then
        return nil
    end

    local previous = Records.getBest(player, mapId)
    if previous and previous <= seconds then
        return previous
    end

    dbExec(
        db,
        [[
            INSERT OR REPLACE INTO records (serial, map_id, best_seconds, updated_at)
            VALUES (?, ?, ?, ?)
        ]],
        serial,
        mapId,
        seconds,
        getRealTime().timestamp
    )

    cache[cacheKey(serial, mapId)] = seconds
    return seconds
end
