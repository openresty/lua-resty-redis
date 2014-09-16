# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
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
            local connector = require "resty.redis.connector"

            local params = {
                redis = { host = "127.0.0.1", port = $TEST_NGINX_REDIS_PORT },
            }

            local redis, err = connector.connect(params)
            if not redis then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis:set("dog", "an animal")
            if not res then
                ngx.say("failed to set dog: ", err)
                return
            end

            ngx.say("set dog: ", res)

            redis:close()
        ';
    }
--- request
    GET /t
--- response_body
set dog: OK
--- no_error_log
[error]


=== TEST 2: test we can try a list of hosts, and connect to the first working one
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local connector = require "resty.redis.connector"

            local hosts = {
                { host = "127.0.0.1", port = 1 },
                { host = "127.0.0.1", port = 2 },
                { host = "127.0.0.1", port = $TEST_NGINX_REDIS_PORT },
            }

            local redis, err, previous_errors = connector.try_hosts(hosts, { connect_timeout = 100 })
            if not redis then
                ngx.say("failed to connect: ", err)
                return
            end
            
            -- Print the failed connection errors
            ngx.say("connection 1 error: ", err)

            ngx.say("connection 2 error: ", previous_errors[1])

            local res, err = redis:set("dog", "an animal")
            if not res then
                ngx.say("failed to set dog: ", err)
                return
            end

            ngx.say("set dog: ", res)


            redis:close()
        ';
    }
--- request
    GET /t
--- response_body
connection 1 error: connection refused
connection 2 error: connection refused
set dog: OK
--- error_log
111: Connection refused


=== TEST 3: Test connect_to_host directly
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local connector = require "resty.redis.connector"

            local host = { host = "127.0.0.1", port = $TEST_NGINX_REDIS_PORT }

            local redis, err = connector.connect_to_host(host)
            if not redis then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = redis:set("dog", "an animal")
            if not res then
                ngx.say("failed to set dog: ", err)
                return
            end

            ngx.say("set dog: ", res)

            redis:close()
        ';
    }
--- request
    GET /t
--- response_body
set dog: OK
--- no_error_log
[error]


=== TEST 4: Test connect options override
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local connector = require "resty.redis.connector"

            local host = { host = "127.0.0.1", port = $TEST_NGINX_REDIS_PORT }
            local options = { connect_timeout = 1 }

            local redis, err = connector.connect_to_host(host, options)
            if not redis then
                ngx.say("failed to connect: ", err)
                return
            end

            redis:close()
        ';
    }
--- request
    GET /t
--- response_body
set dog: OK
--- no_error_log
[error]
