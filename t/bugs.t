# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();
my $HtmlDir = html_dir;

our $HttpConfig = qq{
    lua_package_path "$HtmlDir/?.lua;$pwd/lib/?.lua;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

no_long_string();
#no_diff();

log_level 'warn';

run_tests();

__DATA__

=== TEST 1: github issue #108: ngx.locaiton.capture + redis.set_keepalive
--- http_config eval: $::HttpConfig
--- config
    location /r1 {
        default_type text/html;
        set $port $TEST_NGINX_REDIS_PORT;
        #lua_code_cache off;
        lua_need_request_body on;
        content_by_lua_file html/r1.lua;
    }

    location /r2 {
        default_type text/html;
        set $port $TEST_NGINX_REDIS_PORT;
        #lua_code_cache off;
        lua_need_request_body on;
        content_by_lua_file html/r2.lua;
    }

    location /anyurl {
        internal;
        proxy_pass http://127.0.0.1:$server_port/dummy;
    }

    location = /dummy {
        echo dummy;
    }
--- user_files
>>> r1.lua
local redis = require "resty.redis"
local red = redis:new()
local ok, err = red:connect("127.0.0.1", ngx.var.port)
local ok, err = red:flushall()
red:set_keepalive()
local http_ress = ngx.location.capture("/r2") -- 1
ngx.say("ok")

>>> r2.lua
local redis = require "resty.redis"
local red = redis:new()
local ok, err = red:connect("127.0.0.1", ngx.var.port) --2
local res = ngx.location.capture("/anyurl") --3
--- request
    GET /r1
--- response_body
ok
--- no_error_log
[error]



=== TEST 2: exit(404) after I/O (ngx_lua github issue #110
https://github.com/chaoslawful/lua-nginx-module/issues/110
--- http_config eval: $::HttpConfig
--- config
    location /foo {
        access_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            -- or connect to a unix domain socket file listened
            -- by a redis server:
            --     local ok, err = red:connect("unix:/path/to/redis.sock")

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return
            end

            res, err = red:set("dog", "an animal")
            if not res then
                ngx.log(ngx.ERR, "failed to set dog: ", err)
                return
            end

            -- ngx.say("set dog: ", res)

            local res, err = red:get("dog")
            if err then
                ngx.log(ngx.ERR, "failed to get dog: ", err)
                return
            end

            if not res then
                -- ngx.say("dog not found.")
                return
            end

            -- ngx.say("dog: ", res)

            -- red:close()
            red:set_keepalive()

            ngx.exit(ngx.HTTP_NOT_FOUND)
        ';
        echo Hello;
    }
--- request
    GET /foo
--- response_body_like: 404 Not Found
--- error_code: 404
--- no_error_log
[error]

