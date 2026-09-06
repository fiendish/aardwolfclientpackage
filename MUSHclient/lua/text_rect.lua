-- Small bits of this code and ideas were borrowed and remixed from the MUSHclient community. https://www.mushclient.com/forum/?id=9385 and others.

require "wait"
require "copytable"
require "colors"
require "mw_theme_base"
local socket = require "socket"
local window_font_fallback = require "window_font_fallback"

dofile (GetInfo(60) .. "aardwolf_colors.lua")

local function getHighlightColor(bg)
   local h, s, l = colors.rgb_string_to_hsl(string.format('#%06x', bg))
   if l >= 0.5 then
      bgr = {colors.hsl_to_rgb(h, s, l/2)}
      local buffer = "0x"
      for i,v in ipairs(bgr) do
         buffer = buffer..string.format("%02x",math.floor(v*255+0.5))
      end
      return tonumber(buffer)
   else
      return bg+0x444444
   end
end

TextRect = {
   hotspot_map = {}
}
TextRect_defaults = {
   raw_lines = {},
   wrapped_lines = {},
   max_lines = 1000,
   font_name = "Dina",
   font_size = 10,
   start_line = 1,
   display_start_line = 1,
   end_line = 1,
   display_end_line = 1,
   num_raw_lines = 0,
   num_wrapped_lines = 0,
   keepscrolling = "",
   padding = 5,
   background_color = 0x000000,
   highlight_color = getHighlightColor(0x000000),
   show_scrollback_marker = true
}
TextRect_mt = { __index = TextRect }

function TextRect.new(
   window, name, left, top, right, bottom, max_lines, scrollable, background_color,
   padding, font_name, font_size, external_scroll_handler, call_on_select,
   unselectable, uncopyable, no_url_hyperlinks, no_autowrap,
   menu_generator_function, line_spacing
)
   new_tr = setmetatable(copytable.deep(TextRect_defaults), TextRect_mt)
   new_tr.id = "TextRect_"..window.."_"..name
   new_tr.window = window
   new_tr.name = name
   new_tr:configure(
      left, top, right, bottom, max_lines, scrollable, background_color,
      padding, font_name, font_size, external_scroll_handler, call_on_select,
      unselectable, uncopyable, no_url_hyperlinks, no_autowrap,
      menu_generator_function, line_spacing)
   return new_tr
end

function TextRect:set_bgcolor(bgcolor)
   if bgcolor ~= self.background_color then
      self.background_color = bgcolor or self.background_color
      self.highlight_color = getHighlightColor(self.background_color)
   end
end

function TextRect:setLineSpacing(line_spacing)
   self.line_spacing = line_spacing
   -- Calculate line_height: use line_spacing if configured, otherwise font's natural height
   -- line_spacing of 0 or nil means use font's natural height
   if self.line_spacing and self.line_spacing > 0 then
      self.line_height = self.line_spacing
   else
      self.line_height = self.font_height
   end
   if self.padded_height then
      -- Keep this calculation consistent with setRect.
      self.rect_lines = math.floor((self.padded_height + (self.line_height / 3)) / self.line_height)
   end
end

function TextRect:configure(
   left, top, right, bottom, max_lines, scrollable, background_color,
   padding, font_name, font_size, external_scroll_handler, call_on_select,
   unselectable, uncopyable, no_url_hyperlinks, no_autowrap,
   menu_generator_function, line_spacing
)
   self:setExternalMenuFunction(menu_generator_function)
   self.scrollable = scrollable
   self.external_scroll_handler = external_scroll_handler
   self.call_on_select = call_on_select
   self.padding = padding or self.padding
   self.max_lines = max_lines or self.max_lines
   self.font_name = font_name or self.font_name
   self.font_size = font_size or self.font_size
   self.line_spacing = line_spacing  -- nil means use font metrics only
   self.no_autowrap = no_autowrap
   self.unselectable = unselectable
   self.uncopyable = uncopyable
   self.no_url_hyperlinks = no_url_hyperlinks
   self:set_bgcolor(background_color)
   self:loadFont(self.font_name, self.font_size)
   self:setRect(left, top, right, bottom)
end

-- Load the normal and bold fonts used by this TextRect. Optional input styles
-- let callers match another MUSHclient font without loading it themselves.
function TextRect:loadFont(name, size, options)
   options = options or {}
   name = name or self.font_name or TextRect_defaults.font_name
   size = tonumber(size or self.font_size) or TextRect_defaults.font_size
   local bold = options.bold == true
   local italic = options.italic == true
   local charset = tonumber(options.charset) or 0
   local pitch_and_family = tonumber(options.pitch_and_family) or miniwin.font_pitch_default
   local reload_token = options.reload_token
   local changed =
      not self.font or
      name ~= self.font_name or
      size ~= self.font_size or
      bold ~= self.font_is_bold or
      italic ~= self.font_is_italic or
      charset ~= self.font_charset or
      pitch_and_family ~= self.font_pitch_and_family or
      reload_token ~= self.font_reload_token

   if not changed then
      return false
   end

   self.font = self.id.."_font"
   self.font_bold = self.id.."_font_bold"
   local fallback_name = self.loaded_font_name or TextRect_defaults.font_name
   local fallback_size = self.loaded_font_size or TextRect_defaults.font_size
   local loaded_name, loaded_size = window_font_fallback.ensure_font(
      self.window,
      self.font,
      name,
      size,
      fallback_name,
      fallback_size,
      bold,
      italic,
      false,
      false,
      charset,
      pitch_and_family)
   window_font_fallback.ensure_font(
      self.window,
      self.font_bold,
      loaded_name,
      loaded_size,
      fallback_name,
      fallback_size,
      true,
      italic,
      false,
      false,
      charset,
      pitch_and_family)

   self.font_name = name
   self.font_size = size
   self.font_is_bold = bold
   self.font_is_italic = italic
   self.font_charset = charset
   self.font_pitch_and_family = pitch_and_family
   self.font_reload_token = reload_token
   self.loaded_font_name = loaded_name
   self.loaded_font_size = loaded_size
   self.font_height = WindowFontInfo(self.window, self.font, 1)
   self:setLineSpacing(self.line_spacing)
   return true
end

-- Returns an array {start, end, text}
function TextRect:findURLs(text)
   local URLs = {}
   local start, position = 0, 0
   -- "rex" is a table supplied by MUSHclient for PCRE functionality.
   local re = rex.new("(?:https?://|mailto:)\\S*[\\w/=@#\\-\\?]")
   re:gmatch(text,
      function (link, _)
         start, position = string.find(text, link, position, true)
         table.insert(URLs, {start=start, stop=position, text=link})
      end
   )
   return URLs
end -- function findURL

