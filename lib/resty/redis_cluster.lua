local redis = require "redis"
local bit = require "bit"

local setmetatable = setmetatable
local pairs = pairs
local sub = string.sub
local find = string.find
local byte = string.byte
local char = string.char
local tostring = tostring
local tonumber = tonumber


local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

local _M = new_tab(0, 20)

_M._VERSION = '0.01'

local REDIS_CLUSTER_HASH_SLOTS = 16384
local REDIS_CLUSTER_REQUEST_TTL = 16
local REDIS_CLUSTER_DEFAULT_TIMEOUT = 1000   --1sec
local REDIS_CLUSTER_DEFAULT_KEEPALIVE_DURATION = 10000   --10sec
local REDIS_CLUSTER_DEFAULT_KEEPALIVE_SIZE = 100   --100 connections

-- TODO: move to separate file
local XMODEMCRC16Lookup = {
        0x0000,0x1021,0x2042,0x3063,0x4084,0x50a5,0x60c6,0x70e7,
        0x8108,0x9129,0xa14a,0xb16b,0xc18c,0xd1ad,0xe1ce,0xf1ef,
        0x1231,0x0210,0x3273,0x2252,0x52b5,0x4294,0x72f7,0x62d6,
        0x9339,0x8318,0xb37b,0xa35a,0xd3bd,0xc39c,0xf3ff,0xe3de,
        0x2462,0x3443,0x0420,0x1401,0x64e6,0x74c7,0x44a4,0x5485,
        0xa56a,0xb54b,0x8528,0x9509,0xe5ee,0xf5cf,0xc5ac,0xd58d,
        0x3653,0x2672,0x1611,0x0630,0x76d7,0x66f6,0x5695,0x46b4,
        0xb75b,0xa77a,0x9719,0x8738,0xf7df,0xe7fe,0xd79d,0xc7bc,
        0x48c4,0x58e5,0x6886,0x78a7,0x0840,0x1861,0x2802,0x3823,
        0xc9cc,0xd9ed,0xe98e,0xf9af,0x8948,0x9969,0xa90a,0xb92b,
        0x5af5,0x4ad4,0x7ab7,0x6a96,0x1a71,0x0a50,0x3a33,0x2a12,
        0xdbfd,0xcbdc,0xfbbf,0xeb9e,0x9b79,0x8b58,0xbb3b,0xab1a,
        0x6ca6,0x7c87,0x4ce4,0x5cc5,0x2c22,0x3c03,0x0c60,0x1c41,
        0xedae,0xfd8f,0xcdec,0xddcd,0xad2a,0xbd0b,0x8d68,0x9d49,
        0x7e97,0x6eb6,0x5ed5,0x4ef4,0x3e13,0x2e32,0x1e51,0x0e70,
        0xff9f,0xefbe,0xdfdd,0xcffc,0xbf1b,0xaf3a,0x9f59,0x8f78,
        0x9188,0x81a9,0xb1ca,0xa1eb,0xd10c,0xc12d,0xf14e,0xe16f,
        0x1080,0x00a1,0x30c2,0x20e3,0x5004,0x4025,0x7046,0x6067,
        0x83b9,0x9398,0xa3fb,0xb3da,0xc33d,0xd31c,0xe37f,0xf35e,
        0x02b1,0x1290,0x22f3,0x32d2,0x4235,0x5214,0x6277,0x7256,
        0xb5ea,0xa5cb,0x95a8,0x8589,0xf56e,0xe54f,0xd52c,0xc50d,
        0x34e2,0x24c3,0x14a0,0x0481,0x7466,0x6447,0x5424,0x4405,
        0xa7db,0xb7fa,0x8799,0x97b8,0xe75f,0xf77e,0xc71d,0xd73c,
        0x26d3,0x36f2,0x0691,0x16b0,0x6657,0x7676,0x4615,0x5634,
        0xd94c,0xc96d,0xf90e,0xe92f,0x99c8,0x89e9,0xb98a,0xa9ab,
        0x5844,0x4865,0x7806,0x6827,0x18c0,0x08e1,0x3882,0x28a3,
        0xcb7d,0xdb5c,0xeb3f,0xfb1e,0x8bf9,0x9bd8,0xabbb,0xbb9a,
        0x4a75,0x5a54,0x6a37,0x7a16,0x0af1,0x1ad0,0x2ab3,0x3a92,
        0xfd2e,0xed0f,0xdd6c,0xcd4d,0xbdaa,0xad8b,0x9de8,0x8dc9,
        0x7c26,0x6c07,0x5c64,0x4c45,0x3ca2,0x2c83,0x1ce0,0x0cc1,
        0xef1f,0xff3e,0xcf5d,0xdf7c,0xaf9b,0xbfba,0x8fd9,0x9ff8,
        0x6e17,0x7e36,0x4e55,0x5e74,0x2e93,0x3eb2,0x0ed1,0x1ef0
}

