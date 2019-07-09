local class = require 'middleclass'
--- 导入需要的模块
local socketchannel = require 'socketchannel'
local serialchannel = require 'serialchannel'
local sum = require 'hashings.sum'
local basexx = require 'basexx'


--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("Dev_Simulator_App")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1

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
    local devscfg = require 'userlib.conf'

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
        channel_type = 'serial'
    }
    -- self._log:notice(config["dev"][1])
    local plcxx = {}
    if (config.dev) then
        for i,sn in ipairs(config.dev) do
            --- 根据PLC配置信息添加采集项
            local inputs = {}
            for i,v in ipairs(devscfg.inputs) do
                table.insert (inputs, v)
            end
            --- 生成设备的序列号，要求全局唯一
            local dev_sn = sys_id.."."..sn
            --- 生成设备对象
            local meta = self._api:default_meta()
            meta.name = devscfg.meta.name
            meta.description = devscfg.meta.description
            meta.series = devscfg.meta.series
            
            local plcdev = self._api:add_device(dev_sn, meta,  inputs)
            local plcobj = {}
            plcobj["dev"] = plcdev
            plcobj["conf"] = devscfg.inputs
            table.insert(plcxx, plcobj)
        end
    end

    --- 设定通讯口数据回调
    self._plcxx = plcxx

    return true
end

--- 应用退出函数
function app:close(reason)
    self._log:notice(self._name, reason)
end

--- 应用运行入口
function app:run(tms)
    --self._log:notice(self._name, " Start!")
    local plcxx = self._plcxx
    for i,plc in ipairs(plcxx) do
        local dev = plc.dev
        local conf = plc.conf
        for i,v in ipairs(conf) do
            local now = self._sys:time()
            dev:set_input_prop(v.name, "value", math.random(1,100), now, 0)
        end
    end
    --self._log:notice(self._name, " End!")
-- 分割线----------------------------------------

    --- 循环周期
    return 1000
end

--- 返回应用对象
return app
