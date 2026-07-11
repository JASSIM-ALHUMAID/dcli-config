local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- Shared helper functions.
function M.config_builder()
	return wezterm.config_builder and wezterm.config_builder() or {}
end

function M.send_line(text)
	return act.SendString(text .. "\r")
end

function M.quick_cd(path)
	return M.send_line('cd "' .. path .. '"')
end

function M.shell_quote_pwsh(arg)
	arg = tostring(arg or ""):gsub("'", "''")
	return "'" .. arg .. "'"
end

function M.basename(path)
	return (tostring(path or ""):gsub("[\\/]+$", ""):match("([^\\/]+)$")) or ""
end

-- Single-quote wrapper safe for the path shapes we handle.
function M.squote(s)
	return "'" .. tostring(s) .. "'"
end

-- Normalize a cwd from various shapes to "C:/foo/bar".
-- Accepts "/C:/foo", "/c/foo", "C:/foo", "C:\foo".
function M.normalize_cwd(path)
	path = tostring(path or ""):gsub("\\", "/")
	path = path:gsub("^/(%a:/)", "%1")
	path = path:gsub("^/(%a)/", function(d)
		return d:upper() .. ":/"
	end)
	return path
end

-- Convert "C:/foo" to msys POSIX form "/c/foo" for fish.
function M.to_msys_path(path)
	path = tostring(path or ""):gsub("\\", "/")
	return path:gsub("^(%a):/(.*)", function(drive, rest)
		return "/" .. drive:lower() .. "/" .. rest
	end)
end

local SHELL_NAMES = {
	fish = "fish", pwsh = "pwsh", powershell = "pwsh",
	bash = "bash", zsh = "zsh", sh = "sh",
}

-- Detect the shell name from a foreground process path.
-- Returns "fish", "pwsh", "bash", "zsh", "sh", or nil.
function M.detect_shell(process_path)
	if not process_path then
		return nil
	end
	local base = (process_path:gsub("\\", "/"):match("([^/]+)$") or process_path):gsub("%.exe$", ""):lower()
	return SHELL_NAMES[base]
end

-- Build spawn args for a new pane/tab: an interactive shell that starts in
-- the given cwd.  shell can be "fish", "pwsh", or nil (use default_prog).
-- Passes cwd via a startup --command / -C flag because WezTerm's mux APIS
-- ignore the `cwd` spawn parameter on Windows.
function M.win_spawn_args(shell, cwd, default_prog)
	if cwd and cwd ~= "" then
		local norm = M.normalize_cwd(cwd)
		if shell == "fish" then
			return { "C:\\msys64\\usr\\bin\\fish.exe", "-i", "-C", "cd " .. M.squote(M.to_msys_path(norm)) }
		end
		if shell == "pwsh" then
			return { "pwsh.exe", "-NoLogo", "-NoExit", "-Command", "Set-Location " .. M.squote(norm) }
		end
		-- Non-shell process (opencode, nvim, etc.): detect the default
		-- shell from default_prog and recurse so cwd gets injected
		-- correctly for whatever the default shell is.
		local default = default_prog or M.win_fish_prog()
		return M.win_spawn_args(M.detect_shell(default[1]), cwd, default_prog)
	end
	if shell == "fish" then
		return M.win_fish_prog()
	end
	if shell == "pwsh" then
		return M.win_pwsh_prog()
	end
	return default_prog or M.win_fish_prog()
end

-- Cross-platform spawn args. Uses Windows-specific paths on Windows,
-- the user's SHELL on Linux/macOS.
function M.spawn_args(shell, cwd, constants)
	if constants.is_windows then
		return M.win_spawn_args(shell, cwd, M.get_default_prog(constants))
	end
	local sh = os.getenv("SHELL") or (constants.is_darwin and "/bin/zsh" or "/bin/bash")
	if cwd and cwd ~= "" then
		return { sh, "-l", "-c", "cd " .. M.squote(cwd) .. " && exec " .. sh }
	end
	return { sh, "-l" }
end

-- Windows shells. Fish ships with MSYS2; spawn its exe directly so it inherits
-- the terminal's full Windows PATH (scoop/winget/Program Files tools). NOTE: no
-- `-l` (login) flag on purpose -- msys2's /etc/fish/config.fish sources
-- msys2.fish for login shells, which rebuilds PATH down to msys-only dirs and
-- hides every Windows-side tool (fastfetch, starship, lazygit, ...).
function M.win_fish_prog()
	return { "C:\\msys64\\usr\\bin\\fish.exe", "-i" }
end

function M.win_pwsh_prog()
	return { "pwsh.exe", "-NoLogo" }
end

function M.get_default_prog(constants)
	if constants.is_windows then
		-- Fish is the default shell. Fastfetch was the source of intermittent
		-- first-pane hangs under ConPTY (terminal probes on /dev/tty), so it
		-- is no longer called from fish_greeting; run it manually if wanted.
		return M.win_fish_prog()
	end

	if constants.is_linux then
		return { os.getenv("SHELL") or "/bin/bash", "-l" }
	end

	if constants.is_darwin then
		return { os.getenv("SHELL") or "/bin/zsh", "-l" }
	end

	return { "/bin/sh" }
end

-- New-tab dropdown / command-palette shell entries (Windows only).
function M.build_launch_menu(constants)
	if not constants.is_windows then
		return {}
	end
	return {
		{ label = "fish (UCRT64)", args = M.win_fish_prog() },
		{ label = "PowerShell", args = M.win_pwsh_prog() },
	}
end

return M
