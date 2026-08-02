-- ~/.config/hypr/shells/ml4w/hyprland.lua
-- ml4w (mylinuxforwork/dotfiles, ML4W OS) — Hyprland Lua config (modular loader)
--
-- The shell is the quickshell config named "ml4w" (~/.config/quickshell/ml4w,
-- a symlink into ~/.local/share/ml4w-dotfiles/dotfiles/.config/quickshell).
-- Everything it exposes goes through `qs -c ml4w ipc call <target> <fn>` — see
-- hyprland/keybinds.lua.

-- Default monitor conf
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Modules
require("hyprland.env")
require("hyprland.general")
require("hyprland.input")
require("hyprland.scrolling")
require("hyprland.decoration")
require("hyprland.animations")
require("hyprland.misc")
require("hyprland.rules")
require("hyprland.execs")
require("hyprland.keybinds")
