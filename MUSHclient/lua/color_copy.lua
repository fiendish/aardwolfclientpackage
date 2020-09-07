-- Amended slightly by Nick Gammon, from Worstje's version, on 17 Feb 2008
-- Thank you, Shaun Biggs, for taking your time to write the
-- (formerly Copy2) function below. It was slightly altered by me to suit
-- my usage (wordwrapped lines and no \r\n at start of selection). -- Nick Gammon

-- And then I ripped out its heart in a complete refactor. -- Fiendish

-- functions for handling Aardwolf color codes
dofile (GetPluginInfo(GetPluginID(), 20).."aardwolf_colors.lua")

function get_selection_with_color()
   -- find selection in output window, if any
   local first_line, last_line = GetSelectionStartLine(),
                     math.min (GetSelectionEndLine(), GetLinesInBufferCount())
   local first_column, last_column = GetSelectionStartColumn(), GetSelectionEndColumn()

   -- nothing selected, do normal copy
   if first_line <= 0 then
      return nil
   end -- if nothing to copy from output window

   local cpstr = ""

   -- iterate to build up copy text
   for line = first_line, last_line do
      if line < last_line then
         cpstr = cpstr..StylesToColours(TruncateStyles(GetStyleInfo(line), first_column, GetLineInfo(line).length))
         first_column = 1

         -- Is this a new line or merely the continuation of a paragraph?
         if GetLineInfo(line, 3) then
            cpstr = cpstr.."\r\n"
         end  -- new line
      else
         cpstr = cpstr..StylesToColours(TruncateStyles(GetStyleInfo(line), first_column, last_column-1))
      end -- if
   end  -- for loop

   -- Get rid of a spurious extra new line at the start.
   if cpstr:sub(1, 2) == "\r\n" then
      cpstr = cpstr:sub (3)
   end
   return cpstr
end
