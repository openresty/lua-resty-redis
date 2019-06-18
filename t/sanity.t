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

=== TEST 1: set and get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ok, err = red:select(1)
            if not ok then
                ngx.say("failed to select: ", err)
                return
            end

            local res, err = red:set("dog", "an animal")
            if not res then
                ngx.say("failed to set dog: ", err)
                return
            end

            ngx.say("set dog: ", res)

            for i = 1, 2 do
                local res, err = red:get("dog")
                if err then
                    ngx.say("failed to get dog: ", err)
                    return
                end

                if not res then
                    ngx.say("dog not found.")
                    return
                end

                ngx.say("dog: ", res)
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
set dog: OK
dog: an animal
dog: an animal
--- no_error_log
[error]



=== TEST 2: flushall
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:flushall()
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end
            ngx.say("flushall: ", res)

            red:close()
        ';
    }
--- request
GET /t
--- response_body
flushall: OK
--- no_error_log
[error]



=== TEST 3: get nil bulk value
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:flushall()
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            ngx.say("flushall: ", res)

            for i = 1, 2 do
                res, err = red:get("not_found")
                if err then
                    ngx.say("failed to get: ", err)
                    return
                end

                if res == ngx.null then
                    ngx.say("not_found not found.")
                    return
                end

                ngx.say("get not_found: ", res)
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
flushall: OK
not_found not found.
--- no_error_log
[error]



=== TEST 4: get nil list
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:flushall()
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            ngx.say("flushall: ", res)

            for i = 1, 2 do
                res, err = red:lrange("nokey", 0, 1)
                if err then
                    ngx.say("failed to get: ", err)
                    return
                end

                if res == ngx.null then
                    ngx.say("nokey not found.")
                    return
                end

                ngx.say("get nokey: ", #res, " (", type(res), ")")
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
flushall: OK
get nokey: 0 (table)
get nokey: 0 (table)
--- no_error_log
[error]



=== TEST 5: incr and decr
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:set("connections", 10)
            if not res then
                ngx.say("failed to set connections: ", err)
                return
            end

            ngx.say("set connections: ", res)

            res, err = red:incr("connections")
            if not res then
                ngx.say("failed to set connections: ", err)
                return
            end

            ngx.say("incr connections: ", res)

            local res, err = red:get("connections")
            if err then
                ngx.say("failed to get connections: ", err)
                return
            end

            res, err = red:incr("connections")
            if not res then
                ngx.say("failed to incr connections: ", err)
                return
            end

            ngx.say("incr connections: ", res)

            res, err = red:decr("connections")
            if not res then
                ngx.say("failed to decr connections: ", err)
                return
            end

            ngx.say("decr connections: ", res)

            res, err = red:get("connections")
            if not res then
                ngx.say("connections not found.")
                return
            end

            ngx.say("connections: ", res)

            res, err = red:del("connections")
            if not res then
                ngx.say("failed to del connections: ", err)
                return
            end

            ngx.say("del connections: ", res)

            res, err = red:incr("connections")
            if not res then
                ngx.say("failed to set connections: ", err)
                return
            end

            ngx.say("incr connections: ", res)

            res, err = red:get("connections")
            if not res then
                ngx.say("connections not found.")
                return
            end

            ngx.say("connections: ", res)

            red:close()
        ';
    }
--- request
GET /t
--- response_body
set connections: OK
incr connections: 11
incr connections: 12
decr connections: 11
connections: 11
del connections: 1
incr connections: 1
connections: 1
--- no_error_log
[error]



=== TEST 6: bad incr command format
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:incr("connections", 12)
            if not res then
                ngx.say("failed to set connections: ", res, ": ", err)
                return
            end

            ngx.say("incr connections: ", res)

            red:close()
        ';
    }
--- request
GET /t
--- response_body
failed to set connections: false: ERR wrong number of arguments for 'incr' command
--- no_error_log
[error]



=== TEST 7: lpush and lrange
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:flushall()
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end
            ngx.say("flushall: ", res)

            local res, err = red:lpush("mylist", "world")
            if not res then
                ngx.say("failed to lpush: ", err)
                return
            end
            ngx.say("lpush result: ", res)

            res, err = red:lpush("mylist", "hello")
            if not res then
                ngx.say("failed to lpush: ", err)
                return
            end
            ngx.say("lpush result: ", res)

            res, err = red:lrange("mylist", 0, -1)
            if not res then
                ngx.say("failed to lrange: ", err)
                return
            end
            local cjson = require "cjson"
            ngx.say("lrange result: ", cjson.encode(res))

            red:close()
        ';
    }
