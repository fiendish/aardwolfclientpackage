--[[
This file contains code that that allows many different miniwindow plugins
to maintain the same UI theme, as long as they follow certain guidelines.
We can use this to get a base set of colors, standard display elements,
and title fonts that get used everywhere in order to unify the visual style
and provide a way to customize that style easily.

Steps for use: (also see https://github.com/fiendish/aardwolfclientpackage/wiki/Miniwindow-Color-Themes )
1) Inside your plugins, require this file at the very beginning of your script section.
2) Use variable names as spelled out in lua/mw_themes/Charcoal.lua for colorization within the "Theme." namespace, e.g. Theme.BODY_TEXT etc.
3) Use the shared graphics functions defined below for drawing various elements with the current color theme.
   Some of the functions are not for drawing things. You can ignore them.
4) Four things make a miniwindow fit the theme: The border, the titlebar, the resize widget, and the general colors being used.
   The border, titlebar, resize widget, and 3D boxes all have special draw functions included below. The colors are defined in the theme files.
4) Optional: Make your own themes (clone one of the files in lua/mw_themes and customize your colors).
5) Optional: If your plugin wants to preserve state between theme changes (changing theme reloads the plugin),
   you can detect whether the plugin is closing because of a theme change with GetVariable(Theme.reloading_variable).
--]]
require "checkplugin"
require "movewindow"
dofile(GetInfo(60) .. "aardwolf_colors.lua")

module ("Theme", package.seeall)

function b9315e040989d3f81f4328d6()
   -- used for theme system detection
   return true
end

theme_dir = GetInfo(66).."lua\\mw_themes\\"
theme_file = "Charcoal.lua"

function get_theme()
   return theme_file
end

reloading_variable = "aard_theme_just_reloading"

function just_reloading()
   SetVariable(reloading_variable, 1)
   SaveState()
end

DeleteVariable(reloading_variable)
SaveState()

local default_theme = {
   LOGO_OPACITY = 0.02,

   PRIMARY_BODY = 0x0c0c0c,
   SECONDARY_BODY = 0x777777,
   BODY_TEXT = 0xe8e8e8,

   CLICKABLE = 0x666666,
   CLICKABLE_HOVER = 0x444444,
   CLICKABLE_HOT = 0x40406b,
   CLICKABLE_TEXT = 0xc8c8c8,
   CLICKABLE_HOVER_TEXT = 0xdddddd,
   CLICKABLE_HOT_TEXT = 0xcfc5df,

   TITLE_PADDING = 2,

   THREE_D_HIGHLIGHT = 0xe8e8e8,

   THREE_D_GRADIENT = miniwin.gradient_vertical,
   THREE_D_GRADIENT_FIRST = 0xcdced1,
   THREE_D_GRADIENT_SECOND = 0x8c8c8c,
   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x606060,
   THREE_D_HARDSHADOW = 0x303030,
   THREE_D_SURFACE_DETAIL = 0x050505,

   SCROLL_TRACK_COLOR1 = 0x444444,
   SCROLL_TRACK_COLOR2 = 0x888888,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   VERTICAL_BUTTON_PADDING = 15,
   HORIZONTAL_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16,

   DYNAMIC_BUTTON_PADDING = 20  -- deprecated
}

function load_theme(file)
   local file_loaded, data_from_file = pcall(dofile, theme_dir..file)

   -- init defaults
   for k,v in pairs(default_theme) do
      Theme[k] = v
   end

   if file_loaded then
      if type(data_from_file) == "table" then
         for k,v in pairs(data_from_file) do
            Theme[k] = v
         end
         theme_file = file
      else
         print("Error loading theme file: ", theme_dir..file)
         print("This theme file is invalid. Please delete it and select a different theme.")
         print()
      end
   else
      print("Error loading theme file: ", theme_dir..file)
      print(data_from_file) -- error message
   end
end

-- junk files that should not have existed in the first place
local bad_shas = {
   ["default.lua"] = {
      ["d189be39efb49730537c8ada65fbd5382d3e44ad"] = true,
      ["39d9b7fc4d571ac62d1005b52f8da43c4b7827e1"] = true,
      ["774bdd2f098f1c4fe81d9a6b8eb5bfad6bd79c51"] = true,
      ["b7fd919be678f0c7b1c52bea644f183a7b9397f1"] = true,
      ["acc1d615901050b2faa50e1b0497ee30b72f5118"] = true,
      ["ac993b349691eb51e472ca5b1b0ae18a03943bf2"] = true,
      ["0cd5bcca0723a57eabedd08a9cfa6f4ec93ea469"] = true
  },
  ["dark_pony.lua"] = {
      ["d189be39efb49730537c8ada65fbd5382d3e44ad"] = true
  },
   ["Joker.lua"] = {
      ["17fa722746df781326b100744dd790c66721b749"] = true,
      ["b2b83804ce87eb889127658cb80c9d23d76082b4"] = true
  }
}

