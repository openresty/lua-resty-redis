
Name
====

lua-resty-redis-cluster 

Table of Contents
=================

* [Name](#name)
* [Status](#status)
* [Description](#description)
* [Install](#Install)
* [Example](#Example)



Status
======

This library is considered production ready.

Description
===========

This Lua library is a redis cluster client driver implement for the ngx_lua nginx module:

This Lua library takes advantage of [https://github.com/openresty/lua-resty-redis](https://github.com/agentzh) and [https://github.com/cuiweixie/lua-resty-redis-cluster]

Install
========

### Compile luacrc16

```shell
make clean && make install
```
###nginx.conf add config:
```
lua_shared_dict redis_dict 100k;
```

`Note:`

* the compile luacrc16 need lua.h lualib.h lauxlib.h .If not exist, you need to change them that comes with openresty

```lua
-- modify before
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

-- modify after
#include </usr/local/openresty/luajit/include/luajit-2.1/lua.h>
#include </usr/local/openresty/luajit/include/luajit-2.1/lualib.h>
#include </usr/local/openresty/luajit/include/luajit-2.1/lauxlib.h>
```

### Add lib
add rediscluster.lua and lua-resty-redis libray in nginx.conf like:

lua_package_path "/path/lualib/?.lua;";
lua_package_cpath "/path/lualib/?.so;";

Example
========
```
content_by_lua '
local config = {
name = "test",
serv_list = {
{ip="127.0.0.1", port = 7001},
{ip="127.0.0.1", port = 7002},
{ip="127.0.0.1", port = 7003},
{ip="127.0.0.1", port = 7004},
{ip="127.0.0.1", port = 7005},
{ip="127.0.0.1", port = 7006},
},
}
local redis_cluster = require "resty.rediscluster"
local red_c =  redis_cluster:new(config)
local ok, err = red_c:set("hello","world")
local result, err = red_c:get("hello")
ngx.say(result)
';
```

### Add default parameters
Default parameters can be set in the configuration if necessary just like:
```
content_by_lua '
local config = {
name = "test",
serv_list = {
{ip="127.0.0.1", port = 7001},
{ip="127.0.0.1", port = 7002},
{ip="127.0.0.1", port = 7003},
{ip="127.0.0.1", port = 7004},
{ip="127.0.0.1", port = 7005},
{ip="127.0.0.1", port = 7006},
connect_timeout=10, --in ms
keepalive_conns=50,
keepalive_timeout=100,
},
}
local redis_cluster = require "resty.rediscluster"
local red_c =  redis_cluster:new(config)
local ok, err = red_c:set("hello","world")
local result, err = red_c:get("hello")
ngx.say(result)
';
```

### Add instance management
In high concurrency scenarios, the threshold of redis instances can be controlled by instance management. When the number of instances exceeds instance_max, no instances are created in order to protect redis.

####nginx.conf add config:
```
lua_shared_dict redis_dict 100k;
```
```
content_by_lua '
local config = {
name = "test",
serv_list = {
{ip="127.0.0.1", port = 7001},
{ip="127.0.0.1", port = 7002},
{ip="127.0.0.1", port = 7003},
{ip="127.0.0.1", port = 7004},
{ip="127.0.0.1", port = 7005},
{ip="127.0.0.1", port = 7006},
instance_max = 5000.
},
}
local redis_cluster = require "resty.rediscluster"
local red_c =  redis_cluster:new(config)
local ok, err = red_c:set("hello","world")
local result, err = red_c:get("hello")
ngx.say(result)
';
```



Copyright 
=====================

Copyright (C) 2018. 

[Back to TOC](#table-of-contents)




