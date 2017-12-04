require "commas"
require "mw_theme_base"

ScrollBar = {
   hotspot_map = {}
}
ScrollBar_defaults = {
   total_steps = 1,
   visible_steps = 1,
   step = 1
}
ScrollBar_mt = { __index = ScrollBar }

function ScrollBar.new(window, name, left, top, width, height)
   new_sb = setmetatable(copytable.deep(ScrollBar_defaults), ScrollBar_mt)
   new_sb.id = "ScrollBar_"..window.."_"..tostring(GetUniqueNumber())
   new_sb.name = name
   new_sb.window = window
   new_sb.left = left
   new_sb.top = top
   new_sb.width = width
   new_sb.height = height
   return new_sb
end

function ScrollBar:initButtons()
   -- scroll bar up/down button hotspots
   WindowAddHotspot(self.window, self:generateHotspotID("up"), self.left, self.top, self.left + self.width, self.top + self.width, "", "", "ScrollBar.mouseDownUpArrow", "ScrollBar.cancelMouseDown", "ScrollBar.mouseUp", "", 1, 0)
   WindowAddHotspot(self.window, self:generateHotspotID("down"), self.left, self.top + self.height - self.width, self.left + self.width, self.top + self.height, "", "", "ScrollBar.mouseDownDownArrow", "ScrollBar.cancelMouseDown", "ScrollBar.mouseUp", "", 1, 0)
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

function ScrollBar:setRect(left, top, width, height)
   self.left = left
   self.top = top
   self.width = width
   self.height = height
   WindowMoveHotspot(self.window, self:generateHotspotID("up"), self.left, self.top, self.left + self.width, self.top + self.width)
   WindowMoveHotspot(self.window, self:generateHotspotID("down"), self.left, self.top + self.height - self.width, self.left + self.width, self.top + self.height)
end

function ScrollBar:doUpdateCallbacks()
   if self.update_callbacks then
      for _, cb in ipairs(self.update_callbacks) do
         local obj = cb[1]
         local func = cb[2]
         func(obj, self.step)
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
      self.left, self.top + self.width, self.left + self.width, self.top + self.height - self.width,
      theme.INACTIVE_BODY, miniwin.pen_solid, 1,
      theme.THREE_D_SURFACE, miniwin.brush_fine_pattern) -- brush

