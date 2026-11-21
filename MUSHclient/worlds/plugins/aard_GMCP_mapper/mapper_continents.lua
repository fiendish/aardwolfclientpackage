-- Continent geometry, artwork, image caches, and incremental rendering.
local mapper_bitmap = require "mapper_bitmap"
local mapper_image_cache = require "mapper_image_cache"
-- Capture the loaded generation once. A database change can reinitialize this
-- module after its files have been edited but before the plugin is reloaded.
local mapper_cache_version = mapper_image_cache.capture({
   debug.getinfo(1, "S").source, debug.getinfo(mapper_image_cache.new, "S").source,
})
local copytable = require "copytable"
local M = {}
local CONTINENT_MAX_ROOM_SIZE = 25
local VIDBLAIN_MAX_ROOM_SIZE = 29
M.CONTINENT_MAX_ROOM_SIZE, M.VIDBLAIN_MAX_ROOM_SIZE = CONTINENT_MAX_ROOM_SIZE, VIDBLAIN_MAX_ROOM_SIZE

local continent_brush_patterns = {
   {
      id = "pines",
      rows = {
         "...#....",
         "...#....",
         "..###...",
         ".#####..",
         "...#....",
         "...#....",
         ".......#",
         ".......#",
         "#.....##",
         "##...###",
         ".......#",
         ".......#",
      },
   }, {
      id = "paving",
      rows = {
         "########",
         "...#....",
         "...#....",
         "...#....",
         "########",
         ".......#",
         ".......#",
         ".......#"},
   }, {
      id = "cracked-earth",
      rows = {
         "....#...",
         "...##...",
         "..#.....",
         ".#......",
         "#.....##",
         ".....#..",
         "....#...",
         "....#..."},
   }, {
      id = "sand-grains",
      rows = {
         "##......",
         "##......",
         "........",
         "........",
         "....##..",
         "....##..",
         "........",
         "........"},
   }, {
      id = "scattered-dots", width = 96, height = 96,
      dots = {
         {45, 2}, {92, 4}, {4, 6}, {27, 14}, {88, 18}, {20, 21},
         {47, 23}, {91, 23}, {54, 34}, {10, 41}, {17, 41}, {52, 58},
         {26, 60}, {35, 60}, {4, 61}, {86, 72}, {62, 76}, {57, 81},
         {39, 85}, {46, 86}, {81, 88}, {3, 90}, {39, 90}, {52, 93},
      },
   }, {
      id = "scattered-dots-2", width = 96, height = 96,
      dots = {
         {44, 12}, {28, 16}, {40, 18}, {48, 18}, {25, 23}, {89, 23},
         {36, 29}, {26, 31}, {44, 32}, {16, 35}, {18, 40}, {27, 44},
         {16, 45}, {54, 45}, {24, 52}, {22, 58}, {94, 60}, {26, 64},
         {1, 73}, {31, 75}, {58, 87}, {35, 90}, {27, 95}, {36, 95},
      },
   }, {
      id = "wide-zigzags",
      rows = {
         "#......#",
         ".#....#.",
         "..#..#..",
         "...##...",
         "........",
         "........",
         "........",
         "........"},
   }, {
      id = "buildings",
      rows = {
         "........",
         ".######.",
         ".#....#.",
         ".#....#.",
         ".#....#.",
         ".#....#.",
         ".#....#.",
         "........"},
   }, {
      id = "small-ripples",
      rows = {
         "........",
         ".##.....",
         "#..#....",
         "........",
         "........",
         ".....##.",
         "....#..#",
         "........"},
   }, {
      id = "long-waves",
      rows = {
         "#......#",
         ".#....#.",
         "..####..",
         "........",
         "........",
         "........",
         "........",
         "........"},
   }, {
      id = "gentle-waves",
      rows = {
         "........",
         "#......#",
         ".######.",
         "........",
         "........",
         "........",
         "........",
         "........"},
   }, {
      id = "low-peaks",
      rows = {
         "........",
         "...#....",
         "..#.#...",
         ".#...#..",
         "........",
         "........",
         "........",
         "........"},
   }, {
      id = "staggered-peaks",
      rows = {
         "............",
         "...#........",
         "...#........",
         "..#.#....#..",
         "..#.#....#..",
         ".#...#..#.#.",
         "............",
         "............",
         "............",
         "......#.....",
         "......#.....",
         "#....#.#....",
         "#....#.#....",
         ".#..#...#..#",
         "............",
         "............",
      },
   }, {
      id = "offset-hills",
      rows = {
         "..###...",
         ".#...#..",
         "........",
         "........",
         "#.....##",
         ".#...#..",
         "........",
         "........"},
   }, {
      id = "grass-tufts",
      rows = {
         "....#...",
         "....#...",
         "...#....",
         "........",
         "#.......",
         "#.......",
         ".......#",
         "........"},
   }, {
      id = "reeds",
      rows = {
         ".#......",
         ".#.#....",
         ".#.#....",
         "........",
         ".....#..",
         ".....#.#",
         ".....#.#",
         "........"},
   }, {
      id = "pebbles",
      rows = {
         "........",
         ".##.....",
         "#..#....",
         ".##.....",
         "........",
         ".....##.",
         "....#..#",
         ".....##."},
   }, {
      id = "jungle-leaves",
      rows = {
         ".##.##..",
         ".#####..",
         "..###...",
         "...#....",
         "##.#.##.",
         ".#####..",
         "..###...",
         "...#....",
         "##...##.",
         "##...###",
         "#.....##",
         ".......#",
         ".##.##.#",
         "##...###",
         "#.....##",
         ".......#",
      },
   },
}
local continent_custom_brushes = {}
for _, pattern in ipairs(continent_brush_patterns) do
   if pattern.rows then
      pattern.width, pattern.height = #pattern.rows[1], #pattern.rows
   end
   continent_custom_brushes[pattern.id] = pattern
end

local function castle_symbol(fill, style, left, top, pitch)
   -- Even dimensions give equal pixel margins at every continent size.
   local height = math.max(4, pitch - 2)
   local width = math.min(pitch, math.max(4, 2 * math.floor(height / 3 + 0.5)))
   local x = left + (pitch - width) / 2
   local y = top + (pitch - height) / 2
   local cap = math.max(1, math.floor(height / 7 + 0.5))
   local merlon = math.max(1, math.floor(width / 5))
   fill(x, y + cap, x + width, y + height, style.colour)
   fill(x, y, x + merlon, y + cap, style.colour)
   fill(x + width - merlon, y, x + width, y + cap, style.colour)
   if width >= 6 then
      local center_width = 2 * math.ceil(merlon / 2)
      local center_x = x + (width - center_width) / 2
      fill(center_x, y, center_x + center_width, y + cap, style.colour)
   end
   local gate_width = math.min(width - 2, math.max(2, 2 * math.floor(width / 6)))
   local gate_height = math.max(1, math.floor(height * 0.4))
   local gate_x = x + (width - gate_width) / 2
   fill(gate_x, y + height - gate_height, gate_x + gate_width, y + height, style.background)
end

local function pillar_symbol(fill, style, left, top, pitch)
   local height = math.max(3, pitch - 2)
   local width = math.min(pitch - 1, math.max(3, 2 * math.floor(height * 5 / 14) + 1))
   local x = left + math.floor((pitch - width) / 2)
   local y = top + math.floor((pitch - height) / 2)
   local cap = math.max(1, math.floor(height / 7 + 0.5))
   local inset = math.max(1, math.floor(width / 5 + 0.5))
   fill(x, y, x + width, y + cap, style.colour)
   fill(x + inset, y + cap, x + width - inset, y + height - cap, style.colour)
   fill(x, y + height - cap, x + width, y + height, style.colour)
   local shaft_width = width - inset * 2
   if shaft_width >= 3 then
      local groove = math.max(1, math.floor(shaft_width / 3))
      local groove_x = x + inset + math.floor((shaft_width - groove) / 2)
      fill(groove_x, y + cap, groove_x + groove, y + height - cap, style.background)
   end
end

local function star_symbol(large)
   return function(fill, style, left, top, pitch)
      local radius = large and math.max(1, math.floor((pitch - 2) / 3))
         or math.max(0, math.floor((pitch - 2) / 4))
      local center_x = left + math.floor((pitch - 1) / 2)
      local center_y = top + math.floor((pitch - 1) / 2)
      for y = -radius, radius do
         local half_width = y == 0 and radius or math.floor((radius - math.abs(y)) / 2)
         fill(center_x - half_width, center_y + y,
            center_x + half_width + 1, center_y + y + 1, style.colour)
      end
   end
end

M.room_symbols = {
   ["castles"] = castle_symbol, ["stone-columns"] = pillar_symbol,
   ["small-star"] = star_symbol(false), ["large-star"] = star_symbol(true),
}
M.definitions = {
   [0] = {first_uid = 11435, area = "mesolar", width = 60, height = 40, x = 60, y = 0},
   [1] = {first_uid = 4863, area = "southern", width = 60, height = 15, x = 60, y = 40},
   [2] = {first_uid = 17131, area = "gelidus", width = 60, height = 40, x = 60, y = 55},
   [3] = {first_uid = 24236, area = "abend", width = 30, height = 40, x = 30, y = 0},
   [4] = {first_uid = 2492, area = "alagh", width = 30, height = 50, x = 0, y = 0},
   [5] = {first_uid = 6999, area = "uncharted", width = 60, height = 55, x = 0, y = 40},
   [6] = {first_uid = 33136, area = "vidblain", width = 30, height = 30, x = 0, y = 0},
}
local artwork_directory = assert(debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) .. "vidblain_art/"
local artwork_files = {core = artwork_directory .. "core-28.png", optional = artwork_directory .. "optional-28.png"}
local directions = {n = {0, -1}, s = {0, 1}, e = {1, 0}, w = {-1, 0}}
local world_rows, inner_sea_rows = {}, {}
local zone_paint_order = {5, 2, 1, 0, 3, 4}

-- The Inner Sea changes only the priority of the Uncharted Ocean.
local function projected_row(inner_sea, y)
   local rows = inner_sea and inner_sea_rows or world_rows
   if rows[y] then return rows[y] end
   local world = {}
   for _, zone in ipairs(zone_paint_order) do
      local d = M.definitions[zone]
      if y >= d.y and y < d.y + d.height then
         for x = d.x, d.x + d.width - 1 do world[x] = zone end
      end
   end
   local sea, ocean = world, M.definitions[5]
   if y >= ocean.y and y < ocean.y + ocean.height then
      for x = ocean.x, ocean.x + ocean.width - 1 do
         if world[x] ~= 5 then
            if sea == world then sea = copytable.shallow(world) end
            sea[x] = 5
         end
      end
   end
   world_rows[y], inner_sea_rows[y] = world, sea
   return rows[y]
