local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local services = require 'utils.services'
local inifile = require 'inifile'
local cjson = require 'cjson'
local restful = require 'restful'
local log = require 'utils.log'
local com_table = require 'userlib.model'
local app = class("freeioe_Vserial_CLASS")

app.API_VER = 4

function trim(input)
	return (string.gsub(input, "^%s*(.-)%s*$", "%1"))
end


local function get_status(url, dev)
	local _restapi = restful:new(url)
	local status, body = _restapi:get('/api/status')
	log:info("return::::", status, body)
	if status and status == 200 then
		local data = cjson.decode(body)
		log:info("return::::", cjson.encode(data.tcp))
		
		for k,v in ipairs(data.tcp) do
-- 			local tag = string.sub(v.name,#v.name-6,-4)
			if v.status == "running" then
				log:info(k, cjson.encode(v.name))
				dev:set_input_prop_emergency('com_to_net_mapport', 'value', v.remote_addr)
			else
				dev:set_input_prop_emergency('com_to_net_mapport', 'value', ' ')
			end
		end
		return true
	else
	    dev:set_input_prop_emergency('com_to_net_mapport', 'value', ' ')
	end
	return nil
end

local function get_default_conf(sys, conf)
	local ini_conf = {}
	local id = sys:id()

	ini_conf.common = {
		server_addr = conf.server_addr or 'bj.proxy.thingsroot.com',
		server_port = conf.server_port or '1699',
		token = conf.token or 'F^AYnHp29U=M96#o&ESqXB3pL=$)W*qr',
		protocol = conf.protocol or 'tcp',

		log_file = '/tmp/log/'..sys._app_name..'.log',
		log_level = 'info',
		log_max_days = 1,
		admin_addr="0.0.0.0",
		admin_port=7421,
		login_fail_exit = false,
	}


	if conf.enable_adminapi then
		ini_conf[id..'__adminapi'] = {
			['type'] = 'stcp',
			sk = string.lower(id),
			local_ip = '127.0.0.1',
			local_port = 7421,
			use_encryption = true,
			use_compression = true,
		}
  	end

	local model_number =  string.sub( id, 1, 7)
	if com_table[model_number] then

		ini_conf[id..'__ser2net_vserial'] = {
			['type'] = 'tcp',
			local_port = 4700,
			local_ip = '127.0.0.1',
			use_encryption = true,
			use_compression = true,
			remote_port = 0
		}

	end

	local visitors = {}
	for k,v in pairs(ini_conf) do
		if k ~= 'common' then
			visitors[#visitors + 1] = k
		end
	end

	return ini_conf, visitors
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
	self._ini_file = sys:app_dir()..".frpc.ini"

	local conf, visitors = get_default_conf(sys, self._conf)

	self._log:info("config::", cjson.encode(conf))

	inifile.save(self._ini_file, conf)
	self._visitors = cjson.encode(visitors)

	local frpc_bin = sys:app_dir().."bin/frpc"
	self._service = services:new(self._name, frpc_bin, {'-c', self._ini_file})
	local info, err = sysinfo.exec("chmod +x "..frpc_bin)
	
	local ser2net_bin = sys:app_dir().."bin/ser2net"
	sysinfo.exec("chmod +x "..ser2net_bin)
	local ser2net_conf = sys:app_dir()..".ser2net_vserial.conf"
	self._service_vserial = services:new("ser2net_vserial", ser2net_bin, {'-d -c', ser2net_conf})
	
end

function app:start()
	local sys = self._sys
	local id = sys:id()
	local model_number =  string.sub( id, 1, 7)
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			self._log:trace('on_output', app, sn, output, prop, value)
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end
			if output == 'config' then
				if type(value) ~= 'table' then
					local conf, err = cjson.decode(value)
					if not conf then
						self._log:error('Incorrect configuration value found, value:', value)
						return false, "Incorrect configuration value found"
					end
					value = conf
				end
				self._conf = value

				self._log:notice('Try to change freeioe_Vserial configuration, value:', cjson.encode(value))

				local conf, visitors = get_default_conf(self._sys, self._conf)
				inifile.save(self._ini_file, conf)
				self._visitors = cjson.encode(visitors)

				if self._conf.auto_start then
					self._sys:post('service_ctrl', 'restart')
				else
					self._sys:post('service_ctrl', 'stop')
				end
				return true
			end
			if output == 'enable_heartbeat' then
				self._log:notice('Enable hearbeat for keeping freeioe_Vserial running, value:', value)
				local value = tonumber(value)
				if not value or value == 0 then
					self._enable_heartbeat = false
				else
					self._enable_heartbeat = true 
				end
				self._heartbeat_timeout = self._sys:time() + 60
				return true
			end
			if output == 'heartbeat_timeout' then
				self._log:trace('Hearbeat for keeping freeioe_Vserial running, value:', value)
				local timeout = tonumber(value) or 60
				self._heartbeat_timeout = self._sys:time() + timeout
				return true
			end
			
			if output == 'serial_start' then
				self._log:trace('start freeioe_Vserial value:', value)
				if value ~= nil then
                    self._sys:post('service_ctrl', 'start')
                end
				return true
			end
			
			if output == 'serial_stop' then
				self._log:trace('stop freeioe_Vserial value:', value)
				if value ~= nil then
                    self._sys:post('service_ctrl', 'stop')
                end
				return true
			end			

			if output == 'serial_config' then
				self._log:trace('serial_config, value:', value)
				local comconf = nil
				
				if type(value) ~= 'table' then
					comconf, err = cjson.decode(value)
				end
				
				if comconf ~= nil then
    				
    				if comconf.server_addr ~= nil then
    
        				self._conf = {server_addr = comconf.server_addr}
        				self._log:notice('Try to change FRPC configuration, value:', cjson.encode(value))
        				self._dev:set_input_prop_emergency('current_com', 'value', '--', self._sys:time(), 0)
        				self._dev:set_input_prop_emergency('com_to_net_run', 'value', '--', self._sys:time(), 0)
        				self._dev:set_input_prop_emergency('com_to_net_config', 'value', '--', self._sys:time(), 0)
        				self._dev:set_input_prop_emergency('com_to_net_feedback', 'value', '--', self._sys:time(), 0)
        				self._dev:set_input_prop_emergency('com_to_net_mapport', 'value', '--', self._sys:time(), 0)
        				
        				local conf, visitors = get_default_conf(self._sys, self._conf)
        				inifile.save(self._ini_file, conf)
        				self._visitors = cjson.encode(visitors)
    				end
    				
    				if com_table[model_number]~=nil then
    					
    					if com_table[model_number][comconf.serial]~=nil then
    						self._log:info('dest serial:', com_table[model_number][comconf.serial]['name'])
    						local dest_com = comconf.serial						
    						local baudrate = comconf.baudrate or '9600'
    						local databit = comconf.databit or '8'
    						local stopbit = comconf.stopbit or '1'
    						local parity = comconf.parity or "NONE"
    						
    						local ser2net_conf = sys:app_dir()..".ser2net_vserial.conf"
    						local ser2net_args = '4700:raw:600:/dev/'..com_table[model_number][comconf.serial]['name']..':' .. baudrate..' '.. parity..' '.. stopbit..'STOPBIT'..' '.. databit..'DATABITS' ..' -XONXOFF LOCAL -RTSCTS'
    						local r, err = sysinfo.exec("echo "..ser2net_args.." > "..ser2net_conf)
    						if not r then
    							self._log:error("Error:", err)
    							return nil, "Error: "..err
    						end
                            self._dev:set_input_prop_emergency('current_com', 'value', dest_com)
            				self._dev:set_input_prop_emergency('com_to_net_config', 'value', cjson.encode(comconf))

    				        self._sys:post('service_ctrl', 'restart')
    						
    						self._log:info("+++++++++++++++++++++++++++++++++++++++++++++++++++++++get_status")
    						self._sys:timeout(3000, function()	get_status('http://127.0.0.1:7421', self._dev) end)
    					else
    						self._dev:set_input_prop('applog', 'value', comconf.serial..' is nonexistent')
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
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end
			-- command: start, stop, restart
			local commands = { start = 1, stop = 1, restart = 1 }
			local f = commands[command]
			if f then
				self._sys:post('service_ctrl', command)
				self._log:error('device command send!', command)

				self._sys:timeout(2000, function()	get_status('http://127.0.0.1:7421', self._dev) end)
				return true
			else
				self._log:error('device command not exists!', command)
				return false, 'device command not exists!'
			end
			
		end,
		on_ctrl = function(app, command, param, ...)
			self._log:trace('on_ctrl', app, command, param, ...)
		end,
	})

	local dev_sn = self._sys:id()..'.'..self._name
	local inputs = {
		{
			name = "app_log",
			desc = "freeioe_Vserial tips",
			vt = "string",
		},
		{
			name = "valid",
			desc = "freeioe_Vserial valid",
			vt = "string",
		},		
		{
			name = "starttime",
			desc = "freeioe_Vserial start time in UTC",
			vt = "int",
		},
		{
			name = "uptime",
			desc = "freeioe_Vserial process uptime",
			vt = "int",
		},
		{
			name = "frpc_run",
			desc = "freeioe_Vserial process running status",
			vt = "int",
		},
		{
			name = "frpc_visitors",
			desc = "current enabled freeioe_Vserial visitors",
			vt = "string"
		},
		{
			name = "config",
			desc = "freeioe_Vserial configuration (json)",
			vt = "string",
		},
		{
			name = "enable_heartbeat",
			desc = "freeioe_Vserial enable_heartbeat",
			vt = "int",
		},
		{
			name = "heartbeat_timeout",
			desc = "freeioe_Vserial heartbeat_timeout",
			vt = "int",
		},
		{
			name = "current_com",
			desc = "ser2net_vserial current_com",
			vt = "string",
		},
		{
			name = "com_to_net_run",
			desc = "ser2net_vserial run",
			vt = "string",
		},
		{
			name = "com_to_net_config",
			desc = "ser2net_vserial config",
			vt = "string",
		},
		{
			name = "com_to_net_feedback",
			desc = "ser2net_vserial feedback",
			vt = "string",
		},
		{
			name = "com_to_net_mapport",
			desc = "ser2net_vserial mapport",
			vt = "string",
		}
	}
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
		},
		{
			name = "heartbeat_timeout",
			desc = "set heartbeat_timeout",
			vt = "int",
		},
		{
			name = "enable_heartbeat",
			desc = "set enable_heartbeat",
			vt = "int",
		}
	}
	
	local cmds = {
		{
			name = "start",
			desc = "start freeioe_Vserial process",
		},
		{
			name = "stop",
			desc = "stop freeioe_Vserial process",
		},
		{
			name = "restart",
			desc = "restart freeioe_Vserial process",
		},
	}
	
	local model_number =  string.sub( self._sys:id(), 1, 7)
	self._log:info("model_number::", model_number)
	if com_table[model_number]==nil then
		self._log:error("APP not support the model!")
	end

	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "freeioe_Vserial"
	meta.description = "freeioe_Vserial Status"
	meta.series = "Q"
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs, cmds)


	if com_table[model_number]==nil then
		self._dev:set_input_prop('app_log', 'value', 'APP not support the model')
		self._dev:set_input_prop('valid', 'value', '0')
	else
		self._dev:set_input_prop('app_log', 'value', '')
		self._dev:set_input_prop('valid', 'value', '1')
	end
	self._dev:set_input_prop('current_com', 'value', '')	
	self._dev:set_input_prop('com_to_net_run', 'value', '')
	self._dev:set_input_prop('com_to_net_config', 'value', '')
	self._dev:set_input_prop('com_to_net_feedback', 'value', '')
	self._dev:set_input_prop('com_to_net_mapport', 'value', '')
	