--   WindowRectOp(self.window, 2, self.left, self.top + self.width, self.left + self.width, self.top + self.height - self.width, theme.INACTIVE_BODY) -- scroll bar background
   WindowRectOp(self.window, 1, self.left + 2, self.top + self.width + 2, self.left + self.width - 2, self.top + self.height - self.width - 2, theme.BODY_CONTRAST) -- scroll bar background inset rectangle

   local mid_x = (self.width - 2)/2

   -- draw the up button
   local points = ""

   if (self.keepscrolling == "up") then
      Draw3DRect(self.window, self.left, self.top, self.left + self.width, self.top + self.width, true)
      points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
         self.left + math.floor(mid_x) + 1, self.top + math.ceil(self.width/4 + 0.5) + 2, self.left + math.floor(mid_x) - math.floor(mid_x/2) + 1, self.top + round_banker(self.width/2) + 2,
         self.left + math.ceil(mid_x) + math.floor(mid_x/2) + 1, self.top + round_banker(self.width/2) + 2,
         self.left + math.ceil(mid_x) + 1, self.top + math.ceil(self.width/4 + 0.5) + 2 )
   else
      Draw3DRect(self.window, self.left, self.top, self.left + self.width, self.top + self.width, false)
      points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
         self.left + math.floor(mid_x), self.top + math.ceil(self.width/4 + 0.5) + 1, self.left + math.floor(mid_x) - math.floor(mid_x/2), self.top + round_banker(self.width/2) + 1,
         self.left + math.ceil(mid_x) + math.floor(mid_x/2), self.top + round_banker(self.width/2) + 1,
         self.left + math.ceil(mid_x), self.top + math.ceil(self.width/4 + 0.5) + 1)
   end
   WindowPolygon(self.window, points, theme.THREE_D_SURFACE_DETAIL, miniwin.pen_solid + miniwin.pen_join_miter, 1, theme.THREE_D_SURFACE_DETAIL, 0, true, false)

   -- draw the down button
   if (self.keepscrolling == "down") then
      Draw3DRect(self.window, self.left, self.top + self.height - self.width, self.left + self.width, self.top + self.height, true)
      points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
         self.left + math.floor(mid_x) + 1, self.top + self.height - 1 - math.ceil(self.width/4 + 0.5), self.left + math.floor(mid_x) - math.floor(mid_x/2) + 1, self.top + self.height - 1 - round_banker(self.width/2),
         self.left + math.ceil(mid_x) + math.floor(mid_x/2) + 1, self.top + self.height - 1 - round_banker(self.width/2),
         self.left + math.ceil(mid_x) + 1, self.top + self.height - 1 - math.ceil(self.width/4 + 0.5))
   else
      Draw3DRect(self.window, self.left, self.top + self.height - self.width, self.left + self.width, self.top + self.height, false)
      points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
         self.left + math.floor(mid_x), self.top + self.height - 2 - math.ceil(self.width/4 + 0.5), self.left + math.floor(mid_x) - math.floor(mid_x/2), self.top + self.height - 2 - round_banker(self.width/2),
         self.left + math.ceil(mid_x) + math.floor(mid_x/2), self.top + self.height - 2 - round_banker(self.width/2),
         self.left + math.ceil(mid_x), self.top + self.height - 2 - math.ceil(self.width/4 + 0.5))
   end
   WindowPolygon(self.window, points, 0x000000, 0, 1, 0x000000, 0, true, false)

   -- draw the content indicator
   slots = math.max(0, self.total_steps - self.visible_steps)
   local position
   local scroll_height = self.height - (2 * self.width)
   if slots ~= 0 then
      self.size = math.max(10, scroll_height - slots)
      local available_space = scroll_height - self.size
      local space_per_step = available_space / slots
      position = self.top + self.width + (space_per_step * (self.step-1))
      if position + self.size > self.top + self.height - self.width then
         position = self.height + self.top - self.size - self.width
      end
   else
      position = self.top + self.width
      self.size = scroll_height
   end
   if (not self.has_hotspots) then
      WindowAddHotspot(self.window, self:generateHotspotID("scroller"), self.left, position, self.left + self.width, position + self.size, "", "", "ScrollBar.mouseDown", "", "ScrollBar.mouseUp", "", 1, 0)
      WindowDragHandler(self.window, self:generateHotspotID("scroller"), "ScrollBar.dragMove", "ScrollBar.dragRelease", 0)
   else
      WindowMoveHotspot(self.window, self:generateHotspotID("scroller"), self.left, position, self.left + self.width, position + self.size)
   end
   Draw3DRect(self.window, self.left, position, self.left + self.width, position + self.size)
   BroadcastPlugin(999, "repaint")
   self.has_hotspots = true

   if not inside_callback then
      self:doUpdateCallbacks()
   end
end

function ScrollBar.mouseDown(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   sb.start_pos = WindowHotspotInfo(sb.window, sb:generateHotspotID("scroller"), 2) - WindowInfo(sb.window, 15)
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
   local available_end = sb.top + sb.height - sb.width - sb.size
   local position = math.min(math.max(top_coord, available_begin), available_end) - available_begin
   sb.dragging_scrollbar = true
   local available_space = sb.height - (2 * sb.width) - sb.size
   if available_space > 0 then
      local space_per_step = available_space / (sb.total_steps - sb.visible_steps)
      sb.step = math.floor(position / space_per_step) + 1
   end
   sb:draw()
end

function ScrollBar.dragRelease(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   sb.dragging_scrollbar = false
   sb:draw()
end

function ScrollBar.cancelMouseDown(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   sb.keepscrolling = ""
   sb:draw()
end

function ScrollBar.mouseUp(flags, hotspot_id)
   local sb = ScrollBar.hotspot_map[hotspot_id]
   sb.keepscrolling = ""
   sb:draw()
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
         wait.time(0.01)
      end
   end)
end
