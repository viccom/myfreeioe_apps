local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local services = require 'utils.services'
local inifile = require 'inifile'
local cjson = require 'cjson'

local app = class("FREEIOE_APP_Port_tunnel_CLASS")
app.API_VER = 1

local function get_default_conf(sys, conf)
	local ini_conf = {}
	local id = sys:id()

	ini_conf.common = {
		server_addr = conf.server_addr or 'hs.symgrid.com',
		server_port = conf.server_port or '5443',
		token = conf.token or 'BWYJVj2HYhVtdGZL',
		protocol = conf.protocol or 'kcp',

		log_file = '/tmp/log/Port_tunnel_'..sys._app_name..'.log',
		log_level = 'info',
		log_max_days = 1,
		admin_addr="127.0.0.1",
		admin_port=7402,
		login_fail_exit = false,
	}


	if conf.enable_adminapi then
		ini_conf[id..'__adminapi'] = {
			['type'] = 'stcp',
			sk = string.lower(id),
			local_ip = '127.0.0.1',
			local_port = 7402,
			use_encryption = true,
			use_compression = true,
		}
    end

	if conf.enable_webshell then
		ini_conf[id..'__pweb'] = {
			['type'] = 'http',
			local_port = 80,
			local_ip = '127.0.0.1',
			subdomain = string.lower(id)..'_pweb',
			use_encryption = true,
			use_compression = true,
		}
	end

	for k,v in pairs(conf.tcp_devices or {}) do
		ini_conf[id..'_tcp_' .. v.id] = {
			['type'] = 'tcp',
			local_ip = v.dest_ip,
			local_port = v.dest_port,
			remote_port = v.remote_port or '0',
			use_encryption = false,
			use_compression = true,
		}
	end

	for k,v in pairs(conf.udp_devices or {}) do
		ini_conf[id..'_udp_' .. v.id] = {
			['type'] = 'udp',
			local_ip = v.dest_ip,
			local_port = v.dest_port,
			remote_port = v.remote_port or '0',
			use_encryption = false,
			use_compression = true,
		}
	end

	for k,v in pairs(conf.stcp_devices or {}) do
		ini_conf[id..'_stcp_' .. v.id] = {
			['type'] = 'stcp',
			local_ip = v.dest_ip,
			local_port = v.dest_port,
			sk = v.sk or 'password',
			use_encryption = false,
			use_compression = true,
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

	local frpc_bin = sys:app_dir().."/bin/frpc"
	self._service = services:new(self._name, frpc_bin, {'-c', self._ini_file})
	local info, err = sysinfo.exec("chmod +x "..frpc_bin)
end

function app:start()
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

				self._log:notice('Try to change FRPC configuration, value:', cjson.encode(value))

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
				self._log:notice('Enable hearbeat for keeping FRPC running, value:', value)
				local value = tonumber(value)
				if not value or value == 0 then
					self._conf.enable_heartbeat = nil
				else
					self._conf.enable_heartbeat = true 
				end
				self._heartbeat_timeout = self._sys:time() + 60
				return true
			end
			if output == 'heartbeat' then
				self._log:trace('Hearbeat for keeping FRPC running, value:', value)
				local timeout = tonumber(value) or 60
				self._heartbeat_timeout = self._sys:time() + timeout
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
			name = "starttime",
			desc = "Port_tunnel start time in UTC",
			vt = "int",
		},
		{
			name = "uptime",
			desc = "Port_tunnel process uptime",
			vt = "int",
		},
		{
			name = "frpc_run",
			desc = "Port_tunnel process running status",
			vt = "int",
		},
		{
			name = "frpc_visitors",
			desc = "current enabled Port_tunnel visitors",
			vt = "string"
		},
		{
			name = "config",
			desc = "Port_tunnel configuration (json)",
			vt = "string",
		},

	}

	local cmds = {
		{
			name = "start",
			desc = "start Port_tunnel process",
		},
		{
			name = "stop",
			desc = "stop Port_tunnel process",
		},
		{
			name = "restart",
			desc = "restart Port_tunnel process",
		},
	}

	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "Port tunnel"
	meta.description = "Port tunnel Status"
	meta.series = "Q"
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs, cmds)

	local r, err = self._service:create()
	if not r then
		self._log:error("Service create failure. Error:", err)
		return nil, "Service create failure. Error: "..err
	end

	return true
