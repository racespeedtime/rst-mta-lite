--[[
    rst_ui / client/custommodels.lua

    可选：服务器默认载具 DFF/TXD。

    推荐用载具模型 ID 命名，文件和模型一一对应：

        models/411.dff
        models/411.txd

    也可以用车名 slug 作为别名：

        models/infernus.dff
        models/infernus.txd

    同一车型的 DFF/TXD 数字 ID 文件优先于车名文件。

    默认没有模型文件，所以不会产生任何替换。
    地图 resource 的模型脚本在地图启动后加载，因此地图自己替换某个模型时
    会覆盖这里的默认模型，优先使用地图的 DFF/TXD。
]]

local ENABLED = true
local MODEL_MIN = 400
local MODEL_MAX = 611

local appliedModels = {}

local function nameSlug(model)
    local name = getVehicleNameFromModel(model)
    if not name or name == false then
        return nil
    end
    return tostring(name):lower():gsub('[^%w]', '')
end

local function findFile(model, extension, slug)
    local byId = ('models/%d.%s'):format(model, extension)
    if fileExists(byId) then
        return byId
    end
    if slug and slug ~= '' then
        local byName = ('models/%s.%s'):format(slug, extension)
        if fileExists(byName) then
            return byName
        end
    end
    return nil
end

local function applyFallback()
    if not ENABLED then
        return
    end

    appliedModels = {}
    for model = MODEL_MIN, MODEL_MAX do
        if getVehicleNameFromModel(model) then
            local slug = nameSlug(model)
            local dffPath = findFile(model, 'dff', slug)
            local txdPath = findFile(model, 'txd', slug)
            if dffPath or txdPath then
                local dff = dffPath and engineLoadDFF(dffPath) or nil
                local txd = txdPath and engineLoadTXD(txdPath) or nil

                if txd then
                    engineImportTXD(txd, model)
                end
                if dff then
                    engineReplaceModel(dff, model)
                end
                if dff or txd then
                    appliedModels[#appliedModels + 1] = model
                    outputDebugString(('[custommodels] model=%d dff=%s txd=%s'):format(
                        model, tostring(dffPath or '-'), tostring(txdPath or '-')
                    ))
                end
            end
        end
    end
end

addEvent('rst:ui:custommodel', true)
addEventHandler('rst:ui:custommodel', root, function()
    applyFallback()
end)

addEventHandler('onClientResourceStart', resourceRoot, function()
    -- 资源文件此时已经下载完成；尽早应用，地图脚本随后可覆盖
    applyFallback()
end)

-- 资源热重载时恢复地图自己的模型
addEventHandler('onClientResourceStop', resourceRoot, function()
    for _, model in ipairs(appliedModels) do
        engineRestoreModel(model)
    end
    appliedModels = {}
end)
