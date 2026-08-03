local home = os.getenv("HOME")

hl.on("hyprland.start", function()
    -- The shell: one quickshell instance as named config "ml4w".
    hl.exec_cmd("qs -c ml4w")
    -- The workspace overview and the settings app are SEPARATE quickshell
    -- processes upstream (ml4w-autostart starts both), not windows of the main
    -- shell — they are `qs -p <path>` instances with their own IPC targets
    -- ("overview", "settings"). Started here so the binds in keybinds.lua have
    -- something to talk to; switch-shell.sh starts and tears down both too.
    hl.exec_cmd("qs -p " .. home .. "/.config/ml4w-overview")
    -- PROFILE picks the settings profile dir under
    -- ~/.config/ml4w-dotfiles-settings; without it SettingsWindow has no
    -- settings.json to render. Same value ml4w-autostart uses.
    hl.exec_cmd("env PROFILE=com.ml4w.dotfiles qs -p "
        .. home .. "/.local/share/ml4w-dotfiles-settings/quickshell")
    -- Supporting daemons. Shared infra that survives shell switches, so on a
    -- mid-session switch the switch script re-guards (starts if missing) them.
    hl.exec_cmd("swaync")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("nm-applet --indicator")
    -- Wallpaper + theming. Theme.qml reads ~/.config/ml4w/colors/colors.json
    -- and its onCompleted reload is disabled upstream, so load the colors
    -- explicitly after quickshell has registered its IPC handler. exec-once
    -- does not re-fire on `hyprctl reload`, so this is start-only; the switch
    -- script re-triggers the reload on switch.
    hl.exec_cmd("awww img " .. os.getenv("HOME") .. "/.config/ml4w/wallpapers/default.jpg")
    hl.exec_cmd("matugen -c " .. os.getenv("HOME") .. "/.config/matugen-ml4w/config.toml image "
        .. os.getenv("HOME") .. "/.config/ml4w/wallpapers/default.jpg --source-color-index 0")
    hl.exec_cmd("sh -c 'sleep 2; qs -c ml4w ipc call theme-manager reload'")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
