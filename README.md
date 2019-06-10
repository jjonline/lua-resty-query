# new方法

功能：设置需要操作的数据表

用法：

* `query:new(config)` 实例化query对象并设置连接配置

> 其中config为固定结构的table数组

config结构

````
{
    host      = "127.0.0.1",
    port      = 3306,
    database  = "",
    username  = "",
    password  = "",
    charset   = 'utf8mb4',
    collation = 'utf8mb4_general_ci',
    prefix    = "",
    strict    = true,
    engine    = nil,
    page_size = 10,
}
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
| EXP | 表达式查询 |`where('field','EXP', 'IN (1,2)')`|

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
* `whereExp('table.field','IN (1,2)')` 快捷`EXP`查询

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
* `group('sum(field3)')` 支持聚合函数


# having 方法

功能：设置group分组的筛选条件

注意：配合group方法使用

用法：

* `group('field1 > 10')` 

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
* `order({id = 1, name = "晶晶""})` 数组形式设置多个键值对，一个参数

# select 方法

功能：执行select批量查询

用法：

* `select()` 执行select查询，select方法不支持任何参数

# find 方法

功能：执行select单条数据查询

用法：

* `find()` 执行select查询，find方法不支持任何参数

# update 方法

功能：执行update更新数据操作

用法：

* `update()` 通过`data`设置要更新的键值对，通过where系列方法设置更新条件
* `update(data)` 通过参数设置要更新的键值对，会覆盖由`data`方法设置的值

# insert 方法

功能：执行insert方法新增1条数据

用法：

* `insert()` 通过`data`设置要新增的键值对
* `insert(data)` 通过参数设置要新增的键值对，会覆盖由`data`方法设置的值
* `insert(data, true)` 通过第二个参数给予true，使用`REPLACE`语法执行新增，若不想通过第一个参数赋值，给予一个空数组`{}`即可
