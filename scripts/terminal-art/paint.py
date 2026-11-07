"""Paint a live-art theme ahead of the greeting, into atomically swapped generations.

usage (paint-terminal-art.sh resolves every argument; run that, not this):
    python3 -E -s paint.py --theme <name> --live <symlink path> --mode still|next
                           --palette <json> [--now <ISO 8601>]

Layout of the live dir (state/terminal/live/):
    <theme>             symlink to the current generation (what {{live}} names)
    .<theme>.<ns>/      a generation: logo.png and the theme's text files, plus
                        expires (epoch s), kind (still|full), palette (JSON),
                        painted_for (the epoch s the art depicts)
    .<theme>.state/     the theme's own persistent state (PaintContext.state_dir)
    <theme>.lock        flock: one paint per theme at a time
    paint.log           failures only, newest last, at most PAINT_LOG_KEEP lines

Policy. Art is current when it exists, is unexpired, was painted with this
palette and depicts no later moment than now: an earlier --now, or the clock
stepping back, repaints instead of keeping a picture of hours ahead. --mode
still paints a STILL frame only when the art is not current. --mode next
paints the FULL art unless current art is already full; a theme with
REPAINT_AFTER_GREETING repaints on every next. A still waits up to
STILL_LOCK_WAIT_S for a running paint (whose art is then usually current); a
next skips at once, so terminals opening together never queue up paints.

A paint writes .<theme>.<ns>.tmp, renames it to .<theme>.<ns>, then swaps the
symlink with a temp link and one rename: a reader resolves the old generation
or the new, never a partial one. The previous generation is kept (a reader may
still have it open); older ones and debris of crashed paints are deleted.

Exit status: 0 painted, up to date or busy; 1 failed (logged, old art kept);
2 usage. Nothing is printed on success, except with --now: then the run says
what it did ("paint: <theme> <request> for <time>: painted|up-to-date|busy"),
so a screenshot run that changed nothing is visible.

Log entry: "<ISO 8601 time> <theme> <still|next> failed: <Type>: <message>",
then the traceback with every line indented two spaces (doctor.sh reads the
unindented summary lines).
"""

import argparse
import fcntl
import importlib.util
import os
import re
import shutil
import sys
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from pathlib import Path
from types import ModuleType
from typing import IO

from artlib import Mode, PaintContext, Painted, Palette, SystemStats

THEMES_DIR = Path(__file__).resolve().parent / "themes"
THEME_NAME = re.compile(r"[a-z][a-z0-9_]*")

# A still blocks a waiting greeting; a next runs in the background and must not pile up.
STILL_LOCK_WAIT_S = 2.0
NEXT_LOCK_WAIT_S = 0.0
LOCK_POLL_S = 0.05

PAINT_LOG_NAME = "paint.log"
PAINT_LOG_KEEP = 200
LOG_INDENT = "  "

LOGO_FILE = "logo.png"
EXPIRES_FILE = "expires"
KIND_FILE = "kind"
PALETTE_FILE = "palette"
PAINTED_FOR_FILE = "painted_for"

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_USAGE = 2


class Request(Enum):
    """What the caller wants: art for this greeting, or the best art for the next one."""

    STILL = "still"
    NEXT = "next"


class Outcome(Enum):
    """What a run did; every one of them exits 0."""

    PAINTED = "painted"
    UP_TO_DATE = "up-to-date"
    BUSY = "busy"


class UsageError(Exception):
    """A bad command line or theme name: exit 2, nothing logged."""


class PaintError(Exception):
    """A paint failed: the detail is in paint.log and the previous art is still shown."""


@dataclass(frozen=True)
class Generation:
    """The art the live symlink shows now."""

    kind: Mode
    expires: int
    palette: Palette
    painted_for: int


