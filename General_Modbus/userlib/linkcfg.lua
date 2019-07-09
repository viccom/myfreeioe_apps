local cfg = {    
    tpls = {               
            {  id = "TPL000000109",  name = "tpl1",  ver = 2 },               
            {  id = "TPL000000110",  name = "tpl2",  ver = 3 },           
        },   
        Link_type = "socket",   protocol = "tcp",   
        serial = { port = "/dev/ttymxc0", baudrate = 115200, data_bits = 8, 
        parity = "NONE", stop_bits = 1, flow_control = "OFF" },   
        socket = { host = "192.168.174.1", port = 502, nodelay = true },   
        devs = { 
            {sn = "xx1", name = "sim1", desc = "modbus sim1", addr="1", tpl="tpl1"},       
            {sn = "xx2", name = "sim2", desc = "modbus sim2", addr="1", tpl="tpl2"},   
        }
    }
    return cfg