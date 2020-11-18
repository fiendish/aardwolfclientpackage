-- Bits of this code and ideas were borrowed and remixed from the MUSHclient community. https://www.mushclient.com/forum/?id=9385 and others.

require "wait"
require "copytable"
require "colors"
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
   highlight_color = getHighlightColor(0x000000)
}
TextRect_mt = { __index = TextRect }

function TextRect.new(
   window, name, left, top, right, bottom, max_lines, scrollable, background_color, 
   padding, font_name, font_size, external_scroll_handler, call_on_select, 
   unselectable, uncopyable, no_url_hyperlinks, no_autowrap,
   menu_generator_function
)
   new_tr = setmetatable(copytable.deep(TextRect_defaults), TextRect_mt)
   new_tr.id = "TextRect_"..window.."_"..name
   new_tr.window = window
   new_tr.name = name
   new_tr:configure(
      left, top, right, bottom, max_lines, scrollable, background_color, 
      padding, font_name, font_size, external_scroll_handler, call_on_select, 
      unselectable, uncopyable, no_url_hyperlinks, no_autowrap, 
      menu_generator_function)
   return new_tr
end

function TextRect:configure(
   left, top, right, bottom, max_lines, scrollable, background_color,
   padding, font_name, font_size, external_scroll_handler, call_on_select,
   unselectable, uncopyable, no_url_hyperlinks, no_autowrap,
   menu_generator_function
)
   self:setExternalMenuFunction(menu_generator_function)
   self.scrollable = scrollable
   self.external_scroll_handler = external_scroll_handler
   self.call_on_select = call_on_select
   self.padding = padding or self.padding
   self.max_lines = max_lines or self.max_lines
   self.font_name = font_name or self.font_name
   self.font_size = font_size or self.font_size
   self.no_autowrap = no_autowrap
   self.unselectable = unselectable
   self.uncopyable = uncopyable
   self.no_url_hyperlinks = no_url_hyperlinks
   if background_color ~= self.background_color then
      self.background_color = background_color or self.background_color
      self.highlight_color = getHighlightColor(self.background_color)
   end
   self:loadFont(self.font_name, self.font_size)
   self:setRect(left, top, right, bottom)
end

function TextRect:loadFont(name, size)
   if (not self.font) or (name ~= self.font_name) or (size ~= self.font_size) then
      self.font = self.id.."_font"
      self.font_bold = self.id.."_font_bold"
      self.font_name = name or self.font_name
      self.font_size = size or self.font_size

      WindowFont(self.window, self.font, self.font_name, self.font_size, false, false, false, false, 0)
      WindowFont(self.window, self.font_bold, self.font_name, self.font_size, true, false, false, false, 0)
      self.line_height = WindowFontInfo(self.window, self.font, 1)
   end
   if self.padded_height then
      self.rect_lines = math.floor(self.padded_height / self.line_height)
   end
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

function TextRect:addText(message, limit_break)
   if type(message) == "string" then
      message = ColoursToStyles(message, nil, nil, true)
   end
   -- try to be flexible about input
   assert(type(message) == "table", "TextRect:addText must be given a color coded string, table of styles, or table of tables (multiple lines) of styles")
   if message.text then
      message = {message}
   elseif message[1] then
      if message[1][1] and not limit_break then
         for _,v in ipairs(message) do
            self:addText(v, true)
         end
         return
      end
      assert(message[1].text, "TextRect:addText must be given a color coded string, table of styles, or table of tables (multiple lines) of styles")
   end

   -- extract URLs so we can add our movespots later
   local urls = self:findURLs(strip_colours_from_styles(message))

   -- pop the oldest line from our buffer if we're at capacity
   if self.num_raw_lines >= self.max_lines then
      table.remove(self.raw_lines, 1)
      self.num_raw_lines = self.num_raw_lines - 1
   end

   -- add to raw lines table
   table.insert(self.raw_lines, {[1]=message, [2]=urls})
   self.num_raw_lines = self.num_raw_lines + 1

   -- add to wrapped lines table for display
   self:wrapLine(message, urls, self.num_raw_lines)
end

function TextRect:addColorLine(line)
   self:addText(line)
end

