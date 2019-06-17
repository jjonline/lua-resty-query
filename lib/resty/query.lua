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
local tonumber     = tonumber
local table_insert = table.insert
local string_sub   = string.sub
local string_len   = string.len
local setmetatable = setmetatable
local getmetatable = getmetatable
local utils        = require "resty.com.utils"
local connection   = require "resty.com.connection"
local builder      = require "resty.com.builder"

local _M           = { version = "0.0.1" }
local mt           = { __index = _M }
local LAST_SQL     = 'no exist last SQL' -- 全局记录最后执行的sql
local FIELDS       = {} -- 全局记录表本身的字段信息 { table_name1 = {}, table_name2 = {} }

-- 设置最近1次执行过的sql，全局模式
local function set_last_sql(sql)
    LAST_SQL = sql
end

-- 获取最近1次执行过的sql，全局模式
local function get_last_sql()
    return LAST_SQL
end

local selectSQL    = "SELECT#DISTINCT# #FIELD# FROM #TABLE##JOIN##WHERE##GROUP##HAVING##ORDER##LIMIT##LOCK#"
local insertSQL    = "#INSERT# INTO #TABLE# (#FIELD#) VALUES (#DATA#)"
local updateSQL    = "UPDATE #TABLE# SET #SET##JOIN##WHERE##ORDER##LIMIT# #LOCK#"
local deleteSQL    = "DELETE FROM #TABLE##JOIN##WHERE##ORDER##LIMIT# #LOCK#"
local insertAllSQL = "#INSERT# INTO #TABLE# (#FIELD#) VALUES #DATA#"

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
        utils.exception("[table]please set table name without prefix at first")
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
        return logic .. " (" ..column .. " NOT BETWEEN " .. condition[1] .. " AND " .. condition[2] .. ")"
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
                -- exp原始值类型解析，字面量原始值类型
                -- 可使用 utils.db_bind_value 执行值绑定，而不是直接拼接，以防止注入风险
                table_insert(where_arr, logic .. " " .. item)
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
                    utils.exception("[where]callable execute error, please use corrected method and param")
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
-- @param array data_set  可额外传入仅处理该数据
-- @return array {field = 'value', field2 = value} or {{},{}}
local function parseData(self, data_set)
    local data = data_set or self:getOptions("data")

    -- 未设置任何数据，返回空数组，由调用方处理
    if utils.empty(data) then
        return {}
    end

    -- 循环处理关联数组成索引数组
    local _data = {}

    -- deal
    for key,val in pairs(data) do
        -- 键名称为字符串，依据值类型处理
        if "string" == type(key) then
            -- 处理字段
            key = utils.set_back_quote(utils.strip_back_quote(key))

            -- 处理值
            if ngx.null == val then
                -- null
                _data[key] = "NULL" -- 直接NULL字符串本身，无需携带引号
            elseif "table" == type(val) then
                -- 数组值，实现一些特定需求，{"INC", 1}、{"DEC", 1}
                if 2 == #val then
                    if val[1] == "INC" then
                        -- 自增字段需求
                        _data[key] = key .. " + " .. tonumber(val[2] or 1)
                    elseif val[1] == "DEC" then
                        -- 自减字段需求
                        _data[key] = key .. " - " .. tonumber(val[2] or 1)
                    else
                        -- 需要扩展在此添加
                    end
                else
                    utils.exception("[data]not support operator in data " .. val[1])
                end
            else
                -- 值类型，处理值
                _data[key] = utils.quote_value(val)
            end
        end

        -- 键名为数字，设置批量数据情况直接返回
        if "number" == type(key) then
            return data
        end
    end

    return _data
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

-- 内部方法，获取数据表字段新
-- @return array
local function autoGetFields(self)
    -- get table
    local table = self:getOptions("table")

    -- check
    if utils.empty(table) then
        utils.exception("[getFields]please set table name at first when get all this table fields info")
    end

    -- 已处理过，直接使用
    if not utils.empty(FIELDS[table]) then
        return FIELDS[table]
    end

    -- execute sql get fields info
    local sql = "SHOW COLUMNS FROM " .. table

    -- send sql to MySQL server and execute
    self.connection:query(sql)

    -- self.connection:destruct()

    -- fetch MySQL server return result
    local result = self.connection:fetch()

    -- deal structure
    local fields = {}
    local info   = {}
    for _, val in pairs(result) do
        local _name  = val.Field

        -- 设置主键
        if val.Key == "PRI" then
            fields.primary = _name
        end

        -- 设置每个字段详情
        info[_name] = {
            primary        = "PRI" == val.Key, -- boolean 是否为主键
            type           = val.Type,
            default        = val.Default,
            not_null       = "NO" == val.Null, -- boolean 是否能为null
            auto_increment = "auto_increment" == val.Extra, -- boolean 是否自增
        }
    end

    --[[
    -- 存储结构
    {
        primary = "id", -- 该表的主键
        fields  = {
            id = {
                type = "int(11)", -- 字段类型
                not_null = true, -- 是否允许为null
                default = "", -- 默认值
                primary = false, -- 是否主键
                auto_increment = false -- 是否自增键
            } -- 该表每个字段的信息
        },
    }
    -]]
    fields.fields = info

    -- set to local variable
    FIELDS[table] = fields

    -- record last SQL
    set_last_sql(sql)

    return fields
