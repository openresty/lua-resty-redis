-- Copyright (C) 2012 Zhang "agentzh" Yichun (章亦春)

module("resty.redis", package.seeall)


local mt = { __index = resty.redis }

local sub = string.sub
local tcp = ngx.socket.tcp


function new(self)
    return setmetatable({ sock = tcp() }, mt)
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


function set(self, ...)
    return _do_cmd(self, "set", ...)
end


function get(self, ...)
    return _do_cmd(self, "get", ...)
end


function _do_cmd(self, ...)
    local args = {...}

    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local req = {"*", #args, "\r\n"}
    for i, arg in ipairs(args) do
        if not arg then
            table.insert(req, "$-1\r\n")
        else
            table.insert(req, "$")
            table.insert(req, string.len(arg))
            table.insert(req, "\r\n")
            table.insert(req, arg)
            table.insert(req, "\r\n")
        end
    end

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    return read_reply(sock)
end


function read_reply(sock)
    local line, err = sock:receive()
    if not line then
        return nil, err
    end

    local prefix = sub(line, 1, 1)

    if prefix == "$" then
        local size = tonumber(sub(line, 2))
        if size < 0 then
            return nil, nil
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
        -- status reply
        return sub(line, 2)

    elseif prefix == "*" then
        -- multi-bulk reply
        local n = tonumber(sub(line, 2))
        local vals = {};
        for i = 1, n do
            table.insert(vals, read_reply(sock))
        end
        return vals

    elseif prefix == ":" then
        -- integer reply
        return tonumber(sub(line, 2))

    elseif prefix == "-" then
        return nil, sub(line, 2)

    else
        return nil, "unkown prefix: \"" .. prefix .. "\""
    end
end


-- to prevent use of casual module global variables
getmetatable(resty.redis).__newindex = function (table, key, val)
    error('attempt to write to undeclared variable "' .. key .. '": '
            .. debug.traceback())
end

