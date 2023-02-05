require "gmcphelper"
require "gag_next_blank_line"
dofile(GetInfo(60).."telnet_options.lua")

module ("Capture", package.seeall)


function ExecuteNoEcho(command)
   local original_echo_setting = GetOption("display_my_input")
   SetOption ("display_my_input", 0)
   Execute(command)
   SetOption ("display_my_input", original_echo_setting)
 end

___storage = {}

function ___capture_body(name, line, wildcards, styles)
   local i = name:sub(28)
   table.insert(___storage[i]["captured_lines"], styles)
end

function ___capture_end(name, line, wildcards, styles)
   local i = name:sub(27)
   ___storage[i]["timeout_callback"] = nil
   ___storage[i]["callback"](
      ___storage[i]["captured_lines"], ___storage[i]["start_line"], line
   )
end

function ___create_capture(i, start_line)
   local omit_response_from_output = ___storage[i]["omit_response_from_output"]
   local end_tag = ___storage[i]["end_tag"]
   local tags_are_regexp = ___storage[i]["tags_are_regexp"]
   ___storage[i]["start_line"] = start_line
   ___storage[i]["captured_lines"] = {}
   AddTriggerEx(
      "tag_captures_module___body_"..i,
      ".*",
      "StopEvaluatingTriggers(true)",
      trigger_flag.RegularExpression + (omit_response_from_output and trigger_flag.OmitFromLog or 0) + (omit_response_from_output and trigger_flag.OmitFromOutput or 0) + trigger_flag.Temporary + trigger_flag.Enabled,
      -1, 0, "", "Capture.___capture_body", sendto.script, ___storage[i]["sequence_high"]
   )
   AddTriggerEx(
      "tag_captures_module___end_"..i,
      end_tag,
      "DeleteTrigger('tag_captures_module___body_"..i.."');StopEvaluatingTriggers(true)",
      (tags_are_regexp and trigger_flag.RegularExpression or 0) + trigger_flag.OmitFromLog + trigger_flag.OmitFromOutput + trigger_flag.Temporary + trigger_flag.OneShot + trigger_flag.Enabled,
      -1, 0, "", "Capture.___capture_end", sendto.script, ___storage[i]["sequence_low"]
   )
end

function ___terminate(i)
   DeleteTrigger("tag_captures_module___start_"..i)
   DeleteTrigger("tag_captures_module___body_"..i)
   DeleteTrigger("tag_captures_module___end_"..i)
   UngagBlankLine(i)
   if ___storage[i] and ___storage[i]["timeout_callback"] then
      ___storage[i]["timeout_callback"]()
   end
   ___storage[i] = nil

   -- if storage is empty, reset the sequence numbers
   for k,v in pairs(___storage) do
      return
   end
   ___sequence = 1
end

___sequence = 1

function ___contents(start_tag, end_tag, tags_are_regexp, omit_response_from_output, callback_function, one_shot, timeout_callback)
   local i = tostring(___sequence)
   ___storage[i] = {
      ["i"] = i,
      ["sequence_low"] = ___sequence,
      ["sequence_high"] = ___sequence + 5000,
      ["omit_response_from_output"] = omit_response_from_output,
      ["callback"] = callback_function,
      ["end_tag"] = end_tag,
      ["tags_are_regexp"] = tags_are_regexp,
      ["timeout_callback"] = timeout_callback
   }

   local flags = trigger_flag.OmitFromLog + trigger_flag.OmitFromOutput + trigger_flag.Temporary + trigger_flag.Enabled
   AddTriggerEx(
      "tag_captures_module___start_"..i,
      start_tag,
      "Capture.___create_capture('"..i.."', '%0');StopEvaluatingTriggers(true)",
      flags + (one_shot and trigger_flag.OneShot or 0) + (tags_are_regexp and trigger_flag.RegularExpression or 0),
      -1, 0, "", "", sendto.script, ___storage[i]["sequence_low"]
   )
   ___sequence = (___sequence + 1) % 5000
   return i
end

function command(
   command_to_send,
   capture_start_tag,
   capture_end_tag,
   tags_are_regexp,
   no_command_echo,
   omit_response_from_output,
   no_prompt_after,
   callback_function,
   send_via_execute,
   manual_tags,
   timeout_callback
)
   local compact_mode = gmcp("config.compact")
   local prompt_mode = gmcp("config.prompt")

   local i = ___contents(
      capture_start_tag, capture_end_tag, tags_are_regexp, omit_response_from_output, callback_function, true, timeout_callback
   )

   TelnetOptionOff(TELOPT_PAGING)
   if compact_mode == "NO" then
      GagBlankLine(i, ___storage[i]["sequence_high"])
      Send_GMCP_Packet("config compact YES")
   end
   if prompt_mode == "YES" then
      Send_GMCP_Packet("config prompt NO")
   end

   if manual_tags then
      SendNoEcho("echo "..capture_start_tag)
   end

   if no_command_echo then
      if send_via_execute then
         ExecuteNoEcho(command_to_send)
      else
         SendNoEcho(command_to_send)
      end
   else
      if send_via_execute then
         Execute(command_to_send)
      else
         Send(command_to_send)
      end
   end

   if manual_tags then
      SendNoEcho("echo "..capture_end_tag)
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
   DoAfterSpecial(20, "Capture.___terminate('"..i.."')", sendto.script)
end


-- Public interfaces

function untagged_output(
   command_to_send,
   no_command_echo,
   omit_response_from_output,
   no_prompt_after,
   callback_function,
   send_via_execute,
   timeout_callback
)
   local sequence = tostring(___sequence)
   local capture_start_tag = "{Begin Capture "..sequence.."}"
   local capture_end_tag = "{End Capture "..sequence.."}"
   local tags_are_regexp = false
   local manual_tags = true

   command(
      command_to_send,
      capture_start_tag,
      capture_end_tag,
      tags_are_regexp,
      no_command_echo,
      omit_response_from_output,
      no_prompt_after,
      callback_function,
      send_via_execute,
      manual_tags,
      timeout_callback
   )
end

function tagged_output(
   command_to_send,
   capture_start_tag,
   capture_end_tag,
   tags_are_regexp,
   no_command_echo,
   omit_response_from_output,
   no_prompt_after,
   callback_function,
   send_via_execute,
   timeout_callback
)
   local manual_tags = false

   command(
      command_to_send,
      capture_start_tag,
      capture_end_tag,
      tags_are_regexp,
      no_command_echo,
      omit_response_from_output,
      no_prompt_after,
      callback_function,
      send_via_execute,
      manual_tags,
      timeout_callback
   )
end

