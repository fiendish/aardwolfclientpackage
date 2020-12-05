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
local timing            -- true to show timing and other info
local show_completed    -- true to show "Speedwalk completed."

-- current room number
local current_room

-- our copy of rooms info
local rooms = {}
local last_visited = {}
local textures = {}
local last_result_list = {}

-- other locals
local HALF_ROOM, connectors, half_connectors, arrows
local plan_to_draw, drawn, drawn_coords
local last_drawn, depth, font_height
local walk_to_room_name
local total_times_drawn = 0
local total_time_taken = 0

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

   SHOW_AREA_EXITS = false
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
   local room = supplied_get_room (uid)
   room = room or { unknown = true }

   -- defaults in case they didn't supply them ...
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

   room.textimage = nil

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

   local config_entries = {"Map Configuration", "Show Room ID", "Show Area Exits", "Font", "Depth", "Area Textures", "Room size"}
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

local function add_another_room (uid, path, x, y)
   local path = path or {}
   return {uid=uid, path=path, x = x, y = y}
end  -- add_another_room

local function draw_room (uid, path, x, y)

   local coords = string.format ("%i,%i", math.floor (x), math.floor (y))

   -- need this for the *current* room !!!
   drawn_coords [coords] = uid

   -- print ("drawing", uid, "at", coords)

   if drawn [uid] then
      return
   end -- done this one

   -- don't draw the same room more than once
   drawn [uid] = { coords = coords, path = path }

   local room = rooms [uid]

   -- not cached - get from caller
   if not room then
      room = get_room (uid)
      rooms [uid] = room
   end -- not in cache


   local left, top, right, bottom = x - HALF_ROOM, y - HALF_ROOM, x + HALF_ROOM, y + HALF_ROOM

   -- forget it if off screen
   if (x < HALF_ROOM) or (y < (title_bottom or font_height)+HALF_ROOM) or
      (x > config.WINDOW.width - HALF_ROOM) or (y > config.WINDOW.height - HALF_ROOM) then
      return
   end -- if

   -- exits

   local texits = {}

   for dir, exit_uid in pairs (room.exits) do
      table.insert (texits, dir)
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
            rooms [exit_uid] = get_room (exit_uid)
         end -- if

         if rooms [exit_uid].unknown then
            linetype = miniwin.pen_dot -- dots
         end -- if

         local next_x = x + exit_info.at [1] * (ROOM_SIZE + DISTANCE_TO_NEXT_ROOM)
         local next_y = y + exit_info.at [2] * (ROOM_SIZE + DISTANCE_TO_NEXT_ROOM)

         local next_coords = string.format ("%i,%i", math.floor (next_x), math.floor (next_y))

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
                  local new_path = copytable.deep (path)
                  table.insert (new_path, { dir = dir, uid = exit_uid })
                  table.insert (rooms_to_be_drawn, add_another_room (exit_uid, new_path, next_x, next_y))
                  drawn_coords [next_coords] = exit_uid
                  plan_to_draw [exit_uid] = next_coords

                  -- if exit room known
                  if not rooms [exit_uid].unknown then
                     local exit_time = last_visited [exit_uid] or 0
                     local this_time = last_visited [uid] or 0
                     local now = os.time ()
                     if exit_time > (now - LAST_VISIT_TIME) and
                        this_time > (now - LAST_VISIT_TIME) then
                        linewidth = 2
                     end -- if
                  end -- if
               end -- if
            end -- if
         end -- if drawn on this spot

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
      end -- if we know what to do with this direction
   end -- for each exit


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

   WindowAddHotspot(win, uid,
      left, top, right, bottom,   -- rectangle
      "",  -- mouseover
      "",  -- cancelmouseover
      "",  -- mousedown
      "",  -- cancelmousedown
      "mapper.mouseup_room",  -- mouseup
      room.hovermessage,
      miniwin.cursor_hand, 0)  -- hand cursor

   WindowScrollwheelHandler (win, uid, "mapper.zoom_map")
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
      return
   end

   -- timing
   local start_time = utils.timer ()

   -- start with initial room
   rooms = { [uid] = get_room (uid) }

   -- lookup current room
   local room = rooms [uid]

   room = room or { name = "<Unknown room>", area = "<Unknown area>" }
   last_visited [uid] = os.time ()

   current_area = room.area

   -- update dimensions and position here because the bigmap might have changed them
   windowinfo.window_left = WindowInfo(win, 1) or windowinfo.window_left
   windowinfo.window_top = WindowInfo(win, 2) or windowinfo.window_top
   config.WINDOW.width = WindowInfo(win, 3) or config.WINDOW.width
   config.WINDOW.height = WindowInfo(win, 4) or config.WINDOW.height

   WindowCreate (win,
      windowinfo.window_left,
      windowinfo.window_top,
      config.WINDOW.width,
      config.WINDOW.height,
      windowinfo.window_mode,   -- top right
      windowinfo.window_flags,
      Theme.PRIMARY_BODY)

   -- Handle background texture.
   if room.textimage ~= nil and config.USE_TEXTURES.enabled == true then
      local iwidth = WindowImageInfo(win,room.textimage,2)
      local iheight= WindowImageInfo(win,room.textimage,3)
      local x = 0
      local y = 0

      while y < config.WINDOW.height do
         x = 0
         while x < config.WINDOW.width do
            WindowDrawImage (win, room.textimage, x, y, 0, 0, 1)  -- straight copy
            x = x + iwidth
         end
         y = y + iheight
      end
   end

   -- for zooming
   WindowAddHotspot(win,
      "zzz_zoom",
      0, 0, 0, 0,
      "", "", "", "", "mapper.MouseUp",
      "",  -- hint
      miniwin.cursor_arrow, 0)

   WindowScrollwheelHandler (win, "zzz_zoom", "mapper.zoom_map")

   -- set up for initial room, in middle
   drawn, drawn_coords, rooms_to_be_drawn, plan_to_draw, area_exits = {}, {}, {}, {}, {}, {}
   depth = 0

   -- insert initial room
   table.insert (rooms_to_be_drawn, add_another_room (uid, {}, config.WINDOW.width / 2, config.WINDOW.height / 2))

   while #rooms_to_be_drawn > 0 and depth < config.SCAN.depth do
      local old_generation = rooms_to_be_drawn
      rooms_to_be_drawn = {}  -- new generation
      for i, part in ipairs (old_generation) do
         draw_room (part.uid, part.path, part.x, part.y)
      end -- for each existing room
      depth = depth + 1
   end -- while all rooms_to_be_drawn

   for area, zone_exit in pairs (area_exits) do
      draw_zone_exit (zone_exit)
   end -- for

   local room_name = room.name
   local name_width = WindowTextWidth (win, FONT_ID, room_name)
   local add_dots = false

   -- truncate name if too long
   local available_width = (config.WINDOW.width - 20 - WindowTextWidth (win, FONT_ID, "*?"))
   while name_width > available_width do
      room_name = room_name:sub(1, -3)
      name_width = WindowTextWidth (win, FONT_ID, room_name .. "...")
      add_dots = true
      if room_name == "" then
         break
      end
   end -- while

   if add_dots then
      room_name = room_name .. "..."
   end -- if

   Theme.DrawBorder(win)

   -- room name
   title_bottom = Theme.DrawTitleBar(win, FONT_ID, room_name)

   if config.SHOW_ROOM_ID then
      Theme.DrawTextBox(win, FONT_ID,
         (config.WINDOW.width - WindowTextWidth (win, FONT_ID, "ID: "..uid)) / 2,   -- left
         title_bottom,    -- top
         "ID: "..uid, false, false)
   end

   -- area name

   local areaname = room.area

   if areaname then
      Theme.DrawTextBox(win, FONT_ID,
         (config.WINDOW.width - WindowTextWidth (win, FONT_ID, areaname)) / 2,   -- left
         config.WINDOW.height - 4 - font_height,    -- top
         areaname:gsub("^%l", string.upper), false, false)
   end -- if area known

   -- configure?

   if draw_configure_box then
      draw_configuration ()
   else
      WindowShow(config_win, false)
      local x = 2
      local y = math.max(2, (title_bottom-font_height)/2)
      local text_width = Theme.DrawTextBox(win, FONT_ID,
         x,   -- left
         y-2,   -- top
         "*", false, false)

      WindowAddHotspot(win, "<configure>",
         x-2, y-4, x+text_width, y + font_height,   -- rectangle
         "",  -- mouseover
         "",  -- cancelmouseover
         "",  -- mousedown
         "",  -- cancelmousedown
         "mapper.mouseup_configure",  -- mouseup
         "Click to configure map",
         miniwin.cursor_plus, 0)
   end -- if

   if type (show_help) == "function" then
      local x = config.WINDOW.width - WindowTextWidth (win, FONT_ID, "?") - 6
      local y = math.max(2, (title_bottom-font_height)/2)
      local text_width = Theme.DrawTextBox(win, FONT_ID,
         x-1,   -- left
         y-2,   -- top
         "?", false, false)

      WindowAddHotspot(win, "<help>",
         x-3, y-4, x+text_width+3, y + font_height,   -- rectangle
         "",  -- mouseover
         "",  -- cancelmouseover
         "",  -- mousedown
         "",  -- cancelmousedown
         "mapper.show_help",  -- mouseup
         "Click for help",
         miniwin.cursor_help, 0)
   end -- if

   Theme.AddResizeTag(win, 1, nil, nil, "mapper.resize_mouse_down", "mapper.resize_move_callback", "mapper.resize_release_callback")

   -- make sure window visible
   WindowShow (win, not window_hidden)

   last_drawn = uid  -- last room number we drew (for zooming)

   local end_time = utils.timer ()

   -- timing stuff
   if timing then
      local count= 0
      for k in pairs (drawn) do
         count = count + 1
      end
      print (string.format ("Time to draw %i rooms = %0.3f seconds, search depth = %i", count, end_time - start_time, depth))

      total_times_drawn = total_times_drawn + 1
      total_time_taken = total_time_taken + end_time - start_time

      print (string.format ("Total times map drawn = %i, average time to draw = %0.3f seconds",
         total_times_drawn,
         total_time_taken / total_times_drawn))
   end -- if

   -- let them move it around
   movewindow.add_drag_handler (win, 0, 0, 0, title_bottom)

   CallPlugin("abc1a0944ae4af7586ce88dc", "BufferedRepaint")
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
   timing = t.timing           -- true for timing info
   show_completed = t.show_completed  -- true to show "Speedwalk completed." message
   show_other_areas = t.show_other_areas  -- true to show other areas
   show_up_down = t.show_up_down        -- true to show up or down
   speedwalk_prefix = t.speedwalk_prefix  -- how to speedwalk (prefix)

   -- force some config defaults if not supplied
   for k, v in pairs (default_config) do
      config[k] = config[k] or v
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
