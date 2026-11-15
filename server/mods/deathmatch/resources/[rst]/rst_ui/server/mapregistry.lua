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

-- 外部展示元数据按地图 resource 拆成 sidecar，按需读取；
-- 不再把上万张地图的封面/YouTube 信息塞进一个 mapmeta.json。
local externalCache = {}

local function loadMapMeta(mapId)
    if externalCache[mapId] ~= nil then
        return externalCache[mapId] or nil
    end

    local handle = fileOpen('mapmeta/' .. mapId .. '.json')
    if not handle then
        externalCache[mapId] = false
        return nil
    end

    local size = fileGetSize(handle)
    local text = size > 0 and fileRead(handle, size) or ''
    fileClose(handle)

    local data = fromJSON(text or '')
    if type(data) ~= 'table' then
        externalCache[mapId] = false
        return nil
    end

    externalCache[mapId] = data
    return data
end

local function applyMapMeta(entry)
    if not entry or entry._externalLoaded then
        return entry
    end
    entry._externalLoaded = true

    local extra = loadMapMeta(entry.id)
    if type(extra) == 'table' then
        entry.cover = extra.cover
        entry.youtube = extra.youtube
        entry.sourceUrl = extra.sourceUrl
        entry.uploadedAt = extra.uploadedAt
        entry.downloads = tonumber(extra.downloads)
        entry.difficulty = extra.difficulty
        entry.fileSize = tonumber(extra.fileSize)
        entry.tags = extra.tags
    end
    return entry
end

local function readMap(resource)
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

    local mapRoot = xmlLoadFile(':' .. resourceName .. '/' .. mapSrc, true)
    if not mapRoot then
        xmlUnloadFile(meta)
        return nil
    end

    local spawns = {}
    local pickups = {}
    local lastCheckpoint    local hunterCount = 0
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

    local entry
    if #spawns > 0 then
        local first = spawns[1]
        local finish
        local settings = readSettings(meta)
        if hunterCount > 0 then
            finish = { x = hunterX / hunterCount, y = hunterY / hunterCount, z = hunterZ / hunterCount }
        elseif lastCheckpoint then
            finish = {
                x = num(lastCheckpoint, 'posX'),
                y = num(lastCheckpoint, 'posY'),
                z = num(lastCheckpoint, 'posZ'),
            }
        end

        entry = {
            id = resourceName,
            resource = resourceName,
            name = (infoNode and attr(infoNode, 'name')) or getResourceInfo(resource, 'name') or resourceName,
            author = (infoNode and attr(infoNode, 'author')) or getResourceInfo(resource, 'author') or '未知作者',
            dimension = tonumber(attr(mapNode, 'dimension')) or 0,
            spawnpoints = spawns,
            x = first.x,
            y = first.y,
            z = first.z,
            rot = first.rot or 0,
            vehicle = first.vehicle,
            finish = finish,
            pickups = pickups,
            settings = settings,
        }
    end

    xmlUnloadFile(mapRoot)
    xmlUnloadFile(meta)
    return entry
end

function MapRegistry.init()
    maps = {}
    ids = {}
    externalCache = {}

    for _, resource in ipairs(getResources()) do
        local entry = readMap(resource)
        if entry then
            maps[entry.id] = entry
            ids[#ids + 1] = entry.id
        elseif getResourceInfo(resource, 'type') == 'map' then
            outputServerLog(('[MAP] skipped %s: no usable spawnpoint / .map'):format(
                tostring(getResourceName(resource))
            ))
        end
    end

    table.sort(ids, function(a, b)
        return (maps[a].name or a) < (maps[b].name or b)
    end)

    for _, id in ipairs(ids) do
        local entry = maps[id]
        outputServerLog(('[MAP] native %s spawns=%d first=(%.2f, %.2f, %.2f) vehicle=%s finish=%s'):format(
            tostring(entry.name),
            #entry.spawnpoints,
            entry.x,
            entry.y,
            entry.z,
            tostring(entry.vehicle or 'default'),
            entry.finish and 'hunter/checkpoint' or 'none'
        ))
        outputServerLog(('[MAP] pickups %s count=%d'):format(
            tostring(entry.name), #(entry.pickups or {})
        ))
        local settings = entry.settings or {}
        outputServerLog(('[MAP] settings %s time=%s weather=%s duration=%s locked_time=%s'):format(
            tostring(entry.name),
            tostring(settings.time),
            tostring(settings.weather),
            tostring(settings.duration),
            tostring(settings.locked_time)
        ))
    end

    outputServerLog(('[MAP] discovered %d native map resource(s); metadata sidecars are lazy loaded'):format(
        #ids
    ))
    return #ids
end

function MapRegistry.get(mapId)
    return applyMapMeta(maps[mapId])
end

function MapRegistry.list()
    return ids
end

function MapRegistry.count()
    return #ids
end
