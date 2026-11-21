--[[
Authors: Original by Nick Gammon. Rewritten by Fiendish for Aardwolf.

Map renderer for aard_GMCP_mapper.xml.
The plugin owns stored map data, GMCP updates, searches, routes and travel.
This file owns display records, layout, drawing jobs, images and pointer state.

init(options) receives:
   config                   -- saved display configuration
   continent_data           -- continent room, terrain and area callbacks
   get_room(uid, traversal_only) -- copied room data; true skips display preparation
   get_continent_room_overlays(room) -- PK and note flags from raw continent data
   prefetch_rooms(uids)      -- load at most ROOM_PREFETCH_BATCH_SIZE raw records
   activate_target(flags, target) -- handle travel; return a UID for a context menu
   room_click(uid, flags)    -- open the returned room's context menu
   show_help                -- native help callback
   timing, detailed_timing  -- drawing diagnostics
   show_up_down             -- follow up/down exits
   running, hidden          -- initial travel flag and saved visibility

Room display records contain name, exits, area, canonical area_id, continent,
hovermessage, bordercolour, borderpen, borderpenwidth, fillcolour, fillbrush and
texture. The plugin retains ownership of the raw records.
--]]

module(..., package.seeall)

require "aard_register_z_on_create"

require "mw_theme_base"
require "movewindow"
require "gauge"
local window_fonts = require "window_fonts"
continent_maps = require "mapper_continents"
local new_continent_maps = continent_maps.new
dofile(GetInfo(60) .. "aardwolf_colors.lua")

styles = {}

ROOM_PREFETCH_BATCH_SIZE = 32
local CONTINENT_MAX_ROOM_SIZE = continent_maps.CONTINENT_MAX_ROOM_SIZE
local VIDBLAIN_MAX_ROOM_SIZE = continent_maps.VIDBLAIN_MAX_ROOM_SIZE
local FONT_ID = "fn" -- internal font identifier
local CONFIG_FONT_ID = "cfn"
local CONFIG_FONT_ID_UL = "cfnu"
local ROOM_PREFETCH_SCAN_LIMIT = 128

-- Room sizes and spacing are stored separately for ordinary areas and continents.
local ROOM_SIZE = tonumber(GetVariable("ROOM_SIZE")) or 18

local DISTANCE_TO_NEXT_ROOM = math.max(-1, tonumber(GetVariable("DISTANCE_TO_NEXT_ROOM")) or 8)

local room_layout = {
   area = {size = ROOM_SIZE, spacing = DISTANCE_TO_NEXT_ROOM},
   continent = {
      size = tonumber(GetVariable("CONTINENT_ROOM_SIZE")) or 9,
      stretch = GetVariable("CONTINENT_STRETCH_TO_FIT") == "1",
   },
}
room_layout.vidblain = {
   size = math.max(9, math.min(VIDBLAIN_MAX_ROOM_SIZE, tonumber(GetVariable("VIDBLAIN_ROOM_SIZE")) or 9)),
   stretch = GetVariable("VIDBLAIN_STRETCH_TO_FIT") == "1",
}
local timing -- true to show frame timing summary
local detailed_timing -- true to show detailed sub-phase breakdown

local room_cache_hits = 0 -- timing: cache hit counter
local room_cache_misses = 0 -- timing: cache miss counter
-- All batches in a frame use the same cutoff for recent-visit exit lines.
local frame_timestamp = 0

-- Keep the frame being built separate from the published selection views.
-- Mouse input must use the room positions that match the visible pixels.
local drawing = {slice_seconds = 0.100, room_batch_size = 128, map_region = {}}
local offscreen_window, completed_frame_cache
local control_hotspots = {}
local HALF_ROOM, connectors, arrows

local recent_frame_times = {}
local recent_frame_index = 0
local RECENT_FRAME_COUNT = 30

local frame_metrics = {}
local function reset_frame_counters()
   frame_metrics.sum_room_time = 0
   frame_metrics.min_room_time = math.huge
   frame_metrics.max_room_time = 0
   frame_metrics.rooms_drawn_count = 0
   frame_metrics.total_exit_planning_time = 0
   frame_metrics.total_exit_drawing_time = 0
   frame_metrics.total_room_cache_time = 0
   frame_metrics.total_room_db_time = 0
   frame_metrics.total_room_prefetch_time = 0
   frame_metrics.room_prefetch_count = 0
   frame_metrics.total_room_defaults_time = 0
   frame_metrics.total_room_texture_time = 0
   frame_metrics.total_graphics_time = 0
   frame_metrics.total_hotspot_time = 0
   frame_metrics.total_window_setup_time = 0
   frame_metrics.total_bg_texture_time = 0
   frame_metrics.total_room_loop_time = 0
   frame_metrics.total_continent_view_time = 0
   frame_metrics.total_continent_atlas_time = 0
   frame_metrics.total_continent_blend_time = 0
   frame_metrics.total_continent_scale_time = 0
   frame_metrics.total_map_overlay_time = 0
   frame_metrics.total_dress_window_time = 0
   frame_metrics.total_current_room_time = 0
   frame_metrics.total_map_capture_time = 0
   frame_metrics.total_map_render_time = 0
   frame_metrics.map_image_reused = false
   frame_metrics.map_image_retained = false
   frame_metrics.total_repaint_request_time = 0
   frame_metrics.total_get_room_time = 0
   frame_metrics.room_load_count = 0
   frame_metrics.visible_room_count = 0
end
reset_frame_counters()

local window_call_groups = {
   Drawing = {"WindowImageOp", "WindowCircleOp", "WindowLine", "WindowPolygon", "WindowBezier", "WindowRectOp", "WindowGradient", "WindowSetPixel", "WindowText"},
   Images = {"WindowDrawImage", "WindowDrawImageAlpha", "WindowBlendImage", "WindowTransformImage", "WindowFilter", "WindowImageFromWindow", "WindowLoadImage", "WindowLoadImageMemory", "WindowWrite"},
   Hotspots = {"WindowAddHotspot", "WindowDeleteHotspot", "WindowDeleteAllHotspots", "WindowMoveHotspot", "WindowDragHandler", "WindowScrollwheelHandler", "WindowHotspotTooltip", "WindowHotspotList", "WindowHotspotInfo"},
   Window = {"WindowCreate", "WindowResize", "WindowPosition", "WindowShow", "WindowSetZOrder"},
   Queries = {"WindowInfo", "WindowTextWidth", "WindowFontInfo", "WindowFontList", "WindowImageInfo"},
}
local window_call_stats

local default_width = 271
local default_height = 335
local default_x = 884 + Theme.RESIZER_SIZE + 2
local default_y = 0

styles.BACKGROUND_COLOUR = {name = "Area Background", colour = ColourNameToRGB("#111111")}
styles.ROOM_COLOUR = {name = "Room", colour = ColourNameToRGB("#dcdcdc")}
styles.EXIT_COLOUR = {name = "Exit", colour = ColourNameToRGB("#e0ffff")}
styles.EXIT_COLOUR_UP_DOWN = {name = "Exit up/down", colour = ColourNameToRGB("#ffb6c1")}
styles.ROOM_NOTE_COLOUR = {name = "Room notes", colour = ColourNameToRGB("lightgreen")}
styles.OUR_ROOM_COLOUR = {name = "Our room", colour = ColourNameToRGB("#ff1493")}
styles.UNKNOWN_ROOM_COLOUR = {name = "Unknown room", colour = ColourNameToRGB("#9b0000")}
styles.DIFFERENT_AREA_COLOUR = {name = "Another area", colour = ColourNameToRGB("#ff0000")}
styles.AREA_EXIT_FILL_COLOUR = {name = "Area exit room", colour = ColourNameToRGB("#b03060")}
styles.PK_BORDER_COLOUR = {name = "PK border", colour = ColourNameToRGB("red")}
styles.SHOP_FILL_COLOUR = {name = "Shop", colour = ColourNameToRGB("#ffad2f")}
styles.HEALER_FILL_COLOUR = {name = "Healer", colour = ColourNameToRGB("#9acd32")}
styles.TRAINER_FILL_COLOUR = {name = "Trainer", colour = ColourNameToRGB("#9acd32")}
styles.QUESTOR_FILL_COLOUR = {name = "Questor", colour = ColourNameToRGB("deepskyblue")}
styles.BANK_FILL_COLOUR = {name = "Bank", colour = ColourNameToRGB("#ffD700")}
styles.GUILD_FILL_COLOUR = {name = "Guild", colour = ColourNameToRGB("magenta")}
styles.SAFEROOM_FILL_COLOUR = {name = "Safe room", colour = ColourNameToRGB("lightblue")}
styles.MAPPER_NOTE_COLOUR = {name = "Messages", colour = ColourNameToRGB("lightgreen")}

styles.ROOM_NAME_TEXT = {name = "Room name text", colour = ColourNameToRGB("#BEF3F1")}
styles.ROOM_NAME_FILL = {name = "Room name fill", colour = ColourNameToRGB("#105653")}
styles.ROOM_NAME_BORDER = {name = "Room name box", colour = ColourNameToRGB("black")}

styles.AREA_NAME_TEXT = {name = "Area name text", colour = ColourNameToRGB("#BEF3F1")}
styles.AREA_NAME_FILL = {name = "Area name fill", colour = ColourNameToRGB("#105653")}
styles.AREA_NAME_BORDER = {name = "Area name box", colour = ColourNameToRGB("black")}

local RECENT_VISIT_SECONDS = 60 * 3

local default_config = {
   FONT = {name = window_fonts.get_preferred_font({"Dina", "Lucida Console", "Fixedsys", "Courier"}), size = 8},
   WINDOW = {width = default_width, height = default_height},
   SCAN = {depth = 300},
   USE_TEXTURES = {enabled = true},
   SHOW_ROOM_ID = false,
   SHOW_ROOM_BORDERS = true,
   SHOW_VIEW_DISTANCE_RING = true,
   PK_ROOM_STRIPES = false,
   BLINK_PK_TITLE = true,
   MOUSEWHEEL_ZOOM = true,
   VIDBLAIN_OVERLAY_OPACITY = 100,
}

local callbacks = {}
local map_origin_uid, map_area_name
-- Display records are copies; drawing changes must not modify stored room data.
local display_room_cache, room_visit_times = {}, {}
-- A false entry is pending. A numeric entry is the WindowLoadImage result.
local area_texture_results = {}
local config_window, windowinfo, font_height

-- The first path to a position wins, so exit order must be stable.
local exit_order = {"d", "e", "n", "s", "u", "w"}

-- Use the reverse exit to distinguish a shared line from a one-way arrow.
local inverse_direction = {n = "s", s = "n", e = "w", w = "e", u = "d", d = "u"}

local drawn_min_x, drawn_min_y, drawn_max_x, drawn_max_y
local bodyleft, bodytop, bodyright, bodybottom
local resize_dragging = false
local is_running = false
local pan_offset_x, pan_offset_y = 0, 0
local pan_last_mouse_x, pan_last_mouse_y = 0, 0
local pan_dragging, pan_rebaseline_on_drag, pan_animating = false, false, false
local pan_animation_time = 0
local last_area_for_pan
local MAP_DRAG_THRESHOLD = 4 -- ignore small pointer movements during a click
local pan_tooltip_text = "Drag to pan map"
local PAN_ANIMATION_INTERVAL = 1 / 30
local previous_origin_uid, previous_area_name
local title_color, next_blink_color, truncated_room_name, room_title_cache

local blink_cycle = {"@R", "@Y", "@W"}
local config_panel_open
local hidden, show_on_redraw
local credits = {
   "MUSHclient mapper", "Made for Aardwolf by Fiendish", "Original concept by Nick Gammon", "World: " .. WorldName(),
   GetInfo(3),
}
local resize_start_x, resize_start_y

local function snap_continent_room_size(size, minimum, maximum)
   return math.max(minimum or 5, math.min(maximum or 25, math.floor((size - 1) / 4 + 0.5) * 4 + 1))
end

function cancel_draw()
   drawing.job = nil
end

-- Values after a nil still take part in the comparison.
local function same_values(saved, ...)
   for i = 1, select("#", ...) do
      if saved[i] ~= select(i, ...) then
         return false
      end
   end
   return true
end

-- Record every map primitive with its drawing arguments. Reuse the captured map
-- only when the complete drawing sequence and background are unchanged.
local function record_map_command(name, ...)
   local job = drawing.job
   local index = job.command_count + 1
   job.command_count = index
   local count = select("#", ...)
   if not job.commands_changed then
      local previous = completed_frame_cache and completed_frame_cache.commands[index]
      if previous and previous.name == name and previous.count == count and same_values(previous, ...) then
         job.commands[index] = previous
         return
      end
      job.commands_changed = true
   end
   job.commands[index] = {name = name, count = count, ...}
end

local function replay_map_commands(commands, first, last)
   for i = first, last do
      local command = commands[i]
      check(_G[command.name](offscreen_window, unpack(command, 1, command.count)))
   end
end

local function ensure_control_hotspot(id, left, top, right, bottom, mouseup, tooltip, cursor)
   local cached = control_hotspots[id]
   if cached and WindowHotspotInfo(win, id, 1) ~= nil and cached.left == left and cached.top == top and cached.right
      == right and cached.bottom == bottom and cached.mouseup == mouseup and cached.tooltip == tooltip and cached.cursor
      == cursor then
      return
   end
   check(WindowAddHotspot(win, id, left, top, right, bottom, "", "", "", "", mouseup, tooltip, cursor, 0))
   control_hotspots[id] = {
      left = left,
      top = top,
      right = right,
      bottom = bottom,
      mouseup = mouseup,
      tooltip = tooltip,
      cursor = cursor,
   }
end

local function add_room_target(view, rows, id, uid, x, y, tooltip, room_index)
   local row = math.floor((y - view.origin_y) / view.pitch + 0.5)
   local targets = rows[row]
   if not targets then
      targets = {}
      rows[row] = targets
   end
   targets[#targets + 1] = {
      id = tostring(id),
      uid = uid,
      tooltip = tooltip,
      room_index = room_index,
      left = math.floor(x - view.half),
      top = math.floor(y - view.half),
      right = math.floor(x + view.half),
      bottom = math.floor(y + view.half),
   }
end

-- Measure Window calls made by both the mapper and the shared theme. These
-- wrappers exist only during a detailed refresh. Normal drawing uses the
-- original functions. Keep all return values, including nil, and restore the
-- functions before propagating an error.
local function with_window_timing(render_batch, request, enabled, callback_started)
   local originals = {}
   local previous_stats = window_call_stats
   if enabled ~= false then
      window_call_stats = {}
   end
   local timer = utils.timer
   local child_time = 0
   local callback = callback_started and {started = callback_started}
   local previous_callback = drawing.callback
   drawing.callback = callback

   local function finish_call(stat, start_time, children_before, ...)
      local elapsed = timer() - start_time
      -- WindowCreate can be a Lua wrapper that makes other Window calls.
      -- Exclude those child calls so category totals do not count them twice.
      local own_time = elapsed - (child_time - children_before)
      child_time = children_before + elapsed
      stat.calls = stat.calls + 1
      stat.time = stat.time + own_time
      stat.max = math.max(stat.max, own_time)
      return ...
   end

   if enabled ~= false then
      for group, names in pairs(window_call_groups) do
         for _, name in ipairs(names) do
            local original = _G[name]
            if type(original) == "function" then
               originals[name] = {value = rawget(_G, name)}
               local stat = {name = name, group = group, calls = 0, time = 0, max = 0}
               window_call_stats[name] = stat
               _G[name] = function(...)
                  local children_before = child_time
                  local start_time = timer()
                  return finish_call(stat, start_time, children_before, original(...))
               end
            end
         end
      end
   end

   local ok, err = xpcall(function()
      render_batch(request)
   end, function(err)
      if type(err) == "string" then
         return debug.traceback(err, 2)
      end
      return err
   end)
   for name, original in pairs(originals) do
      rawset(_G, name, original.value)
   end
   window_call_stats = previous_stats
   drawing.callback = previous_callback
   if not ok then
      cancel_draw()
      error(err, 0)
   end
   if callback and callback.more then
      local job = callback.job
      local returned = timer()
      job.report_time = (job.report_time or 0) + callback.report_ended - callback.batch_ended
      job.callback_return_time = (job.callback_return_time or 0) + returned - callback.report_ended
      -- This marks the end of mapper cleanup. The interval to the next mapper
      -- callback also includes host work, repaint, and other plugin callbacks.
      job.callback_returned = returned
   end
