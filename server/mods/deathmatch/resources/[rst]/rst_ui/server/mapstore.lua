--[[
    rst_ui / server/mapstore.lua

    按需地图资源 + 地图级客户端静态资源缓存：

    - [rst]/maplib 是纯数据 resource：maps/<id>/ 里是展开后的地图文件。
    - 每张玩过的地图使用独立槽位 resource：rst_map_<mapId>。
      MTA 客户端按 resource 名缓存声明的客户端文件；地图 XML 和运行世界仍会
      在每次启动地图 resource 时重新加载/构建。
    - 第一次进入某张图时才创建槽位并复制文件；之后只启动已有槽位，
      不再删除 / 覆盖其他地图的槽位。
    - 未被启动的槽位不会加载地图文件；开服时间仍与地图库规模基本无关。

    槽位文件保留在服务器上可避免重复复制；客户端静态文件也可按 resource 名
    复用。如需清理，可手动删除 resources/[rst]/rst_map_* 目录，下次进入会
    重新创建 / 复制槽位。
]]

MapStore = {}

local LIB_NAME = 'maplib'
local SLOT_PREFIX_NAME = 'rst_map'
local SLOT_ORG_DIR = '[rst]'
local LIB_MAPS = ':' .. LIB_NAME .. '/maps/'
local INDEX_PATH = ':' .. LIB_NAME .. '/index.json'

local INDEX_MAX_BYTES = 64 * 1024 * 1024
local LIST_MAX_BYTES = 1024 * 1024
local COPY_CHUNK_MS = 8          -- 每个 tick 最多复制这么久，避免卡住主线程
local COPY_TICK_MS = 30
local REFRESH_TIMEOUT_MS = 10000 -- 槽位重新加载的等待上限
local REFRESH_POLL_MS = 100

MapStore.libraryName = LIB_NAME
MapStore.slotPrefix = SLOT_PREFIX_NAME

local index = {}          -- id -> { id, name, author, map, dimension, bytes, files }
local ids = {}            -- 排序后的地图 id 列表
local fileCache = {}      -- id -> { 相对路径 }
local fileCacheOrder = {}
local installing = false
local loadedMapId         -- 最近一次安装的图
local queue = {}

local function log(message)
    outputServerLog('[MAPSTORE] ' .. tostring(message))
end

local function readText(path, maxBytes)
    -- 先判存在：fileOpen 打开不存在的文件会在服务端日志里刷 warning
    if not fileExists(path) then
        return nil
    end

    local handle = fileOpen(path, true)
    if not handle then
        return nil
    end

    local size = fileGetSize(handle)
    if type(size) ~= 'number' then
        fileClose(handle)
        return nil
    end
    if maxBytes and size > maxBytes then
        fileClose(handle)
        return nil
    end

    local data = size > 0 and fileRead(handle, size) or ''
    fileClose(handle)
    return data
end

