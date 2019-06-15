---
--- MySQL底层Connection管理器
---

local mysql = require "resty.mysql"
local utils = require "resty.com.utils"

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
        utils.exception("please set MySQL config")
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

    -- lua-resty-mysql建立实例和连接
    local instance, err = mysql:new()
    if not instance then
        utils.exception("failed to instantiate mysql: " .. err)
        return nil
    end

    instance:set_timeout(1000) -- 3 sec

    -- 返回初始化并建立好连接的resty.mysql对象
    return instance
end

-- 内部方法：执行resty.mysql真正建立连接过程
local function _connect(self)
    -- 已建立过连接
    if self.state == CONNECTED then
        return
    end

    --- 执行连接并检查
    local ok, error, code, state = self.instance:connect(config)
    if not ok then
        utils.exception("failed to connect: " .. error)
        self.state = DISCONNECTED
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
        if utils.empty(sqlstate) then
            sqlstate = ''
        else
            sqlstate = "[" .. sqlstate .. "]"
        end
        utils.logger(code .. "- " .. sqlstate .. err)
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
    if code ~= nil then
        if utils.empty(sqlstate) then
            sqlstate = ''
        else
            sqlstate = "[" .. sqlstate .. "]"
        end
        utils.logger(code .. "-" .. sqlstate .. err)
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
        if utils.empty(sqlstate) then
            sqlstate = ''
        else
            sqlstate = "[" .. sqlstate .. "]"
        end
        utils.logger(code .. "-" .. sqlstate .. err)
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
        if utils.empty(sqlstate) then
            sqlstate = ''
        else
            sqlstate = "[" .. sqlstate .. "]"
        end
        utils.logger(code .. "-" .. sqlstate .. err)
    end

    return nil
end

-- 开始一个事务
function _M.beginTransaction(self) end

-- 回滚一个事务
function _M.rollback(self) end

-- 提交一个事务
function _M.commit(self) end

-- 析构方法：不要求调用方显示执行close和维护连接池
-- 调用方在业务完成之后显式调用析构方法即可
function _M.destruct(self)
    if self.state == CONNECTED then
        -- 析构方法，将底层socket加入连接池，无需显式执行close
        local ok, err = self.instance:set_keepalive(pool_config.pool_timeout, pool_config.pool_size)
        if ok then
            self.state = DISCONNECTED
        else
            utils.exception(err)
            return false
        end
        return true;
    end
    return true
end

return _M
