-- Shared snapping for visible miniwindows and other displayed rectangles.

local window_snap = {}

local feedback_prefix = "__aard_snap_feedback_"
local feedback_windows = {}
local feedback_slots = {}
local feedback_next_slot = 0

function window_snap.is_feedback_window(win)
   return win:sub(1, #feedback_prefix) == feedback_prefix
end

local function feedback_rectangle(axis, candidate)
   local screen_width, screen_height = GetInfo(281), GetInfo(280)
   if axis == "x" then
      local edge = candidate.coordinate
      if edge < 0 or edge > screen_width then return end
      local top = math.max(0, math.floor(candidate.low))
      local bottom = math.min(screen_height, math.ceil(candidate.high))
      if bottom <= top then return end
      local thickness = math.min(2, screen_width)
      local x = candidate.edge == "right" and edge - thickness or edge
      return math.max(0, math.min(screen_width - thickness, x)), top,
         thickness, bottom - top
   end
   local edge = candidate.coordinate
   if edge < 0 or edge > screen_height then return end
   local left = math.max(0, math.floor(candidate.low))
   local right = math.min(screen_width, math.ceil(candidate.high))
   if right <= left then return end
   local thickness = math.min(2, screen_height)
   local y = candidate.edge == "bottom" and edge - thickness or edge
   return left, math.max(0, math.min(screen_height - thickness, y)),
      right - left, thickness
end

local function feedback_key(candidate)
   -- A target edge remains the same contact when its displayed coordinate moves.
   return string.format("%s:%d:%s:%s", candidate.axis, #candidate.target,
      candidate.target, candidate.edge)
end

local function delete_feedback(key)
   local entry = feedback_windows[key]
   assert(WindowDelete(entry.win) == 0, "Cannot delete snap feedback window")
   feedback_windows[key] = nil
   feedback_slots[#feedback_slots + 1] = entry.win
end

function window_snap.hide_feedback()
   for key in pairs(feedback_windows) do
      delete_feedback(key)
   end
end

-- Keep each target's overlay while it matches. Update its rectangle in place
-- as the shared edge span changes, and remove it when contact ends.
function window_snap.show_feedback(selection)
   local matches = selection and selection.matches or {}
   if #matches == 0 then
      window_snap.hide_feedback()
      return
   end

   local desired, rectangles = {}, {}
   for _, candidate in ipairs(matches) do
      local left, top, width, height = feedback_rectangle(candidate.axis, candidate)
      if left then
         local key = feedback_key(candidate)
         if not desired[key] then
            desired[key] = true
            rectangles[#rectangles + 1] = {
               key = key, left = left, top = top, width = width, height = height,
               colour = ColourNameToRGB(candidate.corner and "yellow" or "cyan"),
            }
         end
      end
   end
   for key in pairs(feedback_windows) do
      if not desired[key] then delete_feedback(key) end
   end
   for _, rect in ipairs(rectangles) do
      local entry = feedback_windows[rect.key]
      if entry then
         local changed = entry.left ~= rect.left or entry.top ~= rect.top or
            entry.width ~= rect.width or entry.height ~= rect.height or
            entry.colour ~= rect.colour
         if changed then
            if entry.width ~= rect.width or entry.height ~= rect.height then
               assert(WindowResize(entry.win, rect.width, rect.height,
                  rect.colour) == 0, "Cannot resize snap feedback window")
            end
            if entry.left ~= rect.left or entry.top ~= rect.top then
               assert(WindowPosition(entry.win, rect.left, rect.top, 0,
                  miniwin.create_absolute_location + miniwin.create_ignore_mouse) == 0,
                  "Cannot move snap feedback window")
            end
            if entry.colour ~= rect.colour then
               assert(WindowRectOp(entry.win, miniwin.rect_fill, 0, 0,
                  rect.width, rect.height, rect.colour) == 0,
                  "Cannot recolour snap feedback window")
            end
            assert(WindowShow(entry.win, true) == 0, "Cannot refresh snap feedback window")
            entry.left, entry.top = rect.left, rect.top
            entry.width, entry.height, entry.colour = rect.width, rect.height, rect.colour
         end
      else
         local win = table.remove(feedback_slots)
         if not win then
            feedback_next_slot = feedback_next_slot + 1
            win = feedback_prefix .. (GetPluginID() or "world") .. "_" .. feedback_next_slot
         end
         assert(WindowCreate(win, rect.left, rect.top, rect.width, rect.height, 0,
            miniwin.create_absolute_location + miniwin.create_ignore_mouse,
            rect.colour) == 0, "Cannot create snap feedback window")
         assert(WindowSetZOrder(win, 99999) == 0, "Cannot raise snap feedback window")
         assert(WindowShow(win, true) == 0, "Cannot show snap feedback window")
         feedback_windows[rect.key] = {
            win = win, left = rect.left, top = rect.top,
            width = rect.width, height = rect.height, colour = rect.colour,
         }
      end
   end
end

function window_snap.finish_feedback()
   window_snap.hide_feedback()
end

-- The miniwindow's creator can return false from OnPluginSnapTarget(win)
-- to keep a helper window out of every drag and resize target scan.
local function target_allowed(target, snap)
   local cache = snap.targetable_cache
   if not cache then
      cache = {}
      snap.targetable_cache = cache
   end
   if cache[target] ~= nil then return cache[target] end

   local creator = WindowInfo(target, 23)
   local allowed = true
   if creator and creator ~= "" then
      local status, answer, detail = CallPlugin(creator, "OnPluginSnapTarget", target)
      if status == error_code.eOK then
         allowed = answer ~= false
      else
         -- An unavailable optional callback leaves the window targetable.
         assert(status == error_code.eNoSuchRoutine or
            status == error_code.ePluginDisabled or
            status == error_code.eNoSuchPlugin,
            "Cannot query snap target " .. target .. " from plugin " .. creator ..
            ": " .. tostring(detail or answer))
      end
   end
   cache[target] = allowed
   return allowed
end

function window_snap.enabled()
   return (GetPluginVariable("c293f9e7f04dde889f65cb90", "snap_miniwindows") or "1") == "1"
end

local function snap_setting(name, default, minimum)
   local value = tonumber(GetPluginVariable("c293f9e7f04dde889f65cb90", name) or default)
   assert(value and value > -math.huge and value < math.huge and value % 1 == 0 and
      (minimum == nil or value >= minimum),
      "Invalid miniwindow snap setting: " .. name)
   return value
end

function window_snap.get_settings()
   return snap_setting("snap_miniwindows_threshold", 7, 0),
      snap_setting("snap_miniwindows_offset", 0)
end

-- Spans must overlap, meet, or leave the configured gap. The threshold allows
-- both axes to approach a corner before the final positions are checked.
local function within_snap_span(position, size, low, high, threshold, offset)
   return (position + size >= low - threshold and position <= high + threshold) or
      math.abs(position + size - (low - offset)) <= threshold or
      math.abs(position - (high + offset)) <= threshold
end

-- Keep every target that aligns with the chosen coordinate. The visual span
-- is the shared part of the two edges, or a short mark at a corner.
local function matching_edges(candidates, position, span_position, span_size, axis, offset)
   local matches, seen = {}, {}
   for _, candidate in ipairs(candidates) do
      if candidate.target and candidate.position == position and
         within_snap_span(span_position, span_size, candidate.low, candidate.high, 0, offset) then
         local low = math.max(span_position, candidate.low)
         local high = math.min(span_position + span_size, candidate.high)
         local corner = high <= low
         if corner then
            local point = span_position + span_size <= candidate.low and
               candidate.low or candidate.high
            low = math.max(candidate.low, math.min(point, candidate.high - 8))
            high = math.min(candidate.high, low + 8)
         end
         local key = table.concat({axis, candidate.target, candidate.edge,
            candidate.coordinate, low, high}, ":")
         if not seen[key] then
            seen[key] = true
            matches[#matches + 1] = {
               axis = axis, target = candidate.target, edge = candidate.edge,
               coordinate = candidate.coordinate, low = low, high = high,
               corner = corner,
            }
         end
      end
   end
   table.sort(matches, function(a, b)
      if a.axis ~= b.axis then return a.axis < b.axis end
      if a.coordinate ~= b.coordinate then return a.coordinate < b.coordinate end
      if a.low ~= b.low then return a.low < b.low end
      if a.high ~= b.high then return a.high < b.high end
      if a.edge ~= b.edge then return a.edge < b.edge end
      return a.target < b.target
   end)
   return matches
end

local function add_snap_candidates(candidates, position, size, near, far, low, high,
   minimum, maximum, threshold, offset, target,
   near_edge, far_edge)
   -- Apply the offset to opposite edges. Matching edges stay aligned.
   for index, candidate in ipairs({near - size - offset, far + offset, near, far - size}) do
      if math.abs(candidate - position) <= threshold and
         candidate >= minimum and candidate <= maximum then
         local near_side = index == 1 or index == 3
         candidates[#candidates + 1] = {
            position = candidate, low = low, high = high, target = target,
            edge = near_side and near_edge or far_edge,
            coordinate = near_side and near or far,
         }
      end
   end
end

-- Snap an arbitrary displayed rectangle so non-miniwindow surfaces can use
-- the same visible targets, edge offsets, and corner selection as miniwindows.
function window_snap.snap_bounds(bounds, snap)
   local posx, posy = bounds.left, bounds.top
   local width, height = bounds.right - posx, bounds.bottom - posy
   if width <= 0 or height <= 0 then
      return posx, posy
   end

   local threshold, offset = snap.threshold, snap.offset
   local screen_width, screen_height = GetInfo(281), GetInfo(280)
   local excluded = snap.excluded or {}
   local area = snap.area or {left = 0, top = 0, right = screen_width, bottom = screen_height}
   local limits = snap.limits or {left = 0, top = 0, right = screen_width, bottom = screen_height}

   -- Keep the unsnapped position as a fallback for each axis.
   local xs, ys = {{position = posx}}, {{position = posy}}
   -- Area bounds align with the same edges of the dragged rectangle.
   add_snap_candidates(xs, posx, width, area.left, area.right, area.top, area.bottom,
      limits.left, limits.right, threshold, 0, "bounds", "left", "right")
   add_snap_candidates(ys, posy, height, area.top, area.bottom, area.left, area.right,
      limits.top, limits.bottom, threshold, 0, "bounds", "top", "bottom")
   for _, target in ipairs(WindowList() or {}) do
      if not excluded[target] and not window_snap.is_feedback_window(target) and
         WindowInfo(target, 5) and not WindowInfo(target, 6) and
         target_allowed(target, snap) then
         -- Use the displayed rectangle, including automatic positioning.
         local left, top = WindowInfo(target, 10), WindowInfo(target, 11)
         local right, bottom = WindowInfo(target, 12), WindowInfo(target, 13)
         if right > left and bottom > top and
            right > 0 and bottom > 0 and left < screen_width and top < screen_height then
            if within_snap_span(posy, height, top, bottom, threshold, offset) then
               add_snap_candidates(xs, posx, width, left, right, top, bottom,
                  limits.left, limits.right, threshold, offset, target, "left", "right")
            end
            if within_snap_span(posx, width, left, right, threshold, offset) then
               add_snap_candidates(ys, posy, height, top, bottom, left, right,
                  limits.top, limits.bottom, threshold, offset, target, "top", "bottom")
            end
         end
      end
   end

   local bestx, besty = posx, posy
   local best_x_candidate, best_y_candidate
   local best_count, best_distance = 0, 0
   for _, x in ipairs(xs) do
      for _, y in ipairs(ys) do
         -- Validate the final pair: one correction can affect the other edge.
         if (not x.low or within_snap_span(y.position, height, x.low, x.high, 0, offset)) and
            (not y.low or within_snap_span(x.position, width, y.low, y.high, 0, offset)) then
            local count = (x.low and 1 or 0) + (y.low and 1 or 0)
            local distance = (x.position - posx)^2 + (y.position - posy)^2
            -- Prefer snapping both axes, then the shortest move. Coordinate ties
            -- make the result independent of WindowList order.
            if count > best_count or
               (count == best_count and (distance < best_distance or
                  (distance == best_distance and (x.position < bestx or
                     (x.position == bestx and y.position < besty))))) then
               bestx, besty = x.position, y.position
               best_x_candidate, best_y_candidate = x, y
               best_count, best_distance = count, distance
            end
         end
      end
   end
   local matches = matching_edges(xs, bestx, besty, height, "x", offset)
   local horizontal = matching_edges(ys, besty, bestx, width, "y", offset)
   for _, candidate in ipairs(horizontal) do
      matches[#matches + 1] = candidate
   end
   return bestx, besty, {x = best_x_candidate, y = best_y_candidate,
      matches = matches}
end

-- Record the mouse and size once. Resize callbacks keep their own width and
-- height, so they must receive snapped mouse coordinates before they update them.
function window_snap.begin_resize(win, bounds, extra_excluded)
   if not window_snap.enabled() then
      return nil
   end
   local threshold, offset = window_snap.get_settings()
   return {
      win = win,
      mouse_x = WindowInfo(win, 17),
      mouse_y = WindowInfo(win, 18),
      width = bounds and (bounds.right - bounds.left) or WindowInfo(win, 3),
      height = bounds and (bounds.bottom - bounds.top) or WindowInfo(win, 4),
      left = bounds and bounds.left,
      top = bounds and bounds.top,
      extra_excluded = extra_excluded,
      threshold = threshold,
      offset = offset,
   }
end

local function add_resize_candidates(candidates, position, low_edge, high_edge,
   low, high, minimum, maximum, threshold,
   target, low_coordinate, high_coordinate,
   low_label, high_label)
   for index, edge in ipairs({low_edge, high_edge}) do
      if math.abs(edge - position) <= threshold and edge > minimum and edge <= maximum then
         candidates[#candidates + 1] = {
            position = edge, low = low, high = high, target = target,
            coordinate = index == 1 and low_coordinate or high_coordinate,
            edge = index == 1 and low_label or high_label,
         }
      end
   end
end

function window_snap.resize_coordinates(drag, mouse_x, mouse_y, right_limit,
   bottom_limit, friend_excluded)
   local win = drag.win
   local left = drag.left or WindowInfo(win, 10)
   local top = drag.top or WindowInfo(win, 11)
   local right = left + drag.width + mouse_x - drag.mouse_x
   local bottom = top + drag.height + mouse_y - drag.mouse_y
   local screen_width, screen_height = GetInfo(281), GetInfo(280)
   local threshold, offset = drag.threshold, drag.offset
   right_limit = right_limit or screen_width
   bottom_limit = bottom_limit or screen_height
   local xs, ys = {{position = right}}, {{position = bottom}}

   -- The output area edges always align flush.
   add_resize_candidates(xs, right, right_limit, right_limit,
      0, screen_height, left, right_limit, threshold,
      "bounds", right_limit, right_limit, "right", "right")
   add_resize_candidates(ys, bottom, bottom_limit, bottom_limit,
      0, screen_width, top, bottom_limit, threshold,
      "bounds", bottom_limit, bottom_limit, "bottom", "bottom")

   local excluded = {[win] = true}
   for _, other in ipairs(drag.extra_excluded or {}) do
      excluded[other] = true
   end
   for _, friend in ipairs(friend_excluded or {}) do
      if friend then excluded[friend] = true end
   end
   for _, target in ipairs(WindowList() or {}) do
      if not excluded[target] and not window_snap.is_feedback_window(target) and
         WindowInfo(target, 5) and not WindowInfo(target, 6) and
         target_allowed(target, drag) then
         local target_left, target_top = WindowInfo(target, 10), WindowInfo(target, 11)
         local target_right, target_bottom = WindowInfo(target, 12), WindowInfo(target, 13)
         if target_right > target_left and target_bottom > target_top and
            target_right > 0 and target_bottom > 0 and
            target_left < screen_width and target_top < screen_height then
            if within_snap_span(top, bottom - top, target_top, target_bottom,
               threshold, offset) then
               add_resize_candidates(xs, right, target_left - offset, target_right,
                  target_top, target_bottom, left, right_limit, threshold,
                  target, target_left, target_right, "left", "right")
            end
            if within_snap_span(left, right - left, target_left, target_right,
               threshold, offset) then
               add_resize_candidates(ys, bottom, target_top - offset, target_bottom,
                  target_left, target_right, top, bottom_limit, threshold,
                  target, target_top, target_bottom, "top", "bottom")
            end
         end
      end
   end

   local best_x, best_y = right, bottom
   local best_x_candidate, best_y_candidate
   local best_count, best_distance = 0, 0
   for _, x in ipairs(xs) do
      for _, y in ipairs(ys) do
         if (not x.low or within_snap_span(top, y.position - top, x.low, x.high, 0, offset)) and
            (not y.low or within_snap_span(left, x.position - left, y.low, y.high, 0, offset)) then
            local count = (x.low and 1 or 0) + (y.low and 1 or 0)
            local distance = (x.position - right)^2 + (y.position - bottom)^2
            if count > best_count or
               (count == best_count and (distance < best_distance or
                  (distance == best_distance and (x.position < best_x or
                     (x.position == best_x and y.position < best_y))))) then
               best_x, best_y = x.position, y.position
               best_x_candidate, best_y_candidate = x, y
               best_count, best_distance = count, distance
            end
         end
      end
   end
   local matches = matching_edges(xs, best_x, top, best_y - top, "x", offset)
   local horizontal = matching_edges(ys, best_y, left, best_x - left, "y", offset)
   for _, candidate in ipairs(horizontal) do
      matches[#matches + 1] = candidate
   end
   return drag.mouse_x + best_x - left - drag.width,
      drag.mouse_y + best_y - top - drag.height,
      {x = best_x_candidate, y = best_y_candidate, matches = matches}
end

return window_snap
