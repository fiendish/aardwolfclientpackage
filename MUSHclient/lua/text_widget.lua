--[[
   Create a new text box widget, bound to the contents of a miniwindow.
   TextWidget_MT.new(name, parent_miniwindow_name, values)

   * name must be a string composed of only alphanumeric values
   * parent_miniwindow_name is the name of miniwindow that will hold this widget, and must be a string composed of only alphanumeric values
   * values is a table of custom settings to override TextWidget_MT variables described below as USER SETTINGS

   To add text to the widget, call either (depending on the input format)
      your_widget:addColouredLine("HELLO@RHello@Mhello@x215hello@x66HELLO")
   or
      your_widget:addStyles(style_run_table)
]]--

TextWidget_MT = {
  -- USER SETTINGS --
  name = "",
  window_name = "",
  text_x_position=0,
  text_y_position=0,
  text_width=0,
  text_height=0,
  font_name = "",
  font_size = "",
  color_window_background = GetNormalColour(1),
  scrollable=true, -- enable/disable the scrollbar
  scrollbar_x_position = 0,
  scrollbar_y_position = 0,
  scrollbar_width = 16,
  scrollbar_height = 0,
  max_scrollback_lines = 10000,
  color_scroll_detail = 0x000000,
  color_scroll_background = 0xE8E8E8,
  external_rightclick_menu = nil,

  -- SEMI-PRIVATE VARIABLES --
  resize_scrollbar_height = 0,
  resize_scrollbar_x = 0,
  resize_scrollbar_y = 0,
  resize_text_width = 0,
  resize_text_height = 0,

  -- PRIVATE VARIABLES. DO NOT TOUCH. --
  lines = {},
  raw_lines = {},
  hyperlinks = {},
  line_start = "",
  line_end = "",
  window_lines = "",
  font_height = "",
  dragging_scrollbar = false,
  scrollbar_pos = 0,
  scrollbar_size = 0,
  line_height = "",
  scrollbar_steps = 1,
  scrollbar_start_pos = 0,
  temp_start_copying_x = 0,
  start_copying_y = 0,
  copy_start_windowline = 0,
  temp_start_line = 0,
  copied_text = "",
  copy_start_line = 0,
  copy_end_line = 0,
}

require "copytable"
require "wait"
require "movewindow"

--usage: widget:addColouredLine("HELLO@RHello@Mhello@x215hello@x66HELLO")
function TextWidget_MT:addColouredLine(string)
  self:addStyles(ColoursToStyles(string))
end

function TextWidget_MT:addStyles(styles)
  local styles = copytable.deep(styles)

  --strip out our URLs, so we can add our movespots later
  local urls = self:findURLs(strip_colours_from_styles(styles))

  --pop our last line from our buffer, if we're at our max.
  if #self.raw_lines > self.max_scrollback_lines then
    table.remove(self.raw_lines, 1)
  end
  table.insert(self.raw_lines, {[1]=styles, [2]=urls})
  self:wrapLine(styles, urls)
end

TextWidgetSaveStrings = {"font_name", "font_size"}
TextWidgetSaveNumbers = {"width", "height"}

TextWidgetNameMap = {}
TextWidgetHotspotMap = {}
local function getWidgetFromHotspotID(hotspot_id)
   return TextWidgetNameMap[TextWidgetHotspotMap[hotspot_id] or ""]
end

-- Give our hotspots unique names, to ensure no naming conflicts for our handlers
function TextWidget_MT:generateHotspotName(name)
  local hotspotName = self.name.."__hotspot__"..name
  TextWidgetHotspotMap[hotspotName] = self.name
  return hotspotName
end

function TextWidget_MT:saveState()
  for _,variable in pairs(TextWidgetSaveStrings) do
    if self[variable] ~= nil then
      SetVariable(self.name..variable, self[variable])
    end
  end
  for _,variable in pairs(TextWidgetSaveNumbers) do
    if self[variable] ~= nil then
      SetVariable(self.name..variable, self[variable])
    end
  end
end

function TextWidget_MT:loadState()
  for _,variable in pairs(TextWidgetSaveStrings) do
    result = GetVariable(self.name..variable)
    if result ~= nil then
      self[variable] = GetVariable(self.name..variable)
    end
  end
  for _,variable in pairs(TextWidgetSaveNumbers) do
    result = GetVariable(self.name..variable)
    if result ~= nil then
      self[variable] = tonumber(GetVariable(self.name..variable))
    end
  end
  self:initialize()
end

function TextWidget_MT.new(name, window_name, values)
  name = "Textwidget_"..GetPluginID()..name -- throw a character onto the start of our name, to make sure our variables work
  local self = copytable.deep(TextWidget_MT)
  self:set_values(values)
  self.name = name
  self.window_name = window_name
  self:initialize()
  return self
end

