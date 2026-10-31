-- ryoku window borders, from the wallpaper palette.
--
-- The ryoku daemon's matugen pass writes ~/.cache/ryoku/hypr-colors.lua
-- (`return { active = "#rrggbb", inactive = "#rrggbb" }`) on every wallpaper
-- change; upstream's decoration.lua reads it the same way. Upstream also pushes
-- the colours live through its ryoku-wm-hyprland provider, which is not
-- installed here (it re-authors ~/.config/hypr), so a new palette reaches the
-- borders on the next config parse — login, shell switch or `hyprctl reload`.
-- Absent or malformed file: the house defaults stay.
local ok, palette = pcall(dofile, os.getenv("HOME") .. "/.cache/ryoku/hypr-colors.lua")
if not ok or type(palette) ~= "table" then
    return
end

local function rgb(hex)
    if type(hex) ~= "string" or not hex:match("^#%x%x%x%x%x%x$") then
        return nil
    end
    return "rgb(" .. hex:sub(2) .. ")"
end

local active, inactive = rgb(palette.active), rgb(palette.inactive)
if active and inactive then
    hl.config({
        general = {
            col = {
                active_border   = active,
                inactive_border = inactive,
            },
        },
    })
end
