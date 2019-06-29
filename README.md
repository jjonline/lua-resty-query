# new方法

功能：实例化一个query对象

用法：

* `query:new(config)` 实例化query对象并设置连接配置

> 其中config为固定结构的table数组

config结构

````
{
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
    page_size = 10,
    pool_size = 10,
    pool_timeout = 10000,
}
````

示例：
````
local query = require "resty.query"

local config = {
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
    page_size = 10,
    pool_size = 10,
    pool_timeout = 10000,
}

local db = query:new(config):table("resty_query")

-- 等价于
-- local db = query:name("resty_query"):setSelfConfig(config)

local res = db:where('id',1):find()

-- 生成的sql类似
-- SELECT * FROM `lua_resty_query` WHERE `id`=1  LIMIT 1

--- 若查询到了数据，res的结构类似：
{
	update_time = "2019-06-17 20:01:36",
	id = 1,
	name = "晶晶",
	create_time = "2019-06-15 00:13:22",
	null_field = userdata: NULL,
	gender = "男",
	age = 1,
	json_field = userdata: NULL,
	user_name = "jjonline",
}

-- 此时query对象已被实例化，再次生成1个对象可无需传配置参数

local db1 = query:name("resty_query")

-- 直接执行查询，底层自动重用上方设置的配置参数
db1:find(2)

````

# name方法

功能：快捷实例化query对象并设置无前缀数据表名称

用法：

* `query:name(table)` 实例化query对象并设置无前缀数据表名称


# table 方法

功能：设置需要操作的数据表

用法：

* `table('table_anme')` 不带前缀的无别名形式
* `table('table_name table_alias_name')` 不带前缀的使用空格标识别名的形式
* `table('table_name AS table_alias_name')` 不带前缀的使用`as`标识别名的形式
* `table({"SELECT * FROM xx", "sub_query"})` 数组形式设置table子查询

# field 方法

功能：设置操作的字段

用法：

* `field('*')` 模糊查询所有字段，尽量避免使用
* `field('field1')` 无表名称(或表别名)形式
* `field('field2 AS field3')` 无表名称(或表别名)但有字段名别名的形式
* `field('table.field4')` 有表名称(或表别名)形式
* `field('table.field5 AS field6')` 有表名称(或表别名)且有字段别名的形式
* `field('table.field7 AS field8,field9')` 字符串形式设置多个字段
* `field({'table.field10 AS field11','field12'})` 数组形式设置多个字段

> 字符串形式使用半角逗号传递多个字段

> 数组形式多个数组元素传递多个字段

> `as`关键字不区分大小写，建议全部大写

示例：
````
local query = require "resty.query"

local config = {
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
    page_size = 10,
    pool_size = 10,
    pool_timeout = 10000,
}

local db = query:new(config):table("resty_query")

local res = db:field("id as user_id")
        :field({"name", "gender as sex"})
        :where('id',1)
        :find()

-- 生成的sql类似
-- SELECT `id` AS `user_id`,`name`,`gender` AS `sex` FROM `lua_resty_query` WHERE `id`=1  LIMIT 1

-- res结构则变化为：
{
	sex = "男",
	name = "晶晶",
	user_id = 1,
}
````

# fieldRaw 方法

功能：设置特殊操作的字段，譬如使用SQL函数

用法：

* `fieldRaw('SUM(aactount) as acc')` 方法体只支持字符串形式，`raw`形式设置‘字段’

````
local db2 = db:name("resty_query as user")
local where = {}
    
where["user.id"] = {"in", "1,2,3"}
where["age"] = {"between", {0,11}}
    
local where_res = db2:field("id"):fieldRaw('SUM(score) as sc'):where(where):select()

-- 构造的sql类似：
SELECT `id`,SUM(score) as sc FROM `lua_resty_query` AS `user` WHERE (`age` BETWEEN '0' AND '11') AND `user`.`id` IN ('1','2','3')

````

# alias 方法

功能：设置数据表别名

用法：

* `alias("alias_name")` 设置当前表的别名

````
local db2 = db:name("resty_query")

db2:alias("user")

