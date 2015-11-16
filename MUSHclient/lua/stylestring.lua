-- Original from Twisol ( http://www.mushclient.com/forum/?id=11073&reply=21#reply21 )
-- Simplified and improved by Fiendish

require "copytable"

local stylestring = {} -- the table representing the class, which will double as the metatable for the instances
stylestring.__index = stylestring

setmetatable(stylestring, {
   __call = function (cls, ...)
      return cls.new(...)
   end,
})

function stylestring.new(str, styles)
   local self = setmetatable({}, stylestring)
   self.str = str
   self.styles = copytable.deep(styles)
   return self
end

function stylestring.tell(self)
   local styles = self.styles
   for i = 1,#styles do
     ColourTell(RGBColourToName(styles[i].textcolour), RGBColourToName(styles[i].backcolour), styles[i].text)
   end
end

function stylestring.note(self)
   self:tell()
   Note()
end

-- Simple replace. Clean and fast. Can't match across color boundaries.
function stylestring.replace(self, match, replace)
   local styles = self.styles
   self.str = self.str:gsub(match, replace)
   for i=1,#styles do
      styles[i].text = styles[i].text:gsub(match, replace)
      styles[i].length = #styles[i].text
   end
end


-- Complex replace. Matches across color boundaries
function stylestring.deepreplace(self, match, replace)
   -- NYI
end

return stylestring
