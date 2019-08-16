local buf = ">4536546\nrdsfsf\n"
local str = string.match(buf, "[>]([^\r\n]-)[\r\n]")
print(str)