local function splitLines(text)
    local lines = {}
    for line in tostring(text or ''):gmatch('[^\r\n]+') do
        line = line:gsub('^%s+', ''):gsub('%s+$', '')
        if line ~= '' then
            lines[#lines + 1] = line
        end
    end
    return lines
end

-- 地图 id 是稳定 slug；resource 名前缀保证以字母开头，避免 -foo 这类 id。
local function slotNameFor(mapId)
    local safe = tostring(mapId or ''):gsub('[^%w_-]', '_')
    return SLOT_PREFIX_NAME .. '_' .. safe
end

MapStore.slotNameFor = slotNameFor

function MapStore.isSlotResourceName(name)
    name = tostring(name or '')
    return name == SLOT_PREFIX_NAME
        or name:sub(1, #SLOT_PREFIX_NAME + 1) == SLOT_PREFIX_NAME .. '_'
end

local function slotPrefix(slotName)
    return ':' .. slotName .. '/'
end

local function slotResourceFor(mapId)
    return getResourceFromName(slotNameFor(mapId))
end

-- ---------------------------------------------------------------------------
-- 地图库索引
-- ---------------------------------------------------------------------------

function MapStore.init()
    index, ids = {}, {}
    fileCache, fileCacheOrder = {}, {}

    local raw = readText(INDEX_PATH, INDEX_MAX_BYTES)
    if not raw then
        log(('地图库索引不存在：%s（先运行 node tools/mapstore/build-library.mjs）'):format(INDEX_PATH))
        return 0
    end

    local data = fromJSON(raw)
    if type(data) ~= 'table' or type(data.maps) ~= 'table' then
        log(('地图库索引无法解析：%s'):format(INDEX_PATH))
        return 0
    end

    local skipped = 0
    for _, item in ipairs(data.maps) do
        local id = tostring(item.id or '')
        if id ~= '' then
            if item.valid == false or not item.map or item.map == '' then
                skipped = skipped + 1
                local missing = type(item.missing) == 'table' and item.missing or {}
                log(('跳过 %s：meta 引用缺失 %d 个文件'):format(id, #missing))
            else
                index[id] = {
                    id = id,
                    name = tostring(item.name or ''),
                    author = tostring(item.author or ''),
                    map = tostring(item.map),
                    dimension = tonumber(item.dimension) or 0,
                    bytes = tonumber(item.bytes) or 0,
                    files = tonumber(item.files) or 0,
                }
                ids[#ids + 1] = id
            end
        end
    end

    table.sort(ids)
    log(('地图库 %d 张可玩；槽位按地图 ID 复用（%s_<mapId>）'):format(#ids, SLOT_PREFIX_NAME))
    if skipped > 0 then
        log(('%d 张地图 meta 引用缺失文件，已从地图池排除'):format(skipped))
    end
    return #ids
end

function MapStore.count()
    return #ids
end

function MapStore.list()
    return ids
end

function MapStore.get(mapId)
    return index[mapId]
end

function MapStore.has(mapId)
    return index[mapId] ~= nil
end

-- 读取一张地图的文件清单（由 build-library.mjs 生成，只含相对路径）
function MapStore.files(mapId)
    local cached = fileCache[mapId]
    if cached then
        return cached
    end

    local list = splitLines(readText(LIB_MAPS .. mapId .. '/_files.txt', LIST_MAX_BYTES))
    if #list == 0 then
        return list
    end

    fileCache[mapId] = list
    fileCacheOrder[#fileCacheOrder + 1] = mapId
    while #fileCacheOrder > 4 do
        fileCache[table.remove(fileCacheOrder, 1)] = nil
    end
    return list
end

-- ---------------------------------------------------------------------------
-- 槽位 resource
-- ---------------------------------------------------------------------------

local function ensureSlot(mapId)
    local name = slotNameFor(mapId)
    local resource = getResourceFromName(name)
    if resource then
        return resource, name
    end

    resource = createResource(name, SLOT_ORG_DIR)
    if not resource then
        -- 目录可能已经存在但 MTA 尚未识别，刷新后再试一次
        refreshResources(true)
        resource = getResourceFromName(name)
    end
    if not resource then
        log(('无法创建槽位 resource %s（检查 ACL function.createResource）'):format(name))
        return nil, name
    end
    return resource, name
end

local function copyFiles(mapId, files, slotName, onDone)
    local position = 1
    local total = #files
    local prefix = slotPrefix(slotName)
    local timer

    local function step()
        local startedAt = getTickCount()
        while position <= total and (getTickCount() - startedAt) < COPY_CHUNK_MS do
            local name = files[position]
            if not fileCopy(LIB_MAPS .. mapId .. '/' .. name, prefix .. name, true) then
                if isTimer(timer) then
                    killTimer(timer)
                end
                onDone(false, '复制地图文件失败：' .. name)
                return
            end
            position = position + 1
        end

        if position > total then
            if isTimer(timer) then
                killTimer(timer)
            end
            onDone(true)
        end
    end

    timer = setTimer(step, COPY_TICK_MS, 0)
    if timer then
        step()
    else
        onDone(false, '无法启动复制计时器')
    end
end

local function waitForSlot(slotName, expectedName, onDone)
    local waited = 0
    local timer

    timer = setTimer(function()
        local resource = getResourceFromName(slotName)
        if not resource then
            killTimer(timer)
            onDone(false, '槽位 resource 重新加载失败')
            return
        end

        local state = getResourceState(resource)
        local name = tostring(getResourceInfo(resource, 'name') or '')
        local nameMatches = expectedName == '' or name == expectedName
        -- 没有 <info name> 的地图只能按状态判断，多等一小会儿避开上一张图的 loaded 状态
        local settled = expectedName ~= '' or waited >= 300

        if state == 'loaded' and nameMatches and settled then
            killTimer(timer)
            onDone(true, name)
            return
        end

        waited = waited + REFRESH_POLL_MS
        if waited >= REFRESH_TIMEOUT_MS then
            killTimer(timer)
            onDone(false, name ~= '' and name or tostring(state))
        end
    end, REFRESH_POLL_MS, 0)
end

-- ---------------------------------------------------------------------------
-- 安装 / 卸载
-- ---------------------------------------------------------------------------

-- 把地图库里的 mapId 装进独立槽位。完成后回调 onDone(ok, err)。
-- 同一时间只装一张；并发调用会排队。已存在的槽位直接复用。
function MapStore.install(mapId, onDone)
    onDone = type(onDone) == 'function' and onDone or function() end

    if not index[mapId] then
        onDone(false, '地图库里没有这张图')
        return
    end

    -- 最近一次安装的就是这张图，直接复用当前槽位
    if loadedMapId == mapId and #queue == 0 then
        local resource = slotResourceFor(mapId)
        local state = resource and getResourceState(resource) or 'missing'
        if state == 'loaded' or state == 'running' then
            onDone(true)
            return
        end
    end

    if installing then
        queue[#queue + 1] = { id = mapId, callback = onDone }
        return
    end

    installing = true

    local function finish(ok, err)
        installing = false
        onDone(ok, err)

        local nextRequest = table.remove(queue, 1)
        if nextRequest then
            MapStore.install(nextRequest.id, nextRequest.callback)
        end
    end

    local slot, slotName = ensureSlot(mapId)
    if not slot then
        finish(false, '地图槽位不可用')
        return
    end

    if getResourceState(slot) == 'running' then
        stopResource(slot)
    end

    local files = MapStore.files(mapId)
    if #files == 0 then
        finish(false, '地图文件清单缺失（重跑 build-library.mjs）')
        return
    end

    local prefix = slotPrefix(slotName)
    local ready = fileExists(prefix .. 'meta.xml') and fileExists(prefix .. '_files.txt')
    if ready then
        for _, name in ipairs(files) do
            if not fileExists(prefix .. name) then
                ready = false
                break
            end
        end
    end

    if ready then
        -- 槽位已经完整复制过：只校验文件存在，不比较 maplib 源文件变化；
        -- 更新源地图后需要删除该槽位再进入。客户端静态文件可按同一 resource 名复用。
        local state = getResourceState(slot)
        if state == 'loaded' or state == 'running' then
            loadedMapId = mapId
            log(('复用槽位 %s（%s）'):format(slotName, mapId))
            finish(true)
            return
        end
        refreshResources(true)
        waitForSlot(slotName, (index[mapId] and index[mapId].name) or '', function(loaded, detail)
            if not loaded then
                finish(false, ('槽位重新加载超时（%s）'):format(tostring(detail)))
                return
            end
            local entry = index[mapId]
            if entry.name and entry.name ~= '' and detail ~= entry.name then
                finish(false, ('槽位地图不符：期望 %s，实际 %s'):format(entry.name, tostring(detail)))
                return
            end
            loadedMapId = mapId
            log(('复用槽位 %s（%s）'):format(slotName, mapId))
            finish(true)
        end)
        return
    else
        copyFiles(mapId, files, slotName, function(copied, copyErr)
            if not copied then
                finish(false, copyErr)
                return
            end
            fileCopy(LIB_MAPS .. mapId .. '/_files.txt', prefix .. '_files.txt', true)
            refreshResources(true)
            waitForSlot(slotName, (index[mapId] and index[mapId].name) or '', function(loaded, detail)
                if not loaded then
                    finish(false, ('槽位重新加载超时（%s）'):format(tostring(detail)))
                    return
                end
                local entry = index[mapId]
                if entry.name and entry.name ~= '' and detail ~= entry.name then
                    finish(false, ('槽位地图不符：期望 %s，实际 %s'):format(entry.name, tostring(detail)))
                    return
                end
                loadedMapId = mapId
                log(('已创建槽位 %s（%s，%d 个文件）'):format(
                    slotName, entry.name ~= '' and entry.name or mapId, #files
                ))
                finish(true)
            end)
        end)
        return
    end

end

function MapStore.isInstalling()
    return installing
end

function MapStore.slotState(mapId)
    local resource = mapId and slotResourceFor(mapId) or nil
    if not resource and loadedMapId then
        resource = slotResourceFor(loadedMapId)
    end
    if not resource then
        return 'missing'
    end
    return getResourceState(resource)
end

-- 停掉最近安装的槽位。槽位文件保留，供服务端复用和客户端静态文件缓存。
function MapStore.stop()
    if not loadedMapId then
        return
    end
    local resource = slotResourceFor(loadedMapId)
    if resource and getResourceState(resource) == 'running' then
        stopResource(resource)
    end
end
