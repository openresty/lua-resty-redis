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

=== TEST 1: basic
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

            for i = 1, 2 do
                red:init_pipeline()

                red:set("hello", "openresty")
                red:get("hello")
                red:set("foo", "bar")
                red:get("foo")

                local results = red:commit_pipeline()
                local cjson = require "cjson"
                ngx.say(cjson.encode(results))
            end


        ';
    }
--- request
GET /t
--- response_body
["OK","openresty","OK","bar"]
["OK","openresty","OK","bar"]
--- no_error_log
[error]

