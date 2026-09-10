-- House overrides for end4 keybinds
-- Adds the switch-shell bind

hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))

-- House overrides: wallpaper + workspace navigation
-- Unbind conflicting upstream binds first so the combos below win.
local qsScripts = "$HOME/.config/quickshell/$qsConfig/scripts"
local qsIpcCall = "qs -c $qsConfig ipc call"
local qsIsAlive = qsIpcCall .. " TEST_ALIVE"

-- SUPER+SHIFT+W: wallpaper selector (upstream uses CTRL+SUPER+T; SUPER+W is browser)
hl.unbind("SUPER + SHIFT + W")
hl.bind("SUPER + SHIFT + W", hl.dsp.global("quickshell:wallpaperSelectorToggle"),
    { description = "Shell: Change wallpaper" })
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd(qsIsAlive .. " || " .. qsScripts .. "/colors/switchwall.sh"))

-- SUPER+Tab / SUPER+SHIFT+Tab: next/prev workspace WITH window (move + follow)
-- Upstream SUPER+Tab is overview toggle.
hl.unbind("SUPER + Tab")
hl.unbind("SUPER + SHIFT + Tab")
hl.bind("SUPER + Tab", hl.dsp.window.move({ workspace = "r+1", follow = true }),
    { description = "Workspace: Next with window" })
hl.bind("SUPER + SHIFT + Tab", hl.dsp.window.move({ workspace = "r-1", follow = true }),
    { description = "Workspace: Prev with window" })

-- SUPER+X / SUPER+Z: next/prev workspace focus only (upstream SUPER+X is text editor)
hl.unbind("SUPER + X")
hl.unbind("SUPER + Z")
hl.bind("SUPER + X", hl.dsp.focus({ workspace = "r+1" }),
    { description = "Workspace: Focus next" })
hl.bind("SUPER + Z", hl.dsp.focus({ workspace = "r-1" }),
    { description = "Workspace: Focus prev" })
