require "string_split"

local BLACK = 1
local RED = 2
local GREEN = 3
local YELLOW = 4
local BLUE = 5
local MAGENTA = 6
local CYAN = 7
local WHITE = 8

CODE_PREFIX = "@"
PREFIX_ESCAPE = "@@"

XTERM_CHAR = "x"

BLACK_CHAR = "k"
RED_CHAR = "r"
GREEN_CHAR = "g"
YELLOW_CHAR = "y"
BLUE_CHAR = "b"
MAGENTA_CHAR = "m"
CYAN_CHAR = "c"
WHITE_CHAR = "w"

BOLD_BLACK_CHAR = "D"
BOLD_RED_CHAR = "R"
BOLD_GREEN_CHAR = "G"
BOLD_YELLOW_CHAR = "Y"
BOLD_BLUE_CHAR = "B"
BOLD_MAGENTA_CHAR = "M"
BOLD_CYAN_CHAR = "C"
BOLD_WHITE_CHAR = "W"

NORMAL_CHARS = RED_CHAR..GREEN_CHAR..YELLOW_CHAR..BLUE_CHAR..MAGENTA_CHAR..CYAN_CHAR..WHITE_CHAR
BOLD_CHARS = BOLD_BLACK_CHAR..BOLD_RED_CHAR..BOLD_GREEN_CHAR..BOLD_YELLOW_CHAR..BOLD_BLUE_CHAR..BOLD_MAGENTA_CHAR..BOLD_CYAN_CHAR..BOLD_WHITE_CHAR
ALL_CHARS = XTERM_CHAR..NORMAL_CHARS..BOLD_CHARS

XTERM_CODE = CODE_PREFIX..XTERM_CHAR

BLACK_CODE = CODE_PREFIX..BLACK_CHAR
RED_CODE = CODE_PREFIX..RED_CHAR
GREEN_CODE = CODE_PREFIX..GREEN_CHAR
YELLOW_CODE = CODE_PREFIX..YELLOW_CHAR
BLUE_CODE = CODE_PREFIX..BLUE_CHAR
MAGENTA_CODE = CODE_PREFIX..MAGENTA_CHAR
CYAN_CODE = CODE_PREFIX..CYAN_CHAR
WHITE_CODE = CODE_PREFIX..WHITE_CHAR

BOLD_BLACK_CODE = CODE_PREFIX..BOLD_BLACK_CHAR
BOLD_RED_CODE = CODE_PREFIX..BOLD_RED_CHAR
BOLD_GREEN_CODE = CODE_PREFIX..BOLD_GREEN_CHAR
BOLD_YELLOW_CODE = CODE_PREFIX..BOLD_YELLOW_CHAR
BOLD_BLUE_CODE = CODE_PREFIX..BOLD_BLUE_CHAR
BOLD_MAGENTA_CODE = CODE_PREFIX..BOLD_MAGENTA_CHAR
BOLD_CYAN_CODE = CODE_PREFIX..BOLD_CYAN_CHAR
BOLD_WHITE_CODE = CODE_PREFIX..BOLD_WHITE_CHAR

TILDE_PATTERN = CODE_PREFIX.."%-"
X_NONNUMERIC_PATTERN = XTERM_CODE.."([^%d])"
X_THREEHUNDRED_PATTERN = XTERM_CODE.."[3-9]%d%d"
X_TWOSIXTY_PATTERN = XTERM_CODE.."2[6-9]%d"
X_TWOFIFTYSIX_PATTERN = XTERM_CODE.."25[6-9]"
X_DIGITS_CAPTURE_PATTERN = XTERM_CODE.."(%d%d?%d?)"
X_ANY_DIGITS_PATTERN = XTERM_CODE.."%d?%d?%d?"

ALL_CODES_PATTERN = CODE_PREFIX.."."
HIDDEN_GARBAGE_PATTERN = CODE_PREFIX.."[^"..ALL_CHARS.."]"
BOLD_CODES_CAPTURE_PATTERN = "("..CODE_PREFIX.."["..BOLD_CHARS.."])"
NORMAL_CODES_CAPTURE_PATTERN = "("..CODE_PREFIX.."["..NORMAL_CHARS.."])"
NONX_CODES_CAPTURE_PATTERN = "("..CODE_PREFIX.."[^"..XTERM_CHAR.."])"
CODE_REST_CAPTURE_PATTERN = "("..CODE_PREFIX.."%a)([^"..CODE_PREFIX.."]*)"

