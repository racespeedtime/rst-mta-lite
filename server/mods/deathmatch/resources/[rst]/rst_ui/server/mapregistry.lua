--[[
    rst_ui / server/mapregistry.lua

    地图池来源：
    - 主来源是按需地图库 [rst]/maplib（MapStore 读 index.json）
    - 兼容手动丢进 resources/ 的原生 MTA map resource（type="map"）

    启动只读地图库索引，不打开任何 .map；只有地图被选中时才解析
    spawnpoint / racepickup / checkpoint。运行槽位 rst_map 不进池子。
]]

MapRegistry = {}

local maps = {}
local ids = {}
local rankedIds = {}    -- 按热度 / 名称排好序，地图池分页直接扫，避免每次请求都 table.sort
local rankedDirty = false

-- YYYY-MM-DD → YYYYMMDD 数字；解析失败或明显异常的年份按“未知”处理
local function dateStamp(value)
    local text = tostring(value or '')
    local year, month, day = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
    if not year then
        return 0
    end
    if tonumber(year) < 2000 then
        return 0
    end
    return tonumber(year .. month .. day) or 0
end

local LIB_META = ':' .. MapStore.libraryName .. '/maps/%s/meta.xml'
local LIB_MAP = ':' .. MapStore.libraryName .. '/maps/%s/%s'

local function attr(node, name)
    local value = xmlNodeGetAttribute(node, name)
    if value == nil or value == '' then
        return nil
    end
    return value
end

local function num(node, name)
    return tonumber(attr(node, name))
end

local function child(node, name)
    if not node then
        return nil
    end
    for _, value in ipairs(xmlNodeGetChildren(node) or {}) do
        if xmlNodeGetName(value) == name then
            return value
        end
    end
    return nil
end

