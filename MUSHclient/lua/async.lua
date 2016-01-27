module("async", package.seeall)
local _llthreads = require("llthreads")
require "socket.http" -- just make sure they can load
require "ssl.https" -- just make sure they can load

local thread_pool = {}
local request_urls = {}
local request_times = {}
local result_callbacks = {}
local timeout_callbacks = {}
local timeouts = {}

-- This is really the function you should use instead of calling request directly.
-- result_callback_function gets arguments (retval, page, status, headers, full_status, requested_url)
-- callback_on_timeout function gets arguments (requested_url, timeout_after)
-- request_protocol is either HTTP or HTTPS
-- timeout_after is in seconds
function doAsyncRemoteRequest(request_url, result_callback_function, request_protocol, timeout_after, callback_on_timeout)
   if request_protocol == nil then
      request_protocol = "HTTPS"
   end
   if timeout_after == nil then
      timeout_after = 30
   end

   thread_id = tostring(GetUniqueNumber())
   
   assert(type(request_url) == "string")
   assert(request_protocol == "HTTP" or request_protocol == "HTTPS")
   assert(type(timeout_after) == "number")
   assert(type(result_callback_function) == "function" or type(result_callback_function) == "string")
   assert(type(callback_on_timeout) == "function" or type(callback_on_timeout) == "string" or callback_on_timeout == nil)
   
   request_urls[thread_id] = request_url
   timeouts[thread_id] = timeout_after
   thread_pool[thread_id] = request(request_url, request_protocol)
   request_times[thread_id] = os.time()

   if type(result_callback_function) == "function" then
      result_callbacks[thread_id] = result_callback_function
   else
      result_callbacks[thread_id] = loadstring(result_callback_function)
   end
   
   if type(callback_on_timeout) == "function" or callback_on_timeout == nil then
      timeout_callbacks[thread_id] = callback_on_timeout
   else
      timeout_callbacks[thread_id] = loadstring(callback_on_timeout)
   end
   
   __checkCompletionFor(thread_id)
end





function default_timeout_callback(requested_url, timeout) 
   print("Async Request ["..requested_url.."] Thread Timed Out After "..tostring(timeout).."s") 
end

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
    local thread = _llthreads.new(network_thread_code, {url=url, protocol=protocol})
    thread:start()
    return thread
end

function __checkCompletionFor(thread_id)
   if thread_pool[thread_id]:alive() then
      if os.time() - request_times[thread_id] > timeouts[thread_id] then
         -- stop trying after timeout_after seconds
         local timeout_callback = timeout_callbacks[thread_id]
         local request_url = request_urls[thread_id]
         local timeout = timeouts[thread_id]
         
         thread_pool[thread_id] = nil
         request_times[thread_id] = nil
         result_callbacks[thread_id] = nil
         timeout_callbacks[thread_id] = nil
         timeouts[thread_id] = nil
         request_urls[thread_id] = nil
         
         if timeout_callback ~= nil then
            timeout_callback(request_url, timeout)
         else
            default_timeout_callback(request_url, timeout)
         end
      else
         DoAfterSpecial(0.2, "async.__checkCompletionFor('"..thread_id.."')", sendto.script)
      end
   else
      local retval, page, status, headers, full_status = thread_pool[thread_id]:join()
      local request_url = request_urls[thread_id]
      local callback_func = result_callbacks[thread_id]
      
      result_callbacks[thread_id] = nil
      timeout_callbacks[thread_id] = nil
      thread_pool[thread_id] = nil
      request_times[thread_id] = nil
      timeouts[thread_id] = nil
      request_urls[thread_id] = nil

      callback_func(retval, page, status, headers, full_status, request_url)
   end
end
