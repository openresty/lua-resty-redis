# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: single channel
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local cjson = require "cjson"
            local redis = require "resty.redis"

            local red = redis:new()
            local red2 = redis:new()

            red:set_timeout(1000) -- 1 sec
            red2:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("1: failed to connect: ", err)
                return
            end

            ok, err = red2:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("2: failed to connect: ", err)
                return
            end

            res, err = red:subscribe("dog")
            if not res then
                ngx.say("1: failed to subscribe: ", err)
                return
            end

            ngx.say("1: subscribe: ", cjson.encode(res))

            res, err = red2:publish("dog", "Hello")
            if not res then
                ngx.say("2: failed to publish: ", err)
                return
            end

            ngx.say("2: publish: ", cjson.encode(res))

            res, err = red:read_reply()
            if not res then
                ngx.say("1: failed to read reply: ", err)
                return
            end

            ngx.say("1: receive: ", cjson.encode(res))

            red:close()
            red2:close()
        ';
    }
--- request
GET /t
--- response_body
1: subscribe: ["subscribe","dog",1]
2: publish: 1
1: receive: ["message","dog","Hello"]
--- no_error_log
[error]



=== TEST 2: single channel (retry read_reply() after timeout)
--- http_config eval: $::HttpConfig
--- config
    lua_socket_log_errors off;
    location /t {
        content_by_lua '
            local cjson = require "cjson"
            local redis = require "resty.redis"

            local red = redis:new()
            local red2 = redis:new()

            red:set_timeout(1000) -- 1 sec
            red2:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("1: failed to connect: ", err)
                return
            end

            ok, err = red2:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("2: failed to connect: ", err)
                return
            end

            res, err = red:subscribe("dog")
            if not res then
                ngx.say("1: failed to subscribe: ", err)
                return
            end

            ngx.say("1: subscribe: ", cjson.encode(res))

            red:set_timeout(1)
            for i = 1, 2 do
                res, err = red:read_reply()
                if not res then
                    ngx.say("1: failed to read reply: ", err)
                    if err ~= "timeout" then
                        return
                    end
                end
            end
            red:set_timeout(1000)

            res, err = red:unsubscribe("dog")
            if not res then
                ngx.say("1: failed to unsubscribe: ", err)
            else
                ngx.say("1: unsubscribe: ", cjson.encode(res))
            end

            res, err = red2:publish("dog", "Hello")
            if not res then
                ngx.say("2: failed to publish: ", err)
                return
            end

            ngx.say("2: publish: ", cjson.encode(res))

            res, err = red:read_reply()
            if not res then
                ngx.say("1: failed to read reply: ", err)

            else
                ngx.say("1: receive: ", cjson.encode(res))
            end

            res, err = red:unsubscribe("dog")
            if not res then
                ngx.say("1: failed to unsubscribe: ", err)
                return
            end

            ngx.say("1: unsubscribe: ", cjson.encode(res))

            red:close()
            red2:close()
        ';
    }
--- request
GET /t
--- response_body
1: subscribe: ["subscribe","dog",1]
1: failed to read reply: timeout
1: failed to read reply: timeout
1: unsubscribe: ["unsubscribe","dog",0]
2: publish: 0
1: failed to read reply: not subscribed
1: unsubscribe: ["unsubscribe","dog",0]
--- no_error_log
[error]

