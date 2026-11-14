--[[
    rst_ui / server/accounts.lua

    账号存储：SQLite（全局 databases 目录），bcrypt 哈希。
    账号名直接使用玩家进入服务器时的昵称。
]]

Accounts = {}

local config = RST.config
local db

function Accounts.init()
    db = dbConnect('sqlite', ':/rst_ui_accounts.db')
    if not db then
        outputServerLog('[rst_ui] 无法连接账号数据库')
        return false
    end

    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS accounts (
            username TEXT PRIMARY KEY,
            password_hash TEXT NOT NULL,
            created_at INTEGER NOT NULL
        )
    ]])
    return true
end

function Accounts.isReady()
    return db ~= nil
end

local function queryOne(callback, sql, ...)
    if not db then
        callback(nil)
        return
    end

    local handle = dbQuery(db, sql, ...)
    if not handle then
        callback(nil)
        return
    end

    local result = dbPoll(handle, -1)
    callback(result and result[1] or nil)
end

function Accounts.exists(username, callback)
    queryOne(function(row)
        callback(row ~= nil)
    end, 'SELECT username FROM accounts WHERE username = ? LIMIT 1', username)
end

function Accounts.create(username, password, callback)
    if not db then
        callback(false, '账号系统不可用')
        return
    end

    passwordHash(password, 'bcrypt', {}, function(hash)
        if not hash then
            callback(false, '密码处理失败，请重试')
            return
        end

        local ok = dbExec(
            db,
            'INSERT INTO accounts (username, password_hash, created_at) VALUES (?, ?, ?)',
            username,
            hash,
            getRealTime().timestamp
        )

        if not ok then
            callback(false, '注册失败，账号可能已存在')
            return
        end

        callback(true)
    end)
end

function Accounts.verify(username, password, callback)
    queryOne(function(row)
        if not row then
            callback(false, '账号不存在，请先注册')
            return
        end

        local ok = passwordVerify(password, row.password_hash)
        if not ok then
            callback(false, '密码错误')
            return
        end

        callback(true)
    end, 'SELECT password_hash FROM accounts WHERE username = ? LIMIT 1', username)
end
