-- Make it possible to replace or wrap the behavior of a global function even before that
-- function is defined. This allows our lua code to wrap MUSHclient callbacks even if the
-- plugin defines them after our code runs. We use this for e.g. altering the behavior of
-- the OnPluginDisable and OnPluginClose callbacks in themed windows, and for wrapping
-- the movement callbacks in Bast's plugins that don't use the default movement handler.
--
-- Defining a global function in Lua assigns a function to _G[name]. We keep that key
-- absent which makes function lookups go through _G's metatable, allowing us to capture
-- assignments, store the original function separately, and return the desired function
-- wrapped by our own behavior.
local callbacks = {}

-- Combine wrappers. The last one added runs first.
local function rebuild(entry)
   local call = entry.original
   for _, layer in ipairs(entry.wrappers) do
      local original = call
      call = function(...) return layer(original, ...) end
   end
   entry.call = call
end

-- Preserve existing behavior for other globals.
local previous = getmetatable(_G) or {}
local mt = {}
for key, value in pairs(previous) do mt[key] = value end

mt.__index = function(t, key)
   if callbacks[key] then return callbacks[key].dispatch end
   if type(previous.__index) == "function" then return previous.__index(t, key) end
   if previous.__index then return previous.__index[key] end
end

-- Keep wrappers when the plugin defines or replaces the function.
mt.__newindex = function(t, key, value)
   if callbacks[key] then
      callbacks[key].original = value
      rebuild(callbacks[key])
   elseif type(previous.__newindex) == "function" then
      previous.__newindex(t, key, value)
   elseif previous.__newindex then
      previous.__newindex[key] = value
   else
      rawset(t, key, value)
   end
end
setmetatable(_G, mt)

local function wrap(name, wrapper)
   local entry = callbacks[name]
   if not entry then
      entry = {original = _G[name], wrappers = {}}
      entry.dispatch = function(...)
         return entry.call(...)
      end
      callbacks[name] = entry
      -- Keep reads and assignments routed through the proxy.
      rawset(_G, name, nil)
   end
   entry.wrappers[#entry.wrappers + 1] = wrapper
   rebuild(entry)
end

return {wrap = wrap}
