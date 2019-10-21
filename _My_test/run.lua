-- local buf = ">4536546\nrdsfsf\n"
-- local str = string.match(buf, "[>]([^\r\n]-)[\r\n]")

local isIpaddr = false
local ip = "192.0.0.1"
-- local str = string.match(buf, "[>]([^\r\n]-)[\r\n]")
local o1,o2,o3,o4 = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
-- print(o1,o2,o3,o4)
if 223>tonumber(o1) and tonumber(o1)>0 and 255>tonumber(o2) and tonumber(o2)>=0 and 255>tonumber(o3)and tonumber(o3)>=0 and 255>tonumber(o4) and tonumber(o4)>0 then
    isIpaddr = true
end
print(isIpaddr)