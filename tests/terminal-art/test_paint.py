"""Unit tests for paint.py: policy, lock, generations and the failure log.

Every test paints with an in-memory fake theme module into a temp live dir, so
nothing here needs Pillow or touches the real state/terminal/live.

Run: PYTHONPATH=scripts/terminal-art python3 -m unittest discover -s tests/terminal-art -p 'test_*.py'
"""

import contextlib
import fcntl
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import types
import unittest
from collections.abc import Callable
from datetime import datetime, timedelta
from pathlib import Path

import paint
from artlib import NEVER_EXPIRES, Mode, PaintContext, Painted, Palette, SystemStats
from paint import (
    PAINT_LOG_KEEP,
    Outcome,
    PaintError,
    Request,
    UsageError,
    load_theme,
    log_failure,
    main,
    parse_now,
    run,
)

PALETTE_JSON = {
    "background": "#111318",
    "surface": "#111318",
    "surfaceContainer": "#1d2024",
    "surfaceVariant": "#43474e",
    "text": "#e2e2e9",
    "primary": "#a8c8ff",
    "onPrimary": "#062e6f",
    "secondary": "#bec6dc",
    "tertiary": "#ddbce0",
    "error": "#ffb4ab",
    "outline": "#8d9199",
}
PALETTE = Palette.from_json(json.dumps(PALETTE_JSON))
OTHER_PALETTE = Palette.from_json(json.dumps(PALETTE_JSON | {"primary": "#d71921"}))
STATS = SystemStats(
    hostname="fixturehost",
    kernel="6.18.0-fixture",
    os_name="Fixture Linux",
    mem_total_kib=32000000,
    mem_available_kib=8000000,
    load1=1.5,
    threads=16,
    uptime_s=3600.5,
    disk_total_b=1000,
    disk_free_b=400,
)
NOW = datetime(2026, 11, 7, 14, 3, 20).astimezone()
LIFETIME_S = 600
GENERATION = re.compile(r"^\.fake\.\d+$")
OLD_ENTRY_LINES = 5
PROBE_THEME = (
    "from artlib import NEVER_EXPIRES, Painted\n"
    "REPAINT_AFTER_GREETING = True\n"
    "def paint(ctx):\n"
    "    (ctx.out_dir / 'logo.png').write_bytes(b'png')\n"
    "    return Painted(expires=NEVER_EXPIRES)\n"
)


class FakeTheme:
    """A theme module in memory: records each paint, writes a stand-in logo."""

    def __init__(
        self,
        *,
        repaint_after_greeting: bool = False,
        lifetime_s: int = LIFETIME_S,
        error: Exception | None = None,
        draws_logo: bool = True,
    ) -> None:
        self.contexts: list[PaintContext] = []
        self.lifetime_s = lifetime_s
        self.error = error
        self.draws_logo = draws_logo
        self.module = types.ModuleType("themes.fake")
        vars(self.module).update(REPAINT_AFTER_GREETING=repaint_after_greeting, paint=self.paint)

    def paint(self, ctx: PaintContext) -> Painted:
        self.contexts.append(ctx)
        if self.error is not None:
            raise self.error
        if self.draws_logo:
            (ctx.out_dir / "logo.png").write_bytes(b"\x89PNG fake " + ctx.mode.value.encode())
        expires = NEVER_EXPIRES if self.lifetime_s < 0 else int(ctx.now.timestamp()) + self.lifetime_s
        return Painted(expires=expires)


class PaintTestCase(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.live_dir = Path(tmp.name) / "live"
        self.live = self.live_dir / "fake"
        self.log = self.live_dir / "paint.log"

    def paint(
        self,
        theme: FakeTheme,
        request: Request,
        *,
        at: datetime = NOW,
        palette: Palette = PALETTE,
        lock_wait_s: float = 0.0,
    ) -> Outcome:
        return run(theme.module, self.live, request, palette, at, STATS, lock_wait_s)

    def generations(self) -> list[str]:
        return sorted(p.name for p in self.live_dir.iterdir() if GENERATION.match(p.name))

    def leftovers(self) -> list[str]:
        return sorted(p.name for p in self.live_dir.iterdir() if p.name.endswith((".tmp", ".link")))

    def kind(self) -> str:
        return (self.live / "kind").read_text().strip()

    def expires(self) -> int:
        return int((self.live / "expires").read_text())

    def hold_lock(self) -> None:
        self.live_dir.mkdir(parents=True, exist_ok=True)
        holder = self.enterContext(open(self.live_dir / "fake.lock", "a"))
        fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)


