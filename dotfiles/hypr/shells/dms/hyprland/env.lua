hl.config({
    env = {
        { "GDK_BACKEND", "wayland,x11" },
        { "QT_QPA_PLATFORM", "wayland;xcb" },
        { "SDL_VIDEODRIVER", "wayland,x11,windows" },
        { "CLUTTER_BACKEND", "wayland" },
        { "ELECTRON_OZONE_PLATFORM_HINT", "auto" },
        { "XDG_CURRENT_DESKTOP", "Hyprland" },
        { "XDG_SESSION_TYPE", "wayland" },
        { "XDG_SESSION_DESKTOP", "Hyprland" },
    },
})
