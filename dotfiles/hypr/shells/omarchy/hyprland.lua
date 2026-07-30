-- ~/.config/hypr/shells/omarchy/hyprland.lua
-- omarchy — Hyprland Lua config
--
-- Unlike dms/noctalia/end4/end4pc, this file is a LOADER, not a standalone
-- config: omarchy ships a complete Lua Hyprland config and we run it, then
-- layer the house preferences on top. Same idea as caelestia and ambxst, except
-- those two load a file inside their own checkout and get their tweaks from
-- shells/<name>-overrides.lua — here the file the entry point loads is already
-- ours, so there is no separate omarchy-overrides.lua.
--
-- Loading order mirrors omarchy's own config/hypr/hyprland.lua:
--   bootstrap.lua           sets package.path for the three module roots
--   default.hypr.omarchy    helpers, autostart, bindings, envs, looknfeel,
--                           input, windows, and the current theme's colours
--   <our layer>             the four things below
--   default.hypr.toggles    runtime toggle state, must come last
--
-- TRAPS
--
-- 1. bootstrap.lua puts ~/.config/?.lua on package.path, so a require("hypr.x")
--    from anywhere in omarchy resolves into ~/.config/hypr — this repo's SHARED
--    hypr directory, used by all seven shells. Never `require` our own code from
--    here (use dofile), and never create dotfiles/hypr/{monitors,input,bindings,
--    looknfeel,autostart}.lua: those are the names omarchy's user config uses
--    and they would silently start loading for every shell.
--
-- 2. Two binds on one combo BOTH fire. omarchy binds nearly every SUPER combo,
--    so anything added below must either use a key omarchy leaves free or
--    hl.unbind() first. `hyprctl binds -j | jq 'group_by([.modmask,.key,.release])'`
--    is the check.
--
-- 3. This config must NOT trust $OMARCHY_PATH from the environment — neither
--    that it is set, nor that it is right. os.getenv() here runs at config-PARSE
--    time, and two separate consumers read it, only one of which fails loudly:
--
--      bootstrap.lua  builds package.path from it  -> "module
--                     default.hypr.omarchy not found", config dies, so none of
--                     the binds below register either.
--      paths.lua      exports it as paths.omarchy_path, which bindings.lua and
--                     apps.lua hand to require_all.files() -> that runs
--                     `find <dir>`, which finds nothing on a bad path and
--                     returns SILENTLY. Zero keybinds, no error anywhere.
--
--    Both are therefore resolved here and injected, never read downstream.
--
--    A WRONG value is worse than a missing one, because it beats the fallback.
--    That is not hypothetical: a previous dotfiles/environment.d/60-omarchy.conf
--    (since deleted) wrote `OMARCHY_PATH=%h/.local/share/omarchy`, and
--    environment.d does not expand %h — that is a systemd unit-file specifier,
--    and environment.d(5) supports "no other elements of shell syntax". The
--    literal "%h/..." then took precedence over the correct default and the
--    desktop came up with 3 binds instead of 216. Hence has_bootstrap(): probe
--    for the file, do not believe the variable.

local home = os.getenv("HOME")

local function has_bootstrap(dir)
    if not dir or dir == "" then return false end
    local f = io.open(dir .. "/default/hypr/bootstrap.lua", "r")
    if not f then return false end
    f:close()
    return true
end

local env_path = os.getenv("OMARCHY_PATH")
local omarchy = has_bootstrap(env_path) and env_path or (home .. "/.local/share/omarchy")

-- Fail loudly rather than half-loading. Without this, a missing checkout yields
-- a desktop that looks up but has almost no keybinds — the hardest kind of
-- breakage to notice. An error at least lands in `hyprctl configerrors`.
if not has_bootstrap(omarchy) then
    error("omarchy checkout not found at " .. omarchy ..
        " — run scripts/setup-omarchy.sh")
end

dofile(omarchy .. "/default/hypr/bootstrap.lua")

