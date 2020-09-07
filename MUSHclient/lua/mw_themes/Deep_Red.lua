-- Copy this file to create your own custom themes, but please do not modify this file.

-- DEEP RED THEME
return {
   LOGO_OPACITY = 0.03,

   PRIMARY_BODY = 0x00018,
   SECONDARY_BODY = 0x222255,
   BODY_TEXT = 0x0000ff,

   -- flat buttons
   CLICKABLE = 0x111122,
   CLICKABLE_HOVER = 0x00007b,
   CLICKABLE_HOT = 0x111150,
   CLICKABLE_TEXT = 0x0000ff,
   CLICKABLE_HOVER_TEXT = 0x1111ff,
   CLICKABLE_HOT_TEXT = 0x1111ff,

   TITLE_PADDING = 2,

   -- for 3D surfaces
   THREE_D_HIGHLIGHT = 0x0000aa,

   THREE_D_GRADIENT = miniwin.gradient_vertical,
   THREE_D_GRADIENT_FIRST = 0x080860,
   THREE_D_GRADIENT_SECOND = 0x101030,
   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x080825,
   THREE_D_HARDSHADOW = 0x040412,
   THREE_D_SURFACE_DETAIL = 0x0000ff, -- for contrasting details/text drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x111133,
   SCROLL_TRACK_COLOR2 = 0x222266,
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

      WindowCreate("WiLl_It_BlEnD", 0, 0, 0, 0, 0, 0, 0)
      WindowLoadImage("WiLl_It_BlEnD", "tExTuRe", imgpath)
      local tw = WindowImageInfo("WiLl_It_BlEnD", "tExTuRe", 2)
      local th = WindowImageInfo("WiLl_It_BlEnD", "tExTuRe", 3)
      WindowResize("WiLl_It_BlEnD", tw, th, Theme.THREE_D_HIGHLIGHT)
      WindowImageFromWindow("WiLl_It_BlEnD", "cOlOr", "WiLl_It_BlEnD")

      WindowDrawImage("WiLl_It_BlEnD", "tExTuRe", 0, 0, 0, 0, 1)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 7, 100)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 9, 4)
      WindowBlendImage("WiLl_It_BlEnD", "cOlOr", 0, 0, 0, 0, 5, 0.8)

      imgpath = GetInfo(66).."worlds/plugins/images/temp_theme_blend.png"
      WindowWrite("WiLl_It_BlEnD", imgpath)

      return imgpath
   end
}