-- 等价于
db:name("resty_query user") 
-- 或
db:name("resty_query AS user") 

````

````
db:table("admin_user"):alias("user"):join("level level", "user.id = level.user_id", "LEFT")

-- 构造的SQL为

SELECT * FROM prefix_admin_user AS user LEFT JOIN prefix_level level ON user.id = level.user_id

-- 上述写法等价于：

db:table("admin_user"):alias("user"):join("level", "user.id = level.user_id", "LEFT")

db:table("admin_user"):alias("user"):join("level AS level", "user.id = level.user_id", "LEFT")

db:table("admin_user user"):join("level AS level", "user.id = level.user_id", "LEFT")
````

# join 方法

功能：设置join关联查询

用法：

* `join('no_prefix_table_name', 'no_prefix_table_name.id=table1.cid')` 两个参数默认`inner`查询
* `join('no_prefix_table_name as alias_name', 'alias_name.id=table1.cid')` 两个参数join表带自定义别名，as语法
* `join('no_prefix_table_name', 'no_prefix_table_name.id=table1.cid', 'LEFT')` 三个参数指定join类型
* `join('no_prefix_table_name as alias_name', 'alias_name.id=? AND table.cid=?', 'inner', {1, 11})` 四个参数join条件里使用参数绑定增强安全性


# where 方法

* 方法原型1：`where('可选的表名.字段名','操作符', '查询值')` `AND`类型查询
* 方法原型2：`whereOr('可选的表名.字段名', '操作符', '查询值')` `OR`类型查询

操作符列表：

| code | 说明 | 示例 |
| :--: | :-- |:--|
| = | 等于 |`where('field','=','val')`  简写：`where('field','val')`|
| <> | 不等于 |`where('field','<>','val')`|
| > | 大于 |`where('field','>','val')`|
| >= | 大于等于 |`where('field','>=','val')`|
| < | 小于 |`where('field','<','val')`|
| <= | 小于等于 |`where('field','<=','val')`|
| LIKE | like模糊检索 |`where('field','LIKE','%val%')`|
| NOT LIKE | like模糊检索取非 |`where('field','NOT LIKE','%val%')`|
| BETWEEN | between区间查询 |`where('field','BETWEEN','1,10')` 或 `where('field','BETWEEN',{1,10})`|
| NOT BETWEEN | between区间查询取非 |`where('field','NOT BETWEEN','1,10')` 或 `where('field','NOT BETWEEN',{1,10})`|
| IN | in查询 |`where('field','IN','1,2,10')` 或 `where('field','IN',{1,2,10})`|
| NOT IN | in查询取非 |`where('field','NOT IN','1,2,10')` 或 `where('field','NOT IN',{1,2,10})`|
| NULL | null等价查询 |`where('field','NULL')`，如果需要查询等于字符串null的，写法：`where('field','=','NULL')`|
| NOT NULL | null等价查询取非 |`where('field','NOT NULL')`|
| EXP | 表达式查询 |`where('field','EXP', ' IN (1,2)')`， 尽量避免使用，确需使用请务必处理好第三个参数 |

> 操作符不区分大小写，建议统一使用大写！

快捷用法：

* `whereNull('field')` 快捷`null`查询
* `whereNotNull('field')` 快捷`not null`查询
* `whereIn('table.field','1,2,10')` 快捷`in`查询
* `whereNotIn('table.field',{1,2,10})` 快捷`not in`查询
* `whereBetween('table.field',{1,10})` 快捷`between`查询
* `whereNotBetween('table.field',{1,10})` 快捷`not between`查询
* `whereLike('table.field','%晶晶')` 快捷`like`查询
* `whereNotLike('table.field','%晶晶%')` 快捷`not like`查询
* `whereExp('table.field',' IN (1,2)')` 快捷`EXP`查询

函数回调参数形式

* `where(callback)` 其中`callback`是一个函数，参数为一个`query`对象

````
where(function (query) 
    query:where('id','=',1):whereOr('cid',2)
end):where(function(query)
    query:where('id','=',3):whereOr('name','LIKE','%晶晶%')
end)
````
构造的sql为：`(id=1 OR cid=2) AND (id= 3 OR name LIKE '%晶晶%')`