end

-- 实例化1个新的底层connection对象
-- @param array config 配置数组
local function newConnection(self)
    return connection:new(self:getSelfConfig())
end
_M.newConnection = newConnection

-- 获取底层connection对象
function _M.getConnection(self)
    return self.connection
end

-- 设置底层connection对象，某些场景下需要1个新链接处理的情况
-- @param connection _connection 新的connection对象
function _M.setConnection(self, _connection)
    self.connection = _connection
    return self
end

-- 初始化方法，类似构造函数
-- 启用ngx.ctx特性，保证同一个request周期内被执行的代码一直使用同一个底层mysql连接
-- 若需在同1个request生命周期内启用多个底层mysql连接，使用对象实例的newConnection方法生成新连接，再通过setConnection设置进去
-- @param array config 初始化传入配置数组参数，数组结构参照上方 options.config
function _M.new(_, config)
    local build    = builder:new(config)
    local super_mt = getmetatable(build)

    -- 当方法在子类中查询不到时，可以再去父类中去查找。
    setmetatable(_M, super_mt)

    -- 使用request级别生命周期的ngx.ctx作为connection句柄
    -- 保证1次请求内不显式新生成1个connection的情况下
    -- 所有sql执行都是通过同一个连接执行，这里ngx.ctx倘若使用Up-value形式会导致问题
    if utils.empty(ngx.ctx.connection) then
        ngx.ctx.connection = newConnection(build)
    end
    build.connection = ngx.ctx.connection

    return setmetatable(build, mt)
end

-- 构造1个新的query对象并且底层重新新建mysql连接
function _M.newQueryWithNewConnection(self)
    local query = self:new()
    query.connection = newConnection(query)

    return query
end

-- 显式执行Db连接
function _M.connect(self, config)
    -- 连接配置参数，如果未传则读取对象携带的配置参数
    config = config or self:getSelfConfig()
    -- 判断是否已连接
    if utils.empty(self.connection.state) then
        self.connection:connect()
    end

    return self
end

-- name方法隐含实例化过程，可直接 query:name(table_name)完成新query对象的生成
-- @param string table 不带前缀的数据表名称
function _M.name(self, table)
    return self:new():table(table)
end

-- 克隆方法，即将当前对象各属性保留生成1个新对象，内部options等信息保留
-- 与new方法、name方法的区别在于，保不保留内部options选项
function _M.clone(self)
    local new_query = self:new()

    -- obtain origin options
    new_query:setOptions(self:getOptions())

    return new_query
end

-- 重置query对象的内部选项值
-- removeOptions方法的别名，避免removeOptions引起的歧义误解
function _M.reset(self)
    return self:removeOptions()
end

-- 显式执行Db关闭连接
function _M.close(self)
    self.connection:destruct()
end

-- 闭包方法内安全执行事务，方法体内部自动构造新底层连接执行事务
-- @param function callable 被执行的回调函数，回调函数的参数为1个query对象
-- @return boolean, callable result 返回两个值，第一个值布尔值标记事务执行成功与否，第二值为回调函数执行后的返回值
function _M.transaction(self, callable)
    -- create a new query with a new connection
    local query = self:newQueryWithNewConnection()

    -- beginTransaction
    query.connection:startTrans()

    -- protected pcall run callable
    local ok,result = pcall(callable, query)

    -- check if there has an error
    if not ok then
        -- error occur and rollback
        query.connection:rollback()
    else
        -- no error occur and commit
        query.connection:commit()
    end

    -- destroy this query and release db connection to co-socket pool
    query:destruct()
    query = nil

    return not (not ok), result
end

