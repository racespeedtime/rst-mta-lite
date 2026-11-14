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
    spawnCountdown = 3,     -- 进入回合出生后的 3-2-1-GO 倒计时（秒）
    minPasswordLength = 4,
    maxPasswordLength = 128,

    -- 竞速模式：每张赛道出生直接给一辆赛车
    vehicle = 411,
    vehicleNitro = true,

    -- 地图作者与流行度是占位信息；流行度后续可从外部站点抓取后写入
    maps = {
        airport = { name = 'Los Santos 机场', author = 'RST Team', popularity = 78, vehicle = 411, x = 1678.0, y = -2286.0, z = 14.0, rot = 90 },
        grove = { name = 'Grove Street', author = 'RST Team', popularity = 95, vehicle = 411, x = 2495.0, y = -1687.0, z = 13.6, rot = 180 },
        beach = { name = 'Santa Maria 海滩', author = 'RST Team', popularity = 62, vehicle = 411, x = 374.0, y = -2074.0, z = 8.0, rot = 0 },
        pershing = { name = 'Pershing Square', author = 'RST Team', popularity = 84, vehicle = 411, x = 1481.0, y = -1772.0, z = 19.0, rot = 90 },
    },

    mapPool = { 'airport', 'grove', 'beach', 'pershing' },

    rooms = {
        { id = 'main', name = 'DeathMatch · 主舞台', dimension = 1 },
        { id = 'sub', name = 'DeathMatch · 副舞台', dimension = 2 },
    },
}
