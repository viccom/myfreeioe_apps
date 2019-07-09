local class = require 'middleclass'
local datacenter = require 'skynet.datacenter'
local cjson = require 'cjson.safe'
local md5 = require 'md5'
local redis  = require "skynet.db.redis"


--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("sendto_redis")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1

local redisconf = nil

--- Whether using the async mode (which cause crashes for now -_-!)
local close_connection = false

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = self._sys:data_api()
	self._log = sys:logger()
end

function app:start()
	local sys = self._sys
	local log = self._log
	local redisconf = {
		host = "172.30.0.187",
		port = 6379,
		db = 0,
		auth = "Pa88word",
		appinst = "HWUPS2000"
	}

	-- self._log:info("host:", redisconf.host, redisconf.port, redisconf.db, redisconf.auth)

	local r, redisdb = pcall(redis.connect, redisconf)
	if not r then
		self._log:info("???????????", redisdb)
		return false
	end
	self._log:info("!!!!!!!!!!!!!")
	self._api:set_handler({
		on_input = function(app, sn, input, prop, value, timestamp, quality)
			-- local key = table.concat({sn, input, prop}, '/')
			local timestamp = timestamp or sys:time()
			local quality = quality or 0
			-- log:trace('app inst:', app, sn)
			if app==redisconf.appinst then
				if redisdb then
					log:info("Publish data", sn, input, value, timestamp, quality)
					local val = cjson.encode({timestamp, value, quality}) or value
					redisdb:set(input.."/"..prop, val, 'ex', '600')
				end			
			end
		end,
	}, true)

	local sys_id = self._sys:id()
	return true
end



function app:close(reason)
	--print(self._name, reason)
end

function app:run(tms)
	--connect_proc()
	return 1000 * 1
end

return app