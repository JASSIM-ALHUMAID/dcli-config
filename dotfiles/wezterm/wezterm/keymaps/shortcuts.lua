local act = require("wezterm").action

local M = {}

-- Quick directory and app shortcuts.
function M.append(keys, constants, helpers)
	-- Shell launchers: fish/pwsh on Windows, system SHELL on Linux/macOS.
	if constants.is_windows then
		table.insert(keys, {
			key = "g",
			mods = "LEADER",
			action = act.SpawnCommandInNewTab({ args = helpers.win_fish_prog() }),
		})
		table.insert(keys, {
			key = "G",
			mods = "LEADER|SHIFT",
			action = act.SpawnCommandInNewTab({ args = helpers.win_pwsh_prog() }),
		})
	else
		local sh = os.getenv("SHELL") or (constants.is_darwin and "/bin/zsh" or "/bin/bash")
		table.insert(keys, {
			key = "g",
			mods = "LEADER",
			action = act.SpawnCommandInNewTab({ args = { sh, "-l" } }),
		})
	end
end

return M
