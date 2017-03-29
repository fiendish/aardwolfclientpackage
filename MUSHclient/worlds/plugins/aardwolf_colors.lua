local BLACK = 1
local RED = 2
local GREEN = 3
local YELLOW = 4
local BLUE = 5
local MAGENTA = 6
local CYAN = 7
local WHITE = 8

local atletter_to_ansi_digit = {
   r = 31,
   g = 32,
   y = 33,
   b = 34,
   m = 35,
   c = 36,
   w = 37,
   D = 30,
   R = 31,
   G = 32,
   Y = 33,
   B = 34,
   M = 35,
   C = 36,
   W = 37
}

local function init_ansi()
   -- declaration of produced tables
   color_value_to_atcode = {}
   atletter_to_color_value = {}
   color_value_to_xterm_number = {}
   xterm_number_to_color_value = extended_colours
   basic_colors_to_atletters = {}

   for i,v in ipairs(xterm_number_to_color_value) do
      color_value_to_xterm_number[v] = i
   end

   -- The start of this table uses the colours as defined in the MUSHclient ANSI settings
   -- for visual clarity over xterm numbers, with the defaults shown on the right.
   atletter_to_color_value = {
      k = GetNormalColour (BLACK)   ,   -- 0x000000 (not used)
      r = GetNormalColour (RED)     ,   -- 0x000080
      g = GetNormalColour (GREEN)   ,   -- 0x008000
      y = GetNormalColour (YELLOW)  ,   -- 0x008080
      b = GetNormalColour (BLUE)    ,   -- 0x800000
      m = GetNormalColour (MAGENTA) ,   -- 0x800080
      c = GetNormalColour (CYAN)    ,   -- 0x808000
      w = GetNormalColour (WHITE)   ,   -- 0xC0C0C0
      D = GetBoldColour   (BLACK)   ,   -- 0x808080
      R = GetBoldColour   (RED)     ,   -- 0x0000FF
      G = GetBoldColour   (GREEN)   ,   -- 0x00FF00
      Y = GetBoldColour   (YELLOW)  ,   -- 0x00FFFF
      B = GetBoldColour   (BLUE)    ,   -- 0xFF0000
      M = GetBoldColour   (MAGENTA) ,   -- 0xFF00FF
      C = GetBoldColour   (CYAN)    ,   -- 0xFFFF00
      W = GetBoldColour   (WHITE)   ,   -- 0xFFFFFF
   }

   for k,v in pairs(atletter_to_color_value) do
      basic_colors_to_atletters[v] = k
   end

   bold_colors_to_atcodes = {
      [GetBoldColour(BLACK)]   = "@D",
      [GetBoldColour(RED)]     = "@R",
      [GetBoldColour(GREEN)]   = "@G",
      [GetBoldColour(YELLOW)]  = "@Y",
      [GetBoldColour(BLUE)]    = "@B",
      [GetBoldColour(MAGENTA)] = "@M",
      [GetBoldColour(CYAN)]    = "@C",
      [GetBoldColour(WHITE)]   = "@W"
   }

   -- Set up xterm color conversions using the xterm_number_to_color_value global array
   for i = 0,255 do
      local xterm_colour = xterm_number_to_color_value[i]
      if not color_value_to_atcode[xterm_colour] then
         color_value_to_atcode[xterm_colour] = string.format("@x%03d",i)
      end
      atletter_to_color_value[string.format("x%03d",i)] = xterm_colour
      atletter_to_color_value[string.format("x%02d",i)] = xterm_colour
      atletter_to_color_value[string.format("x%d",i)] = xterm_colour
   end

   -- Aardwolf bumps a few very dark xterm colors to brighter values to improve visibility.
   -- This seems like a good idea.
   for i = 232,237 do
      atletter_to_color_value[string.format("x%d",i)] = xterm_number_to_color_value[238]
   end
   for i = 17,19 do
      atletter_to_color_value[string.format("x%03d",i)] = xterm_number_to_color_value[19]
      atletter_to_color_value[string.format("x%d",i)] = xterm_number_to_color_value[19]
   end
end

