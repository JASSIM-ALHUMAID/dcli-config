"""Shared types and helpers for live-art themes (the terminal greeting's painted logo).

Live art is painted AHEAD of the greeting by paint.py into a fresh generation
directory, then swapped in atomically; fish only ever shows what is on disk.

Theme module contract (checked by paint.py before every paint):
    themes/<name>.py, loaded as ``themes.<name>`` (``scripts/terminal-art`` is on
    sys.path, ``themes`` is a namespace package: helpers import as
    ``from themes.<helper> import …``, engine types as ``from artlib import …``).
    It defines
        REPAINT_AFTER_GREETING: bool
            True: ``--next`` paints a new piece after every greeting, whatever
            the current art (gallery). False: only missing, expired or
            other-palette art is repainted (horizon).
        paint(ctx: PaintContext) -> Painted
            Draws ``logo.png`` and the theme's text files into ``ctx.out_dir``
            (a private, empty directory) and returns when the art expires.
            ``ctx.mode`` is STILL for the quick first frame a waiting greeting
            needs, FULL for the complete version painted in the background.
            Keep anything that must outlive a generation (a sequence number)
            in ``ctx.state_dir``, written with write_text_atomic. Raise on
            failure: paint.py logs it and keeps the previous art.
    paint.py itself writes ``expires``, ``kind`` and ``palette`` beside them.

Pillow is imported only by the theme modules that draw; nothing here needs it.
"""

import json
import os
import re
from dataclasses import dataclass, fields
from datetime import datetime
from enum import Enum
from pathlib import Path

RGB = tuple[int, int, int]

# Epoch seconds that never come (the largest 32-bit time): art that is current until replaced.
NEVER_EXPIRES = 2**31 - 1

_HEX_COLOUR = re.compile(r"#[0-9a-fA-F]{6}")
_DEFAULT_OS_NAME = "Linux"


class Mode(Enum):
    """What a paint must produce: a quick single frame, or the complete art."""

    STILL = "still"
    FULL = "full"


def _json_key(field_name: str) -> str:
    head, *rest = field_name.split("_")
    return head + "".join(part.title() for part in rest)


@dataclass(frozen=True)
class Palette:
    """The running shell's colours (lib/palette.sh's normalised object), as RGB.

    Field names are the snake_case forms of the JSON keys (``onPrimary`` →
    ``on_primary``), so a theme reads ``ctx.palette.surface_variant``.
    """

    background: RGB
    surface: RGB
    surface_container: RGB
    surface_variant: RGB
    text: RGB
    primary: RGB
    on_primary: RGB
    secondary: RGB
    tertiary: RGB
    error: RGB
    outline: RGB

    @classmethod
    def from_json(cls, text: str) -> "Palette":
        """Parse ``{"background": "#rrggbb", …}``.

        Raises ValueError naming the first missing or invalid key.
        """
        try:
            data = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"palette is not JSON: {exc}") from None
        if not isinstance(data, dict):
            raise ValueError(f"palette is not a JSON object: {text[:60]!r}")
        colours: dict[str, RGB] = {}
        for field in fields(cls):
            key = _json_key(field.name)
            if key not in data:
                raise ValueError(f"palette has no '{key}'")
            value = data[key]
            if not isinstance(value, str) or not _HEX_COLOUR.fullmatch(value):
                raise ValueError(f"palette '{key}' is not a #rrggbb colour: {value!r}")
            colours[field.name] = (int(value[1:3], 16), int(value[3:5], 16), int(value[5:7], 16))
        return cls(**colours)

    def to_json(self) -> str:
        """The inverse of from_json: compact JSON with the palette's camelCase keys."""
        return json.dumps(
            {_json_key(field.name): "#{:02x}{:02x}{:02x}".format(*getattr(self, field.name)) for field in fields(self)},
            separators=(",", ":"),
        )


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _first_float(path: Path) -> float:
    text = _read_text(path)
    try:
        return float(text.split()[0])
    except (IndexError, ValueError):
        raise ValueError(f"{path}: expected a number first, got {text[:40]!r}") from None


