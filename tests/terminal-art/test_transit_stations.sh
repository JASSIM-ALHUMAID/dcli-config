#!/bin/bash
# transit prompt: the [custom.stations] command in the theme's starship.toml
# must draw every path shape as the right metro stations. The command is read
# from the TOML, never copied here, and run the way starship runs it: fed to sh
# on stdin from inside the directory. sh replaces a PWD that does not name its
# working directory, so every case is a real directory (a fixture tree for the
# home cases). Silent on success; the first mismatch prints expected vs got on
# stderr and exits 1.
set -euo pipefail
shopt -s extglob

REPO_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)
STARSHIP_TOML="$REPO_DIR/dotfiles/terminal/_themes/transit/starship.toml"
STATIONS_SECTION="[custom.stations]"
TOML_LITERAL_DELIM="'''"
ANSI_RESET=$'\e[0m'

fail() { printf 'transit stations: %s\n' "$*" >&2; exit 1; }

# ── extract: the command exactly as starship reads it ────────────────────────
# Only the ''' literal form is read (the theme's form); TOML drops a newline
# right after the opening delimiter. Exits 1 when there is no such command.
stations_command() {
  awk -v section="$STATIONS_SECTION" -v delim="$TOML_LITERAL_DELIM" '
    reading {
      end = index($0, delim)
      if (end) { printf "%s", substr($0, 1, end - 1); found = 1; exit }
      print
      next
    }
    /^\[/ { in_section = ($0 == section); next }
    in_section && $0 ~ ("^command[ \t]*=[ \t]*" delim) {
      sub("^command[ \t]*=[ \t]*" delim, "")
      end = index($0, delim)
      if (end) { printf "%s", substr($0, 1, end - 1); found = 1; exit }
      reading = 1
      if ($0 != "") print
    }
    END { exit !found }' "$STARSHIP_TOML"
}

[ -f "$STARSHIP_TOML" ] || fail "no theme prompt at ${STARSHIP_TOML#"$REPO_DIR"/}"
command=$(stations_command) ||
  fail "no ''' command under $STATIONS_SECTION in ${STARSHIP_TOML#"$REPO_DIR"/}"

# ── cases ────────────────────────────────────────────────────────────────────
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
home="$fixture/home/u"
# A name a printf format or an awk -v assignment would mangle.
hostile='100%s \n'
mkdir -p "$home/.config/dcli" "$home/a/b/c/d/e" "$home/my dir/نجم" "$home/$hostile"
for outside in / /etc/systemd; do
  [ -d "$outside" ] || fail "needs the real directory $outside for the outside-home cases"
done

# expect <dir> <HOME> <expected stations, ANSI stripped>
expect() {
  local dir="$1" home_dir="$2" want="$3" raw got
  raw=$( { cd "$dir" && PWD="$dir" HOME="$home_dir" sh <<<"$command"; } 2>"$fixture/stderr") ||
    fail "command exited non-zero at PWD=$dir: $(cat "$fixture/stderr")"
  [ ! -s "$fixture/stderr" ] || fail "command wrote to stderr at PWD=$dir: $(cat "$fixture/stderr")"
  got=${raw//$'\e['*([0-9;])m/}
  [ "$got" = "$want" ] ||
    fail "PWD=$dir HOME=$home_dir"$'\n'"  expected: $want"$'\n'"  got:      $got"
  # The next prompt module must not inherit the current station's bold colour.
  [[ $raw == *"$ANSI_RESET" ]] || fail "PWD=$dir: output does not end with a colour reset"
}

expect "$home" "$home" "◉ ~"
expect "$home/.config/dcli" "$home" "◯ ~ ━━ ◯ .config ━━ ◉ dcli"
expect "$home/a/b/c/d/e" "$home" "┄ ◯ b ━━ ◯ c ━━ ◯ d ━━ ◉ e"
expect / "$home" "◉ /"
expect /etc/systemd "$home" "◯ / ━━ ◯ etc ━━ ◉ systemd"
expect "$home/my dir/نجم" "$home" "◯ ~ ━━ ◯ my dir ━━ ◉ نجم"
# Truncation edges: four stations fit, a fifth pushes the first off the map.
expect "$home/a/b/c" "$home" "◯ ~ ━━ ◯ a ━━ ◯ b ━━ ◉ c"
expect "$home/a/b/c/d" "$home" "┄ ◯ a ━━ ◯ b ━━ ◯ c ━━ ◉ d"
# HOME is a station only as a whole path component, with or without a trailing
# slash; a root HOME is not one.
expect /etc/systemd /etc/sys "◯ / ━━ ◯ etc ━━ ◉ systemd"
expect "$home/.config/dcli" "$home/" "◯ ~ ━━ ◯ .config ━━ ◉ dcli"
expect /etc/systemd / "◯ / ━━ ◯ etc ━━ ◉ systemd"
expect "$home/$hostile" "$home" "◯ ~ ━━ ◉ $hostile"
