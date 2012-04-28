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

