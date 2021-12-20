require "gmcphelper"
dofile(GetInfo(60).."telnet_options.lua")

module ("Capture", package.seeall)

___storage = {}

function ___capture_body(name, line, wildcards, styles)
   local i = name:sub(28)
   local thing = ___storage[i]
   table.insert(thing["captured_lines"], styles)
end

function ___capture_end(name, line, wildcards, styles)
   local i = name:sub(27)
   ___storage[i]["callback"](
      ___storage[i]["captured_lines"], ___storage[i]["start_line"], line
   )
end

function ___create_capture(i, start_line)
   local omit = ___storage[i]["omit"]
   local end_tag = ___storage[i]["end_tag"]
   local regexp = ___storage[i]["regexp"]
   ___storage[i]["start_line"] = start_line
   ___storage[i]["captured_lines"] = {}
   AddTriggerEx(
      "tag_captures_module___body_"..i,
      ".*",
      "StopEvaluatingTriggers(true)",
      trigger_flag.RegularExpression + (omit and trigger_flag.OmitFromLog or 0) + (omit and trigger_flag.OmitFromOutput or 0) + trigger_flag.Temporary + trigger_flag.Enabled,
      -1, 0, "", "Capture.___capture_body", sendto.script, ___storage[i]["sequence_high"]
   )
   AddTriggerEx(
      "tag_captures_module___end_"..i,
      end_tag,
      "DeleteTrigger('tag_captures_module___body_"..i.."');StopEvaluatingTriggers(true)",
      (regexp and trigger_flag.RegularExpression or 0) + trigger_flag.OmitFromLog + trigger_flag.OmitFromOutput + trigger_flag.Temporary + trigger_flag.OneShot + trigger_flag.Enabled,
      -1, 0, "", "Capture.___capture_end", sendto.script, ___storage[i]["sequence_low"]
   )
end

function ___add_squelch_triggers(i)
   AddTriggerEx(
      "tag_captures_module___squelch"..i,
      "^$",
      "DeleteTrigger('tag_captures_module___nosquelch"..i.."');StopEvaluatingTriggers(true)",
      trigger_flag.RegularExpression + trigger_flag.OmitFromLog + trigger_flag.OmitFromOutput + trigger_flag.Temporary + trigger_flag.Enabled + trigger_flag.OneShot,
      -1, 0, "", "", sendto.script, ___storage[i]["sequence_high"]
   )
   AddTriggerEx(
      "tag_captures_module___nosquelch"..i,
      ".+",
      "DeleteTrigger('tag_captures_module___squelch"..i.."')",
      trigger_flag.KeepEvaluating + trigger_flag.RegularExpression + trigger_flag.Temporary + trigger_flag.Enabled + trigger_flag.OneShot,
      -1, 0, "", "", sendto.script, 0
   )
end

function ___terminate(i)
   DeleteTrigger("tag_captures_module___start_"..i)
   DeleteTrigger("tag_captures_module___body_"..i)
   DeleteTrigger("tag_captures_module___end_"..i)
   ___storage[i] = nil

   -- if storage is empty, reset the sequence numbers
   for k,v in pairs(___storage) do
      return
   end
   ___sequence = 1
end

___sequence = 1

function contents(start_tag, end_tag, regexp, omit, call_with_result, one_shot)
   local i = tostring(___sequence)
   ___storage[i] = {
      ["i"] = i,
      ["sequence_low"] = ___sequence,
      ["sequence_high"] = ___sequence + 5000,
      ["omit"] = omit,
      ["callback"] = call_with_result,
      ["end_tag"] = end_tag,
      ["regexp"] = regexp
   }

   local flags = trigger_flag.OmitFromLog + trigger_flag.OmitFromOutput + trigger_flag.Temporary + trigger_flag.Enabled
   AddTriggerEx(
      "tag_captures_module___start_"..i,
      start_tag,
      "Capture.___create_capture('"..i.."', '%0');StopEvaluatingTriggers(true)",
      flags + (one_shot and trigger_flag.OneShot or 0) + (regexp and trigger_flag.RegularExpression or 0),
      -1, 0, "", "", sendto.script, ___storage[i]["sequence_low"]
   )
   ___sequence = (___sequence + 1) % 5000
   return i
end


function command(command_to_send, capture_start_tag, capture_end_tag, regexp, silent, omit, no_prompt_after, call_with_result)
   compact_mode = gmcp("config.compact")
   prompt_mode = gmcp("config.prompt")

   local i = contents(
      capture_start_tag, capture_end_tag, regexp, omit, call_with_result, true
   )

   TelnetOptionOff(TELOPT_PAGING)
   if compact_mode == "NO" then
      ___add_squelch_triggers(i)
      Send_GMCP_Packet("config compact YES")
   end
   if prompt_mode == "YES" then
      Send_GMCP_Packet("config prompt NO")
   end

   if silent then
      SendNoEcho(command_to_send)
   else
      Send(command_to_send)
   end

   if compact_mode == "NO" then
      Send_GMCP_Packet("config compact NO")
   end
   if prompt_mode == "YES" then
      Send_GMCP_Packet("config prompt YES")
   end

   if not no_prompt_after then
      SendNoEcho("")
   end

   TelnetOptionOn(TELOPT_PAGING)
end
