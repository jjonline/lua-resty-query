---
--- MySQL底层Connection管理器
---

local mysql = require "resty.mysql"
local utils = require "resty.com.utils"

local connection

-- 支持断线重连的建立连接，内部可支持连接池
connection.connect = function() end

-- 断开连接
connection.close = function() end

-- 执行查询类型sql
connection.query = function() end

-- 执行操作类型sql，应当返回受影响的行数
connection.execute = function() end

-- 结果集返回下一行
connection.fetch = function() end

-- 返回所有结果集
connection.fetchAll = function() end

-- 返回最后插入行的ID或序列值
connection.lastInertId = function() end

-- 开始一个事务
connection.beginTransaction = function() end

-- 回滚一个事务
connection.rollback = function() end

-- 提交一个事务
connection.commit = function() end

return connection