X3DIGIT_FORMAT = XTERM_CODE.."%03d"
X2DIGIT_FORMAT = XTERM_CODE.."%02d"
X1DIGIT_FORMAT = XTERM_CODE.."%d"


local code_to_ansi_digit = {
   [RED_CODE] = 31,
   [GREEN_CODE] = 32,
   [YELLOW_CODE] = 33,
   [BLUE_CODE] = 34,
   [MAGENTA_CODE] = 35,
   [CYAN_CODE] = 36,
   [WHITE_CODE] = 37,
   [BOLD_BLACK_CODE] = 30,
   [BOLD_RED_CODE] = 31,
   [BOLD_GREEN_CODE] = 32,
   [BOLD_YELLOW_CODE] = 33,
   [BOLD_BLUE_CODE] = 34,
   [BOLD_MAGENTA_CODE] = 35,
   [BOLD_CYAN_CODE] = 36,
   [BOLD_WHITE_CODE] = 37
}

local ansi_digit_to_dim_code = {
   [31] = RED_CODE,
   [32] = GREEN_CODE,
   [33] = YELLOW_CODE,
   [34] = BLUE_CODE,
   [35] = MAGENTA_CODE,
   [36] = CYAN_CODE,
   [37] = WHITE_CODE
}

local ansi_digit_to_bold_code = {
   [30] = BOLD_BLACK_CODE,
   [31] = BOLD_RED_CODE,
   [32] = BOLD_GREEN_CODE,
   [33] = BOLD_YELLOW_CODE,
   [34] = BOLD_BLUE_CODE,
   [35] = BOLD_MAGENTA_CODE,
   [36] = BOLD_CYAN_CODE,
   [37] = BOLD_WHITE_CODE
}

local first_15_to_code = {}
local code_to_xterm = {}
for k,v in pairs(ansi_digit_to_dim_code) do
   first_15_to_code[k-30] = v  -- 1...7
end
for k,v in pairs(ansi_digit_to_bold_code) do
   first_15_to_code[k-22] = v  -- 8...15
end
for k,v in pairs(first_15_to_code) do
   code_to_xterm[v] = string.format(X3DIGIT_FORMAT, k)
end

local is_bold_code = {
   [BOLD_BLACK_CODE]=true, [BOLD_RED_CODE]=true, [BOLD_GREEN_CODE]=true, [BOLD_YELLOW_CODE]=true, [BOLD_BLUE_CODE]=true,
   [BOLD_MAGENTA_CODE]=true, [BOLD_CYAN_CODE]=true, [BOLD_WHITE_CODE]=true
}
for i = 9,15 do
   is_bold_code[string.format(X3DIGIT_FORMAT,i)] = true
   is_bold_code[string.format(X2DIGIT_FORMAT,i)] = true
   is_bold_code[string.format(X1DIGIT_FORMAT,i)] = true
end


local code_to_client_color = {}
local client_color_to_dim_code = {}
local client_color_to_bold_code = {}

local function init_basic_to_color ()
   default_black = GetNormalColour(BLACK)

   code_to_client_color = {
      [RED_CODE] = GetNormalColour(RED),
      [GREEN_CODE] = GetNormalColour(GREEN),
      [YELLOW_CODE] = GetNormalColour(YELLOW),
      [BLUE_CODE] = GetNormalColour(BLUE),
      [MAGENTA_CODE] = GetNormalColour(MAGENTA),
      [CYAN_CODE] = GetNormalColour(CYAN),
      [WHITE_CODE] = GetNormalColour(WHITE),
      [BOLD_BLACK_CODE] = GetBoldColour(BLACK),
      [BOLD_RED_CODE] = GetBoldColour(RED),
      [BOLD_GREEN_CODE] = GetBoldColour(GREEN),
      [BOLD_YELLOW_CODE] = GetBoldColour(YELLOW),
      [BOLD_BLUE_CODE] = GetBoldColour(BLUE),
      [BOLD_MAGENTA_CODE] = GetBoldColour(MAGENTA),
      [BOLD_CYAN_CODE] = GetBoldColour(CYAN),
      [BOLD_WHITE_CODE] = GetBoldColour(WHITE)
   }
