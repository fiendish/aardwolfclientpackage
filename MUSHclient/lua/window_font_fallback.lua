--- Apply WindowFont with a fallback if the first font cannot be loaded.
local M = {}

function M.ensure_font(win, font_id, font_name, font_size, fallback_font_name, fallback_font_size, ...)
   local function display_name()
      local function basepath(path)
         return path:match("([^/\\]+)$") or path
      end

      local name = GetPluginName()
      if name ~= "" then
         return name .. " (" .. basepath(GetPluginInfo(GetPluginID(), 6)) .. ")"
      end
      return GetInfo(2) .. " (" .. basepath(GetInfo(54)) .. ")"
   end

   if WindowFont(win, font_id, font_name, font_size, ...) ~= error_code.eOK then
      ColourNote(
         "white", "red",
         string.format(
            "%s expected a font [%s %d] that is no longer available. It will be set to [%s %d] as fallback.",
            display_name(), font_name, font_size, fallback_font_name, fallback_font_size))
      font_name = fallback_font_name
      font_size = fallback_font_size
      if WindowFont(win, font_id, font_name, font_size, ...) ~= error_code.eOK then
         error(string.format(
            "%s: fallback font [%s %d] could not be loaded",
            display_name(), font_name, font_size))
      end
   end
   return font_name, font_size
end

return M
