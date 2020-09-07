-- Copy this file to create your own custom themes, but please do not modify this file.

-- DEEP MAGENTA THEME
return {
   LOGO_OPACITY = 0.03,

   PRIMARY_BODY = 0x180018,
   SECONDARY_BODY = 0x552255,
   BODY_TEXT = 0xff00ff,

   -- flat buttons
   CLICKABLE = 0x221122,
   CLICKABLE_HOVER = 0x7b007b,
   CLICKABLE_HOT = 0x201150,
   CLICKABLE_TEXT = 0xff00ff,
   CLICKABLE_HOVER_TEXT = 0xff11ff,
   CLICKABLE_HOT_TEXT = 0xff00dd,

   TITLE_PADDING = 2,

   -- for 3D surfaces
   THREE_D_HIGHLIGHT = 0xaa00aa,

   THREE_D_GRADIENT = miniwin.gradient_vertical,
   THREE_D_GRADIENT_FIRST = 0x600860,
   THREE_D_GRADIENT_SECOND = 0x301030,
   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x250825,
   THREE_D_HARDSHADOW = 0x120412,
   THREE_D_SURFACE_DETAIL = 0xff00ff, -- for contrasting details/text drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x331133,
   SCROLL_TRACK_COLOR2 = 0x664466,
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
