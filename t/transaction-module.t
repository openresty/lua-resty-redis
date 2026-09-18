# vim:set ft= ts=4 sw=4 et:

use t::Test;

repeat_each(2);

plan tests => repeat_each() * (4 * blocks());

run_tests();

__DATA__

=== TEST 1: module multi preserves arguments and permits keepalive
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            redis.register_module_prefix("review")

            local red = redis:new()
            red:set_timeout(1000)

            local ok, err = red:connect("127.0.0.1", 1922)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("reply: ", (red:review():multi("one", "two")))
            local ok, err = red:set_keepalive(0, 1)
            ngx.say("keepalive: ", ok, " ", err)
        }
--- tcp_listen: 1922
--- tcp_query eval
"*3\r\n\$12\r\nreview.multi\r\n\$3\r\none\r\n\$3\r\ntwo\r\n"
--- tcp_reply eval
"+OK\r\n"
--- tcp_no_close
--- response_body
reply: OK
keepalive: 1 nil
--- no_error_log
[error]



=== TEST 2: module exec preserves arguments and permits keepalive
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            redis.register_module_prefix("review")

            local red = redis:new()
            red:set_timeout(1000)

            local ok, err = red:connect("127.0.0.1", 1922)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("reply: ", (red:review():exec("one", "two")))
            local ok, err = red:set_keepalive(0, 1)
            ngx.say("keepalive: ", ok, " ", err)
        }
--- tcp_listen: 1922
--- tcp_query eval
"*3\r\n\$11\r\nreview.exec\r\n\$3\r\none\r\n\$3\r\ntwo\r\n"
--- tcp_reply eval
"+OK\r\n"
--- tcp_no_close
--- response_body
reply: OK
keepalive: 1 nil
--- no_error_log
[error]



=== TEST 3: module discard preserves arguments and permits keepalive
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            redis.register_module_prefix("review")

            local red = redis:new()
            red:set_timeout(1000)

            local ok, err = red:connect("127.0.0.1", 1922)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("reply: ", (red:review():discard("one", "two")))
            local ok, err = red:set_keepalive(0, 1)
            ngx.say("keepalive: ", ok, " ", err)
        }
--- tcp_listen: 1922
--- tcp_query eval
"*3\r\n\$14\r\nreview.discard\r\n\$3\r\none\r\n\$3\r\ntwo\r\n"
--- tcp_reply eval
"+OK\r\n"
--- tcp_no_close
--- response_body
reply: OK
keepalive: 1 nil
--- no_error_log
[error]



=== TEST 4: a direct module exec does not end a transaction
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            redis.register_module_prefix("review")

            local red = redis:new()
            red:set_timeout(1000)

            local ok, err = red:connect("127.0.0.1", 1922)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("multi: ", (red:multi()))
            ngx.say("module reply: ", (red:review():exec()))

            local ok, err = red:set_keepalive(0, 1)
            ngx.say("keepalive: ", ok, " ", err)
            red:close()
        }
--- tcp_listen: 1922
--- tcp_query eval
"*1\r\n\$5\r\nmulti\r\n"
# The first reply acknowledges MULTI; the second is the module command's reply.
--- tcp_reply eval
"+OK\r\n+QUEUED\r\n"
--- tcp_no_close
--- response_body
multi: OK
module reply: QUEUED
keepalive: nil in transaction
--- no_error_log
[error]



=== TEST 5: a direct module discard does not end a transaction
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            redis.register_module_prefix("review")

            local red = redis:new()
            red:set_timeout(1000)

            local ok, err = red:connect("127.0.0.1", 1922)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("multi: ", (red:multi()))
            ngx.say("module reply: ", (red:review():discard()))

            local ok, err = red:set_keepalive(0, 1)
            ngx.say("keepalive: ", ok, " ", err)
            red:close()
        }
--- tcp_listen: 1922
--- tcp_query eval
"*1\r\n\$5\r\nmulti\r\n"
# The first reply acknowledges MULTI; the second is the module command's reply.
--- tcp_reply eval
"+OK\r\n+QUEUED\r\n"
--- tcp_no_close
--- response_body
multi: OK
module reply: QUEUED
keepalive: nil in transaction
--- no_error_log
[error]



=== TEST 6: pipelined module commands preserve arguments and do not open a transaction
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            redis.register_module_prefix("review")

            local red = redis:new()
            red:set_timeout(1000)

            local ok, err = red:connect("127.0.0.1", 1922)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:init_pipeline()
            red:review():exec("one", "two")
            red:review():discard("one", "two")
            red:review():multi("one", "two")
            red:ping()

            local results, err = red:commit_pipeline()
            if not results then
                ngx.say("failed to commit: ", err)
                return
            end

            ngx.say("replies: ", require("cjson").encode(results))
            local ok, err = red:set_keepalive(0, 1)
            ngx.say("keepalive: ", ok, " ", err)
        }
--- tcp_listen: 1922
--- tcp_query eval
"*3\r\n\$11\r\nreview.exec\r\n\$3\r\none\r\n\$3\r\ntwo\r\n" .
"*3\r\n\$14\r\nreview.discard\r\n\$3\r\none\r\n\$3\r\ntwo\r\n" .
"*3\r\n\$12\r\nreview.multi\r\n\$3\r\none\r\n\$3\r\ntwo\r\n" .
"*1\r\n\$4\r\nping\r\n"
--- tcp_reply eval
"+OK\r\n+OK\r\n+OK\r\n+PONG\r\n"
--- tcp_no_close
--- response_body
replies: ["OK","OK","OK","PONG"]
keepalive: 1 nil
--- no_error_log
[error]



=== TEST 7: pipelined module exec and discard leave a transaction open
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            redis.register_module_prefix("review")

            local red = redis:new()
            red:set_timeout(1000)

            local ok, err = red:connect("127.0.0.1", 1922)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:init_pipeline()
            red:multi()
            red:review():exec("one", "two")
            red:review():discard("one", "two")

            local results, err = red:commit_pipeline()
            if not results then
                ngx.say("failed to commit: ", err)
                return
            end

            ngx.say("replies: ", require("cjson").encode(results))
            local ok, err = red:set_keepalive(0, 1)
            ngx.say("keepalive: ", ok, " ", err)
            red:close()
        }
--- tcp_listen: 1922
--- tcp_query eval
"*1\r\n\$5\r\nmulti\r\n" .
"*3\r\n\$11\r\nreview.exec\r\n\$3\r\none\r\n\$3\r\ntwo\r\n" .
"*3\r\n\$14\r\nreview.discard\r\n\$3\r\none\r\n\$3\r\ntwo\r\n"
--- tcp_reply eval
"+OK\r\n+QUEUED\r\n+QUEUED\r\n"
--- tcp_no_close
--- response_body
replies: ["OK","QUEUED","QUEUED"]
keepalive: nil in transaction
--- no_error_log
[error]
