local tab_bar = require("wezterm.tab_bar")

local M = {}

function M.append(keys, wezterm)
	-- Toggle tab bar visibility (LEADER+t)
	table.insert(keys, {
		key = "t",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, _)
			tab_bar.toggle(window)
		end),
	})
end

return M
