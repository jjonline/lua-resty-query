---
--- OOP实现
---
local getmetatable = getmetatable
local setmetatable = setmetatable

-- 实例化1个class
-- @param mixed class名称，
-- @param mixed ... 可变参数，作为被实例化对象的__construct方法调用的参数
local function _instance(class, ...)
    local inst = setmetatable({__class=class}, {__index = class})
    if inst.__construct then
        inst:__construct(...)
    end
    return inst
end

-- 创建1个对象类
-- @param mixed 可选的父类、基类
local function class(base)
    return setmetatable({__parent = base}, {
        __call = _instance,
        __index = base
    })
end

-- 检查对象是否为某类的实例
-- @param object 对象实例，其实就是一个table
-- @param class_name 基础的class类
-- @return Boolean
local function instanceof(object, class_name)
    local meta = getmetatable(object)
    while meta and meta.__index do
        if meta.__index == class_name then
            return true
        end
        meta = getmetatable(meta.__index)
    end
    return false
end

-- 暴露的方法
return {
    class = class,
    instanceof = instanceof,
}
