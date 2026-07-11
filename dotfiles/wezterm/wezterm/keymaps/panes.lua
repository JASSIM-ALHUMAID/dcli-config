local act = require("wezterm").action

local M = {}

local function split_with_inherited_env(window, pane, wezterm, helpers, constants, direction)
	local cwd_uri = pane:get_current_working_dir()
	local cwd = cwd_uri and cwd_uri.file_path or nil
	local process = pane:get_foreground_process_name()
	local shell = helpers.detect_shell(process)
	local args = helpers.spawn_args(shell, cwd, constants)
	local split_action = direction == "Vertical" and act.SplitVertical or act.SplitHorizontal
	window:perform_action(split_action({ args = args, domain = "CurrentPaneDomain" }), pane)
end

-- Pane movement and resizing bindings.
function M.append(keys, wezterm, constants, helpers)
	table.insert(keys, {
		key = "]",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, pane)
			split_with_inherited_env(window, pane, wezterm, helpers, constants, "Vertical")
		end),
	})
	table.insert(keys, {
		key = "[",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, pane)
			split_with_inherited_env(window, pane, wezterm, helpers, constants, "Horizontal")
		end),
	})
	table.insert(keys, { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") })
	table.insert(keys, { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") })
	table.insert(keys, { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") })
	table.insert(keys, { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") })
	table.insert(keys, { key = "phys:Space", mods = "LEADER", action = act.RotatePanes("Clockwise") })
	table.insert(keys, { key = "z", mods = "LEADER", action = act.TogglePaneZoomState })
	table.insert(keys, {
		key = "x",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, pane)
			window:perform_action(act.SendKey({ key = "c", mods = "CTRL" }), pane)
			wezterm.time.call_after(0.05, function()
				window:perform_action(act.CloseCurrentPane({ confirm = false }), pane)
			end)
		end),
	})
	table.insert(keys, { key = "r", mods = "LEADER", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) })
end

return M