* `where({可选的表名.字段名 = {操作符, 查询值}})` 数组形式
````
local db2 = db:name("resty_query as user")
local where = {}
    
where["user.id"] = {"in", "1,2,3"}
where["age"] = {"between", {0,11}}
    
local where_res = db2:where(where):select()

-- 构造的sql类似：
SELECT * FROM `lua_resty_query` AS `user` WHERE (`age` BETWEEN '0' AND '11') AND `user`.`id` IN ('1','2','3')

其实就等价于：

db2:where("user.id", "IN", "1,2,3"):where("age", "BETWEEN", {0,11})
````

## [不]等于查询(=、<>)

示例：
````
db:where('id',"=",1):find() 
````
等价于
````
local res = db:where('id',1):find()
````
生成的SQL为：
````
SELECT * FROM `lua_resty_query` WHERE `id`=1  LIMIT 1
````

## 比较查询(>、>=、<、<=)

````
db:where('id',">",1):find() 
````
生成的SQL为：
````
SELECT * FROM `lua_resty_query` WHERE `id`>1  LIMIT 1
````

## [not] in查询

````
db:where('id',"IN",{1,2,3}):find() 
-- 或
db:where('id',"IN",'1,2,3'):find() 
-- 或
db:whereIn('id', '1,2,3'):find() 
````
生成的SQL为：
````
SELECT * FROM `lua_resty_query` WHERE `id` IN ('1','2','3')  LIMIT 1
````

## [not] like查询

````
db:where('name',"LIKE","%晶%"):find() 
-- 或
db:whereLike('name', "%晶%")
````
生成的SQL为：
````
SELECT * FROM `lua_resty_query` WHERE `name` LIKE '%晶%'  LIMIT 1
````

## [not] BETWEEN查询

````
db:where('id',"BETWEEN",{10,200}):find() 
-- 或
db:where('id',"BETWEEN",'100,200'):find() 
-- 或
db:whereBetween('id', {100,200}):find()
````
生成的SQL为：
````
SELECT * FROM `lua_resty_query` WHERE (`id` BETWEEN '100' AND '200')  LIMIT 1
````

## [NOT] NULL查询

````
db:where('id',"NULL"):find() 
-- 或
db:whereNull('id'):find() 
````
生成的SQL为：
````
SELECT * FROM `lua_resty_query` WHERE `id` IS NULL LIMIT 1
````
not null写法:
````
db:where('id',"NOT NULL"):find() 
-- 或
db:whereNotNull('id'):find() 
````
生成的SQL为：
````
SELECT * FROM `lua_resty_query` WHERE `id` IS NOT NULL LIMIT 1
````
若需要查询`id`的值为`NULL`字符串的写法如下：
````
db:where('id',"=", "NULL"):find() 
````
生成的SQL为：
````
SELECT * FROM `lua_resty_query` WHERE `id`='NULL' LIMIT 1
````

# EXP表达式查询

> EXP表达式，即第三个参数作为sql的原生字符串的一部分，底层不做任何处理，实现一些原生SQL构造，这里要主要的是尽量使用系统提供的参数绑定机制，避免注入风险

````
db:where('id',"EXP", " IN(1,2)"):select() 
-- 或
db:whereExp('id', " IN(1,2)"):select() 
-- 注意参数前方的空格
````
生成的SQL为：
````
SELECT * FROM `lua_resty_query` WHERE `id` IN(1,2)
````
若exp字符串中有拼接变量需求，合理利用系统提供的参数绑定机制，避免注入风险：
````
local exp_val = " IN(?,?)"
exp_val = utils.db_bind_value(exp_val, {1,2})
db:where('id',"EXP", exp_val):select() 
````

# order 方法

功能：设置order排序条件

用法：

* `order('id')` 或 `order('id', 'ASC')` 按id升序排列
* `order('id', 'DESC')` 按id降序排列
* `order({'id' = 'DESC'})` 按id降序排列，数组形式参数
* `order({'id' = 'DESC', 'cid' = 'ASC'})` 按id降序同时按cid升序排列，数组形式参数