function TextWidget_MT:set_values(values)
  if values ~= nil then
    for key,value in pairs(values) do
      if type(value) == "number" then value = math.floor(value) end
      self[key] = value
    end
  end
end

--initialization has to happen for anything else to work.  Called automatically from TextWidget_MT.new
function TextWidget_MT:initialize()
  self:initializeFonts()
  self.line_start = 1
  self.line_end = 1
  self:initializeMiniwindowHandlers()
  self:draw()
  TextWidgetNameMap[self.name] = self
end

function TextWidget_MT:initializeFonts()
  self.font = "font"..self.name
  check(WindowFont(self.window_name, self.font, self.font_name, self.font_size))
  self.font_height = WindowFontInfo(self.window_name, self.font, 1) -  WindowFontInfo(self.window_name, self.font, 4) + 1
  self.line_height = self.font_height + 1
  self.window_lines = math.floor(self.text_height / self.line_height)
end

function TextWidget_MT:initializeMiniwindowHandlers()
  if self.scrollable then
     -- scroll bar up/down button hotspots
     WindowAddHotspot(self.window_name, self:generateHotspotName("up"), self.scrollbar_x_position, self.scrollbar_y_position, self.scrollbar_x_position + self.scrollbar_width, self.scrollbar_y_position + self.scrollbar_width, "", "", "TextWidget_MT.MouseDownUpArrow", "TextWidget_MT.CancelMouseDown", "TextWidget_MT.MouseUp", "", 1, 0)
     WindowAddHotspot(self.window_name, self:generateHotspotName("down"), self.scrollbar_x_position, self.scrollbar_y_position + self.scrollbar_height - self.scrollbar_width, self.scrollbar_x_position + self.scrollbar_width, self.scrollbar_y_position + self.scrollbar_height, "", "", "TextWidget_MT.MouseDownDownArrow", "TextWidget_MT.CancelMouseDown", "TextWidget_MT.MouseUp", "", 1, 0)
  end

  --highlight, right click, scrolling
  local textarea_name = self:generateHotspotName("textarea")
  WindowAddHotspot(self.window_name, textarea_name, self.text_x_position, self.text_y_position, self.text_x_position + self.text_width, self.text_y_position + self.text_height, "", "", "TextWidget_MT.MouseDownText", "TextWidget_MT.CancelMouseDown", "TextWidget_MT.MouseUp", "", 2, 0)
  WindowDragHandler(self.window_name, textarea_name, "TextWidget_MT.TextareaMoveCallback", "TextWidget_MT.TextareaReleaseCallback", 0x10)
  if self.scrollable then
     WindowScrollwheelHandler(self.window_name, textarea_name, "TextWidget_MT.WheelMoveCallback")
  end
end

-- draw functions only work after all initialization is complete
function TextWidget_MT:draw()
  if self.scrollable then
    self:drawScrollbar()
  end
  
  -- reset url hyperlinks
  for k,v in pairs(self.hyperlinks) do
    WindowDeleteHotspot(self.window_name, k)
  end
  self.hyperlinks = {}

  self:refreshText()
end

require "commas"
function TextWidget_MT:drawScrollbar()
  WindowRectOp(self.window_name, 2, self.scrollbar_x_position, self.scrollbar_y_position, self.scrollbar_x_position + self.scrollbar_width, self.scrollbar_y_position + self.scrollbar_height, self.color_scroll_background) -- scroll bar background
  WindowRectOp(self.window_name, 1, self.scrollbar_x_position + 1, self.scrollbar_y_position + 1, self.scrollbar_x_position + self.scrollbar_width - 1, self.scrollbar_y_position + self.scrollbar_height - 1, self.color_scroll_detail) -- scroll bar background inset rectangle

  local midpoint = (self.scrollbar_width - 2)/2

  -- draw the scroll up button
  local button_style = miniwin.rect_edge_at_all + miniwin.rect_option_fill_middle
  local button_edge = miniwin.rect_edge_raised
  local points = ""

  if (self.keepscrolling == "up") then
    button_edge = miniwin.rect_edge_sunken
    points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
self.scrollbar_x_position + math.floor(midpoint) + 1, self.scrollbar_y_position + math.ceil(self.scrollbar_width/4 + 0.5) + 2, self.scrollbar_x_position + math.floor(midpoint) - math.floor(midpoint/2) + 1, self.scrollbar_y_position + round_banker(self.scrollbar_width/2) + 2, 
self.scrollbar_x_position + math.ceil(midpoint) + math.floor(midpoint/2) + 1, self.scrollbar_y_position + round_banker(self.scrollbar_width/2) + 2, 
self.scrollbar_x_position + math.ceil(midpoint) + 1, self.scrollbar_y_position + math.ceil(self.scrollbar_width/4 + 0.5) + 2 )
  else
    points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
