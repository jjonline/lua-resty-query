---
--- Db查询执行器
---

----------------------------------------------------------------
--- 用法如下：
---
--- <引入query类>
--- local query = require "resty.query"
---
--- `实例化`query类产生1个类实例，参数为数组结构的配置
--- local table_query = query:new(config)
--- local table_query = query:name(table)
---
--- 查询单条数据用法：
---     local one_result = table_query:where({where}):find()
--- 查询多条数据用法：
---     local list_result = table_query:where({where}):select()
--- 分页查询数据用法：
---     local page_result = table_query:where({where}):page(offset, page_size):select()
---     local page_result = table_query:where({where}):paginate(page, page_size, is_complex)
--- 更新数据用法：
---     local update_result = table_query:where({where}):data({data}):update() -- 为避免整个表更新，where为空时不执行，且报告异常
---     local update_result = table_query:where({where}):update({data}) -- 为避免整个表更新，where为空时不执行，且报告异常
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
local string_upper = string.upper
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

local selectSQL    = "SELECT#DISTINCT# #FIELD# FROM #TABLE##JOIN##WHERE##GROUP##HAVING##ORDER##LIMIT##LOCK#"
local insertSQL    = "#INSERT# INTO #TABLE# (#FIELD#) VALUES (#DATA#)"
local updateSQL    = "UPDATE #TABLE# SET #SET##JOIN##WHERE##ORDER##LIMIT# #LOCK#"
local deleteSQL    = "DELETE FROM #TABLE##JOIN##WHERE##ORDER##LIMIT# #LOCK#"
local insertAllSQL = "#INSERT# INTO #TABLE# (#FIELD#) #DATA#"

-- 内部方法：解析是否distinct唯一
-- @return string
local function parseDistinct(self)
    local distinct = self:getOptions("distinct")

    if not utils.empty(distinct) then
        return " DISTINCT"
    end

    return ''
end

-- 内部方法：解析字段
-- @return string
local function parseField(self)
    local field = self:getOptions('field')

    -- 如果未调用field方法设置字段，则返回通配
    if utils.empty(field) then
        return "*"
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

-- 内部方法：解析数据表名
-- @return string
local function parseTable(self)
    -- 获取并检测是否设置表
    local table = self:getOptions("table")
    if utils.empty(table) then
        utils.exception('please set table name without prefix first')
    end

    return table
end

-- 构造where内部子句
-- @param string logic 运算符 AND|OR
-- @param array  item  字段|条件|查询值
-- @return string
local function buildWhereItem(logic, item)
    local column    = item[1]
    local operate   = item[2]
    local condition = item[3]

    if "NULL" == operate then
        return logic .. " " .. column .. " IS NULL"
    elseif "NOT NULL" == operate then
        return logic .. " " .. column .. " IS NOT NULL"
    elseif "BETWEEN" == operate then
        return logic .. " (" ..column .. " BETWEEN " .. condition[1] .. " AND " .. condition[2] .. ")"
    elseif "NOT BETWEEN" == operate then
        return logic .. " (" ..column .. " BETWEEN " .. condition[1] .. " AND " .. condition[2] .. ")"
    elseif utils.in_array(operate, {"LIKE", "NOT LIKE"}) then
        return logic .. " " .. column .. " " .. operate .. " " .. condition
    elseif utils.in_array(operate, {"IN", "NOT IN"}) then
        return logic .. " " .. column .. " " .. operate .. " (" .. utils.implode(",", condition) .. ")"
    else
        return logic .. " " .. column .. operate .. condition
    end
end

