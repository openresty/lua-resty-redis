Name
====

lua-resty-redis - Lua redis client driver for the ngx_lua based on the cosocket API

Status
======

This library is considered experimental and still under active development.

The API is still in flux and may change without notice.

Description
===========

This Lua library is a redis client driver for the ngx_lua nginx module:

http://wiki.nginx.org/HttpLuaModule

This Lua library takes advantage of ngx_lua's cosocket API, which ensures
100% nonblocking behavior.

Note that at least [ngx_lua 0.5.0rc5](https://github.com/chaoslawful/lua-nginx-module/tags) or [ngx_openresty 1.0.11.7](http://openresty.org/#Download) is required.

Synopsis
========

    lua_package_path "/path/to/lua-resty-redis/lib/?.lua;;";

    server {
        location /test {
            content_by_lua '
                local redis = require "resty.redis"
                local red = redis:new()

                red:set_timeout(1000) -- 1 sec

                -- or connect to a unix domain socket file listened
                -- by a redis server:
                --     local ok, err = red:connect("unix:/path/to/redis.sock")

                local ok, err = red:connect("127.0.0.1", 6379)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                res, err = red:set("dog", "an aniaml")
                if not ok then
                    ngx.say("failed to set dog: ", err)
                    return
                end

                ngx.say("set result: ", res)

                local res, err = red:get("dog")
                if not res then
                    ngx.say("failed to get dog: ", err)
                    return
                end

                if res == ngx.null then
                    ngx.say("dog not found.")
                    return
                end

                ngx.say("dog: ", res)

                -- put it into the connection pool of size 100,
                -- with 0 idle timeout
                red:set_keepalive(0, 100)

                -- or just close the connection right away:
                -- local ok, err = red:close()
                -- if not ok then
                --     ngx.say("failed to close: ", err)
                --     return
                -- end
            ';
        }
    }

Methods
=======

All of the Redis commands have their own methods with the same name except all in lower case.

You can find the complete list of Redis commands here:

http://redis.io/commands

You need to check out this Redis command reference to see what Redis command accepts what arguments.

The Redis command arguments can be directly fed into the corresponding method call. For example, the "GET" redis command accepts a single key argument, then you can just call the "get" method like this:

    local res, err = red:get("key")

Similarly, the "LRANGE" redis command accepts threee arguments, then you should call the "lrange" method like this:

    local res, err = red:lrange("nokey", 0, 1)

For example, "SET", "GET", "LRANGE", and "BLPOP" commands correspond to the methods "set", "get", "lrange", and "blpop".

All these command methods returns a single result in success and `nil` otherwise. In case of errors or failures, it will also return a second value which is a string describing the error.

A Redis "status reply" results in a string typed return value with the "+" prefix stripped.

A Redis "integer reply" results in a Lua number typed return value.

A Redis "error reply" results in a `false` value *and* a string describing the error.

A non-nil Redis "bulk reply" results in a Lua string as the return value. A nil bulk reply results in a `ngx.null` return value.

A non-nil Redis "multi-bulk reply" results in a Lua table holding all the composing values (if any). If any of the composing value is a valid redis error value, then it will be a two element table `{false, err}`.

A nil multi-bulk reply returns in a `ngx.null` value.

See http://redis.io/topics/protocol for details regarding various Redis reply types.

In addition to all those redis command methods, the following methods are also provided:

new
---
`syntax: red = redis:new()`

Creates a redis object. Returns `nil` on error.

connect
-------
`syntax: ok, err = red:connect(host, port)`
`syntax: ok, err = red:connect("unix:/path/to/unix.sock")`

Attempts to connect to the remote host and port that the redis server is listening to or a local unix domain socket file listened by the redis server.

Before actually resolving the host name and connecting to the remote backend, this method will always look up the connection pool for matched idle connections created by previous calls of this method.

set_timeout
----------
`syntax: red:set_timeout(time)`

Sets the timeout (in ms) protection for subsequent operations, including the `connect` method.

set_keepalive
------------
`syntax: ok, err = red:set_keepalive(max_idle_timeout, pool_size)`

Keeps the current redis connection alive and put it into the ngx_lua cosocket connection pool.

You can specify the max idle timeout (in ms) when the connection is in the pool and the maximal size of the pool every nginx worker process.

In case of success, returns `1`. In case of errors, returns `nil` with a string describing the error.

get_reused_times
----------------
`syntax: red:set_keepalive(max_idle_timeout, pool_size)`

This method returns the (successfully) reused times for the current connection. In case of error, it returns `nil` and a string describing the error.


If the current connection does not come from the built-in connection pool, then this method always returns `0`, that is, the connection has never been reused (yet). If the connection comes from the connection pool, then the return value is always non-zero. So this method can also be used to determine if the current connection comes from the pool.

close
-----
`syntax: ok, err = red:close()`

Closes the current redis connection and returns the status.

In case of success, returns `1`. In case of errors, returns `nil` with a string describing the error.

Debugging
=========

It is usually convenient to use the [lua-cjson](http://www.kyne.com.au/~mark/software/lua-cjson.php) library to encode the return values of the redis command methods to JSON. For example,

    local cjson = require "cjson"
    ...
    local res, err = red:mget("h1234", "h5678")
    if res then
        print("res: ", cjson.encode(res))
    end

TODO
====

* implement the redis pipelining API.

Author
======

Zhang "agentzh" Yichun (章亦春) <agentzh@gmail.com>

Copyright and License
=====================

This module is licensed under the BSD license.

Copyright (C) 2012, by Zhang "agentzh" Yichun (章亦春) <agentzh@gmail.com>.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

See Also
========
* the ngx_lua module: http://wiki.nginx.org/HttpLuaModule
* the redis wired protocol specification: http://redis.io/topics/protocol
* the lua-resty-memcached library: https://github.com/agentzh/lua-resty-memcached

