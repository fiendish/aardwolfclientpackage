--[[
This file contains code that that allows many different miniwindow plugins
to maintain the same UI theme, as long as they follow certain guidelines.
We can use this to get a base set of colors, standard display elements,
and title fonts that get used everywhere in order to unify the visual style
and provide a way to customize that style easily.

Steps for use:
1) Inside your plugins, require "mw_theme_base" at the very beginning of your script section.
2) Use variable names as spelled out in lua/mw_themes/Charcoal.lua for colorization
3) Use the shared graphics functions defined below for drawing any 3D rectangles with the chosen color theme
4) Optional: Make your own themes (clone one of the files in lua/mw_themes and customize your colors).
--]]
require "checkplugin"
require "movewindow"
dofile(GetPluginInfo(GetPluginID(), 20) .. "aardwolf_colors.lua")

theme_dir = GetInfo(66).."lua\\mw_themes\\"
theme_file = "Charcoal.lua"

function b9315e040989d3f81f4328d6()
   -- used for theme system detection
   return true
end

function get_theme()
   return theme_file
end

function just_reloading()
   SetVariable("just_reloading", 1)
end

function load_theme(file)
   status, theme = pcall(dofile, file)

   if status then
      theme_file = file

      theme.TITLE_FONT = "theme_title_font"
      theme.TITLE_FONTS = theme.TITLE_FONTS or {}
      table.insert(theme.TITLE_FONTS, {["name"]="Dina", ["size"]=10}) -- in case other fonts aren't found
   end
end

function ExecuteInGlobalSpace(inner_action)
   local prefix = GetAlphaOption("script_prefix")
   local action = [[
      SetAlphaOption("script_prefix", "/")
      Execute("/]] .. inner_action:gsub("\\", "\\\\") .. [[")
      SetAlphaOption("script_prefix", "]] .. prefix:gsub("\\", "\\\\") .. [[")
   ]]
   DoAfterSpecial(0.1, action, sendto.script)
end

local theme_controller = "b9315e040989d3f81f4328d6"
if GetPluginID() ~= theme_controller and not IsPluginInstalled(theme_controller) then
   local inner_action = [[DoAfterSpecial(0.1, 'require \'checkplugin\';do_plugin_check_now(\']]..theme_controller..[[\', \'aard_Theme_Controller\')', sendto.script)]]
   ExecuteInGlobalSpace(inner_action)
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
      WindowLine(win, left, top+1, right, top+1, theme.THREE_D_HARDSHADOW, 0x0200, 1)
      WindowLine(win, left+1, top, left+1, bottom, theme.THREE_D_HARDSHADOW, 0x0200, 1)

      WindowLine(win, left, top, right, top, theme.THREE_D_HARDSHADOW, 0x0200, 1)
      WindowLine(win, left, top, left, bottom, theme.THREE_D_HARDSHADOW, 0x0200, 1)
   end
end

function AddResizeTag(win, type, x1, y1, mousedown_callback, dragmove_callback, dragrelease_callback)
   local x1, y1 = DrawResizeTag(win, type, x1, y1)

   -- Add handler hotspots
   if WindowMoveHotspot(win, "resize", x1, y1, 0, 0) ~= 0 then
      WindowAddHotspot(win, "resize", x1, y1, 0, 0, nil, nil, mousedown_callback, nil, nil, "", 6, 0)
      WindowDragHandler(win, "resize", dragmove_callback, dragrelease_callback, 0)
   end

   return x1, y1
end

