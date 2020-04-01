# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua::Stream;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

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

=== TEST 1: single channel
--- global_config eval: $::GlobalConfig
--- server_config
        content_by_lua '
            local cjson = require "cjson"
            local redis = require "resty.redis"

            redis.add_commands("foo", "bar")

            local red = redis:new()

            red:set_timeout(1000) -- 1 sec

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = red:foo("a")
            if not res then
                ngx.say("failed to foo: ", err)
            end

            res, err = red:bar()
            if not res then
                ngx.say("failed to bar: ", err)
            end
        ';
--- response_body eval
qr/\Afailed to foo: ERR unknown command [`']foo[`'](?:, with args beginning with: `a`,\s*)?
failed to bar: ERR unknown command [`']bar[`'](?:, with args beginning with:\s*)?
\z/
--- no_error_log
[error]
