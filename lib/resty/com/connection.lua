---
--- MySQL底层Connection管理器
---

local mysql        = require "resty.mysql"
local utils        = require "resty.com.utils"
local setmetatable = setmetatable

local _M = {}
local mt = { __index = _M }

-- 标记连接状态
local CONNECTED = 1 -- 已连接
local DISCONNECTED = 0 -- 已断开

-- 标记是否使用unix socket
local use_socket = false

-- db配置
local config = {
    -- host            = "127.0.0.1",
    -- port            = 3306,
    -- path            = "",
    database        = "",
    user            = "",
    password        = "",
    charset         = "",
    compact_arrays  = false,
    max_packet_size = 1024 * 1024,
}

-- db连接池相关配置
local pool_config = {
    pool_size = 10,
    pool_timeout = 10000 -- ms
}

-- 设置配置
local function _config(_, config_set)
    if utils.empty(config_set) then
        utils.exception("[config]please set MySQL config use associative array")
    end

    -- db连接池相关配置
    if not utils.empty(config_set.pool_size) then
        pool_config.pool_size = config_set.pool_size
    end
    if not utils.empty(config_set.pool_timeout) then
        pool_config.pool_timeout = config_set.pool_timeout
    end

    -- db\user\pwd
    config.database = config_set.database
    config.user     = config_set.username
    config.password = config_set.password
    config.charset  = config_set.charset

    -- 检查主机连接协议自动配置连接参数
    if not utils.empty(config_set.socket) then
        use_socket  = true
        config.path = config_set.socket
    else
        config.host = config_set.host
        config.port = config_set.port
    end
end
_M.config = _config

-- 内部方法：初始化resty.mysql
-- 惰性连接，只有执行sql时才真正执行连接过程
local function _init(self, config_set)
    -- 若传递有配置参数，则调用
    if not utils.empty(config_set) then
        self:config(config_set)
    end

    -- lua-resty-mysql建立实例
    local instance, err = mysql:new()
    if not instance then
        utils.exception("[new]failed to instantiate MySQL:" .. err)
        return nil
    end

    instance:set_timeout(1000) -- 1 sec

    -- 返回初始化的resty.mysql对象，内部并未执行建立鉴权和连接的过程
    return instance
end

-- 内部方法：执行resty.mysql真正建立连接过程
local function _connect(self)
    -- 已建立过连接
    if self.state == CONNECTED then
        return
    end

    --- 执行连接并检查
    local ok, err, code, sqlstate = self.instance:connect(config)
    if not ok then
        -- 处理错误码、mysql错误编号、错误描述
        if nil ~= code then
            if not utils.empty(sqlstate) then
                err = err .. ", error code is " .. code .. " and " .. sqlstate
            end
        end
        self.state = DISCONNECTED

        utils.exception("[connect]failed to connect MySQL. " .. err)

        return
    end

    -- 标记已连接
    self.state = CONNECTED
end

-- 实例化connection
-- @param array _config 可选的链接参数
-- @return DB instance
function _M.new(self, config_set)
    local instance = _init(self, config_set)
    local _self = {
        state          = DISCONNECTED, -- new出的对象并未建立起连接，只有一个resty.mysql对象
        instance       = instance, -- resty.mysql对象，是否已执行连接，由state标记
        in_transaction = false, -- 内部标记是否处于事务中
    }

    return setmetatable(_self, mt)
end

-- 建立连接，方法体内部会检查是否已建立过连接
-- @param array _config 可选的链接配置参数
-- @return DB instance
function _M.connect(self, config_set)
    -- 传递有配置参数则设置配置参数
    if not utils.empty(config_set) then
        self:config(config_set)
    end

    -- 智能执行连接
    _connect(self)

    return self
end

-- 执行查询类型sql，没有返回值
-- @param string sql 执行的sql语句
function _M.query(self, sql)
    -- 智能执行连接
    self:connect()
    -- 返回发送给mysql的字节数，出错则nil,err字符串描述内容
    local byte,err = self.instance:send_query(sql)

    if utils.empty(byte) then
        utils.exception(err)
    end
end

-- 迭代返回结果集，调用方需迭代
-- @return array
function _M.fetch(self)
    -- read
    local res, err, code, sqlstate = self.instance:read_result()

    -- 如果没有结果集则终止迭代
    if nil ~= res then
        return res -- array，可能是空数组
    end

    -- 如果是sql错误，则记录错误日志
    if nil ~= code then
        if not utils.empty(sqlstate) then
            err = err .. ", error code is " .. code .. " and " .. sqlstate
        end
        utils.exception("[fetch]failed to execute SQL statement. " .. err)
    end

    return nil
end

-- fetch方法返回的迭代器，多条分号分隔的sql多结果集迭代获取
local function fetchIterator(self, index)
    index = index + 1

    -- 迭代器，调用方需迭代获取所有结果
    local res, err, code, sqlstate = self.instance:read_result()

    -- 如果没有结果集则终止迭代
    if res then
        return index, res
    end

    -- 如果是sql错误，则记录错误日志
    if nil ~= code then
        if not utils.empty(sqlstate) then
            err = err .. ", error code is " .. code .. " and " .. sqlstate
        end
        utils.exception("[fetchMany]failed to execute SQL statement. " .. err)
    end

    return nil
