repeat_each(1);
plan tests => repeat_each() * (2 * blocks());


our $HttpConfig = qq{
    lua_package_path "/usr/local/lib/lua/?.lua;;";
    lua_package_cpath "/usr/local/lib/lua/?.so;;";
    lua_shared_dict redis_dict 100k;
};

no_shuffle();
run_tests();

__DATA__
__DATA__

=== TEST 1: continue using the obj when read timeout happens
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
                    connect_timeout=100,--in ms
                },
            }
            local redis_cluster = require "resty.rediscluster"
            local red = redis_cluster:new(config)

                for i =1 ,2 do
                local data, err = red:get("foo_xx")
                if not data or data == ngx.null then
                    ngx.say("failed to get: foo_xx")
                else
                    ngx.say("get: ", data);
                end
                ngx.sleep(0.1)
                end
        ';
    }
--- request
GET /t
--- response_body
failed to get: foo_xx
failed to get: foo_xx
--- no_error_log