--[[
This file contains code that can be inherited by other plugins that allows
many different miniwindow plugins to follow the same UI theme, as long as they
follow certain guidelines. We can use this to maintain a base set of colors
and title fonts that get used everywhere in order to unify the visual style
and provide a way to customize that style easily.

Steps for use:
1) From inside your other plugins, call: require "mw_theme_base".
2) Use variable names as spelled out below (theme.WINDOW_BACKGROUND, theme.WINDOW_BORDER, etc.).
3) Link some action in your plugin with either the choose_theme or the list_themes and load_theme functions.
4) Make your own themes (copy lua/mw_themes/default.lua to a new *.lua file and customize the colors).
--]]

theme_dir = GetInfo(66).."lua\\mw_themes\\"
theme_file = "default.lua"

function list_themes ()
   t, e = utils.readdir(theme_dir.."*.lua")
   for k,v in pairs(t) do
      t[k] = k:gsub("%.lua", "")
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

   -- fallback defaults if the file is missing or any necessary values are undefined
   theme = status and theme or {}
   theme.HIGHLIGHT = theme.HIGHLIGHT or ColourNameToRGB("white")
   theme.FACE = theme.FACE or ColourNameToRGB("#D4D0C8")
   theme.FACE_GRADIENT = theme.FACE_GRADIENT or theme.FACE
   theme.INNERSHADOW  = theme.INNERSHADOW or ColourNameToRGB("#808080")
   theme.OUTERSHADOW = theme.OUTERSHADOW or ColourNameToRGB("#404040")
   theme.WINDOW_BACKGROUND = theme.WINDOW_BACKGROUND or ColourNameToRGB("#000000")
   theme.WINDOW_BORDER = theme.WINDOW_BORDER or ColourNameToRGB("#E8E8E8")
   theme.BACK_FACE = theme.BACK_FACE or ColourNameToRGB("#E8E8E8")
   theme.DETAIL = theme.DETAIL or ColourNameToRGB("#000000")
   theme.TITLE_HEIGHT = theme.TITLE_HEIGHT or 17
   theme.SUBTITLE_HEIGHT = theme.SUBTITLE_HEIGHT or 17
   theme.TITLE_FONT_NAME = theme.TITLE_FONT_NAME or "Dina"
   theme.TITLE_FONT_SIZE = theme.TITLE_FONT_SIZE or 8

   if status then
      theme_file = file
      SetVariable("theme_file", theme_file)
      if not no_broadcast then
         BroadcastPlugin(1999, "new_theme:"..theme_file)
      end
   end
end

function OnPluginBroadcast (msg, id, name, text)
   if (msg == 1999) and (text:sub(1,10) == "new_theme:") then
      load_theme(text:sub(11), true)
   end
end

load_theme(GetVariable("theme_file") or theme_file, true)

-- Replacement for WindowRectOp action 5, which allows for a 3D look while maintaining color theme.
-- Requires global theme.HIGHLIGHT, theme.FACE, theme.INNERSHADOW, and theme.OUTERSHADOW colors to be set.
function DrawThemed3DRect(Window, left, top, right, bottom)
   if theme.FACE ~= theme.FACE_GRADIENT then
      WindowGradient(Window, left, top, right, bottom, theme.FACE, theme.FACE_GRADIENT, 2)
   else
      WindowRectOp(Window, 2, left, top, right, bottom, theme.FACE)
   end
   WindowLine(Window, left, top, right, top, theme.HIGHLIGHT, 0 + 0x0200, 1)
   WindowLine(Window, left, top, left, bottom, theme.HIGHLIGHT, 0 + 0x0200, 1)
   WindowLine(Window, left, bottom-2, right, bottom-2, theme.INNERSHADOW, 0 + 0x0200, 1)
   WindowLine(Window, right-2, top, right-2, bottom-2, theme.INNERSHADOW, 0 + 0x0200, 1)
   WindowLine(Window, left, bottom-1, right, bottom-1, theme.OUTERSHADOW, 0 + 0x0200, 1)
   WindowLine(Window, right-1, top, right-1, bottom-1, theme.OUTERSHADOW, 0 + 0x0200, 1)
end

-- the thing that goes in the bottom right corner for resizing miniwindows
function DrawThemedResizeTag(Window, x1, y1, size)
    local x2, y2 = x1+size, y1+size
    DrawThemed3DRect(Window, x1, y1, x2, y2)
    local m = 2
    local n = 2
    while (x1+m+2 <= x2-3 and y1+n+1 <= y2-4) do
        WindowLine(Window, x1+m+1, y2-4, x2-3, y1+n, theme.HIGHLIGHT, 0, 1)
        WindowLine(Window, x1+m+2, y2-4, x2-3, y1+n+1, theme.INNERSHADOW, 0, 1)
        m = m+3
        n = n+3
    end
end