-- 内部方法：构造where条件
-- @return string
local function buildWhere(this)
    local where_str = ''
    local where     = this:getOptions("where")

    -- 未曾设置任何where条件返回空字符串
    if utils.empty(where) then
        return ""
    end

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
                    local sub_where = logic .. " (" .. buildWhere(sub_query) .. ")" -- 闭包加入括号包裹
                    table_insert(where_arr, sub_where)
                else
                    utils.exception('callable execute error,please use corrected method and param')
                end
                -- +++++++++++++++++++++++++++++++++++++++
                -- +++++++++++++++++++++++++++++++++++++++
            elseif "table" == type(item) then
                -- 字段、条件、值 类型解析
                table_insert(where_arr, buildWhereItem(logic, item))
            end
        end

        -- 构造多个条件
        if utils.empty(where_str) then
            where_str = utils.implode(" ", where_arr)
            -- 截取掉字符串开头的逻辑符号，逻辑运算符号长度加1个空格，注意下标从1开始
            where_str = string_sub(where_str, string_len(logic) + 2, string_len(where_str))
        else
            where_str = where_str .. " " .. utils.implode(" ", where_arr)
        end
    end

    return where_str
end

-- 内部方法：解析where条件
-- @return string
local function parseWhere(self)
    local where = buildWhere(self)

    if utils.empty(where) then
        return ""
    end

    return " WHERE " .. where
end

-- 内部方法：解析data方法设置的数据
-- @return string
local function parseData(self)
    local data = self:getOptions("data")

    -- 循环处理关联数组成索引数组
    if not utils.empty(data) then
        local _data = {}

        for key,val in pairs(data) do
            table_insert(_data, key .. "=" .. val)
        end

        return _data
    end

    return {}
end

-- 解析join关联表
-- @return string
local function parseJoin(self)
    local join = self:getOptions("join")

    -- 没有join语句
    if utils.empty(join) then
        return ''
    end

    local join_str = ''
    for _,item in pairs(join) do
        join_str = join_str .. item[2] .. " JOIN " .. utils.set_back_quote(item[1][1]) .. " AS " .. utils.set_back_quote(item[1][2]) .. " ON " .. item[3]
    end

    return " " .. join_str .. " "
end

-- 内部方法：解析group分组
-- @return string
local function parseGroup(self)
    local group = self:getOptions("group")

    if utils.empty(group) then
        return ''
    end

    return " GROUP BY " .. group
end

-- 内部方法：解析group分组搭配的having条件
-- @return string
local function parseHaving(self)
    local having = self:getOptions("having")

    if utils.empty(having) then
        return ''
    end

    return " HAVING " .. having
end

-- 内部方法：解析order排序条件
-- @return string
local function parseOrder(self)
    local order = self:getOptions('order')

    if utils.empty(order) then
        return ''
    end

    local order_str = ' ORDER BY '
    for _,item in pairs(order) do
        order_str = order_str .. item[1] .. " " ..item[2] .. ","
    end

    return utils.rtrim(order_str, ",")
end

-- 内部方法：解析limit限定条件
-- @return string
local function parseLimit(self)
    local limit = self:getOptions("limit")

    if utils.empty(limit) then
        return ''
    end

    return " LIMIT " .. limit .. " "
end

-- 内部方法：解析加锁
-- @return string
local function parseLock(self)
    local lock = self:getOptions("lock")

    if utils.empty(lock) then
        return ''
    end

    return " " .. lock .. " "
end

local _M = {}
local mt = { __index = _M }
local LAST_SQL = 'no exist last SQL' -- 全局记录最后执行的sql

-- 初始化方法，类似构造函数
-- @param array config 初始化传入配置数组参数，数组结构参照上方 options.config
function _M.new(_, config)
    local build    = builder:new(config)
    local super_mt = getmetatable(build)

    -- 当方法在子类中查询不到时，可以再去父类中去查找。
    setmetatable(_M, super_mt)

    -- 这样设置后，可以通过self.super.method(self, ...) 调用父类的已被覆盖的方法。
    build.super = setmetatable({}, super_mt)

    -- 底层db连接管理器
    build.connection = connection:new(config)

    return setmetatable(build, mt)
end

-- 显式执行Db连接
function _M.connect(self, config)
    -- 判断是否已连接
    if utils.empty(self.connection.state) then
        self.connection:connect(config)
    end

    return self
end

-- 内部debug调试方法
function _M.debug(self, ...)
    utils.dump(parseDistinct(self))
    return self
end

