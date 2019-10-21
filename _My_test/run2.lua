local cmd = "route|grep default"
local info, err = sysinfo.exec(cmd)

function split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function ( w )
        table.insert(resultStrList,w)
    end)
    return resultStrList
end

if not string.match(info, "default") then
    return nil, errinfo
else
    info = string.gsub(info, "^[%s\n\r\t]*(.-)[%s\n\r\t]*$", "%1")
    print("default route", info)
    -- local route = split(info, " ")
    -- print(route)
end