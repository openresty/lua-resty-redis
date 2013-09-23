-- Copyright (C) 2012-2013 Yichun Zhang (agentzh), CloudFlare Inc.


local sub = string.sub
local tcp = ngx.socket.tcp
local concat = table.concat
local len = string.len
local null = ngx.null
local pairs = pairs
local unpack = unpack
local setmetatable = setmetatable
local tonumber = tonumber
local error = error


local _M = {
    _VERSION = '0.16'
}

local commands = {
    "append",            "auth",              "bgrewriteaof",
    "bgsave",            "bitcount",          "bitop",
    "blpop",             "brpop",
    "brpoplpush",        "client",            "config",
    "dbsize",
    "debug",             "decr",              "decrby",
    "del",               "discard",           "dump",
    "echo",
    "eval",              "exec",              "exists",
    "expire",            "expireat",          "flushall",
    "flushdb",           "get",               "getbit",
    "getrange",          "getset",            "hdel",
    "hexists",           "hget",              "hgetall",
    "hincrby",           "hincrbyfloat",      "hkeys",
    "hlen",
    "hmget",             --[[ "hmset", ]]     "hset",
    "hsetnx",            "hvals",             "incr",
    "incrby",            "incrbyfloat",       "info",
    "keys",
    "lastsave",          "lindex",            "linsert",
    "llen",              "lpop",              "lpush",
    "lpushx",            "lrange",            "lrem",
    "lset",              "ltrim",             "mget",
    "migrate",
    "monitor",           "move",              "mset",
    "msetnx",            "multi",             "object",
    "persist",           "pexpire",           "pexpireat",
    "ping",              "psetex",            "psubscribe",
    "pttl",
    "publish",           "punsubscribe",      "pubsub",
    "quit",
    "randomkey",         "rename",            "renamenx",
    "restore",
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
    "sunionstore",       "sync",              "time",
    "ttl",
    "type",              "unsubscribe",       "unwatch",
    "watch",             "zadd",              "zcard",
    "zcount",            "zincrby",           "zinterstore",
    "zrange",            "zrangebyscore",     "zrank",
    "zrem",              "zremrangebyrank",   "zremrangebyscore",
    "zrevrange",         "zrevrangebyscore",  "zrevrank",
    "zscore",            "zunionstore",       "evalsha"
}


local mt = { __index = _M }


function _M.new(self)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end
    return setmetatable({ sock = sock }, mt)
end


function _M.set_timeout(self, timeout)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:settimeout(timeout)
end


function _M.connect(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:connect(...)
end


function _M.set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end


function _M.get_reused_times(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:getreusedtimes()
end


function _M.close(self)
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
        local nvals = 0
        for i = 1, n do
            local res, err = _read_reply(sock)
            if res then
                nvals = nvals + 1
                vals[nvals] = res

            elseif res == nil then
                return nil, err

            else
                -- be a valid redis error value
                nvals = nvals + 1
                vals[nvals] = {false, err}
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
    local nbits = #req
    local nargs = #args

    for i = 1, nargs do
        local arg = args[i]

        if not arg then
            nbits = nbits + 1
            req[nbits] = "$-1\r\n"

        else
            req[nbits + 1] = "$"
            req[nbits + 2] = len(arg)
            req[nbits + 3] = "\r\n"
            req[nbits + 4] = arg
            req[nbits + 5] = "\r\n"
            nbits = nbits + 5
        end
    end

    -- it is faster to do string concatenation on the Lua land
    return concat(req)
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
        reqs[#reqs + 1] = req
        return
    end

    -- print("request: ", table.concat(req))

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    return _read_reply(sock)
end


function _M.read_reply(self)
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


function _M.hmset(self, hashname, ...)
    local args = {...}
    if #args == 1 then
        local t = args[1]
        local array = {}
        local n = 0
        for k, v in pairs(t) do
            array[n + 1] = k
            array[n + 2] = v
            n = n + 2
        end
        -- print("key", hashname)
        return _do_cmd(self, "hmset", hashname, unpack(array))
    end

    -- backwards compatibility
    return _do_cmd(self, "hmset", hashname, ...)
end


function _M.init_pipeline(self)
    self._reqs = {}
end


function _M.cancel_pipeline(self)
    self._reqs = nil
end


function _M.commit_pipeline(self)
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
    local nvals = 0
    local nreqs = #reqs
    for i = 1, nreqs do
        local res, err = _read_reply(sock)
        if res then
            nvals = nvals + 1
            vals[nvals] = res

        elseif res == nil then
            return nil, err

        else
            -- be a valid redis error value
            nvals = nvals + 1
            vals[nvals] = {false, err}
        end
    end

    return vals
end


function _M.array_to_hash(self, t)
    local h = {}
    for i = 1, #t, 2 do
        h[t[i]] = t[i + 1]
    end
    return h
end


function _M.add_commands(...)
    local cmds = {...}
    for i = 1, #cmds do
        local cmd = cmds[i]
        _M[cmd] =
            function (self, ...)
                return _do_cmd(self, cmd, ...)
            end
    end
end


return _M
