local BLACK = 1
local RED = 2
local GREEN = 3  
local YELLOW = 4 
local BLUE = 5 
local MAGENTA = 6 
local CYAN = 7 
local WHITE = 8
local DEFAULT_COLOUR = "@w"

-- colour styles (eg. @r is normal red, @R is bold red)

local conversion = {
  [GetNormalColour (BLACK)]   = "@k", -- note: aardwolf does not use this
  [GetNormalColour (RED)]     = "@r",
  [GetNormalColour (GREEN)]   = "@g",
  [GetNormalColour (YELLOW)]  = "@y",
  [GetNormalColour (BLUE)]    = "@b",
  [GetNormalColour (MAGENTA)] = "@m",
  [GetNormalColour (CYAN)]    = "@c",
  [GetNormalColour (WHITE)]   = "@w",
  [GetBoldColour   (BLACK)]   = "@D",
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

function StylesToColoursOneLine (styles, startcol, endcol)
  copystring = ""
  -- remove unneeded style runs at the start
  while next (styles) and startcol > styles [1].length do
    startcol = startcol - styles [1].length
    endcol = endcol - styles [1].length
    table.remove (styles, 1)
  end -- do
  
  -- nothing left? uh oh
  if not next (styles) then return end
  
  -- discard unwanted part of first good style
  if startcol > 1 then
    styles [1].length = styles [1].length - startcol
    endcol = endcol - startcol + 1
    styles [1].text =  styles [1].text:sub (startcol)   
    startcol = 1
  end -- if
  
  -- copy appropriate styles and codes into the output
  while next (styles) do
    local len = endcol - startcol + 1
    
    if len < 0 or endcol < 1 then
      return
    end -- done
    
    -- last style?
    if len < styles [1].length then
      styles [1].length = len
      styles [1].text = styles [1].text:sub (1, len)
    end -- if last style
  
    -- fixup string first - change @ to @@ and ~ to @-
    local text = string.gsub (styles [1].text, "@", "@@")
    text = string.gsub (styles [1].text, "~", "@-")
    
    -- put code in front, if we can find one
    local code = conversion [styles [1].textcolour]
    if code then
      copystring = copystring .. code
    end -- if code found
    
    -- now the text
    copystring = copystring .. text
    
    -- less to go now
    endcol = endcol - styles [1].length
    
    -- done this style
    table.remove (styles, 1)
  end -- while
  return copystring
end -- DoOneLine

-- converts text with colour styles in it into style runs

function ColoursToStyles (Text)
    if Text:match ("@") then
        astyles = {}

        Text = Text:gsub ("@%-", "~") -- fix tildes
        Text = Text:gsub ("@@", "\0") -- change @@ to 0x00
        Text = Text:gsub ("@ ", "")  -- rip out hidden garbage

        -- make sure we start with @ or gsub doesn't work properly
        if Text:sub (1, 1) ~= "@" then
           Text = DEFAULT_COLOUR .. Text
        end -- if

        for colour, text in Text:gmatch ("@(%a)([^@]+)") do

           text = text:gsub ("%z", "@") -- put any @ characters back

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

function strip_colours (s)
  s = s:gsub ("@%-", "~")    -- fix tildes
  s = s:gsub ("@@", "\0")  -- change @@ to 0x00
  s = s:gsub ("@ ", "")  -- rip out hidden garbage
  s = s:gsub ("@%a([^@]*)", "%1")
  return (s:gsub ("%z", "@")) -- put @ back
end -- strip_colours

