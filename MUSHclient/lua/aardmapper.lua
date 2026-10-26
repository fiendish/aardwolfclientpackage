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

module (..., package.seeall)

require "aard_register_z_on_create"

require "mw_theme_base"
require "movewindow"
require "gauge"
local window_fonts = require "window_fonts"
dofile (GetInfo(60) .. "aardwolf_colors.lua")

styles = {}

ROOM_PREFETCH_BATCH_SIZE = 32
local new_continent_maps
local FONT_ID     = "fn"  -- internal font identifier
local FONT_ID_UL  = "fnu" -- internal font identifier - underlined
local CONFIG_FONT_ID = "cfn"
local CONFIG_FONT_ID_UL = "cfnu"
local ROOM_PREFETCH_SCAN_LIMIT = 128

-- Room sizes and spacing are stored separately for ordinary areas and continents.
local ROOM_SIZE = tonumber(GetVariable("ROOM_SIZE")) or 18

local DISTANCE_TO_NEXT_ROOM = math.max(-1,tonumber(GetVariable("DISTANCE_TO_NEXT_ROOM")) or 8)

local room_layout = {
   area = {size = ROOM_SIZE, spacing = DISTANCE_TO_NEXT_ROOM},
   continent = {
      size = tonumber(GetVariable("CONTINENT_ROOM_SIZE")) or 9,
      stretch = GetVariable("CONTINENT_STRETCH_TO_FIT") == "1",
   },
}
room_layout.vidblain = {
   size = tonumber(GetVariable("VIDBLAIN_ROOM_SIZE")) or 9,
   stretch = GetVariable("VIDBLAIN_STRETCH_TO_FIT") == "1",
}
local timing            -- true to show frame timing summary
local detailed_timing   -- true to show detailed sub-phase breakdown

local room_cache_hits = 0    -- timing: cache hit counter
local room_cache_misses = 0  -- timing: cache miss counter
-- All batches in a frame use the same cutoff for recent-visit exit lines.
local frame_timestamp = 0

-- Keep the frame being built separate from the published selection views.
-- Mouse input must use the room positions that match the visible pixels.
local drawing = {
   slice_seconds=0.100, room_batch_size=128,
   map_region={},
}
local offscreen_window, completed_frame_cache, frame_commands, frame_commands_changed
local map_command_state = {buffers={{}, {}}, count=0}
local control_hotspots = {}
local HALF_ROOM, connectors, half_connectors, arrows

local queued_room_uids, queued_room_x, queued_room_y
local room_queue_buffers = {{uid={}, x={}, y={}}, {uid={}, x={}, y={}}}
local recent_frame_times = {}
local recent_frame_index = 0
local RECENT_FRAME_COUNT = 30

local room_draw_times = {}
local rooms_drawn_count = 0
local frame_metrics = {
   total_exit_planning_time = 0,
   total_exit_drawing_time = 0,
   total_room_cache_time = 0,
   total_room_db_time = 0,
   total_room_prefetch_time = 0,
   room_prefetch_count = 0,
   total_room_defaults_time = 0,
   total_room_texture_time = 0,
   total_graphics_time = 0,
   total_hotspot_time = 0,
   total_window_setup_time = 0,
   total_bg_texture_time = 0,
   total_room_loop_time = 0,
   total_map_overlay_time = 0,
   total_dress_window_time = 0,
   total_current_room_time = 0,
   total_map_capture_time = 0,
   total_map_render_time = 0,
   map_image_reused = false,
   map_image_retained = false,
   total_repaint_request_time = 0,
   total_get_room_time = 0,
   room_load_count = 0,
   visible_room_count = 0,
}
local window_call_groups = {
   Drawing = {"WindowCircleOp", "WindowLine", "WindowPolygon", "WindowBezier",
      "WindowRectOp", "WindowGradient", "WindowSetPixel", "WindowText"},
   Images = {"WindowDrawImage", "WindowDrawImageAlpha", "WindowBlendImage",
      "WindowTransformImage", "WindowFilter", "WindowImageFromWindow", "WindowLoadImage"},
   Hotspots = {"WindowAddHotspot", "WindowDeleteHotspot", "WindowDeleteAllHotspots",
      "WindowMoveHotspot", "WindowDragHandler", "WindowScrollwheelHandler",
      "WindowHotspotTooltip", "WindowHotspotList", "WindowHotspotInfo"},
   Window = {"WindowCreate", "WindowResize", "WindowPosition", "WindowShow", "WindowSetZOrder"},
   Queries = {"WindowInfo", "WindowTextWidth", "WindowFontInfo", "WindowFontList", "WindowImageInfo"},
}
local window_call_stats

-- cached tiled background texture
local cached_bg_image = nil
local cached_bg_width = 0
local cached_bg_height = 0
local cached_bg_texture = nil
local default_width = 271
local default_height = 335
local default_x = 884 + Theme.RESIZER_SIZE + 2
local default_y = 0

styles.BACKGROUND_COLOUR     = { name = "Area Background",  colour =  ColourNameToRGB "#111111"}
styles.ROOM_COLOUR           = { name = "Room",             colour =  ColourNameToRGB "#dcdcdc"}
styles.EXIT_COLOUR           = { name = "Exit",             colour =  ColourNameToRGB "#e0ffff"}
styles.EXIT_COLOUR_UP_DOWN   = { name = "Exit up/down",     colour =  ColourNameToRGB "#ffb6c1"}
styles.ROOM_NOTE_COLOUR      = { name = "Room notes",       colour =  ColourNameToRGB "lightgreen"}
styles.OUR_ROOM_COLOUR       = { name = "Our room",         colour =  ColourNameToRGB "#ff1493"}
styles.UNKNOWN_ROOM_COLOUR   = { name = "Unknown room",     colour =  ColourNameToRGB "#9b0000"}
styles.DIFFERENT_AREA_COLOUR = { name = "Another area",     colour =  ColourNameToRGB "#ff0000"}
styles.AREA_EXIT_FILL_COLOUR = { name = "Area exit room",   colour =  ColourNameToRGB "#b03060"}
styles.PK_BORDER_COLOUR      = { name = "PK border",        colour =  ColourNameToRGB "red"}
styles.SHOP_FILL_COLOUR      = { name = "Shop",             colour =  ColourNameToRGB "#ffad2f"}
styles.HEALER_FILL_COLOUR    = { name = "Healer",           colour =  ColourNameToRGB "#9acd32"}
styles.TRAINER_FILL_COLOUR   = { name = "Trainer",          colour =  ColourNameToRGB "#9acd32"}
styles.QUESTOR_FILL_COLOUR   = { name = "Questor",          colour =  ColourNameToRGB "deepskyblue"}
styles.BANK_FILL_COLOUR      = { name = "Bank",             colour =  ColourNameToRGB "#ffD700"}
styles.GUILD_FILL_COLOUR     = { name = "Guild",            colour =  ColourNameToRGB "magenta"}
styles.SAFEROOM_FILL_COLOUR  = { name = "Safe room",        colour =  ColourNameToRGB "lightblue"}
styles.MAPPER_NOTE_COLOUR    = { name = "Messages",         colour =  ColourNameToRGB "lightgreen"}

styles.ROOM_NAME_TEXT        = { name = "Room name text",   colour = ColourNameToRGB "#BEF3F1"}
styles.ROOM_NAME_FILL        = { name = "Room name fill",   colour = ColourNameToRGB "#105653"}
styles.ROOM_NAME_BORDER      = { name = "Room name box",    colour = ColourNameToRGB "black"}

styles.AREA_NAME_TEXT        = { name = "Area name text",   colour = ColourNameToRGB "#BEF3F1"}
styles.AREA_NAME_FILL        = { name = "Area name fill",   colour = ColourNameToRGB "#105653"}
styles.AREA_NAME_BORDER      = { name = "Area name box",    colour = ColourNameToRGB "black"}

local RECENT_VISIT_SECONDS = 60 * 3

local default_config = {
   FONT = { name =  window_fonts.get_preferred_font {"Dina",  "Lucida Console",  "Fixedsys", "Courier",} ,
            size = 8
         } ,
   WINDOW = { width = default_width, height = default_height },
   SCAN = { depth = 300 },
   USE_TEXTURES = { enabled = true },
   SHOW_ROOM_ID = false,
   SHOW_ROOM_BORDERS = true,
   BLINK_PK_TITLE = true,
   MOUSEWHEEL_ZOOM = true
}

local callbacks = {}
local map_origin_uid, map_area_name
-- Display records are copies; drawing changes must not modify stored room data.
local display_room_cache, room_visit_times, texture_image_cache = {}, {}, {}
local config_window, windowinfo, font_height

-- The first path to a position wins, so exit order must be stable.
local exit_order = {"d", "e", "n", "s", "u", "w"}

-- Use the reverse exit to distinguish a shared line from a one-way arrow.
local inverse_direction = {
   n = "s",
   s = "n",
   e = "w",
   w = "e",
   u = "d",
   d = "u",
}

-- Reserve positions when exits are queued, including rooms outside the visible window.
local planned_room_positions, processed_room_positions, occupied_room_positions, area_exits, traversal_depth
local drawn_min_x, drawn_min_y, drawn_max_x, drawn_max_y
local bodyleft, bodytop, bodyright, bodybottom
local resize_dragging = false
local is_running = false
local pan_offset_x, pan_offset_y = 0, 0
local pan_last_mouse_x, pan_last_mouse_y = 0, 0
local pan_dragging, pan_rebaseline_on_drag, pan_animating = false, false, false
local pan_animation_time = 0
local last_area_for_pan
local MAP_DRAG_THRESHOLD = 4  -- ignore small pointer movements during a click
local pan_tooltip_text = "Drag to pan map"
local PAN_ANIMATION_INTERVAL = 1 / 30
local previous_origin_uid, previous_area_name
local title_color, next_blink_color, truncated_room_name, room_title_cache

local blink_cycle = {
   "@R",
   "@Y",
   "@W"
}
local config_panel_open
local hidden, show_on_redraw
local credits = {
   "MUSHclient mapper",
   "Made for Aardwolf by Fiendish",
   "Original concept by Nick Gammon",
   "World: "..WorldName (),
   GetInfo (3),
}
local resize_start_x, resize_start_y

