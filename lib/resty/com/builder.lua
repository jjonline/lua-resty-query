---
--- Db底层查询构造器
---
local utils        = require "resty.com.utils"
local field        = require "resty.com..field"
local where_class  = require "resty.com..where"
local oop          = require "resty.com.oop"
local type         = type
local tonumber     = tonumber
local table_insert = table.insert
local string_lower = string.lower
local builder      = oop.class() --oop实现继承、链式调用

-- 链式调用where的本地对象
local where_object = where_class()

-- 构造器内部各参数存储容器，内部结构如下:
--[[
    options = {}

    -- 表名称前缀
    options.table_prefix = 'table_prefix_'

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

    -- group子句内部结构的字段名
    options.group = 'column_name';
    -- 或 多个字段：options.group = 'column_name,column_name1';

    -- 设置group的having条件
    options.having = ''

    -- 是否distinct唯一
    options.distinct = false;
]]--
local options = {
    prefix = '',
    table  = nil,
    field  = {},
    where  = {
        AND = {},
        OR  = {},
    },
    join      = {},
    order     = {},
    limit     = '',
    group     = '',
    having    = '',
    distinct  = false,
    lock      = '',
}

-- 数据库配置
local config  = {
    prefix = '' -- 表名称前缀
}

-- 构造器内部分析处理表名称的方法
-- @param string table_name 参数形式：no_prefix_table|no_prefix_table as table_alias
-- @return string `with_prefix_table`|`with_prefix_table` AS `table_alias`
local parseJoinTable = function(table_name)
   -- 去除可能的两端空白 后 按空格截取后长度之可能为1、2、3的数组
    local _table_array = utils.explode('%s+', utils.trim(table_name));

    -- 使用了as语法显式设置别名
    if #_table_array == 3 then
        return {
            config.prefix .. _table_array[1],
            _table_array[3]
        }
    end

    -- 使用了空格显式设置别名
    if #_table_array == 2 then
        return {
            config.prefix .. _table_array[1],
            _table_array[2]
        }
    end

    -- 未显式设置别名，使用无前缀的表名作为别名
    if #_table_array == 1 then
        return {
            config.prefix .. _table_array[1],
            _table_array[1]
        }
    end

    -- 解析出的数组长度大于3或为0，join的格式有误
    utils.logger("[parse error]JOIN table name param format error,please modify it")
    return nil
end

-- 参数配置设置方式【必须是第一个被调用的方法】
-- @param array _config Db数据库连接配置参数数组
builder.setConfig = function(self, _config)
    -- 配置参数内部数组
    config = _config
    -- 设置内部表名称前缀
    if utils.empty(config.prefix) then
        options.prefix = ''
    else
        options.prefix = config.prefix
    end
    return self
end

--- 获取builder内部构造器选项项目table
--- @param string option 可选的内部构造器选项名称
builder.getOptions = function(option)
    if options[option] then
        return options[option]
    end
    return options
end

--- 设置表名称
--- @param string table 不带前缀的数据表名称
builder.table = function(self, table)
    if 'string' ~= type(table) then
        -- table只支持字符串形式的参数
        utils.logger("[parse error]TABLE name param type error,please use string")
        return self
    end

    -- 拼接成完整表名称后反引号包裹
    options.table = utils.set_back_quote(options.prefix .. utils.strip_back_quote(table))
    return self
end

--- 设置查询表字段名称
--- @param string|array fields 需要查的表字段名称，字符串或数组
builder.field = function(self, fields)
    --- field模块设置处理字段
    field.set(fields)
    --- 从field模块读取出设置处理好的字段名称数组
    options.field = field.get(true)

    return self
end

-- join查询设置
-- @param string table           要join关联的表名称，格式：xxx xxx1
-- @param string|where condition 关联提交，字符串形式或者where对象
-- @param string operate         join的类型，inner|left|right，默认inner
-- @param array binds            可选的对condition进行参数绑定的额外变量参数，condition中必须使用问号(?)占位
builder.join = function(self, table, condition, operate, binds)
    -- 检查必选参数
    if utils.empty(table) or utils.empty(condition) then
        utils.logger('[parse error]JOIN required param `table` or `condition` is empty')
        return self
    end

    -- join构造的格式
    -- {'table','operate', 'condition'}
    local join = {}

    -- 解析join的表名称
    local join_table = parseJoinTable(table)
    if utils.empty(join_table) then
        utils.logger('[parse error]JOIN parse param `table` occur fatal error')
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
    table_insert(options.join, join)

    return self
end

-- where构造查询条件核心方法
-- @param string column  字段名称
-- @param string operate 操作符
-- @param string|array condition 操作条件
builder.where = function(self, column, operate, condition)
    -- 传递给内部where对象处理
    where_object.where(where_object, column, operate, condition)

    -- 从where对象获取到处理好的内部options
    options.where = where_object.getOptions()

    return self
