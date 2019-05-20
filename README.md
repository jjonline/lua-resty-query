# lua-resty-db

基于[openresty/lua-resty-mysql](https://github.com/openresty/lua-resty-mysql)库的openresty下lua相关no block操作mysql的封装，支持简单的链式调用。

## 快速上手

* 查询单条数据
````
local query = require "resty/db/query"

local db = query("user")

-- 用法1
local user = db:table("user"):where("id", 1):find()

-- 用法2
local user = db:table("user"):where({"id" = 1}):find()

-- user结果集示例：
-- {
--    "id"     = 1,
--    "type"   = 1,
--    "name"   = "jjonline",
--    "gender" = 1,
--    "email"  = "jjonline@jjonline.cn"
-- }

````

* 查询多条数据

````
local query = require "resty/db/query"

local db = query("user")

-- 用法1
local users = db:table("user"):where("type", 1):select()

-- 用法2
local users = db:table("user"):where({"type" = 1}):select()

-- users结果集示例：
-- {
--    {
--      "id"     = 1,
--      "type"   = 1,
--      "name"   = "jjonline",
--      "gender" = 1,
--      "email"  = "jjonline@jjonline.cn"
--    },
--    {
--      "id"     = 2,
--      "type"   = 1,
--      "name"   = "yang",
--      "gender" = 1,
--      "email"  = "jjonline@qq.com"
--    },   
-- }

````

## 方法列表

* query
    * [config](#config)
    * [connect](#connect)
    * [close](#close)
    * [new](#new)
    * [connection](#connection)
    * [buildSQL](#buildSQL)
    * [table](#table)
    * [alias](#alias)
    * [field](#field)
    * [innerJoin](#innerJoin)
    * [lefJoin](#lefJoin)
    * [rightJoin](#rightJoin)
    * [fullJoin](#fullJoin)
    * [where](#where)
    * [order](#order)
    * [limit](#limit)
    * [insert](#insert)
    * [insertGetId](#insertGetId)
    * [find](#find)
    * [select](#select)
    * [page](#page)
    * [update](#update)
    * [delete](#delete)
    * [query](#query)
    * [startTrans](#startTrans)
    * [commit](#commit)
    * [rollback](#rollback)
    * [transaction](#transaction)
* env
* utils

config
---

connect
---

close
---

new
---

new
---

## 鸣谢并使用的依赖包

> 以下依赖包直接归并到了本git库，无需额外引入直接使用

| 包名称 | 版本 | 协议 |说明 |
| :----: | :----: | :----: |:----: |
| lua-resty-ini | master | BSD | [Github](https://github.com/doujiang24/lua-resty-ini) |