# limit 方法

功能：设置limit分页

方法原型：`limit(offset,length)` 第一个参数为偏移量，第二个参数为数据条数长度

用法：

* `limit(10)` 单个参数形式，限制查询指定参数指定数目的数据
* `limit(1,10)` int数字型参数，从偏移量开始查询
* `limit('1','10')` 支持字符串形式的整数

# page 方法

功能：自然语义设置分页

方法原型：`page(page,page_size)` 第一个参数为当前页码，第二个参数为1页数据条数

用法：

* `page(1,10)` 第一页数据，每页10条数，等价于`limit(0, 10)` 或 `limit(10)`
* `page(1)` 第一页数据，每页条数参数省略，则从配置项`page_size`中读取，默认配置值10


# group 方法

功能：设置group分组

注意：新版MySQL对于group的字段可能因模式的不同而要求不同，譬如严格模式下，group子句必须出现select中的所有字段

用法：

* `group('field1')` 单个字段分组
* `group('field1,field2')` 多个字段分组
* `group({"field1","field2"})` 支持数组形式设置多个group字段


# having 方法

功能：设置group分组的筛选条件

注意：配合group方法使用

用法：

* `having('field1 > 10')` 

# distinct 方法

功能：唯一值设置

注意：distinct用法一般用于查询不重复的某一列，多列则是多列组合的唯一，某些场景下可group代替

用法：

* `distinct(true)` 参数为true等价值则distinct，false等价值则不distinct


# lock 方法

功能：设置锁机制

用法：

* `lock(true)` 加入`FOR UPDATE`锁
* `lock('lock in share mode')` 字符串用于一些特殊的锁定要求

# data 方法

功能：设置数据方法，用于insert新增或update更新数据的设置

用法：

* `data('id', 1)` 字段与值的设置方式，两个参数
* `data({id = 1, name = "晶晶""})` 数组形式设置多个键值对，一个参数
* `data({{id = 1, name = "晶晶"}})` 二维数组形式设置批量新增的数据，多次调用后方会覆盖前方设置的批量数据

# select 方法

功能：执行select批量查询

用法：

* `select()` 执行select查询，select方法不支持任何参数

# paginate 方法

功能：分页查询数据列表

用法：

* `paginate(page, page_size, is_complex)` 获取1页最多包含`page_size`条的第`page`页数据，如果`is_complex`为true即复杂模式，则一并返回该查询的总记录数

> 3个参数均为可选参数，page默认值为1即默认查询第一页，page_size可通过配置方式设置后此处省略，is_complex模式默认为false即简单模式，查询结果不包含总数

# find 方法

功能：执行select单条数据查询

用法：

* `find()` 执行select查询1条数据，不使用任何参数形式，使用where方法设置查询条件
* `find(pri_value)` 传入唯一的标量值参数，查询单个主键的表，按该参数值的去查询对应主键的记录
* `find({pk1=va1,pk2=val2})` 数组形式的参数查询复合主键的单条记录，其中pk1、pk2为构成复合主键的字段名称，复合主键有几个就需传几个

````
local db = require "resty.query"
-- 假设user表的主键字段为id
db:name("user"):find(1)

-- 等价于
db:name("user"):where("id", 1):find()

-- 最终生成的sql均为：
select * from `prefix_user` where `id`=1 limit 1

-- 复合主键查询
db:name("complex_pk"):find({pk1="val1", pk2="val2"})

生成的SQL为：

select * from `prefix_user` where ( `pk1`='val1' AND `pk2`='val2' ) limit 1
-- 注意复合主键查询会显式添加括号，将多个复合主键字段的条件包裹起来
````

# update 方法

功能：执行update更新数据操作

用法：

* `update()` 通过`data`设置要更新的键值对，通过where系列方法设置更新条件
* `update(data)` 通过参数设置要更新的键值对，会覆盖由`data`方法设置的值

````
local db = require "resty.query"
db:name("user"):data({name='jingjing', gender=1}):where('id',1):update()

