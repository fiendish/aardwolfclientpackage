-- Thank you, Shaun Biggs, for taking your time to write the CopyScript
-- (formerly Copy2) function below. It was slightly altered by me to suit
-- my usage (wordwrapped lines and no \r\n at start of selection).


local BLACK = 1
local RED = 2
local GREEN = 3  
local YELLOW = 4 
local BLUE = 5 
local MAGENTA = 6 
local CYAN = 7 
local WHITE = 8

-- how each colour is to appear (black is not supported on Aardwolf)

local conversion = {
  [GetNormalColour (RED)]     = "@r",
  [GetNormalColour (GREEN)]   = "@g",
  [GetNormalColour (YELLOW)]  = "@y",
  [GetNormalColour (BLUE)]    = "@b",
  [GetNormalColour (MAGENTA)] = "@m",
  [GetNormalColour (CYAN)]    = "@c",
  [GetNormalColour (WHITE)]   = "@w",
  [GetBoldColour   (RED)]     = "@R",
  [GetBoldColour   (GREEN)]   = "@G",
  [GetBoldColour   (YELLOW)]  = "@Y",
  [GetBoldColour   (BLUE)]    = "@B",
  [GetBoldColour   (MAGENTA)] = "@M",
  [GetBoldColour   (CYAN)]    = "@C",
  [GetBoldColour   (WHITE)]   = "@W",
  }  -- end conversion table
  
function ColourConvertOneLine (styles, startcol, endcol)
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