--- request
GET /t
--- response_body
flushall: OK
lpush result: 1
lpush result: 2
lrange result: ["hello","world"]
--- no_error_log
[error]



=== TEST 8: blpop expires its own timeout
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(2500) -- 2.5 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:flushall()
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end
            ngx.say("flushall: ", res)

            local res, err = red:blpop("key", 1)
            if err then
                ngx.say("failed to blpop: ", err)
                return
            end

            if res == ngx.null then
                ngx.say("no element popped.")
                return
            end

            local cjson = require "cjson"
            ngx.say("blpop result: ", cjson.encode(res))

            red:close()
        ';
    }
--- request
GET /t
--- response_body
flushall: OK
no element popped.
--- no_error_log
[error]
--- timeout: 3



=== TEST 9: blpop expires cosocket timeout
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:flushall()
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end
            ngx.say("flushall: ", res)

            red:set_timeout(200) -- 200 ms

            local res, err = red:blpop("key", 1)
            if err then
                ngx.say("failed to blpop: ", err)
                return
            end

            if not res then
                ngx.say("no element popped.")
                return
            end

            local cjson = require "cjson"
            ngx.say("blpop result: ", cjson.encode(res))

            red:close()
        ';
    }
--- request
GET /t
--- response_body
flushall: OK
failed to blpop: timeout
--- error_log
lua tcp socket read timed out



=== TEST 10: set keepalive and get reused times
--- http_config eval: $::HttpConfig
--- config
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local times = red:get_reused_times()
            ngx.say("reused times: ", times)

            local ok, err = red:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end

            ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            times = red:get_reused_times()
            ngx.say("reused times: ", times)
        ';
    }
--- request
GET /t
--- response_body
reused times: 0
reused times: 1
--- no_error_log
[error]



=== TEST 11: mget
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ok, err = red:flushall()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local res, err = red:set("dog", "an animal")
            if not res then
                ngx.say("failed to set dog: ", err)
                return
            end

            ngx.say("set dog: ", res)

            for i = 1, 2 do
                local res, err = red:mget("dog", "cat", "dog")
                if err then
                    ngx.say("failed to get dog: ", err)
                    return
                end

                if not res then
                    ngx.say("dog not found.")
                    return
                end

                local cjson = require "cjson"
                ngx.say("res: ", cjson.encode(res))
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
set dog: OK
res: ["an animal",null,"an animal"]
res: ["an animal",null,"an animal"]
--- no_error_log
[error]



=== TEST 12: hmget array_to_hash
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ok, err = red:flushall()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local res, err = red:hmset("animals", { dog = "bark", cat = "meow", cow = "moo" })
            if not res then
                ngx.say("failed to set animals: ", err)
                return
            end

            ngx.say("hmset animals: ", res)

            local res, err = red:hmget("animals", "dog", "cat", "cow")
            if not res then
                ngx.say("failed to get animals: ", err)
                return
            end

            ngx.say("hmget animals: ", res)

            local res, err = red:hgetall("animals")
            if err then
                ngx.say("failed to get animals: ", err)
                return
            end

            if not res then
                ngx.say("animals not found.")
                return
            end

            local h = red:array_to_hash(res)

            ngx.say("dog: ", h.dog)
            ngx.say("cat: ", h.cat)
            ngx.say("cow: ", h.cow)

            red:close()
        ';
    }
--- request
GET /t
--- response_body
hmset animals: OK
hmget animals: barkmeowmoo
dog: bark
cat: meow
cow: moo
--- no_error_log
[error]



=== TEST 13: boolean args
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ok, err = red:set("foo", true)
            if not ok then
                ngx.say("failed to set: ", err)
                return
            end

            local res, err = red:get("foo")
            if not res then
                ngx.say("failed to get: ", err)
                return
            end

            ngx.say("foo: ", res, ", type: ", type(res))

            ok, err = red:set("foo", false)
            if not ok then
                ngx.say("failed to set: ", err)
                return
            end

            local res, err = red:get("foo")
            if not res then
                ngx.say("failed to get: ", err)
                return
            end

            ngx.say("foo: ", res, ", type: ", type(res))

            ok, err = red:set("foo", nil)
            if not ok then
                ngx.say("failed to set: ", err)
            end

            local res, err = red:get("foo")
            if not res then
                ngx.say("failed to get: ", err)
                return
            end

            ngx.say("foo: ", res, ", type: ", type(res))

            local ok, err = red:set_keepalive(10, 10)
            if not ok then
                ngx.say("failed to set_keepalive: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
foo: true, type: string
foo: false, type: string
failed to set: ERR wrong number of arguments for 'set' command
foo: false, type: string
--- no_error_log
[error]



=== TEST 14: set and get (key with underscores)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:set("a_dog", "an animal")
            if not res then
                ngx.say("failed to set a_dog: ", err)
                return
            end

            ngx.say("set a_dog: ", res)

            for i = 1, 2 do
                local res, err = red:get("a_dog")
                if err then
                    ngx.say("failed to get a_dog: ", err)
                    return
                end

                if not res then
                    ngx.say("a_dog not found.")
                    return
                end

                ngx.say("a_dog: ", res)
            end

            red:close()
        ';
    }