require "gitsha"
function theme_has_bad_sha(filename)
   return bad_shas[filename] and bad_shas[filename][gitsha(theme_dir..filename)]
end

local theme_controller_ID = "b9315e040989d3f81f4328d6"
local theme_controller_name = "aard_Theme_Controller"

function _load_controller()
   if not GetInfo(119) then
      DoAfterSpecial(0.1, 'Theme._load_controller()', sendto.script)
      return
   end
   if not IsPluginInstalled(theme_controller_ID) then
      local inner_action = [[if not theme_plugin_loading then theme_plugin_loading = true; DoAfterSpecial(0.1, 'require \'checkplugin\'; theme_plugin_loading = nil; do_plugin_check_now(\']]..theme_controller_ID..[[\', \']]..theme_controller_name..[[\')', sendto.scriptafteromit) end]]
      -- run_in_global_space(inner_action)
      local prefix = GetAlphaOption("script_prefix")
      SetAlphaOption("script_prefix", "/")
      Execute("/"..inner_action)
      SetAlphaOption("script_prefix", prefix)
   end
end

if (GetPluginID() ~= theme_controller_ID) then
   _load_controller()

   local maybe_theme_file = GetPluginVariable(theme_controller_ID, "theme_file") or theme_file

   if not theme_has_bad_sha(maybe_theme_file) then
      theme_file = maybe_theme_file
   end

   load_theme(theme_file)
end

-- Replacement for WindowRectOp action 5, which allows for a 3D look while maintaining color theme.
function Draw3DRect (win, left, top, right, bottom, depressed)
   local gradient = (not THREE_D_GRADIENT_ONLY_IN_TITLE or __theme_istitle) and THREE_D_GRADIENT or false
   __theme_istitle = false

   if right > 0 then
      right = right + 1
   end
   if bottom > 0 then
      bottom = bottom + 1
   end

   if gradient and (THREE_D_GRADIENT_FIRST == THREE_D_GRADIENT_SECOND) then
      gradient = false
   end

   if (gradient == 1) or (gradient == 2) or (gradient == 3) then
      WindowGradient(win, left, top, right, bottom,
                THREE_D_GRADIENT_FIRST,
                THREE_D_GRADIENT_SECOND,
                gradient)
   else
      WindowRectOp(win, 2, left, top, right, bottom, THREE_D_GRADIENT_FIRST)
   end

   if not depressed then
      WindowLine(win, left+1, top+1, right, top+1, THREE_D_HIGHLIGHT, 0x0200, 1)
      WindowLine(win, left+1, top+1, left+1, bottom, THREE_D_HIGHLIGHT, 0x0200, 1)

      WindowLine(win, left, bottom-2, right, bottom-2, THREE_D_SOFTSHADOW, 0x0200, 1)
      WindowLine(win, right-2, top, right-2, bottom-2, THREE_D_SOFTSHADOW, 0x0200, 1)

      WindowLine(win, left, bottom-1, right, bottom-1, THREE_D_HARDSHADOW, 0x0200, 1)
      WindowLine(win, right-1, top, right-1, bottom-1, THREE_D_HARDSHADOW, 0x0200, 1)
   else
      WindowLine(win, left, top+1, right, top+1, THREE_D_HARDSHADOW, 0x0200, 1)
      WindowLine(win, left+1, top, left+1, bottom, THREE_D_HARDSHADOW, 0x0200, 1)

      WindowLine(win, left, top, right, top, THREE_D_HARDSHADOW, 0x0200, 1)
      WindowLine(win, left, top, left, bottom, THREE_D_HARDSHADOW, 0x0200, 1)
   end
end

function Draw3DTextBox(win, font, left, top, text, utf8, depressed, x_padding, y_padding, width, height)
   x_padding = x_padding or 0
   y_padding = y_padding or 0
   text = text or ""
   local text_width = WindowTextWidth(win, font, text, utf8)
   local text_height = WindowFontInfo(win, font, 1)
   if width then
      right = left + width
   else
      right = (left + text_width + (2*x_padding) + 4)
   end
   if height then
      bottom = top + height
   else
      bottom = (top + text_height + (2*y_padding)) + 2
   end
   Draw3DRect(win, left, top, right, bottom, depressed)
   local offset = 0
   if depressed then
      offset = 2
   end
   local text_left = math.max(left + 2, (left + right - text_width)/2)
   local text_top = math.max(top, (top + bottom + 2 - text_height)/2)
   WindowText(win, font, text, text_left + offset, text_top + offset, right-1, bottom-1, THREE_D_SURFACE_DETAIL, utf8)
   return right, bottom
