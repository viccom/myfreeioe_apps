local serial = require 'serialdriver'
local basexx = require 'basexx'
local sapp = require 'app.base'
local device_model = require 'devices.RemoDAQ'
local NumConvert = require 'devices.NumConvert'
-- local device_outputs = require 'RemoDAQ.outputs'
local cjson = require 'cjson.safe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = sapp:subclass("RemoDAQ_MONITOR_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

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
	self._log:debug("RemoDAQ monitor application initlized")

	conf.down = conf.down or {
		port = "/dev/ttymxc0",
		--port = "/tmp/ttyS1",
		baudrate = 19200,
		data_bits = 8,
		parity = "NONE",
		stop_bits = 1,
		flow_control = "OFF"
	}
	conf.up = conf.up or {
		port = "/dev/ttymxc1",
		--port = "/tmp/ttyS2",
		baudrate = 19200,
		data_bits = 8,
		parity = "NONE",
		stop_bits = 1,
		flow_control = "OFF"
	}
	self._up_stream_buffer = ''
	self._down_stream_buffer = ''
    self._skip_up = false
    self._devsconf = conf.devs
end

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._sys:gen_sn("hash_key_here_serial")

	local appmeta = self._api:default_meta()
	appmeta.name = "RemoDAQ"
	appmeta.manufacturer = "北京集智达智能科技有限责任公司"
	appmeta.description = "北京集智达智能科技有限责任公司RemoDAQ"
    self._dev = self._api:add_device(sn, appmeta, {}, {}, {})
	-- local inputs = {}
	-- local outputs = {}
	local  commands = {}
