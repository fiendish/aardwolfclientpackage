-- mapper.lua

--[[

Authors: Original by Nick Gammon. Modified heavily for Aardwolf by Fiendish.

Generic MUD mapper.

Exposed functions:

init (t)            -- call once, supply:
   t.findpath    -- function for finding the path between two rooms (src, dest)
   t.config      -- ie. colours, sizes
   t.get_room    -- info about room (uid)
   t.show_help   -- function that displays some help
   t.room_click  -- function that handles RH click on room (uid, flags)
   t.timing      -- true to show timing
   t.show_completed  -- true to show "Speedwalk completed."
   t.show_other_areas -- true to show non-current areas
   t.show_up_down    -- follow up/down exits
   t.speedwalk_prefix   -- if not nil, speedwalk by prefixing with this

zoom_in ()          -- zoom in map view
zoom_out ()         -- zoom out map view
mapprint (message)  -- like print, but uses mapper colour
maperror (message)  -- like print, but prints in red
hide ()             -- hides map window (eg. if plugin disabled)
show ()             -- show map window  (eg. if plugin enabled)
save_state ()       -- call to save plugin state (ie. in OnPluginSaveState)
draw (uid)          -- draw map - starting at room 'uid'
start_speedwalk (path)  -- starts speedwalking. path is a table of directions/uids
build_speedwalk (path)  -- builds a client speedwalk string from path
cancel_speedwalk ()     -- cancel current speedwalk, if any
check_we_can_find ()    -- returns true if doing a find is OK right now
find (f, show_uid, count, walk)      -- generic room finder

Exposed variables:

win                 -- the window (in case you want to put up menus)
VERSION             -- mapper version
last_hyperlink_uid  -- room uid of last hyperlink click (destination)
last_speedwalk_uid  -- room uid of last speedwalk attempted (destination)
<various functions> -- functions required to be global by the client (eg. for mouseup)

Room info should include:

   name          (what to show as room name)
   exits         (table keyed by direction, value is exit uid)
   area          (area name)
   hovermessage  (what to show when you mouse-over the room)
   bordercolour  (colour of room border)     - RGB colour
   borderpen     (pen style of room border)  - see WindowCircleOp (values 0 to 6)
   borderpenwidth(pen width of room border)  - eg. 1 for normal, 2 for current room
   fillcolour    (colour to fill room)       - RGB colour, nil for default
   fillbrush     (brush to fill room)        - see WindowCircleOp (values 0 to 12)
   texture       (background texture file)   - cached in textures

--]]

module (..., package.seeall)

VERSION = 2.5   -- for querying by plugins
require "aard_register_z_on_create"

require "mw_theme_base"
require "movewindow"
require "copytable"
require "gauge"
require "pairsbykeys"
dofile (GetInfo(60) .. "aardwolf_colors.lua")


local FONT_ID     = "fn"  -- internal font identifier
local FONT_ID_UL  = "fnu" -- internal font identifier - underlined
local CONFIG_FONT_ID = "cfn"
local CONFIG_FONT_ID_UL = "cfnu"

-- size of room box
local ROOM_SIZE = tonumber(GetVariable("ROOM_SIZE")) or 12

-- how far away to draw rooms from each other
local DISTANCE_TO_NEXT_ROOM = tonumber(GetVariable("DISTANCE_TO_NEXT_ROOM")) or 8

-- supplied in init
local supplied_get_room
local room_click
local timing            -- true to show frame timing summary
local detailed_timing   -- true to show detailed sub-phase breakdown
local show_completed    -- true to show "Speedwalk completed."

-- current room number
local current_room

-- our copy of rooms info
local rooms = {}
local last_visited = {}
local textures = {}
local last_result_list = {}
local prev_draw_room = nil   -- uid of previous current room (for cache invalidation)
local prev_draw_area = nil   -- area of previous current room (for area-change detection)
local room_cache_hits = 0    -- timing: cache hit counter
local room_cache_misses = 0  -- timing: cache miss counter
local draw_now = 0           -- os.time() cached once per frame

-- other locals
local HALF_ROOM, connectors, half_connectors, arrows
local plan_to_draw, drawn, drawn_coords
local rooms_to_be_drawn_uid, rooms_to_be_drawn_x, rooms_to_be_drawn_y
local last_drawn, depth, font_height
local walk_to_room_name
local recent_frame_times = {}
local recent_frame_index = 0
local RECENT_FRAME_COUNT = 30

-- room drawing timing metrics
local room_draw_times = {}
local rooms_drawn_count = 0
-- draw_room sub-phases
local total_exit_planning_time = 0
local total_exit_drawing_time = 0
local total_room_cache_time = 0     -- get_room calls inside exit loop
local total_room_db_time = 0        -- supplied_get_room (DB lookup)
local total_room_defaults_time = 0  -- strip_colours, field defaults
local total_room_texture_time = 0   -- texture cache/load
local total_graphics_time = 0
local total_hotspot_time = 0
-- draw() outer phases
local total_window_setup_time = 0   -- window create/clear, hotspot cleanup
local total_bg_texture_time = 0     -- background texture tiling/blit
local total_room_loop_time = 0      -- the fan-out while loop
local total_zone_exit_time = 0      -- draw_zone_exit calls
local total_dress_window_time = 0   -- dress_window, theme, PK

-- cached tiled background texture
local cached_bg_image = nil
local cached_bg_width = 0
local cached_bg_height = 0
local cached_bg_texture = nil

-- pan offset for dragging the map view
local pan_offset_x = 0
local pan_offset_y = 0
local pan_last_mouse_x = 0
local pan_last_mouse_y = 0
local pan_dragging = false  -- true while dragging (skip hotspot updates)
local pan_animating = false
local last_area_for_pan = nil
-- bounding box of drawn rooms in window coords (updated each draw, used for pan clamping)
local drawn_min_x, drawn_min_y, drawn_max_x, drawn_max_y

default_width = 269
default_height = 335
default_x = 868 + Theme.RESIZER_SIZE + 2
default_y = 0

function reset_pos()
   config.WINDOW.width = default_width
   config.WINDOW.height = default_height
   WindowPosition(win, default_x, default_y, 0, 18)
   WindowResize(win, default_width, default_height, BACKGROUND_COLOUR.colour)
   Repaint() -- hack because WindowPosition doesn't immediately update coordinates
end

local function build_room_info ()

   HALF_ROOM   = math.ceil(ROOM_SIZE / 2)
   local THIRD_WAY   = math.ceil(DISTANCE_TO_NEXT_ROOM / 3)
   local HALF_WAY = math.ceil(DISTANCE_TO_NEXT_ROOM / 2)

   barriers = {
      n =  { x1 = -HALF_ROOM, y1 = -HALF_ROOM, x2 = HALF_ROOM, y2 = -HALF_ROOM},
      s =  { x1 = -HALF_ROOM, y1 =  HALF_ROOM, x2 = HALF_ROOM, y2 =  HALF_ROOM},
      e =  { x1 =  HALF_ROOM, y1 = -HALF_ROOM, x2 =  HALF_ROOM, y2 = HALF_ROOM},
      w =  { x1 = -HALF_ROOM, y1 = -HALF_ROOM, x2 = -HALF_ROOM, y2 = HALF_ROOM},

      u = { x1 =  HALF_ROOM-HALF_WAY, y1 = -HALF_ROOM-HALF_WAY, x2 =  HALF_ROOM+HALF_WAY, y2 = -HALF_ROOM+HALF_WAY},
      d = { x1 = -HALF_ROOM+HALF_WAY, y1 =  HALF_ROOM+HALF_WAY, x2 = -HALF_ROOM-HALF_WAY, y2 =  HALF_ROOM-HALF_WAY},

   } -- end barriers

   -- how to draw a line from this room to the next one (relative to the center of the room)
   connectors = {
      n =  { x1 = 0,            y1 = - HALF_ROOM, x2 = 0,                             y2 = - HALF_ROOM - HALF_WAY, at = { 0, -1 } },
      s =  { x1 = 0,            y1 =   HALF_ROOM, x2 = 0,                             y2 =   HALF_ROOM + HALF_WAY, at = { 0,  1 } },
      e =  { x1 =   HALF_ROOM,  y1 = 0,           x2 =   HALF_ROOM + HALF_WAY,  y2 = 0,                            at = {  1,  0 }},
      w =  { x1 = - HALF_ROOM,  y1 = 0,           x2 = - HALF_ROOM - HALF_WAY,  y2 = 0,                            at = { -1,  0 }},

      u = { x1 =   HALF_ROOM,  y1 = - HALF_ROOM, x2 =   HALF_ROOM + HALF_WAY , y2 = - HALF_ROOM - HALF_WAY, at = { 1, -1 } },
      d = { x1 = - HALF_ROOM,  y1 =   HALF_ROOM, x2 = - HALF_ROOM - HALF_WAY , y2 =   HALF_ROOM + HALF_WAY, at = {-1,  1 } },

   } -- end connectors

   -- how to draw a stub line
   half_connectors = {
      n =  { x1 = 0,            y1 = - HALF_ROOM, x2 = 0,                        y2 = - HALF_ROOM - THIRD_WAY, at = { 0, -1 } },
      s =  { x1 = 0,            y1 =   HALF_ROOM, x2 = 0,                        y2 =   HALF_ROOM + THIRD_WAY, at = { 0,  1 } },
      e =  { x1 =   HALF_ROOM,  y1 = 0,           x2 =   HALF_ROOM + THIRD_WAY,  y2 = 0,                       at = {  1,  0 }},
      w =  { x1 = - HALF_ROOM,  y1 = 0,           x2 = - HALF_ROOM - THIRD_WAY,  y2 = 0,                       at = { -1,  0 }},

      u = { x1 =   HALF_ROOM,  y1 = - HALF_ROOM, x2 =   HALF_ROOM + THIRD_WAY , y2 = - HALF_ROOM - THIRD_WAY, at = { 1, -1 } },
      d = { x1 = - HALF_ROOM,  y1 =   HALF_ROOM, x2 = - HALF_ROOM - THIRD_WAY , y2 =   HALF_ROOM + THIRD_WAY, at = {-1,  1 } },

   } -- end half_connectors

   -- how to draw one-way arrows (relative to the center of the room)
   arrows = {
      n =  { - 2, - HALF_ROOM - 2,  2, - HALF_ROOM - 2,  0, - HALF_ROOM - 6 },
      s =  { - 2,   HALF_ROOM + 2,  2,   HALF_ROOM + 2,  0,   HALF_ROOM + 6  },
      e =  {   HALF_ROOM + 2, -2,   HALF_ROOM + 2, 2,   HALF_ROOM + 6, 0 },
      w =  { - HALF_ROOM - 2, -2, - HALF_ROOM - 2, 2, - HALF_ROOM - 6, 0 },

      u = {   HALF_ROOM + 3,  - HALF_ROOM,  HALF_ROOM + 3, - HALF_ROOM - 3,  HALF_ROOM, - HALF_ROOM - 3 },
      d = { - HALF_ROOM - 3,    HALF_ROOM,  - HALF_ROOM - 3,   HALF_ROOM + 3,  - HALF_ROOM,   HALF_ROOM + 3},

   } -- end of arrows

