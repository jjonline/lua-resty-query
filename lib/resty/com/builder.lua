---
--- Db底层查询构造器
---
local utils        = require "resty.com.utils"
local field        = require "resty.com.field"
local where_class  = require "resty.com.where"
local type         = type
local tonumber     = tonumber
local pairs        = pairs
local setmetatable = setmetatable
local table_insert = table.insert
local string_lower = string.lower

local _M = {}
local mt = { __index = _M }

-- 构造器内部各参数存储容器，内部结构如下:
--[[
    options = {}

    -- 查询字段名称
    options.field = {
        'table.column1',
        'table.column2 as column3'
    }

    -- 表别名
    options.alias = {
        {full_table_name1, 'alias_name1'},
        {full_table_name2, 'alias_name2'}
    }

    -- 设置好的表完整名称，可带别名
    options.table = 'full_table_name[ as alias_name]'
    -- 或者 options.table = 'full_table_name as alias_name'

    -- join查询内部结构
    options.join = {
        {join_full_table_name, 'join_alias_name'},
        'LEFT|RIGHT|INNER',
        'condition'
    }

    -- where条件内部结构
    options.where = {
        AND = {
            {
                '字段名1',
                '操作符1',
                '操作值1'
            },
            {
                'whereCallBack1' -- 只有1个参数形式，回调函数执行生成where片段
            }
        },
        OR  = {
            {
                '字段名2',
                '操作符2',
                '操作值2'
            },
            {
                'whereCallBack2' -- 只有1个参数形式，回调函数执行生成where片段
            }
        },
    }

    -- 排序字段内部结构
    options.order = {
        {'sorted_column1', 'ASC'},
        {'sorted_column2', 'DESC'}
    }

    -- limit子句内部结构
    options.limit = '0,50';

    -- page方法设置的参数
    options.page  = {0,50};

    -- data方法设置的key/value键值对值
    options.data  = {key = value, key1 = value1};

    -- group子句内部结构的字段名
    options.group = 'column_name';
    -- 或 多个字段：options.group = 'column_name,column_name1';

    -- 设置group的having条件
    options.having = ''

    -- 是否distinct唯一
    options.distinct = false;
]]--

-- 内部option默认结构和默认值
local options = {
    table     = '',
    field     = {},
    where     = { AND = {}, OR  = {} },
    join      = {},
    order     = {},
    limit     = '',
    data      = {},
    page      = {},
    group     = '',
    having    = '',
    distinct  = false,
    lock      = ''
}

-- 数据库配置，多个实例可共用
local config  = {
    host      = "127.0.0.1",
    port      = 3306,
    socket    = "",
    database  = "",
    username  = "",
    password  = "",
    charset   = 'utf8mb4',
    collation = 'utf8mb4_general_ci',
    prefix    = "",
    strict    = true,
    engine    = nil,
    page_size = 10, -- 分页读取时1页条数
    pool_size = 10, -- socket层连接池数量
    pool_timeout = 10000, -- 连接池idle的超时时长，单位毫秒
}

-- 构造器内部分析处理表名称的方法
-- @param string table_name 参数形式：no_prefix_table|no_prefix_table as table_alias
-- @return string `with_prefix_table`|`with_prefix_table` AS `table_alias`
local parseJoinTable = function(self, table_name)
   -- 去除可能的两端空白 后 按空格截取后长度之可能为1、2、3的数组
    local _table_array = utils.explode('%s+', utils.trim(table_name));

    -- 使用了as语法显式设置别名
    if #_table_array == 3 then
        return {
            self._config.prefix .. _table_array[1],
            _table_array[3]
        }
    end

    -- 使用了空格显式设置别名
    if #_table_array == 2 then
        return {
            self._config.prefix .. _table_array[1],
            _table_array[2]
        }
    end

    -- 未显式设置别名，使用无前缀的表名作为别名
    if #_table_array == 1 then
        return {
            self._config.prefix .. _table_array[1],
            _table_array[1]
        }
    end

    -- 解析出的数组长度大于3或为0，join的格式有误
    utils.exception("[parse error]JOIN table name param format error,please modify it")
    return nil
end

