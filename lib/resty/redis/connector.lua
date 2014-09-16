local redis = require "resty.redis"
local sentinel = require "resty.redis.sentinel"


local ipairs, type, setmetatable = ipairs, type, setmetatable
local ngx_null = ngx.null
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local tbl_insert = table.insert
local tbl_remove = table.remove

local ok, tbl_new = pcall(require, "table.new")
if not ok then
    tbl_new = function (narr, nrec) return {} end
end


local _M = {}
_M._VERSION = 0.01


local HOST_DEFAULTS = {
    host = "127.0.0.1",
    port = 6379,
    socket = nil,
    password = nil,
}

local SENTINEL_DEFAULTS = {
    hosts = {
        { host = "127.0.0.1", port = 26379 }
    },
    master_name = "mymaster",
    try_slaves = false,
}

local OPTIONS_DEFAULTS = {
    connect_timeout = 100,
    read_timeout = 1000,
    database = 0,
    connect_options = nil, -- pool, etc
}


function _M.connect(params, options)
    if not params then params = {} end
    if not options then options = {} end
    setmetatable(options, { __index = OPTIONS_DEFAULTS })

    local redis, sentinel = params.redis, params.sentinel

    if redis then
        return _M.connect_to_host(params.redis, options)
    elseif sentinel then
        setmetatable(sentinel, { __index = SENTINEL_DEFAULTS })
        return _M.connect_via_sentinel(sentinel.hosts, sentinel.master_name, sentinel.try_slaves, options)
    end
end


function _M.connect_via_sentinel(sentinels, master_name, try_slaves, options)
    local sentnl, err, previous_errors = _M.try_hosts(sentinels, options)
    if not sentnl then
        return nil, err, previous_errors
    end

    local master, err = sentinel.get_master(sentnl, master_name)
    if master then
        return _M.connect_to_host(master, options)
    else
        if not try_slaves then
            return nil, err
        else
            local slaves, err = sentinel.get_slaves(sentnl, master_name)
            if not slaves then
                return nil, err
            end

            local slave, err, previous_errors = _M.try_hosts(slaves, options)
            if not slave then
                return nil, err, previous_errors
            end

            return slave
        end
    end
end


-- In case of errors, returns "nil, err, previous_errors" where err is
-- the last error received, and previous_errors is a table of the previous errors.
function _M.try_hosts(hosts, options)
    local errors = tbl_new(#hosts, 0)
    for i, host in ipairs(hosts) do
        local r
        r, errors[i] = _M.connect_to_host(host, options)
        if r then
            return r, tbl_remove(errors), errors
        end
    end
    return nil, tbl_remove(errors), errors
end


function _M.connect_to_host(host, options)
    if not host then host = {} end
    if not options then options = {} end
    setmetatable(host, { __index = HOST_DEFAULTS })
    setmetatable(options, { __index = OPTIONS_DEFAULTS })

    local r = redis.new()
    r:set_timeout(options.connect_timeout)

    local ok, err
    local socket = host.socket
    if socket then
        if options.connect_options then
            ok, err = r:connect(socket, options.connect_options)
        else
            ok, err = r:connect(socket)
        end
    else
        if options.connect_options then
            ok, err = r:connect(host.host, host.port, options.connect_options)
        else
            ok, err = r:connect(host.host, host.port)
        end
    end

    if not ok then
        ngx_log(ngx_ERR, err)
        return nil, err
    else
        r:set_timeout(self, options.read_timeout)
        r:select(options.database)
        return r, nil
    end
end


return _M
