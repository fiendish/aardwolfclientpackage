require "gmcphelper"
require "gag_next_blank_line"
dofile(GetInfo(60).."telnet_options.lua")

module ("Capture", package.seeall)

-- The Capture module provides functions for capturing arbitrary command output from the game.
-- The tagged_output function is used to capture text that is reliably enclosed by recognizeable text.
-- The untagged_output function is used to capture text that is not reliably enclosed by recognizeable text.

function tagged_output(
   command_to_send,            -- The command to send to the game.
   capture_start_tag,          -- The opening tag that marks the start of the text to be captured.
   capture_end_tag,            -- The closing tag that marks the end of the text to be captured.
   tags_are_regexp,            -- A boolean indicating whether the tags are regular expressions (default is false).
   no_command_echo,            -- A boolean indicating whether the command should be echoed to the screen (true means omit, false/nil means show).
   omit_response_from_output,  -- A boolean indicating whether the response to the command should be shown in the output window (true means omit, false/nil means show).
   no_prompt_after,            -- A boolean indicating whether the prompt should be displayed after the command is done (true means no prompt, false/nil means yes prompt).
   callback_function,          -- A function to be called when the captured text has been obtained which should take three arguments: captured_styles, start_line, and end_line.
                               --    captured_styles are the output style lines that were captured
                               --    start_line is the text of the line with the start tag
                               --    end_line is the text of the line with the end tag
   send_via_execute,           -- A boolean indicating whether the command should be sent via Execute instead of Send (true means use Execute, false/nil means use Send).
   timeout_callback            -- A function to be called if the capture times out.
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

function untagged_output(
   command_to_send,            -- The command to send to the game.
   no_command_echo,            -- A boolean indicating whether the command should be echoed to the screen (true means omit, false/nil means show).
   omit_response_from_output,  -- A boolean indicating whether the response to the command should be shown in the output window (true means omit, false/nil means show).
   no_prompt_after,            -- A boolean indicating whether the prompt should be displayed after the command is done (true means no prompt, false/nil means yes prompt).
   callback_function,          -- A function to be called when the captured text has been obtained which should take three arguments: captured_styles, start_line, and end_line.
                               --    captured_styles are the output style lines that were captured
                               --    start_line is the text of the line with the start tag
                               --    end_line is the text of the line with the end tag
   send_via_execute,           -- A boolean indicating whether the command should be sent via Execute instead of Send (true means use Execute, false/nil means use Send).
   timeout_callback            -- A function to be called if the capture times out.
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


--- Ignore everything below here


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
   DeleteTrigger("tag_captures_module___immortal_start_"..i)
   DeleteTrigger("tag_captures_module___immortal_end_"..i)
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
   local i = tostring(___sequence)

   local compact_mode = gmcp("config.compact")
   local prompt_mode = gmcp("config.prompt")

   -- immortal echo works a little differently than normal player echo
   local my_level = tonumber(gmcp("char.base.level")) or 0
   local echo_command = "echo "
   local echo_prefix = ""
   if manual_tags and my_level >= 202 then
      local my_name = gmcp("char.base.name")
      echo_command = "echo self "
      echo_prefix = my_name.." echo> "
      AddTriggerEx(
         "tag_captures_module___immortal_start_"..i,
         "You echo "..capture_start_tag.." to "..my_name..".",
         "StopEvaluatingTriggers(true)",
         trigger_flag.OmitFromLog + trigger_flag.OmitFromOutput + trigger_flag.Temporary + trigger_flag.Enabled + trigger_flag.OneShot,
         -1, 0, "", "", sendto.script, ___sequence
      )
      AddTriggerEx(
         "tag_captures_module___immortal_end_"..i,
         "You echo "..capture_end_tag.." to "..my_name..".",
         "StopEvaluatingTriggers(true)",
         trigger_flag.OmitFromLog + trigger_flag.OmitFromOutput + trigger_flag.Temporary + trigger_flag.Enabled + trigger_flag.OneShot,
         -1, 0, "", "", sendto.script, ___sequence
      )
   end

   -- store the details
   ___storage[i] = {
      ["i"] = i,
      ["sequence_low"] = ___sequence,
      ["sequence_high"] = ___sequence + 5000,
      ["omit_response_from_output"] = omit_response_from_output,
      ["callback"] = callback_function,
      ["end_tag"] = echo_prefix..capture_end_tag,
      ["tags_are_regexp"] = tags_are_regexp,
      ["timeout_callback"] = timeout_callback
   }

   -- start trigger
   AddTriggerEx(
      "tag_captures_module___start_"..i,
      echo_prefix..capture_start_tag,
      "Capture.___create_capture('"..i.."', '%0');StopEvaluatingTriggers(true)",
      trigger_flag.OmitFromLog + trigger_flag.OmitFromOutput + trigger_flag.Temporary + trigger_flag.Enabled + trigger_flag.OneShot + (tags_are_regexp and trigger_flag.RegularExpression or 0),
      -1, 0, "", "", sendto.script, ___storage[i]["sequence_low"]
   )

   ___sequence = (___sequence + 1) % 5000

   -- toggle flags and send the commands
   TelnetOptionOff(TELOPT_PAGING)
   if compact_mode == "NO" then
      GagBlankLine(i, ___storage[i]["sequence_high"])
      Send_GMCP_Packet("config compact YES")
   end
   if prompt_mode == "YES" then
      Send_GMCP_Packet("config prompt NO")
   end

   if manual_tags then
      SendNoEcho(echo_command..capture_start_tag)
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
      SendNoEcho(echo_command..capture_end_tag)
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
