hl.on("hyprland.start", function()
    -- The shell: one quickshell instance as named config "ml4w".
    hl.exec_cmd("qs -c ml4w")
    -- Supporting daemons. These are shared infra and survive shell switches,
    -- so a switch never needs to (re)start them.
    hl.exec_cmd("swaync")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("nm-applet --indicator")
    -- Wallpaper + theming. Theme.qml reads ~/.config/ml4w/colors/colors.json
    -- and its onCompleted reload is disabled upstream, so load the colors
    -- explicitly after quickshell has registered its IPC handler. exec-once
    -- does not re-fire on `hyprctl reload`, so this is start-only; the switch
    -- script re-triggers the reload on switch.
    hl.exec_cmd("awww img " .. os.getenv("HOME") .. "/.config/ml4w/wallpapers/default.jpg")
    hl.exec_cmd("matugen -c " .. os.getenv("HOME") .. "/.config/matugen-ml4w/config.toml "
        .. os.getenv("HOME") .. "/.config/ml4w/wallpapers/default.jpg")
    hl.exec_cmd("sh -c 'sleep 2; qs -c ml4w ipc call theme-manager reload'")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