-- 	创建freeioe_Vserial服务和
	local r, err = self._service:create()
	if not r then
		self._log:error("Service freeioe_Vserial create failure. Error:", err)
		return nil, "Service freeioe_Vserial create failure. Error: "..err
	end
	
	local r, err = self._service_vserial:create()
	if not r then
		self._log:error("Service ser2net_vserial create failure. Error:", err)
	end
	
	if not self._enable_heartbeat then
		self:on_post_service_ctrl('stop', true)
		self._enable_heartbeat = true
	    self._heartbeat_timeout = sys:time() + 60
		self._dev:set_input_prop('uptime', 'value', 0)
	end
	return true
end

function app:close(reason)
	self:on_post_service_ctrl('stop', true)
	self._service:remove()
	self._service_vserial:remove()
	--print(self._name, reason)
end

function app:on_frpc_start()
	if self._start_time then
		self:on_frpc_stop()
	end

	self._start_time = self._sys:time()
	self._uptime_start = self._sys:now()

	self:set_run_inputs()

	local calc_uptime = nil
	calc_uptime = function()
		self._cancel_uptime_timer = self._sys:cancelable_timeout(1000 * 60, calc_uptime)
		self._dev:set_input_prop('uptime', 'value', self._sys:now() - self._uptime_start)
		--- Starttime
	    self._dev:set_input_prop('starttime', 'value', self._start_time or 0)
	end
	calc_uptime()

	local r, err = self._service_vserial:start()
	if r then
		self._log:info("Start ser2net_Vserial successful. ")
		self._dev:set_input_prop_emergency('com_to_net_run', 'value', 'running')
		self._dev:set_input_prop_emergency('com_to_net_feedback', 'value', 'Start ser2net_Vserial successful')
	else
		self._log:error("Start ser2net_Vserial failed. ", err)
		self._dev:set_input_prop_emergency('com_to_net_feedback', 'value', 'Start ser2net_Vserial failure')
	end

