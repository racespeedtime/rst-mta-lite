--[[
    rst_ui / client/custommodels.lua

    可选：服务器默认 Infernus 模型。

    默认没有模型文件，所以不会产生任何替换。
    把下面两个文件放到本资源目录即可生效：

        models/infernus.dff
        models/infernus.txd

    地图 resource 的模型脚本在地图启动后加载，因此地图自己替换 411 时
    会覆盖这里的默认模型，优先使用地图的 DFF/TXD。
]]

local ENABLED = true
local MODEL_ID = 411
local DFF_PATH = 'models/infernus.dff'
local TXD_PATH = 'models/infernus.txd'

local applied = false

local function applyFallback()
    if not ENABLED then
        return
    end

    local hasDff = fileExists(DFF_PATH)
    local hasTxd = fileExists(TXD_PATH)
    if not hasDff and not hasTxd then
        return
    end

    local dff = hasDff and engineLoadDFF(DFF_PATH) or nil
    local txd = hasTxd and engineLoadTXD(TXD_PATH) or nil

    if txd then
        engineImportTXD(txd, MODEL_ID)
    end
    if dff then
        engineReplaceModel(dff, MODEL_ID)
    end

    applied = true
    outputDebugString(('[custommodels] infernus fallback dff=%s txd=%s'):format(
        tostring(dff ~= nil), tostring(txd ~= nil)
    ))
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
    if applied then
        engineRestoreModel(MODEL_ID)
    end
end)
