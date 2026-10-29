-- omarchy house layer — input
-- omarchy's default/hypr/input.lua derives kb_layout from /etc/vconsole.conf
-- and sets kb_options to "compose:caps,shift:both_capslock_cancel", which loses
-- both the Arabic layout and ctrl:nocaps. Re-assert the house settings; hl.config
-- merges, so the touchpad/repeat defaults it set survive.
--
-- dofile, not require: see trap 1 in ../hyprland.lua.

local common = os.getenv("HOME") .. "/.config/hypr/common/"

dofile(common .. "input.lua")
hl.config({ input = { kb_variant = "" } })
dofile(common .. "gestures.lua")
