--[[
    rst_ui / client/main.lua

    职责：
    1. 创建全屏 CEF 浏览器（local 模式），加载 http://mta/local/ui/index.html
    2. 用 dxDrawImage 渲染浏览器纹理，并注入鼠标 / 键盘输入
    3. 提供 Lua <-> JS 双向桥：
       - JS -> Lua: mta.triggerEvent("rst:ui:*", jsonString)
       - Lua -> JS: executeBrowserJavascript(browser, "window.rst.dispatch(...)")
]]

local UI_URL = "http://mta/local/ui/index.html"
local UI_VERSION = "0.1.0"

local browser
local browserReady = false
local menuOpen = false
local interactive = false
local screenW, screenH = guiGetScreenSize()
local serverInfo = { name = "rst-mta-lite", online = 0 }

-- ---------------------------------------------------------------------------
-- 与页面通信
-- ---------------------------------------------------------------------------

local function callJs(name, ...)
    if not browser or not browserReady then
        return false
    end

    local args = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" then
            args[#args + 1] = string.format("%q", value)
        else
            args[#args + 1] = tostring(value)
        end
    end

    local code = ("window.rst && window.rst.%s(%s)"):format(name, table.concat(args, ","))
    return executeBrowserJavascript(browser, code)
end

local function dispatch(name, payload)
    return callJs("dispatch", name, toJSON(payload or {}))
end

-- ---------------------------------------------------------------------------
-- 渲染
-- ---------------------------------------------------------------------------

local function render()
    if not browserReady then
        return
    end

    local width, height = guiGetScreenSize()
    if width > 0 and height > 0 and (width ~= screenW or height ~= screenH) then
        screenW, screenH = width, height
        resizeBrowser(browser, screenW, screenH)
    end

    dxDrawImage(0, 0, screenW, screenH, browser, 0, 0, 0, tocolor(255, 255, 255, 255), false)
end

-- ---------------------------------------------------------------------------
-- 交互状态：菜单打开时显示鼠标、接管键盘并禁用游戏控制
-- ---------------------------------------------------------------------------

local function setInteractive(enabled)
    enabled = enabled == true
    if enabled == interactive then
        return
    end
    interactive = enabled

    showCursor(enabled)
    guiSetInputEnabled(enabled)
    toggleAllControls(not enabled, true, false)

    if browserReady then
        if enabled then
            focusBrowser(browser)
        else
            focusBrowser(nil)
        end
    end
end

local function setMenuOpen(open)
    open = open == true
    if menuOpen == open then
        return
    end

    menuOpen = open
    setInteractive(open)
    dispatch("menu", { open = menuOpen })
end

-- ---------------------------------------------------------------------------
-- 向页面推送数据
-- ---------------------------------------------------------------------------

local function sendBootstrap()
    dispatch("bootstrap", {
        playerName = getPlayerName(localPlayer) or "player",
        serverName = serverInfo.name or "rst-mta-lite",
        online = tonumber(serverInfo.online) or 0,
        revision = UI_VERSION,
    })
    dispatch("menu", { open = menuOpen })
end

local statsTimer = setTimer(function()
    if not browserReady then
        return
    end

    dispatch("stats", {
        health = math.floor(tonumber(getElementHealth(localPlayer)) or 100),
        armor = math.floor(tonumber(getPedArmor(localPlayer)) or 0),
    })
end, 1000, 0)

-- ---------------------------------------------------------------------------
-- 浏览器生命周期
-- ---------------------------------------------------------------------------

local function onBrowserCreated()
    browserReady = true
    loadBrowserURL(source, UI_URL)
end

local function onBrowserLoadingFailed(url, errorCode, errorDescription)
    outputDebugString(
        ("rst_ui: 页面加载失败 %s (%s: %s)"):format(
            tostring(url),
            tostring(errorCode),
            tostring(errorDescription)
        ),
        1
    )
end

local function createUiBrowser()
    screenW, screenH = guiGetScreenSize()
    browser = createBrowser(screenW, screenH, true, true)
    if not browser then
        outputDebugString("rst_ui: createBrowser 失败", 1)
        return
    end

    addEventHandler("onClientBrowserCreated", browser, onBrowserCreated)
    addEventHandler("onClientBrowserLoadingFailed", browser, onBrowserLoadingFailed)
    addEventHandler("onClientRender", root, render)
end

-- ---------------------------------------------------------------------------
-- 输入转发到 CEF
-- ---------------------------------------------------------------------------

addEventHandler("onClientCursorMove", root, function(_, _, absoluteX, absoluteY)
    if interactive and browserReady then
        injectBrowserMouseMove(browser, absoluteX, absoluteY)
    end
end)

addEventHandler("onClientClick", root, function(button, state, absoluteX, absoluteY)
    if not interactive or not browserReady then
        return
    end

    injectBrowserMouseMove(browser, absoluteX, absoluteY)
    if state == "down" then
        injectBrowserMouseDown(browser, button)
    else
        injectBrowserMouseUp(browser, button)
    end
end)

addEventHandler("onClientMouseWheel", root, function(delta)
    if interactive and browserReady and type(delta) == "number" then
        injectBrowserMouseWheel(browser, delta)
    end
end)

-- ---------------------------------------------------------------------------
-- JS -> Lua 事件（页面里用 mta.triggerEvent 触发）
-- ---------------------------------------------------------------------------

addEvent("rst:ui:ready", false)
addEvent("rst:ui:menu:close", false)
addEvent("rst:ui:test", false)
addEvent("rst:ui:devtools", false)
addEvent("rst:ui:serverInfo", true)

addEventHandler("rst:ui:ready", root, function()
    sendBootstrap()
end)

addEventHandler("rst:ui:menu:close", root, function()
    setMenuOpen(false)
end)

addEventHandler("rst:ui:test", root, function()
    dispatch("toast", {
        text = "Lua 收到测试事件，玩家：" .. (getPlayerName(localPlayer) or "?"),
    })
end)

addEventHandler("rst:ui:devtools", root, function()
    if browser then
        toggleBrowserDevTools(browser)
    end
end)

addEventHandler("rst:ui:serverInfo", root, function(json)
    local data = fromJSON(json)
    if type(data) ~= "table" then
        return
    end

    serverInfo.name = data.name or serverInfo.name
    serverInfo.online = data.online or serverInfo.online
    if browserReady then
        sendBootstrap()
    end
end)

-- ---------------------------------------------------------------------------
-- 入口 / 退出
-- ---------------------------------------------------------------------------

bindKey("F2", "down", function()
    setMenuOpen(not menuOpen)
end)

addCommandHandler("ui", function()
    setMenuOpen(not menuOpen)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if statsTimer and isTimer(statsTimer) then
        killTimer(statsTimer)
    end

    setInteractive(false)
    if browser and isElement(browser) then
        destroyElement(browser)
    end
    removeEventHandler("onClientRender", root, render)
end)

createUiBrowser()
