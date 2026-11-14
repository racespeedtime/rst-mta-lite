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
    for _, value in ipairs(xmlNodeGetChildren(node) or {}) do
        if xmlNodeGetName(value) == name then
            return value
        end
    end
    return nil
end

local function all(node, name)
    local found = {}
    for _, value in ipairs(xmlNodeGetChildren(node) or {}) do
        if xmlNodeGetName(value) == name then
            found[#found + 1] = value
        end
    end
    return found
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
            local vehicle = tonumber(attr(node, 'vehicle'))
            if pickupType == 'vehiclechange' and vehicle == 425 then
                local x, y, z = num(node, 'posX'), num(node, 'posY'), num(node, 'posZ')
                if x and y and z then
                    hunterCount = hunterCount + 1
                    hunterX = hunterX + x
                    hunterY = hunterY + y
                    hunterZ = hunterZ + z
                end
            end
        end
    end

    local entry
    if #spawns > 0 then
        local first = spawns[1]
        local finish
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
        }
    end

    xmlUnloadFile(mapRoot)
    xmlUnloadFile(meta)
    return entry
end

function MapRegistry.init()
    maps = {}
    ids = {}

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
    end

    outputServerLog(('[MAP] discovered %d native map resource(s)'):format(#ids))
    return #ids
end

function MapRegistry.get(mapId)
    return maps[mapId]
end

function MapRegistry.list()
    return ids
end

function MapRegistry.count()
    return #ids
end