end

-- 如果有多条sql同时被发送，则需要迭代获取结果集
function _M.fetchMany(self)
    return fetchIterator, self, 0;
end

-- 执行查询类型sql，没有返回值，使用affectedRows或lastInsertId获取返回值
-- @param string sql 执行的sql语句
function _M.execute(self, sql)
    -- 智能执行连接
    self:connect()
    -- 返回发送给mysql的字节数，出错则nil,err字符串描述内容
    local byte,err = self.instance:send_query(sql)

    if utils.empty(byte) then
        utils.exception(err)
    end
end

-- 返回受影响行数
-- @return number|nil 执行成功返回影响行数，执行失败返回nil[可能影响行数为0，注意判断的逻辑合理性]
function _M.affectedRows(self)
    -- read
    local res, err, code, sqlstate = self.instance:read_result()

    -- 如果没有结果集则终止迭代
    if nil ~= res then
        return res.affected_rows or nil -- 返回影响行数或nil
    end

    -- 如果是sql错误，则记录错误日志
    if nil ~= code then
        if not utils.empty(sqlstate) then
            err = err .. ", error code is " .. code .. " and " .. sqlstate
        end
        utils.exception("[affectedRows]failed to execute SQL statement. " .. err)
    end

    return nil
end

-- 返回最后插入行的ID或序列值
-- @return number|nil 返回新增id或失败nil
function _M.lastInsertId(self)
    -- read
    local res, err, code, sqlstate = self.instance:read_result()

    -- 如果没有结果集则终止迭代
    if nil ~= res then
        return res.insert_id or nil -- 新增的id或nil
    end

    -- 如果是sql错误，则记录错误日志
    if nil ~= code then
        if not utils.empty(sqlstate) then
            err = err .. ", error code is " .. code .. " and " .. sqlstate
        end
        utils.exception("[lastInsertId]failed to execute SQL statement. " .. err)
    end

    return nil
end

-- 开始一个事务
-- @return boolean
function _M.startTrans(self)
    if self.in_transaction then
        -- 不支持事务嵌套
        utils.exception("[startTrans]do not support transactions nesting")
        return false
    end

    -- 智能执行连接
    self:connect()

    -- 开始事务
    local res, err, code, sqlstate = self.instance:query("START TRANSACTION;")

    -- 如果是sql错误，则记录错误日志
    if utils.empty(res) or nil ~= code then
        if not utils.empty(sqlstate) then
            err = err .. ", error code is " .. code .. " and " .. sqlstate
        end
        utils.exception("[startTrans]failed to execute SQL statement. " .. err)
        return false
    end

    -- 标记当前处于事务之中
    self.in_transaction = true

    return true
end

-- 回滚一个事务
-- @return boolean
function _M.rollback(self)
    if not self.in_transaction then
        utils.exception("[rollback]do not in transaction, not allow use this method")
        return false
    end

    -- 智能执行连接
    self:connect()

    -- 回滚事务
    local res, err, code, sqlstate = self.instance:query("ROLLBACK;")

    -- 如果是sql错误，则记录错误日志
    if utils.empty(res) or nil ~= code then
        if not utils.empty(sqlstate) then
            err = err .. ", error code is " .. code .. " and " .. sqlstate
        end
        utils.exception("[rollback]failed to execute SQL statement. " .. err)
        return false
    end

    -- 取消事务占用标记
    self.in_transaction = false

    return true
end

-- 提交一个事务
-- @return boolean
function _M.commit(self)
    if not self.in_transaction then
        utils.exception("[commit]do not in transaction, not allow use this method")
        return false
    end

    -- 智能执行连接
    self:connect()

    -- 提交事务 commit
    local res, err, code, sqlstate = self.instance:query("COMMIT;")

    -- 如果是sql错误，则记录错误日志
    if utils.empty(res) or nil ~= code then
        if not utils.empty(sqlstate) then
            err = err .. ", error code is " .. code .. " and " .. sqlstate
        end
        utils.exception("[commit]failed to execute SQL statement. " .. err)
        return false
    end

    -- 取消事务占用标记
    self.in_transaction = false

    return true
end

-- 析构方法：调用方需显式执行以维护连接池
-- 调用方在业务完成之后显式调用析构方法即可
function _M.destruct(self)
    if self.state == CONNECTED then
        -- 析构方法，将底层socket加入连接池，无需显式执行close
        local ok, err = self.instance:set_keepalive(pool_config.pool_timeout, pool_config.pool_size)
        self.state = DISCONNECTED
        if not ok then
            -- 析构将连接放入连接池失败，不报错记录日志，执行关闭操作
            self.instance:close()

            utils.logger(err)
            return false
        end
    end
    return true
end

return _M