--- request
GET /t
--- response_body
set a_dog: OK
a_dog: an animal
a_dog: an animal
--- no_error_log
[error]



=== TEST 15: connection refused
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(10000) -- 10 sec

            local ok, err = red:connect("127.0.0.1", 81)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected")

            red:close()
        ';
    }
--- request
GET /t
--- response_body
failed to connect: connection refused
--- timeout: 3
--- no_error_log
[alert]



=== TEST 16: set_timeouts() connect timeout
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeouts(100, 1000, 1000) -- 0.1 sec

            local ok, err = red:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
            end
        }
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- no_error_log
[alert]



=== TEST 17: set_timeouts() send timeout
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeouts(1000, 100, 1000) -- 0.1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:flushall()
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            ngx.say("flushall: ", res)

            local res, err = red:blpop("key", 1)
            if err then
                ngx.say("failed to blpop: ", err)
            end

            red:close()
        }
    }
--- request
GET /t
--- response_body
flushall: OK
failed to blpop: timeout
--- no_error_log
[alert]



=== TEST 18: set_timeouts() read timeout
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeouts(1000, 1000, 100) -- 0.1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:flushall()
            if not res then
                ngx.say("failed to flushall: ", err)
                return
            end

            ngx.say("flushall: ", res)

            local res, err = red:blpop("key", 1)
            if err then
                ngx.say("failed to blpop: ", err)
            end

            red:close()
        }
    }
--- request
GET /t
--- response_body
flushall: OK
failed to blpop: timeout
--- no_error_log
[alert]



=== TEST 19: connect() bad host argument (boolean)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:connect(true)
        }
    }
--- request
GET /t
--- error_code: 500
--- ignore_response_body
--- error_log
bad argument #1 host: string expected, got boolean
--- no_error_log
[crit]



=== TEST 20: connect() bad host argument (nil)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:connect(nil)
        }
    }
--- request
GET /t
--- error_code: 500
--- ignore_response_body
--- error_log
bad argument #1 host: string expected, got nil
--- no_error_log
[crit]



=== TEST 21: connect() bad port argument (nil)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:connect("127.0.0.1", nil)
        }
    }
--- request
GET /t
--- error_code: 500
--- ignore_response_body
--- error_log
bad argument #2 port: number expected, got nil
--- no_error_log
[crit]



=== TEST 22: connect() bad port argument (boolean)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:connect("127.0.0.1", true)
        }
    }
--- request
GET /t
--- error_code: 500
--- ignore_response_body
--- error_log
bad argument #2 port: number expected, got boolean
--- no_error_log
[crit]



=== TEST 23: connect() bad port argument (string)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:connect("127.0.0.1", "foo")
        }
    }
--- request
GET /t
--- error_code: 500
--- ignore_response_body
--- error_log
bad argument #2 port: number expected, got string
--- no_error_log
[crit]



=== TEST 24: connect() accepts port argument as string
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", tostring($TEST_NGINX_REDIS_PORT))
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 25: connect() bad opts argument
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, true)
        }
    }
--- request
GET /t
--- error_code: 500
--- ignore_response_body
--- error_log
bad argument #3 opts: nil or table expected, got boolean
--- no_error_log
[crit]



=== TEST 26: connect() bad opts argument for unix sockets
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:connect("unix:", true)
        }
    }
--- request
GET /t
--- error_code: 500
--- ignore_response_body
--- error_log
bad argument #2 opts: nil or table expected, got boolean
--- no_error_log
[crit]



=== TEST 27: connect() unix socket arguments when 'host' starts with 'unix:'
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            local pok, perr = pcall(red.connect, red, "unix:", true)
            if not pok then
                ngx.say(perr)
            end

            local pok, perr = pcall(red.connect, red, "_unix:", true)
            if not pok then
                ngx.say(perr)
            end
        }
    }
--- request
GET /t
--- response_body
bad argument #2 opts: nil or table expected, got boolean
bad argument #2 port: number expected, got boolean
--- no_error_log
[error]
