---
--- helper方法类
---
local type          = type
local pairs         = pairs
local next          = next
local setmetatable  = setmetatable
local getmetatable  = getmetatable
local ipairs        = ipairs
local table_concat  = table.concat
local table_insert  = table.insert
local string_char   = string.char
local string_gsub   = string.gsub
local quote_sql_str = ngx.quote_sql_str
local ngx_log       = ngx.log
local output        = ngx.print -- debug输出任意变量使用的输出方法

-- table数组去重值唯一，数组下标将自动重排
-- @param mixed data 拟调试输出的变量
-- @return array
local function unique(array)
    -- 类型检查
    if "table" ~= type(array) then
        return {}
    end
    local check = {}
    local result = {}
    for _, v in ipairs(array) do
        if not check[v] then
            table_insert(result,v)
            check[v] = true
        end
    end
    return result
end

-- 调试输出任意变量方法
-- @param mixed data 拟调试输出的变量
-- @param boolean showMetatable 是否要输出table的元组信息
-- [@param mixed lastCount 递归使用标记，调用时不许传参]
local function dump(data, showMetatable, lastCount)
    if type(data) ~= "table" then
        --Value
        if type(data) == "string" then
            output("\"", data, "\"")
        else
            output(tostring(data))
        end
    else
        --Format
        local count = lastCount or 0
        count = count + 1
        output("{\n")
        --Metatable
        if showMetatable then
            for i = 1,count do output("\t") end
            local mt = getmetatable(data)
            output("\"__metatable\" = ")
            dump(mt, showMetatable, count)    -- 如果不想看到元表的元表，可将showMetatable处填nil
            output(",\n")     --如果不想在元表后加逗号，可以删除这里的逗号
        end
        --Key
        for key,value in pairs(data) do
            for i = 1,count do output("\t") end
            if type(key) == "string" then
                output("\"", key, "\" = ")
            elseif type(key) == "number" then
                output("[", key, "] = ")
            else
                output(tostring(key))
            end
            dump(value, showMetatable, count) -- 如果不想看到子table的元表，可将showMetatable处填nil
            output(",\n")     --如果不想在table的每一个item后加逗号，可以删除这里的逗号
        end
        --Format
        for i = 1,lastCount or 0 do output("\t") end
        output("}")
    end
    --Format
    if not lastCount then
        output("\n")
    end
end

-- 检查变量是否为空
local function empty(value)
    if value == nil or value == '' or value == false then
        return true
    elseif type(value) == 'table' then
        return next(value) == nil
    else
        return false
    end
end

-- 简单日志记录
local function logger(log, level)
    if empty(level) then
        level = ngx.INFO
    end
    ngx_log(level, log)
end

-- 去除字符串中的所有反引号
-- @param string s 待处理的字符串
-- @return string
local function strip_back_quote(s)
    return string_gsub(s, "%`(.-)", "%1")
end

-- 设置字符串被反引号括起，一般用于处理 表名称、字段名称
-- @param string s 待处理的字符串
-- @return string
local function set_back_quote(s)
    -- 两边拼接反引号
    local s_rep = "`" .. s .. "`"

    -- as语法的处理，as不区分大小写
    local s1 = string_gsub(s_rep, "%s+%a+%s+", "` AS `")

    -- 如果匹配到了as语法的字段
    if not empty(s1) then
        s_rep = s1
    end

    -- 有别名的点(.)字符处理
    local s2 = string_gsub(s_rep, "(%.)", "`.`")
    if empty(s2) then
        return s_rep
    end

    return s2
end

-- 去除字符串两端空白
-- @param string s 待处理的字符串
-- @param string char 可选的去除两边的字符类型，不传则去除空白，传则去除指定
local function trim(s, char)
    if empty(char) then
        return (string_gsub(s, "^%s*(.-)%s*$", "%1"))
    end
    return (string_gsub(s, "^".. char .."*(.-)".. char .."*$", "%1"))
end

-- 去除字符串左端空白
-- @param string s 待处理的字符串
-- @param string char 可选的去除两边的字符类型，不传则去除空白，传则去除指定
local function ltrim(s, char)
    if empty(char) then
        return (string_gsub(s, "^%s*(.-)$", "%1"))
    end
    return (string_gsub(s, "^".. char .."*(.-)$", "%1"))