-- 等价于
db:name("user"):where('id',1):update({name='jingjing', gender=1})

生成的sql均为：
UPDATE `prefix_user` SET `name`='jingjing',`gender`='1' WHERE `id`=1

-- 支持多表关联更新
db:alias("resty_query")
    :join("resty_join", "resty_join.query_id=resty_query.id")
    :data("resty_query.user_name", "join_update_username")
    :data("resty_join.null_field", "join_update_null_field")
    :where("resty_query.id", 10)
    :update()
-- 构造的sql:
UPDATE `lua_resty_query` AS `resty_query` INNER JOIN `lua_resty_join` AS `resty_join` ON resty_join.query_id=resty_query.id SET `resty_join`.`null_field` = 'join_update_null_field' , `resty_query`.`user_name` = 'join_update_username'  WHERE `resty_query`.`id`=10

-- 多表更新不支持limit和order子句，否则会报HY000错误
````

# setField 方法

功能：快捷更新指定字段方法

用法：

* `setField(field, value)` 更新1个字段。将字段`field`更新为`value`， 通过where系列方法设置更新条件
* `setField({field1 = value1,field2 = value2})` 更新多个字段。将字段`field1`更新为`value1`同时将字段`field2`更新为`value2`， 通过where系列方法设置更新条件

````
local db = require "resty.query"

-- 更新设置1个字段
db:name("user"):where('id', 1):setField("name", "晶晶")
-- 等价于如下写法
db:name("user"):where('id', 1):date("name", "晶晶"):update()

-- 生成的sql类型如下
-- update prefix_user set name = '晶晶' where id=1

-- 更新设置多个字段
db:name("user"):where('id', 1):setField({name = "晶晶", vip =7})
-- 等价于如下写法
db:name("user"):where('id', 1):data({name = "晶晶", vip =7}):update()

-- 生成的sql类型如下
-- update prefix_user set name = '晶晶', vip = 7 where id=1
````

# increment 方法

功能：字段值自增方法

用法：

* `increment(field, step)` 通过where系列方法设置更新条件，按`step`步幅自增`field`的值
* `increment({field1 = step1, field2 = step2})` 通过where系列方法设置更新条件，一次性自增多个字段

> 注意：虽然方法名为`increment`，递增的含义，你仍然可以通过设置`step`参数为负数实现自减的效果，但这样会引起语义上的歧义，如非必要不建议如此操作！

````
local db = require "resty.query"

-- 自增1个字段
db:name("user"):where('id', 1):increment("score")
-- 下方写法等价，第二个参数为自增的步幅，默认值1
db:name("user"):where('id', 1):increment("score", 1)

-- 生成的sql类型如下
-- update prefix_user set score = score + 1 where id=1

-- 自增多个字段
db:name("user"):where('id', 1):increment({score = 1, age = 2})

-- 生成的sql类型如下
-- update prefix_user set score = score + 1,age = age + 2 where id=1
````

# decrement 方法

功能：字段值自减方法

用法：

* `decrement(field, step)` 通过where系列方法设置更新条件，按`step`步幅自减`field`的值
* `decrement({field1 = step1, field2 = step2})` 通过where系列方法设置更新条件，一次性自减多个字段

> 注意：虽然方法名为`decrement`，递减的含义，你仍然可以通过设置`step`参数为负数实现自增的效果，但这样会引起语义上的歧义，如非必要不建议如此操作！

# insert 方法

功能：执行insert方法新增1条数据

用法：

* `insert()` 通过`data`设置要新增的键值对
* `insert(data)` 通过参数设置要新增的键值对，会覆盖由`data`方法设置的值
* `insert(data, true)` 通过第二个参数给予true，使用`REPLACE`语法执行新增，若不想通过第一个参数赋值而使用data方法，则insert方法第一个参数给予一个空数组`{}`或`nil`即可

````
local db = require "resty.query"
db:name("resty_query"):data({name='jingjing', gender=1}):insert()

-- 等价于
db:name("resty_query"):insert({name='jingjing', gender=1})

