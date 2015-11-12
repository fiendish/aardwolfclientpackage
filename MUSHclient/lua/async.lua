module("async", package.seeall)
local _llthreads = require("llthreads")

local thread_pool = {}
local request_urls = {}
local request_times = {}
local result_callbacks = {}
local timeouts = {}

-- result_callback_function gets arguments (retval, page, status, headers, full_status, requested_url)
function doAsyncRemoteRequest(request_url, result_callback_function, request_protocol, timeout_after)
   if request_protocol == nil then
      request_protocol = "HTTP"
   end
   if timeout_after == nil then
      timeout_after = 30
   end

   thread_id = tostring(GetUniqueNumber())
      
   assert(type(request_url) == "string")  
   assert(request_protocol == "HTTP" or request_protocol == "HTTPS")
   assert(type(timeout_after) == "number")
   assert(type(result_callback_function) == "function" or type(result_callback_function) == "string")
   
   request_urls[thread_id] = request_url
   timeouts[thread_id] = timeout_after
   thread_pool[thread_id] = request(request_url, request_protocol)   
   request_times[thread_id] = os.time()

   if type(result_callback_function) == "function" then
      result_callbacks[thread_id] = result_callback_function
   elseif type(result_callback_function) == "string" then
      result_callbacks[thread_id] = loadstring(result_callback_function)
   end
   
   __checkCompletionFor(thread_id)
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
         print("Async Request ["..request_urls[thread_id].."] Failed")
         thread_pool[thread_id] = nil
         request_times[thread_id] = nil
         result_callbacks[thread_id] = nil
         timeouts[thread_id] = nil
         request_urls[thread_id] = nil
      else
         DoAfterSpecial(0.2, "async.__checkCompletionFor('"..thread_id.."')", sendto.script)
      end
   else
      retval, page, status, headers, full_status  = thread_pool[thread_id]:join()
      request_url = request_urls[thread_id]
      callback_func = result_callbacks[thread_id]
      result_callbacks[thread_id] = nil
      thread_pool[thread_id] = nil
      request_times[thread_id] = nil
      timeouts[thread_id] = nil
      request_urls[thread_id] = nil

      callback_func(retval, page, status, headers, full_status, request_url)
   end
end
