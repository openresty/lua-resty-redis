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

=== TEST 1: module size of resty.redis
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
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
                    instance_max=1000
                },
            }
            local redis_cluster = require "resty.rediscluster"
            n = 0
            for _, _ in pairs(redis_cluster) do
                n = n + 1
            end
            ngx.say("size: ", n)
        ';
    }
--- request
GET /t
--- response_body
size: 84
--- no_error_log
[error]