-- 开始1个事务
-- @return boolean
function _M.startTrans(self)
    -- 底层connection发送事务开始标记
    return self.connection:startTrans()
end

-- commit提交1个事务
-- @return boolean
function _M.commit(self)
    -- 底层connection发送事务提交标记
    return self.connection:commit()
end

-- rollback回滚1个事务
-- @return boolean
function _M.rollback(self)
    -- 底层connection发送事务回滚标记
    return self.connection:rollback()
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
        utils.exception("[delete]execute update SQL must be set where condition")
    end

    -- deal update data
    local data     = parseData(self)
    local data_set = {}
    for key,val in pairs(data) do
        table_insert(data_set, key .. " = " .. val)
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
                utils.implode(" , ", data_set),
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
    local data = parseData(self)

    -- 没有数据集对象
    if utils.empty(data) then
        utils.exception("[insert]please use data method or insert method set insert data")
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
            insertSQL
    )

    return utils.rtrim(sql)
end

-- 构造批量insert语句
-- @param boolean is_replace mysql特有REPLACE方式插入数据
-- @return string
local function buildInsertAll(self, is_replace)
    -- get origin multi data
    local data = parseData(self)

    -- check origin multi data
    if utils.empty(data) then
        utils.exception("[insertAll]please use insertAll method first param set insert data list")
    end

    -- 依据replace条件调度新增语句的方式
    if is_replace then
        is_replace = "REPLACE"
    else
        is_replace = "INSERT"
    end

    -- deal multi data
    local fields = {}
    local values = {}
    for index,val in pairs(data) do
        if "number" ~= type(index) or "table" ~= type(val) then
            utils.exception("[insertAll]multi insert data structure error")
        end

        -- parse two level data
        local item  = parseData(self, val) -- one item data
        local value = utils.array_values(item) -- one item value

        -- set multi insert fields
        if utils.empty(fields) then
            fields = utils.array_keys(item)
        else
            -- 检查字段长度和值长度是否一致
            if utils.array_count(item) ~= #value then
                utils.exception("[insertAll]data fields count not equal values count at " .. index)
            end
        end

        -- set multi value item
        table_insert(values, "( " .. utils.implode(",", value) .. " )")
    end

    local sql = utils.str_replace(
            {
                "#INSERT#",
                "#TABLE#",
                "#FIELD#",
                "#DATA#",
            },
            {
                is_replace,
                parseTable(self),
                utils.implode(" , ", fields),
                utils.implode(" , ", values)
            },
            insertAllSQL
    )

    return utils.rtrim(sql)
end

-- 构建delete的sql语句
-- @param string
local function buildDelete(self)
    -- 未设置where条件，不允许执行
    local where = self:getOptions("where")
    if utils.empty(where.OR) and utils.empty(where.AND) then
        utils.exception("[delete]execute delete SQL must be set where condition")
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

    return utils.rtrim(sql)
end

-- 构建count查询的sql语句
-- @param field string count查询的字段名称
-- @param string
local function buildCount(self, field)
    -- group分组查询情况进行子查询处理
    if not utils.empty(self:getOptions("group")) then
        local sub_query = self:clone() -- 克隆1份对象方法
        local sub_sql   = buildSelect(sub_query) -- 构造group子查询sql

        -- 设置子查询成为为父查询的table表名称和表别名
        self:setOptions("table", "(" .. sub_sql .. ") _resty_query_group_count_")

        -- reset group and field
        field = ""

        -- clear self do no used options
        self:removeOptions("group")
        self:removeOptions("where")
        self:removeOptions("order")
        self:removeOptions("limit")
    end

    -- parse count field
    local count_field
    if not utils.empty(field) then
        count_field = utils.set_back_quote(utils.strip_back_quote(field))
        count_field = "count(" .. count_field .. ") AS `resty_query_count`"
    else
        count_field = "count(*) AS `resty_query_count`"
    end

    -- clear field that may exist
    self:removeOptions("field")

    -- set limit param 1
    self:limit(1)

    -- set count field
    self:setOptions("field", {count_field})

    return buildSelect(self)
end

-- 生成拟执行的sql语句而不是执行
-- @param boolean is_fetch 是否不执行sql，而是返回拟执行的sql，默认true
function _M.fetchSql(self, is_fetch)
    self:setOptions("fetch_sql", is_fetch or true)
    return self
end

-- 获取最近执行过的最后1次的sql
function _M.getLastSql(_)
    return get_last_sql()
end

