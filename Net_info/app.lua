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
		return nil, err
	else
		local route = split(info, " ")
		-- self._log:debug("default route", cjson.encode(route))
		return route
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
			return "interface is exist!"
		end

		local info, err = sysinfo.exec("uci set network." .. cmds.interface.."=interface")
		local info, err = sysinfo.exec("uci set network." .. cmds.interface .. ".ifname='".. cmds.ifname .. "'")
	else
		self._log:debug("interface or  ifname is nil!")
		return "interface or  ifname is nil!"
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

end

function app:del_interface(cmds)
	self._log:debug("interface:", cmds.interface)
	local cmdstr = "uci delete network." .. cmds.interface
	local info, err = sysinfo.exec(cmdstr)
	local info, err = sysinfo.exec('uci commit network')
	local info, err = sysinfo.exec('ubus call network reload')
	self._log:debug("delete interface".. cmds.interface .." is successful!")
	self:refresh_interfaces()

end
function app:mod_interface_config(cmds)
	-- self._log:debug("interface:", cmds.interface)
	-- self._log:debug("proto:", cmds.proto)
	-- self._log:debug("ipaddr:", cmds.ipaddr)
	-- self._log:debug("netmask:", cmds.netmask)
	-- self._log:debug("gateway:", cmds.gateway)
	-- self._log:debug("dns:", cmds.dns)

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
		local info, err = sysinfo.exec("uci delete network." .. cmds.gateway .. ".dns")
		local info, err = sysinfo.exec("uci delete network." .. cmds.ipaddr .. ".dns")
		local info, err = sysinfo.exec("uci delete network." .. cmds.netmask .. ".dns")
	end
	
	local info, err = sysinfo.exec(cmdstr)
	local info, err = sysinfo.exec('uci commit network')
	local info, err = sysinfo.exec('ubus call network reload')
	self._log:debug("modify interface".. cmds.interface .." is successful!")
	self:refresh_interfaces()
end

function app:refresh_interfaces()
	local dev = self.net_info_dev	
	self:show_interfaces()
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
			name = "net_info",
			desc = "net_info",
			vt = "string",
		}
	}
	for p, q in ipairs(self._interfaces) do
		-- self._log:debug(p, q)
		if q.interface ~= 'loopback' then
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
	dev:mod(inputs)
	for p, q in ipairs(self._interfaces) do
		-- self._log:debug(p, q)
		if q.interface ~= 'loopback' then
			if q.up then
			 --   self._log:debug("q value::", cjson.encode(q))
				dev:set_input_prop(q.interface .. '_dev', "value", q.l3_device)
				if next(q['ipv4-address']) ~= nil then
				    -- self._log:debug(q.interface, q.device, "ipaddr", q['ipv4-address'][1].address)
				    dev:set_input_prop(q.interface .. '_ipaddr', "value", q['ipv4-address'][1].address .. '/' ..q['ipv4-address'][1].mask)
				end
				if next(q.route) ~= nil then
					-- self._log:debug(q.interface, "route", q.route[1].nexthop)
					for k, v in ipairs(q.route) do
						if v.target == "0.0.0.0" then
							dev:set_input_prop(q.interface .. '_nexthop', "value", v.nexthop)
						end
					end
				end
			end

        end

	end	
	local routeinfo = self:show_defaultgw()
	if routeinfo then
		dev:set_input_prop('default_gw', "value", routeinfo[2])
		dev:set_input_prop('gw_interface', "value", routeinfo[8])
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
				
				local cmds, err = cjson.decode(param)
				
				if type(cmds) ~= 'table' then
					self._log:debug("command is not json, value::", cjson.encode(cmds))
					return nil
				end
				
				if cmds ~= nil then
    				if command == "add_interface" then
    					self:add_interface(cmds)
    				end
    				if command == "del_interface" then
    					self:del_interface(cmds)
    
    				end
    				if command == "mod_interface" then
    					self:mod_interface_config(cmds)
    				end
			    end


		end,	
		on_ctrl = function(app, command, param, ...)
		end,
	})

	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._name


	--- 增加设备实例
	local inputs = {}
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

	return 60 * 1000 --下一采集周期为xx秒
end

--- 返回应用对象
return app