class PolicyTest(PaintTestCase):
    def test_still_paints_when_missing(self) -> None:
        theme = FakeTheme()
        self.assertIs(self.paint(theme, Request.STILL), Outcome.PAINTED)
        self.assertTrue(self.live.is_symlink())
        self.assertEqual((self.live / "logo.png").read_bytes(), b"\x89PNG fake still")
        self.assertEqual(self.kind(), "still")
        self.assertEqual(self.expires(), int(NOW.timestamp()) + LIFETIME_S)
        self.assertEqual([ctx.mode for ctx in theme.contexts], [Mode.STILL])

    def test_still_is_noop_when_unexpired(self) -> None:
        theme = FakeTheme()
        self.paint(theme, Request.STILL)
        later = NOW + timedelta(seconds=LIFETIME_S - 1)
        self.assertIs(self.paint(theme, Request.STILL, at=later), Outcome.UP_TO_DATE)
        self.assertEqual(len(theme.contexts), 1)

    def test_still_repaints_when_expired(self) -> None:
        theme = FakeTheme()
        self.paint(theme, Request.STILL)
        at_expiry = NOW + timedelta(seconds=LIFETIME_S)
        self.assertIs(self.paint(theme, Request.STILL, at=at_expiry), Outcome.PAINTED)
        self.assertEqual(self.expires(), int(at_expiry.timestamp()) + LIFETIME_S)

    def test_still_keeps_unexpired_full_art(self) -> None:
        theme = FakeTheme()
        self.paint(theme, Request.NEXT)
        self.assertIs(self.paint(theme, Request.STILL), Outcome.UP_TO_DATE)
        self.assertEqual(self.kind(), "full")

    def test_next_upgrades_still_to_full(self) -> None:
        theme = FakeTheme()
        self.paint(theme, Request.STILL)
        self.assertIs(self.paint(theme, Request.NEXT), Outcome.PAINTED)
        self.assertEqual(self.kind(), "full")
        self.assertEqual([ctx.mode for ctx in theme.contexts], [Mode.STILL, Mode.FULL])

    def test_next_is_noop_when_full_and_unexpired(self) -> None:
        theme = FakeTheme()
        self.paint(theme, Request.NEXT)
        self.assertIs(self.paint(theme, Request.NEXT), Outcome.UP_TO_DATE)
        self.assertEqual(len(theme.contexts), 1)

    def test_next_repaints_expired_full_art(self) -> None:
        theme = FakeTheme()
        self.paint(theme, Request.NEXT)
        at_expiry = NOW + timedelta(seconds=LIFETIME_S)
        self.assertIs(self.paint(theme, Request.NEXT, at=at_expiry), Outcome.PAINTED)

    def test_next_always_paints_when_theme_repaints_after_greeting(self) -> None:
        theme = FakeTheme(repaint_after_greeting=True, lifetime_s=-1)
        self.assertIs(self.paint(theme, Request.NEXT), Outcome.PAINTED)
        self.assertIs(self.paint(theme, Request.NEXT), Outcome.PAINTED)
        self.assertEqual(self.expires(), NEVER_EXPIRES)
        # The greeting itself never waits for a new piece: it shows the one painted ahead.
        self.assertIs(self.paint(theme, Request.STILL), Outcome.UP_TO_DATE)

    def test_art_painted_with_another_palette_is_stale(self) -> None:
        theme = FakeTheme()
        self.paint(theme, Request.NEXT)
        self.assertIs(self.paint(theme, Request.NEXT, palette=OTHER_PALETTE), Outcome.PAINTED)
        self.assertIs(self.paint(theme, Request.STILL, palette=PALETTE), Outcome.PAINTED)
        self.assertEqual(theme.contexts[-1].palette, PALETTE)

    def test_art_painted_for_a_later_instant_is_stale(self) -> None:
        # An earlier --now, or the clock stepping back (an RTC kept in local time), must not
        # leave a sky from hours ahead on screen until real time catches up with it.
        theme = FakeTheme()
        later = NOW + timedelta(hours=3)
        self.paint(theme, Request.NEXT, at=later)
        self.assertIs(self.paint(theme, Request.NEXT, at=NOW), Outcome.PAINTED)
        self.assertEqual(int((self.live / "painted_for").read_text()), int(NOW.timestamp()))
        self.paint(theme, Request.STILL, at=later)
        self.assertIs(self.paint(theme, Request.STILL, at=NOW), Outcome.PAINTED)
        self.assertIs(self.paint(theme, Request.STILL, at=NOW), Outcome.UP_TO_DATE)
        self.assertEqual([ctx.now for ctx in theme.contexts], [later, NOW, later, NOW])

    def test_paint_receives_its_context(self) -> None:
        theme = FakeTheme()
        self.paint(theme, Request.STILL)
        self.paint(theme, Request.NEXT)
        first, second = theme.contexts
        self.assertEqual((first.now, first.palette, first.stats), (NOW, PALETTE, STATS))
        self.assertNotEqual(first.out_dir, second.out_dir)
        self.assertEqual(first.state_dir, self.live_dir / ".fake.state")
        self.assertEqual(second.state_dir, first.state_dir)
        self.assertTrue(first.state_dir.is_dir())


