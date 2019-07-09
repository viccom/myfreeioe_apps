local ftcsv = require 'ftcsv'
local log = require 'utils.log'

local tpl_dir = 'tpl/'

local function load_tpl(name)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local meta = {}
	local inputs = {}
	local outputs = {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'META' then
				meta.name = v[2]
				meta.desc = v[3]
				meta.series = v[4]
			end
			if v[1] == 'INPUT' then
				local input = {
					name = v[2],
					desc = v[3],
				}
				-- if string.len(v[4]) > 0 then
				-- 	input.vt = v[4]
				-- end
				input.unit = v[4]
				input.rw = v[5]
				input.dt = v[6]
				input.fc = v[7]
				input.dbnum = tonumber(v[8])
				input.saddr = tonumber(v[9])
				input.pos = tonumber(v[10])
				input.rate = tonumber(v[11])
				input.vt = v[12]
				-- log.info("@@@@@@",v[8])
				inputs[#inputs + 1] = input
			end
			if v[1] == 'OUTPUT' then
				local output = {
					name = v[2],
					desc = v[3],
				}
				-- if string.len(v[4]) > 0 then
				-- 	input.vt = v[4]
				-- end
				input.unit = v[4]
				input.rw = v[5]
				input.dt = v[6]
				input.fc = v[7]
				input.dbnum = tonumber(v[8])
				input.saddr = tonumber(v[9])
				input.pos = tonumber(v[10])
				input.rate = tonumber(v[11])
				input.vt = v[12]
				-- log.info("@@@@@@",v[8])
				outputs[#outputs + 1] = output
			end
		end
	end

	return {
		meta = meta,
		inputs = inputs,
		outputs = outputs
	}
end

--[[
--local cjson = require 'cjson.safe'
local tpl = load_tpl('bms')
print(cjson.encode(tpl))
]]--

return {
	load_tpl = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
