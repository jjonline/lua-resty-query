---
--- Db底层where条件查询构造器
---
local utils        = require "resty.com.utils"
local string_upper = string.upper
local type         = type
local pairs        = pairs
local table_insert = table.insert
local setmetatable = setmetatable

local _M = {}
local mt = { __index = _M }

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

--[[ where方法内部的保存结构，对外暴露
local options = {
    AND = {},
    OR  = {}
}
]]--

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

-- new语法构造新对象
function _M.new(_)
    local self = {
        options  = {
            AND = {},
            OR  = {}
        }
    }

    return setmetatable(self, mt)
end

-- 内部方法：解析between|not between条件值
local function parseBetweenVal(range)
    -- 字符串类型使用逗号分隔解析
    if "string" == type(range) then
        range = utils.explode(',', range)
    end

    -- 数组类型，两个元素
    if "table" == type(range) and #range == 2 then
        return {
            utils.quote_value(utils.trim(range[1])),
            utils.quote_value(utils.trim(range[2]))
        }
    end

    -- 两个元素的索引数组，或逗号分隔的字符串
    utils.exception("[where between]please use index array or string separated by comma")
end

-- 内部方法：解析in|not in条件值
local function parseInVal(range)
    -- 字符串类型使用逗号分隔解析
    if "string" == type(range) then
        range = utils.explode(',', range)
    end

    -- 数组类型，两个元素
    local in_arr = {}
    if "table" == type(range) then
        for _,val in pairs(range) do
            table_insert(in_arr, utils.quote_value(utils.trim(val)))
        end

        return in_arr
    end

    -- 索引数组，或逗号分隔的字符串
    utils.exception("[where in]please use index array or string separated by comma")
end

-- 获取内部保存的where整个数组
function _M.getOptions(self)
    return self.options
end

-- where构造查询条件核心方法
-- @param string column  字段名称
-- @param string operate 操作符
-- @param string|array condition 操作条件
function _M.where(self, column, operate, condition)
    if not column then
        utils.exception("[where]method first param is missing")
    end

    -- 处理变量
    local _where = {}

    -- 处理column字段
    -- 回调函数形式实现闭包括号功能
    if 'function' == type(column) then
        table_insert(self.options.AND, column)
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
            if utils.in_array(_operate, {'IN', 'NOT IN'}) then
                table_insert(_where, parseInVal(condition))
            elseif utils.in_array(_operate, {'BETWEEN', 'NOT BETWEEN'}) then
                table_insert(_where, parseBetweenVal(condition))
            elseif "EXP" == _operate then
                -- 构造成字符串，EXP模式可能会导致注入，尽量避免使用
                _where = utils.set_back_quote(utils.strip_back_quote(column)) .. utils.rtrim(condition)
            else
                -- 将operate参数传递过来的值quote之后存储
                table_insert(_where, utils.quote_value(condition))
            end
        end
    else
        -- 等于查询简写形式
        table_insert(_where, '=')
        -- 将值quote之后存储
        table_insert(_where, utils.quote_value(operate))
    end

    -- 内部结构化存储
    table_insert(self.options.AND, _where)

    return self
end

-- whereOr构造查询条件核心方法
-- @param string column  字段名称
-- @param string operate 操作符
-- @param string|array condition 操作条件
function _M.whereOr(self, column, operate, condition)
    if not column then
        utils.exception("[whereOr]method first param is missing")
    end

    -- 处理变量
    local _where = {}

    -- 处理column字段
    -- 回调函数形式实现闭包括号功能
    if 'function' == type(column) then
        table_insert(self.options.OR, column)
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
            if utils.in_array(_operate, {'IN', 'NOT IN'}) then
                table_insert(_where, parseInVal(condition))
            elseif utils.in_array(_operate, {'BETWEEN', 'NOT BETWEEN'}) then
                table_insert(_where, parseBetweenVal(condition))
            elseif "EXP" == _operate then
                -- 构造成字符串，EXP模式可能会导致注入，尽量避免使用，若确需使用请务必过滤好condition参数
                _where = utils.set_back_quote(utils.strip_back_quote(column)) .. utils.rtrim(condition)
            else
                -- 将operate参数传递过来的值quote之后存储
                table_insert(_where, utils.quote_value(condition))
            end
        end
    else
        -- 等于查询简写形式
        table_insert(_where, '=')
        -- 将值quote之后存储
        table_insert(_where, utils.quote_value(operate))
    end

    -- 内部结构化存储
    table_insert(self.options.OR, _where)

    return self
end

return _M
