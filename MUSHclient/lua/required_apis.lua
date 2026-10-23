-- Check the MUSHclient APIs required by a feature.
local function HasRequiredAPIs(required, feature)
   local missing = {}
   for _, name in ipairs(required) do
      if type(_G[name]) ~= "function" then
         table.insert(missing, name)
      end
   end
   if #missing == 0 then
      return true
   end

   ColourNote(
      "white",
      "red",
      feature .. " unavailable. This MUSHclient build is missing: " ..
         table.concat(missing, ", "))
   return false
end

return HasRequiredAPIs
