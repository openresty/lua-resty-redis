# vim:set ft= ts=4 sw=4 et:

use t::Test;

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

run_tests();

__DATA__

=== TEST 1: db option selects on fresh connections and uses its own pool
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local opts = { db = 1 }

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, opts)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:del("db-opt")
            red:set("db-opt", "in db 1")
            ngx.say("opts.pool: ", opts.pool)
            red:set_keepalive(0, 1024)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("db 0: ", (red:get("db-opt")))
            red:set_keepalive(0, 1024)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, opts)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("reused: ", (red:get_reused_times()))
            ngx.say("db 1: ", (red:get("db-opt")))

            red:del("db-opt")
            red:close()
        }
--- response_body
opts.pool: nil
db 0: null
reused: 1
db 1: in db 1
--- no_error_log
[error]



=== TEST 2: an explicit pool name wins over the db isolation
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT,
                                        { db = 1, pool = "shared" })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:set_keepalive(0, 1024)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT,
                                        { pool = "shared" })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("reused: ", (red:get_reused_times()))
            red:close()
        }
--- response_body
reused: 1
--- no_error_log
[error]



=== TEST 3: nothing is re-applied on a reused connection
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, { db = 1 })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:select(2)
            red:set_keepalive(0, 1024)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, { db = 1 })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("reused: ", (red:get_reused_times()))

            local info = red:client("info")
            ngx.say("db: ", string.match(info, "db=(%d+)"))
            red:close()
        }
--- response_body
reused: 1
db: 2
--- no_error_log
[error]



=== TEST 4: username + password authenticate as an ACL user, with their own pool
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

            local res, err = red:acl("setuser", "resty-opts", "reset", "on",
                                     ">s3cret", "~*", "+@all")
            if not res then
                ngx.say("failed to create the acl user: ", err)
                return
            end

            red:set_keepalive(0, 1024)

            local opts = { username = "resty-opts", password = "s3cret" }

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, opts)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("whoami: ", (red:acl("whoami")))
            red:set_keepalive(0, 1024)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, opts)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("reused: ", (red:get_reused_times()))
            ngx.say("whoami: ", (red:acl("whoami")))
            red:set_keepalive(0, 1024)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("whoami: ", (red:acl("whoami")))
            red:acl("deluser", "resty-opts")
            red:close()
        }
--- response_body
whoami: resty-opts
reused: 1
whoami: resty-opts
whoami: default
--- no_error_log
[error]



=== TEST 5: a wrong password fails the connect and closes the socket
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

            red:acl("setuser", "resty-opts", "reset", "on", ">s3cret", "~*", "+@all")
            red:set_keepalive(0, 1024)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT,
                                        { username = "resty-opts", password = "wrong" })
            ngx.say("connect: ", ok, " ", err)

            local times, err = red:get_reused_times()
            ngx.say("reused: ", times, " ", err)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:acl("deluser", "resty-opts")
            red:close()
        }
--- response_body_like chop
^connect: nil failed to authenticate: WRONGPASS .*
reused: nil closed
$
--- no_error_log
[error]



=== TEST 6: password on a server without one fails; an empty password is ignored
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT,
                                        { password = "x" })
            ngx.say("connect: ", ok, " ", err)

            local times, err = red:get_reused_times()
            ngx.say("reused: ", times, " ", err)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT,
                                        { password = "", username = "" })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("ping: ", (red:ping()))
            red:close()
        }
--- response_body_like chop
^connect: nil failed to authenticate: ERR AUTH .* without any password .*
reused: nil closed
ping: PONG
$
--- no_error_log
[error]



=== TEST 7: an invalid db fails the connect and closes the socket
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT,
                                        { db = 99999 })
            ngx.say("connect: ", ok, " ", err)

            local times, err = red:get_reused_times()
            ngx.say("reused: ", times, " ", err)
        }
--- response_body
connect: nil failed to select database 99999: ERR DB index is out of range
reused: nil closed
--- no_error_log
[error]



=== TEST 8: tcp_keepalive enables SO_KEEPALIVE on the connection
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT,
                                        { tcp_keepalive = true })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            -- nginx strips PATH down to /usr/local/bin:/usr/bin
            local p = io.popen("PATH=$PATH:/usr/sbin:/sbin ss -tno state established "
                               .. "'( dport = :$TEST_NGINX_REDIS_PORT )'")
            local out = p:read("*a")
            p:close()

            ngx.say("keepalive timer: ",
                    string.find(out, "timer:(keepalive", 1, true) and "yes" or "no")
            ngx.say("ping: ", (red:ping()))
            red:close()
        }
--- response_body
keepalive timer: yes
ping: PONG
--- no_error_log
[error]



=== TEST 9: db and username never share a pool
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

            local res, err = red:acl("setuser", "1", "reset", "on", ">s3cret", "~*", "+@all")
            if not res then
                ngx.say("failed to create the acl user: ", err)
                return
            end

            red:set_keepalive(0, 1024)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, { db = 1 })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:set_keepalive(0, 1024)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT,
                                        { username = "1", password = "s3cret" })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("whoami: ", (red:acl("whoami")))
            ngx.say("db: ", string.match(red:client("info"), "db=(%d+)"))
            red:close()

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:acl("deluser", "1")
            red:close()
        }
--- response_body
whoami: 1
db: 0
--- no_error_log
[error]



=== TEST 10: db must be a number
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = pcall(red.connect, red, "127.0.0.1", $TEST_NGINX_REDIS_PORT,
                                  { db = "1/user=alice" })
            ngx.say("connect: ", ok, " ", err)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, { db = "1" })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("db: ", string.match(red:client("info"), "db=(%d+)"))
            red:close()
        }
--- response_body
connect: false bad option db: number expected, got string
db: 1
--- no_error_log
[error]
