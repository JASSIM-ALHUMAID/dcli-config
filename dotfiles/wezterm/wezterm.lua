local wezterm = require("wezterm")

-- Main WezTerm entrypoint.
package.path = table.concat({
	wezterm.config_dir .. "/?.lua",
	wezterm.config_dir .. "/?/init.lua",
	package.path,
}, ";")

local constants = require("wezterm.constants")
local helpers = require("wezterm.helpers")
local workspaces = require("wezterm.workspaces")

local config = helpers.config_builder()

require("wezterm.appearance").apply(config, wezterm, constants)
require("wezterm.keymaps").apply(config, wezterm, workspaces, constants, helpers)
require("wezterm.events").register(wezterm, workspaces, constants)

config.default_prog = helpers.get_default_prog(constants)
config.launch_menu = helpers.build_launch_menu(constants)
config.default_workspace = constants.DEFAULT_WORKSPACE

return config
