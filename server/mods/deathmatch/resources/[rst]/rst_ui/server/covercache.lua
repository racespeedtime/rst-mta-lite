--[[
    rst_ui / server/covercache.lua

    地图封面服务端缓存：
    - mtavault 的 cover 基本是 YouTube 缩略图，玩家客户端不直接访问远端
    - 服务端 fetchRemote 下载到 covers/<key>.jpg，再读成 data URI 下发给 CEF
    - 同一张图并发请求只下载一次
    - 限并发、限速、小时预算、失败指数退避、连续失败熔断
    - fetchRemote 由 libcurl 驱动，会继承 MTA Server 进程的 HTTP_PROXY / HTTPS_PROXY
]]

CoverCache = {}

local config = RST.config.coverCache or {}
local MAX_ACTIVE = math.max(1, tonumber(config.maxConcurrent) or 2)
local MIN_INTERVAL_MS = math.max(0, tonumber(config.minIntervalMs) or 1200)
local QUEUE_LIMIT = math.max(1, tonumber(config.queueLimit) or 60)
local HOURLY_LIMIT = math.max(1, tonumber(config.hourlyLimit) or 300)
local FAILURE_BASE = math.max(30, tonumber(config.failureBaseSeconds) or 300)
local FAILURE_MAX = math.max(FAILURE_BASE, tonumber(config.failureMaxSeconds) or 21600)
local BREAKER_FAILURES = math.max(1, tonumber(config.breakerFailures) or 8)
local BREAKER_SECONDS = math.max(60, tonumber(config.breakerSeconds) or 1800)
local QUALITY_FILES = {
    mq = 'mqdefault.jpg',
    hq = 'hqdefault.jpg',
    sd = 'sddefault.jpg',
    max = 'maxresdefault.jpg',
}
local THUMB_QUALITY = tostring(config.thumbnailQuality or 'mq'):lower()

local pending = {}
local waiters = {}
local failed = {}
local queue = {}
local queueOrder = {}
local dataCache = {}
local activeRequests = {}
local progressTimer

local activeFetches = 0
local nextFetchAt = 0
local budgetStart = os.time()
local budgetCount = 0
local consecutiveFailures = 0
local breakerUntil = 0
local pumpTimer
local running = true
local pumpQueue

local function safeKey(value)
    return tostring(value or ''):gsub('[^%w_-]', '_')
end

-- YouTube 原图 hqdefault 是 480x360 的 4:3 带黑边缩略图；
-- mqdefault 是 320x180 的 16:9，体积大约减半，地图详情预览完全够用。
local function optimizeCoverUrl(url)
    if THUMB_QUALITY == 'original' then
        return url
    end
    local file = QUALITY_FILES[THUMB_QUALITY]
    if not file then
        return url
    end
    local lower = url:lower()
    if not lower:find('img.youtube.com', 1, true) and not lower:find('i.ytimg.com', 1, true) then
        return url
    end
    for _, name in ipairs({ 'hqdefault', 'mqdefault', 'sddefault', 'maxresdefault' }) do
        local needle = '/' .. name .. '.jpg'
        if url:find(needle, 1, true) then
            return (url:gsub('/' .. name .. '%.jpg', '/' .. file, 1))
        end
    end
    return url
end

local function imageMime(data)
    if type(data) ~= 'string' or #data < 4 then
        return nil
    end
    local b1, b2, b3, b4 = data:byte(1, 4)
    if b1 == 0xFF and b2 == 0xD8 and b3 == 0xFF then
        return 'image/jpeg'
    end
    if b1 == 0x89 and b2 == 0x50 and b3 == 0x4E and b4 == 0x47 then
        return 'image/png'
    end
    if b1 == 0x47 and b2 == 0x49 and b3 == 0x46 then
        return 'image/gif'
    end
    if b1 == 0x52 and b2 == 0x49 and b3 == 0x46 and b4 == 0x46 then
        return 'image/webp'
    end
    return nil
end

local function imageDataUri(data)
    local mime = imageMime(data)
    if not mime then
        return nil
    end
    local ok, encoded = pcall(encodeString, 'base64', data)
    if not ok or type(encoded) ~= 'string' or encoded == '' then
        return nil
    end
    return 'data:' .. mime .. ';base64,' .. encoded
end

local function readCoverFile(file)
    if not file or file == '' then
        return nil
    end
    if dataCache[file] then
        return dataCache[file]
    end
    if not fileExists(file) then
        return nil
    end

    local handle = fileOpen(file)
    if not handle then
        return nil
    end
    local size = fileGetSize(handle)
    local data = size > 0 and fileRead(handle, size) or nil
    fileClose(handle)

    local uri = imageDataUri(data)
    if uri then
        dataCache[file] = uri
    end
    return uri
end

