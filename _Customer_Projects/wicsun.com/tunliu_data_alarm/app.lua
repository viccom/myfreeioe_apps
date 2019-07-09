local class = require 'middleclass'
local datacenter = require 'skynet.datacenter'
local cjson = require 'cjson.safe'
local csv_tpl = require 'userlib.csv_tpl'
local event = require 'app.event'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("tunliu_data_alarm")
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
	self._api = self._sys:data_api()
	self._log = sys:logger()

end

function app:start()
	local sys = self._sys
    local log = self._log    
	local sys_id = self._sys:id()
	
	csv_tpl.init(self._sys:app_dir())
	local alarms, err = csv_tpl.load_tpl("data_alarm")
	
	local _alarm_points = {}
	local _alarm_timers = {}
	local _alarmed_points = {}
	
	if not alarms then
		self._log:error("loading csv tpl failed", err)
	else
-- 		self._log:info(cjson.encode(alarms))
		for m, n in ipairs(alarms) do
            if string.upper(n.gatesn) == string.upper(sys_id) then
                table.insert(_alarm_points, n)
            end
        end
	end

-- 	self._log:info(cjson.encode(_points))
	
	self._log:info("!!!!!!!!!!!")
	self._api:set_handler({
		on_input = function(app, sn, input, prop, value, timestamp, quality)
		    
            for k, v in ipairs(_alarm_points) do
                if string.upper(v.devicesn) == string.upper(sn) and string.upper(v.tagname) == string.upper(input) then
                    -- 	self._log:info(input,value, "1限值：", v.threshold)
                    
                    -- 模拟量报警触发 start
                    if v.tagvt == "AI" then
                        if value < v.threshold then
                		    self._log:info(input,value, "2限值：", v.threshold)
            				if not _alarmed_points[input] and not _alarm_timers[input] then
            				        self._log:info("3", input,value)
            					_alarm_timers[input] = sys:cancelable_timeout(1000, function()
            				        self._log:info("5", input,value)
            						_alarm_timers[input] = nil
            						_alarmed_points[input] = true
    
                                    local event_info = {
                                        info = "低限报警",
                                        name = v.tagname,
                                        desc = v.tagdesc,
                                        value = value,
                                        lowlimit = v.threshold,
                                        time = timestamp,
                                        quality =quality
                                    }
            				 		sys:fire_event(sn, event.LEVEL_WARNING, event.EVENT_DATA, "数据越限报警", event_info)
            				        self._log:info("alarm!alarm!", input,value)
            					end)
            				end
            			else
            			    if _alarmed_points[input] then
            			                local event_info = {
                                            info = "恢复正常",
                                            name = v.tagname,
                                            desc = v.tagdesc,
                                            value = value,
                                            lowlimit = v.threshold,
                                            time = timestamp,
                                            quality =quality
                                        }
            			        sys:fire_event(sn, event.LEVEL_WARNING, event.EVENT_DATA, "数据恢复正常", event_info)
            			    end
            				_alarmed_points[input] = nil
            				if _alarm_timers[input] then
            				    self._log:info("4", input,value)
            					_alarm_timers[input]()
            					_alarm_timers[input] = nil
            				end
                		end
                    end

                    -- 模拟量报警触发 end
                
                    -- 开关量报警触发 start
                    if v.tagvt == "DI" then
                        if v.tagvt == "DI" and value == v.threshold then
                		    self._log:info(input,value, "20限值：", v.threshold)
            				if not _alarmed_points[input] and not _alarm_timers[input] then
            					_alarm_timers[input] = sys:cancelable_timeout(1000, function()
            						_alarm_timers[input] = nil
            						_alarmed_points[input] = true
    
                                    local event_info = {
                                        info = "开关量报警",
                                        name = v.tagname,
                                        desc = v.tagdesc,
                                        value = value,
                                        alarmtrigger = v.threshold,
                                        time = timestamp,
                                        quality =quality
                                    }
            				 		sys:fire_event(sn, event.LEVEL_WARNING, event.EVENT_DATA, "开关报警", event_info)
            					end)
            				end
            			else
            			    if _alarmed_points[input] then
            			                local event_info = {
                                            info = "开关量恢复正常",
                                            name = v.tagname,
                                            desc = v.tagdesc,
                                            value = value,
                                            alarmtrigger = v.threshold,
                                            time = timestamp,
                                            quality =quality
                                        }
            			        sys:fire_event(sn, event.LEVEL_WARNING, event.EVENT_DATA, "开关报警恢复正常", event_info)
            			    end
            				_alarmed_points[input] = nil
            				if _alarm_timers[input] then
            				    self._log:info("4", input,value)
            					_alarm_timers[input]()
            					_alarm_timers[input] = nil
            				end
                		end
                        
                    end
                    -- 开关量报警触发 end
                
                end
                
            end


		end,
	}, true)

	self._alarm_points = _alarm_points
	self._alarm_timers = _alarm_timers
	self._alarmed = _alarmed_points
	
	return true
end



function app:close(reason)
	--print(self._name, reason)
end

function app:run(tms)
	--connect_proc()

--     local event_info = {
--         info = "低限报警",
--         name = 'D15',
--         desc = '实时二回压',
--         value = 42,
--         time = self._sys:time(),
--         quality = 0
--     }
--  	self._sys:fire_event('2-30002-001824-00647.tunliu_delta_ccd.1', event.LEVEL_WARNING, event.EVENT_DATA, "数据越限报警", event_info)

	return 1000 * 5
end

return app