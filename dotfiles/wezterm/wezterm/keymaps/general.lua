local act = require("wezterm").action

local M = {}

-- Core non-layout actions.
function M.append(keys, wezterm)
	table.insert(keys, { key = "a", mods = "LEADER|CTRL", action = act.SendKey({ key = "a", mods = "CTRL" }) })
	table.insert(keys, { key = "y", mods = "LEADER", action = act.ActivateCopyMode })
	table.insert(keys, { key = ";", mods = "LEADER", action = act.ActivateCommandPalette })
	table.insert(keys, {
		key = "r",
		mods = "LEADER|CTRL",
		action = wezterm.action_callback(function(window, pane)
			window:perform_action(act.ReloadConfiguration, pane)
			window:toast_notification("WezTerm", "Config reloaded", nil, 2000)
		end),
	})
	table.insert(keys, { key = "F", mods = "LEADER|SHIFT", action = act.ToggleFullScreen })
	table.insert(keys, {
		key = "!",
		mods = "LEADER|SHIFT",
		action = wezterm.action_callback(function(_, pane)
			pane:move_to_new_tab()
		end),
	})
end

return M
