local class = require 'middleclass'
--- 导入需要的模块
local socketchannel = require 'socketchannel'
local serialchannel = require 'serialchannel'
local event = require 'app.event'
local sum = require 'hashings.sum'
local basexx = require 'basexx'
local sm_client = require 'userlib.smclient'
local csv_tpl = require 'userlib.csv_tpl'
local parser = require 'userlib.points_parser'
local modbus_cmd = nil

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("General_Modbus_RTU")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1

local function _register_format(s)
    if (s ~= nil) then
        if (#s == 1) then
            return "0" .. string.upper(s)
        else
            return string.upper(s)
        end
    end
    return nil
end

local _dt_len_map = {
    int8 = 1,
    uint8 = 1,
    int16 = 1,
    uint16 = 1,
    int32 = 2,
    uint32 = 2,
    int64 = 4,
    uint64 = 4,
    float = 2,
    double = 4
}

local _dt_format = {
    int8 = '>i1',
    uint8 = '>I1',
    int16 = '>i2',
    uint16 = '>I2',
    int32 = '>i4',
    uint32 = '>I4',
    int64 = '>i8',
    uint64 = '>I8',
    float = '>f',
    double = '>D'
}

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
    self._log:notice(name .. " Application initlized")
end

--- 应用启动函数
function app:start()
    --- 加载设备配置信息（设备参数，点信息等）
    local devinfo = require 'userlib.conf'
    -- local Link = require 'userlib.linkcfg'
    --- 设定回调处理函数
    self._api:set_handler({
        on_output = function(app, sn, output, prop, value)
            self._log:notice('on_output', app, sn, output, prop, value)
            local devsyy = self._devsyy
            local dev = devsyy[sn][1]
            local stat = devsyy[sn][2]
            local client = devsyy[sn][3]
            local outputs = devsyy[sn][4]

            local devsn = devsyy[sn][5]
            local devaddr = devsyy[sn][6]        
            local protocol = string.lower(devsyy[sn][7])
            self._log:notice("ouput name: ", output, value, devaddr, devsn, protocol)
            for i, v in ipairs(outputs) do
                if output == v.name then
                    self._log:notice("this is target name: " .. v.name)
                    -- for p, q in pairs(v) do
                    --     self._log:info(p, q)
                    -- end
                    self._log:info(v.name, v.desc, v.rw, v.saddr, v.fc, v.dt)
                    local fc = _register_format(tostring(v.fc))
                    if fc=='05' then
                        if value then
                            value = 1
                        else
                            value = 0
                        end
                    end
                    local msg = modbus_cmd[fc]._encode(devaddr, v.fc, v.saddr, v.dt, tonumber(value)/v.rate)
                    self._log:notice("ouput mes: ", v.name, v.saddr, v.fc, v.vt, basexx.to_hex(msg))
                    local r, pdu, err = pcall(function(msg, timeout)
                        --- 发出报文
                        dev:dump_comm(devsn .. '-下置-发送', msg)
                        self._log:info(v.name .. '-下置-发送', basexx.to_hex(msg))
                        --- 统计发出数据
                        stat:inc('packets_out', 1)
                        self._writing = true
                        if protocol == "rtu" then
                            return client:rtu_wrequest(msg, 8, timeout)
                        end
                        if protocol == "tcp" then
                            return client:tcp_wrequest(msg, 12, timeout)
                        end
                    end, msg, 300)


                    if not r then
                        local resp = tostring(pdu)
                        if string.find(resp, 'timeout') then
                            self._log:debug(resp, err)
                        else
                            self._log:warning(resp, err)
                        end
                        self._log:info(v.name .. " Write Failed")
                        return
                    end
                    if pdu then
                        --- 收到报文
                        dev:dump_comm(devsn .. '-下置-接收', pdu)
                        self._log:info(v.name .. '-下置-接收', basexx.to_hex(pdu))
                        --- 统计收到数据
                        stat:inc('packets_in', 1)
                        dev:set_input_prop_emergency(v.name, "value", tonumber(value), self._sys:time(), 0)
                        self._log:info(v.name .. " Write successful")
                    end
                end
            end
            return true, "done"
        end,
        on_ctrl = function(app, sn, command, param, ...)
            self._log:notice('on_ctrl', app, sn, command, param, ...)
        end,
    })

    ---获取设备序列号和应用配置
    local sys_id = self._sys:id()

    local Link = self._conf

    if Link == nil then
        Link = require 'userlib.linkcfg'
    else
        if next(Link) == nil then
            Link = require 'userlib.linkcfg'
        end
    end

    local devsxx = {}
    local devsyy = {}
    local smclient = nil

    self._log:info("Link type:", Link)

    if Link.Link_type == 'socket' then
        self._log:notice("-------------", Link.Link_type)
        -- client = socketchannel.channel(devA.Link_type.socket)
        smclient = sm_client(socketchannel, Link.socket)
        modbus_cmd = require 'userlib.modbus_tcp'
    else
        -- client = serialchannel.channel(devA.Link_type.serial)
        smclient = sm_client(serialchannel, Link.serial)
        modbus_cmd = require 'userlib.modbus_rtu'
    end


    for i, dev in ipairs(Link.devs) do
        -- self._log:notice("-------------",dev.sn, dev.name, dev.addr)
        --- 加载CSV点表并分析
        csv_tpl.init(self._sys:app_dir())
        local tplfile = dev.tpl or "tpl1"
        local tpl, err = csv_tpl.load_tpl(tplfile)
        local _points = {}
        local new_inputs = nil
        local _packs = {}
        local new_packs = {}
        if not tpl then
            self._log:error("loading csv tpl failed", err)
        else
            _points = parser._fc_split(tpl.inputs)
        end

        for k, v in pairs(_points) do
            -- self._log:info(#v)
            if #v > 0 then
                new_inputs = parser._sort(v, 'saddr')
                _packs = parser._split(new_inputs, 64)
                table.move(_packs, 1, #_packs, #new_packs + 1, new_packs)
            end

        end

        --- 加载CSV点表并分析
        --- 根据配置信息添加采集项
        local now = self._sys:time()
        local inputs = {}
        local outputs = {}
        for i, v in ipairs(new_packs) do
            for m, n in ipairs(v.inputs) do
                table.insert(inputs, n)
                if string.upper(n.rw) == string.upper("rw") then
                    if n.fc == "3" and _dt_len_map[n.dt] > 1 then
                        n.fc = 16
                    elseif n.fc == "3" then
                        n.fc = 6                
                    end
                    if n.fc == "2" then
                        n.fc = 5
                    end
                    table.insert(outputs, n)
                end
            end
        end

        -- local ouputs = devinfo.outputs
        --- 生成设备的序列号
        local dev_sn = sys_id .. "." .. dev.name .. "." .. dev.sn
        --- 生成设备对象
        local meta = self._api:default_meta()
        if (dev.name ~= nil) then
            meta.inst = dev.name
        else
            meta.inst = devinfo.meta.name
        end
        meta.description = devinfo.meta.description
        meta.series = devinfo.meta.series
        meta.manufacturer = devinfo.meta.manufacturer

        local mbdev = self._api:add_device(dev_sn, meta, inputs, outputs)

        --- 设备对象设置初值，IO点数值为0，质量戳为1
        -- self._log:notice(dev_sn, "设置初值")
        for i, v in ipairs(new_packs) do
            for m, n in ipairs(v.inputs) do
                mbdev:set_input_prop(n.name, "value", 0, self._sys:time(), 99)
            end
        end

        --- 生成设备通讯口统计对象
        local devstat = mbdev:stat('port')

        local devobj = {}
        devobj["dev"] = mbdev
        devobj["protocol"] = Link.protocol
        devobj["devsn"] = dev_sn
        devobj["addr"] = dev.addr
        devobj["client"] = smclient
        devobj["stat"] = devstat
        devobj["conf"] = new_packs
        devobj["event_trigger"] = {}
        devsyy[dev_sn] = { mbdev, devstat, smclient, outputs, dev_sn, dev.addr, Link.protocol }
        table.insert(devsxx, devobj)
    end

    --- 设定通讯口数据回调
    self._devsxx = devsxx
    self._devsyy = devsyy
    return true
end

--- 应用退出函数
function app:close(reason)
    self._log:notice(self._name, reason)
end

--- 应用运行入口
function app:run(tms)
    -- self._log:notice(self._name, "Start!")
    local devsxx = self._devsxx
    for i, dev in ipairs(devsxx) do
        local client = dev.client
        local mbdev = dev.dev
        local stat = dev.stat
        local conf = dev.conf
        local devaddr = dev.addr
        local devsn = dev.devsn
        local protocol = string.lower(dev.protocol) or "rtu"
        if not client then
            return
        end
        -- self._log:notice(devsn, "start!")
        for i, v in ipairs(conf) do
            if self._writing then
                self._log:notice(i, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
                self._sys:sleep(100)
                self._writing = false
            end
            -- self._log:notice(i, "begin!")
            local now = self._sys:time()
            local devconf = v.conf
            local pack_mes = nil
            local fc = _register_format(devconf.mb_cmd)
            local reg_len = devconf.reg_len


            -- self._log:notice("+++++++++",devaddr, fc, devconf.start_reg, reg_len)
            pack_mes = modbus_cmd[fc]._encode(devaddr, fc, devconf.start_reg, reg_len)
            -- self._log:notice("@@@@@@@!", basexx.to_hex(pack_mes))
            -- self._log:notice("@@@@@@@!", protocol)
            local r, pdu, err = pcall(function(pack_mes, devaddr, fc, reg_len, timeout)
                --- 发出报文
                mbdev:dump_comm(devaddr .. '-采集-发送', pack_mes)
                --- 统计发出数据
                stat:inc('packets_out', 1)
                if protocol == "rtu" then
                    return client:rtu_request(pack_mes, devaddr, fc, reg_len, timeout)
                end
                if protocol == "tcp" then
                    return client:tcp_request(pack_mes, devaddr, fc, reg_len, timeout)
                end
            end, pack_mes, devaddr, fc, reg_len, 300)

            --- pcall执行出错，产生事件
            if not r then
                local resp = tostring(pdu)
                local event_info = {
                    error = resp,
                    start_time = now,
                    time = self._sys:time(),
                    devaddr = devaddr,
                    fc = fc,
                    start_reg = devconf.start_reg,
                    reg_len = reg_len
                }
                self._log:notice("^^^^^^^^^^^^^^^^^^^^^^", devsn, resp)
                if string.find(resp, 'Serial read timeout') then
                    self._log:debug("0", devsn .. "返回为空")
                    stat:inc('packets_error', 1)
                    if not mbdev._link_error then
                        mbdev:fire_event(event.LEVEL_FATAL, event.EVENT_COMM, devsn .. "返回为空!", event_info)
                        mbdev._link_error = true
                        mbdev._link_error_time = now
                    end
                    if mbdev._link_error_time and (now - mbdev._link_error_time) > 3600 then
                        mbdev:fire_event(event.LEVEL_FATAL, event.EVENT_COMM, devsn .. "返回为空!", event_info)
                        mbdev._link_error_time = now
                    end

                elseif string.find(resp, 'socket: disconnect') or string.find(resp, 'Error: socket') then
                    self._log:debug("0", devsn .. "连接断开")
                    stat:inc('packets_error', 1)
                    if not mbdev._link_error then
                        mbdev:fire_event(event.LEVEL_FATAL, event.EVENT_COMM, devsn .. "连接断开!", event_info)
                        mbdev._link_error = true
                        mbdev._link_error_time = now
                    end
                    if mbdev._link_error_time and (now - mbdev._link_error_time) > 3600 then
                        mbdev:fire_event(event.LEVEL_FATAL, event.EVENT_COMM, devsn .. "连接断开!", event_info)
                        mbdev._link_error_time = now
                    end

                else
                    self._log:warning("2", devsn .. resp, err)
                    stat:inc('packets_error', 1)
                    if not mbdev._msg_error then
                        mbdev:fire_event(event.LEVEL_ERROR, event.EVENT_COMM, devsn .. "报文错误!", event_info)
                        mbdev._msg_error = true
                        mbdev._msg_error_time = now
                    end
                    if mbdev._msg_error_time and (now - mbdev._msg_error_time) > 3600 then
                        mbdev:fire_event(event.LEVEL_ERROR, event.EVENT_COMM, devsn .. "报文错误!", event_info)
                        mbdev._msg_error_time = now
                    end
                end
                --- 通讯出错时设置设备IO点数值为上一次数值，质量戳为1
                for p, q in ipairs(v.inputs) do
                    local lastvalue = mbdev:get_input_prop(q.name, "value")
                    mbdev:set_input_prop(q.name, "value", lastvalue, now, 1)
                end
                -- break
            else
                --- 收到报文
                -- self._log:notice(devsn.."-"..i, "successful!")
                -- self._log:notice("**********!", basexx.to_hex(pdu))
                mbdev:dump_comm(devaddr .. '-采集-接收', pdu)
                --- 统计收到数据
                stat:inc('packets_in', 1)

                local data_set = modbus_cmd[fc]._decode(pdu, v.inputs, "big")

                --- 对设备IO点写数
                if data_set then                                
                    for p, q in ipairs(v.inputs) do
                        -- self._log:info("NO:", p, q.name," Value:", data_set[p])
                        mbdev:set_input_prop(q.name, "value", data_set[p], now, 0)
                    end
                end
            end
            -- self._log:notice(i, "end!")
            self._sys:sleep(100)
        end
        -- self._log:notice(devsn, "end!")
        self._sys:sleep(100)
    end

    -- 分割线----------------------------------------
    --- 循环周期
    return 3000
end

--- 返回应用对象
return app