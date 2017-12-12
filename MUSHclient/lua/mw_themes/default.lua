-- Copy this file to create your own custom themes, but please do not modify this file.

-- SILVER THEME
return {
   BODY = 0x000000,             
   LINES = 0xe8e8e8,            
   BUTTON = 0x696969,           
   BUTTON_HOVER = 0x444444,     
   BUTTON_ACTIVITY = 0x00008b,  

   TITLE_GRADIENT = miniwin.gradient_vertical,
   TITLE_GRADIENT_FIRST = 0x000000,
   TITLE_GRADIENT_SECOND = 0x444444,

   TITLE_FONTS = {                    -- for miniwindow title bar
      {["name"]="Dina", ["size"]=10},
      {["name"]="Courier New", ["size"]=10},
      {["name"]="Lucida Console", ["size"]=10}
   },
   TITLE_PADDING = 4,                 -- for miniwindow title bar

   -- for 3D surfaces like scrollbars
   THREE_D_SURFACE = 0xced0cf,
   THREE_D_OUTERHIGHLIGHT = 0xffffff,
   THREE_D_INNERHIGHLIGHT = 0xdfe0e2,
   THREE_D_INNERSHADOW = 0x888c8f,
   THREE_D_OUTERSHADOW = 0x404040,
   THREE_D_SURFACE_DETAIL = 0x050608, -- for contrasting details drawn on 3D surfaces
   THREE_D_TRACK_COLOR1 = 0x444444,
   THREE_D_TRACK_COLOR2 = 0x696969,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal
}

-- SEE EXAMPLES IN BLOCK COMMENT BELOW

--[[

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

--]]

