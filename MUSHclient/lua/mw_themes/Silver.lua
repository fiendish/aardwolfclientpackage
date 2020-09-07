-- Copy this file to create your own custom themes, but please do not modify this file.

-- SILVER THEME
return {
   LOGO_OPACITY = 0.02,

   PRIMARY_BODY = 0x0c0c0c,
   SECONDARY_BODY = 0x777777,
   BODY_TEXT = 0xe8e8e8,

   -- flat buttons
   CLICKABLE = 0x666666,
   CLICKABLE_HOVER = 0x444444,
   CLICKABLE_HOT = 0x40406b,
   CLICKABLE_TEXT = 0xc8c8c8,
   CLICKABLE_HOVER_TEXT = 0xdddddd,
   CLICKABLE_HOT_TEXT = 0xcfc5df,

   TITLE_PADDING = 2,

   -- for 3D surfaces
   THREE_D_HIGHLIGHT = 0xe8e8e8,

   THREE_D_GRADIENT = miniwin.gradient_vertical,
   THREE_D_GRADIENT_FIRST = 0xcdced1,
   THREE_D_GRADIENT_SECOND = 0x8c8c8c,
   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x606060,
   THREE_D_HARDSHADOW = 0x303030,
   THREE_D_SURFACE_DETAIL = 0x050505, -- for contrasting details/text drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x444444,
   SCROLL_TRACK_COLOR2 = 0x888888,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   VERTICAL_BUTTON_PADDING = 15,
   HORIZONTAL_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16,

   DYNAMIC_BUTTON_PADDING = 20  -- deprecated
}
