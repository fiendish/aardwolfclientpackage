-- Font selection and loading for miniwindows.
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

-- get font from preferred font list
function M.get_preferred_font (t)
  local fonts = utils.getfontfamilies ()
  
  -- convert to upper-case
  local f2 = {}
  for k in pairs (fonts) do
    f2 [k:upper ()] = true
  end -- for
  
  for _, s in ipairs (t) do
    if f2 [s:upper ()] then
      return s
    end -- if
  end -- for each item

  return "Courier"
end -- get_preferred_font

return M
