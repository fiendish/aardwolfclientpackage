require "gmcphelper"
require "checkplugin"

-- Load plugins which are either necessary for the package to function or unobjectionably utile.
do_plugin_check_now("520bc4f29806f7af0017985f", "Hyperlink_URL2") -- make hyperlinks from urls
do_plugin_check_now("162bba4a5ecef2bb32b5652f", "aard_package_update_checker") -- package update checker
do_plugin_check_now("abc1a0944ae4af7586ce88dc", "aard_repaint_buffer") -- repaint buffer
do_plugin_check_now("3e7dedbe37e44942dd46d264", "aard_GMCP_handler")    -- GMCP handler
do_plugin_check_now("462b665ecb569efbf261422f", "aard_miniwindow_z_order_monitor") -- z order manager
do_plugin_check_now("55616ea13339bc68e963e1f8", "aard_chat_echo") -- gmcp channels in main display

-- Activate various useful world file settings

-- These get activated always
SetOption("omit_date_from_save_files", 1)  -- slightly less clutter in settings files
SetOption("utf_8", 1)  -- needed for alternate maptypes in main output

-- These get activated at least once, but not after that
aardclient_settings_to_activate_at_least_once = {
   "show_underline",  -- needed for hyperlink underlining
   "underline_hyperlinks"  -- oddly enough also needed for hyperlink underlining
}

for i,v in ipairs(aardclient_settings_to_activate_at_least_once) do
   if GetVariable("aardclient_activated_"..v) ~= "done" then
      SetOption (v, 1)
      SetVariable("aardclient_activated_"..v, "done")
   end
end
