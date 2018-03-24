-- Copy this file to create your own custom themes, but please do not modify this file.

-- PINK NEON THEME
return {
   LOGO_OPACITY = 0.06,

   PRIMARY_BODY = 0x000000,
   SECONDARY_BODY = 0x110011,
   BODY_TEXT = 0xff00ff,

   -- flat buttons
   CLICKABLE = 0x220022,
   CLICKABLE_HOVER = 0x7b007b,
   CLICKABLE_HOT = 0x301160,
   CLICKABLE_TEXT = 0xff00ff,
   CLICKABLE_HOVER_TEXT = 0xff11ff,
   CLICKABLE_HOT_TEXT = 0xff00dd,

   TITLE_PADDING = 2,

   -- for 3D surfaces
   THREE_D_HIGHLIGHT = 0xff00ff,

   THREE_D_GRADIENT = false,
   THREE_D_GRADIENT_FIRST = 0x000000,
--   THREE_D_GRADIENT_SECOND = 0x301030,
--   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x500050,
   THREE_D_HARDSHADOW = 0x000000,
   THREE_D_SURFACE_DETAIL = 0xff00ff, -- for contrasting details/text drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0xaa00aa,
   SCROLL_TRACK_COLOR2 = 0x442244,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   DYNAMIC_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16
}
