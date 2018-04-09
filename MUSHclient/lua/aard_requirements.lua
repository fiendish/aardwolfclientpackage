require "gmcphelper" -- https://github.com/fiendish/aardwolfclientpackage/wiki/Using-GMCP
require "checkplugin"

-- Guarantee various useful world file settings
SetOption("omit_date_from_save_files", 1)  -- slightly less clutter in settings files
SetAlphaOption("terminal_identification", "MUSHclient-Aard") -- helps Lasher count for the 'clients' in-game command

if not GetVariable("aard_theme_just_reloading") then
   -- Edit the preferences db to stop opening the activity window at startup
   local aard_req_prefs_db = sqlite3.open(GetInfo(82))
   local aard_req_pref_activity_window = 1
   for a in aard_req_prefs_db:nrows('SELECT value FROM prefs WHERE name = "OpenActivityWindow"') do
      aard_req_pref_activity_window = a['value']
   end
   if tonumber(aard_req_pref_activity_window) ~= 0 then
      aard_req_prefs_db:exec 'UPDATE prefs SET value = 0 WHERE name = "OpenActivityWindow"'
      aard_req_prefs_db:close()
      utils.reload_global_prefs()
   end
   if aard_req_prefs_db:isopen() then
      aard_req_prefs_db:close()
   end

   -- Load plugins which are either necessary for the package to function or unobjectionably utile.
   do_plugin_check_now("162bba4a5ecef2bb32b5652f", "aard_package_update_checker") -- package update checker
   do_plugin_check_now("abc1a0944ae4af7586ce88dc", "aard_repaint_buffer") -- repaint buffer
   do_plugin_check_now("3e7dedbe37e44942dd46d264", "aard_GMCP_handler")    -- GMCP handler
   do_plugin_check_now("462b665ecb569efbf261422f", "aard_miniwindow_z_order_monitor") -- z order manager
   do_plugin_check_now("55616ea13339bc68e963e1f8", "aard_chat_echo") -- gmcp channels in main display
   do_plugin_check_now("520bc4f29806f7af0017985f", "Hyperlink_URL2") -- make hyperlinks from urls
   do_plugin_check_now("04d9e64f835452b045b427a7", "aard_Copy_Colour_Codes") -- Ctrl+D to copy selected text with color codes
   do_plugin_check_now("23832d1089f727f5f34abad8", "aard_soundpack") -- pre-made collection of common sound triggers
end

DeleteVariable("aard_theme_just_reloading")