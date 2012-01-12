local BLACK = 1
local RED = 2
local GREEN = 3  
local YELLOW = 4 
local BLUE = 5 
local MAGENTA = 6 
local CYAN = 7 
local WHITE = 8
local DEFAULT_COLOUR = "@w"

-- map from color values to aardwolf color codes
conversion_colours = {
   [GetNormalColour (BLACK)]   = "@x000",
   [GetNormalColour (RED)]     = "@r",
   [GetNormalColour (GREEN)]   = "@g",
   [GetNormalColour (YELLOW)]  = "@y",
   [GetNormalColour (BLUE)]    = "@b",
   [GetNormalColour (MAGENTA)] = "@m",
   [GetNormalColour (CYAN)]    = "@c",
   [GetNormalColour (WHITE)]   = "@w",
   [GetBoldColour   (BLACK)]   = "@D", -- gray
   [GetBoldColour   (RED)]     = "@R",
   [GetBoldColour   (GREEN)]   = "@G",
   [GetBoldColour   (YELLOW)]  = "@Y",
   [GetBoldColour   (BLUE)]    = "@B",
   [GetBoldColour   (MAGENTA)] = "@M",
   [GetBoldColour   (CYAN)]    = "@C",
   [GetBoldColour   (WHITE)]   = "@W",
}  -- end conversion table
  
-- This table uses the colours as defined in the MUSHclient ANSI tab, however the
-- defaults are shown on the right if you prefer to use those.

-- map from aardwolf color codes to color values
colour_conversion = {
   k = GetNormalColour (BLACK)   ,   -- 0x000000 
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
}  -- end conversion table

-- Set up xterm color conversions using the extended_colours global array
for i = 1,8 do
   colour_conversion[string.format("x%03d",i-1)] = GetNormalColour(i)
   colour_conversion[string.format("x%02d",i-1)] = GetNormalColour(i)
   colour_conversion[string.format("x%d",i-1)] = GetNormalColour(i)
end
for i = 9,16 do
   colour_conversion[string.format("x%03d",i-1)] = GetBoldColour(i-8)
   colour_conversion[string.format("x%02d",i-1)] = GetBoldColour(i-8)
   colour_conversion[string.format("x%d",i-1)] = GetBoldColour(i-8)
end
for i = 16,255 do
   local xterm_colour = extended_colours[i]
   conversion_colours[xterm_colour] = (conversion_colours[xterm_colour] or string.format("@x%03d",i))
   colour_conversion[string.format("x%03d",i)] = xterm_colour
   colour_conversion[string.format("x%d",i)] = xterm_colour
end

-- Aardwolf bumps a few very dark xterm colors to brighter values to improve visibility
for i = 232,237 do
   colour_conversion[string.format("x%d",i)] = extended_colours[238]
end
for i = 17,19 do
   colour_conversion[string.format("x%03d",i)] = extended_colours[19]
   colour_conversion[string.format("x%d",i)] = extended_colours[19]
end

-- Convert a line of style runs into color codes.
-- The caller may optionally choose to start and stop at arbitrary character indices.
-- Negative indices are measured back from the end.
-- The order of start and end columns does not matter, since the start will always be lower than the end.
function StylesToColoursOneLine (styles, startcol, endcol)
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

   -- start/end order does not matter when calling this function
   if startcol > endcol then
      startcol, endcol = endcol, startcol
   end

   local copystring = ""
   
   -- skip unused style runs at the start
   local style_start = 0
   local first_style = 0
   local last_style = 0
   for k,v in ipairs(styles) do
      if startcol <= style_start+v.length then
         first_style = k
         startcol = startcol - style_start
         break
      end
      style_start = style_start+v.length
   end
      
   -- startcol larger than the sum length of all styles? return empty string
   if first_style == 0 then 
      return copystring 
   end
   
   for i = first_style,#styles do
      local v = styles[i]
      local text = string.sub(v.text, startcol, endcol - style_start)

      -- fixup string: change @ to @@ and ~ to @-
      text = string.gsub(string.gsub(text, "@", "@@"),"~", "@-")
      
      local code = conversion_colours[v.textcolour]
      if code then
         copystring = copystring..code..text
      else
         copystring = copystring..text
      end
      
      -- stopping here before the end?
      if endcol <= style_start + v.length then
         break
      end
      
      -- all styles after the first one have startcol of 1
      startcol = 1
      style_start = style_start + v.length
   end
   return copystring