end

-- whereOr构造查询条件核心方法
-- @param string column  字段名称
-- @param string operate 操作符
-- @param string|array condition 操作条件
builder.whereOr = function(self, column, operate, condition)
    -- 传递给内部where对象处理
    where_object.whereOr(where_object, column, operate, condition)

    -- 从where对象获取到处理好的内部options
    options.where = where_object.getOptions()

    return self
end

-- IS NULL 快捷用法
-- @param string column 字段名称
builder.whereNull = function(self, column)
    where_object.where(self, column, 'NULL')
    return self
end

-- IS NOT NULL 快捷用法
-- @param string column 字段名称
builder.whereNotNull = function(self, column)
    where_object.where(self, column, 'NOT NULL')
    return self
end

-- In快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
builder.whereIn = function(self, column, condition)
    where_object.where(self, column, 'IN', condition)
    return self
end

-- Not In快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
builder.whereNotIn = function(self, column, condition)
    where_object.where(self, column, 'NOT IN', condition)
    return self
end

-- between快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
builder.whereBetween = function(self, column, condition)
    where_object.where(self, column, 'BETWEEN', condition)
    return self
end

-- Not between快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
builder.whereNotBetween = function(self, column, condition)
    where_object.where(self, column, 'NOT BETWEEN', condition)
    return self
end

-- LIKE快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
builder.whereLike = function(self, column, condition)
    where_object.where(self, column, 'LIKE', condition)
    return self
end

-- Not LIKE快捷用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
builder.whereNotLike = function(self, column, condition)
    where_object.where(self, column, 'NOT LIKE', condition)
    return self
end

-- Exp表达式用法
-- @param string column 字段名称
-- @param string|array condition 操作条件
builder.whereExp = function(self, column, condition)
    where_object.where(self, column, 'EXP', condition)
    return self
end

-- 设置order排序字段和条件
-- @param string|array column 需指定的排序字段名称
-- @param string sorted       排序类型，ASC|DESC，不传则默认ASC
builder.order = function(self, column, sorted)
    if not utils.in_array(sorted, {'ASC', 'DESC'}) then
        sorted = 'ASC'
    end

    -- 字符串形式
    if 'string' == type(column) then
        table_insert(options.order, {utils.set_back_quote(utils.strip_back_quote(column)), sorted})
    end

    -- 关联数组形式多个排序
    if 'table' == type(column) then
        for k_column,v_sorted in pairs(column) do
            if 'string' == type(k_column) then
                if not utils.in_array(v_sorted, {'ASC', 'DESC'}) then
                    v_sorted = 'ASC'
                end
                table_insert(options.order, {utils.set_back_quote(utils.strip_back_quote(k_column)), v_sorted})
            end
        end
    end

    return self
end

-- 设置limit条件，只能调用1次，多次调用后面的将覆盖前面的
-- @param integer offset 偏移量
-- @param integer length 读取数量
builder.limit = function(self, offset, length)
    offset = tonumber(offset) or nil
    -- 限定返回条数
    if 'number' == type(offset) and utils.empty(length) then
        options.limit = offset
        return self
    end

    length = tonumber(length) or nil
    if not offset or not length then
        utils.logger('[parse error]LIMIT offset and length must be integer')
    else
        options.limit = offset .. ',' .. length
    end

    return self
end

-- 设置group条件，只能调用1次，多次调用后面的将覆盖前面的
-- @param string column 需要分组的字段名，仅支持字符串
builder.group = function(self, column)
    -- 仅支持字符串参数
    if 'string' == type(column) then
        options.group = utils.trim(column)
    else
        utils.logger('[parse error]GROUP param must be string')
    end

    return self
end

-- 设置having条件，配合group使用
-- @param string condition having条件，字符串形式支持聚合函数
builder.having = function(self, condition)
    -- 仅支持字符串参数
    if 'string' == type(condition) then
        -- having支持聚合函数，这里仅去掉可能两端空白，不做进一步处理
        options.having = utils.trim(condition)
    else
        utils.logger('[parse error]HAVING param must be string')
    end

    return self
end

-- 设置distinct唯一
-- @param bool distinct 是否唯一，布尔值
builder.distinct = function(self, distinct)
    -- 等价空值则不distinct，等价非空值则distinct
    options.distinct = not utils.empty(distinct)

    return self
end

-- 设置锁机制
-- @param bool|string lock_mode 传入true则是FOR UPDATE锁，传入字符串则是特殊的锁，譬如：lock in share mode
builder.lock = function(self, lock_mode)
    if true == lock_mode then
        options.lock = 'FOR UPDATE'
    end
    if 'string' == type(lock_mode) then
        options.lock = utils.trim(lock_mode)
    end
    return self
end

return builder
