
local ffi = require 'ffi'


local ffi_new = ffi.new
local C = ffi.C
local type = type
local pairs = pairs
local unpack = unpack
local setmetatable = setmetatable
local tonumber = tonumber
local tostring = tostring
local ngx_log = ngx.log
local redis_dict = ngx.shared.redis_dict
local instance_count = "instance_count"
local redis_flag = "redis_flag"

local DEFAULT_RETRY_COUNT = 3
local DEFUALT_KEEPALIVE_TIMEOUT = 1000
local DEFAULT_KEEPALIVE_CONS = 100



local ok, new_tab = pcall(require, "table.new")
if not ok or type(new_tab) ~= "function" then
    new_tab = function (narr, nrec) return {} end
end


local _M = new_tab(0, 84)
local mt = { __index = _M }
local slot_cache = {}


ffi.cdef[[
int lua_redis_crc16(char *key, int keylen);
]]


local function load_shared_lib(so_name)
    local string_gmatch = string.gmatch
    local string_match = string.match
    local io_open = io.open
    local io_close = io.close
    local cpath = package.cpath

    for k, _ in string_gmatch(cpath, "[^;]+") do
        local fpath = string_match(k, "(.*/)")
        fpath = fpath .. so_name
        local f = io_open(fpath)
        if f ~= nil then
            io_close(f)
            return ffi.load(fpath)
        end
    end
end


local clib , err= load_shared_lib("libredis_slot.so")
if not clib then
    ngx_log(ngx.ERR,"load failed",err)
end