end -- build_room_info

-- assorted colours
BACKGROUND_COLOUR     = { name = "Area Background",  colour =  ColourNameToRGB "#111111"}
ROOM_COLOUR           = { name = "Room",             colour =  ColourNameToRGB "#dcdcdc"}
EXIT_COLOUR           = { name = "Exit",             colour =  ColourNameToRGB "#e0ffff"}
EXIT_COLOUR_UP_DOWN   = { name = "Exit up/down",     colour =  ColourNameToRGB "#ffb6c1"}
ROOM_NOTE_COLOUR      = { name = "Room notes",       colour =  ColourNameToRGB "lightgreen"}
OUR_ROOM_COLOUR       = { name = "Our room",         colour =  ColourNameToRGB "#ff1493"}
UNKNOWN_ROOM_COLOUR   = { name = "Unknown room",     colour =  ColourNameToRGB "#9b0000"}
DIFFERENT_AREA_COLOUR = { name = "Another area",     colour =  ColourNameToRGB "#ff0000"}
PK_BORDER_COLOUR      = { name = "PK border",        colour =  ColourNameToRGB "red"}
SHOP_FILL_COLOUR      = { name = "Shop",             colour =  ColourNameToRGB "#ffad2f"}
HEALER_FILL_COLOUR    = { name = "Healer",           colour =  ColourNameToRGB "#9acd32"}
TRAINER_FILL_COLOUR   = { name = "Trainer",          colour =  ColourNameToRGB "#9acd32"}
QUESTOR_FILL_COLOUR   = { name = "Questor",          colour =  ColourNameToRGB "deepskyblue"}
BANK_FILL_COLOUR      = { name = "Bank",             colour =  ColourNameToRGB "#ffD700"}
GUILD_FILL_COLOUR     = { name = "Guild",            colour =  ColourNameToRGB "magenta"}
SAFEROOM_FILL_COLOUR  = { name = "Safe room",        colour =  ColourNameToRGB "lightblue"}
MAPPER_NOTE_COLOUR    = { name = "Messages",         colour =  ColourNameToRGB "lightgreen"}

ROOM_NAME_TEXT        = { name = "Room name text",   colour = ColourNameToRGB "#BEF3F1"}
ROOM_NAME_FILL        = { name = "Room name fill",   colour = ColourNameToRGB "#105653"}
ROOM_NAME_BORDER      = { name = "Room name box",    colour = ColourNameToRGB "black"}

AREA_NAME_TEXT        = { name = "Area name text",   colour = ColourNameToRGB "#BEF3F1"}
AREA_NAME_FILL        = { name = "Area name fill",   colour = ColourNameToRGB "#105653"}
AREA_NAME_BORDER      = { name = "Area name box",    colour = ColourNameToRGB "black"}

-- how many seconds to show "recent visit" lines (default 3 minutes)
LAST_VISIT_TIME = 60 * 3

default_config = {
   FONT = { name =  get_preferred_font {"Dina",  "Lucida Console",  "Fixedsys", "Courier",} ,
            size = 8
         } ,

   -- size of map window
   WINDOW = { width = default_width, height = default_height },

   -- how far from where we are standing to draw (rooms)
   SCAN = { depth = 300 },

   -- show custom tiling background textures
   USE_TEXTURES = { enabled = true },

   SHOW_ROOM_ID = false,

   SHOW_AREA_EXITS = false,

   BLINK_PK_TITLE = true
}

local expand_direction = {
   n = "north",
   s = "south",
   e = "east",
   w = "west",
   u = "up",
   d = "down",
}  -- end of expand_direction

local function get_room (uid)
   local db_t0 = detailed_timing and utils.timer()
   local room = supplied_get_room (uid)
   room = room or { unknown = true }
   if db_t0 then
      total_room_db_time = total_room_db_time + (utils.timer() - db_t0)
   end

   -- defaults in case they didn't supply them ...
   local def_t0 = detailed_timing and utils.timer()
   room.name = room.name or string.format ("Room %s", uid)
   room.name = strip_colours (room.name)  -- no colour codes for now
   room.exits = room.exits or {}
   room.area = room.area or "<No area>"
   room.hovermessage = room.hovermessage or "<Unexplored room>"
   room.bordercolour = room.bordercolour or ROOM_COLOUR.colour
   room.borderpen = room.borderpen or 0 -- solid
   room.borderpenwidth = room.borderpenwidth or 1
   room.fillcolour = room.fillcolour or 0x000000
   room.fillbrush = room.fillbrush or 1 -- no fill
   room.texture = room.texture or nil -- no texture
   if def_t0 then
      total_room_defaults_time = total_room_defaults_time + (utils.timer() - def_t0)
   end

   room.textimage = nil

   local tex_t0 = detailed_timing and utils.timer()
   if room.texture == nil or room.texture == "" then room.texture = "test5.png" end
   if textures[room.texture] then
      room.textimage = textures[room.texture] -- assign image
   else
      if textures[room.texture] ~= false then
         local dir = GetInfo(66)
         imgpath = dir .. "worlds\\plugins\\images\\" ..room.texture
         if WindowLoadImage(win, room.texture, imgpath) ~= 0 then
            textures[room.texture] = false  -- just indicates not found
         else
            textures[room.texture] = room.texture -- imagename
            room.textimage = room.texture
         end
      end
   end
   if tex_t0 then
      total_room_texture_time = total_room_texture_time + (utils.timer() - tex_t0)
   end

   return room

end -- get_room

function check_connected ()
   if not IsConnected() then
      mapprint ("You are not connected to", WorldName())
      return false
   end -- if not connected
   return true
end -- check_connected

local function make_number_checker (title, min, max, decimals)
   return function (s)
      local n = tonumber (s)
      if not n then
         utils.msgbox (title .. " must be a number", "Incorrect input", "ok", "!", 1)
         return false  -- bad input
      end -- if
      if n < min or n > max then
         utils.msgbox (title .. " must be in range " .. min .. " to " .. max, "Incorrect input", "ok", "!", 1)
         return false  -- bad input
      end -- if
      if not decimals then
         if string.match (s, "%.") then
            utils.msgbox (title .. " cannot have decimal places", "Incorrect input", "ok", "!", 1)
            return false  -- bad input
         end -- if
      end -- no decimals
      return true  -- good input
   end -- generated function
end -- make_number_checker


local function get_number_from_user (msg, title, current, min, max, decimals)
   local max_length = math.ceil (math.log10 (max) + 1)

   -- if decimals allowed, allow room for them
   if decimals then
      max_length = max_length + 2  -- allow for 0.x
   end -- if

   -- if can be negative, allow for minus sign
   if min < 0 then
      max_length = max_length + 1
   end -- if can be negative

   return tonumber (utils.inputbox (msg, title, current, nil, nil,
      { validate = make_number_checker (title, min, max, decimals),
         prompt_height = 14,
         box_height = 130,
         box_width = 300,
         reply_width = 150,
         max_length = max_length,
      }  -- end extra stuff
   ))
end -- get_number_from_user