end

local function report_window_timing(frame_time)
   local groups, calls = {}, {}
   for _, stat in pairs(window_call_stats) do
      if stat.calls > 0 then
         calls[#calls + 1] = stat
         local group = groups[stat.group] or {calls = 0, time = 0}
         groups[stat.group] = group
         group.calls = group.calls + stat.calls
         group.time = group.time + stat.time
      end
   end
   print("  Window calls: included in phase times; detailed timing adds overhead.")
   for _, name in ipairs({"Drawing", "Images", "Hotspots", "Window", "Queries"}) do
      local group = groups[name] or {calls = 0, time = 0}
      print(string.format("    %-10s %5i calls  %7.3f ms  (%4.1f%%)", name, group.calls, group.time * 1000,
         frame_time > 0 and group.time / frame_time * 100 or 0))
   end
   table.sort(calls, function(a, b)
      if a.time == b.time then
         return a.name < b.name
      end
      return a.time > b.time
   end)
   print("    Call                         Count  Total ms    Avg us    Max us")
   for _, stat in ipairs(calls) do
      print(string.format("    %-28s %5i  %8.3f  %8.3f  %8.3f", stat.name, stat.calls, stat.time * 1000,
         stat.time / stat.calls * 1000000, stat.max * 1000000))
   end
end

local function capture_map_image(source_win)
   check(WindowImageFromWindow(win, "cached_map", source_win))
end

function reset_pos()
   cancel_draw()
   config.WINDOW.width = default_width
   config.WINDOW.height = default_height
   WindowPosition(win, default_x, default_y, 0, 18)
   WindowResize(win, default_width, default_height, styles.BACKGROUND_COLOUR.colour)
   Repaint() -- hack because WindowPosition doesn't immediately update coordinates
end

local exit_offsets = {
   n = {0, -1}, s = {0, 1}, e = {1, 0}, w = {-1, 0}, u = {1, -1}, d = {-1, 1},
}

local function update_room_geometry()
   HALF_ROOM = math.ceil(ROOM_SIZE / 2)
   local THIRD_WAY = math.ceil(DISTANCE_TO_NEXT_ROOM / 3)
   local HALF_WAY = math.ceil(DISTANCE_TO_NEXT_ROOM / 2)

   local step = ROOM_SIZE + DISTANCE_TO_NEXT_ROOM
   connectors = {}
   for dir, vector in pairs(exit_offsets) do
      local dx, dy = vector[1], vector[2]
      local x, y = dx * HALF_ROOM, dy * HALF_ROOM
      connectors[dir] = {
         x1 = x, y1 = y, x2 = x + dx * HALF_WAY, y2 = y + dy * HALF_WAY,
         dx = dx * step, dy = dy * step,
         stub = {x1 = x, y1 = y, x2 = x + dx * THIRD_WAY, y2 = y + dy * THIRD_WAY},
      }
   end

   -- how to draw one-way arrows (relative to the center of the room)
   arrows = {
      n = {-2, -HALF_ROOM - 2, 2, -HALF_ROOM - 2, 0, -HALF_ROOM - 6},
      s = {-2, HALF_ROOM + 2, 2, HALF_ROOM + 2, 0, HALF_ROOM + 6},
      e = {HALF_ROOM + 2, -2, HALF_ROOM + 2, 2, HALF_ROOM + 6, 0},
      w = {-HALF_ROOM - 2, -2, -HALF_ROOM - 2, 2, -HALF_ROOM - 6, 0},

      u = {HALF_ROOM + 3, -HALF_ROOM, HALF_ROOM + 3, -HALF_ROOM - 3, HALF_ROOM, -HALF_ROOM - 3},
      d = {-HALF_ROOM - 3, HALF_ROOM, -HALF_ROOM - 3, HALF_ROOM + 3, -HALF_ROOM, HALF_ROOM + 3},
   }
end

-- Stored spacing is relative to ROOM_SIZE. Account for the rounded box
-- bounds and the unbordered fill edge when room edges meet.
local function minimum_area_spacing(size)
   return 2 * math.ceil(size / 2) - size - (config.SHOW_ROOM_BORDERS and 0 or 1)
end

local function layout_for_room(room)
   if not room or room.continent ~= true then
      return room_layout.area
   end
   return room.area_id == "vidblain" and room_layout.vidblain or room_layout.continent
end

local function select_room_layout(room)
   room_layout.current_is_continent = room.continent == true
   local layout = layout_for_room(room)
   room_layout.current = layout
   if layout == room_layout.area then
      layout.spacing = math.max(minimum_area_spacing(layout.size), layout.spacing)
   end
   if room_layout.current_is_continent then
      layout.size = snap_continent_room_size(layout.size, layout == room_layout.vidblain and 9 or 5,
         layout == room_layout.vidblain and VIDBLAIN_MAX_ROOM_SIZE or nil)
   end
   local spacing = room_layout.current_is_continent and -1 or layout.spacing
   if ROOM_SIZE ~= layout.size or DISTANCE_TO_NEXT_ROOM ~= spacing then
      ROOM_SIZE, DISTANCE_TO_NEXT_ROOM = layout.size, spacing
      update_room_geometry()
   end
end

local function load_area_texture(name)
   local result = WindowLoadImage(offscreen_window, name, GetInfo(66) .. "worlds\\plugins\\images\\" .. name)
   if result == error_code.eNoSuchWindow then check(result) end
   return result
end

local function load_room(uid, traversal_only)
   local prepare_display = not traversal_only
   local db_t0 = detailed_timing and utils.timer()
   local room = callbacks.get_room(uid, traversal_only)
   room = room or {unknown = true}
   if db_t0 then
      frame_metrics.total_room_db_time = frame_metrics.total_room_db_time + (utils.timer() - db_t0)
   end

   local def_t0 = detailed_timing and utils.timer()
   room.name = room.name or string.format("Room %s", uid)
   room.name = strip_colours(room.name) -- no colour codes for now
   room.exits = room.exits or {}
   room.area = room.area or "<No area>"
   if prepare_display then
      room.hovermessage = room.hovermessage or "<Unexplored room>"
      room.bordercolour = room.bordercolour or styles.ROOM_COLOUR.colour
      room.borderpen = room.borderpen or 0 -- solid
      room.borderpenwidth = room.borderpenwidth or 1
      room.fillcolour = room.fillcolour or 0x000000
      room.fillbrush = room.fillbrush or 1 -- no fill
      room.mapper_pk_warning = room.info and room.info:match("pk")
      room.mapper_note = room.notes and room.notes ~= ""
   else
      room.mapper_needs_display = true
   end
   if def_t0 then
      frame_metrics.total_room_defaults_time = frame_metrics.total_room_defaults_time + (utils.timer() - def_t0)
   end

   if prepare_display then
      local tex_t0 = detailed_timing and utils.timer()
      if not room.texture or room.texture == "" then
         room.texture = "test5.png"
      end
      if area_texture_results[room.texture] == nil then
         area_texture_results[room.texture] = config.USE_TEXTURES.enabled == true and load_area_texture(room.texture)
      end
      if tex_t0 then
         frame_metrics.total_room_texture_time = frame_metrics.total_room_texture_time + (utils.timer() - tex_t0)
      end
   end

   if db_t0 then
      frame_metrics.total_get_room_time = frame_metrics.total_get_room_time + (utils.timer() - db_t0)
      frame_metrics.room_load_count = frame_metrics.room_load_count + 1
   end
   display_room_cache[uid] = room
   return room
end

local function get_display_room(uid)
   local room = display_room_cache[uid]
   if room and not room.mapper_needs_display then return room end
   return load_room(uid)
end

local function make_number_checker(title, min, max)
   return function(s)
      local n = tonumber(s)
      if not n then
         utils.msgbox(title .. " must be a number", "Incorrect input", "ok", "!", 1)
         return false -- bad input
      end
      if n < min or n > max then
         utils.msgbox(title .. " must be in range " .. min .. " to " .. max, "Incorrect input", "ok", "!", 1)
         return false -- bad input
      end
      if string.match(s, "%.") then
         utils.msgbox(title .. " cannot have decimal places", "Incorrect input", "ok", "!", 1)
         return false -- bad input
      end
      return true -- good input
   end
end

local function get_number_from_user(msg, title, current, min, max)
   local max_length = math.ceil(math.log10(max) + 1)

   return tonumber(utils.inputbox(msg, title, current, nil, nil, {
      validate = make_number_checker(title, min, max),
      prompt_height = 14,
      box_height = 130,
      box_width = 300,
      reply_width = 150,
      max_length = max_length,
   } -- end extra stuff
   ))
end

local function draw_configuration()
   local GAP = 5
   local title = "Map Configuration"

   local function on_off(value)
      return value and "On" or "Off"
   end

   local area = room_layout.area
   local area_spacing = math.max(0, area.spacing - minimum_area_spacing(area.size))
   local rows = {
      {
         label = "Area scan depth",
         value = config.SCAN.depth,
         id = "depth",
         right_padding = GAP,
         callback = "mapper.mouseup_change_depth",
         tooltip = "Click to change the ordinary-area scan depth",
      }, {
         label = "Font",
         value = config.FONT.name .. " " .. config.FONT.size,
         id = "font",
         left_align = true,
         right_padding = GAP,
         callback = "mapper.mouseup_change_font",
         tooltip = "Click to change font",
      }, {
         label = "Area Textures",
         value = on_off(config.USE_TEXTURES.enabled),
         id = "area_textures",
         right_padding = GAP,
         callback = "mapper.mouseup_change_area_textures",
         tooltip = "Click to toggle use of area textures",
      }, {
         label = "Show Room ID",
         value = on_off(config.SHOW_ROOM_ID),
         id = "room_id",
         right_padding = GAP,
         callback = "mapper.mouseup_change_show_id",
         tooltip = "Click to toggle display of room UID",
      }, {
         label = "Area room size",
         layout = "area",
         property = "size",
         decrease = "mapper.smaller_rooms",
         increase = "mapper.bigger_rooms",
      }, {
         label = "Area room spacing",
         layout = "area",
         property = "spacing",
         value = area_spacing,
         decrease = "mapper.denser",
         increase = "mapper.sparser",
      }, {
         label = "Stretch continents to fit",
         value = on_off(room_layout.continent.stretch),
         id = "continent_stretch",
         callback = "mapper.mouseup_change_stretch",
         tooltip = "Click to fit surface continents. Room artwork scales down from maximum size; brush patterns keep their native pixel size.",
      }, {
         label = "Continent room size",
         layout = "continent",
         property = "size",
         disabled = room_layout.continent.stretch,
         decrease = "mapper.smaller_rooms",
         increase = "mapper.bigger_rooms",
      }, {
         label = "Stretch Vidblain to fit",
         value = on_off(room_layout.vidblain.stretch),
         id = "vidblain_stretch",
         callback = "mapper.mouseup_change_stretch",
         tooltip = "Click to fit Vidblain. Room artwork scales down from maximum size; brush patterns keep their native pixel size.",
      }, {
         label = "Vidblain room size",
         layout = "vidblain",
         property = "size",
         disabled = room_layout.vidblain.stretch,
         decrease = "mapper.smaller_rooms",
         increase = "mapper.bigger_rooms",
      }, {
         label = "Vidblain overlay opacity",
         value = config.VIDBLAIN_OVERLAY_OPACITY .. "%",
         id = "vidblain_overlay_opacity",
         callback = "mapper.mouseup_change_vidblain_overlay_opacity",
         tooltip = "Cycle 100%, 50%, 25%, and 0%. Stars, planets, Moonrift, asteroids, and area entrances stay fully visible.",
      }, {
         label = "View distance ring",
         value = on_off(config.SHOW_VIEW_DISTANCE_RING),
         id = "view_distance_ring",
         callback = "mapper.mouseup_change_view_distance_ring",
         tooltip = "Show the continent view distance ring and player box. When off, show a magenta asterisk at the player.",
      }, {
         label = "Ordinary Room Borders",
         value = on_off(config.SHOW_ROOM_BORDERS),
         id = "room_borders",
         callback = "mapper.mouseup_change_room_borders",
         tooltip = "Toggle ordinary borders; keep current-room and PK borders and special markings",
      }, {
         label = "Striped PK Rooms",
         value = on_off(config.PK_ROOM_STRIPES),
         id = "pk_room_stripes",
         callback = "mapper.mouseup_change_pk_room_stripes",
         tooltip = "Use 2-pixel diagonal silver, yellow, and red stripes in PK rooms",
      }, {
         label = "Blink Name in PK Rooms",
         value = on_off(config.BLINK_PK_TITLE),
         id = "blink_pk_rooms",
         right_padding = GAP,
         callback = "mapper.mouseup_change_blink_pk_title",
         tooltip = "Click to toggle title blinking in PK rooms",
      }, {
         label = "Mousewheel Zoom",
         value = on_off(config.MOUSEWHEEL_ZOOM),
         id = "mousewheel_zoom",
         callback = "mapper.mouseup_change_mousewheel_zoom",
         tooltip = "Click to toggle mousewheel zoom",
      },
   }
   local config_entries = {title}
   local width = 0
   for _, row in ipairs(rows) do
      row.text = row.layout and row.label .. " (" .. (row.value or room_layout[row.layout][row.property]) .. ")"
                    or row.label
      config_entries[#config_entries + 1] = row.text
      if row.layout and row.layout ~= "area" and row.property == "size" then
         -- Reserve the widest supported value so zooming does not move the controls.
         local minimum = row.layout == "vidblain" and 9 or 5
         local maximum = row.layout == "vidblain" and VIDBLAIN_MAX_ROOM_SIZE or 25
         for size = minimum, maximum, 4 do
            width = math.max(width,
               WindowTextWidth(config_window, CONFIG_FONT_ID, row.label .. " (" .. size .. ")", true))
         end
      end
   end
   width = math.max(width, max_text_width(config_window, CONFIG_FONT_ID, config_entries, true))
   local row_height = font_height + GAP

   local x = 0
   local y = 0
   local box_size = font_height - 2
   local rh_size = math.max(box_size, max_text_width(config_window, CONFIG_FONT_ID, {
      config.FONT.name .. " " .. config.FONT.size, ((config.USE_TEXTURES.enabled and "On") or "Off"), "- +",
      tostring(config.SCAN.depth),
   }, true))

   for _, row in ipairs(rows) do
      if row.value ~= nil then
         rh_size = math.max(rh_size, WindowTextWidth(config_window, CONFIG_FONT_ID_UL, tostring(row.value)))
      end
   end

   local frame_height = row_height * #config_entries + GAP
   local frame_width = GAP + width + GAP + rh_size + GAP

   WindowCreate(config_window, windowinfo.window_left, windowinfo.window_top, frame_width, frame_height,
      windowinfo.window_mode, windowinfo.window_flags, 0xDCDCDC)
   WindowSetZOrder(config_window, 99999) -- always on top

   draw_3d_box(config_window, 0, 0, frame_width, frame_height)

   y = y + GAP
   x = x + GAP

   WindowText(config_window, CONFIG_FONT_ID, title,
      ((frame_width - WindowTextWidth(config_window, CONFIG_FONT_ID, title)) / 2), y, 0, 0, 0x808080)

   WindowRectOp(config_window, miniwin.rect_frame, x, y + 1, x + box_size, y + 1 + box_size, 0x808080)
   WindowLine(config_window, x + 3, y + 4, x + box_size - 3, y - 2 + box_size, 0x808080, miniwin.pen_solid, 1)
   WindowLine(config_window, x + box_size - 4, y + 4, x + 2, y - 2 + box_size, 0x808080, miniwin.pen_solid, 1)

   WindowAddHotspot(config_window, "$<close_configure>", x, y + 1, x + box_size, y + 1 + box_size, -- rectangle
   "", "", "", "", "mapper.mouseup_close_configure", -- mouseup
   "Click to close", miniwin.cursor_hand, 0) -- hand cursor

   y = y + row_height

   for _, row in ipairs(rows) do
      WindowText(config_window, CONFIG_FONT_ID, row.text, x, y, 0, 0, row.disabled and 0x808080 or 0x000000)
      if row.layout then
         local down_x = width + rh_size / 2 + box_size / 2 - WindowTextWidth(config_window, CONFIG_FONT_ID, "-")
         local up_x = width + rh_size / 2 + box_size + GAP
         local id = "$<" .. row.layout .. "_" .. row.property
         local font = row.disabled and CONFIG_FONT_ID or CONFIG_FONT_ID_UL
         local colour = row.disabled and 0xB0B0B0 or 0x808080
         WindowText(config_window, font, "-", down_x, y, 0, 0, colour)
         WindowText(config_window, font, "+", up_x, y, 0, 0, colour)
         if not row.disabled then
            WindowAddHotspot(config_window, id .. "_down>", down_x, y, down_x + box_size, y + font_height, "", "", "",
               "", row.decrease, "Decrease " .. row.label, miniwin.cursor_hand, 0)
            WindowAddHotspot(config_window, id .. "_up>", up_x, y,
               up_x + WindowTextWidth(config_window, CONFIG_FONT_ID, "+"), y + font_height, "", "", "", "",
               row.increase, "Increase " .. row.label, miniwin.cursor_hand, 0)
         else
            WindowDeleteHotspot(config_window, id .. "_down>")
            WindowDeleteHotspot(config_window, id .. "_up>")
         end
      else
         local value_x = x + width + GAP
         if not row.left_align then
            value_x = width + rh_size / 2 + box_size - WindowTextWidth(config_window, CONFIG_FONT_ID_UL, row.value) / 2
         end
         WindowText(config_window, CONFIG_FONT_ID_UL, tostring(row.value), value_x, y, 0, 0, 0x808080)
         WindowAddHotspot(config_window, "$<" .. row.id .. ">", x + GAP, y, frame_width + (row.right_padding or 0),
            y + font_height, "", "", "", "", row.callback, row.tooltip, miniwin.cursor_hand, 0)
      end
      y = y + row_height
   end

   WindowShow(config_window, true)
end

-- Look ahead only within the discovered breadth layer. Queued rooms already
-- have their exits, since drawing their parents loaded them. Do not traverse
-- another layer here or change the order in which rooms are drawn.
local function prefetch_exit_destinations(job)
   local ids = {}
   local level = job.level
   -- Limit cache inspection as well as database reads. Most queued rooms may be cached.
   for i = job.index, math.min(job.index + ROOM_PREFETCH_SCAN_LIMIT - 1, level.count) do
      local uid = level.uid[i]
      local room = display_room_cache[uid]
      if room and (not room_layout.current_is_continent
         or (level.x[i] >= job.boundary_left and level.y[i] >= job.boundary_top and level.x[i]
            <= job.boundary_right and level.y[i] <= job.boundary_bottom)) then
         for dir, exit_uid in pairs(room.exits) do
            if connectors[dir] and not display_room_cache[exit_uid] and not job.prefetched[exit_uid] then
               ids[#ids + 1] = exit_uid
               job.prefetched[exit_uid] = true
               if #ids == ROOM_PREFETCH_BATCH_SIZE then
                  break
               end
            end
         end
      end
      if #ids == ROOM_PREFETCH_BATCH_SIZE then
         break
      end
   end
   if #ids == 0 then
      return
   end
   local start = detailed_timing and utils.timer()
   callbacks.prefetch_rooms(ids)
   if start then
      frame_metrics.total_room_prefetch_time = frame_metrics.total_room_prefetch_time + utils.timer() - start
      frame_metrics.room_prefetch_count = frame_metrics.room_prefetch_count + 1
   end
end

-- Full-colour pattern images retain all three stripe colours.
local function record_pk_room_stripes(left, top, right, bottom)
   if not drawing.pk_stripes_ready then
      local pattern_window = win .. "_pk_stripes"
      local colours = {0xC0C0C0, 0x00FFFF, 0x0000FF} -- silver, yellow, red
      check(WindowCreate(pattern_window, 0, 0, 6, 6, 0, miniwin.create_ignore_mouse, colours[1]))
      for y = 0, 5 do
         for x = 0, 5 do
            check(WindowSetPixel(pattern_window, x, y, colours[math.floor((x + y) % 6 / 2) + 1]))
         end
      end
      check(WindowImageFromWindow(offscreen_window, "pk_room_stripes", pattern_window))
      drawing.pk_stripes_ready = true
   end
   record_map_command("WindowImageOp", miniwin.circle_rectangle, left, top, right, bottom,
      0, miniwin.pen_null, 0, 0, "pk_room_stripes")
end

local function room_on_screen(x, y)
   return x >= HALF_ROOM and x <= config.WINDOW.width - HALF_ROOM
      and y >= font_height + HALF_ROOM and y <= config.WINDOW.height - HALF_ROOM
end

local function record_room_fill(left, top, right, bottom, colour, brush)
   -- Match the right and bottom edges of a GDI rectangle drawn without a pen.
   if brush == miniwin.brush_solid and left < right and top < bottom and right >= 2 and bottom >= 2 then
      record_map_command("WindowRectOp", 2, left, top, right - 1, bottom - 1, colour)
   else
      record_map_command("WindowCircleOp", miniwin.circle_rectangle, left, top, right, bottom, 0,
         miniwin.pen_null, 0, colour, brush)
   end
end

-- Borderless fills leave one extra pixel at the right and bottom.
-- WindowLine excludes its last pixel, so extend the wall to cover the shared corner.
local function record_room_wall(x, y, dir)
   local pitch = ROOM_SIZE + DISTANCE_TO_NEXT_ROOM
   local inset = config.SHOW_ROOM_BORDERS and 1 or 2
   local low, high = math.floor((-pitch - inset) / 2), math.floor((pitch - inset) / 2)
   x, y = math.floor(x), math.floor(y)
   if dir == "n" or dir == "s" then
      y = y + (dir == "n" and low or high)
      record_map_command("WindowLine", x + low, y, x + high + 1, y, styles.ROOM_COLOUR.colour, miniwin.pen_solid, 1)
   else
      x = x + (dir == "w" and low or high)
      record_map_command("WindowLine", x, y + low, x, y + high + 1, styles.ROOM_COLOUR.colour, miniwin.pen_solid, 1)
   end
end

local function draw_room(uid, x, y)
   local coords = math.floor(x) * 100000 + math.floor(y)

   local job = drawing.job
   local occupied, planned = job.occupied, job.planned

   -- Reserve the room's position before checking exits that can loop back to it.
   occupied[coords] = uid

   -- Ordinary areas traverse off-screen paths. Continents stop at the search bounds.
   local on_screen = room_on_screen(x, y)
   job.drawn[coords] = #job.room_ends + 1
   if room_layout.current_is_continent
      and (x < job.boundary_left or y < job.boundary_top or x > job.boundary_right or y > job.boundary_bottom) then
      return
   end
   local room = display_room_cache[uid]

   -- Prepare display data when the room first becomes visible.
   if not room or (on_screen and room.mapper_needs_display) then
      room = load_room(uid, not on_screen)
      if detailed_timing then
         room_cache_misses = room_cache_misses + 1
      end
   else
      if detailed_timing then
         room_cache_hits = room_cache_hits + 1
      end
   end -- not in cache

   local left, top, right, bottom = x - HALF_ROOM, y - HALF_ROOM, x + HALF_ROOM, y + HALF_ROOM

   -- track bounding box of visible rooms for pan clamping
   if on_screen then
      if not drawn_min_x or x < drawn_min_x then drawn_min_x = x end
      if not drawn_max_x or x > drawn_max_x then drawn_max_x = x end
      if not drawn_min_y or y < drawn_min_y then drawn_min_y = y end
      if not drawn_max_y or y > drawn_max_y then drawn_max_y = y end
   end

   local exit_start_time = nil
   local exit_draw_accum = 0
   if detailed_timing then
      exit_start_time = utils.timer()
   end

   local draw_exits = on_screen and DISTANCE_TO_NEXT_ROOM >= 4

   for _, dir in ipairs(exit_order) do
      local exit_uid = room.exits[dir]
      if exit_uid ~= nil then
         local exit_info = connectors[dir]
         local dashed
         -- try to cache room
         local dest = display_room_cache[exit_uid]
         if not dest then
            if not job.prefetched[exit_uid] then
               prefetch_exit_destinations(job)
            end
            local cache_t0 = detailed_timing and utils.timer()
            dest = load_room(exit_uid, true)
            if cache_t0 then
               frame_metrics.total_room_cache_time = frame_metrics.total_room_cache_time + (utils.timer() - cache_t0)
               room_cache_misses = room_cache_misses + 1
            end
         else
            if detailed_timing then
               room_cache_hits = room_cache_hits + 1
            end
         end

         local next_x = x + exit_info.dx
         local next_y = y + exit_info.dy

         local next_coords = math.floor(next_x) * 100000 + math.floor(next_y)

         -- Keep every area exit in traversal order, including shared destinations.
         if room.area ~= dest.area and not dest.unknown and not (room.continent and dest.continent) then
            job.area_exits[#job.area_exits + 1] = {uid = exit_uid, room_x = next_x, room_y = next_y, room_coords = next_coords}
            job.overlay_changed = true
         end

         -- Preserve placement precedence: occupied cell, self-exit, area limit,
         -- then conflicting first placement.
         if occupied[next_coords] and occupied[next_coords] ~= exit_uid then
            exit_info = exit_info.stub
         elseif exit_uid == uid then
            exit_info = exit_info.stub
            dashed = true
         elseif (dest.area ~= map_area_name and not dest.unknown
            and not (room_layout.current_is_continent and dest.continent))
            or (not show_up_down and (dir == "u" or dir == "d")) then
            exit_info = exit_info.stub
         elseif planned[exit_uid] and planned[exit_uid] ~= next_coords then
            exit_info = exit_info.stub
            dashed = true
         else
            if not planned[exit_uid] and exit_uid ~= job.uid then
               local next_level = job.next_level
               local n = next_level.count + 1
               next_level.count = n
               next_level.uid[n] = exit_uid
               next_level.x[n] = next_x
               next_level.y[n] = next_y
            end
            occupied[next_coords] = exit_uid
            planned[exit_uid] = next_coords
         end

         -- Dense maps still traverse every exit; there is no space for exit lines or arrows.
         if draw_exits then
            local draw_t0 = detailed_timing and utils.timer()
            local lock = room.exit_locks and room.exit_locks[dir]
            local locked = lock ~= nil and lock ~= "0"
            local colour = styles.EXIT_COLOUR.colour
            if locked then
               colour = 0x0000FF
            elseif dir == "u" or dir == "d" then
               colour = styles.EXIT_COLOUR_UP_DOWN.colour
            end
            local cutoff = frame_timestamp - RECENT_VISIT_SECONDS
            local recent = exit_info == connectors[dir] and not dest.unknown
               and (room_visit_times[uid] or 0) > cutoff and (room_visit_times[exit_uid] or 0) > cutoff
            local pen = dashed and miniwin.pen_dash or dest.unknown and miniwin.pen_dot or miniwin.pen_solid
            record_map_command("WindowLine", x + exit_info.x1, y + exit_info.y1, x + exit_info.x2,
               y + exit_info.y2, colour, pen + 0x0200, (locked or recent) and 2 or 1)

            if not dest.unknown and dest.exits[inverse_direction[dir]] ~= uid then
               local arrow = arrows[dir]
               local points = string.format("%i,%i,%i,%i,%i,%i", x + arrow[1], y + arrow[2], x + arrow[3],
                  y + arrow[4], x + arrow[5], y + arrow[6])
               record_map_command("WindowPolygon", points, colour, miniwin.pen_solid, 1, colour, miniwin.brush_solid, true, true)
            end
            if draw_t0 then
               exit_draw_accum = exit_draw_accum + (utils.timer() - draw_t0)
            end
         end
      end
   end

   if detailed_timing and exit_start_time then
      local exit_total = utils.timer() - exit_start_time
      frame_metrics.total_exit_drawing_time = frame_metrics.total_exit_drawing_time + exit_draw_accum
      frame_metrics.total_exit_planning_time = frame_metrics.total_exit_planning_time + (exit_total - exit_draw_accum)
   end

   -- off-screen rooms only needed exit traversal above
   if not on_screen then
      return
   end
   if detailed_timing then
      frame_metrics.visible_room_count = frame_metrics.visible_room_count + 1
   end

   local graphics_start_time = nil
   if detailed_timing then
      graphics_start_time = utils.timer()
   end

   local is_current_room = uid == map_origin_uid
   if is_current_room then
      -- Keep the border separate so later rooms and exit markers cannot cover it.
      job.border_room = room
      job.border_left, job.border_top = left, top
      job.border_right, job.border_bottom = right, bottom
   end

   if room.unknown then
      record_map_command("WindowCircleOp", miniwin.circle_rectangle, left, top, right, bottom,
         styles.UNKNOWN_ROOM_COLOUR.colour, is_current_room and miniwin.pen_null or miniwin.pen_dot,
         is_current_room and 0 or 1, 0, miniwin.brush_hatch_forwards_diagonal)
   else
      local show_border = not is_current_room
                             and (config.SHOW_ROOM_BORDERS or (room.info and string.match(room.info, "pk")))
      -- A solid fill and a one-pixel solid border can share one rectangle.
      -- Hatch and pattern brushes depend on the fill call's pen colour.
      local striped_pk = config.PK_ROOM_STRIPES and room.mapper_pk_warning
      local combined_fill =
         not striped_pk and show_border and room.fillbrush == miniwin.brush_solid and room.borderpen == miniwin.pen_solid
            and room.borderpenwidth == 1
      -- A null pen and null brush cannot change any pixels.
      if striped_pk then
         record_pk_room_stripes(left, top, right, bottom)
      elseif room.fillbrush ~= miniwin.brush_null and not combined_fill then
         record_room_fill(left, top, right, bottom, room.fillcolour, room.fillbrush)
      end

      -- room border, with the fill when both can share the same call
      if show_border then
         record_map_command("WindowCircleOp", miniwin.circle_rectangle, left, top, right, bottom,
            room.bordercolour, room.borderpen, room.borderpenwidth, combined_fill and room.fillcolour or -1,
            combined_fill and room.fillbrush or miniwin.brush_null)
      end

      -- mark rooms with notes
      if room.notes ~= nil and room.notes ~= "" then
         record_map_command("WindowCircleOp", miniwin.circle_rectangle, left - 1 - room.borderpenwidth,
            top - 1 - room.borderpenwidth, right + 1 + room.borderpenwidth, bottom + 1 + room.borderpenwidth,
            styles.ROOM_NOTE_COLOUR.colour, room.borderpen, room.borderpenwidth, -1, miniwin.brush_null)
      end
   end

   -- Draw each wall after both rooms, so a later fill cannot cover it.
   if not room_layout.current_is_continent
      and DISTANCE_TO_NEXT_ROOM - minimum_area_spacing(ROOM_SIZE) < 4 then
      for _, dir in ipairs({"n", "s", "e", "w"}) do
         local connector = connectors[dir]
         local next_x, next_y = x + connector.dx, y + connector.dy
         local next_coords = math.floor(next_x) * 100000 + math.floor(next_y)
         local next_uid = occupied[next_coords]
         if next_uid and job.drawn[next_coords]
            and room_on_screen(next_x, next_y) then
            local adjacent = display_room_cache[next_uid]
            local connected = false
            -- A one-way exit still connects the rooms. Check all six directions.
            for _, exit_dir in ipairs(exit_order) do
               if room.exits[exit_dir] == next_uid or adjacent.exits[exit_dir] == uid then
                  connected = true
                  break
               end
            end
            if not connected then
               record_room_wall(x, y, dir)
            end
         end
      end
   end

   if detailed_timing and graphics_start_time then
      frame_metrics.total_graphics_time = frame_metrics.total_graphics_time + (utils.timer() - graphics_start_time)
   end

   -- Record selection bounds with this room's drawing batch.
   local hotspot_start_time = nil
   if detailed_timing then
      hotspot_start_time = utils.timer()
   end

   add_room_target(job.room_view, job.room_view.rooms, uid, uid, x, y, room.hovermessage, #job.room_ends + 1)

   if detailed_timing and hotspot_start_time then
      frame_metrics.total_hotspot_time = frame_metrics.total_hotspot_time + (utils.timer() - hotspot_start_time)
   end
end

local function area_exit_room_bounds(job, exit, room_limit)
   local room_index = job.drawn[exit.room_coords]
   -- A queued room may be beyond the depth limit. Keep the area-exit marker
   -- until a room is drawn here.
   if room_index and room_index <= room_limit then
      return
   end
   local x, y = exit.room_x, exit.room_y
   if not room_on_screen(x, y) then
      return
   end
   return x - HALF_ROOM, y - HALF_ROOM, x + HALF_ROOM, y + HALF_ROOM
end

local function build_area_exit_targets(job)
   local exits = {}
   for index, exit in ipairs(job.area_exits) do
      if exit.visible then
         local room = get_display_room(exit.uid)
         add_room_target(job.room_view, exits, "zz_area_exit:" .. index .. ":" .. exit.uid, exit.uid, exit.room_x, exit.room_y,
            room.hovermessage, 0)
      end
   end
   return exits
end

-- Area boxes select known entry rooms or approach an unexplored entrance.
-- Other cells select their continent room.
drawing.continent_cell_target = function(cell, view)
   local entries, uid, id, tooltip
   if cell.entry_rooms and #cell.entry_rooms > 0 then
      entries = cell.entry_rooms
      id = "0:continent_entry:" .. cell.zone .. ":" .. cell.x .. ":" .. cell.y .. ":" .. table.concat(entries, ",")
      if #entries == 1 then
         uid = entries[1]
         local room = get_display_room(uid)
         tooltip = room.hovermessage
         if room.unknown then
            tooltip = room.name .. "\n" .. tooltip
         end
      else
         local names = {}
         for i, entry in ipairs(entries) do
            names[i] = tostring(entry) .. ": " .. strip_colours(get_display_room(entry).name)
         end
         tooltip = table.concat(names, "\n")
      end
   elseif cell.entrance_approaches then
      uid = cell.uid
      id = "0:continent_unexplored:" .. cell.zone .. ":" .. cell.x .. ":" .. cell.y
      tooltip = "<Unexplored area entrance>"
   elseif cell.uid or cell.unexplored_uid then
      local cell_uid = cell.uid or cell.unexplored_uid
      local room = get_display_room(cell_uid)
      uid, id, tooltip = cell_uid, tostring(cell_uid), room.hovermessage
      if cell.unexplored_uid then
         tooltip = room.name .. "\n" .. tooltip
      end
   end
   if id then
      return {
         id = id,
         uid = uid,
         tooltip = tooltip,
         left = cell.left,
         top = cell.top,
         right = cell.left + view.size,
         bottom = cell.top + view.size,
         entry_rooms = entries,
         entrance_approaches = cell.entrance_approaches,
      }
   end
end

drawing.continent_target = function(x, y)
   local view = drawing.continent_view
   if not view or not x or not y or view.cell_count == 0 then
      return
   end
   local size = view.size
   local column, row, mincol, minrow
   if view.origin_x then
      mincol, column = continent_maps.visible_cells(view.raster_x, view.source_x, view.raster_width, view.grid_width,
         size, x, math.floor(x) + 1)
      minrow, row = continent_maps.visible_cells(view.raster_y, view.source_y, view.raster_height, view.grid_height,
         size, y, math.floor(y) + 1)
   else
      column = math.floor((x - view.left) / view.pitch_x)
      row = math.floor((y - view.top) / view.pitch_y)
      mincol, minrow = column - 1, row - 1
   end
   local best
   for cy = minrow, row do
      for cx = mincol, column do
         if cx >= 0 and cx < view.columns and cy >= 0 and cy < view.rows then
            local cell = view:cell(cx, cy)
            local left, top = cell.left, cell.top
            if x >= left and x < left + size and y >= top and y < top + size then
               local target = drawing.continent_cell_target(cell, view)
               if target and (not best or target.id < best.id) then
                  best = target
               end
            end
         end
      end
   end
   return best
end

drawing.map_target = function(x, y)
   if not x or not y then
      return
   end
   if drawing.continent_view then
      return drawing.continent_target(x, y)
   end
   local view = drawing.room_view
   if not view then
      return
   end
   local row = math.floor((y - view.origin_y) / view.pitch + 0.5)
   local reach = math.ceil(view.half / view.pitch)
   local best
   for index = 1, 2 do
      local rows = index == 1 and view.rooms or view.exits
      for candidate_row = row - reach, row + reach do
         local targets = rows[candidate_row]
         if targets then
            for _, target in ipairs(targets) do
               if target.room_index <= view.room_limit and x >= target.left and x < target.right and y >= target.top
                  and y < target.bottom and (not best or target.id < best.id) then
                  best = target
               end
            end
         end
      end
   end
   return best
end

drawing.travel_target = function(x, y)
   if resize_dragging or not x or not y or not bodytop or x < bodyleft or x >= bodyright or y < bodytop or y
      >= bodybottom then
      return
   end
   local direct = drawing.map_target(x, y)
   if direct then
      return direct
   end
   local best, distance

   local function consider(target)
      if not target then
         return
      end
      local dx, dy = (target.left + target.right) / 2 - x, (target.top + target.bottom) / 2 - y
      local squared = dx * dx + dy * dy
      if not distance or squared < distance or squared == distance and target.id < best.id then
         best, distance = target, squared
      end
   end

   local view = drawing.continent_view
   if view then
      if view.cell_count == 0 then
         return
      end
      local size = view.size
      local pitch_x, pitch_y = view.pitch_x, view.pitch_y
      local origin_x, origin_y = view.origin_x or view.left, view.origin_y or view.top
      local column = math.max(0, math.min(view.columns - 1, math.floor((x - origin_x - size / 2) / pitch_x + 0.5)))
      local row = math.max(0, math.min(view.rows - 1, math.floor((y - origin_y - size / 2) / pitch_y + 0.5)))
      local rounding = view.origin_x and 1 or 0

      local function axis_distance(center, pointer)
         return math.max(0, math.abs(center - pointer) - rounding) ^ 2
      end

      local nearest_dx = axis_distance(origin_x + column * pitch_x + size / 2, x)
      local nearest_dy = axis_distance(origin_y + row * pitch_y + size / 2, y)

      local function visit(cx, cy)
         if cx < 0 or cx >= view.columns or cy < 0 or cy >= view.rows then
            return
         end
         local cell = view:cell(cx, cy)
         if not (cell.uid or cell.unexplored_uid or cell.entry_rooms and #cell.entry_rooms > 0) then
            return
         end
         local dx, dy = cell.left + size / 2 - x, cell.top + size / 2 - y
         if not distance or dx * dx + dy * dy <= distance then
            consider(drawing.continent_cell_target(cell, view))
         end
      end

      for radius = 0, math.max(view.columns, view.rows) - 1 do
         if radius == 0 then
            visit(column, row)
         else
            for cx = math.max(0, column - radius), math.min(view.columns - 1, column + radius) do
               visit(cx, row - radius)
               visit(cx, row + radius)
            end
            for cy = math.max(0, row - radius + 1), math.min(view.rows - 1, row + radius - 1) do
               visit(column - radius, cy)
               visit(column + radius, cy)
            end
         end
         local remaining = math.huge
         if column - radius > 0 then
            remaining = math.min(remaining,
               axis_distance(origin_x + (column - radius - 1) * pitch_x + size / 2, x) + nearest_dy)
         end
         if column + radius < view.columns - 1 then
            remaining = math.min(remaining,
               axis_distance(origin_x + (column + radius + 1) * pitch_x + size / 2, x) + nearest_dy)
         end
         if row - radius > 0 then
            remaining = math.min(remaining,
               axis_distance(origin_y + (row - radius - 1) * pitch_y + size / 2, y) + nearest_dx)
         end
         if row + radius < view.rows - 1 then
            remaining = math.min(remaining,
               axis_distance(origin_y + (row + radius + 1) * pitch_y + size / 2, y) + nearest_dx)
         end
         if distance and distance < remaining then
            break
         end
      end
   elseif drawing.room_view then
      view = drawing.room_view
      for _, rows in ipairs({view.rooms, view.exits}) do
         for _, targets in pairs(rows) do
            for _, target in ipairs(targets) do
               if target.room_index <= view.room_limit then
                  consider(target)
               end
            end
         end
      end
   end
   return best
end

drawing.highlight_target = function(target, repaint)
   local region = drawing.map_region
   if is_running or pan_dragging or resize_dragging or region.down or region.outside or not region.frame_ready then
      target = nil
   end
   local old = region.highlight
   if drawing.same_map_target(old and old.target, target) then
      return
   end
   if old then
      check(WindowDrawImage(win, "cached_map", old.left, old.top, old.right, old.bottom, 1, old.left, old.top,
         old.right, old.bottom))
      region.highlight = nil
   end
   if target then
      local left, top = math.max(bodyleft, target.left - 2), math.max(bodytop, target.top - 2)
      local right, bottom = math.min(bodyright, target.right + 1), math.min(bodybottom, target.bottom + 1)
      if left < right and top < bottom then
         check(WindowRectOp(win, 1, left, top, right, bottom, ColourNameToRGB("white")))
         region.highlight = {target = target, left = left, top = top, right = right, bottom = bottom}
      end
   end
   if repaint ~= false and (old or region.highlight) then
      BufferedRepaint()
   end
end

drawing.same_map_target = function(a, b)
   if not a or not b then
      return a == b
   end
   return a.id == b.id and a.left == b.left and a.top == b.top and a.right == b.right and a.bottom == b.bottom
             and a.tooltip == b.tooltip
end

drawing.refresh_map_region = function(repaint)
   local region = drawing.map_region
   if region.down or region.updating or WindowInfo(win, 1) == nil then
      return
   end
   local target = not region.outside and drawing.travel_target(WindowInfo(win, 14), WindowInfo(win, 15)) or nil
   local width, height = config.WINDOW.width, config.WINDOW.height
   local id = "zzz_zoom"
   local present = WindowHotspotInfo(win, id, 1) ~= nil
   if present and region.width == width and region.height == height and drawing.same_map_target(region.target, target) then
      drawing.highlight_target(target, repaint)
      return
   end
   local tooltip = target and target.tooltip or pan_tooltip_text
   local cursor = target and miniwin.cursor_plus or miniwin.cursor_hand
   -- Replacing the same ID resets native hover state and the tooltip timer.
   -- Keep one hotspot for all room selection, background panning and zoom.
   region.updating = true
   check(WindowAddHotspot(win, id, 0, 0, width, height, "mapper.map_mouseover", "mapper.map_cancel_mouseover",
      "mapper.map_mousedown", "mapper.map_cancel_mousedown", "mapper.map_mouseup", tooltip, cursor,
      miniwin.hotspot_report_all_mouseovers))
   check(WindowDragHandler(win, id, "mapper.map_dragmove", "mapper.pan_dragrelease", 0))
   check(WindowScrollwheelHandler(win, id, "mapper.zoom_map"))
   region.updating = false
   region.id, region.target, region.tooltip, region.width, region.height = id, target, tooltip, width, height
   drawing.highlight_target(target, repaint)
end

drawing.commit_map_view = function(continent_view, room_view)
   drawing.continent_view, drawing.room_view = continent_view, room_view
end

drawing.plan_continent = function(view)
   for _, rectangle in ipairs(view.rectangles) do
      record_map_command("WindowDrawImage", "continent_surface", unpack(rectangle))
   end
   if view.bounds then
      drawn_min_x, drawn_min_y, drawn_max_x, drawn_max_y = unpack(view.bounds)
   end
   if detailed_timing then
      frame_metrics.rooms_drawn_count = frame_metrics.rooms_drawn_count + view.room_count
      frame_metrics.visible_room_count = frame_metrics.visible_room_count + view.room_count
   end
   for _, cell in ipairs(view.overlays) do
      if cell.uid then
         local room = cell.room
         local pk, note, width, pen
         if room and cell.uid ~= map_origin_uid then
            pk, note, width, pen = callbacks.get_continent_room_overlays(room)
         else
            room = get_display_room(cell.uid)
            pk, note, width, pen = room.mapper_pk_warning, room.mapper_note, room.borderpenwidth, room.borderpen
         end
         if pk then
            if config.PK_ROOM_STRIPES then
               local right = cell.right or cell.left + (view.pitch_x or view.pitch)
               local bottom = cell.bottom or cell.top + (view.pitch_y or view.pitch)
               if right > cell.left and bottom > cell.top then
                  -- Null-pen rectangles leave the final row and column unpainted.
                  record_pk_room_stripes(cell.left, cell.top, right + 1, bottom + 1)
               end
            end
            record_map_command("WindowCircleOp", miniwin.circle_rectangle, cell.left, cell.top,
               cell.left + view.size, cell.top + view.size, styles.PK_BORDER_COLOUR.colour, miniwin.pen_solid, 3, 0,
               miniwin.brush_null)
         end
         if note then
            record_map_command("WindowCircleOp", miniwin.circle_rectangle, cell.left - 1 - width,
               cell.top - 1 - width, cell.left + view.size + 1 + width, cell.top + view.size + 1 + width,
               styles.ROOM_NOTE_COLOUR.colour, pen, width, 0, miniwin.brush_null)
         end
      end
   end
end

local function draw_current_entrance(view)
   if not view.current_entrance then return end
   local left, top, right, bottom = unpack(view.current_entrance)
   -- Copy the border from the visible map crops to keep it above the player marker.
   local function copy_edge(l, t, r, b)
      for _, crop in ipairs(view.rectangles) do
         local x1, y1 = math.max(l, crop[1]), math.max(t, crop[2])
         local x2, y2 = math.min(r, crop[3]), math.min(b, crop[4])
         if x1 < x2 and y1 < y2 then
            local dx, dy = crop[6] - crop[1], crop[7] - crop[2]
            record_map_command("WindowDrawImage", "continent_surface", x1, y1, x2, y2, 1,
               x1 + dx, y1 + dy, x2 + dx, y2 + dy)
         end
      end
   end
   copy_edge(left, top, right + 1, top + 1)
   copy_edge(left, bottom, right + 1, bottom + 1)
   copy_edge(left, top + 1, left + 1, bottom)
   copy_edge(right, top + 1, right + 1, bottom)
end

local function draw_map_overlays(room_limit)
   local job = drawing.job
   local view = job.continent_view
   if view then
      if view.size <= 0 then
         return
      end
      if view.inner_sea_bounds then
         local left, top, right, bottom = unpack(view.inner_sea_bounds)
         local colour = ColourNameToRGB("white")
         record_map_command("WindowLine", left, top, right, top, colour, miniwin.pen_solid, 1)
         record_map_command("WindowLine", right, top, right, bottom, colour, miniwin.pen_solid, 1)
         record_map_command("WindowLine", right, bottom, left, bottom, colour, miniwin.pen_solid, 1)
         record_map_command("WindowLine", left, bottom, left, top, colour, miniwin.pen_solid, 1)
      end
      local x, y, size = view.center_x, view.center_y, view.size
      if not config.SHOW_VIEW_DISTANCE_RING then
         local cx, cy = view.marker_x or math.floor(x + 0.5), view.marker_y or math.floor(y + 0.5)
         if cx + 11 >= 1 and cy + 11 >= 1 and cx - 11 < config.WINDOW.width and cy - 11 < config.WINDOW.height then
            -- Draw the complete outline before the bright inner strokes.
            local rays = {{0, -7}, {7, -5}, {7, 5}, {0, 7}, {-7, 5}, {-7, -5}}
            for _, pen in ipairs({{ColourNameToRGB("#5544cc"), 7}, {ColourNameToRGB("magenta"), 3}}) do
               for _, point in ipairs(rays) do
                  record_map_command("WindowLine", cx, cy, cx + point[1], cy + point[2],
                     pen[1], miniwin.pen_solid, pen[2])
               end
            end
         end
      else
         if x + 3 * size - 1 >= 1 and y + 3 * size >= 1 and x - 3 * size < config.WINDOW.width and y - 3 * size - 1
            < config.WINDOW.height then
            for _, pen in ipairs({{ColourNameToRGB("purple"), 4}, {ColourNameToRGB("magenta"), 2}}) do
               record_map_command("WindowCircleOp", miniwin.circle_round_rectangle, x - 3 * size, y - 3 * size - 1,
                  x + 3 * size - 1, y + 3 * size, pen[1], miniwin.pen_solid, pen[2], 0, miniwin.brush_null, 25, 25)
            end
         end
         if x + size / 2 - 1 >= 1 and y + size / 2 - 1 >= 1 and x - size / 2 < config.WINDOW.width and y - size / 2
            < config.WINDOW.height then
            record_map_command("WindowCircleOp", miniwin.circle_rectangle, x - size / 2, y - size / 2,
               x + size / 2 - 1, y + size / 2 - 1, ColourNameToRGB("magenta"), miniwin.pen_solid, 2, 0, miniwin.brush_null)
         end
      end
      draw_current_entrance(view)
      return
   end
   for _, exit in ipairs(job.area_exits) do
      local left, top, right, bottom = area_exit_room_bounds(job, exit, room_limit)
      local visible = left ~= nil
      if visible ~= exit.visible then
         job.overlay_changed = true
         exit.visible = visible
      end
      if visible then
         record_room_fill(left, top, right, bottom, styles.AREA_EXIT_FILL_COLOUR.colour, miniwin.brush_solid)
      end
   end

   local room = job.border_room
   if room then
      record_map_command("WindowCircleOp", miniwin.circle_rectangle, job.border_left,
         job.border_top, job.border_right, job.border_bottom,
         room.unknown and styles.UNKNOWN_ROOM_COLOUR.colour or room.bordercolour,
         room.unknown and miniwin.pen_dot or room.borderpen, room.unknown and 1 or room.borderpenwidth, -1,
         miniwin.brush_null)
   end
end

-- Display queries and updates used by the plugin.

function displayed_room()
   return map_origin_uid
end

function room_info(uid)
   return display_room_cache[uid] or load_room(uid)
end

function set_running(run)
   run = run == true
   if is_running == run then
      return
   end
   is_running = run
   if run then
      if not pan_animating and (pan_offset_x ~= 0 or pan_offset_y ~= 0) then
         start_pan_animation()
      end
   end
   drawing.refresh_map_region()
end

-- invalidate cached room data (call when GMCP updates a room, notes change, etc.)
function invalidate_room(uid)
   cancel_draw()
   if uid then
      display_room_cache[uid] = nil
   else
      display_room_cache = {}
      previous_origin_uid = nil
      previous_area_name = nil
      drawing.prev_continent = false
   end
end

local function next_title_color()
   if not config.BLINK_PK_TITLE then return "@R" end
   next_blink_color = next_blink_color % #blink_cycle + 1
   return blink_cycle[next_blink_color]
end

function blink_title()
   local colour = next_title_color()
   if colour == title_color then return end
   title_color = colour
   drawing.highlight_target(nil, false)
   drawing.map_region.frame_ready = false
   draw_window_frame(truncated_room_name, map_origin_uid, map_area_name, win, true)
   capture_map_image(win)
   drawing.map_region.frame_ready = true
   completed_frame_cache = nil
   drawing.highlight_target(drawing.map_region.target, false)
   BufferedRepaint()
end

local function fit_room_name(room_name)
   if room_title_cache and room_title_cache.room_name == room_name and room_title_cache.width == config.WINDOW.width
      and room_title_cache.font_name == config.FONT.name and room_title_cache.font_size == config.FONT.size then
      return room_title_cache.text
   end
   local truncated_room_name = room_name
   local name_width = WindowTextWidth(win, FONT_ID, truncated_room_name)
   local add_dots = false

   -- truncate name if too long
   local available_width = (config.WINDOW.width - 20 - WindowTextWidth(win, FONT_ID, "*?"))
   while name_width > available_width do
      truncated_room_name = truncated_room_name:sub(1, -3)
      name_width = WindowTextWidth(win, FONT_ID, truncated_room_name .. "...")
      add_dots = true
      if truncated_room_name == "" then
         break
      end
   end

   if add_dots then
      truncated_room_name = truncated_room_name .. "..."
   end

   room_title_cache = {
      room_name = room_name,
      width = config.WINDOW.width,
      font_name = config.FONT.name,
      font_size = config.FONT.size,
      text = truncated_room_name,
   }
   return truncated_room_name
end

function draw_window_frame(room_name, room_uid, area_name, target_window, paint_only)
   target_window = target_window or win
   bodyleft, bodytop, bodyright, bodybottom = Theme.DrawBorder(target_window)
   bodytop = Theme.DrawTitleBar(target_window, FONT_ID, title_color .. room_name, "center")
   if not paint_only then
      Theme.AddDragHotspot(win, bodytop)
   end

   if config.SHOW_ROOM_ID then
      if room_uid:sub(1, 5) == "nomap" then
         room_uid = "NONE"
      end

      Theme.DrawTextBox(target_window, FONT_ID,
         (config.WINDOW.width - WindowTextWidth(win, FONT_ID, "ID: " .. room_uid)) / 2, -- left
         bodytop, -- top
         "ID: " .. room_uid, false, false)
   end

   Theme.DrawTextBox(target_window, FONT_ID, (config.WINDOW.width - WindowTextWidth(win, FONT_ID, area_name)) / 2, -- left
      config.WINDOW.height - 4 - font_height, -- top
      area_name:gsub("^%l", string.upper), false, false)

   local x = config.WINDOW.width - WindowTextWidth(win, FONT_ID, "?") - 6
   local y = math.max(2, (bodytop - font_height) / 2)
   local box_right = Theme.DrawTextBox(target_window, FONT_ID, x - 1, -- left
   y - 2, -- top
   "?", false, false)
   local box_width = box_right - (x - 1)

   if not pan_dragging and not paint_only then
      ensure_control_hotspot("<help>", x - 3, y - 4, x + box_width + 3, y + font_height, "mapper.show_help",
         "Click for help", miniwin.cursor_help)
   end

   if config_panel_open then
      if not paint_only then
         WindowDeleteHotspot(win, "<configure>")
         control_hotspots["<configure>"] = nil
         draw_configuration()
      end
   else
      -- button
      if not paint_only then
         WindowShow(config_window, false)
      end
      local x = 2
      local y = math.max(2, (bodytop - font_height) / 2)
      local text_width = Theme.DrawTextBox(target_window, FONT_ID, x, -- left
      y - 2, -- top
      "*", false, false)

      if not pan_dragging and not paint_only then
         ensure_control_hotspot("<configure>", x - 2, y - 4, x + text_width, y + font_height,
            "mapper.mouseup_configure", "Click to configure map", miniwin.cursor_plus)
      end
   end
end

-- Redraw the frame controls for each batch, but start the PK blink timer only once.
local function draw_frame_controls(job, target_window)
   local uid, room = job.uid, job.room
   local dress_t0 = detailed_timing and utils.timer()
   local start_blink
   if not job.dressed then
      truncated_room_name = fit_room_name(room.name)
      start_blink = room.info and ("," .. room.info .. ","):find(",pk,", 1, true)
      next_blink_color = 0
      title_color = start_blink and next_title_color() or ""
      if not start_blink then DeleteTimer("blink_title") end
   end
   draw_window_frame(truncated_room_name, uid, room.area, target_window)
   if start_blink then
      AddTimer("blink_title", 0, 0, 0.5, "", timer_flag.Enabled + timer_flag.Temporary + timer_flag.Replace,
         "mapper.blink_title")
   end

   local resize_x, resize_y = Theme.DrawResizeTag(target_window, 1)
   Theme.AddResizeHotspot(win, resize_x, resize_y, "mapper.resize_mouse_down", "mapper.resize_move_callback",
      "mapper.resize_release_callback")

   if dress_t0 then
      frame_metrics.total_dress_window_time = utils.timer() - dress_t0
   end
end

local function reset_frame_metrics()
   if detailed_timing then
      -- Count Window calls only within the measured refresh.
      for _, stat in pairs(window_call_stats) do
         stat.calls, stat.time, stat.max = 0, 0, 0
      end
      reset_frame_counters()
      room_cache_hits = 0
      room_cache_misses = 0
   end
end

local function report_frame(start_time, continuing, job, more)
   local end_time = utils.timer()
   local frame_time = end_time - start_time
   if drawing.callback then
      drawing.callback.batch_ended = end_time
   end

   job.active_time = (job.active_time or 0) + frame_time
   job.batches = (job.batches or 0) + 1
   -- frame total + rolling average (last 30 frames)
   if timing or detailed_timing then
      recent_frame_index = (recent_frame_index % RECENT_FRAME_COUNT) + 1
      recent_frame_times[recent_frame_index] = frame_time
      local n = #recent_frame_times
      local sum = 0
      for i = 1, n do
         sum = sum + recent_frame_times[i]
      end
      print(string.format("=== Mapper %s: %s, %0.1f ms (avg %0.1f ms over %i batches) ===",
         continuing and "continuation" or "frame",
         job.continent_view and "cached continent" or "depth " .. job.depth, frame_time * 1000, sum / n * 1000, n))
   end

   if detailed_timing then
      -- helper for consistent formatting
      local function pct(t)
         return (frame_time > 0) and (t / frame_time * 100) or 0
      end

      local function ms(t)
         return t * 1000
      end

      local mode = continuing and "map continuation" or pan_dragging and "pan drag" or pan_animating and "pan animation"
                      or resize_dragging and "resize update" or "map update"
      if job.continent_view then
         print(string.format("  Cells: %i visible, %i with room metadata; %s", job.continent_view.cell_count,
            frame_metrics.visible_room_count, mode))
         print("  Continent image: " .. job.continent_view.image_status)
      else
         print(string.format("  Rooms: %i traversed, %i visible; %s", frame_metrics.rooms_drawn_count,
            frame_metrics.visible_room_count, mode))
      end
      print("  Refresh execution only; excludes report output and deferred screen repaint.")
      print("  Map image: "
               .. (frame_metrics.map_image_retained and "retained" or frame_metrics.map_image_reused and "reused"
                  or "rebuilt"))

      -- outer draw() phases
      print(string.format("  Current room:      %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_current_room_time),
         pct(frame_metrics.total_current_room_time)))
      print(string.format("  Window setup:      %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_window_setup_time),
         pct(frame_metrics.total_window_setup_time)))
      print(string.format("  Background tex:    %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_bg_texture_time),
         pct(frame_metrics.total_bg_texture_time)))
      if job.continent_view then
         print(string.format("  Continent view:    %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_continent_view_time),
            pct(frame_metrics.total_continent_view_time)))
         print("    Included in continent view:")
         print(string.format("      Atlas image:   %6.2f ms", ms(frame_metrics.total_continent_atlas_time)))
         print(string.format("      Opacity blend: %6.2f ms", ms(frame_metrics.total_continent_blend_time)))
         print(string.format("      Image scaling: %6.2f ms", ms(frame_metrics.total_continent_scale_time)))
      end
      print(string.format("  Room loop:         %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_room_loop_time),
         pct(frame_metrics.total_room_loop_time)))
      print(string.format("  Map overlays:      %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_map_overlay_time),
         pct(frame_metrics.total_map_overlay_time)))
      print(string.format("  Map drawing:       %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_map_render_time),
         pct(frame_metrics.total_map_render_time)))
      print(string.format("  Map image copy:    %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_map_capture_time),
         pct(frame_metrics.total_map_capture_time)))
      print(string.format("  Dress window:      %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_dress_window_time),
         pct(frame_metrics.total_dress_window_time)))
      print(string.format("  Repaint request:   %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_repaint_request_time),
         pct(frame_metrics.total_repaint_request_time)))

      -- room loop breakdown
      if not job.continent_view and frame_metrics.rooms_drawn_count > 0 then
         local avg_room_time = frame_metrics.sum_room_time / frame_metrics.rooms_drawn_count
         local loop_overhead = frame_metrics.total_room_loop_time - frame_metrics.sum_room_time

         print(string.format("  --- Room loop breakdown (%i rooms traversed) ---", frame_metrics.rooms_drawn_count))
         print(string.format("    Per-room:  avg %0.4f ms, min %0.4f ms, max %0.4f ms", ms(avg_room_time),
            ms(frame_metrics.min_room_time), ms(frame_metrics.max_room_time)))
         local total_lookups = room_cache_hits + room_cache_misses
         print(string.format("    Cache: %i hits, %i misses (%0.1f%% hit rate)", room_cache_hits, room_cache_misses,
            (total_lookups > 0) and (room_cache_hits / total_lookups * 100) or 0))
         print(string.format("    Exit planning:   %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_exit_planning_time),
            pct(frame_metrics.total_exit_planning_time)))
         print(string.format("      get_room:      %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_room_cache_time),
            pct(frame_metrics.total_room_cache_time)))
         print(string.format("      Batch prefetch: %5.2f ms  (%4.1f%%, %i calls)",
            ms(frame_metrics.total_room_prefetch_time), pct(frame_metrics.total_room_prefetch_time),
            frame_metrics.room_prefetch_count))
         local plan_other = frame_metrics.total_exit_planning_time - frame_metrics.total_room_cache_time
                               - frame_metrics.total_room_prefetch_time
         print(string.format("      other logic:   %6.2f ms  (%4.1f%%)", ms(plan_other), pct(plan_other)))
         print(string.format("    Exit commands:   %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_exit_drawing_time),
            pct(frame_metrics.total_exit_drawing_time)))
         print(string.format("    Room commands:   %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_graphics_time),
            pct(frame_metrics.total_graphics_time)))
         print(string.format("    Hotspot setup:   %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_hotspot_time),
            pct(frame_metrics.total_hotspot_time)))
         print(string.format("    Loop remainder:  %6.2f ms  (%4.1f%%)", ms(loop_overhead), pct(loop_overhead)))
      end

      -- These room-load totals cover the whole refresh, not just exit planning.
      print(string.format("  Room loads: %i calls, %6.2f ms (included in phases)", frame_metrics.room_load_count,
         ms(frame_metrics.total_get_room_time)))
      print(string.format("    Room callback:   %6.2f ms", ms(frame_metrics.total_room_db_time)))
      print(string.format("    Defaults:        %6.2f ms", ms(frame_metrics.total_room_defaults_time)))
      print(string.format("    Texture lookup:  %6.2f ms", ms(frame_metrics.total_room_texture_time)))
      report_window_timing(frame_time)

      -- unaccounted time
      local accounted = frame_metrics.total_current_room_time + frame_metrics.total_window_setup_time
                           + frame_metrics.total_bg_texture_time + frame_metrics.total_room_loop_time
                           + frame_metrics.total_map_overlay_time + frame_metrics.total_map_render_time
                           + frame_metrics.total_map_capture_time + frame_metrics.total_dress_window_time
                           + frame_metrics.total_repaint_request_time + frame_metrics.total_continent_view_time
      local unaccounted = frame_time - accounted
      print(string.format("  Unaccounted:       %6.2f ms  (%4.1f%%)", ms(unaccounted), pct(unaccounted)))
   end
   if not more and (timing or detailed_timing) then
      print(string.format("  Map complete: %0.1f ms elapsed, %0.1f ms executing in %i batches.",
         (end_time - job.started) * 1000, job.active_time * 1000, job.batches))
      if job.profiled_batches == job.batches and not job.callback_timing_incomplete then
         print(string.format(
            "  Between-batch work: %0.1f ms reports, %0.1f ms callback return, %0.1f ms callback entry.",
            (job.report_time or 0) * 1000, (job.callback_return_time or 0) * 1000, (job.callback_entry_time or 0) * 1000))
         local resumes = job.tick_continuations or 0
         print(string.format(
            "  Between mapper callbacks: %0.1f ms total, %0.1f ms avg, %0.1f ms min, %0.1f ms max; %i tick continuations.",
            (job.between_callback_time or 0) * 1000, resumes > 0 and job.between_callback_time / resumes * 1000 or 0,
            (job.min_callback_gap or 0) * 1000, (job.max_callback_gap or 0) * 1000, resumes))
         print(
            "  Between callbacks includes client work and repaint; excludes the final report and deferred final repaint.")
      else
         print("  Between-batch timing is incomplete: timing changed during this map.")
      end
   end
end

-- Keep every non-command input to the cached frame together. Some values can be nil.
local function frame_inputs(width, height, uid, room, view, background)
   return width, height, uid, room.name, room.area, room.info, config.SHOW_ROOM_ID, config_panel_open,
      config.FONT.name, config.FONT.size, background, Theme.PRIMARY_BODY, view and view.key, view and view.image.version
end

local function draw_map(request)
   local continuing = type(request) == "table"
   local uid = continuing and request.uid or request
   if not continuing then
      cancel_draw()
   end
   if not uid then
      maperror("Cannot draw map right now, I don't know where you are - try: LOOK")
      return
   end

   map_origin_uid = uid -- remember where we are

   local start_time = utils.timer()

   reset_frame_metrics()

   local job = continuing and request or nil
   local room, window_exists
   if continuing then
      room = job.room
      job.command_count = job.room_ends[#job.room_ends]
   else
      local current_t0 = detailed_timing and utils.timer()
      frame_timestamp = os.time()

      -- The origin has a distinct border, so reload its display record after movement.
      room = load_room(uid)
      local new_area = room.area
      room_visit_times[uid] = os.time()

      map_area_name = room.area
      select_room_layout(room)

      -- check for area change and start smooth pan reset
      if last_area_for_pan ~= nil and last_area_for_pan ~= map_area_name then
         if not pan_animating and (pan_offset_x ~= 0 or pan_offset_y ~= 0) then
            start_pan_animation()
         end
      end
      last_area_for_pan = map_area_name
      if current_t0 then
         frame_metrics.total_current_room_time = utils.timer() - current_t0
      end

      -- Read the current window dimensions and position.
      local setup_t0 = detailed_timing and utils.timer()
      local window_left = WindowInfo(win, 1)
      windowinfo.window_left = window_left or windowinfo.window_left
      windowinfo.window_top = WindowInfo(win, 2) or windowinfo.window_top
      config.WINDOW.width = WindowInfo(win, 3) or config.WINDOW.width
      config.WINDOW.height = WindowInfo(win, 4) or config.WINDOW.height

      -- check if window already exists (preserves zzz_zoom hotspot for drag operations)
      window_exists = window_left ~= nil

      if not window_exists then
         -- create new window
         control_hotspots = {}
         completed_frame_cache = nil
         drawing.map_region = {}
         drawing.continent_view, drawing.room_view = nil, nil
         WindowCreate(win, windowinfo.window_left, windowinfo.window_top, config.WINDOW.width, config.WINDOW.height,
            windowinfo.window_mode, -- top right
            windowinfo.window_flags, Theme.PRIMARY_BODY)
      end

      if setup_t0 then
         frame_metrics.total_window_setup_time = utils.timer() - setup_t0
      end

      drawing.refresh_map_region()

      drawn_min_x, drawn_min_y, drawn_max_x, drawn_max_y = nil, nil, nil, nil

      -- Reuse matching commands from the last completed frame.
      job = {
         uid = uid,
         room = room,
         commands = {},
         command_count = 0,
         width = config.WINDOW.width,
         height = config.WINDOW.height,
         started = start_time,
         room_ends = {[0] = 0}, -- Last body command after each room.
         rendered_rooms = 0,
      }
      drawing.job = job
      local continent_t0 = room.continent and detailed_timing and utils.timer()
      if room.continent then
         job.continent_view = continents.view(uid, {
            count_rooms = not not detailed_timing,
            size = ROOM_SIZE,
            width = job.width,
            height = job.height,
            stretch = room_layout.current.stretch,
            stretch_bounds = room_layout.current.stretch and {Theme.BodyMetrics(win, FONT_ID, font_height, 1)} or nil,
            pan_x = pan_offset_x,
            pan_y = pan_offset_y,
            top = font_height,
         })
      else
         continents.zoom_image = nil
      end
      if continent_t0 then
         frame_metrics.total_continent_view_time = utils.timer() - continent_t0
         continent_t0 = utils.timer()
      end
      local cached_continent = job.continent_view ~= nil
      local area_changed = previous_area_name ~= nil and previous_area_name ~= new_area
      if area_changed and not (drawing.prev_continent and cached_continent) or drawing.prev_continent
         and not cached_continent then
         -- Ordinary room borders depend on map_area_name, including a fallback from the cached renderer.
         display_room_cache = {}
      elseif previous_origin_uid and previous_origin_uid ~= uid then
         -- Refresh the old current room, which had OUR_ROOM_COLOUR and a wider border.
         display_room_cache[previous_origin_uid] = nil
      end
      if area_changed and drawing.prev_continent and cached_continent then
         -- PK note widths also depend on map_area_name; terrain and tooltips do not.
         for room_uid, cached in pairs(display_room_cache) do
            if cached.notes and cached.notes ~= "" and cached.info and cached.info:match("pk") then
               display_room_cache[room_uid] = nil
            end
         end
      end
      display_room_cache[uid] = room
      previous_origin_uid, previous_area_name, drawing.prev_continent = uid, new_area, cached_continent
      if cached_continent then
         drawing.plan_continent(job.continent_view)
         job.room_ends[1] = job.command_count
      else
         -- Reserve room positions as exits enter the queue, including off-screen exits.
         job.occupied, job.planned, job.drawn, job.area_exits = {}, {}, {}, {}
         job.prefetched, job.depth = {}, 0
         local center_x, center_y = job.width / 2 + pan_offset_x, job.height / 2 + pan_offset_y
         job.room_view = {rooms = {}, origin_y = center_y, pitch = ROOM_SIZE + DISTANCE_TO_NEXT_ROOM, half = HALF_ROOM}
         -- Traverse back to the viewport even when the current room is panned off screen.
         job.boundary_left, job.boundary_right = math.min(HALF_ROOM, center_x), math.max(job.width - HALF_ROOM, center_x)
         job.boundary_top = math.min(font_height + HALF_ROOM, center_y)
         job.boundary_bottom = math.max(job.height - HALF_ROOM, center_y)
         job.level = {uid = {uid}, x = {center_x}, y = {center_y}, count = 1}
         job.next_level = {uid = {}, x = {}, y = {}, count = 0}
         job.index = 1
      end
      if continent_t0 then
         frame_metrics.total_room_loop_time = utils.timer() - continent_t0
      end
   end
   local callback = drawing.callback
   if callback then
      callback.job = job
      job.profiled_batches = (job.profiled_batches or 0) + 1
      if continuing then
         if job.callback_returned then
            local gap = callback.started - job.callback_returned
            job.between_callback_time = (job.between_callback_time or 0) + gap
            job.min_callback_gap = math.min(job.min_callback_gap or gap, gap)
            job.max_callback_gap = math.max(job.max_callback_gap or gap, gap)
            job.callback_entry_time = (job.callback_entry_time or 0) + start_time - callback.started
            job.tick_continuations = (job.tick_continuations or 0) + 1
         else
            job.callback_timing_incomplete = true
         end
         job.callback_returned = nil
      end
   end
   local background = not job.continent_view and config.USE_TEXTURES.enabled == true
                         and not room_layout.current_is_continent and area_texture_results[room.texture] == 0 and room.texture or false
   local reference = completed_frame_cache
   if not reference or not same_values(reference.inputs,
      frame_inputs(job.width, job.height, uid, room, job.continent_view, background))
      or WindowImageInfo(win, "cached_map", 1) == nil then
      job.commands_changed = true
   end
   local deadline = start_time + drawing.slice_seconds
   local progressed, canvas_ready, display_changed = false, false, false

   local function prepare_body()
      if canvas_ready then
         return
      end
      -- Keep the visible bitmap unchanged while commands and hotspots run.
      -- Native callbacks can repaint before the final overlays are ready.
      completed_frame_cache = nil
      if WindowInfo(offscreen_window, 3) ~= job.width or WindowInfo(offscreen_window, 4) ~= job.height then
         check(WindowCreate(offscreen_window, 0, 0, job.width, job.height, 0, 0, Theme.PRIMARY_BODY))
      end
      if job.continent_view then
         continents.install_image(job.continent_view, offscreen_window)
      end
      if job.render_started then
         local image_t0 = detailed_timing and utils.timer()
         check(WindowDrawImage(offscreen_window, "continuation_map", 0, 0, 0, 0, 1))
         if image_t0 then
            frame_metrics.total_map_render_time = frame_metrics.total_map_render_time + utils.timer() - image_t0
         end
      else
         local bg_t0 = detailed_timing and utils.timer()
         if background then
            -- A null-pen rectangle leaves its final row and column unpainted.
            check(WindowImageOp(offscreen_window, miniwin.circle_rectangle, 0, 0, job.width + 1, job.height + 1,
               0, miniwin.pen_null, 0, 0xffffff, background))
         else
            check(WindowRectOp(offscreen_window, 2, 0, 0, job.width, job.height, Theme.PRIMARY_BODY))
         end
         if bg_t0 then
            frame_metrics.total_bg_texture_time = utils.timer() - bg_t0
         end
      end
      job.render_started, canvas_ready, display_changed = true, true, true
   end

   local function render_room_batch()
      local last_room = math.min(#job.room_ends, job.rendered_rooms + drawing.room_batch_size)
      local last_command = job.room_ends[last_room]
      local first_command = job.room_ends[job.rendered_rooms] + 1
      if first_command <= last_command then
         prepare_body()
         local render_t0 = detailed_timing and utils.timer()
         replay_map_commands(job.commands, first_command, last_command)
         if render_t0 then
            frame_metrics.total_map_render_time = frame_metrics.total_map_render_time + utils.timer() - render_t0
         end
      end
      job.rendered_rooms = last_room
   end

   -- Plan and draw in room batches. Read the clock only after
   -- a batch, and retain the queue and image when the callback must yield.
   while true do
      if job.commands_changed and job.rendered_rooms < #job.room_ends then
         render_room_batch()
      else
         if job.continent_view or job.depth >= config.SCAN.depth then
            break
         end
         local loop_t0 = detailed_timing and utils.timer()
         local rooms_planned = 0
         while rooms_planned < drawing.room_batch_size and job.depth < config.SCAN.depth and job.level.count > 0 do
            local level, i = job.level, job.index
            local start = detailed_timing and utils.timer()
            draw_room(level.uid[i], level.x[i], level.y[i])
            if start then
               local elapsed = utils.timer() - start
               frame_metrics.sum_room_time = frame_metrics.sum_room_time + elapsed
               if elapsed < frame_metrics.min_room_time then
                  frame_metrics.min_room_time = elapsed
               end
               if elapsed > frame_metrics.max_room_time then
                  frame_metrics.max_room_time = elapsed
               end
               frame_metrics.rooms_drawn_count = frame_metrics.rooms_drawn_count + 1
            end
            job.room_ends[#job.room_ends + 1] = job.command_count
            rooms_planned = rooms_planned + 1
            if i == level.count then
               job.level, job.next_level = job.next_level, level
               level.count = 0
               job.depth = job.depth + 1
               job.index = 1
            else
               job.index = i + 1
            end
         end
         if loop_t0 then
            frame_metrics.total_room_loop_time = frame_metrics.total_room_loop_time + utils.timer() - loop_t0
         end
         if rooms_planned == 0 then
            break
         end
         if job.commands_changed then
            render_room_batch()
         end
      end
      progressed = true
      if utils.timer() >= deadline then
         break
      end
   end
   local traversal_more = not job.continent_view and job.depth < config.SCAN.depth
                             and job.level.count > 0

   -- An area teleport can leave every room outside the panned view. Recenter it.
   if not traversal_more and drawn_min_x == nil and (pan_offset_x ~= 0 or pan_offset_y ~= 0) and not pan_animating then
      start_pan_animation()
   end

   local overlay_t0 = detailed_timing and utils.timer()
   local body_count = job.command_count
   local body_changed = job.commands_changed
   -- A map without body commands can compare its overlays immediately. Other
   -- partial maps still occupy slots used by the old complete map's body.
   local compare_overlays = not traversal_more or (reference and reference.body_count == 0 and body_count == 0)
   if not compare_overlays then
      job.commands_changed = true
   end
   local overlay_room_limit = body_changed and job.rendered_rooms or #job.room_ends
   draw_map_overlays(overlay_room_limit)
   if not compare_overlays then
      job.commands_changed = body_changed
   end
   if overlay_t0 then
      frame_metrics.total_map_overlay_time = utils.timer() - overlay_t0
   end

   -- Only the complete command sequence can confirm image reuse. Until a
   -- difference appears, matching commands are already visible in that image.
   if compare_overlays and reference and job.command_count ~= #reference.commands then
      job.commands_changed = true
   end
   local reuse_map = not traversal_more and not job.commands_changed
   if reuse_map then
      job.rendered_rooms = #job.room_ends
   elseif job.commands_changed then
      -- An overlay difference can require replaying a matching body prefix.
      -- Replay the same room batches, with one clock check after each batch.
      while job.rendered_rooms < #job.room_ends and (not progressed or utils.timer() < deadline) do
         render_room_batch()
         progressed = true
      end
   end
   if job.room_ends[job.rendered_rooms] == body_count then
      job.rendered_rooms = #job.room_ends
   end
   if job.commands_changed and job.rendered_rooms ~= overlay_room_limit then
      local overlay_replay_t0 = detailed_timing and utils.timer()
      job.command_count = body_count
      draw_map_overlays(job.rendered_rooms)
      if overlay_replay_t0 then
         frame_metrics.total_map_overlay_time = frame_metrics.total_map_overlay_time + utils.timer() - overlay_replay_t0
      end
   end
   -- Empty room batches still need a canvas for the current-room outline
   -- and area markers. Publish them before movement can cancel this map.
   if job.commands_changed and body_count == 0 and not job.render_started then
      prepare_body()
   end
   local more = traversal_more or job.rendered_rooms < #job.room_ends
   -- Keep the old complete image until a changed body actually starts.
   -- Planning an area marker must not publish an empty body at the cutoff.
   display_changed = display_changed or reuse_map or (job.overlay_changed and job.render_started)
                        or (not more and not job.render_started and job.commands_changed)
   if display_changed then
      local room_view, exit_targets, room_limit
      if not job.continent_view then
         local targets_t0 = detailed_timing and utils.timer()
         -- Room records are append-only. The published limit excludes new
         -- records until their drawing batch reaches the visible bitmap.
         room_view = job.room_view
         exit_targets = build_area_exit_targets(job)
         room_limit = job.commands_changed and job.rendered_rooms or #job.room_ends
         if targets_t0 then
            frame_metrics.total_hotspot_time = frame_metrics.total_hotspot_time + utils.timer() - targets_t0
         end
      end
      if not reuse_map then
         prepare_body()
         local render_t0 = detailed_timing and utils.timer()
         if more then
            -- Save only executed body commands. The next callback restores
            -- this image, so old overlays cannot remain under new rooms.
            check(WindowImageFromWindow(offscreen_window, "continuation_map", offscreen_window))
         end
         replay_map_commands(job.commands, body_count + 1, job.command_count)
         if render_t0 then
            frame_metrics.total_map_render_time = frame_metrics.total_map_render_time + utils.timer() - render_t0
         end
      end
      draw_frame_controls(job, offscreen_window)
      -- Remove the old highlight before replacing its restoration image.
      drawing.highlight_target(nil, false)
      drawing.map_region.frame_ready = false
      if not reuse_map then
         local capture_t0 = detailed_timing and utils.timer()
         capture_map_image(offscreen_window)
         if capture_t0 then
            frame_metrics.total_map_capture_time = utils.timer() - capture_t0
         end
      end
      local publish_t0 = detailed_timing and utils.timer()
      check(WindowDrawImage(win, "cached_map", 0, 0, 0, 0, 1))
      if room_view then
         room_view.exits, room_view.room_limit = exit_targets, room_limit
      end
      drawing.commit_map_view(job.continent_view, room_view)
      drawing.map_region.frame_ready = true
      WindowShow(win, show_on_redraw)
      if publish_t0 then
         frame_metrics.total_map_render_time = frame_metrics.total_map_render_time + utils.timer() - publish_t0
         if reuse_map then
            frame_metrics.map_image_reused = true
         end
      end
      job.overlay_changed, job.dressed = false, true
   elseif detailed_timing then
      frame_metrics.map_image_retained = true
   end
   if display_changed then
      drawing.refresh_map_region(false)
   elseif job.room_view and drawing.room_view == job.room_view and drawing.room_view.room_limit < job.rendered_rooms then
      -- A room can add a selection target without changing any map pixels.
      drawing.room_view.room_limit = job.rendered_rooms
      drawing.refresh_map_region()
   end
   if not more then
      -- A later batch can cover an exit marker from an earlier batch.
      for i = #job.commands, job.command_count + 1, -1 do
         job.commands[i] = nil
      end
      completed_frame_cache = {
         commands = job.commands,
         body_count = body_count,
         inputs = {frame_inputs(config.WINDOW.width, config.WINDOW.height, uid, room, job.continent_view, background)},
      }
   end

   local repaint_t0 = detailed_timing and utils.timer()
   if display_changed then
      if pan_animating then
         BufferedRepaint(PAN_ANIMATION_INTERVAL)
      else
         BufferedRepaint()
      end
   end
   if repaint_t0 then
      frame_metrics.total_repaint_request_time = utils.timer() - repaint_t0
   end

   report_frame(start_time, continuing, job, more)
   if callback then
      callback.more = more
      callback.report_ended = utils.timer()
   end
   if more then
      job.pending = true
   else
      drawing.job = nil
   end
end

function draw(uid)
   local callback_started = (timing or detailed_timing) and utils.timer()
   with_window_timing(draw_map, uid, detailed_timing and uid ~= nil or false, callback_started)
end

-- The GMCP plugin forwards OnPluginTick to resume unfinished frames and centering.
function continue_drawing()
   if continents and continents.zoom_image and not drawing.job and not hidden and not pan_dragging
      and utils.timer() >= continents.zoom_due then continents.finish_zoom() end
   if pan_animating and not drawing.job then
      pan_animate_step()
      return
   end
   local callback_started = (timing or detailed_timing) and utils.timer()
   local job = drawing.job
   if not job or not job.pending then
      return
   end
   job.pending = nil
   if hidden or pan_dragging then
      cancel_draw()
      return
   end
   if WindowInfo(win, 3) ~= job.width or WindowInfo(win, 4) ~= job.height then
      draw(job.uid)
      return
   end
   with_window_timing(draw_map, job, detailed_timing or false, callback_started)
end

function set_timing(mode)
   assert(mode == "off" or mode == "on" or mode == "detailed", "Invalid mapper timing mode")
   timing = mode == "on" or mode == "detailed"
   detailed_timing = mode == "detailed"
   frame_metrics.enabled = detailed_timing
   recent_frame_times = {}
   recent_frame_index = 0
end

function get_timing()
   return detailed_timing and "detailed" or timing and "on" or "off"
end

local function draw_credits()
   check(WindowCreate(offscreen_window, 0, 0, config.WINDOW.width, config.WINDOW.height, 0, 0, Theme.PRIMARY_BODY))
   local top = (config.WINDOW.height - #credits * font_height) / 2

   for _, v in ipairs(credits) do
      local width = WindowTextWidth(offscreen_window, FONT_ID, v)
      local left = (config.WINDOW.width - width) / 2
      WindowText(offscreen_window, FONT_ID, v, left, top, 0, 0, Theme.BODY_TEXT)
      top = top + font_height
   end

   Theme.DrawBorder(offscreen_window)
   local resize_x, resize_y = Theme.DrawResizeTag(offscreen_window, 1)
   Theme.AddResizeHotspot(win, resize_x, resize_y, "mapper.resize_mouse_down", "mapper.resize_move_callback",
      "mapper.resize_release_callback")
   drawing.map_region.frame_ready = false
   capture_map_image(offscreen_window)
   check(WindowDrawImage(win, "cached_map", 0, 0, 0, 0, 1))
   drawing.map_region.frame_ready = true
   WindowShow(win, show_on_redraw)
   WindowShow(config_window, false)
end

function build_continent_maps()
   local started = (timing or detailed_timing) and utils.timer()
   local hits_before, baked_before = continents.cache_hits, continents.baked_planes
   local atlas_before, blend_before
   if detailed_timing then
      atlas_before = frame_metrics.total_continent_atlas_time
      blend_before = frame_metrics.total_continent_blend_time
   end
   continents.build_images(room_layout.continent.stretch and CONTINENT_MAX_ROOM_SIZE or snap_continent_room_size(room_layout.continent.size),
      {continent = room_layout.continent.stretch, vidblain = room_layout.vidblain.stretch})
   if started then
      print(string.format("=== Mapper continent startup: %0.1f ms ===", (utils.timer() - started) * 1000))
      print(string.format("  World cache images loaded: %i, packaged artwork layers used: %i",
         continents.cache_hits - hits_before, continents.baked_planes - baked_before))
      if detailed_timing then
         print(string.format("  Atlas image:   %6.2f ms", (frame_metrics.total_continent_atlas_time - atlas_before) * 1000))
         print(string.format("  Opacity blend: %6.2f ms", (frame_metrics.total_continent_blend_time - blend_before) * 1000))
      end
   end
end

local function set_map_fonts()
   local name, size = config.FONT.name, config.FONT.size
   WindowFont(win, FONT_ID, name, size)
   WindowFont(offscreen_window, FONT_ID, name, size)
   WindowFont(config_window, CONFIG_FONT_ID, name, size)
   WindowFont(config_window, CONFIG_FONT_ID_UL, name, size, false, false, true)

   font_height = WindowFontInfo(win, FONT_ID, 1)
end

-- Recreate window resources on installation or reinitialization.
function init(options)
   if continents then
      continents.close()
   end
   cancel_draw()

   -- Keep the supplied configuration table so the plugin can save option changes.
   config = options.config
   assert(type(config) == "table", "No 'config' table supplied to mapper.")
   config.SHOW_AREA_EXITS = nil -- Remove the retired setting from saved configurations.
   config.CONTINENT_COLOURS = nil
   config.CONTINENT_BRUSHES = nil
   config.CONTINENT_BACKGROUNDS = nil
   config.VIDBLAIN_COLOURS = nil
   config.VIDBLAIN_BRUSHES = nil
   if config.VIDBLAIN_OVERLAY_OPACITY == nil then
      config.VIDBLAIN_OVERLAY_OPACITY = config.VIDBLAIN_SKY_ART == false and 0 or 100
   end
   config.VIDBLAIN_SKY_ART = nil
   continents = new_continent_maps(options.continent_data, GetPluginID() .. "_continent",
      {vidblain_overlay_opacity = config.VIDBLAIN_OVERLAY_OPACITY, frame_metrics = frame_metrics})

   control_hotspots = {}
   drawing.map_region = {}
   drawing.continent_view, drawing.room_view = nil, nil
   drawing.pk_stripes_ready = false
   room_title_cache = nil
   completed_frame_cache = nil
   is_running = options.running == true
   show_on_redraw = options.hidden ~= true
   callbacks.activate_target = options.activate_target
   callbacks.get_room = options.get_room
   callbacks.get_continent_room_overlays = options.get_continent_room_overlays
   callbacks.prefetch_rooms = options.prefetch_rooms
   assert(type(callbacks.prefetch_rooms) == "function", "Invalid 'prefetch_rooms' callback.")
   assert(type(callbacks.get_room) == "function", "No 'get_room' function supplied to mapper.")

   show_help = options.show_help -- "help" function
   callbacks.room_click = options.room_click -- RH mouse-click function
   timing = options.timing -- true for frame timing summary
   detailed_timing = options.detailed_timing -- true for detailed sub-phase breakdown
   frame_metrics.enabled = detailed_timing
   show_up_down = options.show_up_down -- true to show up or down

   for k, v in pairs(default_config) do
      if config[k] == nil then
         config[k] = v
      end
   end

   win = GetPluginID() .. "_mapper"
   offscreen_window = win .. "_render"
   config_window = GetPluginID() .. "_z_config_win"

   WindowCreate(win, 0, 0, 0, 0, 0, 0, 0)
   WindowCreate(offscreen_window, 0, 0, 0, 0, 0, 0, 0)
   WindowCreate(config_window, 0, 0, 0, 0, 0, 0, 0)

   set_map_fonts()

   -- find where window was last time
   windowinfo = movewindow.install(win, miniwin.pos_bottom_right, miniwin.create_absolute_location, true,
      {config_window}, {
         mouseup = MouseUp,
         mousedown = LeftClickOnly,
         dragmove = LeftClickOnly,
         dragrelease = LeftClickOnly,
      }, {x = default_x, y = default_y})

   update_room_geometry()

   if not config.WINDOW then
      config.WINDOW = {}
   end
   config.WINDOW.width = config.WINDOW.width or default_width
   config.WINDOW.height = config.WINDOW.height or default_height

   WindowCreate(win, windowinfo.window_left, windowinfo.window_top, config.WINDOW.width, config.WINDOW.height,
      windowinfo.window_mode, -- top right
      windowinfo.window_flags, Theme.PRIMARY_BODY)

   movewindow.add_drag_handler(win, 0, 0, 0, 0)

   resize_dragging = false
   draw_credits()
end

function MouseUp(flags, hotspot_id, win)
   if bit.band(flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      pan_dragging = false
      pan_rebaseline_on_drag = true
      right_click_menu()
   end
   return true
end

function LeftClickOnly(flags, hotspot_id, win)
   if bit.band(flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      return true
   end
   return false
end

local function with_pan_tooltip_hidden(callback, ...)
   WindowHotspotTooltip(win, "zzz_zoom", "")
   local result = callback(...)
   WindowHotspotTooltip(win, "zzz_zoom", drawing.map_region.tooltip)
   return result
end

function right_click_menu()
   local menustring = "Bring To Front|Send To Back"

   -- add center map option if panned
   if pan_offset_x ~= 0 or pan_offset_y ~= 0 then
      menustring = menustring .. "|-|Center Map"
   end

   local result = with_pan_tooltip_hidden(WindowMenu, win, WindowInfo(win, 14), -- x position
   WindowInfo(win, 15), -- y position
   menustring) -- content
   if result == "Bring To Front" then
      CallPlugin("462b665ecb569efbf261422f", "boostMe", win)
   elseif result == "Send To Back" then
      CallPlugin("462b665ecb569efbf261422f", "dropMe", win)
   elseif result == "Center Map" then
      reset_pan()
   end
end

local function selected_layout(hotspot_id)
   local kind = hotspot_id and hotspot_id:match("^%$<([%a]+)_")
   if kind == "area" or kind == "continent" or kind == "vidblain" then
      return room_layout[kind]
   end
   return room_layout.current or room_layout.area
end

function mouseup_change_stretch(flags, hotspot_id)
   local layout = selected_layout(hotspot_id)
   layout.stretch = not layout.stretch
   draw(map_origin_uid)
   SaveState()
end

local function change_layout(layout, size_change, spacing_change)
   if not map_origin_uid or size_change ~= 0 and layout.stretch then
      return
   end
   local size = layout.size
   if layout ~= room_layout.area then
      size = snap_continent_room_size(size + (size_change > 0 and 4 or -4),
         layout == room_layout.vidblain and 9 or 5, layout == room_layout.vidblain and VIDBLAIN_MAX_ROOM_SIZE or nil)
      if size == layout.size then
         return
      end
      layout.size = size
   else
      local spacing, min_spacing = layout.spacing
      if size_change ~= 0 and spacing_change == size_change then
         -- Wheel zoom changes size and visible spacing together. Shorten the last step to reach zero.
         if size_change < 0 then
            local gap = layout.spacing - minimum_area_spacing(layout.size)
            size_change = -math.min(-size_change, gap)
            size = layout.size + size_change
            min_spacing = minimum_area_spacing(size)
            spacing = gap + size_change + min_spacing
         else
            size, spacing = layout.size + size_change, layout.spacing + spacing_change
            min_spacing = minimum_area_spacing(size)
         end
         if size < 4 or size > 40 or spacing < min_spacing or spacing > 40 then
            return
         end
      else
         if size_change ~= 0 then
            size = math.max(4, math.min(40, size + size_change))
         end
         min_spacing = minimum_area_spacing(size)
         if spacing_change ~= 0 then
            spacing = math.max(min_spacing, math.min(40, spacing + spacing_change))
         end
      end
      if size == layout.size and spacing == layout.spacing then
         return
      end
      layout.size, layout.spacing = size, spacing
   end
   draw(map_origin_uid)
   SaveState()
end

function bigger_rooms(flags, hotspot_id)
   change_layout(selected_layout(hotspot_id), 2, 0)
end

function smaller_rooms(flags, hotspot_id)
   change_layout(selected_layout(hotspot_id), -2, 0)
end

function sparser(flags, hotspot_id)
   local layout = room_layout.area
   local step = layout.spacing < 2 and 1 or 2
   change_layout(layout, 0, step)
end

function denser(flags, hotspot_id)
   local layout = room_layout.area
   local step = layout.spacing < 2 and 1 or 2
   change_layout(layout, 0, -step)
end

function zoom_in()
   local layout = selected_layout()
   local maximum = layout == room_layout.vidblain and VIDBLAIN_MAX_ROOM_SIZE or 40
   if layout.size < maximum then
      change_layout(layout, 2, layout == room_layout.area and 2 or 0)
   end
end

function zoom_out()
   local layout = selected_layout()
   if layout.size > 4 then
      change_layout(layout, -2, layout == room_layout.area and -2 or 0)
   end
end

function mapprint(...)
   local old_note_colour = GetNoteColourFore()
   SetNoteColourFore(styles.MAPPER_NOTE_COLOUR.colour)
   print(...)
   SetNoteColourFore(old_note_colour)
end

function maperror(...)
   local old_note_colour = GetNoteColourFore()
   SetNoteColourFore(ColourNameToRGB("red"))
   print(...)
   SetNoteColourFore(old_note_colour)
end

function show()
   WindowShow(win, true)
   hidden = false
   show_on_redraw = true
   if map_origin_uid then
      draw(map_origin_uid)
   end
end

-- Hiding stops pending batches. keep_hidden also hides later redraws.
function hide(keep_hidden)
   show_on_redraw = not keep_hidden
   cancel_draw()
   WindowShow(win, false)
   hidden = true
end

function save_state()
   SetVariable("ROOM_SIZE", room_layout.area.size)
   SetVariable("DISTANCE_TO_NEXT_ROOM", room_layout.area.spacing)
   SetVariable("CONTINENT_ROOM_SIZE", room_layout.continent.size)
   SetVariable("VIDBLAIN_ROOM_SIZE", room_layout.vidblain.size)
   SetVariable("CONTINENT_STRETCH_TO_FIT", room_layout.continent.stretch and "1" or "0")
   SetVariable("VIDBLAIN_STRETCH_TO_FIT", room_layout.vidblain.stretch and "1" or "0")
   if WindowInfo(win, 1) and WindowInfo(win, 5) then
      movewindow.save_state(win)
      config.WINDOW.width = WindowInfo(win, 3)
      config.WINDOW.height = WindowInfo(win, 4)
   end
end

-- Map pointer callbacks.

local function is_left_button_only(flags)
   return bit.band(flags, miniwin.hotspot_got_lh_mouse) ~= 0 and bit.band(flags, miniwin.hotspot_got_rh_mouse) == 0
end

function map_mouseover()
   drawing.map_region.outside = false
   drawing.refresh_map_region()
end

function map_cancel_mouseover()
   if drawing.map_region.updating then
      return
   end
   drawing.map_region.outside = true
   drawing.highlight_target(nil)
end

function map_mousedown(flags, hotspot_id)
   local region = drawing.map_region
   region.down = {
      travel = is_left_button_only(flags),
      client_x = WindowInfo(win, 17),
      client_y = WindowInfo(win, 18),
   }
   drawing.highlight_target(nil)
end

function map_cancel_mousedown()
   drawing.map_region.down = nil
   drawing.refresh_map_region()
end

function map_mouseup(flags, hotspot_id)
   local region = drawing.map_region
   local down = region.down
   region.down = nil
   drawing.refresh_map_region()
   if not down or down.cancelled then
      return
   end
   local find_target = down.travel and drawing.travel_target or drawing.map_target
   local target = find_target(WindowInfo(win, 14), WindowInfo(win, 15))
   if target then
      local uid = callbacks.activate_target(flags, target)
      if uid then
         pan_dragging = false
         pan_rebaseline_on_drag = true
         with_pan_tooltip_hidden(callbacks.room_click, uid, flags)
      end
   else
      MouseUp(flags, hotspot_id)
   end
end

function map_dragmove(flags, hotspot_id)
   local down = drawing.map_region.down
   if down and not down.cancelled and is_left_button_only(flags) then
      local dx = WindowInfo(win, 17) - down.client_x
      local dy = WindowInfo(win, 18) - down.client_y
      if dx * dx + dy * dy <= MAP_DRAG_THRESHOLD * MAP_DRAG_THRESHOLD then
         return
      end
      down.cancelled = true
      pan_mousedown(flags, hotspot_id)
      -- Keep the full movement from the press when the drag starts.
      pan_last_mouse_x, pan_last_mouse_y = down.client_x, down.client_y
      pan_rebaseline_on_drag = false
   end
   pan_dragmove(flags, hotspot_id)
end

-- Map panning and recentering.

local function begin_map_pan()
   cancel_draw()
   pan_animating = false
   -- Keep control hotspots stable while the pointer remains captured.
   pan_dragging = true
   pan_last_mouse_x, pan_last_mouse_y = WindowInfo(win, 17), WindowInfo(win, 18)
end

function pan_mousedown(flags, hotspot_id)
   begin_map_pan()
end

function pan_dragmove(flags, hotspot_id)
   if not is_left_button_only(flags) then
      return -- ignore non-left drags without updating stored drag position
   end

   if not pan_dragging or pan_rebaseline_on_drag then
      begin_map_pan()
      pan_rebaseline_on_drag = false
      return
   end

   if not map_origin_uid then
      return
   end

   local mouse_x = WindowInfo(win, 17)
   local mouse_y = WindowInfo(win, 18)

   local delta_x = mouse_x - pan_last_mouse_x
   local delta_y = mouse_y - pan_last_mouse_y

   pan_last_mouse_x = mouse_x
   pan_last_mouse_y = mouse_y

   pan_offset_x = pan_offset_x + delta_x
   pan_offset_y = pan_offset_y + delta_y

   if drawn_max_x then
      local view = drawing.continent_view
      local half = view and view.origin_x and view.size / 2 or HALF_ROOM
      -- Correct the drag if the last whole room would leave the viewport.
      local function correction(first, last, near, far)
         if last < near then return near - last end
         return math.min(0, far - first)
      end
      pan_offset_x = pan_offset_x + correction(drawn_min_x + delta_x + half, drawn_max_x + delta_x - half,
         0, config.WINDOW.width)
      pan_offset_y = pan_offset_y + correction(drawn_min_y + delta_y + half, drawn_max_y + delta_y - half,
         bodytop or font_height * 2, config.WINDOW.height)
   end

   -- Keep the captured hotspot while drawing the new pan position.
   draw(map_origin_uid)
end

function pan_dragrelease(flags, hotspot_id)
   if not pan_dragging then
      return
   end

   -- Publish room selection bounds at the final pan position.
   pan_dragging = false
   pan_rebaseline_on_drag = false
   if map_origin_uid then
      draw(map_origin_uid)
   end
end

function reset_pan()
   pan_offset_x = 0
   pan_offset_y = 0
   if map_origin_uid then
      draw(map_origin_uid)
   end
end

function start_pan_animation()
   pan_animating = true
   pan_animation_time = utils.timer()
end

function pan_animate_step()
   local now = utils.timer()
   local elapsed = now - pan_animation_time
   -- Skip ticks that arrive before the animation interval.
   if elapsed < PAN_ANIMATION_INTERVAL then
      return
   end
   pan_animation_time = now

   local dist = math.sqrt(pan_offset_x * pan_offset_x + pan_offset_y * pan_offset_y)
   local max_speed, ease_time = 250, 0.25 -- pixels/second and seconds
   -- Travel at the speed limit, then ease continuously toward zero.
   -- Integrate both parts so delayed callbacks follow the same trajectory.
   local linear_time = math.min(elapsed, math.max(0, (dist - max_speed * ease_time) / max_speed))
   local remaining = (dist - max_speed * linear_time) * math.exp(-(elapsed - linear_time) / ease_time)
   if remaining <= 0.5 then
      pan_offset_x, pan_offset_y = 0, 0
      pan_animating = false
   else
      local scale = remaining / dist
      pan_offset_x, pan_offset_y = pan_offset_x * scale, pan_offset_y * scale
   end
   if map_origin_uid then
      draw(map_origin_uid)
   end
end

function mouseup_configure(flags, hotspot_id)
   config_panel_open = true
   draw(map_origin_uid)
end

function mouseup_close_configure(flags, hotspot_id)
   config_panel_open = false
   SaveState()
   draw(map_origin_uid)
end

function mouseup_change_vidblain_overlay_opacity(flags, hotspot_id)
   local opacity = assert(({[100] = 50, [50] = 25, [25] = 0, [0] = 100})[config.VIDBLAIN_OVERLAY_OPACITY],
      "Invalid Vidblain overlay opacity.")
   continents.set_vidblain_overlay_opacity(opacity)
   config.VIDBLAIN_OVERLAY_OPACITY = opacity
   check(SaveState())
   draw(map_origin_uid)
end

function mouseup_change_font(flags, hotspot_id)
   local newfont = utils.fontpicker(config.FONT.name, config.FONT.size, styles.ROOM_NAME_TEXT.colour)

   if not newfont then
      return
   end

   config.FONT.name = newfont.name

   if newfont.size > 12 then
      utils.msgbox("Maximum allowed font size is 12 points.", "Font too large", "ok", "!", 1)
   else
      config.FONT.size = newfont.size
   end

   styles.ROOM_NAME_TEXT.colour = newfont.colour

   set_map_fonts()

   draw(map_origin_uid)
end

function mouseup_change_depth(flags, hotspot_id)
   local depth = get_number_from_user("Choose scan depth (3 to 300 rooms)", "Depth", config.SCAN.depth, 3, 300)

   if not depth then
      return
   end

   config.SCAN.depth = depth
   draw(map_origin_uid)
end

function mouseup_change_area_textures(flags, hotspot_id)
   local enabled = config.USE_TEXTURES.enabled ~= true
   if enabled then
      for name, result in pairs(area_texture_results) do
         if result == false then area_texture_results[name] = load_area_texture(name) end
      end
   end
   config.USE_TEXTURES.enabled = enabled
   draw(map_origin_uid)
end

function mouseup_change_show_id(flags, hotspot_id)
   config.SHOW_ROOM_ID = config.SHOW_ROOM_ID ~= true
   draw(map_origin_uid)
end

function mouseup_change_view_distance_ring(flags, hotspot_id)
   config.SHOW_VIEW_DISTANCE_RING = not config.SHOW_VIEW_DISTANCE_RING
   draw(map_origin_uid)
   check(SaveState())
end

function mouseup_change_room_borders(flags, hotspot_id)
   config.SHOW_ROOM_BORDERS = not config.SHOW_ROOM_BORDERS
   draw(map_origin_uid)
   SaveState()
end

function mouseup_change_pk_room_stripes(flags, hotspot_id)
   config.PK_ROOM_STRIPES = not config.PK_ROOM_STRIPES
   draw(map_origin_uid)
   SaveState()
end

function mouseup_change_blink_pk_title(flags, hotspot_id)
   config.BLINK_PK_TITLE = config.BLINK_PK_TITLE ~= true
   draw(map_origin_uid)
end

function mouseup_change_mousewheel_zoom(flags, hotspot_id)
   config.MOUSEWHEEL_ZOOM = not config.MOUSEWHEEL_ZOOM
   draw(map_origin_uid)
   SaveState()
end

function zoom_map(flags, hotspot_id)
   if not config.MOUSEWHEEL_ZOOM then
      return
   end
   if bit.band(flags, 0x100) ~= 0 then
      zoom_out()
   else
      zoom_in()
   end
end

function resize_mouse_down(flags, hotspot_id)
   cancel_draw()
   drawing.highlight_target(nil)
   drawing.map_region.frame_ready = false
   resize_dragging = true
   continents.start_resize()
   resize_start_x, resize_start_y = WindowInfo(win, 17), WindowInfo(win, 18)
end

function resize_release_callback()
   resize_dragging = false
   if continents.resize_preview then
      completed_frame_cache = nil
   end
   continents.end_resize()
   config.WINDOW.width = WindowInfo(win, 3)
   config.WINDOW.height = WindowInfo(win, 4)
   if map_origin_uid then
      draw(map_origin_uid)
   else
      draw_credits()
   end
end

function resize_move_callback()
   if GetPluginVariable("c293f9e7f04dde889f65cb90", "lock_down_miniwindows") == "1" then
      return
   end
   local function resize_axis(size, pointer, previous, origin, screen_info)
      local requested = size + pointer - previous
      if requested < 50 then return 50, origin + 50 end
      local screen_edge = GetInfo(screen_info)
      if origin + requested > screen_edge then return screen_edge - origin, screen_edge end
      return requested, pointer
   end
   local posx, posy = WindowInfo(win, 17), WindowInfo(win, 18)
   local width, height
   width, resize_start_x = resize_axis(WindowInfo(win, 3), posx, resize_start_x, windowinfo.window_left, 281)
   height, resize_start_y = resize_axis(WindowInfo(win, 4), posy, resize_start_y, windowinfo.window_top, 280)

   cancel_draw()
   check(WindowResize(win, width, height, styles.BACKGROUND_COLOUR.colour))
   config.WINDOW.width = width
   config.WINDOW.height = height
   if map_origin_uid then
      draw(map_origin_uid)
   else
      draw_credits()
      BufferedRepaint()
   end
end
