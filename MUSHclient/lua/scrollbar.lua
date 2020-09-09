require "commas"
require "mw_theme_base"
require "wait"

ScrollBar = {
   hotspot_map = {}
}
ScrollBar_defaults = {
   total_steps = 1,
   visible_steps = 1,
   step = 1
}
ScrollBar_mt = { __index = ScrollBar }

function ScrollBar.new(window, name, left, top, right, bottom, min_thumb_size)
   new_sb = setmetatable(copytable.deep(ScrollBar_defaults), ScrollBar_mt)
   new_sb.id = "ScrollBar_"..window.."_"..name
   new_sb.name = name
   new_sb.window = window
   new_sb.left = left
   new_sb.top = top
   new_sb.right = right
   new_sb.bottom = bottom
   new_sb.width = right-left
   new_sb.height = bottom-top
   new_sb.min_thumb_size = min_thumb_size or 10
   return new_sb
end

function ScrollBar:initButtons()
   -- scroll bar up/down button hotspots
   WindowAddHotspot(self.window, self:generateHotspotID("up"), self.left, self.top, self.right, self.top + self.width, "", "", "ScrollBar.mouseDownUpArrow", "ScrollBar.cancelMouseDown", "ScrollBar.mouseUp", "", 1, 0)
   WindowAddHotspot(self.window, self:generateHotspotID("down"), self.left, self.bottom - self.width, self.right, self.bottom, "", "", "ScrollBar.mouseDownDownArrow", "ScrollBar.cancelMouseDown", "ScrollBar.mouseUp", "", 1, 0)
end

function ScrollBar:_delHotspot(key)
   local id = self:generateHotspotID(key)
   ScrollBar.hotspot_map[id] = nil
   WindowDeleteHotspot(self.window, id)
end

function ScrollBar:unInit()
   self.has_hotspots = false
   self:_delHotspot("up")
   self:_delHotspot("down")
   self:_delHotspot("scroller")
end

function ScrollBar:setRect(left, top, right, bottom)
   if (self.left ~= left) or (self.top ~= top) or (self.right ~= right) or (self.bottom ~= bottom) then
      self.left = left
      self.top = top
      self.right = right
      self.bottom = bottom
      self.width = right-left
      self.height = bottom-top
      WindowMoveHotspot(self.window, self:generateHotspotID("up"), self.left, self.top, self.right, self.top + self.width)
      WindowMoveHotspot(self.window, self:generateHotspotID("down"), self.left, self.bottom - self.width, self.right, self.bottom)
   end
end

function ScrollBar:doUpdateCallbacks()
   if self.update_callbacks then
      for _, cb in ipairs(self.update_callbacks) do
         local obj = cb[1]
         local func = cb[2]
         if obj then
            func(obj, self.step)
         else
            func(self.step)
         end
      end
   end
end

function ScrollBar:setScroll(step, visible_steps, total_steps)
   self.step = step or self.step
   self.visible_steps = visible_steps or self.visible_steps
   self.total_steps = total_steps or self.total_steps
   self:draw(true)
end

