---
--- Db查询执行器
---

----------------------------------------------------------------
--- 实现后的用法如下：
---
--- <引入query类>
--- local query = require "resty.query"
---
--- `实例化`query类产生1个类实例，参数为数组结构的配置
--- local table_query = query(config)
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
---     local sql = table_query:where(where):limit(limit):group(group):buildSQL("insert|find|select|update|delete")
----------------------------------------------------------------

local pairs        = pairs
local type         = type
local pcall        = pcall
local table_insert = table.insert
local string_sub   = string.sub
local string_len   = string.len
local setmetatable = setmetatable
local getmetatable = getmetatable
local utils        = require "resty.com.utils"
local connection   = require "resty.com.connection"
local builder      = require "resty.com.builder"

--[[
-- 定义内部存储变量
local options = {
    connection = connection,
    where      = nil
}
]]--

local _M = {}
local mt = { __index = _M }

-- 初始化方法，类似构造函数
-- @param array config 初始化传入配置数组参数，数组结构参照上方 options.config
function _M.new(_, config)
    local build    = builder:new(config)
    local super_mt = getmetatable(build)
    -- 当方法在子类中查询不到时，再去父类中去查找。
    setmetatable(_M, super_mt)
    -- 这样设置后，可以通过self.super.method(self, ...) 调用父类的已被覆盖的方法。
    build.super = setmetatable({}, super_mt)
    return setmetatable(build, mt)
end

-- name方法隐含实例化过程，可直接 query:name(table_name)完成新query对象的生产
-- @param string table 不带前缀的数据表名称
function _M.name(self, table)
    utils.dump(self:getConfig())
    return self:new():table(table)
end

-- 内部方法：解析数据表名
-- @return string
local function parseTable(self)
    -- 获取并检测是否设置表
    local table = self.getOptions('table')
    if utils.empty(table) then
        utils.exception('please set table name without prefix first')
    end

    return table
end

-- 内部方法：解析字段
-- @return string
local function parseField(self)
    local field = self.getOptions('field')

    -- 如果未调用field方法设置字段，则返回通配
    if utils.empty(field) then
        return '*'
    end

    -- 循环处理字段
    local field_str = ''
    for _,item in pairs(field) do
        if item ~= '*' then
            field_str = field_str .. ',' .. item
        end
    end

    return utils.trim(field_str, ',')
end

-- 解析where内部子句
-- @param string logic 运算符 AND|OR
-- @param array  item  字段|条件|查询值
-- @return string
local function parseWhereItem(logic, item)
    local column    = item[1]
    local operate   = item[2]
    local condition = item[3]

    if 'NULL' == operate then
        return logic .. " " .. column .. " IS NULL"
    elseif 'NOT NULL' == operate then
        return logic .. " " .. column .. " IS NOT NULL"
    elseif 'BETWEEN' == operate then
        return logic .. " (" ..column .. " BETWEEN " .. condition[1] .. " AND " .. condition[2] .. ")"
    elseif 'NOT BETWEEN' == operate then
        return logic .. " (" ..column .. " BETWEEN " .. condition[1] .. " AND " .. condition[2] .. ")"
    else
        return logic .. " " .. column .. " " .. operate .. " " .. condition
    end
end

-- 解析where条件
-- @return string
local function parseWhere(this)
    local where_str = ''
    local where     = this:getOptions('where')

    -- 循环处理条件
    for logic,list in pairs(where) do
        local where_arr = {}

        -- where内层循环
        for _,item in pairs(list) do
            if "string" == type(item) then
                -- exp原始值类型解析
                utils.dump("string")
            elseif "function" == type(item) then
                -- +++++++++++++++++++++++++++++++++++++++
                -- +++++++++++++++++++++++++++++++++++++++
                -- 回调函数闭包类型 解析
                local sub_query = this:new(this:getSelfConfig()) -- 实例化一个新query，使用对象级别的config

                -- 保护模式执行回调函数，执行完毕sub_query对象将包含闭包条件
                local is_ok,_ = pcall(item, sub_query)
                if is_ok then
                    local sub_where = logic .. " (" .. parseWhere(sub_query) .. ")" -- 闭包加入括号包裹
                    table_insert(where_arr, sub_where)
                else
                    utils.exception('callable execute error,please use corrected method and param')
                end
                -- +++++++++++++++++++++++++++++++++++++++
                -- +++++++++++++++++++++++++++++++++++++++
            elseif "table" == type(item) then
                -- 字段、条件、值 类型解析
                table_insert(where_arr, parseWhereItem(logic, item))
            end
        end

        -- 构造多个条件
        if utils.empty(where_str) then
            where_str = utils.implode(" ", where_arr)
            -- 截取掉字符串开头的逻辑符号和空格，逻辑运算符号长度加两个空格，注意下标从1开始
            where_str = string_sub(where_str, string_len(logic) + 2, string_len(where_str))
        else
            where_str = where_str .. utils.implode(" ", where_arr)
        end
    end

    return where_str
end

local function parseJoin()  end
local function parseLimit()  end
local function parseGroup()  end

function _M.debug(self, ...)
    utils.dump(parseWhere(self))
    return self
end

-- 显式执行Db连接
function _M.connect(self, ...)

    -- 与db建立tcp连接，支持断线重连

    return self
end

-- 显式执行Db关闭连接
function _M.close(self, ...)
    return self
end

-- 获取底层connection对象
function _M.getConnection(self, ...)
    return self
end

-- 闭包方法内执行事务
function _M.transaction(self, callable)

    return self
end

-- 开始1个事务
function _M.startTrans(self, callable)

    return self
end

-- commit提交1个事务
function _M.commit(self, ...)

    return self
end

-- rollback回滚1个事务
function _M.rollback(self, ...)

    return self
end

-- 依据action动作生成拟执行的sql语句
-- @param string action 拟执行的动作，枚举值：insert|select|find|update|delete
-- @return string
function _M.buildSQL(self, action)

    return self
end

-- 执行单条数据新增
function _M.insert(self, ...)

    return self
end

-- 执行单条数据新增并返回新增后的id
function _M.insertGetId(self, ...)

    return self
end

-- 执行单条查询
function _M.find(self, ...)

    return self
end

-- 执行多条查询
function _M.select(self, ...)

    return self
end

-- 执行分页查询
-- @param integer page 当前页码，不传或传nil则自动从http变量名中读取，变量名称配置文件配置
-- @param integer page_size 一页多少条数据，不传或传nil则自动从分页配置中读取
-- @param boolean is_complex 是否复杂模式，不传则默认为简单模式 【复杂模式则返回值自动获取总记录数，简单模式则不获取总记录数】
function _M.page(self, page, page_size, is_complex)
    utils.dump(page)
    utils.dump(page_size)
    utils.dump(utils.empty(is_complex))
    return self
end

-- 执行更新操作
function _M.update(self, ...)

    return self
end

-- 执行删除操作
function _M.delete(self, ...)

    return self
end

-- 执行原生sql的查询--select
-- @param string SQL语句
-- @param array  可选的参数绑定，SQL语句中的问号(?)依次使用该数组参数替换
function _M.query(self, ...)

    return self
end

-- 执行原生sql的命令--update、delete、create、alter等
-- @param string SQL语句
-- @param array  可选的参数绑定，SQL语句中的问号(?)依次使用该数组参数替换
function _M.execute(self, ...)

    -- 返回影响行数
    return self
end

-- 可链式调用对象
return _M
