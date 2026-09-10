-- ~/.config/hypr/hyprland.lua
-- Hyprland Lua config entry point — reads active.conf and dispatches

local home = os.getenv("HOME")
local hypr = home .. "/.config/hypr"

local shell_paths = {
    caelestia = home .. "/.local/share/caelestia/hypr/hyprland.lua",
    ambxst    = home .. "/.local/share/ambxst/hyprland.lua",
    dms       = hypr .. "/shells/dms/hyprland.lua",
    noctalia  = hypr .. "/shells/noctalia/hyprland.lua",
    end4      = hypr .. "/shells/end4/hyprland.lua",
    end4pc    = hypr .. "/shells/end4pc/hyprland.lua",
    -- omarchy's own config lives in its checkout, but the file below is a
    -- loader we own that dofile()s it — so it belongs here, not in ~/.local.
    omarchy   = hypr .. "/shells/omarchy/hyprland.lua",
    xenon     = hypr .. "/shells/xenon/hyprland.lua",
}

-- active.conf holds a bare shell name; older versions wrote a
-- "source = ~/.config/hypr/shells/<name>.conf" line, still accepted here.
local function read_active_shell()
    local f = io.open(hypr .. "/shells/active.conf", "r")
    if not f then return "caelestia" end

    local shell
    for line in f:lines() do
        local name = line:match("^%s*(.-)%s*$")
        if name ~= "" and not name:match("^#") then
            name = name:gsub("^source%s*=%s*", ""):gsub("^.-shells/", ""):gsub("%.conf$", ""):gsub("%.lua$", "")
            if shell_paths[name] then
                shell = name
                break
            end
        end
    end
    f:close()

    return shell or "caelestia"
end

local function file_exists(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

local function copy(src, dst)
    local input = io.open(src, "r")
    if not input then return end
    local out = io.open(dst, "w")
    if out then
        out:write(input:read("*a"))
        out:close()
    end
    input:close()
end

-- Shells whose config lives outside ~/.config/hypr can't find their own
-- modules: hyprland only puts the main config's dir on package.path, so a
-- dofile'd config's require("variables") looks in ~/.config/hypr. Append the
-- shell's dir so its modules resolve, but keep it after ~/.config/hypr, which
-- is where the caelestia CLI writes the live scheme/current.lua.
local function add_to_package_path(dir)
    package.path = package.path .. ";" .. dir .. "/?.lua;" .. dir .. "/?/init.lua"
end

-- Colours are require()'d as scheme.current. The caelestia CLI rewrites that
-- file on every scheme change, but it has to exist before the first one.
local function seed_scheme(dir)
    local current = hypr .. "/scheme/current.lua"
    if file_exists(current) then return end

    local default = dir .. "/scheme/default.lua"
    if not file_exists(default) then return end

    os.execute("mkdir -p '" .. hypr .. "/scheme'")
    copy(default, current)
end

-- DCLI_HYPRMOD_SHELL: set by scripts/edit-hypr.sh in hyprmod's environment
-- only, so hyprmod's config reader (which executes this file) evaluates the
-- shell being edited instead of the active one. Hyprland never has it set.
-- Ignored unless it names a known shell.
local edit_shell = os.getenv("DCLI_HYPRMOD_SHELL")
local shell = (edit_shell and shell_paths[edit_shell]) and edit_shell or read_active_shell()
local path = shell_paths[shell]
local dir = path:match("^(.*)/")

add_to_package_path(dir)
seed_scheme(dir)
dofile(path)

-- Local overrides for shells whose config is owned upstream
local overrides = hypr .. "/shells/" .. shell .. "-overrides.lua"
if file_exists(overrides) then dofile(overrides) end

-- HyprMod per-shell managed settings (edited via scripts/edit-hypr.sh, which
-- points hyprmod's config-path at this shell's file). Loaded last so GUI
-- edits override both the shell config and shells/<name>-overrides.lua.
-- require() rather than dofile() so Hyprland's autoreload tracks the file.
local managed = hypr .. "/shells/" .. shell .. "/hyprmod.lua"
if file_exists(managed) then require("shells." .. shell .. ".hyprmod") end
