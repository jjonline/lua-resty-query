---
--- Db数据表字段管理器
---
local utils        = require "resty.com.utils"
local type         = type
local pairs        = pairs
local table_insert = table.insert
local setmetatable = setmetatable

local _M = {}
local mt = { __index = _M }

-- 定义字段对象内部的数据结构
-- 内部格式如下：
--[[
    {
        '`field1`',
        '`field2` as `field3`',
        '`table`.`filed4`',
        '`table`.`filed5` as `filed6`',
    }
]]--

-- 解析单个字符串的成标准sql字段
-- @param string string 字符串形式的字段
-- @return string
local function parse_to_field(string)
    -- 单个字段可能的形式
    -- `aa`.`a as bcd
    -- `bb`.b
    -- `cc as dd`
    -- `ee`
    return utils.set_back_quote(utils.strip_back_quote(string))
end

-- 解析字符串形式的字段
-- 匹配处理形如：
--      1、"aa,bb, cc,dd , ee ,ff"
--      2、"aa.gg,bb, cc,dd , ee ,ff"
--      3、"`aa`.`gg`,bb, `cc`,dd , `ee` ,ff`"  注意 最后的ff带反引号不标准也支持
--      4、"`aa`.`gg` as d,bb, `cc`,dd , `ee`"  as语法
--      5、"`aa`.`gg`,bb as `bed`, `cc`,dd , `ee`" as语法
-- @param string field 字符串形式的字段，譬如："*"、"id,name,gender,phone"、"`id`,`name`"
-- @return array {} 譬如：{"`aa`","`bb`.`cc`","`dd` as `ee`","`ff`.`gg` as `hh`"}
-----------------------------------
--      {
--          "`aa`",
--          "`bb`.`cc`",
--          "`dd` as `ee`",
--          "`ff`.`gg` as `hh`"
--      }
-----------------------------------
local function parse_string(field)
    local s_field = utils.trim(field) -- 去除两端空白后执行分析
    if "*" == s_field then
        return {}
    end

    -- 定义返回的数组
    local r_field = {}

    -- 按英文半角逗号分割成array
    s_field = utils.explode(",", s_field)

    -- 逐个处理字段内容
    for _,v in pairs(s_field) do
        table_insert(r_field, parse_to_field(v))
    end

    -- 返回【可能存在重复，最终解析使用前需要去重】
    return r_field
end

-- 解析数组|dict形式的value 的字段
-- @param string field 字符串形式的字段，譬如："*"、"id,name,gender,phone"、"`id`,`name`"
-- @return array {} 譬如：{"`aa`","`bb`.`cc`","`dd` as `ee`","`ff`.`gg` as `hh`"}
-----------------------------------
--      {
--          "`aa`",
--          "`bb`.`cc`",
--          "`dd` as `ee`",
--          "`ff`.`gg` as `hh`"
--      }
-----------------------------------
local function parse_array(array)
    -- 定义返回的数组
    local r_field = {}

    -- 逐个处理字段内容
    for _,v in pairs(array) do
        table_insert(r_field, parse_to_field(v))
    end

    -- 返回【可能存在重复，最终解析使用前需要去重】
    return r_field
end

-- new语法构造新对象
function _M.new(_)
    return setmetatable({field = {}}, mt)
end

-- 设置1个query的字段对象
-- @param mixed field 字符串、table等格式
function _M.set(self, field)
    local field_array = {}
    if "string" == type(field) then
        field_array = parse_string(field)
    elseif "table" == type(field) then
        field_array = parse_array(field)
    else
        -- 暂时仅支持string和table类型参数，其他类型报错
        utils.exception("[field]please use associative array or string separated by comma")
    end

    -- 逐个添加进数组
    for _,v in pairs(field_array) do
        table_insert(self.field, v)
    end

    -- 去重返回所有已设置的字段数组
    self.field = utils.unique(self.field)
    return self.field
end

-- 设置1个字符串原型query的字段对象
-- @param string field 字符串raw原型
function _M.setRaw(self, field)
    if "string" ~= type(field) then
        -- raw set only support string
        utils.exception("[fieldRaw]please use string in raw field mode")
    end

    -- add to array
    table_insert(self.field, utils.trim(field))

    -- 去重返回所有已设置的字段数组
    self.field = utils.unique(self.field)
    return self.field
end

-- 获取1个query使用的字段对象
-- @param boolean is_array 调试用参数，true返回table false或不传返回字符串
function _M.get(self, is_array)
    if utils.empty(is_array) then
        return utils.implode(",", self.field)
    end
    return self.field
end

-- 清理内部设置的字段
function _M.reset(self)
    self.field = {}
    return self
end

return _M
