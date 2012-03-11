# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: basic
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            -- or connect to a unix domain socket file listened
            -- by a redis server:
            --     local ok, err = red:connect("unix:/path/to/redis.sock")

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            for i = 1, 2 do
                red:init_pipeline()

                red:set("dog", "an animal")
                red:get("dog")
                red:set("dog", "hello")
                red:get("dog")

                local results = red:commit_pipeline()
                local cjson = require "cjson"
                ngx.say(cjson.encode(results))
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
["OK","an animal","OK","hello"]
["OK","an animal","OK","hello"]
--- no_error_log
[error]



=== TEST 2: cancel automatically
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            -- or connect to a unix domain socket file listened
            -- by a redis server:
            --     local ok, err = red:connect("unix:/path/to/redis.sock")

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:init_pipeline()

            red:set("dog", "an animal")
            red:get("dog")

            for i = 1, 2 do
                red:init_pipeline()

                red:set("dog", "an animal")
                red:get("dog")
                red:set("dog", "hello")
                red:get("dog")

                local results = red:commit_pipeline()
                local cjson = require "cjson"
                ngx.say(cjson.encode(results))
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
["OK","an animal","OK","hello"]
["OK","an animal","OK","hello"]
--- no_error_log
[error]



=== TEST 3: cancel explicitly
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            -- or connect to a unix domain socket file listened
            -- by a redis server:
            --     local ok, err = red:connect("unix:/path/to/redis.sock")

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:init_pipeline()

            red:set("dog", "an animal")
            red:get("dog")

            red:cancel_pipeline()

            local res, err = red:flushall()
            if not res then
                ngx.say("failed to flush all: ", err)
                return
            end

            ngx.say("flushall: ", res)

            for i = 1, 2 do
                red:init_pipeline()

                red:set("dog", "an animal")
                red:get("dog")
                red:set("dog", "hello")
                red:get("dog")

                local results = red:commit_pipeline()
                local cjson = require "cjson"
                ngx.say(cjson.encode(results))
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
flushall: OK
["OK","an animal","OK","hello"]
["OK","an animal","OK","hello"]
--- no_error_log
[error]

