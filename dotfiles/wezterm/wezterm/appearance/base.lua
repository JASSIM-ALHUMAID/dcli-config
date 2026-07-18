local M = {}

-- General terminal behavior and shared appearance defaults.
function M.apply(config, wezterm, constants)
	config.front_end = "WebGpu"
	config.color_scheme = "Afterglow"
	config.window_background_opacity = 0.8
	config.window_close_confirmation = "NeverPrompt"
	config.quit_when_all_windows_are_closed = true
	config.scrollback_lines = 3000
	config.default_cursor_style = "BlinkingBar"
	config.automatically_reload_config = true
	config.enable_tab_bar = true
	config.use_fancy_tab_bar = false
	config.status_update_interval = 1000
	config.tab_bar_at_bottom = false
	config.inactive_pane_hsb = {
		saturation = 0.24,
		brightness = 0.5,
	}
	config.line_height = 1.1
end

return M