生成的sql均为：
INSERT INTO `lua_resty_query` (`name`,`gender`) VALUES ('晶晶','1')

-- 还可以启用replace语法
db:name("resty_query"):insert({name='jingjing', gender=1}, true)
-- 或
db:name("resty_query"):data({name='jingjing', gender=1}):insert(nil, true)

生成的sql均为：
REPLACE INTO `lua_resty_query` (`name`,`gender`) VALUES ('晶晶','1')
````

# insertAll 方法

功能：执行insert方法批量新增多条数据

用法：

* `insertAll()` 批量数据通过`data`方法设置
* `insertAll(data)` 批量数据通过方法体参数设置，会忽略掉data方法设置的数据
* `insertAll(data, true)` 通过第二个参数给予true，使用`REPLACE`语法执行新增

````
local db = require "resty.query"

-- data参数格式
local data = {
    {name="y",sex=1},
    {name="j",sex=2}
}

db:name("user"):insertAll(data)

-- 或
db:name("user"):data(data):insertAll()
````
> 务必保证批量数据格式的字段均相一致，批量方法不宜一次性大量插入过多数据

# insertGetId 方法

功能：执行insert方法新增1条数据并返回新增数据的主键id

说明：`insertGetId` 为insert的升级方法，insert方法返回新增数据行数，`insertGetId`执行insert数据成功后返回新增数据的主键id，参数与insert相同，仅返回值有差异。

# delete 方法

功能：执行delete语句删除数据

用法：

* `delete()` 执行delete语句删除数据
* `delete(pri_key_val)` 按主键值执行删除，单主键表传标量值，多主键表使用主键字段名称为key，该字段对应的需删除的值为value构成的索引数组

````
local db = require "resty.query"

-- 假设prefix_resty_query表的主键为id
db:name("resty_query"):where("id", 1):delete()
-- 或
db:name("resty_query"):delete(1)

-- 构造的sql均为：
DELETE FROM `prefix_resty_query` WHERE `id`=1

-- 复合主键快捷删除

-- 假设lua_multi_primary表的主键字段为id,name
db:name("resty_query"):delete({id=2,name="jing"})

-- 构造的sql均为：
DELETE FROM `lua_multi_primary` WHERE ( `id`=2 AND `name`='jing' )  LIMIT 1
-- 注意构造的sql中的括号

-- 支持join多表联合删除:
local db = db:name("resty_query")
db:name("resty_query")
    :join('resty_join', "resty_join.query_id=resty_query.id")
    :where('resty_query.id', "=", 10)
    :delete()

-- 构造的sql类似
DELETE resty_query,resty_join FROM `lua_resty_query` AS `resty_query` INNER JOIN `lua_resty_join` AS `resty_join` ON resty_join.query_id=resty_query.id WHERE `resty_query`.`id`=10

-- 多表删除不支持order和limit子句
````

# count 方法

功能：获取查询语句的结果集总数，返回数字

用法：

* `count()` 获取查询语句执行后的结果总数
* `count(field)` 按`field`字段查询结果集总数

# max 方法

功能：max函数查询字段最大值

用法：

* `max(field)` 查询field字段的数字最大值
* `max(field, false)` 最大值不是一个数值时使用第二个参数false

````
local db = require "resty.query"

local max = db:max("id")

-- 构造的sql类似
SELECT MAX(`id`) AS `resty_query_max` FROM `lua_resty_query` LIMIT 1
````
> max方法仅支持字段本身的计算，若有复杂的max计算，使用fieldRaw方法，配合select或find实现

# min 方法

功能：min函数查询字段最小值

用法：

* `min(field)` 查询field字段的数字最小值
* `min(field, false)` 最小值不是一个数值时使用第二个参数false

````
local db = require "resty.query"

local max = db:min("id")

-- 构造的sql类似
SELECT MIN(`id`) AS `resty_query_max` FROM `lua_resty_query` LIMIT 1
````
> min方法仅支持字段本身的计算，若有复杂的min计算，使用fieldRaw方法，配合select或find实现

# avg 方法

功能：avg函数查询字段平均值，返回数字

用法：