-- name方法隐含实例化过程，可直接 query:name(table_name)完成新query对象的生产
-- @param string table 不带前缀的数据表名称
function _M.name(self, table)
    return self:new():table(table)
end

-- 对象本身克隆，内部options等信息保留
function _M.clone(self)
    return utils.deep_copy(self)
end

-- 显式执行Db关闭连接
function _M.close(self, ...)
    return self
end

-- 获取底层connection对象
function _M.getConnection(self)
    return self.connection
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

-- 设置最近1次执行过的sql，全局模式
local function set_last_sql(sql)
    LAST_SQL = sql
end

-- 获取最近1次执行过的sql，全局模式
local function get_last_sql()
    return LAST_SQL
end

-- 构建select的sql语句
-- @param string
local function buildSelect(self)
    local sql = utils.str_replace(
            {
                "#TABLE#",
                "#DISTINCT#",
                "#FIELD#",
                "#JOIN#",
                "#WHERE#",
                "#GROUP#",
                "#HAVING#",
                "#ORDER#",
                "#LIMIT#",
                "#LOCK#"
            },
            {
                parseTable(self),
                parseDistinct(self),
                parseField(self),
                parseJoin(self),
                parseWhere(self),
                parseGroup(self),
                parseHaving(self),
                parseOrder(self),
                parseLimit(self),
                parseLock(self),
            },
            selectSQL
    )

    return utils.rtrim(sql)
end

-- 构建update的sql语句
-- @param string
local function buildUpdate(self)
    -- 未设置where条件，不允许执行
    local where = self:getOptions("where")
    if utils.empty(where.OR) and utils.empty(where.AND) then
        utils.exception("execute update SQL must be set where condition")
        return false
    end

    local sql = utils.str_replace(
            {
                "#TABLE#",
                "#SET#",
                "#JOIN#",
                "#WHERE#",
                "#ORDER#",
                "#LIMIT#",
                "#LOCK#"
            },
            {
                parseTable(self),
                utils.implode(" , ", parseData(self)),
                parseJoin(self),
                parseWhere(self),
                parseOrder(self),
                parseLimit(self),
                parseLock(self),
            },
            updateSQL
    )

    return utils.rtrim(sql)
end

-- 构建insert的sql语句
-- @param string
local function buildInsert(self, is_replace)
    -- 获取要新增的数据
    local data = self:getOptions("data")

    -- 没有数据集对象
    if utils.empty(data) then
        utils.exception("please set insert data first")
    end

    -- 依据replace条件调度新增语句的方式
    if is_replace then
        is_replace = "REPLACE"
    else
        is_replace = "INSERT"
    end

    -- 处理键值对
    local fields = utils.array_keys(data)
    local values = utils.array_values(data)

    local sql = utils.str_replace(
            {
                "#INSERT#",
                "#TABLE#",
                "#FIELD#",
                "#DATA#"
            },
            {
                is_replace,
                parseTable(self),
                utils.implode(" , ", fields),
                utils.implode(" , ", values)
            },
            -- #INSERT# INTO #TABLE# (#FIELD#) VALUES (#DATA#)
            insertSQL
    )

    -- 记录最近一次执行过的sql
    set_last_sql(sql)

    return utils.rtrim(sql)
end

-- 构建delete的sql语句
-- @param string
local function buildDelete(self)
    -- 未设置where条件，不允许执行
    local where = self:getOptions("where")
    if utils.empty(where.OR) and utils.empty(where.AND) then
        utils.exception("execute delete SQL must be set where condition")
        return false
    end

    local sql = utils.str_replace(
            {
                "#TABLE#",
                "#JOIN#",
                "#WHERE#",
                "#ORDER#",
                "#LIMIT#",
                "#LOCK#"
            },
            {
                parseTable(self),
                parseJoin(self),
                parseWhere(self),
                parseOrder(self),
                parseLimit(self),
                parseLock(self),
            },
            deleteSQL
    )

    -- 记录最近一次执行过的sql
    set_last_sql(sql)

    return utils.rtrim(sql)
end

