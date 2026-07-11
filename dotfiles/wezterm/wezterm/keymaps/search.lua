local act = require("wezterm").action

local M = {}

-- Scrollback search and navigation bindings.
function M.append(keys)
	table.insert(keys, { key = "/", mods = "LEADER", action = act.Search("CurrentSelectionOrEmptyString") })
	table.insert(keys, { key = "C", mods = "LEADER|SHIFT", action = act.ClearScrollback("ScrollbackAndViewport") })
	table.insert(keys, { key = "PageUp", mods = "LEADER", action = act.ScrollByPage(-1) })
	table.insert(keys, { key = "PageDown", mods = "LEADER", action = act.ScrollByPage(1) })
end

return M
