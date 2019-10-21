local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local cjson = require 'cjson'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("net_info")
--- 设定应用最小运行接口版本(最新版本为2,为了以后的接口兼容性)
app.API_VER = 2


function split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function ( w )
        table.insert(resultStrList,w)
    end)
    return resultStrList
end

function isIpaddr(ip)
    local isIpaddr = false
    local o1,o2,o3,o4 = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
    -- print(o1,o2,o3,o4)
    if o1==nil or o2 ==nil or o3 ==nil or o4 ==nil then
        return false
    end
    if 224>tonumber(o1) and tonumber(o1)>0 and 255>tonumber(o2) and tonumber(o2)>=0 and 255>tonumber(o3)and tonumber(o3)>=0 and 255>tonumber(o4) and tonumber(o4)>0 then
        isIpaddr = true
    end
    return isIpaddr
end


function name2ip(name)
	local cmd = "nslookup " .. name .. "|grep \"Address 1:\""
	local info, err = sysinfo.exec(cmd)
	if not info then
		return nil, err
	end
	local gwip = split(info, ":")[2]
	return gwip
end

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
	self._api = self._sys:data_api()
	--- 获取日志接口
	self._log = sys:logger()
	--- 设备实例
	self._devs = {}
    self._intefaces_count = 0
	self._log:debug("net_info Application initlized")
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


function app:show_defaultgw()
	local cmd = "route|grep default"
	local info, err = sysinfo.exec(cmd)
	if not string.match(info, "default") then
		return nil, errinfo
	else
	    info = string.match(info, "^[^\n\r]*")
	   -- self._log:debug("default route", info)
		local route = split(info, " ")
-- 		self._log:debug("default route", cjson.encode(route))
		return route
	end
end

function app:show_dns()
    local dev = self.net_info_dev
	local cmd = "cat /etc/resolv.conf|grep nameserver"
	local info, err = sysinfo.exec(cmd)
	dns_servers = {}
	if not string.match(info, "nameserver") then
		return nil, err
	else
		local _dns = split(info, "\n")
