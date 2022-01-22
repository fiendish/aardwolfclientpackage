-- Copy this file to create your own custom themes, but please do not modify this file.

return {
   LOGO_OPACITY = 0.03,

   PRIMARY_BODY = 0x000000,                -- Text background for main output
   SECONDARY_BODY = 0x000000,              -- Color under the tabs on chat window
   BODY_TEXT = 0xBBFFBB,                   -- Color of text of current tab, and body of most plugins -mapper-

   -- flat buttons
   CLICKABLE = 0x004000,
   CLICKABLE_HOVER = 0x63D471,             -- Color when hovering over the tab with mouse
   CLICKABLE_HOT = 0x11a212,               -- Color of tab when you have an unread message
   CLICKABLE_TEXT = 0xFFFFFF,              -- Color of tab text
   CLICKABLE_HOVER_TEXT = 0xFFFFFF,        -- Color of tab text when hovering over it
   CLICKABLE_HOT_TEXT = 0x8CE6F0,          -- Color of tab text when you have an unread message

   TITLE_PADDING = 2,

   -- for 3D surfaces
   THREE_D_HIGHLIGHT = 0x63D471,            -- Color of outside-most window border color, resizer, tab borders, and scrollbar highlights

   THREE_D_GRADIENT = miniwin.gradient_vertical,
   THREE_D_GRADIENT_FIRST = 0x233329,
   THREE_D_GRADIENT_SECOND = 0x63D471,
   THREE_D_GRADIENT_ONLY_IN_TITLE = false,

   THREE_D_SOFTSHADOW = 0x233329,
   THREE_D_HARDSHADOW = 0x233329,           -- Partial color of resizer, inner border of title windows, bottom/right color of scroller
   THREE_D_SURFACE_DETAIL = 0xFFFFFF,       -- for contrasting details/text drawn on 3D surfaces -TEXT COLOR-

   -- for scrollbar background
   SCROLL_TRACK_COLOR1 = 0x000000,          -- Color of diagonal lines on scrollbar
   SCROLL_TRACK_COLOR2 = 0x63D471,          -- Main color of scrollbar
   VERTICAL_TRACK_BRUSH = miniwin.brush_hatch_forwards_diagonal,

   DYNAMIC_BUTTON_PADDING = 20,
   RESIZER_SIZE = 16,

   -- bg_texture_function is optional to override the default behavior.
   -- See Charcoal.lua for a "do nothing" variant.
   -- Just make sure to return the path to a valid png file.
   bg_texture_function = function()
      imgpath = GetInfo(66).."worlds/plugins/images/hell.png"

      WindowCreate("WiLl_It_BlEnD", 0, 0, 0, 0, 0, 0, Theme.THREE_D_HIGHLIGHT)
      WindowLoadImage("WiLl_It_BlEnD", "tExTuRe", imgpath)
      local tw = WindowImageInfo("WiLl_It_BlEnD", "tExTuRe", 2)
      local th = WindowImageInfo("WiLl_It_BlEnD", "tExTuRe", 3)
      WindowResize("WiLl_It_BlEnD", tw, th, Theme.THREE_D_HIGHLIGHT)
      WindowImageFromWindow("WiLl_It_BlEnD", "cOlOr", "WiLl_It_BlEnD")

      WindowDrawImage("WiLl_It_BlEnD", "tExTuRe", 0, 0, 0, 0, 1)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 7, 50)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 8, 30)
      WindowFilter("WiLl_It_BlEnD", 0, 0, 0, 0, 7, -120)
      WindowBlendImage("WiLl_It_BlEnD", "cOlOr", 0, 0, 0, 0, 6, 0.4)

      imgpath = GetInfo(66).."worlds/plugins/images/temp_theme_blend.png"
      WindowWrite("WiLl_It_BlEnD", imgpath)

      return imgpath
   end
}
