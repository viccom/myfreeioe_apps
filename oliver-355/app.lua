local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local cjson = require 'cjson'
local serialchannel = require 'serialchannel'
local event = require 'app.event'
local sum = require 'hashings.sum'
local basexx = require 'basexx'
local sm_client = require 'userlib.smclient'

local app = class("oliver_355_CLASS")
app.API_VER = 1

local serial = {port = "/dev/ttymxc0", baudrate = 19200, data_bits = 8, parity = "NONE", stop_bits = 1, flow_control = "OFF"}
	
local Dev_Inputs_commands = {
	{
		name = "Working_Mode",
		desc = "激光器工作模式",
		vt = "int",
		cmd = "state?\n",
		decode_mode = 1,
	},
	{
		name = "Working_Frequency",
		desc = "激光器工作频率",
		vt = "int",
		unit = "khz",
		rate = 0.001,
		cmd = "tf?\n",
		decode_mode = 1,
	},		
	{
		name = "Trigger_Mode",
		desc = "激光器触发模式",
		vt = "int",
		cmd = "trig?\n",
		decode_mode = 1,
	},
	{
		name = "Scaling_down_Setting",
		desc = "分频设置",
		vt = "int",
		cmd = "eaom_div?\n",
		decode_mode = 1,
	},
	{
		name = "Power_Settings",
		desc = "功率设置",
		vt = "int",
		unit = "%",
		rate = 0.1,
		cmd  ="pf?\n",
		decode_mode = 1,
    },
	{
		name = "Report_Errors",
		desc = "报错",
		vt = "int",
		cmd = "geterrors?\n",
		decode_mode = 1,
	},
-- 	{
-- 		name = "Command_Table",
-- 		desc = "显示激光器命令表",
-- 		vt = "string",
-- 		cmd = "display\n",
-- 		decode_mode = 0,
-- 	},
	{
		name = "Run_Status",
		desc = "显示激光器运行状态",
		vt = "string",
		cmd = "k\n",
		decode_mode = 0,
	},
	{
		name = "Soft_Version",
		desc = "激光器软件版本号",
		vt = "string",
		cmd = "Copyright?\n",
		decode_mode = 1,
	},
	{
		name = "ontime",
		desc = "State 2状态总时长",
		vt = "string",
		cmd = "ontime?\n",
		decode_mode = 1,
	},
	{
		name = "sleeptime",
		desc = "State 1状态总时长",
		vt = "string",
		cmd = "sleeptime?\n",
		decode_mode = 1,
	},
	{
		name = "standbytime",
		desc = "State 0状态总时长",
		vt = "string",
		cmd = "standbytime?\n",
		decode_mode = 1,
	},
	{
		name = "powerontime",
		desc = "激光器开机总时长",
		vt = "string",
		cmd = "powerontime?\n",
		decode_mode = 1,
	},
}

	
local Dev_Outputs_commands = {
	{
		name = "Set_Working_Mode",
		desc = "设定激光器的操作状态",
		vt = "int",
		cmd = "state",
		decode_mode = 1,
	},
	{
		name = "Set_Frequency",
		desc = "设定出光频率",
		vt = "int",
		cmd = "tf",
		decode_mode = 1,
	},		
	{
		name = "Set_Trigger_Mode",
		desc = "设定trig模式",
		vt = "int",
		cmd = "trig",
		decode_mode = 1,
	},
	{
		name = "Set_Scaling_down",
		desc = "设置分频功能",
		vt = "int",
		cmd = "eaomdiv",
		decode_mode = 1,
	},
	{
		name = "Set_Power",
		desc = "设置功率",
		vt = "int",
		cmd  ="pf",
		decode_mode = 1,
    }
}



function split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function ( w )
        table.insert(resultStrList,w)
    end)
    return resultStrList
end

function trim(input)
	return (string.gsub(input, "^%s*(.-)%s*$", "%1"))
end

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
    --- 获取数据接口
    self._api = sys:data_api()
    --- 获取日志接口
    self._log = sys:logger()

end

