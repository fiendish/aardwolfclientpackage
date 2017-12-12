-- DARK PONY THEME
return {
   BODY = 0x000000,
   LINES = 0xff00ff,
   BUTTON = 0x222222,
   BUTTON_HOVER = 0x664466,
   BUTTON_ACTIVITY = 0x7b007b,

   TITLE_GRADIENT = miniwin.gradient_vertical,
   TITLE_GRADIENT_FIRST = 0x000000,
   TITLE_GRADIENT_SECOND = 0x442244,

   TITLE_FONTS = {                    -- for miniwindow title bar
      {["name"]="Dina", ["size"]=10},
      {["name"]="Courier New", ["size"]=10},
      {["name"]="Lucida Console", ["size"]=10}
   },
   TITLE_PADDING = 4,                 -- for miniwindow title bar

   THREE_D_SURFACE = 0x242024,        -- for 3D surfaces
   THREE_D_OUTERHIGHLIGHT = 0xff00ff, -- for 3D surfaces
   THREE_D_INNERHIGHLIGHT = 0x583858, -- for 3D surfaces
   THREE_D_INNERSHADOW = 0x201020,    -- for 3D surfaces
   THREE_D_OUTERSHADOW = 0x000000,    -- for 3D surfaces
   THREE_D_SURFACE_DETAIL = 0xff00ff, -- for contrasting details drawn on 3D surfaces
   THREE_D_TRACK_COLOR1 = 0x444444,
   THREE_D_TRACK_COLOR2 = 0x664466,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal
}