end

local empty_exits = {}
local EMPTY_COLOUR = 0
-- Keep the continent display palette separate from the GMCP sector palette.
M.terrain_styles = {
   air = {colour = 0xffff00, brush = 0, background = 0x8c8c00},
   areaexit = {colour = 0xffff00, brush = 1, background = 0x8c8c00, entrance = true},
   beach = {colour = 0x00ffff, brush = "sand-grains", background = 0xaae6ff},
   bridge = {colour = 0xdcdcdc, brush = 0, background = 0x2d52a0},
   castle = {colour = 0xdcdcdc, brush = "castles", background = 0x1d3158},
   cave = {colour = 0xc05542, brush = 11, background = 0x0f2435},
   city = {colour = 0xd3d3d3, brush = "buildings", background = 0x696969},
   clanexit = {colour = 0xffff00, brush = 1, background = 0x8c8c00, entrance = true},
   dark = {colour = 0x696969, brush = 0, background = 0x000000},
   desert = {colour = 0x20a5da, brush = "cracked-earth", background = 0x83ebff},
   dungeon = {colour = 0x000000, brush = 1, background = 0x000000},
   field = {colour = 0x3f7b65, brush = "reeds", background = 0x238e6b},
   field2 = {colour = 0x008000, brush = "reeds", background = 0x004600},
   field3 = {colour = 0x238e6b, brush = "reeds", background = 0x32a589},
   field4 = {colour = 0x238e6b, brush = "reeds", background = 0x47a576},
   forest = {colour = 0x003200, brush = "pines", background = 0x006400},
   hell1 = {colour = 0x0000ff, brush = "low-peaks", background = 0x000080},
   hell2 = {colour = 0x2222b2, brush = "low-peaks", background = 0x000080},
   hell3 = {colour = 0x000080, brush = 0, background = 0x000046},
   hills = {colour = 0x32cd9a, brush = "offset-hills", background = 0x008c00},
   ice = {colour = 0xfff5db, brush = 0, background = 0x8c8678},
   icehills = {colour = 0xdcdcdc, brush = "offset-hills", background = 0xfffde4},
   icemount = {colour = 0xdac5a8, brush = "staggered-peaks", background = 0xf1f0d3},
   interestpoint = {colour = 0xffff00, brush = 1, background = 0x8c8c00, entrance = true},
   jungle = {colour = 0x008000, brush = "jungle-leaves", background = 0x004600},
   moon = {colour = 0x800000, brush = 0, background = 0x460000},
   mountain = {colour = 0x466d96, brush = "staggered-peaks", background = 0x1f3341},
   mountain_cyan = {colour = 0x808000, brush = "staggered-peaks", background = 0x464600},
   ocean = {colour = 0xe16941, brush = "gentle-waves", background = 0x7c3a24},
   ocean2 = {colour = 0xe16941, brush = "long-waves", background = 0x7c3a24},
   ocean3 = {colour = 0xe16941, brush = "wide-zigzags", background = 0x7c3a24},
   ocean4 = {colour = 0xe16941, brush = "small-ripples", background = 0x7c3a24},
   pillar = {colour = 0xdcdcdc, brush = "stone-columns", background = 0x238e6b},
   plain = {colour = 0x6fac96, brush = "grass-tufts", background = 0x32cd9a},
   river = {colour = 0xe16941, brush = 11, background = 0x7c3a24},
   road = {colour = 0xdcdcdc, brush = "paving", background = 0xc0c0c0},
   rocks = {colour = 0x008080, brush = 12, background = 0x004646},
   shore = {colour = 0xe6e0b0, brush = 11, background = 0x8c8c00},
   smallroad = {colour = 0xa9a9a9, brush = 8, background = 0xd3d3d3},
   smallroad_ew = {colour = 0xa9a9a9, brush = 8, background = 0xd3d3d3},
   snow = {colour = 0xffffff, brush = 0, background = 0x8c8c8c},
   space1 = {colour = 0xc0c0c0, brush = "scattered-dots", background = 0x000000},
   space2 = {colour = 0xc0c0c0, brush = "large-star", background = 0x000000},
   space3 = {colour = 0xc0c0c0, brush = "small-star", background = 0x000000},
   space4 = {colour = 0xc0c0c0, brush = "scattered-dots-2", background = 0x000000},
   swamp = {colour = 0x008000, brush = 11, background = 0x004600},
   trail_ew = {colour = 0x3f8fb3, brush = "pebbles", background = 0x3f7e9e},
   underground = {colour = 0x000000, brush = 1, background = 0x000000},
   volcano = {colour = 0x0000ff, brush = 12, background = 0x00008c},
   waternoswim = {colour = 0xe16941, brush = 11, background = 0x000000},
   waterswim = {colour = 0xff0000, brush = 0, background = 0x8c0000},
}

local function uid_less(a, b)
   local first, second = tonumber(a), tonumber(b)
   if first and second and first ~= second then
      return first < second
   end
   if first and not second then
      return true
   end
   if second and not first then
      return false
   end
   return tostring(a) < tostring(b)
end

