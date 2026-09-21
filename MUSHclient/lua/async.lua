module("async", package.seeall)
local _llthreads = require("llthreads2")
require "socket.http" -- just make sure that this can load so we don't get a surprise later
require "ssl.https" -- just make sure that this can load so we don't get a surprise later
local _ltn12 = require "ltn12"

local requests = {}
local dispatcher_timer = "async_request_dispatcher__"
local dispatcher_interval = 0.2
local dispatcher_command = "async.__pollRequests()"

local function timer_error(action, status)
   local description = error_desc and error_desc[status]
   error(action.." failed: "..(description or tostring(status)), 3)
end

local function enable_dispatcher()
   local status = IsTimer(dispatcher_timer)
   if status == error_code.eTimerNotFound then
      status = AddTimer(
         dispatcher_timer,
         0,
         0,
         dispatcher_interval,
         dispatcher_command,
         timer_flag.ActiveWhenClosed,
         ""
      )
   elseif status ~= error_code.eOK then
      timer_error("Inspecting the async dispatcher timer", status)
   end

   if status ~= error_code.eOK then
      timer_error("Creating the async dispatcher timer", status)
   end

   status = SetTimerOption(dispatcher_timer, "send", dispatcher_command)
   if status ~= error_code.eOK then
      timer_error("Configuring the async dispatcher command", status)
   end

   status = SetTimerOption(dispatcher_timer, "send_to", tostring(sendto.script))
   if status ~= error_code.eOK then
      timer_error("Configuring the async dispatcher destination", status)
   end

   status = EnableTimer(dispatcher_timer, true)
   if status ~= error_code.eOK then
      timer_error("Enabling the async dispatcher timer", status)
   end
end

local function disable_dispatcher()
   local status = EnableTimer(dispatcher_timer, false)
   if status ~= error_code.eOK then
      timer_error("Disabling the async dispatcher timer", status)
   end
end

-- Use doAsyncRemoteRequest to make generic asynchronous requests.
-- Use HEAD to retrieve just file header information.

-- result_callback_function gets arguments (retval, page, status, headers, full_status, requested_url, request_body)
-- You can set result_callback_function to nil (or the print function) if you just want to print everything that comes back to the screen.
-- callback_on_timeout function gets arguments (requested_url, timeout_after, request_body)
-- request_protocol is HTTP or HTTPS (if not provided, it will be inferred from the request_url)
-- timeout_after is in seconds
-- request_body is either nil, a string (which will switch the HTTP method to POST instead of the default GET), or a table of HTTP request parameters such as source/method/headers.
-- See http://w3.impa.br/~diego/software/luasocket/http.html for more details on the request_body table, but with the caveat that body.source needs to be a string of data and body.sink needs to be a string (writes to file) or nothing (returns the body).
-- This is because any data sent to the background thread needs to be serializable, and the ltn12.source and ltn12.sink objects are not.
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

   result_callback_function = result_callback_function or print

   local thread_id = tostring(GetUniqueNumber())

   assert(type(request_url) == "string")
   assert(request_protocol == "HTTP" or request_protocol == "HTTPS")
   assert(type(timeout_after) == "number")
   assert(type(result_callback_function) == "function" or type(result_callback_function) == "string")
   assert(type(callback_on_timeout) == "function" or type(callback_on_timeout) == "string" or callback_on_timeout == nil)

   local result_callback = result_callback_function
   if type(result_callback) == "string" then
      result_callback = loadstring(result_callback)
   end

   local timeout_callback = callback_on_timeout
   if type(timeout_callback) == "string" then
      timeout_callback = loadstring(timeout_callback)
   end

   enable_dispatcher()

   requests[thread_id] = {
      url = request_url,
      body = request_body,
      timeout = timeout_after,
      started_at = os.time(),
      thread = request(request_url, request_protocol, request_body, timeout_after),
      result_callback = result_callback,
      timeout_callback = timeout_callback,
      timed_out = false,
   }
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
   local _http = require("socket.http")
   -- Bound an inactive socket operation with the request timeout.
   _http.TIMEOUT = args.timeout or _http.TIMEOUT

   local _socketeer = nil
   if args.protocol == "HTTPS" then
      _socketeer = require("ssl.https")
   elseif args.protocol == "HTTP" then
      _socketeer = _http
   else
      return false
   end

   local body = args["body"]
   local page, status, headers, full_status
   local result_table = {}

   if type(body) == "table" then
      _ltn12 = require "ltn12"

      body.url = args.url

      if type(body.sink) == "string" then  -- write to file named as the string
         body.sink = _ltn12.sink.file(io.open(body.sink, "wb"))
      else
         body.sink = _ltn12.sink.table(result_table)
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

   return next(result_table) and table.concat(result_table) or page, status, headers, full_status
end)

-- makes an asynchronous HTTP or HTTPS request to a URL
function request(url, protocol, body, timeout)
   local thread = _llthreads.new(network_thread_code, {
      url = url,
      protocol = protocol,
      body = body,
      timeout = timeout,
   })
   thread:start()
   return thread
end

-- This named, non-temporary timer is not removed by DeleteTemporaryTimers().
-- One dispatcher services every request in this plugin or world script state.
function __pollRequests()
   local now = os.time()
   local thread_ids = {}

   -- Callbacks can start requests, so poll a stable list of IDs.
   for thread_id in pairs(requests) do
      thread_ids[#thread_ids + 1] = thread_id
   end

   for _, thread_id in ipairs(thread_ids) do
      local request_data = requests[thread_id]
      if request_data then
         if request_data.thread:alive() then
            if not request_data.timed_out and
               now - request_data.started_at > request_data.timeout then
               local timeout_callback = request_data.timeout_callback
               local request_url = request_data.url
               local timeout = request_data.timeout
               local request_body = request_data.body

               request_data.timed_out = true
               request_data.url = nil
               request_data.body = nil
               request_data.result_callback = nil
               request_data.timeout_callback = nil

               if timeout_callback ~= nil then
                  timeout_callback(request_url, timeout, request_body)
               else
                  default_timeout_callback(request_url, timeout, request_body)
               end
            end
         else
            local retval, page, status, headers, full_status = request_data.thread:join()
            local callback_func = request_data.result_callback
            local timeout_callback = request_data.timeout_callback
            local request_url = request_data.url
            local request_body = request_data.body
            local timeout = request_data.timeout
            -- Route the socket inactivity timeout through request timeout handling.
            local network_timed_out = status == "timeout"
            local deliver_timeout = not request_data.timed_out and network_timed_out
            local deliver_result = not request_data.timed_out and not network_timed_out

            -- Release all library references before calling user code. A callback
            -- error must not retain a completed request.
            requests[thread_id] = nil

            if deliver_timeout then
               if timeout_callback ~= nil then
                  timeout_callback(request_url, timeout, request_body)
               else
                  default_timeout_callback(request_url, timeout, request_body)
               end
            elseif deliver_result then
               callback_func(retval, page, status, headers, full_status, request_url, request_body)
            end
         end
      end
   end

   if next(requests) == nil then
      disable_dispatcher()
   end
end