end

local function init_color_to_basic ()
   client_color_to_dim_code = {
      [code_to_client_color[RED_CODE]] = RED_CODE,
      [code_to_client_color[GREEN_CODE]] = GREEN_CODE,
      [code_to_client_color[YELLOW_CODE]] = YELLOW_CODE,
      [code_to_client_color[BLUE_CODE]] = BLUE_CODE,
      [code_to_client_color[MAGENTA_CODE]] = MAGENTA_CODE,
      [code_to_client_color[CYAN_CODE]] = CYAN_CODE,
      [code_to_client_color[WHITE_CODE]] = WHITE_CODE
   }

   client_color_to_bold_code = {
      [code_to_client_color[BOLD_BLACK_CODE]] = BOLD_BLACK_CODE,
      [code_to_client_color[BOLD_RED_CODE]] = BOLD_RED_CODE,
      [code_to_client_color[BOLD_GREEN_CODE]] = BOLD_GREEN_CODE,
      [code_to_client_color[BOLD_YELLOW_CODE]] = BOLD_YELLOW_CODE,
      [code_to_client_color[BOLD_BLUE_CODE]] = BOLD_BLUE_CODE,
      [code_to_client_color[BOLD_MAGENTA_CODE]] = BOLD_MAGENTA_CODE,
      [code_to_client_color[BOLD_CYAN_CODE]] = BOLD_CYAN_CODE,
      [code_to_client_color[BOLD_WHITE_CODE]] = BOLD_WHITE_CODE
   }
end

local function init_basic_colors ()
   init_basic_to_color()
   init_color_to_basic()
end


local xterm_number_to_client_color = extended_colours
local client_color_to_xterm_number = {}
local client_color_to_xterm_code = {}
local x_to_client_color = {}
local x_not_too_dark = {}
local function init_xterm_colors ()
   for i = 0,255 do
      local color = xterm_number_to_client_color[i]
      x_not_too_dark[i] = i
      x_to_client_color[string.format(X3DIGIT_FORMAT,i)] = color
      x_to_client_color[string.format(X2DIGIT_FORMAT,i)] = color
      x_to_client_color[string.format(X1DIGIT_FORMAT,i)] = color

      client_color_to_xterm_number[color] = i
      client_color_to_xterm_code[color] = string.format(X3DIGIT_FORMAT,i)
   end

   -- Aardwolf bumps a few very dark xterm colors to brighter values to improve
   -- visibility. This seems like a good idea.
   local function override_dark_color (replace_what, with_what)
      local new_color = xterm_number_to_client_color[with_what]
      x_not_too_dark[replace_what] = with_what
      x_to_client_color[string.format(X3DIGIT_FORMAT,replace_what)] = new_color
      x_to_client_color[string.format(X2DIGIT_FORMAT,replace_what)] = new_color
      x_to_client_color[string.format(X1DIGIT_FORMAT,replace_what)] = new_color
   end

   override_dark_color(0, 7)
   override_dark_color(16, 7)
   override_dark_color(17, 19)
   override_dark_color(18, 19)
   for i = 232,237 do
      override_dark_color(i, 238)
   end
end

init_xterm_colors()
init_basic_colors()

function StylesToColours (styles, dollarC_resets)
   init_basic_colors()
   local lastcode = ""

   -- convert to multiline if needed
   local style_lines = styles
   if styles[1] and not styles[1][1] then
      style_lines = {styles}
   end

   local line_texts = {}
   for _,line in ipairs(style_lines) do
      local line_parts = {}
      for _,style in ipairs(line) do
         local bold = style.bold or (style.style and ((style.style % 2) == 1))
         local text = string.gsub(style.text, CODE_PREFIX, PREFIX_ESCAPE)
         local textcolor = style.textcolour
         local code = (
            style.fromx
            or textcolor and (
               bold and client_color_to_bold_code[textcolor]
               or client_color_to_dim_code[textcolor]
               or client_color_to_xterm_code[textcolor]
               or string.format(X3DIGIT_FORMAT, bgr_number_to_nearest_x256(textcolor))
            )
         )

         if code and (lastcode ~= code) then
            table.insert(line_parts, code)
            lastcode = code
         end
         if dollarC_resets then
            text = text:gsub("%$C", lastcode)
         end
         table.insert(line_parts, text)
      end
      table.insert(line_texts, table.concat(line_parts))
   end

   return table.concat(line_texts, "\n")