end

function app:close(reason)
	self:on_post_service_ctrl('stop', true)
	self._service:remove()
	--print(self._name, reason)
end

function app:on_frpc_start()
	if self._start_time then
		self:on_frpc_stop()
	end

	self._start_time = self._sys:time()
	self._uptime_start = self._sys:now()
	self._heartbeat_timeout = 0

	self:set_run_inputs()

	local calc_uptime = nil
	calc_uptime = function()
		self._cancel_uptime_timer = self._sys:cancelable_timeout(1000 * 60, calc_uptime)
		self._dev:set_input_prop('uptime', 'value', self._sys:now() - self._uptime_start)
	end
	calc_uptime()
end

function app:on_frpc_stop()
	if self._cancel_uptime_timer then
		self._cancel_uptime_timer()
		self._cancel_uptime_timer = nil
		self._start_time = nil
		self._uptime_start = nil
	end
	self._service:cleanup()
end

function app:on_post_service_ctrl(action, force)
	if self._in_service_ctrl then
		self._log:warning("Operation for frpc(process-monitor) is processing, please wait for it completed")
		return
	end
	self._in_service_ctrl = true
	if action == 'restart' then
		self._log:debug("Restart frpc(process-monitor)")

		--- Try to stop service(frpc)
		if self._start_time then
			local r, err = self._service:stop()
			if not r then
				self._log:warning("Stop frpc failed. ", err)
			end
			self:on_frpc_stop()
		end

		--- Try to start service(frpc)
		local r, err = self._service:start()
		if r then
			self:on_frpc_start()
		else
			self._log:error("Start frpc failed. ", err)
		end
	end
	if action == 'stop' then
		--- check whether it start or not
		if not force and not self._start_time then
			self._log:error("Frpc already stoped!")
			self._in_service_ctrl = nil
			return
		end

		self._log:debug("Stop frpc(process-monitor)")
		local r, err = self._service:stop()
		if not r and not force then
			self._log:warning("Stop frpc failed. ", err)
		end
		--- stop cleanup always
		self:on_frpc_stop()
	end
	if action == 'start' then
		--- check whether it start or not
		if not force and self._start_time then
			self._log:error("Frpc already started!")
			self._in_service_ctrl = nil
			return
		end

		self._log:debug("Start frpc(process-monitor)")
		local r, err = self._service:start()
		if r then
			self:on_frpc_start()
		else
			self._log:error("Start frpc failed. ", err)
		end
	end
	self._in_service_ctrl = nil
end

function app:check_heartbeat()
	if self._conf.enable_heartbeat then
		if self._sys:time() > (self._heartbeat_timeout + 10) then
			self._log:warning('Frpc running heartbeat rearched, close frpc')
			self._sys:post('service_ctrl', 'stop')
			-- Clear heartbeat
			self._conf.enable_heartbeat = 0
			self._heartbeat_timeout = 0
		end
	end
end

function app:set_run_inputs()

	--- Starttime
	self._dev:set_input_prop('starttime', 'value', self._start_time or 0)

	-- for heartbeat stuff
-- 	self._dev:set_input_prop('enable_heartbeat', 'value', self._conf.enable_heartbeat and 1 or 0)
-- 	self._dev:set_input_prop('heartbeat_timeout', 'value', self._heartbeat_timeout or 0)

	--- for configurations
	self._dev:set_input_prop('config', 'value', cjson.encode(self._conf))
	self._dev:set_input_prop('frpc_visitors', 'value', self._visitors)
end

function app:run(tms)
	if not self._first_start then
		self:on_post_service_ctrl('stop', true)
		self:on_post_service_ctrl('start')
		self._first_start = true
	end

	local status = self._service:status()
	self._dev:set_input_prop('frpc_run', 'value', status and 1 or 0)

	self:set_run_inputs()

	-- self:check_heartbeat()

	return 1000 * 5 -- five seconds
end



return app
