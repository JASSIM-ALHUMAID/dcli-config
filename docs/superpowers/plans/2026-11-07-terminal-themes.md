# Terminal Themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three shell-independent terminal themes (horizon, gallery, transit), each a starship prompt + fastfetch greeting, on a new `_themes` layer with painted-ahead "live art".

**Architecture:** `_themes/<t>/` templates resolved ahead of the per-shell layers by `scripts/lib/terminal-theme.sh`, rendered with the running shell's palette plus a `{{live}}` token. horizon and gallery logos are painted by Python (`scripts/terminal-art/`) into atomically swapped generations under `state/terminal/live/`. fish_greeting paints a quick still only when the art has expired, then paints the next full piece in the background.

**Tech Stack:** Bash 5.3, fish, fastfetch 2.70.0, starship 1.27.0, Python 3.14 + Pillow 13 (stdlib `unittest`), WezTerm (iTerm2 inline images, APNG animates).

**Spec:** `docs/superpowers/specs/2026-11-07-terminal-themes-design.md`

## Global Constraints

- Work only in the worktree `/home/awhss/.config/dcli/.worktrees/terminal-themes` (branch `feat/terminal-themes`). Never edit the main checkout `/home/awhss/.config/dcli` except `devfiles/` and `AGENTS.md` in Task 6 (they are git-ignored and exist only there). Never touch the live links `~/.config/starship.toml` / `~/.config/fastfetch` or `~/.config/fish`; use a fixture `HOME` and `TERMINAL_STATE_DIR`.
- Commits: conventional (`feat(terminal): …`), **no** `Co-Authored-By` or "Generated with" lines.
- Read `AGENTS.md` (main checkout) coding rules: `set -euo pipefail` in executables; shellcheck clean under `.shellcheckrc`; `# ── label ──` banners in files with 2+ concerns; every tunable is a named constant next to its use; comments only for *why*; search `scripts/lib/` before defining a helper (no second `current_shell`, `KNOWN`, palette reader).
- Python: type hints everywhere, `dataclass(frozen=True)`, `Enum` for modes, no bare `except`, no numpy, Pillow imported only where drawing happens. Errors go to stderr with detail; nothing prints on success except where a CLI says so.
- Versions: fastfetch 2.70.0, starship 1.27.0, Python 3.14, Pillow 13.
- Width target 80–100 columns. Never use `█▒░▰▱`; bars use `● ○ ■ □ ◆ ◇ ▪ ▫ ▬ ▭ ━ ╌ ·`.
- Prompts: no right-hand frame; `command_timeout = 300`; custom commands are one `sh`/`awk` call, no network, no package queries.
- Palette tokens available: `background surface surfaceContainer surfaceVariant text primary onPrimary secondary tertiary error outline` as `{{k}}` (#rrggbb) and `{{k.rgb}}` (r;g;b). Plus `{{live}}` in `_themes` only (Task 2).
- WezTerm cell = 12 × 30 px. Images may be larger than their box; always `"preserveAspectRatio": true`.
- Visual check: `/tmp/claude-1000/-home-awhss--config-dcli/cd13edd0-a5b6-4199-8feb-06fe11267448/scratchpad/snap-terminal.sh <out-prefix> <shots> <interval-s> -- <command…>` opens a real WezTerm window on the user's screen, waits for it to tile, runs the command, and saves screenshots; view them with the Read tool. Put outputs under that scratchpad directory. Look at every theme you build this way before reporting done; judge it as a designer would.
- Gate before reporting: `bash tests/smoke.sh` (≈80 s) ends with `smoke: all checks passed`.

## Review Focus

1. A saved theme whose directory was deleted or renamed → the next layer is worn and one warning is printed; the prompt never breaks. (Task 2 test `theme: saved theme that no longer exists falls through`.)
2. Pillow missing or a generator raising → greeting still prints (fastfetch falls back to the distro logo), the old art is kept, the error is in `paint.log`, doctor reports it. (Task 3 tests `paint_failure_keeps_previous_generation`, `paint_failure_is_logged`.)
3. Two terminals opening at once → no torn art, one paint at a time, `--next` skips while a paint runs. (Task 3 test `next_skips_while_locked`.)
4. Time edges: a bucket boundary, the minute of sunrise/sunset, after sunset before midnight vs after midnight before sunrise (the moon bar must use the right night). (Task 4 tests `bucket_expiry_is_next_boundary`, `night_progress_spans_midnight`.)
5. Deep, spaced or unicode paths in the transit prompt, and an 80-column terminal for every greeting. (Task 1 test cases in `tests/terminal-art/test_transit_stations.sh`; Task 1/4/5 snaps at 80 columns.)

---

### Task 1: transit theme (text only)

**Files:**
- Create: `dotfiles/terminal/_themes/transit/starship.toml`
- Create: `dotfiles/terminal/_themes/transit/fastfetch/config.jsonc`
- Create: `dotfiles/terminal/_themes/transit/fastfetch/logo.txt`
- Create: `tests/terminal-art/test_transit_stations.sh`

**Interfaces:**
- Consumes: nothing (Task 2 wires the layer; until then, test the files directly).
- Produces: a complete theme directory, the first entry in the `_themes` layer. Task 2's tests use `transit` as their real theme.

- [ ] **Step 1: Write the failing station test.** `tests/terminal-art/test_transit_stations.sh` extracts the `[custom.stations]` command from `starship.toml` (read it with a small awk over the TOML, do not duplicate the command) and runs it with `PWD` and `HOME` set, printing ANSI-stripped output. Cases (input PWD with HOME=/home/u → expected stripped output):
  - `/home/u` → `◉ ~`
  - `/home/u/.config/dcli` → `◯ ~ ━━ ◯ .config ━━ ◉ dcli`
  - `/home/u/a/b/c/d/e` → `┄ ◯ b ━━ ◯ c ━━ ◯ d ━━ ◉ e` (last 4 stations only)
  - `/` → `◉ /`
  - `/etc/systemd` → `◯ / ━━ ◯ etc ━━ ◉ systemd`
  - `/home/u/my dir/نجم` → `◯ ~ ━━ ◯ my dir ━━ ◉ نجم`
  Exit non-zero on the first mismatch, printing expected vs got.
- [ ] **Step 2: Run it** — `bash tests/terminal-art/test_transit_stations.sh` → FAIL (no starship.toml).
- [ ] **Step 3: Write `starship.toml`.** Layout per spec (§ transit Prompt). `[custom.stations]`: `command` = one `awk` program over `$PWD`/`$HOME`, `when = true`, `shell = ["sh"]`; colours inline as ANSI (fixed Session `#9B5DE5` line, current station bold `#E6E6E6`, others `#8A90A0`). `git_branch` format `⇄ $branch` in Compute `#2F7DE1`; `[status] disabled = false`, format `⚠ disruption · exit $status` in Boot `#E8453C`; `cmd_duration` `min_time = 2000`, `delayed $duration`; `time` `%H:%M`; `character` `›` (Memory green / Boot red).
- [ ] **Step 4: Run the station test** → PASS. Also `STARSHIP_CONFIG=dotfiles/terminal/_themes/transit/starship.toml starship prompt --status=1 --cmd-duration=5000` prints no `warn`/`error`, and `time (starship prompt …)` stays under 30 ms.
- [ ] **Step 5: Write `logo.txt`** — original line-map emblem (spec § transit Logo): ≤ 24 cols × ≤ 12 rows, truecolor ANSI, transparent cells are spaces. Not a copy of any real transit mark.
- [ ] **Step 6: Write `fastfetch/config.jsonc`.** `"logo": {"type": "file", "source": "~/.config/fastfetch/logo.txt", …}`. Modules per spec § transit Greeting; keys carry the track glyphs with ANSI colour; stations: firmware (`bios`), kernel, init (`initsystem`), compositor (`wm`), shell, terminal (`terminal`, marked "◉ you are here"); branches off the boot line: cpu (Compute), memory with bar (Memory), disk `/` with bar (Storage), gpu if present (Compute); footer: "service status" with uptime and package count. Comment header in the house style (see `_alt-v2/noctalia/fastfetch/config.jsonc`).
- [ ] **Step 7: Validate** — `fastfetch -c dotfiles/terminal/_themes/transit/fastfetch/config.jsonc --logo dotfiles/terminal/_themes/transit/fastfetch/logo.txt --pipe true 2>&1 >/dev/null` prints nothing.
- [ ] **Step 8: Look at it.** Snap the greeting followed by a prompt, e.g. `snap-terminal.sh <scratch>/transit 1 0 -- bash -c 'fastfetch -c … --logo …; cd ~/.config/dcli; STARSHIP_CONFIG=… starship prompt --status=1 --cmd-duration=12000; echo'`. Fix anything misaligned, cramped or ugly. Also check at 80 columns (`stty cols 80` before fastfetch).
- [ ] **Step 9: Commit** — `feat(terminal): transit theme — the system as a metro map`.

---

### Task 2: the `_themes` layer (resolver, apply, refresh, doctor, preview)

**Files:**
- Modify: `scripts/lib/terminal-theme.sh` (header comment, constants, `terminal_themes`, `terminal_theme_choice`, `terminal_source`, `terminal_rendered_path`, `terminal_render`)
- Modify: `scripts/apply-terminal-theme.sh` (flags, `--use theme:<n>`, `--refresh`, usage)
- Modify: `scripts/doctor.sh` (`check_terminal_theme`)
- Modify: `scripts/preview-terminal-themes.sh` (`--variant theme:<name>`)
- Modify: `tests/smoke.sh` (terminal section)

**Interfaces:**
- Consumes: `dotfiles/terminal/_themes/transit/` (Task 1).
- Produces (later tasks rely on these exact names):
  - `TERMINAL_THEMES_DIR="$TERMINAL_DOTFILES_DIR/_themes"`, `TERMINAL_THEME_FILE="$TERMINAL_STATE_DIR/theme"`, `TERMINAL_LIVE_DIR="$TERMINAL_STATE_DIR/live"`.
  - `terminal_themes` → prints theme names (dirs with both `starship.toml` and `fastfetch/config.jsonc`), sorted, one per line.
  - `terminal_theme_choice` → prints the active theme or nothing; one-shot env `TERMINAL_THEME` beats all; any one-shot `TERMINAL_PREFER_ALT*` beats a saved theme; a saved name that is not in `terminal_themes` prints `!! terminal: saved theme '<n>' no longer exists — ignoring it` to stderr and prints nothing.
  - Rendered path `_themes/<t>/…` → `$TERMINAL_RENDER_DIR/theme/<t>/…`.
  - `{{live}}` → `$TERMINAL_LIVE_DIR/<t>` for sources under `_themes/<t>/`; part of the render signature.
  - CLI: `apply-terminal-theme.sh [--dry-run] [--theme <name>|--alt|--alt-v2|--alt-v3] <shell>`, `--use alt|alt-v2|alt-v3|upstream|theme:<name>`, `--refresh`. Unknown theme → exit 2 with usage.
  - `preview-terminal-themes.sh --variant theme:<name> [shell…]`.

- [ ] **Step 1: Write failing smoke tests** in `tests/smoke.sh`'s terminal section (reuse `t_home`, `t_state`, `t_apply`, `xenon_palette`). One `ok`/`bad` each:
  - `theme: every _themes theme has a starship and fastfetch template` (iterate `terminal_themes`; ≥ 1).
  - Extend the render-all loop to `_themes/*/starship.toml` and `_themes/*/fastfetch`, rendering with shell `xenon`; `{{live}}` must be filled.
  - `theme: --theme is one switch` — `t_apply --theme transit xenon` links `render/theme/transit/starship.toml` and `…/fastfetch`; then `t_apply xenon` → `render/main/xenon/…`.
  - `theme: --use theme:transit persists across shells and clears alt flags` — after `t_apply --use alt-v2`, `t_apply --use theme:transit` → `$t_state/theme` contains `transit`, no `prefer-alt*`; `t_apply noctalia` → still `render/theme/transit/…`; `t_apply --use alt-v2` → `$t_state/theme` gone.
  - `theme: a one-shot --alt-v2 beats a saved theme`.
  - `theme: unknown theme is a usage error` — `--theme nope xenon` and `--use theme:nope` exit 2 and change no link.
  - `theme: saved theme that no longer exists falls through` — write `ghost` to `$t_state/theme`; `t_apply xenon` exits 0, links `render/main/xenon/…`, stderr contains `saved theme 'ghost' no longer exists`.
  - `theme: --refresh follows a theme link with the running shell's palette` — wear transit via `--use theme:transit`, change `xenon_palette`, `--refresh` succeeds (transit has no palette tokens, so assert the render signature file changed; use a fixture theme dir with `{{primary}}` under a temporary `TERMINAL_DOTFILES_DIR` copy if you need a visible colour).
  - `theme: {{live}} renders to the theme's live dir` — render a temp `_themes/probe/fastfetch/live-art` containing `{{live}}` and assert it equals `$t_state/live/probe`.
  - `theme: preview renders a theme without retargeting live links`.
- [ ] **Step 2: Run** `bash tests/smoke.sh` → the new checks FAIL, the old ones still pass.
- [ ] **Step 3: Implement** the Produces list in `terminal-theme.sh` and `apply-terminal-theme.sh`. Update the header comments to describe the layer and precedence. `--refresh`: a `render/theme/<t>/…` link re-renders `_themes/<t>/…` with `current_shell`'s palette.
- [ ] **Step 4: doctor** — `check_terminal_theme` reports `ok "terminal: $tool wears theme <t>"` when the link matches the theme target.
- [ ] **Step 5: preview** — `--variant theme:<name>` renders that theme for each requested shell (all shells by default) into the temp state; validate the name against `terminal_themes`.
- [ ] **Step 6: Run** `bash tests/smoke.sh` → all checks pass; `shellcheck scripts/*.sh scripts/lib/*.sh` clean.
- [ ] **Step 7: Commit** — `feat(terminal): shell-independent _themes layer (--theme, --use theme:<name>)`.

---

### Task 3: live-art engine (painter, greeting hook, Pillow dependency)

**Files:**
- Create: `scripts/terminal-art/artlib.py` (shared types and helpers)
- Create: `scripts/terminal-art/paint.py` (CLI, policy, lock, generations, log)
- (`scripts/terminal-art/themes/` arrives with Task 4's first file; `paint.py` resolves theme modules from it, and this task's tests use fake modules.)
- Create: `scripts/paint-terminal-art.sh`
- Modify: `scripts/doctor.sh` (live-art health), `scripts/preview-terminal-themes.sh` (paint a still for live themes)
- Create: `tests/terminal-art/test_artlib.py`, `tests/terminal-art/test_paint.py`
- Modify: `dotfiles/fish/functions/fish_greeting.fish`
- Modify: `modules/shell-fish.yaml` (add `python-pillow` with a why-comment)
- Modify: `tests/smoke.sh` (run the unit tests; painter no-op check)

**Interfaces:**
- Consumes: `TERMINAL_LIVE_DIR`, `terminal_theme_choice`, `{{live}}` (Task 2); `current_shell` (`lib/shell-common.sh`), `palette_for` + `shell_wallpaper` (`lib/palette.sh`, `lib/wallpaper.sh`).
- Produces — `artlib.py`:
  - `class Mode(Enum): STILL = "still"; FULL = "full"`
  - `RGB = tuple[int, int, int]`
  - `@dataclass(frozen=True) class Palette` with one `RGB` field per palette key (snake_case: `surface_container`, `surface_variant`, `on_primary`, …); `Palette.from_json(text: str) -> Palette` raises `ValueError` naming the missing/invalid key.
  - `@dataclass(frozen=True) class SystemStats`: `hostname: str, kernel: str, os_name: str, mem_total_kib: int, mem_available_kib: int, load1: float, threads: int, uptime_s: float, disk_total_b: int, disk_free_b: int`; properties `mem_used_fraction`, `disk_used_fraction`; `SystemStats.read(proc: Path = Path("/proc"), disk: Path = Path("/"), os_release: Path = Path("/etc/os-release")) -> SystemStats`.
  - `@dataclass(frozen=True) class PaintContext`: `out_dir: Path, mode: Mode, now: datetime` (tz-aware, local), `palette: Palette, stats: SystemStats, state_dir: Path` (persistent per-theme dir `live/.<theme>.state/`, created by paint.py).
  - `@dataclass(frozen=True) class Painted`: `expires: int` (epoch s).
  - `NEVER_EXPIRES = 2**31 - 1`
  - `write_text_atomic(path: Path, text: str) -> None`
  - Theme module contract (documented in artlib, checked by paint.py): module `themes/<name>.py` defines `REPAINT_AFTER_GREETING: bool` and `paint(ctx: PaintContext) -> Painted`; it writes `logo.png` and its text files into `ctx.out_dir`.
- Produces — `paint.py`: `python3 -E -s paint.py --theme <name> --live <symlink path> --mode still|next --palette <json> [--now <ISO 8601>]`; `--now` overrides the clock (for screenshots and tests; documented in the usage text). Exits 0 on success or no-op, 1 on failure (logged), 2 on usage. Public functions for tests: `class Request(Enum): STILL = "still"; NEXT = "next"`, `class Outcome(Enum): PAINTED, UP_TO_DATE, BUSY`, `run(theme: ModuleType, live: Path, request: Request, palette: Palette, now: datetime, stats: SystemStats, lock_wait_s: float) -> Outcome`. Writes `expires` and `kind` into each generation. Lock file `<live>.lock` (fcntl). Log `<live parent>/paint.log`, trimmed to `PAINT_LOG_KEEP = 200` lines. Constants: `STILL_LOCK_WAIT_S = 2.0`.
- Produces — `scripts/paint-terminal-art.sh --still|--next [--theme <name>]`: theme defaults to `basename` of the path in `~/.config/fastfetch/live-art` (exit 0 silently when absent, or when `scripts/terminal-art/themes/<name>.py` does not exist); palette from `palette_for "$(current_shell)" …`; runs `python3 -E -s "$SCRIPT_DIR/terminal-art/paint.py" …`.
- Produces — greeting contract: a theme opts into live art by shipping `fastfetch/live-art` containing `{{live}}`.

- [ ] **Step 1: Write failing unit tests.** Run with `PYTHONPATH=scripts/terminal-art python3 -m unittest discover -s tests/terminal-art -p 'test_*.py'`.
  - `test_artlib.py`: `palette_from_json_parses_all_keys`, `palette_from_json_names_missing_key` (message contains `onPrimary`), `stats_read_from_fixture_proc` (fixture `meminfo` MemTotal 32000000 kB / MemAvailable 8000000 kB → `mem_used_fraction == 0.75`; `loadavg` `1.50 …` → `load1 == 1.5`; `uptime` `3600.5 …` → `uptime_s == 3600.5`), `write_text_atomic_replaces_whole_file`.
  - `test_paint.py` with a fake theme module (a `types.SimpleNamespace` with `REPAINT_AFTER_GREETING` and a `paint` that writes `logo.png` bytes and returns `Painted(expires=…)`): `still_paints_when_missing`, `still_is_noop_when_unexpired` (→ `UP_TO_DATE`), `still_repaints_when_expired`, `next_upgrades_still_to_full`, `next_is_noop_when_full_and_unexpired`, `next_always_paints_when_theme_repaints_after_greeting`, `next_skips_while_locked` (hold the lock in the test → `BUSY`), `generation_swap_keeps_previous_and_prunes_older` (after 3 paints: symlink → newest, exactly 2 generation dirs), `paint_failure_keeps_previous_generation` (theme raises → symlink unchanged, no `.tmp` dirs left), `paint_failure_is_logged` (log contains the exception text), `log_is_trimmed_to_keep_lines`.
- [ ] **Step 2: Run** → FAIL (modules missing).
- [ ] **Step 3: Implement `artlib.py` and `paint.py`** to the Produces contract. Generation dirs `.<theme>.<time_ns>`; write into `….tmp`, rename, then replace the symlink via a temp symlink + `os.replace`. Theme module loading: `importlib` from `scripts/terminal-art/themes/`, name must match `^[a-z][a-z0-9_]*$`.
- [ ] **Step 4: Run unit tests** → PASS.
- [ ] **Step 5: `scripts/paint-terminal-art.sh`** per Produces; usage error → exit 2.
- [ ] **Step 6: fish_greeting.** Before the existing `switch "$active"`: if `~/.config/fastfetch/live-art` is readable, read the live dir; if `$dir/expires` is missing, non-numeric or ≤ `(date +%s)`, run `paint-terminal-art.sh --still` synchronously with output discarded. After the switch: if `live-art` exists, start `paint-terminal-art.sh --next` in the background (`&>/dev/null &; disown`, as the existing refresher does). Why-comment in the existing voice. `fish -n` passes.
- [ ] **Step 7: Package** — add `python-pillow` to `modules/shell-fish.yaml` `packages:` with a one-line why-comment (live-art logos).
- [ ] **Step 7b: doctor + preview.** `doctor.sh`: when the worn fastfetch has `live-art`, `warn` if `python3 -c 'import PIL'` fails and `warn` with the last error line when `paint.log` holds a failure newer than the current generation; otherwise `ok "terminal: live art for <t> is current"`. `preview-terminal-themes.sh --variant theme:<t>`: when the rendered fastfetch has `live-art`, run `paint-terminal-art.sh --still --theme <t>` against the temp state first, so the preview has a picture.
- [ ] **Step 8: Smoke** — add: `terminal-art: python unit tests pass` (the unittest command above, skipped with `ok … (python3/Pillow missing)` only if `python3 -c 'import PIL'` fails), `terminal-art: painter is a no-op without a live theme` (fixture HOME without `live-art` → exit 0, nothing created), `terminal-art: fish_greeting parses` (`fish -n`).
- [ ] **Step 9: Run** `bash tests/smoke.sh` → all pass. Commit — `feat(terminal): live-art painter — paint ahead, swap atomically, greet instantly`.

---

### Task 4: horizon theme

**Files:**
- Create: `scripts/terminal-art/themes/horizon.py` (entry: `paint`, `REPAINT_AFTER_GREETING = False`)
- Create: `scripts/terminal-art/themes/sky.py` (pure astronomy + colour math; no Pillow)
- Create: `tests/terminal-art/test_sky.py`, `tests/terminal-art/test_horizon.py`
- Create: `dotfiles/terminal/_themes/horizon/starship.toml`
- Create: `dotfiles/terminal/_themes/horizon/fastfetch/config.jsonc`, `…/fastfetch/live-art` (`{{live}}`)
- Modify: `tests/smoke.sh` (painter end-to-end check for horizon)

**Interfaces:**
- Consumes: `artlib` (`Mode`, `Palette`, `SystemStats`, `PaintContext`, `Painted`, `write_text_atomic`), paint.py contract, `{{live}}` (Tasks 2–3).
- Produces: `sky.py` — `@dataclass(frozen=True) class Location(lat: float, lon: float, place: str)`; `location_from_env(env: Mapping[str, str]) -> tuple[Location, str | None]` (second item = warning text for an invalid override); `sun_position(when: datetime, loc: Location) -> tuple[float, float]` (altitude°, azimuth°); `sun_times(day: date, loc: Location, tz: tzinfo) -> SunTimes` (`sunrise, sunset, solar_noon: datetime`); `moon_position(when, loc) -> tuple[float, float]`; `moon_illumination(when) -> tuple[float, bool]` (fraction lit, waxing); `sky_state(altitude: float) -> SkyState` (Enum: NIGHT, ASTRONOMICAL, NAUTICAL, CIVIL, GOLDEN, DAY); `bucket_expiry(now: datetime) -> int`; `sun_bar_progress(now, today: SunTimes, tomorrow_sunrise: datetime, yesterday_sunset: datetime) -> tuple[bool, float]` (is_day, 0..1). Constants `SKY_BUCKET_S = 600`, `RIYADH = Location(24.7136, 46.6753, "Riyadh")`, `VIEW_AZIMUTH = (60.0, 300.0)`, `HORIZON_Y = 0.72`, `SKY_SIZE = (792, 540)`.
- Text files written per paint: `sun` (`<sunrise> <sunset> <next sunrise>` epoch s, where "next sunrise" is the next one after now), `place`, `sky`, `almanac`, `moon` (one human line each).

- [ ] **Step 1: Failing `test_sky.py`** (all times Asia/Riyadh, `RIYADH`):
  - `equinox_noon_altitude` — 2026-03-20 at solar noon → altitude 65.3 ± 1.0.
  - `solstice_noon_altitude` — 2026-06-21 solar noon → 88.7 ± 1.0.
  - `midnight_is_night` — 2026-11-07 00:00 → `sky_state(...) == SkyState.NIGHT`.
  - `sunrise_before_noon_before_sunset` and `equinox_day_length` — 2026-03-20 day length 12 h 08 m ± 10 m; `june_days_longer_than_december`.
  - `full_moon_is_lit` — 2026-03-03 11:38 UTC → fraction > 0.98; `new_moon_is_dark` — 2026-02-17 12:01 UTC → < 0.02; `waxing_before_full` — 2026-02-27 → waxing True.
  - `full_moon_opposes_sun` — 2026-03-03 00:30 local → moon altitude > 30; 2026-03-03 12:00 local → moon altitude < 0.
  - `sky_state_thresholds` — −20 NIGHT, −15 ASTRONOMICAL, −9 NAUTICAL, −3 CIVIL, 3 GOLDEN, 30 DAY.
  - `bucket_expiry_is_next_boundary` — 14:03:20 → epoch of 14:10:00; exactly 14:10:00 → 14:20:00.
  - `night_progress_spans_midnight` — 2026-11-07 23:00 and 2026-11-08 03:00 are both night with progress in (0, 1), the 03:00 value larger; progress at sunset ≈ 0 and at next sunrise ≈ 1.
  - `invalid_latlon_override_warns_and_defaults` — `{"DCLI_HORIZON_LATLON": "north"}` → `RIYADH`, warning mentions `DCLI_HORIZON_LATLON`; `{"DCLI_HORIZON_LATLON": "51.5,-0.12", "DCLI_HORIZON_PLACE": "London"}` → that location, no warning.
- [ ] **Step 2: Run** → FAIL. **Step 3:** implement `sky.py`. **Step 4:** PASS.
- [ ] **Step 5: Failing `test_horizon.py`** (fixed `now`, fixture palette/stats, temp `out_dir`): `still_writes_one_frame_png` (Pillow reads `n_frames == 1`, size `SKY_SIZE`, ≤ 500 KB), `full_writes_animated_png` (`n_frames` 12–16, `is_animated`, ≤ 2 MB, loop 0), `writes_text_files` (`sun` has 3 integers with sunrise < sunset; `almanac` mentions sunrise and sunset times), `expires_is_bucket_end`, `night_sky_is_darker_than_noon` (mean luminance of the top 20 % of a 00:00 frame < that of a 12:00 frame), `same_day_same_dunes` (bottom 15 % rows identical between 10:00 and 10:20 stills… compare ridge silhouettes, not colours: alpha/mask of the ground layer), `still_paints_within_budget` (wall time < 0.3 s for `Mode.STILL`, after a warm-up call).
- [ ] **Step 6: Run** → FAIL. **Step 7:** implement `horizon.py` (spec § horizon: sky gradient by state, sun disc + glow, moon with lit limb, stars, three dune ridges, FULL-mode twinkle/shimmer, `save_all` APNG `loop=0`). **Step 8:** PASS.
- [ ] **Step 9: Templates.** `config.jsonc`: `"logo": {"type": "iterm", "source": "{{live}}/logo.png", "width": 44, "height": 12, "preserveAspectRatio": true, …}`; modules: `command` modules reading `{{live}}/place`, `sky`, `almanac`, `moon` (`"text": "cat {{live}}/…"`), a rule, then host, kernel, uptime, memory (bar), disk (bar), cpu, packages. `starship.toml`: spec § horizon Prompt; `[custom.sun]` = one `awk` reading `{{live}}/sun` and `systime()`, `when = "test -r {{live}}/sun"`; day bar in a warm gold, night in silver-blue; colours otherwise from palette tokens.
- [ ] **Step 10: Smoke** — `terminal-art: horizon paints a still and a full sky` (fixture HOME wearing `--use theme:horizon`; `paint-terminal-art.sh --still` then `--next`; live symlink resolves; `kind` is `full`; `logo.png` frames > 1). Skip like Task 3 when Pillow is missing.
- [ ] **Step 11: Look at it.** Paint into a scratch state with `paint.py --now <ISO 8601>` at 06:00, 12:00, 17:15, 22:00; snap each greeting with 3 shots 0.5 s apart; confirm the animation moves, the sky reads as that time, nothing is cropped at 80 columns. Iterate until it looks like a picture you would keep.
- [ ] **Step 12: Run** `bash tests/smoke.sh` → pass. Commit — `feat(terminal): horizon theme — the sky over Riyadh, right now`.

---

### Task 5: gallery theme

**Files:**
- Create: `scripts/terminal-art/themes/gallery.py` (entry: `paint`, `REPAINT_AFTER_GREETING = True`)
- Create: `scripts/terminal-art/themes/composition.py` (pure layout model + colour selection + label text; no Pillow)
- Create: `tests/terminal-art/test_composition.py`, `tests/terminal-art/test_gallery.py`
- Create: `dotfiles/terminal/_themes/gallery/starship.toml`, `…/fastfetch/config.jsonc`, `…/fastfetch/live-art`
- Modify: `tests/smoke.sh` (painter end-to-end for gallery)

**Interfaces:**
- Consumes: `artlib` and the paint.py contract (Task 3), `{{live}}` (Task 2).
- Produces: `composition.py` — `class Composition(Enum): SQUARES, GRID, FIELDS, ORBITS, STRIPES`; `class ShapeKind(Enum): RECT, ELLIPSE, ARC, BAND`; `@dataclass(frozen=True) class Shape(kind: ShapeKind, box: tuple[float, float, float, float], color: int, rotation: float = 0.0)` (box in unit canvas coordinates 0..1; `color` an index into the chosen colours, 0 = dominant, 1 = second; later shapes paint over earlier ones); `layout(comp: Composition, stats: SystemStats, rng: random.Random) -> list[Shape]`; `dominant_area(shapes) -> float` and `second_area(shapes) -> float` (unit-canvas area of colour indices 0 and 1 after occlusion — rasterise the model on a coarse grid if needed); `divisions(threads: int) -> int`; `tension(load1: float, threads: int) -> float`; `accents(uptime_s: float) -> int`; `distinct_colors(palette: Palette, n: int) -> list[RGB]`; `title(rng) -> str`; `credit(stats, year: int) -> str`; `note(comp, stats, when: datetime) -> str`; `accession(when: datetime, sequence: int) -> str`. Constants `CANVAS_SIZE = (720, 720)`, `MIN_COLOR_DISTANCE = 48`.
- Text files per paint: `title`, `credit`, `note`, `accession`. Sequence persisted in `ctx.state_dir/sequence` via `write_text_atomic`.

- [ ] **Step 1: Failing `test_composition.py`:**
  - `divisions_clamp` — threads 1→2, 16→4, 64→6.
  - `accents_clamp` — 0 s→1, 5 h→5, 30 h→12.
  - `tension_range` — load 0→0.0, load ≥ threads→1.0.
  - `dominant_area_tracks_memory` — for every `Composition`, with `mem_used_fraction` 0.25 / 0.6, `dominant_area(layout(...))` within ± 0.03 of it (seeds 1..5).
  - `second_area_tracks_disk` — same for `disk_used_fraction`, ± 0.05, where the composition has room (document any composition that caps it and assert the cap).
  - `distinct_colors_are_distinct` — with glyph's palette (`primary #d71921`, `secondary`/`tertiary` both `#8c8c8c`, `outline #2a2a2a`) and caelestia's (`#f9b7a3 #e7bdb1 #ffebcc …`), every pair of `distinct_colors(p, 4)` is ≥ `MIN_COLOR_DISTANCE` apart.
  - `title_shape` — matches `^[A-Z][a-z]+ for a [A-Z][a-z]+ [A-Z][a-z]+, No\. \d+$` and is deterministic per seed.
  - `note_states_real_number` — with memory 41 % the note contains `41%`; length ≤ 104.
  - `accession_format` — 2026-11-07, sequence 423 → `2026.311.0423`.
- [ ] **Step 2: Run** → FAIL. **Step 3:** implement `composition.py`. **Step 4:** PASS.
- [ ] **Step 5: Failing `test_gallery.py`:** `writes_png_and_label` (720×720 RGBA, ≤ 400 KB, four text files non-empty), `corners_are_transparent`, `sequence_increments_per_painting` (two paints → accessions end `.0001`, `.0002`), `expires_never`, `consecutive_paintings_differ`, `paints_within_budget` (< 0.3 s).
- [ ] **Step 6: Run** → FAIL. **Step 7:** implement `gallery.py` (rasterise shapes with Pillow; canvas texture; mat; thin frame; soft shadow; transparent margin). **Step 8:** PASS.
- [ ] **Step 9: Templates.** `config.jsonc`: `"logo": {"type": "iterm", "source": "{{live}}/logo.png", "width": 28, "height": 12, "preserveAspectRatio": true, …}`; label modules per spec § gallery Greeting (`command` modules reading `{{live}}/title|credit|note|accession`; native modules for the facts with label-style keys). `starship.toml` per spec § gallery Prompt, swatches from `{{primary}} {{secondary}} {{tertiary}}`; dim text `{{secondary}}` (not `{{outline}}`, invisible on glyph's black).
- [ ] **Step 10: Smoke** — `terminal-art: gallery paints a new piece every greeting` (two `--next` runs → different `accession`).
- [ ] **Step 11: Look at it.** Snap greetings with the palettes of caelestia, glyph and noctalia (render the theme per shell with `preview-terminal-themes.sh --variant theme:gallery <shell>` or a fixture state) and at least one of each composition. Iterate until each could hang on a wall.
- [ ] **Step 12: Run** `bash tests/smoke.sh` → pass. Commit — `feat(terminal): gallery theme — the machine as a modernist painting`.

---

### Task 6: docs, ideas, final gates

**Files:**
- Modify (worktree, committed): `docs/ARCHITECTURE.md` (§ Terminal, step 13), `docs/NOTES.md` (live art: WezTerm-only pictures, `paint.log`, Pillow), `README.md` if it lists terminal commands (grep `apply-terminal-theme`).
- Modify (main checkout, git-ignored): `/home/awhss/.config/dcli/devfiles/doc/ui-ux-design.md` (§ terminal: the three themes), `workflow.md` (commands), `project-structure.md` (`_themes/`, `scripts/terminal-art/`, `paint-terminal-art.sh`, `tests/terminal-art/`), `system-design.md` (live-art protocol: generations, `expires`/`kind`, lock, log, exit codes; state files `state/terminal/theme`, `state/terminal/live/`), `/home/awhss/.config/dcli/AGENTS.md` (Commands block: `--theme`, `--use theme:<name>`, `paint-terminal-art.sh`).
- Create (main checkout, git-ignored): `/home/awhss/.config/dcli/devfiles/doc/terminal-theme-ideas.md`.

**Interfaces:**
- Consumes: everything above; read the final code, do not document from this plan alone.

- [ ] **Step 1:** Update the committed docs and devfiles docs to match the code as built (names, flags, paths, exit codes).
- [ ] **Step 2:** Write `terminal-theme-ideas.md`: one section per unbuilt idea with concept, medium, greeting, prompt, and the technique/risk it would need: demoscene intro (plasma + sine-scroller carrying the stats, APNG), specimen plate (procedural mirror-symmetric insect from the hostname, Latin binomial, collection label), tarot of the day (date-seeded arcana, stats as the card's reading), uptime bonsai (L-system tree that grows with uptime, seasons from the date), heartbeat prompt (EKG trace that flatlines on a failed command), orrery (real planet positions for today), plus any idea the earlier tasks' reports recorded. Also note the follow-ups found while building (e.g. sixel fallback for foot, a theme picker in the shell switcher).
- [ ] **Step 3:** From the main checkout run `node devfiles/tools/build-docs.mjs` → no errors.
- [ ] **Step 4:** In the worktree run `bash tests/smoke.sh` → `smoke: all checks passed`; `shellcheck scripts/*.sh scripts/lib/*.sh` clean; `for s in $(… KNOWN …); do DCLI_HYPRMOD_SHELL=$s Hyprland --verify-config -c ~/.config/hypr/hyprland.lua; done` is **not** needed (no Hyprland config changed) — state that in the report.
- [ ] **Step 5:** Commit the worktree docs — `docs(terminal): themes layer, live art, horizon / gallery / transit`.
