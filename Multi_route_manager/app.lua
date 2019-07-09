local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local cjson = require 'cjson'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("multi_route_manager")
--- 设定应用最小运行接口版本(最新版本为2,为了以后的接口兼容性)
app.API_VER = 2


function split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function ( w )
        table.insert(resultStrList,w)
    end)
    return resultStrList
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

	self._log:debug("net_manager Application initlized")
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
			    if next(q['ipv4-address']) ~= nil then
    				self._log:debug(q.interface, q.device, "ipaddr", q['ipv4-address'][1].address)
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

	end
	return ip, dev, nexthop
end



function app:show_defaultgw()
	local cmd = "route|grep default"
	local info, err = sysinfo.exec(cmd)
	if not string.match(info, "default") then
		return nil, err
	else
		local route = split(info, " ")
		-- self._log:debug("default route", cjson.encode(route))
		return route
	end
end

function app:query_static_route(destip, ethname)
	local cmd_queryroute = "route -n|grep UGH|grep " .. destip
	local info, err = sysinfo.exec(cmd_queryroute)
	if not info then
		return nil, err
	end
	local static_route_info = split(info, " ")
	return static_route_info[8]
end

function app:switch_route(gwip, ethname)
	local cmd_delroute = "route delete default"
	local cmd_addroute = "route add default gw " .. gwip .. " dev " .. ethname
	sysinfo.exec(cmd_delroute)
	sysinfo.exec(cmd_addroute)
end

