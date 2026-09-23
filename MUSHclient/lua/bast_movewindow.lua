-- Adapt Bastmush's movement callbacks to add global miniwindow snapping/locking without
-- changing its plugin files.
local states = setmetatable({}, {__mode = "k"})
local active
local movement, snap

local function pack(...)
   return {n = select("#", ...), ...}
end

local function movement_object(hotspot)
   if type(hotspot) ~= "string" then return end
   local id, name = hotspot:match("^(.-):(.*)$")
   local helper = rawget(_G, "phelper")
   local object = helper and helper.pobjects_by_id and helper.pobjects_by_id[id]
   if name == "drag_hotspot" and object and object.otype == "Miniwin" and
      object.hyperlink_functions and object.hyperlink_functions.movecallback and
      type(object.dragmove) == "function" and
      object.hyperlink_functions.movecallback[name] == object.dragmove then
      return object
   end
end

local function finish()
   if active then
      snap.finish_feedback()
      active = nil
   end
end

local function begin(object, flags, hotspot)
   finish()
   if not movement then
      require "movewindow"
      movement = movewindow
      snap = require "window_snap"
   end
   local state = states[object]
   if not state then
      -- movewindow.install needs an identifier suitable for generated Lua callback names,
      -- and Bast's window names may not be Lua identifiers.
      local key = "bast_" .. object.winid:gsub(".", function(c)
         return string.format("%02x", c:byte())
      end)
      state = movement.install(key, 0, 2, true)
      state.win = object.winid
      states[object] = state
   end
   state.window_left = WindowInfo(object.winid, 1)
   state.window_top = WindowInfo(object.winid, 2)
   state.window_mode = WindowInfo(object.winid, 7)
   state.window_flags = WindowInfo(object.winid, 8)
   state.mousedown(flags, hotspot)
   active = object
end

local wrappers = {}
function wrappers.mousedown(original, flags, hotspot, ...)
   local results = pack(original(flags, hotspot, ...))
   local object = movement_object(hotspot)
   if object then begin(object, flags, hotspot) end
   return unpack(results, 1, results.n)
end

function wrappers.movecallback(original, flags, hotspot, ...)
   local object = movement_object(hotspot)
   if object and active == object then
      local state = states[object]
      state.dragmove(flags, hotspot)
      if not state.drag_locked then
         object.x, object.y = state.window_left, state.window_top
         object.windowpos = -1
      end
      return
   end
   return original(flags, hotspot, ...)
end

function wrappers.releasecallback(original, flags, hotspot, ...)
   local object = movement_object(hotspot)
   if object and active == object then
      states[object].dragrelease(flags, hotspot)
      finish()
      return
   end
   return original(flags, hotspot, ...)
end

for _, name in ipairs({"cancelmousedown", "OnPluginDisable", "OnPluginClose"}) do
   wrappers[name] = function(original, ...)
      finish()
      if original then return original(...) end
   end
end

-- Keep these wrappers active when plugins define or replace their callbacks.
local proxy = require "callback_proxy"
for name, wrapper in pairs(wrappers) do
   proxy.wrap(name, function(original, ...)
      if original or name == "OnPluginClose" or name == "OnPluginDisable" then
         return wrapper(original, ...)
      end
   end)
end

return true
