require "aard_register_z_on_create"
require "mw_theme_base"
require "movewindow"

Window = {
   hotspot_map = {},
   window_map = {},
   blank = function(window)
      WindowRectOp(window.id, 2, window.bodyleft, window.bodytop, window.bodyright+1, window.bodybottom+1, Theme.PRIMARY_BODY)
   end
}

local title_font = "Window_title_font"

function BaseWindow(
   id, default_left, default_top, default_width, default_height, title, title_alignment, is_temporary, 
   resizer_type, do_while_resizing, do_after_resizing, do_on_delete, title_font_name, title_font_size
)
   if Window.window_map[id] and Window.window_map[id].do_on_delete then
      Window.prepare_to_delete(Window.window_map[id])
      WindowDelete(id)
   end

   local self = {
      id = id,
      title_font_name = title_font_name or "Dina",
      title_font_size = title_font_size or 10,
      title = title,
      min_width = 100,
      min_height = 50,
      title_alignment = title_alignment,
      do_while_resizing = do_while_resizing,
      do_after_resizing = do_after_resizing,
      do_on_delete = do_on_delete,
      resizer_type = resizer_type,
      is_temporary = is_temporary,
      width = tonumber(GetVariable(id.."width")) or default_width,
      height = tonumber(GetVariable(id.."height")) or default_height,
      windowinfo = movewindow.install(id, miniwin.pos_top_right, miniwin.create_absolute_location, false, nil, {mousedown=Window.LeftClickOnlyCallback, dragmove=Window.LeftClickOnlyCallback, dragrelease=Window.SavePositionAfterDrag},{x=default_left, y=default_top})
   }

   function self.dress_window()
      local title = self.title
      if self.is_temporary then
         title = "  "..self.title
      end
      self.bodyleft, self.bodytop, self.bodyright, self.bodybottom = Theme.DressWindow(self.id, title_font, title, self.title_alignment)
      if self.is_temporary then
         local padding = Theme.TITLE_PADDING
         Window.hotspot_map[self.id.."_close"] = self
         Theme.Add3DButton(self.id, self.id.."_close", title_font, -1, -1, "X", false, padding, padding, "Remove Window", nil, Window.DeleteCallback)
      else
         Window.hotspot_map[self.id.."_close"] = nil
      end
      if self.resizer_type then
         Window.hotspot_map[self.id.."_resize"] = self
         Theme.AddResizeTag(self.id, self.resizer_type, nil, nil, "Window.ResizeMouseDownCallback", "Window.ResizeMoveCallback", "Window.ResizeReleaseCallback")
      else
         Window.hotspot_map[self.id.."_resize"] = nil
      end
   end

   function self.resize(width, height, during_resize)
      self.width = width
      self.height = height
      WindowResize(self.id, width, height, Theme.PRIMARY_BODY)
      _, _, _, self.bodyleft, self.bodytop, self.bodyright, self.bodybottom = Theme.BodyMetrics(self.id, title_font, self.title)
      if during_resize then
         if self.do_while_resizing then
            self.do_while_resizing(self)
         end
      else
         if self.do_after_resizing then
            self.do_after_resizing(self)
         end
      end
      self.dress_window()
   end

   WindowCreate(self.id, self.windowinfo.window_left, self.windowinfo.window_top, self.width, self.height, self.windowinfo.window_mode, self.windowinfo.window_flags, Theme.PRIMARY_BODY)
   WindowFont(self.id, title_font, self.title_font_name, self.title_font_size, false, false, false, false, 0)
   WindowShow(self.id, true)
   self.dress_window()

   Window.window_map[self.id] = self
   return self
end

function Window.prepare_to_delete(window)
   for k, v in pairs(Window.hotspot_map) do
      if v.id == window.id then
         Window.hotspot_map[k] = nil
      end
   end
   if window.do_on_delete then
      window.do_on_delete(window)
   end
   Window.window_map[window.id] = nil
end

function Window.DeleteCallback(flags, hotspot_id)
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   local window = Window.hotspot_map[hotspot_id]
   Window.prepare_to_delete(window)
   DoAfterSpecial(0.1, "WindowDelete(\""..window.id.."\")", 12)
end

function Window.ResizeMouseDownCallback(flags, hotspot_id)
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   local window = Window.hotspot_map[hotspot_id]
   window.resize_startx = WindowInfo(window.id, 17)
   window.resize_starty = WindowInfo(window.id, 18)