end

function DrawTextBox(win, font, left, top, text, utf8, outlined, bgcolor, textcolor, x_padding, y_padding)
   if nil == bgcolor then
      bgcolor = CLICKABLE
   end
   if nil == textcolor then
      textcolor = CLICKABLE_TEXT
   end
   x_padding = x_padding or 0
   y_padding = y_padding or 0
   local right = left + WindowTextWidth(win, font, text, utf8) + 4 + (2*x_padding)
   local bottom = top + WindowFontInfo(win, font, 1) + (2*y_padding)
   WindowRectOp(win, 2, left, top+1, right, bottom+2, bgcolor)
   if outlined then
      WindowRectOp(win, 1, left-1, top, right+1, bottom+3, textcolor)
   end
   WindowText(win, font, text, left+2, top+1, right, bottom+1, textcolor, utf8)
   return right-left
end

Theme.button_callbacks = {}
Theme.button_metrics = {}
function Add3DTextButton(win, button_id, font, left, top, text, utf8, x_padding, y_padding, tooltip, mousedown_callback, mouseup_callback, width, height)
   if type(win) == "table" then
      win = win.id
   end
   x_padding = x_padding or VERTICAL_BUTTON_PADDING or DYNAMIC_BUTTON_PADDING
   y_padding = y_padding or HORIZONTAL_BUTTON_PADDING or DYNAMIC_BUTTON_PADDING
   local right, bottom = Draw3DTextBox(win, font, left, top, text, utf8, false, x_padding, y_padding, width, height)
   Theme.button_metrics[button_id] = {win, font, left, top, text, utf8, x_padding, y_padding, width, height}
   Theme.button_callbacks[button_id] = {mousedown_callback=mousedown_callback, mouseup_callback=mouseup_callback}
   if WindowMoveHotspot(win, button_id, left, top, right, bottom) ~= 0 then
      WindowAddHotspot(win, button_id, left, top, right, bottom, nil, nil, "Theme.ThreeDeeTextButtonMouseDown", "Theme.ThreeDeeTextButtonMouseCancel", "Theme.ThreeDeeTextButtonMouseUp", tooltip, 1, 0)
   end
   return right, bottom
end

function ThreeDeeTextButtonMouseDown(flags, hotspot_id)
   local callbacks = Theme.button_callbacks[hotspot_id]
   local win, font, left, top, text, utf8, x_padding, y_padding, width, height= unpack(Theme.button_metrics[hotspot_id])
   if callbacks.mousedown_callback then
      if callbacks.mousedown_callback(flags, hotspot_id) then
         return
      end
   end
   Draw3DTextBox(win, font, left, top, text, utf8, true, x_padding, y_padding, width, height)
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function ThreeDeeTextButtonMouseUp(flags, hotspot_id)
   local callbacks = Theme.button_callbacks[hotspot_id]
   local win, font, left, top, text, utf8, x_padding, y_padding, width, height = unpack(Theme.button_metrics[hotspot_id])
   Draw3DTextBox(win, font, left, top, text, utf8, false, x_padding, y_padding, width, height)
   if callbacks.mouseup_callback then
      callbacks.mouseup_callback(flags, hotspot_id)
   end
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function ThreeDeeTextButtonMouseCancel(flags, hotspot_id)
   local win, font, left, top, text, utf8, x_padding, y_padding, width, height = unpack(Theme.button_metrics[hotspot_id])
   Draw3DTextBox(win, font, left, top, text, utf8, false, x_padding, y_padding, width, height)
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function AddResizeTag(win, type, x1, y1, mousedown_callback, dragmove_callback, dragrelease_callback)
   local x1, y1 = DrawResizeTag(win, type, x1, y1)

   -- Add handler hotspots
   local hs = win.."_resize"
   if WindowMoveHotspot(win, hs, x1, y1, 0, 0) ~= 0 then
      WindowAddHotspot(win, hs, x1, y1, 0, 0, nil, nil, mousedown_callback, nil, nil, "", 6, 0)
      WindowDragHandler(win, hs, dragmove_callback, dragrelease_callback, 0)
   end

   return x1, y1
end

