#!/bin/bash
# Update Noctalia shell: pulls latest QML and re-downloads noctalia-qs binary.
# Run with --force to re-download the binary even if it already exists.
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

NOCTALIA_VERSION="v4.7.7"
QML_DIR="$REAL_HOME/.config/quickshell/noctalia-shell"
OPT_DIR="$REAL_HOME/.local/opt/noctalia-qs"
FORCE=false

[[ "${1:-}" == "--force" ]] && FORCE=true

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# 1) Update Noctalia QML
if [ -d "$QML_DIR/.git" ]; then
    echo ":: Updating noctalia-shell QML"
    as_user git -C "$QML_DIR" fetch --depth 1 origin "$NOCTALIA_VERSION"
    as_user git -C "$QML_DIR" checkout FETCH_HEAD
else
    echo "!! QML not found at $QML_DIR — run setup-noctalia.sh first" >&2
    exit 1
fi

# 2) Update noctalia-qs binary
if [ -x "$OPT_DIR/usr/bin/quickshell" ] && [ "$FORCE" = false ]; then
    echo ":: noctalia-qs already present (use --force to re-download)"
else
    echo ":: Downloading noctalia-qs package"
    url=$(pacman -Sp noctalia-qs | tail -1)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -sL -o "$tmp/noctalia-qs.pkg.tar.zst" "$url"
    as_user mkdir -p "$OPT_DIR"
    as_user tar -xf "$tmp/noctalia-qs.pkg.tar.zst" -C "$OPT_DIR" usr
    as_user ln -sf quickshell "$OPT_DIR/usr/bin/qs"
    echo ":: noctalia-qs updated"
fi

echo ":: Noctalia updated — restart shell with switch-shell.sh noctalia"