-- 依据action动作生成拟执行的sql语句
-- @param string action 拟执行的动作，枚举值：insert|select|find|update|delete
-- @return string
function _M.buildSql(self, action)
    local _action = string_upper(action)
    local sql

    if "SELECT" == _action then
        sql = buildSelect(self)
    elseif "FIND" == _action then
        self:limit(1)
        sql = buildSelect(self)
        self:removeOptions("limit")
    elseif "UPDATE" == _action then
        sql = buildUpdate(self)
    elseif "INSERT" == _action then
        sql = buildInsert(self)
    elseif "DELETE" == _action then
        sql = buildDelete(self)
    end

    return sql
end

-- 获取最近执行过的最后1次的sql
function _M.getLastSql(self)
    return get_last_sql()
end

-- 执行单条数据新增
-- @param array   data 可以通过insert第一个参数设置要信息的key-value值对象，会覆盖由data设置的值
-- @param boolean is_replace 是否使用REPLACE语句执行新增，默认否
-- @return number|nil 方法添加数据成功返回添加成功的条数，通常情况返回1，失败或异常返回nil
function _M.insert(self, data, is_replace)
    -- insert第一个参数传入要insert的键值对，执行设置data
    if "table" == type(data) then
        self:data(data)
    end

    -- build insert sql
    local sql = buildInsert(self, is_replace)

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- remove all setOptions
    self:removeOptions();

    -- self.connection:destruct()

    -- record last SQL
    set_last_sql(sql)

    -- fetch MySQL server execute result info
    return self.connection:affectedRows()
end

-- 执行单条数据新增并返回新增后的id
-- @param array   data 可以通过insert第一个参数设置要信息的key-value值对象，会覆盖由data设置的值
-- @param boolean is_replace 是否使用REPLACE语句执行新增，默认否
-- @return number|string|boolean 执行成功返回新增的主键id，执行失败返回false
function _M.insertGetId(self, data, is_replace)
    -- insert第一个参数传入要insert的键值对，执行设置data
    if "table" == type(data) then
        self:data(data)
    end

    -- build insert sql
    local sql = buildInsert(self, is_replace)

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- remove all setOptions
    self:removeOptions();

    -- self.connection:destruct()

    -- record last SQL
    set_last_sql(sql)

    -- fetch MySQL server execute result info and return last insert id
    return self.connection:lastInsertId()
end

-- 执行单条查询，find不支持通过参数设置查询条件，仅支持通过where方法设置
-- @return array|nil 查找到返回一维数组，查找不到返回nil
function _M.find(self)
    -- 查找1条，强制覆盖limit条件为1条
    self:setOptions("limit", 1);

    -- 生成查找1条的sql
    local sql = buildSelect(self)

    -- 清理方法体强制设置的limit条件
    self:removeOptions("limit")

    -- send sql to MySQL server and query
    self.connection:query(sql)

    -- fetch MySQL server return result
    local result = self.connection:fetch()

    -- remove all setOptions
    self:removeOptions();

    -- record last SQL
    set_last_sql(sql)

    -- self.connection:destruct()

    -- 不为空返回第一个值，为空则返回nil
    return result[1]
end

-- 执行多条查询，select支持通过参数设置查询条件，仅支持通过where方法设置
-- @return array|nil 查找到返回二维数组，查找不到返回nil
function _M.select(self)
    -- build select SQL
    local sql = buildSelect(self)

    -- send sql to MySQL server and execute
    self.connection:query(sql)

    -- remove all setOptions
    self:removeOptions();

    -- self.connection:destruct()

    -- record last SQL
    set_last_sql(sql)

    -- fetch MySQL server return result
    return self.connection:fetch()
end

