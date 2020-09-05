module("async", package.seeall)
local _llthreads = require("llthreads2")
require "socket.http" -- just make sure that this can load so we don't get a surprise later
require "ssl.https" -- just make sure that this can load so we don't get a surprise later
local _ltn12 = require "ltn12"

local thread_pool = {}
local requests = {}
local request_times = {}
local result_callbacks = {}
local timeout_callbacks = {}
local timeouts = {}

-- Use doAsyncRemoteRequest to make generic asynchronous requests.
-- Use HEAD to retrieve just file header information.

-- result_callback_function gets arguments (retval, page, status, headers, full_status, requested_url, request_body)
-- You can set result_callback_function to nil if you just want to print everything that comes back to the screen.
-- callback_on_timeout function gets arguments (requested_url, timeout_after, request_body)
-- request_protocol is HTTP or HTTPS (if not provided, it will be inferred from the request_url)
-- timeout_after is in seconds
-- request_body is either nil, a string (which will switch the HTTP method to POST instead of the default GET), or a table of HTTP request parameters such as source/sink/method/headers. See http://w3.impa.br/~diego/software/luasocket/http.html for more details
function doAsyncRemoteRequest(request_url, result_callback_function, request_protocol, timeout_after, callback_on_timeout, request_body)
   if request_protocol == nil then
      if starts_with(request_url:lower(), "https:") then
         request_protocol = "HTTPS"
      elseif starts_with(request_url:lower(), "http:") then
         request_protocol = "HTTP"
      end
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

   requests[thread_id] = {['url']=request_url, ['body']=request_body}
   timeouts[thread_id] = timeout_after
   thread_pool[thread_id] = request(request_url, request_protocol, request_body)
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

function HEAD(request_url, result_callback_function, request_protocol, timeout_after, callback_on_timeout)
   local request_body = { method = "HEAD" }
   doAsyncRemoteRequest(request_url, result_callback_function, request_protocol, timeout_after, callback_on_timeout, request_body)
end

function GETFILE(request_url, result_callback_function, request_protocol, file_name, timeout_after, callback_on_timeout)
   local request_body = { sink = file_name }
   doAsyncRemoteRequest(request_url, result_callback_function, request_protocol, timeout_after, callback_on_timeout, request_body)
end


function starts_with(str, start)
   return str:sub(1, #start) == start
end

function default_timeout_callback(requested_url, timeout, request_body)
   print("Request to ["..requested_url.."] timed out after "..tostring(timeout).." second"..(timeout ~= 1 and "s." or "."))
   if request_body then
      if type(request_body) == "table" then
         require "tprint"
         print("Message body was: {")
         tprint(request_body, 3)
         print("}")
      else
         print("Message Body Was:", request_body)
      end
   end
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

   local body = args["body"]
   local page, status, headers, full_status

   if type(body) == "table" then
      _ltn12 = require "ltn12"

      body.url = args.url

      if type(body.sink) == "string" then  -- write to file
         body.sink = _ltn12.sink.file(io.open(body.sink, "wb"))
      end

      if type(body.source) == "string" then
         body.headers = body.headers or {}
         body.headers["content-length"] = tostring(#body.source)
         body.headers["content-type"] = body.headers["content-type"] or "application/x-www-form-urlencoded"
         body.method = "POST"
         body.source = _ltn12.source.string(body.source)
      end

      page, status, headers, full_status = _socketeer.request(body)
   else
      page, status, headers, full_status = _socketeer.request(args.url, body)
   end

   return page, status, headers, full_status
end)

-- makes an asynchronous HTTP or HTTPS request to a URL
function request(url, protocol, body)
   local thread = _llthreads.new(network_thread_code, {url=url, protocol=protocol, body=body})
   thread:start()
   return thread
end

function __checkCompletionFor(thread_id)
   if thread_pool[thread_id]:alive() then
      if os.time() - request_times[thread_id] > timeouts[thread_id] then
         -- stop trying after timeout_after seconds
         local timeout_callback = timeout_callbacks[thread_id]
         local request_data = requests[thread_id]
         local timeout = timeouts[thread_id]

         thread_pool[thread_id] = nil
         request_times[thread_id] = nil
         result_callbacks[thread_id] = nil
         timeout_callbacks[thread_id] = nil
         timeouts[thread_id] = nil
         requests[thread_id] = nil

         if timeout_callback ~= nil then
            timeout_callback(request_data['url'], timeout, request_data['body'])
         else
            default_timeout_callback(request_data['url'], timeout, request_data['body'])
         end
      else
         DoAfterSpecial(0.2, "async.__checkCompletionFor('"..thread_id.."')", sendto.script)
      end
   else
      local retval, page, status, headers, full_status = thread_pool[thread_id]:join()
      local request_data = requests[thread_id]
      local callback_func = result_callbacks[thread_id]

      result_callbacks[thread_id] = nil
      timeout_callbacks[thread_id] = nil
      thread_pool[thread_id] = nil
      request_times[thread_id] = nil
      timeouts[thread_id] = nil
      requests[thread_id] = nil

      callback_func(retval, page, status, headers, full_status, request_data['url'], request_data['body'])
   end
end
