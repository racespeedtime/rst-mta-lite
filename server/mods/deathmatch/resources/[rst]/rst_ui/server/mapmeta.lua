--[[
    rst_ui / server/mapmeta.lua

    地图外部展示元数据。
    主存储是 SQLite（map_meta），不再使用单文件 mapmeta.json。
    mtavault 全量 DM/HDM 目录由 tools/mtavault/fetch-mapmeta.mjs 抓取，
    首次启动时导入 catalog，之后按地图 resource 懒查询。
]]

MapMeta = {}

local db
local cache = {}
local DB_PATH = ':/rst_ui_mapmeta.db'
local CATALOG_PATH = 'mapmeta-catalog.json'

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

local function countCatalogRows()
    local row = queryOne('SELECT COUNT(*) AS total FROM map_meta WHERE mtavault_id IS NOT NULL')
    return row and tonumber(row.total) or 0
end

local function videoUrl(value)
    value = tostring(value or '')
    if value == '' then
        return nil
    end
    if value:find('^https?://') then
        return value
    end
    return 'https://www.youtube.com/watch?v=' .. value
end

local function importCatalog()
    local handle = fileOpen(CATALOG_PATH, true)
    if not handle then
        outputServerLog('[MAPMETA] catalog not found: ' .. CATALOG_PATH)
        return 0
    end

    local size = fileGetSize(handle)
    local text = size > 0 and fileRead(handle, size) or ''
    fileClose(handle)

    local data = fromJSON(text or '')
    if type(data) ~= 'table' or type(data.maps) ~= 'table' then
        outputServerLog('[MAPMETA] invalid catalog JSON')
        return 0
    end

    local rows = data.maps
    if countCatalogRows() >= #rows then
        return #rows
    end

    local imported = 0
    for _, map in ipairs(rows) do
        local tags = type(map.tags) == 'table' and map.tags or {}
        local mapType = 'DM'
        for _, tag in ipairs(tags) do
            if tostring(tag):upper() == 'HDM' then
                mapType = 'HDM'
            end
        end
        if tostring(map.fileName or ''):find('%[HDM%]') then
            mapType = 'HDM'
        end

        local authors = type(map.authors) == 'table'
            and table.concat(map.authors, ', ')
            or tostring(map.authors or '')

        dbExec(db, [[
            INSERT OR REPLACE INTO map_meta
                (mtavault_id, resource, name, name_norm, authors, author_norm,
                 file_name, file_name_norm, cover, youtube, source_url, uploaded_at,
                 downloads, difficulty, file_size, tags, map_type, updated_at)
            VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]],
            tostring(map.id or ''),
            tostring(map.name or ''),
            normalize(map.name),
            authors,
            normalize(authors),
            tostring(map.fileName or ''),
            normalize(map.fileName),
            map.coverUrl or map.coverLocal or '',
            videoUrl(map.videoUrl) or '',
            map.sourceUrl or '',
            map.uploadedAt or '',
            tonumber(map.popularity) or 0,
            map.difficulty or '',
            tonumber(map.fileSize) or 0,
            toJSON(tags),
            mapType,
            os.time()
        )
        imported = imported + 1
    end
    outputServerLog(('[MAPMETA] imported %d mtavault DM/HDM rows'):format(imported))
    return imported
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
    return countCatalogRows()
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

    importCatalog()
    outputServerLog(('[MAPMETA] sqlite rows=%d'):format(countCatalogRows()))
    return true
end