function DrawResizeTag(win, type, x1, y1)
   local x2, y2
   if not (x1 and y1) then
      x2 = WindowInfo(win, 3) - 3
      y2 = WindowInfo(win, 4) - 3
      x1 = x2 - RESIZER_SIZE + 1
      y1 = y2 - RESIZER_SIZE + 1
   else
      x2 = x1 + RESIZER_SIZE
      y2 = y1 + RESIZER_SIZE
   end

   local m = 2
   local n = 2
   if (type == 2) or (type == "full") then
      Draw3DRect(win, x1, y1, x2, y2, false)
      while (x1+m < x2 and y1+n+1 < y2) do
         WindowLine(win, x1+m-1, y2-2, x2-1, y1+n-2, THREE_D_HIGHLIGHT, 0, 1)
         WindowLine(win, x1+m, y2-2, x2-1, y1+n-1, THREE_D_HARDSHADOW, 0, 1)
         WindowLine(win, x1+m+1, y2-2, x2-1, y1+n, THREE_D_GRADIENT_FIRST, 0, 1)
         m = m+3
         n = n+3
      end
      WindowSetPixel(win, x2-2, y2-2, THREE_D_HIGHLIGHT)
   else
      while (x1+m < x2 and y1+n+1 < y2) do
         WindowLine(win, x1+m, y2-1, x2, y1+n-1, THREE_D_HIGHLIGHT, 0, 1)
         WindowLine(win, x1+m+1, y2-1, x2, y1+n, THREE_D_HARDSHADOW, 0, 1)
         WindowLine(win, x1+m+2, y2-1, x2, y1+n+1, THREE_D_GRADIENT_FIRST, 0, 1)
         m = m+3
         n = n+3
      end
      WindowLine(win, x1, y2, x2, y2, THREE_D_HARDSHADOW, 0, 1)
      WindowLine(win, x2, y1, x2, y2+1, THREE_D_HARDSHADOW, 0, 1)
      WindowSetPixel(win, x2-1, y2-1, THREE_D_HIGHLIGHT)
   end
   return x1, y1
end

function TextHeight(win, font)
   return WindowFontInfo(win, font, 1)
end

