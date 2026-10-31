-- ~/.config/hypr/shells/glyph/hyprland.lua
-- glyph-rice (Nebelung-cloud/glyph-rice) — loader for the checkout's config.
--
-- WHY A LOADER: glyph's hyprland.lua requires its own modules by BARE name
-- (`hyprland.env`, `variables`, `scheme.demonshot`). The entry point appends the
-- registry config's directory after ~/.config/hypr, and ~/.config/hypr/hyprland/
-- is a real directory other configurators write into — a short name can resolve
-- there and silently load someone else's file. Prepending the checkout makes
-- glyph's modules win, while the house `common.*` layer still resolves because
-- glyph has no files by those names.
--
-- Everything below the loader is upstream-owned: variables.lua (apps, gaps,
-- blur, keymap), scheme/demonshot.lua (colours) and hyprland/*.lua (rules,
-- anims, binds). Edit binds in the checkout's gitignored config/hypr/user.lua,
-- which upstream loads last; this file only adds the house escape hatch.

local home = os.getenv("HOME")
local glyph_dir = home .. "/.local/share/glyph-rice/config/hypr"

-- A missing checkout must not take the session down with a raw Lua error:
-- Hyprland would drop the whole config and leave the desktop with no binds.
local probe = io.open(glyph_dir .. "/hyprland.lua", "r")
if not probe then
    io.stderr:write("shells/glyph/hyprland.lua: glyph-rice not found at " .. glyph_dir
        .. " — run: dcli module run-hook shell-glyph\n")
    return
end
probe:close()

package.path = glyph_dir .. "/?.lua;" .. glyph_dir .. "/?/init.lua;" .. package.path

dofile(glyph_dir .. "/hyprland.lua")

-- The one bind every shell here shares. glyph does not use SUPER+SHIFT+O, but
-- unbind first per the house rule (a rebind of a live combo stacks handlers).
hl.unbind("SUPER + SHIFT + O")
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(home .. "/.config/dcli/scripts/switch-shell.sh"))

-- House monitor and input win over glyph's own (highres/auto scale, us,ru with
-- alt+shift): scale stays 1 and the layout toggle is Super+Space, caps = ctrl.
-- hl.config merges, so glyph's other input keys (touchpad, repeat) survive.
require("common.monitor")
require("common.input")
