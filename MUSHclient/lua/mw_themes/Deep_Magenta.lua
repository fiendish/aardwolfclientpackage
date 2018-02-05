-- Copy this file to create your own custom themes, but please do not modify this file.

-- DARK MAGENTA THEME
return {
   LOGO_OPACITY = 0.03,

   BODY = 0x0c000c,
   BODY_TEXT = 0xff00ff,
   BUTTON = 0x221122,
   BUTTON_HOVER = 0x7b007b,
   BUTTON_HOT = 0x201150,

   -- for miniwindow titlebar
   TITLE_FONTS = {
      {["name"]="Dina", ["size"]=10},
      {["name"]="Courier New", ["size"]=10},
      {["name"]="Lucida Console", ["size"]=10}
   },
   TITLE_PADDING = 1,
   
   -- for 3D surfaces other than the titlebar, like buttons and scrollbars
   THREE_D_HIGHLIGHT = 0xaa00aa,

   THREE_D_GRADIENT = miniwin.gradient_vertical,
   THREE_D_GRADIENT_FIRST = 0x600860,
   THREE_D_GRADIENT_SECOND = 0x301030,
   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x250825,
   THREE_D_HARDSHADOW = 0x120412,
   THREE_D_SURFACE_DETAIL = 0xff00ff, -- for contrasting details drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x444444,
   SCROLL_TRACK_COLOR2 = 0x664466,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   DYNAMIC_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16
}
