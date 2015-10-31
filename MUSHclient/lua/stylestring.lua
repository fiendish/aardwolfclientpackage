-- Original from Twisol ( http://www.mushclient.com/forum/?id=11073&reply=21#reply21 )
-- Completed and improved a bit by Fiendish

stylestring = {} -- the table representing the class, which will double as the metatable for the instances
stylestring.__index = stylestring

setmetatable(stylestring, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

function stylestring.new(str, styles)
  local self = setmetatable({}, stylestring)
  self.str = str
  self.styles = styles
  return self
end

function stylestring.tell(self)
  local str, styles = self.str, self.styles
  local left = 1
  for _,t in pairs(styles) do
    local fg = RGBColourToName(t.textcolour)
    local bg = RGBColourToName(t.backcolour)
    ColourTell(fg, bg, str:sub(left, left + t.length - 1))
    left = left + t.length
  end
end

function stylestring.note(self)
  self:tell()
  AnsiNote() -- not sure if Note() preserves the current color, but I know this does - Twisol
end

function stylestring.replace(self, match, replace)
  local str = self.str
  local styles = self.styles
  local match_len = #match
  
  local left = 1
  local mid = str:find(match)
  if mid == nil then return end
  
  local st_left = 0
  local st_right = 0
  local st_i_not_before = 1
  local st_i_not_after = 1
  while mid do
    if left then
      str = str:sub(left, mid-1) .. replace .. str:sub(mid + match_len)
      while st_left + styles[st_i_not_before].length < mid do
         st_left = st_left + styles[st_i_not_before].length
         st_i_not_before = st_i_not_before + 1
      end
       styles[st_i_not_before].text = styles[st_i_not_before].text:gsub(match, replace)
       styles[st_i_not_before].length = match_len
       left = mid + match_len
       -- continue implementing here if matches allowed across style boundaries
    end
    mid = str:find(match, left)
  end
  
  self.str = str
end
