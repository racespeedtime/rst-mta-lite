--[[
    rst_ui / server/mapstore.lua

    按需地图资源（服务器端真正只加载一张图）：

    - [rst]/maplib 是纯数据 resource：maps/<id>/ 里是展开后的地图文件，
      它的 meta.xml 不声明任何文件，所以 MTA 开服时只会读一个 meta，
      不会扫描 / 哈希这 26 GB 地图内容。
    - 运行期只有一个固定槽位 resource：resources/rst_map。
    - 换图时把库里的目标地图文件复制进槽位，refresh 重新加载，再启动。

    这样开服时间与地图数量无关；一张图约 6-24 MB，复制 + 重新校验在
    几百毫秒内完成，客户端也只会下载当前这张图。
]]

MapStore = {}

local LIB_NAME = 'maplib'
local SLOT_NAME = 'rst_map'
local LIB_MAPS = ':' .. LIB_NAME .. '/maps/'
local SLOT_PREFIX = ':' .. SLOT_NAME .. '/'
local INDEX_PATH = ':' .. LIB_NAME .. '/index.json'

local INDEX_MAX_BYTES = 64 * 1024 * 1024
local LIST_MAX_BYTES = 1024 * 1024
local COPY_CHUNK_MS = 8          -- 每个 tick 最多复制这么久，避免卡住主线程
local COPY_TICK_MS = 30
local REFRESH_TIMEOUT_MS = 10000 -- 槽位重新加载的等待上限
local REFRESH_POLL_MS = 100

MapStore.slotName = SLOT_NAME
MapStore.libraryName = LIB_NAME

local index = {}          -- id -> { id, name, author, map, dimension, bytes, files }
local ids = {}            -- 排序后的地图 id 列表
local fileCache = {}      -- id -> { 相对路径 }
local fileCacheOrder = {}
local installing = false
local loadedMapId         -- 槽位里当前装着哪张图
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

local function slotResource()
    return getResourceFromName(SLOT_NAME)
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
    log(('地图库 %d 张可玩，运行槽位 %s，按需复制'):format(#ids, SLOT_NAME))
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

local function ensureSlot()
    local resource = slotResource()
    if resource then
        return resource
    end

    resource = createResource(SLOT_NAME)
    if not resource then
        log('无法创建槽位 resource ' .. SLOT_NAME .. '（检查 ACL function.createResource）')
        return nil
    end
    return resource
end

local function deleteSlotFiles()
    local listed = splitLines(readText(SLOT_PREFIX .. '_files.txt', LIST_MAX_BYTES))
    for _, name in ipairs(listed) do
        if name ~= '_files.txt' then
            fileDelete(SLOT_PREFIX .. name)
        end
    end
end

local function copyFiles(mapId, files, onDone)
    local position = 1
    local total = #files
    local timer

    local function step()
        local startedAt = getTickCount()
        while position <= total and (getTickCount() - startedAt) < COPY_CHUNK_MS do
            local name = files[position]
            if not fileCopy(LIB_MAPS .. mapId .. '/' .. name, SLOT_PREFIX .. name, true) then
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

local function waitForSlot(expectedName, onDone)
    local waited = 0
    local timer

    timer = setTimer(function()
        local resource = slotResource()
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

-- 把地图库里的 mapId 装进槽位。完成后回调 onDone(ok, err)。
-- 同一时间只装一张；并发调用会排队。
function MapStore.install(mapId, onDone)
    onDone = type(onDone) == 'function' and onDone or function() end

    if not index[mapId] then
        onDone(false, '地图库里没有这张图')
        return
    end

    -- 槽位里已经是这张图（上一回合刚玩过 / 刚装载完），直接复用
    if loadedMapId == mapId and #queue == 0 then
        local state = MapStore.slotState()
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

    local slot = ensureSlot()
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

    deleteSlotFiles()

    copyFiles(mapId, files, function(copied, copyErr)
        if not copied then
            finish(false, copyErr)
            return
        end

        -- 记下这张图的文件清单，下次安装前用它清理残留
        fileCopy(LIB_MAPS .. mapId .. '/_files.txt', SLOT_PREFIX .. '_files.txt', true)

        refreshResources(true)

        local entry = index[mapId]
        waitForSlot(entry.name or '', function(loaded, detail)
            if not loaded then
                finish(false, ('槽位重新加载超时（%s）'):format(tostring(detail)))
                return
            end
            if entry.name and entry.name ~= '' and detail ~= entry.name then
                finish(false, ('槽位地图不符：期望 %s，实际 %s'):format(entry.name, tostring(detail)))
                return
            end
            log(('已装载 %s（%s，%d 个文件）'):format(
                entry.name ~= '' and entry.name or mapId, mapId, #files
            ))
            loadedMapId = mapId
            finish(true)
        end)
    end)
end

function MapStore.isInstalling()
    return installing
end

function MapStore.slotState()
    local resource = slotResource()
    if not resource then
        return 'missing'
    end
    return getResourceState(resource)
end

-- 停掉槽位（rst_ui 停止 / 换图时调用）。文件留着，下次安装前会清理。
function MapStore.stop()
    local resource = slotResource()
    if resource and getResourceState(resource) == 'running' then
        stopResource(resource)
    end
end