local function localCoverFile(detail)
    local legacy = 'covers/' .. safeKey(detail.id) .. '.jpg'
    if fileExists(legacy) then
        return legacy
    end
    local keyed = 'covers/' .. safeKey(detail.mtavaultId or detail.id) .. '.jpg'
    if fileExists(keyed) then
        return keyed
    end
    return nil
end

local function notify(key, cover)
    local list = waiters[key]
    waiters[key] = nil
    for _, waiter in ipairs(list or {}) do
        if isElement(waiter.player) then
            triggerClientEvent(waiter.player, 'rst:ui:mapdetail:cover', waiter.player, toJSON({
                requestId = waiter.requestId,
                mapId = waiter.mapId,
                cover = cover,
                pending = false,
                error = cover == nil,
                progress = cover and 100 or 0,
            }))
        end
    end
end

local function notifyProgress(key, progress)
    local list = waiters[key]
    for _, waiter in ipairs(list or {}) do
        if isElement(waiter.player) then
            triggerClientEvent(waiter.player, 'rst:ui:mapdetail:cover', waiter.player, toJSON({
                requestId = waiter.requestId,
                mapId = waiter.mapId,
                cover = nil,
                pending = true,
                error = false,
                progress = progress,
            }))
        end
    end
end

local function ensureProgressTimer()
    if progressTimer and isTimer(progressTimer) then
        return
    end
    progressTimer = setTimer(function()
        local any = false
        for key, active in pairs(activeRequests) do
            any = true
            local ok, info = pcall(getRemoteRequestInfo, active.request)
            local progress = -1
            if ok and type(info) == 'table' then
                local received = tonumber(info.bytesReceived) or 0
                local total = tonumber(info.bytesTotal) or 0
                if total > 0 then
                    progress = math.max(0, math.min(100, math.floor(received / total * 100)))
                end
            end
            notifyProgress(key, progress)
        end
        if not any then
            killTimer(progressTimer)
            progressTimer = nil
        end
    end, 500, 0)
end

local function retryDelay(attempts)
    local delay = FAILURE_BASE
    for _ = 2, math.max(1, attempts) do
        delay = delay * 2
        if delay >= FAILURE_MAX then
            return FAILURE_MAX
        end
    end
    return math.min(delay, FAILURE_MAX)
end

local function budgetAllowed()
    local now = os.time()
    if now - budgetStart >= 3600 then
        budgetStart = now
        budgetCount = 0
    end
    return budgetCount < HOURLY_LIMIT
end

local function markFailed(key, attempts)
    failed[key] = {
        at = os.time(),
        attempts = attempts,
    }
end

local function failQueue(reason)
    for _, key in ipairs(queueOrder) do
        local job = queue[key]
        queue[key] = nil
        pending[key] = nil
        if job then
            markFailed(key, 1)
            notify(key, nil)
        end
    end
    queueOrder = {}
    outputServerLog(('[COVER] 队列暂停：%s'):format(tostring(reason)))
end

local function schedulePump(delay)
    if not running then
        return
    end
    if pumpTimer and isTimer(pumpTimer) then
        killTimer(pumpTimer)
    end
    pumpTimer = setTimer(function()
        pumpTimer = nil
        pumpQueue()
    end, math.max(50, delay or 50), 1)
end

local function onFetchFailed(key, status, data)
    consecutiveFailures = consecutiveFailures + 1
    local previous = failed[key]
    local attempts = (previous and previous.attempts or 0) + 1
    markFailed(key, attempts)

    if status == 403 or status == 429 or status == 503 then
        breakerUntil = math.max(breakerUntil, os.time() + BREAKER_SECONDS * 2)
        outputServerLog(('[COVER] 远端返回 %s，熔断至 %d'):format(
            tostring(status), breakerUntil
        ))
    elseif consecutiveFailures >= BREAKER_FAILURES then
        breakerUntil = os.time() + BREAKER_SECONDS
        consecutiveFailures = 0
        outputServerLog(('[COVER] 连续失败触发熔断，暂停远端请求 %d 秒'):format(BREAKER_SECONDS))
    end

    outputServerLog(('[COVER] 缓存失败 %s status=%s attempts=%d'):format(
        tostring(key), tostring(status), attempts
    ))
    if type(data) == 'string' and #data > 0 and #data < 120 then
        outputServerLog(('[COVER] 失败响应 %s: %s'):format(tostring(key), data))
    end
end

