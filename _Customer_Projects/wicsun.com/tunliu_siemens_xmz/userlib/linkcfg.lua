local cfg = {
    meta = { name = "siemens_S7_1200", description = "General_snap7", series = "1200", manufacturer = "siemens" },
    inputs = {
        { name = "ModuleTypeName", desc = "ModuleTypeName", dt = "string"},
        { name = "SerialNumber", desc = "SerialNumber", dt = "string"},
        { name = "ASName", desc = "ASName", dt = "string"},
        { name = "ModuleName", desc = "ModuleName", dt = "string"},
        { name = "PlcStatus", desc = "PlcStatus", dt = "string"}
    },
    devs = {
        {sn = "1", name = "tunliu_plc_1200", host = "192.168.3.25", rack=0, slot=0, tpl="tpl1"},
    }
}

return cfg