-- 参数配置设置方式【必须是第一个被调用的方法】
-- @param array _config Db数据库连接配置参数数组
local function _setConfig(self, _config)
    -- 尝试合并数组
    _config = utils.array_merge(config, _config)

    -- 合并后结果正常则赋值
    if not utils.empty(_config) then
        config = _config
    end

    return self
end
_M.setConfig = _setConfig

-- 获取配置
-- @param string key 可选的按指定配置项返回
-- @return mixed
local function _getConfig(_, key)
    if config[key] then
        return config[key]
    end

    -- 返回数组
    return config
end
_M.getConfig = _getConfig

-- 默认情况下一次设置配置，底层可自动共用这一份配置，也就是说惯例情况下配置是类级别的
-- 该方法用于设置对象实例自身的配置参数，用于某些情况下的实例级别配置调整
-- @param string _config 指定格式的配置数组
function _M.setSelfConfig(self, _config)
    _config = utils.array_merge(self._config, _config)

    -- 合并后结果正常则赋值
    if not utils.empty(_config) then
        self._config = _config
    end

    return self
end

-- 默认情况下一次设置配置，底层可自动共用这一份配置，也就是说惯例情况下配置是类级别的
-- 该方法用于获取对象实例自身的配置参数
-- @param string _config 指定格式的配置数组
function _M.getSelfConfig(self, key)
    if self._config[key] then
        return self._config[key]
    end

    -- 返回数组
    return self._config
end

--- 获取builder内部构造器选项项目table
--- @param string option 可选的内部构造器选项名称
--- @return mixed
local function _getOptions(self, option)
    if self.options[option] ~= nil then
        return self.options[option]
    end

    -- 返回数组
    return self.options
end
_M.getOptions = _getOptions

--- 设置builder内部构造器选项项目table【外部直接调用有风险，务必清楚你调用该方法的目的，内部options结构参照上方局部变量options】
--- @param string option 内部构造器选项名称
--- @param mixed  value  内部构造器值
--- @return mixed
local function _setOptions(self, option, value)
    -- 检查是否存在内部配置项名称后直接赋值，不做任何检查
    if nil ~= options[option] then
        self.options[option] = value
    end

    -- 返回数组
    return self
end
_M.setOptions = _setOptions

--- 清理内部options设置项【外部直接调用有风险，务必清楚你调用该方法的目的，内部options结构参照上方局部变量options】
--- @param string option 可选内部构造器选项名称，不传你则清理所有
--- @return mixed
local function _removeOptions(self, option)
    -- 如果未传参option则表示清理所有内部option
    -- 如果有传参option则检查该option是否为内部的key后单独清理该1个option
    if nil == option then
        self.options = options -- 直接内部默认选项结构覆盖，清理全部已设置的option选项
    else
        -- 存在该内部选项值，则只清理该一项，不存在该key时避免混乱不做任何动作
        if nil ~= options[option] then
            self.options[option] = options[option]
        end
    end

    return self
end
_M.removeOptions = _removeOptions

-- new语法构造新对象
function _M.new(self, _config)
    if not utils.empty(_config) then
        _setConfig(self, _config)
    end

    -- 复制一份config配置，首次设置config后无需再显式设置配置参数
    local __config = utils.cold_copy(config)

    local _self = {
        _config = __config,
        _field  = field:new(),
        _where  = where_class:new(),
        options = {
            table     = '',
            field     = {},
            where     = { AND = {}, OR  = {} },
            join      = {},
            order     = {},
            limit     = '',
            data      = {},
            page      = {},
            group     = '',
            having    = '',
            distinct  = false,
            lock      = ''
        }
    }

    return setmetatable(_self, mt)
end

--- 设置表名称
--- @param string table 不带前缀的数据表名称
function _M.table(self, table)
    if 'string' ~= type(table) then
        -- table只支持字符串形式的参数
        utils.exception("[parse error]TABLE name param type error,please use string")
        return self
    end

    -- 拼接成完整表名称后反引号包裹
    self.options.table = utils.set_back_quote(self._config.prefix .. utils.strip_back_quote(table))
    return self
end

