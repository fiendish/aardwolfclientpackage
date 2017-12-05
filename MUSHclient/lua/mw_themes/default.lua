-- Copy this file to create your own custom themes, but please do not modify this file.

-- SILVER THEME
return {
   BODY = 0x000000,                   -- where you put all your main stuff
   BODY_CONTRAST = 0xe8e8e8,          -- elements that should stand out from the body
   INACTIVE_BODY = 0x696969,          -- body frame that has been deactivated
   INACTIVE_BODY_HOVER = 0x444444, -- elements that should stand out from INACTIVE_BODY
   INACTIVE_BODY_ACTIVITY = 0x00008b, -- indicate that a deactive body frame might become active if you click

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
   BODY = 0x000000,                   -- where you put all your main stuff
   BODY_CONTRAST = 0xff00ff,          -- elements that should stand out from the body
   INACTIVE_BODY = 0x444444,          -- body frame that has been deactivated
   INACTIVE_BODY_HOVER = 0x664466, -- elements that should stand out from INACTIVE_BODY
   INACTIVE_BODY_ACTIVITY = 0x7b007b, -- indicate that a deactive body frame might become active if you click

   TITLE_FONTS = {                    -- for miniwindow title bar
      {["name"]="Dina", ["size"]=10},
      {["name"]="Courier New", ["size"]=10},
      {["name"]="Lucida Console", ["size"]=10}
   },
   TITLE_PADDING = 4,                 -- for miniwindow title bar

   THREE_D_SURFACE = 0x242322,        -- for 3D surfaces
   THREE_D_OUTERHIGHLIGHT = 0x2e2e2d, -- for 3D surfaces
   THREE_D_INNERHIGHLIGHT = 0x383838, -- for 3D surfaces
   THREE_D_INNERSHADOW = 0x191816,    -- for 3D surfaces
   THREE_D_OUTERSHADOW = 0x0d0e0a,    -- for 3D surfaces
   THREE_D_SURFACE_DETAIL = 0xff00ff, -- for contrasting details drawn on 3D surfaces
   THREE_D_TRACK_COLOR1 = 0x444444,
   THREE_D_TRACK_COLOR2 = 0x664466,
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal
}

--]]

