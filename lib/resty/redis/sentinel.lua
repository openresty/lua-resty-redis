local ipairs, type = ipairs, type
local ngx_null = ngx.null
local tbl_insert = table.insert

local ok, tbl_new = pcall(require, "table.new")
if not ok then
    tbl_new = function (narr, nrec) return {} end
end


local _M = {}
_M._VERSION = 0.01


function _M.get_master(sentinel, master_name)
    local res, err = sentinel:sentinel(
        "get-master-addr-by-name",
        master_name
    )
    if res and res ~= ngx_null and res[1] and res[2] then
        return { host = res[1], port = res[2] }
    else
        return nil, err
    end
end


function _M.get_slaves(sentinel, master_name)
    local res, err = sentinel:sentinel("slaves", master_name)

    if res and type(res) == "table" then
        local hosts = tbl_new(#res, 0)
        for _,slave in ipairs(res) do
            local num_recs = #slave
            local host = tbl_new(0, num_recs + 1)
            for i = 1, num_recs, 2 do
                host[slave[i]] = slave[i + 1]
            end
            host.host = host.ip -- for parity with other functions
            tbl_insert(hosts, host)
        end
        if hosts[1] ~= nil then
            return hosts
        else
            return nil, "no slaves available"
        end
    else
        return nil, err
    end
end


return _M