function TextRect:textWidth(styles_or_color_coded_text)
   local width = 0
   for _, styles in ipairs(ToMultilineStyles(styles_or_color_coded_text, nil, nil, true)) do
      width = math.max(width, self:styles_width(styles))
   end
   return width
end

function TextRect:addText(message, hyperlinks)
   for i, message in ipairs(ToMultilineStyles(message, Theme.BODY_TEXT, nil, true)) do
      -- extract URLs so we can add our movespots later
      local links = {}
      if hyperlinks then
         if (hyperlinks[i] == nil) or ((type(hyperlinks[i]) == "table") and ((next(hyperlinks[i]) == nil) or (#hyperlinks[i] > 1))) then
            links = copytable.deep(hyperlinks[i] or {})
         else
            links = copytable.deep(hyperlinks)
         end
      end
      if not self.no_url_hyperlinks then
         for _,v in ipairs(self:findURLs(strip_colours_from_styles(message))) do
            table.insert(links, v)
         end
      end

      -- pop the oldest line from our buffer if we're at capacity
      if self.max_lines > 0 and self.num_raw_lines >= self.max_lines then
         table.remove(self.raw_lines, 1)
         self.num_raw_lines = self.num_raw_lines - 1
      end

      -- add to raw lines table
      table.insert(self.raw_lines, {[1]=message, [2]=links})
      self.num_raw_lines = self.num_raw_lines + 1

      -- add to wrapped lines table for display
      self:wrapLine(message, links, self.num_raw_lines)
   end
end

function TextRect:addColorLine(line, hyperlinks)
   self:addText(line, hyperlinks)
end

function TextRect:addStyles(styles, hyperlinks)
   self:addText(styles, hyperlinks)
end

function TextRect:doUpdateCallbacks()
   if self.update_callbacks then
      for _, cb in ipairs(self.update_callbacks) do
         local obj = cb[1]
         local func = cb[2]
         func(obj, self.display_start_line, self.rect_lines, self.num_wrapped_lines)
      end
   end
end

function TextRect:cap_messages()
   if self.max_lines > 0 and self.num_wrapped_lines >= self.max_lines then
      -- if the history buffer is full then remove the oldest line
      table.remove(self.wrapped_lines, 1)
      self.num_wrapped_lines = self.num_wrapped_lines - 1
      self.start_line = math.max(1, self.start_line - 1)
      self.end_line = math.max(1, self.end_line - 1)
      self.display_start_line = math.max(1, self.display_start_line - 1)
      self.display_end_line = math.max(1, self.display_end_line - 1)
      if self.copy_start_line then
         self.copy_start_line = math.max(0, self.copy_start_line - 1)
         self.copy_end_line = math.max(self.copy_start_line, self.copy_end_line - 1)
      end
   end -- buffer full
end

function TextRect:lockstep()
   -- scroll down if viewing the bottom
   if self.end_line == self.num_wrapped_lines then
      if self.end_line >= self.rect_lines then
         self.start_line = self.start_line + 1
         self.display_start_line = self.start_line
      end
      self.end_line = self.end_line + 1
      self.display_end_line = self.end_line
   end
end

function TextRect:wrapLine(stylerun, rawURLs, raw_index)
   local available = self.padded_width
   local line_styles = {}
   local beginning = true
   local length = 0
   local raw_offset = 0
   local styles = copytable.deep(stylerun)
   local urls = copytable.deep(rawURLs)

   local remove = table.remove
   local insert = table.insert
   local sub = string.sub
   local find = string.find
   local show_bold = (GetOption("show_bold")==1)
   local utf = (GetOption("utf_8") == 1)

   -- Keep pulling out styles and trying to fit them on the current line
   while #styles > 0 do
      -- break off the next style
      local style = remove(styles, 1)

      local font = self.font
      if style.bold and show_bold then
         font = self.font_bold
      end
      local t = style.text
      local t_width = WindowTextWidth(self.window, font, t, utf and utils.utf8valid(t))

      -- if it fits, copy whole style in
      -- also if literally no room for anything, just wedge the whole style in because that's silly
      t = sub(style.text, 1, 1)
      if self.no_autowrap or (t_width <= available) or ((length == 0) and (WindowTextWidth(self.window, font, t, utf and utils.utf8valid(t)) > available)) then
         if style.length > 0 then
            insert(line_styles, style)
         end
         length = length + style.length
         available = available - t_width
      else -- otherwise, have to split style
         -- look for spaces to break at
         local col = 2
         local fit_col = nil
         while col < style.length do
            if sub(style.text, col, col) == " " then
               t = sub(style.text, 1, col-1)
               t_width = WindowTextWidth(self.window, font, t, utf and utils.utf8valid(t))
               if t_width > available then
                  break
               else
                  fit_col = col -- found a space where we can split
               end
            end
            col = col + 1
         end
         if not fit_col then -- no spaces available for split
            if available == self.padded_width then -- starts at the beginning of the line
               -- step backward from the last measured col
               while col > 1 do
                  t = sub(style.text, 1, col)
                  t_width = WindowTextWidth(self.window, font, t, utf and utils.utf8valid(t))
                  if t_width <= available then
                     fit_col = col
                     break
                  end
                  col = col - 1
               end
            end
         end

         if fit_col then
            -- if we found a place to split, truncate the style and put the rest
            -- back into the styles list
            local style_left = copytable.shallow(style)
            style.text = sub(style.text, 1, fit_col)
            style.length = fit_col
            style_left.text = sub(style_left.text, fit_col + 1)
            style_left.length = style_left.length - fit_col
            if style.length > 0 then
               insert(line_styles, style)
            end
            insert(styles, 1, style_left)
            length = length + style.length
         else
            -- put the style back for the next line
            insert(styles, 1, style) -- put style back for the next line
         end -- if
         available = 0 -- now we need to wrap
      end -- if could/not fit whole thing in

      -- out of styles or out of room? add a line for what we have so far
      if ((available <= 0) and not self.no_autowrap) or (#styles == 0) then
         self:cap_messages()

         local line_urls = {}
         while urls[1] and urls[1].stop <= length do
            insert(line_urls, remove(urls, 1))
         end

         if urls[1] and urls[1].start < length then
            local url = copytable.deep(urls[1])
            url.stop = length + 1
            urls[1].old = true
            insert(line_urls, url)
         end

         for i,v in ipairs(urls) do
            urls[i].start = urls[i].start - length
            urls[i].stop = urls[i].stop - length
            if urls[i].start <= 1 then
               urls[i].start = 1
            end
         end

         self:lockstep()

         -- add new wrapped line component
         self.num_wrapped_lines = self.num_wrapped_lines + 1
         local raw_index_delta = self.num_wrapped_lines - raw_index
         table.insert(self.wrapped_lines, {
            [1]=line_styles,
            [2]=beginning,
            [3]=line_urls,
            [4]=raw_index_delta,
            raw_offset=raw_offset,
            text_length=length
         })
         raw_offset = raw_offset + length

         -- prep for next line
         available = self.padded_width
         line_styles = {}
         length = 0
         beginning = false
      end -- line full
   end -- while we still have styles left
end

local function current_raw_line(line_number, line)
   return line_number - line[4]
end

function TextRect:clear(draw_after)
   local draw_after = (draw_after == nil) or (draw_after == true)
   self.raw_lines = {}
   self.num_raw_lines = 0
   self:reWrapLines()
   if draw_after then
      self:draw()
   end
end

function TextRect:debug(when)
   require "pairsbykeys"
   print("ERROR in `"..when.."`: SEND THIS TO FIENDISH")
   for k,v in pairsByKeys(self) do print(k, "--", v) end
   print()
end

function TextRect:reWrapLines()
   local raw_index = 0
   -- wrapLine messes with the start position, so track a temporary variable
   -- for start_line instead of self.start_line
   local start_line = math.max(1, self.display_start_line or 1) -- easier than finding where it goes negative

   if self.num_wrapped_lines ~= 0 then
      if self.wrapped_lines[start_line] == nil then
         self:debug("reWrapLines")
      end
      raw_index = current_raw_line(start_line, self.wrapped_lines[start_line])
   end

   self.wrapped_lines = {}
   self.num_wrapped_lines = 0
   for i, line in ipairs(self.raw_lines) do
      if i == raw_index then
         start_line = self.num_wrapped_lines + 1
      end
      self:wrapLine(line[1], line[2], i)
   end

   self.start_line = start_line
   self.start_line, self.end_line = self:snapToBottom()
   self.display_start_line = self.start_line
   self.display_end_line = self.end_line
end

function TextRect:drawLine(line, styles, selection_start, selection_end, utf8, show_bold)
   local left = self.padded_left
   local top = self.padded_top + (line * self.line_height) + 1

   -- selection backfill
   if (selection_start ~= nil) and (selection_end ~= nil) then
      WindowRectOp(self.window, 2, selection_start, top, selection_end-1, top + self.line_height, self.highlight_color)
   end

   -- text colors
   for _, v in ipairs(styles) do
      local t = v.text
      local is_utf = utf8 and utils.utf8valid(t)
      local font = self.font
      if show_bold and v.bold then
         font = self.font_bold
      end

      -- background
      if v.backcolour and (v.backcolour ~= 0) then
         local bgwidth = WindowTextWidth(self.window, font, t, is_utf)
         local bgleft = left
         local bgright = left + bgwidth

         -- The different scenarios for interaction between bgcolor and selection color are:
         --     S
         --   BBBBB
         --  SSS SSS
         --  SSSSSSS
         if (selection_start ~= nil) and (selection_end ~= nil) then
            if (bgleft <= selection_start) and (bgright >= selection_end) then
               WindowRectOp(self.window, 2, bgleft, top, math.min(self.padded_right, selection_start), math.min(self.padded_bottom, top + self.line_height), v.backcolour)
               bgleft = selection_end
            else
               if (bgleft >= selection_start) and (bgleft <= selection_end) then
                  bgleft = selection_end
               end
               if (bgright >= selection_start) and (bgright <= selection_end) then
                  bgright = selection_start
               end
            end
         end
         if bgleft < bgright then
            WindowRectOp(self.window, 2, bgleft, top, math.min(self.padded_right, bgright), math.min(self.padded_bottom, top + self.line_height), v.backcolour)
         end
      end

      -- foreground
      left = left + WindowText(self.window, font, t, left, top, self.padded_right, self.padded_bottom, v.textcolour, is_utf)
   end
end

function TextRect:styles_width(styles, show_bold)
   if show_bold == nil then
      show_bold = (GetOption("show_bold")== 1)
   end
   return StylesWidth(self.window, self.font, self.font_bold, styles, show_bold)
end

function TextRect:set_cursor(line_number, offset, visible, show_bold)
   self.cursor = {
      line = line_number,
      offset = offset,
      visible = visible == true,
      show_bold = show_bold
   }
end

function TextRect:set_column_guide(column)
   self.column_guide = {
      column = column
   }
end

function TextRect:draw_column_guide()
   if not self.column_guide then
      return
   end

   local character_width = WindowFontInfo(self.window, self.font, 6)
   local x = self.padded_left + (self.column_guide.column * character_width)
   if x > self.padded_left and x < self.padded_right then
      WindowLine(
         self.window,
         x,
         self.padded_top,
         x,
         self.padded_bottom - 1,
         Theme.THREE_D_HIGHLIGHT,
         miniwin.pen_dot,
         1)
   end
end

function TextRect:draw_cursor()
   local cursor = self.cursor
   if not cursor or not cursor.visible then
      return
   end
   if cursor.line < self.display_start_line or cursor.line > self.display_end_line then
      return
   end

   local line = self.wrapped_lines[cursor.line]
   if not line then
      return
   end
   local offset = math.max(0, math.min(cursor.offset or 0, self:line_length(cursor.line)))
   local before_cursor = TruncateStyles(line[1], 0, offset)
   local show_bold = cursor.show_bold
   if show_bold == nil then
      show_bold = (GetOption("show_bold") == 1)
   end
   local utf8 = (GetOption("utf_8") == 1)
   local x = self.padded_left + StylesWidth(
      self.window,
      self.font,
      self.font_bold,
      before_cursor,
      show_bold,
      utf8)
   local top = self.padded_top + ((cursor.line - self.display_start_line) * self.line_height) + 1
   WindowLine(
      self.window,
      x,
      top,
      x,
      math.min(self.padded_bottom, top + self.line_height - 1),
      Theme.BODY_TEXT,
      miniwin.pen_solid,
      1)
end

function TextRect:draw(cleanup_first, inside_callback)
   if cleanup_first ~= false then -- default true
      self:_deleteHyperlinks()
   end

   if not self.area_hotspot then
      self:initArea()
   end
   WindowRectOp(self.window, 2, self.left, self.top, self.right, self.bottom+1, self.background_color) -- clear
   local ax = nil
   local zx = nil
   local line_styles = {}
   local count = 0
   self.display_start_line, self.display_end_line = self:snapToBottom()
   if self.num_wrapped_lines >= 1 then
      local show_bold = (GetOption("show_bold")== 1)
      local utf8 = (GetOption("utf_8") == 1)
      for count = self.display_start_line, self.display_end_line do
         ax = nil
         zx = nil
         line_styles = self.wrapped_lines[count][1]
         if self.keepscrolling == "" then
            -- create clickable links
            for _,url_part in ipairs(self.wrapped_lines[count][3]) do
               -- bold widths in links. replacement for: local left = self.padded_left + WindowTextWidth(self.window, self.font, string.sub(line_no_colors, 1, url_part.start-1))
               local left = self.padded_left + self:styles_width(TruncateStyles(line_styles, 0, url_part.start-1), show_bold)
               -- bold widths in links. replacement for: local right = left + WindowTextWidth(self.window, self.font, string.sub(line_no_colors, url_part.start-1, url_part.stop-1))
               local right = left + self:styles_width(TruncateStyles(line_styles, url_part.start, url_part.stop), show_bold)
               local top = self.padded_top + ((count - self.display_start_line) * self.line_height)-1
               local bottom = top + self.line_height
               local link_id = self:generateHotspotID(table.concat({url_part.text, " ", count, " ", url_part.start, " ", url_part.stop}))

               if not WindowHotspotInfo(self.window, link_id, 1) then
                  self.hyperlinks[link_id] = url_part.text
                  WindowAddHotspot(self.window, link_id, left, top, math.min(right, self.padded_right), bottom, "TextRect.linkHover", "TextRect.cancelLinkHover", "TextRect.clickUrl", "", "TextRect.mouseUp", url_part.label or ("Right-click this URL if you want to open it:\n"..url_part.text), 1)
                  if self.scrollable then
                     WindowScrollwheelHandler(self.window, link_id, "TextRect.wheelMove")
                  elseif self.external_scroll_handler then
                     WindowScrollwheelHandler(self.window, link_id, self.external_scroll_handler)
                  end
               end
            end
         end

         local line_length = self.padded_left + self:styles_width(line_styles, show_bold)

         -- create highlighting parameters when text is selected
         if self.copy_start_line ~= nil and self.copy_end_line ~= nil and count >= self.copy_start_line and count <= self.copy_end_line then
            ax = (
               (count == self.copy_start_line)
               and self.start_copying_x
               and math.min(self.start_copying_x, line_length)
               or self.padded_left
            )
            -- end of highlight for this line
            zx = math.min(
               self.padded_right,
               (
                  (count == self.copy_end_line)
                  and self.end_copying_x
                  and math.min(self.end_copying_x, line_length)
                  or line_length
               )
            )
         end
         if ax == zx then
            ax = nil
            zx = nil
         end
         self:drawLine(count - self.display_start_line, self.wrapped_lines[count][1], ax, zx, utf8, show_bold)
      end
   end

   self:draw_column_guide()
   self:draw_cursor()

   if not inside_callback then
      self:doUpdateCallbacks()
   end
   
   self:underline_hyperlinks()

   if self.show_scrollback_marker ~= false then
      self:draw_scrollback_marker()
   end
end

function TextRect:draw_scrollback_marker()
   if self.display_end_line < self.num_wrapped_lines then
      local text = "Scroll down for more"
      local width = self:textWidth(text)
      local left = self.right - width - 15
      local top = self.bottom - WindowFontInfo(self.window, self.font, 1) + 1
      WindowCircleOp(self.window, 2, left, top, self.right-5, self.bottom+2, Theme.THREE_D_SOFTSHADOW, 0, 1, Theme.THREE_D_GRADIENT_FIRST, 0)
      WindowText(self.window, self.font, text, left+5, top, self.right-3, self.bottom, Theme.THREE_D_SURFACE_DETAIL, false)
   end
end

function TextRect:addUpdateCallback(object, callback)
   self.update_callbacks = self.update_callbacks or {}
   table.insert(self.update_callbacks, {object, callback})
end

function TextRect:snapToBottom()
   local start_line = math.max(1, math.min(self.start_line, self.num_wrapped_lines - self.rect_lines + 1))
   local end_line = math.max(1, math.min(start_line + self.rect_lines - 1, self.num_wrapped_lines))
   return start_line, end_line
end

function TextRect:setRect(left, top, right, bottom)
   self.left = left
   self.top = top
   self.right = right
   self.bottom = bottom + 1
   self.width = right-left
   self.height = bottom-top + 1
   self.padded_left = self.left + self.padding
   self.padded_top = self.top + self.padding
   self.padded_right = self.right - self.padding
   self.padded_bottom = self.bottom - self.padding
   self.padded_width = self.padded_right - self.padded_left
   self.padded_height = self.padded_bottom - self.padded_top
   if self.area_hotspot then
      WindowMoveHotspot(self.window, self.area_hotspot, self.left, self.top, self.right, self.bottom)
   end
   if self.line_height then
      -- add a third of a line before subdividing to make resizing a bit more comfortable
      self.rect_lines = math.floor((self.padded_height+(self.line_height/3)) / self.line_height)
   end
end

function TextRect:line_length(line_number)
   local line = self.wrapped_lines[line_number]
   if not line then
      return 0
   end
   return line.text_length
end

function TextRect:wrapped_to_raw(line_number, offset)
   local line = self.wrapped_lines[line_number]
   if not line then
      return
   end

   local raw_line = current_raw_line(line_number, line)
   offset = math.max(0, math.min(tonumber(offset) or 0, self:line_length(line_number)))
   return raw_line, line.raw_offset + offset
end

function TextRect:raw_to_wrapped(raw_line, offset)
   raw_line = tonumber(raw_line)
   if not raw_line then
      return
   end

   offset = math.max(0, tonumber(offset) or 0)
   local last_line

   for line_number, line in ipairs(self.wrapped_lines) do
      local line_raw = current_raw_line(line_number, line)
      if line_raw == raw_line then
         last_line = line_number
         local line_offset = line.raw_offset
         local line_length = self:line_length(line_number)
         local line_end = line_offset + line_length

         if offset < line_end then
            return line_number, math.max(0, offset - line_offset)
         end
         if offset == line_end then
            local next_line = self.wrapped_lines[line_number + 1]
            local next_raw = next_line and current_raw_line(line_number + 1, next_line)
            if next_raw == raw_line then
               return line_number + 1, 0
            end
            return line_number, line_length
         end
      elseif last_line and line_raw > raw_line then
         break
      end
   end

   if last_line then
      return last_line, self:line_length(last_line)
   end
end

function TextRect:ensure_visible(line_number)
   if self.num_wrapped_lines == 0 then
      return
   end

   line_number = math.max(1, math.min(tonumber(line_number) or 1, self.num_wrapped_lines))
   local visible_lines = math.max(1, self.rect_lines or 1)
   local start_line = self.start_line or 1
   if line_number < start_line then
      start_line = line_number
   elseif line_number >= start_line + visible_lines then
      start_line = line_number - visible_lines + 1
   end

   self.start_line = start_line
   self.start_line, self.end_line = self:snapToBottom()
   self.display_start_line = self.start_line
   self.display_end_line = self.end_line
end

function TextRect:getScroll()
   return self.start_line
end

function TextRect:setScroll(new_pos, no_draw_after)
   self.start_line = math.max(1, math.min(new_pos, self.num_wrapped_lines - self.rect_lines + 1))
   self.end_line = math.min(self.start_line + self.rect_lines - 1, self.num_wrapped_lines)
   self.display_start_line = self.start_line
   self.display_end_line = self.end_line
   if not no_draw_after then
      self:draw(true, true)
   end
end

-- Scroll through the window contents line by line. Used when dragging out of text area
function TextRect:scroll(dragging)
   wait.make(function ()
      while self.keepscrolling == "up" or self.keepscrolling == "down" do
         if self.keepscrolling == "up" then
            if (self.start_line > 1) then
               self.start_line = self.start_line - 1
               self.end_line = self.end_line - 1
               self.display_start_line = self.start_line
               self.display_end_line = self.end_line
            end
         elseif self.keepscrolling == "down" then
            if (self.end_line < self.num_wrapped_lines) then
               self.start_line = self.start_line + 1
               self.end_line = self.end_line + 1
               self.display_start_line = self.start_line
               self.display_end_line = self.end_line
            end
         end
         if dragging then
            self:updateSelect()
         else
            self:draw(false)
         end
         CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
         wait.time(0.01)
      end
   end)
end

function TextRect:initArea()
   --highlight, right click, scrolling
   self.area_hotspot = self:generateHotspotID("textarea")
   if (not self.unselectable) or self.scrollable or self.external_scroll_handler then
      if self.unselectable then
         WindowAddHotspot(self.window, self.area_hotspot, self.left, self.top, self.right, self.top + self.height, "", "", "", "", "TextRect.mouseUp", "", nil, 0)
      else
         WindowAddHotspot(self.window, self.area_hotspot, self.left, self.top, self.right, self.top + self.height, "", "", "TextRect.mouseDown", "TextRect.cancelMouseDown", "TextRect.mouseUp", "", miniwin.cursor_ibeam, 0)
         WindowDragHandler(self.window, self.area_hotspot, "TextRect.dragMove", "TextRect.dragRelease", 0x10)
      end
      if self.scrollable then
         WindowScrollwheelHandler(self.window, self.area_hotspot, "TextRect.wheelMove")
      elseif self.external_scroll_handler then
         WindowScrollwheelHandler(self.window, self.area_hotspot, self.external_scroll_handler)
      end
   end
   self.hyperlinks = {}
end

function TextRect:_deleteHyperlinks()
   if self.hyperlinks then
      for k, v in pairs(self.hyperlinks) do
         WindowDeleteHotspot(self.window, k)
         TextRect.hotspot_map[k] = nil
      end
   end
   self.hyperlinks = {}
end

function TextRect:unInit()
   -- unload all hotspots
   if self.area_hotspot then
      TextRect.hotspot_map[self.area_hotspot] = nil
      WindowDeleteHotspot(self.window, self.area_hotspot)
      self.area_hotspot = nil
   end
   self:_deleteHyperlinks()
end

function TextRect:get_target_bounds(separator_pattern, line_number, target_x, partition_cache_key)
   self.last_partitioned_styles = self.last_partitioned_styles or {}
   self.last_partitioned_line_sections = self.last_partitioned_line_sections or {}
   partition_cache_key = partition_cache_key or "default"
   target_x = math.min(math.max(target_x, self.padded_left), self.padded_right)
   local line = self.wrapped_lines[line_number]
   if not line then
      return
   end
   local line_styles = line[1]
   local show_bold = (GetOption("show_bold")== 1)
   if separator_pattern then
      if line_styles ~= self.last_partitioned_styles[partition_cache_key] then
         self.last_partitioned_styles[partition_cache_key] = line_styles
         self.last_partitioned_line_sections[partition_cache_key] = partition_boundaries(line_styles, separator_pattern)
      end
   else
      self.last_partitioned_line_sections[partition_cache_key] = {line_styles}
   end
   local section_start = self.padded_left
   local section_end = self.padded_left
   local start_pos = 0
   local end_pos = 0
   local utf = (GetOption("utf_8") == 1)
   for _,section in ipairs(self.last_partitioned_line_sections[partition_cache_key]) do
      local section_size = 0
      local section_length = 0
      for _,style in ipairs(section) do
         local font = self.font
         if show_bold and style.bold then
            font = self.font_bold
         end
         local t = style.text
         section_size = section_size + WindowTextWidth(self.window, font, t, utf and utils.utf8valid(t))
         section_length = section_length + style.length
      end
      section_end = section_start + section_size
      end_pos = start_pos + section_length
      if (section_start <= target_x) and (section_end >= target_x) then
         break
      end
      section_start = section_end
      start_pos = end_pos
   end
   return start_pos, end_pos, section_start, section_end
end

local function get_offset_bounds(styles, separator_pattern, target_offset)
   local start_pos = 0
   local end_pos = 0
   local last_start = 0
   local last_end = 0
   local sections = partition_boundaries(styles, separator_pattern)
   for _, section in ipairs(sections) do
      local section_length = 0
      for _, style in ipairs(section) do
         section_length = section_length + style.length
      end
      end_pos = start_pos + section_length
      last_start = start_pos
      last_end = end_pos
      if target_offset < end_pos then
         return start_pos, end_pos
      end
      start_pos = end_pos
   end
   return last_start, last_end
end

-- Convert miniwindow coordinates to a wrapped line and text offset.
-- Character hits use the nearest insertion boundary. Word hits use the raw
-- logical line, so their returned bounds can cross wrapped display lines.
function TextRect:hit_test(x, y, options)
   if self.num_wrapped_lines == 0 then
      return
   end

   options = options or {}
   local relative_line = math.floor((y - self.padded_top) / self.line_height)
   local display_start_line = math.max(1, self.display_start_line or 1)
   local first_line = 1
   local last_line = self.num_wrapped_lines
   if not options.allow_offscreen then
      first_line = display_start_line
      last_line = math.min(
         self.num_wrapped_lines,
         self.display_end_line or self.num_wrapped_lines)
   end
   local line_number = display_start_line + relative_line
   line_number = math.max(first_line, math.min(line_number, last_line))
   local unit = options.unit or "character"

   if unit == "line" then
      return {
         line = line_number,
         offset = 0,
         first_line = line_number,
         first_offset = 0,
         last_line = line_number,
         last_offset = self:line_length(line_number)
      }
   end

   if unit == "word" then
      local first =
         self:get_target_bounds(".", line_number, x, options.cache_key or "hit_test_character")
      if first == nil then
         return
      end

      local wrapped_offset = first
      local raw_line, raw_offset = self:wrapped_to_raw(line_number, wrapped_offset)
      local raw = raw_line and self.raw_lines[raw_line]
      if not raw then
         return
      end

      local raw_first, raw_last = get_offset_bounds(
         raw[1],
         options.separator_pattern or "[^%w%-]+",
         raw_offset)
      local first_line, first_offset = self:raw_to_wrapped(raw_line, raw_first)
      local last_line, last_offset = self:raw_to_wrapped(raw_line, raw_last)
      if not first_line or not last_line then
         return
      end

      return {
         line = line_number,
         offset = wrapped_offset,
         first_line = first_line,
         first_offset = first_offset,
         last_line = last_line,
         last_offset = last_offset
      }
   end

   local cache_key = options.cache_key or ("hit_test_" .. unit)
   local first, last, first_x, last_x =
      self:get_target_bounds(".", line_number, x, cache_key)
   if first == nil then
      return
   end

   local offset = first
   if unit == "character" and x >= first_x + ((last_x - first_x) / 2) then
      offset = last
   end

   return {
      line = line_number,
      offset = offset,
      first_line = line_number,
      first_offset = first,
      last_line = line_number,
      last_offset = last
   }
end

function TextRect:get_editor_selection()
   if not self.editor_selection_anchor or not self.editor_selection_active then
      return
   end

   local anchor_line = self.editor_selection_anchor.line
   local anchor_offset = self.editor_selection_anchor.offset
   local active_line = self.editor_selection_active.line
   local active_offset = self.editor_selection_active.offset
   local first_line, first_offset = anchor_line, anchor_offset
   local last_line, last_offset = active_line, active_offset
   if first_line > last_line or
      (first_line == last_line and first_offset > last_offset) then
      first_line, last_line = last_line, first_line
      first_offset, last_offset = last_offset, first_offset
   end

   return {
      anchor = {line=anchor_line, offset=anchor_offset},
      active = {line=active_line, offset=active_offset},
      first = {line=first_line, offset=first_offset},
      last = {line=last_line, offset=last_offset},
      collapsed = first_line == last_line and first_offset == last_offset
   }
end

function TextRect:set_editor_selection(anchor_line, anchor_offset, active_line, active_offset)
   if self.num_wrapped_lines == 0 or
      not (anchor_line and anchor_offset and active_line and active_offset) then
      self.editor_selection_anchor = nil
      self.editor_selection_active = nil
      self:set_selection(nil, nil, nil, nil)
      return
   end

   anchor_line = math.max(1, math.min(anchor_line, self.num_wrapped_lines))
   active_line = math.max(1, math.min(active_line, self.num_wrapped_lines))
   anchor_offset = math.max(0, math.min(anchor_offset, self:line_length(anchor_line)))
   active_offset = math.max(0, math.min(active_offset, self:line_length(active_line)))
   self.editor_selection_anchor = {line=anchor_line, offset=anchor_offset}
   self.editor_selection_active = {line=active_line, offset=active_offset}

   local state = self:get_editor_selection()
   if state.collapsed then
      self:set_selection(nil, nil, nil, nil)
   else
      self:set_selection(
         state.first.line,
         state.last.line,
         state.first.offset,
         state.last.offset)
   end
   return state
end

function TextRect:set_selection_callback(callback)
   assert(callback == nil or type(callback) == "function", "TextRect selection callback must be a function or nil")
   self.selection_callback = callback
end

function TextRect:begin_selection(flags, x, y, options)
   options = options or {}
   self.pointer_selecting = true
   self.last_partitioned_styles = {}
   self.last_partitioned_line_sections = {}

   local now = socket.gettime()
   local clicks = 1
   if bit.band(flags, miniwin.hotspot_got_dbl_click) ~= 0 then
      clicks = 2
   elseif self.editor_last_click_time and now - self.editor_last_click_time < 0.4 then
      clicks = (self.editor_click_count or 1) + 1
      if clicks > 3 then
         clicks = 1
      end
   end
   self.editor_last_click_time = now
   self.editor_click_count = clicks

   local hit
   local kind = "cursor"
   if clicks == 2 then
      kind = "word"
      hit = self:hit_test(x, y, {
         unit="word",
         separator_pattern=options.word_separator_pattern,
         cache_key="editor_word"
      })
   elseif clicks == 3 then
      kind = "line"
      hit = self:hit_test(x, y, {unit="line"})
   else
      hit = self:hit_test(x, y, {unit="character", cache_key="editor_character"})
   end
   if not hit then
      self.pointer_selecting = false
      return
   end

   self.pointer_selection_unit = kind
   self.pointer_selection_origin = {
      first_line=hit.first_line,
      first_offset=hit.first_offset,
      last_line=hit.last_line,
      last_offset=hit.last_offset
   }
   self.pointer_word_separator_pattern = options.word_separator_pattern

   local anchor_line = hit.line
   local anchor_offset = hit.offset
   local active_line = hit.line
   local active_offset = hit.offset
   if kind == "word" or kind == "line" then
      anchor_line = hit.first_line
      anchor_offset = hit.first_offset
      active_line = hit.last_line
      active_offset = hit.last_offset
   elseif bit.band(flags, miniwin.hotspot_got_shift) ~= 0 and self.editor_selection_anchor then
      anchor_line = self.editor_selection_anchor.line
      anchor_offset = self.editor_selection_anchor.offset
   end

   local state = self:set_editor_selection(anchor_line, anchor_offset, active_line, active_offset)
   if self.selection_callback and state then
      self.selection_callback(self, state)
   end
   return state
end

function TextRect:update_selection(x, y)
   if not self.pointer_selecting or not self.editor_selection_anchor then
      return
   end

   local unit = self.pointer_selection_unit or "cursor"
   local hit_options = {
      unit="character",
      cache_key="editor_character",
      allow_offscreen=true
   }
   if unit == "word" then
      hit_options.unit = "word"
      hit_options.cache_key = "editor_word"
      hit_options.separator_pattern = self.pointer_word_separator_pattern
   elseif unit == "line" then
      hit_options.unit = "line"
   end

   local hit = self:hit_test(x, y, hit_options)
   if not hit then
      return
   end

   local anchor_line = self.editor_selection_anchor.line
   local anchor_offset = self.editor_selection_anchor.offset
   local active_line = hit.line
   local active_offset = hit.offset
   if unit == "word" or unit == "line" then
      local origin = self.pointer_selection_origin
      local before_origin = hit.first_line < origin.first_line or
         (hit.first_line == origin.first_line and hit.first_offset < origin.first_offset)
      if before_origin then
         anchor_line = origin.last_line
         anchor_offset = origin.last_offset
         active_line = hit.first_line
         active_offset = hit.first_offset
      else
         anchor_line = origin.first_line
         anchor_offset = origin.first_offset
         active_line = hit.last_line
         active_offset = hit.last_offset
      end
   end

   if self.editor_selection_anchor.line == anchor_line and
      self.editor_selection_anchor.offset == anchor_offset and
      self.editor_selection_active and
      self.editor_selection_active.line == active_line and
      self.editor_selection_active.offset == active_offset then
      return self:get_editor_selection(), false
   end

   local state = self:set_editor_selection(
      anchor_line,
      anchor_offset,
      active_line,
      active_offset)
   if self.selection_callback and state then
      self.selection_callback(self, state)
   end
   return state, true
end

function TextRect:finish_selection(x, y)
   local state, changed = self:update_selection(x, y)
   state = state or self:get_editor_selection()
   self.pointer_selecting = false
   self.pointer_selection_unit = nil
   self.pointer_selection_origin = nil
   self.pointer_word_separator_pattern = nil
   return state, changed
end

function TextRect:cancel_selection()
   self.pointer_selecting = false
   self.pointer_selection_unit = nil
   self.pointer_selection_origin = nil
   self.pointer_word_separator_pattern = nil
end

function TextRect.mouseDown(flags, hotspot_id)
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   local tr = TextRect.hotspot_map[hotspot_id]
   tr:begin_selection(
      flags,
      WindowInfo(tr.window, 14),
      WindowInfo(tr.window, 15),
      {word_separator_pattern="[^%w%-]+"})
   tr:draw(false)
   if tr.call_on_select then
      tr.call_on_select(tr.copy_start_line, tr.copy_end_line, tr.start_copying_pos, tr.end_copying_pos, tr.start_copying_x, tr.end_copying_x)
   end
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end


function TextRect.dragMove(flags, hotspot_id)
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   local tr = TextRect.hotspot_map[hotspot_id]

   if tr.num_wrapped_lines == 0 then
      return
   end
   
   tr:updateSelect()

   if tr.scrollable then
      -- Scroll if the mouse is dragged off the top or bottom
      if tr.end_copying_y < tr.top then
         if tr.keepscrolling ~= "up" then
            tr.keepscrolling = "up"
            tr:scroll(true)
         end
         return
      elseif tr.end_copying_y > tr.bottom then
         if tr.keepscrolling ~= "down" then
            tr.keepscrolling = "down"
            tr:scroll(true)
         end
         return
      else
         tr.keepscrolling = ""
      end
   end
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function TextRect.dragRelease(flags, hotspot_id)
   local tr = TextRect.hotspot_map[hotspot_id]
   tr:finish_selection(
      WindowInfo(tr.window, 17) - WindowInfo(tr.window, 10),
      WindowInfo(tr.window, 18) - WindowInfo(tr.window, 11))
   if tr.call_on_select then
      tr.call_on_select(tr.copy_start_line, tr.copy_end_line, tr.start_copying_pos, tr.end_copying_pos, tr.start_copying_x, tr.end_copying_x)
   end
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function TextRect.mouseUp(flags, hotspot_id)
   local tr = TextRect.hotspot_map[hotspot_id]
   tr.keepscrolling = ""
   tr:draw()
   if bit.band(flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      tr:rightClickMenu(hotspot_id)
   end
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
   return true
end

function TextRect.cancelMouseDown(flags, hotspot_id)
   local tr = TextRect.hotspot_map[hotspot_id]
   tr.keepscrolling = ""
   tr:cancel_selection()
   tr:draw()
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function TextRect:set_selection(start_line, end_line, start_pos, end_pos)
   if (
      start_line and end_line and start_pos and end_pos and
      ((start_line >= 1) or (end_line >= 1)) and
      ((start_line <= self.num_wrapped_lines) or (end_line <= self.num_wrapped_lines))
   ) then
      if start_line < 1 and end_line >= 1 then
         start_line = 1
         start_pos = 0
      end
      if end_line > self.num_wrapped_lines and start_line <= self.num_wrapped_lines then
         end_line = self.num_wrapped_lines
         end_pos = #strip_colours_from_styles(self.wrapped_lines[end_line][1])
      end
      self.start_copying_pos = start_pos
      self.end_copying_pos = end_pos
      self.copy_end_line = end_line
      self.copy_start_line = start_line
      self.start_copying_x = self.padded_left + self:styles_width(
         TruncateStyles(self.wrapped_lines[start_line][1], 0, start_pos)
      )
      self.end_copying_x = self.padded_left + self:styles_width(
         TruncateStyles(self.wrapped_lines[end_line][1], 0, end_pos)
      )
   else
      self.start_copying_pos = nil
      self.end_copying_pos = nil
      self.copy_end_line = nil
      self.copy_start_line = nil
      self.start_copying_x = nil
      self.end_copying_x = nil
   end
   -- do not call self.call_on_select here
end

function TextRect:updateSelect()
   self.end_copying_y = WindowInfo(self.window, 18) - WindowInfo(self.window, 11)
   local cursor_x = WindowInfo(self.window, 17) - WindowInfo(self.window, 10)
   local state = self:update_selection(cursor_x, self.end_copying_y)
   self:draw(false)
   if self.call_on_select then
      self.call_on_select(self.copy_start_line, self.copy_end_line, self.start_copying_pos, self.end_copying_pos, self.start_copying_x, self.end_copying_x)
   end
   return state
end

function TextRect.wheelMove(flags, hotspot_id)
   local tr = TextRect.hotspot_map[hotspot_id]
   local delta = math.ceil(bit.shr(flags, 16) / 3)
   local line_delta = math.ceil(delta / tr.line_height)
   tr.wheeling = true
   if bit.band(flags, miniwin.wheel_scroll_back) ~= 0 then
      -- down
      if tr.start_line < tr.num_wrapped_lines - tr.rect_lines + 1 then
         tr.start_line = math.max(1, math.min(tr.num_wrapped_lines - tr.rect_lines + 1, tr.start_line + line_delta))
         tr.end_line = math.min(tr.num_wrapped_lines, tr.start_line + tr.rect_lines - 1)
         tr.display_start_line = tr.start_line
         tr.display_end_line = tr.end_line
         tr:draw()
         CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
      end
   else
      -- up
      if tr.start_line > 1 then
         tr.start_line = math.max(1, tr.start_line - line_delta)
         tr.end_line = math.min(tr.num_wrapped_lines, tr.start_line + tr.rect_lines - 1)
         tr.display_start_line = tr.start_line
         tr.display_end_line = tr.end_line
         tr:draw()
         CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
      end -- if
   end
   tr.wheeling = false
end

function TextRect:underline_hyperlinks()
   local hotspot_id = WindowInfo(self.window, 19)
   if hotspot_id then
      local url = self.hyperlinks[hotspot_id]
      if url then
         for _, v in ipairs (WindowHotspotList(self.window)) do
            if string.find(v, url, 1, true) then
               local left = WindowHotspotInfo(self.window, v, 1)
               local right = WindowHotspotInfo(self.window, v, 3)
               local bottom = WindowHotspotInfo(self.window, v, 4) + 1
               WindowLine(self.window, left, bottom, right, bottom, 0xffffff, 256, 1);
            end
         end
      end
   end
end

function TextRect.linkHover(flags, hotspot_id)
   local tr = TextRect.hotspot_map[hotspot_id]
   if tr.wheeling or (GetOption("underline_hyperlinks") == 0) then
      return
   end
   tr:underline_hyperlinks()
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function TextRect.cancelLinkHover(flags, hotspot_id)
   local tr = TextRect.hotspot_map[hotspot_id]
   local url = tr.hyperlinks[hotspot_id]

   if not string.find(WindowInfo(tr.window, 19), url, 1, true) then
      tr:draw(false)
      CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
   end
end

function TextRect:setExternalMenuFunction(menu_generator_function)
   self.external_menu_generator = menu_generator_function
end

function TextRect:rightClickMenu(hotspot_id)
   local menu_text = {}
   local menu_functions = {}

   local function extend_options(external_string, external_functions)
      if external_string:sub(1,1) == "!" then
         external_string = external_string:sub(2)
      end
      if #menu_text > 0 then
         table.insert(menu_text, "-")
      end
      table.insert(menu_text, external_string)
      for _, v in ipairs(external_functions) do
         table.insert(menu_functions, v)
      end
   end

   if self.hyperlinks[hotspot_id] and (#(self:findURLs(self.hyperlinks[hotspot_id])) > 0) then
      table.insert(menu_text, "Browse URL: " .. self.hyperlinks[hotspot_id])
      table.insert(menu_text, "Copy URL to Clipboard")
      table.insert(menu_text, "-")
      table.insert(menu_functions, TextRect.browseUrl)
      table.insert(menu_functions, TextRect.copyUrl)
   end

   if not self.uncopyable then
      if (self.copy_start_line ~= nil) and (self.copy_end_line ~= nil) then
         table.insert(menu_text, "Copy Selected")
         table.insert(menu_text, "Copy Selected Without Colors")
         table.insert(menu_functions, TextRect.copy)
         table.insert(menu_functions, TextRect.copyPlain)
      end
      table.insert(menu_text, "Copy All")
      table.insert(menu_functions, TextRect.copyFull)
      table.insert(menu_text, "Copy All Without Colors")
      table.insert(menu_functions, TextRect.copyFullPlain)
   end

   if self.external_menu_generator then
      local external_string, external_functions = self.external_menu_generator((self.copy_start_line ~= nil) and (self.copy_end_line ~= nil) and self:selected_text(false) or nil)
      extend_options(external_string, external_functions)
   end

   result = tonumber(
      WindowMenu (
         self.window,
         WindowInfo (self.window, 14), -- x coord
         WindowInfo (self.window, 15), -- y coord
         "!"..table.concat(menu_text, "|")
      )
   )

   if result then
      menu_functions[result](self, hotspot_id, result)
   end
end

function TextRect:browseUrl(hotspot_id)
   local url = self.hyperlinks[hotspot_id]
   if url then
      if #(self:findURLs(url)) > 0 then
         OpenBrowser(url)
      else
         loadstring(url)()
      end
   end
end

function TextRect.clickUrl(flags, hotspot_id)
   if bit.band(flags, miniwin.hotspot_got_rh_mouse) ~= 0 then  -- only left-button
      return
   end
   local tr = TextRect.hotspot_map[hotspot_id]
   tr:browseUrl(hotspot_id)
end

function TextRect:serializeContents()
   require "serialize"
   local keys = {
      raw_lines = {},
      start_line = 1,
   }

   local contents = {}
   for k,v in pairs(keys) do
      contents[k] = self[k]
   end

   return serialize.save_simple(contents)
end

function TextRect:deserializeContents(contents, no_draw_after)
   if (type(contents) == "string") and (contents ~= "") then
      local contents = loadstring("return "..contents)()
      if (type(contents) == "table") and contents.raw_lines and contents.start_line then
         self.raw_lines = contents.raw_lines
         self.num_raw_lines = #self.raw_lines
         self:reWrapLines()
         self:setScroll(contents.start_line, no_draw_after)
      end
   end
end

function TextRect:copyAndNotify(text)
   ColourNote("cyan","","--------------------Copied to clipboard--------------------")
   ColourNote("yellow","", text)
   ColourNote("cyan","","-----------------------------------------------------------")
   SetClipboard(text)
end

function TextRect:copyUrl(hotspot_id)
   local url = self.hyperlinks[hotspot_id]
   if url then
      self:copyAndNotify(url)
   end
end

function TextRect:copyPlain()
   self:copyAndNotify(self:selected_text(false))
end

function TextRect:copy()
   self:copyAndNotify(self:selected_text(true))
end

function TextRect:selected_text(with_colors)
   s_text = {}
   current_message = {}

   function store_message()
      if current_message then
         -- preserve the message and start the next one
         if with_colors then
            table.insert(s_text, canonicalize_colours(StylesToColours(current_message), true))
         else
            table.insert(s_text, strip_colours_from_styles(current_message))
         end
         current_message = {}
      end
   end

   for copy_line = self.copy_start_line, self.copy_end_line do
      if (self.wrapped_lines[copy_line] ~= nil) then
         local startpos = 0
         local endpos = 99999
         if copy_line == self.copy_start_line then
            startpos = self.start_copying_pos
         end
         if copy_line == self.copy_end_line then
            endpos = self.end_copying_pos
         end

         if (endpos ~= startpos) or (self.copy_start_line ~= self.copy_end_line) then
            -- store current message when starting a new one after the first one
            if (copy_line ~= self.copy_start_line) and self.wrapped_lines[copy_line][2] then
               store_message()
            end
            -- add styles from this wrapped line to the current message
            local line_styles = TruncateStyles(self.wrapped_lines[copy_line][1], startpos+1, endpos)
            if line_styles then
               for _, s in ipairs(line_styles) do
                  table.insert(current_message, s)
               end
            else
               table.insert(s_text, "")
            end
         end
      end
   end

   -- preserve the final message
   store_message()

   return table.concat(s_text, "\n")
end

function TextRect:getStyles()
   local t = {}
   for _,line in ipairs(self.raw_lines) do
      table.insert(t, line[1])
   end
   return t
end

function TextRect:getText()
   local t = {}
   for _,line in ipairs(self.raw_lines) do
      table.insert(t, canonicalize_colours(StylesToColours(line[1]), true))
   end
   return table.concat(t, "\n")
end

function TextRect:copyFull()
   SetClipboard(self:getText())
   ColourNote("yellow","","All text copied to clipboard ","limegreen","","with","yellow",""," colors.")
end

function TextRect:copyFullPlain()
   SetClipboard(strip_colours(self:getText()))
   ColourNote("yellow","","All text copied to clipboard ","red","","without","yellow",""," colors.")
end

function TextRect:generateHotspotID(id)
   local hotspot_id = self.id.."_hotspot_"..id
   TextRect.hotspot_map[hotspot_id] = self
   return hotspot_id
end
