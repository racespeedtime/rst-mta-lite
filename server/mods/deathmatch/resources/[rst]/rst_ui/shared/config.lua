--[[
    rst_ui / shared/config.lua

    地图、房间、回合、投票等玩法参数（仅服务端加载）。
]]

RST = RST or {}

function RST.nowMs()
    local t = getRealTime()
    return t.timestamp * 1000 + (tonumber(t.millisecond) or 0)
end

RST.config = {
    roundSeconds = 60 * 60, -- 每张地图最长 1 小时
    defaultMode = 'training', -- training | competitive
    competitiveLives = 10,  -- 竞技模式每人 rewind 命数
    voteSeconds = 30,       -- 换图投票持续时间
    modeVoteSeconds = 20,   -- 模式投票持续时间
    votePoolSize = 5,       -- 每次投票随机从地图池抽取的候选数量
    voteCooldown = 180,     -- 手动发起换图投票的冷却（秒）
    modeVoteCooldown = 120, -- 手动发起模式投票的冷却（秒）
    startVoteCooldown = 10, -- 开局投票的短冷却（秒），投票结束/失败后计时
    recentMapLimit = 2,     -- 最近玩过的地图数量，抽池时尽量避开
    manualVoteImmediate = true, -- 玩家自发投票出结果后立即换图；false = 等本回合结束再换
    chatMinIntervalMs = 900,   -- 两条聊天之间的最小间隔（毫秒）
    chatBurstWindowMs = 10000, -- 聊天频率窗口（毫秒）
    chatBurstLimit = 6,        -- 窗口内最多条数，超出丢弃
    playPopularityWeight = 5, -- 服务器内每玩一场给热度加分
    respawnDelay = 4000,    -- 死亡后重生间隔
    spawnCountdown = 3,     -- 训练模式出生倒计时（秒）
    competitiveCountdown = 5, -- 竞技模式全员准备后的倒计时（秒）
    raceEndCountdown = 30,   -- 竞速第一名完赛后的结算倒计时
    raceResultSeconds = 8,   -- 结算排行展示时间，之后进入换图投票
    trainingReturnSeconds = 6, -- 训练模式完赛回出生点延迟
    finishResultDelay = 3,      -- 完赛先 toast，几秒后再弹结算
    waterRespawnSpeed = 1.5,    -- 竞技落水按 R 重生允许的最大速度
    blockVehicleExit = true,    -- 比赛进行中（训练/竞技）禁止主动下车
    coverCache = {
        thumbnailQuality = 'mq',  -- YouTube 缩略图质量：mq / hq / sd / max / original
        maxConcurrent = 2,       -- 同时下载封面的最大请求数
        minIntervalMs = 1200,    -- 两次请求之间的最小间隔
        queueLimit = 60,         -- 等待队列上限，超过直接放弃本次加载
        hourlyLimit = 300,       -- 每小时最多请求数，避免触发远端风控
        failureBaseSeconds = 300, -- 首次失败后的冷却
        failureMaxSeconds = 21600, -- 连续失败的最大冷却
        breakerFailures = 8,     -- 连续失败多少次后暂停远端请求
        breakerSeconds = 1800,   -- 熔断持续时间
    },
    scoreTable = { 10, 8, 6, 4, 3, 2, 1 },
    teamColors = {
        red = { 255, 80, 80 },
        blue = { 70, 150, 255 },
    },
    minPasswordLength = 8,
    maxPasswordLength = 128,

    -- 竞速模式：按地图 spawnpoint 给对应车辆，不默认安装氮气
    vehicle = 411,

    -- 地图池不在这里维护：MapRegistry 运行时扫描原生 type="map" resource，
    -- 从 meta.xml / .map 读取 name、author、spawnpoint、vehicle、Hunter finish。

    -- 一个服务器即一个舞台；不再提供主/副舞台选择
    rooms = {
        { id = 'main', name = 'DeathMatch · 服务器', dimension = 0 },
    },
}