local cluster_invalid_cmds = {
    ["info"] = true,
    ["multi"] = true,
    ["exec"] = true,
    ["slaveof"] = true,
    ["config"] = true,
    ["shutdown"] = true
}

local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift = bit.lshift, bit.rshift

-- Depends on luajit bitop extension.
local function crc16(str)
    local crc = 0
    -- prevent the cases when client pass a wrong type of argument
    str = tostring(str)
    for i = 1, #str do
        local b = byte(str, i)
        crc = bxor(band(lshift(crc, 8), 0xffff), XMODEMCRC16Lookup[band(bxor(rshift(crc, 8), b), 0xff) + 1])
    end
    return crc
end

local clusters = new_tab(0, 20)

local function get_redis_link(host, port, timeout)
    local r = redis:new()
    r:set_timeout(timeout)
    local ok, err = r:connect(host, port)

    return r, ok, err
end

local function set_node_name(n)
    if n["name"] == nil then
        n["name"] = n["host"] .. ":" .. n["port"]
    end
end

local function string_split(str, delim, max)
    if str == nil or delim == nil then
        return nil 
    end 

    if max == nil or max <= 0 then
        max = 1000
    end 

    local t = new_tab(max, 0)
    local index = 1 
    local start = 1 
    for i = 1, max do
        local last, delim_last = find(str, delim, start, true)
        if last == nil or delim_last == nil then
            break
        end 

        t[i] = sub(str, start, last - 1)
        start = delim_last + 1 
        index = i + 1 
    end 
    t[index] = sub(str, start)
    return t
end

local mt = { __index = _M }

function _M.new(self, cluster_id, startup_nodes, opt)
    if clusters[cluster_id] == nil then
        clusters[cluster_id] = {
            startup_nodes = startup_nodes,
            nodes = nil,
            slots = nil,
            timeout = (opt and opt.timeout) and opt.timeout or REDIS_CLUSTER_DEFAULT_TIMEOUT,
            keepalive_size = (opt and opt.keepalive_size) and opt.keepalive_size or REDIS_CLUSTER_DEFAULT_KEEPALIVE_SIZE,
            keepalive_duration = (opt and opt.keepalive_duration) and opt.keepalive_duration or REDIS_CLUSTER_DEFAULT_KEEPALIVE_DURATION,
            ttl = (opt and opt.ttl) and opt.ttl or REDIS_CLUSTER_REQUEST_TTL,
            refresh_table_asap = false,
            initialized = false
        }
    end

    local obj = {
        cluster_id = cluster_id
    }
    return setmetatable(obj, mt)
end