init_ansi()


function StylesToColours(styles, dollarC_resets)
   local reinit = true
   local copystring = ""
   local lastcode = ""
   for i,style in ipairs(styles) do
      -- fixup string: change @ to @@
      local text = string.gsub(style.text, "@", "@@")
      local code = color_value_to_atcode[style.textcolour]
      if code then
         if style.bold or (style.style and ((style.style % 2) == 1)) then
            if bold_colors_to_atcodes[style.textcolour] then
               code = bold_colors_to_atcodes[style.textcolour]
            elseif reinit then -- set up basic color table again, but only once per run
               reinit = false
               init_ansi()
            end
         end

         if dollarC_resets then
            text = text:gsub("%$C", code)
         end
         copystring = copystring..code..text
         lastcode = code
      else
         if dollarC_resets then
            text = text:gsub("%$C", lastcode)
         end
         copystring = copystring..text
      end
   end
   return copystring
end


require "copytable"
function TruncateStyles(styles, startcol, endcol)
   if not styles or #styles == 0 then
      return ""
   end

   local startcol = startcol or 1
   local endcol = endcol or 99999 -- 99999 is assumed to be long enough to cover ANY style run

   -- negative column indices are used to measure back from the end
   if startcol < 0 or endcol < 0 then
      local total_chars = 0
      for k,v in ipairs(styles) do
         total_chars = total_chars + v.length
      end
      if startcol < 0 then
         startcol = total_chars + startcol + 1
      end
      if endcol < 0 then
         endcol = total_chars + endcol + 1
      end
   end

   -- start/end order does not matter
   if startcol > endcol then
      startcol, endcol = endcol, startcol
   end

   -- Trim to start and end positions in styles
   local first_style = 0 -- not 1 because we check for foundness
   local col_counter = 0
   local new_styles = {}
   local break_after = false
   for k,v in ipairs(styles) do
      local new_style = copytable.shallow(v)
      col_counter = col_counter + new_style.length
      if endcol <= col_counter then
         new_style.text = new_style.text:sub(1, endcol - (col_counter - v.length))
         new_style.length = #(new_style.text)
         break_after = true
      end
      if startcol <= col_counter then
         if first_style == 0 then
            first_style = k
            new_style.text = new_style.text:sub(startcol - (col_counter - v.length))
            new_style.length = #(new_style.text)
         end
         table.insert(new_styles, new_style)
      end
      if break_after then break end
   end

   return new_styles
end


-- Deprecated historical function without purpose. Use StylesToColours.
-- Use TruncateStyles if you must, but that seems to be pretty uncommon.
--
-- Convert a partial line of style runs into color codes.
-- Yes the "OneLine" part of the function name is meaningless. It stays that way for historical compatibility.
-- Think of it instead as TruncatedStylesToColours
-- The caller may optionally choose to start and stop at arbitrary character indices.
-- Negative indices are measured backward from the end.
-- The order of start and end columns does not matter, since the start will always be lower than the end.
function StylesToColoursOneLine (styles, startcol, endcol)
   if startcol or endcol then
      return StylesToColours( TruncateStyles(styles, startcol, endcol) )
   else
      return StylesToColours( styles )
   end
end -- StylesToColoursOneLine