--- 设置查询表字段名称
--- @param string|array fields 需要查的表字段名称，字符串或数组
function _M.field(self, fields)
    --- field模块设置处理字段
    self._field:set(fields)
    --- 从field模块读取出设置处理好的字段名称数组
    self.options.field = self._field:get(true)

    return self
end

-- join查询设置
-- @param string table           要join关联的表名称，格式：xxx xxx1
-- @param string|where condition 关联提交，字符串形式或者where对象
-- @param string operate         join的类型，inner|left|right，默认inner
-- @param array binds            可选的对condition进行参数绑定的额外变量参数，condition中必须使用问号(?)占位
function _M.join(self, table, condition, operate, binds)
    -- 检查必选参数
    if utils.empty(table) or utils.empty(condition) then
        utils.exception('[parse error]JOIN required param `table` or `condition` is empty')
        return self
    end

    -- join构造的格式
    -- {'table','operate', 'condition'}
    local join = {}

    -- 解析join的表名称
    local join_table = parseJoinTable(self, table)
    if utils.empty(join_table) then
        utils.exception('[parse error]JOIN parse param `table` occur fatal error')
        return self
    end
    table_insert(join, join_table)

    -- 处理join操作类型：inner、left、right
    if utils.empty(operate) then
        table_insert(join, 'INNER')
    elseif 'left' == string_lower(operate) then
        table_insert(join, 'LEFT')
    else
        table_insert(join, 'RIGHT')
    end

    -- join条件里有参数绑定
    if not utils.empty(binds) then
        condition = utils.db_bind_value(condition, binds)
    end

    table_insert(join,condition)

    -- 将解析的结果保存
    table_insert(self.options.join, join)

    return self
end

-- where构造查询条件核心方法
-- @param string column  字段名称
-- @param string operate 操作符
-- @param string|array condition 操作条件
function _M.where(self, column, operate, condition)
    -- 传递给内部where对象处理
    self._where.where(self._where, column, operate, condition)

    -- 从where对象获取到处理好的内部options
    self.options.where = self._where:getOptions()

    return self
end

-- whereOr构造查询条件核心方法
-- @param string column  字段名称
-- @param string operate 操作符
-- @param string|array condition 操作条件
function _M.whereOr(self, column, operate, condition)
    -- 传递给内部where对象处理
    self._where.whereOr(self._where, column, operate, condition)

    -- 从where对象获取到处理好的内部options
    self.options.where = self._where:getOptions()

    return self
end

-- IS NULL 快捷用法
-- @param string column 字段名称
function _M.whereNull(self, column)
    self.where(self, column, 'NULL')
    return self
end

-- IS NOT NULL 快捷用法
-- @param string column 字段名称
function _M.whereNotNull(self, column)
    self.where(self, column, 'NOT NULL')
    return self
end

-- In快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
function _M.whereIn(self, column, condition)
    self.where(self, column, 'IN', condition)
    return self
end

-- Not In快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
function _M.whereNotIn(self, column, condition)
    self.where(self, column, 'NOT IN', condition)
    return self
end

-- between快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
function _M.whereBetween(self, column, condition)
    self.where(self, column, 'BETWEEN', condition)
    return self
end

-- Not between快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
function _M.whereNotBetween(self, column, condition)
    self.where(self, column, 'NOT BETWEEN', condition)
    return self
end

-- LIKE快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
function _M.whereLike(self, column, condition)
    self.where(self, column, 'LIKE', condition)
    return self
end

-- Not LIKE快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
function _M.whereNotLike(self, column, condition)
    self.where(self, column, 'NOT LIKE', condition)
    return self
end

-- Exp表达式用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
function _M.whereExp(self, column, condition)
    self.where(self, column, 'EXP', condition)
    return self
end

-- 设置order排序字段和条件
-- @param string|array column 需指定的排序字段名称
-- @param string sorted       排序类型，ASC|DESC，不传则默认ASC
function _M.order(self, column, sorted)
    if not utils.in_array(sorted, {'ASC', 'DESC'}) then
        sorted = 'ASC'
    end

    -- 字符串形式
    if 'string' == type(column) then
        table_insert(self.options.order, {utils.set_back_quote(utils.strip_back_quote(column)), sorted})
    end

    -- 关联数组形式多个排序
    if 'table' == type(column) then
        for k_column,v_sorted in pairs(column) do
            if 'string' == type(k_column) then
                if not utils.in_array(v_sorted, {'ASC', 'DESC'}) then
                    v_sorted = 'ASC'
                end
                table_insert(self.options.order, {utils.set_back_quote(utils.strip_back_quote(k_column)), v_sorted})
            end
        end
    end

    return self