local function startFetch(key, url, file)
    if not running then
        return
    end

    activeFetches = activeFetches + 1
    pending[key] = true
    nextFetchAt = getTickCount() + MIN_INTERVAL_MS + math.random(0, 400)
    budgetCount = budgetCount + 1

    -- 当前服务端构建仍以 legacy 签名为准：URL, queue, attempts, timeout, callback
    url = optimizeCoverUrl(url)
    local request = fetchRemote(url, 'cover-cache', 2, 8000, function(data, info)
        local active = activeRequests[key]
        local startedAt = active and active.startedAt or 0
        activeFetches = math.max(0, activeFetches - 1)
        activeRequests[key] = nil
        if not running then
            return
        end
        pending[key] = nil

        local status, success
        if type(info) == 'table' then
            status = tonumber(info.statusCode)
            success = info.success ~= false
        elseif type(info) == 'number' then
            status = info
            success = info == 0
        else
            success = true
        end

        local valid = success
            and type(data) == 'string'
            and #data > 0
            and data ~= 'ERROR'
            and imageMime(data) ~= nil
        if valid and status and status >= 400 then
            valid = false
        end

        local uri
        if valid then
            local handle = fileCreate(file)
            if handle then
                fileWrite(handle, data)
                fileClose(handle)
                uri = readCoverFile(file)
            end
            if not uri then
                uri = imageDataUri(data)
            end
        end

        if uri then
            dataCache[file] = uri
            failed[key] = nil
            consecutiveFailures = 0
            local elapsed = startedAt > 0 and (getTickCount() - startedAt) or 0
            outputServerLog(('[COVER] 缓存成功 %s bytes=%d time=%dms'):format(
                tostring(key), type(data) == 'string' and #data or 0, elapsed
            ))
        else
            onFetchFailed(key, status, data)
        end

        notify(key, uri)
        pumpQueue()
    end)

    if request then
        activeRequests[key] = { request = request, startedAt = getTickCount() }
        ensureProgressTimer()
    else
        activeFetches = math.max(0, activeFetches - 1)
        pending[key] = nil
        onFetchFailed(key, nil, nil)
        notify(key, nil)
        pumpQueue()
    end
end

pumpQueue = function()
    if not running then
        return
    end
    if activeFetches >= MAX_ACTIVE or #queueOrder == 0 then
        return
    end

    local now = os.time()
    if breakerUntil > now then
        failQueue('熔断中')
        return
    end
    if not budgetAllowed() then
        failQueue('小时预算已用完')
        return
    end

    local waitMs = nextFetchAt - getTickCount()
    if waitMs > 0 then
        schedulePump(waitMs)
        return
    end

    local key = table.remove(queueOrder, 1)
    local job = key and queue[key] or nil
    if not key or not job then
        pumpQueue()
        return
    end
    queue[key] = nil
    job()

    if #queueOrder > 0 and activeFetches < MAX_ACTIVE then
        schedulePump(10)
    end
end

-- 把 detail.cover 换成 data URI；未命中时返回 coverPending
function CoverCache.prepare(player, detail, requestId)
    if type(detail) ~= 'table' then
        return detail
    end

    detail.coverPending = false
    detail.coverError = false
    detail.coverProgress = -1
    local cover = detail.cover
    if type(cover) ~= 'string' or cover == '' then
        return detail
    end

    local cachedFile = localCoverFile(detail)
    if cachedFile then
        local uri = readCoverFile(cachedFile)
        if uri then
            detail.cover = uri
            return detail
        end
    end

    if not cover:lower():match('^https?://') then
        detail.cover = readCoverFile(cover)
        return detail
    end

    local key = safeKey(detail.mtavaultId or detail.id)
    local file = 'covers/' .. key .. '.jpg'

    if dataCache[file] then
        detail.cover = dataCache[file]
        return detail
    end

    local failure = failed[key]
    if failure then
        local retryAt = (failure.at or 0) + retryDelay(failure.attempts or 1)
        if os.time() < retryAt then
            detail.cover = nil
            return detail
        end
    end

    if breakerUntil > os.time() then
        detail.cover = nil
        return detail
    end

    if pending[key] then
        detail.cover = nil
        detail.coverPending = true
        waiters[key] = waiters[key] or {}
        waiters[key][#waiters[key] + 1] = {
            player = player,
            mapId = detail.id,
            requestId = requestId,
        }
        return detail
    end

    if #queueOrder >= QUEUE_LIMIT then
        detail.cover = nil
        return detail
    end

    detail.cover = nil
    detail.coverPending = true
    detail.coverProgress = -1
    waiters[key] = waiters[key] or {}
    waiters[key][#waiters[key] + 1] = {
        player = player,
        mapId = detail.id,
        requestId = requestId,
    }

    queue[key] = function()
        startFetch(key, cover, file)
    end
    queueOrder[#queueOrder + 1] = key
    pending[key] = true
    pumpQueue()
    return detail
end

-- 不在 Lua 里读取环境变量（MTA 禁止 os.getenv）；启动前设置的 HTTP(S)_PROXY
-- 会被 fetchRemote 底层的 libcurl 直接继承。

addEventHandler('onResourceStop', resourceRoot, function()
    running = false
    if pumpTimer and isTimer(pumpTimer) then
        killTimer(pumpTimer)
    end
    pumpTimer = nil
    if progressTimer and isTimer(progressTimer) then
        killTimer(progressTimer)
    end
    progressTimer = nil
end)