function ScrollBar:draw(inside_callback)
   if not self.has_hotspots then
      self:initButtons()
   end

   -- draw the background
   WindowCircleOp(
      self.window, miniwin.circle_rectangle,
      self.left, self.top + self.width + 1, self.right + 1, self.bottom - self.width,
      Theme.SCROLL_TRACK_COLOR1, miniwin.pen_solid, 1,
      Theme.SCROLL_TRACK_COLOR2, Theme.VERTICAL_TRACK_BRUSH)

   local mid_x = (self.width - 2)/2

   -- draw the up button
   local points = ""

   if (self.keepscrolling == "up") then -- button depressed
      Theme.Draw3DRect(self.window, self.left, self.top, self.right, self.top + self.width, true)
      points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
         self.left + math.floor(mid_x) + 3, self.top + math.ceil(self.width/4 + 0.5) + 3,
         self.left + math.floor(mid_x) - math.floor(mid_x/2) + 3, self.top + round_banker(self.width/2) + 3,
         self.left + math.ceil(mid_x) + math.floor(mid_x/2) + 3, self.top + round_banker(self.width/2) + 3,
         self.left + math.ceil(mid_x) + 3, self.top + math.ceil(self.width/4 + 0.5) + 3 )
   else
      Theme.Draw3DRect(self.window, self.left, self.top, self.right, self.top + self.width, false)
      points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
         self.left + math.floor(mid_x) + 1, self.top + math.ceil(self.width/4 + 0.5) + 1,
         self.left + math.floor(mid_x) - math.floor(mid_x/2) + 1, self.top + round_banker(self.width/2) + 1,
         self.left + math.ceil(mid_x) + math.floor(mid_x/2) + 1, self.top + round_banker(self.width/2) + 1,
         self.left + math.ceil(mid_x) + 1, self.top + math.ceil(self.width/4 + 0.5) + 1)
   end
   WindowPolygon(self.window, points, Theme.THREE_D_SURFACE_DETAIL, miniwin.pen_solid + miniwin.pen_join_miter, 1, Theme.THREE_D_SURFACE_DETAIL, 0, true, false)

   -- draw the down button
   if (self.keepscrolling == "down") then -- button depressed
      Theme.Draw3DRect(self.window, self.left, self.bottom - self.width, self.right, self.bottom, true)
      points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
         self.left + math.floor(mid_x) + 3, self.bottom - math.ceil(self.width/4 + 0.5) + 1,
         self.left + math.floor(mid_x) - math.floor(mid_x/2) + 3, self.bottom - round_banker(self.width/2) + 1,
         self.left + math.ceil(mid_x) + math.floor(mid_x/2) + 3, self.bottom - round_banker(self.width/2) + 1,
         self.left + math.ceil(mid_x) + 3, self.bottom - math.ceil(self.width/4 + 0.5) + 1)
   else
      Theme.Draw3DRect(self.window, self.left, self.bottom - self.width, self.right, self.bottom, false)
      points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
         self.left + math.floor(mid_x) + 1, self.bottom - 1 - math.ceil(self.width/4 + 0.5),
         self.left + math.floor(mid_x) - math.floor(mid_x/2) + 1, self.bottom - 1 - round_banker(self.width/2),
         self.left + math.ceil(mid_x) + math.floor(mid_x/2) + 1, self.bottom - 1 - round_banker(self.width/2),
         self.left + math.ceil(mid_x) + 1, self.bottom - 1 - math.ceil(self.width/4 + 0.5))
   end
   WindowPolygon(self.window, points, Theme.THREE_D_SURFACE_DETAIL, miniwin.pen_solid + miniwin.pen_join_miter, 1, Theme.THREE_D_SURFACE_DETAIL, 0, true, false)

   -- draw the content indicator
   slots = math.max(0, self.total_steps - self.visible_steps)
   local position
   local scroll_height = self.height - (2 * self.width) - 2
   if slots ~= 0 then
      self.size = math.min(scroll_height, math.max(self.min_thumb_size, scroll_height - slots))
      local available_space = scroll_height - self.size
      local space_per_step = available_space / slots
      position = self.top + self.width + math.ceil(space_per_step * self.step)
      if position > self.bottom - self.width - self.size then
         position = self.bottom - self.width - self.size
      end
   else
      position = self.top + self.width + 1
      self.size = scroll_height
   end
   if (not self.has_hotspots) then
      WindowAddHotspot(self.window, self:generateHotspotID("scroller"), self.left, position, self.right, position + self.size, "", "", "ScrollBar.mouseDown", "", "ScrollBar.mouseUp", "", 1, 0)
      WindowDragHandler(self.window, self:generateHotspotID("scroller"), "ScrollBar.dragMove", "ScrollBar.dragRelease", 0)
   else
      WindowMoveHotspot(self.window, self:generateHotspotID("scroller"), self.left, position, self.right, position + self.size)
   end
   Theme.Draw3DRect(self.window, self.left, position, self.right, position + self.size, false)

   self.has_hotspots = true

   if not inside_callback then
      self:doUpdateCallbacks()
   end
end

function ScrollBar.mouseDown(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   sb.start_pos = WindowHotspotInfo(sb.window, hotspot_id, 2) - WindowInfo(sb.window, 15)
   sb.dragging_scrollbar = true
end

function ScrollBar.mouseDownDownArrow(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   sb.keepscrolling = "down"
   sb:scroll()
end

function ScrollBar.mouseDownUpArrow(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   sb.keepscrolling = "up"
   sb:scroll()
end

function ScrollBar:addUpdateCallback(object, callback)
   self.update_callbacks = self.update_callbacks or {}
   table.insert(self.update_callbacks, {object, callback})
end

function ScrollBar.dragMove(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   local mouse_y = WindowInfo(sb.window, 18) - WindowInfo(sb.window, 2)
   local top_coord = mouse_y + sb.start_pos
   local bottom_coord = top_coord + sb.size
   local available_begin = sb.top + sb.width
   local available_end = sb.bottom - sb.width - sb.size
   local position = math.min(math.max(top_coord, available_begin), available_end) - available_begin
   sb.dragging_scrollbar = true
   local available_space = sb.height - (2 * sb.width) - sb.size
   if available_space > 0 then
      local space_per_step = available_space / (sb.total_steps - sb.visible_steps)
      sb.step = math.floor(position / space_per_step) + 1
   end
   sb:draw()
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function ScrollBar.dragRelease(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   sb.dragging_scrollbar = false
   sb:draw()
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function ScrollBar.cancelMouseDown(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   sb.keepscrolling = ""
   sb:draw()
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
end

function ScrollBar.mouseUp(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   sb.keepscrolling = ""
   sb:draw()
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
   return true
end

function ScrollBar:generateHotspotID(id)
   local hotspot_id = self.id.."_hotspot_"..id
   ScrollBar.hotspot_map[hotspot_id] = self
   return hotspot_id
end

-- Scroll through the contents step by step. Used when pressing the up/down arrow buttons.
function ScrollBar:scroll()
   wait.make(function ()
      while self.keepscrolling == "up" or self.keepscrolling == "down" do
         if self.keepscrolling == "up" then
            if (self.step > 1) then
               self.step = self.step - 1
            end
         elseif self.keepscrolling == "down" then
            if ((self.step + self.visible_steps) <= self.total_steps) then
               self.step = self.step + 1
            end
         end
         self:draw()
         CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
         wait.time(0.01)
      end
   end)
end