-- Converts text with colour codes in it into style runs
function ColoursToStyles (Text, default_foreground_code, default_background_code)
   if default_foreground_code and atletter_to_color_value[default_foreground_code] then
      default_foreground = atletter_to_color_value[default_foreground_code]
      default_foreground_code = "@"..default_foreground_code
   else
      default_foreground = GetNormalColour(WHITE)
      default_foreground_code = "@w"
   end
   if default_background_code and atletter_to_color_value[default_background_code] then
      default_background = atletter_to_color_value[default_background_code]
   else
      default_background = GetNormalColour(BLACK)
   end

   if Text:find("@", nil, true) then
      astyles = {}

      -- make sure we start with a color
      if Text:sub(1, 1) ~= "@" then
         Text = default_foreground_code .. Text
      end -- if

      Text = Text:gsub ("@@", "\0") -- change @@ to 0x00
      Text = Text:gsub ("@%-", "~") -- fix tildes (historical)
      Text = Text:gsub ("@x([^%d])","%1") -- strip invalid xterm codes (non-number)
      Text = Text:gsub ("@x[3-9]%d%d","") -- strip invalid xterm codes (300+)
      Text = Text:gsub ("@x2[6-9]%d","") -- strip invalid xterm codes (260+)
      Text = Text:gsub ("@x25[6-9]","") -- strip invalid xterm codes (256+)
      Text = Text:gsub ("@[^xrgybmcwDRGYBMCWd]", "")  -- strip hidden garbage

      for colour, text in Text:gmatch ("@(%a)([^@]+)") do
         text = text:gsub ("%z", "@") -- put any @ characters back

         if colour == "x" then -- xterm 256 colors
            code,text = text:match("(%d%d?%d?)(.*)")
            colour = colour..code
         end

         if #text > 0 then
            table.insert (astyles, { text = text,
               bold = (colour == colour:upper()),
               length = #text,
               textcolour = atletter_to_color_value[colour] or default_foreground,
               backcolour = default_background })
         end -- if some text
      end -- for each colour run.

      return astyles
   end -- if any colour codes at all

   -- No colour codes, create a single style.
   return { { text = Text,
      bold = (default_foreground_code == default_foreground_code:upper()),
      length = #Text,
      textcolour = default_foreground,
      backcolour = default_background } }
end  -- function ColoursToStyles


-- Strip all color codes from a string
function strip_colours (s)
   s = s:gsub ("@@", "\0")  -- change @@ to 0x00
   s = s:gsub ("@%-", "~")    -- fix tildes (historical)
   s = s:gsub ("@x%d?%d?%d?", "") -- strip valid and invalid xterm color codes
   s = s:gsub ("@.([^@]*)", "%1") -- strip normal color codes and hidden garbage
   return (s:gsub ("%z", "@")) -- put @ back
end -- strip_colours


-- Convert Aardwolf and short x codes to 3 digit x codes
function canonicalize_colours (s)
   if s:find("@", nil, true) then
      s = s:gsub ("@x(%d%d?%d?)", function(a)
         local b = tonumber(a)
         if b and b <= 255 and b >= 0 then
            return string.format("@x%03d", b)
         else
            return ""
         end
      end)
      s = s:gsub ("@([^x])", function(a)
         if atletter_to_color_value[a] then
            return color_value_to_atcode[atletter_to_color_value[a]]
         end
      end)
   end
   return s
end


-- Strip all color codes from a table of styles
function strip_colours_from_styles(styles)
   local ret = {}
   for i,v in ipairs(styles) do
      table.insert(ret, v.text)
   end
   return table.concat(ret)
end


-- Returns a string with embedded ansi codes.
-- This can get confused if the player has redefined their color chart.
function stylesToANSI(styles, dollarC_resets)
   local line = {}
   local reinit = true
   local lastcode = ""
   for _,v in ipairs (styles) do
      local code = ""
      if v.textcolour then
         if basic_colors_to_atletters[v.textcolour] then
            local a = basic_colors_to_atletters[v.textcolour]
            if a == string.upper(a) then
               code = ANSI(1,atletter_to_ansi_digit[a])
            else
               code = ANSI(0,atletter_to_ansi_digit[a])
            end
         elseif color_value_to_xterm_number[v.textcolour] then
            local isbold = (v.bold or (v.style and ((v.style % 2) == 1)))
            code = ANSI(isbold and 1 or 0,38,5,color_value_to_xterm_number[v.textcolour])
         elseif reinit then -- set up again, but limit performance damage
            reinit = false
            init_ansi()
         end
      end
      if code ~= "" then
         table.insert(line, code)
         lastcode = code
      end
      if dollarC_resets then
         v.text = v.text:gsub("%$C", lastcode)
      end
      table.insert(line, (v.text))
   end
   return table.concat(line)
end

-- Aardwolf bold colors
local ansi_digit_to_bold_atcode = {
   [30] = "@D",
   [31] = "@R",
   [32] = "@G",
   [33] = "@Y",
   [34] = "@B",
   [35] = "@M",
   [36] = "@C",
   [37] = "@W"
}

