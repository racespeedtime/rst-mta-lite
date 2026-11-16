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

-- mtavault 元数据索引：地图池排序（下载量 / 上传日期）会频繁读取，避免逐图查 SQLite
local downloadsByResource, downloadsBySlug, downloadsByFile, downloadsByName = {}, {}, {}, {}
local uploadedByResource, uploadedBySlug, uploadedByFile = {}, {}, {}
local metaNames = {}

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

local function slugFromSourceUrl(url)
    local slug = tostring(url or ''):match('/map/([^/?#]+)')
    return slug and slug:lower() or nil
end

local function loadMetaIndex()
    downloadsByResource, downloadsBySlug, downloadsByFile, downloadsByName = {}, {}, {}, {}
    uploadedByResource, uploadedBySlug, uploadedByFile = {}, {}, {}
    metaNames = {}

    local handle = dbQuery(db, [[
        SELECT resource, source_url, name_norm, file_name_norm, downloads, uploaded_at
        FROM map_meta
    ]])
    if not handle then
        return
    end
    local rows = dbPoll(handle, -1)
    if not rows then
        return
    end

    for _, row in ipairs(rows) do
        local downloads = tonumber(row.downloads) or 0
        local resource = tostring(row.resource or '')
        local slug = slugFromSourceUrl(row.source_url)
        local nameNorm = tostring(row.name_norm or '')
        local fileNorm = tostring(row.file_name_norm or '')
        local uploaded = tostring(row.uploaded_at or '')

        if resource ~= '' then
            downloadsByResource[resource] = downloads
            if uploaded ~= '' then
                uploadedByResource[resource] = uploaded
            end
        end
        if slug then
            downloadsBySlug[slug] = downloads
            if uploaded ~= '' then
                uploadedBySlug[slug] = uploaded
            end
        end
        if fileNorm ~= '' then
            downloadsByFile[fileNorm] = downloads
            if uploaded ~= '' then
                uploadedByFile[fileNorm] = uploaded
            end
        end
        if nameNorm ~= '' then
            downloadsByName[nameNorm] = downloads
            metaNames[#metaNames + 1] = {
                name = nameNorm,
                downloads = downloads,
            }
        end
    end

    -- 长名称优先匹配，避免 "Silent Hill" 被更短的名字抢先
    table.sort(metaNames, function(a, b)
        return #a.name > #b.name
    end)
end

function MapMeta.downloads(resource, name, author)
    resource = tostring(resource or '')
    if resource ~= '' then
        if downloadsByResource[resource] then
            return downloadsByResource[resource]
        end
        local slug = resource:lower()
        if downloadsBySlug[slug] then
            return downloadsBySlug[slug]
        end
        local fileNorm = normalize(resource)
        if downloadsByFile[fileNorm] then
            return downloadsByFile[fileNorm]
        end
    end

    local nameNorm = normalize(name)
    if nameNorm ~= '' then
        if downloadsByName[nameNorm] then
            return downloadsByName[nameNorm]
        end
        -- 兼容 mtavault 名称被地图 meta 加上前缀的情况，例如 "[DM] X - Silent Hill"
        for _, candidate in ipairs(metaNames) do
            if nameNorm:find(candidate.name, 1, true) then
                return candidate.downloads
            end
        end
    end

    return 0
end

-- 地图池启动时按 id 批量取下载量：只做精确匹配，避免 4486 次子串扫描拖慢开服
function MapMeta.downloadsForId(resource)
    local key = tostring(resource or '')
    if key == '' then
        return 0
    end
    if downloadsByResource[key] then
        return downloadsByResource[key]
    end
    local slug = key:lower()
    if downloadsBySlug[slug] then
        return downloadsBySlug[slug]
    end
    local fileNorm = normalize(key)
    if downloadsByFile[fileNorm] then
        return downloadsByFile[fileNorm]
    end
    return 0
end

-- 上传日期（YYYY-MM-DD）：和下载量同一套索引，只做精确匹配
function MapMeta.uploadedForId(resource)
    local key = tostring(resource or '')
    if key == '' then
        return nil
    end
    if uploadedByResource[key] then
        return uploadedByResource[key]
    end
    local slug = key:lower()
    if uploadedBySlug[slug] then
        return uploadedBySlug[slug]
    end
    local fileNorm = normalize(key)
    if uploadedByFile[fileNorm] then
        return uploadedByFile[fileNorm]
    end
    return nil
end

local function rowToMeta(row)
    if not row then
        return nil
    end
    local tags = fromJSON(row.tags or '[]')
    if type(tags) == 'table' and type(tags[1]) == 'table' then
        tags = tags[1]
    end
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

    loadMetaIndex()
    local rows = countRows()
    outputServerLog(('[MAPMETA] sqlite rows=%d'):format(rows))
    if rows == 0 then
        outputServerLog('[MAPMETA] metadata DB is empty; run: node tools/mtavault/install-mapmeta-db.mjs')
    end
    return true
end