end

function app:on_frpc_stop()
	if self._cancel_uptime_timer then
		self._cancel_uptime_timer()
		self._cancel_uptime_timer = nil
		self._start_time = nil
		self._uptime_start = nil
	end
	self._service:cleanup()

    self._dev:set_input_prop('starttime', 'value', 0)
    self._dev:set_input_prop('uptime', 'value', 0)
    
	local r, err = self._service_vserial:stop()
	if not r then
		self._log:warning("Stop ser2net_Vserial successful. ", err)
		self._service_vserial:cleanup()
		self._dev:set_input_prop_emergency('com_to_net_run', 'value', 'stopped')
		self._dev:set_input_prop_emergency('com_to_net_feedback', 'value', 'Stop ser2net_Vserial successful')
	else
	    self._log:warning("Stop ser2net_Vserial failed. ", err)
		self._dev:set_input_prop_emergency('com_to_net_feedback', 'value', 'Stop ser2net_Vserial failure')
	end



end

function app:on_post_service_ctrl(action, force)
	if self._in_service_ctrl then
		self._log:warning("Operation for freeioe_Vserial(process-monitor) is processing, please wait for it completed")
		return
	end
	self._in_service_ctrl = true
	if action == 'restart' then
		self._log:debug("Restart freeioe_Vserial(process-monitor)")

		--- Try to stop service(freeioe_Vserial)
		if self._start_time then
			local r, err = self._service:stop()
			if not r then
				self._log:warning("Stop freeioe_Vserial failed. ", err)
			end
			self:on_frpc_stop()
		end

		--- Try to start service(freeioe_Vserial)
		local r, err = self._service:start()
		if r then
			self:on_frpc_start()
		else
			self._log:error("Start freeioe_Vserial failed. ", err)
		end

	end


	if action == 'stop' then
		--- check whether it start or not
		self._log:info("stop freeioe_Vserial . ")
		
		if not force and not self._start_time then
			self._log:error("freeioe_Vserial already stoped!")
			self._in_service_ctrl = nil
			return
		end


		local r, err = self._service:stop()
		if not r and not force then
			self._log:warning("Stop freeioe_Vserial failed. ", err)
		end
		--- stop cleanup always
		self:on_frpc_stop()

	end


	if action == 'start' then
		--- check whether it start or not
		self._log:info("Start freeioe_Vserial . ")

		if not force and self._start_time then
			self._log:error("freeioe_Vserial already started!")
			self._in_service_ctrl = nil
			return
		end
		local r, err = self._service:start()
		if r then
			self:on_frpc_start()
			self._log:info("Start freeioe_Vserial successful. ")
		else
			self._log:error("Start freeioe_Vserial failed. ", err)
		end
		
	end
	self._in_service_ctrl = nil
