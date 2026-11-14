--[[
    rst_ui / shared/config.lua

    地图、房间、回合、投票等玩法参数（仅服务端加载）。
]]

RST = RST or {}

RST.config = {
    roundSeconds = 30 * 60, -- 每张地图最长 30 分钟
    defaultMode = 'training', -- training | competitive
    competitiveLives = 10,  -- 竞技模式每人 rewind 命数
    voteSeconds = 30,       -- 换图投票持续时间
    modeVoteSeconds = 20,   -- 模式投票持续时间
    votePoolSize = 5,       -- 每次投票随机从地图池抽取的候选数量
    voteCooldown = 180,     -- 手动发起换图投票的冷却（秒）
    modeVoteCooldown = 120, -- 手动发起模式投票的冷却（秒）
    recentMapLimit = 2,     -- 最近玩过的地图数量，抽池时尽量避开
    playPopularityWeight = 5, -- 服务器内每玩一场给热度加分
    respawnDelay = 4000,    -- 死亡后重生间隔
    spawnCountdown = 3,     -- 训练模式出生倒计时（秒）
    competitiveCountdown = 5, -- 竞技模式全员准备后的倒计时（秒）
    finishRadius = 30,       -- 终点判定半径（米）
    raceEndCountdown = 30,   -- 竞速第一名完赛后的结算倒计时
    raceResultSeconds = 8,   -- 结算排行展示时间，之后进入换图投票
    trainingReturnSeconds = 5, -- 训练模式完赛回出生点延迟
    minPasswordLength = 8,
    maxPasswordLength = 128,

    -- 竞速模式：按地图 spawnpoint 给对应车辆，不默认安装氮气
    vehicle = 411,

    -- 地图池不在这里维护：MapRegistry 运行时扫描原生 type="map" resource，
    -- 从 meta.xml / .map 读取 name、author、spawnpoint、vehicle、Hunter finish。

    -- 当前两个舞台共用同一个 map resource，同一时间只允许一个舞台开局。
    rooms = {
        { id = 'main', name = 'DeathMatch · 主舞台', dimension = 0 },
        { id = 'sub', name = 'DeathMatch · 副舞台', dimension = 0 },
    },
}
