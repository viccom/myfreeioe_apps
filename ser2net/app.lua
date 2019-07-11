local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local services = require 'utils.services'
local inifile = require 'inifile'
local cjson = require 'cjson'
local restful = require 'restful'
local log = require 'utils.log'
local com_table = require 'userlib.model'
local app = class("ser2net_CLASS")

app.API_VER = 4

function trim(input)
	return (string.gsub(input, "^%s*(.-)%s*$", "%1"))
end


function app:initialize(name, sys, conf)
	if conf == nil then
		conf = require 'userlib.config'
	else
		if next(conf) == nil then
			conf = require 'userlib.config'
		end
	end

	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = self._sys:data_api()
	self._log = sys:logger()

	local id = sys:id()
	local model_number =  string.sub( id, 1, 6)
    if model_number == "2-3000" then
        model_number =  string.sub( id, 1, 7)
    end
	local ser2net_bin = sys:app_dir().."bin/ser2net"
	sysinfo.exec("chmod +x "..ser2net_bin)
	
    
	local ser2net_services = {}
	if com_table[model_number] ~=nil then
	    self._log:error("info:", cjson.encode(com_table[model_number]))
		for k,v in pairs(com_table[model_number]) do
			--local tag = string.sub(v.name,#v.name-6,-4)
			self._log:error("xxxxxxxinfoxxxxx:", k ,v)
			local ser2net_conf = sys:app_dir()..k..".ser2net.conf"
			self._log:error("ser2net_conf:", ser2net_conf)
			ser2net_services[k] = services:new(k.."_ser2net", ser2net_bin, {'-d -c', ser2net_conf})
		end
	end
	self._ser2net_services = ser2net_services
	
end

function app:start()
	local sys = self._sys
	local id = sys:id()
	local model_number =  string.sub( id, 1, 6)
    if model_number == "2-3000" then
        model_number =  string.sub( id, 1, 7)
    end
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			self._log:trace('on_output', app, sn, output, prop, value)
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end

			
			if output == 'serial_start' then
				self._log:trace('serial_start, value:', value)
				local comconf = nil
				
				if type(value) ~= 'table' then
					comconf, err = cjson.decode(value)
				end
				if comconf ~= nil then
				    local dest_com = comconf.serial	
                	self._sys:post('service_ctrl', 'start', dest_com)
			-- 		self._log:info("+++++++++++++++++++++++++++++++++++++++++++++++++++++++get_status")
					self._sys:timeout(1000, function()	self:set_services_status() end)
			        return true, "successful"
			    else
			        return false, "failure"
                end
			end
			
			if output == 'serial_stop' then
				self._log:trace('serial_stop, value:', value)
				local comconf = nil
				
				if type(value) ~= 'table' then
					comconf, err = cjson.decode(value)
				end
				if comconf ~= nil then
				    local dest_com = comconf.serial	
                	self._sys:post('service_ctrl', 'stop', dest_com)
			-- 		self._log:info("+++++++++++++++++++++++++++++++++++++++++++++++++++++++get_status")
					self._sys:timeout(1000, function()	self:set_services_status() end)
			        return true, "successful"
			    else
			        return false, "failure"
                end
			end			

			if output == 'serial_config' then
				self._log:trace('serial_config, value:', value)
				local comconf = nil
				
				if type(value) ~= 'table' then
					comconf, err = cjson.decode(value)
				end
				
				if comconf ~= nil then
    				
    				if com_table[model_number]~=nil then
    					
    					if com_table[model_number][comconf.serial]~=nil then
    						self._log:info('dest serial:', com_table[model_number][comconf.serial]['name'])
    						local dest_com = comconf.serial						
    						local baudrate = comconf.baudrate or '9600'
    						local databit = comconf.databit or '8'
    						local stopbit = comconf.stopbit or '1'
    						local parity = comconf.parity or "NONE"
    						
    						local ser2net_conf = sys:app_dir()..dest_com..".ser2net.conf"
    						local ser2net_args = com_table[model_number][comconf.serial]['port']..':raw:600:/dev/'..com_table[model_number][comconf.serial]['name']..':' .. baudrate..' '.. parity..' '.. stopbit..'STOPBIT'..' '.. databit..'DATABITS' ..' -XONXOFF LOCAL -RTSCTS'
    						local r, err = sysinfo.exec("echo "..ser2net_args.." > "..ser2net_conf)
    						if not r then
    							self._log:error("Error:", err)
    							return nil, "Error: "..err
    						end
                            self._dev:set_input_prop_emergency(dest_com .. "_tcpport", 'value', com_table[model_number][dest_com]['port'])
            				self._dev:set_input_prop_emergency(dest_com .. '_parameter', 'value', cjson.encode(comconf))

    				        self._sys:post('service_ctrl', 'restart', dest_com)
    						
    				-- 		self._log:info("+++++++++++++++++++++++++++++++++++++++++++++++++++++++get_status")
    						self._sys:timeout(1000, function()	self:set_services_status() end)
    				        return true, "successful"
    						
    						
    					else
    						self._dev:set_input_prop('applog', 'value', comconf.serial..' is nonexistent')
    						return false, comconf.serial..' is nonexistent'
    					end				
    
    				end
				
				else
				    	self._log:error('Incorrect configuration value found, value:', value)
						return false, "Incorrect configuration value found"
				end
				
				return true
			end

			return true, "done"
		end,

		on_command = function(app, sn, command, param)
			self._log:trace('on_command', app, command, param)
			
		end,

	})

	local dev_sn = self._sys:id()..'.'..self._name
	local inputs = {
		{
			name = "app_log",
			desc = "freeioe_ser2net tips",
			vt = "string",
		},
		{
			name = "starttime",
			desc = "freeioe_ser2net start time in UTC",
			vt = "int",
		},
	}

	
	if com_table[model_number] ~=nil then
		for k,v in pairs(com_table[model_number]) do
			local tag_com = {
				name = k .. "_tcpport",
				desc = k .. "_tcpport",
				vt = "string"
			}
			inputs[#inputs + 1] = tag_com

			local tag_com_config = {
				name = k .. "_parameter",
				desc = k .. "_parameter",
				vt = "string"
			}
			inputs[#inputs + 1] = tag_com_config

			local tag_com_service_status = {
				name = k .. "_service_status",
				desc = k .. "_service_status",
				vt = "string"
			}
			inputs[#inputs + 1] = tag_com_service_status

		end
	end

	local outputs = {
	    {
			name = "serial_config",
			desc = "serial_config",
		},
		{
			name = "serial_start",
			desc = "serial_start",
		},
	    {
			name = "serial_stop",
			desc = "serial_stop",
		}
	}
	
	local cmds = {

	}

	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "ser2net"
	meta.description = "ser2net"
	meta.series = "Q"
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs)

	local ser2net_services = self._ser2net_services
	for k,v in pairs(ser2net_services) do
		-- 	创建ser2net服务
		self._log:error("creat Service ser2net:", k)
		local r, err = v:create()
		if not r then
			self._log:error("Service ser2net create failure. Error:", k, err)
		end
	end
	for _,v in pairs(ser2net_services) do
		-- 	停止ser2net服务
		local r, err = v:stop()
	end
	
	-- 	设置初值
    self._dev:set_input_prop('starttime', 'value', self._sys:time())
	for k,v in pairs(inputs) do
	    if v.vt=="string" then
            self._dev:set_input_prop(v.name, 'value', " ")
        end
	end
	
	return true
end

function app:close(reason)
	-- self:on_post_service_ctrl('stop', true)

	local ser2net_services = self._ser2net_services
	for _,v in pairs(ser2net_services) do
		-- 	停止ser2net服务
		local r, err = v:stop()
	end

	for _,v in pairs(ser2net_services) do
		-- 	移除ser2net服务
		local r, err = v:remove()
	end
	--print(self._name, reason)
end


function app:on_post_service_ctrl(action, com_num)
    self._log:info("on_post_service_ctrl::", action, com_num)
    local ser2net_services = self._ser2net_services
    local serviceobj = ser2net_services[com_num]
	if self._in_service_ctrl then
		self._log:warning("Operation for freeioe_ser2net(process-monitor) is processing, please wait for it completed")
		return
	end
	
	self._in_service_ctrl = true
	
	if action == 'restart' then
		self._log:debug("Restart freeioe_ser2net(process-monitor)")

		local r, err = serviceobj:stop()
		if not r then
			self._log:warning("Stop freeioe_ser2net failed. ", err)
		end
		serviceobj:cleanup()
		--- Try to start service(freeioe_Vserial)
		local r, err = serviceobj:start()
		if not r then
			self._log:error("Start freeioe_ser2net failed. ", err)
		end
	end


	if action == 'stop' then
		--- check whether it start or not
		self._log:info("stop freeioe_ser2net . ")
		local r, err = serviceobj:stop()
		if not r then
			self._log:warning("Stop freeioe_ser2net failed. ", err)
		end
		--- stop cleanup always
		serviceobj:cleanup()
	end


	if action == 'start' then
		--- check whether it start or not
		self._log:info("Start freeioe_ser2net . ")
		local r, err = serviceobj:start()
		if r then
			self._log:info("Start freeioe_ser2net successful. ")
		else
			self._log:error("Start freeioe_ser2net failed. ", err)
		end
    end

	self._in_service_ctrl = false
	self._log:warning("Operation end!!")
end


function app:set_services_status()
    local ser2net_services = self._ser2net_services
	for k,v in pairs(ser2net_services) do
	    -- 	停止ser2net服务
	    local service_status = 'stopped'
    	if v:status() then
    		service_status = 'running'
    	end
    	self._dev:set_input_prop(k .. "_service_status", 'value', service_status)
	end

end

function app:run(tms)
	-- 	self._log:warning('_enable_heartbeat:::', self._enable_heartbeat)


	-- local ser2net_status = 'stopped'
	-- if self._service_ser2net:status() then
	-- 	ser2net_status = 'running'
	-- end

	self:set_services_status()

	-- 	local info, err = sysinfo.exec("echo abcdef > /dev/ttyS1")

	return 1000 * 5 -- five seconds
end



return app
