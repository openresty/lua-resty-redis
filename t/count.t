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

=== TEST 1: module size of resty.redis
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua '
            local redis = require "resty.redis"
            n = 0
            for _, _ in pairs(redis) do
                n = n + 1
            end
            ngx.say("size: ", n)
        ';
    }
--- request
GET /t
--- response_body
size: 156
--- no_error_log
[error]


=== TEST 2: command size of resty.redis
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua '
            local redis = require "resty.redis"
            local commands = redis.get_commands()
            n = 0
            for _, _ in ipairs(commands) do
                n = n + 1
            end
            ngx.say("size: ", n)
        ';
    }
--- request
GET /t
--- response_body
size: 142
--- no_error_log
[error]


=== TEST 3: command size of resty.redis with add_commands
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua '
            local redis = require "resty.redis"
            redis.add_commands("new_test_command")

            local commands = redis.get_commands()
            n = 0
            for _, _ in ipairs(commands) do
                n = n + 1
            end
            ngx.say("size: ", n - 1)
        ';
    }
--- request
GET /t
--- response_body
size: 142
--- no_error_log
[error]

