#!/bin/bash
# Bootstrap Noctalia shell WITHOUT replacing stock quickshell.
#
# Noctalia >= 4.7 requires noctalia-qs (its quickshell fork, e.g. the
# PwAudioSpectrum type). The noctalia-qs package Conflicts=quickshell, and
# stock quickshell must stay for caelestia + dms. So instead of installing
# the package we:
#   1) clone the noctalia QML to  ~/.config/quickshell/noctalia-shell
#   2) extract the noctalia-qs package (no pacman install, no conflict)
#      to ~/.local/opt/noctalia-qs
#   3) create the ~/.local/bin/noctalia wrapper that launches noctalia
#      with the fork binary
# Launch/IPC:  noctalia   /   noctalia ipc call launcher toggle
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

NOCTALIA_VERSION="v4.7.7"
QML_DIR="$REAL_HOME/.config/quickshell/noctalia-shell"
OPT_DIR="$REAL_HOME/.local/opt/noctalia-qs"
WRAPPER="$REAL_HOME/.local/bin/noctalia"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# 1) Noctalia QML
if [ -e "$QML_DIR/shell.qml" ]; then
    echo ":: Noctalia QML already present at $QML_DIR"
else
    echo ":: Cloning noctalia-shell $NOCTALIA_VERSION"
    as_user git clone --depth 1 --branch "$NOCTALIA_VERSION" \
        https://github.com/noctalia-dev/noctalia-shell.git "$QML_DIR"
fi

# 2) noctalia-qs fork binary (extracted, not installed)
if [ -x "$OPT_DIR/usr/bin/quickshell" ]; then
    echo ":: noctalia-qs already extracted at $OPT_DIR"
else
    echo ":: Downloading noctalia-qs package (cachyos repo)"
    url=$(pacman -Sp noctalia-qs | tail -1)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -sL -o "$tmp/noctalia-qs.pkg.tar.zst" "$url"
    as_user mkdir -p "$OPT_DIR"
    as_user tar -xf "$tmp/noctalia-qs.pkg.tar.zst" -C "$OPT_DIR" usr
    # package's qs symlink points at /usr/bin/quickshell (stock) — fix it
    as_user ln -sf quickshell "$OPT_DIR/usr/bin/qs"
fi

# 3) wrapper
if [ ! -e "$WRAPPER" ]; then
    as_user mkdir -p "$(dirname "$WRAPPER")"
    cat > "$WRAPPER" <<'EOF'
#!/bin/bash
# Noctalia needs its own quickshell fork (noctalia-qs) which conflicts with
# the stock quickshell package — so the fork lives unpackaged in ~/.local/opt
# and this wrapper launches noctalia with it. Managed by dcli (setup-noctalia.sh).
exec "$HOME/.local/opt/noctalia-qs/usr/bin/quickshell" -c noctalia-shell "$@"
EOF
    chmod 755 "$WRAPPER"
    chown "$REAL_USER:$(id -gn "$REAL_USER")" "$WRAPPER" 2>/dev/null || true
    echo ":: Created $WRAPPER"
fi

echo ":: Noctalia ready — launch with 'noctalia', switch with switch-shell.sh noctalia"
