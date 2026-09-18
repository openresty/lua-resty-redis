# vim:set ft= ts=4 sw=4 et:

use t::Test;

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

run_tests();

__DATA__

=== TEST 1: sanity
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua '
            local cjson = require "cjson"
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local redis_key = "foo"

            local ok, err = red:multi()
            if not ok then
                ngx.say("failed to run multi: ", err)
                return
            end

            ngx.say("multi ans: ", cjson.encode(ok))

            local ans, err = red:sort("log", "by", redis_key .. ":*->timestamp")
            if not ans then
                ngx.say("failed to run sort: ", err)
                return
            end

            ngx.say("sort ans: ", cjson.encode(ans))

            ans, err = red:exec()

            ngx.say("exec ans: ", cjson.encode(ans))

            local ok, err = red:set_keepalive(0, 1024)
            if not ok then
                ngx.say("failed to put the current redis connection into pool: ", err)
                return
            end
        ';
--- response_body
multi ans: "OK"
sort ans: "QUEUED"
exec ans: [{}]
--- no_error_log
[error]



=== TEST 2: redis cmd reference sample: redis does not halt on errors
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua '
            local cjson = require "cjson"
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = red:multi()
            if not ok then
                ngx.say("failed to run multi: ", err)
                return
            end

            ngx.say("multi ans: ", cjson.encode(ok))

            local ans, err = red:set("a", "abc")
            if not ans then
                ngx.say("failed to run sort: ", err)
                return
            end

            ngx.say("set ans: ", cjson.encode(ans))

            local ans, err = red:lpop("a")
            if not ans then
                ngx.say("failed to run sort: ", err)
                return
            end

            ngx.say("set ans: ", cjson.encode(ans))

            ans, err = red:exec()

            ngx.say("exec ans: ", cjson.encode(ans))

            red:close()
        ';
--- response_body_like chop
^multi ans: "OK"
set ans: "QUEUED"
set ans: "QUEUED"
exec ans: \["OK",\[false,"(?:ERR|WRONGTYPE) Operation against a key holding the wrong kind of value"\]\]
$
--- no_error_log
[error]



=== TEST 3: github issue #176: set_keepalive is refused while MULTI is open
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = red:multi()
            if not ok then
                ngx.say("failed to run multi: ", err)
                return
            end

            ngx.say("set: ", (red:set("txn", 1)))

            local ok, err = red:set_keepalive(0, 1024)
            if not ok then
                ngx.say("refused: ", err)
            else
                ngx.say("kept alive")
            end

            ngx.say("discard: ", (red:discard()))

            local ok, err = red:set_keepalive(0, 1024)
            if not ok then
                ngx.say("refused: ", err)
                return
            end

            ngx.say("ok")
        }
--- response_body
set: QUEUED
refused: in transaction
discard: OK
ok
--- no_error_log
[error]



=== TEST 4: exec ends the transaction state
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:multi()
            red:set("txn", 2)

            local res, err = red:exec()
            if not res then
                ngx.say("failed to exec: ", err)
                return
            end

            local ok, err = red:set_keepalive(0, 1024)
            if not ok then
                ngx.say("refused: ", err)
                return
            end

            ngx.say("ok")
        }
--- response_body
ok
--- no_error_log
[error]



=== TEST 5: connect resets the transaction state
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:multi()
            red:close()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = red:set_keepalive(0, 1024)
            if not ok then
                ngx.say("refused: ", err)
                return
            end

            ngx.say("ok")
        }
--- response_body
ok
--- no_error_log
[error]



=== TEST 6: a pipelined MULTI is tracked too
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local cjson = require "cjson"
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:init_pipeline()
            red:multi()
            red:set("txn", 3)

            local results, err = red:commit_pipeline()
            if not results then
                ngx.say("failed to commit: ", err)
                return
            end

            ngx.say("results: ", cjson.encode(results))

            local ok, err = red:set_keepalive(0, 1024)
            if not ok then
                ngx.say("refused: ", err)
            else
                ngx.say("kept alive")
            end

            ngx.say("discard: ", (red:discard()))

            local ok, err = red:set_keepalive(0, 1024)
            if not ok then
                ngx.say("refused: ", err)
                return
            end

            ngx.say("ok")
        }
--- response_body
results: ["OK","QUEUED"]
refused: in transaction
discard: OK
ok
--- no_error_log
[error]



=== TEST 7: cancel_pipeline forgets a MULTI that was never sent
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:init_pipeline()
            red:multi()
            red:cancel_pipeline()

            local ok, err = red:set_keepalive(0, 1024)
            if not ok then
                ngx.say("refused: ", err)
                return
            end

            ngx.say("ok")
        }
--- response_body
ok
--- no_error_log
[error]