-- 	commands = {
-- 		{
-- 			name = "force_read",
-- 			desc = "屏蔽HMI，并发起读取指令"
-- 		}
-- 	}
   
    self._devs ={}
    
    for _, v in ipairs(self._devsconf) do
        local sn = sys_id.."."..self._name.."."..v.addr
        local model = device_model[v.model]
        local meta = self._api:default_meta()
        if v.model == "8018" then
            meta.inst = v.name
            meta.name = model.meta.name
            meta.manufacturer = model.meta.manufacturer
            meta.description = model.meta.description
            local inputs = {}
            for i = 1, model.channel, 1 do
                local newtag = {
                    name = "channel_" .. i,
                    desc = "channel_" .. i,
                    vt = 'float'
                }
                inputs[#inputs + 1] = newtag
            end
            self._devs[v.addr] = self._api:add_device(sn, meta, inputs, {}, commands)
        end
        
        if v.model == "8060" then
            meta.inst = v.name
            meta.name = model.meta.name
            meta.manufacturer = model.meta.manufacturer
            meta.description = model.meta.description
            local inputs = {}
            local outputs = {}
            for i = 1, model.channel/2, 1 do
                local newtag = {
                    name = "di_" .. i,
                    desc = "di_" .. i,
                    vt = 'int'
                }
                inputs[#inputs + 1] = newtag
            end
            for i = 1, model.channel/2, 1 do
                local newtag = {
                    name = "do_" .. i,
                    desc = "do_" .. i,
                    vt = 'int'
                }
                inputs[#inputs + 1] = newtag
                outputs[#outputs + 1] = newtag
            end
            

            
            self._devs[v.addr] = self._api:add_device(sn, meta, inputs, outputs, commands)
        end
	end

	local down_conf = self._conf.down
	local up_conf = self._conf.up

	--local port = serial:new("/tmp/ttyS10", 9600, 8, "NONE", 1, "OFF")

	local down_port = serial:new(down_conf.port,
								 down_conf.baudrate,
								 down_conf.data_bits,
								 down_conf.parity, 
								 down_conf.stop_bits, 
								 down_conf.flow_control)
	local r, err = down_port:open()
	if not r then
		self._log:warning("Failed open port["..down_conf.port.."] error: "..err)
		return nil, err
	end

	local up_port = serial:new(up_conf.port,
							   up_conf.baudrate,
							   up_conf.data_bits,
							   up_conf.parity, 
							   up_conf.stop_bits, 
							   up_conf.flow_control)
	local r, err = up_port:open()
	if not r then
		self._log:warning("Failed open port["..up_conf.port.."] error: "..err)
		return nil, err
	end


	down_port:start(function(data, err)
		-- Recevied Data here
		if data then
-- 			self._log:debug("DownPort Recevied data::", basexx.to_hex(data))
			self._dev:dump_comm("DEV-IN", data)
			if self._up_port and not self._skip_up then
				self._dev:dump_comm("PC-OUT", data)
				self._up_port:write(data)
			end
			self._sys:post('stream_from_down', data)
		else
			self._log:error(err)
			--- TODO:
			self:on_close()
			self._sys:exit()
		end
	end)
	self._down_port = down_port

	up_port:start(function(data, err)
		-- Recevied Data here
		if data then
-- 			self._log:debug("UpPort Recevied data::", basexx.to_hex(data))
			self._dev:dump_comm("PC-IN", data)
			if self._skip_up then
				self._log:warning("Commands from PC skipped as requested")
				return
			end
			if self._down_port then
				self._dev:dump_comm("DEV-OUT", data)
				self._down_port:write(data)
			end
			self._sys:post('stream_from_up', data)
		else
			self._log:error(err)
			--- TODO:
			self:on_close()
			self._sys:exit()
		end
	end)
	self._up_port = up_port
	
	return true
end

--- 应用退出函数
function app:on_close(reason)
	if self._up_port then
		self._up_port:close(reason)
		self._up_port = nil
	end
	if self._down_port then
		self._down_port:close(reason)
		self._down_port = nil
	end
end

--- 应用运行入口
function app:on_run(tms)
	return 10000 --下一采集周期为10秒
end

function app:on_post_stream_from_up(stream)
-- 	if self._working_cmd and self._working_cmd.name ~= 'laser' then
-- 		local cmd = self._working_cmd
-- 		local cmd_time = self._working_cmd_time

-- 		if cmd.decode_mode == 0 then
-- 			local content = self._down_stream_buffer
-- 			self._dev:dump_comm("DEV-PACKET", content)
-- 			self._dev:set_input_prop(cmd.name, 'value', conent, cmd_time, 0)
-- 		else
-- 			self._log:warning(string.format("CMD[%s] timeout!!", cmd.name))
-- 		end

-- 		self._working_cmd = nil
-- 		self._down_stream_buffer = ''
-- 	end

	--self._log:trace("PC Sending stream",basexx.to_hex(stream))
	self._up_stream_buffer = self._up_stream_buffer..stream
	local buf = self._up_stream_buffer
-- 	self._log:trace("PC Sending xxxxxxxxxxxx",basexx.to_hex(buf))
	
	local cmd = string.match(buf, "[#@]([^\r#@]+)\r")
-- 	self._log:trace("PC Sending buffffffff", cmd or 'N/A', '||||', buf)
	if cmd then
-- 		self._log:trace("PC Sending command", cmd)
		--- Clean all buffers
		self._up_stream_buffer = ''
		self._down_stream_buffer = ''
		self._working_cmd = nil

		for _, v in ipairs(self._devsconf) do
			if v.addr == cmd then
				--self._log:trace("Finded supported command", cjson.encode(v))
				self._working_cmd = v
				self._working_cmd_time = self._sys:time()
			end
        end
	end
	if string.len(self._up_stream_buffer) > 256 then
		self._up_stream_buffer = ''
	end
end

function app:on_output(app, sn, output, prop, value)
    self._log:trace("output::", sn, output, prop, value)
	if value ~= nil then
	    if self._skip_up then
	        return false, "Is Writing!!!!!!!"
	    end
	    
	    local sys_id = self._sys:id()
    	local inst_name = self._name
        local dev_addr = nil
        for _, v in ipairs(self._devsconf) do
            local snstr = sys_id.."."..inst_name.."."..v.addr
            
            if sn==snstr then
                dev_addr = v.addr
            end
        end

        if not dev_addr then
            return
        end

	    self._skip_up = true
	--- Sleep 5 seconds to make sure there is no data on serial
	    self._sys:sleep(1000)
	    local channel_num = tonumber(string.sub(output, 4, 4)) - 1
	    assert(channel_num >= 0 and channel_num <= 3)
	    
    	local r, err = self:force_read_cmd('@'.. dev_addr ..'\r', function(result, err)
    	    if not result then
    	        return false, "Read registers failed!!!"
    	    end
    	    --- 
    	    
    	    local val = string.unpack('<I1',basexx.from_hex(result))
    	   -- self._log:trace("output write::", val, value, channel_num)
    	    if tonumber(value) == 1 then
                val = val | (value << channel_num)
    	    else
    	        val = val & (0xF ~ (1 << channel_num) )
    	    end

    	    local val_str = string.format('%X',val)

    	    val_str = string.sub(val_str, -1)
    	   -- self._log:trace("output write::", '@'.. dev_addr ..val_str..'\r')
    	    ----
            return self:force_read_cmd('@'..dev_addr..val_str..'\r', function(result, err)
                self._skip_up = false
                if result then
                    --- TODO
                    
                    return true
                else
                    return false
                end
                -- process data
            end)
    	end)
    	if not r then
    	    self._skip_up = false
    	    return nil, err
    	end
    	
	    return self:force_read_cmd('@'.. dev_addr ..'\r', function(result, err)
    	    self._skip_up = false
    	    return result, err
	    end)
	end
	return false, "unknown command"
end

function app:force_read_cmd(force_read_cmd, process_cb)
	self._log:trace("FreeIOE sending force_read command")

	if not self._down_port then
		return false, "Device connection port not opened!"
	end
	
	
	--- Set proper command
	for _, v in ipairs(self._devsconf) do
		if '@'.. v.addr ..'\r' == force_read_cmd then
			--self._log:trace("Finded supported command", cjson.encode(v))
			self._working_cmd = v
			self._working_cmd_time = self._sys:time()
		end
    end

	self._dev:dump_comm("DEV-OUT", force_read_cmd)

	-- Request
	self._force_read_cmd = {}
	self._down_port:write(force_read_cmd)

    self._sys:sleep(3000, self._force_read_cmd)
	self._force_read_cmd = nil
    
    if self._force_read_result then
        return process_cb(self._force_read_result)
    else
        return process_cb(false, "Not register readded")
    end
end

function app:on_post_stream_from_down(stream)
	local cmd = self._working_cmd
	if cmd and stream then
		self._down_stream_buffer = self._down_stream_buffer .. stream


        local buf = self._down_stream_buffer
        
        if cmd.model == "8018" then
            local str = string.match(buf, "[>]([^\r]+)\r")
            -- self._log:trace("Device receive bufffffer",str)
            
            if str then
                -- self._log:trace("Finding supported command result", str)
                local value = {}
                for v in string.gmatch(str, "([%+%-][%d%.]+)") do
                    value[#value + 1] = tonumber(v)
                    -- self._log:trace(tonumber(v))
                end
    
                if #value>1 then
                    --self._log:trace("Got command result", value)
                    self._dev:dump_comm("DEV-PACKET", buf)
                    -- self._log:trace("setvalue", cjson.encode(cmd))
                    local dev = self._devs[cmd.addr]
                    for i, v in ipairs(value) do
                        dev:set_input_prop('channel_'..i, 'value', v)
                    end

                    self._working_cmd = nil
                    self._down_stream_buffer = ''
                end
                

            end
        end
        
        if cmd.model == "8060" then
            local str = string.match(buf, "[>]([^\r]+)\r")
            -- self._log:trace("Device receive bufffffer",str)
            
            if str then
                -- self._log:trace("Finding supported command result", str)
                self._dev:dump_comm("DEV-PACKET", buf)
                
                local dev = self._devs[cmd.addr]
                
                local dostr = string.sub(str, 1, 2)
                local donum = string.unpack('<I1', basexx.from_hex(dostr))
                local dodatastr =  string.reverse(NumConvert.ConvertDec2X(donum, 2))
                if (#dodatastr ~= 4) then
                    dodatastr = dodatastr..string.rep('0', (4-#dodatastr))
                end
                for i = 1, 4, 1 do
                    local _val = tonumber(string.sub(dodatastr, i, i))
                    dev:set_input_prop('do_'..i, 'value', _val)
                end


                
                local distr = string.sub(str, 3, 4)
                local dinum = string.unpack('<I1', basexx.from_hex(distr))
                local didatastr =  string.reverse(NumConvert.ConvertDec2X(dinum, 2))
                if (#didatastr ~= 4) then
                    didatastr = didatastr..string.rep('0', (4-#didatastr))
                end
                for i = 1, 4, 1 do
                    local _val = tonumber(string.sub(didatastr, i, i))
                    dev:set_input_prop('di_'..i, 'value', _val)
                end
                -- self._log:trace("8060 receive ",didatastr)
                
                self._working_cmd = nil
                self._down_stream_buffer = ''
                
                if self._force_read_cmd then
                    self._force_read_result = str
                    self._sys:wakeup(self._force_read_cmd)
                end
            end
        end


		if string.len(self._down_stream_buffer) > 256 then
			self._down_stream_buffer = ''
		end
	end
end

--- 返回应用对象
return app