-- title_alignment can be "left", "right", or "center" (the default)
function DressWindow(win, font, title, title_alignment, title_leftpadding)
   local l, t, r, b = DrawBorder(win)

   local handler_bottom = 0
   if title and ((type(title) == "string") or (#title > 0)) then
      t = DrawTitleBar(win, font, title, title_alignment, title_leftpadding)
      handler_bottom = t
   end

   if WindowMoveHotspot(win, "zz_mw_" .. win .. "_movewindow_hotspot", 0, 0, 0, handler_bottom) ~= 0 then
      movewindow.add_drag_handler(win, 0, 0, 0, t)
   end

   return l, t, r, b
end

function BodyMetrics(win, font, title_line_height, num_title_lines)
   local l, t, r, b = BorderMetrics(win)
   local title_height = 0
   if num_title_lines > 0 then
      if title_line_height == nil then
        return (2*TITLE_PADDING)
      end
      title_height = (2*TITLE_PADDING) + (title_line_height * num_title_lines) + 1
      t = title_height + 1
   end
   return title_height, l, t, r, b
end


function ToMultilineStyles(msg)
   if type(msg) == "string" then
      msg = ColoursToStyles(msg, Theme.THREE_D_SURFACE_DETAIL, nil, true, true)
   elseif type(msg) == "table" then
      if msg.text then  -- single style, wrap in line and container
         msg = {{msg}}
      elseif msg[1] then
         if msg[1].text then  -- single line, wrap in container
            msg = {msg}
         elseif msg[1][1] then
            if msg[1][1].text or (msg[1][1][1] == nil) then  -- already multiline styles (probably)
               return msg
            else
               return nil
            end
         end
      else  -- empty
         msg = {{{}}}
      end
   else 
      return nil
   end
   return msg
end


function DrawTitleBar(win, font, title, title_alignment, title_leftpadding, utf8)
   local title_lines = ToMultilineStyles(title)
   assert(title_lines, "Title must be a string, table of styles, or table of tables of styles.")

   local title_line_height = WindowFontInfo(win, font, 1)
   local title_height, l, t, r, b = BodyMetrics(win, font, title_line_height, #title_lines)

   __theme_istitle = true
   Draw3DRect(win, -1, -1, WindowInfo(win, 3)-1, title_height, false)

   local first_color = nil
   local txt = nil
   for i,styles in ipairs(title_lines) do
      local text_width = StylesWidth (win, font, nil, styles, false, utf8)

      title_leftpadding = title_leftpadding or 0
      local text_left = math.max(TITLE_PADDING + l + title_leftpadding, (WindowInfo(win, 3) - text_width) / 2)  -- default text align center
      if title_alignment == "left" then
         text_left = TITLE_PADDING + l + title_leftpadding
      elseif title_alignment == "right" then
         text_left = WindowInfo(win, 3) - text_width - TITLE_PADDING
      end
      local text_right = WindowInfo(win, 3) - TITLE_PADDING

      local text_top = (title_line_height * (i-1)) + TITLE_PADDING
      WindowTextFromStyles(win, font, styles, text_left, text_top, text_right, title_height, utf8)
   end
   return title_height+1
end

function BorderMetrics(win)
   return 2, 2, WindowInfo(win, 3)-3, WindowInfo(win, 4)-3
end

function DrawBorder(win)
   WindowRectOp(win, 1, 0, 0, 0, 0, THREE_D_HIGHLIGHT)
   WindowRectOp(win, 1, 1, 1, -1, -1, THREE_D_SOFTSHADOW)
   return BorderMetrics(win)
end

function OutlinedText(win, font, text, startx, starty, endx, endy, color, outline_color, utf8, thickness)
   if thickness == nil then
      thickness = 1
   end
   if outline_color == nil then
      outline_color = THREE_D_HARDSHADOW
   end
   local right = nil
   for xi = -thickness,thickness do
      for yi = -thickness,thickness do
         right = WindowText(win, font, text, startx+xi, starty+yi, endx+1, endy+1, outline_color, utf8)
      end
   end
   -- local right = WindowText(win, font, text, startx+1, starty+1, endx, endy, outline_color, utf8)
   WindowText(win, font, text, startx, starty, endx, endy, color, utf8)
   return right
end

function WindowTextFromStyles(win, font, styles, left, top, right, bottom, utf8)
   for i,v in ipairs(styles) do
      left = left + WindowText(win, font, v.text, left, top, right, bottom, v.textcolour or BODY_TEXT, utf8)
   end
   return left
end

-- text with a black outline
function OutlinedTextFromStyles(win, font, styles, startx, starty, endx, endy, outline_color, utf8, thickness)
   if thickness == nil then
      thickness = 1
   end
   if outline_color == nil then
      outline_color = THREE_D_HARDSHADOW
   end
   local text = strip_colours_from_styles(styles)
   local right = nil
   for xi = -thickness,thickness do
      for yi = -thickness,thickness do
         right = WindowText(win, font, text, startx+xi, starty+yi, endx+1, endy+1, outline_color, utf8)
      end
   end
   WindowTextFromStyles(win, font, styles, startx, starty, endx, endy, utf8)
   return right
end

-- Based on mw.lua's popup function, but with theme colors
function Popup(win,   -- window name to use
   font_id,           -- font to use for each body line
   info,              -- table of lines to show (plain text or styles)
   left, top,         -- preferred location
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
   --    left = left - infowidth
   -- end -- if align_right

   -- if align_bottom then
   --    top = top - infoheight
   -- end -- if align_bottom

   top = math.min(top, GetInfo(280) - infoheight)
   top = math.max(0, top)
   if left < stay_left_of then
      if left+infowidth > stay_left_of then
         left = stay_left_of - infowidth
      end
      if left < 0 then
         left = stay_right_of
      end
   else
      if left < stay_right_of then
         left = stay_right_of
      end
      if (left + infowidth) > GetInfo(281) then
         left = stay_left_of - infowidth
      end
   end
   WindowCreate(win,
      left, top,    -- where
      infowidth,    -- width  (gap of 5 pixels per side)
      infoheight,   -- height
      miniwin.pos_top_left,  -- position mode: can't be 0 to 3
      miniwin.create_absolute_location + miniwin.create_transparent,
      SECONDARY_BODY)

   WindowCircleOp(win, miniwin.circle_round_rectangle,
      BORDER_WIDTH, BORDER_WIDTH, -BORDER_WIDTH, -BORDER_WIDTH,  -- border inset
      THREE_D_HIGHLIGHT, miniwin.pen_solid, BORDER_WIDTH,  -- line
      PRIMARY_BODY, miniwin.brush_solid,          -- fill
      5, 5)  -- diameter of ellipse

   local x = BORDER_WIDTH + WindowFontInfo (win, font_id, 6) / 2    -- start 1/2 character in
   local y = BORDER_WIDTH + 5          -- skip border, and leave 5 pixel gap

   -- show each line
   for _, line in ipairs(info) do
      if type(line) == "string" then
         WindowText(win, font_id, line, x, y, 0, 0, BODY_TEXT)
      else
         WindowTextFromStyles(win, font_id, line, x, y, 0, 0)
      end

      y = y + font_height
   end -- for

   -- display popup window
   WindowShow(win, true)
end -- popup
