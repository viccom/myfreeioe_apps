--- 定义目标设备的所有配置信息
-- Modbus Package function
-- addr=number
-- command="03"
-- fixed=0x000000000000
-- start_reg=
-- reg_len=
local cfg = {
    meta = { name = "DVP_12SA2", description = "delta_DVP_12SA2", series = "DVP_12SA2", manufacturer = "delta" },
    packs = {
       
    },
    outputs = {
        { name = "Citag1", desc = "Citag1 dsc", vt = "int16", addr = "1", mb_cmd = "01", start_reg = "0" },
        { name = "Citag2", desc = "Citag2 dsc", vt = "int16", addr = "1", mb_cmd = "01", start_reg = "1" },
        { name = "Citag3", desc = "Citag2 dsc", vt = "int16", addr = "1", mb_cmd = "01", start_reg = "2" },
    },
    commands = {
        { name = "stop", desc = "Dtag dsc", commands = "stop", addr = "0", PLC_cmd = "wr", start_reg = "0" },
        { name = "start", desc = "Dtag dsc", commands = "start", addr = "0", PLC_cmd = "wr", start_reg = "0" },
    },            
}

return cfg