end

function Window.ResizeMoveCallback(flags, hotspot_id)
   if GetPluginVariable("c293f9e7f04dde889f65cb90", "lock_down_miniwindows") == "1" then
      return
   end
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   local window = Window.hotspot_map[hotspot_id]

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
      window.resize(window.width, window.height, true)
      CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
      lastRefresh = utils.timer()
   end
end

lastRefresh = 0

function Window.ResizeReleaseCallback(flags, hotspot_id)
   if bit.band(flags, miniwin.hotspot_got_lh_mouse) == 0 then
      return  -- ignore non-left mouse button
   end
   local window = Window.hotspot_map[hotspot_id]
   window.resize(window.width, window.height, false)
   SetVariable(window.id.."width", window.width)
   SetVariable(window.id.."height", window.height)
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function Window.LeftClickOnlyCallback(flags, hotspot_id, win)
   if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      return true
   end
   return false
end

function Window.SavePositionAfterDrag(flags, hotspot_id, win)
   if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      return true
   end
   movewindow.save_state(win)
   return false
end


function TextWindow(
   id, default_left, default_top, default_width, default_height, title, title_alignment, 
   is_temporary, resizeable, text_scrollable, title_font_name, title_font_size,
   text_font_name, text_font_size, text_max_lines, text_padding
)
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

   local function DuringResize(window)
      local tr_right = window.bodyright
      if window.scrollbar then
         tr_right = tr_right - Theme.RESIZER_SIZE + 1
      end
      window.textrect:setRect(window.bodyleft, window.bodytop, tr_right, window.bodybottom)
      if window.scrollbar then
         window.scrollbar:setRect(tr_right, window.bodytop, window.bodyright, window.bodybottom-Theme.RESIZER_SIZE)
         window.scrollbar:draw()
      end
      window.textrect:draw()
   end

   local function AfterResize(window)
      local tr_right = window.bodyright
      if window.scrollbar then
         tr_right = tr_right - Theme.RESIZER_SIZE + 1
      end
      window.textrect:setRect(window.bodyleft, window.bodytop, tr_right, window.bodybottom)
      window.textrect:reWrapLines()
      if window.scrollbar then
         window.scrollbar:setRect(tr_right, window.bodytop, window.bodyright, window.bodybottom-Theme.RESIZER_SIZE)
         window.scrollbar:draw()
      end
      window.textrect:draw()
   end

   local function OnDelete(window)
      window.textrect:unInit()
      if window.scrollbar then
         window.scrollbar:unInit()
      end
   end

   local self = BaseWindow(
      id, default_left, default_top, default_width, default_height, title, title_alignment, is_temporary, 
      resizer_type, DuringResize, AfterResize, OnDelete, title_font_name, title_font_size
   )

   local tr_right = self.bodyright
   if text_scrollable then
      tr_right = tr_right - Theme.RESIZER_SIZE + 1
   end
   local scrollbar_bottom = self.bodybottom
   if resizeable then
      scrollbar_bottom = scrollbar_bottom-Theme.RESIZER_SIZE
   end
   self.textrect = TextRect.new(self.id, "textrect", self.bodyleft, self.bodytop, tr_right, self.bodybottom, text_max_lines, text_scrollable, Theme.PRIMARY_BODY, text_padding, text_font_name, text_font_size)
   if text_scrollable then
      self.min_height = 100   
      self.scrollbar = ScrollBar.new(self.id, "scrollbar", tr_right, self.bodytop, self.bodyright, scrollbar_bottom)
      self.textrect:addUpdateCallback(self.scrollbar, self.scrollbar.setScroll)
      self.scrollbar:addUpdateCallback(self.textrect, self.textrect.setScroll)
   end

   function self.addColorLine(color_text)
      self.textrect:addColorLine(color_text)
      self.textrect:draw()
      if self.scrollbar then
         self.scrollbar:draw()
      else
         if resizeable then
            self.dress_window()
         end
      end
   end

   function self.addStyles(styles)
      self.textrect:addStyles(styles)
      self.textrect:draw()
      if self.scrollbar then
         self.scrollbar:draw()
      else
         if resizeable then
            self.dress_window()
         end
      end
   end
   
   function self.clear()
      self.textrect:clear()
      if self.scrollbar then
         self.scrollbar:draw()
      else
         if resizeable then
            self.dress_window()
         end
      end
   end

   self.clear()
   return self
end
