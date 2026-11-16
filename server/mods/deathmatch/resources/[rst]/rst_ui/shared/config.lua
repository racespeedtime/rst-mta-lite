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
