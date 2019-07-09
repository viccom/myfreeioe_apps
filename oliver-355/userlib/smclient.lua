local skynet = require 'skynet'
local class = require 'middleclass'
local basexx = require 'basexx'
local sum = require 'hashings.sum'
local log = require 'utils.log'

local client = class("_Ser_Client")

local command_ret = {
	state = "state",
	tf = "trigfreq",
	trig = "trig",
	eaom_div = "eaomdiv",
	pf  ="powerfactor",
	geterrors = "geterrors",
	k = "k",
	Copyright = "Copyright",
	ontime = "ontime",
	sleeptime = "sleeptime",
	standbytime = "standbytime",
	powerontime = "powerontime"
}

function client:initialize(sc, opt)
	local channel = sc.channel(opt)
	self._chn = channel
end

function client:connect(only_once)
	return self._chn:connect(only_once)
end

------------------------------------------------------------
-- local function make_read_response(msg, timeout)
--     return function(sock)
--         local ret1 = sock:read(1, timeout)
--         if ret1 then
--             local ret2 = sock:read(1024, 100)
--             while string.len(ret2) == 1024 do
--                 sock:read(1024, 100)
--             end
--             log.info("command_return::", msg)
--             log.info("command_return msg::", ret1..ret2)
--             return true, ret1..ret2
--         end
--         return false, "timeout"
--     end
-- end

local function make_read_response(msg, timeout)
	return function(sock)
	    local buffer = {}

	    while true do
	        local ret1 = sock:read(1, timeout)
	        if ret1 then
                if msg=="k\n" then
                    local ret2 = sock:read(1024, 2000)
                    while string.len(ret2) == 1024 do
                        sock:read(1024, 100)
                    end
                    -- log.info("command_return::", msg)
                    -- log.info("command_return msg::", ret1..ret2)
                    return true, ret1..ret2
                else
    	            if ret1 == '\n' then
    	                local cmd = string.sub (msg, 1 , -3)
    	                local retstring = table.concat(buffer)
    	               -- log.info("command_return::", cmd)
    	               -- log.info("command_return msg::", retstring)
    	                local ret = string.find(retstring, command_ret[cmd], 1 , true)
    
    	                if ret==1 then
    	                    return true, retstring
    	                else
                            local ret2 = sock:read(1024, 100)
                            while string.len(ret2) == 1024 do
                                sock:read(1024, 10)
                            end
    	                    buffer = {}
    	                end
    	            else
    	                table.insert(buffer, ret1)
    	            end
                end
	            
	       else
	           break
	       end
	       
	    end
	    log.info("timeout msg::", table.concat(buffer))
	    return false, "timeout"

	end
end

function client:request(msg, timeout)
	return self._chn:request(msg, make_read_response(msg, timeout))
end
------------------------------------------------------------



local function make_write_response(msg, timeout)
    log.info("write_command::", msg)
	return function(sock)
	    local buffer = {}
	    while true do
	        skynet.sleep(0)
	        local ret1 = sock:read(1, timeout)
	        if ret1 then
	               --local ret2 = sock:read(1024, 2000)
                --     while string.len(ret2) == 1024 do
                --         sock:read(1024, 100)
                --     end
                --     -- log.info("command_return::", msg)
                --     -- log.info("command_return msg::", ret1..ret2)
                --     return true, ret1..ret2
	            if ret1 == '\n' then
	                local retstring = table.concat(buffer)
	                log.info("write_command_return msg::", retstring)
	                return true, table.concat(buffer)
	            else
	                table.insert(buffer, ret1)
	            end
	       else
	           break
	       end
	       
	    end
	    log.info("write_command timeout!")
	    return false, "timeout"

	end
end

function client:wrequest(msg, timeout)
	return self._chn:request(msg, make_write_response(msg, timeout))
end





return client
