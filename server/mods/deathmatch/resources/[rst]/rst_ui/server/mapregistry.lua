--[[
    rst_ui / server/mapregistry.lua

    运行时直接发现原生 MTA map resource：
    - 资源类型 type="map"
    - 读取 meta.xml 里的 <map src="...">
    - 读取 .map 里的 spawnpoint / racepickup / checkpoint 原生元素
    - 不生成新的地图文件格式，也不维护重复的 config.maps
]]

MapRegistry = {}

local maps = {}
local ids = {}

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

local function readMapMeta(resource)
    local resourceName = getResourceName(resource)
    if not resourceName or getResourceInfo(resource, 'type') ~= 'map' then
        return nil
    end
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
        mapSrc = mapSrc,
        name = (infoNode and attr(infoNode, 'name')) or getResourceInfo(resource, 'name') or resourceName,
        author = (infoNode and attr(infoNode, 'author')) or getResourceInfo(resource, 'author') or '未知作者',
        dimension = tonumber(attr(mapNode, 'dimension')) or 0,
        settings = readSettings(meta),
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

    local mapRoot = xmlLoadFile(':' .. entry.resource .. '/' .. entry.mapSrc, true)
    if not mapRoot then
        entry._detailsFailed = true
        return false
    end

    local spawns = {}
    local pickups = {}
    local lastCheckpoint
    local hunterCount = 0
    local hunterX, hunterY, hunterZ = 0, 0, 0

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
                hunterCount = hunterCount + 1
                hunterX = hunterX + x
                hunterY = hunterY + y
                hunterZ = hunterZ + z
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
    if hunterCount > 0 then
        finish = {
            x = hunterX / hunterCount,
            y = hunterY / hunterCount,
            z = hunterZ / hunterCount,
        }
    elseif lastCheckpoint then
        finish = {
            x = num(lastCheckpoint, 'posX'),
            y = num(lastCheckpoint, 'posY'),
            z = num(lastCheckpoint, 'posZ'),
        }
    end

    entry.spawnpoints = spawns
    entry.x, entry.y, entry.z = first.x, first.y, first.z
    entry.rot = first.rot or 0
    entry.vehicle = first.vehicle
    entry.finish = finish
    entry.pickups = pickups
    entry._detailsLoaded = true

    xmlUnloadFile(mapRoot)
    return true
end

function MapRegistry.init()
    maps = {}
    ids = {}

    for _, resource in ipairs(getResources()) do
        local entry = readMapMeta(resource)
        if entry then
            entry.mtavaultDownloads = MapMeta and MapMeta.downloads(
                entry.resource, entry.name, entry.author
            ) or 0
            maps[entry.id] = entry
            ids[#ids + 1] = entry.id
        elseif getResourceInfo(resource, 'type') == 'map' then
            outputServerLog(('[MAP] skipped %s: unreadable meta/map declaration'):format(
                tostring(getResourceName(resource))
            ))
        end
    end

    table.sort(ids, function(a, b)
        return (maps[a].name or a) < (maps[b].name or b)
    end)

    outputServerLog(('[MAP] discovered %d native map resource(s); .map details are lazy loaded'):format(
        #ids
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
    if not loadMapDetails(entry) then
        outputServerLog(('[MAP] failed to load details for %s'):format(tostring(mapId)))
        return nil
    end
    return applyMapMeta(entry)
end

function MapRegistry.list()
    return ids
end

function MapRegistry.count()
    return #ids
end

-- 地图池分页：只返回轻量信息，不解析 .map
function MapRegistry.page(page, pageSize, search)
    page = tonumber(page) or 1
    pageSize = tonumber(pageSize) or 30
    page = math.max(1, math.floor(page))
    pageSize = math.max(1, math.min(100, math.floor(pageSize)))
    search = tostring(search or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')

    local filtered = {}
    for _, mapId in ipairs(ids) do
        local entry = maps[mapId]
        if entry then
            if search == ''
                or tostring(entry.name or ''):lower():find(search, 1, true)
                or tostring(entry.author or ''):lower():find(search, 1, true)
                or tostring(mapId):lower():find(search, 1, true)
            then
                filtered[#filtered + 1] = entry
            end
        end
    end

    local total = #filtered
    table.sort(filtered, function(a, b)
        local ap = MapStats and MapStats.popularity(a.id, a) or (a.mtavaultDownloads or 0)
        local bp = MapStats and MapStats.popularity(b.id, b) or (b.mtavaultDownloads or 0)
        if ap ~= bp then
            return ap > bp
        end
        return tostring(a.name or a.id) < tostring(b.name or b.id)
    end)

    local pages = math.max(1, math.ceil(total / pageSize))
    page = math.min(page, pages)
    local start = (page - 1) * pageSize + 1
    local items = {}
    for index = start, math.min(start + pageSize - 1, total) do
        local entry = filtered[index]
        items[#items + 1] = {
            id = entry.id,
            resource = entry.resource,
            name = entry.name,
            author = entry.author,
            dimension = entry.dimension or 0,
            downloads = entry.mtavaultDownloads or 0,
            popularity = MapStats and MapStats.popularity(entry.id, entry) or 0,
        }
    end

    return {
        page = page,
        pageSize = pageSize,
        total = total,
        pages = pages,
        search = search,
        items = items,
    }
end