end


require "copytable"
function TruncateStyles (styles, startcol, endcol)
   if (styles == nil) or (styles[1] == nil) then
      return styles
   end

   local startcol = startcol or 1
   local endcol = endcol or 99999 -- 99999 is assumed to be long enough to cover ANY style run

   -- negative column indices are used to measure back from the end
   if (startcol < 0) or (endcol < 0) then
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
   local found_first = false
   local col_counter = 0
   local new_styles = {}
   local break_after = false
   for k,v in ipairs(styles) do
      local new_style = copytable.shallow(v)
      col_counter = col_counter + new_style.length
      if endcol <= col_counter then
         local marker = endcol - (col_counter - v.length)
         new_style.text = new_style.text:sub(1, marker)
         new_style.length = marker
         break_after = true
      end
      if startcol <= col_counter then
         if not found_first then
            local marker = startcol - (col_counter - v.length)
            found_first = true
            new_style.text = new_style.text:sub(marker)
            new_style.length = new_style.length - marker + 1
         end
         table.insert(new_styles, new_style)
      end
      if break_after then break end
   end

   return new_styles
end

function StylesWidth (win, plain_font, bold_font, styles, show_bold, utf8)
   local width = 0
   for i,v in ipairs(styles) do
      local font = plain_font
      if show_bold and v.bold and bold_font then
         font = bold_font
      end
      width = width + WindowTextWidth(win, font, v.text, utf8)
   end
   return width
end


function ToMultilineStyles (message, default_foreground_color, background_color, multiline, dollarC_resets)
   function err()
      assert(false, "Function '"..(debug.getinfo(3, "n").name or debug.getinfo(2, "n").name).."' cannot convert message to multiline styles if it isn't a color coded string, table of styles, or table of tables (multiple lines) of styles.")
   end

   if type(message) == "string" then
      message = ColoursToStyles(message, default_foreground_color, background_color, multiline, dollarC_resets)
   end

   if type(message) ~= "table" then
      err()
   end

   if message.text then
      message = {{message}}
   elseif (type(message[1]) == "table") and message[1].text then
      message = {message}
   end

   if (type(message[1]) ~= "table") or (type(message[1][1]) ~= "table") or not message[1][1].text then
      err()
   end

   local default_black = GetNormalColour(BLACK)
   for _,line in ipairs(message) do
      for _,style in ipairs(line) do
         if style.length == nil then
            style.length = #(style.text)
         end
         if style.backcolour == default_black then
            style.backcolour = nil
         end
      end
   end

   return message
end

-- Partitions a line of styles at some separator pattern (default is "%s+" for blank space)
-- returns {{nonspace styles},{space styles},{nonspace styles},...}
function partition_boundaries (styles, separator_pattern)
   separator_pattern = separator_pattern or "%s+"
   local partitions = {}
   local last_text = nil
   local cur_partition = {}
   for _,style in ipairs(styles) do
      local style_tokens = style.text:split(separator_pattern, true)
      for _,text in ipairs(style_tokens) do
         if last_text then
            local last_endswith = last_text:match(separator_pattern.."$")
            local this_startswith = text:match("^"..separator_pattern)
            if last_endswith ~= this_startswith then
               if #cur_partition == 0 then
                  cur_partition = {{
                     text="",
                     length=0
                  }}
               end
               table.insert(partitions, cur_partition)
               cur_partition = {}
            end
         end
         local length = #text
         if length > 0 then
            table.insert(cur_partition, {text=text, length=length, bold=style.bold, backcolour=style.backcolour, textcolour=style.textcolour})
         end
         last_text = text
      end
   end
   if #cur_partition == 0 then
      cur_partition = {{
         text="",
         length=0
      }}
   end
   table.insert(partitions, cur_partition)
   return partitions
