--[[
    rst_ui / server/mapmeta.lua

    地图外部展示元数据。
    主存储是 SQLite（map_meta），数据库由 tools/mtavault/seed 安装，
    服务端只查询，不再从 JSON catalog 导入。
]]

MapMeta = {}

local db
local cache = {}
local DB_PATH = ':/rst_ui_mapmeta.db'

local function normalize(value)
    return tostring(value or ''):lower():gsub('[^%w]', '')
end

local function queryOne(sql, params)
    if not db then
        return nil
    end
    local handle = dbQuery(db, sql, unpack(params or {}))
    if not handle then
        return nil
    end
    local result = dbPoll(handle, -1)
    dbFree(handle)
    return type(result) == 'table' and result[1] or nil
end

local function countRows()
    local row = queryOne('SELECT COUNT(*) AS total FROM map_meta WHERE mtavault_id IS NOT NULL')
    return row and tonumber(row.total) or 0
end

local function rowToMeta(row)
    if not row then
        return nil
    end
    local tags = fromJSON(row.tags or '[]')
    return {
        mtavaultId = row.mtavault_id,
        mapType = row.map_type,
        name = row.name,
        authors = row.authors,
        cover = row.cover,
        youtube = row.youtube,
        sourceUrl = row.source_url,
        uploadedAt = row.uploaded_at,
        downloads = tonumber(row.downloads),
        difficulty = row.difficulty,
        fileSize = tonumber(row.file_size),
        tags = type(tags) == 'table' and tags or {},
    }
end

function MapMeta.get(resource, name, author)
    if not resource then
        return nil
    end
    if cache[resource] ~= nil then
        return cache[resource] or nil
    end

    local row = queryOne('SELECT * FROM map_meta WHERE resource = ? LIMIT 1', { resource })
    if not row then
        row = queryOne('SELECT * FROM map_meta WHERE file_name_norm = ? LIMIT 1', { normalize(resource) })
    end
    if not row then
        local nameNorm = normalize(name)
        local authorNorm = normalize(author)
        if nameNorm ~= '' then
            row = queryOne([[
                SELECT * FROM map_meta
                WHERE instr(?, name_norm) > 0
                  AND (? = '' OR instr(?, author_norm) > 0)
                ORDER BY length(name_norm) DESC
                LIMIT 1
            ]], { nameNorm, authorNorm, authorNorm })
        end
    end

    local meta = rowToMeta(row)
    if meta then
        if row.resource ~= resource then
            dbExec(db, 'UPDATE map_meta SET resource = ? WHERE mtavault_id = ?', resource, row.mtavault_id)
        end
        cache[resource] = meta
    else
        cache[resource] = false
    end
    return meta
end

function MapMeta.count()
    return countRows()
end

function MapMeta.init()
    db = dbConnect('sqlite', DB_PATH)
    if not db then
        outputServerLog('[MAPMETA] failed to open ' .. DB_PATH)
        return false
    end

    local ok = dbExec(db, [[
        CREATE TABLE IF NOT EXISTS map_meta (
            mtavault_id TEXT PRIMARY KEY,
            resource TEXT,
            name TEXT,
            name_norm TEXT,
            authors TEXT,
            author_norm TEXT,
            file_name TEXT,
            file_name_norm TEXT,
            cover TEXT,
            youtube TEXT,
            source_url TEXT,
            uploaded_at TEXT,
            downloads INTEGER,
            file_size INTEGER,
            tags TEXT,
            map_type TEXT,
            updated_at INTEGER,
            difficulty TEXT
        )
    ]])
    if not ok then
        outputServerLog('[MAPMETA] failed to create map_meta table')
        return false
    end

    dbExec(db, 'CREATE INDEX IF NOT EXISTS idx_map_meta_resource ON map_meta(resource)')
    dbExec(db, 'CREATE INDEX IF NOT EXISTS idx_map_meta_file_name ON map_meta(file_name_norm)')
    dbExec(db, 'CREATE INDEX IF NOT EXISTS idx_map_meta_name ON map_meta(name_norm)')

    local rows = countRows()
    outputServerLog(('[MAPMETA] sqlite rows=%d'):format(rows))
    if rows == 0 then
        outputServerLog('[MAPMETA] metadata DB is empty; run: node tools/mtavault/install-mapmeta-db.mjs')
    end
    return true
end
