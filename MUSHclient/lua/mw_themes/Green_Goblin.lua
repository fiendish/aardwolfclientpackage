-- Copy this file to create your own custom themes, but please do not modify this file.

-- GREEN GOBLIN THEME
return {
   LOGO_OPACITY = 0.05,

   PRIMARY_BODY = 0x1a000c,
   SECONDARY_BODY = 0x662233,
   BODY_TEXT = 0x00bb55,

   -- flat buttons
   CLICKABLE = 0x2a001c,
   CLICKABLE_HOVER = 0x6b006b,
   CLICKABLE_HOT = 0x401150,
   CLICKABLE_TEXT = 0x00bb55,
   CLICKABLE_HOVER_TEXT = 0x00bb55,
   CLICKABLE_HOT_TEXT = 0x00bb55,

   -- for miniwindow titlebar
   TITLE_PADDING = 2,

   -- for 3D surfaces
   THREE_D_HIGHLIGHT = 0x00bb55,

   THREE_D_GRADIENT = miniwin.gradient_vertical,
   THREE_D_GRADIENT_FIRST = 0x600075,
   THREE_D_GRADIENT_SECOND = 0x550037,
   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x200020,
   THREE_D_HARDSHADOW = 0x000000,
   THREE_D_SURFACE_DETAIL = 0x0088ee, -- for contrasting details/text drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x444444,
   SCROLL_TRACK_COLOR2 = 0x446644,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   VERTICAL_BUTTON_PADDING = 15,
   HORIZONTAL_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16,

   DYNAMIC_BUTTON_PADDING = 20  -- deprecated
}