-- 执行分页查询
-- @param integer page 当前页码，不传或传nil则自动从http变量名中读取，变量名称配置文件配置
-- @param integer page_size 一页多少条数据，不传或传nil则自动从分页配置中读取
-- @param boolean is_complex 是否复杂模式，不传则默认为简单模式 【复杂模式则返回值自动获取总记录数，简单模式则不获取总记录数】
-- @return array {list = {}, page = 1, page_size = 10, total = 10}
function _M.paginate(self, page, page_size, is_complex)
    -- set page param
    if not utils.empty(page) then
        self:page(page, page_size)
    end

    -- checkout is set page options,use the default first page and use setting page_size
    if utils.empty(self:getOptions("page")) then
        self:page(1, page_size)
    end

    local page_set = self:getOptions("page")

    -- build select SQL
    local sql = buildSelect(self)

    -- result structure
    local result = {
        list       = {}, -- 分页数据列表
        page       = page_set[1], -- 当前页码
        page_size  = page_set[2], -- 当前设置项目中的1页多少条
        total      = false, -- 依据is_complex参数是否返回分页的总数
    }

    -- complex model，execute the count
    if not utils.empty(is_complex) then
        -- todo
    end

    -- send single or multi sql to MySQL server and execute
    self.connection:query(sql)

    -- fetch now page list result
    for key,val in self.connection:fetchMany() do
        if key == 1 then
            result.list = val
        end
        if key == 2 then
            result.total = val
        end
    end

    -- record last SQL
    set_last_sql(sql)

    -- self.connection:destruct()

    return result
end

function _M.count(self, field)
    local count_field = field or "*"

    -- record last SQL
    set_last_sql(sql)
end

-- 执行更新操作
-- @param array   data 设置需要更新数据的键值对
-- @return number|nil 执行更新成功返回update影响的行数，执行失败返回nil
function _M.update(self, data)
    -- 如果有设置更新数据的键值对，则设置键值对
    if "table" == type(data) then
        self:data(data)
    end

    -- build update SQL
    local sql = buildUpdate(self)

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- remove all setOptions
    self:removeOptions();

    -- record last SQL
    set_last_sql(sql)

    -- self.connection:destruct()

    return self.connection:affectedRows()
end

-- 执行删除操作，delete不支持通过参数设置删除条件，仅支持通过where方法设置
-- @return number|nil 执行更新成功返回删除影响的行数，执行失败返回nil
function _M.delete(self)
    -- build delete SQL
    local sql = buildDelete(self)

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- remove all setOptions
    self:removeOptions();

    -- record last SQL
    set_last_sql(sql)

    -- self.connection:destruct()

    return self.connection:affectedRows()
end

-- 执行原生sql的查询
-- @param string sql   SQL语句
-- @param array  binds 可选的参数绑定，SQL语句中的问号(?)依次使用该数组参数替换
-- @return array
function _M.query(self, sql, binds)
    -- check
    if utils.empty(sql) then
        utils.exception("please set query SQL statement use first param")
        return nil
    end

    -- bind
    if not utils.empty(binds) and "table" == type(binds) then
        sql = utils.db_bind_value(sql, binds)
    end

    -- send single or multi sql to MySQL server and execute
    self.connection:query(sql)

    -- fetch more result use iterator
    local result = {}
    for key,val in self.connection:fetchMany() do
        result[key] = val
    end

    -- record last SQL
    set_last_sql(sql)

    -- self.connection:destruct()

    -- if just one statement return level one
    if 1 == #result then
        return result[1]
    end

    return result
end

-- 执行原生sql的命令--update、delete、create、alter等
-- @param string sql   SQL语句
-- @param array  binds 可选的参数绑定，SQL语句中的问号(?)依次使用该数组参数替换
-- @return array
function _M.execute(self, sql, binds)
    -- check
    if utils.empty(sql) then
        utils.exception("please set execute SQL statement use first param")
        return nil
    end

    -- bind
    if not utils.empty(binds) and "table" == type(binds) then
        sql = utils.db_bind_value(sql, binds)
    end

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- fetch more result use iterator
    local result = {}
    for key,val in self.connection:fetchMany() do
        result[key] = val
    end

    -- record last SQL
    set_last_sql(sql)

    -- self.connection:destruct()

    -- if just one statement return level one
    if 1 == #result then
        return result[1]
    end

    return result
end

-- 可链式调用对象
return _M
