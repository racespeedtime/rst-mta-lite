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
    minPasswordLength = 8,
    maxPasswordLength = 128,

    -- 竞速模式：每张赛道出生直接给一辆赛车
    vehicle = 411,
    vehicleNitro = true,

    -- 真实 mtavault 地图：spawn / Hunter 终点来自本地 .map 扫描
    maps = {
        silent_hill = {
            resource = 'mtavault_silent_hill',
            name = '[DM] BaSzTy v1 - Silent Hill',
            author = 'BaSzTy',
            popularity = 400,
            vehicle = 495,
            x = -159.09961, y = -586.5, z = 2107.158, rot = 89.742,
            finish = { x = 1524.6, y = 3812.6, z = 8.4 },
        },
        a_new_dawn = {
            resource = 'mtavault_a_new_dawn',
            name = '[DM] Nice v10 - A New Dawn',
            author = '*Nice^^',
            popularity = 364,
            vehicle = 411,
            x = 3640.0, y = 5.0, z = 400.76501, rot = -90,
            finish = { x = 6877.4, y = -828.0, z = 1.3 },
        },
        descendants = {
            resource = 'mtavault_descendants_skills_v',
            name = "[DM] Chipy - Descendant's Skills V",
            author = 'Chipy',
            popularity = 341,
            vehicle = 411,
            x = 2978.3994, y = -1668.6953, z = 1610.7008, rot = -90,
            finish = { x = 6940.9, y = 291.6, z = 332.9 },
        },
    },

    mapPool = { 'silent_hill', 'a_new_dawn', 'descendants' },

    -- MTA map resource 是单实例；当前先使用一个 0 维真实地图舞台。
    -- 双舞台同时跑不同地图需要地图资源复制 / 维度实例化，后续再做。
    rooms = {
        { id = 'main', name = 'DeathMatch · 主舞台', dimension = 0 },
    },
}
