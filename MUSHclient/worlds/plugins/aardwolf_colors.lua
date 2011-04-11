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
    [526344] = "@x232",
    [1184274] = "@x233",
    [1842204] = "@x234",
    [2500134] = "@x235",
    [3158064] = "@x236",
    [3815994] = "@x237",
    [4473924] = "@x238",
    [5131854] = "@x239",
    [5789784] = "@x240",
    [6447714] = "@x241",
    [7105644] = "@x242",
    [7763574] = "@x243",
    [8421504] = "@x244",
    [9079434] = "@x245",
    [9737364] = "@x246",
    [10395294] = "@x247",
    [11053224] = "@x248",
    [11711154] = "@x249",
    [12369084] = "@x250",
    [13027014] = "@x251",
    [13684944] = "@x252",
    [14342874] = "@x253",
    [15000804] = "@x254",
    [15658734] = "@x255",
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
    x232 = 526344,
    x233 = 1184274,
    x234 = 1842204,
    x235 = 2500134,
    x236 = 3158064,
    x237 = 3815994,
    x238 = 4473924,
    x239 = 5131854,
    x240 = 5789784,
    x241 = 6447714,
    x242 = 7105644,
    x243 = 7763574,
    x244 = 8421504,
    x245 = 9079434,
    x246 = 9737364,
    x247 = 10395294,
    x248 = 11053224,
    x249 = 11711154,
    x250 = 12369084,
    x251 = 13027014,
    x252 = 13684944,
    x253 = 14342874,
    x254 = 15000804,
    x255 = 15658734,
}  -- end conversion table

-- Set up xterm color conversions
xterm_intensities = {0x00, 0x33, 0x66, 0x99, 0xCC, 0xFF}
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
for i = 16,231 do
    BLUE = ((i-16)%6) + 1
    GREEN = (math.floor((i-16)/6)%6) + 1
    RED = (math.floor((i-16)/36)%6) + 1
    xterm_colour = bit.shl(xterm_intensities[BLUE],16)+bit.shl(xterm_intensities[GREEN],8)+xterm_intensities[RED]
    conversion[xterm_colour] = (conversion[xterm_colour] or string.format("@x%03d",i))
    colour_conversion[string.format("x%03d",i)] = xterm_colour
    colour_conversion[string.format("x%02d",i)] = xterm_colour
    colour_conversion[string.format("x%d",i)] = xterm_colour
end

-- convert a line of style runs into color codes
function StylesToColoursOneLine (styles, startcol, endcol)
  copystring = ""
  -- remove unneeded style runs at the start
  while next (styles) and startcol > styles [1].length do
    startcol = startcol - styles [1].length
    endcol = endcol - styles [1].length
    table.remove (styles, 1)
  end -- do

  -- nothing left? uh oh
  if not next (styles) then return copystring end
  
  -- discard unwanted part of first good style
  if startcol > 1 then
    styles [1].length = styles [1].length - startcol + 1
    endcol = endcol - startcol + 1
    styles [1].text =  styles [1].text:sub (startcol)   
    startcol = 1
  end -- if
  
  -- copy appropriate styles and codes into the output
  while next (styles) do
    local len = endcol - startcol + 1

    if len < 1 or endcol < 1 then
      break
    end -- done

    -- last style?
    if len < styles [1].length then
      styles [1].length = len
      styles [1].text = styles [1].text:sub (1, len)
    end -- if last style

    -- fixup string first - change @ to @@ and ~ to @-
    local text = string.gsub (styles [1].text, "@", "@@")
    text = string.gsub (text, "~", "@-")

    -- put code in front, if we can find one
    local code = conversion [styles[1].textcolour]

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
end -- StylesToColoursOneLine

-- converts text with colour codes in it into style runs
function ColoursToStyles (Text)
    if Text:match ("@") then
        astyles = {}

        Text = Text:gsub ("@%-", "~") -- fix tildes
        Text = Text:gsub ("@@", "\0") -- change @@ to 0x00
        Text = Text:gsub ("@x([^%d])","%1") -- strip invalid xterm codes
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

function strip_colours (s)
  s = s:gsub ("@%-", "~")    -- fix tildes
  s = s:gsub ("@@", "\0")  -- change @@ to 0x00
  s = s:gsub ("@[^xcmyrgbwCMYRGBWD]", "")  -- rip out hidden garbage
  s = s:gsub ("@x%d?%d?%d?", "") -- strip xterm color codes
  s = s:gsub ("@%a([^@]*)", "%1") -- strip normal color codes
  return (s:gsub ("%z", "@")) -- put @ back
end -- strip_colours