def read_generation(live: Path) -> Generation | None:
    """The current art, or None when there is none to show (missing, half-written, unreadable)."""
    try:
        if not (live / LOGO_FILE).is_file():
            return None
        return Generation(
            kind=Mode((live / KIND_FILE).read_text().strip()),
            expires=int((live / EXPIRES_FILE).read_text()),
            palette=Palette.from_json((live / PALETTE_FILE).read_text()),
            painted_for=int((live / PAINTED_FOR_FILE).read_text()),
        )
    except (OSError, ValueError):
        return None


def mode_to_paint(
    request: Request, current: Generation | None, palette: Palette, now_s: int, repaint_after_greeting: bool
) -> Mode | None:
    """The policy: which mode to paint, or None when the current art will do."""
    if current is None or current.expires <= now_s or current.palette != palette or current.painted_for > now_s:
        return Mode.STILL if request is Request.STILL else Mode.FULL
    if request is Request.STILL:
        return None
    if repaint_after_greeting or current.kind is Mode.STILL:
        return Mode.FULL
    return None


# ── Themes ───────────────────────────────────────────────────────────────────
def load_theme(name: str, themes_dir: Path = THEMES_DIR) -> ModuleType:
    """Import themes/<name>.py as ``themes.<name>``.

    Loaded from its file, not through sys.path, so another ``themes`` package on
    the path can never stand in for it. Raises UsageError for a bad or unknown
    name; whatever the module raises while importing propagates.
    """
    if not THEME_NAME.fullmatch(name):
        raise UsageError(f"not a theme name: {name!r} (want {THEME_NAME.pattern})")
    path = themes_dir / f"{name}.py"
    if not path.is_file():
        raise UsageError(f"no live-art theme '{name}' ({path} does not exist)")
    module_name = f"themes.{name}"
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    # Registered before it runs: dataclasses look a class's module up in sys.modules.
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
    except BaseException:
        del sys.modules[module_name]
        raise
    return module


def theme_contract(theme: ModuleType) -> tuple[bool, Callable[[PaintContext], object]]:
    """(REPAINT_AFTER_GREETING, paint) of a theme module; TypeError for anything else (a helper module)."""
    name = getattr(theme, "__name__", repr(theme))
    repaint_after_greeting = getattr(theme, "REPAINT_AFTER_GREETING", None)
    paint = getattr(theme, "paint", None)
    if not isinstance(repaint_after_greeting, bool):
        raise TypeError(
            f"{name} is not a live-art theme: REPAINT_AFTER_GREETING must be a bool, not {repaint_after_greeting!r}"
        )
    if not callable(paint):
        raise TypeError(f"{name} is not a live-art theme: it has no callable paint(ctx)")
    return repaint_after_greeting, paint


# ── Generations ──────────────────────────────────────────────────────────────
def _acquire(lock: IO[str], wait_s: float) -> bool:
    deadline = time.monotonic() + wait_s
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except BlockingIOError:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            time.sleep(min(LOCK_POLL_S, remaining))


def _discard(path: Path) -> None:
    # Best effort on a path already failing: the next paint's prune deletes what is left.
    shutil.rmtree(path, ignore_errors=True)


def _paint_generation(
    paint: Callable[[PaintContext], object],
    live: Path,
    mode: Mode,
    palette: Palette,
    now: datetime,
    stats: SystemStats,
) -> Path:
    generation = live.with_name(f".{live.name}.{time.time_ns()}")
    staging = generation.with_name(f"{generation.name}.tmp")
    state_dir = live.with_name(f".{live.name}.state")
    state_dir.mkdir(exist_ok=True)
    staging.mkdir()
    try:
        painted = paint(
            PaintContext(out_dir=staging, mode=mode, now=now, palette=palette, stats=stats, state_dir=state_dir)
        )
        if not isinstance(painted, Painted) or type(painted.expires) is not int:
            raise TypeError(f"paint() must return Painted(expires=<epoch s>), not {painted!r}")
        if not (staging / LOGO_FILE).is_file():
            raise FileNotFoundError(f"paint() drew no {LOGO_FILE}")
        (staging / EXPIRES_FILE).write_text(f"{painted.expires}\n")
        (staging / KIND_FILE).write_text(f"{mode.value}\n")
        (staging / PALETTE_FILE).write_text(f"{palette.to_json()}\n")
        (staging / PAINTED_FOR_FILE).write_text(f"{int(now.timestamp())}\n")
        staging.rename(generation)
    except BaseException:
        _discard(staging)
        raise
    return generation


