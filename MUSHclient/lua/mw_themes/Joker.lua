-- BARNEY THEME
return {
   BODY = 0x0d000d,
   BODY_TEXT = 0x00bb55,
   BUTTON = 0x221122,
   BUTTON_HOVER = 0x6b006b,
   BUTTON_HOT = 0x201150,

   -- for miniwindow titlebar
   TITLE_FONTS = {
      {["name"]="Dina", ["size"]=10},
      {["name"]="Courier New", ["size"]=10},
      {["name"]="Lucida Console", ["size"]=10}
   },
   TITLE_PADDING = 4,

   -- for 3D surfaces other than the titlebar, like buttons and scrollbars
   THREE_D_HIGHLIGHT = 0x00bb55,

   THREE_D_GRADIENT = miniwin.gradient_vertical,
   THREE_D_GRADIENT_FIRST = 0x600065,
   THREE_D_GRADIENT_SECOND = 0x550037,
   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x200020,
   THREE_D_HARDSHADOW = 0x000000,
   THREE_D_SURFACE_DETAIL = 0x00bb55, -- for contrasting details drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x444444,
   SCROLL_TRACK_COLOR2 = 0x446644,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   DYNAMIC_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16
}
