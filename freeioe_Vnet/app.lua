local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local services = require 'utils.services'
local inifile = require 'inifile'
local cjson = require 'cjson'

local app = class("freeioe_Vnet_CLASS")
app.API_VER = 4

function trim(input)
	return (string.gsub(input, "^%s*(.-)%s*$", "%1"))
end

local netmaptag = {
	['symbridge'] = 'bridge',
	['symrouter'] = 'router',
}

local bridge_tinc={
	'Interface = symbridge',
	'Name = i102',
	'connectTo = viccom',
	'Mode = switch'
}
local router_tinc={
	'Interface = symrouter',
	'Name = i102',
	'connectTo = viccom',
	'Broadcast = mst',
	'Mode = switch'
}
local vnet={
	Address = '0.0.0.0',
	Port = '665',
	subnet = '192.168.0.99/32',
	key = [[
-----BEGIN RSA PUBLIC KEY-----
MIIBCgKCAQEA8uRPG2eRiIVJ4hT3hcUgmjy1bGMvURNskBMBTgeAD1u4vb/Rr51K
doH6z8EMB7hTY/OpUNZWzca28Fkzs02AxUW/wBIuIPJ+RAKbIZYpfbQ7EIaqNNJi
AG9Zadjhy0g67Vx9NEf08vLVuJGqWX+noiJzNDU+HVw9+rb3WqlwMD5l4WryG22H
2yhR29tFh5AXr+rRex+tLoEuqoymEwiIs2lSVoxPLrT1hkw5pargXRd/jkFCc9lE
bfA3qk2hOlQmRNTPoOOgrMq512vEme3xlFSxz8vnKTm38jxL71op/Ti/sU/MZhvo
/EisyNbD2gLrelVNGlBevTARjDGotSO0AQIDAQAB
-----END RSA PUBLIC KEY-----		
]]
}


function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = self._sys:data_api()
	self._log = sys:logger()
	self._bridge_tinc = '/etc/tinc/symbridge/tinc.conf'
	self._bridge_netfile = '/etc/tinc/symbridge/hosts/viccom'
	self._router_tinc = '/etc/tinc/symrouter/tinc.conf'
	self._router_netfile = '/etc/tinc/symrouter/hosts/viccom'

end

function app:appendfile(fileName,content)
	local  f = assert(io.open(fileName,'a'))
	f:write(content)
	f:close()
end
function app:readfile(filename)
	local rfile=io.open(filename, "r")
	assert(rfile)
	for str in rfile:lines() do		
		self._log:info(str)				
	end
	rfile:close()					
end
function app:writefile(filename, content)
	local wfile=io.open(filename, "w")
	assert(wfile)
	wfile:write(content)
	wfile:close()
end

function app:proc_status(procname)
	local cmd='ps|grep ' .. procname .. ' | grep -v grep |wc -l'
	local r, err = sysinfo.exec(cmd)
	-- self._log:info(procname..'  status:',r)
	-- self._log:info(procname..'  status type:',type(r))
	local tag = 'bridge_run'
	if procname=='symrouter' then
		tag = 'router_run'
	end
	if r then
		if trim(r)=='1' then
			self._dev:set_input_prop(tag, 'value', 'running')
			return 'running'
		else
			self._dev:set_input_prop(tag, 'value', 'stoped')
			return 'stopped'
		end
	else
		self._dev:set_input_prop(tag, 'value', nil)
		return nil
	end
end


function app:show_interfaces()

	local cmd = "ubus call network.interface dump"
	local info, err = sysinfo.exec(cmd)
	if not info then
		return nil, err
	end
    local interfaces = cjson.decode(info)
    self._interfaces = interfaces.interface
end