def _meminfo_kib(path: Path, *keys: str) -> list[int]:
    values: dict[str, int] = {}
    for line in _read_text(path).splitlines():
        key, _, rest = line.partition(":")
        amount = rest.split()
        if amount and amount[0].isdigit():
            values[key.strip()] = int(amount[0])
    missing = [key for key in keys if key not in values]
    if missing:
        raise ValueError(f"{path}: no {', '.join(missing)}")
    return [values[key] for key in keys]


def _cpu_threads(path: Path) -> int:
    threads = sum(1 for line in _read_text(path).splitlines() if re.match(r"cpu\d+\s", line))
    if threads == 0:
        raise ValueError(f"{path}: no per-CPU lines")
    return threads


def _os_name(path: Path) -> str:
    try:
        text = _read_text(path)
    except FileNotFoundError:
        return _DEFAULT_OS_NAME
    release: dict[str, str] = {}
    for line in text.splitlines():
        key, sep, value = line.partition("=")
        if sep:
            value = value.strip()
            quote = value[:1]
            if quote in ('"', "'") and value[1:].endswith(quote):
                value = re.sub(r"\\(.)", r"\1", value[1:-1])
            release[key.strip()] = value
    return release.get("PRETTY_NAME") or release.get("NAME") or _DEFAULT_OS_NAME


@dataclass(frozen=True)
class SystemStats:
    """A snapshot of the machine, for themes whose art encodes it."""

    hostname: str
    kernel: str
    os_name: str
    mem_total_kib: int
    mem_available_kib: int
    load1: float
    threads: int
    uptime_s: float
    disk_total_b: int
    disk_free_b: int

    @property
    def mem_used_fraction(self) -> float:
        """Memory in use (total minus available) as 0..1."""
        if self.mem_total_kib <= 0:
            return 0.0
        return min(1.0, max(0.0, 1 - self.mem_available_kib / self.mem_total_kib))

    @property
    def disk_used_fraction(self) -> float:
        """Disk not available to the user (so reserved blocks count as used) as 0..1."""
        if self.disk_total_b <= 0:
            return 0.0
        return min(1.0, max(0.0, 1 - self.disk_free_b / self.disk_total_b))

    @classmethod
    def read(
        cls,
        proc: Path = Path("/proc"),
        disk: Path = Path("/"),
        os_release: Path = Path("/etc/os-release"),
    ) -> "SystemStats":
        """Read everything from ``proc`` (and statvfs of ``disk``), so a fixture tree can stand in.

        Raises OSError for an unreadable file and ValueError naming what a file lacks.
        """
        mem_total, mem_available = _meminfo_kib(proc / "meminfo", "MemTotal", "MemAvailable")
        disk_stat = os.statvfs(disk)
        return cls(
            hostname=_read_text(proc / "sys" / "kernel" / "hostname").strip(),
            kernel=_read_text(proc / "sys" / "kernel" / "osrelease").strip(),
            os_name=_os_name(os_release),
            mem_total_kib=mem_total,
            mem_available_kib=mem_available,
            load1=_first_float(proc / "loadavg"),
            threads=_cpu_threads(proc / "stat"),
            uptime_s=_first_float(proc / "uptime"),
            disk_total_b=disk_stat.f_blocks * disk_stat.f_frsize,
            disk_free_b=disk_stat.f_bavail * disk_stat.f_frsize,
        )


@dataclass(frozen=True)
class PaintContext:
    """Everything a theme's paint() gets; it writes only into ``out_dir`` and ``state_dir``."""

    out_dir: Path
    mode: Mode
    # Timezone-aware, in the local zone (paint.py --now overrides the clock).
    now: datetime
    palette: Palette
    stats: SystemStats
    # Persistent across generations: live/.<theme>.state/, created by paint.py.
    state_dir: Path


@dataclass(frozen=True)
class Painted:
    """What a paint returns: the epoch second from which the art is stale (NEVER_EXPIRES: never)."""

    expires: int


def write_text_atomic(path: Path, text: str) -> None:
    """Replace ``path`` with ``text`` (UTF-8) so a reader sees the old file or the new, never half.

    The temp name carries the pid: two processes never share one, and a stale
    one left by a dead process of the same pid is simply overwritten. No fsync:
    after a crash the worst case is an empty file, which every reader treats as
    stale and repaints.
    """
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        tmp.write_text(text, encoding="utf-8")
        os.replace(tmp, path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
