-- Hyprland >= 0.51 has no default workspace swipe: it must be declared.
-- Tuning (distance, cancel ratio, invert, ...) lives in gestures:* options,
-- editable from HyprMod's Gestures page.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
