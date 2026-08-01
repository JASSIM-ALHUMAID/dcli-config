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
--   <our layer>             monitor, input, unbinds (loaded via dofile)
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

-- ---------------------------------------------------------------------------
-- House layer — modular sub-modules
-- ---------------------------------------------------------------------------
-- Loaded via dofile (not require) to avoid the ~/.config/?.lua path collision
-- described in trap 1. Sub-modules live in shells/omarchy/hyprland/.

local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or (home .. "/.config/hypr/shells/omarchy/")

dofile(script_dir .. "hyprland/monitor.lua")
dofile(script_dir .. "hyprland/input.lua")
dofile(script_dir .. "hyprland/keybinds.lua")

-- Runtime toggle state and workspace layouts. Last, exactly as in omarchy's own
-- config/hypr/hyprland.lua — it re-reads ~/.local/state/omarchy/toggles/hypr.
require("default.hypr.toggles")
