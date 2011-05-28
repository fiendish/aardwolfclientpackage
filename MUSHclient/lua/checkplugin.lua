-- checkplugin.lua

-- Checks the nominated plugin is installed

function do_plugin_check_now (id, name)

   if not IsPluginInstalled (id) then
      ColourNote ("white", "green", "Plugin '" .. name .. "' not installed. Attempting to install it...") 
      LoadPlugin (GetPluginInfo(GetPluginID (), 20) .. name .. ".xml") 

      if IsPluginInstalled (id) then
         ColourNote ("white", "green", "Success!") 
      else
         ColourNote ("white", "red", string.rep ("-", 80))
         ColourNote ("white", "red", "Plugin '" .. name .. "' not installed. Please download and install it.") 
         ColourNote ("white", "red", "It is required for the correct operation of the " ..
                    GetPluginName () .. " plugin.")
         ColourNote ("white", "red", string.rep ("-", 80))
         return
      end
   end
   
   if not GetPluginInfo(id, 17) then
      ColourNote ("white", "green", "Plugin '" .. name .. "' not enabled. Attempting to enable it...")
      EnablePlugin(id, true)
      if GetPluginInfo(id, 17) then
         ColourNote ("white", "green", "Success!") 
      else
         ColourNote ("white", "red", string.rep ("-", 80))
         ColourNote ("white", "red", "Plugin '" .. name .. "' not enabled. Please make sure it can be enabled.")
         ColourNote ("white", "red", "It is required for the correct operation of the " ..
                    GetPluginName () .. " plugin.")
         ColourNote ("white", "red", string.rep ("-", 80))        
      end
   end
end -- do_plugin_check_now



function checkplugin (id, name)
  -- give them time to load
  DoAfterSpecial (2, 
                  "do_plugin_check_now ('" .. id .. "', '" .. name .. "')", 
                  sendto.script)
end -- checkplugin

function load_ppi (id, name)
local PPI = require "ppi"

  local ppi = PPI.Load(id)  
  if ppi then
    return ppi
  end
  
  ColourNote ("white", "green", "Plugin '" .. name .. "' not installed. Attempting to install it...") 
  LoadPlugin (GetPluginInfo(GetPluginID (), 20) .. name .. ".xml") 
  
  ppi = PPI.Load(id)  -- try again
  if ppi then
    ColourNote ("white", "green", "Success!") 
    return ppi
  end

  ColourNote ("white", "red", string.rep ("-", 80))
  ColourNote ("white", "red", "Plugin '" .. name .. "' not installed. Please download and install it.") 
  ColourNote ("white", "red", string.rep ("-", 80))
  
  return nil
end -- function load_ppi 