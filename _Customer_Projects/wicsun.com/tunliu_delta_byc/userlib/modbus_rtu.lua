-- modbus decode functions
-- 
local basexx = require 'basexx'
local sum = require 'hashings.sum'
local log = require 'utils.log'
local crc16 = require 'userlib.crc16'
local NumConvert = require 'userlib.NumConvert'

local _M = {}

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

local _byte_len_map = {
    int8 = 1,
    uint8 = 1,
    int16 = 2,
    uint16 = 2,
    int32 = 4,
    uint32 = 4,
    int64 = 8,
    uint64 = 8,
    float = 4,
    double = 8
}

local big_dt_format = {
    int8 = '>i1',
    uint8 = '>I1',
    int16 = '>i2',
    uint16 = '>I2',
    int32 = '>i4',
    uint32 = '>I4',
    int64 = '>i8',
    uint64 = '>I8',
    float = '>f',
    double = '>d'
}

local little_dt_format = {
    int8 = '<i1',
    uint8 = '<I1',
    int16 = '<i2',
    uint16 = '<I2',
    int32 = '<i4',
    uint32 = '<I4',
    int64 = '<i8',
    uint64 = '<I8',
    float = '<f',
    double = '<d'
}

_M["01"] = {}
-- 01功能码发送报文组合，地址，寄存器名称，开始地址，长度
_M["01"]._encode = function(addr, fc, startnum, reglen)
    local pack_bin =  string.pack(">I1", addr) .. string.pack(">I1", fc) .. string.pack(">I2", startnum) .. string.pack(">I2", reglen)
    return pack_bin .. string.pack("<I2", crc16(pack_bin))
end

