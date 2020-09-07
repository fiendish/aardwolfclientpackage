-- Copy this file to create your own custom themes, but please do not modify this file.

-- GREEN NEON THEME
return {
   LOGO_OPACITY = 0.06,

   PRIMARY_BODY = 0x000000,
   SECONDARY_BODY = 0x001100,
   BODY_TEXT = 0x00ff00,

   -- flat buttons
   CLICKABLE = 0x002200,
   CLICKABLE_HOVER = 0x007b00,
   CLICKABLE_HOT = 0x116060,
   CLICKABLE_TEXT = 0x00ff00,
   CLICKABLE_HOVER_TEXT = 0x11ff11,
   CLICKABLE_HOT_TEXT = 0x10ff00,

   TITLE_PADDING = 2,

   -- for 3D surfaces
   THREE_D_HIGHLIGHT = 0x00ff00,

   THREE_D_GRADIENT = false,
   THREE_D_GRADIENT_FIRST = 0x000000,
--   THREE_D_GRADIENT_SECOND = 0x103010,
--   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x005000,
   THREE_D_HARDSHADOW = 0x000000,
   THREE_D_SURFACE_DETAIL = 0x00ff00, -- for contrasting details/text drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x00aa00,
   SCROLL_TRACK_COLOR2 = 0x224422,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   VERTICAL_BUTTON_PADDING = 15,
   HORIZONTAL_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16,

   DYNAMIC_BUTTON_PADDING = 20,  -- deprecated

   -- bg_texture_function is optional to override the default behavior.
   -- See Charcoal.lua for a "do nothing" variant.
   -- Just make sure to return the path to a valid png file.
   bg_texture_function = function()
      imgpath = GetInfo(66).."worlds/plugins/images/bg1.png"

      WindowCreate("WiLl_It_BlEnD", 0, 0, 0, 0, 0, 0, Theme.THREE_D_HIGHLIGHT)
      WindowLoadImage("WiLl_It_BlEnD", "tExTuRe", imgpath)
      local tw = WindowImageInfo("WiLl_It_BlEnD", "tExTuRe", 2)
      local th = WindowImageInfo("WiLl_It_BlEnD", "tExTuRe", 3)
      WindowResize("WiLl_It_BlEnD", tw, th, Theme.THREE_D_HIGHLIGHT)
      WindowImageFromWindow("WiLl_It_BlEnD", "cOlOr", "WiLl_It_BlEnD")

      WindowDrawImage("WiLl_It_BlEnD", "tExTuRe", 0, 0, 0, 0, 1)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 7, 50)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 8, 30)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 7, -120)
      WindowBlendImage("WiLl_It_BlEnD", "cOlOr", 0, 0, 0, 0, 5, 0.9)

      imgpath = GetInfo(66).."worlds/plugins/images/temp_theme_blend.png"
      WindowWrite("WiLl_It_BlEnD", imgpath)

      return imgpath
   end
}
