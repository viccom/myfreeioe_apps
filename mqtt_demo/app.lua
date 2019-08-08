local ioe = require 'ioe'
local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'

local sub_topics = {
	"app/#",
	"sys/#",
	"output/#",
	"command/#",
}

function split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function ( w )
        table.insert(resultStrList,w)
    end)
    return resultStrList
end
function revtable(t)
	local newtable = {}
	for k,v in pairs(t) do
		newtable[v]=true
	end
	return newtable
end

--- 注册对象(请尽量使用唯一的标识字符串)
local app = mqtt_app:subclass("_MQTT_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.static.API_VER = 4

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	--- 更新默认配置
	if conf.username ~= nil then
	    if #conf.username>0 then
        	conf.username = conf.username
        	conf.password = conf.password
    	else
    	    conf.username = "demo"
        	conf.password = "qWZ/lxXqz2W33NZir6MW13RpCPAFELSiirVvGDfaaQw="
    	end
	end
	conf.server = conf.server or "dongbala.top"
	conf.port = conf.port or 1883
	
	if conf.period ~= nil then
    	    conf.period = conf.period
	else
	    conf.period = 10
	end
	if conf.devs ~= nil then
    	if #conf.devs>0 then
    	    self._filters = revtable(split(conf.devs,','))
    	end
	end
	if conf.enable_compress ~= nil then
        self._enable_compress = conf.enable_compress
	end
	if conf.enable_batch ~= nil then
        self._enable_batch = conf.enable_batch
	end

	if conf.enable_data_cache ~= nil then
		conf.enable_data_cache = conf.enable_data_cache
	else
		conf.enable_data_cache = 0
	end
-- 	conf.enable_tls = conf.enable_tls or false
-- 	conf.tls_cert = "root_cert.pem"
    
	--- 基础类初始化
	mqtt_app.initialize(self, name, sys, conf)
	
    self._log = sys:logger()
    self._mqtt_topic_prefix = sys:id()
	self._log:info("_filters is::", cjson.encode(self._filters))
end

function app:on_input(src_app, sn, input, prop, value, timestamp, quality)
    if self._filters~=nil then
        -- self._log:info("sn is::", sn)
        if (self._filters[sn]) then
            mqtt_app.on_input(self, src_app, sn, input, prop, value, timestamp, quality)
        end
    else
        mqtt_app.on_input(self, src_app, sn, input, prop, value, timestamp, quality)
    end
end

function app:on_publish_data(key, value, timestamp, quality)
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	local msg = {
		sn = sn,
		input = input,
		prop = prop,
		value = value,
		timestamp = timestamp,
		quality = quality
	}
	return self:publish(self._mqtt_topic_prefix.."/data", cjson.encode(msg), 0, false)
end

function app:on_publish_data_list(val_list)
    -- self._log:info("val_list is::", cjson.encode(val_list))
    local data=cjson.encode(val_list)

    if self._enable_batch ~= nil and self._enable_batch==false then
    	for _, v in ipairs(val_list) do
    		self:on_publish_data(table.unpack(v))
    	end
    	return true
    
    end
    
    if self._enable_compress ~= nil and self._enable_compress then
        data = self:compress(data)
        self:publish(self._mqtt_topic_prefix.."/data_gz", data, 0, false)
	    return true
        
    end
    
    self:publish(self._mqtt_topic_prefix.."/data", data, 0, false)
    return true
end

function app:on_publish_cached_data_list(val_list)
	local data=self:compress(cjson.encode(val_list))
	self:publish(self._mqtt_topic_prefix.."/cached_data_gz", data, 0, false)
	return true
end

function app:on_event(app, sn, level, data, timestamp)
    if self._filters~=nil then
        if (self._filters[sn]) then
        	local msg = {
        		app = app,
        		sn = sn,
        		level = level,
        		data = data,
        		timestamp = timestamp,
        	}
        	return self:publish(self._mqtt_topic_prefix.."/events", cjson.encode(msg), 1, false)
    	end
	end
end

function app:on_stat(app, sn, stat, prop, value, timestamp)
	local msg = {
		app = app,
		sn = sn,
		stat = stat,
		prop = prop,
		value = value,
		timestamp = timestamp,
	}
	return self:publish(self._mqtt_topic_prefix.."/statistics", cjson.encode(msg), 1, false)
end

function app:on_publish_devices(devices)
    -- self._log:info(" devices is:", cjson.encode(devices))
    local newdevs = {}
    if self._filters~=nil then
        -- self._log:info(" devices length:", #devices)
        for k, v in pairs(devices) do
            -- self._log:info(k.." is::", cjson.encode(self._filters[k]))
            if (self._filters[k]) then
                newdevs[#newdevs + 1] = v
            end
        end
    else
        for k, v in pairs(devices) do
            newdevs[#newdevs + 1] = v
        end
    end
    
    if #newdevs >0 then
        if self._enable_compress ~= nil and self._enable_compress then
            local data=self:compress(cjson.encode(newdevs))
            self:publish(self._mqtt_topic_prefix.."/devices", nil, 1, true)
            return self:publish(self._mqtt_topic_prefix.."/devices_gz", data, 1, true)
        else
            self:publish(self._mqtt_topic_prefix.."/devices_gz", nil, 1, true)
            return self:publish(self._mqtt_topic_prefix.."/devices", cjson.encode(newdevs), 1, true)
        end
	end
end

function app:on_mqtt_connect_ok()
	for _, v in ipairs(sub_topics) do
		self:subscribe(self._mqtt_topic_prefix.."/"..v, 1)
	end
	return self:publish(self._mqtt_topic_prefix.."/status", cjson.encode({device=self._mqtt_topic_prefix, status="ONLINE", time=ioe.time()}), 1, true)
end

function app:on_mqtt_message(packet_id, topic, payload, qos, retained)
	if topic == 'output' then
		local data = cjson.encode(payload)
		local traceid = data.data.id
		local dev_sn = data.data.device
		local output = data.data.output
		local value = data.data.value
		local device, err = self._api:get_device(dev_sn)
		if not device then
			self._log:error('Cannot parse payload!')
			return self:publish(self._mqtt_topic_prefix.."/result/output", cjson.encode({id=traceid, result=false}), 1, true)
		end
		local priv = { id = traceid, dev_sn = dev_sn, input = output }
		local r, err = device:set_output_prop(output, 'value', value, ioe.time(), priv)
		if not r then
			self._log:error('Set output prop failed!', err)
			return self:publish(self._mqtt_topic_prefix.."/result/output", cjson.encode({id=traceid, result=false}), 1, true)
		end
		return self:publish(self._mqtt_topic_prefix.."/result/output", cjson.encode({id=traceid, result=true}), 1, true)
	end
	--print(...)
end

function app:on_output_result(app_src, priv, result, err)
	if result then
		return self:publish(self._mqtt_topic_prefix.."/result/output", cjson.encode({id=priv.id, result=true}), 1, true)
	else
		return self:publish(self._mqtt_topic_prefix.."/result/output", cjson.encode({id=priv.id, result=false}), 1, true)
	end
end

function app:mqtt_will()
	return self._mqtt_topic_prefix.."/status", cjson.encode({device=self._mqtt_topic_prefix, status="OFFLINE"}), 1, true
end

--- 返回应用对象
return app
