# The greeting follows the active shell: each one ships its own fastfetch
# config, swapped on every switch by scripts/apply-terminal-theme.sh, and the
# flags a config expects belong to that config, not to the greeting.
function fish_greeting
    # dcli's own prompt/fastfetch configs wear the shell's live palette; a new
    # wallpaper recolours a Material You shell mid-session, so each terminal
    # re-renders them in the background (a no-op when nothing changed). The
    # render is atomic, so the fastfetch below never reads a half-written file.
    set -l refresher ~/.config/dcli/scripts/apply-terminal-theme.sh
    if test -x $refresher
        command $refresher --refresh &>/dev/null &
        disown 2>/dev/null
    end

    command -q fastfetch; or return

    set -l active_conf ~/.config/hypr/shells/active.conf
    set -l active
    test -r $active_conf; and set active (string match -rv '^\s*(#|$)' < $active_conf)[1]

    switch "$active"
        case caelestia
            # Upstream's config has "logo": null and indents its own keys, so the
            # banner and padding belong to it; the --alt one carries its own logo.
            if string match -q '*"logo": null*' < ~/.config/fastfetch/config.jsonc 2>/dev/null
                echo -ne '\x1b[38;5;16m' # primary colour
                echo '     ______           __          __  _       '
                echo '    / ____/___ ____  / /__  _____/ /_(_)___ _ '
                echo '   / /   / __ `/ _ \/ / _ \/ ___/ __/ / __ `/ '
                echo '  / /___/ /_/ /  __/ /  __(__  ) /_/ / /_/ /  '
                echo '  \____/\__,_/\___/_/\___/____/\__/_/\__,_/   '
                set_color normal
                fastfetch --key-padding-left 5
            else
                fastfetch
            end
        case ryoku
            # ryoku-fastfetch exports this; its config prints it verbatim otherwise
            # (`command -q`, not a 2>/dev/null: fish reports an unknown command itself)
            if not set -q RYOKU_BASE_OS
                if command -q ryoku-base-os
                    set -gx RYOKU_BASE_OS (ryoku-base-os)
                else
                    set -gx RYOKU_BASE_OS Linux
                end
            end
            fastfetch
        case '*'
            fastfetch
    end
end
