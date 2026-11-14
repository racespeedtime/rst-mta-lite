--[[
    rst_ui / shared/config.lua

    地图、房间、回合、投票等玩法参数（仅服务端加载）。
]]

RST = RST or {}

RST.config = {
    roundSeconds = 30 * 60, -- 每张地图最长 30 分钟
    voteSeconds = 30,       -- 投票持续时间
    respawnDelay = 4000,    -- 死亡后重生间隔
    minPasswordLength = 4,
    maxPasswordLength = 128,

    weapon = 31,            -- M4
    ammo = 500,

    maps = {
        airport = { name = 'Los Santos 机场', x = 1678.0, y = -2286.0, z = 14.0, rot = 90 },
        grove = { name = 'Grove Street', x = 2495.0, y = -1687.0, z = 13.6, rot = 180 },
        beach = { name = 'Santa Maria 海滩', x = 374.0, y = -2074.0, z = 8.0, rot = 0 },
        pershing = { name = 'Pershing Square', x = 1481.0, y = -1772.0, z = 19.0, rot = 90 },
    },

    mapPool = { 'airport', 'grove', 'beach', 'pershing' },

    rooms = {
        { id = 'main', name = 'DeathMatch · 主舞台', dimension = 1 },
        { id = 'sub', name = 'DeathMatch · 副舞台', dimension = 2 },
    },
}
