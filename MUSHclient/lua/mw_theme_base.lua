--[[
This file contains code that can be inherited by other plugins that allows
many different miniwindow plugins to follow the same UI theme, as long as they
follow certain guidelines. We can use this to maintain a base set of colors
and title fonts that get used everywhere in order to unify the visual style
and provide a way to customize that style easily.

Steps for use:
1) From inside your other plugins, call: require "mw_theme_base".
2) Use variable names as spelled out in mw_themes\default.lua
3) Optional: Link some action in your plugin with either the choose_theme or the list_themes and load_theme functions.
4) Optional: Make your own themes (copy lua/mw_themes/default.lua to a new *.lua file and customize the colors).
--]]

theme_dir = GetInfo(66).."lua\\mw_themes\\"
theme_file = "default.lua"

function list_themes ()
   t, e = utils.readdir(theme_dir.."*.lua")
   for k,v in pairs(t) do
      t[k] = k:gsub("%.lua", ""):gsub("_", " ")
   end
   return t
end

function choose_theme ()
   t = list_themes()
   load_theme(
      utils.listbox ("Which theme would you like to use?", "Choose Theme", t, theme_file)
      or theme_file
   )
end

function load_theme (file, no_broadcast)
   status, theme = pcall(dofile, theme_dir..file)

   if status then
      theme_file = file
      SetVariable("theme_file", theme_file)
      if not no_broadcast then
         BroadcastPlugin(1999, "new_theme:"..theme_file)
      end

      theme.TITLE_FONT = "theme_title_font"
      theme.TITLE_FONTS = theme.TITLE_FONTS or {}
      table.insert(theme.TITLE_FONTS, {["name"]="Dina", ["size"]=8}) -- in case other fonts aren't found
   end
end

function OnPluginBroadcast (msg, id, name, text)
   if (msg == 1999) and (text:sub(1,10) == "new_theme:") then
      load_theme(text:sub(11), true)
   end
end

load_theme(GetVariable("theme_file") or theme_file, true)

-- Replacement for WindowRectOp action 5, which allows for a 3D look while maintaining color theme.
function Draw3DRect (win, left, top, right, bottom, sunken)
   if right > 0 then
      right = right + 1
   end
   if bottom > 0 then
      bottom = bottom + 1
   end
   WindowRectOp(win, 2, left, top, right, bottom, theme.THREE_D_SURFACE)
   if not sunken then
      WindowLine(win, left, top+1, right, top+1, theme.THREE_D_INNERHIGHLIGHT, 0x0200, 1)
      WindowLine(win, left+1, top, left+1, bottom, theme.THREE_D_INNERHIGHLIGHT, 0x0200, 1)

      WindowLine(win, left, bottom-2, right, bottom-2, theme.THREE_D_INNERSHADOW, 0x0200, 1)
      WindowLine(win, right-2, top, right-2, bottom-2, theme.THREE_D_INNERSHADOW, 0x0200, 1)

      WindowLine(win, left, top, right, top, theme.THREE_D_OUTERHIGHLIGHT, 0x0200, 1)
      WindowLine(win, left, top, left, bottom, theme.THREE_D_OUTERHIGHLIGHT, 0x0200, 1)

      WindowLine(win, left, bottom-1, right, bottom-1, theme.THREE_D_OUTERSHADOW, 0x0200, 1)
      WindowLine(win, right-1, top, right-1, bottom-1, theme.THREE_D_OUTERSHADOW, 0x0200, 1)
   else
      WindowLine(win, left, top+1, right, top+1, theme.THREE_D_INNERSHADOW, 0x0200, 1)
      WindowLine(win, left+1, top, left+1, bottom, theme.THREE_D_INNERSHADOW, 0x0200, 1)

      WindowLine(win, left, top, right, top, theme.THREE_D_OUTERSHADOW, 0x0200, 1)
      WindowLine(win, left, top, left, bottom, theme.THREE_D_OUTERSHADOW, 0x0200, 1)

      WindowLine(win, left, bottom-1, right, bottom-1, theme.THREE_D_OUTERHIGHLIGHT, 0x0200, 1)
      WindowLine(win, right-1, top, right-1, bottom-1, theme.THREE_D_OUTERHIGHLIGHT, 0x0200, 1)
   end
end

-- the thing that goes in the bottom right corner for resizing miniwindows
function DrawResizeTag (win, x1, y1, size)
    local x2, y2 = x1+size, y1+size
    Draw3DRect(win, x1, y1, x2, y2)
    local m = 0
    local n = 0
    while (x1+m+2 <= x2-1 and y1+n+1 <= y2-2) do
        WindowLine(win, x1+m+1, y2-2, x2-1, y1+n, theme.THREE_D_INNERHIGHLIGHT, 0, 1)
        WindowLine(win, x1+m+2, y2-2, x2-1, y1+n+1, theme.THREE_D_INNERSHADOW, 0, 1)
        m = m+3
        n = n+3
    end
end

function TextHeight(win, font)
   return WindowFontInfo(win, font, 1) - WindowFontInfo(win, font, 4)
end

function LoadTitleFont(win)
   for i,F in ipairs(theme.TITLE_FONTS) do
      if 0 == WindowFont(win, theme.TITLE_FONT, F["name"], F["size"]) then
         break
      end
   end

   theme.TITLE_HEIGHT = TextHeight(win, theme.TITLE_FONT) + (2 * theme.TITLE_PADDING) + 4
   return theme.TITLE_FONT
end

function DrawTitleBar(win, title, text_alignment, full_width)
   local font = LoadTitleFont(win)
   local title_width = WindowTextWidth(win, font, title)
   local text_left = (WindowInfo(win, 3) - title_width) / 2    -- text align center
   if text_alignment == "left" then
      text_left = theme.TITLE_PADDING
   elseif text_alignment == "right" then
      text_left = WindowInfo(win, 3) - title_width - theme.TITLE_PADDING
   end
   local text_right = math.min(text_left + title_width, WindowInfo(win, 3) - theme.TITLE_PADDING)
   if full_width then
      Draw3DRect(
         win,
         0,
         0,
         WindowInfo(win, 3)-1,
         theme.TITLE_HEIGHT-1
      )
   else
      Draw3DRect(
         win,
         math.max(0, text_left - theme.TITLE_PADDING),
         0,
         math.min(text_left + title_width + theme.TITLE_PADDING, WindowInfo(win, 3)),
         theme.TITLE_HEIGHT
      )
   end
   WindowText(win, font, title, text_left, theme.TITLE_PADDING, text_right, theme.TITLE_HEIGHT, theme.THREE_D_SURFACE_DETAIL)
   return theme.TITLE_HEIGHT
end
