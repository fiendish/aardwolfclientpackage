--[[
This file contains code that that allows many different miniwindow plugins
to follow the same UI theme, as long as they follow certain guidelines.
We can use this to maintain a base set of colors, standard display elements,
and title fonts that get used everywhere in order to unify the visual style
and provide a way to customize that style easily.

Steps for use:
1) Inside your plugins, require "mw_theme_base" at the very beginning of your script section.
2) Use variable names as spelled out in mw_themes\default.lua for colorization
3) Use the shared graphics functions defined below for drawing any 3D rectangles with the chosen color theme
4) Call FinalizeThemes() at the very end of your script section.
6) Optional: Make your own themes (copy lua/mw_themes/default.lua to a new *.lua file and customize the colors).
--]]
require "checkplugin"

theme_dir = GetInfo(66).."lua\\mw_themes\\"
theme_file = "Charcoal.lua"

function b9315e040989d3f81f4328d6()
   -- used for theme system detection
   return true
end

function get_theme()
   return theme_file
end

function load_theme (file)
   status, theme = pcall(dofile, file)

   if status then
      theme_file = file

      theme.TITLE_FONT = "theme_title_font"
      theme.TITLE_FONTS = theme.TITLE_FONTS or {}
      table.insert(theme.TITLE_FONTS, {["name"]="Dina", ["size"]=10}) -- in case other fonts aren't found
   end
end

local theme_controller = "b9315e040989d3f81f4328d6"
if GetPluginID() ~= theme_controller and not IsPluginInstalled(theme_controller) then
   local action = [[DoAfterSpecial(0.1, 'require \'checkplugin\';do_plugin_check_now(\']]..theme_controller..[[\', \'aard_Theme_Controller\')', sendto.script)]]
   local prefix = GetAlphaOption("script_prefix")
   action = [[
      SetAlphaOption("script_prefix", "/")
      Execute("/]]..action:gsub("\\", "\\\\")..[[")
      SetAlphaOption("script_prefix", "]]..prefix:gsub("\\", "\\\\")..[[")
   ]]
   DoAfterSpecial(0.1, action, sendto.script)
end
theme_file = GetPluginVariable(theme_controller, "theme_file") or theme_file
load_theme(theme_dir..theme_file)

-- Replacement for WindowRectOp action 5, which allows for a 3D look while maintaining color theme.
function Draw3DRect (win, left, top, right, bottom, depressed)
   local gradient = (not theme.THREE_D_GRADIENT_ONLY_IN_TITLE or __theme_istitle) and theme.THREE_D_GRADIENT or false
   __theme_istitle = false

   if right > 0 then
      right = right + 1
   end
   if bottom > 0 then
      bottom = bottom + 1
   end

   if gradient and (theme.THREE_D_GRADIENT_FIRST == theme.THREE_D_GRADIENT_SECOND) then
      gradient = false
   end

   if (gradient == 1) or (gradient == 2) or (gradient == 3) then
      WindowGradient(win, left, top, right, bottom,
                theme.THREE_D_GRADIENT_FIRST,
                theme.THREE_D_GRADIENT_SECOND,
                gradient)
   else
      WindowRectOp(win, 2, left, top, right, bottom, theme.THREE_D_GRADIENT_FIRST)
   end

   if not depressed then
      WindowLine(win, left+1, top+1, right, top+1, theme.THREE_D_HIGHLIGHT, 0x0200, 1)
      WindowLine(win, left+1, top+1, left+1, bottom, theme.THREE_D_HIGHLIGHT, 0x0200, 1)

      WindowLine(win, left, bottom-2, right, bottom-2, theme.THREE_D_SOFTSHADOW, 0x0200, 1)
      WindowLine(win, right-2, top, right-2, bottom-2, theme.THREE_D_SOFTSHADOW, 0x0200, 1)

      WindowLine(win, left, bottom-1, right, bottom-1, theme.THREE_D_HARDSHADOW, 0x0200, 1)
      WindowLine(win, right-1, top, right-1, bottom-1, theme.THREE_D_HARDSHADOW, 0x0200, 1)
   else
      WindowLine(win, left, top+1, right, top+1, theme.THREE_D_SOFTSHADOW, 0x0200, 1)
      WindowLine(win, left+1, top, left+1, bottom, theme.THREE_D_SOFTSHADOW, 0x0200, 1)

      WindowLine(win, left, top, right, top, theme.THREE_D_HARDSHADOW, 0x0200, 1)
      WindowLine(win, left, top, left, bottom, theme.THREE_D_HARDSHADOW, 0x0200, 1)

      WindowLine(win, left+1, bottom-1, right, bottom-1, theme.THREE_D_SOFTSHADOW, 0x0200, 1)
      WindowLine(win, right-1, top+1, right-1, bottom-1, theme.THREE_D_SOFTSHADOW, 0x0200, 1)
   end
end

-- the thing that goes in the bottom right corner for resizing miniwindows
function DrawResizeTag (win, type, x1, y1, size)
   if not size then
      size = theme.RESIZER_SIZE
   end
   local x2, y2
   if not (x1 and y1) then
      x2 = WindowInfo(win, 3) - 1
      y2 = WindowInfo(win, 4) - 1
      x1 = x2 - size - 1
      y1 = y2 - size - 1
   else
      x2, y2 = x1+size, y1+size
   end

   if type == 2 then -- full
      Draw3DRect(win, x1, y1, x2, y2, false)
   else
      WindowRectOp(win, miniwin.rect_fill, x1, y1, x2+1, y2+1, theme.BODY)
   end


   local m = 2
   local n = 2
   while (x1+m+1 <= x2 and y1+n+2 <= y2) do
      WindowLine(win, x1+m, y2-1, x2, y1+n-1, theme.THREE_D_HIGHLIGHT, 0, 1)
      WindowLine(win, x1+m+1, y2-1, x2, y1+n, theme.THREE_D_HARDSHADOW, 0, 1)
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

function DressWindow(win, title, title_alignment, resizer_type)
   if resizer_type then
      DrawResizeTag(win, resizer_type)
   end
   local l, t, r, b = DrawBorder(win)
   theme.TITLE_HEIGHT = 0
   if title and Trim(title) ~= "" then
      t = DrawTitleBar(win, title, title_alignment)
   end
   return l, t, r, b
end

function DrawTitleBar(win, title, text_alignment)
   local font = LoadTitleFont(win)
   local title_width = WindowTextWidth(win, font, title)
   local text_left = (WindowInfo(win, 3) - title_width) / 2    -- default text align center
   if text_alignment == "left" then
      text_left = theme.TITLE_PADDING + 10
   elseif text_alignment == "right" then
      text_left = WindowInfo(win, 3) - title_width - theme.TITLE_PADDING
   end
   local text_right = math.min(text_left + title_width, WindowInfo(win, 3) - theme.TITLE_PADDING)

   __theme_istitle = true
   Draw3DRect(
      win,
      -1,
      -1,
      WindowInfo(win, 3),
      theme.TITLE_HEIGHT,
      false
   )
   WindowText(win, font, title, text_left, theme.TITLE_PADDING, text_right, theme.TITLE_HEIGHT, theme.THREE_D_SURFACE_DETAIL)
   return theme.TITLE_HEIGHT+1
end

function DrawBorder(win)
   local r = WindowInfo(win, 3)-3
   local b = WindowInfo(win, 4)-3
   WindowRectOp(win, 1, 0, 0, 0, 0, theme.THREE_D_HIGHLIGHT)
   WindowRectOp(win, 1, 1, 1, -1, -1, theme.THREE_D_SOFTSHADOW)
   return 2, 2, r, b
end