-- Repair what bootstrap.lua just derived from the env var: it applies its own
-- /usr/share/omarchy fallback independently of the resolution above.
-- Prepending is enough — package.path is searched in order, so our entry wins.
package.path = omarchy .. "/?.lua;" .. package.path

-- Replace default.hypr.paths before anything requires it, so every consumer of
-- paths.omarchy_path gets the checkout. This has to come AFTER the dofile above:
-- bootstrap.lua clears package.loaded for the "default.hypr" prefix on reload,
-- which would otherwise wipe this. Mirrors upstream's paths.lua field for field.
package.loaded["default.hypr.paths"] = {
    home        = home,
    config_home = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config"),
    state_home  = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state"),
    omarchy_path = omarchy,
}

require("default.hypr.omarchy")

-- With paths fixed, omarchy's own default/hypr/envs.lua has already done
-- hl.env("OMARCHY_PATH", ...) and put its bin/ at the front of PATH for every
-- client Hyprland spawns. environment.d is still worth having — it covers
-- terminals and anything else outside the compositor — but the shell no longer
-- depends on it, so a relogin is not required to switch here.

-- ---------------------------------------------------------------------------
-- House layer
-- ---------------------------------------------------------------------------
--
-- Deliberately small. This shell KEEPS omarchy's keymap — that is the reason to
-- load its config at all — so the only binds touched are the two that would
-- otherwise make the machine unusable: the Arabic layout toggle and the way out
-- of this shell. Everything else omarchy binds stays omarchy's.
-- See docs/shells/omarchy.md for the resulting differences from the other six.

local terminal     = "wezterm-gui"
local browser      = "brave-browser-nightly"
local fileExplorer = "thunar"

-- Monitor: omarchy leaves this to the user's hypr/monitors.lua, which we do not
-- load (see trap 1). Same default as the other shells.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Input. omarchy's default/hypr/input.lua derives kb_layout from
-- /etc/vconsole.conf and sets kb_options to "compose:caps,shift:both_capslock",
-- which loses both the Arabic layout and ctrl:nocaps. Re-assert the house
-- settings; hl.config merges, so the touchpad/repeat defaults it set survive.
hl.config({
    input = {
        kb_layout     = "us,ara",
        kb_variant    = "",
        kb_options    = "grp:win_space_toggle, ctrl:nocaps",
        sensitivity   = 0.3,
        accel_profile = "flat",
    },
})

-- SUPER+SPACE is the us/ara toggle on every shell here, but omarchy binds it to
-- its menu. Both would fire. Free the combo and move the menu onto a Super tap,
-- which is where noctalia's launcher lives too.
hl.unbind("SUPER + SPACE")
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd("omarchy-menu toggle"), { release = true })

-- The way out. omarchy binds SUPER+SHIFT+O to Obsidian (only when its
-- preinstalled-app bindings are on, but unbind is harmless either way).
hl.unbind("SUPER + SHIFT + O")
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(home .. "/.config/dcli/scripts/switch-shell.sh"))

-- House app binds on combos omarchy leaves free. SUPER+RETURN already opens a
-- terminal via omarchy-launch-terminal -> xdg-terminal-exec, which resolves to
-- wezterm from the XDG default; SUPER+T is bound below only as the explicit
-- house alias. SUPER+W is NOT rebound to the browser here — omarchy uses it to
-- close windows, and SUPER+Q is added as the house-style close instead.
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + B", hl.dsp.exec_cmd(browser))
hl.bind("SUPER + E", hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + R", hl.dsp.exec_cmd(fileExplorer))
hl.bind("CTRL + ALT + B", hl.dsp.exec_cmd("blueman-manager"))

-- Terminal alias. omarchy has SUPER+T on float-toggle, so unbind first.
hl.unbind("SUPER + T")
hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal))

-- Runtime toggle state and workspace layouts. Last, exactly as in omarchy's own
-- config/hypr/hyprland.lua — it re-reads ~/.local/state/omarchy/toggles/hypr.
require("default.hypr.toggles")