do
   local M = {}
   M.definitions = {
      [0]={first_uid=11435, area="mesolar", width=60, height=40, x=60, y=0},
      [1]={first_uid=4863, area="southern", width=60, height=15, x=60, y=40},
      [2]={first_uid=17131, area="gelidus", width=60, height=40, x=60, y=55},
      [3]={first_uid=24236, area="abend", width=30, height=40, x=30, y=0},
      [4]={first_uid=2492, area="alagh", width=30, height=50, x=0, y=0},
      [5]={first_uid=6999, area="uncharted", width=60, height=55, x=0, y=40},
      [6]={first_uid=33136, area="vidblain", width=30, height=30, x=0, y=0},
   }
   local directions = {n={0,-1}, s={0,1}, e={1,0}, w={-1,0}}
   local surface_zones = {{4,3,0,1,2,5}, {5,4,3,0,1,2}}
   local empty_exits = {}
   local EMPTY_COLOUR = 0
   -- Keep the continent display palette separate from the GMCP sector palette.
   -- Each entry gives the original bigmap glyph and its foreground RGB colour.
   M.terrain_styles = {
      areaexit={"?",0xffffff}, clanexit={"?",0xffffff}, interestpoint={"?",0xffffff},
      beach={".",0x00ffff}, desert={"~",0x00ffff},
      ocean={"~",0xe16941}, ocean2={"^",0xe16941}, ocean3={"~",0xe16941}, ocean4={"~",0xe16941},
      cave={"~",0xe16941}, river={".",0xe16941}, shore={"~",0xffff00},
      mountain={"^",0x008080}, mountain_cyan={"^",0x808000}, rocks={"^",0x008080},
      hills={"^",0x00ff00}, volcano={"^",0x0000ff},
      field={"#",0x008000}, field2={"#",0x008000}, field3={"#",0x008000}, field4={"#",0x008000},
      swamp={"#",0x008000}, forest={"*",0x00ff00}, jungle={"*",0x008000}, plain={"#",0x008080},
      hell1={"#",0x000080}, hell2={"#",0x000080}, hell3={"#",0x000080},
      ice={"#",0xffffff}, icehills={"#",0xffffff}, icemount={"/",0xffffff}, snow={"#",0xffffff},
      road={"#",0xffffff}, bridge={"=",0xffffff}, castle={"#",0xffffff}, city={"%",0xffffff},
      pillar={"*",0xffffff}, smallroad={"|",0xc0c0c0}, smallroad_ew={"-",0xc0c0c0}, trail_ew={".",0xc0c0c0},
      dark={" ",0}, space1={" ",0}, space4={" ",0}, underground={" ",0}, waternoswim={" ",0}, dungeon={" ",0},
   }

   local function uid_less(a,b)
      local first,second=tonumber(a),tonumber(b)
      if first and second and first~=second then return first<second end
      if first and not second then return true end
      if second and not first then return false end
      return tostring(a)<tostring(b)
   end

   local function split_axis(start, source_start, period, first, last, copies)
      local spans, count = {}, 0
      while count < period do
         local source = (source_start + count) % period
         local length = math.min(copies==1 and period-source or period, period-count)
         local destination = start+count
         local left, right = math.max(destination,first), math.min(destination+length,last)
         if left < right then spans[#spans+1]={left=left, source=source+left-destination, length=right-left} end
         count = count+length
      end
      return spans
   end

   -- Use the cached image's integer period for both wrapped crops and room edges.
   local function fit_axis(origin,source,period,pixels,first,last)
      local scale=pixels/period
      local position=source*pixels/period
      local start=math.floor(position)
      origin=math.floor(origin)
      return split_axis(origin,start,pixels,first,last,1),origin+position-start,scale,origin-start
   end

   -- Use the published grid, including off-screen neighbors and wrapped seams.
   local function view_entrance_approaches(view,source)
      local definition=M.definitions[source.zone]
      local stitched=view.grid_width==120
      local x=source.x+(stitched and definition.x or 0)
      local y=source.y+(stitched and definition.y or 0)
      local result={}
      for _,dir in ipairs({"n","e","s","w"}) do
         local offset=directions[dir]
         local adjacent=view.grid[(y-offset[2])%view.grid_height+1].cells[(x-offset[1])%view.grid_width+1]
         if adjacent==view.current_source then adjacent=view.current_cell end
         if adjacent.uid then
            result[#result+1]={uid=adjacent.uid,dir=dir}
         end
      end
      return result
   end

   -- Resolve only the cells needed for overlays or mouse input. A view keeps
   -- its own grid rows, so later observations cannot change a published frame.
   local function view_cell(view,column,row)
      local source=view.grid[(view.source_y+row)%view.grid_height+1].cells[(view.source_x+column)%view.grid_width+1]
      if source==view.current_source then source=view.current_cell end
      return {zone=source.zone,x=source.x,y=source.y,uid=source.uid,room=source.room,
         unexplored_uid=source.unexplored_uid,entry_rooms=source.entry_rooms,
         entrance_approaches=source.unexplored_entrance and view_entrance_approaches(view,source) or nil,
         left=view.raster_x and view.raster_x+math.floor((view.source_x+column)*view.raster_width/view.grid_width)
            or math.floor(view.base_left+column*view.base_pitch),
         top=view.raster_y and view.raster_y+math.floor((view.source_y+row)*view.raster_height/view.grid_height)
            or math.floor(view.base_top+row*view.base_pitch)}
   end

   local function has_overlay(room)
      return room and (room.info and room.info:match("pk") or room.notes and room.notes~="")
   end

   function new_continent_maps(context, window)
      local api = context.api or _G
      local mini = api.miniwin

      local function same(a,b)
         if a==b then return true end
         return a and b and a.brush==b.brush and a.entrance==b.entrance
            and (a.brush==mini.brush_null or a.colour==b.colour)
      end

      local brushes = {['~']=mini.brush_waves_horizontal, ['^']=mini.brush_waves_vertical,
         ['.']=mini.brush_hatch_backwards_diagonal, ['?']=mini.brush_null, [' ']=mini.brush_null}
      local state = {rooms={}, index={}, positions={}, images={}, overrides={}, revision=0, loaded=false,
         destination_areas={},room_links={},unmapped_links={},entrance_targets={},entrance_entries={},unexplored_targets={},unexplored_entries={},pending={},cells={},grids={}}
      local exits, update_entrances

      local function check(code) assert(code==0, "Continent window call failed: "..tostring(code)) end

      local zone_for=context.zone_for

      local function glyph_style(character, colour)
         return {brush=brushes[character] or mini.brush_solid, colour=colour,
            entrance=character=="?"}
      end

      local styles={}
      for terrain,style in pairs(M.terrain_styles) do styles[terrain]=glyph_style(style[1],style[2]) end

      local function room_style(room)
         local style=styles[room.terrain]
         if style then return style end
         local colour=context.terrain_colour(room.terrain)
         if colour==nil then return end
         return glyph_style("#",colour)
      end

      local function insert_position(uid, zone, x, y)
         local definition = assert(M.definitions[zone])
         x,y = x%definition.width,y%definition.height
         local previous=state.positions[uid]
         if previous then
            local old=state.index[previous.zone][previous.y*M.definitions[previous.zone].width+previous.x]
            if old then for i=#old,1,-1 do if old[i]==uid then table.remove(old,i) end end end
         end
         state.positions[uid]={zone=zone,x=x,y=y}
         state.index[zone]=state.index[zone] or {}
         local key=y*definition.width+x
         local list=state.index[zone][key] or {}
         list[#list+1]=uid
         state.index[zone][key]=list
      end

      -- Recover the offline numeric grid only when all known cardinal edges agree.
      local function numeric_grid(definition,zone_rooms,repair_seeds)
         local bases,numeric,missing,seeds={},{},false,0
         for _,uid in ipairs(zone_rooms) do
            local n=tonumber(uid)
            if n then numeric[#numeric+1]=n end
            local p=state.positions[uid]
            if n and not p then missing=true end
            if n and p then
               seeds=seeds+1
               local b=n-p.y*definition.width-p.x
               bases[b]=(bases[b] or 0)+1
            end
         end
         local base,best=nil,0
         for b,n in pairs(bases) do if n>best then base,best=b,n end end
         if repair_seeds then
            -- Only a strict majority can correct conflicting stored coordinates.
            if best==seeds or best*2<=seeds then return end
         elseif not missing then return end
         if not base then
            table.sort(numeric)
            local first=1
            for i,n in ipairs(numeric) do
               if i>1 and n~=numeric[i-1]+1 then first=i end
               if i-first+1==definition.width*definition.height then base=numeric[first];break end
            end
         end
         base=base or definition.first_uid
         local candidates={}
         for _,uid in ipairs(zone_rooms) do
            local numeric_uid=tonumber(uid)
            local offset=numeric_uid and numeric_uid-base
            if offset and offset>=0 and offset<definition.width*definition.height then
               candidates[uid]={x=offset%definition.width,y=math.floor(offset/definition.width)}
            end
         end
         local adjacent=repair_seeds and {}
         for uid,p in pairs(candidates) do
            for dir,dest in pairs(state.rooms[uid].exits) do
               local q,offset=candidates[dest],directions[dir]
               if q and offset then
                  if (q.x-p.x-offset[1])%definition.width~=0 or
                        (q.y-p.y-offset[2])%definition.height~=0 then return end
                  if adjacent then
                     adjacent[uid]=adjacent[uid] or {};adjacent[uid][dest]=true
                     adjacent[dest]=adjacent[dest] or {};adjacent[dest][uid]=true
                  end
               end
            end
         end
         if repair_seeds then
            -- Each connected component must support this origin on its own.
            -- Cardinal exits constrain coordinates in both directions, even
            -- when an exit is only traversable in one direction.
            local visited={}
            for first in pairs(candidates) do
               if not visited[first] then
                  local queue,head,support,seeds={first},1,0,0
                  visited[first]=true
                  while head<=#queue do
                     local uid=queue[head];head=head+1
                     local p,seed=candidates[uid],state.positions[uid]
                     if seed then
                        seeds=seeds+1
                        if seed.x==p.x and seed.y==p.y then support=support+1 end
                     end
                     for dest in pairs(adjacent[uid] or empty_exits) do
                        if not visited[dest] then visited[dest]=true;queue[#queue+1]=dest end
                     end
                  end
                  if support*2<=seeds then
                     for _,uid in ipairs(queue) do candidates[uid]=nil end
                  end
               end
            end
         end
         return candidates
      end

      local function build_index()
         state.rooms=context.load_rooms()
         state.index,state.positions,state.cells,state.grids,state.overrides={},{},{},{},{}
         state.destination_areas,state.unmapped_links={},{}
         state.room_links,state.entrance_targets,state.entrance_entries={},{},{}
         state.unexplored_targets,state.unexplored_entries={},{}
         local rooms_by_zone,queue={},{}
         for uid,room in pairs(state.rooms) do
            local zone=zone_for(room.area)
            local definition=M.definitions[zone]
            local zone_rooms=rooms_by_zone[zone] or {}
            zone_rooms[#zone_rooms+1]=uid
            rooms_by_zone[zone]=zone_rooms
            local x,y=tonumber(room.x),tonumber(room.y)
            if x and y and x>=0 and y>=0 and x<definition.width and y<definition.height then
               insert_position(uid,zone,x,y);queue[#queue+1]=uid
            end
         end
         -- Repair conflicting seeds before they can displace a whole component.
         -- Pending GMCP observations still apply after this database index is built.
         for zone,definition in pairs(M.definitions) do
            local candidates=numeric_grid(definition,rooms_by_zone[zone] or empty_exits,true)
            for uid,p in pairs(candidates or empty_exits) do
               if state.positions[uid] then insert_position(uid,zone,p.x,p.y) end
            end
         end
         local head=1
         while head<=#queue do
            local uid=queue[head];head=head+1
            local p=state.positions[uid]
            for dir,dest in pairs(state.rooms[uid].exits) do
               local offset=directions[dir]
               if offset and state.rooms[dest] and zone_for(state.rooms[dest].area)==p.zone and not state.positions[dest] then
                  insert_position(dest,p.zone,p.x+offset[1],p.y+offset[2]);queue[#queue+1]=dest
               end
            end
         end
         -- Coordinates and complete grids establish the numeric origin. Keep the
         -- fixed offline origin when deleted rooms leave gaps.
         for zone,definition in pairs(M.definitions) do
            local candidates=numeric_grid(definition,rooms_by_zone[zone] or empty_exits)
            for uid,p in pairs(candidates or empty_exits) do
               if not state.positions[uid] then insert_position(uid,zone,p.x,p.y) end
            end
         end
         state.loaded=true
         for uid in pairs(state.rooms) do update_entrances(uid) end
         for _,cells in pairs(state.index) do
            for _,list in pairs(cells) do table.sort(list,uid_less) end
         end
         for uid,observation in pairs(state.pending) do state.observe(uid,observation.room,observation.coord) end
         state.pending={}
      end

      function state.invalidate_rooms()
         state.loaded=false
         state.revision=state.revision+1
      end

      local function invalidate_cell(zone,key)
         local cached=state.cells[zone] and state.cells[zone][key]
         if cached then cached.stale=true end
         local d=M.definitions[zone]
         local x,y=key%d.width,math.floor(key/d.width)
         for _,grid in pairs(state.grids) do
            local gx,gy=x+(grid.zone and 0 or d.x),y+(grid.zone and 0 or d.y)
            local line=grid.rows[gy+1]
            local source=line and line.cells[gx+1]
            if source and source.zone==zone then grid.dirty[gy+1]=true end
         end
      end

      local function mark_dirty(zone,key)
         invalidate_cell(zone,key)
         for _,image in pairs(state.images) do
            image.dirty=image.dirty or {}
            image.dirty[zone..":"..key]={zone=zone,key=key}
         end
      end

      function state.remove_room(uid)

         local function remove_incoming(room)
            local changed=false
            for dir,dest in pairs(room.exits) do
               if dest==uid then
                  room.exits[dir]=nil
                  room.exit_locks[dir]=nil
                  if room.exit_areas then room.exit_areas[dir]=nil end
                  changed=true
               end
            end
            return changed
         end

         state.pending[uid]=nil
         for _,observation in pairs(state.pending) do remove_incoming(observation.room) end
         if not state.loaded then return end
         local position=state.positions[uid]
         state.rooms[uid],state.positions[uid],state.destination_areas[uid]=nil,nil,nil
         local affected={}
         if position then
            local zone=position.zone
            local key=position.y*M.definitions[zone].width+position.x
            local list=state.index[zone][key]
            for i=#list,1,-1 do
               if list[i]==uid then table.remove(list,i) else affected[list[i]]=true end
            end
            if state.overrides[zone] then state.overrides[zone][key]=nil end
            mark_dirty(zone,key)
            -- Unknown exits can change between an area entry and an unexplored
            -- cell when the deleted room supplied the projected terrain.
            for source in pairs(state.unmapped_links) do affected[source]=true end
         end
         for source,room in pairs(state.rooms) do
            if remove_incoming(room) then affected[source]=true end
         end
         state.room_links[uid],state.unmapped_links[uid]=nil,nil
         update_entrances(uid)
         for source in pairs(affected) do
            state.room_links[source],state.unmapped_links[source]=nil,nil
            update_entrances(source)
         end
      end

      function state.observe(uid,room,coord)
         local zone=tonumber(coord.id)
         if tostring(coord.cont)~="1" or not M.definitions[zone] then return end
         local x,y=tonumber(coord.x),tonumber(coord.y)
         if not x or not y or x<0 or y<0 or x>=M.definitions[zone].width or y>=M.definitions[zone].height then return end
         if not state.loaded then
            state.pending[uid]={room=room,coord={id=zone,cont="1",x=x,y=y}}
            return
         end
         local previous_position=state.positions[uid]
         local was_known=state.rooms[uid]~=nil
         local key=y*M.definitions[zone].width+x
         local list=state.index[zone] and state.index[zone][key]
         local primary=list and state.rooms[list[1]]
         local old=state.overrides[zone] and state.overrides[zone][key] or primary and room_style(primary)
         room.uid=uid
         state.room_links[uid],state.unmapped_links[uid]=nil,nil
         state.destination_areas[uid]=nil
         state.rooms[uid]=room
         insert_position(uid,zone,x,y)
         local style=room_style(room)
         local style_changed=not same(style,old)
         local position_changed=previous_position and (previous_position.zone~=zone or previous_position.x~=x or previous_position.y~=y)
         -- Keep an observed cell correction even when its UID differs from the
         -- database room at that coordinate. A database reload retires it.
         local base=room_style(state.rooms[state.index[zone][key][1]])
         if style and not same(style,base) then
            state.overrides[zone]=state.overrides[zone] or {}
            state.overrides[zone][key]=style
         elseif state.overrides[zone] then state.overrides[zone][key]=nil end
         if style_changed then mark_dirty(zone,key) end
         update_entrances(uid)
         -- Unmapped destinations can become known, or their projected terrain
         -- can gain or lose the area marker used to infer an entry. Relocation
         -- also changes the old cell, even when the new cell has the same style.
         if not was_known or style_changed or position_changed then
            local affected={}
            if style_changed or position_changed then

               -- A cell correction also changes the distance of exits from
               -- other room IDs already indexed at that coordinate.
               local function affect_position(zone,key)
                  local sources=state.index[zone] and state.index[zone][key]
                  for _,source in ipairs(sources or empty_exits) do
                     if source~=uid then affected[source]=true end
                  end
               end

               affect_position(zone,key)
               if position_changed then
                  affect_position(previous_position.zone,previous_position.y*M.definitions[previous_position.zone].width+previous_position.x)
               end
            end
            for source,links in pairs(state.unmapped_links) do
               if source~=uid then
                  for _,exit in ipairs(links) do
                     if style_changed or position_changed or exit.uid==uid then affected[source]=true;break end
                  end
               end
            end
            for source in pairs(affected) do
               state.room_links[source],state.unmapped_links[source]=nil,nil
               update_entrances(source)
            end
         end
         -- Room metadata can change without a terrain patch.
         if position_changed then
            mark_dirty(previous_position.zone,previous_position.y*M.definitions[previous_position.zone].width+previous_position.x)
            mark_dirty(zone,key)
         elseif not style_changed then invalidate_cell(zone,key) end
      end

      exits=function(room)
         if state.room_links[room.uid] then
            return state.room_links[room.uid],state.unmapped_links[room.uid] or empty_exits
         end
         local result,unmapped={},empty_exits
         for dir,dest in pairs(room.exits) do
            if directions[dir] or dir=="u" or dir=="d" then
               local destination=state.rooms[dest]
               local area=room.exit_areas and room.exit_areas[dir]
               if not destination and area==nil then
                  area=state.destination_areas[dest]
                  if area==nil then area=context.destination_area(dest) or false;state.destination_areas[dest]=area end
               end
               if not destination and area and area~=room.area and zone_for(area)==nil then
                  result[#result+1]={dir=dir,uid=dest}
               elseif not destination and not area then
                  if unmapped==empty_exits then unmapped={} end
                  unmapped[#unmapped+1]={dir=dir,uid=dest}
               end
            end
         end
         state.room_links[room.uid]=result
         state.unmapped_links[room.uid]=unmapped~=empty_exits and unmapped or nil
         return result,unmapped
      end

      local function cell(zone,x,y,current_uid)
         local definition=M.definitions[zone]
         local key=y*definition.width+x
         local list=state.index[zone] and state.index[zone][key]
         local uid=list and list[1]
         local current=state.positions[current_uid]
         if current and current.zone==zone and current.x==x and current.y==y then uid=current_uid end
         local room=uid and state.rooms[uid]
         local style=state.overrides[zone] and state.overrides[zone][key] or room and room_style(room)
         local result={}
         result.zone,result.x,result.y,result.uid=zone,x,y,uid
         result.room,result.style=room,style
         result.overlay=has_overlay(room)
         -- A different room at this coordinate can become the current room.
         if not result.overlay and list and #list>1 then
            for _,other in ipairs(list) do
               if has_overlay(state.rooms[other]) then result.overlay=true;break end
            end
         end
         -- A saved exit supplies an unexplored room's ID without its metadata.
         local unknown=state.unexplored_entries[zone] and state.unexplored_entries[zone][key]
         if not uid and unknown then
            for dest in pairs(unknown) do
               if not state.rooms[dest] and (not result.unexplored_uid or uid_less(dest,result.unexplored_uid)) then
                  result.unexplored_uid=dest
               end
            end
         end
         local entry_counts=state.entrance_entries[zone] and state.entrance_entries[zone][key]
         local entry_rooms=empty_exits
         if entry_counts and next(entry_counts) then
            entry_rooms={}
            for entry_uid in pairs(entry_counts) do entry_rooms[#entry_rooms+1]=entry_uid end
            table.sort(entry_rooms,uid_less)
         end
         result.entry_rooms=entry_rooms
         result.unexplored_entrance=style==styles.areaexit and #entry_rooms==0
         result.entrance=(style and style.entrance) or (entry_counts and next(entry_counts)~=nil) or false
         return result
      end

      local function cached_cell(zone,x,y)
         local cells=state.cells[zone] or {}
         state.cells[zone]=cells
         local key=y*M.definitions[zone].width+x
         local cached=cells[key]
         if not cached or cached.stale then
            cached=cell(zone,x,y)
            cells[key]=cached
         end
         return cached
      end

      local function surface_cell(surface,x,y,cached)
         local lookup=cached and cached_cell or cell
         if surface.zone then return lookup(surface.zone,x,y) end
         -- The detached Inner Sea shares a projected rectangle with Alagh.
         -- Select its image plane only when the current room is in that region.
         local zones=surface_zones[surface.inner_sea and 2 or 1]
         for _,zone in ipairs(zones) do
            local d=M.definitions[zone]
            if x>=d.x and x<d.x+d.width and y>=d.y and y<d.y+d.height then return lookup(zone,x-d.x,y-d.y) end
         end
      end

      local function grid_for(key,surface)
         local grid=state.grids[key]
         if grid and not next(grid.dirty) then return grid end
         grid=grid or {zone=surface.zone,rows={},dirty={}}
         local rows={}
         for y=0,surface.height-1 do
            local line=grid.rows[y+1]
            if not line or grid.dirty[y+1] then
               line={cells={},counts={[0]=0},overlays={}}
               for x=0,surface.width-1 do
                  local source=surface_cell(surface,x,y,true)
                  line.cells[x+1]=source
                  line.counts[x+1]=line.counts[x]+(source.uid and 1 or 0)
                  if source.overlay then line.overlays[#line.overlays+1]=x end
               end
            end
            rows[y+1]=line
         end
         grid.rows,grid.dirty=rows,{}
         state.grids[key]=grid
         return grid
      end

      -- Each source contributes once to each destination at a projected cell.
      -- Area entries and unexplored rooms use the same reference-count update.
      local function update_destination_counts(previous,wanted,entries,count_error,markers)

         local function update(target,before,after)
            local zone_entries=entries[target.zone] or {}
            entries[target.zone]=zone_entries
            local counts=zone_entries[target.key] or {}
            zone_entries[target.key]=counts
            local had_entries=next(counts)~=nil
            local changed=false
            for dest in pairs(before or empty_exits) do
               if not after or not after[dest] then
                  local count=counts[dest]-1
                  assert(count>=0,count_error)
                  counts[dest]=count>0 and count or nil
                  changed=true
               end
            end
            for dest in pairs(after or empty_exits) do
               if not before or not before[dest] then
                  counts[dest]=(counts[dest] or 0)+1
                  changed=true
               end
            end
            if changed then
               if markers and had_entries~=(next(counts)~=nil) then mark_dirty(target.zone,target.key)
               else invalidate_cell(target.zone,target.key) end
            end
         end

         for key,target in pairs(previous) do update(target,target.entries,wanted[key] and wanted[key].entries) end
         for key,target in pairs(wanted) do if not previous[key] then update(target,nil,target.entries) end end
      end

      update_entrances=function(uid)
         local previous=state.entrance_targets[uid] or empty_exits
         local wanted={}
         local old_unknown=state.unexplored_targets[uid] or empty_exits
         local unknown={}
         local position=state.positions[uid]
         local room=state.rooms[uid]
         if position and room then
            local links,unmapped=exits(room)
            local source=(#links>0 or #unmapped>0) and cell(position.zone,position.x,position.y,uid)
            for i=1,#links+#unmapped do
               local exit=links[i] or unmapped[i-#links]
               local offset=directions[exit.dir]
               local target=source
               -- Area cells and up/down exits have no map distance.
               -- Other connections point to the area cell in their exit direction.
               if offset and not (source.style and source.style.entrance) then
                  local d=M.definitions[position.zone]
                  if position.zone==6 then
                     target=cell(6,(position.x+offset[1])%d.width,(position.y+offset[2])%d.height)
                  else
                     local surface={inner_sea=position.zone==5 and position.x<30 and position.y<10}
                     target=surface_cell(surface,(position.x+d.x+offset[1])%120,(position.y+d.y+offset[2])%95)
                  end
               end
               -- An unexplored destination has no area record. The database
               -- or GMCP area terrain must identify its projected area cell.
               if i<=#links or not state.rooms[exit.uid] and target.style and target.style.entrance then
                  local key=target.y*M.definitions[target.zone].width+target.x
                  local target_key=target.zone..":"..key
                  local record=wanted[target_key] or {zone=target.zone,key=key,entries={}}
                  record.entries[exit.uid]=true
                  wanted[target_key]=record
               elseif i>#links and not target.uid then
                  local key=target.y*M.definitions[target.zone].width+target.x
                  local target_key=target.zone..":"..key
                  local record=unknown[target_key] or {zone=target.zone,key=key,entries={}}
                  record.entries[exit.uid]=true
                  unknown[target_key]=record
               end
            end
         end
         -- Keep unexplored click targets while any known exit points to them.
         -- These targets do not add terrain or area entrance boxes.
         update_destination_counts(old_unknown,unknown,state.unexplored_entries,
            "Negative unexplored continent room count")
         state.unexplored_targets[uid]=next(unknown) and unknown or nil
         -- Attach the actual rooms inside the area to the same cells as its
         -- entrance boxes. Count each source so duplicate incoming connections
         -- can change independently without losing an entry room.
         update_destination_counts(previous,wanted,state.entrance_entries,
            "Negative continent entry room count",true)
         state.entrance_targets[uid]=next(wanted) and wanted or nil
      end

      local function image_point(image,x,y)
         return x*image.pitch,y*image.pitch
      end

      local brush_backgrounds={}

      local function brush_background(colour)
         local background=brush_backgrounds[colour]
         if background==nil then
            local red=math.floor((colour%256)*0.55+0.5)
            local green=math.floor((math.floor(colour/256)%256)*0.55+0.5)
            local blue=math.floor((math.floor(colour/65536)%256)*0.55+0.5)
            background=red+green*256+blue*65536
            brush_backgrounds[colour]=background
         end
         return background
      end

      local function paint(image,c,x,y)
         local left,top=image_point(image,x,y)
         local style=c and c.style
         if style and style.brush~=mini.brush_null then
            local background=style.brush==mini.brush_solid and style.colour or brush_background(style.colour)
            -- Native brushes retain their 8-pixel period at every room size.
            check(api.WindowCircleOp(image.window,mini.circle_rectangle,left,top,left+image.size,top+image.size,
               style.colour,mini.pen_null,0,background,style.brush))
         end
      end

      local function marker(image,c,x,y)
         if c and c.entrance then
            local left,top=image_point(image,x,y)
            check(api.WindowCircleOp(image.window,mini.circle_rectangle,left,top,left+image.size,top+image.size,
               api.ColourNameToRGB("cyan"),mini.pen_solid,2,0,mini.brush_null))
         end
      end

      -- Build or patch the cached terrain image before projecting the viewport.
      local function update_image(key,surface,size)
         local stitched=surface.zone==nil
         local image=state.images[key]
         local image_status="reused"
         local pitch=size-1
         if not image or image.size~=size or image.revision~=state.revision then
            -- Supported sizes always align the atlas width with native brushes.
            -- Repeat non-aligned heights so wrapped crops keep the same phase.
            local copies_y=surface.height*pitch%8~=0 and 2 or 1
            -- Rebuilding reuses the native window. Its old metadata must not
            -- become valid again if drawing fails and settings are restored.
            if image then image.revision=nil end
            image={window=window.."_"..key,size=size,pitch=pitch,
               copies_y=copies_y,
               version=(image and image.version or 0)+1,
               scaled=image and image.scaled}
            image.width=surface.width*pitch
            image.height=surface.height*pitch*copies_y
            check(api.WindowCreate(image.window,0,0,image.width,image.height,0,
               mini.create_ignore_mouse,EMPTY_COLOUR))
            -- Store the window so it can be deleted if drawing fails.
            state.images[key]=image
            for row=0,surface.height*copies_y-1 do for column=0,surface.width-1 do
               paint(image,surface_cell(surface,column,row%surface.height,true),column,row)
            end end
            for row=0,surface.height*copies_y-1 do for column=0,surface.width-1 do
               marker(image,surface_cell(surface,column,row%surface.height,true),column,row)
            end end
            image.revision=state.revision
            image_status="rebuilt"
         elseif image.dirty and next(image.dirty) then
            local wanted={}
            for _,changed in pairs(image.dirty) do
               local d=M.definitions[changed.zone]
               local cx,cy=changed.key%d.width,math.floor(changed.key/d.width)
               if stitched then cx,cy=cx+d.x,cy+d.y end
               local source=surface_cell(surface,cx,cy,true)
               if source and source.zone==changed.zone and (stitched or changed.zone==surface.zone) then
                  for dy=-1,1 do for dx=-1,1 do
                     local px,py=cx+dx,cy+dy
                     if image.copies_y>1 then py=py%surface.height end
                     if px>=0 and py>=0 and px<surface.width and py<surface.height then wanted[py*surface.width+px]={x=px,y=py} end
                  end end
               end
            end
            local ordered={}
            for _,p in pairs(wanted) do
               for dy=0,image.copies_y-1 do
                  ordered[#ordered+1]={x=p.x,y=p.y+dy*surface.height}
               end
            end
            table.sort(ordered,function(a,b) return a.y==b.y and a.x<b.x or a.y<b.y end)
            for _,p in ipairs(ordered) do
               local left,top=image_point(image,p.x,p.y)
               check(api.WindowRectOp(image.window,2,left,top,left+pitch,top+pitch,EMPTY_COLOUR))
            end
            for _,p in ipairs(ordered) do paint(image,surface_cell(surface,p.x,p.y%surface.height,true),p.x,p.y) end
            -- Entrance borders can extend into a neighboring cell. Restore every
            -- border that intersects the repainted cells, including unchanged ones.
            local borders={}
            for _,p in ipairs(ordered) do
               for dy=-1,1 do for dx=-1,1 do
                  local px,py=p.x+dx,p.y+dy
                  if px>=0 and py>=0 and px<surface.width and py<surface.height*image.copies_y then borders[py*surface.width+px]={x=px,y=py} end
               end end
            end
            for _,p in pairs(borders) do marker(image,surface_cell(surface,p.x,p.y%surface.height,true),p.x,p.y) end
            if #ordered>0 then
               image.version=image.version+1
               image_status="patched"
            end
            image.dirty=nil
         end
         return image,image_status
      end

      -- Resize a static atlas once. Movement only copies its wrapped crops.
      local function scale_image(image,scale)
         local width,height=math.max(1,math.floor(image.width*scale)),math.max(1,math.floor(image.height*scale))
         local scaled=image.scaled
         if not scaled then
            scaled={window=image.window.."_fit",version=0}
         end
         if scaled.source_version~=image.version or scaled.width~=width or scaled.height~=height then
            scaled.source_version=nil
            check(api.WindowCreate(scaled.window,0,0,width,height,0,
               mini.create_ignore_mouse,EMPTY_COLOUR))
            image.scaled=scaled
            check(api.WindowImageFromWindow(scaled.window,"continent_source",image.window))
            check(api.WindowDrawImage(scaled.window,"continent_source",0,0,width,height,2))
            scaled.width,scaled.height=width,height
            scaled.version=scaled.version+1
            scaled.source_version=image.version
         end
         return scaled
      end

      function state.build_images(continent_size,vidblain_size)
         if not state.loaded then build_index() end
         local vidblain=M.definitions[6]
         for _,surface in ipairs({
            {key="stitched",width=120,height=95,size=continent_size},
            {key="inner_sea",width=120,height=95,inner_sea=true,size=continent_size},
            {key="6",width=vidblain.width,height=vidblain.height,zone=6,size=vidblain_size},
         }) do
            update_image(surface.key,surface,surface.size)
            grid_for(surface.key,surface)
         end
      end

      function state.view(uid,options)
         if not state.loaded then build_index() end
         local current=state.positions[uid]
         if not current then return end
         local definition=M.definitions[current.zone]
         local stitched=current.zone~=6
         local inner_sea=current.zone==5 and current.x<30 and current.y<10
         local surface={width=stitched and 120 or definition.width,height=stitched and 95 or definition.height,
            zone=not stitched and current.zone or nil,inner_sea=inner_sea}
         local x,y=current.x+(stitched and definition.x or 0),current.y+(stitched and definition.y or 0)
         local player_x,player_y=x,y
         -- Vidblain keeps a fixed projection as the player moves.
         if not stitched then x,y=(surface.width-1)/2,(surface.height-1)/2 end
         local key=stitched and (inner_sea and "inner_sea" or "stitched") or tostring(current.zone)
         local fit=options.stretch
         local size=fit and 9 or options.size
         local pitch,half=size-1,size/2
         local image,image_status=update_image(key,surface,size)
         local first_dx=stitched and -math.floor(surface.width/2) or -x
         local first_dy=stitched and -math.floor(surface.height/2) or -y
         local center_x,center_y=math.floor(options.width/2+options.pan_x-half)+half,
            math.floor(options.height/2+options.pan_y-half)+half
         local left,top=math.floor(center_x-half+first_dx*pitch),math.floor(center_y-half+first_dy*pitch)
         local mincol=math.max(0,math.ceil((half-center_x)/pitch-first_dx))
         local maxcol=math.min(surface.width-1,math.floor((options.width-half-center_x)/pitch-first_dx))
         local minrow=math.max(0,math.ceil((options.top+half-center_y)/pitch-first_dy))
         local maxrow=math.min(surface.height-1,math.floor((options.height-half-center_y)/pitch-first_dy))
         local scale,offset_x,offset_y=1,0,0
         local clip_left,clip_top,clip_right,clip_bottom=0,options.top,options.width,options.height
         if fit then
            local bounds=options.stretch_bounds
            local width,height=surface.width*pitch+1,surface.height*pitch+1
            -- Leave one pixel for rounded room edges at fractional scales.
            scale=math.max(0,math.min((bounds[3]-bounds[1]-1)/width,(bounds[4]-bounds[2]-1)/height))
            offset_x=bounds[1]+((bounds[3]-bounds[1])-width*scale)/2+options.pan_x
            offset_y=bounds[2]+((bounds[4]-bounds[2])-height*scale)/2+options.pan_y
            center_x,center_y=half-first_dx*pitch,half-first_dy*pitch
            mincol,maxcol,minrow,maxrow=0,surface.width-1,0,surface.height-1
            clip_left,clip_top,clip_right,clip_bottom=unpack(bounds)
         end
         local render_image=fit and scale>0 and scale_image(image,scale) or image
         local xs,ys,raster_x,raster_y
         local scale_x,scale_y=scale,scale
         local raster_width,raster_height=scale>0 and render_image.width or 0,scale>0 and render_image.height or 0
         local source_column,source_row=(x+first_dx)%surface.width,(y+first_dy)%surface.height
         if fit then
            xs,offset_x,scale_x,raster_x=fit_axis(offset_x,source_column*pitch,surface.width*pitch,
               raster_width,clip_left,clip_right)
            ys,offset_y,scale_y,raster_y=fit_axis(offset_y,source_row*pitch,surface.height*pitch,
               raster_height,clip_top,clip_bottom)
         else
            xs=split_axis(left,((x+first_dx)%surface.width)*pitch,surface.width*pitch,
               clip_left,clip_right,1)
            ys=split_axis(top,((y+first_dy)%surface.height)*pitch,surface.height*pitch,
               clip_top,clip_bottom,image.copies_y)
         end
         local rectangles={}
         for _,sy in ipairs(ys) do for _,sx in ipairs(xs) do
            rectangles[#rectangles+1]={sx.left,sy.left,sx.left+sx.length,sy.left+sy.length,1,
               sx.source,sy.source,sx.source+sx.length,sy.source+sy.length}
         end end
         local display_size=size*scale
         -- Clip the regular grid once per axis, rather than once per cell.
         local function edge(origin,first,index,pixels,period)
            return origin+math.floor((first+index)*pixels/period)
         end
         if fit then
            while mincol<=maxcol and edge(raster_x,source_column,mincol,raster_width,surface.width)+display_size<=clip_left do mincol=mincol+1 end
            while mincol<=maxcol and edge(raster_x,source_column,maxcol,raster_width,surface.width)>=clip_right do maxcol=maxcol-1 end
            while minrow<=maxrow and edge(raster_y,source_row,minrow,raster_height,surface.height)+display_size<=clip_top do minrow=minrow+1 end
            while minrow<=maxrow and edge(raster_y,source_row,maxrow,raster_height,surface.height)>=clip_bottom do maxrow=maxrow-1 end
         end
         local columns,rows=math.max(0,maxcol-mincol+1),math.max(0,maxrow-minrow+1)
         if columns==0 or rows==0 then columns,rows=0,0 end
         local grid=grid_for(key,surface)
         local base_left=math.floor(center_x-half+(first_dx+mincol)*pitch)
         local base_top=math.floor(center_y-half+(first_dy+minrow)*pitch)
         local view={cell=view_cell,grid=grid.rows,grid_width=surface.width,grid_height=surface.height,
            source_x=(x+first_dx+mincol)%surface.width,source_y=(y+first_dy+minrow)%surface.height,
            columns=columns,rows=rows,cell_count=columns*rows,room_count=0,overlays={},
            base_left=base_left,base_top=base_top,base_pitch=pitch,
            size=display_size,pitch=pitch*scale,pitch_x=pitch*scale_x,pitch_y=pitch*scale_y}
         if fit and view.cell_count>0 then
            view.origin_x,view.origin_y=offset_x+base_left*scale_x,offset_y+base_top*scale_y
            view.raster_x=raster_x+math.floor((source_column+mincol)/surface.width)*raster_width
            view.raster_y=raster_y+math.floor((source_row+minrow)/surface.height)*raster_height
            view.raster_width,view.raster_height=raster_width,raster_height
         end
         local primary=grid.rows[player_y+1].cells[player_x+1]
         if primary.uid~=uid then
            view.current_source,view.current_cell=primary,cell(current.zone,current.x,current.y,uid)
         end
         local first_end=math.min(surface.width,view.source_x+columns)
         local wrapped_end=math.max(0,view.source_x+columns-surface.width)
         for row=0,rows-1 do
            local line=grid.rows[(view.source_y+row)%surface.height+1]
            view.room_count=view.room_count+line.counts[first_end]-line.counts[view.source_x]+line.counts[wrapped_end]
            -- Preserve left-to-right drawing order on either side of the wrap.
            for segment=1,2 do
               local first,last=segment==1 and view.source_x or 0,segment==1 and first_end or wrapped_end
               for _,column in ipairs(line.overlays) do
                  if column>=first and column<last then
                     view.overlays[#view.overlays+1]=view:cell((column-view.source_x)%surface.width,row)
                  end
               end
            end
         end
         if view.cell_count>0 then
            local first,last=view:cell(0,0),view:cell(columns-1,rows-1)
            view.left,view.top=first.left,first.top
            view.bounds={first.left+display_size/2,first.top+display_size/2,
               last.left+display_size/2,last.top+display_size/2}
         end
         local player_center_x=math.floor(center_x-half+(player_x-x)*pitch)+half
         local player_center_y=math.floor(center_y-half+(player_y-y)*pitch)+half
         local inner_sea_bounds
         if inner_sea then
            local sea_left=player_center_x-half-current.x*pitch
            local sea_top=player_center_y-half-current.y*pitch
            inner_sea_bounds={sea_left,sea_top,sea_left+30*pitch,sea_top+10*pitch}
            if fit then
               inner_sea_bounds={edge(raster_x,source_column,inner_sea_bounds[1]/pitch,raster_width,surface.width),
                  edge(raster_y,source_row,inner_sea_bounds[2]/pitch,raster_height,surface.height),
                  edge(raster_x,source_column,inner_sea_bounds[3]/pitch,raster_width,surface.width),
                  edge(raster_y,source_row,inner_sea_bounds[4]/pitch,raster_height,surface.height)}
            end
         end
         view.image,view.render_image,view.key,view.rectangles=image,render_image,key,rectangles
         view.inner_sea_bounds=inner_sea_bounds
         view.center_x,view.center_y=player_center_x,player_center_y
         if fit then
            view.center_x=edge(raster_x,source_column,player_x-x-first_dx,raster_width,surface.width)+display_size/2
            view.center_y=edge(raster_y,source_row,player_y-y-first_dy,raster_height,surface.height)+display_size/2
         end
         view.image_status=image_status
         return view
      end

      local installed

      function state.install_image(view,target)
         local image=view.render_image
         if not installed or installed.target~=target or installed.image~=image or installed.version~=image.version
               or api.WindowImageInfo(target,"continent_surface",1)==nil then
            check(api.WindowImageFromWindow(target,"continent_surface",image.window))
            installed={target=target,image=image,version=image.version}
         end
      end

      function state.close()
         for _,image in pairs(state.images) do
            check(api.WindowDelete(image.window))
            if image.scaled then check(api.WindowDelete(image.scaled.window)) end
         end
         state.images={}
         installed=nil
      end

      return state
   end

   continent_maps = M
end

local function snap_continent_room_size(size)
   return math.max(5, math.min(25, math.floor((size-1)/4+0.5)*4+1))
end

function cancel_draw()
   drawing.job = nil
end

-- Record every map primitive with all its arguments. Reuse the captured map
-- only when the complete drawing sequence and background are unchanged.
local function record_map_command(name, ...)
   local index = map_command_state.count + 1
   local command = frame_commands[index]
   if not command then
      command = {}
      frame_commands[index] = command
   end
   local old_count = command.count or 0
   local count = select("#", ...)
   -- All current primitives fit in eleven arguments. Assign them directly
   -- to avoid a select() call for each argument. Keep larger calls supported.
   command[1], command[2], command[3], command[4], command[5], command[6],
      command[7], command[8], command[9], command[10], command[11] = ...
   for i = 12, count do command[i] = select(i, ...) end
   if old_count > count and old_count > 11 then
      local first = count + 1
      if first < 12 then first = 12 end
      for i = first, old_count do command[i] = nil end
   end
   command.name, command.count = name, count
   -- One difference already requires rebuilding the complete map. Continue
   -- recording its commands, but stop comparing against the previous frame.
   if not frame_commands_changed then
      local previous = completed_frame_cache and completed_frame_cache.commands[index]
      local same = previous and previous.name == name and previous.count == count
      if same then
         for i = 1, count do
            if previous[i] ~= command[i] then same = false; break end
         end
      end
      if not same then frame_commands_changed = true end
   end
   map_command_state.count = index
end

local function ensure_control_hotspot(id, left, top, right, bottom, mouseup, tooltip, cursor)
   local cached = control_hotspots[id]
   if cached and WindowHotspotInfo(win, id, 1) ~= nil and cached.left == left and cached.top == top
         and cached.right == right and cached.bottom == bottom and cached.mouseup == mouseup
         and cached.tooltip == tooltip and cached.cursor == cursor then return end
   check(WindowAddHotspot(win, id, left, top, right, bottom,
      "", "", "", "", mouseup, tooltip, cursor, 0))
   control_hotspots[id] = {left=left, top=top, right=right, bottom=bottom,
      mouseup=mouseup, tooltip=tooltip, cursor=cursor}
end

local function add_room_target(view, id, uid, x, y, tooltip, room_index)
   local column = math.floor((x-view.origin_x)/view.pitch+0.5)
   local row = math.floor((y-view.origin_y)/view.pitch+0.5)
   local cells = view.cells[row]
   if not cells then cells={};view.cells[row]=cells end
   local cell = cells[column]
   if not cell then cell={};cells[column]=cell end
   cell[#cell+1] = {id=tostring(id), uid=uid, tooltip=tooltip, room_index=room_index,
      left=math.floor(x-view.half), top=math.floor(y-view.half),
      right=math.floor(x+view.half), bottom=math.floor(y+view.half)}
end

local function reset_room_queue(queue)
   local uid, x, y = queue.uid, queue.x, queue.y
   for i = 1, #uid do uid[i], x[i], y[i] = nil, nil, nil end
   queued_room_uids, queued_room_x, queued_room_y = uid, x, y
end


-- Measure Window calls made by both the mapper and the shared theme. These
-- wrappers exist only during a detailed refresh. Normal drawing uses the
-- original functions. Keep all return values, including nil, and restore the
-- functions before propagating an error.
local function with_window_timing(render_batch, request, enabled, callback_started)
   local originals = {}
   local previous_stats = window_call_stats
   if enabled ~= false then window_call_stats = {} end
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

   local ok, err = xpcall(function() render_batch(request) end, function(err)
      if type(err) == "string" then return debug.traceback(err, 2) end
      return err
   end)
   for name, original in pairs(originals) do
      rawset(_G, name, original.value)
   end
   window_call_stats = previous_stats
   -- A later title blink must not append commands to a failed frame.
   frame_commands = nil
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
      print(string.format("    %-10s %5i calls  %7.3f ms  (%4.1f%%)", name,
         group.calls, group.time * 1000, frame_time > 0 and group.time / frame_time * 100 or 0))
   end
   table.sort(calls, function(a, b)
      if a.time == b.time then return a.name < b.name end
      return a.time > b.time
   end)
   print("    Call                         Count  Total ms    Avg us    Max us")
   for _, stat in ipairs(calls) do
      print(string.format("    %-28s %5i  %8.3f  %8.3f  %8.3f", stat.name,
         stat.calls, stat.time * 1000, stat.time / stat.calls * 1000000, stat.max * 1000000))
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

local function update_room_geometry ()

   HALF_ROOM   = math.ceil(ROOM_SIZE / 2)
   local THIRD_WAY   = math.ceil(DISTANCE_TO_NEXT_ROOM / 3)
   local HALF_WAY = math.ceil(DISTANCE_TO_NEXT_ROOM / 2)

   -- how to draw a line from this room to the next one (relative to the center of the room)
   connectors = {
      n =  { x1 = 0,            y1 = - HALF_ROOM, x2 = 0,                             y2 = - HALF_ROOM - HALF_WAY, at = { 0, -1 } },
      s =  { x1 = 0,            y1 =   HALF_ROOM, x2 = 0,                             y2 =   HALF_ROOM + HALF_WAY, at = { 0,  1 } },
      e =  { x1 =   HALF_ROOM,  y1 = 0,           x2 =   HALF_ROOM + HALF_WAY,  y2 = 0,                            at = {  1,  0 }},
      w =  { x1 = - HALF_ROOM,  y1 = 0,           x2 = - HALF_ROOM - HALF_WAY,  y2 = 0,                            at = { -1,  0 }},

      u = { x1 =   HALF_ROOM,  y1 = - HALF_ROOM, x2 =   HALF_ROOM + HALF_WAY , y2 = - HALF_ROOM - HALF_WAY, at = { 1, -1 } },
      d = { x1 = - HALF_ROOM,  y1 =   HALF_ROOM, x2 = - HALF_ROOM - HALF_WAY , y2 =   HALF_ROOM + HALF_WAY, at = {-1,  1 } }
   }

   -- Connector offsets change only with the room size or spacing.
   local step = ROOM_SIZE + DISTANCE_TO_NEXT_ROOM
   for _, connector in pairs(connectors) do
      connector.dx, connector.dy = connector.at[1] * step, connector.at[2] * step
   end

   -- how to draw a stub line
   half_connectors = {
      n =  { x1 = 0,            y1 = - HALF_ROOM, x2 = 0,                        y2 = - HALF_ROOM - THIRD_WAY },
      s =  { x1 = 0,            y1 =   HALF_ROOM, x2 = 0,                        y2 =   HALF_ROOM + THIRD_WAY },
      e =  { x1 =   HALF_ROOM,  y1 = 0,           x2 =   HALF_ROOM + THIRD_WAY,  y2 = 0},
      w =  { x1 = - HALF_ROOM,  y1 = 0,           x2 = - HALF_ROOM - THIRD_WAY,  y2 = 0},

      u = { x1 =   HALF_ROOM,  y1 = - HALF_ROOM, x2 =   HALF_ROOM + THIRD_WAY , y2 = - HALF_ROOM - THIRD_WAY },
      d = { x1 = - HALF_ROOM,  y1 =   HALF_ROOM, x2 = - HALF_ROOM - THIRD_WAY , y2 =   HALF_ROOM + THIRD_WAY }
   }

   -- how to draw one-way arrows (relative to the center of the room)
   arrows = {
      n =  { - 2, - HALF_ROOM - 2,  2, - HALF_ROOM - 2,  0, - HALF_ROOM - 6 },
      s =  { - 2,   HALF_ROOM + 2,  2,   HALF_ROOM + 2,  0,   HALF_ROOM + 6  },
      e =  {   HALF_ROOM + 2, -2,   HALF_ROOM + 2, 2,   HALF_ROOM + 6, 0 },
      w =  { - HALF_ROOM - 2, -2, - HALF_ROOM - 2, 2, - HALF_ROOM - 6, 0 },

      u = {   HALF_ROOM + 3,  - HALF_ROOM,  HALF_ROOM + 3, - HALF_ROOM - 3,  HALF_ROOM, - HALF_ROOM - 3 },
      d = { - HALF_ROOM - 3,    HALF_ROOM,  - HALF_ROOM - 3,   HALF_ROOM + 3,  - HALF_ROOM,   HALF_ROOM + 3}
   }
end

-- Stored spacing is relative to ROOM_SIZE. Account for the rounded box
-- bounds and the unbordered fill edge when room edges meet.
local function minimum_area_spacing(size)
   return 2 * math.ceil(size / 2) - size - (config.SHOW_ROOM_BORDERS and 0 or 1)
end

local function layout_for_room(room)
   if not room or room.continent ~= true then return room_layout.area end
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
      layout.size = snap_continent_room_size(layout.size)
   end
   local spacing = room_layout.current_is_continent and -1 or layout.spacing
   if ROOM_SIZE ~= layout.size or DISTANCE_TO_NEXT_ROOM ~= spacing then
      ROOM_SIZE, DISTANCE_TO_NEXT_ROOM = layout.size, spacing
      update_room_geometry()
   end
end

local function get_room (uid, traversal_only)
   local prepare_display = not traversal_only
   local db_t0 = detailed_timing and utils.timer()
   local room = callbacks.get_room (uid, traversal_only)
   room = room or { unknown = true }
   if db_t0 then
      frame_metrics.total_room_db_time = frame_metrics.total_room_db_time + (utils.timer() - db_t0)
   end

   local def_t0 = detailed_timing and utils.timer()
   room.name = room.name or string.format ("Room %s", uid)
   room.name = strip_colours (room.name)  -- no colour codes for now
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
      room.texture = room.texture or nil -- no texture
   else
      room.mapper_needs_display = true
   end
   if def_t0 then
      frame_metrics.total_room_defaults_time = frame_metrics.total_room_defaults_time + (utils.timer() - def_t0)
   end

   if prepare_display then
      room.textimage = nil

      local tex_t0 = detailed_timing and utils.timer()
      if room.texture == nil or room.texture == "" then room.texture = "test5.png" end
      if texture_image_cache[room.texture] then
         room.textimage = texture_image_cache[room.texture] -- assign image
      else
         if texture_image_cache[room.texture] ~= false then
            local dir = GetInfo(66)
            local imgpath = dir .. "worlds\\plugins\\images\\" ..room.texture
            if WindowLoadImage(win, room.texture, imgpath) ~= 0 then
               texture_image_cache[room.texture] = false  -- just indicates not found
            else
               -- Load both windows together; the file may be unavailable on a later redraw.
               check(WindowLoadImage(offscreen_window, room.texture, imgpath))
               texture_image_cache[room.texture] = room.texture -- imagename
               room.textimage = room.texture
            end
         end
      end
      if tex_t0 then
         frame_metrics.total_room_texture_time = frame_metrics.total_room_texture_time + (utils.timer() - tex_t0)
      end

   end

   if db_t0 then
      frame_metrics.total_get_room_time = frame_metrics.total_get_room_time + (utils.timer() - db_t0)
      frame_metrics.room_load_count = frame_metrics.room_load_count + 1
   end
   return room

end

local function get_display_room(uid)
   local room = display_room_cache[uid]
   if not room or room.mapper_needs_display then
      room = get_room(uid)
      display_room_cache[uid] = room
   end
   return room
end

local function make_number_checker (title, min, max)
   return function (s)
      local n = tonumber (s)
      if not n then
         utils.msgbox (title .. " must be a number", "Incorrect input", "ok", "!", 1)
         return false  -- bad input
      end
      if n < min or n > max then
         utils.msgbox (title .. " must be in range " .. min .. " to " .. max, "Incorrect input", "ok", "!", 1)
         return false  -- bad input
      end
      if string.match (s, "%.") then
         utils.msgbox (title .. " cannot have decimal places", "Incorrect input", "ok", "!", 1)
         return false  -- bad input
      end
      return true  -- good input
   end
end


local function get_number_from_user (msg, title, current, min, max)
   local max_length = math.ceil (math.log10 (max) + 1)

   return tonumber (utils.inputbox (msg, title, current, nil, nil,
      { validate = make_number_checker (title, min, max),
         prompt_height = 14,
         box_height = 130,
         box_width = 300,
         reply_width = 150,
         max_length = max_length,
      }  -- end extra stuff
   ))
end

local function draw_configuration ()
   local GAP = 5
   local title = "Map Configuration"

   local function on_off(value) return value and "On" or "Off" end

   local area = room_layout.area
   local area_spacing = math.max(0, area.spacing - minimum_area_spacing(area.size))
   local rows = {
      {label="Area scan depth", value=config.SCAN.depth, id="depth", right_padding=GAP,
         callback="mapper.mouseup_change_depth", tooltip="Click to change the ordinary-area scan depth"},
      {label="Font", value=config.FONT.name .. " " .. config.FONT.size, id="font", left_align=true, right_padding=GAP,
         callback="mapper.mouseup_change_font", tooltip="Click to change font"},
      {label="Area Textures", value=on_off(config.USE_TEXTURES.enabled), id="area_textures", right_padding=GAP,
         callback="mapper.mouseup_change_area_textures", tooltip="Click to toggle use of area textures"},
      {label="Show Room ID", value=on_off(config.SHOW_ROOM_ID), id="room_id", right_padding=GAP,
         callback="mapper.mouseup_change_show_id", tooltip="Click to toggle display of room UID"},
      {label="Area room size", layout="area", property="size",
         decrease="mapper.smaller_rooms", increase="mapper.bigger_rooms"},
      {label="Area room spacing", layout="area", property="spacing", value=area_spacing,
         decrease="mapper.denser", increase="mapper.sparser"},
      {label="Stretch continents to fit", value=on_off(room_layout.continent.stretch), id="continent_stretch",
         callback="mapper.mouseup_change_stretch", tooltip="Click to fit surface continents to the mapper window"},
      {label="Continent room size", layout="continent", property="size", disabled=room_layout.continent.stretch,
         decrease="mapper.smaller_rooms", increase="mapper.bigger_rooms"},
      {label="Stretch Vidblain to fit", value=on_off(room_layout.vidblain.stretch), id="vidblain_stretch",
         callback="mapper.mouseup_change_stretch", tooltip="Click to fit Vidblain to the mapper window"},
      {label="Vidblain room size", layout="vidblain", property="size", disabled=room_layout.vidblain.stretch,
         decrease="mapper.smaller_rooms", increase="mapper.bigger_rooms"},
      {label="Ordinary Room Borders", value=on_off(config.SHOW_ROOM_BORDERS), id="room_borders",
         callback="mapper.mouseup_change_room_borders", tooltip="Toggle ordinary borders; keep current-room and PK borders and special markings"},
      {label="Blink Name in PK Rooms", value=on_off(config.BLINK_PK_TITLE), id="blink_pk_rooms", right_padding=GAP,
         callback="mapper.mouseup_change_blink_pk_title", tooltip="Click to toggle title blinking in PK rooms"},
      {label="Mousewheel Zoom", value=on_off(config.MOUSEWHEEL_ZOOM), id="mousewheel_zoom",
         callback="mapper.mouseup_change_mousewheel_zoom", tooltip="Click to toggle mousewheel zoom"},
   }
   local config_entries = {title}
   local width = 0
   for _, row in ipairs(rows) do
      row.text = row.layout and row.label .. " (" .. (row.value or room_layout[row.layout][row.property]) .. ")" or row.label
      config_entries[#config_entries+1] = row.text
      if row.layout and row.layout~="area" and row.property=="size" then
         -- Reserve the widest supported value so zooming does not move the controls.
         for size=5,25,4 do
            width=math.max(width,WindowTextWidth(config_window,CONFIG_FONT_ID,row.label.." ("..size..")",true))
         end
      end
   end
   width = math.max(width,max_text_width(config_window, CONFIG_FONT_ID, config_entries, true))
   local row_height = font_height + GAP
   local frame_height = row_height * #config_entries + GAP

   local x = 0
   local y = 0
   local box_size = font_height - 2
   local rh_size = math.max (box_size, max_text_width (config_window, CONFIG_FONT_ID,
      {config.FONT.name .. " " .. config.FONT.size,
      ((config.USE_TEXTURES.enabled and "On") or "Off"),
      "- +",
      tostring (config.SCAN.depth)},
      true))
   local frame_width = GAP + width + GAP + rh_size + GAP  -- gap / text / gap / box / gap

   WindowCreate(config_window, windowinfo.window_left, windowinfo.window_top, frame_width, frame_height, windowinfo.window_mode, windowinfo.window_flags, 0xDCDCDC)
   WindowSetZOrder(config_window, 99999) -- always on top

   draw_3d_box (config_window, 0, 0, frame_width, frame_height)

   y = y + GAP
   x = x + GAP

   WindowText (config_window, CONFIG_FONT_ID, title, ((frame_width-WindowTextWidth(config_window,CONFIG_FONT_ID,title))/2), y, 0, 0, 0x808080)

   WindowRectOp (config_window,
      miniwin.rect_frame,
      x,
      y + 1,
      x + box_size,
      y + 1 + box_size,
      0x808080)
   WindowLine (config_window,
      x + 3,
      y + 4,
      x + box_size - 3,
      y - 2 + box_size,
      0x808080,
      miniwin.pen_solid, 1)
   WindowLine (config_window,
      x + box_size - 4,
      y + 4,
      x + 2,
      y - 2 + box_size,
      0x808080,
      miniwin.pen_solid, 1)

   WindowAddHotspot(config_window, "$<close_configure>",
      x,
      y + 1,
      x + box_size,
      y + 1 + box_size,    -- rectangle
      "", "", "", "", "mapper.mouseup_close_configure",  -- mouseup
      "Click to close",
      miniwin.cursor_hand, 0)  -- hand cursor

   y = y + row_height

   for _, row in ipairs(rows) do
      WindowText(config_window, CONFIG_FONT_ID, row.text, x, y, 0, 0, row.disabled and 0x808080 or 0x000000)
      if row.layout then
         local down_x = width + rh_size / 2 + box_size/2 - WindowTextWidth(config_window, CONFIG_FONT_ID, "-")
         local up_x = width + rh_size / 2 + box_size + GAP
         local id = "$<" .. row.layout .. "_" .. row.property
         local font = row.disabled and CONFIG_FONT_ID or CONFIG_FONT_ID_UL
         local colour = row.disabled and 0xB0B0B0 or 0x808080
         WindowText(config_window, font, "-", down_x, y, 0, 0, colour)
         WindowText(config_window, font, "+", up_x, y, 0, 0, colour)
         if not row.disabled then
            WindowAddHotspot(config_window, id .. "_down>",
               down_x, y, down_x + box_size, y + font_height,
               "", "", "", "", row.decrease, "Decrease " .. row.label, miniwin.cursor_hand, 0)
            WindowAddHotspot(config_window, id .. "_up>",
               up_x, y, up_x + WindowTextWidth(config_window, CONFIG_FONT_ID, "+"), y + font_height,
               "", "", "", "", row.increase, "Increase " .. row.label, miniwin.cursor_hand, 0)
         else
            WindowDeleteHotspot(config_window, id .. "_down>")
            WindowDeleteHotspot(config_window, id .. "_up>")
         end
      else
         local value_x = x + width + GAP
         if not row.left_align then
            value_x = width + rh_size / 2 + box_size - WindowTextWidth(config_window, CONFIG_FONT_ID_UL, row.value)/2
         end
         WindowText(config_window, CONFIG_FONT_ID_UL, tostring(row.value), value_x, y, 0, 0, 0x808080)
         WindowAddHotspot(config_window, "$<" .. row.id .. ">",
            x + GAP, y, frame_width + (row.right_padding or 0), y + font_height,
            "", "", "", "", row.callback, row.tooltip, miniwin.cursor_hand, 0)
      end
      y = y + row_height
   end

   WindowShow(config_window, true)
end

-- Look ahead only within the discovered breadth layer. Queued rooms already
-- have their exits, since drawing their parents loaded them. Do not traverse
-- another layer here or change the order in which rooms are drawn.
local function prefetch_exit_destinations(job)
   local ids, seen = {}, {}
   local level = job.level.uid
   -- Limit cache inspection as well as database reads. Most queued rooms may be cached.
   for i = job.index, math.min(job.index + ROOM_PREFETCH_SCAN_LIMIT - 1, #level) do
      local uid = level[i]
      local room = display_room_cache[uid]
      if room and
            (not room_layout.current_is_continent or
               (job.level.x[i] >= job.boundary_left and job.level.y[i] >= job.boundary_top and
                job.level.x[i] <= job.boundary_right and job.level.y[i] <= job.boundary_bottom)) then
         for dir, exit_uid in pairs(room.exits) do
            if connectors[dir] and not display_room_cache[exit_uid]
                  and not job.prefetched[exit_uid] and not seen[exit_uid] then
               ids[#ids + 1] = exit_uid
               seen[exit_uid] = true
               if #ids == ROOM_PREFETCH_BATCH_SIZE then break end
            end
         end
      end
      if #ids == ROOM_PREFETCH_BATCH_SIZE then break end
   end
   if #ids == 0 then return end
   local start = detailed_timing and utils.timer()
   callbacks.prefetch_rooms(ids)
   if start then
      frame_metrics.total_room_prefetch_time = frame_metrics.total_room_prefetch_time + utils.timer() - start
      frame_metrics.room_prefetch_count = frame_metrics.room_prefetch_count + 1
   end
   for _, uid in ipairs(ids) do job.prefetched[uid] = true end
end

local function draw_room (uid, x, y)
   local room_start_time = nil
   if detailed_timing then
      room_start_time = utils.timer()
   end

   local coords = math.floor (x) * 100000 + math.floor (y)

   -- Reserve the room's position before checking exits that can loop back to it.
   occupied_room_positions [coords] = uid
   processed_room_positions [uid] = coords

   -- Ordinary areas traverse off-screen paths. Continents stop at the search bounds.
   local on_screen = not ((x < HALF_ROOM) or (y < font_height+HALF_ROOM) or
      (x > config.WINDOW.width - HALF_ROOM) or (y > config.WINDOW.height - HALF_ROOM))
   local job = drawing.job
   job.room_indices[uid] = #job.room_ends + 1
   if room_layout.current_is_continent and
         (x < job.boundary_left or y < job.boundary_top or
          x > job.boundary_right or y > job.boundary_bottom) then
      if room_start_time then
         table.insert(room_draw_times, utils.timer() - room_start_time)
         rooms_drawn_count = rooms_drawn_count + 1
      end
      return
   end
   local room = display_room_cache [uid]

   -- Prepare display data when the room first becomes visible.
   if not room or (on_screen and room.mapper_needs_display) then
      room = get_room (uid, not on_screen)
      display_room_cache [uid] = room
      if detailed_timing then room_cache_misses = room_cache_misses + 1 end
   else
      if detailed_timing then room_cache_hits = room_cache_hits + 1 end
   end -- not in cache


   local left, top, right, bottom = x - HALF_ROOM, y - HALF_ROOM, x + HALF_ROOM, y + HALF_ROOM

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

   local exit_start_time = nil
   local exit_draw_accum = 0
   if detailed_timing then
      exit_start_time = utils.timer()
   end

   local draw_exits = on_screen and DISTANCE_TO_NEXT_ROOM >= 4

   for _, dir in ipairs(exit_order) do
      local exit_uid = room.exits[dir]
      local exit_info = connectors [dir]
      local stub_exit_info = half_connectors [dir]
      local locked_exit, exit_line_colour
      -- Exit styles are only used when spacing permits a visible line.
      if draw_exits then
         locked_exit = not (room.exit_locks == nil or room.exit_locks[dir] == nil or room.exit_locks[dir] == "0")
         exit_line_colour = (locked_exit and 0x0000FF) or styles.EXIT_COLOUR.colour
         if dir == "u" or dir == "d" then
            exit_line_colour = (locked_exit and 0x0000FF) or styles.EXIT_COLOUR_UP_DOWN.colour
         end
      end

      if exit_uid ~= nil then
         local linetype = miniwin.pen_solid -- unbroken
         local linewidth = (locked_exit and 2) or 1 -- not recent

         -- try to cache room
         local dest = display_room_cache[exit_uid]
         if not dest then
            local job = drawing.job
            if not job.prefetched[exit_uid] then
               prefetch_exit_destinations(job)
            end
            local cache_t0 = detailed_timing and utils.timer()
            dest = get_room (exit_uid, true)
            display_room_cache[exit_uid] = dest
            if cache_t0 then
               frame_metrics.total_room_cache_time = frame_metrics.total_room_cache_time + (utils.timer() - cache_t0)
               room_cache_misses = room_cache_misses + 1
            end
         else
            if detailed_timing then room_cache_hits = room_cache_hits + 1 end
         end

         if draw_exits and dest.unknown then
            linetype = miniwin.pen_dot -- dots
         end

         local next_x = x + exit_info.dx
         local next_y = y + exit_info.dy

         local next_coords = math.floor (next_x) * 100000 + math.floor (next_y)

         -- Keep every area exit in traversal order, including shared destinations.
         if room.area ~= dest.area and not dest.unknown
               and not (room.continent and dest.continent)
               and (show_up_down or (dir ~= "u" and dir ~= "d")) then
            area_exits[#area_exits + 1] = {uid = exit_uid,
               room_x = next_x, room_y = next_y, room_coords = next_coords}
            drawing.job.overlay_changed = true
         end

         -- Preserve placement precedence: occupied cell, self-exit, area limit,
         -- then conflicting first placement.
         if occupied_room_positions[next_coords] and occupied_room_positions[next_coords] ~= exit_uid then
            exit_info = stub_exit_info
         elseif exit_uid == uid then
            exit_info = stub_exit_info
            linetype = miniwin.pen_dash
         elseif (dest.area ~= map_area_name and not dest.unknown
               and not (room_layout.current_is_continent and dest.continent)) or
               (not show_up_down and (dir == "u" or dir == "d")) then
            exit_info = stub_exit_info
         elseif planned_room_positions[exit_uid] and planned_room_positions[exit_uid] ~= next_coords then
            exit_info = stub_exit_info
            linetype = miniwin.pen_dash
         else
            if not planned_room_positions[exit_uid] and not processed_room_positions[exit_uid] then
               local n = #queued_room_uids + 1
               queued_room_uids[n] = exit_uid
               queued_room_x[n] = next_x
               queued_room_y[n] = next_y
            end
            occupied_room_positions[next_coords] = exit_uid
            planned_room_positions[exit_uid] = next_coords

            if draw_exits and not dest.unknown then
               local exit_time = room_visit_times[exit_uid] or 0
               local this_time = room_visit_times[uid] or 0
               if exit_time > (frame_timestamp - RECENT_VISIT_SECONDS) and
                  this_time > (frame_timestamp - RECENT_VISIT_SECONDS) then
                  linewidth = 2
               end
            end
         end

         -- Dense maps still traverse every exit; there is no space for exit lines or arrows.
         if draw_exits then
            local draw_t0 = detailed_timing and utils.timer()
            record_map_command("WindowLine", win, x + exit_info.x1, y + exit_info.y1, x + exit_info.x2, y + exit_info.y2, exit_line_colour, linetype + 0x0200, linewidth)

            -- one-way exit?

            if not dest.unknown then
               -- if inverse direction doesn't point back to us, this is one-way
               if dest.exits [inverse_direction [dir]] ~= uid then
                  local arrow = arrows [dir]
                  -- turn points into string, relative to where the room is
                  local points = string.format ("%i,%i,%i,%i,%i,%i",
                     x + arrow [1],
                     y + arrow [2],
                     x + arrow [3],
                     y + arrow [4],
                     x + arrow [5],
                     y + arrow [6])

                  -- draw arrow
                  record_map_command("WindowPolygon", win, points,
                     exit_line_colour, miniwin.pen_solid, 1,
                     exit_line_colour, miniwin.brush_solid,
                     true, true)
               end -- one way
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
      if room_start_time then
         table.insert(room_draw_times, utils.timer() - room_start_time)
         rooms_drawn_count = rooms_drawn_count + 1
      end
      return
   end
   if detailed_timing then frame_metrics.visible_room_count = frame_metrics.visible_room_count + 1 end

   local graphics_start_time = nil
   if detailed_timing then
      graphics_start_time = utils.timer()
   end

   local is_current_room = uid == map_origin_uid
   if is_current_room then
      -- Keep the border separate so later rooms and exit markers cannot cover it.
      map_command_state.border_room = room
      map_command_state.border_left, map_command_state.border_top = left, top
      map_command_state.border_right, map_command_state.border_bottom = right, bottom
   end

   if room.unknown then
      record_map_command("WindowCircleOp", win, miniwin.circle_rectangle, left, top, right, bottom,
         styles.UNKNOWN_ROOM_COLOUR.colour, is_current_room and miniwin.pen_null or miniwin.pen_dot,
         is_current_room and 0 or 1,
         0, miniwin.brush_hatch_forwards_diagonal)
   else
      local show_border = not is_current_room and (config.SHOW_ROOM_BORDERS
         or (room.info and string.match(room.info, "pk")))
      -- A solid fill and a one-pixel solid border can share one rectangle.
      -- Hatch and pattern brushes depend on the fill call's pen colour.
      local combined_fill = show_border and room.fillbrush == miniwin.brush_solid
         and room.borderpen == miniwin.pen_solid and room.borderpenwidth == 1
      -- A null pen and null brush cannot change any pixels.
      if room.fillbrush ~= miniwin.brush_null and not combined_fill then
         if room.fillbrush == miniwin.brush_solid and left < right and top < bottom
               and right >= 2 and bottom >= 2 then
            -- GDI's null-pen rectangle leaves an extra pixel at the right and bottom.
            record_map_command("WindowRectOp", win, 2, left, top, right - 1, bottom - 1, room.fillcolour)
         else
            record_map_command("WindowCircleOp", win, miniwin.circle_rectangle, left, top, right, bottom,
               0, miniwin.pen_null, 0,  -- no pen
               room.fillcolour, room.fillbrush)  -- brush
         end
      end

      -- room border, with the fill when both can share the same call
      if show_border then
         record_map_command("WindowCircleOp", win, miniwin.circle_rectangle, left, top, right, bottom,
            room.bordercolour, room.borderpen, room.borderpenwidth,
            combined_fill and room.fillcolour or -1, combined_fill and room.fillbrush or miniwin.brush_null)
      end

      -- mark rooms with notes
      if room.notes ~= nil and room.notes ~= "" then
         record_map_command("WindowCircleOp", win, miniwin.circle_rectangle, left-1-room.borderpenwidth, top-1-room.borderpenwidth,
            right+1+room.borderpenwidth, bottom+1+room.borderpenwidth,styles.ROOM_NOTE_COLOUR.colour,
            room.borderpen, room.borderpenwidth,-1,miniwin.brush_null)
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

   add_room_target(job.room_view, uid, uid, x, y, room.hovermessage, #job.room_ends+1)

   if detailed_timing and hotspot_start_time then
      frame_metrics.total_hotspot_time = frame_metrics.total_hotspot_time + (utils.timer() - hotspot_start_time)
   end

   if detailed_timing and room_start_time then
      local room_time = utils.timer() - room_start_time
      table.insert(room_draw_times, room_time)
      rooms_drawn_count = rooms_drawn_count + 1
   end
end

local function area_exit_room_bounds(exit, room_limit)
   local occupant = occupied_room_positions[exit.room_coords]
   -- A queued room may be beyond the depth limit. Keep the area-exit marker
   -- until a room is drawn here.
   if occupant and processed_room_positions[occupant] == exit.room_coords
         and drawing.job.room_indices[occupant] <= room_limit then return end
   local x, y = exit.room_x, exit.room_y
   if x < HALF_ROOM or y < font_height + HALF_ROOM
         or x > config.WINDOW.width - HALF_ROOM or y > config.WINDOW.height - HALF_ROOM then return end
   return x - HALF_ROOM, y - HALF_ROOM, x + HALF_ROOM, y + HALF_ROOM
end

local function build_area_exit_targets(job)
   local view = {cells={}, origin_x=job.room_view.origin_x, origin_y=job.room_view.origin_y,
      pitch=job.room_view.pitch, half=job.room_view.half}
   for index, exit in ipairs(area_exits) do
      if exit.visible then
         local room = get_display_room(exit.uid)
         add_room_target(view, "zz_area_exit:"..index..":"..exit.uid, exit.uid,
            exit.room_x, exit.room_y, room.hovermessage, 0)
      end
   end
   return view.cells
end

-- Area boxes select known entry rooms or approach an unexplored entrance.
-- Other cells select their continent room.
drawing.continent_cell_target = function(cell, view)
   local entries,names
   if cell.entry_rooms and #cell.entry_rooms>0 then
      entries={}
      if #cell.entry_rooms>1 then names={} end
      for _,uid in ipairs(cell.entry_rooms) do
         local room=get_display_room(uid)
         entries[#entries+1]=uid
         if names then names[#names+1]=tostring(uid)..": "..strip_colours(room.name) end
      end
   end
   local uid,id,tooltip
   if entries and #entries>0 then
      uid=#entries==1 and entries[1] or nil
      id="0:continent_entry:"..cell.zone..":"..cell.x..":"..cell.y..":"..table.concat(entries,",")
      tooltip=uid and display_room_cache[uid].hovermessage or table.concat(names,"\n")
      if uid and display_room_cache[uid].unknown then tooltip=display_room_cache[uid].name.."\n"..tooltip end
   elseif cell.entrance_approaches then
      uid=cell.uid
      id="0:continent_unexplored:"..cell.zone..":"..cell.x..":"..cell.y
      tooltip="<Unexplored area entrance>"
   elseif cell.uid or cell.unexplored_uid then
      local cell_uid=cell.uid or cell.unexplored_uid
      local room=get_display_room(cell_uid)
      uid,id,tooltip=cell_uid,tostring(cell_uid),room.hovermessage
      if cell.unexplored_uid then tooltip=room.name.."\n"..tooltip end
   end
   if id then
      return {id=id,uid=uid,tooltip=tooltip,left=cell.left,top=cell.top,
         right=cell.left+view.size,bottom=cell.top+view.size,entry_rooms=entries,
         entrance_approaches=cell.entrance_approaches}
   end
end

drawing.continent_target = function(x, y)
   local view = drawing.continent_view
   if not view or not x or not y or view.cell_count == 0 then return end
   local size = view.size
   local pitch_x,pitch_y = view.pitch_x,view.pitch_y
   local column = math.floor((x-view.left)/pitch_x)
   local row = math.floor((y-view.top)/pitch_y)
   local mincol,minrow=column-1,row-1
   if view.raster_x then
      local width,height=view.raster_width,view.raster_height
      mincol=math.floor(((math.floor(x-size)+1-view.raster_x)*view.grid_width+width-1)/width)-view.source_x
      minrow=math.floor(((math.floor(y-size)+1-view.raster_y)*view.grid_height+height-1)/height)-view.source_y
      column=math.floor(((math.floor(x)+1-view.raster_x)*view.grid_width+width-1)/width)-1-view.source_x
      row=math.floor(((math.floor(y)+1-view.raster_y)*view.grid_height+height-1)/height)-1-view.source_y
   end
   local best
   for cy=minrow,row do for cx=mincol,column do
      if cx>=0 and cx<view.columns and cy>=0 and cy<view.rows then
         local cell = view:cell(cx,cy)
         local left, top = cell.left, cell.top
         if x>=left and x<left+size and y>=top and y<top+size then
            local target=drawing.continent_cell_target(cell,view)
            if target and (not best or target.id<best.id) then
               best=target
            end
         end
      end
   end end
   return best
end

drawing.map_target = function(x, y)
   if not x or not y then return end
   if drawing.continent_view then return drawing.continent_target(x, y) end
   local view = drawing.room_view
   if not view then return end
   local column = math.floor((x-view.origin_x)/view.pitch+0.5)
   local row = math.floor((y-view.origin_y)/view.pitch+0.5)
   local reach = math.ceil(view.half/view.pitch)
   local best
   for dy=-reach,reach do for dx=-reach,reach do
      for index=1,2 do
         local grid = index == 1 and view.cells or view.exits
         local cells = grid[row+dy]
         local cell = cells and cells[column+dx]
         if cell then for _, target in ipairs(cell) do
            if target.room_index <= view.room_limit and x >= target.left and x < target.right
                  and y >= target.top and y < target.bottom and (not best or target.id < best.id) then
               best = target
            end
         end end
      end
   end end
   return best
end

drawing.travel_target = function(x,y)
   if resize_dragging or not x or not y or not bodytop
         or x<bodyleft or x>=bodyright or y<bodytop or y>=bodybottom then return end
   local direct=drawing.map_target(x,y)
   if direct then return direct end
   local best,distance

   local function consider(target)
      if not target then return end
      local dx,dy=(target.left+target.right)/2-x,(target.top+target.bottom)/2-y
      local squared=dx*dx+dy*dy
      if not distance or squared<distance or squared==distance and target.id<best.id then
         best,distance=target,squared
      end
   end

   local view=drawing.continent_view
   if view then
      if view.cell_count==0 then return end
      local size=view.size
      local pitch_x,pitch_y=view.pitch_x,view.pitch_y
      local origin_x,origin_y=view.origin_x or view.left,view.origin_y or view.top
      local column=math.max(0,math.min(view.columns-1,math.floor((x-origin_x-size/2)/pitch_x+0.5)))
      local row=math.max(0,math.min(view.rows-1,math.floor((y-origin_y-size/2)/pitch_y+0.5)))
      local rounding=view.origin_x and 1 or 0

      local function axis_distance(center,pointer) return math.max(0,math.abs(center-pointer)-rounding)^2 end

      local nearest_dx=axis_distance(origin_x+column*pitch_x+size/2,x)
      local nearest_dy=axis_distance(origin_y+row*pitch_y+size/2,y)

      local function visit(cx,cy)
         if cx<0 or cx>=view.columns or cy<0 or cy>=view.rows then return end
         local cell=view:cell(cx,cy)
         if not (cell.uid or cell.unexplored_uid or cell.entry_rooms and #cell.entry_rooms>0) then return end
         local dx,dy=cell.left+size/2-x,cell.top+size/2-y
         if not distance or dx*dx+dy*dy<=distance then consider(drawing.continent_cell_target(cell,view)) end
      end

      for radius=0,math.max(view.columns,view.rows)-1 do
         if radius==0 then visit(column,row) else
            for cx=math.max(0,column-radius),math.min(view.columns-1,column+radius) do
               visit(cx,row-radius);visit(cx,row+radius)
            end
            for cy=math.max(0,row-radius+1),math.min(view.rows-1,row+radius-1) do
               visit(column-radius,cy);visit(column+radius,cy)
            end
         end
         local remaining=math.huge
         if column-radius>0 then remaining=math.min(remaining,axis_distance(origin_x+(column-radius-1)*pitch_x+size/2,x)+nearest_dy) end
         if column+radius<view.columns-1 then remaining=math.min(remaining,axis_distance(origin_x+(column+radius+1)*pitch_x+size/2,x)+nearest_dy) end
         if row-radius>0 then remaining=math.min(remaining,axis_distance(origin_y+(row-radius-1)*pitch_y+size/2,y)+nearest_dx) end
         if row+radius<view.rows-1 then remaining=math.min(remaining,axis_distance(origin_y+(row+radius+1)*pitch_y+size/2,y)+nearest_dx) end
         if distance and distance<remaining then break end
      end
   elseif drawing.room_view then
      view=drawing.room_view
      for _,grid in ipairs({view.cells,view.exits}) do
         for _,line in pairs(grid) do for _,cell in pairs(line) do for _,target in ipairs(cell) do
            if target.room_index<=view.room_limit then consider(target) end
         end end end
      end
   end
   return best
end

drawing.click_target = function(x,y,travel)
   if travel then return drawing.travel_target(x,y) end
   return drawing.map_target(x,y)
end

drawing.highlight_target = function(target,repaint)
   local region=drawing.map_region
   if is_running or pan_dragging or resize_dragging or region.down or region.outside or not region.frame_ready then target=nil end
   local old=region.highlight
   if drawing.same_map_target(old and old.target,target) then return end
   if old then
      check(WindowDrawImage(win,"cached_map",old.left,old.top,old.right,old.bottom,1,
         old.left,old.top,old.right,old.bottom))
      region.highlight=nil
   end
   if target then
      local left,top=math.max(bodyleft,target.left-2),math.max(bodytop,target.top-2)
      local right,bottom=math.min(bodyright,target.right+1),math.min(bodybottom,target.bottom+1)
      if left<right and top<bottom then
         check(WindowRectOp(win,1,left,top,right,bottom,ColourNameToRGB("white")))
         region.highlight={target=target,left=left,top=top,right=right,bottom=bottom}
      end
   end
   if repaint~=false and (old or region.highlight) then BufferedRepaint() end
end

drawing.same_map_target = function(a,b)
   if not a or not b then return a == b end
   return a.id == b.id and a.left == b.left and a.top == b.top
      and a.right == b.right and a.bottom == b.bottom and a.tooltip == b.tooltip
end

drawing.refresh_map_region = function(repaint)
   local region = drawing.map_region
   if region.down or region.updating or WindowInfo(win,1) == nil then return end
   local target = not region.outside and drawing.travel_target(WindowInfo(win,14),WindowInfo(win,15)) or nil
   local width,height = config.WINDOW.width,config.WINDOW.height
   local id = "zzz_zoom"
   local present = WindowHotspotInfo(win,id,1) ~= nil
   if present and region.width == width and region.height == height
         and drawing.same_map_target(region.target,target) then
      drawing.highlight_target(target,repaint)
      return
   end
   local tooltip = target and target.tooltip or pan_tooltip_text
   local cursor = target and miniwin.cursor_plus or miniwin.cursor_hand
   -- Replacing the same ID resets native hover state and the tooltip timer.
   -- Keep one hotspot for all room selection, background panning and zoom.
   region.updating = true
   check(WindowAddHotspot(win,id,0,0,width,height,
      "mapper.map_mouseover","mapper.map_cancel_mouseover","mapper.map_mousedown","mapper.map_cancel_mousedown",
      "mapper.map_mouseup",tooltip,cursor,miniwin.hotspot_report_all_mouseovers))
   check(WindowDragHandler(win,id,"mapper.map_dragmove","mapper.pan_dragrelease",0))
   check(WindowScrollwheelHandler(win,id,"mapper.zoom_map"))
   region.updating = false
   region.id,region.target,region.tooltip,region.width,region.height = id,target,tooltip,width,height
   drawing.highlight_target(target,repaint)
end

drawing.commit_map_view = function(continent_view, room_view)
   drawing.continent_view, drawing.room_view = continent_view, room_view
end

drawing.plan_continent = function(view)
   for _, rectangle in ipairs(view.rectangles) do
      record_map_command("WindowDrawImage", win, "continent_surface", unpack(rectangle))
   end
   if view.bounds then
      drawn_min_x, drawn_min_y, drawn_max_x, drawn_max_y = unpack(view.bounds)
   end
   if detailed_timing then
      rooms_drawn_count=rooms_drawn_count+view.room_count
      frame_metrics.visible_room_count=frame_metrics.visible_room_count+view.room_count
   end
   for _, cell in ipairs(view.overlays) do
      if cell.uid then
         local room=cell.room
         local pk,note,width,pen
         if room and cell.uid~=map_origin_uid then
            pk,note,width,pen=callbacks.get_continent_room_overlays(room)
         else
            room=get_display_room(cell.uid)
            pk,note,width,pen=room.mapper_pk_warning,room.mapper_note,room.borderpenwidth,room.borderpen
         end
         if pk then
            record_map_command("WindowCircleOp",win,miniwin.circle_rectangle,cell.left,cell.top,cell.left+view.size,cell.top+view.size,
               styles.PK_BORDER_COLOUR.colour,miniwin.pen_solid,3,0,miniwin.brush_null)
         end
         if note then
            record_map_command("WindowCircleOp",win,miniwin.circle_rectangle,cell.left-1-width,cell.top-1-width,cell.left+view.size+1+width,cell.top+view.size+1+width,
               styles.ROOM_NOTE_COLOUR.colour,pen,width,0,miniwin.brush_null)
         end
      end
   end
end

local function draw_map_overlays(room_limit)
   local view = drawing.job.continent_view
   if view then
      if view.size <= 0 then return end
      if view.inner_sea_bounds then
         local left,top,right,bottom = unpack(view.inner_sea_bounds)
         local colour = ColourNameToRGB("white")
         record_map_command("WindowLine",win,left,top,right,top,colour,miniwin.pen_solid,1)
         record_map_command("WindowLine",win,right,top,right,bottom,colour,miniwin.pen_solid,1)
         record_map_command("WindowLine",win,right,bottom,left,bottom,colour,miniwin.pen_solid,1)
         record_map_command("WindowLine",win,left,bottom,left,top,colour,miniwin.pen_solid,1)
      end
      local x,y,size = view.center_x,view.center_y,view.size
      if x+3*size-1>=1 and y+3*size>=1 and x-3*size<config.WINDOW.width and y-3*size-1<config.WINDOW.height then
         for _, pen in ipairs({{ColourNameToRGB("purple"),4},{ColourNameToRGB("magenta"),2}}) do
            record_map_command("WindowCircleOp",win,miniwin.circle_round_rectangle,
               x-3*size,y-3*size-1,x+3*size-1,y+3*size,
               pen[1],miniwin.pen_solid,pen[2],0,miniwin.brush_null,25,25)
         end
      end
      if x+size/2-1>=1 and y+size/2-1>=1 and x-size/2<config.WINDOW.width and y-size/2<config.WINDOW.height then
         record_map_command("WindowCircleOp",win,miniwin.circle_rectangle,
            x-size/2,y-size/2,x+size/2-1,y+size/2-1,
            ColourNameToRGB("magenta"),miniwin.pen_solid,2,0,miniwin.brush_null)
      end
      return
   end
   for _, exit in ipairs(area_exits) do
      local left, top, right, bottom = area_exit_room_bounds(exit, room_limit)
      local visible = left ~= nil
      if visible ~= exit.visible then
         drawing.job.overlay_changed = true
         exit.visible = visible
      end
      if visible then
         if left < right and top < bottom and right >= 2 and bottom >= 2 then
            record_map_command("WindowRectOp", win, 2, left, top, right - 1, bottom - 1, styles.AREA_EXIT_FILL_COLOUR.colour)
         else
            record_map_command("WindowCircleOp", win, miniwin.circle_rectangle, left, top, right, bottom,
               0, miniwin.pen_null, 0, styles.AREA_EXIT_FILL_COLOUR.colour, miniwin.brush_solid)
         end
      end
   end

   local room = map_command_state.border_room
   if room then
      record_map_command("WindowCircleOp", win, miniwin.circle_rectangle,
         map_command_state.border_left, map_command_state.border_top,
         map_command_state.border_right, map_command_state.border_bottom,
         room.unknown and styles.UNKNOWN_ROOM_COLOUR.colour or room.bordercolour,
         room.unknown and miniwin.pen_dot or room.borderpen,
         room.unknown and 1 or room.borderpenwidth, -1, miniwin.brush_null)
   end
end


-- Display queries and updates used by the plugin.

function displayed_room()
   return map_origin_uid
end

function room_info(uid)
   if not display_room_cache[uid] then display_room_cache[uid] = get_room(uid) end
   return display_room_cache[uid]
end

function set_running(run)
   run = run == true
   if is_running == run then return end
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

function blink_title(during_frame_render, target_window)
   local prev_title_color = title_color
   if not config.BLINK_PK_TITLE then
      title_color = "@R"
   else
      next_blink_color = (next_blink_color % (#blink_cycle)) + 1
      title_color = blink_cycle[next_blink_color]
   end
   if prev_title_color ~= title_color then
      if during_frame_render~=true then
         drawing.highlight_target(nil,false)
         drawing.map_region.frame_ready=false
      end
      draw_window_frame(truncated_room_name, map_origin_uid, map_area_name, target_window)
      if during_frame_render~=true then
         capture_map_image(win)
         drawing.map_region.frame_ready=true
         completed_frame_cache=nil
         drawing.refresh_map_region(false)
         BufferedRepaint()
      end
   end
end

local function fit_room_name(room_name)
   if room_title_cache and room_title_cache.room_name == room_name
      and room_title_cache.width == config.WINDOW.width
      and room_title_cache.font_name == config.FONT.name and room_title_cache.font_size == config.FONT.size then
      return room_title_cache.text
   end
   local truncated_room_name = room_name
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
   end

   if add_dots then
      truncated_room_name = truncated_room_name .. "..."
   end

   room_title_cache = {room_name = room_name, width = config.WINDOW.width,
      font_name = config.FONT.name, font_size = config.FONT.size, text = truncated_room_name}
   return truncated_room_name
end

function draw_window_frame(room_name, room_uid, area_name, target_window)
   target_window = target_window or win
   bodyleft, bodytop, bodyright, bodybottom = Theme.DrawBorder(target_window)
   bodytop = Theme.DrawTitleBar(target_window, FONT_ID, title_color..room_name, "center")
   Theme.AddDragHotspot(win, bodytop)

   if config.SHOW_ROOM_ID then
      if room_uid:sub(1,5) == "nomap" then
         room_uid = "NONE"
      end

      Theme.DrawTextBox(target_window, FONT_ID,
         (config.WINDOW.width - WindowTextWidth (win, FONT_ID, "ID: "..room_uid)) / 2,   -- left
         bodytop,    -- top
         "ID: "..room_uid, false, false
      )
   end

   Theme.DrawTextBox(target_window, FONT_ID,
      (config.WINDOW.width - WindowTextWidth (win, FONT_ID, area_name)) / 2,   -- left
      config.WINDOW.height - 4 - font_height,    -- top
      area_name:gsub("^%l", string.upper), false, false
   )

   local x = config.WINDOW.width - WindowTextWidth (win, FONT_ID, "?") - 6
   local y = math.max(2, (bodytop-font_height)/2)
   local box_right = Theme.DrawTextBox(target_window, FONT_ID,
      x-1,   -- left
      y-2,   -- top
      "?", false, false
   )
   local box_width = box_right - (x-1)

   if not pan_dragging then
      ensure_control_hotspot("<help>", x-3, y-4, x+box_width+3, y + font_height,
         "mapper.show_help", "Click for help", miniwin.cursor_help)
   end

   if config_panel_open then
      WindowDeleteHotspot(win, "<configure>")
      control_hotspots["<configure>"] = nil
      -- dropdown
      draw_configuration ()
   else
      -- button
      WindowShow(config_window, false)
      local x = 2
      local y = math.max(2, (bodytop-font_height)/2)
      local text_width = Theme.DrawTextBox(target_window, FONT_ID,
         x,   -- left
         y-2,   -- top
         "*", false, false)

      if not pan_dragging then
         ensure_control_hotspot("<configure>", x-2, y-4, x+text_width, y + font_height,
            "mapper.mouseup_configure", "Click to configure map", miniwin.cursor_plus)
      end
   end
end

-- Redraw the frame controls for each batch, but start the PK blink timer only once.
local function draw_frame_controls(job, target_window)
   local uid, room = job.uid, job.room
   local dress_t0 = detailed_timing and utils.timer()
   if job.dressed then
      -- Keep the current PK blink phase and its timer across batches.
      draw_window_frame(truncated_room_name, uid, room.area, target_window)
   else
      truncated_room_name = fit_room_name(room.name)

      local is_pk = false
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
         blink_title(true, target_window)
         AddTimer("blink_title", 0, 0, 0.5, "", timer_flag.Enabled + timer_flag.Temporary + timer_flag.Replace, "mapper.blink_title")
      end

      -- blink_title() has already drawn the title and buttons in a PK room.
      if not is_pk then draw_window_frame(truncated_room_name, uid, room.area, target_window) end
   end

   local resize_x, resize_y = Theme.DrawResizeTag(target_window, 1)
   Theme.AddResizeHotspot(win, resize_x, resize_y, "mapper.resize_mouse_down", "mapper.resize_move_callback", "mapper.resize_release_callback")

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
      room_draw_times = {}
      rooms_drawn_count = 0
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
      room_cache_hits = 0
      room_cache_misses = 0
   end
end

local function report_frame(start_time, continuing, job, more)
   local end_time = utils.timer ()
   local frame_time = end_time - start_time
   if drawing.callback then drawing.callback.batch_ended = end_time end

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
      print (string.format ("=== Mapper %s: %s, %0.1f ms (avg %0.1f ms over %i batches) ===",
         continuing and "continuation" or "frame",job.continent_view and "cached continent" or "depth "..traversal_depth,
         frame_time * 1000, sum / n * 1000, n))
   end

   if detailed_timing then

      -- helper for consistent formatting
      local function pct(t) return (frame_time > 0) and (t / frame_time * 100) or 0 end

      local function ms(t) return t * 1000 end

      local mode = continuing and "map continuation" or pan_dragging and "pan drag" or pan_animating and "pan animation"
                   or resize_dragging and "resize update" or "map update"
      if job.continent_view then
         print(string.format("  Cells: %i visible, %i with room metadata; %s",job.continent_view.cell_count,frame_metrics.visible_room_count,mode))
         print("  Continent image: "..job.continent_view.image_status)
      else
         print(string.format("  Rooms: %i traversed, %i visible; %s", rooms_drawn_count, frame_metrics.visible_room_count, mode))
      end
      print("  Refresh execution only; excludes report output and deferred screen repaint.")
      print("  Map image: " .. (frame_metrics.map_image_retained and "retained" or frame_metrics.map_image_reused and "reused" or "rebuilt"))

      -- outer draw() phases
      print (string.format ("  Current room:      %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_current_room_time), pct(frame_metrics.total_current_room_time)))
      print (string.format ("  Window setup:      %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_window_setup_time), pct(frame_metrics.total_window_setup_time)))
      print (string.format ("  Background tex:    %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_bg_texture_time), pct(frame_metrics.total_bg_texture_time)))
      print (string.format ("  Room loop:         %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_room_loop_time), pct(frame_metrics.total_room_loop_time)))
      print (string.format ("  Map overlays:      %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_map_overlay_time), pct(frame_metrics.total_map_overlay_time)))
      print (string.format ("  Map drawing:       %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_map_render_time), pct(frame_metrics.total_map_render_time)))
      print (string.format ("  Map image copy:    %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_map_capture_time), pct(frame_metrics.total_map_capture_time)))
      print (string.format ("  Dress window:      %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_dress_window_time), pct(frame_metrics.total_dress_window_time)))
      print (string.format ("  Repaint request:   %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_repaint_request_time), pct(frame_metrics.total_repaint_request_time)))

      -- room loop breakdown
      if not job.continent_view and rooms_drawn_count > 0 then
         local sum_room_time = 0
         local min_room_time = 999999
         local max_room_time = 0
         for _, t in ipairs(room_draw_times) do
            sum_room_time = sum_room_time + t
            if t < min_room_time then min_room_time = t end
            if t > max_room_time then max_room_time = t end
         end
         local avg_room_time = sum_room_time / rooms_drawn_count
         local loop_overhead = frame_metrics.total_room_loop_time - sum_room_time

         print (string.format ("  --- Room loop breakdown (%i rooms traversed) ---", rooms_drawn_count))
         print (string.format ("    Per-room:  avg %0.4f ms, min %0.4f ms, max %0.4f ms",
            ms(avg_room_time), ms(min_room_time), ms(max_room_time)))
         local total_lookups = room_cache_hits + room_cache_misses
         print (string.format ("    Cache: %i hits, %i misses (%0.1f%% hit rate)",
            room_cache_hits, room_cache_misses,
            (total_lookups > 0) and (room_cache_hits / total_lookups * 100) or 0))
         print (string.format ("    Exit planning:   %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_exit_planning_time), pct(frame_metrics.total_exit_planning_time)))
         print (string.format ("      get_room:      %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_room_cache_time), pct(frame_metrics.total_room_cache_time)))
         print (string.format ("      Batch prefetch: %5.2f ms  (%4.1f%%, %i calls)", ms(frame_metrics.total_room_prefetch_time), pct(frame_metrics.total_room_prefetch_time), frame_metrics.room_prefetch_count))
         local plan_other = frame_metrics.total_exit_planning_time - frame_metrics.total_room_cache_time - frame_metrics.total_room_prefetch_time
         print (string.format ("      other logic:   %6.2f ms  (%4.1f%%)", ms(plan_other), pct(plan_other)))
         print (string.format ("    Exit commands:   %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_exit_drawing_time), pct(frame_metrics.total_exit_drawing_time)))
         print (string.format ("    Room commands:   %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_graphics_time), pct(frame_metrics.total_graphics_time)))
         print (string.format ("    Hotspot setup:   %6.2f ms  (%4.1f%%)", ms(frame_metrics.total_hotspot_time), pct(frame_metrics.total_hotspot_time)))
         print (string.format ("    Loop remainder:  %6.2f ms  (%4.1f%%)", ms(loop_overhead), pct(loop_overhead)))
      end

      -- These room-load totals cover the whole refresh, not just exit planning.
      print(string.format("  Room loads: %i calls, %6.2f ms (included in phases)", frame_metrics.room_load_count, ms(frame_metrics.total_get_room_time)))
      print(string.format("    Room callback:   %6.2f ms", ms(frame_metrics.total_room_db_time)))
      print(string.format("    Defaults:        %6.2f ms", ms(frame_metrics.total_room_defaults_time)))
      print(string.format("    Texture lookup:  %6.2f ms", ms(frame_metrics.total_room_texture_time)))
      report_window_timing(frame_time)

      -- unaccounted time
      local accounted = frame_metrics.total_current_room_time + frame_metrics.total_window_setup_time + frame_metrics.total_bg_texture_time + frame_metrics.total_room_loop_time
                      + frame_metrics.total_map_overlay_time + frame_metrics.total_map_render_time + frame_metrics.total_map_capture_time + frame_metrics.total_dress_window_time + frame_metrics.total_repaint_request_time
      local unaccounted = frame_time - accounted
      print (string.format ("  Unaccounted:       %6.2f ms  (%4.1f%%)", ms(unaccounted), pct(unaccounted)))
   end
   if not more and (timing or detailed_timing) then
      print(string.format("  Map complete: %0.1f ms elapsed, %0.1f ms executing in %i batches.",
         (end_time - job.started) * 1000, job.active_time * 1000, job.batches))
      if job.profiled_batches == job.batches and not job.callback_timing_incomplete then
         print(string.format("  Between-batch work: %0.1f ms reports, %0.1f ms callback return, %0.1f ms callback entry.",
            (job.report_time or 0) * 1000,
            (job.callback_return_time or 0) * 1000, (job.callback_entry_time or 0) * 1000))
         local resumes = job.tick_continuations or 0
         print(string.format("  Between mapper callbacks: %0.1f ms total, %0.1f ms avg, %0.1f ms min, %0.1f ms max; %i tick continuations.",
            (job.between_callback_time or 0) * 1000,
            resumes > 0 and job.between_callback_time / resumes * 1000 or 0,
            (job.min_callback_gap or 0) * 1000, (job.max_callback_gap or 0) * 1000,
            resumes))
         print("  Between callbacks includes client work and repaint; excludes the final report and deferred final repaint.")
      else
         print("  Between-batch timing is incomplete: timing changed during this map.")
      end
   end
end

local function draw_map (request)
   local continuing = type(request) == "table"
   local uid = continuing and request.uid or request
   if not continuing then cancel_draw() end
   if not uid then
      maperror "Cannot draw map right now, I don't know where you are - try: LOOK"
      return
   end

   map_origin_uid = uid -- remember where we are

   local start_time = utils.timer ()

   reset_frame_metrics()

   local job = continuing and request or nil
   local room, window_exists
   if continuing then
      room = job.room
      frame_commands = job.commands
      map_command_state.count = job.body_count
      frame_commands_changed = job.commands_changed
   else
      local current_t0 = detailed_timing and utils.timer()
      frame_timestamp = os.time ()

      -- The origin has a distinct border, so reload its display record after movement.
      local fresh_current = get_room (uid)
      local new_area = fresh_current.area

      display_room_cache[uid] = fresh_current

      room = fresh_current
      room_visit_times [uid] = os.time ()

      map_area_name = room.area
      select_room_layout(room)

      -- check for area change and start smooth pan reset
      if last_area_for_pan ~= nil and last_area_for_pan ~= map_area_name then
         if not pan_animating and (pan_offset_x ~= 0 or pan_offset_y ~= 0) then
            start_pan_animation()
         end
      end
      last_area_for_pan = map_area_name
      if current_t0 then frame_metrics.total_current_room_time = utils.timer() - current_t0 end

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
         frame_metrics.total_window_setup_time = utils.timer() - setup_t0
      end

      drawing.refresh_map_region()

      -- set up for initial room, in middle
      processed_room_positions, occupied_room_positions, planned_room_positions, area_exits = {}, {}, {}, {}
      reset_room_queue(room_queue_buffers[1])
      drawn_min_x, drawn_min_y, drawn_max_x, drawn_max_y = nil, nil, nil, nil
      traversal_depth = 0

      -- insert initial room (with pan offset applied)
      local center_x = config.WINDOW.width / 2 + pan_offset_x
      local center_y = config.WINDOW.height / 2 + pan_offset_y
      queued_room_uids[1] = uid
      queued_room_x[1] = center_x
      queued_room_y[1] = center_y

      -- Build into the other buffer. The last successful frame remains
      -- unchanged until rendering and image capture both succeed.
      local buffers = map_command_state.buffers
      frame_commands = completed_frame_cache and completed_frame_cache.commands == buffers[1] and buffers[2] or buffers[1]
      frame_commands_changed, map_command_state.count = false, 0
      map_command_state.border_room = nil
      job = {uid = uid, room = room, commands = frame_commands, width = config.WINDOW.width, height = config.WINDOW.height,
         prefetched = {}, started = start_time, body_count = 0, rendered_count = 0,
         room_ends = {}, room_indices = {}, rendered_rooms = 0,
         room_view = {cells={}, origin_x=center_x, origin_y=center_y,
            pitch=ROOM_SIZE+DISTANCE_TO_NEXT_ROOM, half=HALF_ROOM},
         -- Reach the visible window even when panning has moved the current room outside it.
         boundary_left = math.min(HALF_ROOM, center_x),
         boundary_top = math.min(font_height + HALF_ROOM, center_y),
         boundary_right = math.max(config.WINDOW.width - HALF_ROOM, center_x),
         boundary_bottom = math.max(config.WINDOW.height - HALF_ROOM, center_y)}
      drawing.job = job
      local continent_t0 = room.continent and detailed_timing and utils.timer()
      if room.continent then
         job.continent_view = continents.view(uid, {
            size=ROOM_SIZE,width=job.width,height=job.height,
            stretch=room_layout.current.stretch,
            stretch_bounds=room_layout.current.stretch and {Theme.BodyMetrics(win,FONT_ID,font_height,1)} or nil,
            pan_x=pan_offset_x,pan_y=pan_offset_y,top=font_height,
         })
      end
      local cached_continent = job.continent_view ~= nil
      local area_changed = previous_area_name ~= nil and previous_area_name ~= new_area
      if area_changed and not (drawing.prev_continent and cached_continent)
            or drawing.prev_continent and not cached_continent then
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
      display_room_cache[uid] = fresh_current
      previous_origin_uid, previous_area_name, drawing.prev_continent = uid, new_area, cached_continent
      if cached_continent then
         queued_room_uids[1],queued_room_x[1],queued_room_y[1]=nil,nil,nil
         drawing.plan_continent(job.continent_view)
         job.body_count=map_command_state.count
         job.room_ends[1]=job.body_count
      end
      if continent_t0 then frame_metrics.total_room_loop_time=utils.timer()-continent_t0 end
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
      and not room_layout.current_is_continent
      and room.textimage or false
   local reference = completed_frame_cache
   if not reference or reference.width ~= job.width or reference.height ~= job.height
         or reference.background ~= background or reference.body_colour ~= Theme.PRIMARY_BODY
         or reference.uid ~= uid or reference.room_name ~= room.name or reference.area ~= room.area
         or reference.room_info ~= room.info or reference.show_room_id ~= config.SHOW_ROOM_ID
         or reference.configure_open ~= config_panel_open
         or reference.font_name ~= config.FONT.name or reference.font_size ~= config.FONT.size
         or reference.continent_key ~= (job.continent_view and job.continent_view.key)
          or reference.continent_version ~= (job.continent_view and job.continent_view.image.version)
         or WindowImageInfo(win, "cached_map", 1) == nil then
      frame_commands_changed = true
   end
   local deadline = start_time + drawing.slice_seconds
   local progressed, canvas_ready, display_changed = false, false, false

   local function prepare_body()
      if canvas_ready then return end
      -- Keep the visible bitmap unchanged while commands and hotspots run.
      -- Native callbacks can repaint before the final overlays are ready.
      completed_frame_cache = nil
      if WindowInfo(offscreen_window, 3) ~= job.width or WindowInfo(offscreen_window, 4) ~= job.height then
         check(WindowCreate(offscreen_window, 0, 0, job.width, job.height, 0, 0, Theme.PRIMARY_BODY))
      end
      if job.continent_view then continents.install_image(job.continent_view,offscreen_window) end
      if job.render_started then
         local image_t0 = detailed_timing and utils.timer()
         check(WindowDrawImage(offscreen_window, "continuation_map", 0, 0, 0, 0, 1))
         if image_t0 then
            frame_metrics.total_map_render_time = frame_metrics.total_map_render_time + utils.timer() - image_t0
         end
      else
         local bg_t0 = detailed_timing and utils.timer()
         -- Restore the full background before replaying a changed map.
         if background == false then
            check(WindowRectOp(offscreen_window, 2, 0, 0, config.WINDOW.width, config.WINDOW.height, Theme.PRIMARY_BODY))
         end
         -- Handle background texture (cached for performance)
         if background then
            -- check if we need to regenerate the cached background
            local need_regen = (
               cached_bg_image == nil
               or cached_bg_width ~= config.WINDOW.width
               or cached_bg_height ~= config.WINDOW.height
               or cached_bg_texture ~= room.textimage
            )
            if need_regen then
               local iwidth = WindowImageInfo(offscreen_window, room.textimage, 2)
               local iheight = WindowImageInfo(offscreen_window, room.textimage, 3)
               local x, y = 0, 0
               while y < config.WINDOW.height do
                  x = 0
                  while x < config.WINDOW.width do
                     check(WindowDrawImage(offscreen_window, room.textimage, x, y, 0, 0, 1))
                     x = x + iwidth
                  end
                  y = y + iheight
               end

               -- capture the tiled result as a cached image
               cached_bg_image = "cached_bg"
               check(WindowImageFromWindow(offscreen_window, cached_bg_image, offscreen_window))

               cached_bg_width = config.WINDOW.width
               cached_bg_height = config.WINDOW.height
               cached_bg_texture = room.textimage
            else
               -- single blit of cached background
               check(WindowDrawImage(offscreen_window, cached_bg_image, 0, 0, 0, 0, 1))
            end
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
      if job.rendered_count < last_command then
         prepare_body()
         local render_t0 = detailed_timing and utils.timer()
         for i = job.rendered_count + 1, last_command do
            local command = frame_commands[i]
            check(_G[command.name](offscreen_window, unpack(command, 2, command.count)))
            job.rendered_count = i
         end
         if render_t0 then
            frame_metrics.total_map_render_time = frame_metrics.total_map_render_time + utils.timer() - render_t0
         end
      end
      job.rendered_rooms = last_room
   end

   -- Plan and draw in room batches. Read the clock only after
   -- a batch, and retain the queue and image when the callback must yield.
   while true do
      if frame_commands_changed and job.rendered_rooms < #job.room_ends then
         render_room_batch()
      else
         if job.continent_view or traversal_depth >= config.SCAN.depth then break end
         local loop_t0 = detailed_timing and utils.timer()
         local rooms_planned = 0
         while rooms_planned < drawing.room_batch_size and traversal_depth < config.SCAN.depth do
            if not job.level then
               if #queued_room_uids == 0 then break end
               job.level = queued_room_uids == room_queue_buffers[1].uid and room_queue_buffers[1] or room_queue_buffers[2]
               job.index = 1
               reset_room_queue(job.level == room_queue_buffers[1] and room_queue_buffers[2] or room_queue_buffers[1])
            end
            local level, i = job.level, job.index
            draw_room(level.uid[i], level.x[i], level.y[i])
            job.body_count = map_command_state.count
            job.room_ends[#job.room_ends + 1] = job.body_count
            rooms_planned = rooms_planned + 1
            job.index = i + 1
            if job.index > #level.uid then
               job.level = nil
               traversal_depth = traversal_depth + 1
            end
         end
         if loop_t0 then
            frame_metrics.total_room_loop_time = frame_metrics.total_room_loop_time + utils.timer() - loop_t0
         end
         if rooms_planned == 0 then break end
         if frame_commands_changed then
            render_room_batch()
         end
      end
      progressed = true
      if utils.timer() >= deadline then break end
   end
   local traversal_more = not job.continent_view and traversal_depth < config.SCAN.depth
      and (job.level ~= nil or #queued_room_uids > 0)

   -- An area teleport can leave every room outside the panned view. Recenter it.
   if not traversal_more and drawn_min_x == nil and (pan_offset_x ~= 0 or pan_offset_y ~= 0) and not pan_animating then
      start_pan_animation()
   end

   local overlay_t0 = detailed_timing and utils.timer()
   local body_changed = frame_commands_changed
   -- A map without body commands can compare its overlays immediately. Other
   -- partial maps still occupy slots used by the old complete map's body.
   local compare_overlays = not traversal_more
      or (reference and reference.body_count == 0 and job.body_count == 0)
   if not compare_overlays then frame_commands_changed = true end
   local overlay_room_limit = body_changed and job.rendered_rooms or #job.room_ends
   draw_map_overlays(overlay_room_limit)
   if not compare_overlays then frame_commands_changed = body_changed end
   if overlay_t0 then
      frame_metrics.total_map_overlay_time = utils.timer() - overlay_t0
   end

   -- Only the complete command sequence can confirm image reuse. Until a
   -- difference appears, matching commands are already visible in that image.
   if compare_overlays and reference and map_command_state.count ~= reference.count then
      frame_commands_changed = true
   end
   local reuse_map = not traversal_more and not frame_commands_changed
   if reuse_map then
      job.rendered_count, job.rendered_rooms = job.body_count, #job.room_ends
   elseif frame_commands_changed then
      -- An overlay difference can require replaying a matching body prefix.
      -- Replay the same room batches, with one clock check after each batch.
      while job.rendered_rooms < #job.room_ends and (not progressed or utils.timer() < deadline) do
         render_room_batch()
         progressed = true
      end
   end
   if job.rendered_count == job.body_count then job.rendered_rooms = #job.room_ends end
   if frame_commands_changed and job.rendered_rooms ~= overlay_room_limit then
      local overlay_replay_t0 = detailed_timing and utils.timer()
      map_command_state.count = job.body_count
      draw_map_overlays(job.rendered_rooms)
      if overlay_replay_t0 then
         frame_metrics.total_map_overlay_time = frame_metrics.total_map_overlay_time + utils.timer() - overlay_replay_t0
      end
   end
   -- Empty room batches still need a canvas for the current-room outline
   -- and area markers. Publish them before movement can cancel this map.
   if frame_commands_changed and job.body_count == 0 and not job.render_started then prepare_body() end
   local more = traversal_more or job.rendered_count < job.body_count
   job.commands_changed = frame_commands_changed
   -- Keep the old complete image until a changed body actually starts.
   -- Planning an area marker must not publish an empty body at the cutoff.
   display_changed = display_changed or reuse_map or (job.overlay_changed and job.render_started)
      or (not more and not job.render_started and frame_commands_changed)
   local room_view
   if display_changed then
      if not job.continent_view then
         local targets_t0 = detailed_timing and utils.timer()
         -- Room records are append-only. The published limit excludes new
         -- records until their drawing batch reaches the visible bitmap.
         room_view = {cells=job.room_view.cells, exits=build_area_exit_targets(job),
            origin_x=job.room_view.origin_x, origin_y=job.room_view.origin_y,
            pitch=job.room_view.pitch, half=job.room_view.half,
            room_limit=frame_commands_changed and job.rendered_rooms or #job.room_ends}
         if targets_t0 then
            frame_metrics.total_hotspot_time = frame_metrics.total_hotspot_time + utils.timer()-targets_t0
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
         for i = job.body_count + 1, map_command_state.count do
            local command = frame_commands[i]
            check(_G[command.name](offscreen_window, unpack(command, 2, command.count)))
         end
         if render_t0 then
            frame_metrics.total_map_render_time = frame_metrics.total_map_render_time + utils.timer() - render_t0
         end
      end
      draw_frame_controls(job, offscreen_window)
      -- Remove the old highlight before replacing its restoration image.
      drawing.highlight_target(nil,false)
      drawing.map_region.frame_ready=false
      if not reuse_map then
         local capture_t0 = detailed_timing and utils.timer()
         capture_map_image(offscreen_window)
         if capture_t0 then frame_metrics.total_map_capture_time = utils.timer() - capture_t0 end
      end
      local publish_t0 = detailed_timing and utils.timer()
      check(WindowDrawImage(win, "cached_map", 0, 0, 0, 0, 1))
      drawing.commit_map_view(job.continent_view,room_view)
      drawing.map_region.frame_ready=true
      WindowShow(win, show_on_redraw)
      if publish_t0 then
         frame_metrics.total_map_render_time = frame_metrics.total_map_render_time + utils.timer() - publish_t0
         if reuse_map then frame_metrics.map_image_reused = true end
      end
      frame_commands = nil
      job.overlay_changed, job.dressed = false, true
   elseif detailed_timing then
      frame_metrics.map_image_retained = true
   end
   frame_commands = nil
   if display_changed then
      drawing.refresh_map_region(false)
   elseif drawing.room_view and drawing.room_view.cells == job.room_view.cells
         and drawing.room_view.room_limit < job.rendered_rooms then
      -- A room can add a selection target without changing any map pixels.
      drawing.room_view.room_limit = job.rendered_rooms
      drawing.refresh_map_region()
   end
   if not more then
      completed_frame_cache = {commands = job.commands, count = map_command_state.count, body_count = job.body_count,
         width = config.WINDOW.width, height = config.WINDOW.height,
         uid = uid, room_name = room.name, area = room.area, room_info = room.info,
         show_room_id = config.SHOW_ROOM_ID, font_name = config.FONT.name, font_size = config.FONT.size,
         configure_open = config_panel_open,
         background = background, body_colour = Theme.PRIMARY_BODY,
         continent_key = job.continent_view and job.continent_view.key,
         continent_version = job.continent_view and job.continent_view.image.version}
   end

   local repaint_t0 = detailed_timing and utils.timer()
   if display_changed then
      if pan_animating then
         BufferedRepaint(PAN_ANIMATION_INTERVAL)
      else
         BufferedRepaint()
      end
   end
   if repaint_t0 then frame_metrics.total_repaint_request_time = utils.timer() - repaint_t0 end

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
   if pan_animating and not drawing.job then
      pan_animate_step()
      return
   end
   local callback_started = (timing or detailed_timing) and utils.timer()
   local job = drawing.job
   if not job or not job.pending then return end
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
   recent_frame_times = {}
   recent_frame_index = 0
end

function get_timing()
   return detailed_timing and "detailed" or timing and "on" or "off"
end

local function draw_credits()
   check(WindowCreate(offscreen_window, 0, 0, config.WINDOW.width, config.WINDOW.height, 0, 0, Theme.PRIMARY_BODY))
   local top = (config.WINDOW.height - #credits * font_height) /2

   for _, v in ipairs (credits) do
      local width = WindowTextWidth (offscreen_window, FONT_ID, v)
      local left = (config.WINDOW.width - width) / 2
      WindowText (offscreen_window, FONT_ID, v, left, top, 0, 0, Theme.BODY_TEXT)
      top = top + font_height
   end

   Theme.DrawBorder(offscreen_window)
   local resize_x, resize_y = Theme.DrawResizeTag(offscreen_window, 1)
   Theme.AddResizeHotspot(win, resize_x, resize_y, "mapper.resize_mouse_down", "mapper.resize_move_callback", "mapper.resize_release_callback")
   drawing.map_region.frame_ready=false
   capture_map_image(offscreen_window)
   check(WindowDrawImage(win, "cached_map", 0, 0, 0, 0, 1))
   drawing.map_region.frame_ready=true
   WindowShow(win, show_on_redraw)
   WindowShow(config_window, false)
end

function build_continent_maps()
   continents.build_images(
      room_layout.continent.stretch and 9 or snap_continent_room_size(room_layout.continent.size),
      room_layout.vidblain.stretch and 9 or snap_continent_room_size(room_layout.vidblain.size))
end

-- Recreate window resources on installation or reinitialization.
function init (options)
   if continents then continents.close() end
   continents = new_continent_maps(options.continent_data, GetPluginID() .. "_continent")
   cancel_draw()

   -- Keep the supplied configuration table so the plugin can save option changes.
   config = options.config
   assert (type (config) == "table", "No 'config' table supplied to mapper.")
   config.SHOW_AREA_EXITS = nil -- Remove the retired setting from saved configurations.

   control_hotspots = {}
   drawing.map_region = {}
   drawing.continent_view, drawing.room_view = nil, nil
   room_title_cache = nil
   completed_frame_cache, frame_commands = nil, nil
   map_command_state = {buffers = {{}, {}}, count = 0}
   room_queue_buffers = {{uid = {}, x = {}, y = {}}, {uid = {}, x = {}, y = {}}}
   is_running = options.running == true
   show_on_redraw = options.hidden ~= true
   callbacks.activate_target = options.activate_target
   callbacks.get_room = options.get_room
   callbacks.get_continent_room_overlays = options.get_continent_room_overlays
   callbacks.prefetch_rooms = options.prefetch_rooms
   assert (type(callbacks.prefetch_rooms) == "function", "Invalid 'prefetch_rooms' callback.")
   assert (type (callbacks.get_room) == "function", "No 'get_room' function supplied to mapper.")

   show_help = options.show_help     -- "help" function
   callbacks.room_click = options.room_click   -- RH mouse-click function
   timing = options.timing                   -- true for frame timing summary
   detailed_timing = options.detailed_timing  -- true for detailed sub-phase breakdown
   show_up_down = options.show_up_down        -- true to show up or down

   for k, v in pairs (default_config) do
      if config[k] == nil then
         config[k] = v
      end
   end

   win = GetPluginID () .. "_mapper"
   offscreen_window = win .. "_render"
   config_window = GetPluginID () .. "_z_config_win"

   WindowCreate (win, 0, 0, 0, 0, 0, 0, 0)
   WindowCreate(offscreen_window, 0, 0, 0, 0, 0, 0, 0)
   WindowCreate(config_window, 0, 0, 0, 0, 0, 0, 0)

   WindowFont (win, FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (win, FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)
   WindowFont (offscreen_window, FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (offscreen_window, FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)
   WindowFont (config_window, CONFIG_FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (config_window, CONFIG_FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)

   font_height = WindowFontInfo (win, FONT_ID, 1)  -- height

   -- find where window was last time
   windowinfo = movewindow.install (win, miniwin.pos_bottom_right, miniwin.create_absolute_location , true, {config_window}, {mouseup=MouseUp, mousedown=LeftClickOnly, dragmove=LeftClickOnly, dragrelease=LeftClickOnly}, {x=default_x, y=default_y})

   update_room_geometry ()

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

   movewindow.add_drag_handler (win, 0, 0, 0, 0)

   resize_dragging = false
   draw_credits()

end

function MouseUp(flags, hotspot_id, win)
   if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
      pan_dragging = false
      pan_rebaseline_on_drag = true
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
      menustring = menustring.."|-|Center Map"
   end

   local result = with_pan_tooltip_hidden(WindowMenu,
      win,
      WindowInfo (win, 14),  -- x position
      WindowInfo (win, 15),   -- y position
      menustring) -- content
   if result == "Bring To Front" then
      CallPlugin("462b665ecb569efbf261422f","boostMe", win)
   elseif result == "Send To Back" then
      CallPlugin("462b665ecb569efbf261422f","dropMe", win)
   elseif result == "Center Map" then
      reset_pan()
   end
end

local function selected_layout(hotspot_id)
   local kind = hotspot_id and hotspot_id:match("^%$<([%a]+)_")
   if kind == "area" or kind == "continent" or kind == "vidblain" then return room_layout[kind] end
   return room_layout.current or room_layout.area
end

function mouseup_change_stretch(flags, hotspot_id)
   local layout = selected_layout(hotspot_id)
   layout.stretch = not layout.stretch
   draw(map_origin_uid)
   SaveState()
end

local function change_layout(layout, size_change, spacing_change)
   if not map_origin_uid or size_change ~= 0 and layout.stretch then return end
   local size = layout.size
   if layout ~= room_layout.area then
      size = snap_continent_room_size(size + (size_change > 0 and 4 or -4))
      if size == layout.size then return end
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
         if size < 4 or size > 40 or spacing < min_spacing or spacing > 40 then return end
      else
         if size_change ~= 0 then size = math.max(4, math.min(40, size + size_change)) end
         min_spacing = minimum_area_spacing(size)
         if spacing_change ~= 0 then spacing = math.max(min_spacing, math.min(40, spacing + spacing_change)) end
      end
      if size == layout.size and spacing == layout.spacing then return end
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
   if layout.size < 40 then change_layout(layout, 2, layout==room_layout.area and 2 or 0) end
end

function zoom_out()
   local layout = selected_layout()
   if layout.size > 4 then change_layout(layout, -2, layout==room_layout.area and -2 or 0) end
end

function mapprint (...)
   local old_note_colour = GetNoteColourFore ()
   SetNoteColourFore(styles.MAPPER_NOTE_COLOUR.colour)
   print (...)
   SetNoteColourFore (old_note_colour)
end

function maperror (...)
   local old_note_colour = GetNoteColourFore ()
   SetNoteColourFore(ColourNameToRGB "red")
   print (...)
   SetNoteColourFore (old_note_colour)
end

function show()
   WindowShow(win, true)
   hidden = false
   show_on_redraw = true
   if map_origin_uid then draw(map_origin_uid) end
end

-- Hiding stops pending batches. keep_hidden also hides later redraws.
function hide(keep_hidden)
   show_on_redraw = not keep_hidden
   cancel_draw()
   WindowShow(win, false)
   hidden = true
end

function save_state ()
   SetVariable("ROOM_SIZE", room_layout.area.size)
   SetVariable("DISTANCE_TO_NEXT_ROOM", room_layout.area.spacing)
   SetVariable("CONTINENT_ROOM_SIZE", room_layout.continent.size)
   SetVariable("VIDBLAIN_ROOM_SIZE", room_layout.vidblain.size)
   SetVariable("CONTINENT_STRETCH_TO_FIT", room_layout.continent.stretch and "1" or "0")
   SetVariable("VIDBLAIN_STRETCH_TO_FIT", room_layout.vidblain.stretch and "1" or "0")
   if WindowInfo(win,1) and WindowInfo(win,5) then
      movewindow.save_state (win)
      config.WINDOW.width = WindowInfo(win, 3)
      config.WINDOW.height = WindowInfo(win, 4)
   end
end

-- Map pointer callbacks.

local function is_left_button_only(flags)
   return bit.band(flags, miniwin.hotspot_got_lh_mouse) ~= 0 and
      bit.band(flags, miniwin.hotspot_got_rh_mouse) == 0
end

function map_mouseover()
   drawing.map_region.outside=false
   drawing.refresh_map_region()
end

function map_cancel_mouseover()
   if drawing.map_region.updating then return end
   drawing.map_region.outside=true
   drawing.highlight_target(nil)
end

function map_mousedown(flags,hotspot_id)
   local region = drawing.map_region
   local x,y = WindowInfo(win,14),WindowInfo(win,15)
   local travel=is_left_button_only(flags)
   region.down = {target=drawing.click_target(x,y,travel),x=x,y=y,travel=travel,
      client_x=WindowInfo(win,17),client_y=WindowInfo(win,18)}
   drawing.highlight_target(nil)
end

function map_cancel_mousedown()
   drawing.map_region.down = nil
   drawing.refresh_map_region()
end

function map_mouseup(flags,hotspot_id)
   local region = drawing.map_region
   local down = region.down
   region.down = nil
   drawing.refresh_map_region()
   if not down or down.cancelled then return end
   local target = drawing.click_target(WindowInfo(win,14),WindowInfo(win,15),down.travel)
   if target then
      local uid = callbacks.activate_target(flags, target)
      if uid then
         pan_dragging = false
         pan_rebaseline_on_drag = true
         with_pan_tooltip_hidden(callbacks.room_click, uid, flags)
      end
   else
      MouseUp(flags,hotspot_id)
   end
end

function map_dragmove(flags,hotspot_id)
   local down = drawing.map_region.down
   if down and not down.dragging and is_left_button_only(flags) then
      local dx = WindowInfo(win,17) - down.client_x
      local dy = WindowInfo(win,18) - down.client_y
      if dx * dx + dy * dy <= MAP_DRAG_THRESHOLD * MAP_DRAG_THRESHOLD then return end
      down.cancelled,down.dragging = true,true
      pan_mousedown(flags,hotspot_id)
      -- Keep the full movement from the press when the drag starts.
      pan_last_mouse_x,pan_last_mouse_y = down.client_x,down.client_y
      pan_rebaseline_on_drag = false
   end
   pan_dragmove(flags,hotspot_id)
end

-- Map panning and recentering.

local function begin_map_pan()
   cancel_draw()
   pan_animating = false
   -- Keep control hotspots stable while the pointer remains captured.
   pan_dragging = true
   pan_last_mouse_x,pan_last_mouse_y = WindowInfo(win,17),WindowInfo(win,18)
end

function pan_mousedown (flags, hotspot_id)
   begin_map_pan()
end

function pan_dragmove (flags, hotspot_id)
   if not is_left_button_only(flags) then
      return  -- ignore non-left drags without updating stored drag position
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
   
   -- clamp so at least one room remains visible in the viewport
   if drawn_max_x then
      -- bounding box is from the last draw() using the previous offset;
      -- delta shifts all room positions, so new bbox = old bbox + delta
      local new_min_x = drawn_min_x + delta_x
      local new_max_x = drawn_max_x + delta_x
      local new_min_y = drawn_min_y + delta_y
      local new_max_y = drawn_max_y + delta_y
      local title_height = bodytop or (font_height * 2)
      local view=drawing.continent_view
      local half=view and view.origin_x and view.size/2 or HALF_ROOM
      -- pull back so the whole last room stays in the viewport
      if new_max_x - half < 0 then
         pan_offset_x = pan_offset_x - (new_max_x - half)
      elseif new_min_x + half > config.WINDOW.width then
         pan_offset_x = pan_offset_x - (new_min_x + half - config.WINDOW.width)
      end
      if new_max_y - half < title_height then
         pan_offset_y = pan_offset_y - (new_max_y - half - title_height)
      elseif new_min_y + half > config.WINDOW.height then
         pan_offset_y = pan_offset_y - (new_min_y + half - config.WINDOW.height)
      end
   end
   
   -- Keep the captured hotspot while drawing the new pan position.
   draw(map_origin_uid)
end

function pan_dragrelease (flags, hotspot_id)
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
   if elapsed < PAN_ANIMATION_INTERVAL then return end
   pan_animation_time = now

   local dist = math.sqrt(pan_offset_x * pan_offset_x + pan_offset_y * pan_offset_y)
   local max_speed, ease_time = 250, 0.25  -- pixels/second and seconds
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
   if map_origin_uid then draw(map_origin_uid) end
end

function mouseup_configure (flags, hotspot_id)
   config_panel_open = true
   draw (map_origin_uid)
end

function mouseup_close_configure (flags, hotspot_id)
   config_panel_open = false
   SaveState()
   draw (map_origin_uid)
end

function mouseup_change_font (flags, hotspot_id)

   local newfont =  utils.fontpicker (config.FONT.name, config.FONT.size, styles.ROOM_NAME_TEXT.colour)

   if not newfont then
      return
   end

   config.FONT.name = newfont.name

   if newfont.size > 12 then
      utils.msgbox ("Maximum allowed font size is 12 points.", "Font too large", "ok", "!", 1)
   else
      config.FONT.size = newfont.size
   end

   styles.ROOM_NAME_TEXT.colour = newfont.colour

   WindowFont (win, FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (win, FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)
   WindowFont (offscreen_window, FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (offscreen_window, FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)
   WindowFont (config_window, CONFIG_FONT_ID, config.FONT.name, config.FONT.size)
   WindowFont (config_window, CONFIG_FONT_ID_UL, config.FONT.name, config.FONT.size, false, false, true)

   font_height = WindowFontInfo (win, FONT_ID, 1)  -- height

   draw (map_origin_uid)
end

function mouseup_change_depth (flags, hotspot_id)

   local depth = get_number_from_user ("Choose scan depth (3 to 300 rooms)", "Depth", config.SCAN.depth, 3, 300)

   if not depth then
      return
   end

   config.SCAN.depth = depth
   draw (map_origin_uid)
end

function mouseup_change_area_textures (flags, hotspot_id)
   config.USE_TEXTURES.enabled = config.USE_TEXTURES.enabled ~= true
   draw (map_origin_uid)
end

function mouseup_change_show_id (flags, hotspot_id)
   config.SHOW_ROOM_ID = config.SHOW_ROOM_ID ~= true
   draw (map_origin_uid)
end

function mouseup_change_room_borders(flags, hotspot_id)
   config.SHOW_ROOM_BORDERS = not config.SHOW_ROOM_BORDERS
   draw(map_origin_uid)
   SaveState()
end

function mouseup_change_blink_pk_title (flags, hotspot_id)
   config.BLINK_PK_TITLE = config.BLINK_PK_TITLE ~= true
   draw (map_origin_uid)
end

function mouseup_change_mousewheel_zoom(flags, hotspot_id)
   config.MOUSEWHEEL_ZOOM = not config.MOUSEWHEEL_ZOOM
   draw(map_origin_uid)
   SaveState()
end

function zoom_map (flags, hotspot_id)
   if not config.MOUSEWHEEL_ZOOM then return end
   if bit.band (flags, 0x100) ~= 0 then
      zoom_out ()
   else
      zoom_in ()
   end
end

function resize_mouse_down(flags, hotspot_id)
   cancel_draw()
   drawing.highlight_target(nil)
   drawing.map_region.frame_ready=false
   resize_dragging = true
   resize_start_x, resize_start_y = WindowInfo (win, 17), WindowInfo (win, 18)
end

function resize_release_callback()
   resize_dragging = false
   config.WINDOW.width = WindowInfo(win, 3)
   config.WINDOW.height = WindowInfo(win, 4)
   if map_origin_uid then draw(map_origin_uid) else draw_credits() end
end

function resize_move_callback()
   if GetPluginVariable("c293f9e7f04dde889f65cb90", "lock_down_miniwindows") == "1" then
      return
   end
   local posx, posy = WindowInfo (win, 17), WindowInfo (win, 18)

   local width = WindowInfo(win, 3) + posx - resize_start_x
   resize_start_x = posx
   if (50 > width) then
      width = 50
      resize_start_x = windowinfo.window_left + width
   elseif (windowinfo.window_left + width > GetInfo(281)) then
      width = GetInfo(281) - windowinfo.window_left
      resize_start_x = GetInfo(281)
   end

   local height = WindowInfo(win, 4) + posy - resize_start_y
   resize_start_y = posy
   if (50 > height) then
      height = 50
      resize_start_y = windowinfo.window_top + height
   elseif (windowinfo.window_top + height > GetInfo(280)) then
      height = GetInfo(280) - windowinfo.window_top
      resize_start_y = GetInfo(280)
   end

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
