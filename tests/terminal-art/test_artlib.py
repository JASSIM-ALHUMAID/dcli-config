"""Unit tests for artlib: the types and helpers every live-art theme shares.

Run: PYTHONPATH=scripts/terminal-art python3 -m unittest discover -s tests/terminal-art -p 'test_*.py'
"""

import json
import tempfile
import unittest
from pathlib import Path

from artlib import Palette, SystemStats, write_text_atomic

PALETTE_JSON = {
    "background": "#111318",
    "surface": "#121417",
    "surfaceContainer": "#1d2024",
    "surfaceVariant": "#43474e",
    "text": "#e2e2e9",
    "primary": "#a8c8ff",
    "onPrimary": "#062e6f",
    "secondary": "#bec6dc",
    "tertiary": "#ddbce0",
    "error": "#FFB4AB",
    "outline": "#8d9199",
}


class PaletteTest(unittest.TestCase):
    def test_palette_from_json_parses_all_keys(self) -> None:
        palette = Palette.from_json(json.dumps(PALETTE_JSON))
        self.assertEqual(
            palette,
            Palette(
                background=(0x11, 0x13, 0x18),
                surface=(0x12, 0x14, 0x17),
                surface_container=(0x1D, 0x20, 0x24),
                surface_variant=(0x43, 0x47, 0x4E),
                text=(0xE2, 0xE2, 0xE9),
                primary=(0xA8, 0xC8, 0xFF),
                on_primary=(0x06, 0x2E, 0x6F),
                secondary=(0xBE, 0xC6, 0xDC),
                tertiary=(0xDD, 0xBC, 0xE0),
                error=(0xFF, 0xB4, 0xAB),
                outline=(0x8D, 0x91, 0x99),
            ),
        )

    def test_palette_from_json_names_missing_key(self) -> None:
        broken = {k: v for k, v in PALETTE_JSON.items() if k != "onPrimary"}
        with self.assertRaisesRegex(ValueError, "onPrimary"):
            Palette.from_json(json.dumps(broken))

    def test_palette_from_json_names_invalid_colour(self) -> None:
        for bad in ("blue", "#12345", "#1234567", 0x123456, None):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "surfaceVariant"):
                Palette.from_json(json.dumps(PALETTE_JSON | {"surfaceVariant": bad}))

    def test_palette_from_json_rejects_what_is_not_an_object(self) -> None:
        for text in ("", "not json", "[]", '"#ffffff"'):
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "palette"):
                Palette.from_json(text)

    def test_palette_round_trips_through_json(self) -> None:
        palette = Palette.from_json(json.dumps(PALETTE_JSON))
        self.assertEqual(Palette.from_json(palette.to_json()), palette)
        self.assertEqual(json.loads(palette.to_json())["onPrimary"], "#062e6f")


class SystemStatsTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.proc = self.root / "proc"
        (self.proc / "sys" / "kernel").mkdir(parents=True)
        (self.proc / "meminfo").write_text(
            "MemTotal:       32000000 kB\nMemFree:         1000000 kB\nMemAvailable:    8000000 kB\n"
        )
        (self.proc / "loadavg").write_text("1.50 1.20 0.90 2/1500 12345\n")
        (self.proc / "uptime").write_text("3600.5 50000.25\n")
        (self.proc / "stat").write_text(
            "cpu  10 0 10 100 0 0 0 0 0 0\n"
            + "".join(f"cpu{n} 1 0 1 10 0 0 0 0 0 0\n" for n in range(4))
            + "intr 12345\nctxt 999\n"
        )
        (self.proc / "sys" / "kernel" / "hostname").write_text("fixturehost\n")
        (self.proc / "sys" / "kernel" / "osrelease").write_text("6.18.0-fixture\n")
        self.os_release = self.root / "os-release"
        self.os_release.write_text('NAME="Fixture"\nPRETTY_NAME="Fixture Linux"\nID=fixture\n')

    def read(self) -> SystemStats:
        return SystemStats.read(proc=self.proc, disk=self.root, os_release=self.os_release)

    def test_stats_read_from_fixture_proc(self) -> None:
        stats = self.read()
        self.assertEqual(stats.mem_total_kib, 32000000)
        self.assertEqual(stats.mem_available_kib, 8000000)
        self.assertEqual(stats.mem_used_fraction, 0.75)
        self.assertEqual(stats.load1, 1.5)
        self.assertEqual(stats.uptime_s, 3600.5)
        self.assertEqual(stats.threads, 4)
        self.assertEqual(stats.hostname, "fixturehost")
        self.assertEqual(stats.kernel, "6.18.0-fixture")
        self.assertEqual(stats.os_name, "Fixture Linux")
        self.assertGreater(stats.disk_total_b, 0)
        self.assertLessEqual(stats.disk_free_b, stats.disk_total_b)
        self.assertGreaterEqual(stats.disk_used_fraction, 0.0)
        self.assertLessEqual(stats.disk_used_fraction, 1.0)

    def test_stats_os_name_falls_back(self) -> None:
        self.os_release.write_text("NAME='Plain'\n")
        self.assertEqual(self.read().os_name, "Plain")
        self.os_release.unlink()
        self.assertEqual(self.read().os_name, "Linux")

    def test_stats_read_names_what_is_missing(self) -> None:
        (self.proc / "meminfo").write_text("MemTotal: 32000000 kB\n")
        with self.assertRaisesRegex(ValueError, "MemAvailable"):
            self.read()

    def test_stats_used_fractions(self) -> None:
        stats = self.read()
        sized = SystemStats(
            hostname=stats.hostname,
            kernel=stats.kernel,
            os_name=stats.os_name,
            mem_total_kib=0,
            mem_available_kib=0,
            load1=0.0,
            threads=1,
            uptime_s=0.0,
            disk_total_b=1000,
            disk_free_b=250,
        )
        self.assertEqual(sized.disk_used_fraction, 0.75)
        self.assertEqual(sized.mem_used_fraction, 0.0)


class WriteTextAtomicTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)

    def test_write_text_atomic_replaces_whole_file(self) -> None:
        target = self.dir / "note"
        write_text_atomic(target, "x" * 4096)
        write_text_atomic(target, "☀ نجم\n")
        self.assertEqual(target.read_text(encoding="utf-8"), "☀ نجم\n")
        self.assertEqual([p.name for p in self.dir.iterdir()], ["note"])

    def test_write_text_atomic_leaves_nothing_on_failure(self) -> None:
        with self.assertRaises(OSError):
            write_text_atomic(self.dir / "missing" / "note", "text")
        self.assertEqual(list(self.dir.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