local function all(node, name)
    local found = {}
    if not node then
        return found
    end
    for _, value in ipairs(xmlNodeGetChildren(node) or {}) do
        if xmlNodeGetName(value) == name then
            found[#found + 1] = value
        end
    end
    return found
end

local function parseSettingValue(raw)
    if raw == nil or raw == '' then
        return nil
    end

    local ok, parsed = pcall(fromJSON, raw)
    if ok and parsed ~= nil then
        if type(parsed) == 'table' then
            return parsed[1] or parsed
        end
        return parsed
    end
    return raw
end

local function readSettings(meta)
    local settings = {}
    local node = child(meta, 'settings')
    for _, setting in ipairs(all(node, 'setting')) do
        local name = attr(setting, 'name')
        if name then
            settings[name:gsub('^#', '')] = parseSettingValue(attr(setting, 'value'))
        end
    end
    return settings
end

local function applyMapMeta(entry)
    if not entry or entry._externalLoaded then
        return entry
    end
    entry._externalLoaded = true

    local extra = MapMeta and MapMeta.get(entry.id, entry.name, entry.author) or nil
    if type(extra) == 'table' then
        entry.cover = extra.cover
        entry.youtube = extra.youtube
        entry.sourceUrl = extra.sourceUrl
        entry.uploadedAt = extra.uploadedAt
        entry.downloads = extra.downloads
        entry.difficulty = extra.difficulty
        entry.fileSize = extra.fileSize
        entry.tags = extra.tags
        entry.mtavaultId = extra.mtavaultId
        entry.mapType = extra.mapType
    end
    return entry
end

-- 槽位里的地图 meta 只在选中时才读，启动不碰
local function loadSettings(entry)
    if entry._settingsLoaded then
        return
    end
    entry._settingsLoaded = true

    local meta
    if entry.source == 'library' then
        meta = xmlLoadFile(LIB_META:format(entry.id), true)
    else
        meta = xmlLoadFile(':' .. entry.resource .. '/meta.xml', true)
    end
    if not meta then
        return
    end

    entry.settings = readSettings(meta)
    xmlUnloadFile(meta)
end

-- 兼容手动安装的原生 map resource
local function readResourceMapMeta(resource, resourceName)
    local meta = xmlLoadFile(':' .. resourceName .. '/meta.xml', true)
    if not meta then
        return nil
    end

    local infoNode = child(meta, 'info')
    local mapNode = child(meta, 'map')
    local mapSrc = mapNode and attr(mapNode, 'src') or nil
    if not mapSrc then
        xmlUnloadFile(meta)
        return nil
    end

    local entry = {
        id = resourceName,
        resource = resourceName,
        mapSrc = mapSrc:gsub('\\', '/'),
        name = (infoNode and attr(infoNode, 'name')) or getResourceInfo(resource, 'name') or resourceName,
        author = (infoNode and attr(infoNode, 'author')) or getResourceInfo(resource, 'author') or '未知作者',
        dimension = tonumber(attr(mapNode, 'dimension')) or 0,
        source = 'resource',
        spawnpoints = nil,
        pickups = nil,
        finish = nil,
        _detailsLoaded = false,
        _detailsFailed = false,
    }

    xmlUnloadFile(meta)
    return entry
end

local function loadMapDetails(entry)
    if not entry then
        return false
    end
    if entry._detailsLoaded then
        return true
    end
    if entry._detailsFailed then
        return false
    end

    local path
    if entry.source == 'library' then
        path = LIB_MAP:format(entry.id, entry.mapSrc)
    else
        path = ':' .. entry.resource .. '/' .. entry.mapSrc
    end

    local mapRoot = xmlLoadFile(path, true)
    if not mapRoot then
        entry._detailsFailed = true
        return false
    end

    local spawns = {}
    local pickups = {}
    local lastCheckpoint
    local hunterPoints = {}

    for _, node in ipairs(xmlNodeGetChildren(mapRoot) or {}) do
        local name = xmlNodeGetName(node)
        if name == 'spawnpoint' then
            local x, y, z = num(node, 'posX'), num(node, 'posY'), num(node, 'posZ')
            if x and y and z then
                spawns[#spawns + 1] = {
                    x = x,
                    y = y,
                    z = z,
                    rot = num(node, 'rotZ') or 0,
                    vehicle = tonumber(attr(node, 'vehicle')),
                }
            end
        elseif name == 'checkpoint' then
            if num(node, 'posX') and num(node, 'posY') and num(node, 'posZ') then
                lastCheckpoint = node
            end
        elseif name == 'racepickup' then
            local pickupType = attr(node, 'type')
            local x, y, z = num(node, 'posX'), num(node, 'posY'), num(node, 'posZ')
            if pickupType and x and y and z then
                pickups[#pickups + 1] = {
                    id = attr(node, 'id') or ('pickup:' .. tostring(#pickups + 1)),
                    type = pickupType,
                    vehicle = tonumber(attr(node, 'vehicle')),
                    x = x,
                    y = y,
                    z = z,
                    rotZ = num(node, 'rotZ') or 0,
                    respawn = tonumber(attr(node, 'respawn')) or 0,
                    interior = tonumber(attr(node, 'interior')) or 0,
                    alpha = tonumber(attr(node, 'alpha')) or 255,
                }
            end

            local vehicle = tonumber(attr(node, 'vehicle'))
            if pickupType == 'vehiclechange' and vehicle == 425 and x and y and z then
                hunterPoints[#hunterPoints + 1] = { x = x, y = y, z = z }
            end
        end
    end

    if #spawns == 0 then
        entry._detailsFailed = true
        xmlUnloadFile(mapRoot)
        return false
    end

    local first = spawns[1]
    local finish
    local finishes = {}
    if #hunterPoints > 0 then
        -- 一张图可能有多个 Hunter 终点，逐个判定，不能取平均点
        finishes = hunterPoints
        finish = hunterPoints[1]
    elseif lastCheckpoint then
        finish = {
            x = num(lastCheckpoint, 'posX'),
            y = num(lastCheckpoint, 'posY'),
            z = num(lastCheckpoint, 'posZ'),
        }
        finishes[1] = finish
    end

    entry.spawnpoints = spawns
    entry.x, entry.y, entry.z = first.x, first.y, first.z
    entry.rot = first.rot or 0
    entry.vehicle = first.vehicle
    entry.finish = finish
    entry.finishes = finishes
    entry.hasHunterFinish = #hunterPoints > 0
    entry.pickups = pickups
    entry._detailsLoaded = true

    xmlUnloadFile(mapRoot)
    return true
end

local function addEntry(entry)
    if not entry or maps[entry.id] then
        return false
    end

    entry.mtavaultDownloads = MapMeta and MapMeta.downloadsForId
        and MapMeta.downloadsForId(entry.id)
        or 0

    -- 搜索 / 排序用的预计算：地图池分页每帧都会扫，不能每次现场 lower() + 查统计
    entry.search = (tostring(entry.id) .. '\n' .. tostring(entry.name or '') .. '\n' .. tostring(entry.author or '')):lower()
    entry.plays = MapStats and MapStats.getPlays and MapStats.getPlays(entry.id) or 0
    entry.popularity = MapStats and MapStats.popularity(entry.id, entry) or (entry.mtavaultDownloads or 0)
    entry.uploadedAt = MapMeta and MapMeta.uploadedForId and MapMeta.uploadedForId(entry.id) or nil
    entry.uploadedStamp = dateStamp(entry.uploadedAt)
    -- 解析不出来 / 明显异常的日期当“未知”，排序时永远放最后
    if entry.uploadedStamp <= 0 then
        entry.uploadedAt = nil
    end

    maps[entry.id] = entry
    ids[#ids + 1] = entry.id
    return true
end

local function rebuildRanked()
    rankedIds = {}
    for _, mapId in ipairs(ids) do
        if maps[mapId] then
            rankedIds[#rankedIds + 1] = mapId
        end
    end

    table.sort(rankedIds, function(a, b)
        local left, right = maps[a], maps[b]
        local lp = left.popularity or 0
        local rp = right.popularity or 0
        if lp ~= rp then
            return lp > rp
        end
        return tostring(left.name or a) < tostring(right.name or b)
    end)
    rankedDirty = false
end

local function ensureRanked()
    if rankedDirty or #rankedIds ~= #ids then
        rebuildRanked()
    end
end

-- 玩过一场后热度会变：只更新这一条，排序延后到下次翻页时重排（每局最多一次）
function MapRegistry.onPlayRecorded(mapId)
    local entry = maps[mapId]
    if not entry then
        return
    end
    entry.plays = MapStats and MapStats.getPlays and MapStats.getPlays(mapId) or entry.plays or 0
    entry.popularity = MapStats and MapStats.popularity(mapId, entry) or entry.mtavaultDownloads or 0
    rankedDirty = true
end

function MapRegistry.init()
    maps = {}
    ids = {}
    rankedIds = {}
    rankedDirty = false

    local libraryCount = MapStore and MapStore.init() or 0

    -- 1) 按需地图库（主来源）
    if libraryCount > 0 then
        for _, mapId in ipairs(MapStore.list()) do
            local item = MapStore.get(mapId)
            addEntry({
                id = mapId,
                resource = mapId,
                mapSrc = item.map,
                name = (item.name ~= nil and item.name ~= '') and item.name or mapId,
                author = item.author,
                dimension = item.dimension or 0,
                source = 'library',
                spawnpoints = nil,
                pickups = nil,
                finish = nil,
                _detailsLoaded = false,
                _detailsFailed = false,
            })
        end
    end

    -- 2) 兼容手动丢进 resources/ 的原生 map resource
    local manual = 0
    local slotName = MapStore and MapStore.slotName or 'rst_map'
    for _, resource in ipairs(getResources()) do
        local resourceName = getResourceName(resource)
        if resourceName
            and resourceName ~= slotName
            and getResourceInfo(resource, 'type') == 'map'
            and not maps[resourceName]
        then
            local entry = readResourceMapMeta(resource, resourceName)
            if entry and addEntry(entry) then
                manual = manual + 1
            else
                outputServerLog(('[MAP] skipped %s: unreadable meta/map declaration'):format(
                    tostring(resourceName)
                ))
            end
        end
    end

    table.sort(ids, function(a, b)
        return (maps[a].name or a) < (maps[b].name or b)
    end)
    rebuildRanked()

    outputServerLog(('[MAP] 地图池 %d 张（库 %d · 手动 %d），.map 细节按需解析'):format(
        #ids, libraryCount, manual
    ))
    return #ids
end

function MapRegistry.get(mapId)
    return applyMapMeta(maps[mapId])
end

function MapRegistry.peek(mapId)
    return maps[mapId]
end

function MapRegistry.details(mapId)
    local entry = maps[mapId]
    if not entry then
        return nil
    end
    if entry._detailsFailed then
        return nil
    end
    if not loadMapDetails(entry) then
        outputServerLog(('[MAP] failed to load details for %s'):format(tostring(mapId)))
        return nil
    end
    loadSettings(entry)
    return applyMapMeta(entry)
end

function MapRegistry.list()
    return ids
end

function MapRegistry.count()
    return #ids
end

-- 运行期装不出来的图（meta 引用缺失文件等）从地图池摘掉，避免反复失败
function MapRegistry.drop(mapId)
    if not maps[mapId] then
        return false
    end
    maps[mapId] = nil
    for index, id in ipairs(ids) do
        if id == mapId then
            table.remove(ids, index)
            break
        end
    end
    outputServerLog(('[MAP] 已从地图池移除 %s'):format(tostring(mapId)))
    rankedDirty = true
    return true
end

-- 地图详情（地图池里点开某张图时用）：解析 .map + 读外部元数据，只在点开时调用
function MapRegistry.detail(mapId)
    local entry = MapRegistry.details(mapId)
    if not entry then
        return nil
    end

    local vehicles = {}
    local seen = {}
    for _, spawn in ipairs(entry.spawnpoints or {}) do
        local model = spawn.vehicle
        if model and not seen[model] then
            seen[model] = true
            vehicles[#vehicles + 1] = model
        end
    end

    local current = MapManager and MapManager.currentMapId and MapManager.currentMapId() == entry.id

    return {
        id = entry.id,
        name = entry.name,
        author = entry.author,
        resource = entry.resource or entry.id,
        mapSrc = entry.mapSrc,
        spawns = #(entry.spawnpoints or {}),
        pickups = #(entry.pickups or {}),
        vehicles = vehicles,
        dimension = entry.dimension or 0,
        finish = entry.finish ~= nil,
        cover = entry.cover,
        youtube = entry.youtube,
        sourceUrl = entry.sourceUrl,
        uploadedAt = entry.uploadedAt,
        downloads = entry.downloads,
        difficulty = entry.difficulty,
        fileSize = entry.fileSize,
        tags = entry.tags,
        plays = entry.plays or 0,
        popularity = entry.popularity or 0,
        current = current == true,
    }
end

local SORT_FIELDS = {
    popularity = true,
    downloads = true,
    plays = true,
    name = true,
    uploaded = true,
}

local function sortValue(entry, field)
    if field == 'downloads' then
        return entry.mtavaultDownloads or 0
    elseif field == 'plays' then
        return entry.plays or 0
    elseif field == 'name' then
        return tostring(entry.name or entry.id):lower()
    elseif field == 'uploaded' then
        return entry.uploadedStamp or 0
    end
    return entry.popularity or 0
end

local function compareByField(left, right, field, ascending)
    if field == 'uploaded' then
        local lv = left.uploadedStamp or 0
        local rv = right.uploadedStamp or 0
        if lv == 0 or rv == 0 then
            if lv == rv then
                return tostring(left.name or left.id) < tostring(right.name or right.id)
            end
            -- 未知日期不参与方向，统一排最后
            return rv == 0
        end
        if lv ~= rv then
            if ascending then
                return lv < rv
            end
            return lv > rv
        end
    end

    local lv = sortValue(left, field)
    local rv = sortValue(right, field)
    if lv ~= rv then
        if ascending then
            return lv < rv
        end
        return lv > rv
    end

    -- 同值时保持原来的热度优先、再按名称
    local lp = left.popularity or 0
    local rp = right.popularity or 0
    if lp ~= rp then
        return lp > rp
    end
    return tostring(left.name or left.id) < tostring(right.name or right.id)
end

local function mapItem(entry, currentMapId)
    return {
        id = entry.id,
        resource = entry.resource,
        name = entry.name,
        author = entry.author,
        dimension = entry.dimension or 0,
        downloads = entry.mtavaultDownloads or 0,
        popularity = entry.popularity or 0,
        plays = entry.plays or 0,
        uploadedAt = entry.uploadedAt,
        current = currentMapId == entry.id,
    }
end

-- 地图池分页：只返回轻量信息，不解析 .map。
-- 默认按热度降序走预排序的 rankedIds；其它排序（下载量 / 场次 / 名称）才现场排。
function MapRegistry.page(page, pageSize, search, sortField, sortOrder, dateFrom, dateTo)
    page = tonumber(page) or 1
    pageSize = tonumber(pageSize) or 30
    page = math.max(1, math.floor(page))
    pageSize = math.max(1, math.min(100, math.floor(pageSize)))
    search = tostring(search or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')

    local fromStamp = dateStamp(dateFrom)
    local toStamp = dateStamp(dateTo)
    if fromStamp > 0 and toStamp > 0 and fromStamp > toStamp then
        fromStamp, toStamp = toStamp, fromStamp
    end
    local hasDateFilter = fromStamp > 0 or toStamp > 0

    local function matches(entry)
        if not entry then
            return false
        end
        if search ~= '' and not entry.search:find(search, 1, true) then
            return false
        end
        if not hasDateFilter then
            return true
        end
        local stamp = entry.uploadedStamp or 0
        if stamp <= 0 then
            return false
        end
        if fromStamp > 0 and stamp < fromStamp then
            return false
        end
        if toStamp > 0 and stamp > toStamp then
            return false
        end
        return true
    end

    sortField = tostring(sortField or 'popularity')
    if not SORT_FIELDS[sortField] then
        sortField = 'popularity'
    end
    sortOrder = tostring(sortOrder or ''):lower()
    if sortOrder ~= 'asc' then
        sortOrder = 'desc'
    end
    local ascending = sortOrder == 'asc'
    local defaultSort = sortField == 'popularity' and not ascending

    local first = (page - 1) * pageSize + 1
    local last = first + pageSize - 1
    local total = 0
    local items = {}
    local currentMapId = MapManager and MapManager.currentMapId and MapManager.currentMapId() or nil

    if defaultSort then
        ensureRanked()
        for _, mapId in ipairs(rankedIds) do
            local entry = maps[mapId]
            if matches(entry) then
                total = total + 1
                if total >= first and total <= last then
                    items[#items + 1] = mapItem(entry, currentMapId)
                end
            end
        end
    else
        local filtered = {}
        for _, mapId in ipairs(ids) do
            local entry = maps[mapId]
            if matches(entry) then
                filtered[#filtered + 1] = entry
            end
        end

        table.sort(filtered, function(left, right)
            return compareByField(left, right, sortField, ascending)
        end)

        total = #filtered
        for index = first, math.min(last, total) do
            items[#items + 1] = mapItem(filtered[index], currentMapId)
        end
    end

    local pages = math.max(1, math.ceil(total / pageSize))
    if page > pages then
        -- 搜索词 / 排序变化后页码可能越界，回退到最后一页
        return MapRegistry.page(pages, pageSize, search, sortField, sortOrder, dateFrom, dateTo)
    end

    return {
        page = page,
        pageSize = pageSize,
        total = total,
        pages = pages,
        search = search,
        sort = sortField,
        order = sortOrder,
        dateFrom = dateFrom or '',
        dateTo = dateTo or '',
        items = items,
    }
end
