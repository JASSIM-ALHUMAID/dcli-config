-- omarchy house layer — keybinds
-- Deliberately small. This shell KEEPS omarchy's keymap — that is the reason to
-- load its config at all — so the only binds touched are the few that would
-- otherwise make the machine unusable or that provide house-style app launches
-- on combos omarchy leaves free.

local terminal     = "wezterm-gui"
local browser      = "brave-browser-nightly"
local zenBrowser   = "zen-browser"
local fileExplorer = "nautilus"

-- SUPER+SPACE is the us/ara toggle on every shell here, but omarchy binds it to
-- its menu. Both would fire. Free the combo and move the menu onto a Super tap,
-- which is where noctalia's launcher lives too.
hl.unbind("SUPER + SPACE")
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd("omarchy-menu toggle"), { release = true })

-- The way out. omarchy binds SUPER+SHIFT+O to Obsidian (only when its
-- preinstalled-app bindings are on, but unbind is harmless either way).
hl.unbind("SUPER + SHIFT + O")
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))

-- House app binds. SUPER+RETURN already opens a
-- terminal via omarchy-launch-terminal -> xdg-terminal-exec, which resolves to
-- wezterm from the XDG default; SUPER+T is bound below only as the explicit
-- house alias. SUPER+W is unbound from close-window and rebound to zen;
-- SUPER+Q remains the close key.
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.unbind("SUPER + W")
hl.bind("SUPER + W", hl.dsp.exec_cmd(zenBrowser))
hl.bind("SUPER + B", hl.dsp.exec_cmd(browser))
hl.bind("SUPER + E", hl.dsp.exec_cmd(fileExplorer))
hl.bind("CTRL + ALT + B", hl.dsp.exec_cmd("blueman-manager"))

-- Terminal alias. omarchy has SUPER+T on float-toggle, so unbind first.
hl.unbind("SUPER + T")
hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal))