function DrawResizeTag(win, type, x1, y1)
   local x2, y2
   if not (x1 and y1) then
      x2 = WindowInfo(win, 3) - 3
      y2 = WindowInfo(win, 4) - 3
      x1 = x2 - theme.RESIZER_SIZE + 1
      y1 = y2 - theme.RESIZER_SIZE + 1
   else
      x2 = x1 + theme.RESIZER_SIZE
      y2 = y1 + theme.RESIZER_SIZE
   end

   local m = 2
   local n = 2
   if type == 2 then -- full
      Draw3DRect(win, x1, y1, x2, y2, false)
      while (x1+m < x2 and y1+n+1 < y2) do
         WindowLine(win, x1+m-1, y2-2, x2-1, y1+n-2, theme.THREE_D_HIGHLIGHT, 0, 1)
         WindowLine(win, x1+m, y2-2, x2-1, y1+n-1, theme.THREE_D_HARDSHADOW, 0, 1)
         WindowLine(win, x1+m+1, y2-2, x2-1, y1+n, theme.THREE_D_GRADIENT_FIRST, 0, 1)
         m = m+3
         n = n+3
      end
      WindowSetPixel(win, x2-2, y2-2, theme.THREE_D_HIGHLIGHT)
   else
      while (x1+m < x2 and y1+n+1 < y2) do
         WindowLine(win, x1+m, y2-1, x2, y1+n-1, theme.THREE_D_HIGHLIGHT, 0, 1)
         WindowLine(win, x1+m+1, y2-1, x2, y1+n, theme.THREE_D_HARDSHADOW, 0, 1)
         WindowLine(win, x1+m+2, y2-1, x2, y1+n+1, theme.THREE_D_GRADIENT_FIRST, 0, 1)
         m = m+3
         n = n+3
      end
      WindowLine(win, x1, y2, x2, y2, theme.THREE_D_HARDSHADOW, 0, 1)
      WindowLine(win, x2, y1, x2, y2+1, theme.THREE_D_HARDSHADOW, 0, 1)
      WindowSetPixel(win, x2-1, y2-1, theme.THREE_D_HIGHLIGHT)
   end
   return x1, y1
end

function TextHeight(win, font)
   return WindowFontInfo(win, font, 1)
end

function LoadTitleFont(win)
   if WindowFontInfo(win, theme.TITLE_FONT, 1) == nil then
      for i,F in ipairs(theme.TITLE_FONTS) do
         if 0 == WindowFont(win, theme.TITLE_FONT, F["name"], F["size"]) then
            break
         end
      end
   end
   theme.TITLE_LINE_HEIGHT = TextHeight(win, theme.TITLE_FONT) + theme.TITLE_PADDING
   return theme.TITLE_FONT
end

-- title_alignment can be "left", "right", or "center" (the default)
function DressWindow(win, title, title_alignment)
   local l, t, r, b = DrawBorder(win)

   theme.TITLE_LINE_HEIGHT = 0
   if title and (title ~= "") then
      t = DrawTitleBar(win, title, title_alignment)
      if t > 1 then
         movewindow.add_drag_handler(win, 0, 0, 0, t)
      end
   end

   return l, t, r, b
end

