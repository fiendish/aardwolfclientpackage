-- Copy this file to create your own custom themes, but please do not modify this file.

return {
   BODY = 0x000000,                   -- where you put all your main stuff
   BODY_CONTRAST = 0xe8e8e8,          -- elements that should stand out from the body
   INACTIVE_BODY = 0x696969,          -- body frame that has been deactivated
   INACTIVE_BODY_HOVER = 0x444444, -- elements that should stand out from INACTIVE_BODY
   INACTIVE_BODY_ACTIVITY = 0x00008b, -- indicate that a deactive body frame might become active if you click

   TITLE_FONTS = {                    -- for miniwindow title bar
      {["name"]="Dina", ["size"]=8},
      {["name"]="Courier New", ["size"]=9},
      {["name"]="Lucida Console", ["size"]=9}
   },
   TITLE_PADDING = 5,                 -- for miniwindow title bar

   THREE_D_SURFACE = 0xced0cf,        -- for 3D surfaces
   THREE_D_OUTERHIGHLIGHT = 0xffffff, -- for 3D surfaces
   THREE_D_INNERHIGHLIGHT = 0xdfe0e2, -- for 3D surfaces
   THREE_D_INNERSHADOW = 0x888c8f,    -- for 3D surfaces
   THREE_D_OUTERSHADOW = 0x404040,    -- for 3D surfaces
   THREE_D_SURFACE_DETAIL = 0x050608, -- for contrasting details drawn on 3D surfaces
}

-- SEE EXAMPLES IN COMMENT BELOW

--]]

