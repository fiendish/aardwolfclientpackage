--[[ 
This file contains code that can be inherited by other plugins that allows
many different miniwindow plugins to follow the same UI theme, as long as they
follow certain guidelines. We can use this to maintain a base set of colors
and title fonts that get used everywhere in order to unify the visual style
and provide a way to customize that style easily.

Steps for use:
0) This file must be in the plugins folder
1) From inside your other plugins, call dofile(GetPluginInfo(GetPluginID(), 20).."mw_theme_base.lua")
2) Use variable names as spelled out below (theme.WINDOW_BACKGROUND, theme.WINDOW_BORDER, etc.)
3) You'll notice that another file gets loaded below (mw_theme_colors.lua). It should also be in the plugins folder.
The contents of that file should be something along the lines of (note: this is the default theme)...

theme = {
    WINDOW_BACKGROUND = ColourNameToRGB ("#000000"), -- for miniwindow body
    WINDOW_BORDER = ColourNameToRGB("#E8E8E8"), -- for miniwindow body
    
    HIGHLIGHT=ColourNameToRGB("#FFFFFF"), -- for 3D surfaces
    FACE=ColourNameToRGB("#D4D0C8"), -- for 3D surfaces
    FACE_GRADIENT = ColourNameToRGB("#0x333333"), -- for gradient surfaces

    INNERSHADOW=ColourNameToRGB("#808080"), -- for 3D surfaces
    OUTERSHADOW = ColourNameToRGB("#404040"), -- for 3D surfaces
    
    BACK_FACE = ColourNameToRGB ("#E8E8E8"), -- for contrasting details
    DETAIL = ColourNameToRGB ("#000000"), -- for contrasting details

    TITLE_HEIGHT = 17, -- for miniwindow title area
    SUBTITLE_HEIGHT = 17, -- for miniwindow title area
    TITLE_FONT_NAME = "Dina", -- for miniwindow title area
    TITLE_FONT_SIZE = 8 -- for miniwindow title area
}

--]]

theme = {}
themefile = loadfile(GetPluginInfo(GetPluginID(), 20) .. "mw_theme_colors.lua")
if themefile ~= nil then
    themefile()
end

-- use defaults if any necessary values are undefined in the file
if theme == nil then
    theme = {}
end
if theme.HIGHLIGHT == nil then 
    theme.HIGHLIGHT = ColourNameToRGB("white")
end
if theme.FACE == nil then
    theme.FACE = ColourNameToRGB("#D4D0C8")
end
if theme.FACE_GRADIENT == nil then
    theme.FACE_GRADIENT = theme.FACE
end
if theme.INNERSHADOW == nil then
    theme.INNERSHADOW = ColourNameToRGB("#808080")
end
if theme.OUTERSHADOW == nil then
    theme.OUTERSHADOW = ColourNameToRGB("#404040")
end
if theme.WINDOW_BACKGROUND == nil then
    theme.WINDOW_BACKGROUND = ColourNameToRGB ("#000000")
end
if theme.WINDOW_BORDER == nil then
    theme.WINDOW_BORDER = ColourNameToRGB("#E8E8E8")
end
if theme.BACK_FACE == nil then
    theme.BACK_FACE = ColourNameToRGB ("#E8E8E8")
end
if theme.DETAIL == nil then
    theme.DETAIL = ColourNameToRGB ("#000000")
end
if theme.TITLE_HEIGHT == nil then
    theme.TITLE_HEIGHT = 17
end
if theme.SUBTITLE_HEIGHT == nil then
    theme.SUBTITLE_HEIGHT = 17
end
if theme.TITLE_FONT_NAME == nil then
    theme.TITLE_FONT_NAME = "Dina"
end
if theme.TITLE_FONT_SIZE == nil then
    theme.TITLE_FONT_SIZE = 8
end
-- end load color theme

-- replacement for WindowRectOp action 5, which allows for a 3D look while maintaining color theme
-- Requires global theme.HIGHLIGHT, theme.FACE, theme.INNERSHADOW, and theme.OUTERSHADOW rgb colors to be set.
function DrawThemed3DRect(Window, left, top, right, bottom)
    WindowGradient (Window, left, top, right, bottom, theme.FACE, theme.FACE_GRADIENT, 2)
--    WindowRectOp(Window, 2, left, top, right, bottom, theme.FACE)
    WindowLine(Window, left, top, right, top, theme.HIGHLIGHT, 0 + 0x0200, 1)
    WindowLine(Window, left, top, left, bottom, theme.HIGHLIGHT, 0 + 0x0200, 1)
    WindowLine(Window, left, bottom-2, right, bottom-2, theme.INNERSHADOW, 0 + 0x0200, 1)
    WindowLine(Window, right-2, top, right-2, bottom-2, theme.INNERSHADOW, 0 + 0x0200, 1)
    WindowLine(Window, left, bottom-1, right, bottom-1, theme.OUTERSHADOW, 0 + 0x0200, 1)
    WindowLine(Window, right-1, top, right-1, bottom-1, theme.OUTERSHADOW, 0 + 0x0200, 1)    
end

function DrawThemedResizeTag(Window, x1, y1, size)
    local x2, y2 = x1+size, y1+size
    DrawThemed3DRect(Window, x1, y1, x2, y2)
    local m = 2
    local n = 2
    while (x1+m+2 <= x2-3 and y1+n+1 <= y2-4) do
        WindowLine(Window, x1+m+1, y2-4, x2-3, y1+n, theme.HIGHLIGHT, 0, 1)
        WindowLine(Window, x1+m+2, y2-4, x2-3, y1+n+1, theme.INNERSHADOW, 0, 1)
        m = m+3
        n = n+3
    end
end