local function _get_redis_slot(str)
    return clib.lua_redis_crc16(ffi.cast("char *", str), #str)
end


local qps = function(var_prefix)
    local query_count = var_prefix .. "__query_counter"
    local newval, err = redis_dict:incr(query_count, 1)
    if not newval and err == "not found" then
        redis_dict:add(query_count, 1, 86400)
    end
end


function  _M.ssl_qps(prefix)
    qps(prefix)
end


local redis = require "lib.resty.redis"
redis.add_commands("cluster")


local commands = {
    "hexists",           "hget",              "hgetall",            "hincrby",           "hkeys",
    "hlen",              "hmget",             "hmset",              "hset",              "getrange",
    "hsetnx",            "hvals",             "incr",               "incrby",            "keys",
    "lindex",            "linsert",           "llen",               "lpop",              "lpush",
    "lpushx",            "lrange",            "lrem",               "lset",              "ltrim",
    "mget",              "monitor",           "mset",               "msetnx",            "hdel",
    "rpop",              "rpush",             "rpushx",             "get",               "getbit",
    "sadd",              "scard",             "set",                "setbit",            "setex",
    "setnx",             "setrange",          "smembers",           "smove",             "sort",
    "spop",              "srandmember",       "srem",               "strlen",            "sunion",
    "sunionstore",       "ttl",               "exec",               "exists",            "append",
    "type",              "auth",              "decr",               "decrby",            "del",
    "zadd",              "zcard",             "zcount",             "zincrby",           "zinterstore",
    "zrange",            "zrangebyscore",     "zrank",              "zrem",              "zremrangebyrank",
    "zremrangebyscore",  "zrevrange",         "zrevrangebyscore",   "zrevrank",          "zscore",
}

function _M.connect_to_host(self, host, port)
    local red = redis:new()

    if self.config.connect_timeout  then
        red:set_timeout(self.config.connect_timeout)
    end

    local ok, err = red:connect(host, port)
    if not ok then
        ngx_log(ngx.ERR, host, ":", port, ", connect failed: ", err)
        return nil, err
    end

    if self.config.password  then
        local ok, err = red:auth(self.config.password)
        if not ok then
            ngx_log(ngx.ERR, host, ":", port, ", auth failed: ", err)
            return nil, err
        end
    end

    return red
end



function _M.fetch_slots(self)
    redis_dict:set(redis_flag, 0)
    local serv_list = self.config.serv_list
    if not serv_list or #serv_list < 1 then
        ngx_log(ngx.ERR, "redis cluster config has no server  ")
    end

    for i=1,#serv_list do
        local ip = serv_list[i].ip
        local port = serv_list[i].port
        local red, err = self.connect_to_host(self,ip, port)
        if red and not err then
            local slot_info, err = red:cluster("slots")
            if slot_info then
                local slots = {}
                for i=1,#slot_info do
                    local item = slot_info[i]
                    local list = {serv_list={}, index = 1}
                    for j = 3,#item do
                        list.serv_list[#list.serv_list + 1] = {ip = item[j][1], port = item[j][2]}
                    end
                    for slot = item[1],item[2] do
                        slots[slot] = list
                    end
                end
                slot_cache[self.config.name] = slots
                return
            end
        end
    end
    redis_dict:set(redis_flag, 1)
    return nil ," cluster fetch_slots failed"
end


function _M.init_slots(self)
    if not self.config.name then
        ngx_log(ngx.ERR, "redis config need a cluster name  ")
        return
    end

    if slot_cache[self.config.name] then
        return
    end
    local ok, err = redis_dict:get(redis_flag)
    if not ok then
        redis_dict:set(redis_flag, 1)
    end
    local flag = redis_dict:get(redis_flag)
    if flag == 1 then
        self:fetch_slots()
    end
end


function _M.new(self, config)
    local inst = {config = config}

    local instance_max = inst.config.instance_max

    if instance_max then
        local count = redis_dict:get(instance_count)

        if not count then
            local ok, err = redis_dict:safe_add(instance_count, 0)
            count = redis_dict:get(instance_count)
        end

        if count < instance_max then
            redis_dict:incr(instance_count, 1)
            inst.red = redis:new()
        else
            inst.red = nil
        end
    else
        inst.red = redis:new()
    end

    if inst.red == nil then
        return nil
    end

    inst = setmetatable(inst, mt)
    inst:init_slots()
    return inst
end


function _M.red_remove(self)
    self.red = nil
    redis_dict:incr("instance_count", -1)
end


local function _get_slave_list(index, size)

    index = index + 1
    if index > size then
        index = 1
    end
    return index
end



local function _do_cmd(self, cmd, key, ...)
    if self._reqs then
        local args = {...}
        local t = {cmd = cmd, key=key, args=args}
        table.insert(self._reqs, t)
        return
    end
    local config = self.config
    local hash_tag=config.hash_tag

    key = tostring(key)

    if hash_tag then
        key='{'..hash_tag..'}'..key
    end

    local slot = _get_redis_slot(key)

    for i=1, DEFAULT_RETRY_COUNT do
        local slots = slot_cache[self.config.name]
        local serv_list = slots[slot].serv_list
        local index =slots[slot].index
        local ip = serv_list[index].ip
        local port = serv_list[index].port
        self.red:set_timeout(config.connect_timeout or 10)
        local ok, err = self.red:connect(ip, port)
        if ok then
            slots[slot].index = index
            local res, err = (self.red)[cmd](self.red, key, ...)
            self.red:set_keepalive(config.keepalive_timeout or DEFUALT_KEEPALIVE_TIMEOUT, config.keepalive_conns or DEFAULT_KEEPALIVE_CONS)
            if err and string.sub(err, 1, 5) == "MOVED" then
                local ok, err = redis_dict:get(redis_flag)
                if not ok then
                    redis_dict:set(redis_flag, 1)
                end
                local flag = redis_dict:get(redis_flag)
                if flag == 1 then
                    self:fetch_slots()
                end
            else
                return res, err
            end
        else
            slots[slot].index = _get_slave_list(index, #serv_list)
        end
    end

    return nil,"cmd error"
end


for i = 1, #commands do
    local cmd = commands[i]

    _M[cmd] =
    function (self, ...)
        return _do_cmd(self, cmd, ...)
    end
end


function _M.init_pipeline(self)
    self._reqs = {}
end



function _M.commit_pipeline(self)
    if not self._reqs or #self._reqs == 0 then
        return
    end

    local reqs = self._reqs
    self._reqs = nil
    local config = self.config
    local slots = slot_cache[config.name]
    if not slots then
        self:fetch_slots()
    end
    local array_ret = {}
    local array_req = {}

    for i=1,#reqs do
        reqs[i].index = i
        local key = reqs[i].key
        local slot =_get_redis_slot(tostring(key))
        local slot_item = slots[slot]
        local ip = slot_item.serv_list[slot_item.index].ip
        local port = slot_item.serv_list[slot_item.index].port
        local inst_key = ip..port

        if not array_req[inst_key] then
            array_req[inst_key] = {ip=ip,port=port,reqs={}}
            array_ret[inst_key] = {}
        end
        local _req_array = array_req[inst_key].reqs
        _req_array[#_req_array +1] = reqs[i]
    end

    for k, v in pairs(array_req) do
        local ip = v.ip
        local port = v.port
        local ins_reqs = v.reqs
        local red, err = self.connect_to_host(self,ip, port)

        if red and not err then
            red:init_pipeline()
            for i=1,#ins_reqs do
                local req = ins_reqs[i]
                if #req.args > 0 then
                    red[req.cmd](red, req.key, unpack(req.args))
                else
                    red[req.cmd](red, req.key)
                end
            end
            local res, err = red:commit_pipeline()
            red:set_keepalive(config.keepalive_timeout or DEFUALT_KEEPALIVE_TIMEOUT,
            config.keepalive_conns or DEFAULT_KEEPALIVE_CONS)
            if err then
                self:fetch_slots()
                return nil,"commit_pipeline failed" .. ip .. port
            end
            array_ret[k] = res
        else
            self:fetch_slots()
            return nil ,err .. "pipeline connect err" .. ip .. port
        end
    end
    local ret = {}
    for k,v in pairs(array_ret) do
        local ins_reqs = array_req[k].reqs
        local res = v
        for i=1,#ins_reqs do
            ret[ins_reqs[i].index] =res[i]
        end
    end

    return ret

end


function _M.cancel_pipeline(self)
    self._reqs = nil
end


return _M