use Test::Nginx::Socket::Lua;

repeat_each(2);
plan tests => repeat_each() * 3 * blocks();


our $HttpConfig = qq{
    lua_package_path "/usr/local/lib/lua/?.lua;;";
    lua_package_cpath "/usr/local/lib/lua/?.so;;";
    lua_shared_dict redis_dict 100k;

};

no_shuffle();
run_tests();

__DATA__

=== TEST 1: hmset key-pairs
--- http_config eval
"$::HttpConfig"
--- config
    location /t {
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
            local red = redis_cluster:new(config)
            local res, err = red:hmset("Language", "openresty{key}", "lua", "nginx{key}", "c")
            if not res then
                ngx.say("failed to set Language: ", err)
                return
            end
            ngx.say("hmset Language: ", res)

            local res, err = red:hmget("animals", "openresty{key}", "nginx{key}")
            if not res then
                ngx.say("failed to get Language: ", err)
                return
            end

            ngx.say("hmget animals: ", res)

        ';
    }
--- request
GET /t
--- response_body
hmset Language: OK
hmget Language: luac
--- no_error_log
[error]





=== TEST 2: hmset a single scalar
--- http_config eval
"$::HttpConfig"
--- config
    location /t {
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
            local red = redis_cluster:new(config)

            local res, err = red:hmset("Language", "openresty{key}","lua")
            if not res then
                ngx.say("failed to set Language: ", err)
                return
            end
            ngx.say("hmset Language: ", res)

            local res, err = red:hmget("Language", "openresty{key}")
            if not res then
                ngx.say("failed to get Language: ", err)
                return
            end

            ngx.say("hmget Language: ", res)

            red:close()
        ';
    }
--- request
GET /t
--- response_body
hmset Language: OK
hmget Language: lua
--- no_error_log
[error]