function TextRect:addStyles(styles)
   self:addText(styles)
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
   if self.num_wrapped_lines >= self.max_lines then
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
   local styles = copytable.deep(stylerun)
   local urls = copytable.deep(rawURLs)

   local remove = table.remove
   local insert = table.insert
   local sub = string.sub
   local find = string.find
   local show_bold = (GetOption("show_bold")==1)

   -- Keep pulling out styles and trying to fit them on the current line
   while #styles > 0 do
      -- break off the next style
      local style = remove(styles, 1)

      local font = self.font
      if style.bold and show_bold then
         font = self.font_bold
      end
      local t_width = WindowTextWidth(self.window, font, style.text)

      -- if it fits, copy whole style in
      if self.no_autowrap or (t_width <= available) then
         if style.length > 0 then
            insert(line_styles, style)
         end
         length = length + style.length
         available = available - t_width
      else -- otherwise, have to split style
         -- look for spaces to break at
         local col = 2
         local fits = true
         local fit_col = nil
         while col < style.length do
            if sub(style.text, col, col) == " " then
               t_width = WindowTextWidth(self.window, font, sub(style.text, 1, col-1))
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
                  t_width = WindowTextWidth(self.window, font, sub(style.text, 1, col))
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
            urls[1].stop = urls[1].stop-1
            urls[1].old = true
            insert(line_urls, url)
         end

         for i,v in ipairs(urls) do
            urls[i].start = urls[i].start - length
            urls[i].stop = urls[i].stop - length
            if urls[i].start <= 1 then
               urls[i].start = 1
               urls[i].stop = urls[i].stop
            end
         end

         self:lockstep()

         -- add new wrapped line component
         self.num_wrapped_lines = self.num_wrapped_lines + 1
         local raw_index_delta = self.num_wrapped_lines - raw_index
         table.insert(self.wrapped_lines, {[1]=line_styles, [2]=beginning, [3]=line_urls, [4]=raw_index_delta} )

         -- prep for next line
         available = self.padded_width
         line_styles = {}
         length = 0
         beginning = false
      end -- line full
   end -- while we still have styles left
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
      raw_index = start_line - self.wrapped_lines[start_line][4]
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

function TextRect:drawLine(line, styles, backfill_start, backfill_end)
   local left = self.padded_left
   local top = self.padded_top + (line * self.line_height) + 1
   if (backfill_start ~= nil and backfill_end ~= nil) then
      WindowRectOp(self.window, 2, backfill_start, top, backfill_end-1, top + self.line_height, self.highlight_color)
   end -- backfill
   if styles then
      local utf8 = (GetOption("utf_8") == 1)
      local show_bold = (GetOption("show_bold")== 1)
      for _, v in ipairs(styles) do
         local t = v.text
         local font = self.font
         if show_bold and v.bold then
            font = self.font_bold
         end
         left = left + WindowText(self.window, font, t, left, top, self.padded_right, self.padded_bottom, v.textcolour, utf8 and utils.utf8valid(t))
      end
   end
end

function TextRect:styles_width(styles, show_bold)
   if show_bold == nil then
      show_bold = (GetOption("show_bold")== 1)
   end
   return StylesWidth(self.window, self.font, self.font_bold, styles, show_bold)
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
      for count = self.display_start_line, self.display_end_line do
         ax = nil
         zx = nil
         line_styles = self.wrapped_lines[count][1]
         if (self.keepscrolling == "") and not self.no_url_hyperlinks then
            -- create clickable links for urls
            for _,url_part in ipairs(self.wrapped_lines[count][3]) do
               -- bold widths in urls. replacement for: local left = self.padded_left + WindowTextWidth(self.window, self.font, string.sub(line_no_colors, 1, url_part.start-1))
               local left = self.padded_left + self:styles_width(TruncateStyles(line_styles, 0, url_part.start-1), show_bold)
               -- bold widths in urls. replacement for: local right = left + WindowTextWidth(self.window, self.font, string.sub(line_no_colors, url_part.start-1, url_part.stop-1))
               local right = left + self:styles_width(TruncateStyles(line_styles, url_part.start, url_part.stop), show_bold)
               local top = self.padded_top + ((count - self.display_start_line) * self.line_height)-1
               local bottom = top + self.line_height
               local link_id = self:generateHotspotID(table.concat({url_part.text, " ", count, " ", url_part.start, " ", url_part.stop}))

               if not WindowHotspotInfo(self.window, link_id, 1) then
                  self.hyperlinks[link_id] = url_part.text
                  WindowAddHotspot(self.window, link_id, left, top, math.min(right, self.padded_right), bottom, "TextRect.linkHover", "TextRect.cancelLinkHover", "TextRect.clickUrl", "", "TextRect.mouseUp", "Right-click this URL if you want to open it:\n"..url_part.text, 1)
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
         self:drawLine(count - self.display_start_line, self.wrapped_lines[count][1], ax, zx )
      end
   end

   if not inside_callback then
      self:doUpdateCallbacks()
   end
   
   self:underline_hyperlinks()
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

function TextRect:getScroll()
   return self.start_line
end

function TextRect:setScroll(new_pos)
   self.start_line = math.max(1, math.min(new_pos, self.num_wrapped_lines - self.rect_lines + 1))
   self.end_line = math.min(self.start_line + self.rect_lines - 1, self.num_wrapped_lines)
   self.display_start_line = self.start_line
   self.display_end_line = self.end_line
   self:draw(true, true)
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