end

function app:check_heartbeat()
	if self._enable_heartbeat then
		if self._sys:time() > (self._heartbeat_timeout + 10) then
			self._log:warning('freeioe_Vserial running heartbeat rearched, close service')
			self._sys:post('service_ctrl', 'stop')
			-- Clear heartbeat
-- 			self._enable_heartbeat = false
			self._heartbeat_timeout = 0
		end
	end
end

function app:set_run_inputs()


	-- for heartbeat stuff
	self._dev:set_input_prop('enable_heartbeat', 'value', self._enable_heartbeat and 1 or 0)
	self._dev:set_input_prop('heartbeat_timeout', 'value', self._heartbeat_timeout or 0)

	--- for configurations
	self._dev:set_input_prop('config', 'value', cjson.encode(self._conf))
	self._dev:set_input_prop('frpc_visitors', 'value', self._visitors)
end

function app:run(tms)

	
-- 	self._log:warning('_enable_heartbeat:::', self._enable_heartbeat)
	
	local frpc_status = self._service:status()
	self._dev:set_input_prop('frpc_run', 'value', frpc_status and 1 or 0)
	
	local ser2net_status = 'stopped'
	if self._service_vserial:status() then
	    ser2net_status = 'running'
    end
    -- self._log:warning('_service_vserial:::', self._service_vserial:status())
    self._dev:set_input_prop('com_to_net_run', 'value', ser2net_status)

	self:set_run_inputs()

    get_status('http://127.0.0.1:7421', self._dev)
    
    
	self:check_heartbeat()
	
-- 	local info, err = sysinfo.exec("echo abcdef > /dev/ttyS1")
	
	return 1000 * 5 -- five seconds
end



return app
