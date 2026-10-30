-- ryoku login bootstrap.
--
-- RYOKU_SHELL_DIR is how the daemon finds its QML tree; upstream's dev-run.sh
-- exports the same value. No RYOKU_POLKIT_AGENT: the house hyprpolkitagent
-- keeps the session's single agent slot (the daemon starts its own otherwise).
hl.on("hyprland.start", function()
    hl.exec_cmd("RYOKU_SHELL_DIR=\"$HOME/.local/share/ryoku-shell/ryoku/shell\" \"$HOME/.local/bin/ryoku-shell\" daemon")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
