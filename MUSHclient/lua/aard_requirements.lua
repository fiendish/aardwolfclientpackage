require "gmcphelper" -- https://github.com/fiendish/aardwolfclientpackage/wiki/Using-GMCP
require "checkplugin"

-- Guarantee various useful world file settings
SetOption("omit_date_from_save_files", 1)  -- slightly less clutter in settings files
SetOption("utf_8", 1)  -- needed for alternate maptypes in main output
SetAlphaOption("terminal_identification", "MUSHclient-Aard") -- helps Lasher count for the 'clients' in-game command

db = sqlite3.open(GetInfo(82))  -- open preferences
db:exec 'UPDATE prefs SET value = 0 WHERE name = "OpenActivityWindow"' -- stop opening the activity window
db:close()  -- close
utils.reload_global_prefs()

-- Load plugins which are either necessary for the package to function or unobjectionably utile.
do_plugin_check_now("162bba4a5ecef2bb32b5652f", "aard_package_update_checker") -- package update checker
do_plugin_check_now("abc1a0944ae4af7586ce88dc", "aard_repaint_buffer") -- repaint buffer
do_plugin_check_now("3e7dedbe37e44942dd46d264", "aard_GMCP_handler")    -- GMCP handler
do_plugin_check_now("462b665ecb569efbf261422f", "aard_miniwindow_z_order_monitor") -- z order manager
do_plugin_check_now("55616ea13339bc68e963e1f8", "aard_chat_echo") -- gmcp channels in main display
do_plugin_check_now("520bc4f29806f7af0017985f", "Hyperlink_URL2") -- make hyperlinks from urls