-- 		self._log:debug("dns :::", cjson.encode(_dns))
		for _, q in ipairs(_dns) do
		    local dns = split(q, " ")
		    local ip =string.gsub(dns[2], "^%s*(.-)%s*$", "%1")
		  --  self._log:debug("ipaddr is:::", ip)
		    if isIpaddr(ip) then
		        dns_servers[#dns_servers + 1] = ip
		      --  self._log:debug("is ipaddr ::", isIpaddr(ip))
		    end
		end
		dev:set_input_prop('dns_servers', "value", cjson.encode(dns_servers))
		return dns_servers
	end
end

function app:add_dns(cmds)
    self._log:debug("cmds ::", cjson.encode(cmds))
    if cmds.newdns==nil then
        return false, "no param"
    end
    local dnsip = cmds.newdns
    if isIpaddr(dnsip) then
    	local cmd = "echo nameserver " .. dnsip .. " >>/etc/resolv.conf"
    	local info, err = sysinfo.exec(cmd)
    	self:show_dns()
    	return true
    else
        return false, "ipaddr is invalid"
	end
end

function app:del_dns(cmds)
    if cmds.olddns==nil then
        return false, "no param"
    end
    local dnsip = cmds.olddns
    if isIpaddr(dnsip) then
    	local cmd = "sed -i '/"  .. dnsip ..  "/d'  /etc/resolv.conf"
    	local info, err = sysinfo.exec(cmd)
    	self:show_dns()
    	return true
    else
        return false, "ipaddr is invalid"
	end
end


function app:mod_dns(cmds)
    if cmds.olddns==nil or cmds.newdns==nil then
        return false, "param error"
    end
    local olddns = cmds.olddns
    local dnsip = cmds.newdns
    if isIpaddr(dnsip) then
    	local cmd = "sed -i 's/" .. olddns .. "/" .. dnsip .. "/g' /etc/resolv.conf"
    -- 	self._log:debug("mod_dns_cmd:", cmd)
    	local info, err = sysinfo.exec(cmd)
    	self:show_dns()
    	return true
    else
        return false, "ipaddr is invalid"
	end

end

function app:add_interface(cmds)
	-- self._log:debug("interface:", cmds.interface)
	-- self._log:debug("ifname:", cmds.ifname)
	-- self._log:debug("proto:", cmds.proto)
	-- self._log:debug("ipaddr:", cmds.ipaddr)
	-- self._log:debug("netmask:", cmds.netmask)
	-- self._log:debug("gateway:", cmds.gateway)
	-- self._log:debug("dns:", cmds.dns)

	if cmds.interface~=nil and cmds.ifname~=nil then
		local info, err = sysinfo.exec("uci show network." .. cmds.interface)

		if string.match(info, "network") then
			self._log:debug("interface is exist!")
			return false
		end

		local info, err = sysinfo.exec("uci set network." .. cmds.interface.."=interface")
		local info, err = sysinfo.exec("uci set network." .. cmds.interface .. ".ifname='".. cmds.ifname .. "'")
	else
		self._log:debug("interface or  ifname is nil!")
		return false
	end
	
	if not isIpaddr(cmds.ipaddr) then
        return false, "ipaddr is invalid"
	end
	
	local cmdstr = nil
	if cmds.proto=='static' then
		cmdstr = "uci set network." .. cmds.interface .. ".proto='" .. cmds.proto .. "' && uci set network." .. cmds.interface .. ".ipaddr='" .. cmds.ipaddr .. "' && uci set network." .. cmds.interface .. ".netmask='" .. cmds.netmask .. "'"
		if cmds.gateway~=nil then
			local info, err = sysinfo.exec("uci set network." .. cmds.interface .. ".gateway='" ..cmds.gateway .. "'")
		end
		if cmds.dns~=nil then
			local info, err = sysinfo.exec("uci set network." .. cmds.interface .. ".dns='" ..cmds.dns .. "'")
		end
	else
		cmdstr = "uci set network." .. cmds.interface .. ".proto='dhcp'"
	end
	
	local info, err = sysinfo.exec(cmdstr)
	local info, err = sysinfo.exec('uci commit network')
	local info, err = sysinfo.exec('ubus call network reload')
	self._log:debug("add new interface".. cmds.interface .." is successful!")
	self:refresh_interfaces()
    return true
end

function app:del_interface(cmds)
	self._log:debug("interface:", cmds.interface)
	local cmdstr = "uci delete network." .. cmds.interface
	local info, err = sysinfo.exec(cmdstr)
	local info, err = sysinfo.exec('uci commit network')
	local info, err = sysinfo.exec('ubus call network reload')
	self._log:debug("delete interface".. cmds.interface .." is successful!")
	self:refresh_interfaces()
    return true
end
function app:mod_interface_config(cmds)
	self._log:debug("interface:", cmds.interface)
	self._log:debug("proto:", cmds.proto)
	-- self._log:debug("ipaddr:", cmds.ipaddr)
	-- self._log:debug("netmask:", cmds.netmask)
	-- self._log:debug("gateway:", cmds.gateway)
	-- self._log:debug("dns:", cmds.dns)
    if cmds.interface==nil then
        self._log:debug("param is incorrect!")
		return false, "param is incorrect!"
    end
	
	if not isIpaddr(cmds.ipaddr) then
        return false, "ipaddr is invalid"
	end
	
	local info, err = sysinfo.exec("uci show network." .. cmds.interface)
	if not string.match(info, cmds.interface) then
		self._log:debug(cmds.interface, "interface is Nonexist!")
		return false, "interface is Nonexist!"
	end
	local cmdstr = nil
	if cmds.proto=='static' then
		cmdstr = "uci set network." .. cmds.interface .. ".proto='" .. cmds.proto .. "' && uci set network." .. cmds.interface .. ".ipaddr='" .. cmds.ipaddr .. "' && uci set network." .. cmds.interface .. ".netmask='" .. cmds.netmask .. "'"
		if cmds.gateway~=nil then
			local info, err = sysinfo.exec("uci set network." .. cmds.interface .. ".gateway='" ..cmds.gateway .. "'")
		end
		if cmds.dns~=nil then
			local info, err = sysinfo.exec("uci set network." .. cmds.interface .. ".dns='" ..cmds.dns .. "'")
		end
	else
		cmdstr = "uci set network." .. cmds.interface .. ".proto='dhcp'"
		local info, err = sysinfo.exec("uci delete network." .. cmds.dns .. ".dns")
		local info, err = sysinfo.exec("uci delete network." .. cmds.gateway .. ".gateway")
		local info, err = sysinfo.exec("uci delete network." .. cmds.ipaddr .. ".ipaddr")
		local info, err = sysinfo.exec("uci delete network." .. cmds.netmask .. ".netmask")
	end
	
	local info, err = sysinfo.exec(cmdstr)
	local info, err = sysinfo.exec('uci commit network')
	local info, err = sysinfo.exec('ubus call network reload')
	self._log:debug("modify interface".. cmds.interface .." is successful!")
	self:refresh_interfaces()
	return true
end

function app:refresh_interfaces()
	local dev = self.net_info_dev	
	self:show_interfaces()
	local last_intefaces_count =  self._intefaces_count
	local intefaces_count = 0
	
	local inputs = {
		{
			name = "default_gw",
			desc = "default_gw",
			vt = "string",
		},
		{
			name = "gw_interface",
			desc = "gw_interface",
			vt = "string",
		},
		{
			name = "dns_servers",
			desc = "dns_servers",
			vt = "string",
		},
		{
			name = "net_info",
			desc = "net_info",
			vt = "string",
		}
	}
	for p, q in ipairs(self._interfaces) do
		-- self._log:debug(p, q)
		if not (q.interface == 'loopback' or q.interface == 'symrouter' or q.proto=="dhcpv6") then
            intefaces_count = intefaces_count + 1
			local newinterface_dev = {
				name = q.interface .. '_dev',
				desc = q.interface .. '_dev',
				vt = "string"
			}
			inputs[#inputs + 1] = newinterface_dev
	
			local newinterface_ipaddr = {
				name = q.interface .. '_ipaddr',
				desc = q.interface .. '_ipaddr',
				vt = "string"
			}
			inputs[#inputs + 1] = newinterface_ipaddr
	
			local newinterface_nexthop = {
				name = q.interface .. '_nexthop',
				desc = q.interface .. '_nexthop',
				vt = "string"
			}
			inputs[#inputs + 1] = newinterface_nexthop
		end
		
	end
	
	self._intefaces_count = intefaces_count
	if last_intefaces_count ~= intefaces_count then
	    dev:mod(inputs)
	    self._log:debug('intefaces_count change :::', intefaces_count)
	end
	local routeinfo = self:show_defaultgw()
	local gw_interface = nil
	if routeinfo then
	   -- self._log:debug('default_gw :::', routeinfo[2],  "[" .. routeinfo[8] .. "]")
	    if isIpaddr(routeinfo[2]) then
		    dev:set_input_prop('default_gw', "value", routeinfo[2])
		else
		    gw_interface = routeinfo[8]
		end
		dev:set_input_prop('gw_interface', "value", routeinfo[8])
	end
	for p, q in ipairs(self._interfaces) do
		-- self._log:debug(p, q)
		if not (q.interface == 'loopback' or q.interface == 'symrouter' or q.proto=="dhcpv6") then

			if q.up then
			 --   self._log:debug("q value::", cjson.encode(q))
				dev:set_input_prop(q.interface .. '_dev', "value", q.l3_device)
				if next(q['ipv4-address']) ~= nil then
				    -- self._log:debug(q.interface, q.device, "ipaddr", q['ipv4-address'][1].address)
				    dev:set_input_prop(q.interface .. '_ipaddr', "value", q['ipv4-address'][1].address .. '/' ..q['ipv4-address'][1].mask)
				else
				    dev:set_input_prop(q.interface .. '_ipaddr', "value", '--')
				end
				if next(q.route) ~= nil then
				-- 	self._log:debug(q.interface, "route @@@@", q.l3_device, gw_interface)
					for k, v in ipairs(q.route) do
						if v.target == "0.0.0.0" then
							dev:set_input_prop(q.interface .. '_nexthop', "value", v.nexthop)
							if (q.l3_device == gw_interface) then
							    self._log:debug('default_gw @@@', v.nexthop)
							    dev:set_input_prop('default_gw', "value", v.nexthop)
							end
						else
						    dev:set_input_prop(q.interface .. '_nexthop', "value", '--')
						end
					end
				end
    	    else
    	        dev:set_input_prop(q.interface .. '_ipaddr', "value", '--')
    	        dev:set_input_prop(q.interface .. '_nexthop', "value", '--')
    		end

        end

	end	

	dev:set_input_prop('net_info', "value", cjson.encode(self._interfaces))
end

--- 应用启动函数
function app:start()
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
		end,
		on_command = function(app, sn, command, param)
			self._log:debug("on_command", app, sn, command, param)
				
				local cmds = param
				
				if type(cmds) ~= 'table' then
					self._log:debug("command is not json, value::", cjson.encode(param))
					return nil
				end
				
				if next(cmds) == nil then
				    return nil, "param is nil"
				end
				
				if command == "add_interface" then
					return self:add_interface(cmds)
				end
				if command == "del_interface" then
					return self:del_interface(cmds)

				end
				if command == "mod_interface" then
					return self:mod_interface_config(cmds)
				end

				if command == "add_dns" then
					return self:add_dns(cmds)
				end
				if command == "del_dns" then
					return self:del_dns(cmds)

				end
				if command == "mod_dns" then
					return self:mod_dns(cmds)
				end
				
		end,	
		on_ctrl = function(app, command, param, ...)
		end,
	})

	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._name


	--- 增加设备实例
	local inputs = {
		{
			name = "default_gw",
			desc = "default_gw",
			vt = "string",
		},
		{
			name = "gw_interface",
			desc = "gw_interface",
			vt = "string",
		},
		{
			name = "dns_servers",
			desc = "dns_servers",
			vt = "string",
		},
		{
			name = "net_info",
			desc = "net_info",
			vt = "string",
		}
	}
	local cmds = {
		{
			name = "add_interface",
			desc = "add_interface",
		},
		{
			name = "del_interface",
			desc = "del_interface",
		},
		{
			name = "mod_interface",
			desc = "mod_interface",
		},
		{
			name = "add_dns",
			desc = "add_dns",
		},
		{
			name = "del_dns",
			desc = "del_dns",
		},
		{
			name = "mod_dns",
			desc = "mod_dns",
		},
	}
	local meta = self._api:default_meta()
	meta.name = "net_info"
	meta.description = "net_info Meta"
	local dev = self._api:add_device(sn, meta, inputs, {}, cmds)
	self.net_info_dev = dev

	return true
end

--- 应用退出函数
function app:close(reason)
	--print(self._name, reason)
end

--- 应用运行入口
function app:run(tms)

	self._log:debug("start:")
	self:refresh_interfaces()
	self:show_dns()

	return 5 * 1000 --下一采集周期为xx秒
end

--- 返回应用对象
return app