function _M.initialize(self)
    local cluster = clusters[self.cluster_id]

    if cluster == nil or cluster.startup_nodes == nil then
        return nil
    end

    if cluster.initialized == true and cluster.refresh_table_asap == false then
        return nil
    end

    local startup_nodes = cluster["startup_nodes"]

    for i = 1, #startup_nodes do
        local node = startup_nodes[i]
        local r, ok, err = get_redis_link(node[1], node[2], cluster.timeout)

        if ok then
            local results, err = r:cluster("nodes")

            cluster.nodes = new_tab(500, 0)
            cluster.slots = new_tab(REDIS_CLUSTER_HASH_SLOTS, 0)
        
            if results then
                local lines = string_split(results, char(10), 1000)
                for line_index = 1, #lines do
                    local line = lines[line_index]
                    local fields = string_split(line, " ")
                    if #fields > 1 then
                        local addr_str = fields[2]
                        local addr = nil

                        if addr_str == ":0" then
                            addr = { node[1], 
                                 tonumber(node[2]), 
                                 node[1] .. ":" .. tostring(node[2]) }
                        else
                            local host_port = string_split(addr_str, ":", 2)
                            addr = { host_port[1], 
                                 tonumber(host_port[2]), 
                                 addr_str }
                        end
                        cluster.nodes[#(cluster.nodes) + 1] = addr
                    
                        local cluster_slots = cluster.slots

                        for slot_index = 9, #fields do
                            local slot = fields[slot_index]
                            if not slot then 
                                break 
                            end
                        
                            if sub(slot, 1, 1) ~= "[" then
                                local range = string_split(slot, "-", 2)
                                local first = tonumber(range[1])
                                local last = first
                                if #range >= 2 then
                                    last = tonumber(range[2])
                                end

                                for ind = first + 1, last + 1 do
                                    cluster_slots[ind] = addr
                                end
                            end
                        end
                    end
                end
                self:populate_startup_nodes()
                cluster.initialized = true
                cluster.refresh_table_asap = false
                r:set_keepalive(cluster.keepalive_duration, cluster.keepalive_size)
                break
            else
                r:close()
            end
        end
    end
end

function _M.populate_startup_nodes(self)
    local cluster = clusters[self.cluster_id]

    if cluster == nil or cluster.startup_nodes == nil then
        return nil
    end
    
    local startup_nodes = cluster.startup_nodes
    local nodes = cluster.nodes

    local startup_nodes_count = #startup_nodes
    local nodes_count = #nodes

    local unique_nodes = new_tab(0, nodes_count + startup_nodes_count)
    
    for i = 1, startup_nodes_count do
        local startup_node = startup_nodes[i]
        if startup_node[3] == nil then
            startup_node[3] = startup_node[1] .. ":" .. tostring(startup_node[2])
        end

        unique_nodes[startup_node[3]] = startup_node
    end

    
    for i = 1, nodes_count do
        local node = nodes[i]
        unique_nodes[node[3]] = node
    end

    cluster.startup_nodes = new_tab(nodes_count + startup_nodes_count, 0)
    startup_nodes = cluster.startup_nodes

    for name, node in pairs(unique_nodes) do
        startup_nodes[#startup_nodes + 1] = node
    end
end

function _M.flush_slots_cache(self)
    clusters[self.cluster_id].slots = nil
end

function _M.keyslot(self, key)
    local s = find(key, "{")
    if s then
        local e = find(key, "}", s+1)
        if e and e ~= s+1 then
            key = sub(key, s+1, e-1) 
        end
    end

    return (crc16(key) % REDIS_CLUSTER_HASH_SLOTS) + 1
end

function _M.get_random_connection(self)
    local cluster = clusters[self.cluster_id]

    if cluster == nil or cluster.startup_nodes == nil then
        return nil
    end

    local startup_nodes = cluster.startup_nodes
    
    for i = 1, #startup_nodes do
        local node = startup_nodes[i]
        local r, ok, err  = get_redis_link(node[1], node[2], cluster.timeout)
        if ( not ok ) then
            break
        end 
        local result, err = r:ping()
        if result == "PONG" then
            return r
        end
        r:close()
    end

    return nil
end

function _M.get_connection_by_slot(self, slot)
    local cluster = clusters[self.cluster_id]
    local node = cluster.slots[slot]

    if node == nil then
        return self:get_random_connection()
    end

    if node == nil then
    end
    return get_redis_link(node[1], node[2], cluster.timeout)
end

function _M.send_cluster_command(self, cmd, ...)
    local cluster = clusters[self.cluster_id]
    if cluster.initialized == false then
        return nil, "Uninitialized cluster"
    end

    if cluster.refresh_table_asap == true then
        self:initialize()
    end

    local ttl = REDIS_CLUSTER_REQUEST_TTL
    local asking = false
    local try_random_node = false
    local argv = {...}
    local last_error = nil
    
    while ttl > 0 do
        ttl = ttl - 1

        if cluster_invalid_cmds[cmd] == true then
            last_error = "No way to dispatch this command to Redis cluster"
            break
        end

        local key = argv[1]
        local slot = self:keyslot(key)

        local r = nil
        local ok = true
        local err

        if try_random_node == true then
            r = self:get_random_connection()
            try_random_node = false
        else
            r, ok, err = self:get_connection_by_slot(slot)
        end

        -- 
        if r ~= nil and ok then
            if asking == true then
                -- TODO: pipeline
                r:asking()
            end
        
 
            asking = false
            local result, err = r[cmd](r, ...)
            if err == nil and result ~= nil then
                r:set_keepalive(cluster.keepalive_duration, cluster.keepalive_size)
                return result, err
            end

            last_error = err
        
            local err_split = string_split(err, " ")

            if err_split[1] == "ASK" then
                asking = true
            end

            if asking == true or err_split[1] == "MOVED" then
                if asking == false then
                    cluster.refresh_table_asap = true
                end

                local newslot = tonumber(err_split[2]) + 1
                local node_ip_port = string_split(err_split[3], ":")

                local addr = { node_ip_port[1], tonumber(node_ip_port[2]), err_split[3]}

                cluster.slots[newslot] = addr 
            else
                try_random_node = true
            end
        else
            cluster.refresh_table_asap = true 
            self:initialize()
        end
    end
    return nil, last_error
end

local __M = setmetatable(_M, {__index = function (tab, cmd)
    return function (self, ...)
        return tab.send_cluster_command(self, cmd, ...)
    end
end})

return __M