* `avg(field)` 查询field字段的数字平均值

````
local db = require "resty.query"

local max = db:avg("id")

-- 构造的sql类似
SELECT AVG(`id`) AS `resty_query_max` FROM `lua_resty_query` LIMIT 1
````

> avg方法仅支持字段本身的计算，若有复杂的avg计算，使用fieldRaw方法，配合select或find实现

# sum 方法

功能：sum函数查询字段累加值，返回数字

用法：

* `sum(field)` 查询field字段的数字累加值

````
local db = require "resty.query"

local max = db:sum("id")

-- 构造的sql类似
SELECT SUM(`id`) AS `resty_query_max` FROM `lua_resty_query` LIMIT 1
````

> sum方法仅支持字段本身的计算，若有复杂的sum计算，使用fieldRaw方法，配合select或find实现

# transaction 方法

功能：事务闭包方法，闭包内执行事务

用法：

* `transaction(callable)`  回调函数闭包内执行事务

> callable为一个闭包函数，函数的唯一参数为1个新的query对象，此方法是优先推荐使用的！

> callable中若需回滚事务，则使用`error`方法抛出1个异常即可，若没有异常则callable方法体执行完毕后事务提交

# transaction 事务组方法

> 下方3个方法需配合使用，且需自主实现`pcall`机制的异常抛出和捕获以及事务提交、回滚的逻辑

## startTrans 方法

开启1个事务

## commit 方法

提交1个事务

## rollback 方法

回滚1个事务

+++

使用范例：

````
local db = query:new():table("table")

db:startTrans()

-- your trans code

-- commit
db:commit()

-- or rollback
db:rollback()

````

最佳实践：

````
local db = query:new():table("table")
-- 或
-- local db = query:name("table")

-- 开启事务
db:startTrans()

-- 闭包pcall异常保护执行代码
if ok,result = pcall(function () 
    -- your code
    
end, db)

if not ok then
    -- 闭包事务执行出错，回滚
    db:rollback()
else
    -- 闭包事务执行成功，提交
    db:commit()
end

````

# getFields 方法

功能：获取当前表的所有字段信息数组

用法：

* `getFields()` 

````
local db = query:name("table")

db:getFields()

-- 返回类似如下结构
{
    id = {
		"not_null" = true,
		"primary" = true,
		"auto_increment" = true,
		"default" = userdata: NULL,
		"type" = "int(11)",
	},
	name = {
		"not_null" = true,
		"primary" = false,
		"auto_increment" = false,
		"default" = "",
		"type" = "varchar(32)",
	},
}
````

# getPrimaryField 方法

功能：获取当前表的主键字段名称

用法：

* `getPrimaryField()` 

````
local db = query:name("table")

db:getPrimaryField()

-- 返回主键字段名称，譬如 id， 若表并未设置主键字段，则返回空字符串
-- 若表为一个复合主键表，则返回一个索引数组
````

# reset 方法

功能：重置query对象，避免上一次执行后的数据污染

用法：

* `reset()` 

> 正常情况下，无需主动调用该方法，底层会自动执行清理，此方法为`removeOptions()`无参数方法的的别名

# destruct 方法

功能：显式析构，回收至co-socket连接池的方法，一般建议在使用完query对象之后，确认后续不再使用该query时调用该方法

用法：

* `destruct()` 显式析构，释放底层连接至连接池

> 此方法为`close`方法的别名，调用任意一者即可，不能同时调用


# fetchSql 方法

功能：开发调试，用于生成拟执行的SQL语句

用法：

* `fetchSql(is_fetch)` 

> 其中`is_fetch`为布尔值，true则返回拟执行的sql字符串，false则无影响，默认值true

````
local db  = query:name("table")
local sql = db:where('id', 1):fetchSql():find()
-- 等价于
local sql = db:where('id', 1):fetchSql(true):find()

-- sql的值类似如下：
-- select * from prefix_table where id=1
````

# getLastSql 方法

功能：开发调试，用于返回调用位置处最后一次执行的SQL语句

用法：

* `getLastSql()` 获取最后执行的sql语句