local function draw_configuration ()

   local config_entries = {"Map Configuration", "Show Room ID", "Show Area Exits", "Font", "Depth", "Area Textures", "Room size", "Blink Name in PK Rooms"}
   local width =  max_text_width (config_win, CONFIG_FONT_ID, config_entries , true)
   local GAP = 5

   local x = 0
   local y = 0
   local box_size = font_height - 2
   local rh_size = math.max (box_size, max_text_width (config_win, CONFIG_FONT_ID,
      {config.FONT.name .. " " .. config.FONT.size,
      ((config.USE_TEXTURES.enabled and "On") or "Off"),
      "- +",
      tostring (config.SCAN.depth)},
      true))
   local frame_width = GAP + width + GAP + rh_size + GAP  -- gap / text / gap / box / gap

   WindowCreate(config_win, windowinfo.window_left, windowinfo.window_top, frame_width, font_height * #config_entries + GAP+GAP, windowinfo.window_mode, windowinfo.window_flags, 0xDCDCDC)
   WindowSetZOrder(config_win, 99999) -- always on top

   -- frame it
   draw_3d_box (config_win, 0, 0, frame_width, font_height * #config_entries + GAP+GAP)

   y = y + GAP
   x = x + GAP

   -- title
   WindowText (config_win, CONFIG_FONT_ID, "Map Configuration", ((frame_width-WindowTextWidth(config_win,CONFIG_FONT_ID,"Map Configuration"))/2), y, 0, 0, 0x808080)

   -- close box
   WindowRectOp (config_win,
      miniwin.rect_frame,
      x,
      y + 1,
      x + box_size,
      y + 1 + box_size,
      0x808080)
   WindowLine (config_win,
      x + 3,
      y + 4,
      x + box_size - 3,
      y - 2 + box_size,
      0x808080,
      miniwin.pen_solid, 1)
   WindowLine (config_win,
      x + box_size - 4,
      y + 4,
      x + 2,
      y - 2 + box_size,
      0x808080,
      miniwin.pen_solid, 1)

   -- close configuration hotspot
   WindowAddHotspot(config_win, "$<close_configure>",
      x,
      y + 1,
      x + box_size,
      y + 1 + box_size,    -- rectangle
      "", "", "", "", "mapper.mouseup_close_configure",  -- mouseup
      "Click to close",
      miniwin.cursor_hand, 0)  -- hand cursor

   y = y + font_height

   -- depth
   WindowText(config_win, CONFIG_FONT_ID, "Depth", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL,   tostring (config.SCAN.depth), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, config.SCAN.depth)/2, y, 0, 0, 0x808080)

   -- depth hotspot
   WindowAddHotspot(config_win,
      "$<depth>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_depth",  -- mouseup
      "Click to change scan depth",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height

   -- font
   WindowText(config_win, CONFIG_FONT_ID, "Font", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL,  config.FONT.name .. " " .. config.FONT.size, x + width + GAP, y, 0, 0, 0x808080)

   -- font hotspot
   WindowAddHotspot(config_win,
      "$<font>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_font",  -- mouseup
      "Click to change font",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height

   -- area textures
   WindowText(config_win, CONFIG_FONT_ID, "Area Textures", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, ((config.USE_TEXTURES.enabled and "On") or "Off"), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, ((config.USE_TEXTURES.enabled and "On") or "Off"))/2, y, 0, 0, 0x808080)

   -- area textures hotspot
   WindowAddHotspot(config_win,
      "$<area_textures>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_area_textures",  -- mouseup
      "Click to toggle use of area textures",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height


   -- show ID
   WindowText(config_win, CONFIG_FONT_ID, "Show Room ID", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_ROOM_ID and "On") or "Off"), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_ROOM_ID and "On") or "Off"))/2, y, 0, 0, 0x808080)

   -- show ID hotspot
   WindowAddHotspot(config_win,
      "$<room_id>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_show_id",  -- mouseup
      "Click to toggle display of room UID",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height


   -- show area exits
   WindowText(config_win, CONFIG_FONT_ID, "Show Area Exits", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_AREA_EXITS and "On") or "Off"), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, ((config.SHOW_AREA_EXITS and "On") or "Off"))/2, y, 0, 0, 0x808080)

   -- show area exits hotspot
   WindowAddHotspot(config_win,
      "$<area_exits>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_show_area_exits",  -- mouseup
      "Click to toggle display of area exits",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height


   -- room size
   WindowText(config_win, CONFIG_FONT_ID, "Room size", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID, "("..tostring (ROOM_SIZE)..")", x + WindowTextWidth(config_win, CONFIG_FONT_ID, "Room size "), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "-", width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "+", width + rh_size / 2 + box_size + GAP, y, 0, 0, 0x808080)

   -- room size hotspots
   WindowAddHotspot(config_win,
      "$<room_size_down>",
      width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y,
      width + rh_size / 2 + box_size/2 + WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.zoom_out",  -- mouseup
      "Click to zoom out",
      miniwin.cursor_hand, 0)  -- hand cursor
   WindowAddHotspot(config_win,
      "$<room_size_up>",
      width + rh_size / 2 + box_size + GAP,
      y,
      width + rh_size / 2 + box_size + GAP + WindowTextWidth(config_win,CONFIG_FONT_ID,"+"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.zoom_in",  -- mouseup
      "Click to zoom in",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height

   -- blink PK rooms
   WindowText(config_win, CONFIG_FONT_ID, "Blink Name in PK Rooms", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, ((config.BLINK_PK_TITLE and "On") or "Off"), width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, ((config.BLINK_PK_TITLE and "On") or "Off"))/2, y, 0, 0, 0x808080)
   -- blink PK rooms hotspot
   WindowAddHotspot(config_win,
      "$<blink_pk_rooms>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_blink_pk_title",
      "Click to toggle title blinking in PK rooms",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height

   WindowShow(config_win, true)
end -- draw_configuration

-- for calculating one-way paths
local inverse_direction = {
   n = "s",
   s = "n",
   e = "w",
   w = "e",
   u = "d",
   d = "u",
   ne = "sw",
   se = "nw",
   sw = "ne",
   nw = "se"
}  -- end of inverse_direction

local function draw_room (uid, x, y)
   local room_start_time = nil
   if detailed_timing then
      room_start_time = utils.timer()
   end

   local coords = math.floor (x) * 100000 + math.floor (y)

   -- need this for the *current* room !!!
   drawn_coords [coords] = uid

   -- print ("drawing", uid, "at", coords)

   if drawn [uid] then
      return
   end -- done this one

   -- don't draw the same room more than once
   drawn [uid] = coords

   local room = rooms [uid]

   -- not cached - get from caller
   if not room then
      room = get_room (uid)
      rooms [uid] = room
      if detailed_timing then room_cache_misses = room_cache_misses + 1 end
   else
      if detailed_timing then room_cache_hits = room_cache_hits + 1 end
   end -- not in cache


   local left, top, right, bottom = x - HALF_ROOM, y - HALF_ROOM, x + HALF_ROOM, y + HALF_ROOM

   -- check if room is off screen (still traverse exits so panned-into-view rooms draw)
   local on_screen = not ((x < HALF_ROOM) or (y < (title_bottom or font_height)+HALF_ROOM) or
      (x > config.WINDOW.width - HALF_ROOM) or (y > config.WINDOW.height - HALF_ROOM))

   -- track bounding box of visible rooms for pan clamping
   if on_screen then
      if drawn_min_x == nil then
         drawn_min_x, drawn_min_y, drawn_max_x, drawn_max_y = x, y, x, y
      else
         if x < drawn_min_x then drawn_min_x = x end
         if x > drawn_max_x then drawn_max_x = x end
         if y < drawn_min_y then drawn_min_y = y end
         if y > drawn_max_y then drawn_max_y = y end
      end
   end

   -- exits
   local exit_start_time = nil
   local exit_draw_accum = 0
   if detailed_timing then
      exit_start_time = utils.timer()
   end

   for dir, exit_uid in pairs (room.exits) do
      local exit_info = connectors [dir]
      local stub_exit_info = half_connectors [dir]
      local locked_exit = not (room.exit_locks == nil or room.exit_locks[dir] == nil or room.exit_locks[dir] == "0")
      local exit_line_colour = (locked_exit and 0x0000FF) or EXIT_COLOUR.colour
      local arrow = arrows [dir]

      -- draw up in the ne/nw position if not already an exit there at this level
      if dir == "u" then
         exit_line_colour = (locked_exit and 0x0000FF) or EXIT_COLOUR_UP_DOWN.colour
      elseif dir == "d" then
         exit_line_colour = (locked_exit and 0x0000FF) or EXIT_COLOUR_UP_DOWN.colour
      end -- if down

      if exit_info then
         local linetype = miniwin.pen_solid -- unbroken
         local linewidth = (locked_exit and 2) or 1 -- not recent

         -- try to cache room
         if not rooms [exit_uid] then
            local cache_t0 = detailed_timing and utils.timer()
            rooms [exit_uid] = get_room (exit_uid)
            if cache_t0 then
               total_room_cache_time = total_room_cache_time + (utils.timer() - cache_t0)
               room_cache_misses = room_cache_misses + 1
            end
         else
            if detailed_timing then room_cache_hits = room_cache_hits + 1 end
         end -- if

         if rooms [exit_uid].unknown then
            linetype = miniwin.pen_dot -- dots
         end -- if

         local next_x = x + exit_info.at [1] * (ROOM_SIZE + DISTANCE_TO_NEXT_ROOM)
         local next_y = y + exit_info.at [2] * (ROOM_SIZE + DISTANCE_TO_NEXT_ROOM)

         local next_coords = math.floor (next_x) * 100000 + math.floor (next_y)

         -- remember if a zone exit (first one only)
         if config.SHOW_AREA_EXITS and room.area ~= rooms [exit_uid].area and not rooms[exit_uid].unknown then
            area_exits [ rooms [exit_uid].area ] = area_exits [ rooms [exit_uid].area ] or {x = x, y = y, def = barriers[dir]}
         end -- if

         -- if another room (not where this one leads to) is already there, only draw "stub" lines
         if drawn_coords [next_coords] and drawn_coords [next_coords] ~= exit_uid then
            exit_info = stub_exit_info
         elseif exit_uid == uid then
            -- here if room leads back to itself
            exit_info = stub_exit_info
            linetype = miniwin.pen_dash -- dash
         else
         --if (not show_other_areas and rooms [exit_uid].area ~= current_area) or
            if (not show_other_areas and rooms [exit_uid].area ~= current_area and not rooms[exit_uid].unknown) or
               (not show_up_down and (dir == "u" or dir == "d")) then
               exit_info = stub_exit_info    -- don't show other areas
            else
               -- if we are scheduled to draw the room already, only draw a stub this time
               if plan_to_draw [exit_uid] and plan_to_draw [exit_uid] ~= next_coords then
                  -- here if room already going to be drawn
                  exit_info = stub_exit_info
                  linetype = miniwin.pen_dash -- dash
               else
                  -- remember to draw room next iteration
                  local n = #rooms_to_be_drawn_uid + 1
                  rooms_to_be_drawn_uid[n] = exit_uid
                  rooms_to_be_drawn_x[n] = next_x
                  rooms_to_be_drawn_y[n] = next_y
                  drawn_coords [next_coords] = exit_uid
                  plan_to_draw [exit_uid] = next_coords

                  -- if exit room known
                  if not rooms [exit_uid].unknown then
                     local exit_time = last_visited [exit_uid] or 0
                     local this_time = last_visited [uid] or 0
                     if exit_time > (draw_now - LAST_VISIT_TIME) and
                        this_time > (draw_now - LAST_VISIT_TIME) then
                        linewidth = 2
                     end -- if
                  end -- if
               end -- if
            end -- if
         end -- if drawn on this spot

         if on_screen then
            local draw_t0 = detailed_timing and utils.timer()
            WindowLine (win, x + exit_info.x1, y + exit_info.y1, x + exit_info.x2, y + exit_info.y2, exit_line_colour, linetype + 0x0200, linewidth)

            -- one-way exit?

            if not rooms [exit_uid].unknown then
               local dest = rooms [exit_uid]
               -- if inverse direction doesn't point back to us, this is one-way
               if dest.exits [inverse_direction [dir]] ~= uid then
                  -- turn points into string, relative to where the room is
                  local points = string.format ("%i,%i,%i,%i,%i,%i",
                     x + arrow [1],
                     y + arrow [2],
                     x + arrow [3],
                     y + arrow [4],
                     x + arrow [5],
                     y + arrow [6])

                  -- draw arrow
                  WindowPolygon(win, points,
                     exit_line_colour, miniwin.pen_solid, 1,
                     exit_line_colour, miniwin.brush_solid,
                     true, true)
               end -- one way
            end -- if we know of the room where it does
            if draw_t0 then
               exit_draw_accum = exit_draw_accum + (utils.timer() - draw_t0)
            end
         end -- if on_screen (exit drawing)
      end -- if we know what to do with this direction
   end -- for each exit

   if detailed_timing and exit_start_time then
      local exit_total = utils.timer() - exit_start_time
      total_exit_drawing_time = total_exit_drawing_time + exit_draw_accum
      total_exit_planning_time = total_exit_planning_time + (exit_total - exit_draw_accum)
   end

   -- off-screen rooms only needed exit traversal above
   if not on_screen then
      return
   end

   -- graphics operations
   local graphics_start_time = nil
   if detailed_timing then
      graphics_start_time = utils.timer()
   end

   if room.unknown then
      WindowCircleOp (win, miniwin.circle_rectangle, left, top, right, bottom,
         UNKNOWN_ROOM_COLOUR.colour, miniwin.pen_dot, 1,  --  dotted single pixel pen
         0, miniwin.brush_hatch_forwards_diagonal)  -- opaque, no brush
   else
      -- room fill
      WindowCircleOp (win, miniwin.circle_rectangle, left, top, right, bottom,
         0, miniwin.pen_null, 0,  -- no pen
         room.fillcolour, room.fillbrush)  -- brush

      -- room border
      WindowCircleOp (win, miniwin.circle_rectangle, left, top, right, bottom,
         room.bordercolour, room.borderpen, room.borderpenwidth,  -- pen
         -1, miniwin.brush_null)  -- opaque, no brush

      -- mark rooms with notes
      if room.notes ~= nil and room.notes ~= "" then
         WindowCircleOp (win, miniwin.circle_rectangle, left-1-room.borderpenwidth, top-1-room.borderpenwidth,
            right+1+room.borderpenwidth, bottom+1+room.borderpenwidth,ROOM_NOTE_COLOUR.colour,
            room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
      end
   end -- if

   if detailed_timing and graphics_start_time then
      total_graphics_time = total_graphics_time + (utils.timer() - graphics_start_time)
   end

   -- skip hotspot creation during drag (preserves active drag callback)
   local hotspot_start_time = nil
   if detailed_timing then
      hotspot_start_time = utils.timer()
   end

   if not pan_dragging then
      WindowAddHotspot(win, uid,
         left, top, right, bottom,   -- rectangle
         "",  -- mouseover
         "",  -- cancelmouseover
         "mapper.pan_mousedown",  -- mousedown (for dragging)
         "",  -- cancelmousedown
         "mapper.mouseup_room",  -- mouseup
         room.hovermessage,
         miniwin.cursor_hand, 0)  -- hand cursor

      WindowDragHandler(win, uid, "mapper.pan_dragmove", "mapper.pan_dragrelease", 0)
      WindowScrollwheelHandler (win, uid, "mapper.zoom_map")
   end

   if detailed_timing and hotspot_start_time then
      total_hotspot_time = total_hotspot_time + (utils.timer() - hotspot_start_time)
   end

   -- track total time for this room
   if detailed_timing and room_start_time then
      local room_time = utils.timer() - room_start_time
      table.insert(room_draw_times, room_time)
      rooms_drawn_count = rooms_drawn_count + 1
   end
end -- draw_room

local function changed_room (uid)
   if current_speedwalk then
      if uid ~= expected_room then
         local exp = rooms [expected_room]
         if not exp then
            exp = get_room (expected_room) or { name = expected_room }
         end -- if
         local here = rooms [uid]
         if not here then
            here = get_room (uid) or { name = uid }
         end -- if
         exp = expected_room
         here = uid
         maperror (string.format ("Speedwalk failed! Expected to be in '%s' but ended up in '%s'.", exp, here))
         cancel_speedwalk ()
      else
         if #current_speedwalk > 0 then
            local dir = table.remove (current_speedwalk, 1)
            SetStatus ("Walking " .. (expand_direction [dir.dir] or dir.dir) ..
               " to " .. walk_to_room_name ..
               ". Speedwalks to go: " .. #current_speedwalk + 1)
            expected_room = dir.uid
            Send (dir.dir)
         else
            last_hyperlink_uid = nil
            last_speedwalk_uid = nil
            if show_completed then
               mapprint ("Speedwalk completed.")
            end -- if wanted
            cancel_speedwalk ()
         end -- if any left
      end -- if expected room or not
   end -- if have a current speedwalk
end -- changed_room

local function draw_zone_exit (exit)
   local x, y, def = exit.x, exit.y, exit.def
   local offset = ROOM_SIZE

   WindowLine (win, x + def.x1, y + def.y1, x + def.x2, y + def.y2, ColourNameToRGB("yellow"), miniwin.pen_solid + 0x0200, 5)
   WindowLine (win, x + def.x1, y + def.y1, x + def.x2, y + def.y2, ColourNameToRGB("green"), miniwin.pen_solid + 0x0200, 1)
end --  draw_zone_exit


----------------------------------------------------------------------------------
--  EXPOSED FUNCTIONS
----------------------------------------------------------------------------------

-- can we find another room right now?

function check_we_can_find ()
   if not current_room then
      mapprint ("I don't know where you are right now - try: LOOK")
      check_connected ()
      return false
   end
   if current_speedwalk then
      mapprint ("The mapper has detected a speedwalk initiated inside another speedwalk. Aborting.")
      return false
   end -- if
   return true
end -- check_we_can_find

-- draw our map starting at room: uid
dont_draw = false
function halt_drawing(halt)
   dont_draw = halt
   if halt then
      -- bigmap overlay will destroy all hotspots on this window,
      -- killing any active drag without firing pan_dragrelease
      pan_dragging = false
   end
end

-- invalidate cached room data (call when GMCP updates a room, notes change, etc.)
function invalidate_room(uid)
   if uid then
      rooms[uid] = nil
   else
      rooms = {}
      prev_draw_room = nil
      prev_draw_area = nil
   end
end

blink_cycle = {
   "@R",
   "@Y",
   "@W"
}
function blink_title()
   prev_title_color = title_color
   if not config.BLINK_PK_TITLE then
      title_color = "@R"
   else
      next_blink_color = (next_blink_color % (#blink_cycle)) + 1
      title_color = blink_cycle[next_blink_color]
   end
   if prev_title_color ~= title_color then
      dress_window(truncated_room_name, current_room, current_area)
      CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
   end
end

function dress_window(room_name, room_uid, area_name)
   bodyleft, bodytop, bodyright, bodybottom = Theme.DressWindow(win, FONT_ID, title_color..room_name, "center")

   -- room ID number
   if config.SHOW_ROOM_ID then
      if room_uid:sub(1,5) == "nomap" then
         room_uid = "NONE"
      end

      Theme.DrawTextBox(win, FONT_ID,
         (config.WINDOW.width - WindowTextWidth (win, FONT_ID, "ID: "..room_uid)) / 2,   -- left
         bodytop,    -- top
         "ID: "..room_uid, false, false
      )
   end

   -- area name
   if area_name then
      Theme.DrawTextBox(win, FONT_ID,
         (config.WINDOW.width - WindowTextWidth (win, FONT_ID, area_name)) / 2,   -- left
         config.WINDOW.height - 4 - font_height,    -- top
         area_name:gsub("^%l", string.upper), false, false
      )
   end

   -- help button
   if type (show_help) == "function" then
      local x = config.WINDOW.width - WindowTextWidth (win, FONT_ID, "?") - 6
      local y = math.max(2, (bodytop-font_height)/2)
      local box_right, box_bottom = Theme.DrawTextBox(win, FONT_ID,
         x-1,   -- left
         y-2,   -- top
         "?", false, false
      )
      local box_width = box_right - (x-1)

      if not pan_dragging then
         WindowAddHotspot(win, "<help>",
            x-3, y-4, x+box_width+3, y + font_height,   -- rectangle
            "",  -- mouseover
            "",  -- cancelmouseover
            "",  -- mousedown
            "",  -- cancelmousedown
            "mapper.show_help",  -- mouseup
            "Click for help",
            miniwin.cursor_help, 0
         )
      end
   end -- if

   -- configuration
   if draw_configure_box then
      -- dropdown
      draw_configuration ()
   else
      -- button
      WindowShow(config_win, false)
      local x = 2
      local y = math.max(2, (bodytop-font_height)/2)
      local text_width = Theme.DrawTextBox(win, FONT_ID,
         x,   -- left
         y-2,   -- top
         "*", false, false)

      if not pan_dragging then
         WindowAddHotspot(win, "<configure>",
            x-2, y-4, x+text_width, y + font_height,   -- rectangle
            "",  -- mouseover
            "",  -- cancelmouseover
            "",  -- mousedown
            "",  -- cancelmousedown
            "mapper.mouseup_configure",  -- mouseup
            "Click to configure map",
            miniwin.cursor_plus, 0)
      end
   end
end

function draw (uid)
   if not uid then
      maperror "Cannot draw map right now, I don't know where you are - try: LOOK"
      return
   end -- if

   if current_room and current_room ~= uid then
      changed_room (uid)
   end -- if

   current_room = uid -- remember where we are

   if dont_draw then
      DeleteTimer("blink_title")
      -- reset pan so the map is centered when drawing resumes
      if pan_offset_x ~= 0 or pan_offset_y ~= 0 then
         pan_offset_x = 0
         pan_offset_y = 0
         if pan_animating then
            DeleteTimer("pan_animate")
            pan_animating = false
         end
      end
      return
   end

   -- timing
   local start_time = utils.timer ()

   -- reset room drawing metrics for this frame
   if detailed_timing then
      room_draw_times = {}
      rooms_drawn_count = 0
      total_exit_planning_time = 0
      total_exit_drawing_time = 0
      total_room_cache_time = 0
      total_room_db_time = 0
      total_room_defaults_time = 0
      total_room_texture_time = 0
      total_graphics_time = 0
      total_hotspot_time = 0
      total_window_setup_time = 0
      total_bg_texture_time = 0
      total_room_loop_time = 0
      total_zone_exit_time = 0
      total_dress_window_time = 0
      room_cache_hits = 0
      room_cache_misses = 0
   end

   draw_now = os.time ()

   -- selective cache invalidation: fetch current room fresh (needs OUR_ROOM_COLOUR)
   local fresh_current = get_room (uid)
   local new_area = fresh_current and fresh_current.area

   if prev_draw_area ~= nil and prev_draw_area ~= new_area then
      -- area changed: all border decisions depend on current_area, clear everything
      rooms = {}
   elseif prev_draw_room and prev_draw_room ~= uid then
      -- same area, different room: invalidate old current room (had OUR_ROOM_COLOUR)
      rooms[prev_draw_room] = nil
   end

   rooms[uid] = fresh_current
   prev_draw_room = uid
   prev_draw_area = new_area

   -- lookup current room
   local room = rooms [uid]

   room = room or { name = "<Unknown room>", area = "<Unknown area>" }
   last_visited [uid] = os.time ()

   current_area = room.area

   -- check for area change and start smooth pan reset
   if last_area_for_pan ~= nil and last_area_for_pan ~= current_area then
      if not pan_animating and (pan_offset_x ~= 0 or pan_offset_y ~= 0) then
         start_pan_animation()
      end
   end
   last_area_for_pan = current_area

   -- update dimensions and position here because the bigmap might have changed them
   local setup_t0 = detailed_timing and utils.timer()
   windowinfo.window_left = WindowInfo(win, 1) or windowinfo.window_left
   windowinfo.window_top = WindowInfo(win, 2) or windowinfo.window_top
   config.WINDOW.width = WindowInfo(win, 3) or config.WINDOW.width
   config.WINDOW.height = WindowInfo(win, 4) or config.WINDOW.height

   -- check if window already exists (preserves zzz_zoom hotspot for drag operations)
   local window_exists = WindowInfo(win, 1) ~= nil
   
   if window_exists then
      -- during drag, skip hotspot updates (just redraw graphics)
      if not pan_dragging then
         -- delete all hotspots except zzz_zoom
         local hotspots = WindowHotspotList(win) or {}
         for _, hs in ipairs(hotspots) do
            if hs ~= "zzz_zoom" then
               WindowDeleteHotspot(win, hs)
            end
         end
      end
      -- clear the window contents (skip if background texture will cover it)
      if room.textimage == nil or config.USE_TEXTURES.enabled ~= true then
         WindowRectOp(win, 2, 0, 0, config.WINDOW.width, config.WINDOW.height, Theme.PRIMARY_BODY)
      end
   else
      -- create new window
      WindowCreate (win,
         windowinfo.window_left,
         windowinfo.window_top,
         config.WINDOW.width,
         config.WINDOW.height,
         windowinfo.window_mode,   -- top right
         windowinfo.window_flags,
         Theme.PRIMARY_BODY)
   end

   if setup_t0 then
      total_window_setup_time = utils.timer() - setup_t0
   end

   -- Handle background texture (cached for performance)
   local bg_t0 = detailed_timing and utils.timer()
   if room.textimage ~= nil and config.USE_TEXTURES.enabled == true then
      -- check if we need to regenerate the cached background
      local need_regen = (
         cached_bg_image == nil
         or cached_bg_width ~= config.WINDOW.width
         or cached_bg_height ~= config.WINDOW.height
         or cached_bg_texture ~= room.textimage
      )
      if need_regen then
         -- tile the texture directly into win first
         local iwidth = WindowImageInfo(win, room.textimage, 2)
         local iheight = WindowImageInfo(win, room.textimage, 3)
         local x, y = 0, 0
         while y < config.WINDOW.height do
            x = 0
            while x < config.WINDOW.width do
               WindowDrawImage(win, room.textimage, x, y, 0, 0, 1)
               x = x + iwidth
            end
            y = y + iheight
         end
         
         -- capture the tiled result as a cached image
         cached_bg_image = "cached_bg"
         WindowImageFromWindow(win, cached_bg_image, win)
         
         cached_bg_width = config.WINDOW.width
         cached_bg_height = config.WINDOW.height
         cached_bg_texture = room.textimage
      else
         -- single blit of cached background
         WindowDrawImage(win, cached_bg_image, 0, 0, 0, 0, 1)
      end
   end

   if bg_t0 then
      total_bg_texture_time = utils.timer() - bg_t0
   end

   -- for zooming and panning (only create if hotspot doesn't already exist)
   if WindowHotspotInfo(win, "zzz_zoom", 1) == nil then
      WindowAddHotspot(win,
         "zzz_zoom",
         0, 0, config.WINDOW.width, config.WINDOW.height,
         "", "", "mapper.pan_mousedown", "", "mapper.MouseUp",
         "Drag to pan map",
         miniwin.cursor_hand, 0)

      WindowDragHandler(win, "zzz_zoom", "mapper.pan_dragmove", "mapper.pan_dragrelease", 0)
      WindowScrollwheelHandler (win, "zzz_zoom", "mapper.zoom_map")
   end

   -- set up for initial room, in middle
   drawn, drawn_coords, plan_to_draw, area_exits = {}, {}, {}, {}
   rooms_to_be_drawn_uid, rooms_to_be_drawn_x, rooms_to_be_drawn_y = {}, {}, {}
   drawn_min_x, drawn_min_y, drawn_max_x, drawn_max_y = nil, nil, nil, nil
   depth = 0

   -- insert initial room (with pan offset applied)
   local center_x = config.WINDOW.width / 2 + pan_offset_x
   local center_y = config.WINDOW.height / 2 + pan_offset_y
   rooms_to_be_drawn_uid[1] = uid
   rooms_to_be_drawn_x[1] = center_x
   rooms_to_be_drawn_y[1] = center_y

   local loop_t0 = detailed_timing and utils.timer()
   while #rooms_to_be_drawn_uid > 0 and depth < config.SCAN.depth do
      local old_uid, old_x, old_y = rooms_to_be_drawn_uid, rooms_to_be_drawn_x, rooms_to_be_drawn_y
      rooms_to_be_drawn_uid, rooms_to_be_drawn_x, rooms_to_be_drawn_y = {}, {}, {}
      for i = 1, #old_uid do
         draw_room (old_uid[i], old_x[i], old_y[i])
      end -- for each existing room
      depth = depth + 1
   end -- while rooms to be drawn
   if loop_t0 then
      total_room_loop_time = utils.timer() - loop_t0
   end

   -- if all rooms are off-screen (e.g. teleported within area while panned), reset pan
   if drawn_min_x == nil and (pan_offset_x ~= 0 or pan_offset_y ~= 0) and not pan_animating then
      start_pan_animation()
   end

   local zone_t0 = detailed_timing and utils.timer()
   for area, zone_exit in pairs (area_exits) do
      draw_zone_exit (zone_exit)
   end -- for
   if zone_t0 then
      total_zone_exit_time = utils.timer() - zone_t0
   end

   local dress_t0 = detailed_timing and utils.timer()
   truncated_room_name = room.name
   local name_width = WindowTextWidth (win, FONT_ID, truncated_room_name)
   local add_dots = false

   -- truncate name if too long
   local available_width = (config.WINDOW.width - 20 - WindowTextWidth (win, FONT_ID, "*?"))
   while name_width > available_width do
      truncated_room_name = truncated_room_name:sub(1, -3)
      name_width = WindowTextWidth (win, FONT_ID, truncated_room_name .. "...")
      add_dots = true
      if truncated_room_name == "" then
         break
      end
   end -- while

   if add_dots then
      truncated_room_name = truncated_room_name .. "..."
   end -- if

   is_pk = false
   if room.info then
      for _,v in ipairs(utils.split(room.info, ",")) do
         if v == "pk" then
            is_pk = true
            break
         end
      end
   end

   title_color = ""
   next_blink_color = 0
   if not is_pk then
      DeleteTimer("blink_title")
   else
      blink_title()
      AddTimer("blink_title", 0, 0, 0.5, "", timer_flag.Enabled + timer_flag.Temporary + timer_flag.Replace, "mapper.blink_title")
   end

   dress_window(truncated_room_name, uid, room.area)

   Theme.AddResizeTag(win, 1, nil, nil, "mapper.resize_mouse_down", "mapper.resize_move_callback", "mapper.resize_release_callback")

   -- make sure window visible
   WindowShow (win, not window_hidden)
   if dress_t0 then
      total_dress_window_time = utils.timer() - dress_t0
   end

   last_drawn = uid  -- last room number we drew (for zooming)

   local end_time = utils.timer ()
   local frame_time = end_time - start_time

   -- frame total + rolling average (last 30 frames)
   if timing or detailed_timing then
      recent_frame_index = (recent_frame_index % RECENT_FRAME_COUNT) + 1
      recent_frame_times[recent_frame_index] = frame_time
      local n = #recent_frame_times
      local sum = 0
      for i = 1, n do
         sum = sum + recent_frame_times[i]
      end
      print (string.format ("=== Mapper frame: depth %i, %0.1f ms (avg %0.1f ms over %i frames) ===",
         depth, frame_time * 1000, sum / n * 1000, n))
   end

   -- detailed timing breakdown
   if detailed_timing then
      local count = 0
      for k in pairs (drawn) do
         count = count + 1
      end

      -- helper for consistent formatting
      local function pct(t) return (frame_time > 0) and (t / frame_time * 100) or 0 end
      local function ms(t) return t * 1000 end

      print (string.format ("  (%i rooms drawn)", count))

      -- outer draw() phases
      print (string.format ("  Window setup:      %6.2f ms  (%4.1f%%)", ms(total_window_setup_time), pct(total_window_setup_time)))
      print (string.format ("  Background tex:    %6.2f ms  (%4.1f%%)", ms(total_bg_texture_time), pct(total_bg_texture_time)))
      print (string.format ("  Room loop:         %6.2f ms  (%4.1f%%)", ms(total_room_loop_time), pct(total_room_loop_time)))
      print (string.format ("  Zone exits:        %6.2f ms  (%4.1f%%)", ms(total_zone_exit_time), pct(total_zone_exit_time)))
      print (string.format ("  Dress window:      %6.2f ms  (%4.1f%%)", ms(total_dress_window_time), pct(total_dress_window_time)))

      -- room loop breakdown
      if rooms_drawn_count > 0 then
         local sum_room_time = 0
         local min_room_time = 999999
         local max_room_time = 0
         for _, t in ipairs(room_draw_times) do
            sum_room_time = sum_room_time + t
            if t < min_room_time then min_room_time = t end
            if t > max_room_time then max_room_time = t end
         end
         local avg_room_time = sum_room_time / rooms_drawn_count
         local loop_overhead = total_room_loop_time - sum_room_time

         print (string.format ("  --- Room loop breakdown (%i rooms) ---", rooms_drawn_count))
         print (string.format ("    Per-room:  avg %0.4f ms, min %0.4f ms, max %0.4f ms",
            ms(avg_room_time), ms(min_room_time), ms(max_room_time)))
         local total_lookups = room_cache_hits + room_cache_misses
         print (string.format ("    Cache: %i hits, %i misses (%0.1f%% hit rate)",
            room_cache_hits, room_cache_misses,
            (total_lookups > 0) and (room_cache_hits / total_lookups * 100) or 0))
         print (string.format ("    Exit planning:   %6.2f ms  (%4.1f%%)", ms(total_exit_planning_time), pct(total_exit_planning_time)))
         print (string.format ("      get_room:      %6.2f ms  (%4.1f%%)", ms(total_room_cache_time), pct(total_room_cache_time)))
         print (string.format ("        DB lookup:   %6.2f ms  (%4.1f%%)", ms(total_room_db_time), pct(total_room_db_time)))
         print (string.format ("        defaults:    %6.2f ms  (%4.1f%%)", ms(total_room_defaults_time), pct(total_room_defaults_time)))
         print (string.format ("        texture:     %6.2f ms  (%4.1f%%)", ms(total_room_texture_time), pct(total_room_texture_time)))
         local gr_other = total_room_cache_time - total_room_db_time - total_room_defaults_time - total_room_texture_time
         if ms(gr_other) >= 0.01 then
            print (string.format ("        other:       %6.2f ms  (%4.1f%%)", ms(gr_other), pct(gr_other)))
         end
         local plan_other = total_exit_planning_time - total_room_cache_time
         print (string.format ("      other logic:   %6.2f ms  (%4.1f%%)", ms(plan_other), pct(plan_other)))
         print (string.format ("    Exit drawing:    %6.2f ms  (%4.1f%%)", ms(total_exit_drawing_time), pct(total_exit_drawing_time)))
         print (string.format ("    Room graphics:   %6.2f ms  (%4.1f%%)", ms(total_graphics_time), pct(total_graphics_time)))
         print (string.format ("    Hotspot setup:   %6.2f ms  (%4.1f%%)", ms(total_hotspot_time), pct(total_hotspot_time)))
         print (string.format ("    Loop overhead:   %6.2f ms  (%4.1f%%)", ms(loop_overhead), pct(loop_overhead)))
      end

      -- unaccounted time
      local accounted = total_window_setup_time + total_bg_texture_time + total_room_loop_time
                      + total_zone_exit_time + total_dress_window_time
      local unaccounted = frame_time - accounted
      print (string.format ("  Unaccounted:       %6.2f ms  (%4.1f%%)", ms(unaccounted), pct(unaccounted)))
   end -- if detailed_timing

   if pan_animating then
      CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint", 0.04)
   else
      CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
   end
end -- draw

local credits = {
   "MUSHclient mapper",
   string.format ("Version %0.1f", VERSION),
   "Made for Aardwolf by Fiendish",
   "Based on work by Nick Gammon",
   "World: "..WorldName (),
   GetInfo (3),
}

-- call once to initialize the mapper
function init (t)

   -- make copy of colours, sizes etc.
   findpath = t.findpath
   config = t.config
   assert (type (config) == "table", "No 'config' table supplied to mapper.")

   supplied_get_room = t.get_room
   assert (type (supplied_get_room) == "function", "No 'get_room' function supplied to mapper.")

   show_help = t.show_help     -- "help" function
   room_click = t.room_click   -- RH mouse-click function
   timing = t.timing                   -- true for frame timing summary
   detailed_timing = t.detailed_timing  -- true for detailed sub-phase breakdown
   show_completed = t.show_completed  -- true to show "Speedwalk completed." message
   show_other_areas = t.show_other_areas  -- true to show other areas
   show_up_down = t.show_up_down        -- true to show up or down
   speedwalk_prefix = t.speedwalk_prefix  -- how to speedwalk (prefix)

   -- force some config defaults if not supplied
   for k, v in pairs (default_config) do
      if config[k] == nil then
         config[k] = v
      end
   end -- for

   win = GetPluginID () .. "_mapper"
   config_win = GetPluginID () .. "_z_config_win"

   WindowCreate (win, 0, 0, 0, 0, 0, 0, 0)
   WindowCreate(config_win, 0, 0, 0, 0, 0, 0, 0)

   -- add the fonts
   WindowFont (win, FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (win, FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)
   WindowFont (config_win, CONFIG_FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (config_win, CONFIG_FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)

   -- see how high it is
   font_height = WindowFontInfo (win, FONT_ID, 1)  -- height

   -- find where window was last time
   windowinfo = movewindow.install (win, miniwin.pos_bottom_right, miniwin.create_absolute_location , true, {config_win}, {mouseup=MouseUp, mousedown=LeftClickOnly, dragmove=LeftClickOnly, dragrelease=LeftClickOnly}, {x=default_x, y=default_y})

   -- calculate box sizes, arrows, connecting lines etc.
   build_room_info ()

   -- ensure config has proper defaults if not set
   if not config.WINDOW then config.WINDOW = {} end
   config.WINDOW.width = config.WINDOW.width or default_width
   config.WINDOW.height = config.WINDOW.height or default_height

   WindowCreate (win,
      windowinfo.window_left,
      windowinfo.window_top,
      config.WINDOW.width,
      config.WINDOW.height,
      windowinfo.window_mode,   -- top right
      windowinfo.window_flags,
      Theme.PRIMARY_BODY)

   -- let them move it around
   movewindow.add_drag_handler (win, 0, 0, 0, 0)

   local top = (config.WINDOW.height - #credits * font_height) /2

   for _, v in ipairs (credits) do
      local width = WindowTextWidth (win, FONT_ID, v)
      local left = (config.WINDOW.width - width) / 2
      WindowText (win, FONT_ID, v, left, top, 0, 0, Theme.BODY_TEXT)
      top = top + font_height
   end -- for

   Theme.DrawBorder(win)
   Theme.AddResizeTag(win, 1, nil, nil, "mapper.resize_mouse_down", "mapper.resize_move_callback", "mapper.resize_release_callback")

   WindowShow (win, not window_hidden)
   WindowShow (config_win, false)

end -- init

function MouseUp(flags, hotspot_id, win)
   if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      right_click_menu()
   end
   return true
end

function LeftClickOnly(flags, hotspot_id, win)
   if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      return true
   end
   return false
end

function right_click_menu()
   menustring = "Bring To Front|Send To Back"

   -- add center map option if panned
   if pan_offset_x ~= 0 or pan_offset_y ~= 0 then
      menustring = menustring.."|-|Center Map"
   end

   rc, a, b, c = CallPlugin("60840c9013c7cc57777ae0ac", "getCurrentState")
   if rc == 0 and a == true then
      if b == 1 then
         menustring = menustring.."|-|Show Continent Bigmap"
      elseif c == 1 then
         menustring = menustring.."|-|Merge Continent Bigmap Into GMCP Mapper"
      end
   end

   result = WindowMenu (win,
      WindowInfo (win, 14),  -- x position
      WindowInfo (win, 15),   -- y position
      menustring) -- content
   if result == "Bring To Front" then
      CallPlugin("462b665ecb569efbf261422f","boostMe", win)
   elseif result == "Send To Back" then
      CallPlugin("462b665ecb569efbf261422f","dropMe", win)
   elseif result == "Center Map" then
      reset_pan()
   elseif result == "Show Continent Bigmap" then
      Execute("bigmap on")
   elseif result == "Merge Continent Bigmap Into GMCP Mapper" then
      Execute("bigmap merge")
   end
end

function zoom_in ()
   if last_drawn and ROOM_SIZE < 40 then
      ROOM_SIZE = ROOM_SIZE + 2
      DISTANCE_TO_NEXT_ROOM = DISTANCE_TO_NEXT_ROOM + 2
      build_room_info ()
      draw (last_drawn)
      SaveState()
   end -- if
end -- zoom_in


function zoom_out ()
   if last_drawn and ROOM_SIZE > 4 then
      ROOM_SIZE = ROOM_SIZE - 2
      DISTANCE_TO_NEXT_ROOM = DISTANCE_TO_NEXT_ROOM - 2
      build_room_info ()
      draw (last_drawn)
      SaveState()
   end -- if
end -- zoom_out

function mapprint (...)
   local old_note_colour = GetNoteColourFore ()
   SetNoteColourFore(MAPPER_NOTE_COLOUR.colour)
   print (...)
   SetNoteColourFore (old_note_colour)
end -- mapprint

function maperror (...)
   local old_note_colour = GetNoteColourFore ()
   SetNoteColourFore(ColourNameToRGB "red")
   print (...)
   SetNoteColourFore (old_note_colour)
end -- maperror

function show()
   WindowShow(win, true)
   hidden = false
end -- show

function hide()
   WindowShow(win, false)
   hidden = true
end -- hide

function save_state ()
   SetVariable("ROOM_SIZE", ROOM_SIZE)
   SetVariable("DISTANCE_TO_NEXT_ROOM", DISTANCE_TO_NEXT_ROOM)
   if WindowInfo(win,1) and WindowInfo(win,5) then
      movewindow.save_state (win)
      config.WINDOW.width = WindowInfo(win, 3)
      config.WINDOW.height = WindowInfo(win, 4)
   end
end -- save_state

function hyperlinkGoto(uid)
   mapper.goto(uid)
   for i,v in ipairs(last_result_list) do
      if uid == v then
         next_result_index = i
         break
      end
   end
end

require "serialize"
function full_find (dests, show_uid, expected_count, walk, fcb, no_portals)
   local paths = {}
   local notfound = {}
   for i,v in ipairs(dests) do
      SetStatus (string.format ("Pathfinding: searching for route to %i/%i discovered destinations", i, #dests))
      CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
      local foundpath = findpath(current_room, v.uid, no_portals, no_portals)
      if not rooms [v.uid] then
         rooms [v.uid] = get_room (v.uid)
      end
      if foundpath ~= nil then
         paths[v.uid] = {path=foundpath, reason=v.reason}
      else
         table.insert(notfound, {uid=v.uid, reason=v.reason})
      end
   end
   SetStatus ("")

   BroadcastPlugin(500, "found_paths = "..string.gsub(serialize.save_simple(paths),"%s+"," "))
   BroadcastPlugin(501, "unfound_paths = "..string.gsub(serialize.save_simple(notfound),"%s+"," "))

   local t = {}
   local found_count = 0
   for k in pairs (paths) do
      table.insert (t, k)
      found_count = found_count + 1
   end -- for

   -- sort so closest ones are first
   table.sort (t, function (a, b) return #paths [a].path < #paths [b].path end )

   if walk and t[1] then
      local uid = t[1]
      local path = paths[uid].path
      mapprint ("Going to:", rooms[uid].name)
      start_speedwalk(path)
      return
   end -- if walking wanted

   Note("+------------------------------ START OF SEARCH -------------------------------+")
   for _, uid in ipairs (t) do
      local room = rooms [uid] -- ought to exist or wouldn't be in table
      assert (room, "Room " .. uid .. " is not in rooms table.")

      local distance = #paths [uid].path .. " room"
      if #paths [uid].path > 1 or #paths[uid].path == 0 then
         distance = distance .. "s"
      end -- if
      distance = distance .. " away"

      local room_name = room.name
      room_name = room_name .. " (" .. room.area .. ")"

      if show_uid then
         room_name = room_name .. " (" .. uid .. ")"
      end -- if

      if current_room ~= uid then
         table.insert(last_result_list, uid)
         Hyperlink ("!!" .. GetPluginID () .. ":mapper.hyperlinkGoto(" .. uid .. ")",
            "["..#last_result_list.."] "..room_name, "Click to speedwalk there (" .. distance .. ")", "", "", false, NoUnderline_hyperlinks)
      else
         Tell(room_name)
      end
      local info = ""
      if type (paths [uid].reason) == "string" and paths [uid].reason ~= "" then
         info = " [" .. paths [uid].reason .. "]"
      end -- if
      mapprint (" - " .. distance .. info) -- new line

      -- callback to display extra stuff (like find context, room description)
      if fcb then
         fcb (uid)
      end -- if callback
   end -- for each room

   if expected_count and found_count < expected_count then
      local diff = expected_count - found_count
      local were, matches = "were", "matches"
      if diff == 1 then
         were, matches = "was", "match"
      end -- if
      Note("+------------------------------------------------------------------------------+")
      mapprint ("There", were, diff, matches,
         "which I could not find a path to within",
         config.SCAN.depth, "rooms:")
   end -- if
   for i,v in ipairs(notfound) do
      local nfroom = rooms[v.uid]
      local nfline = nfroom.name
      nfline = nfline .. " (" .. nfroom.area .. ")"

      if show_uid then
         nfline = nfline .. " (" .. v.uid .. ")"
      end -- if
      Tell(nfline)
      if type (v.reason) == "string" and v.reason ~= "" then
         nfinfo = " - [" .. v.reason .. "]"
         mapprint (nfinfo) -- new line
      else
         Note("")
      end -- if
   end

   Note("+-------------------------------- END OF SEARCH -------------------------------+")
end

function quick_find(dests, show_uid, expected_count, walk, fcb)
   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
   Note("+------------------------------ START OF SEARCH -------------------------------+")

   for i,v in ipairs(dests) do
      local uid = v.uid
      if not rooms[uid] then
         rooms[uid] = get_room(uid)
      end -- if
      local room = rooms[uid] -- ought to exist or wouldn't be in table

      assert (room, "Room " .. v.uid .. " is not in rooms table.")

      local room_name = room.name
      room_name = room_name .. " (" .. room.area .. ")"
      if show_uid then
         room_name = room_name .. " (" .. v.uid .. ")"
      end

      if current_room ~= v.uid then
         table.insert(last_result_list, v.uid)
         Hyperlink ("!!" .. GetPluginID () .. ":mapper.hyperlinkGoto("..v.uid..")",
            "["..#last_result_list.."] "..room_name, "Click to speedwalk there", "", "", false, NoUnderline_hyperlinks)
      else
         ColourTell(RGBColourToName(MAPPER_NOTE_COLOUR.colour),"","[you are here] "..room_name)
      end

      local info = ""
      if type (v.reason) == "string" and v.reason ~= "" then
         info = " [" .. v.reason .. "]"
         mapprint (" - " .. info) -- new line
      else -- if
         Note("")
      end

      -- callback to display extra stuff (like find context, room description)
      if fcb then
         fcb (uid)
      end -- if callback

      CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
   end -- for each room

   Note("+-------------------------------- END OF SEARCH -------------------------------+")
end

function gotoNextResult(which)
   if tonumber(which) == nil then
      if next_result_index ~= nil then
         next_result_index = next_result_index+1
         if next_result_index <= #last_result_list then
            mapper.goto(last_result_list[next_result_index])
            return
         else
            next_result_index = nil
         end
      end
      ColourNote(RGBColourToName(MAPPER_NOTE_COLOUR.colour),"","NEXT ERROR: No more NEXT results left.")
   else
      next_result_index = tonumber(which)
      if (next_result_index > 0) and (next_result_index <= #last_result_list) then
         mapper.goto(last_result_list[next_result_index])
         return
      else
         ColourNote(RGBColourToName(MAPPER_NOTE_COLOUR.colour),"","NEXT ERROR: There is no NEXT result #"..next_result_index..".")
         next_result_index = nil
      end
   end
end

function goto(uid)
   find (nil,
      {{uid=uid, reason=true}},
      0,
      false,  -- show vnum?
      1,          -- how many to expect
      true        -- just walk there
   )
end

-- generic room finder
-- name is for informational purposes only; it's displayed to the user in the search results
-- dests is a list of room/reason pairs where reason is either true (meaning generic) or a string to find
-- if max_paths <= 0 it's disregarded, otherwise number of dests must be <= max_paths
-- show_uid is true if you want the room uid to be displayed
-- expected_count is the number we expect to find (eg. the number found on a database)
-- if 'walk' is true, we walk to the first match rather than displaying hyperlinks
-- if fcb is a function, it is called back after displaying each line
-- quick_list determines whether we pathfind every destination in advance to be able to sort by distance
function find (name, dests, max_paths, show_uid, expected_count, walk, fcb, quick_list, no_portals)
   if not check_we_can_find () then
      return
   end -- if

   if fcb then
      assert (type (fcb) == "function")
   end -- if

   if max_paths <= 0 then
      max_paths = #dests
   end
   if not walk then
      mapprint ("Found",#dests,"target"..(((#dests ~= 1) and "s") or "")..(((name ~= nil) and (" matching '"..name.."'")) or "")..".")
   end
   if #dests > max_paths then
      mapprint(string.format("Your search returned more than %s results. Choose a more specific pattern.", max_paths))
      return
   end

   if not walk then
      last_result_list = {}
      next_result_index = 0
   end

   if quick_list == true then
      quick_find(dests, show_uid, expected_count, walk, fcb)
   else
      full_find(dests, show_uid, expected_count, walk, fcb, no_portals)
   end
end -- map_find_things

-- build a speedwalk from a path into a string

function build_speedwalk (path, prefix)

   stack_char = ";"
   if GetOption("enable_command_stack")==1 then
      stack_char = GetAlphaOption("command_stack_character")
   else
      stack_char = "\r\n"
   end

   -- build speedwalk string (collect identical directions)
   local tspeed = {}
   for _, dir in ipairs (path) do
      local n = #tspeed
      if n == 0 then
         table.insert (tspeed, { dir = dir.dir, count = 1 })
      else
         if expand_direction[dir.dir] ~= nil and tspeed [n].dir == dir.dir then
            tspeed [n].count = tspeed [n].count + 1
         else
            table.insert (tspeed, { dir = dir.dir, count = 1 })
         end -- if different direction
      end -- if
   end -- for

   if #tspeed == 0 then
      return
   end -- nowhere to go (current room?)

   -- now build string like: 2n3e4(sw)
   local s = ""

   local new_command = false
   for _, dir in ipairs (tspeed) do
      if expand_direction[dir.dir] ~= nil then
         if new_command then
            s = s .. stack_char .. speedwalk_prefix .. " "
            new_command = false
         end
         if dir.count > 1 then
            s = s .. dir.count
         end -- if
         s = s .. dir.dir
      else
         s = s .. stack_char .. dir.dir
         new_command = true
      end -- if
   end -- if

   if prefix ~= nil then
      if s:sub(1, #stack_char) == stack_char then
         s = s:sub(#stack_char+1)
      else
         s = prefix.." "..s
      end
   end

   s = string.gsub(s, ";", stack_char)

   return s, stack_char
end -- build_speedwalk

-- start a speedwalk to a path

function start_speedwalk (path)

   if not check_connected () then
      return
   end -- if

   if myState == 9 or myState == 11 then
      Send("stand")
   end

   if current_speedwalk and #current_speedwalk > 0 then
      mapprint ("You are already speedwalking! (Ctrl + LH-click on any room to cancel)")
      return
   end -- if

   current_speedwalk = path

   if current_speedwalk then
      if #current_speedwalk > 0 then
         last_speedwalk_uid = current_speedwalk [#current_speedwalk].uid

         -- fast speedwalk: just send # 4s 3e  etc.
         if type (speedwalk_prefix) == "string" and speedwalk_prefix ~= "" then
            local s = speedwalk_prefix .. " "
            local p = build_speedwalk (path)
            if p:sub(1,1) ~= stack_char then
               s = s .. p
            else
               s = p:sub(2)
            end
            ExecuteWithWaits(s:gsub(";","\r\n"))
            current_speedwalk = nil
            return
         end -- if

         local dir = table.remove (current_speedwalk, 1)
         local room = get_room (dir.uid)
         walk_to_room_name = room.name
         SetStatus ("Walking " .. (expand_direction [dir.dir] or dir.dir) ..
            " to " .. walk_to_room_name ..
            ". Speedwalks to go: " .. #current_speedwalk + 1)
         Send (dir.dir)
         expected_room = dir.uid
      else
         cancel_speedwalk ()
      end -- if any left
   end -- if

end -- start_speedwalk

-- cancel the current speedwalk

function cancel_speedwalk ()
   if current_speedwalk and #current_speedwalk > 0 then
      mapprint "Speedwalk cancelled."
   end -- if
   current_speedwalk = nil
   expected_room = nil
   SetStatus ("Ready")
end -- cancel_speedwalk


-- ------------------------------------------------------------------
-- mouse-up handlers (need to be exposed)
-- these are for clicking on the map, or the configuration box
-- ------------------------------------------------------------------

function mouseup_room (flags, hotspot_id)
   local uid = hotspot_id

   if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      -- RH click
      if type (room_click) == "function" then
         room_click (uid, flags)
      end
      return
   end -- if RH click

   -- here for LH click

   -- Control key down?
   if bit.band (flags, miniwin.hotspot_got_control) ~= 0 then
      cancel_speedwalk ()
      return
   end -- if ctrl-LH click

   -- find desired room
   find (nil,
      {{uid=uid, reason=true}},
      0,
      false,  -- show vnum?
      1,          -- how many to expect
      true        -- just walk there
   )
end -- mouseup_room

-- ------------------------------------------------------------------
-- pan handlers for dragging the map view
-- ------------------------------------------------------------------

function pan_mousedown (flags, hotspot_id)
   -- cancel any running animation
   if pan_animating then
      DeleteTimer("pan_animate")
      pan_animating = false
   end
   -- mark as dragging (draw() will skip hotspot updates)
   pan_dragging = true
   -- record starting mouse position for incremental tracking
   pan_last_mouse_x = WindowInfo(win, 17)
   pan_last_mouse_y = WindowInfo(win, 18)
end -- pan_mousedown

function pan_dragmove (flags, hotspot_id)
   -- don't pan if we don't have a room to draw
   if not current_room then
      return
   end
   
   -- get current mouse position
   local mouse_x = WindowInfo(win, 17)
   local mouse_y = WindowInfo(win, 18)
   
   -- calculate incremental delta since last move
   local delta_x = mouse_x - pan_last_mouse_x
   local delta_y = mouse_y - pan_last_mouse_y
   
   -- update last position for next increment
   pan_last_mouse_x = mouse_x
   pan_last_mouse_y = mouse_y
   
   -- accumulate into pan offset
   pan_offset_x = pan_offset_x + delta_x
   pan_offset_y = pan_offset_y + delta_y
   
   -- clamp so at least one room remains visible in the viewport
   if drawn_max_x then
      -- bounding box is from the last draw() using the previous offset;
      -- delta shifts all room positions, so new bbox = old bbox + delta
      local new_min_x = drawn_min_x + delta_x
      local new_max_x = drawn_max_x + delta_x
      local new_min_y = drawn_min_y + delta_y
      local new_max_y = drawn_max_y + delta_y
      local title_height = bodytop or (font_height * 2)
      -- pull back so the whole last room stays in the viewport
      if new_max_x - HALF_ROOM < 0 then
         pan_offset_x = pan_offset_x - (new_max_x - HALF_ROOM)
      elseif new_min_x + HALF_ROOM > config.WINDOW.width then
         pan_offset_x = pan_offset_x - (new_min_x + HALF_ROOM - config.WINDOW.width)
      end
      if new_max_y - HALF_ROOM < title_height then
         pan_offset_y = pan_offset_y - (new_max_y - HALF_ROOM - title_height)
      elseif new_min_y + HALF_ROOM > config.WINDOW.height then
         pan_offset_y = pan_offset_y - (new_min_y + HALF_ROOM - config.WINDOW.height)
      end
   end
   
   -- redraw with new offset (window_exists check in draw() preserves our hotspot)
   draw(current_room)
end -- pan_dragmove

function pan_dragrelease (flags, hotspot_id)
   -- no longer dragging - full redraw will recreate hotspots
   pan_dragging = false
   -- redraw with the new pan offset
   if current_room then
      draw(current_room)
   end
end -- pan_dragrelease

function reset_pan()
   pan_offset_x = 0
   pan_offset_y = 0
   if current_room then
      draw(current_room)
   end
end -- reset_pan

function start_pan_animation()
   pan_animating = true
   AddTimer("pan_animate", 0, 0, 0.05, "", 
      timer_flag.Enabled + timer_flag.Temporary + timer_flag.Replace, 
      "mapper.pan_animate_step")
end -- start_pan_animation

function pan_animate_step()
   -- guard against running if animation was cancelled
   if not pan_animating then
      DeleteTimer("pan_animate")
      return
   end
   
   -- move toward zero: max speed until close, then ease down
   local min_move = 4
   local max_move = 30
   local ease_threshold = 200  -- start easing when within this distance
   
   local dist = math.sqrt(pan_offset_x * pan_offset_x + pan_offset_y * pan_offset_y)

   if dist < min_move then
      pan_offset_x = 0
      pan_offset_y = 0
      pan_animating = false
      DeleteTimer("pan_animate")
      -- final draw at center position
      if current_room then
         draw(current_room)
      end
   else
      -- move along direction vector with easing
      local move
      if dist > ease_threshold then
         move = max_move
      else
         move = min_move + (max_move - min_move) * (dist / ease_threshold)
      end
      move = math.min(move, dist)
      local scale = move / dist
      pan_offset_x = pan_offset_x - pan_offset_x * scale
      pan_offset_y = pan_offset_y - pan_offset_y * scale

      -- draw current frame
      if current_room then
         draw(current_room)
      end
      -- schedule next frame
      AddTimer("pan_animate", 0, 0, 0.05, "", 
         timer_flag.Enabled + timer_flag.Temporary + timer_flag.Replace,
         "mapper.pan_animate_step")
   end
end -- pan_animate_step

function mouseup_configure (flags, hotspot_id)
   draw_configure_box = true
   draw (current_room)
end -- mouseup_configure

function mouseup_close_configure (flags, hotspot_id)
   draw_configure_box = false
   SaveState()
   draw (current_room)
end -- mouseup_player

function mouseup_change_colour (flags, hotspot_id)

   local which = string.match (hotspot_id, "^$colour:([%a%d_]+)$")
   if not which then
      return  -- strange ...
   end -- not found

   local newcolour = PickColour (config [which].colour)

   if newcolour == -1 then
      return
   end -- if dismissed

   config [which].colour = newcolour

   draw (current_room)
end -- mouseup_change_colour

function mouseup_change_font (flags, hotspot_id)

   local newfont =  utils.fontpicker (config.FONT.name, config.FONT.size, ROOM_NAME_TEXT.colour)

   if not newfont then
      return
   end -- if dismissed

   config.FONT.name = newfont.name

   if newfont.size > 12 then
      utils.msgbox ("Maximum allowed font size is 12 points.", "Font too large", "ok", "!", 1)
   else
      config.FONT.size = newfont.size
   end -- if

   ROOM_NAME_TEXT.colour = newfont.colour

   -- reload new font
   WindowFont (win, FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (win, FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)
   WindowFont (config_win, CONFIG_FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (config_win, CONFIG_FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)

   -- see how high it is
   font_height = WindowFontInfo (win, FONT_ID, 1)  -- height

   draw (current_room)
end -- mouseup_change_font

function mouseup_change_depth (flags, hotspot_id)

   local depth = get_number_from_user ("Choose scan depth (3 to 300 rooms)", "Depth", config.SCAN.depth, 3, 300)

   if not depth then
      return
   end -- if dismissed

   config.SCAN.depth = depth
   draw (current_room)
end -- mouseup_change_depth

function mouseup_change_area_textures (flags, hotspot_id)
   if config.USE_TEXTURES.enabled == true then
      config.USE_TEXTURES.enabled = false
   else
      config.USE_TEXTURES.enabled = true
   end
   draw (current_room)
end -- mouseup_change_area_textures

function mouseup_change_show_id (flags, hotspot_id)
   if config.SHOW_ROOM_ID == true then
      config.SHOW_ROOM_ID = false
   else
      config.SHOW_ROOM_ID = true
   end
   draw (current_room)
end -- mouseup_change_area_textures

function mouseup_change_show_area_exits (flags, hotspot_id)
   if config.SHOW_AREA_EXITS == true then
      config.SHOW_AREA_EXITS = false
   else
      config.SHOW_AREA_EXITS = true
   end
   draw (current_room)
end -- mouseup_change_area_textures

function mouseup_change_blink_pk_title (flags, hotspot_id)
   if config.BLINK_PK_TITLE == true then
      config.BLINK_PK_TITLE = false
   else
      config.BLINK_PK_TITLE = true
   end
   draw (current_room)
end

function zoom_map (flags, hotspot_id)
   if bit.band (flags, 0x100) ~= 0 then
      zoom_out ()
   else
      zoom_in ()
   end -- if
end -- zoom_map

function resize_mouse_down(flags, hotspot_id)
   startx, starty = WindowInfo (win, 17), WindowInfo (win, 18)
end

function resize_release_callback()
   config.WINDOW.width = WindowInfo(win, 3)
   config.WINDOW.height = WindowInfo(win, 4)
   draw(current_room)
end

function resize_move_callback()
   if GetPluginVariable("c293f9e7f04dde889f65cb90", "lock_down_miniwindows") == "1" then
      return
   end
   local posx, posy = WindowInfo (win, 17), WindowInfo (win, 18)

   local width = WindowInfo(win, 3) + posx - startx
   startx = posx
   if (50 > width) then
      width = 50
      startx = windowinfo.window_left + width
   elseif (windowinfo.window_left + width > GetInfo(281)) then
      width = GetInfo(281) - windowinfo.window_left
      startx = GetInfo(281)
   end

   local height = WindowInfo(win, 4) + posy - starty
   starty = posy
   if (50 > height) then
      height = 50
      starty = windowinfo.window_top + height
   elseif (windowinfo.window_top + height > GetInfo(280)) then
      height = GetInfo(280) - windowinfo.window_top
      starty = GetInfo(280)
   end

   WindowResize(win, width, height, BACKGROUND_COLOUR.colour)
   Theme.DrawBorder(win)
   Theme.AddResizeTag(win, 1, nil, nil, "mapper.resize_mouse_down", "mapper.resize_move_callback", "mapper.resize_release_callback")

   WindowShow(win, true)
end
