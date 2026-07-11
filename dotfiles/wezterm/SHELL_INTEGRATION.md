# Shell integration for workspace persistence

Saved workspaces restore each plain shell pane's **last command** and pre-type it
(without running) so you can pick up where you left off. WezTerm can't read your
shell history on its own, so each shell must publish its command to WezTerm.

## How it works

When you submit a command, the shell emits an invisible escape sequence that sets a
WezTerm **user var** called `WEZTERM_LAST_CMD`:

```
ESC ] 1337 ; SetUserVar=WEZTERM_LAST_CMD=<base64 of the command> BEL
```

WezTerm reads it with `pane:get_user_vars()` when it saves a workspace
(`wezterm/workspaces/persistence.lua`) and types it back with `pane:send_text()`
on restore.

The command is published at **submit time** (before it runs), so a long-running
command (e.g. `npx ...`) is still captured while it's executing — not just after it
finishes.

Each snippet is guarded to only run inside WezTerm (`WEZTERM_PANE`), so it's a no-op
in other terminals. **Restart the shell (open a fresh pane) after adding the snippet**
— profile changes only affect new sessions.

---

## PowerShell (pwsh)

Add to your profile (`$PROFILE`, e.g.
`~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`), **after** any prompt
setup such as `starship init`:

```powershell
# WezTerm: publish current/last command for workspace restore.
if ($env:WEZTERM_PANE) {
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        if ($line) {
            $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($line))
            [Console]::Write("`e]1337;SetUserVar=WEZTERM_LAST_CMD=$b64`a")
        }
        return $true
    }
}
```

`AddToHistoryHandler` fires the instant you press Enter, before the command runs.

---

## Zsh

Add to `~/.zshrc`:

```zsh
# WezTerm: publish current/last command for workspace restore.
if [[ -n "$WEZTERM_PANE" ]]; then
    __wezterm_lastcmd() {
        local b64
        b64=$(printf '%s' "$1" | base64 | tr -d '\n')
        printf '\033]1337;SetUserVar=WEZTERM_LAST_CMD=%s\007' "$b64"
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec __wezterm_lastcmd
fi
```

Zsh's `preexec` hook receives the full command line in `$1`.

---

## Bash

Add to `~/.bashrc`:

```bash
# WezTerm: publish current/last command for workspace restore.
if [ -n "$WEZTERM_PANE" ]; then
    __wezterm_lastcmd_armed=0
    __wezterm_lastcmd_arm() { __wezterm_lastcmd_armed=1; }
    __wezterm_lastcmd_emit() {
        [ -n "$COMP_LINE" ] && return                  # ignore tab-completion
        [ "$__wezterm_lastcmd_armed" = 1 ] || return   # emit once per typed line
        __wezterm_lastcmd_armed=0
        local line b64
        line=$(HISTTIMEFORMAT='' history 1 | sed 's/^ *[0-9]* *//')
        b64=$(printf '%s' "$line" | base64 | tr -d '\n')
        printf '\033]1337;SetUserVar=WEZTERM_LAST_CMD=%s\007' "$b64"
    }
    trap '__wezterm_lastcmd_emit' DEBUG
    PROMPT_COMMAND="__wezterm_lastcmd_arm${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
```

Bash has no native preexec, so this uses the `DEBUG` trap plus `PROMPT_COMMAND`:
the prompt "arms" a flag, and the first `DEBUG` of the next command line emits the
command (read from `history 1`) and disarms, so compound commands emit only once.

---

## Fish

Add to `~/.config/fish/config.fish`:

```fish
# WezTerm: publish current/last command for workspace restore.
if set -q WEZTERM_PANE
    function __wezterm_lastcmd --on-event fish_preexec
        set -l b64 (printf '%s' "$argv[1]" | base64 | tr -d '\n')
        printf '\033]1337;SetUserVar=WEZTERM_LAST_CMD=%s\007' "$b64"
    end
end
```

Fish's `fish_preexec` event delivers the full command line in `$argv[1]`.

---

## Verifying

After restarting the shell, run a command, then in WezTerm's debug overlay
(`CTRL+SHIFT+L`) check the pane's user vars, or just save and restore a workspace and
confirm the command is pre-typed at the prompt. Multi-line commands are intentionally
skipped on restore (typing embedded newlines would run them).
