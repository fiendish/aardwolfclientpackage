-- Draw fitted room symbols and load the shipped artwork planes.
local M = {}
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

-- Match the area filter and sRGB conversion in MUSHclient's WindowDrawImageAlpha.
local linear = {}
for byte = 0, 255 do
   local value = byte / 255
   linear[byte] = value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
end

local function srgb(value)
   if value <= 0 then return 0 end
   if value >= 1 then return 255 end
   value = floor(value * 4096 + 0.5) / 4096
   value = value <= 0.0031308 and value * 12.92 or 1.055 * value ^ (1 / 2.4) - 0.055
   return floor(value * 255 + 0.5)
end

local function rgb(red, green, blue)
   return srgb(red) + 256 * srgb(green) + 65536 * srgb(blue)
end

-- Use the same room painter at both zoom levels. A missing pixel is transparent.
local function symbol_pixels(paint, style, pitch)
   local pixels = {}
   local function fill(left, top, right, bottom, colour, alpha)
      assert(not alpha or alpha == 255, "Expected an opaque room symbol rectangle")
      for y = top, bottom - 1 do
         for x = left, right - 1 do pixels[y * pitch + x] = colour end
      end
   end
   paint(fill, style, 0, 0, pitch)
   return pixels
end

function M.draw_symbols(api, check, target, surface, pitch, bounds, each_symbol)
   local width, height = target.width, target.period_height
   local source_width, source_height = surface.width * pitch, surface.height * pitch
   local step_x, step_y = source_width / width, source_height / height
   local origin_x, origin_y = target.origin_x or 0, target.origin_y or 0
   local first_copy, last_copy = target.copy or 0, target.copy or target.copies_y - 1
   local clip_top = origin_y - first_copy * height
   local clip_right = origin_x + (target.clip_width or width)
   local clip_bottom = clip_top + (target.clip_height or height)
   local shapes, tiles, footprint = {}, {}, {}

   each_symbol(surface, bounds, function(column, row, style, paint)
      row = row % surface.height
      local left = max(origin_x, floor(column * width / surface.width))
      local right = min(clip_right, ceil((column + 1) * width / surface.width))
      local top = max(clip_top, floor(row * height / surface.height))
      local bottom = min(clip_bottom, ceil((row + 1) * height / surface.height))
      if left >= right or top >= bottom then return end
      if not shapes[style] then shapes[style] = symbol_pixels(paint, style, pitch) end
      tiles[row] = tiles[row] or {}
      tiles[row][column] = shapes[style]
      -- Neighboring symbols can share a destination pixel. Blend that pixel only once.
      for y = top, bottom - 1 do
         local columns = footprint[y] or {}
         footprint[y] = columns
         for x = left, right - 1 do columns[x] = true end
      end
   end)

   local function sample(x, y)
      if width == source_width and height == source_height then
         local shape = tiles[floor(y / pitch)][floor(x / pitch)]
         local colour = shape[(y % pitch) * pitch + x % pitch]
         return colour and 1 or 0, colour
      end
      local left, right = x * step_x, (x + 1) * step_x
      local top, bottom = y * step_y, (y + 1) * step_y
      local coverage, red, green, blue = 0, 0, 0, 0
      -- Accumulate horizontal samples first, in source order, as in the native filter.
      for sy = floor(top), min(source_height, ceil(bottom)) - 1 do
         local row = tiles[floor(sy / pitch)]
         if row then
            local offset = (sy % pitch) * pitch
            local row_coverage, row_red, row_green, row_blue = 0, 0, 0, 0
            for sx = floor(left), min(source_width, ceil(right)) - 1 do
               local shape = row[floor(sx / pitch)]
               local colour = shape and shape[offset + sx % pitch]
               if colour then
                  local weight = (min(right, sx + 1) - max(left, sx)) / step_x
                  row_coverage = row_coverage + weight
                  row_red = row_red + linear[colour % 256] * weight
                  row_green = row_green + linear[floor(colour / 256) % 256] * weight
                  row_blue = row_blue + linear[floor(colour / 65536)] * weight
               end
            end
            local weight = (min(bottom, sy + 1) - max(top, sy)) / step_y
            coverage = coverage + row_coverage * weight
            red = red + row_red * weight
            green = green + row_green * weight
            blue = blue + row_blue * weight
         end
      end
      if coverage >= 1 then return coverage, rgb(red, green, blue) end
      return coverage, nil, red, green, blue
   end

   for y, columns in pairs(footprint) do
      for x in pairs(columns) do
         local coverage, solid_colour, red, green, blue = sample(x, y)
         if coverage > 0 then
            for copy = first_copy, last_copy do
               local px, py = x - origin_x, y + copy * height - origin_y
               local colour = solid_colour
               if not colour then
                  local background = api.WindowGetPixel(target.window, px, py)
                  assert(background >= 0 and background <= 0xffffff, "Cannot read fitted symbol background")
                  local weight = 1 - coverage
                  colour = rgb(red + linear[background % 256] * weight,
                     green + linear[floor(background / 256) % 256] * weight,
                     blue + linear[floor(background / 65536)] * weight)
               end
               check(api.WindowSetPixel(target.window, px, py, colour))
            end
         end
      end
   end
end

function M.load_layer(api, check, target, name, path, width, height)
   local id = "continent_art_" .. name
   local loaded = target.loaded_layers or {}
   target.loaded_layers = loaded
   if loaded[name] ~= path then
      loaded[name] = nil
      check(api.WindowLoadImage(target.window, id, path))
      assert(api.WindowImageInfo(target.window, id, 2) == width
         and api.WindowImageInfo(target.window, id, 3) == height
         and api.WindowImageInfo(target.window, id, 6) == 32, "Invalid continent artwork layer")
      loaded[name] = path
      return id, true
   end
   return id
end

return M