--- 应用启动函数
function app:start()
	self._api:set_handler({
		--[[
		--- 处理设备输入项数值变更消息，当需要监控其他设备时才需要此接口，并在set_handler函数传入监控标识
		on_input = function(app, sn, input, prop, value, timestamp, quality)
		end,
		--- 设备紧急数据
		on_input_em = function(app, sn, input, prop, value, timestamp, quality)
		end,
		]]
		on_output = function(app, sn, output, prop, value)
		end,
		on_command = function(app, sn, command, param)
		end,	
		on_ctrl = function(app, command, param, ...)
		end,
	})

	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._name

	--- 获取应用参数
	local config = self._conf
    if config == nil then
        config = require 'userlib.config'
    else
        if next(config) == nil then
            config = require 'userlib.config'
        end
	end
	
	self.appconfig = config

	--- 增加设备实例
	local inputs = {
		{
			name = "lan_ip",
			desc = "lan_ip",
			vt = "string",
        },
        {
			name = "lan_dev",
			desc = "lan_dev",
			vt = "string",
        },
        {
			name = "lan_nexthop",
			desc = "lan_nexthop",
			vt = "string",
        },
        {
			name = "primary_wan_ip",
			desc = "primary_wan_ip",
			vt = "string",
        },
        {
			name = "primary_wan_dev",
			desc = "primary_wan_dev",
			vt = "string",
        },
        {
			name = "primary_wan_nexthop",
			desc = "primary_wan_nexthop",
			vt = "string",
        },
        {
			name = "secondary_wan_ip",
			desc = "secondary_wan_ip",
			vt = "string",
        },
        {
			name = "secondary_wan_dev",
			desc = "secondary_wan_dev",
			vt = "string",
        },
        {
			name = "secondary_wan_nexthop",
			desc = "secondary_wan_nexthop",
			vt = "string",
        },
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
			name = "is_alive",
			desc = "is_alive",
			vt = "int",
		},
		{
			name = "primary_wan_is_alive",
			desc = "primary_wan_is_alive",
			vt = "int",
		}
	}
	local meta = self._api:default_meta()
	meta.name = "Multi_route_manager"
	meta.description = "Multi_route_manager Meta"
	local dev = self._api:add_device(sn, meta, inputs)
	self._devs[#self._devs + 1] = dev
	self.net_manager_dev = dev

	local cmd_del_staticroute="route del -net " .. self.appconfig.lan_live_ip .. " netmask 255.255.255.255"
	sysinfo.exec(cmd_del_staticroute)
	return true
end

--- 应用退出函数
function app:close(reason)
	--print(self._name, reason)
end

--- 应用运行入口
function app:run(tms)
	local dev = self.net_manager_dev
	self._log:debug("start:")

    self:show_interfaces()
    local c1, c2, c3 = self:show_ip(self.appconfig.lan)
    self._log:debug(self.appconfig.lan, "ip", c1, "dev", c2, "nexthop", c3)
    if c1 then
		dev:set_input_prop('lan_ip', "value", c1)
	else
	    dev:set_input_prop('lan_ip', "value", '--')
	end
	if c2 then
		dev:set_input_prop('lan_dev', "value", c2)
	else
	    dev:set_input_prop('lan_dev', "value", '--')
	end
	if c3 then
        dev:set_input_prop('lan_nexthop', "value", c3)
    else
	    dev:set_input_prop('lan_nexthop', "value", '--')
    end

    local a1, a2, a3 = self:show_ip(self.appconfig.primary_wan)
    self._log:debug(self.appconfig.primary_wan, "ip", a1, "dev", a2, "nexthop", a3)
    if a1 then
		dev:set_input_prop('primary_wan_ip', "value", a1)
	else
	    dev:set_input_prop('primary_wan_ip', "value", '--')
	end
	if a2 then
		dev:set_input_prop('primary_wan_dev', "value", a2)
	else
	    dev:set_input_prop('primary_wan_dev', "value", '--')
	end
	if a3 then
        dev:set_input_prop('primary_wan_nexthop', "value", a3)
    else
        dev:set_input_prop('primary_wan_nexthop', "value", '--')
    end

    local b1, b2, b3 = self:show_ip(self.appconfig.secondary_wan)
    self._log:debug(self.appconfig.secondary_wan, "ip", b1, "dev", b2, "nexthop", b3)
    if b1 then    
		dev:set_input_prop('secondary_wan_ip', "value", b1)
	else
	    dev:set_input_prop('secondary_wan_ip', "value", '--')
	end
	if b2 then
		dev:set_input_prop('secondary_wan_dev', "value", b2)
	else
	    dev:set_input_prop('secondary_wan_dev', "value", '--')
	end
	if b3 then
        dev:set_input_prop('secondary_wan_nexthop', "value", b3)
    else
        dev:set_input_prop('secondary_wan_nexthop', "value", '--')
    end
    

	local routeinfo = self:show_defaultgw()
	local default_gw = nil
	local gw_interface = nil
	if routeinfo then
		default_gw = routeinfo[2]
		gw_interface = routeinfo[8]
		self._log:debug("default gateway:", default_gw)
		self._log:debug("gateway interface:", gw_interface)
		dev:set_input_prop('default_gw', "value", default_gw)
		dev:set_input_prop('gw_interface', "value", gw_interface)
	else
	    dev:set_input_prop('default_gw', "value", '--')
		dev:set_input_prop('gw_interface', "value", '--')
	end

	if a3 ~= nil then
	
		local static_route_i = self:query_static_route(self.appconfig.lan_live_ip, self.appconfig.primary_wan)
		if static_route_i==nil then
			-- local cmd_del_staticroute="route del -net " .. self.appconfig.lan_live_ip .. " netmask 255.255.255.255"
			-- sysinfo.exec(cmd_del_staticroute)
			local cmd_add_staticroute="route add -net " .. self.appconfig.lan_live_ip .. " netmask 255.255.255.255 gw ".. a3 .." dev " .. a2
			sysinfo.exec(cmd_add_staticroute)
		end
		local ping_cmd = "ping -c2 -s16 -w5 " .. self.appconfig.live_check_ip .. " &>/dev/null && echo $?"
		local ret, err = sysinfo.exec(ping_cmd)
-- 		self._log:debug("ping ret:", tonumber(ret))
-- 		self._log:debug("ping ret:", not(tonumber(ret)==0))
		if not(tonumber(ret)==0) then
			self._log:debug("cann't connect internet:")
			dev:set_input_prop('is_alive', "value", 0)
			self._log:debug("ping no response, switch route")
			if default_gw==b3 and a2~=nil then
				self:switch_route(a3, a2)
			elseif default_gw==a3 and b2~=nil then
				self:switch_route(b3, b2)
			end
		else
			dev:set_input_prop('is_alive', "value", 1)
			local lan_ping_cmd = "ping -c2 -s16 -w5 -I " .. a2 .. " " .. self.appconfig.lan_live_ip .. " &>/dev/null && echo $?"
			local lanping_ret, err = sysinfo.exec(lan_ping_cmd)
			self._log:debug("LAN route ping:", tonumber(lanping_ret), default_gw, b3)
			if tonumber(lanping_ret)==0 then
			    dev:set_input_prop('primary_wan_is_alive', "value", 1)
				if default_gw==b3  and a2~=nil then
					self._log:debug("LAN route is good, switch to LAN route")
					
					self:switch_route(a3, a2)
				    
				end
		    else
		        dev:set_input_prop('primary_wan_is_alive', "value", 0)
			end
	    end
	else
	    local ping_cmd = "ping -c2 -s16 -w5 " .. self.appconfig.live_check_ip .. " &>/dev/null && echo $?"
		local ret, err = sysinfo.exec(ping_cmd)
		if not(tonumber(ret)==0) then
			dev:set_input_prop('is_alive', "value", 0)
        else
            dev:set_input_prop('is_alive', "value", 1)
	    end
	    dev:set_input_prop('primary_wan_is_alive', "value", 0)
	end


	return self.appconfig.check_cycle * 1000 --下一采集周期为xx秒
end

--- 返回应用对象
return app