function DrawTitleBar(win, title, text_alignment)
   local title_lines
   if type(title) == "string" then
      title_lines = utils.split(title, "\n")
   else
      title_lines = title
   end

   LoadTitleFont(win)
   local title_height = theme.TITLE_PADDING + (theme.TITLE_LINE_HEIGHT * #title_lines)

   __theme_istitle = true
   Draw3DRect(
      win,
      -1,
      -1,
      WindowInfo(win, 3)-1,
      title_height,
      false
   )

   local title_width = 0
   for i,v in ipairs(title_lines) do
      if type(v) == "table" then
         txt = strip_colours_from_styles(v)
      else
         txt = v
      end
      title_width = math.max(title_width, WindowTextWidth(win, theme.TITLE_FONT, txt))
   end

   local text_left = (WindowInfo(win, 3) - title_width) / 2  -- default text align center
   if text_alignment == "left" then
      text_left = theme.TITLE_PADDING + 5
   elseif text_alignment == "right" then
      text_left = WindowInfo(win, 3) - title_width - theme.TITLE_PADDING
   end
   local text_right = math.min(text_left + title_width, WindowInfo(win, 3) - theme.TITLE_PADDING)

   local first_color = nil
   for i,v in ipairs(title_lines) do
      text_top = (theme.TITLE_LINE_HEIGHT * (i-1)) + theme.TITLE_PADDING
      if type(v) == "string" then
         WindowText(win, theme.TITLE_FONT, v, text_left, text_top, text_right, title_height, theme.THREE_D_SURFACE_DETAIL)
      else
         -- The colors of all styles matching the first style color get stripped out and replaced with the default title color
         for i,w in ipairs(v) do
            first_color = first_color or w.textcolour
            if w.textcolour == first_color then
               w.textcolour = theme.THREE_D_SURFACE_DETAIL
            end
         end
         WindowTextFromStyles(win, theme.TITLE_FONT, v, text_left, text_top, text_right, title_height, true)
      end
   end
   return title_height+1
end

function WindowTextFromStyles(win, font, styles, left, top, right, bottom)
   for i,v in ipairs(styles) do
      left = left + WindowText(win, font, v.text, left, top, right, bottom, v.textcolour or theme.BODY_TEXT)
   end
end

function DrawBorder(win)
   local r = WindowInfo(win, 3)-3
   local b = WindowInfo(win, 4)-3
   WindowRectOp(win, 1, 0, 0, 0, 0, theme.THREE_D_HIGHLIGHT)
   WindowRectOp(win, 1, 1, 1, -1, -1, theme.THREE_D_SOFTSHADOW)
   return 2, 2, r, b
end

-- Based on mw.lua's popup function, but with theme colors
function Popup(win,   -- window name to use
   font_id,           -- font to use for each body line
   info,              -- table of lines to show (plain text or styles)
   Left, Top,         -- preferred location
   stay_left_of,      -- guidance for keeping the popup visible
   stay_right_of)     -- guidance for keeping the popup visible

   local BORDER_WIDTH = 2

   assert(WindowInfo (win, 1), "Window " .. win .. " must already exist")
   assert(WindowFontInfo (win, font_id, 1), "No font " .. font_id .. " in " .. win)

   local font_height = WindowFontInfo (win, font_id, 1)
   local font_leading = WindowFontInfo (win, font_id, 4) + WindowFontInfo (win, font_id, 5)

   -- find text width - minus colour codes
   local infowidth = 0
   local infoheight = 0

   -- calculate remaining width and height
   for _, v in ipairs (info) do
      if type(v) == "table" then
         txt = strip_colours_from_styles(v)
      else
         txt = strip_colours(v)
      end
      infowidth  = math.max (infowidth, WindowTextWidth (win, font_id, txt))
      infoheight = infoheight + font_height
   end -- for

   infowidth = infowidth + (2 * BORDER_WIDTH) +    -- leave room for border
      WindowFontInfo (win, font_id, 6)  -- one character width extra

   infoheight = infoheight + (2 * BORDER_WIDTH) +  -- leave room for border
      font_leading +                    -- plus leading below bottom line,
      10                                -- and 5 pixels top and bottom

   -- if align_right then
   --    Left = Left - infowidth
   -- end -- if align_right

   -- if align_bottom then
   --    Top = Top - infoheight
   -- end -- if align_bottom

   Top = math.min(Top, GetInfo(280) - infoheight)
   Top = math.max(0, Top)
   if Left < stay_left_of then
      if Left+infowidth > stay_left_of then
         Left = stay_left_of - infowidth
      end
      if Left < 0 then
         Left = stay_right_of
      end
   else
      if Left < stay_right_of then
         Left = stay_right_of
      end
      if (Left + infowidth) > GetInfo(281) then
         Left = stay_left_of - infowidth
      end
   end
   WindowCreate(win,
      Left, Top,    -- where
      infowidth,    -- width  (gap of 5 pixels per side)
      infoheight,   -- height
      miniwin.pos_top_left,  -- position mode: can't be 0 to 3
      miniwin.create_absolute_location + miniwin.create_transparent,
      theme.SECONDARY_BODY)

   WindowCircleOp(win, miniwin.circle_round_rectangle,
      BORDER_WIDTH, BORDER_WIDTH, -BORDER_WIDTH, -BORDER_WIDTH,  -- border inset
      theme.THREE_D_HIGHLIGHT, miniwin.pen_solid, BORDER_WIDTH,  -- line
      theme.PRIMARY_BODY, miniwin.brush_solid,          -- fill
      5, 5)  -- diameter of ellipse

   local x = BORDER_WIDTH + WindowFontInfo (win, font_id, 6) / 2    -- start 1/2 character in
   local y = BORDER_WIDTH + 5          -- skip border, and leave 5 pixel gap

   -- show each line
   for _, line in ipairs(info) do
      if type(line) == "string" then
         WindowText(win, font_id, line, x, y, 0, 0, theme.BODY_TEXT)
      else
         WindowTextFromStyles(win, font_id, line, x, y, 0, 0)
      end

      y = y + font_height
   end -- for

   -- display popup window
   WindowShow(win, true)

end -- popup
