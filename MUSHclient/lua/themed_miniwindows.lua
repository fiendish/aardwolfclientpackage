require "mw_theme_base"
require "movewindow"

ThemedWindowClass = {
   title_font = "window_title_font",
   hotspot_map = {},
   window_map = {}
}
ThemedWindowClass.__index = ThemedWindowClass


function ThemedWindowClass:blank()
   WindowRectOp(self.id, 2, self.bodyleft, self.bodytop, self.bodyright+1, self.bodybottom+1, Theme.PRIMARY_BODY)
end

function ThemedWindowClass:delete(deferred)
   local width = WindowInfo(self.id, 3)
   local height = WindowInfo(self.id, 4)
   if width and height then
      movewindow.save_state(self.id)
      SetVariable(self.id.."width", width)
      SetVariable(self.id.."height", height)
   end
   for k, v in pairs(self.hotspot_map) do
      if v.id == self.id then
         self.hotspot_map[k] = nil
      end
   end
   if self.do_on_delete then
      self:do_on_delete()
   end
   self.window_map[self.id] = nil
   if deferred then
      DoAfterSpecial(0.1, "WindowDelete(\""..self.id.."\")", 12)
   else
      WindowDelete(self.id)
   end
end

function ThemedWindowClass:reset()
   WindowPosition(self.id, self.default_left_position, self.default_top_position, 0, 18)
   self:resize(self.default_width, self.default_height)
   Repaint() -- hack because WindowPosition doesn't immediately update coordinates
   SetVariable(self.id.."width", self.default_width)
   SetVariable(self.id.."height", self.default_height)
   movewindow.save_state(self.id)
end

function ThemedWindowClass.DeleteCallback(flags, hotspot_id)
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   if ThemedWindowClass.hotspot_map[hotspot_id] then
      ThemedWindowClass.hotspot_map[hotspot_id]:delete(true)
   end
end

function ThemedWindowClass.ResizeMouseDownCallback(flags, hotspot_id)
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   local window = ThemedWindowClass.hotspot_map[hotspot_id]
   window.resize_startx = WindowInfo(window.id, 17)
   window.resize_starty = WindowInfo(window.id, 18)
end

local lastRefresh = 0

function ThemedWindowClass.ResizeMoveCallback(flags, hotspot_id)
   if GetPluginVariable("c293f9e7f04dde889f65cb90", "lock_down_miniwindows") == "1" then
      return
   end
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   local window = ThemedWindowClass.hotspot_map[hotspot_id]

   local posx, posy = WindowInfo(window.id, 17), WindowInfo(window.id, 18)
   window.width = window.width + posx - window.resize_startx
   window.resize_startx = posx
   if (window.width < window.min_width) then
      window.width = window.min_width
      window.resize_startx = window.windowinfo.window_left+window.width
   elseif (window.windowinfo.window_left+window.width > GetInfo(281)) then
      window.width = GetInfo(281)-window.windowinfo.window_left
      window.resize_startx = GetInfo(281)
   end

   window.height = window.height + posy - window.resize_starty
   window.resize_starty = posy
   if (window.height < window.min_height) then
      window.height = window.min_height
      window.resize_starty = window.windowinfo.window_top+window.height
   elseif (window.windowinfo.window_top+window.height > GetInfo(280)) then
      window.height = GetInfo(280)-window.windowinfo.window_top
      window.resize_starty = GetInfo(280)
   end
   if (utils.timer() - lastRefresh > 0.0333) then
      window:resize(window.width, window.height, true)
      CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
      lastRefresh = utils.timer()
   end
end

