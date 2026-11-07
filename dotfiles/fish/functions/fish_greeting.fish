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

    # A live-art theme (its fastfetch ships live-art) draws its logo with Python,
    # too slow to wait for in full: the art is painted ahead into the directory
    # live-art names and shown from disk. Only when it is missing or expired does
    # the greeting wait, for a quick still frame; the full art is painted in the
    # background below, for the next terminal. A failed paint keeps the old art
    # (or none: fastfetch then shows the distro logo) and is in paint.log.
    set -l painter ~/.config/dcli/scripts/paint-terminal-art.sh
    set -l live_art ~/.config/fastfetch/live-art
    if test -r $live_art; and test -x $painter
        set -l expires
        read -l live_dir <$live_art
        and test -r $live_dir/expires
        and read expires <$live_dir/expires
        if not string match -qr '^\d+$' -- "$expires"; or test "$expires" -le (date +%s)
            command $painter --still &>/dev/null
        end
    end

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

    if test -r $live_art; and test -x $painter
        command $painter --next &>/dev/null &
        disown 2>/dev/null
    end
end
