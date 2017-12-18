-- Copy this file to create your own custom themes, but please do not modify this file.

-- CHARCOAL THEME
return {
   BODY = 0x000000,
   BODY_TEXT = 0xc8c8c8,
   BUTTON = 0x222222,
   BUTTON_HOVER = 0x444444,
   BUTTON_HOT = 0x302050,

   -- for miniwindow titlebar
   TITLE_FONTS = {
      {["name"]="Dina", ["size"]=10},
      {["name"]="Courier New", ["size"]=10},
      {["name"]="Lucida Console", ["size"]=10}
   },
   TITLE_PADDING = 4,

   -- for 3D surfaces other than the titlebar, like buttons and scrollbars
   THREE_D_HIGHLIGHT = 0x909090,

   THREE_D_GRADIENT = false,
   THREE_D_GRADIENT_FIRST = 0x555555,
--   THREE_D_GRADIENT_SECOND = 0x333333,
--   THREE_D_GRADIENT_ONLY_IN_TITLE = true,

   THREE_D_SOFTSHADOW = 0x222222,
   THREE_D_HARDSHADOW = 0x000000,
   THREE_D_SURFACE_DETAIL = 0xc8c8c8, -- for contrasting details drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x444444,
   SCROLL_TRACK_COLOR2 = 0x696969,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   DYNAMIC_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16
}

-- ANOTHER EXAMPLE IN BLOCK COMMENT BELOW

--[[

-- DARK MAGENTA THEME
return {
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
   TITLE_PADDING = 4,

   -- for 3D surfaces other than the titlebar, like buttons and scrollbars
   THREE_D_HIGHLIGHT = 0xaa00aa,

   THREE_D_GRADIENT = miniwin.gradient_vertical,
   THREE_D_GRADIENT_FIRST = 0x600860,
   THREE_D_GRADIENT_SECOND = 0x301030,
   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x200020,
   THREE_D_HARDSHADOW = 0x000000,
   THREE_D_SURFACE_DETAIL = 0xff00ff, -- for contrasting details drawn on 3D surfaces

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x444444,
   SCROLL_TRACK_COLOR2 = 0x664466,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   DYNAMIC_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16
}

--]]

