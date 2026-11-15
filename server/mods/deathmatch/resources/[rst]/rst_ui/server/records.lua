--[[
    rst_ui / server/records.lua

    玩家在当前地图的个人最佳完赛成绩。
    统一使用毫秒，按 serial + 地图 resource 持久化到 SQLite。
]]

Records = {}

local db
local cache = {}

local function cacheKey(serial, mapId)
    return serial .. '\0' .. mapId
end

local function tableColumns(tableName)
    local handle = dbQuery(db, ('PRAGMA table_info(%s)'):format(tableName))
    if not handle then
        return {}
    end
    local rows = dbPoll(handle, -1) or {}
    local columns = {}
    for _, row in ipairs(rows) do
        columns[tostring(row.name)] = true
    end
    return columns
end

local function migrateSchema()
    local columns = tableColumns('records')
    if next(columns) == nil then
        dbExec(db, [[
            CREATE TABLE records (
                serial TEXT NOT NULL,
                map_id TEXT NOT NULL,
                name TEXT,
                best_ms INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY (serial, map_id)
            )
        ]])
        return
    end

    if not columns.name then
        dbExec(db, 'ALTER TABLE records ADD COLUMN name TEXT')
        columns.name = true
    end

    if columns.best_ms then
        return
    end

    -- 旧版本是 best_seconds，迁移成毫秒后删除旧列结构
    dbExec(db, 'ALTER TABLE records RENAME TO records_old')
    dbExec(db, [[
        CREATE TABLE records (
            serial TEXT NOT NULL,
            map_id TEXT NOT NULL,
            name TEXT,
            best_ms INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (serial, map_id)
        )
    ]])
    if columns.best_seconds then
        dbExec(db, [[
            INSERT INTO records (serial, map_id, best_ms, updated_at)
            SELECT serial, map_id, CAST(best_seconds * 1000 AS INTEGER), updated_at
            FROM records_old
        ]])
    end
    dbExec(db, 'DROP TABLE records_old')
end

function Records.init()
    cache = {}
    db = dbConnect('sqlite', ':/rst_ui_records.db')
    if not db then
        outputServerLog('[rst_ui] 无法连接个人纪录数据库')
        return false
    end

    migrateSchema()
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
        'SELECT best_ms FROM records WHERE serial = ? AND map_id = ? LIMIT 1',
        serial,
        mapId
    )
    if not handle then
        return nil
    end

    local rows = dbPoll(handle, -1)
    local row = rows and rows[1]
    local best = row and tonumber(row.best_ms) or nil
    cache[key] = best or false
    return best
end

function Records.record(player, mapId, milliseconds)
    if not db or type(mapId) ~= 'string' then
        return nil
    end

    milliseconds = math.floor(tonumber(milliseconds) or 0)
    if milliseconds <= 0 then
        return nil
    end

    local serial = serialOf(player)
    if not serial then
        return nil
    end

    local previous = Records.getBest(player, mapId)
    if previous and previous <= milliseconds then
        return previous
    end

    dbExec(
        db,
        [[
            INSERT OR REPLACE INTO records (serial, map_id, name, best_ms, updated_at)
            VALUES (?, ?, ?, ?, ?)
        ]],
        serial,
        mapId,
        getPlayerName(player) or '',
        milliseconds,
        getRealTime().timestamp
    )

    cache[cacheKey(serial, mapId)] = milliseconds
    return milliseconds
end

function Records.leaderboard(mapId, page, pageSize)
    if not db or type(mapId) ~= 'string' then
        return {
            page = 1,
            pageSize = 20,
            total = 0,
            pages = 1,
            items = {},
        }
    end

    page = math.max(1, math.floor(tonumber(page) or 1))
    pageSize = math.max(1, math.min(100, math.floor(tonumber(pageSize) or 20)))

    local countRow
    local countHandle = dbQuery(db, 'SELECT COUNT(*) AS total FROM records WHERE map_id = ?', mapId)
    if countHandle then
        local rows = dbPoll(countHandle, -1)
        countRow = rows and rows[1]
    end

    local total = countRow and tonumber(countRow.total) or 0
    local pages = math.max(1, math.ceil(total / pageSize))
    page = math.min(page, pages)
    local offset = (page - 1) * pageSize

    local items = {}
    local handle = dbQuery(
        db,
        [[
            SELECT name, best_ms, updated_at
            FROM records
            WHERE map_id = ?
            ORDER BY best_ms ASC, updated_at ASC
            LIMIT ? OFFSET ?
        ]],
        mapId,
        pageSize,
        offset
    )
    if handle then
        local rows = dbPoll(handle, -1) or {}
        for index, row in ipairs(rows) do
            items[#items + 1] = {
                rank = offset + index,
                name = (row.name and row.name ~= '') and row.name or '未知玩家',
                bestMs = tonumber(row.best_ms) or 0,
                updatedAt = tonumber(row.updated_at) or 0,
            }
        end
    end

    return {
        page = page,
        pageSize = pageSize,
        total = total,
        pages = pages,
        items = items,
    }
end