function app:show_ip(ethname)
    local ip = nil
    local dev = nil
    local nexthop = nil
	for p, q in ipairs(self._interfaces) do
		-- self._log:debug(p, q)
		if q.interface == ethname then
			dev = q.l3_device
			-- self._log:debug(q.interface, q.device)
			if q.up then
				-- self._log:debug(q.interface, q.device, "ipaddr", q['ipv4-address'][1].address)
				ip = q['ipv4-address'][1].address
				if next(q.route) ~= nil then
					-- self._log:debug(q.interface, "route", q.route[1].nexthop)
					for k, v in ipairs(q.route) do
						if v.target == "0.0.0.0" then
							nexthop = v.nexthop
						end
					end
				end
			end

        end

	end
	return ip, dev, nexthop
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

			if output == 'enable_heartbeat' then
				self._log:notice('Enable hearbeat for keeping freeioe_Vnet running, value:', value)
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
				self._log:trace('Hearbeat for keeping freeioe_Vnet running, value:', value)
				local timeout = tonumber(value) or 60
				self._heartbeat_timeout = self._sys:time() + timeout
				return true
			end

			if output == 'vnet_config' then
				self._log:trace('vnet_start, value:', value)
				local vnetcfg = cjson.decode(value)

				if vnetcfg~=nil then
					vnet.Address =vnetcfg['Address']
					vnet.Port =vnetcfg['Port']					
					if vnetcfg['net']=='bridge' then
												
						self:vnet_stop('symbridge')

						self:writefile(self._bridge_tinc, table.concat(bridge_tinc,'\n'))
						self:readfile(self._bridge_tinc)
						self:writefile(self._bridge_netfile, table.concat({'Address = '..vnet.Address, 'Port = '..vnet.Port, 'sunbet = '..vnet.subnet, vnet.key},'\n'))
						self:readfile(self._bridge_netfile)
						self._dev:set_input_prop('bridge_config', 'value', cjson.encode(vnetcfg))

						self:vnet_start('symbridge')

						local status = self:proc_status('symbridge')
						if status ~= 'running' then
							self:vnet_start('symbridge')
						end

					end

					if vnetcfg['net']=='router' then
						self:vnet_stop('symrouter')
						self:writefile(self._router_tinc, table.concat(router_tinc,'\n'))
						self:readfile(self._router_tinc)
						self:writefile(self._router_netfile, table.concat({'Address = '..vnet.Address, 'Port = '..vnet.Port, 'sunbet = '..vnet.subnet, vnet.key},'\n'))
						self:readfile(self._router_netfile)
						self:vnet_start('symrouter')

						local status = self:proc_status('symrouter')
						if status ~= 'running' then
							self:vnet_start('symrouter')
						end

					end



				end

				
				return true
			end

			if output == 'vnet_start' then
				self._log:trace('vnet_start, value:', value)
				local vnetcfg = cjson.decode(value)
				if vnetcfg['net']=='bridge' then
					self:vnet_start('symbridge')
				end
				if vnetcfg['net']=='router' then
					self:vnet_start('symrouter')
				end
				return true
			end


			if output == 'vnet_stop' then
				self._log:trace('vnet_stop, value:', value)
				local vnetcfg = cjson.decode(value)
				if vnetcfg['net']=='bridge' then
					self:vnet_stop('symbridge')
				end
				if vnetcfg['net']=='router' then
					self:vnet_stop('symrouter')
					
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
			name = "applog",
			desc = "freeioe_Vnet tips",
			vt = "string",
		},
		{
			name = "valid",
			desc = "freeioe_Vnet valid",
			vt = "string",
		},		
		{
			name = "starttime",
			desc = "freeioe_Vnet start time in UTC",
			vt = "int",
		},
		{
			name = "uptime",
			desc = "freeioe_Vnet process uptime",
			vt = "int",
		},
		{
			name = "lan_ip",
			desc = "lan_ip",
			vt = "string",
        },
		{
			name = "bridge_run",
			desc = "freeioe_Vnet bridge process running status",
			vt = "string",
		},
		{
			name = "bridge_config",
			desc = "freeioe_Vnet bridge config",
			vt = "string"
		},
		{
			name = "bridge_feedback",
			desc = "freeioe_Vnet bridge feedback",
			vt = "string"
		},
		{
			name = "router_run",
			desc = "freeioe_Vnet router process running status",
			vt = "string",
		},
		{
			name = "router_config",
			desc = "freeioe_Vnet bridge config",
			vt = "string"
		},
		{
			name = "router_feedback",
			desc = "freeioe_Vnet router feedback",
			vt = "string"
		},
		{
			name = "enable_heartbeat",
			desc = "freeioe_Vnet enable_heartbeat",
			vt = "int",
		},
		{
			name = "heartbeat_timeout",
			desc = "freeioe_Vnet heartbeat_timeout",
			vt = "int",
		}

	}
	local outputs = {
		{
			name = "vnet_config",
			desc = "freeioe_Vnet configuration (json)",
			vt = "string",
		},
		{
			name = "vnet_start",
			desc = "freeioe_Vnet start (json)",
			vt = "string",
		},
		{
			name = "vnet_stop",
			desc = "freeioe_Vnet stop (json)",
			vt = "string",
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
			desc = "start freeioe_Vnet process",
		},
		{
			name = "stop",
			desc = "stop freeioe_Vnet process",
		},
		{
			name = "restart",
			desc = "restart freeioe_Vnet process",
		}
	}

	

	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "freeioe_Vnet"
	meta.description = "freeioe_Vnet Status"
	meta.series = "Q"
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs, cmds)

    if not self._enable_heartbeat then
		self:vnet_stop('symbridge')
        self:vnet_stop('symrouter')
		self._enable_heartbeat = true
	    self._heartbeat_timeout = sys:time() + 60
		self._dev:set_input_prop('uptime', 'value', 0)
	end
	
	return true
