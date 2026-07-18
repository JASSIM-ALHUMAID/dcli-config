local M = {}

-- Fuzzy cheat sheet for leader-driven workflows.
function M.append(keys, wezterm)
	local act = wezterm.action
	local choices = {
		{ label = "Commands    LEADER m       Command launcher" },
		{ label = "Projects    LEADER P       Project workspace launcher" },
		{ label = "Workspaces  LEADER s       Workspace menu" },
		{ label = "Workspaces  LEADER S       Save current workspace" },
		{ label = "Workspaces  LEADER Q       Save and close workspace" },
		{ label = "Workspaces  LEADER Ctrl+q  Close workspace without saving" },
		{ label = "Workspaces  LEADER D       Delete saved workspace" },
		{ label = "Workspaces  LEADER R       Rename workspace" },
		{ label = "Tabs        LEADER c       New tab" },
		{ label = "Shells      LEADER g       New shell tab" },
		{ label = "Tabs        LEADER w       Tab navigator" },
		{ label = "Tabs        LEADER n/p     Next/previous tab" },
		{ label = "Tabs        LEADER 1-9     Activate tab" },
		{ label = "Tabs        LEADER ,       Rename tab" },
		{ label = "Tabs        LEADER .       Move tab mode" },
		{ label = "Tabs        LEADER t       Toggle bottom tab bar" },
		{ label = "Panes       LEADER [/]     Split pane (right/down)" },
		{ label = "Panes       LEADER h/j/k/l Move between panes" },
		{ label = "Panes       LEADER Space   Rotate panes clockwise" },
		{ label = "Panes       LEADER r       Resize pane mode" },
		{ label = "Panes       LEADER z       Zoom pane" },
		{ label = "Panes       LEADER x       Kill process and close pane" },
		{ label = "Panes       LEADER !       Move pane to new tab" },
		{ label = "General     LEADER ;       Command palette" },
		{ label = "General     LEADER ?       This help" },
		{ label = "General     LEADER Ctrl+r  Reload config" },
		{ label = "General     LEADER Ctrl+a  Send literal Ctrl+a" },
		{ label = "General     LEADER y       Copy mode" },
		{ label = "Search      LEADER /       Search scrollback" },
		{ label = "Search      LEADER C       Clear scrollback" },
		{ label = "Search      LEADER PgUp/PgDn Scroll pages" },
		{ label = "General     LEADER F       Fullscreen" },
	}

	table.insert(keys, {
		key = "?",
		mods = "LEADER|SHIFT",
		action = act.InputSelector({
			title = "Leader help",
			description = "Search available leader shortcuts",
			fuzzy_description = "Shortcut: ",
			fuzzy = true,
			choices = choices,
			action = wezterm.action_callback(function() end),
		}),
	})
end

return M
