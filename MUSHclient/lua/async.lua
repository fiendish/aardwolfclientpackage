module("async", package.seeall)
local _llthreads = require("llthreads")

local network_thread_code = string.dump(function(arg)
    local args = arg
    local _socketeer = nil
    if args.protocol == "HTTPS" then
       _socketeer = require("ssl.https")
    elseif args.protocol == "HTTP" then
       _socketeer = require("socket.http")
    else
       return false
    end

    local page, status, headers, full_status = _socketeer.request(args.url)
    return page, status, headers, full_status
end)

-- makes an asynchronous HTTP or HTTPS request to a URL
function request(url, protocol)
    thread = _llthreads.new(network_thread_code, {url=url, protocol=protocol})
    thread:start()
    return thread
end

