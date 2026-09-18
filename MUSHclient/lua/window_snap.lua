-- Shared snapping for visible miniwindows and other displayed rectangles.

local window_snap = {}

function window_snap.enabled ()
  return GetPluginVariable ("c293f9e7f04dde889f65cb90", "snap_miniwindows") == "1"
end

local function snap_setting (name, default, minimum)
  local value = tonumber (GetPluginVariable ("c293f9e7f04dde889f65cb90", name) or default)
  assert (value and value > -math.huge and value < math.huge and value % 1 == 0 and
          (minimum == nil or value >= minimum),
          "Invalid miniwindow snap setting: " .. name)
  return value
end

function window_snap.get_settings ()
  return snap_setting ("snap_miniwindows_threshold", 7, 0),
         snap_setting ("snap_miniwindows_offset", 0)
end

-- Spans must overlap, meet, or leave the configured gap. The threshold allows
-- both axes to approach a corner before the final positions are checked.
local function within_snap_span (position, size, low, high, threshold, offset)
  return (position + size >= low - threshold and position <= high + threshold) or
         math.abs (position + size - (low - offset)) <= threshold or
         math.abs (position - (high + offset)) <= threshold
end

local function add_snap_candidates (candidates, position, size, near, far, low, high,
                                    minimum, maximum, threshold, offset)
  -- Apply the offset to opposite edges. Matching edges stay aligned.
  for _, candidate in ipairs {near - size - offset, far + offset, near, far - size} do
    if math.abs (candidate - position) <= threshold and
       candidate >= minimum and candidate <= maximum then
      candidates [#candidates + 1] = {position = candidate, low = low, high = high}
    end
  end
end

-- Snap an arbitrary displayed rectangle so non-miniwindow surfaces can use
-- the same visible targets, edge offsets, and corner selection as miniwindows.
function window_snap.snap_bounds (bounds, snap)
  local posx, posy = bounds.left, bounds.top
  local width, height = bounds.right - posx, bounds.bottom - posy
  if width <= 0 or height <= 0 then
    return posx, posy
  end

  local threshold, offset = snap.threshold, snap.offset
  local screen_width, screen_height = GetInfo (281), GetInfo (280)
  local excluded = snap.excluded or {}
  local area = snap.area or {left = 0, top = 0, right = screen_width, bottom = screen_height}
  local limits = snap.limits or {left = 0, top = 0, right = screen_width, bottom = screen_height}

  -- Keep the unsnapped position as a fallback for each axis.
  local xs, ys = {{position = posx}}, {{position = posy}}
  -- Area bounds align with the same edges of the dragged rectangle.
  add_snap_candidates (xs, posx, width, area.left, area.right, area.top, area.bottom,
                       limits.left, limits.right, threshold, 0)
  add_snap_candidates (ys, posy, height, area.top, area.bottom, area.left, area.right,
                       limits.top, limits.bottom, threshold, 0)
  for _, target in ipairs (WindowList () or {}) do
    if not excluded [target] and WindowInfo (target, 5) and not WindowInfo (target, 6) then
      -- Use the displayed rectangle, including automatic positioning.
      local left, top = WindowInfo (target, 10), WindowInfo (target, 11)
      local right, bottom = WindowInfo (target, 12), WindowInfo (target, 13)
      if right > left and bottom > top and
         right > 0 and bottom > 0 and left < screen_width and top < screen_height then
        if within_snap_span (posy, height, top, bottom, threshold, offset) then
          add_snap_candidates (xs, posx, width, left, right, top, bottom,
                               limits.left, limits.right, threshold, offset)
        end
        if within_snap_span (posx, width, left, right, threshold, offset) then
          add_snap_candidates (ys, posy, height, top, bottom, left, right,
                               limits.top, limits.bottom, threshold, offset)
        end
      end
    end
  end

  local bestx, besty = posx, posy
  local best_count, best_distance = 0, 0
  for _, x in ipairs (xs) do
    for _, y in ipairs (ys) do
      -- Validate the final pair: one correction can affect the other edge.
      if (not x.low or within_snap_span (y.position, height, x.low, x.high, 0, offset)) and
         (not y.low or within_snap_span (x.position, width, y.low, y.high, 0, offset)) then
        local count = (x.low and 1 or 0) + (y.low and 1 or 0)
        local distance = (x.position - posx)^2 + (y.position - posy)^2
        -- Prefer snapping both axes, then the shortest move. Coordinate ties
        -- make the result independent of WindowList order.
        if count > best_count or
           (count == best_count and (distance < best_distance or
             (distance == best_distance and (x.position < bestx or
               (x.position == bestx and y.position < besty))))) then
          bestx, besty = x.position, y.position
          best_count, best_distance = count, distance
        end
      end
    end
  end
  return bestx, besty
end

-- Record the mouse and size once. Resize callbacks keep their own width and
-- height, so they must receive snapped mouse coordinates before they update them.
function window_snap.begin_resize (win, bounds, extra_excluded)
  if not window_snap.enabled () then
    return nil
  end
  local threshold, offset = window_snap.get_settings ()
  return {
    win = win,
    mouse_x = WindowInfo (win, 17),
    mouse_y = WindowInfo (win, 18),
    width = bounds and (bounds.right - bounds.left) or WindowInfo (win, 3),
    height = bounds and (bounds.bottom - bounds.top) or WindowInfo (win, 4),
    left = bounds and bounds.left,
    top = bounds and bounds.top,
    extra_excluded = extra_excluded,
    threshold = threshold,
    offset = offset,
  }
end

local function add_resize_candidates (candidates, position, low_edge, high_edge,
                                      low, high, minimum, maximum, threshold)
  for _, edge in ipairs {low_edge, high_edge} do
    if math.abs (edge - position) <= threshold and edge > minimum and edge <= maximum then
      candidates [#candidates + 1] = {position = edge, low = low, high = high}
    end
  end
end

function window_snap.resize_coordinates (drag, mouse_x, mouse_y, right_limit, bottom_limit, friend_excluded)
  local win = drag.win
  local left = drag.left or WindowInfo (win, 10)
  local top = drag.top or WindowInfo (win, 11)
  local right = left + drag.width + mouse_x - drag.mouse_x
  local bottom = top + drag.height + mouse_y - drag.mouse_y
  local screen_width, screen_height = GetInfo (281), GetInfo (280)
  local threshold, offset = drag.threshold, drag.offset
  right_limit = right_limit or screen_width
  bottom_limit = bottom_limit or screen_height
  local xs, ys = {{position = right}}, {{position = bottom}}

  -- The output area edges always align flush.
  add_resize_candidates (xs, right, right_limit, right_limit,
                         0, screen_height, left, right_limit, threshold)
  add_resize_candidates (ys, bottom, bottom_limit, bottom_limit,
                         0, screen_width, top, bottom_limit, threshold)

  local excluded = {[win] = true}
  for _, other in ipairs (drag.extra_excluded or {}) do
    excluded [other] = true
  end
  for _, friend in ipairs (friend_excluded or {}) do
    if friend then excluded [friend] = true end
  end
  for _, target in ipairs (WindowList () or {}) do
    if not excluded [target] and WindowInfo (target, 5) and not WindowInfo (target, 6) then
      local target_left, target_top = WindowInfo (target, 10), WindowInfo (target, 11)
      local target_right, target_bottom = WindowInfo (target, 12), WindowInfo (target, 13)
      if target_right > target_left and target_bottom > target_top and
         target_right > 0 and target_bottom > 0 and
         target_left < screen_width and target_top < screen_height then
        if within_snap_span (top, bottom - top, target_top, target_bottom, threshold, offset) then
          add_resize_candidates (xs, right, target_left - offset, target_right,
                                 target_top, target_bottom, left, right_limit, threshold)
        end
        if within_snap_span (left, right - left, target_left, target_right, threshold, offset) then
          add_resize_candidates (ys, bottom, target_top - offset, target_bottom,
                                 target_left, target_right, top, bottom_limit, threshold)
        end
      end
    end
  end

  local best_x, best_y = right, bottom
  local best_count, best_distance = 0, 0
  for _, x in ipairs (xs) do
    for _, y in ipairs (ys) do
      if (not x.low or within_snap_span (top, y.position - top, x.low, x.high, 0, offset)) and
         (not y.low or within_snap_span (left, x.position - left, y.low, y.high, 0, offset)) then
        local count = (x.low and 1 or 0) + (y.low and 1 or 0)
        local distance = (x.position - right)^2 + (y.position - bottom)^2
        if count > best_count or
           (count == best_count and (distance < best_distance or
             (distance == best_distance and (x.position < best_x or
               (x.position == best_x and y.position < best_y))))) then
          best_x, best_y = x.position, y.position
          best_count, best_distance = count, distance
        end
      end
    end
  end
  return drag.mouse_x + best_x - left - drag.width,
         drag.mouse_y + best_y - top - drag.height
end

return window_snap
