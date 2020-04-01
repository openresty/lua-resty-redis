# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua::Stream;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (4 * blocks());

my $pwd = cwd();

add_block_preprocessor(sub {
    my $block = shift;

    if (!defined $block->http_only) {
        if ($ENV{TEST_SUBSYSTEM} eq "stream") {
            if (!defined $block->stream_config) {
                $block->set_value("stream_config", $block->global_config);
            }
            if (!defined $block->stream_server_config) {
                $block->set_value("stream_server_config", $block->server_config);
            }
            if (defined $block->internal_server_error) {
                $block->set_value("stream_respons", "");
            }
        } else {
            if (!defined $block->http_config) {
                $block->set_value("http_config", $block->global_config);
            }
            if (!defined $block->request) {
                $block->set_value("request", <<\_END_);
GET /t
_END_
            }
            if (!defined $block->config) {
                $block->set_value("config", "location /t {\n" . $block->server_config . "\n}");
            }
            if (defined $block->internal_server_error) {
                $block->set_value("error_code", 500);
                $block->set_value("ignore_response_body", "");
            }
        }
    }
});

our $GlobalConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: continue using the obj when read timeout happens
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua '
            local redis = require "resty.redis"
            local red = redis:new()

            local ok, err = red:connect("127.0.0.1", 1921);
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            red:set_timeout(100) -- 0.1 sec

            for i = 1, 2 do
                local data, err = red:get("foo")
                if not data then
                    ngx.say("failed to get: ", err)
                else
                    ngx.say("get: ", data);
                end
                ngx.sleep(0.1)
            end

            red:close()
        ';
--- tcp_listen: 1921
--- tcp_query eval
"*2\r
\$3\r
get\r
\$3\r
foo\r
"
--- tcp_reply eval
"\$5\r\nhello\r\n"
--- tcp_reply_delay: 150ms
--- response_body
failed to get: timeout
failed to get: closed
--- error_log
lua tcp socket read timed out