end

-- Splits a line of styles at some separator pattern (default is "%s+" for blank space)
-- returns {{nonspace styles},{nonspace styles},...}
function split_boundaries (styles, separator)
   local partitioned_styles = partition_boundaries(styles, separator)
   local style_lines = {}
   for i=1,#partitioned_styles,2 do
      table.insert(style_lines, partitioned_styles[i])
   end
   return style_lines
end


-- Converts text with colour codes in it into a line of style runs or multiple lines of style runs split at newlines if multiline is true.
-- default_foreground_color and background_color can be Aardwolf color codes or MUSHclient's raw numeric color values
-- dollarC_resets is a boolean for whether "$C" in the input will behave like the leading foreground color (default color if no color found at front)
function ColoursToStyles (input, default_foreground_color, background_color, multiline, dollarC_resets)
   -- This function would be a lot simpler if I weren't trying to preserve whether a color came from an xterm code or
   -- not for round-trip safety. :(
   init_basic_to_color()

   local default_foreground_code = nil
   local default_foreground_bold = false
   if default_foreground_color == nil then
      default_foreground_color = code_to_client_color[WHITE_CODE]
      default_foreground_code = WHITE_CODE
   elseif type(default_foreground_color) == "string" then
      default_foreground_code = default_foreground_color
      if default_foreground_code:sub(1,1) ~= CODE_PREFIX then
         default_foreground_code = CODE_PREFIX..default_foreground_code
      end
      default_foreground_color = code_to_client_color[default_foreground_code] or x_to_client_color[default_foreground_code]
      default_foreground_bold = is_bold_code[default_foreground_code] or false
      assert(default_foreground_color, "Invalid default_foreground_color setting. Codes must correspond to one of the available color codes.")
   elseif type(default_foreground_color) == "number" then
      default_foreground_code = client_color_to_xterm_code[default_foreground_color]
   end

   if type(background_color) == "string" then
      if background_color:sub(1,1) ~= CODE_PREFIX then
         background_color = CODE_PREFIX..background_color
      end
      background_color = code_to_client_color[background_color] or x_to_client_color[background_color]
      assert(background_color, "Invalid background_color setting. Codes must correspond to one of the available color codes.")
   end

   section = input

   local styles = {}
   if section:find(CODE_PREFIX, nil, true) then
      section = section:gsub(PREFIX_ESCAPE, "\0") -- change @@ to 0x00
      section = section:gsub(TILDE_PATTERN, "~") -- fix tildes (historical)
      section = section:gsub(X_NONNUMERIC_PATTERN,"%1") -- strip invalid xterm codes (non-number)
      section = section:gsub(X_THREEHUNDRED_PATTERN,"") -- strip invalid xterm codes (300+)
      section = section:gsub(X_TWOSIXTY_PATTERN,"") -- strip invalid xterm codes (260+)
      section = section:gsub(X_TWOFIFTYSIX_PATTERN,"") -- strip invalid xterm codes (256+)
      section = section:gsub(HIDDEN_GARBAGE_PATTERN, "")  -- strip hidden garbage

      local tokens = section:split(ALL_CODES_PATTERN, true)
      local num_tokens = #tokens
      local first_i = 1
      if tokens[1] == "" then
         -- If the line starts with a color code, there will be a blank token at the start before the first color code
         -- because of the split. Skip it and start at the color code.
         if num_tokens > 1 then
            first_i = 2
         end
      else
         -- If the line does not start with a color code, add a dummy slot for the default code to go in.
         tokens[0] = ""
         first_i = 0
      end

      local color = default_foreground_color
      local code = default_foreground_code
      local first_color = nil
      local first_code_bold = nil
      for i=first_i,num_tokens-1,2 do
         code = tokens[i] or code
         local text = tokens[i+1]:gsub("%z", CODE_PREFIX) -- put any @ characters back
         local from_x = nil
         if code == XTERM_CODE then -- xterm 256 colors
            local num = nil
            num, text = text:match("(%d%d?%d?)(.*)")
            code = code..num
            from_x = code

            -- Aardwolf treats x1...x15 as normal ANSI colors.
            -- That behavior does not match MUSHclient's.
            num = tonumber(num)
            if num <= 15 then
               color = code_to_client_color[first_15_to_code[num]]
            else
               color = x_to_client_color[code]
            end
         else
            color = code_to_client_color[code]
         end
         color = color or default_foreground_color

         local function add_token(styles, text, from_x, is_bold, color, background_color)
            table.insert(styles,
            {
               fromx = from_x,
               text = text,
               bold = is_bold or false,
               length = #text,
               textcolour = color,
               backcolour = background_color
            })
         end

         local is_bold = is_bold_code[code]
         if dollarC_resets then
            for i,v in ipairs(text:split("%$C")) do
               if i > 1 then
                  color = default_foreground_color
                  is_bold = default_foreground_bold
               end
               add_token(styles, v, from_x, is_bold, color, background_color)
            end
         else
            add_token(styles, text, from_x, is_bold, color, background_color)
         end
      end
   else
      -- No colour codes, create a single style.
      styles[1] = {
         text = section,
         bold = is_bold_code[default_foreground_code] or false,
         length = #section,
         textcolour = default_foreground_color,
         backcolour = background_color
      }
   end

   if multiline then
      return split_boundaries(styles, "\n")
   else
      return styles
   end
end


-- Strip all color codes from a string
function strip_colours (s)
   s = s:gsub(PREFIX_ESCAPE, "\0")  -- change @@ to 0x00
   s = s:gsub(TILDE_PATTERN, "~")    -- fix tildes (historical)
   s = s:gsub(X_ANY_DIGITS_PATTERN, "") -- strip valid and invalid xterm color codes
   s = s:gsub(ALL_CODES_PATTERN, "") -- strip normal color codes and hidden garbage
   return (s:gsub("%z", CODE_PREFIX)) -- put @ back (has parentheses on purpose)
end -- strip_colours


-- Convert Aardwolf and short x codes to 3 digit x codes
function canonicalize_colours (s, keep_original)
   if s:find(CODE_PREFIX, nil, true) then
      s = s:gsub(X_DIGITS_CAPTURE_PATTERN, function(a)
         local b = tonumber(a)
         if b and b <= 255 and b >= 0 then
            if keep_original and b <= 15 then
               return first_15_to_code[b]
            end
            return string.format(X3DIGIT_FORMAT, b)
         else
            return ""
         end
      end)
      if not keep_original then
         s = s:gsub(NONX_CODES_CAPTURE_PATTERN, function(a)
            return code_to_xterm[a]
         end)
      end
   end
   return s
end


-- Strip all color codes from a table of styles
function strip_colours_from_styles (styles)
   -- convert to multiline if needed
   local style_lines = styles
   if styles[1] and not styles[1][1] then
      style_lines = {styles}
   end

   local line_texts = {}
   for _,line in ipairs(style_lines) do
      local line_parts = {}
      for _,v in ipairs(line) do
         table.insert(line_parts, v.text)
      end
      table.insert(line_texts, table.concat(line_parts))
   end

   return table.concat(line_texts, "\n")
end


-- Returns a string with embedded ansi codes.
-- This can get confused if the player has redefined their color chart.
function stylesToANSI (styles, dollarC_resets)
   local line = {}
   local lastcode = ""
   local needs_reset = false
   init_basic_colors()
   for _,v in ipairs(styles) do
      local code = ""
      local textcolor = v.textcolour
      local backcolor = v.backcolour
      if textcolor then
         local isbold = (v.bold or (v.style and ((v.style % 2) == 1)))
         if v.fromx then
            code = ANSI(isbold and 1 or 0, 38, 5, v.fromx:sub(3))
         else
            code = colorNumberToAnsi(textcolor, isbold, false)
         end
         if backcolor then
            code = code .. colorNumberToAnsi(backcolor, false, true)
            needs_reset = true
         elseif needs_reset then
            code = ANSI(0) .. code
            needs_reset = false
         end
      end
      if code ~= "" then
         lastcode = code
      end
      if dollarC_resets then
         v.text = v.text:gsub("%$C", lastcode)
      end
      table.insert(line, code..v.text)
   end
   return table.concat(line)
end

-- For mushclient numbers, like 10040166 or ColourNameToRGB("rebeccapurple")
function colorNumberToAnsi(color_number, foreground_is_bold, is_background)
   if is_background then
      return ANSI(48, 5, bgr_number_to_nearest_x256(color_number))
   else
      if foreground_is_bold then
         local boldcode = client_color_to_bold_code[color_number]
         if boldcode then
            local code = ANSI(1, code_to_ansi_digit[boldcode])
            if code then
               return code
            end
         end
      else
         local dimcode = client_color_to_dim_code[color_number]
         if dimcode then
            local code = ANSI(0, code_to_ansi_digit[dimcode])
            if code then
               return code
            end
         end
      end
      return ANSI(foreground_is_bold and 1 or 0, 38, 5, bgr_number_to_nearest_x256(color_number))
   end
end

function bgr_number_to_nearest_x256(bgr_number)
   -- https://stackoverflow.com/a/38055734
   local index = client_color_to_xterm_number[color_number]
   if index then return index end

   local abs, min, max, floor = math.abs, math.min, math.max, math.floor

   local function color_split_rgb(bgr_number)
      local band, rshift = bit.band, bit.rshift
      local b = band(rshift(bgr_number, 16), 0xFF)
      local g = band(rshift(bgr_number, 8), 0xFF)
      local r = band(bgr_number, 0xFF)
      return r, g, b
   end

   local r, g, b = color_split_rgb(bgr_number)

   local levels = {[0] = 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff}
   
   local function index_0_5(value)
      return floor(max((value - 35) / 40, value / 58))
   end

   local function nearest_16_231(r, g, b)
      r, g, b = index_0_5(r), index_0_5(g), index_0_5(b)
      return 16 + 36 * r + 6 * g + b, levels[r], levels[g], levels[b]
   end

   local function nearest_232_255(r, g, b)
      local index = min(23, max(0, floor((((3 * r + 10 * g + b) / 14) - 3) / 10)))
      local gray = 8 + index * 10
      return 232 + index, gray, gray, gray
   end

   local function color_distance(r1, g1, b1, r2, g2, b2)
      return abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)
   end

   local idx1, r1, g1, b1 = nearest_16_231(r, g, b)
   local idx2, r2, g2, b2 = nearest_232_255(r, g, b)
   local dist1 = color_distance(r, g, b, r1, g1, b1)
   local dist2 = color_distance(r, g, b, r2, g2, b2)
   return (dist1 < dist2) and idx1 or idx2
