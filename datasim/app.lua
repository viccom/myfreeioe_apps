local class = require 'middleclass'
--- 导入需要的模块
local cjson = require 'cjson'


--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("Dev_Simulator_App")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1


function random(n, m)
    math.randomseed(os.clock()*math.random(1000000,90000000)+math.random(1000000,90000000))
    return math.random(n, m)
end

function randomNumber(len)
    local rt = ""
    for i=1,len,1 do
        if i == 1 then
            rt = rt..random(1,9)
        else
            rt = rt..random(0,9)
        end
    end
    return rt
end

function randomLetter(len)
    local rt = ""
    for i = 1, len, 1 do
        rt = rt..string.char(random(97,122))
    end
    return rt
end

local datatype_map = {"int","float","string"}

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
    self._name = name
    self._sys = sys
    self._conf = conf
    --- 获取数据接口
    self._api = sys:data_api()
    --- 获取日志接口
    self._log = sys:logger()
    self._log:notice(name.." Application initlized") 
end

--- 应用启动函数
function app:start()
    --- 加载设备配置信息（设备参数，点信息等）
    -- local devscfg = require 'userlib.conf'

    --- 设定回调处理函数(目前此应用只做数据采集)
    self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			self._log:notice('on_output', app, sn, output, prop, value)
			return true, "done"
		end,
		on_ctrl = function(app, sn, command, param, ...)
			self._log:notice('on_ctrl', app, sn ,command, param, ...)
		end,
    })

    ---获取设备序列号和应用配置
    local sys_id = self._sys:id()
    local config = self._conf or {
        dev = {name="simulator", desc="simulator", sn = 'x1x1x1x1x1', tagnum = 5, datatype = "0"}
    }
    self._cycle = 1
    if self._conf.cycle ~= nil then
        if math.tointeger( tonumber(self._conf.cycle)) > 0 then
            self._cycle = math.tointeger( tonumber(self._conf.cycle))
        end
    end
    -- self._log:notice("config::::::::::",cjson.encode(config))
    local sims = {}
    if (config.dev ~= nil) then
        for i,dev in pairs(config.dev) do
            --- 根据配置信息添加采集项
            local inputs = {}
            local datatype = math.tointeger( tonumber(dev.datatype or "1") )
            if datatype < 1 or datatype > 3 then
                datatype = 1
            end
            
            if datatype == 1 then
                for i = 1, dev.tagnum, 1 do
                    local newtag = {
        				name = "int_" .. i,
        				desc = "int_" .. i,
        				vt = datatype_map[datatype]
        			    }
    			    inputs[#inputs + 1] = newtag
                end
            end
            if datatype == 2 then
                for i = 1, dev.tagnum, 1 do
                    local newtag = {
        				name = "float_" .. i,
        				desc = "float_" .. i,
        				vt = datatype_map[datatype]
        			    }
    			    inputs[#inputs + 1] = newtag
                end
            end
            if datatype == 3 then
                for i = 1, dev.tagnum, 1 do
                    local newtag = {
        				name = "str_" .. i,
        				desc = "str_" .. i,
        				vt = datatype_map[datatype]
        			    }
    			    inputs[#inputs + 1] = newtag
                end
            end
            --- 生成设备的序列号，要求全局唯一
            local dev_sn = sys_id..'.'..self._name.."."..dev.sn
            --- 生成设备对象
            local meta = self._api:default_meta()
            meta.name = dev.name
            meta.description = dev.desc
            meta.series = "simulator"
            
            local simdev = self._api:add_device(dev_sn, meta,  inputs)
            local devobj = {}
            devobj["dev_sn"] = dev.sn
            devobj["dev"] = simdev
            devobj["inputs"] = inputs
            table.insert(sims, devobj)
        end
    end

    --- 设定通讯口数据回调
    self._sims = sims

    return true
end

--- 应用退出函数
function app:close(reason)
    self._log:notice(self._name, reason)
end

--- 应用运行入口
function app:run(tms)
    --self._log:notice(self._name, " Start!")
    local sims = self._sims
    for i,sim in ipairs(sims) do
        local now = self._sys:time()
        local dev_sn = sim.dev_sn
        local dev = sim.dev
        local inputs = sim.inputs
        dev:dump_comm('INPUT-OUT', randomLetter(10))
        
        for _,v in ipairs(inputs) do
            local value = 0
            if v.vt == "int" then
                value = math.random(1,100)
            end
            if v.vt == "float" then
                value = math.random(1,10000)/math.random(1,10)
            end
            if v.vt == "string" then
                value = randomLetter(10)
            end
            dev:set_input_prop(v.name, "value", value, now, 0)
        end
        dev:dump_comm('INPUT-IN', randomLetter(10))
    end
    --self._log:notice(self._name, " End!")
-- 分割线----------------------------------------

    --- 循环周期
    return self._cycle * 1000
end

--- 返回应用对象
return app