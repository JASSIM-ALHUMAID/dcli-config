local wezterm = require("wezterm")

local constants = require("wezterm.constants")
local helpers = require("wezterm.helpers")

local M = {}
local ctx = {
	wezterm = wezterm,
	act = wezterm.action,
	constants = constants,
	helpers = helpers,
	state = {
		workspace_order = { constants.DEFAULT_WORKSPACE },
	},
}

-- Compose workspace behavior from smaller modules.
require("wezterm.workspaces.order").attach(M, ctx)
require("wezterm.workspaces.navigation").attach(M, ctx)
require("wezterm.workspaces.prompts").attach(M, ctx)
require("wezterm.workspaces.persistence").attach(M, ctx)

return M