end


-- Tries to convert ANSI sequences to Aardwolf color codes
function AnsiToColours (ansi, default_foreground_code)
   if not default_foreground_code then
      default_foreground_code = WHITE_CODE
   elseif default_foreground_code:sub(1,1) ~= CODE_PREFIX then
      default_foreground_code = CODE_PREFIX..default_foreground_code
   end

   local ansi_capture = "\027%[([%d;]+)m"

   -- this stuff goes outside because ANSI is a state machine (lolsigh)
   local bold = false
   local color = ""
   local xstage = 0

   ansi = ansi:gsub(CODE_PREFIX, PREFIX_ESCAPE):gsub(ansi_capture, function(a)
      for c in a:gmatch("%d+") do
         local nc = tonumber(c)
         if nc == 38 then
            xstage = 1
         elseif nc == 5 and xstage == 1 then
            xstage = 2
         elseif xstage == 2 then -- xterm 256 color
            if bold and ansi_digit_to_bold_code[nc+30] then
               color = ansi_digit_to_bold_code[nc+30]
            else
               color = string.format(X3DIGIT_FORMAT, nc)
            end
            xstage = 0
         elseif nc == 1 then
            bold = true
            xstage = 0
         elseif nc == 0 then
            bold = is_bold_code[default_foreground_code] or false
            -- not actually sure if we should set color here or not
            color = default_foreground_code
         elseif nc <= 37 and nc >= 30 then -- regular color
            if bold then
               color = ansi_digit_to_bold_code[nc]
            else
               color = ansi_digit_to_dim_code[nc]
            end
            xstage = 0
         end
      end
      return color
   end)

   return ansi
