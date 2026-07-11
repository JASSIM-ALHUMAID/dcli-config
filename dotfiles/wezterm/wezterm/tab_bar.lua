local M = {}

local state = {}

local function get_tab_count(window)
	local mux_window = window:mux_window()
	if not mux_window then
		return 1
	end
	local tabs = mux_window:tabs()
	return tabs and #tabs or 1
end

local function get_state(window_id)
	if not state[window_id] then
		state[window_id] = { manual_override = nil, last_tab_count = nil }
	end
	return state[window_id]
end

local function compute_effective(s, tab_count)
	if s.manual_override ~= nil then
		return s.manual_override
	end
	return tab_count > 1
end

local function apply(window, effective)
	window:set_config_overrides({ enable_tab_bar = effective })
end

function M.update(window)
	local window_id = window:window_id()
	local s = get_state(window_id)
	local tab_count = get_tab_count(window)

	if s.last_tab_count ~= nil and s.last_tab_count ~= tab_count then
		s.manual_override = nil
	end
	s.last_tab_count = tab_count

	apply(window, compute_effective(s, tab_count))
end

function M.toggle(window)
	local window_id = window:window_id()
	local s = get_state(window_id)
	local tab_count = get_tab_count(window)
	s.last_tab_count = tab_count
	s.manual_override = not compute_effective(s, tab_count)
	apply(window, s.manual_override)
end

return M
