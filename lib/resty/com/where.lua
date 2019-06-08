---
--- Db底层where条件查询构造器
---
local oop          = require "resty.com.oop"
local utils        = require "resty.com.utils"
local string_upper = string.upper
local type         = type
local table_insert = table.insert
local where_class  = oop.class() --oop实现继承、链式调用

--[[
    -- where条件内部结构
    options = {
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
]]
-- where方法内部的保存结构
local options = {
    AND = {},
    OR  = {}
}

--- 预定义查询表达式操作符
local operator = {
    '=', --- 等于
    '<>', --- 不等于
    '>', --- 大于
    '>=', --- 大于等于
    '<', --- 小于
    '<=', --- 小于等于
    'LIKE', --- like模糊检索
    'NOT LIKE', --- like模糊检索取非
    'BETWEEN', --- between区间查询
    'NOT BETWEEN', --- between区间查询取非
    'IN', --- in查询
    'NOT IN', --- in查询取非
    'NULL', --- null等价查询
    'NOT NULL', --- null等价查询取非
    'EXP', --- 表达式查询
}

-- 获取内部保存的where整个数组
where_class.getOptions = function()
    return options
end

-- where构造查询条件核心方法
-- @param string column  字段名称
-- @param string operate 操作符
-- @param string|array condition 操作条件
where_class.where = function(self, column, operate, condition)
    if not column then
        utils.logger('[parse error]WHERE param column is missing')
        return self
    end

    -- 处理变量
    local _where = {}

    -- 处理column字段
    -- 回调函数形式实现闭包括号功能
    if 'function' == type(column) then
        table_insert(options.AND, column)
        return self
    end

    -- 字符串形式的字段名
    table_insert(_where, utils.set_back_quote(utils.strip_back_quote(column)))

    -- 处理操作符
    local _operate = string_upper(operate)
    if utils.in_array(_operate, operator) then
        -- 操作符类型
        table_insert(_where, _operate)
        -- 将operate参数传递过来的值quote之后存储
        table_insert(_where, utils.quote_value(condition))
    else
        -- 等于查询简写形式
        table_insert(_where, '=')
        -- 将值quote之后存储
        table_insert(_where, utils.quote_value(operate))
    end

    -- 内部结构化存储
    table_insert(options.AND, _where)

    return self
end

-- whereOr构造查询条件核心方法
-- @param string column  字段名称
-- @param string operate 操作符
-- @param string|array condition 操作条件
where_class.whereOr = function(self, column, operate, condition)
    if not column then
        utils.logger('[parse error]whereOr param column is missing')
        return self
    end

    -- 处理变量
    local _where = {}

    -- 处理column字段
    -- 回调函数形式实现闭包括号功能
    if 'function' == type(column) then
        table_insert(options.OR, column)
        return self
    end

    -- 字符串形式的字段名
    table_insert(_where, utils.set_back_quote(utils.strip_back_quote(column)))

    -- 处理操作符
    local _operate = string_upper(operate)
    if utils.in_array(_operate, operator) then
        -- 操作符类型
        table_insert(_where, _operate)
        -- [not ]null无需condition
        if  'NULL' ~= _operate and 'NOT NULL' ~= _operate then
            -- 将operate参数传递过来的值quote之后存储
            table_insert(_where, utils.quote_value(condition))
        end
    else
        -- 等于查询简写形式
        table_insert(_where, '=')
        -- 将值quote之后存储
        table_insert(_where, utils.quote_value(operate))
    end

    -- 内部结构化存储
    table_insert(options.OR, _where)

    return self
end

return where_class
