local skynet = require 'skynet'
local class = require 'middleclass'
local basexx = require 'basexx'
local sum = require 'hashings.sum'

local client = class("_Ser_Client")

function client:initialize(sc, opt)
	local channel = sc.channel(opt)
	self._chn = channel
end

function client:connect(only_once)
	return self._chn:connect(only_once)
end

------------------------------------------------------------

function client:request(msg, timeout)
	return self._chn:request(msg, make_read_response(timeout))
end

local function make_read_response(timeout)
	return function(sock)
        local ret1 = sock:read(1, timeout)
        if ret1 then
            ret2 = sock:read(1024, 100)
            while string.len(ret2) == 1024 do
                sock:read(1024, 100)
            end
            return false, ret1..ret2
        else
            return
        end
		return false, "timeout"
	end
end

------------------------------------------------------------

function client:wrequest(msg, timeout)
	return self._chn:request(msg, make_write_response(timeout))
end

local function make_write_response(timeout)
	return function(sock)
        local ret1 = sock:read(1, timeout)
        if ret1 then
            if basexx.to_hex(ret1)=="06" then
                local ret2 = sock:read(4, timeout)
                if ret2 then
                    if #ret2==4 then
                        return true, ret1..ret2
                    else
                        return false, ret1..ret2
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






return client