function TextRect.mouseDown(flags, hotspot_id)
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   local tr = TextRect.hotspot_map[hotspot_id]
   tr.temp_start_copying_x = WindowInfo(tr.window, 14)
   tr.copy_start_windowline = math.floor((WindowInfo(tr.window, 15) - tr.top) / tr.line_height)
   tr.temp_start_line = tr.copy_start_windowline + tr.start_line
   tr:set_selection(nil, nil, nil, nil)
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
   self.copy_start_line = self.temp_start_line
   self.start_copying_x = self.temp_start_copying_x

   self.end_copying_y = WindowInfo(self.window, 18) - WindowInfo(self.window, 2)
   self.copy_end_windowline = math.floor((self.end_copying_y - self.top) / self.line_height)
   self.copy_end_line = self.copy_end_windowline + self.start_line
   self.end_copying_x = math.max(self.left, math.min(self.right, WindowInfo(self.window, 17) - WindowInfo(self.window, 1)))

   -- the user is selecting backwards, so reverse the start/end orders
   if self.copy_end_line < self.copy_start_line then
      self.copy_start_line, self.copy_end_line = self.copy_end_line, self.copy_start_line
      self.start_copying_x, self.end_copying_x = self.end_copying_x, self.start_copying_x
   elseif (self.copy_end_line == self.copy_start_line) and (self.end_copying_x < self.start_copying_x) then
      self.start_copying_x, self.end_copying_x = self.end_copying_x, self.start_copying_x
   end

   -- get the entire line if we drag off the top/bottom
   if self.copy_end_line > self.num_wrapped_lines then
      self.end_copying_x = self.right
   end
   if self.copy_start_line < 1 then
      self.start_copying_x = self.padded_left
   end

   self.copy_start_line = math.max(1, math.min(self.num_wrapped_lines, self.copy_start_line))
   self.copy_end_line = math.max(1, math.min(self.num_wrapped_lines, self.copy_end_line)) 

   local show_bold = (GetOption("show_bold")== 1)

   for copy_line = self.copy_start_line, self.copy_end_line do
      -- Clamp to character boundaries instead of selecting arbitrary pixel positions...
      local line_styles = self.wrapped_lines[copy_line][1]

      -- Clamp the selection start position
      if copy_line == self.copy_start_line then
         local last_marker = self.padded_left
         self.start_copying_pos = 0
         for _,v in ipairs(line_styles) do
            local marker = self.padded_left
            local font = self.font
            if show_bold and v.bold then
               font = self.font_bold
            end
            for cur=v.length,0,-1 do
               marker = last_marker + WindowTextWidth(self.window, font, string.sub(v.text, 1, cur))
               if marker <= self.start_copying_x then
                  self.start_copying_pos = self.start_copying_pos + cur
                  break
               end
            end
            last_marker = marker
         end
         self.start_copying_x = last_marker
      end

      -- Clamp the selection end position
      if copy_line == self.copy_end_line then
         local last_marker = self.padded_left
         self.end_copying_pos = 0
         for _,v in ipairs(line_styles) do
            local marker = self.padded_left
            local font = self.font
            if show_bold and v.bold then
               font = self.font_bold
            end
            for cur=v.length,0,-1 do
               marker = last_marker + WindowTextWidth(self.window, font, string.sub(v.text, 1, cur))
               if marker <= self.end_copying_x then
                  self.end_copying_pos = self.end_copying_pos + cur
                  break
               end
            end
            last_marker = marker
         end
         self.end_copying_x = last_marker
      end
   end

   if (self.copy_start_line == self.copy_end_line) and (self.start_copying_pos == self.end_copying_pos) then
      self:set_selection(nil, nil, nil, nil)
   end

   self:draw(false)
   if self.call_on_select then
      self.call_on_select(self.copy_start_line, self.copy_end_line, self.start_copying_pos, self.end_copying_pos, self.start_copying_x, self.end_copying_x)
   end
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

   if self.hyperlinks[hotspot_id] then
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
      local external_string, external_functions = self.external_menu_generator()
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
      OpenBrowser(url)
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

function TextRect:deserializeContents(contents)
   if (type(contents) == "string") and (contents ~= "") then
      local contents = loadstring("return "..contents)()
      if (type(contents) == "table") and contents.raw_lines and contents.start_line then
         self.raw_lines = contents.raw_lines
         self.num_raw_lines = #self.raw_lines
         self:reWrapLines()
         self:setScroll(contents.start_line)
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

function TextRect:copyFull()
   local t = {}
   for _,line in ipairs(self.raw_lines) do
      table.insert(t, canonicalize_colours(StylesToColours(line[1]), true))
   end
   SetClipboard(table.concat(t, "\n"))
   ColourNote("yellow","","All text copied to clipboard ","limegreen","","with","yellow",""," colors.")
end

function TextRect:copyFullPlain()
   local t = {}
   for _,line in ipairs(self.raw_lines) do
      table.insert(t, strip_colours_from_styles(line[1]))
   end
   SetClipboard(table.concat(t, "\n"))
   ColourNote("yellow","","All text copied to clipboard ","red","","without","yellow",""," colors.")
end

function TextRect:generateHotspotID(id)
   local hotspot_id = self.id.."_hotspot_"..id
   TextRect.hotspot_map[hotspot_id] = self
   return hotspot_id
end