-- 01功能码返回报文解析，IO点数量
_M["01"]._decode = function(response_mes, inputs)
    local datas = string.sub(response_mes, 4, -3)
    local start_reg = inputs[1].saddr
    local mynum = string.unpack('<I'..#datas, datas)
    local datastr =  string.reverse(NumConvert.ConvertDec2X(mynum, 2))
    if (#datastr ~= #datas*8) then
        datastr = datastr..string.rep('0', (#datas*8-#datastr))
    end
    local rdata_set = {}
    for p, q in ipairs(inputs) do
        local _pos = q.saddr - start_reg + 1
        local _val = tonumber(string.sub(datastr, _pos, _pos))
        table.insert(rdata_set, _val)
    end
    
    -- local start_reg = tonumber(inputs[0].saddr)
    -- local end_reg = tonumber(inputs[#inputs].saddr)
    -- local ionums = end_reg - start_reg + 1

    -- local data_set = {}
    -- for i=1, ionums, 1 do
    --     local index = math.floor((i-1) / 8) + 1
    --     local bindex = (i - 1) % 8
    --     local b = string.sub(datas, index, index)
    --     local value = string.byte(b)
    --     value = 1 & (value >> bindex)
    --     table.insert(data_set, value)
    -- end

    -- local rdata_set = {}
    -- for p, q in ipairs(inputs) do
    --     local _pos = q.saddr - start_reg + 1
    --     local _val = data_set[_pos]
    --     table.insert(rdata_set, _val)
    -- end

    return rdata_set
end

_M["02"] = {}
-- 01功能码发送报文组合，地址，寄存器名称，开始地址，长度
_M["02"]._encode = function(addr, fc, startnum, reglen)
    local pack_bin =  string.pack(">I1", addr) .. string.pack(">I1", fc) .. string.pack(">I2", startnum) .. string.pack(">I2", reglen)
    return pack_bin .. string.pack("<I2", crc16(pack_bin))
end

-- 02功能码返回报文解析，IO点数量
_M["02"]._decode = function(response_mes, inputs)
    local datas = string.sub(response_mes, 4, -3)
    local start_reg = inputs[1].saddr
    local mynum = string.unpack('<I'..#datas, datas)
    local datastr =  string.reverse(NumConvert.ConvertDec2X(mynum, 2))
    if (#datastr ~= #datas*8) then
        datastr = datastr..string.rep('0', (#datas*8-#datastr))
    end
    local rdata_set = {}
    for p, q in ipairs(inputs) do
        local _pos = q.saddr - start_reg + 1
        local _val = tonumber(string.sub(datastr, _pos, _pos))
        table.insert(rdata_set, _val)
    end

    return rdata_set
end

_M["03"] = {}
-- 03功能码发送报文组合，地址，寄存器名称，开始地址，长度
_M["03"]._encode = function(addr, fc, startnum, reglen)
    -- log.info(addr, fc, startnum, reglen)
    local pack_bin =  string.pack(">I1", addr) .. string.pack(">I1", fc) .. string.pack(">I2", startnum) .. string.pack(">I2", reglen)
    return pack_bin .. string.pack("<I2", crc16(pack_bin))
end


-- 03功能码返回报文解析，
_M["03"]._decode = function(response_mes, inputs, Endian)
    local datas = string.sub(response_mes, 4, -3)
    local start_reg = inputs[1].saddr
    local data_set = {}
    for p, q in ipairs(inputs) do

        local start_pos = q.saddr * 2 - start_reg * 2 + 1
        local end_pos = (q.saddr + _dt_len_map[q.dt]) * 2 - start_reg * 2
        local val, index
        if Endian=="big" then
            val, index = string.unpack(big_dt_format[q.dt], string.sub(datas, start_pos, end_pos)) * q.rate
        else
            val, index = string.unpack(little_dt_format[q.dt], string.sub(datas, start_pos, end_pos)) * q.rate
        end
        if q.dt=="float" or q.dt=="double" then
            val = (math.ceil(val * 10 ^ 4)) / 10 ^ 4
        end
        table.insert(data_set, val)
    end
    return data_set

end

_M["04"] = {}
-- 04功能码发送报文组合，地址，寄存器名称，开始地址，长度
_M["04"]._encode = function(addr, fc, startnum, reglen)
    local pack_bin =  string.pack(">I1", addr) .. string.pack(">I1", fc) .. string.pack(">I2", startnum) .. string.pack(">I2", reglen)
    return pack_bin .. string.pack("<I2", crc16(pack_bin))
end

-- 04功能码返回报文解析，IO点数量，所有的点类型一致（int16,uint16,int32, uint32, float, double, string）
_M["04"]._decode = function(response_mes, inputs, Endian)
    local datas = string.sub(response_mes, 4, -3)
    local start_reg = inputs[1].saddr
    local data_set = {}
    for p, q in ipairs(inputs) do

        local start_pos = q.saddr * 2 - start_reg * 2 + 1
        local end_pos = (q.saddr + _dt_len_map[q.dt]) * 2 - start_reg * 2
        local val, index
        if Endian=="big" then
            val, index = string.unpack(big_dt_format[q.dt], string.sub(datas, start_pos, end_pos)) * q.rate
        else
            val, index = string.unpack(little_dt_format[q.dt], string.sub(datas, start_pos, end_pos)) * q.rate
        end
        if q.dt=="float" or q.dt=="double" then
            val = (math.ceil(val * 10 ^ 4)) / 10 ^ 4
        end
        table.insert(data_set, val)
    end
    return data_set

end


_M["05"] = {}
-- 05功能码发送报文组合，地址，寄存器名称，开始地址，长度
_M["05"]._encode = function(addr, fc, startnum, datatype, value)
    -- log.info("05 FC::", addr, fc, startnum, datatype, value)
    local valuebin = string.pack(">I1", 255)..string.pack(">I1", 0)
    if tonumber(value)==0 then
        valuebin = string.pack(">I2", 0)
    end
    local pack_bin =  string.pack(">I1", addr) .. string.pack(">I1", fc) .. string.pack(">I2", startnum) .. valuebin
    return pack_bin .. string.pack("<I2", crc16(pack_bin))
end


_M["06"] = {}
-- 06功能码发送报文组合，地址，寄存器名称，开始地址，长度
_M["06"]._encode = function(addr, fc, startnum, datatype, value)
    -- log.info("06 FC::", addr, fc, startnum, datatype, math.floor(value), big_dt_format[datatype])
    local valuebin = string.pack(big_dt_format[datatype], math.floor(value))
    local pack_bin =  string.pack(">I1", addr) .. string.pack(">I1", 6) .. string.pack(">I2", startnum) .. valuebin
    return pack_bin .. string.pack("<I2", crc16(pack_bin))
end

_M["16"] = {}
-- 06功能码发送报文组合，地址，寄存器名称，开始地址，长度
_M["16"]._encode = function(addr, fc, startnum, datatype, value)
    -- log.info("16 FC::", addr, fc, startnum, datatype, value)
    local regnum = _dt_len_map[datatype]
    local datalen = regnum * 2
    local valuebin = string.pack(big_dt_format[datatype], value)
    local pack_bin =  string.pack(">I1", addr) .. string.pack(">I1", 16) .. string.pack(">I2", startnum) .. string.pack(">I2", regnum) .. string.pack(">I1", datalen) .. valuebin
    return pack_bin .. string.pack("<I2", crc16(pack_bin))
end

--- 返回对象
return _M