function app:execute_cmd(tag)
    local now = self._sys:time()
    local dev = self._dev
    local client = self._sm_client
    local devstat = dev:stat('port')
    local cmd = tag.cmd
    
    local r, pdu, err = pcall(function(cmd, timeout) 
        --- 发出报文
        dev:dump_comm('INPUT-OUT', cmd)
        --- 统计发出数据
        devstat:inc('packets_out', 1)
		return client:request(cmd, timeout)
	end, cmd, 3000)
    --- pcall执行出错
    if not r then 
        local resp = tostring(pdu)
        if string.find(resp, 'timeout') then
            self._log:debug(tag.name, 'read error:', resp, err)
        else
            self._log:warning(tag.name, 'read error:', resp, err)
        end
    else
        if pdu then
            --- 收到报文
            dev:dump_comm('INPUT-IN', pdu)
            --- 统计收到数据
            devstat:inc('packets_in', 1)
            -- self._log:info('successed:', pdu)
            
            local value = pdu
            if tag.decode_mode==1 then
                local valist = split(pdu, "?")
                if #valist>1 then
                    value = valist[2]
                    if tag.vt == 'int' then
                        value = math.tointeger(tonumber(value))
                        if tag.rate then
                            value = value*tag.rate
                        end
                        
                    end
                else
                    value = nil
                end
            end
            if value ~= nil then
                dev:set_input_prop(tag.name, "value", value, now, 0)
            end
        end
    end
    return true
end

function app:start()
	local sys = self._sys
	local id = sys:id()
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			self._log:trace('on_output', app, sn, output, prop, value)

            local dev = self._dev
            local client = self._sm_client
            local devstat = dev:stat('port')
            
            for i, v in ipairs(Dev_Outputs_commands) do
                if output == v.name then
                    while self._reading do
                        sys:sleep(10)
                    end
                    self._writing = true
                    self._writing_tag = v.name
                
                    self._log:notice("ouput tag: ", v.name, v.desc, v.cmd)
                    local msg = v.cmd..' '..value..'\n'
                    local r, pdu, err = pcall(function(msg, timeout)
                        --- 发出报文
                        dev:dump_comm('OUTPUT-OUT', msg)
                        self._log:info(v.name .. '-下置-发送', msg)
                        --- 统计发出数据
                        devstat:inc('packets_out', 1)
                        return client:wrequest(msg, timeout)
                    end, msg, 8000)
                    
                    if not r then 
                        local resp = tostring(pdu)
                        if string.find(resp, 'timeout') then
                            self._log:debug(output, 'write error:', resp, err)
                        else
                            self._log:warning(output, 'write error:', resp, err)
                        end
                        self._writing_tag = nil
                        self._writing = false
                        return false, "error"
                    else
                        if pdu then
                            --- 收到报文
                            dev:dump_comm('OUTPUT-IN', pdu)
                            --- 统计收到数据
                            devstat:inc('packets_in', 1)
                            
                            self._writing = false
                            
                            
                            if pdu == "ok" then
                                if v.vt == 'int' then
                                    value = math.tointeger(tonumber(value))
                                end
                                self._log:info(output, 'write successed:', pdu)
                                dev:set_input_prop_emergency(output, "value", value, self._sys:time(), 0)
                                return true, "done"
                            else
                                self._log:info(output, 'write failed:', pdu)
                                return false, "error"
                            end
                        end

                    end
                    
                    
                end
            end


			
		end,
		on_command = function(app, sn, command, param)
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end

		end,
		on_ctrl = function(app, command, param, ...)
			self._log:trace('on_ctrl', app, command, param, ...)
		end,
	})

	local dev_sn = self._sys:id()..'.'..self._name
	

	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "oliver-355"
	meta.description = "oliver-355 description"
	meta.series = "Q"
	self._dev = self._api:add_device(dev_sn, meta, Dev_Inputs_commands, Dev_Outputs_commands)
	self._log:debug('serial', cjson.encode(serial))
	self._sm_client = sm_client(serialchannel, serial)
	
	return true
end

function app:close(reason)
	--print(self._name, reason)
end

function app:run(tms)

    for i, v in ipairs(Dev_Inputs_commands) do
        while self._writing do
            -- self._log:notice(self._writing_tag, " is writing!")
            self._sys:sleep(100)
        end
        -- self._log:info(i, v.name, v.desc, v.cmd)
        self._reading = true
        self:execute_cmd(v)
        self._reading = false
        self._sys:sleep(10) 
    end


	return 1000 * 5 -- five seconds
end



return app
