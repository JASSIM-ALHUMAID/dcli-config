local Module = {}

-- Save and restore workspace sessions (tabs + panes + working dirs) to disk.
function Module.attach(M, ctx)
	local wezterm = ctx.wezterm
	local constants = ctx.constants

	local STATE_DIR = wezterm.config_dir .. "/state/workspaces"

	-- Map an arbitrary workspace name to a safe filename stem.
	local function sanitize(name)
		local s = tostring(name or ""):lower():gsub("[^%w%-_]+", "-"):gsub("%-+", "-")
		return (s:gsub("^%-", ""):gsub("%-$", ""))
	end

	local function state_path(name)
		local stem = sanitize(name)
		if stem == "" then
			return nil
		end
		return STATE_DIR .. "/" .. stem .. ".json"
	end

	-- Make a path WezTerm's spawn cwd accepts on both Windows and POSIX.
	-- get_current_working_dir() yields several Windows shapes depending on
	-- which shell emitted OSC 7: "/C:/Users/..." from pwsh, "/c/Users/..."
	-- from msys2 fish/bash. Both must collapse to "C:/Users/...".
	local function normalize_cwd(path)
		path = tostring(path or ""):gsub("\\", "/")
		-- "/C:/foo" -> "C:/foo"
		path = path:gsub("^/(%a:/)", "%1")
		-- "/c/foo" (msys POSIX form) -> "C:/foo"
		path = path:gsub("^/(%a)/", function(d)
			return d:upper() .. ":/"
		end)
		return path
	end

	-- Convert "C:/foo" to msys POSIX form "/c/foo" for fish.
	local function to_msys_path(path)
		path = tostring(path or ""):gsub("\\", "/")
		return path:gsub("^(%a):/(.*)", function(drive, rest)
			return "/" .. drive:lower() .. "/" .. rest
		end)
	end

	local function ensure_state_dir()
		if constants.is_windows then
			pcall(os.execute, 'mkdir "' .. STATE_DIR:gsub("/", "\\") .. '"')
		else
			pcall(os.execute, 'mkdir -p "' .. STATE_DIR .. '"')
		end
	end

	local function read_file(path)
		local f = io.open(path, "r")
		if not f then
			return nil
		end
		local data = f:read("*a")
		f:close()
		return data
	end

	local function write_file(path, data)
		local f = io.open(path, "w")
		if not f then
			ensure_state_dir()
			f = io.open(path, "w")
		end
		if not f then
			return false
		end
		f:write(data)
		f:close()
		return true
	end

	local function pane_cwd(pane)
		local ok, uri = pcall(function()
			return pane:get_current_working_dir()
		end)
		if not ok or not uri then
			return nil
		end
		-- Newer WezTerm returns a Url object; older returns a string.
		local raw = type(uri) == "string" and uri or uri.file_path
		if not raw or raw == "" then
			return nil
		end
		return normalize_cwd(raw)
	end

	-- TUI programs worth relaunching on restore. Anything else (notably the
	-- shell itself at a prompt) is treated as "no program".
	local ALLOWED_PROGRAMS = {
		nvim = true,
		vim = true,
		helix = true,
		hx = true,
		yazi = true,
		ranger = true,
		lf = true,
		nnn = true,
		btop = true,
		btop4win = true,
		htop = true,
		top = true,
		btm = true,
		bottom = true,
		lazygit = true,
		gitui = true,
		tig = true,
		lazydocker = true,
		k9s = true,
		ncdu = true,
		claude = true,
		opencode = true,
	}

	-- The last command the shell ran in this pane, published as a WezTerm user
	-- var by the shell-integration snippet (pwsh, zsh, bash, fish). Returns the
	-- trimmed command string, or nil when none was recorded.
	local function pane_last_command(pane)
		local ok, vars = pcall(function()
			return pane:get_user_vars()
		end)
		if not ok or type(vars) ~= "table" then
			return nil
		end
		local cmd = vars.WEZTERM_LAST_CMD
		if type(cmd) ~= "string" then
			return nil
		end
		cmd = cmd:gsub("%s+$", "")
		if cmd == "" then
			return nil
		end
		return cmd
	end

	-- The full executable path of an allowlisted foreground program, else nil.
	-- We store the absolute path (like cwd) so it relaunches reliably on this
	-- machine even when the program isn't on PATH.
	local function pane_program(pane)
		local ok, name = pcall(function()
			return pane:get_foreground_process_name()
		end)
		if not ok or type(name) ~= "string" or name == "" then
			return nil
		end
		local normalized = name:gsub("\\", "/")
		local base = (normalized:match("([^/]+)$") or normalized):gsub("%.exe$", ""):lower()
		if ALLOWED_PROGRAMS[base] then
			return normalized
		end
		return nil
	end

	-- Shells we know how to relaunch. Detection is best-effort: we can only
	-- read the foreground process, so panes currently running a TUI return
	-- nil and inherit the workspace-level shell at restore time.
	local KNOWN_SHELLS = {
		pwsh = "pwsh",
		powershell = "pwsh",
		fish = "fish",
		bash = "bash",
		zsh = "zsh",
	}

	local function pane_shell(pane)
		local ok, name = pcall(function()
			return pane:get_foreground_process_name()
		end)
		if not ok or type(name) ~= "string" or name == "" then
			return nil
		end
		local base = (name:gsub("\\", "/"):match("([^/]+)$") or name):gsub("%.exe$", ""):lower()
		return KNOWN_SHELLS[base]
	end

	-- Logical shell name -> base spawn args (interactive shell, no program).
	-- Returns nil to mean "use WezTerm's default_prog".
	local function shell_prog(name)
		if not name then
			return nil
		end
		if constants.is_windows then
			if name == "fish" then
				return ctx.helpers.win_fish_prog()
			end
			if name == "pwsh" then
				return ctx.helpers.win_pwsh_prog()
			end
		end
		local unix_shells = { bash = true, zsh = true, sh = true }
		if unix_shells[name] then
			local sh = os.getenv("SHELL") or (constants.is_darwin and "/bin/zsh" or "/bin/bash")
			return { sh, "-l" }
		end
		return nil
	end

	-- Single-quote a string for fish, escaping any embedded single quotes
	-- using the standard `'\''` close/escape/reopen trick.
	local function fish_squote(s)
		return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
	end

	-- Build a startup cd command for the given shell and normalized path.
	-- Returns empty string when cwd is nil (no cd injected).
	-- On Windows: uses Set-Location (PowerShell) for non-fish shells.
	-- On Linux/macOS: always uses cd.
	local function shell_cd_cmd(cwd, shell)
		if not cwd then
			return ""
		end
		if shell == "fish" then
			return "cd " .. fish_squote(to_msys_path(cwd))
		end
		if constants.is_windows then
			return "Set-Location " .. fish_squote(cwd)
		end
		return "cd " .. fish_squote(cwd)
	end

	-- Build spawn args for a pane. `prog` is an allowlisted TUI to relaunch
	-- (nil for a plain shell pane). `shell` is the logical shell name to use
	-- (nil means default_prog). `cwd` is the directory to cd into at startup
	-- (nil means skip cd). When both prog and cwd are present, the program
	-- runs *inside* the recorded shell which cds first, so the pane drops
	-- back to a shell prompt in the right directory when the program exits.
	-- WezTerm's mux APIs (spawn_tab, pane:split) ignore the `cwd` parameter
	-- on this WezTerm version/Windows, so we inject it as a startup command.
	local function spawn_args(prog, shell, cwd)
		local cd = shell_cd_cmd(cwd, shell)

		if not prog then
			local base = shell_prog(shell)
			if not base then
				return nil
			end
			if cd ~= "" then
				local args = {}
				for _, v in ipairs(base) do
					table.insert(args, v)
				end
				if shell == "fish" then
					table.insert(args, "-C")
					table.insert(args, cd)
				elseif shell == "pwsh" then
					return { "pwsh.exe", "-NoLogo", "-NoExit", "-Command", cd }
				else
					-- Unix: inject cd via -c, then exec the shell
					return { base[1], "-c", cd .. " && exec " .. table.concat(base, " ") }
				end
				return args
			end
			return base
		end

		if constants.is_windows then
			local s = shell or "pwsh"
			if s == "fish" then
				local base = ctx.helpers.win_fish_prog()
				local args = {}
				for _, v in ipairs(base) do
					table.insert(args, v)
				end
				table.insert(args, "-C")
				local cmd = cd ~= "" and cd .. " ; " .. fish_squote(prog) or fish_squote(prog)
				table.insert(args, cmd)
				return args
			end
			local cmd = cd ~= "" and cd .. " ; & " .. fish_squote(prog) or "& " .. fish_squote(prog)
			return { "pwsh.exe", "-NoLogo", "-NoExit", "-Command", cmd }
		end

		local sh = os.getenv("SHELL") or "/bin/bash"
		local cmd = cd ~= "" and cd .. " ; " .. fish_squote(prog) .. " ; exec " .. fish_squote(sh) or fish_squote(prog) .. " ; exec " .. fish_squote(sh)
		return { sh, "-c", cmd }
	end

	-- Find the first mux window bound to the given workspace.
	local function mux_window_for(name)
		for _, mux_win in ipairs(wezterm.mux.all_windows()) do
			if mux_win:get_workspace() == name then
				return mux_win
			end
		end
		return nil
	end

	local function serialize_window(mux_win, name)
		local data = { name = name, tabs = {} }
		for _, tab in ipairs(mux_win:tabs()) do
			local tab_entry = { title = tab:get_title() or "", active = false, panes = {} }
			local ok, infos = pcall(function()
				return tab:panes_with_info()
			end)
			if ok and infos then
				for _, info in ipairs(infos) do
					local prog = pane_program(info.pane)
					table.insert(tab_entry.panes, {
						cwd = pane_cwd(info.pane),
						prog = prog,
						-- Only knowable when no TUI is in the foreground;
						-- TUI panes get the workspace shell at restore time.
						shell = (not prog) and pane_shell(info.pane) or nil,
						-- A relaunched program would conflict with a typed
						-- command, so only record one for plain shell panes.
						last_cmd = (not prog) and pane_last_command(info.pane) or nil,
						active = info.is_active == true,
					})
					if info.is_active then
						tab_entry.active = true
					end
				end
			end
			if #tab_entry.panes > 0 then
				table.insert(data.tabs, tab_entry)
			end
		end
		return data
	end

	function M.save_workspace_by_name(name)
		-- The default workspace is ephemeral by design (spawned fresh at startup,
		-- never restored), so it must never be persisted.
		if not name or name == "" or name == constants.DEFAULT_WORKSPACE then
			return false
		end
		local path = state_path(name)
		if not path then
			return false
		end

		local ok, result = pcall(function()
			local mux_win = mux_window_for(name)
			if not mux_win then
				return false
			end
			local data = serialize_window(mux_win, name)
			if #data.tabs == 0 then
				return false
			end
			return write_file(path, wezterm.json_encode(data))
		end)

		return ok and result == true
	end

	-- Seconds to wait before typing a restored command, so the shell (and its
	-- prompt) has finished initializing and won't swallow the text.
	local TYPE_DELAY = 1.2

	-- Type a plain shell pane's saved command without running it, so the user
	-- can review or edit it. No-op for program panes (those are relaunched).
	local function type_pending_command(pane, entry)
		if not pane or not entry then
			return
		end
		local cmd = entry.last_cmd
		if entry.prog or type(cmd) ~= "string" or cmd == "" then
			return
		end
		-- Embedded newlines would execute the command; leave those alone.
		if cmd:find("\n") then
			return
		end
		wezterm.time.call_after(TYPE_DELAY, function()
			pcall(function()
				pane:send_text(cmd)
			end)
		end)
	end

	local function spawn_pane_layout(tab, first_pane, panes, workspace_shell)
		-- Active pane occupies the first slot; split out the rest with
		-- alternating directions for a simple, predictable layout.
		local active_pane = first_pane
		local last_pane = first_pane
		for i = 2, #panes do
			local entry = panes[i]
			local direction = (i % 2 == 0) and "Right" or "Down"
			local ok, new_pane = pcall(function()
				return last_pane:split({
					direction = direction,
					cwd = entry.cwd,
					args = spawn_args(entry.prog, entry.shell or workspace_shell, entry.cwd),
				})
			end)
			if ok and new_pane then
				last_pane = new_pane
				type_pending_command(new_pane, entry)
				if entry.active then
					active_pane = new_pane
				end
			end
		end
		if active_pane and active_pane ~= first_pane then
			pcall(function()
				active_pane:activate()
			end)
		end
	end

	-- Pick the most common recorded shell across all panes of a saved
	-- workspace; used as the fallback for panes that didn't record one
	-- (older state files, or panes that were running a TUI on save).
	local function infer_workspace_shell(data)
		local counts = {}
		for _, tab_entry in ipairs(data.tabs or {}) do
			for _, pane_entry in ipairs(tab_entry.panes or {}) do
				local s = pane_entry.shell
				if type(s) == "string" and s ~= "" then
					counts[s] = (counts[s] or 0) + 1
				end
			end
		end
		local best, best_count = nil, 0
		for s, c in pairs(counts) do
			if c > best_count then
				best, best_count = s, c
			end
		end
		return best
	end

	function M.restore_workspace_by_name(name)
		if not name or name == constants.DEFAULT_WORKSPACE then
			return false
		end
		local path = state_path(name)
		if not path then
			return false
		end

		local raw = read_file(path)
		if not raw or raw == "" then
			return false
		end

		local ok, data = pcall(wezterm.json_parse, raw)
		if not ok or type(data) ~= "table" or type(data.tabs) ~= "table" or #data.tabs == 0 then
			return false
		end

		-- Re-normalize cwds so older state files saved with msys POSIX paths
		-- (`/c/foo`) heal automatically without needing to be re-saved.
		for _, tab_entry in ipairs(data.tabs) do
			for _, pane_entry in ipairs(tab_entry.panes or {}) do
				if type(pane_entry.cwd) == "string" then
					pane_entry.cwd = normalize_cwd(pane_entry.cwd)
				end
			end
		end

		local restored = pcall(function()
			local workspace_shell = infer_workspace_shell(data)
			local first = (data.tabs[1].panes or {})[1] or {}

			local spawn_tab, spawn_pane, mux_win = wezterm.mux.spawn_window({
				workspace = name,
				cwd = first.cwd,
				args = spawn_args(first.prog, first.shell or workspace_shell, first.cwd),
			})

			for index, tab_entry in ipairs(data.tabs) do
				local tab, pane
				if index == 1 then
					tab, pane = spawn_tab, spawn_pane
				else
					local lead = tab_entry.panes[1] or {}
					local s = lead.shell or workspace_shell
					local t, p = mux_win:spawn_tab({
						cwd = lead.cwd,
						args = spawn_args(lead.prog, s, lead.cwd),
					})
					tab, pane = t, p
				end

				if tab and tab_entry.title and tab_entry.title ~= "" then
					pcall(function()
						tab:set_title(tab_entry.title)
					end)
				end

				type_pending_command(pane, tab_entry.panes[1])

				if pane and tab_entry.panes and #tab_entry.panes > 1 then
					spawn_pane_layout(tab, pane, tab_entry.panes, workspace_shell)
				end
			end

			return true
		end)

		return restored == true
	end

	-- Display names of all saved workspaces, sorted, for pickers.
	function M.list_saved_workspaces()
		local names = {}
		local ok, entries = pcall(wezterm.read_dir, STATE_DIR)
		if not ok or not entries then
			return names
		end

		for _, entry in ipairs(entries) do
			local stem = tostring(entry):gsub("\\", "/"):match("([^/]+)%.json$")
			if stem then
				local display = stem
				local raw = read_file(entry)
				if raw then
					local pok, data = pcall(wezterm.json_parse, raw)
					if pok and type(data) == "table" and type(data.name) == "string" and data.name ~= "" then
						display = data.name
					end
				end
				table.insert(names, display)
			end
		end

		table.sort(names, function(a, b)
			return a:lower() < b:lower()
		end)
		return names
	end

	-- Remove a saved workspace's state file. Returns true if a file was deleted.
	function M.delete_workspace_by_name(name)
		local path = state_path(name)
		if not path then
			return false
		end
		local ok = os.remove(path)
		return ok ~= nil and ok ~= false
	end
end

return Module
