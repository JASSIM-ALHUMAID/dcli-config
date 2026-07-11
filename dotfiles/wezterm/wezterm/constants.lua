local wezterm = require("wezterm")
local target = wezterm.target_triple
local theme = require("wezterm.theme")

-- Environment and shared constants.
local HOME = os.getenv("USERPROFILE") or os.getenv("HOME") or ""
local APPDATA = os.getenv("APPDATA") or (HOME .. "\\AppData\\Roaming")
local CONFIG_DIR = wezterm.config_dir

return {
	DEFAULT_WORKSPACE = "main",
	HOME = HOME,
	APPDATA = APPDATA,
	CONFIG_DIR = CONFIG_DIR,
	is_windows = target:find("windows") ~= nil,
	is_linux = target:find("linux") ~= nil,
	is_darwin = target:find("darwin") ~= nil,
	-- All themed colors live in theme.lua (generated from theme.lua.template
	-- by ~/.config/yasb/colorScheme.ps1). Re-exported here for convenience.
	theme = theme,
	custom_colors = theme.custom_colors,
	status_colors = theme.status,
}