self.scrollbar_x_position + math.floor(midpoint), self.scrollbar_y_position + math.ceil(self.scrollbar_width/4 + 0.5) + 1, self.scrollbar_x_position + math.floor(midpoint) - math.floor(midpoint/2), self.scrollbar_y_position + round_banker(self.scrollbar_width/2) + 1, 
self.scrollbar_x_position + math.ceil(midpoint) + math.floor(midpoint/2), self.scrollbar_y_position + round_banker(self.scrollbar_width/2) + 1, 
self.scrollbar_x_position + math.ceil(midpoint), self.scrollbar_y_position + math.ceil(self.scrollbar_width/4 + 0.5) + 1)
  end
  WindowRectOp(self.window_name, 5, self.scrollbar_x_position, self.scrollbar_y_position, self.scrollbar_x_position + self.scrollbar_width, self.scrollbar_y_position + self.scrollbar_width, button_edge, button_style)
  WindowPolygon(self.window_name, points, 0x000000, miniwin.pen_solid + miniwin.pen_join_miter, 1, 0x000000, 0, true, false)

  -- draw the scroll down button
  button_edge = miniwin.rect_edge_raised
  if (self.keepscrolling == "down") then
    button_edge = miniwin.rect_edge_sunken
    points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
self.scrollbar_x_position + math.floor(midpoint) + 1, self.scrollbar_y_position + self.scrollbar_height - 1 - math.ceil(self.scrollbar_width/4 + 0.5), self.scrollbar_x_position + math.floor(midpoint) - math.floor(midpoint/2) + 1, self.scrollbar_y_position + self.scrollbar_height - 1 - round_banker(self.scrollbar_width/2), 
self.scrollbar_x_position + math.ceil(midpoint) + math.floor(midpoint/2) + 1, self.scrollbar_y_position + self.scrollbar_height - 1 - round_banker(self.scrollbar_width/2), 
self.scrollbar_x_position + math.ceil(midpoint) + 1, self.scrollbar_y_position + self.scrollbar_height - 1 - math.ceil(self.scrollbar_width/4 + 0.5))
  else
    points = string.format("%i,%i,%i,%i,%i,%i,%i,%i",
self.scrollbar_x_position + math.floor(midpoint), self.scrollbar_y_position + self.scrollbar_height - 2 - math.ceil(self.scrollbar_width/4 + 0.5), self.scrollbar_x_position + math.floor(midpoint) - math.floor(midpoint/2), self.scrollbar_y_position + self.scrollbar_height - 2 - round_banker(self.scrollbar_width/2), 
self.scrollbar_x_position + math.ceil(midpoint) + math.floor(midpoint/2), self.scrollbar_y_position + self.scrollbar_height - 2 - round_banker(self.scrollbar_width/2), 
self.scrollbar_x_position + math.ceil(midpoint), self.scrollbar_y_position + self.scrollbar_height - 2 - math.ceil(self.scrollbar_width/4 + 0.5))
  end
  WindowRectOp(self.window_name, 5, self.scrollbar_x_position, self.scrollbar_y_position + self.scrollbar_height - self.scrollbar_width, self.scrollbar_x_position + self.scrollbar_width, self.scrollbar_y_position + self.scrollbar_height, button_edge, button_style)
  WindowPolygon(self.window_name, points, 0x000000, 0, 1, 0x000000, 0, true, false)

  -- The scrollbar position indicator
  self.scrollbar_steps = math.max(1, #self.lines - self.window_lines + 1)
  local scroll_height = self.scrollbar_height - (2 * self.scrollbar_width)
  if (not self.dragging_scrollbar) then
    self.scrollbar_size = math.max(10, scroll_height - self.scrollbar_steps + 1)
    local available_space = scroll_height - self.scrollbar_size
    local space_per_step = available_space / self.scrollbar_steps

    self.scrollbar_pos = math.floor(self.scrollbar_y_position + self.scrollbar_width + (space_per_step*self.line_start))
    if self.scrollbar_pos + self.scrollbar_size > self.scrollbar_y_position + self.scrollbar_height - self.scrollbar_width then
      self.scrollbar_pos = self.scrollbar_height + self.scrollbar_y_position - self.scrollbar_size - self.scrollbar_width
    end
    WindowAddHotspot(self.window_name, self:generateHotspotName("scroller"), self.scrollbar_x_position, self.scrollbar_pos, self.scrollbar_x_position + self.scrollbar_width, self.scrollbar_pos + self.scrollbar_size, "", "", "TextWidget_MT.MouseDownScrollbar", "", "TextWidget_MT.MouseUp", "", 1, 0)
    WindowDragHandler(self.window_name, self:generateHotspotName("scroller"), "TextWidget_MT.ScrollbarMoveCallback", "TextWidget_MT.ScrollbarReleaseCallback", 0)
  end
  WindowRectOp(self.window_name, 5, self.scrollbar_x_position, self.scrollbar_pos, self.scrollbar_x_position + self.scrollbar_width, self.scrollbar_pos + self.scrollbar_size, 5, 15 + 0x800)
end

function TextWidget_MT:refreshText()
  WindowRectOp(self.window_name, 2, self.text_x_position, self.text_y_position, self.text_x_position + self.text_width, self.text_y_position + self.text_height, self.color_window_background) -- clear
  local ax = nil
  local zx = nil
  local line_no_colors = ""
  local count = 0
  if #self.lines >= 1 then
    for count = self.line_start, self.line_end do
        ax = nil
        zx = nil
        line_no_colors = strip_colours_from_styles(self.lines[count][1])

        -- create clickable links for urls
        for i,v in ipairs(self.lines[count][3]) do
          local left = self.text_x_position + WindowTextWidth(self.window_name, self.font, string.sub(line_no_colors, 1, v.start-1))
          local right = left + WindowTextWidth(self.window_name, self.font, string.sub(line_no_colors, v.start-1, v.stop-1))
          local top = self.text_y_position + ((count - self.line_start) * self.line_height)-1
          local bottom = top + self.line_height + 1
          local link_name = table.concat({v.text,"   ",count,v.start,v.stop})
          link_name = self:generateHotspotName(link_name)
          if not WindowHotspotInfo(self.window_name, link_name, 1) then
            self.hyperlinks[link_name] = v.text
            WindowAddHotspot(self.window_name, link_name, left, top, math.min(right, self.text_width), bottom, "TextWidget_MT.LinkHoverCallback", "TextWidget_MT.LinkHoverCancelCallback", "TextWidget_MT.MouseDownText", "TextWidget_MT.CancelMouseDown", "TextWidget_MT.MouseUp", "Right-click this URL if you want to open it:\n"..v.text, 1)
            WindowDragHandler(self.window_name, link_name, "TextWidget_MT.TextareaMoveCallback", "TextWidget_MT.TextareaReleaseCallback", 0x10)
            WindowScrollwheelHandler(self.window_name, link_name, "TextWidget_MT.WheelMoveCallback")
          end
        end
         
        -- create highlighting parameters when text is selected
        if self.copy_start_line ~= nil and self.copy_end_line ~= nil and count >= self.copy_start_line and count <= self.copy_end_line then
          ax = (((count == self.copy_start_line) and math.min(self.start_copying_x, WindowTextWidth(self.window_name, self.font, line_no_colors) + self.text_x_position)) or self.text_x_position)
          -- end of highlight for this line
          zx = math.min(self.text_width + self.text_x_position, (((count == self.copy_end_line) and math.min(self.end_copying_x, WindowTextWidth(self.window_name, self.font, line_no_colors) + self.text_x_position)) or WindowTextWidth(self.window_name, self.font, line_no_colors) + self.text_x_position))
        end
        self:drawLine(count - self.line_start, self.lines[count][1], ax, zx )
    end
  end
  BroadcastPlugin(999, "repaint")
end

function TextWidget_MT:drawLine (line, styles, backfill_start, backfill_end)
  local left = self.text_x_position
  local top = self.text_y_position + (line * self.line_height)
  if (backfill_start ~= nil and backfill_end ~= nil) then
    WindowRectOp(self.window_name, 2, backfill_start, top + 1, backfill_end, top + self.line_height + 1, 0x444444)
  end -- backfill
  if styles then
    for _, v in ipairs(styles) do
      local t = v.text
      -- now clean up dangling newlines that cause block characters to show
      if string.sub(v.text, -1) == "\n" then
        t = string.sub(v.text, 1, -2)
      end
      left = left + WindowText(self.window_name, self.font, t, left, top,  self.text_width + self.text_x_position, self.text_height + self.text_y_position, v.textcolour)
    end
  end
end

function TextWidget_MT:wrapLine(stylerun, rawURLs)
  local avail = self.text_width
  local line_styles = {}
  local beginning = true
  local length = 0
  local styles = copytable.deep(stylerun)
  local urls = copytable.deep(rawURLs)

  local remove = table.remove
  local insert = table.insert

  -- Keep pulling out styles and trying to fit them on the current line
  while #styles > 0 do
    -- break off the next style
    local style = remove(styles, 1)

    -- make this handle forced newlines like in the flickoff social
    -- by splitting off and sticking the next part back into the 
    -- styles list for the next pass
    foundbreak = false
    newline = string.find(style.text, "\n")
    if newline then
      insert(styles, 1, {text = string.sub(style.text,newline+1), 
        length = style.length-newline+1, 
        textcolour = style.textcolour,
        backcolour = style.backcolour}
      )
-- we're leaving in the newline characters here because we need to be 
-- able to copy them later. I'll clean up the buggy visual later when 
-- actually displaying the lines.
      style.length = newline
      style.text = string.sub(style.text,1,newline)
      foundbreak = true
    end

    local text_width = WindowTextWidth(self.window_name, self.font, style.text)

     -- if it fits, copy whole style in
    if text_width <= avail then
      insert(line_styles, style)
      length = length + style.length
      avail = avail - text_width
      if foundbreak then
        avail = 0
      end
    else -- otherwise, have to split style  
      -- look for trailing space (work backwards). remember where space is
      local col = style.length - 1
      local split_col
      -- keep going until out of columns
      while col > 1 do
        text_width = WindowTextWidth(self.window_name, self.font, style.text:sub(1, col))
        if text_width <= avail then
          if not split_col then
            split_col = col  -- in case no space found, this is where we can split
          end -- if
          -- see if space here
          if style.text:sub(col, col) == " " then
            split_col = col
            break
          end -- if space
        end -- if will now fit
        col = col - 1
      end -- while

      if split_col then
        -- if we found a place to split, use old style and truncate it.
        -- Also stick the rest back with the same styling back into the styles list
        insert(line_styles, style)
        local style_copy = copytable.shallow(style)
        style.text = style.text:sub(1, split_col)
        style.length = split_col
        style_copy.text = style_copy.text:sub(split_col + 1)
        style_copy.length = #style_copy.text
        insert(styles, 1, style_copy)
        length = length + style.length
      elseif next(line_styles) == nil then
        -- Actually, I don't think this can ever happen. -Fiendish
        insert(line_styles, style)
        length = length + style.length
      else
        -- if we're about to start a new style and the
        -- line is completely full, put it back in the list for later
        insert(styles, 1, style)
      end -- if    
      avail = 0  -- now we need to wrap    
    end -- if could/not fit whole thing in

    -- out of styles or out of room? add a line for what we have so far
    if #styles == 0 or avail <= 0 then
      if #self.lines >= self.max_scrollback_lines then
        -- if the history buffer is full then remove the oldest line
        remove(self.lines, 1)
        self.line_start = self.line_start - 1
        self.line_end = self.line_end - 1
      end -- buffer full

      local line_urls = {}
      while urls[1] and urls[1].stop <= length do
        insert(line_urls, remove(urls, 1))
      end

      if urls[1] and urls[1].start < length then
        local url = copytable.deep(urls[1])
        url.stop = length + 1
        urls[1].stop = urls[1].stop-1
        urls[1].old = true
        insert(line_urls, url)
      end

      for i,v in ipairs(urls) do
        urls[i].start = urls[i].start - length
        urls[i].stop = urls[i].stop - length
        if urls[i].start <= 1 then
          urls[i].start = 1
          urls[i].stop = urls[i].stop+1
        end
      end

      -- add new line
      table.insert(self.lines, {[1]=line_styles, [2]=beginning, [3]=line_urls} )
      if #self.lines > self.window_lines then
        self.line_start = self.line_start + 1
      end -- if
      if #self.lines > 1 then
        self.line_end = self.line_end + 1
      end -- if

      avail = self.text_width
      line_styles = {}
      length = 0
      beginning = false
    end -- line full
  end -- while we still have styles over
  self:draw()
end

-- Returns an array {start, end, text}
function TextWidget_MT:findURLs(text)
   local URLs = {}
   local start, position = 0, 0
   -- "rex" is a table supplied by MUSHclient for PCRE functionality.
   local re = rex.new("(?:https?://|mailto:)\\S*[\\w/=@#\\-\\?]")
   re:gmatch(text,
      function (link, _)
         start, position = string.find(text, link, position, true)
         table.insert(URLs, {start=start, stop=position, text=link})
      end
   )
   return URLs
end -- function findURL

function TextWidget_MT:wrapAllLines()
  self.lines = {}
  for _,styles in ipairs(self.raw_lines) do
    self:wrapLine(styles[1], styles[2])
  end
  self.line_start = math.max(1, #self.lines - self.window_lines + 1)
  self.line_end = math.max(1, #self.lines)
  self:draw()
end

function TextWidget_MT:clickUrl(hotspot_id)
  local url = self.hyperlinks[hotspot_id]
  if url then
    OpenBrowser(url)
  end
end

function TextWidget_MT:copyAndNotify(text)
  ColourNote("cyan","","--------------------Copied to clipboard--------------------")
  ColourNote("yellow","", text)
  ColourNote("cyan","","-----------------------------------------------------------")         
  SetClipboard(text)
end

function TextWidget_MT:copyUrl(hotspot_id)
  local url = self.hyperlinks[hotspot_id]
  if url then
    self:copyAndNotify(url)
  end
end

function TextWidget_MT:getAllText()
  return copytable.deep(self.raw_lines)
end

function TextWidget_MT:repositionText(x, y, width, height)
  self.text_x_position = x
  self.text_y_position = y
  self.text_width = width
  self.text_height = height
  self.window_lines = math.floor(self.text_height / self.line_height)
  self.line_start = math.max(1, #self.lines - self.window_lines + 1)
  self.line_end = math.max(1, #self.lines)
  WindowMoveHotspot(self.window_name, self:generateHotspotName("textarea"), self.text_x_position, self.text_y_position, self.text_x_position + self.text_width, self.text_y_position + self.text_height)
end

function TextWidget_MT:repositionScrollbar(x, y, height)
  self.scrollbar_x_position = x
  self.scrollbar_y_position = y
  self.scrollbar_height = height
  WindowMoveHotspot(self.window_name, self:generateHotspotName("up"), self.scrollbar_x_position, self.scrollbar_y_position, self.scrollbar_x_position + self.scrollbar_width, self.scrollbar_y_position + self.scrollbar_width)
  WindowMoveHotspot(self.window_name, self:generateHotspotName("down"), self.scrollbar_x_position, self.scrollbar_y_position + self.scrollbar_height - self.scrollbar_width, self.scrollbar_x_position + self.scrollbar_width, self.scrollbar_y_position + self.scrollbar_height)
end

function TextWidget_MT.ScrollbarMoveCallback(flags, hotspot_id)
  local widget = getWidgetFromHotspotID(hotspot_id)
  local mouseposy = WindowInfo(widget.window_name, 18)
  local windowtop = WindowInfo(widget.window_name, 2)
  widget.scrollbar_pos = math.max(mouseposy - windowtop + widget.scrollbar_start_pos, widget.scrollbar_width + widget.scrollbar_y_position)
  if widget.scrollbar_pos + widget.scrollbar_size >= widget.scrollbar_y_position + widget.scrollbar_height - widget.scrollbar_width then
    widget.scrollbar_pos = widget.scrollbar_height + widget.scrollbar_y_position - widget.scrollbar_size - widget.scrollbar_width
    widget.line_start = math.max(1, #widget.lines - widget.window_lines + 1)
    widget.line_end = #widget.lines
  else
    local available_space = widget.scrollbar_height - (2*widget.scrollbar_width) - widget.scrollbar_size
    local space_per_step = available_space / (widget.scrollbar_steps - 1)
    local current_pos = widget.scrollbar_pos - widget.scrollbar_width - widget.scrollbar_y_position
    local current_step = math.floor((current_pos / space_per_step) + 1.5)
    widget.line_start = math.max(1, current_step)
    widget.line_end = math.min(widget.line_start + widget.window_lines - 1, #widget.lines)
  end
  widget:draw()
end

function TextWidget_MT.ScrollbarReleaseCallback(flags, hotspot_id)
  local widget = getWidgetFromHotspotID(hotspot_id)
  widget.dragging_scrollbar = false
  widget:draw()
end

function TextWidget_MT.TextareaMoveCallback(flags, hotspot_id)
  local widget = getWidgetFromHotspotID(hotspot_id)
  if bit.band (flags, miniwin.hotspot_got_lh_mouse) ~= 0 then -- only on left mouse button
    widget.copied_text = ""
    widget.end_copying_x = WindowInfo(widget.window_name, 17) - WindowInfo(widget.window_name, 1)
    widget.end_copying_y = WindowInfo(widget.window_name, 18) - WindowInfo(widget.window_name, 2)
    local ypos = widget.end_copying_y
    widget.copy_end_windowline = math.floor((widget.end_copying_y - widget.text_y_position) / widget.line_height)
    widget.copy_end_line = widget.copy_end_windowline + widget.line_start
    widget.copy_start_line = widget.temp_start_line
    widget.start_copying_x = widget.temp_start_copying_x

    -- get the entire last line if we drag off the bottom
    if widget.copy_end_line <= widget.line_end then
       widget.end_copying_x = math.max(widget.text_x_position, math.min(widget.end_copying_x, widget.text_x_position + widget.text_width))
    else
       widget.end_copying_x = widget.text_x_position + widget.text_width
    end

    if not widget.copy_start_line then
      -- OS bug causing errors for me. hack around stupid mouse click tracking mess.
      -- It really shouldn't be possible to get here, ever, but what the hell, it happened.
      return
    end

    if (widget.copy_start_line > #widget.lines) then
      widget.start_copying_x = widget.text_x_position + widget.text_width
    end

    -- the user is selecting backwards, so reverse the start/end orders
    if widget.copy_end_line < widget.temp_start_line then
      local temp = widget.copy_end_line
      widget.copy_end_line = widget.copy_start_line
      widget.copy_start_line = temp
      temp = widget.end_copying_x
      widget.end_copying_x = widget.start_copying_x
      widget.start_copying_x = temp
    elseif (widget.copy_end_line == widget.copy_start_line) and (widget.end_copying_x < widget.start_copying_x) then
      local temp = widget.end_copying_x
      widget.end_copying_x = widget.start_copying_x
      widget.start_copying_x = temp
    end

    local copied_part = ""
    for copy_line = widget.copy_start_line, widget.copy_end_line do
      if (widget.lines[copy_line] ~= nil) then
        local startpos = 1
        local endpos = 99999
        if (copy_line - widget.line_start + 1 > 0 and copy_line - widget.line_start < widget.window_lines and copy_line - widget.line_start < #widget.lines) then

          -- Clamp to character boundaries instead of selecting arbitrary pixel positions...

          -- Get the line without color codes so we can reference position to character
          local text_table = {}
          for i,v in pairs(widget.lines[copy_line][1]) do
             table.insert(text_table, v.text)
          end
          local line_no_colors = table.concat(text_table)

          startpos = 0
          endpos = #line_no_colors

          -- Clamp the selection start position
          if copy_line == widget.copy_start_line then
            for pos=1,#line_no_colors do
              if WindowTextWidth(widget.window_name, widget.font, string.sub(line_no_colors, 1, pos)) + widget.text_x_position > widget.start_copying_x then
                widget.start_copying_x = WindowTextWidth(widget.window_name, widget.font, string.sub(line_no_colors, 1, pos-1)) + widget.text_x_position
                break
              end
              startpos = pos
            end
          end
          -- Clamp the selection end position
          if copy_line == widget.copy_end_line then
            endpos = 0
            for pos=1,#line_no_colors do
              if WindowTextWidth(widget.window_name, widget.font, string.sub(line_no_colors, 1, pos)) + widget.text_x_position > widget.end_copying_x then
                widget.end_copying_x = WindowTextWidth(widget.window_name, widget.font, string.sub(line_no_colors, 1, pos-1)) + widget.text_x_position
                break
              end
              endpos = pos
            end
          end

        end

        -- Store selected area for later
        if endpos > startpos then
           copied_part = StylesToColoursOneLine(widget.lines[copy_line][1], startpos+1, endpos)
           if copy_line ~= widget.copy_end_line and copy_line ~= #widget.lines and widget.lines[copy_line + 1][2] == true then
             -- only put a line break if the next line is from a different message
             copied_part = copied_part.."@w\n"
           elseif copy_line == widget.copy_end_line or copy_line == #widget.lines then
             -- tack a white code on to the very end
             copied_part = copied_part.."@w"
           end
           widget.copied_text = widget.copied_text..(((copied_part ~= nil) and copied_part) or "")
        end

      end -- if valid line
    end -- for
    
    if widget.scrollable then
       -- Scroll if the mouse is dragged off the top or bottom
       if ypos < widget.text_y_position then
         if widget.keepscrolling ~= "up" then
           widget.keepscrolling = "up"
           widget:scroll()
         end
         return
       elseif ypos > widget.text_y_position + widget.text_height then
         if widget.keepscrolling ~= "down" then
           widget.keepscrolling = "down"
           widget:scroll()
         end
         return
       else
         widget.keepscrolling = ""
       end
    end
    widget:refreshText()
  end
end

function TextWidget_MT.MouseDownText(flags, hotspot_id)
  if (flags == miniwin.hotspot_got_lh_mouse) then
     local widget = getWidgetFromHotspotID(hotspot_id)
     widget.temp_start_copying_x = WindowInfo(widget.window_name, 14)
     widget.start_copying_y = WindowInfo(widget.window_name, 15)
     widget.copy_start_windowline = math.floor((widget.start_copying_y - widget.text_y_position) / widget.line_height)
     widget.temp_start_line = widget.copy_start_windowline + widget.line_start
     widget.copied_text = ""
     widget.copy_start_line = nil
     widget.copy_end_line = nil
     widget:refreshText()
  end
end

function TextWidget_MT.TextareaReleaseCallback(flags, hotspot_id)
  local widget = getWidgetFromHotspotID(hotspot_id)
  widget.copy_start_line = math.min(#widget.lines, widget.copy_start_line or 0)
  widget.copy_end_line = math.min(#widget.lines, widget.copy_end_line or 0)
end

function TextWidget_MT.MouseDownScrollbar(flags, hotspot_id)
  local widget = getWidgetFromHotspotID(hotspot_id)
  widget.scrollbar_start_pos = WindowHotspotInfo(widget.window_name, widget:generateHotspotName("scroller"), 2) - WindowInfo(widget.window_name, 15)
  widget.dragging_scrollbar = true
end

function TextWidget_MT.LinkHoverCallback(flags, hotspot_id)
  local url = string.gsub(hotspot_id, "(.*   ).*", "%1")
  local widget = getWidgetFromHotspotID(hotspot_id)
  local hotspots = WindowHotspotList(widget.window_name)
  for _, v in ipairs (hotspots) do
    if string.find(v, url, 1, true) then
      local left = WindowHotspotInfo(widget.window_name, v, 1)
      local right = WindowHotspotInfo(widget.window_name, v, 3)
      local bottom = WindowHotspotInfo(widget.window_name, v, 4)
      WindowLine(widget.window_name, left, bottom, right, bottom, 0xffffff, 256, 1);
    end
  end
  BroadcastPlugin(999, "repaint")
end

function TextWidget_MT.LinkHoverCancelCallback(flags, hotspot_id)
  local widget = getWidgetFromHotspotID(hotspot_id)
  local url = string.gsub(hotspot_id, "(.*   ).*", "%1")
  if not string.find(WindowInfo(widget.window_name, 19), url, 1, true) then
    widget:refreshText()
  end
end

function TextWidget_MT.WheelMoveCallback(flags, hotspot_id)
   local widget = getWidgetFromHotspotID(hotspot_id)
   if bit.band(flags, 0x100) ~= 0 then
      -- down
      if widget.line_start < #widget.lines - widget.window_lines + 1 then
         widget.line_start = math.max(1, math.min(#widget.lines - widget.window_lines + 1, widget.line_start + 3))
         widget.line_end = math.min(#widget.lines, widget.line_start + widget.window_lines - 1)    
         widget:draw()
      end
   elseif widget.line_start > 1 then
      -- up
      widget.line_start = math.max(1, widget.line_start - 3)
      widget.line_end = math.min(#widget.lines, widget.line_start + widget.window_lines - 1)
      widget:draw()
  end -- if
end

function TextWidget_MT:copyPlain(hotspot_id)
  self:copyAndNotify(strip_colours(self.copied_text))
end

function TextWidget_MT:copy(hotspot_id)
  self:copyAndNotify(self.copied_text)
end

function  TextWidget_MT:copyFull()
   ColourNote("yellow","","All messages copied to clipboard.")
   local t = {}
   for _,styles in ipairs(self.raw_lines) do
      table.insert(t, StylesToColoursOneLine(styles[1]))
   end
   SetClipboard(table.concat(t,"@w\n").."@w")
end

function TextWidget_MT:RightClickMenu(hotspot_id)
  local menuText = ""
  local callbacks = {}
  if self.hyperlinks[hotspot_id] then
     menuText = "Go to URL: "..self.hyperlinks[hotspot_id].."|Copy URL to Clipboard|-"
     callbacks = {TextWidget_MT.clickUrl, TextWidget_MT.copyUrl}
  end
  if self.copied_text ~= "" then
    menuText = menuText..((menuText ~= "") and "|" or "").."Copy Selected Without Colors|Copy Selected"
    table.insert(callbacks, TextWidget_MT.copyPlain)
    table.insert(callbacks, TextWidget_MT.copy)
  end
  menuText = menuText..((menuText ~= "") and "|" or "").."Copy All"
  table.insert(callbacks, TextWidget_MT.copyFull)
  
  local external_text = self.GetExternalMenuText()
  if external_text then
    menuText = menuText.."|-|"..external_text
  end
  local external_callbacks = self.GetExternalMenuFunctions()
  if external_callbacks then
     for i,v in ipairs(external_callbacks) do
        table.insert(callbacks, v)
     end
  end
  if menuText ~= "" then
     result = tonumber( WindowMenu (self.window_name,
        WindowInfo (self.window_name, 14),  -- x position
        WindowInfo (self.window_name, 15),   -- y position
        "!"..menuText) ) -- content

     if result then
        callbacks[result](self, hotspot_id)
     end
  end
end

function TextWidget_MT:GetExternalMenuFunctions()
end
function TextWidget_MT:GetExternalMenuText()
end

function TextWidget_MT.MouseUp(flags, hotspot_id)
  local widget = getWidgetFromHotspotID(hotspot_id)
  widget.keepscrolling = ""
  if bit.band (flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
    widget:RightClickMenu(hotspot_id)
  else
    widget:draw()
  end
  return true
end

function TextWidget_MT.CancelMouseDown(flags, hotspot_id)
  local widget = getWidgetFromHotspotID(hotspot_id)
  widget.keepscrolling = ""
  widget:draw()
end

function TextWidget_MT.MouseDownDownArrow(flags, hotspot_id)
  local widget = getWidgetFromHotspotID(hotspot_id)
  widget.keepscrolling = "down"
  widget:scroll()
end

function TextWidget_MT.MouseDownUpArrow(flags, hotspot_id)
  local widget = getWidgetFromHotspotID(hotspot_id)
  widget.keepscrolling = "up"
  widget:scroll()
end

-- Scroll through the window contents line by line. Used when pressing the up/down arrow buttons.
function TextWidget_MT:scroll()
  wait.make(function ()
     while self.keepscrolling == "up" or self.keepscrolling == "down" do
       if self.keepscrolling == "up" then
         if (self.line_start > 1) then
           self.line_start = self.line_start - 1
           self.line_end = self.line_end - 1
         end
       elseif self.keepscrolling == "down" then
         if (self.line_end < #self.lines) then
           self.line_start = self.line_start + 1
           self.line_end = self.line_end + 1
         end
       end
       self:draw()
       wait.time(0.01)
     end
  end)
end