end


function ColoursToANSI (text)
   -- return stylesToANSI(ColoursToStyles(text))
   if text:find(CODE_PREFIX, nil, true) then
      text = text:gsub(PREFIX_ESCAPE, "\0") -- change @@ to 0x00
      text = text:gsub(TILDE_PATTERN, "~") -- fix tildes (historical)
      text = text:gsub(X_NONNUMERIC_PATTERN,"%1") -- strip invalid xterm codes (non-number)
      text = text:gsub(X_THREEHUNDRED_PATTERN,"") -- strip invalid xterm codes (300+)
      text = text:gsub(X_TWOSIXTY_PATTERN,"") -- strip invalid xterm codes (260+)
      text = text:gsub(X_TWOFIFTYSIX_PATTERN,"") -- strip invalid xterm codes (256+)
      text = text:gsub(HIDDEN_GARBAGE_PATTERN, "")  -- strip hidden garbage

      text = text:gsub(X_DIGITS_CAPTURE_PATTERN, function(a)
         local num_a = tonumber(a)
         -- Aardwolf treats x1...x15 as normal ANSI codes
         if num_a >=1 and num_a <= 15 then
            if num_a >= 9 then
               return ANSI(1, num_a+22)
            else
               return ANSI(0, num_a+30)
            end
         else
            return ANSI(0, 38, 5, x_not_too_dark[num_a])
         end
      end)
      text = text:gsub(BOLD_CODES_CAPTURE_PATTERN, function(a)
         return ANSI(1,code_to_ansi_digit[a])
      end)
      text = text:gsub(NORMAL_CODES_CAPTURE_PATTERN, function(a)
         return ANSI(0,code_to_ansi_digit[a])
      end)

      text = text:gsub("%z", CODE_PREFIX)
   end
   return text