-- Tries to convert ANSI sequences to Aardwolf color codes
function AnsiToColours(ansi, default_foreground_code)
   if not default_foreground_code then
      default_foreground_code = "@w"
   end

   local ansi_capture = "\027%[([%d;]+)m"

   -- this stuff goes outside because ANSI is a state machine (lolsigh)
   local bold = false
   local color = ""
   local xstage = 0

   ansi = ansi:gsub("@","@@"):gsub(ansi_capture, function(a)
      for c in a:gmatch("%d+") do
         local nc = tonumber(c)
         if nc == 38 then
            xstage = 1
         elseif nc == 5 and xstage == 1 then
            xstage = 2
         elseif xstage == 2 then -- xterm 256 color
            if bold and ansi_digit_to_bold_atcode[nc+30] then
               color = ansi_digit_to_bold_atcode[nc+30]
            else
               color = string.format("@x%03d", nc)
            end
            xstage = 0
         elseif nc == 1 then
            bold = true
            xstage = 0
         elseif nc == 0 then
            bold = false
            -- not actually sure if we should set color here or not
            color = default_foreground_code
         elseif nc <= 37 and nc >= 30 then -- regular color
            if bold and ansi_digit_to_bold_atcode[nc] then
               color = ansi_digit_to_bold_atcode[nc]
            else
               color = string.format("@x%03d", nc-30)
            end
            xstage = 0
         end
      end
      return color
   end)

   return ansi
end

function ColoursToANSI(text)
   -- return stylesToANSI(ColoursToStyles(text))
   if text:find("@", nil, true) then
      text = text:gsub ("@@", "\0") -- change @@ to 0x00
      text = text:gsub ("@%-", "~") -- fix tildes (historical)
      text = text:gsub ("@x([^%d])","%1") -- strip invalid xterm codes (non-number)
      text = text:gsub ("@x[3-9]%d%d","") -- strip invalid xterm codes (300+)
      text = text:gsub ("@x2[6-9]%d","") -- strip invalid xterm codes (260+)
      text = text:gsub ("@x25[6-9]","") -- strip invalid xterm codes (256+)
      text = text:gsub ("@[^xrgybmcwDRGYBMCWd]", "")  -- strip hidden garbage

      text = text:gsub ("@x(%d%d?%d?)", function(a) return ANSI(0,38,5,a) end)
      text = text:gsub ("@([DRGYBMCW])", function(a)
         return ANSI(1,atletter_to_ansi_digit[a])
      end)
      text = text:gsub ("@([rgybmcw])", function(a)
         return ANSI(0,atletter_to_ansi_digit[a])
      end)

      text = text:gsub("%z", "@")
   end
   return text
end




-- OLD.
colour_conversion = {
   k = GetNormalColour (BLACK)   ,   -- 0x000000
   r = GetNormalColour (RED)     ,   -- 0x000080
   g = GetNormalColour (GREEN)   ,   -- 0x008000
   y = GetNormalColour (YELLOW)  ,   -- 0x008080
   b = GetNormalColour (BLUE)    ,   -- 0x800000
   m = GetNormalColour (MAGENTA) ,   -- 0x800080
   c = GetNormalColour (CYAN)    ,   -- 0x808000
   w = GetNormalColour (WHITE)   ,   -- 0xC0C0C0
   K = GetBoldColour   (BLACK)   ,   -- 0x808080
   R = GetBoldColour   (RED)     ,   -- 0x0000FF
   G = GetBoldColour   (GREEN)   ,   -- 0x00FF00
   Y = GetBoldColour   (YELLOW)  ,   -- 0x00FFFF
   B = GetBoldColour   (BLUE)    ,   -- 0xFF0000
   M = GetBoldColour   (MAGENTA) ,   -- 0xFF00FF
   C = GetBoldColour   (CYAN)    ,   -- 0xFFFF00
   W = GetBoldColour   (WHITE)   ,   -- 0xFFFFFF
}  -- end conversion table
