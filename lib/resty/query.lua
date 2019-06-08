---
--- Db查询执行器
---

----------------------------------------------------------------
--- 实现后的用法如下：
---
--- <引入query类>
--- local query = require("app.lib.query")
---
--- <`实例化`query类产生1个类实例，参数为无前缀的表名称>
--- local table_query = query("table_name")
---
--- 查询单条数据用法：
---     local one_result = table_query:where({where}):find()
--- 查询多条数据用法：
---     local list_result = table_query:where({where}):select()
--- 分页查询数据用法：
---     local page_result = table_query:where({where}):page(now_page, page_limit, is_complex)
--- 更新数据用法：
---     local update_result = table_query:where({where}):update() -- 为避免整个表更新，where为空时不执行，且报告异常
--- 删除数据用法：
---     local delete_result = table_query:where({where}):delete() -- 为避免整个表删除，where为空时不执行，且报告异常
--- 新增单条数据用法：
---     local insert_result = table_query:insert({data}) 或 insertGetId
--- 获取本次拟执行的SQL：
---     local insert_result = table_query:where({data}):limit():group():buildSQl("insert|find|select|update|delete")
----------------------------------------------------------------

local utils      = require "resty.com.utils"
local connection = require "resty.com.connection"
local builder    = require "resty.com.builder" --query 继承至 builder

-- 定义内部存储变量
local options = {
    table = nil,
    connection = connection,
    builder = nil,
    where = nil,
}

local function parseTable()  end
local function parseField()  end
local function parseWhere()  end
local function parseJoin()  end
local function parseLimit()  end
local function parseGroup()  end

builder.test = function(self)
    utils.dump(options, true)
    return self
end

-- 初始化方法，类似构造函数
-- @param array config 初始化传入配置数组参数
builder.__construct = function (self, config)
    options.config = config
    return self
end

-- 显式执行Db连接
builder.connect = function (self, ...)

    -- 与db建立tcp连接，支持断线重连

    return self
end

-- 显式执行Db关闭连接
builder.close = function (self, ...)
    return self
end

-- 获取底层connection对象
builder.connection = function ()
    return options.connection
end

-- 闭包方法内执行事务
builder.transaction = function (self, callable)

    return self
end

-- 开始1个事务
builder.startTrans = function (self, callable)

    return self
end

-- commit提交1个事务
builder.commit = function (self, ...)

    return self
end

-- rollback回滚1个事务
builder.rollback = function (self, ...)

    return self
end

-- 依据action动作生成拟执行的sql语句
-- @param string action 拟执行的动作，枚举值：insert|select|find|update|delete
-- @return string
builder.buildSQL = function(self, action)

    return self
end

-- 执行单条数据新增
builder.insert = function (self, ...)

    return self
end

-- 执行单条数据新增并返回新增后的id
builder.insertGetId = function (self, ...)

    return self
end

-- 执行单条查询
builder.find = function (self, ...)

    return self
end

-- 执行多条查询
builder.select = function (self, ...)

    return self
end

-- 执行分页查询
-- @param integer page 当前页码，不传或传nil则自动从http变量名中读取，变量名称配置文件配置
-- @param integer page_size 一页多少条数据，不传或传nil则自动从分页配置中读取
-- @param boolean is_complex 是否复杂模式，不传则默认为简单模式 【复杂模式则返回值自动获取总记录数，简单模式则不获取总记录数】
builder.page = function (self, page, page_size, is_complex)
    utils.dump(page)
    utils.dump(page_size)
    utils.dump(utils.empty(is_complex))
    return self
end

-- 执行更新操作
builder.update = function (self, ...)

    return self
end

-- 执行删除操作
builder.delete = function (self, ...)

    return self
end

-- 执行原生sql的查询--select
-- @param string SQL语句
-- @param array  可选的参数绑定，SQL语句中的问号(?)依次使用该数组参数替换
builder.query = function (self, ...)

    return self
end

-- 执行原生sql的命令--update、delete、create、alter等
-- @param string SQL语句
-- @param array  可选的参数绑定，SQL语句中的问号(?)依次使用该数组参数替换
builder.execute = function (self, ...)

    -- 返回影响行数
    return self
end

-- 可链式调用对象
return builder
