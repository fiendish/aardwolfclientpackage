-- Copy this file to create your own custom themes, but please do not modify this file.

-- SILVER THEME
return {
   BODY = 0x0c0c0c,
   BODY_TEXT = 0xe8e8e8,
   BUTTON = 0x696969,
   BUTTON_HOVER = 0x444444,
   BUTTON_HOT = 0x40406b,

   -- for miniwindow titlebar
   TITLE_FONTS = {
      {["name"]="Dina", ["size"]=10},
      {["name"]="Courier New", ["size"]=10},
      {["name"]="Lucida Console", ["size"]=10}
   },
   TITLE_PADDING = 4,

   -- for 3D surfaces other than the titlebar, like buttons and scrollbars
   THREE_D_HIGHLIGHT = 0xe8e8e8,

   THREE_D_GRADIENT = miniwin.gradient_vertical,
   THREE_D_GRADIENT_FIRST = 0xcdced1,
   THREE_D_GRADIENT_SECOND = 0x8c8c8c,
   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x606060,
   THREE_D_HARDSHADOW = 0x303030,
   THREE_D_SURFACE_DETAIL = 0x050505, -- for contrasting details drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x444444,
   SCROLL_TRACK_COLOR2 = 0x696969,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   DYNAMIC_BUTTON_PADDING = 20,
   RESIZER_SIZE = 15
}