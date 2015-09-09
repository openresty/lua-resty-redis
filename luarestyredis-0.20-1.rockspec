package = "LuaRestyRedis"
version = "0.20-1"
source = {
   url = "https://github.com/openresty/lua-resty-redis/archive/v0.20.tar.gz",
   md5 = "215a838573418077fe558e4a2cba8bc2",
   dir = "lua-resty-redis-0.20",
}
description = {
   summary = "Lua redis client driver for the ngx_lua based on the cosocket API",
   detailed = [[
		lua-resty-redis - Lua redis client driver for the ngx_lua based on the cosocket API
   ]],
   license = "BSD",
   homepage = "https://github.com/openresty/lua-resty-redis",
}
dependencies = {
   "lua >= 5.0"
}
build = {
   type = "builtin",
   modules = {
      resty_redis = "lib/resty/redis.lua",
   },
   copy_directories = { "t", },
}