end -- StylesToColoursOneLine

-- converts text with colour codes in it into style runs
function ColoursToStyles (Text)
   if Text:match ("@") then
      astyles = {}

      Text = Text:gsub ("@%-", "~") -- fix tildes
      Text = Text:gsub ("@@", "\0") -- change @@ to 0x00
      Text = Text:gsub ("@x([^%d])","%1") -- strip invalid xterm codes (non-number)
      Text = Text:gsub ("@x[3-9]%d%d","") -- strip invalid xterm codes (300+)
      Text = Text:gsub ("@x2[6-9]%d","") -- strip invalid xterm codes (260+)
      Text = Text:gsub ("@x25[6-9]","") -- strip invalid xterm codes (256+)
      Text = Text:gsub ("@[^xcmyrgbwCMYRGBWD]", "")  -- rip out hidden garbage
      
      -- make sure we start with @ or gsub doesn't work properly
      if Text:sub (1, 1) ~= "@" then
         Text = DEFAULT_COLOUR .. Text
      end -- if

      for colour, text in Text:gmatch ("@(%a)([^@]+)") do
         text = text:gsub ("%z", "@") -- put any @ characters back

         if colour == "x" then -- xterm 256 colors
            code,text = text:match("(%d%d?%d?)(.*)")
            colour = colour..code
         end
           
         if #text > 0 then
            table.insert (astyles, { text = text, 
               length = #text, 
               textcolour = colour_conversion [colour] or GetNormalColour (WHITE),
               backcolour = GetNormalColour (BLACK) })
         end -- if some text
      end -- for each colour run.

      return astyles
   end -- if any colour codes at all

   -- No colour codes, create a single style.
   return { { text = Text, 
      length = #Text, 
      textcolour = GetNormalColour (WHITE),
      backcolour = GetNormalColour (BLACK) } }
end  -- function ColoursToStyles

-- strip all aardwolf color codes from a string
function strip_colours (s)
   s = s:gsub ("@%-", "~")    -- fix tildes
   s = s:gsub ("@@", "\0")  -- change @@ to 0x00
   s = s:gsub ("@[^xcmyrgbwCMYRGBWD]", "")  -- rip out hidden garbage
   s = s:gsub ("@x%d?%d?%d?", "") -- strip xterm color codes
   s = s:gsub ("@%a([^@]*)", "%1") -- strip normal color codes
   return (s:gsub ("%z", "@")) -- put @ back
end -- strip_colours

-- also provide the reverse of the extended_colours global table
colours_extended = {}
for i,v in ipairs(extended_colours) do
   colours_extended[v] = i
end

ANSI_colours = {
   [GetNormalColour (BLACK)]   = {0,30},
   [GetNormalColour (RED)]     = {0,31},
   [GetNormalColour (GREEN)]   = {0,32},
   [GetNormalColour (YELLOW)]  = {0,33},
   [GetNormalColour (BLUE)]    = {0,34},
   [GetNormalColour (MAGENTA)] = {0,35},
   [GetNormalColour (CYAN)]    = {0,36},
   [GetNormalColour (WHITE)]   = {0,37},
   [GetBoldColour   (BLACK)]   = {1,30},
   [GetBoldColour   (RED)]     = {1,31},
   [GetBoldColour   (GREEN)]   = {1,32},
   [GetBoldColour   (YELLOW)]  = {1,33},
   [GetBoldColour   (BLUE)]    = {1,34},
   [GetBoldColour   (MAGENTA)] = {1,35},
   [GetBoldColour   (CYAN)]    = {1,36},
   [GetBoldColour   (WHITE)]   = {1,37}
}  -- end conversion table

-- returns a string with embedded ansi codes
function stylesToANSI (styles)
   line = {}
   for _,v in ipairs (styles) do
      if ANSI_colours[v.textcolour] then
         table.insert(line, ANSI(ANSI_colours[v.textcolour][1],ANSI_colours[v.textcolour][2]))
      elseif colours_extended[v.textcolour] then -- use 256 color xterm ansi when necessary
         table.insert(line, ANSI(38,5,colours_extended[v.textcolour]))
      else
         print("It looks like you changed your ANSI color settings. Please restart MUSHclient for these changes to take full effect.")
      end
      table.insert(line, v.text)
   end
   table.insert(line, ANSI(0))
   return table.concat(line)
end