end

-- 去除字符串右端空白
-- @param string s 待处理的字符串
-- @param string char 可选的去除两边的字符类型，不传则去除空白，传则去除指定
local function rtrim(s, char)
    if empty(char) then
        return (string_gsub(s, "^(.-)%s*$", "%1"))
    end
    return (string_gsub(s, "^(.-)".. char .."*$", "%1"))
end

-- 使用1个字符串分割另外一个字符串返回数组
-- @param string delimiter 切割字符串的分隔点
-- @param string string 待处理的字符串
-- @return array
local function explode(delimiter, string)
    local rt= {}
    --
    string_gsub(string, '[^'..delimiter..']+', function(w)
        table_insert(rt, trim(w))
    end)

    return rt
end

-- 使用1个字符串将一个table结构的数组合并成1个字符串
-- @param string separator 数组元素相互连接之间的字符串
-- @param array array 待拼接的数组
-- @return array
local function implode(separator,array)
    return table_concat(array, separator)
end

-- 深度复制1个table
local function deep_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deep_copy(orig_key)] = deep_copy(orig_value)
        end
        setmetatable(copy, deep_copy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- 检查1个table是否为数组，即数字索引的table
local function table_is_array(t)
    if type(t) ~= "table" then
        return false
    end

    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then
            return false
        end
    end

    return true
end

-- 检查变量是否在数组之中
-- @param string hack 待检查的变量
-- @param array  needle 给定的数组
-- @return bool
local function in_array(hack, needle)
    if 'table' ~= type(needle) then
        return false
    end
    for _, v in pairs(needle) do
        if v == hack then
            return true
        end
    end
    return false
end

-- quote转义单双引号
-- @param string value 需要单双引号转义处理的字符串
-- @return string 转义后的字符串
local function quote_value(value)
    if 'string' ~= type(value) then
        return value
    end
    return quote_sql_str(value)
end

-- 转移特殊字符，与quote_value方法类似
-- @param string str 需转义的字符
-- @return string
local function escape_string(str)
    -- 变量类型检查
    if 'string' ~= type(str) then
        return nil
    end

    local matches = {
        ['\\'] = '\\\\',
        ["\0"] = '\\0',
        ["\n"] = '\\n',
        ["\r"] = '\\r',
        ["'"] = "\\'",
        ['"'] = '\\"',
        ["\x1a"] = '\\Z'
    }

    for i = 0, 255 do
        local c = string_char(i)
        if c:match('[%z\1-\031\128-\255]') and not matches[c] then
            matches[c] = ('\\x%.2X'):format(i)
        end
    end

    return str:gsub('[\\"/%z\1-\031\128-\255]', matches)
end

-- SQL变量绑定，内部自动处理引号问题
-- @param string sql 问号作为占位符的sql语句或sql构成部分
-- @param array 与sql参数中问号占位符数量相同的变量数组
-- @return string
local function db_bind_value(sql, value)
    -- 检查参数
    if not table_is_array(value) then
        logger('[parse error]db_bind_value param error')
        return sql
    end

    local times = 0
    local result,total = string_gsub(sql, '%?', function(res)
        times = times + 1
        -- quote后返回替换值
        return quote_value(value[times])
    end)

    -- 给定的待绑定的参数数量与sql中的问号变量不一致
    if total ~= #value then
        logger('[parse error]db_bind_value bind value length not equal sql variable length')
        return sql
    end

    -- 返回替换后的结果集
    return result
end

-- 返回helper
return {
    logger           = logger,
    explode          = explode,
    implode          = implode,
    strip_back_quote = strip_back_quote,
    set_back_quote   = set_back_quote,
    unique           = unique,
    dump             = dump,
    trim             = trim,
    ltrim            = ltrim,
    rtrim            = rtrim,
    dump             = dump,
    empty            = empty,
    deep_copy        = deep_copy,
    table_is_array   = table_is_array,
    in_array         = in_array,
    quote_value      = quote_value,
    escape_string    = escape_string,
    db_bind_value    = db_bind_value,
}
