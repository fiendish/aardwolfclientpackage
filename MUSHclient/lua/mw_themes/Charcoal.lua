-- Copy this file to create your own custom themes, but please do not modify this file.

-- CHARCOAL THEME
return {
   LOGO_OPACITY = 0.05,                    -- Main output background logo

   PRIMARY_BODY = 0x000000,                -- Background for main output and miniwindow main areas
   SECONDARY_BODY = 0x333333,              -- Secondary background color (color under the chat window tabs)
   BODY_TEXT = 0xc8c8c8,                   -- Body text of plugins

   TITLE_PADDING = 2,                      -- Padding around text in miniwindow titlebars

   -- buttons
   CLICKABLE = 0x444444,                   -- Button face
   CLICKABLE_HOVER = 0x151515,             -- Button face when hovering over it with mouse
   CLICKABLE_HOT = 0x303050,               -- Button face when it wants your attention
   CLICKABLE_TEXT = 0xc8c8c8,              -- Button text
   CLICKABLE_HOVER_TEXT = 0xdddddd,        -- Button text when hovering over it
   CLICKABLE_HOT_TEXT = 0xcfc5df,          -- Button text when it wants your attention

   -- 3D surfaces
   THREE_D_GRADIENT = false,               -- Surface color gradient direction (or false)
   THREE_D_GRADIENT_FIRST = 0x555555,      -- Start color
   THREE_D_GRADIENT_SECOND = 0x555555,     -- End color
   THREE_D_GRADIENT_ONLY_IN_TITLE = true,  -- Only apply gradient in miniwindow titlebars

   THREE_D_HIGHLIGHT = 0x909090,
   THREE_D_SOFTSHADOW = 0x222222,
   THREE_D_HARDSHADOW = 0x000000,
   THREE_D_SURFACE_DETAIL = 0xc8c8c8,      -- Contrasting details/text drawn on 3D surfaces

   -- scrollbar background
   SCROLL_TRACK_COLOR1 = 0x444444,         -- Color of accent brush on scrollbar
   SCROLL_TRACK_COLOR2 = 0x696969,         -- Main color of scrollbar
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,  -- Scrollbar background texture

   VERTICAL_BUTTON_PADDING = 15,           -- Space around text in dynamically-sized text buttons
   HORIZONTAL_BUTTON_PADDING = 20,         -- Space around text in dynamically-sized text buttons
   RESIZER_SIZE = 16,                      -- Miniwindow resizer

   DYNAMIC_BUTTON_PADDING = 20,            -- deprecated

   -- bg_texture_function is optional to override the default behavior.
   -- See Pink_Neon.lua for a "glitter on black" variant.
   -- Just make sure to return the path to a valid png file.
   bg_texture_function = function()
      return GetInfo(66).."worlds/plugins/images/bg1.png"
   end
}