def _swap(live: Path, generation: Path) -> None:
    link = generation.with_name(f"{generation.name}.link")
    os.symlink(generation.name, link)
    try:
        os.replace(link, live)
    except BaseException:
        link.unlink(missing_ok=True)
        raise


def _prune(live: Path, keep: set[str]) -> None:
    debris = re.compile(rf"\.{re.escape(live.name)}\.\d+(?:\.tmp|\.link)?")
    failures: list[str] = []
    with os.scandir(live.parent) as entries:
        for entry in entries:
            if entry.name in keep or not debris.fullmatch(entry.name):
                continue
            try:
                if entry.is_dir(follow_symlinks=False):
                    shutil.rmtree(entry.path)
                else:
                    os.unlink(entry.path)
            except OSError as exc:
                failures.append(f"{entry.name}: {exc.strerror or exc}")
    if failures:
        raise OSError(f"could not delete old art: {'; '.join(failures)}")


def _run(
    theme: ModuleType,
    live: Path,
    request: Request,
    palette: Palette,
    now: datetime,
    stats: SystemStats,
    lock_wait_s: float,
) -> Outcome:
    repaint_after_greeting, paint = theme_contract(theme)
    if live.exists() and not live.is_symlink():
        raise FileExistsError(f"{live} is not a symlink; move it aside and the next paint recreates it")
    live.parent.mkdir(parents=True, exist_ok=True)
    with open(live.with_name(f"{live.name}.lock"), "a") as lock:
        if not _acquire(lock, lock_wait_s):
            return Outcome.BUSY
        mode = mode_to_paint(request, read_generation(live), palette, int(now.timestamp()), repaint_after_greeting)
        if mode is None:
            return Outcome.UP_TO_DATE
        previous = os.path.basename(os.readlink(live)) if live.is_symlink() else None
        generation = _paint_generation(paint, live, mode, palette, now, stats)
        try:
            _swap(live, generation)
        except BaseException:
            _discard(generation)
            raise
        _prune(live, {generation.name} if previous is None else {generation.name, previous})
        return Outcome.PAINTED


def run(
    theme: ModuleType,
    live: Path,
    request: Request,
    palette: Palette,
    now: datetime,
    stats: SystemStats,
    lock_wait_s: float,
) -> Outcome:
    """Paint ``theme`` into the generation ``live`` links to, if the policy says so.

    ``now`` must be timezone-aware. Any failure is logged to paint.log beside
    ``live`` and raised as PaintError; the previous art stays linked.
    """
    if now.tzinfo is None:
        raise ValueError("run() needs a timezone-aware now")
    try:
        return _run(theme, live, request, palette, now, stats, lock_wait_s)
    # A theme is arbitrary code: whatever it raises is one more failed paint.
    except Exception as exc:
        summary = log_failure(live.parent / PAINT_LOG_NAME, live.name, request, exc)
        raise PaintError(f"{live.name} {request.value}: {summary}") from exc


