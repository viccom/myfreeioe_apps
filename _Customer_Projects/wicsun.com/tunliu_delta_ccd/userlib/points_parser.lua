local log = require 'utils.log'


local _M = {}

local _dt_len_map = {
    bool = 1,
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

local function _table_sort(_table, _key)
	local _tmptable = {}  
	for _,v in pairs(_table) do  
		table.insert(_tmptable,tonumber(v[_key]))
	end
	table.sort(_tmptable)
	local new_table = {}
	for _,key_val in pairs(_tmptable) do
		-- log:info(key_val)
		for _, v in ipairs(_table) do
			-- log:info(v[_key])
			if tonumber(v[_key]) == tonumber(key_val) then
				table.insert(new_table,v)
				-- log:info("name:",v.name,"desc:",v.desc,"fc:",v.fc,"saddr:",v.saddr,"dt:",v.dt)
			end
		end 
	end
    return new_table
end


-- table以功能码进行分割
_M._fc_split = function(_table)
    local	_fc01 = {}
	local	_fc02 = {}
	local	_fc03 = {}
    local	_fc04 = {}
    for _, v in ipairs(_table) do
        if tonumber(v.fc)==1 then
            _fc01[#_fc01 + 1] = v
        end

        if tonumber(v.fc)==2 then
            _fc02[#_fc02 + 1] = v
        end

        if tonumber(v.fc)==3 then
            _fc03[#_fc03 + 1] = v
        end

        if tonumber(v.fc)==4 then
            _fc04[#_fc04 + 1] = v
        end

    end
    local _points_table = {fc01 = _fc01, fc02 = _fc02, fc03 = _fc03, fc04 = _fc04}
    return _points_table
end


-- table以指定字段的值进行排序
_M._sort = function(_table, _key)
    return _table_sort(_table, _key)
end

-- table以指定规则拆分分多个包和点表数组
_M._split = function(_table, regmaxlen)
    local _package = {}
    local _tmp_table = {}
    local _start_addr = tonumber(_table[1].saddr)
    local _end_addr = nil
    if regmaxlen < 4 then
        regmaxlen = 4
    end
    -- log:info("_start_addr:", _start_addr)
    for i,v in pairs(_table) do
        -- log:info(v.dt)
        local datalen = _dt_len_map[v.dt]
        -- log:info(datalen)
        if i >1 and (tonumber(v.saddr) + datalen) - tonumber(_table[i-1].saddr) >= regmaxlen then
            if #_tmp_table > 0 then
                local _t = {
                    inputs = _tmp_table,
                    conf = {
                        mb_cmd = _tmp_table[1].fc,
                        start_reg = _tmp_table[1].saddr,
                        reg_len = (_tmp_table[#_tmp_table].saddr + _dt_len_map[_tmp_table[#_tmp_table].dt] - _tmp_table[1].saddr)
                    }
                }

                _package[#_package + 1] = _t
            end
            _tmp_table = {}
            _start_addr = tonumber(v.saddr)
        end
        -- log:info(tonumber(v.saddr), datalen, _start_addr)
        -- log:info(((tonumber(v.saddr) + datalen) - _start_addr) >= regmaxlen)
        if ((tonumber(v.saddr) + datalen) - _start_addr) >= regmaxlen then
            -- log:info(v.saddr)
            local _t = {
                inputs = _tmp_table,
                conf = {
                    mb_cmd = _tmp_table[1].fc,
                    start_reg = _tmp_table[1].saddr,
                    reg_len = (_tmp_table[#_tmp_table].saddr + _dt_len_map[_tmp_table[#_tmp_table].dt] - _tmp_table[1].saddr)
                }
            }

            _package[#_package + 1] = _t
            _tmp_table = {}
            table.insert(_tmp_table,v)
            if i < #_table then
                _start_addr = tonumber(v.saddr)
            end
        else
            table.insert(_tmp_table,v)
        end
    end
    if #_tmp_table > 0 then
        local _t = {
            inputs = _tmp_table,
            conf = {
                mb_cmd = _tmp_table[1].fc,
                start_reg = _tmp_table[1].saddr,
                reg_len = (_tmp_table[#_tmp_table].saddr + _dt_len_map[_tmp_table[#_tmp_table].dt] - _tmp_table[1].saddr)
            }
        }

        _package[#_package + 1] = _t
    end
    return _package
end


--- 返回对象
return _M