-- 获取数据表的字段信息数组
-- @return array 以字段名称作为下标的关联数组
function _M.getFields(self)
    --[[
    -- 返回值结构
    {
        id = {
            type = "int(11)", -- 字段类型
            not_null = true, -- 是否允许为null
            default = "", -- 默认值
            primary = false, -- 是否主键
            auto_increment = false -- 是否自增键
        } -- 该表每个字段的信息
    }
    -]]
    return autoGetFields(self).fields
end

-- 获取数据表的主键字段
-- @return string 主键字段名称，若未设置主键字段则返回空字符串
function _M.getPrimaryField(self)
    return autoGetFields(self).primary or ''
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

    -- not execute sql, rather than return string of SQL
    if self:getOptions("fetch_sql") then
        return sql
    end

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- remove all setOptions
    self:removeOptions()

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

    -- not execute sql, rather than return string of SQL
    if self:getOptions("fetch_sql") then
        return sql
    end

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- remove all setOptions
    self:removeOptions()

    -- self.connection:destruct()

    -- record last SQL
    set_last_sql(sql)

    -- fetch MySQL server execute result info and return last insert id
    return self.connection:lastInsertId()
end

-- 构造批量insert语句
-- @param array data 批量插入语句的数组，二维数组
-- @param boolean is_replace mysql特有REPLACE方式插入数据
-- @return number 返回插入的总条数
function _M.insertAll(self, data, is_replace)
    -- set multi data
    if not utils.empty(data) then
        sel:data(data)
    end

    -- build insert sql
    local sql = buildInsertAll(self, is_replace)

    -- not execute sql, rather than return string of SQL
    if self:getOptions("fetch_sql") then
        return sql
    end

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- remove all setOptions
    self:removeOptions()

    -- self.connection:destruct()

    -- record last SQL
    set_last_sql(sql)

    -- fetch MySQL server execute result info
    return self.connection:affectedRows()
end

-- 执行单条查询，find唯一的可选参数仅支持主键查询，底层自动获取主键，传入主键值即可
-- @return string|number pri_val 可选的按主键快捷查询的主键单个值
-- @return array|nil 查找到返回一维数组，查找不到返回nil
function _M.find(self, pri_val)
    -- 查找1条，强制覆盖limit条件为1条
    self:setOptions("limit", 1);

    -- 如果有传值
    if not utils.empty(pri_val) then
        if "table" == type(pri_val) then
            utils.exception("[find]select one record use primary key auto, param need string or number")
        end

        -- 设置主键查询
        local pri_key = self:getPrimaryField()
        if utils.empty(pri_key) then
            utils.exception("[find]do not have primary key field in " .. self:getOptions("table"))
        end

        -- add primary key where
        self:where(pri_key, "=", pri_val)
    end

    -- 生成查找1条的sql
    local sql = buildSelect(self)

    -- not execute sql, rather than return string of SQL
    if self:getOptions("fetch_sql") then
        return sql
    end

    -- 清理方法体强制设置的limit条件
    self:removeOptions("limit")

    -- send sql to MySQL server and query
    self.connection:query(sql)

    -- fetch MySQL server return result
    local result = self.connection:fetch()

    -- remove all setOptions
    self:removeOptions()

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

    -- not execute sql, rather than return string of SQL
    if self:getOptions("fetch_sql") then
        return sql
    end

    -- send sql to MySQL server and execute
    self.connection:query(sql)

    -- remove all setOptions
    self:removeOptions()

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

    -- get page options variable
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
        -- 构造总数查询的sql，最终执行时一次性发送2条sql
        sql = sql .. ";" .. buildCount(self)
    end

    -- not execute sql, rather than return string of SQL
    if self:getOptions("fetch_sql") then
        return sql
    end

    -- send single or multi sql to MySQL server and execute
    self.connection:query(sql)

    -- fetch now page list result
    for key,val in self.connection:fetchMany() do
        if 1 == key then
            result.list = val
        end
        if 2 == key then
            result.total = tonumber(val[1].resty_query_count or 0) -- 如果有查询总记录数，取出总记录数
        end
    end

    -- remove all setOptions
    self:removeOptions()

    -- record last SQL
    set_last_sql(sql)

    -- self.connection:destruct()

    return result
end