end


-- EVERYTHING BELOW HERE IS DEPRECATED. DO NOT USE. --

-- Historical function without purpose. Use StylesToColours.
-- Use TruncateStyles if you must, but that seems to be rather uncommon.
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


-- should have been marked local to prevent external use
colour_conversion = {
   [BLACK_CHAR] = GetNormalColour(BLACK)   ,   -- 0x000000
   [RED_CHAR] = GetNormalColour(RED)     ,   -- 0x000080
   [GREEN_CHAR] = GetNormalColour(GREEN)   ,   -- 0x008000
   [YELLOW_CHAR] = GetNormalColour(YELLOW)  ,   -- 0x008080
   [BLUE_CHAR] = GetNormalColour(BLUE)    ,   -- 0x800000
   [MAGENTA_CHAR] = GetNormalColour(MAGENTA) ,   -- 0x800080
   [CYAN_CHAR] = GetNormalColour(CYAN)    ,   -- 0x808000
   [WHITE_CHAR] = GetNormalColour(WHITE)   ,   -- 0xC0C0C0
   [BOLD_BLACK_CHAR] = GetBoldColour(BLACK)   ,   -- 0x808080
   [BOLD_RED_CHAR] = GetBoldColour(RED)     ,   -- 0x0000FF
   [BOLD_GREEN_CHAR] = GetBoldColour(GREEN)   ,   -- 0x00FF00
   [BOLD_YELLOW_CHAR] = GetBoldColour(YELLOW)  ,   -- 0x00FFFF
   [BOLD_BLUE_CHAR] = GetBoldColour(BLUE)    ,   -- 0xFF0000
   [BOLD_MAGENTA_CHAR] = GetBoldColour(MAGENTA) ,   -- 0xFF00FF
   [BOLD_CYAN_CHAR] = GetBoldColour(CYAN)    ,   -- 0xFFFF00
   [BOLD_WHITE_CHAR] = GetBoldColour(WHITE)   ,   -- 0xFFFFFF
}  -- end conversion table

atletter_to_color_value = colour_conversion -- lol. https://github.com/endavis/bastmush/commit/6f8aec07449a55a65ccece05c1ab3a0139d70e54
