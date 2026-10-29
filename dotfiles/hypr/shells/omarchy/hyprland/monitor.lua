-- omarchy house layer — monitor
-- omarchy leaves monitor config to the user's hypr/monitors.lua, which we do
-- not load (see trap 1 in hyprland.lua). Same default as the other shells.

dofile(os.getenv("HOME") .. "/.config/hypr/common/monitor.lua")
