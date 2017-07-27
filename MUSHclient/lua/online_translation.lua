-----------------------------------------------------------------
-- Internet-based translation for MUSHclient using the unofficial Google translation API
-- Author: Avi 'fiendish' Kelman
--
-----------------------------------------------------------------
-- Usage
-----------------------------------------------------------------
-- This file goes in MUSHclient\lua\
-- Then you can:
-- (require "online_translation")(src_text, source_language, target_language, function_to_call_with_result)
--
-- source_language and target_language are two letter language codes
-- see https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
-- source_language can also be 'auto'
-- source_language nil defaults to 'auto'
-- target_language nil defaults to 'en'
-- function_to_call_with_result receives two arguments: original text, translated text
--
-----------------------------------------------------------------
-- Examples
-----------------------------------------------------------------
--[[
(require "online_translation")("I like cheese.", "en", "fr")

local translate = require "online_translation"
translate("Je m'appelle Fiendish.", "auto", "en")

function send_to_gt(original, translated)
   Execute("gt \""..original.."\" ---- translates to ---> \""..translated.."\"")
end

translate("I like cheese.", "en", "fr", send_to_gt)
translate("I like Aardwolf.", "en", "es", function(original, result) print(original.." (english) translates to (spanish) "..result) end)
--]]
-----------------------------------------------------------------
-- Code Begins Here
-----------------------------------------------------------------

local async = require "async"
local url = require "socket.url"
local json = require "json"

local __requests = {}

local function __pretty_print(original, translated)
   print("\""..original.."\" ---- translates to ---> \""..translated.."\"")
end

-- Google's unofficial translate api returns pseudo-JSON with empty array entries.
-- It breaks the parser, so we have to fix it.
-- You cannot just blindly replace ",," because any string could have ,, in it.
local function __fix_missing_JSON_array_entries(json)
   local new_json = json:gsub("([^\\][\"%]%d]),,", "%1,\0,")
   while new_json ~= json do
      json = new_json
      new_json = json:gsub("%z,,","\0,\0,")
   end
   json = json:gsub("%z","null")
   return json
end

local function __timeout(requested_url, timeout_after)
   -- Someone poking through the code might be wondering here why this
   -- clears _all_ requests for the url on _any_ timeout, when we go to the
   -- effort to make sure that multiple simultaneous requests can be made for the same
   -- translation. The answer is because 1) timeouts to googleapis should be rare,
   -- 2) that was low hanging fruit, 3) I'm lazy, and 4) wtf stop requesting
   -- the same translation over and over you fool.
   __requests[requested_url] = nil
   print("Translate timed out requesting: "..requested_url)
end

local function __parse_response(retval, page, status, headers, full_status, requested_url)
   local succ,t = pcall(json.decode, __fix_missing_JSON_array_entries(page))
   if (not succ) or (type(t) ~= "table") then
      print("Invalid response from translation service for request "..requested_url)
      print("Maybe try again later, or visit the page in a web browser to see if you receive valid JSON back.")
      return
   end

   local message = t[1][1]
   local translated = message[1]
   local original = message[2]

   local callback = __pretty_print -- default
   if __requests[requested_url] and #__requests[requested_url] > 0 then
      callback = table.remove(__requests[requested_url], 1)
   end

   callback(original, translated)

   if __requests[requested_url] and #__requests[requested_url] == 0 then
      __requests[requested_url] = nil
   end
end

local function __online_translation(src_text, source_language, target_language, function_to_call_with_result)
  local source_language = source_language or 'auto'
  local target_language = target_language or 'en'

  local request_url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl="
            ..source_language.."&tl="..target_language.."&dt=t&q="..url.escape(src_text)

  if __requests[request_url] == nil then
     __requests[request_url] = {}
  end
  table.insert(__requests[request_url], function_to_call_with_result)

  async.doAsyncRemoteRequest(request_url, __parse_response, 'HTTPS', 10, __timeout)
end

return __online_translation