class LockTest(PaintTestCase):
    def test_next_skips_while_locked(self) -> None:
        theme = FakeTheme()
        self.hold_lock()
        self.assertIs(self.paint(theme, Request.NEXT), Outcome.BUSY)
        self.assertEqual(theme.contexts, [])
        self.assertFalse(self.live.exists())

    def test_still_gives_up_after_waiting_for_the_lock(self) -> None:
        theme = FakeTheme()
        self.hold_lock()
        wait_s = 0.2
        started = time.monotonic()
        self.assertIs(self.paint(theme, Request.STILL, lock_wait_s=wait_s), Outcome.BUSY)
        self.assertGreaterEqual(time.monotonic() - started, wait_s)
        self.assertEqual(theme.contexts, [])


class GenerationTest(PaintTestCase):
    def test_generation_swap_keeps_previous_and_prunes_older(self) -> None:
        theme = FakeTheme(repaint_after_greeting=True)
        targets = []
        for _ in range(3):
            self.paint(theme, Request.NEXT)
            targets.append(os.readlink(self.live))
        self.assertEqual(len(set(targets)), 3)
        self.assertEqual(self.generations(), sorted(targets[1:]))
        self.assertEqual(os.readlink(self.live), targets[2])
        self.assertEqual(self.leftovers(), [])

    def test_stale_debris_of_a_crashed_paint_is_pruned(self) -> None:
        theme = FakeTheme()
        self.paint(theme, Request.STILL)
        (self.live_dir / ".fake.123.tmp").mkdir()
        (self.live_dir / ".fake.124.link").symlink_to(".fake.123.tmp")
        self.paint(theme, Request.NEXT)
        self.assertEqual(self.leftovers(), [])
        self.assertEqual(len(self.generations()), 2)

    def test_a_real_directory_in_place_of_the_link_is_refused(self) -> None:
        self.live.mkdir(parents=True)
        with self.assertRaisesRegex(PaintError, "not a symlink"):
            self.paint(FakeTheme(), Request.STILL)
        self.assertTrue(self.live.is_dir())