-- count查询总数
-- @param string field 需要计数的字段，可选参数，留空则count总行数
-- @return number 返回大等于0的整数
function _M.count(self, field)
    -- build count select sql, support group sql statement
    local sql = buildCount(self, field)

    -- not execute sql, rather than return string of SQL
    if self:getOptions("fetch_sql") then
        return sql
    end

    -- send single or multi sql to MySQL server and execute
    self.connection:query(sql)

    -- fetch one result
    local result = self.connection:fetch()

    -- remove all setOptions
    self:removeOptions()

    -- record last SQL
    set_last_sql(sql)

    -- convert to number
    return tonumber(result[1]["resty_query_count"] or 0)
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

    -- not execute sql, rather than return string of SQL
    if self:getOptions("fetch_sql") then
        return sql
    end

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- remove all setOptions
    self:removeOptions()

    -- record last SQL
    set_last_sql(sql)

    -- self.connection:destruct()

    return self.connection:affectedRows()
end

-- 设置某个字段的值，即仅更新指定条件下的某个字段的值
-- @param string|array field 拟更新的字段，或则拟更新的键值对关联数组
-- @param number step  需要更新的值
-- @return number|nil  执行更新成功返回影响的行数，执行失败返回nil
function _M.setField(self, field, val)
    -- clear may exist data
    self:removeOptions("data")

    -- set data
    if "table" == type(field) then
        self:data(field)
    else
        self:data(field, val)
    end

    return self:update()
end

-- 按步幅增加某个字段值
-- @param string|array field 需要自增的字段，或多个递增的字段作为键自增步幅为值的数组
-- @param number step  需要自增的步幅，默认自增1
-- @return number|nil  执行更新成功返回影响的行数，执行失败返回nil
function _M.increment(self, field, step)
    -- 步幅默认1
    step = step or 1

    -- clear may exist data
    self:removeOptions("data")

    -- set data
    if "table" == type(field) then
        for column,bump in pairs(field) do
            if "string" ~= type(column) or "number" ~= type(bump) then
                utils.exception("[increment]increment multi field first param need associative array")
            end
            bump = bump or 1
            self:data(column, {"INC", bump})
        end
    else
        self:data(field, {"INC", step})
    end

    return self.update(self)
end

-- 按步幅减少某个字段值
-- @param string|array field 需要自减的字段，或多个递减的字段作为键自减步幅为值的数组
-- @param number step  需要自减的步幅，默认自增1
-- @return number|nil  执行更新成功返回影响的行数，执行失败返回nil
function _M.decrement(self, field, step)
    -- 步幅默认1
    step = step or 1

    -- clear may exist data
    self:removeOptions("data")

    -- set data
    if "table" == type(field) then
        for column,bump in pairs(field) do
            if "string" ~= type(column) or "number" ~= type(bump) then
                utils.exception("[increment]increment multi field first param need associative array")
            end
            bump = bump or 1
            self:data(column, {"DEC", bump})
        end
    else
        self:data(field, {"DEC", step})
    end

    return self.update(self)
end

-- 执行删除操作，delete不支持通过参数设置删除条件，仅支持通过where方法设置
-- @return number|nil 执行更新成功返回删除影响的行数，执行失败返回nil
function _M.delete(self)
    -- build delete SQL
    local sql = buildDelete(self)

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- remove all setOptions
    self:removeOptions()

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
        utils.exception("[query]please set execute SQL statement use first param")
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

    -- remove all setOptions
    self:removeOptions()

    -- record last SQL
    set_last_sql(sql)

    -- self.connection:destruct()

    -- if just one statement return level one
    if 1 == #result then
        return result[1]
    end

    return result
end

-- 执行原生sql的命令--insert、update、delete、create、alter等
-- @param string sql   SQL语句
-- @param array  binds 可选的参数绑定，SQL语句中的问号(?)依次使用该数组参数替换
-- @return number 返回执行的1条或多条sql总的影响的行数
function _M.execute(self, sql, binds)
    -- check
    if utils.empty(sql) then
        utils.exception("[execute]please set execute SQL statement use first param")
        return nil
    end

    -- bind
    if not utils.empty(binds) and "table" == type(binds) then
        sql = utils.db_bind_value(sql, binds)
    end

    -- send sql to MySQL server and execute
    self.connection:execute(sql)

    -- fetch more result use iterator
    local affected_rows = 0
    for _,val in self.connection:fetchMany() do
        affected_rows = affected_rows + (val.affected_rows or 0)
    end

    -- remove all setOptions
    self:removeOptions()

    -- record last SQL
    set_last_sql(sql)

    -- self.connection:destruct()

    -- return all sql affected_rows count
    return affected_rows
end

-- 析构，query类最后调用的方法
function _M.destruct(self)
    -- 析构将连接放入连接池，实现关闭的功能
    self.connection:destruct()
end

-- 可链式调用对象
return _M
