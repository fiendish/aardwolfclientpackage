local BLACK = 1
local RED = 2
local GREEN = 3
local YELLOW = 4
local BLUE = 5
local MAGENTA = 6
local CYAN = 7
local WHITE = 8


local code_to_ansi_digit = {
   ["@r"] = 31,
   ["@g"] = 32,
   ["@y"] = 33,
   ["@b"] = 34,
   ["@m"] = 35,
   ["@c"] = 36,
   ["@w"] = 37,
   ["@D"] = 30,
   ["@R"] = 31,
   ["@G"] = 32,
   ["@Y"] = 33,
   ["@B"] = 34,
   ["@M"] = 35,
   ["@C"] = 36,
   ["@W"] = 37
}

local ansi_digit_to_dim_code = {
   [31] = "@r",
   [32] = "@g",
   [33] = "@y",
   [34] = "@b",
   [35] = "@m",
   [36] = "@c",
   [37] = "@w"
}

local ansi_digit_to_bold_code = {
   [30] = "@D",
   [31] = "@R",
   [32] = "@G",
   [33] = "@Y",
   [34] = "@B",
   [35] = "@M",
   [36] = "@C",
   [37] = "@W"
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
   code_to_xterm[v] = string.format("@x%03d",k)
end

local bold_codes = {
   ["@D"]=true, ["@R"]=true, ["@G"]=true, ["@Y"]=true, ["@B"]=true,
   ["@M"]=true, ["@C"]=true, ["@W"]=true
}
for i = 9,15 do
   bold_codes[string.format("@x%03d",i)] = true
   bold_codes[string.format("@x%02d",i)] = true
   bold_codes[string.format("@x%d",i)] = true
end


local code_to_client_color = {}
local client_color_to_dim_code = {}
local client_color_to_bold_code = {}

local function init_basic_to_color ()
   default_black = GetNormalColour(BLACK)

   code_to_client_color = {
      ["@r"] = GetNormalColour(RED),
      ["@g"] = GetNormalColour(GREEN),
      ["@y"] = GetNormalColour(YELLOW),
      ["@b"] = GetNormalColour(BLUE),
      ["@m"] = GetNormalColour(MAGENTA),
      ["@c"] = GetNormalColour(CYAN),
      ["@w"] = GetNormalColour(WHITE),
      ["@D"] = GetBoldColour(BLACK),
      ["@R"] = GetBoldColour(RED),
      ["@G"] = GetBoldColour(GREEN),
      ["@Y"] = GetBoldColour(YELLOW),
      ["@B"] = GetBoldColour(BLUE),
      ["@M"] = GetBoldColour(MAGENTA),
      ["@C"] = GetBoldColour(CYAN),
      ["@W"] = GetBoldColour(WHITE)
   }
end

local function init_color_to_basic ()
   client_color_to_dim_code = {
      [code_to_client_color["@r"]] = "@r",
      [code_to_client_color["@g"]] = "@g",
      [code_to_client_color["@y"]] = "@y",
      [code_to_client_color["@b"]] = "@b",
      [code_to_client_color["@m"]] = "@m",
      [code_to_client_color["@c"]] = "@c",
      [code_to_client_color["@w"]] = "@w"
   }

   client_color_to_bold_code = {
      [code_to_client_color["@D"]] = "@D",
      [code_to_client_color["@R"]] = "@R",
      [code_to_client_color["@G"]] = "@G",
      [code_to_client_color["@Y"]] = "@Y",
      [code_to_client_color["@B"]] = "@B",
      [code_to_client_color["@M"]] = "@M",
      [code_to_client_color["@C"]] = "@C",
      [code_to_client_color["@W"]] = "@W"
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
      x_to_client_color[string.format("@x%03d",i)] = color
      x_to_client_color[string.format("@x%02d",i)] = color
      x_to_client_color[string.format("@x%d",i)] = color

      client_color_to_xterm_number[color] = i
      client_color_to_xterm_code[color] = string.format("@x%03d",i)
   end

   -- Aardwolf bumps a few very dark xterm colors to brighter values to improve
   -- visibility. This seems like a good idea.
   local function override_dark_color (replace_what, with_what)
      local new_color = xterm_number_to_client_color[with_what]
      x_not_too_dark[replace_what] = with_what
      x_to_client_color[string.format("@x%03d",replace_what)] = new_color
      x_to_client_color[string.format("@x%02d",replace_what)] = new_color
      x_to_client_color[string.format("@x%d",replace_what)] = new_color
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
   local line = {}
   local lastcode = ""
   for i,style in ipairs(styles) do
      local bold = style.bold or (style.style and ((style.style % 2) == 1))
      local text = string.gsub(style.text, "@", "@@")
      local textcolor = style.textcolour
      local code = style.fromx
                   or bold and client_color_to_bold_code[textcolor]
                   or client_color_to_dim_code[textcolor]
                   or client_color_to_xterm_code[textcolor]

      if code then
         lastcode = code
      end
      if dollarC_resets then
         text = text:gsub("%$C", lastcode)
      end
      table.insert(line, (code or "")..text)
   end
   return table.concat(line)
end


require "copytable"
function TruncateStyles (styles, startcol, endcol)
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


-- Converts text with colour codes in it into style runs
function ColoursToStyles (input, default_foreground_code, default_background_code)
   init_basic_to_color()
   if default_foreground_code and default_foreground_code:sub(1,1) ~= "@" then
      default_foreground_code = "@"..default_foreground_code
   end
   if default_background_code and default_background_code:sub(1,1) ~= "@" then
      default_background_code = "@"..default_background_code
   end
   local default_bold = false
   local default_foreground = code_to_client_color[default_foreground_code] or x_to_client_color[default_foreground_code]
   if not default_foreground then
      default_foreground = code_to_client_color["@w"]
      default_foreground_code = "@w"
   else
      default_bold = bold_codes[default_foreground_code] or false
      default_foreground_code = default_foreground_code
   end
   local default_background = code_to_client_color[default_background_code] or x_to_client_color[default_background_code]
   if not default_background then
      default_background = default_black
   end

   if input:find("@", nil, true) then
      local astyles = {}

      -- make sure we start with a color
      if input:sub(1, 1) ~= "@" then
         input = default_foreground_code .. input
      end -- if

      input = input:gsub("@@", "\0") -- change @@ to 0x00
      input = input:gsub("@%-", "~") -- fix tildes (historical)
      input = input:gsub("@x([^%d])","%1") -- strip invalid xterm codes (non-number)
      input = input:gsub("@x[3-9]%d%d","") -- strip invalid xterm codes (300+)
      input = input:gsub("@x2[6-9]%d","") -- strip invalid xterm codes (260+)
      input = input:gsub("@x25[6-9]","") -- strip invalid xterm codes (256+)
      input = input:gsub("@[^xrgybmcwDRGYBMCW]", "")  -- strip hidden garbage

      for code, text in input:gmatch("(@%a)([^@]*)") do
         local from_x = nil
         text = text:gsub("%z", "@") -- put any @ characters back

         if code == "@x" then -- xterm 256 colors
            num,text = text:match("(%d%d?%d?)(.*)")
            code = code..num
            -- Aardwolf treats x1...x15 as normal ANSI colors.
            -- That behavior does not match MUSHclient's.
            num = tonumber(num)
            from_x = code
            if num <= 15 then
               textcolor = code_to_client_color[first_15_to_code[num]]
            else
               textcolor = x_to_client_color[code]
            end
         else
            textcolor = code_to_client_color[code]
         end

         table.insert(astyles,
         {
            fromx = from_x,
            text = text,
            bold = bold_codes[code] or false,
            length = #text,
            textcolour = textcolor or default_foreground,
            backcolour = default_background
         })
      end -- for each colour run.

      return astyles
   end -- if any colour codes at all

   -- No colour codes, create a single style.
   return {{
      text = input,
      bold = default_bold,
      length = #input,
      textcolour = default_foreground,
      backcolour = default_background
   }}
end  -- function ColoursToStyles


-- Strip all color codes from a string
function strip_colours (s)
   s = s:gsub("@@", "\0")  -- change @@ to 0x00
   s = s:gsub("@%-", "~")    -- fix tildes (historical)
   s = s:gsub("@x%d?%d?%d?", "") -- strip valid and invalid xterm color codes
   s = s:gsub("@.([^@]*)", "%1") -- strip normal color codes and hidden garbage
   return (s:gsub("%z", "@")) -- put @ back (has parentheses on purpose)
end -- strip_colours


-- Convert Aardwolf and short x codes to 3 digit x codes
function canonicalize_colours (s)
   if s:find("@", nil, true) then
      s = s:gsub("@x(%d%d?%d?)", function(a)
         local b = tonumber(a)
         if b and b <= 255 and b >= 0 then
            return string.format("@x%03d", b)
         else
            return ""
         end
      end)
      s = s:gsub("(@[^x])", function(a)
         return code_to_xterm[a]
      end)
   end
   return s
end


-- Strip all color codes from a table of styles
function strip_colours_from_styles (styles)
   local ret = {}
   for i,v in ipairs(styles) do
      table.insert(ret, v.text)
   end
   return table.concat(ret)
end


-- Returns a string with embedded ansi codes.
-- This can get confused if the player has redefined their color chart.
function stylesToANSI (styles, dollarC_resets)
   local line = {}
   local lastcode = ""
   init_basic_colors()
   for _,v in ipairs(styles) do
      local code = ""
      local textcolor = v.textcolour
      if textcolor then
         local isbold = (v.bold or (v.style and ((v.style % 2) == 1)))
         if v.fromx then
            code = ANSI(isbold and 1 or 0, 38, 5, v.fromx:sub(3))
         elseif isbold and client_color_to_bold_code[textcolor] then
            local a = client_color_to_bold_code[textcolor]
            code = ANSI(1, code_to_ansi_digit[a])
         elseif client_color_to_dim_code[textcolor] then
            local a = client_color_to_dim_code[textcolor]
            code = ANSI(0, code_to_ansi_digit[a])
         elseif client_color_to_xterm_number[textcolor] then
            code = ANSI(isbold and 1 or 0, 38, 5, client_color_to_xterm_number[textcolor])
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


-- Tries to convert ANSI sequences to Aardwolf color codes
function AnsiToColours (ansi, default_foreground_code)
   if not default_foreground_code then
      default_foreground_code = "@w"
   elseif default_foreground_code:sub(1,1) ~= "@" then
      default_foreground_code = "@"..default_foreground_code
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
            if bold and ansi_digit_to_bold_code[nc+30] then
               color = ansi_digit_to_bold_code[nc+30]
            else
               color = string.format("@x%03d", nc)
            end
            xstage = 0
         elseif nc == 1 then
            bold = true
            xstage = 0
         elseif nc == 0 then
            bold = bold_codes[default_foreground_code] or false
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
   if text:find("@", nil, true) then
      text = text:gsub("@@", "\0") -- change @@ to 0x00
      text = text:gsub("@%-", "~") -- fix tildes (historical)
      text = text:gsub("@x([^%d])","%1") -- strip invalid xterm codes (non-number)
      text = text:gsub("@x[3-9]%d%d","") -- strip invalid xterm codes (300+)
      text = text:gsub("@x2[6-9]%d","") -- strip invalid xterm codes (260+)
      text = text:gsub("@x25[6-9]","") -- strip invalid xterm codes (256+)
      text = text:gsub("@[^xrgybmcwDRGYBMCW]", "")  -- strip hidden garbage

      text = text:gsub("@x(%d%d?%d?)", function(a)
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
      text = text:gsub("(@[DRGYBMCW])", function(a)
         return ANSI(1,code_to_ansi_digit[a])
      end)
      text = text:gsub("(@[rgybmcw])", function(a)
         return ANSI(0,code_to_ansi_digit[a])
      end)

      text = text:gsub("%z", "@")
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
   k = GetNormalColour(BLACK)   ,   -- 0x000000
   r = GetNormalColour(RED)     ,   -- 0x000080
   g = GetNormalColour(GREEN)   ,   -- 0x008000
   y = GetNormalColour(YELLOW)  ,   -- 0x008080
   b = GetNormalColour(BLUE)    ,   -- 0x800000
   m = GetNormalColour(MAGENTA) ,   -- 0x800080
   c = GetNormalColour(CYAN)    ,   -- 0x808000
   w = GetNormalColour(WHITE)   ,   -- 0xC0C0C0
   K = GetBoldColour(BLACK)   ,   -- 0x808080
   R = GetBoldColour(RED)     ,   -- 0x0000FF
   G = GetBoldColour(GREEN)   ,   -- 0x00FF00
   Y = GetBoldColour(YELLOW)  ,   -- 0x00FFFF
   B = GetBoldColour(BLUE)    ,   -- 0xFF0000
   M = GetBoldColour(MAGENTA) ,   -- 0xFF00FF
   C = GetBoldColour(CYAN)    ,   -- 0xFFFF00
   W = GetBoldColour(WHITE)   ,   -- 0xFFFFFF
}  -- end conversion table

atletter_to_color_value = colour_conversion -- lol. https://github.com/endavis/bastmush/commit/6f8aec07449a55a65ccece05c1ab3a0139d70e54
