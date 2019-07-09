local skynet = require 'skynet'
local class = require 'middleclass'
local basexx = require 'basexx'
local sum = require 'hashings.sum'
local log = require 'utils.log'
local crc16 = require 'userlib.crc16'

local client = class("Modbus_Client")

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


local function tcp_read_response(devaddr, fc, reqlen, timeout)
    return function(sock)
        -- log.info(devaddr, fc, reqlen, 'XXXXXXXXXXXXXXXXXXXXX')
        local ret1 = sock:read(nil)
        -- log.info("return msg::", basexx.to_hex(ret1))
        if ret1~=nil then
            local _ret1 = string.sub(ret1, 1, 6)
            local _rethead = string.sub(ret1, 7, 8)
            local rightstr  = _register_format(devaddr) .. _register_format(fc)
            if _rethead then
                if basexx.to_hex(_rethead) == rightstr then
                    local protocol_len = string.unpack('>I1', string.sub(ret1, 9, 10))
                    local ret2 = string.sub(ret1, 10)
                    if ret2~=nil then
                        if #ret2 >= protocol_len then
                            return true, ret1
                        else
                            local ret3, data = sock:read(protocol_len-#ret2)
                            if ret3 and (#ret3 + #ret2) >= protocol_len then
                                return true, ret1..ret3
                            end
                            return false, "报文长度不正确"
                        end
                    end
                    return false, "报文长度不足"
                else
                    return false, "报文错误"
                end
            end
            return false, "报文错误"
        end
        return false, "读取超时"
    end
end

local function tcp_write_response(msglen, timeout)
    return function(sock)
        local ret1 = sock:read(1, timeout)
        if ret1~=nil then
            if basexx.to_hex(ret1) == "06" then
                local ret2 = sock:read(4, timeout)
                if ret2~=nil then
                    if #ret2 == 4 then
                        return true, ret1 .. ret2
                    else
                        return false, ret1 .. ret2
                    end
                end
                return false, ret1
            else
                ret2 = sock:read(1024, 100)
                while string.len(ret2) == 1024 do
                    sock:read(1024, 100)
                end
                return false, ret1
            end
        else
            return
        end
        return false, "timeout"
    end
end


local function rtu_read_response(devaddr, fc, reqlen, timeout)
    return function(sock)
        -- log.info(devaddr, fc, reqlen, 'XXXXXXXXXXXXXXXXXXXXX')
        local ret1 = sock:read(1, timeout)
        -- log.info("return msg::", basexx.to_hex(ret1))
        if ret1~=nil then
            -- log.info("ret1", ret1)
            local ret2 = sock:read(2, timeout)
            -- log.info("ret2 msg::", basexx.to_hex(ret2))
            local rightstr  = _register_format(devaddr) .. _register_format(fc)
            if ret2~=nil then
                local _ret2 = string.sub(ret2, 1, 1)
                -- log.info("rightstr:", rightstr)
                -- log.info("ret1+_ret2:",  basexx.to_hex(ret1 .. _ret2))
                if basexx.to_hex(ret1 .. _ret2) == rightstr then
                    local protocol_len = string.unpack('>I1', string.sub(ret2, 2))
                    -- log.info("protocol_len::", protocol_len)
                    local ret3 = sock:read(protocol_len, timeout)
                    if ret3~=nil then
                        if #ret3 == protocol_len then
                            local msg_crc = string.pack("<I2", crc16(ret1 .. ret2 .. ret3))
                            local ret4 = sock:read(2, timeout)
                            if msg_crc==ret4 then
                                return true, ret1 .. ret2 .. ret3 .. ret4
                            else
                                return false, "检验码错误"
                            end

                        else
                            local ret4 = sock:read(1024, 100)
                            while string.len(ret4) == 1024 do
                                sock:read(1024, 100)
                            end
                            log.info("ret1+ret2+ret1a:",  basexx.to_hex(ret1 .. ret2 .. ret3 .. ret4))
                            return false, "报文长度不正确"
                        end
                    end
                    return false, "报文长度不足"
                end

                local ret1a = sock:read(1024, 100)
                while string.len(ret1a) == 1024 do
                    sock:read(1024, 100)
                end
                log.info("ret1+ret2+ret1a:",  string.len(ret1), string.len(ret2), string.len(ret1a) )
                log.info("ret1+ret2+ret1a:",  basexx.to_hex(ret1 .. ret2 .. ret1a))
                return false, "报文参数错误，设备地址、功能码、寄存器地址不正确"
                
            end
        else
            local ret1a = sock:read(1024, 100)
            while string.len(ret1a) == 1024 do
                sock:read(1024, 100)
            end
        
            -- log.info("ret1+ret1a:",  basexx.to_hex(ret1 .. ret1a))
            return false, "无返回内容"
        end
        return false, "读取超时"
    end
end

local function rtu_write_response(msglen, timeout)
    return function(sock)
        local ret1 = sock:read(1, timeout)
        -- log.info("ret1:", basexx.to_hex(ret1))
        if ret1==nil then
            local ret2 = sock:read(1024, 100)
            while string.len(ret2) == 1024 do
                sock:read(1024, 100)
            end
            return false, ret1
        else
            local ret2 = sock:read(msglen-1, timeout)
            if ret2~=nil then
                    return true, ret1 .. ret2
            else
                return false, ret1
            end

        end
        return false, "timeout"
    end
end

function client:initialize(sc, opt)
    local channel = sc.channel(opt)
    self._chn = channel
end

function client:connect(only_once)
    return self._chn:connect(only_once)
end

function client:tcp_request(msg, devaddr, fc, reqlen, timeout)
    return self._chn:request(msg, tcp_read_response(devaddr, fc, reqlen, timeout))
end

function client:tcp_wrequest(msg, msglen, timeout)
    return self._chn:request(msg, tcp_write_response(msglen, timeout))
end

function client:rtu_request(msg, devaddr, fc, reqlen, timeout)
    return self._chn:request(msg, rtu_read_response(devaddr, fc, reqlen, timeout))
end

function client:rtu_wrequest(msg, msglen, timeout)
    return self._chn:request(msg, rtu_write_response(msglen, timeout))
end

return client