local ftcsv = require 'ftcsv'
local log = require 'utils.log'

local tpl_dir = 'tpl/'

local function load_tpl(name)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local alarms = {}


	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'alarm' then
				local input = {
					staname = v[2],
					gatesn = v[3],
					devicesn = v[4],
					tagname = v[5],
					tagdesc = v[6],
					tagvt = v[7],
					threshold = v[8],

				}
				alarms[#alarms + 1] = input
			end
		end
	end

	return alarms
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
