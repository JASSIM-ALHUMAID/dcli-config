-- ~/.config/hypr/hyprland.lua
-- Hyprland Lua config entry point — reads active.conf and dispatches

local home = os.getenv("HOME")
local hypr = home .. "/.config/hypr"

-- ── shell registry ──

-- shells/registry is the one list of shells (name|config|icon|blurb); this file
-- needs only the first two fields. A "~/"-prefixed config is $HOME-relative,
-- anything else is relative to ~/.config/hypr.
local REGISTRY_PATH = hypr .. "/shells/registry"
local FALLBACK_SHELL = "caelestia"
local FALLBACK_CONFIG = home .. "/.local/share/caelestia/hypr/hyprland.lua"

local function load_registry()
    local paths = {}
    local f = io.open(REGISTRY_PATH, "r")
    if not f then
        io.stderr:write("hyprland.lua: cannot read " .. REGISTRY_PATH .. "\n")
        return paths
    end

    for line in f:lines() do
        local record = line:match("^%s*(.-)%s*$")
        if record ~= "" and not record:match("^#") then
            local name, config = record:match("^([^|]+)|([^|]+)")
            if name and config then
                if config:match("^~/") then
                    paths[name] = home .. config:sub(2)
                else
                    paths[name] = hypr .. "/" .. config
                end
            else
                io.stderr:write("hyprland.lua: malformed registry line: " .. record .. "\n")
            end
        end
    end
    f:close()

    return paths
end

-- Without a usable registry the session still gets a config: caelestia's.
local shell_paths = load_registry()
if next(shell_paths) == nil then
    io.stderr:write("hyprland.lua: no shells registered, falling back to " .. FALLBACK_SHELL .. "\n")
    shell_paths[FALLBACK_SHELL] = FALLBACK_CONFIG
end

-- ── active shell ──

-- active.conf holds a bare shell name; older versions wrote a
-- "source = ~/.config/hypr/shells/<name>.conf" line, still accepted here.
-- Cross-reference: the bash side is the dcli repo's scripts/lib/shell-common.sh,
-- which reads the same shells/registry and parses active.conf — keep the
-- accepted forms in sync there.
local function read_active_shell()
    local f = io.open(hypr .. "/shells/active.conf", "r")
    if not f then return FALLBACK_SHELL end

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

    return shell or FALLBACK_SHELL
end

-- ── file helpers ──

local function file_exists(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

-- Failures go to stderr — Hyprland surfaces config stderr on reload — rather
-- than failing silently and leaving the shell colorless with zero diagnostics.
local function copy(src, dst)
    local input = io.open(src, "r")
    if not input then
        io.stderr:write("hyprland.lua: copy: cannot read " .. src .. "\n")
        return
    end
    local out = io.open(dst, "w")
    if not out then
        io.stderr:write("hyprland.lua: copy: cannot write " .. dst .. "\n")
        input:close()
        return
    end
    out:write(input:read("*a"))
    out:close()
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

-- ── dispatch ──

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
local overrides = hypr .. "/shells/" .. shell .. "/overrides.lua"
if file_exists(overrides) then dofile(overrides) end

-- HyprMod per-shell managed settings (edited via scripts/edit-hypr.sh, which
-- points hyprmod's config-path at this shell's file). Loaded last so GUI
-- edits override both the shell config and shells/<name>/overrides.lua.
-- require() rather than dofile() so Hyprland's autoreload tracks the file.
local managed = hypr .. "/shells/" .. shell .. "/hyprmod.lua"
if file_exists(managed) then require("shells." .. shell .. ".hyprmod") end

-- ── boot into a chosen shell ──

-- GRUB's "Shells" submenu boots with dcli.shell=<name>; boot-shell.sh turns
-- that into a switch-shell.sh call, once per boot. hyprland.start fires at
-- compositor start only, never on `hyprctl reload`, so a shell switch (a
-- reload) cannot re-run it; the script also records the boot id it consumed.
hl.on("hyprland.start", function()
    hl.exec_cmd(home .. "/.config/dcli/scripts/boot-shell.sh")
end)
