-- Copyright (C) 2012 Yichun Zhang (agentzh)


local sub = string.sub
local tcp = ngx.socket.tcp
local insert = table.insert
local concat = table.concat
local len = string.len
local null = ngx.null
local pairs = pairs
local unpack = unpack
local setmetatable = setmetatable
local tonumber = tonumber
local error = error


module(...)

_VERSION = '0.15'

local commands = {
    "append",            "auth",              "bgrewriteaof",
    "bgsave",            "blpop",             "brpop",
    "brpoplpush",        "config",            "dbsize",
    "debug",             "decr",              "decrby",
    "del",               "discard",           "echo",
    "eval",              "exec",              "exists",
    "expire",            "expireat",          "flushall",
    "flushdb",           "get",               "getbit",
    "getrange",          "getset",            "hdel",
    "hexists",           "hget",              "hgetall",
    "hincrby",           "hkeys",             "hlen",
    "hmget",             --[[ "hmset", ]]     "hset",
    "hsetnx",            "hvals",             "incr",
    "incrby",            "info",              "keys",
    "lastsave",          "lindex",            "linsert",
    "llen",              "lpop",              "lpush",
    "lpushx",            "lrange",            "lrem",
    "lset",              "ltrim",             "mget",
    "monitor",           "move",              "mset",
    "msetnx",            "multi",             "object",
    "persist",           "ping",              "psubscribe",
    "publish",           "punsubscribe",      "quit",
    "randomkey",         "rename",            "renamenx",
    "rpop",              "rpoplpush",         "rpush",
    "rpushx",            "sadd",              "save",
    "scard",             "script",
    "sdiff",             "sdiffstore",
    "select",            "set",               "setbit",
    "setex",             "setnx",             "setrange",
    "shutdown",          "sinter",            "sinterstore",
    "sismember",         "slaveof",           "slowlog",
    "smembers",          "smove",             "sort",
    "spop",              "srandmember",       "srem",
    "strlen",            "subscribe",         "sunion",
    "sunionstore",       "sync",              "ttl",
    "type",              "unsubscribe",       "unwatch",
    "watch",             "zadd",              "zcard",
    "zcount",            "zincrby",           "zinterstore",
    "zrange",            "zrangebyscore",     "zrank",
    "zrem",              "zremrangebyrank",   "zremrangebyscore",
    "zrevrange",         "zrevrangebyscore",  "zrevrank",
    "zscore",            "zunionstore",       "evalsha"
}


local mt = { __index = _M }


function new(self)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end
    return setmetatable({ sock = sock }, mt)
end


function set_timeout(self, timeout)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:settimeout(timeout)
end


function connect(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:connect(...)
end


function set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end


function get_reused_times(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:getreusedtimes()
end


function close(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:close()
end


local function _read_reply(sock)
    local line, err = sock:receive()
    if not line then
        return nil, err
    end

    local prefix = sub(line, 1, 1)

    if prefix == "$" then
        -- print("bulk reply")

        local size = tonumber(sub(line, 2))
        if size < 0 then
            return null
        end

        local data, err = sock:receive(size)
        if not data then
            return nil, err
        end

        local dummy, err = sock:receive(2) -- ignore CRLF
        if not dummy then
            return nil, err
        end

        return data

    elseif prefix == "+" then
        -- print("status reply")

        return sub(line, 2)

    elseif prefix == "*" then
        local n = tonumber(sub(line, 2))

        -- print("multi-bulk reply: ", n)
        if n < 0 then
            return null
        end

        local vals = {};
        for i = 1, n do
            local res, err = _read_reply(sock)
            if res then
                insert(vals, res)

            elseif res == nil then
                return nil, err

            else
                -- be a valid redis error value
                insert(vals, {false, err})
            end
        end
        return vals

    elseif prefix == ":" then
        -- print("integer reply")
        return tonumber(sub(line, 2))

    elseif prefix == "-" then
        -- print("error reply: ", n)

        return false, sub(line, 2)

    else
        return nil, "unkown prefix: \"" .. prefix .. "\""
    end
end


local function _gen_req(args)
    local req = {"*", #args, "\r\n"}

    for i = 1, #args do
        local arg = args[i]

        if not arg then
            insert(req, "$-1\r\n")

        else
            insert(req, "$")
            insert(req, len(arg))
            insert(req, "\r\n")
            insert(req, arg)
            insert(req, "\r\n")
        end
    end

    -- it is faster to do string concatenation on the Lua land
    return concat(req, "")
end


local function _do_cmd(self, ...)
    local args = {...}

    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local req = _gen_req(args)

    local reqs = self._reqs
    if reqs then
        insert(reqs, req)
        return
    end

    -- print("request: ", table.concat(req, ""))

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    return _read_reply(sock)
end


function read_reply(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return _read_reply(sock)
end


for i = 1, #commands do
    local cmd = commands[i]

    _M[cmd] =
        function (self, ...)
            return _do_cmd(self, cmd, ...)
        end
end


function hmset(self, hashname, ...)
    local args = {...}
    if #args == 1 then
        local t = args[1]
        local array = {}
        for k, v in pairs(t) do
            insert(array, k)
            insert(array, v)
        end
        -- print("key", hashname)
        return _do_cmd(self, "hmset", hashname, unpack(array))
    end

    -- backwards compatibility
    return _do_cmd(self, "hmset", hashname, ...)
end


function init_pipeline(self)
    self._reqs = {}
end


function cancel_pipeline(self)
    self._reqs = nil
end


function commit_pipeline(self)
    local reqs = self._reqs
    if not reqs then
        return nil, "no pipeline"
    end

    self._reqs = nil

    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local bytes, err = sock:send(reqs)
    if not bytes then
        return nil, err
    end

    local vals = {}
    for i = 1, #reqs do
        local res, err = _read_reply(sock)
        if res then
            insert(vals, res)

        elseif res == nil then
            return nil, err

        else
            -- be a valid redis error value
            insert(vals, {false, err})
        end
    end

    return vals
end


function array_to_hash(self, t)
    local h = {}
    for i = 1, #t, 2 do
        h[t[i]] = t[i + 1]
    end
    return h
end


local class_mt = {
    -- to prevent use of casual module global variables
    __newindex = function (table, key, val)
        error('attempt to write to undeclared variable "' .. key .. '"')
    end
}


function add_commands(...)
    local cmds = {...}
    local newindex = class_mt.__newindex
    class_mt.__newindex = nil
    for i = 1, #cmds do
        local cmd = cmds[i]
        _M[cmd] =
            function (self, ...)
                return _do_cmd(self, cmd, ...)
            end
    end
    class_mt.__newindex = newindex
end


setmetatable(_M, class_mt)

