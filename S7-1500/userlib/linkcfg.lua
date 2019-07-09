local cfg = {
    meta = { name = "siemens_S7_1500", description = "siemens_S7_1500_plc", series = "1500", manufacturer = "siemens" },
    inputs = {
        { name = "ModuleTypeName", desc = "ModuleTypeName", dt = "string"},
        { name = "SerialNumber", desc = "SerialNumber", dt = "string"},
        { name = "ASName", desc = "ASName", dt = "string"},
        { name = "ModuleName", desc = "ModuleName", dt = "string"},
        { name = "PlcStatus", desc = "PlcStatus", dt = "string"}
    },
    tpls = {
        {  id = "TPL000000109",  name = "tpl1",  ver = 2 },
        {  id = "TPL000000110",  name = "tpl2",  ver = 3 },
    },
    devs = {
        {sn = "1", name = "tunliu_plc_1500", host = "192.168.3.25", rack=0, slot=0, tpl="tpl1"},
    }
}

return cfg