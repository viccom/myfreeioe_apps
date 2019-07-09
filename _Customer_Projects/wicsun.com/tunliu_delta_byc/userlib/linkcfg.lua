local cfg = {
    Link_type = "serial",
    protocol = "rtu",
    serial = { port = "/dev/ttymxc1", baudrate = 115200, data_bits = 8, parity = "NONE", stop_bits = 1, flow_control = "OFF" },
    socket = { host = "192.168.199.132", port = 502, nodelay = true },
    devs = {
        {sn = "1", name = "tunliu_delta_byc", addr="2", tpl="byc"},
    }
}

return cfg