end

-- 设置数据对象，用于insert|update等操作
-- @param string|array 设置的数据内容数组或字符串字段名称
-- @param string       要设置的数据对象值【使用两个参数形式时第一个参数必须是字段名】
function _M.data(self, column, value)
    local data = self.options.data

    -- 数组形式设置data
    if "table" == type(column) then
        for key,val in pairs(column) do
            -- 处理字段名
            key = utils.set_back_quote(utils.strip_back_quote(key))

            -- 转义字段值并使用覆盖方式添加值
            data[key] = utils.quote_value(val)
        end
    end

    -- 两个参数形式设置key-value
    if "string" == type(column) and value ~= nil then
        -- 处理字段名
        local key = utils.set_back_quote(utils.strip_back_quote(column))

        -- 转义字段值并使用覆盖方式添加值
        data[key] = utils.quote_value(value)
    end

    -- 内部记录设置的data
    self.options.data = data

    return self
end

-- 设置limit条件，只能调用1次，多次调用后面的将覆盖前面的
-- @param integer offset 偏移量
-- @param integer length 读取数量
function _M.limit(self, offset, length)
    offset = tonumber(offset) or nil
    -- 限定返回条数
    if 'number' == type(offset) and utils.empty(length) then
        self.options.limit = offset
        return self
    end

    length = tonumber(length) or nil
    if not offset or not length then
        utils.exception('[parse error]LIMIT offset and length must be integer')
    else
        self.options.limit = offset .. ',' .. length
    end

    return self
end

-- 设置分页
-- @param integer page 当前页码，不传或传nil则自动从http变量名中读取，变量名称配置文件配置
-- @param integer page_size 一页多少条数据，不传或传nil则自动从分页配置中读取
function _M.page(self, page, page_size)
    page      = tonumber(page)
    page_size = tonumber(page_size) or self:getOptions("page_size") -- 若未设置分页的一页大小，则从配置中读取

    if "number" ~= type(page) or page_size <= 0 then
        utils.exception("[parse error]Page method param type must be int or number string")
    end

    -- 计算偏移量
    local offset = (page - 1) * page_size

    -- 内部记录page方法设置的参数值
    self.options.page  = {page, page_size}

    -- 转换为limit对应语法
    self.options.limit = offset .. ',' .. page_size

    return self
end

-- 设置group条件，只能调用1次，多次调用后面的将覆盖前面的
-- @param string column 需要分组的字段名，仅支持字符串
function _M.group(self, column)
    -- 仅支持字符串参数
    if 'string' == type(column) then
        self.options.group = utils.trim(column)
    else
        utils.exception('[parse error]GROUP param must be string')
    end

    return self
end

-- 设置having条件，配合group使用
-- @param string condition having条件，字符串形式支持聚合函数
function _M.having(self, condition)
    -- 仅支持字符串参数
    if 'string' == type(condition) then
        -- having支持聚合函数，这里仅去掉可能两端空白，不做进一步处理
        self.options.having = utils.trim(condition)
    else
        utils.exception('[parse error]HAVING param must be string')
    end

    return self
end

-- 设置distinct唯一
-- @param bool distinct 是否唯一，布尔值
function _M.distinct(self, distinct)
    -- 等价空值则不distinct，等价非空值则distinct
    self.options.distinct = not utils.empty(distinct)

    return self
end

-- 设置锁机制
-- @param bool|string lock_mode 传入true则是FOR UPDATE锁，传入字符串则是特殊的锁，譬如：lock in share mode
function _M.lock(self, lock_mode)
    if true == lock_mode then
        self.options.lock = 'FOR UPDATE'
    end
    if 'string' == type(lock_mode) then
        self.options.lock = utils.trim(lock_mode)
    end
    return self
end

return _M
