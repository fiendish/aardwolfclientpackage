-- mapper.lua

--[[

Authors: Original by Nick Gammon. Modified heavily for Aardwolf by Fiendish.

Generic MUD mapper.

Exposed functions:

init (t)            -- call once, supply:
   t.config      -- ie. colours, sizes
   t.get_room    -- info about room (uid)
   t.show_help   -- function that displays some help
   t.room_click  -- function that handles RH click on room (uid, flags)
   t.timing      -- true to show timing
   t.show_other_areas -- true to show non-current areas
   t.show_up_down    -- follow up/down exits

bigger_rooms ()          -- zoom in map view
smaller_rooms ()         -- zoom out map view
mapprint (message)  -- like print, but uses mapper colour
maperror (message)  -- like print, but prints in red
hide ()             -- hides map window (eg. if plugin disabled)
show ()             -- show map window  (eg. if plugin enabled)
save_state ()       -- call to save plugin state (ie. in OnPluginSaveState)
draw (uid)          -- draw map - starting at room 'uid'
start_speedwalk (path)  -- starts speedwalking. path is a table of directions/uids
build_speedwalk (path)  -- builds a client speedwalk string from path
check_we_can_find ()    -- returns true if doing a find is OK right now
find (f, count, walk)      -- generic room finder

Exposed variables:

win                 -- the window (in case you want to put up menus)
VERSION             -- mapper version
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

require "movewindow"
require "copytable"
require "gauge"
require "pairsbykeys"
require "mw"
require "bit"

local FONT_ID     = "fn"  -- internal font identifier
local FONT_ID_UL  = "fnu" -- internal font identifier - underlined
local CONFIG_FONT_ID = "cfn"
local CONFIG_FONT_ID_UL = "cfnu"
local BORDER_TYPES = {"On","Off"}

-- size of room box
local ROOM_SIZE = tonumber(GetVariable("ROOM_SIZE")) or 13
if ROOM_SIZE %2 == 0 then
   ROOM_SIZE = ROOM_SIZE+1
end

local CONTINENT_ROOM_SIZE = tonumber(GetVariable("CONTINENT_ROOM_SIZE")) or 13
if CONTINENT_ROOM_SIZE%2 == 0 then
   CONTINENT_ROOM_SIZE = CONTINENT_ROOM_SIZE+1
end

-- how far away to draw rooms from each other
local DISTANCE_TO_NEXT_ROOM = tonumber(GetVariable("DISTANCE_TO_NEXT_ROOM")) or 8
if DISTANCE_TO_NEXT_ROOM%2 == 1 then
   DISTANCE_TO_NEXT_ROOM = DISTANCE_TO_NEXT_ROOM-1
end

local DISTANCE_TO_NEXT_CONTINENT_ROOM = tonumber(GetVariable("DISTANCE_TO_NEXT_CONTINENT_ROOM")) or 2
if DISTANCE_TO_NEXT_CONTINENT_ROOM%2 == 1 then
   DISTANCE_TO_NEXT_CONTINENT_ROOM = DISTANCE_TO_NEXT_CONTINENT_ROOM-1
end

local ROOM_BORDER_TYPE = tonumber(GetVariable("ROOM_BORDER_TYPE"))
if not BORDER_TYPES[ROOM_BORDER_TYPE] then
   ROOM_BORDER_TYPE = 1
end

local CONTINENT_ROOM_BORDER_TYPE = tonumber(GetVariable("CONTINENT_ROOM_BORDER_TYPE"))
if not BORDER_TYPES[CONTINENT_ROOM_BORDER_TYPE] then
   CONTINENT_ROOM_BORDER_TYPE = 2
end

local STITCH_CONTINENTS = (GetVariable("STITCH_CONTINENTS") == "1")


-- supplied in init
local room_click
local timing            -- true to show timing and other info

-- current room number
local current_room

-- our copy of rooms info
areas = {}
user_terrain_colour = {}
display_rooms = {}
local last_visited = {}
local textures = {}

-- other locals
local plan_to_draw, drawn_uids, drawn_coords
local last_drawn, depth, font_height
local walk_to_room_name
local total_times_drawn = 0
local total_time_taken = 0

default_width = 269
default_height = 335
default_x = 868
default_y = 0

function reset_pos()
   config.WINDOW.width = default_width
   config.WINDOW.height = default_height
   windowinfo.window_left = default_x
   windowinfo.window_top = default_y
   WindowPosition(win, default_x, default_y, 0, 18)
   Repaint() -- hack because WindowPosition doesn't immediately update coordinates
end

local function build_room_info (for_continents)
   require "commas"
   local DISTANCE_TO_NEXT_ROOM = for_continents and DISTANCE_TO_NEXT_CONTINENT_ROOM or DISTANCE_TO_NEXT_ROOM
   local ROOM_SIZE = for_continents and CONTINENT_ROOM_SIZE or ROOM_SIZE

   HALF_ROOM = ROOM_SIZE / 2
   HALF_ROOM_UP   = math.ceil(HALF_ROOM)
   HALF_ROOM_DOWN = math.floor(HALF_ROOM)
   HALF_WAY = DISTANCE_TO_NEXT_ROOM / 2
   HALF_WAY_UP = math.ceil(HALF_WAY)
   HALF_WAY_DOWN = math.floor(HALF_WAY)
   THIRD_WAY = DISTANCE_TO_NEXT_ROOM / 3
   RT_HR_5_SQR_2 = math.sqrt(((HALF_ROOM*.7)*(HALF_ROOM*.7))/2)

   barriers = {
      n = { x1 = -math.floor(HALF_ROOM*.7), y1 = -HALF_ROOM_UP,     x2 = math.ceil(HALF_ROOM*.7),  y2 = -HALF_ROOM_UP},
      s = { x1 = -math.floor(HALF_ROOM*.7), y1 =  HALF_ROOM_UP,     x2 = math.ceil(HALF_ROOM*.7),  y2 =  HALF_ROOM_UP},
      e = { x1 =  HALF_ROOM_UP,     y1 = -math.floor(HALF_ROOM*.7), x2 =  HALF_ROOM_UP,   y2 = math.ceil(HALF_ROOM*.7)},
      w = { x1 = -HALF_ROOM_UP,     y1 = -math.floor(HALF_ROOM*.7), x2 = -HALF_ROOM_UP,   y2 = math.ceil(HALF_ROOM*.7)},
      u = { x1 =  math.ceil(HALF_ROOM-RT_HR_5_SQR_2), y1 = math.floor(-HALF_ROOM-RT_HR_5_SQR_2), x2 =  math.ceil(HALF_ROOM+RT_HR_5_SQR_2), y2 = math.floor(-HALF_ROOM+RT_HR_5_SQR_2)},
      d = { x1 = math.floor(-HALF_ROOM-RT_HR_5_SQR_2), y1 = math.floor(HALF_ROOM-RT_HR_5_SQR_2),  x2 = math.ceil(-HALF_ROOM+RT_HR_5_SQR_2), y2 = math.ceil(HALF_ROOM+RT_HR_5_SQR_2)}
   } -- end barriers

   -- how to draw a line from this room to the next one (relative to the center of the room)
   connectors = {
      n = { x =  0,                               y = -ROOM_SIZE-DISTANCE_TO_NEXT_ROOM, at = { 0, -1 } },
      s = { x =  0,                               y =  ROOM_SIZE+DISTANCE_TO_NEXT_ROOM, at = { 0,  1 } },
      e = { x =  ROOM_SIZE+DISTANCE_TO_NEXT_ROOM, y = 0,                                at = {  1,  0 }},
      w = { x = -ROOM_SIZE-DISTANCE_TO_NEXT_ROOM, y = 0,                                at = { -1,  0 }},
      u = { x =  ROOM_SIZE+DISTANCE_TO_NEXT_ROOM, y = -ROOM_SIZE-DISTANCE_TO_NEXT_ROOM, at = { 1, -1 } },
      d = { x = -ROOM_SIZE-DISTANCE_TO_NEXT_ROOM, y =  ROOM_SIZE+DISTANCE_TO_NEXT_ROOM, at = {-1,  1 } }
   } -- end connectors
   
   -- how to draw a stub line
   stub_connectors = {
      n = { x = 0,                                y = math.floor(-HALF_ROOM-THIRD_WAY), at = { 0, -1 } },
      s = { x = 0,                                y = math.ceil(HALF_ROOM+THIRD_WAY),   at = { 0,  1 } },
      e = { x = math.ceil(HALF_ROOM+THIRD_WAY),   y = 0,                                at = {  1,  0 }},
      w = { x = math.floor(-HALF_ROOM-THIRD_WAY), y = 0,                                at = { -1,  0 }},
      u = { x = math.floor(HALF_ROOM+THIRD_WAY),  y = math.ceil(-HALF_ROOM-THIRD_WAY),  at = { 1, -1 } },
      d = { x = math.ceil(-HALF_ROOM-THIRD_WAY),  y = math.floor(HALF_ROOM+THIRD_WAY),  at = {-1,  1 } }
   }

   -- how to draw one-way arrows (relative to the center of the room)
   arrows = {
      n =  { -round_banker(THIRD_WAY), -(HALF_ROOM + THIRD_WAY/2), --left
               round_banker(THIRD_WAY), -(HALF_ROOM + THIRD_WAY/2), --right
                       0, -round_banker(HALF_ROOM + HALF_WAY + 0.5) }, --top
      
      s =  { -round_banker(THIRD_WAY), (HALF_ROOM + THIRD_WAY/2 + 1), --left
               round_banker(THIRD_WAY), (HALF_ROOM + THIRD_WAY/2 + 1), --right
                       0, round_banker(HALF_ROOM + HALF_WAY + 0.5) }, --bottom
      
      e =  {round_banker(HALF_ROOM + THIRD_WAY/2 + 0.5), - round_banker(THIRD_WAY), -- top
            round_banker(HALF_ROOM + THIRD_WAY/2 + 0.5), round_banker(THIRD_WAY), -- bottom
           HALF_ROOM + HALF_WAY + 0.5, 0 }, -- right
        
      w =  {-round_banker(HALF_ROOM + THIRD_WAY/2 + 0.5), - round_banker(THIRD_WAY), -- top
            -round_banker(HALF_ROOM + THIRD_WAY/2 + 0.5), round_banker(THIRD_WAY), -- bottom
           -(HALF_ROOM + HALF_WAY + 0.5), 0 }, -- left

      u = {math.floor(HALF_ROOM + HALF_WAY - 1), math.ceil(- ROOM_SIZE/2 + 2),  -- bottom
           math.floor(HALF_ROOM + HALF_WAY - 1),        math.ceil(- HALF_ROOM - HALF_WAY + 1), -- righttop
               math.floor(ROOM_SIZE/2 - 2), math.ceil(- HALF_ROOM - HALF_WAY + 1) },  -- left

      d = {- HALF_ROOM - HALF_WAY + 1, ROOM_SIZE/2 - 2, -- top
           - HALF_ROOM - HALF_WAY + 1, HALF_ROOM + HALF_WAY - 1, -- leftbottom
              - ROOM_SIZE/2 + 2, HALF_ROOM + HALF_WAY - 1 } -- right
   } -- end of arrows

   return {
      ROOM_SIZE=ROOM_SIZE,
      DISTANCE_TO_NEXT_ROOM=DISTANCE_TO_NEXT_ROOM,
      HALF_ROOM_UP=HALF_ROOM_UP,
      HALF_ROOM_DOWN=HALF_ROOM_DOWN,
      arrows=arrows,
      stub_connectors=stub_connectors,
      connectors=connectors,
      barriers=barriers
   }
end -- build_room_info

-- assorted colours
BACKGROUND_COLOUR     = { name = "Area Background",  colour =  ColourNameToRGB "#111111"}
ROOM_COLOUR           = { name = "Room",             colour =  ColourNameToRGB "#dcdcdc"}
ROOM_NOTE_COLOUR      = { name = "Room notes",       colour =  ColourNameToRGB "lightgreen"}
OUR_ROOM_COLOUR       = { name = "Our room",         colour =  ColourNameToRGB "#ff1493"}
UNKNOWN_ROOM_COLOUR   = { name = "Unknown room",     colour =  ColourNameToRGB "#8b0000"}
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
EXIT_COLOUR           = ColourNameToRGB "#e0ffff"

-- how many seconds to show "recent visit" lines (default 3 minutes)
LAST_VISIT_TIME = 60 * 3

default_config = {
   FONT = {size = 8, name =  get_preferred_font({"Dina",  "Lucida Console",  "Fixedsys", "Courier",})} ,
   WINDOW = { width = default_width, height = default_height }, -- size of map window
   USE_TEXTURES = { enabled = true }, -- show custom tiling background textures
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

room_display_params = {}

local function get_room_display_params (uid)

   -- look it up
   local ourroom = get_room(uid)

   if not ourroom then
      room_display_params[uid] = {
         unknown = true,
         exits = {},
         name = "< Unexplored Room "..uid.." >",
         hovermessage = "< Unexplored Room "..uid.." >"
      }
   end

   if room_display_params[uid] then
      return room_display_params[uid]
   end

   local room = {name = ourroom.name}

   -- default
   room.borderpen = pen_solid
   room.borderpenwidth = 1
   room.fillcolour = 0xff0000
   room.fillcolor2 = 0
   room.fillbrush = 1 -- no fill
   room.bordercolour = mapper.ROOM_COLOUR.colour

   -- build hover message
   local environmentname = ourroom.terrain
   if tonumber (environmentname) then
      environmentname = environments[tonumber(environmentname)]
   end -- convert to name

   local terrain = ""
   if environmentname and environmentname ~= "" then
      terrain = "\nTerrain: " .. capitalize (environmentname)
   end -- if terrain known

   local info = ""
   if ourroom.info and ourroom.info ~= "" then
      info = "\nInfo: " .. capitalize (ourroom.info)
   end -- if info known

   local notes = ""
   if ourroom.notes and ourroom.notes ~= "" then
      notes = "\nNote: " .. ourroom.notes
   end -- if notes

   local flags = ""
   if ourroom.norecall == 1 then
      flags = flags.."norecall "
   end
   if ourroom.noportal == 1 then
      flags = flags.."noportal"
   end
   if flags ~= "" then
      flags = "\nFlags: "..string.gsub(flags," ",", ")
   end

   local texits = {}
   for dir in pairs (ourroom.exits) do
      table.insert (texits, dir)
   end -- for
   table.sort (texits)

   local areaname = areas[ourroom.area] and areas[ourroom.area].name or "Unknown Area"

   room.hovermessage = string.format (
      "%s\tExits: %s\nRoom: %s\nArea: %s%s%s%s%s",
      ourroom.name,
      table.concat (texits, ", "),
      uid,
      areaname,
      terrain,
      info,
      notes,
      flags
      )

   -- special room fills
   local special_room = false
   if ourroom.info and ourroom.info ~= "" then
      if string.match (ourroom.info, "shop") then
         special_room = true
         room.fillcolour = mapper.SHOP_FILL_COLOUR.colour
         room.fillbrush = 0  -- solid
      elseif string.match (ourroom.info, "healer") then
         special_room = true
         room.fillcolour = mapper.HEALER_FILL_COLOUR.colour
         room.fillbrush = 0  -- solid
      elseif string.match (ourroom.info, "guild") then
         special_room = true
         room.fillcolour = mapper.GUILD_FILL_COLOUR.colour
         room.fillbrush = 0 -- solid
      elseif string.match (ourroom.info, "trainer") then
         special_room = true
         room.fillcolour = mapper.TRAINER_FILL_COLOUR.colour
         room.fillbrush = 0 -- solid
      elseif string.match (ourroom.info, "questor") then
         special_room = true
         room.fillcolour = mapper.QUESTOR_FILL_COLOUR.colour
         room.fillbrush = 0 -- solid
      elseif string.match (ourroom.info, "bank") then
         special_room = true
         room.fillcolour = mapper.BANK_FILL_COLOUR.colour
         room.fillbrush = 0  -- solid
      elseif string.match (ourroom.info, "safe") then
         special_room = true
         room.fillcolour = mapper.SAFEROOM_FILL_COLOUR.colour
         room.fillbrush = 0  -- solid
      end -- if
   end

   -- use terrain colour
   if environmentname and environmentname ~= "" and not special_room then
      local user_color = user_terrain_colour[environmentname]

      if user_color then
         room.fillcolour = user_color.color
         room.fillbrush = user_color.fillbrush
         room.fillcolor2 = user_color.color2
      elseif not requesting_sectors then
         requesting_sectors = true
         Send_GMCP_Packet("request sectors")
      end
   end -- if environmentname

   -- special borders
   if ourroom.info and string.match(ourroom.info, "pk") then
      room.bordercolour = mapper.PK_BORDER_COLOUR.colour
      room.borderpenwidth = 3
   elseif ourroom.notes ~= nil and ourroom.notes ~= "" then
      room.borderpenwidth = 3
      room.bordercolour = ROOM_NOTE_COLOUR.colour
   elseif current_room_is_cont then
      if CONTINENT_ROOM_BORDER_TYPE == 2 or ROOM_BORDER_TYPE == 2 then
         room.borderpen = pen_null
      end
   else
      if areas[ourroom.area] then
         if areas[ourroom.area].color ~= "" then
            room.bordercolour = areas[ourroom.area].color or mapper.ROOM_COLOUR.colour
         end
      end
   end

   room_display_params[uid] = room
   return room

end -- get_room_display_params


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

   local config_entries = {"Map Configuration", "Show Room ID", "Show Area Exits", "Font", 
   "Area Textures", "Area Room Size", "Continent Room Size (without bigmap)", "Area Room Spacing", "Continent Room Spacing (without bigmap)", "Area Room Borders", "Continent Room Borders (without bigmap)", "Stitch Continents (without bigmap)"}
   local width =  max_text_width (config_win, CONFIG_FONT_ID, config_entries , true)
   local GAP = 5

   local x = 0
   local y = 0
   local box_size = font_height - 2
   local rh_size = math.max (box_size, max_text_width (config_win, CONFIG_FONT_ID,
      {config.FONT.name .. " " .. config.FONT.size,
      ((config.USE_TEXTURES.enabled and "On") or "Off"),
      "- +"},
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
      pen_solid, 1)
   WindowLine (config_win,
      x + box_size - 4,
      y + 4,
      x + 2,
      y - 2 + box_size,
      0x808080,
      pen_solid, 1)

   -- close configuration hotspot
   WindowAddHotspot(config_win, "$<close_configure>",
      x,
      y + 1,
      x + box_size,
      y + 1 + box_size,    -- rectangle
      "", "", "", "", "mapper.mouseup_close_configure",  -- mouseup
      "Click to close",
      miniwin.cursor_plus, 0)  -- hand cursor

   y = y + font_height

   -- font
   WindowText(config_win, CONFIG_FONT_ID, "Font", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL,  config.FONT.name .. " " .. config.FONT.size, x + width + GAP, y, 0, 0, 0x808080)
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
   WindowText(config_win, CONFIG_FONT_ID, "Area Room Size", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID, "("..tostring (ROOM_SIZE)..")", x + WindowTextWidth(config_win, CONFIG_FONT_ID, "Area Room size "), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "-", width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "+", width + rh_size / 2 + box_size + GAP, y, 0, 0, 0x808080)
   WindowAddHotspot(config_win,
      "$<room_size_down>",
      width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y,
      width + rh_size / 2 + box_size/2 + WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.smaller_rooms",  -- mouseup
      "Click to emsmallen area rooms",
      miniwin.cursor_hand, 0)  -- hand cursor
   WindowAddHotspot(config_win,
      "$<room_size_up>",
      width + rh_size / 2 + box_size + GAP,
      y,
      width + rh_size / 2 + box_size + GAP + WindowTextWidth(config_win,CONFIG_FONT_ID,"+"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.bigger_rooms",  -- mouseup
      "Click to embiggen area rooms",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height

   -- room spacing
   WindowText(config_win, CONFIG_FONT_ID, "Area Room Spacing", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID, "("..tostring (DISTANCE_TO_NEXT_ROOM)..")", x + WindowTextWidth(config_win, CONFIG_FONT_ID, "Area Room Spacing "), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "-", width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "+", width + rh_size / 2 + box_size + GAP, y, 0, 0, 0x808080)
   WindowAddHotspot(config_win,
      "$<room_spacing_down>",
      width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y,
      width + rh_size / 2 + box_size/2 + WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.denser",  -- mouseup
      "Click to compact area rooms",
      miniwin.cursor_hand, 0)  -- hand cursor
   WindowAddHotspot(config_win,
      "$<room_spacing_up>",
      width + rh_size / 2 + box_size + GAP,
      y,
      width + rh_size / 2 + box_size + GAP + WindowTextWidth(config_win,CONFIG_FONT_ID,"+"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.sparser",  -- mouseup
      "Click to spread area rooms",
      miniwin.cursor_hand, 0)  -- hand cursor

   y = y + font_height

   -- room border type
   WindowText(config_win, CONFIG_FONT_ID, "Area Room Borders", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, BORDER_TYPES[ROOM_BORDER_TYPE], width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, BORDER_TYPES[ROOM_BORDER_TYPE])/2, y, 0, 0, 0x808080)

   -- show area exits hotspot
   WindowAddHotspot(config_win,
      "$<border_type>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_border_type",  -- mouseup
      "Click to change area room border type",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height

   WindowText(config_win, CONFIG_FONT_ID, "Continent Room Size (without bigmap)", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID, "("..tostring (CONTINENT_ROOM_SIZE)..")", x + WindowTextWidth(config_win, CONFIG_FONT_ID, "Continent Room size (without bigmap) "), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "-", width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "+", width + rh_size / 2 + box_size + GAP, y, 0, 0, 0x808080)
   WindowAddHotspot(config_win,
      "$<continent_room_size_down>",
      width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y,
      width + rh_size / 2 + box_size/2 + WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.smaller_rooms",  -- mouseup
      "Click to emsmallen continent rooms",
      miniwin.cursor_hand, 0)  -- hand cursor
   WindowAddHotspot(config_win,
      "$<continent_room_size_up>",
      width + rh_size / 2 + box_size + GAP,
      y,
      width + rh_size / 2 + box_size + GAP + WindowTextWidth(config_win,CONFIG_FONT_ID,"+"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.bigger_rooms",  -- mouseup
      "Click to embiggen continent rooms",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height

   -- continent room spacing
   WindowText(config_win, CONFIG_FONT_ID, "Continent Room Spacing (without bigmap)", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID, "("..tostring (DISTANCE_TO_NEXT_CONTINENT_ROOM)..")", x + WindowTextWidth(config_win, CONFIG_FONT_ID, "Continent Room spacing (without bigmap) "), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "-", width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"), y, 0, 0, 0x808080)
   WindowText(config_win, CONFIG_FONT_ID_UL, "+", width + rh_size / 2 + box_size + GAP, y, 0, 0, 0x808080)
   WindowAddHotspot(config_win,
      "$<continent_room_spacing_down>",
      width + rh_size / 2 + box_size/2 - WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y,
      width + rh_size / 2 + box_size/2 + WindowTextWidth(config_win,CONFIG_FONT_ID,"-"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.denser",  -- mouseup
      "Click to compact continent rooms",
      miniwin.cursor_hand, 0)  -- hand cursor
   WindowAddHotspot(config_win,
      "$<continent_room_spacing_up>",
      width + rh_size / 2 + box_size + GAP,
      y,
      width + rh_size / 2 + box_size + GAP + WindowTextWidth(config_win,CONFIG_FONT_ID,"+"),
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.sparser",  -- mouseup
      "Click to spread continent rooms",
      miniwin.cursor_hand, 0)  -- hand cursor
   y = y + font_height

   -- room border type
   WindowText(config_win, CONFIG_FONT_ID, "Continent Room Borders (without bigmap)", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, BORDER_TYPES[CONTINENT_ROOM_BORDER_TYPE], width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, BORDER_TYPES[CONTINENT_ROOM_BORDER_TYPE])/2, y, 0, 0, 0x808080)

   -- show area exits hotspot
   WindowAddHotspot(config_win,
      "$<continent_border_type>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_change_border_type",  -- mouseup
      "Click to change continent room border type",
      miniwin.cursor_hand, 0)  -- hand cursor

   y = y + font_height

   -- room border type
   WindowText(config_win, CONFIG_FONT_ID, "Stitch Continents (without bigmap)", x, y, 0, 0, 0x000000)
   WindowText(config_win, CONFIG_FONT_ID_UL, STITCH_CONTINENTS and "On" or "Off", width + rh_size / 2 + box_size - WindowTextWidth(config_win, CONFIG_FONT_ID_UL, STITCH_CONTINENTS and "On" or "Off")/2, y, 0, 0, 0x808080)

   -- show area exits hotspot
   WindowAddHotspot(config_win,
      "$<stitch_continents>",
      x + GAP,
      y,
      x + frame_width,
      y + font_height,   -- rectangle
      "", "", "", "", "mapper.mouseup_stitch_continents",  -- mouseup
      "Click to toggle stitching continents together",
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
   d = "u"
}  -- end of inverse_direction

whitebacked_textures = {
   snow=true,
   icemount=true,
   icehills=true,
   ice=true,
   beach=true
}

local function xy_to_coord(x,y)
   return tostring(math.floor (x) + (math.floor (y) * config.WINDOW.width))
end

local function draw_room (uid, x, y, metrics)
   local coords = xy_to_coord(x,y)
   if drawn_uids[uid] then return end

   drawn_coords[xy_to_coord(x,y)] = uid
   drawn_uids[uid] = true

   -- forget it if off screen
   if x < metrics.HALF_ROOM_UP or y <= metrics.HALF_ROOM_UP + font_height or
      x > config.WINDOW.width - metrics.HALF_ROOM_UP or y > config.WINDOW.height - metrics.HALF_ROOM_UP then
      return
   end -- if
   
   local left, top, right, bottom = x - metrics.HALF_ROOM_DOWN, y - metrics.HALF_ROOM_DOWN, x + metrics.HALF_ROOM_UP, y + metrics.HALF_ROOM_UP

   local room_params = get_room_display_params(uid)
   local room = rooms[uid]

   if room then
      local NEXT_ROOM = metrics.ROOM_SIZE + metrics.DISTANCE_TO_NEXT_ROOM
      if metrics.DISTANCE_TO_NEXT_ROOM < 4 then
         for dir,exit_uid in pairs(room.exits) do
            local exit_info = metrics.connectors[dir]
            if exit_info then -- want to draw exits in this direction
               local exit_room = get_room(exit_uid)
               if exit_room then
                  if config.SHOW_AREA_EXITS and room.area ~= exit_room.area then
                     table.insert(area_exits, {x=x, y=y, dir=dir})
                  end
               else
                  linetype = pen_dot
               end
               
               local next_x = x + exit_info.at[1] * NEXT_ROOM
               local next_y = y + exit_info.at[2] * NEXT_ROOM
               local next_coords = xy_to_coord(next_x, next_y)

               -- choose between a real exit or just a stub
               if (drawn_coords[next_coords] and drawn_coords[next_coords] ~= exit_uid) or  -- another room already there
                  ((not show_other_areas and exit_room and exit_room.area ~= current_area) and not (STITCH_CONTINENTS and continent_zones[current_area] and continent_zones[exit_room.area])) or -- room in another area
                  (not show_up_down and (dir == "u" or dir == "d")) then -- room is above/below
                  --nop
               elseif exit_uid == uid then
                  -- if the exit leads back to this room, only draw stub
                  --nop
               elseif not drawn_uids[exit_uid] and not drawn_coords[next_coords] then
                  -- queue for next level of rooms
                  table.insert(rooms_to_draw_next, {exit_uid, next_x, next_y})
                  drawn_coords[next_coords] = exit_uid
               end
            end
         end
      else
         -- look at exits first
         for dir,exit_uid in pairs(room.exits) do
            local exit_info = metrics.connectors[dir]
            if exit_info then -- want to draw exits in this direction
               local locked_exit = not (room.exit_locks == nil or room.exit_locks[dir] == nil or room.exit_locks[dir] == "0")
               local exit_line_colour = (locked_exit and 0x0000FF) or EXIT_COLOUR

               local linewidth = (locked_exit and 3) or 1
               local linetype = pen_solid

               local exit_room = get_room(exit_uid)

               if exit_room then
                  if config.SHOW_AREA_EXITS and room.area ~= exit_room.area then -- zone exits get drawn later
                     table.insert(area_exits, {x=x, y=y, dir=dir})
                  end
                  
                  local now = os.time()
                  if (last_visited[exit_uid] or 0) > (now - LAST_VISIT_TIME) and
                     (last_visited[uid] or 0) > (now - LAST_VISIT_TIME) then
                     if (dir == "u" or dir == "d") then linewidth = 2 else linewidth = 3 end
                     if not locked_exit then
                        exit_line_colour = ColourNameToRGB("orange")
                     end
                  end -- if
               else
                  linetype = pen_dot
               end

               local next_x = x + exit_info.at[1] * NEXT_ROOM
               local next_y = y + exit_info.at[2] * NEXT_ROOM
               local next_coords = xy_to_coord(next_x, next_y)
               
               -- choose between a real exit or just a stub
               if (drawn_coords[next_coords] and drawn_coords[next_coords] ~= exit_uid) or  -- another room already there
                  ((not show_other_areas and exit_room and exit_room.area ~= current_area) and not (STITCH_CONTINENTS and continent_zones[current_area] and continent_zones[exit_room.area])) or -- room in another area
                  (not show_up_down and (dir == "u" or dir == "d")) then -- room is above/below
                  exit_info = metrics.stub_connectors[dir]
               elseif exit_uid == uid then
                  -- if the exit leads back to this room, only draw stub
                  exit_info = metrics.stub_connectors[dir]
                  linetype = pen_dash
               elseif not drawn_uids[exit_uid] and not drawn_coords[next_coords] then
                  -- queue for next level of rooms
                  table.insert(rooms_to_draw_next, {exit_uid, next_x, next_y})
                  drawn_coords[next_coords] = exit_uid
               end

               if not drawn_uids[exit_uid] then
                  WindowLine (win, x, y, x + exit_info.x, y + exit_info.y, exit_line_colour, linetype, linewidth)
               end

               -- one-way exit arrow
               if exit_room and exit_room.exits[inverse_direction[dir]] ~= uid then
                  local arrow = metrics.arrows[dir]
                  -- draw arrow
                  if daredevil_mode then
                     WindowPolygon(win, 
                        string.format("%i,%i,%i,%i,%i,%i",
                           x + arrow[1],
                           y + arrow[2],
                           x + arrow[3],
                           y + arrow[4],
                           x + arrow[5],
                           y + arrow[6]),
                        exit_line_colour, 
                        pen_dot, 
                        1,
                        -1, 
                        miniwin.brush_null,
                        true, 
                        true)
                  else
                     WindowPolygon(win, 
                        string.format("%i,%i,%i,%i,%i,%i",
                           x + arrow[1],
                           y + arrow[2],
                           x + arrow[3],
                           y + arrow[4],
                           x + arrow[5],
                           y + arrow[6]),
                        exit_line_colour, 
                        pen_solid, 
                        1,
                        exit_line_colour, 
                        miniwin.brush_solid,
                        true, 
                        true)
                  end
               end -- one way
            end -- if we know what to do with this direction
         end -- for each exit
      end

      if daredevil_mode then
         WindowCircleOp (win, miniwin.circle_rectangle, left, top, right, bottom,
            EXIT_COLOUR, pen_dot, 1,  --  dotted single pixel pen
            -1, miniwin.brush_null)  -- opaque, no brush
      else  
         -- room fill
         WindowCircleOp (win, miniwin.circle_rectangle, left, top, right+1, bottom+1,
            room_params.fillcolor2, pen_null, 0,  -- no pen
            room_params.fillcolour, room_params.fillbrush)  -- brush
         
         local borderpen = room_params.borderpen
         local borderpenwidth = room_params.borderpenwidth
         local bordercolour = room_params.bordercolour

         if uid == current_room then
            bordercolour = mapper.OUR_ROOM_COLOUR.colour
            borderpenwidth = 3
            borderpen = pen_solid
         elseif room.area ~= current_area then
            bordercolour = mapper.DIFFERENT_AREA_COLOUR.colour
            borderpen = pen_null
         end

         if borderpen ~= pen_null then
            -- room border
            WindowCircleOp (win, miniwin.circle_rectangle, left, top, right, bottom,
                  bordercolour, borderpen, borderpenwidth,  -- pen
                  -1, miniwin.brush_null)  -- opaque, no brush
         end
      end
   else
      WindowCircleOp (win, miniwin.circle_rectangle, left, top, right, bottom,
         UNKNOWN_ROOM_COLOUR.colour, pen_dot, 1,  --  dotted single pixel pen
         -1, miniwin.brush_null)  -- opaque, no brush
   end

   WindowAddHotspot(win, uid,
      left, top, right, bottom,   -- rectangle
      "",  -- mouseover
      "",  -- cancelmouseover
      "",  -- mousedown
      "",  -- cancelmousedown
      "mapper.mouseup_room",  -- mouseup
      daredevil_mode and "" or room_params.hovermessage,
      miniwin.cursor_hand, 0)  -- hand cursor

   WindowScrollwheelHandler (win, uid, "mapper.zoom_map")
end -- draw_room

local function draw_zone_exit (exit, barriers)
   local x, y, def = exit.x, exit.y, barriers[exit.dir]
   local x1, y1, x2, y2 = x + def.x1, y + def.y1, x + def.x2, y + def.y2
   WindowLine (win, x1, y1, x2, y2, ColourNameToRGB("yellow"), pen_solid, 5)
   WindowLine (win, x1, y1, x2, y2, ColourNameToRGB("green"), pen_solid, 1)
end --  draw_zone_exit

pen_solid = miniwin.pen_solid + 0x0200
pen_dot = miniwin.pen_dot + 0x0200
pen_dash = miniwin.pen_dash + 0x0200
pen_null = miniwin.pen_null

----------------------------------------------------------------------------------
--  EXPOSED FUNCTIONS
----------------------------------------------------------------------------------

function verify_search_target(target_uid, command_line)
   local wanted = string.match(target_uid, "^(nomap_.+)$") or tonumber(target_uid)
  
   if not wanted or (type(wanted) == "number" and  wanted < 0) then
      mapprint ("The mapper "..string.match(command_line, "^mapper (%a*)").." command expects a valid room id as input. Got: "..target_uid)
      return nil
   end
  
   wanted = tostring(wanted)

   if not get_room(wanted) then
      mapprint("The room you requested ["..target_uid.."] doesn't appear to exist.")
      return nil
   end

   return wanted
end

-- can we find another room right now?
function check_we_can_find()
   if not current_room then
      mapprint ("I don't know where you are right now - try: LOOK")
      check_connected ()
      return false
   end

   if current_speedwalk then
      mapprint ("The mapper has detected a mapper goto initiated inside another goto. That isn't allowed. Blocking the inner goto.")
      return false
   end -- if

   return true
end -- check_we_can_find


dont_draw = false
function halt_drawing(halt)
   dont_draw = halt
end

function draw_fullarea()
   draw(current_room, true)
end

function draw_area(uid, fullarea)
   -- set up for initial room, in middle
   drawn_uids, drawn_coords, rooms_to_draw_next, area_exits = {}, {}, {}, {}, {}
   depth = 0

   local metrics
   if current_room_is_cont then
      metrics = CONTINENTS_ROOM_INFO
   else
      metrics = AREA_ROOM_INFO
   end

   -- insert initial room
   local draw_elapsed = utils.timer()
   table.insert(rooms_to_draw_next, {uid, config.WINDOW.width / 2, config.WINDOW.height / 2})
   while #rooms_to_draw_next > 0 do
      local this_draw_level = rooms_to_draw_next
      rooms_to_draw_next = {}  -- new generation
      for i, room in ipairs(this_draw_level) do
         draw_room(room[1], room[2], room[3], metrics)
      end -- for each existing room
      depth = depth + 1
      if (not fullarea and utils.timer()-draw_elapsed > 0.08) then
         if not running then
            AddTimer("draw_fullarea", 0, 0, 0.1, "mapper.draw_fullarea()", timer_flag.Enabled + timer_flag.OneShot + timer_flag.Replace + timer_flag.Temporary, "")
            SetTimerOption("draw_fullarea", "send_to", sendto.script)
         end
         break
      end
   end -- while all rooms_to_draw_next

   local barriers = metrics.barriers
   for i, zone_exit in ipairs(area_exits) do
      draw_zone_exit(zone_exit, barriers)
   end -- for
end

-- draw our map starting at room: uid
function draw (uid, fullarea_passthrough)
   if not uid then
      draw_credits()
      return
   end -- if

   current_room = uid -- remember where we are

   if hidden or dont_draw then -- bigmap plugin merge blocks room drawing
      return
   end

   -- timing
   local start_time = utils.timer ()

   -- lookup current room
   local room_params = get_room_display_params(uid)
   local room = get_room(uid)

   last_visited[uid] = os.time ()

   if not room then
      return
   end

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
      BACKGROUND_COLOUR.colour)

   if config.USE_TEXTURES.enabled == true and not daredevil_mode then
      -- Load background texture
      local textimage = nil
      local texture = nil
      if areas[room.area] then
         texture = areas[room.area].texture
      end
      if texture == nil or texture == "" then texture = "test5.png" end

      if textures[texture] then
         textimage = textures[texture]
      else
         if textures[texture] ~= false then
            local dir = GetInfo(66)
            local imgpath = dir .. "worlds\\plugins\\images\\" ..texture
            if WindowLoadImage(win, texture, imgpath) ~= 0 then
               textures[texture] = false  -- file not found
            else
               textures[texture] = texture -- cache image
               textimage = texture
            end
         end
      end

      -- Draw background texture.
      if textimage ~= nil then
         local iwidth = WindowImageInfo(win,textimage,2)
         local iheight= WindowImageInfo(win,textimage,3)
         local x = 0
         local y = 0

         while y < config.WINDOW.height do
            x = 0
            while x < config.WINDOW.width do
               WindowDrawImage(win, textimage, x, y, 0, 0, 1)  -- straight copy
               x = x + iwidth
            end
            y = y + iheight
         end
      end
   end

   -- let them move it around
   movewindow.add_drag_handler(win, 0, 0, 0, font_height)

   -- for zooming
   WindowAddHotspot(win,
      "zzz_zoom",
      0, 0, 0, 0,
      "", "", "", "", "mapper.MouseUp",
      "",  -- hint
      miniwin.cursor_arrow,
      0)
   WindowScrollwheelHandler(win, "zzz_zoom", "mapper.zoom_map")

   draw_area(uid, fullarea_passthrough)

   local room_name = room.name
   local name_width = WindowTextWidth(win, FONT_ID, room_name)
   local add_dots = false

   -- truncate name if too long
   while name_width + 19 + WindowTextWidth(win, FONT_ID, "*?") > config.WINDOW.width do
      -- get rid of last letter until it fits
      room_name = room_name:sub(1, -2)
      if room_name == "" then
         break
      end
      name_width = WindowTextWidth(win, FONT_ID, room_name.."...")
      add_dots = true
   end -- while

   if add_dots then
      room_name = room_name.."..."
   end -- if

   -- room name

   local name_box_width = draw_text_box (win, FONT_ID,
      (config.WINDOW.width - WindowTextWidth (win, FONT_ID, room_name)) / 2,   -- left
      2,    -- top
      room_name, false,             -- what to draw, utf8
      ROOM_NAME_TEXT.colour,   -- text colour
      ROOM_NAME_FILL.colour,   -- fill colour
      ROOM_NAME_BORDER.colour)     -- border colour
      
   if config.SHOW_ROOM_ID then
      draw_text_box (win, FONT_ID,
         (config.WINDOW.width - WindowTextWidth (win, FONT_ID, "ID: "..uid)) / 2,   -- left
         2+font_height+1,    -- top
         "ID: "..uid, false,             -- what to draw, utf8
         ROOM_NAME_TEXT.colour,   -- text colour
         ROOM_NAME_FILL.colour,   -- fill colour
         ROOM_NAME_BORDER.colour)     -- border colour
   end

   -- area name

   local areaname = room.area

   if areaname then
      draw_text_box (win, FONT_ID,
         (config.WINDOW.width - WindowTextWidth (win, FONT_ID, areaname)) / 2,   -- left
         config.WINDOW.height - 3 - font_height,    -- top
         string.gsub(areas[areaname] and areas[areaname].name or areaname, "^%l", string.upper), false,
         AREA_NAME_TEXT.colour,   -- text colour
         AREA_NAME_FILL.colour,   -- fill colour
         AREA_NAME_BORDER.colour) -- border colour
   end -- if area known

   -- configure?

   if draw_configure_box then
      draw_configuration ()
   else
      WindowShow(config_win, false)
      local x = 2
      local y = 2
      local text_width = draw_text_box (win, FONT_ID,
         x+3,   -- left
         y,   -- top
         "*", false,              -- what to draw, utf8
         AREA_NAME_TEXT.colour,   -- text colour
         AREA_NAME_FILL.colour,   -- fill colour
         AREA_NAME_BORDER.colour) -- border colour

      WindowAddHotspot(win, "$<configure>",
         0, 0, x+text_width+6, y + font_height,   -- rectangle
         "",  -- mouseover
         "",  -- cancelmouseover
         "",  -- mousedown
         "",  -- cancelmousedown
         "mapper.mouseup_configure",  -- mouseup
         "Click to configure map",
         miniwin.cursor_plus, 0)  -- hand cursor
   end -- if

   if type (show_help) == "function" then
      local x = config.WINDOW.width - WindowTextWidth (win, FONT_ID, "?") - 5
      local y = 2
      local text_width = draw_text_box (win, FONT_ID,
         x,   -- left
         y,   -- top
         "?", false,              -- what to draw, utf8
         AREA_NAME_TEXT.colour,   -- text colour
         AREA_NAME_FILL.colour,   -- fill colour
         AREA_NAME_BORDER.colour) -- border colour

      WindowAddHotspot(win, " $<help>",
         x-3, y, x+text_width+3, y + font_height,   -- rectangle
         "",  -- mouseover
         "",  -- cancelmouseover
         "",  -- mousedown
         "",  -- cancelmousedown
         "mapper.show_help",  -- mouseup
         "Click for help",
         miniwin.cursor_help, 0)  -- hand cursor
   end -- if

   draw_edge()

   -- make sure window visible
   WindowShow (win, not window_hidden)

   last_drawn = uid  -- last room number we drew (for zooming)

   local end_time = utils.timer ()

   -- timing stuff
   if timing then
      local count= 0
      for k in pairs (drawn_uids) do
         count = count + 1
      end
      print (string.format ("Time to draw %i rooms = %0.3f seconds, search depth = %i", count, end_time - start_time, depth))

      total_times_drawn = total_times_drawn + 1
      total_time_taken = total_time_taken + end_time - start_time

      print (string.format ("Total times map drawn = %i, average time to draw = %0.3f seconds",
         total_times_drawn,
         total_time_taken / total_times_drawn))
   end -- if
   BroadcastPlugin (999, "repaint")
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
   config = t.config
   assert (type (config) == "table", "No 'config' table supplied to mapper.")

   show_help = t.show_help     -- "help" function
   room_click = t.room_click   -- RH mouse-click function
   timing = t.timing           -- true for timing info
   show_other_areas = t.show_other_areas  -- true to show other areas
   show_up_down = t.show_up_down        -- true to show up or down

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
   AREA_ROOM_INFO = build_room_info()
   CONTINENTS_ROOM_INFO = build_room_info(true)

   WindowCreate (win,
      windowinfo.window_left,
      windowinfo.window_top,
      config.WINDOW.width,
      config.WINDOW.height,
      windowinfo.window_mode,   -- top right
      windowinfo.window_flags,
      BACKGROUND_COLOUR.colour)

   CallPlugin("462b665ecb569efbf261422f", "registerMiniwindow", win) -- fail silently

   -- let them move it around
   movewindow.add_drag_handler (win, 0, 0, 0, 0)

   draw_credits()

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

ROOM_SCALE_LIMITS = {
   DISTANCE_TO_NEXT_ROOM_MIN = -1, 
   DISTANCE_TO_NEXT_ROOM_MAX = 40,
   ROOM_SIZE_MIN = 4, 
   ROOM_SIZE_MAX = 40,
   SIZE_STEP = 2,
   DISTANCE_STEP = 2
}

function sparser (flags, id)
   if last_drawn then
      local for_continents = id:find("continent")
      local step = ROOM_SCALE_LIMITS.DISTANCE_STEP
      if (for_continents and DISTANCE_TO_NEXT_CONTINENT_ROOM or DISTANCE_TO_NEXT_ROOM) < ROOM_SCALE_LIMITS.DISTANCE_TO_NEXT_ROOM_MAX then
         if for_continents then
            if DISTANCE_TO_NEXT_CONTINENT_ROOM < 2 then
               step = 1
            end
            DISTANCE_TO_NEXT_CONTINENT_ROOM = DISTANCE_TO_NEXT_CONTINENT_ROOM + step
         else
            if DISTANCE_TO_NEXT_ROOM < 2 then
               step = 1
            end
            DISTANCE_TO_NEXT_ROOM = DISTANCE_TO_NEXT_ROOM + step
         end
         AREA_ROOM_INFO = build_room_info()
         CONTINENTS_ROOM_INFO = build_room_info(true)
         draw (last_drawn)
         OnPluginSaveState()
         return true
      end -- if
   end
   return false
end

function denser (flags, id)
   if last_drawn then
      local for_continents = id:find("continent")
      local step = ROOM_SCALE_LIMITS.DISTANCE_STEP
      if (for_continents and DISTANCE_TO_NEXT_CONTINENT_ROOM or DISTANCE_TO_NEXT_ROOM) > ROOM_SCALE_LIMITS.DISTANCE_TO_NEXT_ROOM_MIN then
         if for_continents then
            if DISTANCE_TO_NEXT_CONTINENT_ROOM <= 2 then
               step = 1
            end
            DISTANCE_TO_NEXT_CONTINENT_ROOM = DISTANCE_TO_NEXT_CONTINENT_ROOM - step
         else
            if DISTANCE_TO_NEXT_ROOM <= 2 then
               step = 1
            end
            DISTANCE_TO_NEXT_ROOM = DISTANCE_TO_NEXT_ROOM - step
         end
         AREA_ROOM_INFO = build_room_info()
         CONTINENTS_ROOM_INFO = build_room_info(true)
         draw (last_drawn)
         OnPluginSaveState()
         return true
      end -- if
   end
   return false
end

function bigger_rooms (flags, id)
   if last_drawn then
      local for_continents = id:find("continent")
      if (for_continents and CONTINENT_ROOM_SIZE or ROOM_SIZE) < ROOM_SCALE_LIMITS.ROOM_SIZE_MAX then
         if for_continents then
            CONTINENT_ROOM_SIZE = CONTINENT_ROOM_SIZE + ROOM_SCALE_LIMITS.SIZE_STEP
         else
            ROOM_SIZE = ROOM_SIZE + ROOM_SCALE_LIMITS.SIZE_STEP
         end
         AREA_ROOM_INFO = build_room_info()
         CONTINENTS_ROOM_INFO = build_room_info(true)
         draw(last_drawn)
         OnPluginSaveState()
         return true
      end -- if
   end
   return false
end -- bigger_rooms


function smaller_rooms (flags, id)
   if last_drawn then
      local for_continents = id:find("continent")
      if (for_continents and CONTINENT_ROOM_SIZE or ROOM_SIZE)  > ROOM_SCALE_LIMITS.ROOM_SIZE_MIN then
         if for_continents then
            CONTINENT_ROOM_SIZE = CONTINENT_ROOM_SIZE - ROOM_SCALE_LIMITS.SIZE_STEP
         else
            ROOM_SIZE = ROOM_SIZE - ROOM_SCALE_LIMITS.SIZE_STEP
         end
         AREA_ROOM_INFO = build_room_info()
         CONTINENTS_ROOM_INFO = build_room_info(true)
         draw (last_drawn)
         OnPluginSaveState()
         return true
      end
   end -- if
   return false
end -- smaller_rooms

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
   hidden = false
   WindowShow(win, true)
   draw(current_room) -- force
end -- show

function hide()
   hidden = true
   WindowShow(win, false)
end -- hide

function save_state ()
   SetVariable("ROOM_SIZE", ROOM_SIZE)
   SetVariable("CONTINENT_ROOM_SIZE", CONTINENT_ROOM_SIZE)
   SetVariable("DISTANCE_TO_NEXT_ROOM", DISTANCE_TO_NEXT_ROOM)
   SetVariable("DISTANCE_TO_NEXT_CONTINENT_ROOM", DISTANCE_TO_NEXT_CONTINENT_ROOM)
   SetVariable("ROOM_BORDER_TYPE", ROOM_BORDER_TYPE)
   SetVariable("CONTINENT_ROOM_BORDER_TYPE", CONTINENT_ROOM_BORDER_TYPE)
   SetVariable("STITCH_CONTINENTS", STITCH_CONTINENTS and "1" or "0")
   if WindowInfo(win,1) and WindowInfo(win,5) then
      movewindow.save_state (win)
   end
   room_display_params = {}
end -- save_state

function addRunHyperlink(destination_uid, msg_override, bubble_addition, no_renumber, foreground_color, background_color)
   table.insert(last_result_list, destination_uid)
   local dest = get_room(destination_uid)
   local destination_name = dest.name
   if msg_override then
      Hyperlink ("!!" .. GetPluginID () .. ":mapper.hyperlinkGoto(" .. destination_uid .. ")",
      msg_override..(no_renumber and "" or "["..#last_result_list.."]"),
      "Click here to run to room ("..destination_uid..") \""..destination_name.."\""..(bubble_addition or ""),
      foreground_color or "", background_color or "", false)
   else
      Hyperlink ("!!" .. GetPluginID () .. ":mapper.hyperlinkGoto(" .. destination_uid .. ")",
      (no_renumber and "" or "["..#last_result_list.."] ")..destination_name.." ("..destination_uid..") ("..dest.area..")" ,
      "Click here to run to room ("..destination_uid..") \""..destination_name.."\""..(bubble_addition or ""),
      foreground_color or "", background_color or "", false)
   end
end

function hyperlinkGoto(uid)
   mapper.goto(uid)
   for i,v in ipairs(last_result_list) do
      if uid == v then
         next_result_index = i
         break
      end
   end
end

-- original findpath function idea contributed by Spartacus. we don't use that one anymore.
function findpath(src, dst, noportals, norecalls)
   local findpath_elapsed = utils.timer()

   local used_recalls = norecalls
   local used_portals = noportals

   local portals = {}
   local recalls = {}
   if not norecalls or not noportals then
      for row in dbnrowsWRAPPER("select rooms.area,rooms.name,exits.touid,exits.fromuid,exits.dir,exits.level from exits left outer join rooms on rooms.uid=exits.touid where exits.fromuid in ('*','**')") do
         if row.level <= mylevel+(mytier*10) then
            if row.fromuid == "**" then
               table.insert(recalls, {row.dir, row.touid})
            else
               table.insert(portals, {row.dir, row.touid})
            end
         end -- if row.level
      end -- for row (portals query)
   end

   function search_for_dst(dst, su, rooms_to_search_next, searched)
      if not searched[su[3]] then
         searched[su[3]] = su
         if su[3] == dst then
            return true
         end
         local room = get_room(su[3])
         if room then
            -- always follow cexits first
            for dir,next_room in pairs(room.exits) do
               if not directions[dir] then
                  table.insert(rooms_to_search_next, {su[3], dir, next_room})
               end
            end
            -- then regular exits
            for dir,next_room in pairs(room.exits) do
               if directions[dir] then
                  table.insert(rooms_to_search_next, {su[3], dir, next_room})
               end
            end
            -- then portals
            if not used_portals and room.noportal ~= 1 then
               used_portals = true
               for i,p in ipairs(portals) do
                  table.insert(rooms_to_search_next, {su[3], p[1], p[2]})
               end
            -- then recalls
            elseif not used_recalls and room.norecall ~= 1 then
               used_recalls = true
               for i,r in ipairs(recalls) do
                  table.insert(rooms_to_search_next, {su[3], r[1], r[2]})
               end
            end
         end
      end
   end
   
   local rooms_to_search_next = {}
   local searched = {}
   if not search_for_dst(dst, {nil, nil, current_room}, rooms_to_search_next, searched) then
      local found = false
      local first_bounce = nil
      while not found and #rooms_to_search_next > 0 do
         local this_level = rooms_to_search_next
         rooms_to_search_next = {}
         for i,su in ipairs(this_level) do
            found = search_for_dst(dst, su, rooms_to_search_next, searched)
            if found then
               break
            end
         end
      end
   end

   local path = {}
   local su = searched[dst]
   while su and su[1] do
      table.insert(path, {dir=su[2], uid=su[3]})
      su = searched[su[1]]
   end

   -- reverse
   for i=1, math.floor(#path / 2) do
      path[i], path[#path - i + 1] = path[#path - i + 1], path[i]
   end

   if show_timing then
      mapprint("Time elapsed pathfinding ",#path," levels: ", utils.timer()-findpath_elapsed)
   end

   if #path > 0 then
      return path
   else
      return
   end
end -- function findpath

require "serialize"
function full_find (dests, walk, no_portals)
   local paths = {}
   local notfound = {}
   for i,v in ipairs(dests) do
      SetStatus(string.format ("Pathfinding: searching for route to %i/%i discovered destinations", i, #dests))
      BroadcastPlugin(999, "repaint")
      local foundpath = findpath(current_room, v.uid, no_portals, no_portals)

      get_room(v.uid)

      if foundpath ~= nil then
         table.insert(paths, {uid=v.uid, path=foundpath, reason=v.reason})
      else
         table.insert(notfound, {uid=v.uid, reason=v.reason})
      end
   end
   SetStatus ("")

   BroadcastPlugin(500, "found_paths = "..string.gsub(serialize.save_simple(paths),"%s+"," "))
   BroadcastPlugin(501, "unfound_paths = "..string.gsub(serialize.save_simple(notfound),"%s+"," "))

   local found_count = #paths

   -- sort so closest ones are first
   table.sort(paths, function (a, b) return #a.path < #b.path end)

   if walk and paths[1] then
      local uid = paths[1].uid
      local path = paths[1].path
      mapprint("Going to:", get_room_display_params(uid).name)
      start_speedwalk(path)
      return
   end -- if walking wanted

   Note("+------------------------------ START OF SEARCH -------------------------------+")
   for _, p in ipairs(paths) do
      local room = rooms[p.uid] -- ought to exist or wouldn't be in table
      assert (room, "Room " .. p.uid .. " is not in rooms table.")

      local distance = #p.path .. " room"
      if #p.path > 1 or #p.path == 0 then
         distance = distance .. "s"
      end -- if
      distance = distance .. " away"

      if current_room ~= p.uid then
         addRunHyperlink(p.uid)
      else
         Tell(room.name)
      end
      local info = ""
      if type (p.reason) == "string" and p.reason ~= "" then
         info = "[" .. p.reason .. "]"
      end -- if
      mapprint (" - " .. distance .. info) -- new line

   end -- for each room

   if #notfound > 0 then
      local were, matches = "were", "matches"
      if #notfound == 1 then
         were, matches = "was", "match"
      end -- if
      Note("+------------------------------------------------------------------------------+")
      mapprint ("There", were, #notfound, matches,  "which I could not find a path to:")
   end -- if
   for i,v in ipairs(notfound) do
      local nfroom = rooms[v.uid]
      local nfline = nfroom.name
      nfline = nfline .. " (" .. nfroom.area .. ")"
      nfline = nfline .. " (" .. v.uid .. ")"
      Tell(nfline)
      if type (v.reason) == "string" and v.reason ~= "" then
         nfinfo = " -[" .. v.reason .. "]"
         mapprint (nfinfo) -- new line
      else
         Note("")
      end -- if
   end

   Note("+-------------------------------- END OF SEARCH -------------------------------+")
end

function quick_find(dests, walk)
   BroadcastPlugin (999, "repaint")
   Note("+------------------------------ START OF SEARCH -------------------------------+")

   for i,v in ipairs(dests) do
      local uid = v.uid
      local room = get_room(uid)

      assert (room, "Room " .. v.uid .. " is not in rooms table.")

      if current_room ~= v.uid then
         addRunHyperlink(v.uid)
      else
         ColourTell(RGBColourToName(MAPPER_NOTE_COLOUR.colour),"","[you are here] "..room.name)
      end

      local info = ""
      if type (v.reason) == "string" and v.reason ~= "" then
         info = "[" .. v.reason .. "]"
         mapprint (" - " .. info) -- new line
      else -- if
         Note("")
      end

      BroadcastPlugin (999, "repaint")
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
      if (next_result_index > 0) and last_result_list and (next_result_index <= #last_result_list) then
         mapper.goto(last_result_list[next_result_index])
         return
      else
         ColourNote(RGBColourToName(MAPPER_NOTE_COLOUR.colour),"","NEXT ERROR: There is no NEXT result #"..next_result_index..".")
         next_result_index = nil
      end
   end
end

-- generic room finder
-- dests is a list of room/reason pairs where reason is either true (meaning generic) or a string to find
-- if 'walk' is true, we walk to the first match rather than displaying hyperlinks
-- quick_list determines whether we pathfind every destination in advance to be able to sort by distance
function find (name, dests, walk, quick_list, no_portals)
   local find_elapsed = utils.timer()
   if not check_we_can_find() then
      return
   end -- if

   if not walk then
      mapprint ("Found",#dests,"target"..(((#dests ~= 1) and "s") or "")..(((name ~= nil) and (" matching '"..name.."'")) or "")..".")
   end

   local max_paths = 50
   if #dests > max_paths and not quick_list then
      mapprint("Your search would pathfind more than "..tostring(max_paths).." results. Choose a more specific pattern or activate the mapper quicklist setting.")
      return
   end

   if not walk then
      last_result_list = {}
      next_result_index = 0
   end

   if quick_list == true then
      quick_find(dests, walk)
   else
      full_find(dests, walk, no_portals)
   end
   if show_timing then
      print("mapper find elapsed: ", utils.timer() - find_elapsed)
   end
end -- map_find_things

-- build a speedwalk from a path into a string
function build_speedwalk(path)

   if #path == 0 then
      return
   end -- nowhere to go (current room?)

   if GetOption("enable_command_stack")==1 then
      stack_char = GetAlphaOption("command_stack_character")
   else
      stack_char = "\r\n"
   end

   -- combine direction chains
   local tspeed = {}
   local n = 0
   for _, ex in ipairs(path) do
      if (n == 0) or (expand_direction[ex.dir] == nil) or (tspeed[n].dir ~= ex.dir) then
         table.insert(tspeed, {dir=ex.dir, count=1})
         n = n + 1
      else
         tspeed[n].count = tspeed[n].count + 1
      end -- if new direction
   end -- for

   -- now build string like: run 2n3e4;open east;east;run 3n
   local s = ""
   local new_command = true
   for i, dir in ipairs(tspeed) do
      if expand_direction[dir.dir] then
         if new_command then
            s = s .. ((i > 1) and ";" or "") .. "run "
            new_command = false
         end
         if dir.count > 1 then
            s = s .. dir.count
         end -- if
         s = s .. dir.dir
      else
         s = s .. ((i > 1) and ";" or "") .. dir.dir
         new_command = true
      end -- if
   end -- if

   return string.gsub(s,";",stack_char)
end -- build_speedwalk

-- start a speedwalk to a path
function start_speedwalk(path)
   if not check_connected () then
      return
   end -- if

   if path and #path > 0 then
      current_speedwalk = path

      if myState == 9 or myState == 11 then
         Send("stand")
      end

      last_speedwalk_uid = path[#path].uid

      -- fast speedwalk: send run 4s3e etc.
      ExecuteWithWaits(build_speedwalk(path))
   end -- if any steps
   current_speedwalk = nil

end -- start_speedwalk

-- ------------------------------------------------------------------
-- mouse-up handlers (need to be exposed)
-- these are for clicking on the map, or the configuration box
-- ------------------------------------------------------------------
function goto(dest, force_walking)
   if not dest or not check_we_can_find() or not check_connected() then
      return
   end

   if dest == current_room then
      mapprint(string.format("You are already in room %s.", dest))
      return
   end

   local path = findpath(current_room, dest, force_walking, force_walking)

   if path then
      start_speedwalk(path)
   else
      mapprint (string.format ("Path from here to %s could not be found.", dest))
   end
end

function mouseup_room (flags, hotspot_id)

   if bit.band(flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      -- RH click
      if type (room_click) == "function" then
         room_click(hotspot_id, flags)
      end
      return
   end -- if RH click

   -- here for LH click

   -- find desired room
   goto(hotspot_id)
end -- mouseup_room

function mouseup_configure (flags, hotspot_id)
   draw_configure_box = true
   draw_configuration()
end -- mouseup_configure

function mouseup_close_configure (flags, hotspot_id)
   draw_configure_box = false
   OnPluginSaveState()
   draw(current_room)
end -- mouseup_player

function mouseup_stitch_continents(flags, hotspot_id)
   STITCH_CONTINENTS = not STITCH_CONTINENTS
   OnPluginSaveState()
   draw(current_room)
end

function mouseup_change_border_type (flags, hotspot_id)
   if hotspot_id:find("continent") then
      CONTINENT_ROOM_BORDER_TYPE = CONTINENT_ROOM_BORDER_TYPE + 1
      if CONTINENT_ROOM_BORDER_TYPE > #BORDER_TYPES then
         CONTINENT_ROOM_BORDER_TYPE = 1
      end
   else
      ROOM_BORDER_TYPE = ROOM_BORDER_TYPE + 1
      if ROOM_BORDER_TYPE > #BORDER_TYPES then
         ROOM_BORDER_TYPE = 1
      end
   end
   OnPluginSaveState()
   draw(current_room)
end

function mouseup_change_colour (flags, hotspot_id)

   local which = string.match (hotspot_id, "^$colour:([%a%d_]+)$")
   if not which then
      return  -- strange ...
   end -- not found

   local newcolour = PickColour (config[which].colour)

   if newcolour == -1 then
      return
   end -- if dismissed

   config[which].colour = newcolour

   draw (current_room)
end -- mouseup_change_colour

function mouseup_change_font (flags, hotspot_id)

   local newfont =  utils.fontpicker (config.FONT.name, config.FONT.size, ROOM_NAME_TEXT.colour)

   if not newfont then
      return
   end -- if dismissed

   config.FONT.name = newfont.name
   config.FONT.size = newfont.size

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
   local rs = current_room_is_cont and CONTINENT_ROOM_SIZE or ROOM_SIZE
   local dtnr = current_room_is_cont and DISTANCE_TO_NEXT_CONTINENT_ROOM or DISTANCE_TO_NEXT_ROOM

   if bit.band(flags, 0x100) ~= 0 then
      if rs > ROOM_SCALE_LIMITS.ROOM_SIZE_MIN and dtnr > ROOM_SCALE_LIMITS.DISTANCE_TO_NEXT_ROOM_MIN then
         smaller_rooms(0, current_room_is_cont and "continent" or "")
         denser(0, current_room_is_cont and "continent" or "")
      end
   else
      if rs < ROOM_SCALE_LIMITS.ROOM_SIZE_MAX and dtnr < ROOM_SCALE_LIMITS.DISTANCE_TO_NEXT_ROOM_MAX then
         bigger_rooms(0, current_room_is_cont and "continent" or "")
         sparser(0, current_room_is_cont and "continent" or "")
      end
   end -- if
end -- zoom_map

function resize_mouse_down(flags, hotspot_id)
   if (hotspot_id == "$<resize>") then
      startx, starty = WindowInfo (win, 17), WindowInfo (win, 18)
   end
end

function draw_credits()
   local top = (config.WINDOW.height - #credits * font_height) /2

   WindowRectOp (win, 2, 0, 0, 0, 0, 0)

   for _, v in ipairs (credits) do
      local width = WindowTextWidth (win, FONT_ID, v)
      local left = (config.WINDOW.width - width) / 2
      WindowText (win, FONT_ID, v, left, top, 0, 0, ROOM_COLOUR.colour)
      top = top + font_height
   end -- for

   draw_edge()
   BroadcastPlugin (999, "repaint")
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
   draw_edge()

   WindowShow(win,true)
end

function add_resize_tag()
   -- draw the resize widget bottom right corner.
   local width  = WindowInfo(win, 3)
   local height = WindowInfo(win, 4)

   WindowLine(win, width-4, height-2, width-2, height-4, 0xffffff, 0, 2)
   WindowLine(win, width-5, height-2, width-2, height-5, 0x696969, 0, 1)
   WindowLine(win, width-7, height-2, width-2, height-7, 0xffffff, 0, 2)
   WindowLine(win, width-8, height-2, width-2, height-8, 0x696969, 0, 1)
   WindowLine(win, width-10, height-2, width-2, height-10, 0xffffff, 0, 2)
   WindowLine(win, width-11, height-2, width-2, height-11, 0x696969, 0, 1)
   WindowLine(win, width-13, height-2, width-2, height-13, 0xffffff, 0, 2)
   WindowLine(win, width-14, height-2, width-2, height-14, 0x696969, 0, 1)

   -- Hotspot for resizer.
   local x = width - 14
   local y = height - 14
   if (WindowHotspotInfo(win, "$<resize>", 1) == nil) then
      WindowAddHotspot(win, "$<resize>",
         x, y, 0, 0,   -- rectangle
         "", "", "mapper.resize_mouse_down", "", "",
         "Drag to resize",
         6, 0)  -- hand cursor
      WindowDragHandler(win, "$<resize>", "mapper.resize_move_callback", "mapper.resize_release_callback", 0)
   else
      WindowMoveHotspot(win, "$<resize>", x, y,  0,  0)
   end
end -- draw resize tag.

function draw_edge()
   -- draw edge frame.
   check (WindowRectOp (win, 1, 0, 0, 0, 0, 0xE8E8E8, 15))
   check (WindowRectOp (win, 1, 1, 1, -1, -1, 0x777777, 15))
   add_resize_tag()
end