function ThemedWindowClass.ResizeReleaseCallback(flags, hotspot_id)
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   local window = ThemedWindowClass.hotspot_map[hotspot_id]
   SetVariable(window.id.."width", window.width)
   SetVariable(window.id.."height", window.height)
   window:resize(window.width, window.height, false)
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function ThemedWindowClass:resize(width, height, still_dragging)
   self.width = width
   self.height = height
   CallPlugin("abc1a0944ae4af7586ce88dc", "pause")
   WindowResize(self.id, width, height, Theme.PRIMARY_BODY)
   _, self.bodyleft, self.bodytop, self.bodyright, self.bodybottom = Theme.BodyMetrics(self.id, self.title_font, WindowFontInfo(self.id, self.title_font, 1), #self.title)
   if still_dragging then
      if self.do_while_resizing then
         self:do_while_resizing()
      else
         self:blank()
      end
   else
      if self.do_after_resizing then
         self:do_after_resizing()
      else
         self:blank()
      end
   end
   self:dress_window()
   CallPlugin("abc1a0944ae4af7586ce88dc", "resume")
end

function ThemedWindowClass:add_3d_text_button(id, left, top, text, utf8, tooltip, mousedown_callback, mouseup_callback, font, x_padding, y_padding, width, height)
   self.hotspot_map[id] = self
   local right, bottom = Theme.Add3DTextButton(self.id, id, font or self.title_font, left or self.bodyleft, top or self.bodytop, text, utf8, x_padding, y_padding, tooltip, mousedown_callback, mouseup_callback, width, height)
   return right, bottom
end

function ThemedWindowClass:dress_window()
   boxwidth = WindowTextWidth(self.id, self.title_font, "!") + (3*Theme.TITLE_PADDING) + 5
   self.bodyleft, self.bodytop, self.bodyright, self.bodybottom = Theme.DressWindow(self.id, self.title_font, self.title, self.title_alignment, self.is_temporary and boxwidth or 0)
   
   if WindowMoveHotspot(self.id, "zzzzzzzzzz"..self.id.."_body", self.bodyleft, self.bodytop, self.bodyright, self.bodybottom) ~= 0 then
      local cursor = 0
      if (self.title == nil) or (#(self.title) == 0) then
         cursor = 1
      end
      self.hotspot_map["zzzzzzzzzz"..self.id.."_body"] = self
      WindowAddHotspot(self.id, "zzzzzzzzzz"..self.id.."_body", self.bodyleft, self.bodytop, self.bodyright, self.bodybottom, nil, nil, nil, nil, "ThemedWindowClass.RightClickMenuCallback", "", cursor, 0)
   end

   if self.is_temporary then
      local right, bottom = self:add_3d_text_button(self.id.."_close", -1, -1, "!", false, "Remove Window", ThemedWindowClass.LeftButtonOnlyCallback, ThemedWindowClass.DeleteCallback, self.title_font, Theme.TITLE_PADDING, Theme.TITLE_PADDING)
      right = right+1
      WindowLine(self.id, right, -1, right, bottom, Theme.THREE_D_HIGHLIGHT, miniwin.pen_solid, 1)
   else
      self.hotspot_map[self.id.."_close"] = nil
   end

   if self.resizer_type then
      self.hotspot_map[self.id.."_resize"] = self
      Theme.AddResizeTag(self.id, self.resizer_type, nil, nil, "ThemedWindowClass.ResizeMouseDownCallback", "ThemedWindowClass.ResizeMoveCallback", "ThemedWindowClass.ResizeReleaseCallback")
   else
      self.hotspot_map[self.id.."_resize"] = nil
   end
end

function ThemedWindowClass:get_menu_items()
   local menu_table = {
      "Bring To Front",
      "Send To Back"
   }
   local menu_handlers = {
      function() self:bring_to_front() end,
      function() self:send_to_back() end
   }
   local menu_string = table.concat(menu_table, "|")
   return menu_string, menu_handlers
end

function ThemedWindowClass:right_click_menu(hotspot_id)
   local menu_string, menu_handlers = self:get_menu_items()
   
   if menu_string:sub(1,1) ~= "!" then
      menu_string = "!"..menu_string
   end

   local result = tonumber(WindowMenu(
      self.id,
      WindowInfo(self.id, 14), -- x coord
      WindowInfo(self.id, 15), -- y coord
      menu_string
   ))
   if result then
      menu_handlers[result]()
   end
end


function ThemedWindowClass.RightClickMenuCallback(flags, hotspot_id, win)
   if bit.band(flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      local window = ThemedWindowClass.hotspot_map[hotspot_id] or ThemedWindowClass.window_map[win]
      window:right_click_menu(hotspot_id)
      return true
   end
   return false
end

function ThemedWindowClass.LeftButtonOnlyCallback(flags, hotspot_id, win)
   if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      return true
   end
   return false
end

function ThemedWindowClass.SavePositionAfterDrag(flags, hotspot_id, win)
   if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      return true
   end
   movewindow.save_state(win)
   return false
end

function ThemedWindowClass:show()
   WindowShow(self.id, true)
end

function ThemedWindowClass:hide()
   WindowShow(self.id, false)
end

function ThemedWindowClass:bring_to_front()
   CallPlugin("462b665ecb569efbf261422f","boostMe", self.id)
end

function ThemedWindowClass:send_to_back()
   CallPlugin("462b665ecb569efbf261422f","dropMe", self.id)
end


function ThemedBasicWindow(
   id, default_left_position, default_top_position, default_width, default_height, title, title_alignment, is_temporary, 
   resizer_type, do_while_resizing, do_after_resizing, do_on_delete, title_font_name, title_font_size
)
   assert(id, "ThemedBasicWindow Error: argument 1, id is required")
   assert(default_left_position, "ThemedBasicWindow Error: argument 2, default_left_position is required")
   assert(default_top_position, "ThemedBasicWindow Error: argument 3, default_top_position is required")
   assert(default_width, "ThemedBasicWindow Error: argument 4, default_width is required")
   assert(default_height, "ThemedBasicWindow Error: argument 5, default_height is required")

   if ThemedWindowClass.window_map[id] then
      ThemedWindowClass.window_map[id]:delete()
   end

   local self = {
      id = id,
      title_font_name = title_font_name or "Dina",
      title_font_size = title_font_size or 10,
      title = Theme.ToMultilineStyles(title),
      min_width = 100,
      min_height = 50,
      default_left_position = default_left_position,
      default_top_position = default_top_position,
      default_width = default_width,
      default_height = default_height,
      title_alignment = title_alignment,
      do_while_resizing = do_while_resizing,
      do_after_resizing = do_after_resizing,
      do_on_delete = do_on_delete,
      resizer_type = resizer_type,
      is_temporary = is_temporary,
      width = tonumber(GetVariable(id.."width")) or default_width,
      height = tonumber(GetVariable(id.."height")) or default_height,
   }
   setmetatable(self, ThemedWindowClass)

   self.window_map[self.id] = self

   self.windowinfo = movewindow.install(self.id, miniwin.pos_top_right, miniwin.create_absolute_location, false, nil, {mouseup=self.RightClickMenuCallback, mousedown=self.LeftButtonOnlyCallback, dragmove=self.LeftButtonOnlyCallback, dragrelease=self.SavePositionAfterDrag},{x=default_left_position, y=default_top_position})
   WindowCreate(self.id, self.windowinfo.window_left, self.windowinfo.window_top, self.width, self.height, self.windowinfo.window_mode, self.windowinfo.window_flags, Theme.PRIMARY_BODY)
   WindowFont(self.id, self.title_font, self.title_font_name, self.title_font_size, false, false, false, false, 0)
   self:dress_window()
   WindowShow(self.id, true)

   return self
end






ThemedTextWindowClass = setmetatable({}, ThemedWindowClass)
ThemedTextWindowClass.__index = ThemedTextWindowClass

function ThemedTextWindowClass:__set_text_rect(rewrap)
   local tr_right = self.bodyright
   if self.scrollbar then
      tr_right = tr_right - Theme.RESIZER_SIZE + 1
   end
   self.textrect:setRect(self.bodyleft, self.bodytop, tr_right, self.bodybottom-1)
   if rewrap then
      self.textrect:reWrapLines()
   end
   self.textrect:draw()
end

function ThemedTextWindowClass:__set_scrollbar()
   if self.scrollbar then
      local tr_right = self.bodyright - Theme.RESIZER_SIZE + 1
      self.scrollbar:setRect(tr_right, self.bodytop, self.bodyright, self.bodybottom-Theme.RESIZER_SIZE)
      self.scrollbar:draw()
   end
end

function ThemedTextWindowClass:do_while_resizing()
   self:__set_text_rect(false)
   self:__set_scrollbar()
end


function ThemedTextWindowClass:do_after_resizing()
   self:__set_text_rect(true)
   self:__set_scrollbar()
end

function ThemedTextWindowClass:OnDelete()
   self.textrect:unInit()
   if self.scrollbar then
      self.scrollbar:unInit()
   end
end

function ThemedTextWindowClass:add_text(styles_or_color_coded_text, draw_after)
   draw_after = (draw_after == nil) or (draw_after == true)
   self.textrect:addText(styles_or_color_coded_text)
   if draw_after then
      self:draw()
   end
end

function ThemedTextWindowClass:__draw_framing()
   if self.scrollbar then
      self.scrollbar:draw()
   else
      if self.resizer_type then
         -- the text goes "under" the resizer, so we have to re-dress
         self:dress_window()
      end
   end
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function ThemedTextWindowClass:draw()
   self.textrect:draw()
   self:__draw_framing()
end

-- deprecated
function ThemedTextWindowClass:add_color_line(color_text)
   self:add_text(color_text)
end

-- deprecated
function ThemedTextWindowClass:add_styles(styles)
   self:add_text(styles)
end

function ThemedTextWindowClass:clear(draw_after)
   draw_after = (draw_after == nil) or (draw_after == true)
   self.textrect:clear(draw_after)
   if draw_after then
      self:__draw_framing()
   end
end

function ThemedTextWindow(
   id, default_left_position, default_top_position, default_width, default_height, title, title_alignment, 
   is_temporary, resizeable, text_scrollable, text_selectable, text_copyable, url_hyperlinks,
   autowrap,
   title_font_name, title_font_size, text_font_name, text_font_size, text_max_lines, text_padding
)
   assert(id, "ThemedTextWindow Error: argument 1, id is required")
   assert(default_left_position, "ThemedTextWindow Error: argument 2, default_left_position is required")
   assert(default_top_position, "ThemedTextWindow Error: argument 3, default_top_position is required")
   assert(default_width, "ThemedTextWindow Error: argument 4, default_width is required")
   assert(default_height, "ThemedTextWindow Error: argument 5, default_height is required")

   require "text_rect"
   if text_scrollable then
      require "scrollbar"
   end
   local resizer_type = nil
   if resizeable then
      if text_scrollable then
         resizer_type = 2
      else
         resizer_type = 1
      end
   end

   local self = ThemedBasicWindow(
      id, default_left_position, default_top_position, default_width, default_height, title, title_alignment, is_temporary, 
      resizer_type, ThemedTextWindowClass.do_while_resizing, ThemedTextWindowClass.do_after_resizing, 
      ThemedTextWindowClass.OnDelete, title_font_name, title_font_size
   )
   setmetatable(self, ThemedTextWindowClass)

   local tr_right = self.bodyright
   if text_scrollable then
      tr_right = tr_right - Theme.RESIZER_SIZE + 1
   end
   local scrollbar_bottom = self.bodybottom
   if self.resizer_type then
      scrollbar_bottom = scrollbar_bottom-Theme.RESIZER_SIZE
   end
   self.textrect = TextRect.new(
      self.id, "textrect", self.bodyleft, self.bodytop, tr_right, self.bodybottom-1, text_max_lines, 
      text_scrollable, Theme.PRIMARY_BODY, text_padding, text_font_name, text_font_size, nil, nil, not text_selectable,
      not text_copyable, not url_hyperlinks, not autowrap
   )
   self.textrect:setExternalMenuFunction(function() return self:get_menu_items() end)
   if text_scrollable then
      self.min_height = 100   
      self.scrollbar = ScrollBar.new(self.id, "scrollbar", tr_right, self.bodytop, self.bodyright, scrollbar_bottom)
      self.textrect:addUpdateCallback(self.scrollbar, self.scrollbar.setScroll)
      self.scrollbar:addUpdateCallback(self.textrect, self.textrect.setScroll)
   end
   self:clear(true)
   return self
end



-- global function overrides

ThemedWindowClass.proxyStore = {}

function proxy_G(proxy_function_map)
   local proxyMetatable = {}
   function proxyMetatable.__index(t, k)
      return proxy_function_map[k] or rawget(world, k)
   end
   function proxyMetatable.__newindex(t, k, v)
      if proxy_function_map[k] then
         ThemedWindowClass.proxyStore[k] = v
      else
         rawset(_G, k, v)
      end
   end
   for k, _ in pairs(proxy_function_map) do
      ThemedWindowClass.proxyStore[k] = _G[k]
      _G[k] = nil
   end
   setmetatable(_G, proxyMetatable)   
end

-- wrap world.WindowCreate
function NewWindowCreate(w, ...)
   ret = world.WindowCreate(w, ...)
   CallPlugin("462b665ecb569efbf261422f", "registerMiniwindow", w)
   return ret
end

-- wrap OnPluginBroadcast even if it hasn't been created yet
function NewOnPluginBroadcast(msg, id, name, text)
   if (id == "462b665ecb569efbf261422f" and msg==996 and text == "re-register z") then
      for win_id, _ in pairs(ThemedWindowClass.window_map) do
         CallPlugin("462b665ecb569efbf261422f", "registerMiniwindow", win_id)
      end
   end
   local func = ThemedWindowClass.proxyStore["OnPluginBroadcast"] or rawget(_G, "OnPluginBroadcast")
   if func then
      func(msg, id, name, text)
   end
end

proxy_G({OnPluginBroadcast=NewOnPluginBroadcast, WindowCreate=NewWindowCreate})
