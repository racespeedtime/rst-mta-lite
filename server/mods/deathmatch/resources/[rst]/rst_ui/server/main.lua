--[[
    rst_ui / server/main.lua

    把服务器信息推给客户端页面（bootstrap 里的 serverName / online）。
]]

local thisResource = getThisResource()

local function sendServerInfo(player)
    triggerClientEvent(player, "rst:ui:serverInfo", player, toJSON({
        name = getServerName(),
        online = getPlayerCount(),
    }))
end

-- 新玩家完成资源下载后补发一次
addEventHandler("onPlayerResourceStart", root, function(startedResource)
    if startedResource ~= thisResource then
        return
    end
    sendServerInfo(source)
end)

-- 资源启动时给已经在线的玩家发一次（客户端会在就绪后取用）
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        sendServerInfo(player)
    end
end)
