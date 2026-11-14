--[[
    rst_ui / server/mapstats.lua

    地图游玩次数统计：
    - 持久化到 SQLite，服务端启动时加载
    - 有效热度 = 配置里的基础热度（未来可由爬虫写入）+ 游玩次数 * playPopularityWeight
]]

MapStats = {}

local db
local plays = {}

function MapStats.init()
    db = dbConnect('sqlite', ':/rst_ui_mapstats.db')
    if not db then
        outputServerLog('[rst_ui] 无法连接地图统计数据库')
        return false
    end

    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS map_stats (
            map_id TEXT PRIMARY KEY,
            plays INTEGER NOT NULL DEFAULT 0
        )
    ]])

    local handle = dbQuery(db, 'SELECT map_id, plays FROM map_stats')
    if handle then
        local rows = dbPoll(handle, -1)
        if rows then
            for _, row in ipairs(rows) do
                plays[row.map_id] = tonumber(row.plays) or 0
            end
        end
    end

    return true
end

function MapStats.getPlays(mapId)
    return plays[mapId] or 0
end

function MapStats.popularity(mapId)
    local map = RST.config.maps[mapId]
    local base = map and tonumber(map.popularity) or 0
    local weight = RST.config.playPopularityWeight or 0
    return base + MapStats.getPlays(mapId) * weight
end

function MapStats.recordPlay(mapId)
    if type(mapId) ~= 'string' then
        return
    end

    plays[mapId] = (plays[mapId] or 0) + 1

    if db then
        dbExec(db, 'INSERT OR IGNORE INTO map_stats (map_id, plays) VALUES (?, 0)', mapId)
        dbExec(db, 'UPDATE map_stats SET plays = plays + 1 WHERE map_id = ?', mapId)
    end
end