class FailureTest(PaintTestCase):
    def test_paint_failure_keeps_previous_generation(self) -> None:
        self.paint(FakeTheme(), Request.STILL)
        before = os.readlink(self.live)
        with self.assertRaises(PaintError):
            self.paint(FakeTheme(error=RuntimeError("the sky fell")), Request.NEXT)
        self.assertEqual(os.readlink(self.live), before)
        self.assertEqual(self.generations(), [before])
        self.assertEqual(self.leftovers(), [])
        self.assertEqual((self.live / "logo.png").read_bytes(), b"\x89PNG fake still")

    def test_paint_failure_is_logged(self) -> None:
        with self.assertRaisesRegex(PaintError, "the sky fell"):
            self.paint(FakeTheme(error=RuntimeError("the sky fell")), Request.STILL)
        log = self.log.read_text()
        self.assertIn("RuntimeError: the sky fell", log)
        stamp = r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d"
        self.assertRegex(log.splitlines()[0], rf"^{stamp} fake still failed: RuntimeError: the sky fell$")
        self.assertTrue(all(line.startswith("  ") for line in log.splitlines()[1:]))

    def seed_log(self, entries: int) -> None:
        """Old entries of OLD_ENTRY_LINES lines each: a summary, then indented frames."""
        self.live_dir.mkdir(parents=True, exist_ok=True)
        self.log.write_text(
            "".join(
                f"2026-11-01T00:00:00+03:00 fake next failed: RuntimeError: old-{n:03d}\n"
                + "".join(f"  frame {f} of old-{n:03d}\n" for f in range(OLD_ENTRY_LINES - 1))
                for n in range(entries)
            )
        )

    def assert_whole_entries(self, lines: list[str]) -> None:
        self.assertFalse(lines[0].startswith(" "), "the log starts with a summary line")
        for n in {m.group(1) for line in lines if (m := re.search(r"old-(\d{3})", line))}:
            self.assertEqual(sum(f"old-{n}" in line for line in lines), OLD_ENTRY_LINES, f"entry old-{n} is cut")

    def test_log_is_trimmed_to_keep_lines(self) -> None:
        self.seed_log(100)
        with self.assertRaises(PaintError):
            self.paint(FakeTheme(error=ValueError("newest")), Request.NEXT)
        lines = self.log.read_text().splitlines()
        self.assertLessEqual(len(lines), PAINT_LOG_KEEP)
        self.assertGreaterEqual(len(lines), PAINT_LOG_KEEP - (OLD_ENTRY_LINES - 1))
        self.assertFalse(any("old-000" in line for line in lines))
        self.assert_whole_entries(lines)
        summaries = [line for line in lines if not line.startswith(" ")]
        self.assertTrue(summaries[-1].endswith("fake next failed: ValueError: newest"))

    def test_log_trim_drops_the_entry_the_cut_lands_in(self) -> None:
        # 500 seeded lines + a 2-line entry (an exception never raised has no frames):
        # the last 200 begin on line 3 of old-060, so its 3 remaining lines go too.
        self.seed_log(100)
        log_failure(self.log, "fake", Request.NEXT, ValueError("newest"))
        lines = self.log.read_text().splitlines()
        self.assertEqual(len(lines), PAINT_LOG_KEEP - 3)
        self.assertTrue(lines[0].endswith("old-061"))
        self.assertFalse(any("old-060" in line for line in lines))
        self.assert_whole_entries(lines)
        self.assertTrue(lines[-2].endswith("fake next failed: ValueError: newest"))
        self.assertEqual(lines[-1], "  ValueError: newest")

    def test_theme_that_draws_no_logo_fails(self) -> None:
        with self.assertRaisesRegex(PaintError, "logo.png"):
            self.paint(FakeTheme(draws_logo=False), Request.STILL)
        self.assertFalse(self.live.exists())
        self.assertEqual(self.leftovers(), [])

    def test_theme_returning_no_painted_fails(self) -> None:
        theme = FakeTheme()
        vars(theme.module)["paint"] = lambda ctx: (ctx.out_dir / "logo.png").write_bytes(b"png")
        with self.assertRaisesRegex(PaintError, "Painted"):
            self.paint(theme, Request.STILL)

    def test_module_that_is_not_a_theme_is_rejected(self) -> None:
        cases: list[tuple[str, Callable[[types.ModuleType], None]]] = [
            ("REPAINT_AFTER_GREETING", lambda m: delattr(m, "REPAINT_AFTER_GREETING")),
            ("REPAINT_AFTER_GREETING", lambda m: setattr(m, "REPAINT_AFTER_GREETING", "yes")),
            ("paint", lambda m: delattr(m, "paint")),
            ("paint", lambda m: setattr(m, "paint", "not callable")),
        ]
        for missing, breaks in cases:
            theme = FakeTheme()
            breaks(theme.module)
            with self.subTest(missing=missing), self.assertRaisesRegex(PaintError, missing):
                self.paint(theme, Request.STILL)
        self.assertFalse(self.live.exists())


class LoadThemeTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.themes = Path(tmp.name) / "themes"
        self.themes.mkdir()
        (self.themes / "probe.py").write_text(PROBE_THEME)
        self.addCleanup(sys.modules.pop, "themes.probe", None)

    def test_loads_a_theme_module_by_name(self) -> None:
        module = load_theme("probe", self.themes)
        self.assertEqual(module.__name__, "themes.probe")
        self.assertIs(module.REPAINT_AFTER_GREETING, True)

    def test_rejects_names_that_are_not_theme_names(self) -> None:
        for name in ("", "Probe", "9lives", "../probe", "pro-be", "probe.py"):
            with self.subTest(name=name), self.assertRaisesRegex(UsageError, "theme name"):
                load_theme(name, self.themes)

    def test_rejects_a_theme_with_no_module(self) -> None:
        with self.assertRaisesRegex(UsageError, "no live-art theme 'absent'"):
            load_theme("absent", self.themes)


class CommandLineTest(unittest.TestCase):
    PAINT_PY = Path(paint.__file__)

    def cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        # As paint-terminal-art.sh runs it, plus -B: -E ignores PYTHONDONTWRITEBYTECODE,
        # and a test run must not leave bytecode in the repo.
        return subprocess.run(
            [sys.executable, "-E", "-s", "-B", str(self.PAINT_PY), *args], capture_output=True, text=True, check=False
        )

    def test_usage_errors_exit_2(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            live = str(Path(tmp) / "live" / "probe")
            base = ["--theme", "probe", "--live", live, "--palette", json.dumps(PALETTE_JSON)]
            cases = {
                "no mode": base,
                "bad mode": [*base, "--mode", "sometimes"],
                "bad clock": [*base, "--mode", "still", "--now", "teatime"],
                "bad theme name": ["--theme", "Bad-Name", "--live", live, "--mode", "still", "--palette", "{}"],
                "unknown theme": ["--theme", "nosuchtheme", "--live", live, "--mode", "still", "--palette", "{}"],
            }
            for case, args in cases.items():
                with self.subTest(case=case):
                    result = self.cli(*args)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertTrue(result.stderr.strip())
            self.assertFalse((Path(tmp) / "live").exists())

    def test_usage_text_documents_the_clock_override(self) -> None:
        result = self.cli("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("--now", result.stdout)
        self.assertIn("ISO 8601", result.stdout)

    def test_clock_override_prints_the_outcome(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            themes = Path(tmp) / "themes"
            themes.mkdir()
            (themes / "probe.py").write_text(PROBE_THEME)
            self.addCleanup(sys.modules.pop, "themes.probe", None)
            argv = ["--theme", "probe", "--live", str(Path(tmp) / "live" / "probe"), "--mode", "still"]
            argv += ["--palette", json.dumps(PALETTE_JSON)]

            def paint_at(*now: str) -> tuple[int, str]:
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    status = main([*argv, *now], themes_dir=themes)
                return status, out.getvalue()

            night = parse_now("2026-11-07T22:00:00").isoformat()
            painted = (0, f"paint: probe still for {night}: painted\n")
            self.assertEqual(paint_at("--now", "2026-11-07T22:00:00"), painted)
            self.assertRegex(paint_at("--now", "2026-11-07T22:00:00")[1], r": up-to-date\n$")
            self.assertRegex(paint_at("--now", "2026-11-07T06:00:00")[1], r"T06:00:00.*: painted\n$")
            self.assertEqual(paint_at(), (0, ""), "without --now nothing prints")

    def test_parse_now_is_local_and_aware(self) -> None:
        utc = datetime.fromisoformat("2026-11-07T06:00:00+00:00")
        aware = parse_now("2026-11-07T06:00:00+00:00")
        self.assertEqual(aware, utc)
        self.assertEqual(aware.utcoffset(), utc.astimezone().utcoffset())
        naive = parse_now("2026-11-07T06:00:00")
        self.assertIsNotNone(naive.tzinfo)
        self.assertEqual((naive.hour, naive.minute), (6, 0))
        with self.assertRaises(ValueError):
            parse_now("teatime")


if __name__ == "__main__":
    unittest.main()