end

function app:close(reason)
	self:vnet_stop('symbridge')
	self:vnet_stop('symrouter')
	--print(self._name, reason)
end

function app:vnet_start(name)
	self._start_time = self._sys:time()
	self._uptime_start = self._sys:now()
	self._heartbeat_timeout = 0
	local r, err = sysinfo.exec("/etc/init.d/"..name.." start")
	if r then
		self._log:info("Start "..name.." successed. ")
		self._dev:set_input_prop(netmaptag[name]..'_feedback', 'value', 'Start '..name..' successed')
	else
		self._log:error("Start "..name.." failed. ", err)
		self._dev:set_input_prop(netmaptag[name]..'_feedback', 'value', 'Start '..name..' failed')
	end

	self._sys:timeout(1000, function()	self:proc_status(name) end)

	self:set_run_inputs()

end

function app:vnet_stop(name)
    self._start_time = nil
	self._uptime_start = nil


	local r, err = sysinfo.exec("/etc/init.d/"..name.. " stop")
	if r then
		self._log:info("Stop "..name.." successed. ", r)
		self._dev:set_input_prop(netmaptag[name]..'_feedback', 'value', 'Stop '..name..' successed')
	else
		self._log:error("Stop "..name.." failed. ", err)
		self._dev:set_input_prop(netmaptag[name]..'_feedback', 'value', 'Stop '..name..' failed')
	end
	self._sys:timeout(1000, function()	self:proc_status(name) end)
	
end


function app:check_heartbeat()
	if self._enable_heartbeat then
		if self._sys:time() > (self._heartbeat_timeout + 10) then
			self._log:warning('freeioe_Vnet running heartbeat rearched, close freeioe_Vnet')
			self:vnet_stop('symbridge')
            self:vnet_stop('symrouter')

		end
	end
end

function app:set_run_inputs()

	--- Starttime
	self._dev:set_input_prop('starttime', 'value', self._start_time or 0)
-- 	for heartbeat stuff
	self._dev:set_input_prop('enable_heartbeat', 'value', self._enable_heartbeat and 1 or 0)
	self._dev:set_input_prop('heartbeat_timeout', 'value', self._heartbeat_timeout or 0)
	local calc_uptime = nil
	if self._uptime_start then
    	self._dev:set_input_prop('uptime', 'value', self._sys:now() - self._uptime_start)
	else
	    self._dev:set_input_prop('uptime', 'value', 0)
	end

end

function app:run(tms)


	self:show_interfaces()
    local c1, c2, c3 = self:show_ip('lan')
    if c1 then
		self._dev:set_input_prop('lan_ip', "value", c1)
	end
	-- self:check_heartbeat()
	
	self:set_run_inputs()
	

	self:proc_status('symbridge')
	self:proc_status('symrouter')
	return 1000 * 5 -- five seconds
end



return app