# ── Failure log ──────────────────────────────────────────────────────────────
def log_failure(log: Path, theme: str, request: Request, exc: BaseException) -> str:
    """Append ``exc`` with its traceback to ``log``, keep the last PAINT_LOG_KEEP lines; returns the summary.

    The log is shared by every theme, so it is locked while written and
    trimmed. Trimming drops whole entries only, and an entry longer than the
    log keeps its innermost frames. When the log cannot be written, the entry
    goes to stderr instead.
    """
    import traceback  # Only a failure pays for it: start-up is on the greeting's path.

    summary = " ".join(f"{type(exc).__name__}: {exc}".split())
    stamp = datetime.now().astimezone().isoformat(timespec="seconds")
    detail = [f"{LOG_INDENT}{line}\n" for line in "".join(traceback.format_exception(exc)).splitlines()]
    entry = [f"{stamp} {theme} {request.value} failed: {summary}\n", *detail[-(PAINT_LOG_KEEP - 1) :]]
    try:
        log.parent.mkdir(parents=True, exist_ok=True)
        with open(log, "a+", encoding="utf-8") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            handle.writelines(entry)
            handle.seek(0)
            lines = handle.readlines()
            if len(lines) > PAINT_LOG_KEEP:
                kept = lines[-PAINT_LOG_KEEP:]
                while kept[0].startswith(LOG_INDENT):
                    kept.pop(0)
                handle.seek(0)
                handle.truncate()
                handle.writelines(kept)
    except OSError as log_exc:
        print(f"paint: could not write {log}: {log_exc}", file=sys.stderr)
        sys.stderr.writelines(entry)
    return summary


# ── Command line ─────────────────────────────────────────────────────────────
def parse_now(text: str) -> datetime:
    """An ISO 8601 time as an aware local datetime; a time without an offset is local."""
    return datetime.fromisoformat(text).astimezone()


def _now_argument(text: str) -> datetime:
    try:
        return parse_now(text)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not an ISO 8601 time: {text!r}") from None


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="paint.py",
        description="Paint a live-art theme ahead of the terminal greeting (normally run by paint-terminal-art.sh).",
        epilog="Exit status: 0 painted, up to date or busy; 1 failed (logged to paint.log beside the live link); "
        "2 usage.",
    )
    parser.add_argument("--theme", required=True, help="theme module themes/<name>.py; [a-z][a-z0-9_]*")
    parser.add_argument("--live", required=True, type=Path, help="the theme's live symlink, state/terminal/live/<name>")
    parser.add_argument(
        "--mode",
        required=True,
        choices=[request.value for request in Request],
        help="still: a quick frame, only if the art is missing or stale; next: the full art for the next greeting",
    )
    parser.add_argument("--palette", required=True, help="the shell's palette, lib/palette.sh's JSON object")
    parser.add_argument(
        "--now",
        type=_now_argument,
        metavar="TIME",
        help="an ISO 8601 time to paint instead of the clock (screenshots, tests); without an offset it is "
        "local. Prints what the run did: painted, up-to-date or busy",
    )
    return parser


def main(argv: Sequence[str] | None = None, themes_dir: Path = THEMES_DIR) -> int:
    args = _parser().parse_args(argv)
    request = Request(args.mode)
    live: Path = args.live.absolute()
    log = live.parent / PAINT_LOG_NAME
    now: datetime = args.now or datetime.now().astimezone()
    lock_wait_s = STILL_LOCK_WAIT_S if request is Request.STILL else NEXT_LOCK_WAIT_S
    try:
        theme = load_theme(args.theme, themes_dir)
        palette = Palette.from_json(args.palette)
        stats = SystemStats.read()
        outcome = run(theme, live, request, palette, now, stats, lock_wait_s)
    except UsageError as exc:
        print(f"paint: {exc}", file=sys.stderr)
        return EXIT_USAGE
    except PaintError as exc:
        print(f"paint: {exc} (details in {log})", file=sys.stderr)
        return EXIT_FAILED
    # The theme's import, the palette or /proc failed: logged like any failed paint.
    except Exception as exc:
        summary = log_failure(log, args.theme, request, exc)
        print(f"paint: {args.theme} {request.value}: {summary} (details in {log})", file=sys.stderr)
        return EXIT_FAILED
    if args.now is not None:
        print(f"paint: {args.theme} {request.value} for {now.isoformat(timespec='seconds')}: {outcome.value}")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