local function split_axis(start, source_start, period, first, last, copies)
   local spans, count = {}, 0
   while count < period do
      local source = (source_start + count) % period
      local length = math.min(copies == 1 and period - source or period, period - count)
      local destination = start + count
      local left, right = math.max(destination, first), math.min(destination + length, last)
      if left < right then
         spans[#spans + 1] = {left = left, source = source + left - destination, length = right - left}
      end
      count = count + length
   end
   return spans
end

-- Use the cached image's integer period for both wrapped crops and room edges.
local function fit_axis(origin, source, period, pixels, first, last, copies)
   local scale = pixels / period
   local position = source * pixels / period
   local start = math.floor(position)
   origin = math.floor(origin)
   return split_axis(origin, start, pixels, first, last, copies or 1), origin + position - start, scale, origin - start
end

-- Use the published grid, including off-screen neighbors and wrapped seams.
local function view_entrance_approaches(view, source)
   local definition = M.definitions[source.zone]
   local stitched = view.grid_width == 120
   local x = source.x + (stitched and definition.x or 0)
   local y = source.y + (stitched and definition.y or 0)
   local result = {}
   for _, dir in ipairs({"n", "e", "s", "w"}) do
      local offset = directions[dir]
      local adjacent = view.grid[(y - offset[2]) % view.grid_height + 1].cells[(x - offset[1]) % view.grid_width + 1]
      if adjacent == view.current_source then
         adjacent = view.current_cell
      end
      if adjacent.uid then
         result[#result + 1] = {uid = adjacent.uid, dir = dir}
      end
   end
   return result
end

-- The same integer image edges position cells, markers, and selection bounds.
local function grid_edge(origin, index, pixels, cells)
   return origin + math.floor(index * pixels / cells)
end

function M.visible_cells(origin, source, pixels, cells, size, clip_first, clip_last)
   local first, last = 0, cells - 1
   while first <= last and grid_edge(origin, source + first, pixels, cells) + size <= clip_first do
      first = first + 1
   end
   while first <= last and grid_edge(origin, source + last, pixels, cells) >= clip_last do
      last = last - 1
   end
   return first, last
end

-- Resolve only the cells needed for overlays or mouse input. A view keeps
-- its own grid rows, so later observations cannot change a published frame.
local function view_cell(view, column, row)
   column, row = view.source_x + column, view.source_y + row
   local source = view.grid[row % view.grid_height + 1].cells[column % view.grid_width + 1]
   if source == view.current_source then
      source = view.current_cell
   end
   return {
      zone = source.zone,
      x = source.x,
      y = source.y,
      uid = source.uid,
      room = source.room,
      unexplored_uid = source.unexplored_uid,
      entry_rooms = source.entry_rooms,
      entrance_approaches = source.entrance == "unexplored" and view_entrance_approaches(view, source) or nil,
      left = grid_edge(view.raster_x, column, view.raster_width, view.grid_width),
      top = grid_edge(view.raster_y, row, view.raster_height, view.grid_height),
      right = grid_edge(view.raster_x, column + 1, view.raster_width, view.grid_width),
      bottom = grid_edge(view.raster_y, row + 1, view.raster_height, view.grid_height),
   }
end

local function has_overlay(room)
   return room and (room.info and room.info:match("pk") or room.notes and room.notes ~= "")
end

-- Fixed Vidblain appearance. Saved settings do not change this palette.
local vidblain_palette = {
   moon = {colour = 0xff0000, brush = 0, background = 0x000000},
   space1 = {colour = 0x323232, brush = "scattered-dots", background = 0x000000},
   space2 = {colour = 0xc0c0c0, brush = "large-star", background = 0x000000},
   space3 = {colour = 0x808080, brush = "small-star", background = 0x000000},
   space4 = {colour = 0x2d2d2d, brush = "scattered-dots-2", background = 0x000000},
}

function M.new(context, window, options)
   local frame_metrics = options and options.frame_metrics or {}
   local function check_opacity(value)
      assert(value == 0 or value == 25 or value == 50 or value == 100,
         "Invalid Vidblain overlay opacity: " .. tostring(value))
      return value
   end
   local sky_opacity = options and options.vidblain_overlay_opacity
   sky_opacity = check_opacity(sky_opacity == nil and 100 or sky_opacity)
   local api = context.api or _G
   local mini = api.miniwin

   local function same(a, b)
      if a == b then
         return true
      end
      return a and b and a.brush == b.brush and a.entrance == b.entrance and a.colour == b.colour
                and (a.brush == mini.brush_solid or a.background == b.background)
   end

   local state = {
      rooms = {},
      index = {},
      positions = {},
      images = {},
      fit_images = {},
      revision = 0,
      loaded = false,
      destination_areas = {},
      unmapped_links = {},
      entrance_targets = {},
      entrance_entries = {},
      directional_targets = {},
      directional_entries = {},
      unexplored_targets = {},
      unexplored_entries = {},
      pending = {},
      grids = {},
   }
   -- Destination -> positioned continent rooms with an exit to it.
   local incoming = {}
   -- Each unresolved exit is indexed at the tile where the mapper projects it.
   local unmapped_sources_by_tile = {}
   local function update_exit_index(uid, previous, current)
      for dir, dest in pairs(previous) do
         if current[dir] ~= dest then
            local sources = incoming[dest]
            sources[uid] = sources[uid] - 1
            if sources[uid] == 0 then sources[uid] = nil end
            if not next(sources) then incoming[dest] = nil end
         end
      end
      for dir, dest in pairs(current) do
         if previous[dir] ~= dest then
            local sources = incoming[dest] or {}
            sources[uid] = (sources[uid] or 0) + 1
            incoming[dest] = sources
         end
      end
   end
   local update_entrances
   local pattern_images = {}
   local brush_window = window .. "_brush"
   local brush_window_created = false

   local function check(code)
      assert(code == 0, "Continent window call failed: " .. tostring(code))
   end

   local disk_cache = context.cache_prefix and mapper_image_cache.new(api, check, context.cache_prefix,
      context.cache_version or mapper_cache_version)
   state.cache_hits, state.baked_planes = 0, 0
   local zone_for = context.zone_for

   local brush_backgrounds = {}

   local function brush_background(colour)
      local background = brush_backgrounds[colour]
      if background == nil then
         local red = math.floor((colour % 256) * 0.55 + 0.5)
         local green = math.floor((math.floor(colour / 256) % 256) * 0.55 + 0.5)
         local blue = math.floor((math.floor(colour / 65536) % 256) * 0.55 + 0.5)
         background = red + green * 256 + blue * 65536
         brush_backgrounds[colour] = background
      end
      return background
   end

   local function terrain_style(colour, terrain, brush, background, entrance)
      return {
         brush = brush or mini.brush_solid,
         colour = colour,
         background = background or brush_background(colour),
         terrain = terrain,
         entrance = entrance == true,
      }
   end

   local styles = {}
   for terrain, style in pairs(M.terrain_styles) do
      styles[terrain] = terrain_style(style.colour, terrain, style.brush, style.background, style.entrance)
   end

   local vidblain_styles = {}
   for terrain, style in pairs(styles) do
      local fixed = vidblain_palette[terrain]
      vidblain_styles[terrain] = fixed and terrain_style(fixed.colour, terrain, fixed.brush, fixed.background)
         or style
   end

   local brush_period, room_symbols = 8, false
   for _, style in pairs(styles) do
      local brush = style.brush
      room_symbols = room_symbols or M.room_symbols[brush] ~= nil
      local pattern = continent_custom_brushes[brush]
      if pattern and brush_period % pattern.height ~= 0 then
         local a, b = brush_period, pattern.height
         while b ~= 0 do a, b = b, a % b end
         brush_period = brush_period / a * pattern.height
      end
   end

   local function vertical_copies(surface, period_height)
      -- Only the ordinary continents scroll across the vertical seam.
      return surface.zone ~= 6 and period_height % brush_period ~= 0 and 2 or 1
   end

   local function styles_for_zone(zone)
      return zone == 6 and vidblain_styles or styles
   end

   local function room_style(room)
      local zone = zone_for(room.area)
      if zone == 6 and room.uid == "33321" then
         return vidblain_styles.moon
      end
      local style = styles_for_zone(zone)[room.terrain]
      if style then
         return style
      end
      local colour = context.terrain_colour(room.terrain)
      if colour == nil then
         return
      end
      return terrain_style(colour, room.terrain)
   end

   local function remove_from_tile(tiles, key, uid)
      local tile = tiles[key]
      if not tile then return end
      for i = #tile, 1, -1 do
         if tile[i] == uid then table.remove(tile, i) end
      end
      if not tile[1] and not tile.override then tiles[key] = nil end
   end

   local function insert_position(uid, zone, x, y)
      local definition = assert(M.definitions[zone])
      x, y = x % definition.width, y % definition.height
      local previous = state.positions[uid]
      if previous then
         remove_from_tile(state.index[previous.zone], previous.y * M.definitions[previous.zone].width + previous.x, uid)
      end
      local tiles = state.index[zone] or {}
      state.index[zone] = tiles
      local key = y * definition.width + x
      local tile = tiles[key]
      if tile then
         tile[#tile + 1] = uid
         state.positions[uid] = {zone = zone, x = x, y = y}
      else
         -- The first room on a tile uses the tile itself as its position.
         tile = {uid, zone = zone, x = x, y = y}
         tiles[key], state.positions[uid] = tile, tile
      end
   end

   -- Recover the offline numeric grid only when all known cardinal edges agree.
   local function numeric_grid(definition, zone_rooms, repair_seeds)
      local bases, numeric, missing, seeds = {}, {}, false, 0
      for _, uid in ipairs(zone_rooms) do
         local n = tonumber(uid)
         if n then
            numeric[#numeric + 1] = n
         end
         local p = state.positions[uid]
         if n and not p then
            missing = true
         end
         if n and p then
            seeds = seeds + 1
            local b = n - p.y * definition.width - p.x
            bases[b] = (bases[b] or 0) + 1
         end
      end
      local base, best = nil, 0
      for b, n in pairs(bases) do
         if n > best then
            base, best = b, n
         end
      end
      if repair_seeds then
         -- Only a strict majority can correct conflicting stored coordinates.
         if best == seeds or best * 2 <= seeds then
            return
         end
      elseif not missing then
         return
      end
      if not base then
         table.sort(numeric)
         local first = 1
         for i, n in ipairs(numeric) do
            if i > 1 and n ~= numeric[i - 1] + 1 then
               first = i
            end
            if i - first + 1 == definition.width * definition.height then
               base = numeric[first]
               break
            end
         end
      end
      base = base or definition.first_uid
      local candidates = {}
      for _, uid in ipairs(zone_rooms) do
         local numeric_uid = tonumber(uid)
         local offset = numeric_uid and numeric_uid - base
         if offset and offset >= 0 and offset < definition.width * definition.height then
            candidates[uid] = {x = offset % definition.width, y = math.floor(offset / definition.width)}
         end
      end
      local adjacent = repair_seeds and {}
      for uid, p in pairs(candidates) do
         for dir, dest in pairs(state.rooms[uid].exits) do
            local q, offset = candidates[dest], directions[dir]
            if q and offset then
               if (q.x - p.x - offset[1]) % definition.width ~= 0 or (q.y - p.y - offset[2]) % definition.height ~= 0 then
                  return
               end
               if adjacent then
                  adjacent[uid] = adjacent[uid] or {}
                  adjacent[uid][dest] = true
                  adjacent[dest] = adjacent[dest] or {}
                  adjacent[dest][uid] = true
               end
            end
         end
      end
      if repair_seeds then
         -- Each connected component must support this origin on its own.
         -- Cardinal exits constrain coordinates in both directions, even
         -- when an exit is only traversable in one direction.
         local visited = {}
         for first in pairs(candidates) do
            if not visited[first] then
               local queue, head, support, seeds = {first}, 1, 0, 0
               visited[first] = true
               while head <= #queue do
                  local uid = queue[head]
                  head = head + 1
                  local p, seed = candidates[uid], state.positions[uid]
                  if seed then
                     seeds = seeds + 1
                     if seed.x == p.x and seed.y == p.y then
                        support = support + 1
                     end
                  end
                  for dest in pairs(adjacent[uid] or empty_exits) do
                     if not visited[dest] then
                        visited[dest] = true
                        queue[#queue + 1] = dest
                     end
                  end
               end
               if support * 2 <= seeds then
                  for _, uid in ipairs(queue) do
                     candidates[uid] = nil
                  end
               end
            end
         end
      end
      return candidates
   end

   local function build_index()
      state.rooms = context.load_rooms()
      incoming, unmapped_sources_by_tile = {}, {}
      state.index, state.positions, state.grids = {}, {}, {}
      state.destination_areas, state.unmapped_links = {}, {}
      state.entrance_targets, state.entrance_entries = {}, {}
      state.directional_targets, state.directional_entries = {}, {}
      state.unexplored_targets, state.unexplored_entries = {}, {}
      local rooms_by_zone, queue = {}, {}
      for uid, room in pairs(state.rooms) do
         local zone = zone_for(room.area)
         local definition = M.definitions[zone]
         local zone_rooms = rooms_by_zone[zone] or {}
         zone_rooms[#zone_rooms + 1] = uid
         rooms_by_zone[zone] = zone_rooms
         local x, y = tonumber(room.x), tonumber(room.y)
         if x and y and x >= 0 and y >= 0 and x < definition.width and y < definition.height then
            insert_position(uid, zone, x, y)
            queue[#queue + 1] = uid
         end
      end
      -- Repair conflicting seeds before they can displace a whole component.
      -- Pending GMCP observations still apply after this database index is built.
      for zone, definition in pairs(M.definitions) do
         local candidates = numeric_grid(definition, rooms_by_zone[zone] or empty_exits, true)
         for uid, p in pairs(candidates or empty_exits) do
            if state.positions[uid] then
               insert_position(uid, zone, p.x, p.y)
            end
         end
      end
      local head = 1
      while head <= #queue do
         local uid = queue[head]
         head = head + 1
         local p = state.positions[uid]
         for dir, dest in pairs(state.rooms[uid].exits) do
            local offset = directions[dir]
            if offset and state.rooms[dest] and zone_for(state.rooms[dest].area) == p.zone
               and not state.positions[dest] then
               insert_position(dest, p.zone, p.x + offset[1], p.y + offset[2])
               queue[#queue + 1] = dest
            end
         end
      end
      -- Coordinates and complete grids establish the numeric origin. Keep the
      -- fixed offline origin when deleted rooms leave gaps.
      for zone, definition in pairs(M.definitions) do
         local candidates = numeric_grid(definition, rooms_by_zone[zone] or empty_exits)
         for uid, p in pairs(candidates or empty_exits) do
            if not state.positions[uid] then
               insert_position(uid, zone, p.x, p.y)
            end
         end
      end
      state.loaded = true
      -- Entrances must use the same primary room as the displayed tile.
      for _, cells in pairs(state.index) do
         for _, list in pairs(cells) do
            if #list > 1 then table.sort(list, uid_less) end
         end
      end
      for uid, room in pairs(state.rooms) do
         update_exit_index(uid, empty_exits, room.exits)
         update_entrances(uid)
      end
      for uid, observation in pairs(state.pending) do
         state.observe(uid, observation.room, observation.coord)
      end
      state.pending = {}
   end

   local function custom_image(target, style)
      local pattern = assert(continent_custom_brushes[style.brush])
      local images = pattern_images[target] or {}
      pattern_images[target] = images
      local previous = images[style.terrain]
      local id = "continent_brush:" .. style.terrain
      if not previous or previous.brush ~= style.brush or previous.colour ~= style.colour or previous.background
         ~= style.background or api.WindowImageInfo(target, id, 1) == nil then
         check(api.WindowCreate(brush_window, 0, 0, pattern.width, pattern.height, 0, mini.create_ignore_mouse,
            style.background))
         brush_window_created = true
         if pattern.dots then
            for _, dot in ipairs(pattern.dots) do
               local x, y = dot[1], dot[2]
               check(api.WindowRectOp(brush_window, 2, x, y, x + 1, y + 1, style.colour))
            end
         else
            for y, row in ipairs(pattern.rows) do
               for first, last in row:gmatch("()#+()") do
                  check(api.WindowRectOp(brush_window, 2, first - 1, y - 1, last - 1, y, style.colour))
               end
            end
         end
         check(api.WindowImageFromWindow(target, id, brush_window))
         images[style.terrain] = {brush = style.brush, colour = style.colour, background = style.background}
      end
      return id
   end

   local function custom_rectangle(target, style, left, top, right, bottom, patch)
      local id = custom_image(target, style)
      if patch and patch.origin_x then
         -- A Vidblain tile and its border fit within one period of either star pattern.
         -- Start at the map pixel so the cropped pattern lines up with the rest of the sky.
         local pattern = continent_custom_brushes[style.brush]
         local xs = split_axis(left, patch.origin_x + left, pattern.width, left, right, 1)
         local ys = split_axis(top, patch.origin_y + top, pattern.height, top, bottom, 1)
         for _, y in ipairs(ys) do
            for _, x in ipairs(xs) do
               check(api.WindowDrawImage(target, id, x.left, y.left, x.left + x.length, y.left + y.length, 1,
                  x.source, y.source, x.source + x.length, y.source + y.length))
            end
         end
      else
         check(api.WindowImageOp(target, mini.circle_rectangle, left, top, right + 1, bottom + 1, style.colour,
            mini.pen_null, 0, style.background, id))
      end
   end

   function state.set_vidblain_overlay_opacity(opacity)
      opacity = check_opacity(opacity)
      if sky_opacity == opacity then return false end
      sky_opacity = opacity
      return true
   end

   function state.invalidate_rooms()
      state.loaded = false
      state.revision = state.revision + 1
   end

   local function invalidate_cell(zone, key)
      local had_entrance = false
      local d = M.definitions[zone]
      local x, y = key % d.width, math.floor(key / d.width)
      for _, grid in pairs(state.grids) do
         local gx, gy = x + (grid.zone and 0 or d.x), y + (grid.zone and 0 or d.y)
         local line = grid.rows[gy + 1]
         local source = line and line.cells[gx + 1]
         if source and source.zone == zone then
            source.stale = true
            had_entrance = had_entrance or source.entrance
            grid.dirty[gy + 1] = true
         end
      end
      return had_entrance
   end

   -- Published views retain their room records. Replace only the edited data.
   function state.update_room_metadata(uid, cached, direction)
      local pending = state.pending[uid]
      local room = pending and pending.room or state.rooms[uid]
      if not room then return end

      local updated
      if direction then
         local level = cached.exit_locks[direction]
         if not room.exits[direction] or room.exit_locks[direction] == level then return end
         updated = copytable.shallow(room)
         updated.exit_locks = copytable.shallow(room.exit_locks)
         updated.exit_locks[direction] = level
      else
         if room.notes == cached.notes then return end
         updated = copytable.shallow(room)
         updated.notes = cached.notes
      end

      if pending then
         pending.room = updated
      else
         state.rooms[uid] = updated
         local position = state.positions[uid]
         if state.loaded and position then
            invalidate_cell(position.zone, position.y * M.definitions[position.zone].width + position.x)
         end
      end
   end

   local function each_projected_image(zone, key, visit)
      local d = M.definitions[zone]
      local x, y = key % d.width + d.x, math.floor(key / d.width) + d.y
      local function visit_map(name)
         local fixed, fit = state.images[name], state.fit_images[name]
         if (fixed or fit) and (zone == 6 or projected_row(name == "inner_sea", y)[x] == zone) then
            local pos = zone == 6 and key or y * 120 + x
            if fixed then visit(fixed, false, pos) end
            if fit then visit(fit, true, pos) end
         end
      end
      if zone == 6 then
         visit_map("6")
      else
         visit_map("stitched")
         visit_map("inner_sea")
      end
   end

   local ROOM_PATCH, BORDER_PATCH, SURROUNDING_TILES_PATCH = 1, 2, 3

   local function queue_patch(image, pos, kind)
      image.patches = image.patches or {}
      image.patches[pos] = math.max(image.patches[pos] or 0, kind)
   end

   local function mark_dirty(zone, key)
      local had_entrance = invalidate_cell(zone, key)
      each_projected_image(zone, key, function(image, fit, pos)
         if zone == 6 then
            if fit then image.star_background_cached = nil end
            queue_patch(image, pos, had_entrance and BORDER_PATCH or ROOM_PATCH)
         elseif fit or image.missing then
            -- Unpainted zoom tiles read the updated grid when they are first drawn.
            queue_patch(image, pos, ROOM_PATCH)
         else
            queue_patch(image, pos, SURROUNDING_TILES_PATCH)
            image.save_after_patch = disk_cache ~= nil
         end
      end)
   end

   local function mark_neighbors(tiles, width, height, x, y, first)
      for dy = first, 1 do
         for dx = first, 1 do
            tiles[((y + dy) % height) * width + (x + dx) % width] = true
         end
      end
   end

   local function collect_tile_sources(affected, zone, key)
      -- Rooms sharing this tile can gain or lose a zero-distance entrance.
      for _, source in ipairs(state.index[zone][key] or empty_exits) do
         if state.unmapped_links[source] or state.entrance_targets[source] then
            affected[source] = true
         end
      end
      for source in pairs(unmapped_sources_by_tile[zone .. ":" .. key] or empty_exits) do
         affected[source] = true
      end
   end

   function state.destination_changed(uid, area)
      if not state.loaded then return end
      local sources = incoming[uid]
      state.destination_areas[uid] = sources and area
      for source in pairs(sources or empty_exits) do
         local room = state.rooms[source]
         if room.exit_areas then
            for dir, dest in pairs(room.exits) do
               if dest == uid then room.exit_areas[dir] = area end
            end
         end
         update_entrances(source)
      end
   end

   function state.remove_room(uid, keep_area)
      local function remove_incoming(room)
         if keep_area and room.area == keep_area then return false end
         local changed = false
         for dir, dest in pairs(room.exits) do
            if dest == uid then
               room.exits[dir] = nil
               room.exit_locks[dir] = nil
               if room.exit_areas then
                  room.exit_areas[dir] = nil
               end
               changed = true
            end
         end
         return changed
      end

      state.pending[uid] = nil
      for _, observation in pairs(state.pending) do
         remove_incoming(observation.room)
      end
      if not state.loaded then
         return
      end
      local position = state.positions[uid]
      if state.rooms[uid] then update_exit_index(uid, state.rooms[uid].exits, empty_exits) end
      state.rooms[uid], state.positions[uid], state.destination_areas[uid] = nil, nil, nil
      local affected = {}
      if position then
         local zone = position.zone
         local key = position.y * M.definitions[zone].width + position.x
         state.index[zone][key].override = nil
         remove_from_tile(state.index[zone], key, uid)
         mark_dirty(zone, key)
         collect_tile_sources(affected, zone, key)
      end
      local sources = incoming[uid]
      if sources then
         for source in pairs(sources) do
            if remove_incoming(state.rooms[source]) then sources[source] = nil end
            affected[source] = true
         end
         if not next(sources) then incoming[uid] = nil end
      end
      update_entrances(uid)
      affected[uid] = nil
      for source in pairs(affected) do
         update_entrances(source)
      end
   end

   function state.observe(uid, room, coord)
      local zone = tonumber(coord.id)
      if tostring(coord.cont) ~= "1" or not M.definitions[zone] then
         return
      end
      local x, y = tonumber(coord.x), tonumber(coord.y)
      if not x or not y or x < 0 or y < 0 or x >= M.definitions[zone].width or y >= M.definitions[zone].height then
         return
      end
      if not state.loaded then
         state.pending[uid] = {room = room, coord = {id = zone, cont = "1", x = x, y = y}}
         return
      end
      local previous_position = state.positions[uid]
      local previous_room = state.rooms[uid]
      local was_known = previous_room ~= nil
      local key = y * M.definitions[zone].width + x
      local list = state.index[zone] and state.index[zone][key]
      local primary = list and state.rooms[list[1]]
      room.uid = uid
      local style = room_style(room)
      local previous_override = list and list.override
      local old = previous_override
      if not old and primary then
         if primary.uid == uid and primary.area == room.area and primary.terrain == room.terrain then
            old = style
         else
            old = room_style(primary)
         end
      end
      state.destination_areas[uid] = nil
      update_exit_index(uid, previous_room and previous_room.exits or empty_exits, room.exits)
      state.rooms[uid] = room
      local style_changed = not same(style, old)
      local position_changed = previous_position
                                  and (previous_position.zone ~= zone or previous_position.x ~= x
                                     or previous_position.y ~= y)
      -- At shared coordinates a new observation moves its UID to the end of the list.
      local reindexed = not previous_position or position_changed or list[#list] ~= uid
      if reindexed then insert_position(uid, zone, x, y) end
      list = state.index[zone][key]
      local primary_uid = list[1]
      -- Keep an observed cell correction even when its UID differs from the
      -- database room at that coordinate. A database reload retires it.
      local override
      if style and primary_uid ~= uid and not same(style, room_style(state.rooms[primary_uid])) then
         override = style
      end
      list.override = override
      if style_changed or position_changed or (zone == 6 and not primary) then
         mark_dirty(zone, key)
      end
      update_entrances(uid)
      if reindexed or style_changed or not same(previous_override, override) then
         local affected = {}
         collect_tile_sources(affected, zone, key)
         if position_changed then
            collect_tile_sources(affected, previous_position.zone,
               previous_position.y * M.definitions[previous_position.zone].width + previous_position.x)
         end
         if not was_known then
            for source in pairs(incoming[uid] or empty_exits) do affected[source] = true end
         end
         affected[uid] = nil
         for source in pairs(affected) do update_entrances(source) end
      end
      -- Room metadata can change without a terrain patch.
      if position_changed then
         mark_dirty(previous_position.zone,
            previous_position.y * M.definitions[previous_position.zone].width + previous_position.x)
      elseif not style_changed then
         invalidate_cell(zone, key)
      end
   end

   local function cell(zone, x, y, current_uid)
      local definition = M.definitions[zone]
      local key = y * definition.width + x
      local list = state.index[zone] and state.index[zone][key]
      local uid = list and list[1]
      local current = state.positions[current_uid]
      if current and current.zone == zone and current.x == x and current.y == y then
         uid = current_uid
      end
      local room = uid and state.rooms[uid]
      local style = list and list.override or room and room_style(room)
      local result = {zone = zone, x = x, y = y, uid = uid, room = room, style = style,
         overlay = has_overlay(room), entry_rooms = empty_exits}
      -- A different room at this coordinate can become the current room.
      if not result.overlay and list and #list > 1 then
         for _, other in ipairs(list) do
            if has_overlay(state.rooms[other]) then
               result.overlay = true
               break
            end
         end
      end
      -- A saved exit supplies an unexplored room's ID without its metadata.
      local unknown = not uid and state.unexplored_entries[zone] and state.unexplored_entries[zone][key]
      if unknown then
         for dest in pairs(unknown) do
            if not state.rooms[dest] and (not result.unexplored_uid or uid_less(dest, result.unexplored_uid)) then
               result.unexplored_uid = dest
            end
         end
      end
      local entry_counts = state.directional_entries[zone] and state.directional_entries[zone][key]
      if entry_counts and next(entry_counts) then
         local entry_rooms = {}
         for entry_uid in pairs(entry_counts) do
            entry_rooms[#entry_rooms + 1] = entry_uid
         end
         table.sort(entry_rooms, uid_less)
         result.entry_rooms = entry_rooms
      end
      local entrances = state.entrance_entries[zone] and state.entrance_entries[zone][key]
      if entrances and next(entrances) then
         result.entrance = "border"
      elseif style == styles_for_zone(zone).areaexit then
         result.entrance = "unexplored"
      elseif style and style.entrance then
         result.entrance = "border"
      end
      return result
   end

   local function surface_cell(surface, x, y, other)
      if surface.zone then return cell(surface.zone, x, y) end
      local zone = projected_row(surface.inner_sea, y)[x]
      if zone then
         if other and not other.stale and other.zone == zone then return other end
         local d = M.definitions[zone]
         return cell(zone, x - d.x, y - d.y)
      end
   end

   local function cell_style(cell)
      return cell.style
   end

   local function space4_background(cell)
      if cell.style and cell.style.terrain == "space4" then return vidblain_styles.space4 end
   end

   local function missing_room_background(cell)
      if not cell.uid then return vidblain_styles.space1 end
   end

   local function known_rooms(line, first, last)
      local count = 0
      for x = first + 1, last do
         if line.cells[x].uid then count = count + 1 end
      end
      return count
   end

   -- All brush layers combine consecutive cells with the same style.
   local function each_brush_run(surface, copies_y, visit, style_for, bounds)
      style_for = style_for or cell_style
      local function scan_row(row, first, last)
         local line = surface.rows[row % surface.height + 1]
         if style_for == missing_room_background and known_rooms(line, first, last) == last - first then
            return
         end
         local run_style, run_first
         for column = first, last do
            local style = column < last and style_for(line.cells[column + 1]) or nil
            if style ~= run_style then
               if run_style then
                  visit(run_style, run_first, column, row)
               end
               run_style, run_first = style, column
            end
         end
      end

      if bounds then
         for row = bounds[2], bounds[4] - 1 do scan_row(row, bounds[1], bounds[3]) end
      else
         for row = 0, surface.height * copies_y - 1 do
            scan_row(row, 0, surface.width)
         end
      end
   end

   local function symbol_columns(line)
      if not line.symbols then
         local symbols = {}
         for column, source in ipairs(line.cells) do
            local style = source.style
            if style and M.room_symbols[style.brush] then symbols[#symbols + 1] = column - 1 end
         end
         line.symbols = symbols
      end
      return line.symbols
   end

   local function each_room_symbol(surface, bounds, visit)
      local x1, y1, x2, y2 = 0, 0, surface.width, surface.height
      if bounds then x1, y1, x2, y2 = unpack(bounds) end
      for y = y1, y2 - 1 do
         local line = surface.rows[y % surface.height + 1]
         for _, x in ipairs(symbol_columns(line)) do
            if x >= x2 then break end
            if x >= x1 then
               local style = line.cells[x + 1].style
               visit(x, y, style, M.room_symbols[style.brush])
            end
         end
      end
   end

   function state.room_grid(zone, inner_sea)
      if not state.loaded then build_index() end
      local key = zone and tostring(zone) or (inner_sea and "inner_sea" or "stitched")
      local grid = state.grids[key]
      if grid and not next(grid.dirty) then
         return grid
      end
      if not grid then
         local d = zone and assert(M.definitions[zone])
         grid = {key = key, zone = zone, inner_sea = inner_sea, width = d and d.width or 120,
            height = d and d.height or 95, rows = {}, dirty = {}}
      end
      local other = not zone and state.grids[inner_sea and "stitched" or "inner_sea"]
      local rows = {}
      for y = 0, grid.height - 1 do
         local previous = grid.rows[y + 1]
         local line = not grid.dirty[y + 1] and previous
         if not line and other and not other.dirty[y + 1] and projected_row(false, y) == projected_row(true, y) then
            line = other.rows[y + 1]
         end
         if not line then
            line = {cells = {}, overlays = {}, entrances = {}}
            local other_line = other and other.rows[y + 1]
            for x = 0, grid.width - 1 do
               local source = previous and previous.cells[x + 1]
               if not source or source.stale then
                  source = surface_cell(grid, x, y, other_line and other_line.cells[x + 1])
               end
               line.cells[x + 1] = source
               if source.entrance then line.entrances[#line.entrances + 1] = x end
               if source.overlay then
                  line.overlays[#line.overlays + 1] = x
               end
            end
         end
         rows[y + 1] = line
      end
      grid.rows, grid.dirty = rows, {}
      state.grids[key] = grid
      return grid
   end

   local function paint_brushes(target, surface, style_for, bounds)
      local ox, oy = target.origin_x or 0, target.origin_y or 0
      local period_height = target.period_height or target.height / target.copies_y
      local fixed_terrain = not target.period_height and surface.zone ~= 6
      each_brush_run(surface, target.copies_y, function(style, first, last, row)
         local brush = style.brush
         if brush == mini.brush_null then return end
         local left = math.floor(first * target.width / surface.width) - ox
         local right = math.floor(last * target.width / surface.width) - ox
         local top = math.floor(row * period_height / surface.height) - oy
         local bottom = math.floor((row + 1) * period_height / surface.height) - oy
         if left >= right or top >= bottom then return end
         if target.origin_x then
            left, top = math.max(left, 0), math.max(top, 0)
            right, bottom = math.min(right, target.clip_width), math.min(bottom, target.clip_height)
            if left >= right or top >= bottom then return end
         end

         local fill = brush == mini.brush_solid and style.colour or style.background
         if continent_custom_brushes[brush] then
            custom_rectangle(target.window, style, left, top, right, bottom, surface.zone == 6 and target)
         elseif M.room_symbols[brush] or (brush == mini.brush_solid and not fixed_terrain) then
            check(api.WindowRectOp(target.window, 2, left, top, right, bottom, fill))
         elseif fixed_terrain or (type(brush) == "number" and brush > mini.brush_null) then
            -- Fixed terrain and native pattern brushes use the null-pen rectangle bounds.
            check(api.WindowCircleOp(target.window, mini.circle_rectangle, left, top, right + 1, bottom + 1,
               style.colour, mini.pen_null, 0, fill, brush))
         end
      end, style_for, bounds)
   end

   local function paint_fitted_star_background(image, scaled, surface, bounds)
      local id = "continent_star_background"
      if not bounds and image.star_background_cached and api.WindowImageInfo(scaled.window, id, 2) == scaled.width
         and api.WindowImageInfo(scaled.window, id, 3) == scaled.height then
         check(api.WindowDrawImage(scaled.window, id, 0, 0, 0, 0, 1))
         return
      end
      custom_rectangle(scaled.window, vidblain_styles.space1, 0, 0, scaled.clip_width or scaled.width,
         scaled.clip_height or scaled.height, scaled)
      paint_brushes(scaled, surface, space4_background, bounds)
      if not bounds then
         check(api.WindowImageFromWindow(scaled.window, id, scaled.window))
         image.star_background_cached = true
      end
   end

   -- Each source contributes once to each destination at a projected cell.
   -- Area entries and unexplored rooms use the same reference-count update.
   local function update_destination_counts(previous, wanted, entries, count_error, markers)
      local function update(target, before, after)
         local zone_entries = entries[target.zone] or {}
         entries[target.zone] = zone_entries
         local counts = zone_entries[target.key] or {}
         zone_entries[target.key] = counts
         local had_entries = next(counts) ~= nil
         local changed = false
         for dest in pairs(before or empty_exits) do
            if not after or not after[dest] then
               local count = counts[dest] - 1
               assert(count >= 0, count_error)
               counts[dest] = count > 0 and count or nil
               changed = true
            end
         end
         for dest in pairs(after or empty_exits) do
            if not before or not before[dest] then
               counts[dest] = (counts[dest] or 0) + 1
               changed = true
            end
         end
         if changed then
            invalidate_cell(target.zone, target.key)
            if markers and had_entries ~= (next(counts) ~= nil) then
               each_projected_image(target.zone, target.key, function(image, _, pos)
                  queue_patch(image, pos, BORDER_PATCH)
               end)
            end
         end
      end

      for key, target in pairs(previous) do
         update(target, target.entries, wanted[key] and wanted[key].entries)
      end
      for key, target in pairs(wanted) do
         if not previous[key] then
            update(target, nil, target.entries)
         end
      end
   end

   update_entrances = function(uid)
      local previous = state.entrance_targets[uid] or empty_exits
      local wanted = {}
      local previous_directional = state.directional_targets[uid] or empty_exits
      local directional = {}
      local old_unknown = state.unexplored_targets[uid] or empty_exits
      local unknown = {}
      local position = state.positions[uid]
      local room = state.rooms[uid]
      local unmapped_tiles
      if position and room then
         local source
         for dir, dest in pairs(room.exits) do
            local destination = state.rooms[dest]
            local area = room.exit_areas and room.exit_areas[dir]
            if not destination and area == nil then
               area = state.destination_areas[dest]
               if area == nil then
                  area = context.destination_area(dest) or false
                  state.destination_areas[dest] = area
               end
            end
            if not destination and (not area or area ~= room.area and zone_for(area) == nil) then
               source = source or cell(position.zone, position.x, position.y, uid)
               local offset = directions[dir]
               local target = source
               -- Area cells and exits without a map direction have no map distance.
               -- Other connections point to the area cell in their exit direction.
               if offset and not (source.style and source.style.entrance) then
                  local d = M.definitions[position.zone]
                  if position.zone == 6 then
                     target = cell(6, (position.x + offset[1]) % d.width, (position.y + offset[2]) % d.height)
                  else
                     local surface = {inner_sea = position.zone == 5 and position.x < 30 and position.y < 10}
                     target = surface_cell(surface, (position.x + d.x + offset[1]) % 120,
                        (position.y + d.y + offset[2]) % 95)
                  end
               end
               local key = target.y * M.definitions[target.zone].width + target.x
               local target_key = target.zone .. ":" .. key
               if not area then
                  unmapped_tiles = unmapped_tiles or {}
                  unmapped_tiles[target_key] = true
               end
               -- An unexplored destination has no area record. The database
               -- or GMCP area terrain must identify its projected area cell.
               if area or target.style and target.style.entrance then
                  local record = wanted[target_key] or {zone = target.zone, key = key, entries = {}}
                  record.entries[dest] = true
                  wanted[target_key] = record
                  -- Only compass exits supply area destinations for clicks.
                  if offset then
                     local entry = directional[target_key] or {zone = target.zone, key = key, entries = {}}
                     entry.entries[dest] = true
                     directional[target_key] = entry
                  end
               elseif not target.uid then
                  local record = unknown[target_key] or {zone = target.zone, key = key, entries = {}}
                  record.entries[dest] = true
                  unknown[target_key] = record
               end
            end
         end
      end
      -- Keep unexplored click targets while any known exit points to them.
      -- These targets do not add terrain or area entrance boxes.
      update_destination_counts(old_unknown, unknown, state.unexplored_entries,
         "Negative unexplored continent room count")
      state.unexplored_targets[uid] = next(unknown) and unknown or nil
      -- The border stays visible while any source has an exit to the area.
      update_destination_counts(previous, wanted, state.entrance_entries, "Negative continent entry room count", true)
      state.entrance_targets[uid] = next(wanted) and wanted or nil
      update_destination_counts(previous_directional, directional, state.directional_entries,
         "Negative directional entrance room count")
      state.directional_targets[uid] = next(directional) and directional or nil

      -- Index each source room once per tile, even when several exits land there.
      local previous_tiles = state.unmapped_links[uid]
      if previous_tiles then
         for tile in pairs(previous_tiles) do
            local sources = unmapped_sources_by_tile[tile]
            sources[uid] = nil
            if not next(sources) then unmapped_sources_by_tile[tile] = nil end
         end
      end
      if unmapped_tiles then
         for tile in pairs(unmapped_tiles) do
            local sources = unmapped_sources_by_tile[tile] or {}
            sources[uid] = true
            unmapped_sources_by_tile[tile] = sources
         end
      end
      state.unmapped_links[uid] = unmapped_tiles
   end

   local function cache_identity(surface, image)
      if not disk_cache or surface.zone == 6 then return end
      local parts = {table.concat({image.size, image.width, image.height, image.copies_y}, ":") .. ";"}
      local style_keys = {}
      for y = 0, surface.height - 1 do
         local cells = surface.rows[y + 1].cells
         for x = 0, surface.width - 1 do
            local c = cells[x + 1]
            local style = c and c.style
            local style_key = "-"
            if style then
               style_key = style_keys[style]
               if not style_key then
                  style_key = string.format("%q,%q,%q,%s,", tostring(style.brush), tostring(style.colour),
                     tostring(style.background), style.entrance and "1" or "0")
                  style_keys[style] = style_key
               end
            end
            -- Grid order supplies position. Only appearance affects this ordinary atlas.
            parts[#parts + 1] = style_key .. (c and c.entrance and "1;" or "0;")
         end
      end
      return surface.key, disk_cache.key(parts)
   end

   local function marker(target, surface, c, x, y, bounds)
      local height = target.period_height or target.height / target.copies_y
      local left = grid_edge(0, x, target.width, surface.width)
      local top = grid_edge(0, y, height, surface.height)
      local right = grid_edge(0, x + 1, target.width, surface.width) + 1
      local bottom = grid_edge(0, y + 1, height, surface.height) + 1
      if target.period_height then
         right, bottom = math.min(target.width, right), math.min(target.height, bottom)
      end
      if target.origin_x then
         left, right = left - target.origin_x, right - target.origin_x
         top, bottom = top - target.origin_y, bottom - target.origin_y
         if right <= 0 or bottom <= 0 or left >= target.clip_width or top >= target.clip_height then return end
      end
      local style = c.style
      local marker_style = style and style.entrance and style or styles_for_zone(c.zone).areaexit
      if bounds and (x < bounds[1] or y < bounds[2] or x + 1 == bounds[3] or y + 1 == bounds[4]) then
         local l, t, r, b = bounds[1] * target.pitch, bounds[2] * target.pitch,
            bounds[3] * target.pitch, bounds[4] * target.pitch
         local function edge(x1, y1, x2, y2)
            x1, y1, x2, y2 = math.max(l, x1), math.max(t, y1), math.min(r, x2), math.min(b, y2)
            if x1 < x2 and y1 < y2 then
               check(api.WindowRectOp(target.window, 2, x1, y1, x2, y2, marker_style.colour))
            end
         end
         edge(left, top, right, top + 1)
         edge(left, bottom - 1, right, bottom)
         edge(left, top + 1, left + 1, bottom - 1)
         edge(right - 1, top + 1, right, bottom - 1)
         return
      end
      check(api.WindowCircleOp(target.window, mini.circle_rectangle, left, top, right,
         bottom, marker_style.colour, mini.pen_solid, 1, 0, mini.brush_null))
   end

   local function paint_sky_artwork(image, surface, bounds)
      local pitch = VIDBLAIN_MAX_ROOM_SIZE - 1
      local width, height = surface.width * pitch, surface.height * pitch
      local sx, sy, ex, ey = 0, 0, width, height
      local left, top = -(image.origin_x or 0), -(image.origin_y or 0)
      local right, bottom = left + image.width, top + image.height
      if not image.period_height then
         -- Fixed views can draw an exact tile crop. Fitted patches retain the full image scale.
         local x1, y1, x2, y2 = unpack(bounds)
         left, top, right, bottom = x1 * image.pitch, y1 * image.pitch, x2 * image.pitch, y2 * image.pitch
         sx, sy, ex, ey = x1 * pitch, y1 * pitch, x2 * pitch, y2 * pitch
      end
      local function layer(plane, opacity)
         local id, loaded = mapper_bitmap.load_layer(api, check, image, plane, artwork_files[plane],
            width, height)
         if loaded then state.baked_planes = state.baked_planes + 1 end
         local started = frame_metrics.enabled and not image.period_height and opacity < 1 and api.utils.timer()
         check(api.WindowDrawImageAlpha(image.window, id, left, top, right, bottom, opacity, sx, sy, ex, ey))
         if started then
            frame_metrics.total_continent_blend_time = frame_metrics.total_continent_blend_time + api.utils.timer() - started
         end
      end
      if sky_opacity > 0 then layer("optional", sky_opacity / 100) end
      layer("core", 1)
      paint_brushes(image, surface, missing_room_background, bounds)
   end

   local function paint_entrances(target, surface, bounds)
      local x1, y1, x2, y2 = unpack(bounds)
      local clip
      if not target.period_height then
         -- Fixed borders can extend into the crop from above and from the left.
         x1, y1 = math.max(0, x1 - 1), math.max(0, y1 - 1)
         clip = bounds
      end
      for y = y1, y2 - 1 do
         local line = surface.rows[y % surface.height + 1]
         for _, x in ipairs(line.entrances) do
            if x >= x2 then break end
            if x >= x1 then marker(target, surface, line.cells[x + 1], x, y, clip) end
         end
      end
   end

   local function paint_fixed(image, surface, bounds)
      local x1, y1, x2, y2 = unpack(bounds)
      local pitch = image.pitch
      local left, top, right, bottom = x1 * pitch, y1 * pitch, x2 * pitch, y2 * pitch
      if surface.zone == 6 then
         custom_rectangle(image.window, vidblain_styles.space1, left, top, right, bottom)
         -- The star background already covers a crop with no known rooms.
         for y = y1, y2 - 1 do
            if known_rooms(surface.rows[y + 1], x1, x2) > 0 then
               paint_brushes(image, surface, space4_background, bounds)
               paint_sky_artwork(image, surface, bounds)
               break
            end
         end
      else
         paint_brushes(image, surface, nil, bounds)
         if room_symbols then
            local function fill(x1, y1, x2, y2, colour)
               check(api.WindowRectOp(image.window, 2, x1, y1, x2, y2, colour))
            end
            each_room_symbol(surface, bounds, function(x, y, style, paint)
               paint(fill, style, x * pitch, y * pitch, pitch)
            end)
         end
      end
      paint_entrances(image, surface, bounds)
   end

   local function each_fixed_patch(image, surface, visit)
      local cells = {}
      for pos, kind in pairs(image.patches) do
         local x, y = pos % surface.width, math.floor(pos / surface.width)
         if surface.zone ~= 6 then
            mark_neighbors(cells, surface.width, surface.height, x, y, kind == SURROUNDING_TILES_PATCH and -1 or 0)
         elseif kind == BORDER_PATCH or surface.rows[y + 1].cells[x + 1].entrance then
            -- The bottom and right pixels of a border can fall in the adjacent tiles.
            for row = y, math.min(y + 1, surface.height - 1) do
               for col = x, math.min(x + 1, surface.width - 1) do cells[row * surface.width + col] = true end
            end
         else
            cells[pos] = true
         end
      end
      for pos in pairs(cells) do
         local x, y = pos % surface.width, math.floor(pos / surface.width)
         visit(x, y)
      end
   end

   -- Missing rectangles are disjoint and use integer room coordinates. Subtract
   -- a rectangle only after the native draw succeeds, so a failed draw can retry.
   local function fill_missing(image, wanted)
      local missing = image.missing
      for i = #missing, 1, -1 do
         local r = missing[i]
         local l, t = math.max(r[1], wanted[1]), math.max(r[2], wanted[2])
         local right, b = math.min(r[3], wanted[3]), math.min(r[4], wanted[4])
         if l < right and t < b then
            paint_fixed(image, image.surface, {l, t, right, b})
            table.remove(missing, i)
            if r[2] < t then missing[#missing + 1] = {r[1], r[2], r[3], t} end
            if b < r[4] then missing[#missing + 1] = {r[1], b, r[3], r[4]} end
            if r[1] < l then missing[#missing + 1] = {r[1], t, l, b} end
            if right < r[3] then missing[#missing + 1] = {right, t, r[3], b} end
            image.version = image.version + 1
         end
      end
   end

   local function finish_image(image)
      if disk_cache and not image.surface.zone then
         local slot, identity = cache_identity(image.surface, image)
         disk_cache.save(slot, identity, image)
      end
      image.missing, image.surface = nil, nil
      if state.zoom_image == image then state.zoom_image = nil end
   end

   -- Zoom requests paint only their source rectangles. Other builds can load a complete disk image.
   local function update_image(surface, size, visible, copies_y)
      local key = surface.key
      local image = state.images[key]
      local image_status = "reused"
      local pitch = size - 1
      local vidblain = surface.zone == 6
      local atlas_t0 = frame_metrics.enabled and api.utils.timer()
      if not image or image.size ~= size or image.revision ~= state.revision
         or (vidblain and image.sky_opacity ~= sky_opacity) then
         copies_y = copies_y or vertical_copies(surface, surface.height * pitch)
         -- Rebuilding reuses the native window. Its old metadata must not
         -- become valid again if drawing fails and settings are restored.
         if image then
            image.revision = nil
         end
         image = {
            window = window .. "_" .. key,
            size = size,
            pitch = pitch,
            copies_y = copies_y,
            sky_opacity = sky_opacity,
            loaded_layers = image and image.loaded_layers,
            version = (image and image.version or 0) + 1,
         }
         image.width = surface.width * pitch
         image.height = surface.height * pitch * copies_y
         check(api.WindowCreate(image.window, 0, 0, image.width, image.height, 0, mini.create_ignore_mouse,
            EMPTY_COLOUR))
         -- Store the window so it can be deleted if drawing fails.
         state.images[key] = image
         local all = {0, 0, surface.width, surface.height * copies_y}
         if visible then
            image.missing = {all}
            image.surface = surface
         else
            local slot, identity = cache_identity(surface, image)
            local loaded = slot and disk_cache.load(slot, identity, image)
            if loaded then
               state.cache_hits = state.cache_hits + 1
            else
               paint_fixed(image, surface, all)
               if slot then image.cache_pending = {slot, identity} end
            end
            image_status = loaded and "loaded" or "rebuilt"
         end
         image.revision = state.revision
         if visible then image_status = "rebuilt" end
      end
      if image.patches then
         local painted = false
         each_fixed_patch(image, surface, function(x, y)
            for copy = 0, image.copies_y - 1 do
               local row = y + copy * surface.height
               local pending = false
               for _, r in ipairs(image.missing or empty_exits) do
                  if x >= r[1] and x < r[3] and row >= r[2] and row < r[4] then pending = true; break end
               end
               if not pending then
                  if not vidblain then
                     check(api.WindowRectOp(image.window, 2, x * pitch, row * pitch, (x + 1) * pitch,
                        (row + 1) * pitch, EMPTY_COLOUR))
                  end
                  paint_fixed(image, surface, {x, row, x + 1, row + 1})
                  painted = true
               end
            end
         end)
         if painted then
            image.version = image.version + 1
            image_status = "patched"
         end
         if image.save_after_patch then
            image.cache_pending = {cache_identity(surface, image)}
            image.save_after_patch = nil
         end
         image.patches = nil
      end
      if image.missing then
         if visible then
            for _, r in ipairs(visible) do
               fill_missing(image, {math.floor(r[6] / pitch), math.floor(r[7] / pitch),
                  math.ceil(r[8] / pitch), math.ceil(r[9] / pitch)})
            end
            if not image.missing[1] and not (disk_cache and not vidblain) then
               finish_image(image)
            elseif state.zoom_image ~= image then
               state.zoom_image, state.zoom_due = image, api.utils.timer() + 0.20
            end
         else
            while image.missing[1] do fill_missing(image, image.missing[1]) end
            finish_image(image)
         end
      end
      if image.cache_pending then
         disk_cache.save(image.cache_pending[1], image.cache_pending[2], image)
         image.cache_pending = nil
      end
      if atlas_t0 then
         frame_metrics.total_continent_atlas_time = frame_metrics.total_continent_atlas_time
            + api.utils.timer() - atlas_t0
      end
      return image, image_status
   end

   -- OnPluginTick services one replaceable deadline, including when world timers are disabled.
   function state.finish_zoom()
      local image = state.zoom_image
      if not image then return end
      if image ~= state.images[image.surface.key] or image.revision ~= state.revision
         or image.surface.zone == 6 and image.sky_opacity ~= sky_opacity then
         state.zoom_image = nil
         return
      end
      if image.patches then
         update_image(state.room_grid(image.surface.zone, image.surface.inner_sea), image.size, {})
      end
      if not image.missing then return end
      local r = image.missing[1]
      if r then
         -- Limit the amount of drawing in a single UI tick.
         local cells = image.surface.zone == 6 and 48 or 480
         local rows = math.max(1, math.floor(cells / (r[3] - r[1])))
         fill_missing(image, {r[1], r[2], r[3], math.min(r[4], r[2] + rows)})
         if image.missing[1] then return true end
      end
      finish_image(image)
   end

   -- Keep the normal fitted image as the source throughout a resize drag.
   local function resize_preview(image, width, period_height, copies_y)
      local source = image.scaled
      local preview = state.resize_preview or {window = window .. "_resize_preview", version = 0}
      local height = period_height * copies_y
      local capture = preview.source ~= source or preview.source_version ~= source.version
      if capture or preview.width ~= width or preview.height ~= height or preview.period_height ~= period_height then
         preview.width = nil
         check(api.WindowCreate(preview.window, 0, 0, width, height, 0, mini.create_ignore_mouse, EMPTY_COLOUR))
         state.resize_preview = preview
         if capture then
            check(api.WindowImageFromWindow(preview.window, "source", source.window))
            preview.source, preview.source_version = source, source.version
         end
         for copy = 0, copies_y - 1 do
            local source_top = (copy % source.copies_y) * source.period_height
            check(api.WindowDrawImageAlpha(preview.window, "source", 0, copy * period_height,
               width, (copy + 1) * period_height, 1, 0, source_top,
               source.width, source_top + source.period_height))
         end
         preview.width, preview.height = width, height
         preview.period_height, preview.copies_y = period_height, copies_y
         preview.version = preview.version + 1
      end
      return preview
   end

   local function paint_fit(image, scaled, surface, bounds)
      if surface.zone == 6 then
         paint_fitted_star_background(image, scaled, surface, bounds)
         paint_sky_artwork(scaled, surface, bounds)
      else
         paint_brushes(scaled, surface, nil, bounds)
         mapper_bitmap.draw_symbols(api, check, scaled, surface, image.pitch, bounds, each_room_symbol)
      end
      -- Entrance borders go above all artwork.
      paint_entrances(scaled, surface, bounds or {0, 0, surface.width, surface.height * scaled.copies_y})
   end

   local function patch_fit_tiles(image, scaled, surface)
      -- Preserve the full-image scale when a room edge falls between pixels.
      local groups = {}
      local function add_rect(copy, left, top, right, bottom)
         if left >= right or top >= bottom then return end
         local ox, oy = left, top
         if surface.zone ~= 6 then
            -- Align the ordinary continent brushes to their common period.
            ox, oy = left - left % 96, top - top % 96
         end
         local key = copy .. ":" .. ox .. ":" .. oy
         local group = groups[key]
         if not group then
            group = {copy = copy, ox = ox, oy = oy, right = right, bottom = bottom}
            groups[key] = group
         end
         group.right, group.bottom = math.max(group.right, right), math.max(group.bottom, bottom)
         group[#group + 1] = {left, top, right, bottom}
      end
      for pos, kind in pairs(image.patches) do
         local x, y = pos % surface.width, math.floor(pos / surface.width)
         -- Ordinary brushes, smoothed symbols, and entrance borders can share an edge pixel.
         local shared_edge = surface.zone ~= 6 or kind == BORDER_PATCH or surface.rows[y + 1].cells[x + 1].entrance
         local extra = shared_edge and 1 or 0
         local left = math.floor(x * scaled.width / surface.width)
         local right = math.min(scaled.width, math.floor((x + 1) * scaled.width / surface.width) + extra)
         local top = math.floor(y * scaled.period_height / surface.height)
         local bottom = math.floor((y + 1) * scaled.period_height / surface.height) + extra
         for copy = 0, scaled.copies_y - 1 do
            local base = copy * scaled.period_height
            local seam = base + scaled.period_height
            add_rect(copy, left, base + top, right, math.min(seam, base + bottom))
            if base + bottom > seam and copy + 1 < scaled.copies_y then
               add_rect(copy + 1, left, seam, right, base + bottom)
            end
         end
      end
      if not next(groups) then
         -- At this size the changed tiles cover no pixels.
         image.patches = nil
         return
      end
      local scratch = image.patch or {window = image.window}
      image.patch = scratch
      scratch.width, scratch.height = scaled.width, scaled.height
      scratch.period_height, scratch.copies_y = scaled.period_height, scaled.copies_y
      for _, group in pairs(groups) do
         local ox, oy, copy = group.ox, group.oy, group.copy
         local right, bottom = group.right, group.bottom
         scratch.origin_x, scratch.origin_y, scratch.copy = ox, oy, copy
         scratch.clip_width, scratch.clip_height = right - ox, bottom - oy
         check(api.WindowCreate(scratch.window, 0, 0, scratch.clip_width, scratch.clip_height, 0,
            mini.create_ignore_mouse, EMPTY_COLOUR))
         -- A border can reach one pixel into the next tile, including across the vertical seam.
         local bounds = {math.max(0, math.floor((ox - 1) * surface.width / scaled.width)),
            math.max(0, math.floor((oy - 1) * surface.height / scaled.period_height)),
            math.min(surface.width, math.ceil(right * surface.width / scaled.width) + 1),
            math.min(surface.height * scaled.copies_y, math.ceil(bottom * surface.height / scaled.period_height) + 1)}
         paint_fit(image, scratch, surface, bounds)
         check(api.WindowImageFromWindow(scaled.window, "continent_patch", scratch.window))
         for _, rect in ipairs(group) do
            local l, t, r, b = unpack(rect)
            check(api.WindowDrawImage(scaled.window, "continent_patch", l, t, r, b, 1, l - ox, t - oy, r - ox, b - oy))
         end
      end
      image.version, scaled.version = image.version + 1, scaled.version + 1
      scaled.source_version = image.version
      image.patches = nil
   end

   -- Resize a static atlas once. Movement only copies its wrapped crops.
   local function scale_image(image, scale, surface)
      local width = math.max(1, math.floor(image.width * scale))
      local period_height = math.max(1, math.floor(surface.height * image.pitch * scale))
      local copies_y = vertical_copies(surface, period_height)
      local height = period_height * copies_y
      local scaled = image.scaled
      if image.patches and scaled and scaled.source_version == image.version
         and (state.resizing or scaled.width == width and scaled.height == height) then
         patch_fit_tiles(image, scaled, surface)
      end
      if state.resizing and scaled and scaled.source_version == image.version then
         return resize_preview(image, width, period_height, copies_y)
      end
      if not scaled then
         scaled = {window = image.window .. "_fit", version = 0}
      end
      if scaled.source_version ~= image.version or scaled.width ~= width or scaled.height ~= height
         or scaled.period_height ~= period_height or scaled.copies_y ~= copies_y then
         local scale_t0 = frame_metrics.enabled and api.utils.timer()
         scaled.source_version = nil
         check(api.WindowCreate(scaled.window, 0, 0, width, height, 0, mini.create_ignore_mouse, EMPTY_COLOUR))
         image.scaled = scaled
         scaled.width, scaled.height, scaled.period_height, scaled.copies_y = width, height, period_height, copies_y
         paint_fit(image, scaled, surface)
         scaled.version = scaled.version + 1
         scaled.source_version = image.version
         image.patches = nil
         if scale_t0 then
            frame_metrics.total_continent_scale_time = frame_metrics.total_continent_scale_time
               + api.utils.timer() - scale_t0
         end
      end
      return scaled
   end

   -- Fitted views need source geometry, but no full-size source bitmap.
   local function fit_geometry(surface, size)
      local key = surface.key
      local image = state.fit_images[key]
      if not image or image.size ~= size or image.revision ~= state.revision then
         local previous = image
         local pitch = size - 1
         image = {window = window .. "_" .. key .. "_geometry",
            size = size, pitch = pitch, width = surface.width * pitch,
            height = surface.height * pitch, copies_y = 1, revision = state.revision,
            sky_opacity = sky_opacity, version = (previous and previous.version or 0) + 1,
            scaled = previous and previous.scaled, patch = previous and previous.patch}
         if not previous then
            check(api.WindowCreate(image.window, 0, 0, 1, 1, 0, mini.create_ignore_mouse, EMPTY_COLOUR))
         end
         state.fit_images[key] = image
         return image, "rebuilt"
      end
      if surface.zone == 6 and image.sky_opacity ~= sky_opacity then
         image.sky_opacity = sky_opacity
         image.version = image.version + 1
         return image, "rebuilt"
      end
      return image, image.patches and "patched" or "reused"
   end

   function state.build_images(continent_size, fit)
      local function build(zone, inner_sea, size, fitted)
         local surface = state.room_grid(zone, inner_sea)
         if fitted then
            fit_geometry(surface, size)
         elseif zone ~= 6 then
            update_image(surface, size)
         end
      end
      build(nil, false, continent_size, fit and fit.continent)
      build(nil, true, continent_size, fit and fit.continent)
      build(6, false, VIDBLAIN_MAX_ROOM_SIZE, fit and fit.vidblain)
   end

   function state.view(uid, options)
      if not state.loaded then
         build_index()
      end
      local current = state.positions[uid]
      if not current then
         return
      end
      local definition = M.definitions[current.zone]
      local stitched = current.zone ~= 6
      local inner_sea = current.zone == 5 and current.x < 30 and current.y < 10
      local surface = state.room_grid(not stitched and current.zone or nil, inner_sea)
      local x, y = current.x + (stitched and definition.x or 0), current.y + (stitched and definition.y or 0)
      local player_x, player_y = x, y
      -- Vidblain keeps a fixed projection as the player moves.
      if not stitched then
         x, y = (surface.width - 1) / 2, (surface.height - 1) / 2
      end
      local key = surface.key
      local fit = options.stretch
      local size = fit and (surface.zone == 6 and VIDBLAIN_MAX_ROOM_SIZE or CONTINENT_MAX_ROOM_SIZE) or options.size
      local pitch, half = size - 1, size / 2
      local image, image_status, copies_y
      local previous = state.images[key]
      local zoom = not fit and previous and (previous.size ~= size or previous.missing)
      if not zoom or state.zoom_image ~= previous or previous.size ~= size then state.zoom_image = nil end
      if fit then
         image, image_status = fit_geometry(surface, size)
      elseif zoom then
         copies_y = vertical_copies(surface, surface.height * pitch)
      else
         image, image_status = update_image(surface, size)
         copies_y = image.copies_y
      end
      local first_dx = stitched and -math.floor(surface.width / 2) or -x
      local first_dy = stitched and -math.floor(surface.height / 2) or -y
      local scale, scale_x, scale_y = 1, 1, 1
      local offset_x, offset_y, xs, ys, raster_x, raster_y
      local raster_width, raster_height = surface.width * pitch, surface.height * pitch
      local mincol, maxcol, minrow, maxrow
      local source_column, source_row = (x + first_dx) % surface.width, (y + first_dy) % surface.height
      local render_image = image
      if fit then
         local left, top, right, bottom = unpack(options.stretch_bounds)
         local width, height = raster_width + 1, raster_height + 1
         -- Leave one pixel for rounded room edges at fractional scales.
         scale = math.max(0, math.min(1, (right - left - 1) / width, (bottom - top - 1) / height))
         offset_x = left + (right - left - width * scale) / 2 + options.pan_x
         offset_y = top + (bottom - top - height * scale) / 2 + options.pan_y
         render_image = scale > 0 and scale_image(image, scale, surface) or image
         raster_width = scale > 0 and render_image.width or 0
         raster_height = scale > 0 and render_image.height / render_image.copies_y or 0
         xs, offset_x, scale_x, raster_x = fit_axis(offset_x, source_column * pitch, surface.width * pitch,
            raster_width, left, right)
         ys, offset_y, scale_y, raster_y = fit_axis(offset_y, source_row * pitch, surface.height * pitch,
            raster_height, top, bottom, render_image.copies_y)
         mincol, maxcol = M.visible_cells(raster_x, source_column, raster_width, surface.width, size * scale, left, right)
         minrow, maxrow = M.visible_cells(raster_y, source_row, raster_height, surface.height, size * scale, top, bottom)
      else
         local center_x = math.floor(options.width / 2 + options.pan_x - half) + half
         local center_y = math.floor(options.height / 2 + options.pan_y - half) + half
         local left = math.floor(center_x - half + first_dx * pitch)
         local top = math.floor(center_y - half + first_dy * pitch)
         raster_x, raster_y = left - source_column * pitch, top - source_row * pitch
         xs = split_axis(left, source_column * pitch, raster_width, 0, options.width, 1)
         ys = split_axis(top, source_row * pitch, raster_height, options.top, options.height, copies_y)
         mincol = math.max(0, math.ceil((half - center_x) / pitch - first_dx))
         maxcol = math.min(surface.width - 1, math.floor((options.width - half - center_x) / pitch - first_dx))
         minrow = math.max(0, math.ceil((options.top + half - center_y) / pitch - first_dy))
         maxrow = math.min(surface.height - 1, math.floor((options.height - half - center_y) / pitch - first_dy))
      end
      local rectangles = {}
      for _, sy in ipairs(ys) do
         for _, sx in ipairs(xs) do
            rectangles[#rectangles + 1] = {
               sx.left, sy.left, sx.left + sx.length, sy.left + sy.length, 1, sx.source, sy.source,
               sx.source + sx.length, sy.source + sy.length,
            }
         end
      end
      if zoom then
         image, image_status = update_image(surface, size, rectangles, copies_y)
         render_image = image
      end
      local display_size = size * scale
      local columns, rows = math.max(0, maxcol - mincol + 1), math.max(0, maxrow - minrow + 1)
      if columns == 0 or rows == 0 then
         columns, rows = 0, 0
      end
      local view = {
         cell = view_cell,
         grid = surface.rows,
         grid_width = surface.width,
         grid_height = surface.height,
         source_x = (x + first_dx + mincol) % surface.width,
         source_y = (y + first_dy + minrow) % surface.height,
         columns = columns,
         rows = rows,
         cell_count = columns * rows,
         room_count = options.count_rooms ~= false and 0 or nil,
         overlays = {},
         size = display_size,
         pitch = pitch * scale,
         pitch_x = pitch * scale_x,
         pitch_y = pitch * scale_y,
      }
      if view.cell_count > 0 then
         if fit then
            view.origin_x, view.origin_y = offset_x + mincol * pitch * scale_x, offset_y + minrow * pitch * scale_y
         end
         view.raster_x = raster_x + math.floor((source_column + mincol) / surface.width) * raster_width
         view.raster_y = raster_y + math.floor((source_row + minrow) / surface.height) * raster_height
         view.raster_width, view.raster_height = raster_width, raster_height
      end
      local primary = surface.rows[player_y + 1].cells[player_x + 1]
      if primary.uid ~= uid then
         view.current_source, view.current_cell = primary, cell(current.zone, current.x, current.y, uid)
      end
      local first_end = math.min(surface.width, view.source_x + columns)
      local wrapped_end = math.max(0, view.source_x + columns - surface.width)
      for row = 0, rows - 1 do
         local line = surface.rows[(view.source_y + row) % surface.height + 1]
         -- Preserve left-to-right drawing order on either side of the wrap.
         for segment = 1, 2 do
            local first, last = segment == 1 and view.source_x or 0, segment == 1 and first_end or wrapped_end
            if view.room_count then
               view.room_count = view.room_count + known_rooms(line, first, last)
            end
            for _, column in ipairs(line.overlays) do
               if column >= first and column < last then
                  view.overlays[#view.overlays + 1] = view:cell((column - view.source_x) % surface.width, row)
               end
            end
         end
      end
      local function x_edge(column)
         return grid_edge(raster_x, source_column + column, raster_width, surface.width)
      end
      local function y_edge(row)
         return grid_edge(raster_y, source_row + row, raster_height, surface.height)
      end
      if view.cell_count > 0 then
         view.left, view.top = x_edge(mincol), y_edge(minrow)
         view.bounds = {view.left + display_size / 2, view.top + display_size / 2,
            x_edge(maxcol) + display_size / 2, y_edge(maxrow) + display_size / 2}
      end
      local column, row = player_x - x - first_dx, player_y - y - first_dy
      local left, top = x_edge(column), y_edge(row)
      local right, bottom = x_edge(column + 1), y_edge(row + 1)
      view.center_x, view.center_y = left + display_size / 2, top + display_size / 2
      view.marker_x = math.floor((left + right - 1) / 2)
      view.marker_y = math.floor((top + bottom - 1) / 2)
      if primary.entrance then
         view.current_entrance = {left, top, right, bottom}
      end
      if inner_sea then
         local sea_column, sea_row = column - current.x, row - current.y
         view.inner_sea_bounds = {x_edge(sea_column), y_edge(sea_row), x_edge(sea_column + 30), y_edge(sea_row + 10)}
      end
      view.image, view.render_image, view.key, view.rectangles = image, render_image, key, rectangles
      view.image_status = image_status
      return view
   end

   local installed

   function state.install_image(view, target)
      local image = view.render_image
      if not installed or installed.target ~= target or installed.image ~= image or installed.version ~= image.version
         or api.WindowImageInfo(target, "continent_surface", 1) == nil then
         check(api.WindowImageFromWindow(target, "continent_surface", image.window))
         installed = {target = target, image = image, version = image.version}
      end
   end

   function state.end_resize()
      state.resizing = false
      if state.resize_preview then
         check(api.WindowDelete(state.resize_preview.window))
         state.resize_preview = nil
      end
   end

   function state.start_resize()
      state.end_resize()
      state.resizing = true
   end

   function state.close()
      state.end_resize()
      state.zoom_image = nil
      for _, collection in ipairs({state.images, state.fit_images}) do
         for _, image in pairs(collection) do
            check(api.WindowDelete(image.window))
            if image.scaled then check(api.WindowDelete(image.scaled.window)) end
         end
      end
      state.images, state.fit_images = {}, {}
      if brush_window_created then
         check(api.WindowDelete(brush_window))
         brush_window_created = false
      end
      pattern_images = {}
      installed = nil
   end

   return state
end

return M
