local sim_dev =
    {
        meta = {name="simulator", description = "simulator", series = "001"},
        inputs = {
                    {name = "Dtag1", desc = "Dtag dsc", vt = "int16", addr = "0", PLC_cmd = "wr", regname = "D", start_reg = "0"},
                    {name = "Dtag2", desc = "Dtag dsc", vt = "int16", addr = "0", PLC_cmd = "wr", regname = "D", start_reg = "1"},
                    {name = "Dtag3", desc = "Dtag dsc", vt = "int16", addr = "0", PLC_cmd = "wr", regname = "D", start_reg = "2"},
                },
              
    }
return sim_dev