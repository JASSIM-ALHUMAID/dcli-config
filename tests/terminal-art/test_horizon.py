"""Unit tests for themes/horizon.py: the painted sky over Riyadh.

Every test paints a fixed instant into a temp directory with a fixture palette
and fixture machine stats; nothing here reads the real clock, /proc or zone.

Run: PYTHONPATH=scripts/terminal-art python3 -m unittest discover -s tests/terminal-art -p 'test_*.py'
"""

import contextlib
import io
import json
import math
import os
import re
import subprocess
import tempfile
import time
import tomllib
import unittest
from datetime import date, datetime, timezone
from pathlib import Path
from unittest import mock
from zoneinfo import ZoneInfo

from PIL import Image, ImageStat

from artlib import Mode, PaintContext, Painted, Palette, SystemStats
from themes import horizon
from themes.sky import HORIZON_Y, sun_bar_progress, RIYADH, SKY_SIZE, Location, bucket_expiry, moon_position, sun_position, sun_times, view_x, view_y

RIYADH_TZ = ZoneInfo("Asia/Riyadh")
PALETTE = Palette.from_json(
    json.dumps(
        {
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
    )
)
STATS = SystemStats("fixturehost", "6.18.0", "Fixture Linux", 32000000, 8000000, 1.5, 16, 3600.5, 1000, 400)
# The environment horizon sees: Riyadh's own zone, no location override.
CLEAN_ENV = {"TZ": "Asia/Riyadh"}
STILL_BUDGET_S = 0.3
STILL_MAX_BYTES = 500_000
FULL_MAX_BYTES = 2_000_000
FRAMES = range(12, 17)
LABEL_COLUMNS = 32


def at(day: int, hour: int, minute: int = 0, month: int = 11) -> datetime:
    return datetime(2026, month, day, hour, minute, tzinfo=RIYADH_TZ)


class HorizonCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        env = mock.patch.dict(os.environ, CLEAN_ENV, clear=True)
        env.start()
        self.addCleanup(env.stop)

    def paint(self, now: datetime, mode: Mode = Mode.STILL, name: str = "out") -> tuple[Path, Painted]:
        out = self.root / name
        out.mkdir(exist_ok=True)
        state = self.root / "state"
        state.mkdir(exist_ok=True)
        painted = horizon.paint(PaintContext(out, mode, now, PALETTE, STATS, state))
        return out, painted

    def text(self, out: Path, name: str) -> str:
        return (out / name).read_text(encoding="utf-8")


class PaintContractTest(HorizonCase):
    def test_theme_declares_it_does_not_repaint_after_the_greeting(self) -> None:
        self.assertIs(horizon.REPAINT_AFTER_GREETING, False)

    def test_still_writes_one_frame_png(self) -> None:
        out, _ = self.paint(at(7, 12))
        with Image.open(out / "logo.png") as image:
            self.assertEqual(image.size, SKY_SIZE)
            self.assertEqual(getattr(image, "n_frames", 1), 1)
        self.assertLessEqual((out / "logo.png").stat().st_size, STILL_MAX_BYTES)

    def test_full_writes_animated_png(self) -> None:
        for now in (at(7, 12), at(7, 22), at(7, 17, 15)):
            with self.subTest(now=now):
                out, _ = self.paint(now, Mode.FULL, f"full-{now.hour}")
                with Image.open(out / "logo.png") as image:
                    self.assertEqual(image.size, SKY_SIZE)
                    self.assertTrue(image.is_animated)
                    self.assertIn(image.n_frames, FRAMES)
                    self.assertEqual(image.info.get("loop"), 0)
                self.assertLessEqual((out / "logo.png").stat().st_size, FULL_MAX_BYTES)

    def test_full_animation_moves_and_loops_seamlessly(self) -> None:
        for now in (at(7, 0), at(7, 12)):
            with self.subTest(now=now):
                out, _ = self.paint(now, Mode.FULL, f"loop-{now.hour}")
                with Image.open(out / "logo.png") as image:
                    frames = []
                    for index in range(image.n_frames):
                        image.seek(index)
                        frames.append(image.convert("RGB").tobytes())
                self.assertGreater(len(set(frames)), 1, "no frame differs from the others")
                self.assertEqual(len(frames), len(set(frames)), "a frame repeats inside the loop")

    def test_expires_is_bucket_end(self) -> None:
        now = at(7, 14, 3).replace(second=20)
        _, painted = self.paint(now)
        self.assertEqual(painted.expires, bucket_expiry(now))
        self.assertEqual(painted.expires, int(at(7, 14, 10).timestamp()))

    def test_naive_clock_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            self.paint(datetime(2026, 11, 7, 12))


class TextFilesTest(HorizonCase):
    def test_sun_file_holds_the_cycle_around_now(self) -> None:
        out, _ = self.paint(at(7, 12))
        sunrise, sunset, next_sunrise = (int(field) for field in self.text(out, "sun").split())
        times = sun_times(date(2026, 11, 7), RIYADH, RIYADH_TZ)
        self.assertLess(sunrise, sunset)
        self.assertLess(sunset, next_sunrise)
        self.assertAlmostEqual(sunrise, times.sunrise.timestamp(), delta=1)
        self.assertAlmostEqual(sunset, times.sunset.timestamp(), delta=1)
        self.assertGreater(next_sunrise, at(7, 12).timestamp())

    def test_sun_file_before_dawn_names_yesterdays_day_and_todays_sunrise(self) -> None:
        out, _ = self.paint(at(7, 3))
        sunrise, sunset, next_sunrise = (int(field) for field in self.text(out, "sun").split())
        today = sun_times(date(2026, 11, 7), RIYADH, RIYADH_TZ)
        self.assertLess(sunset, at(7, 3).timestamp())
        self.assertAlmostEqual(next_sunrise, today.sunrise.timestamp(), delta=1)
        self.assertLess(sunrise, sunset)

    def test_sun_file_after_sunset_points_at_tomorrows_sunrise(self) -> None:
        out, _ = self.paint(at(7, 22))
        _, sunset, next_sunrise = (int(field) for field in self.text(out, "sun").split())
        tomorrow = sun_times(date(2026, 11, 8), RIYADH, RIYADH_TZ)
        self.assertLess(sunset, at(7, 22).timestamp())
        self.assertAlmostEqual(next_sunrise, tomorrow.sunrise.timestamp(), delta=1)

    def test_greeting_lines(self) -> None:
        out, _ = self.paint(at(7, 12))
        times = sun_times(date(2026, 11, 7), RIYADH, RIYADH_TZ)
        self.assertEqual(self.text(out, "place").strip(), "Riyadh · Saturday 7 November")
        self.assertIn(times.sunrise.strftime("%H:%M"), self.text(out, "almanac"))
        self.assertIn(times.sunset.strftime("%H:%M"), self.text(out, "almanac"))
        self.assertIn("sunrise", self.text(out, "almanac"))
        self.assertIn("sunset", self.text(out, "almanac"))
        self.assertTrue(self.text(out, "sky").startswith("daylight"))
        self.assertIn("lit", self.text(out, "moon"))
        self.assertRegex(self.text(out, "daylight"), r"^11 h 0\d m of daylight\n$")

    def test_each_greeting_line_is_one_short_line(self) -> None:
        for now in (at(7, 3), at(7, 12), at(7, 18, 40), at(24, 21)):
            out, _ = self.paint(now, name=f"t-{now.day}-{now.hour}")
            for name in ("place", "sky", "almanac", "moon", "daylight"):
                with self.subTest(now=now, file=name):
                    content = self.text(out, name)
                    self.assertTrue(content.endswith("\n") and content.count("\n") == 1, content)
                    self.assertLessEqual(len(content.rstrip("\n")), LABEL_COLUMNS, content)

    def test_sky_line_names_the_phase_and_the_sun_height(self) -> None:
        out, _ = self.paint(at(7, 22))
        self.assertRegex(self.text(out, "sky"), r"^night · sun −\d+°\n$")
        out, _ = self.paint(at(7, 12), name="noon")
        self.assertRegex(self.text(out, "sky"), r"^daylight · sun \+4\d°\n$")

    def test_moon_line_matches_the_calendar(self) -> None:
        # Full moon 2026-11-24; new moon 2026-11-09.
        out, _ = self.paint(at(24, 22))
        self.assertIn("full moon", self.text(out, "moon"))
        out, _ = self.paint(at(9, 22), name="new")
        self.assertIn("new moon", self.text(out, "moon"))

    def test_long_place_names_are_shortened_to_fit(self) -> None:
        env = {"TZ": "Asia/Riyadh", "DCLI_HORIZON_LATLON": "51.5,-0.12", "DCLI_HORIZON_PLACE": "Llanfairpwllgwyngyll Gogerychwyrndrobwll"}
        with mock.patch.dict(os.environ, env, clear=True):
            out, _ = self.paint(at(7, 12), name="long")
        line = self.text(out, "place").rstrip("\n")
        self.assertLessEqual(len(line), LABEL_COLUMNS)
        self.assertIn("…", line)
        self.assertTrue(line.endswith("Saturday 7 November"))

    def test_invalid_location_override_warns_on_stderr_and_paints_riyadh(self) -> None:
        env = {"TZ": "Asia/Riyadh", "DCLI_HORIZON_LATLON": "north"}
        stderr = io.StringIO()
        with mock.patch.dict(os.environ, env, clear=True), contextlib.redirect_stderr(stderr):
            out, _ = self.paint(at(7, 12), name="bad")
        self.assertIn("DCLI_HORIZON_LATLON", stderr.getvalue())
        self.assertTrue(self.text(out, "place").startswith("Riyadh"))


class ZoneTest(HorizonCase):
    def test_times_are_shown_on_the_named_zones_clock_across_a_dst_changeover(self) -> None:
        # London, 2026-03-29: clocks go forward at 01:00 UTC. At 00:30 UTC the fixed
        # offset astimezone() reports is +00:00, but the day's sunrise happens on BST.
        london = {"TZ": "Europe/London", "DCLI_HORIZON_LATLON": "51.5,-0.12", "DCLI_HORIZON_PLACE": "London"}
        zone = ZoneInfo("Europe/London")
        now = datetime(2026, 3, 29, 0, 30, tzinfo=timezone.utc)
        with mock.patch.dict(os.environ, london, clear=True):
            out, _ = self.paint(now, name="london")
        expected = sun_times(date(2026, 3, 29), Location(51.5, -0.12, "London"), zone)
        almanac = self.text(out, "almanac")
        self.assertIn(expected.sunrise.strftime("%H:%M"), almanac)
        self.assertIn(expected.sunset.strftime("%H:%M"), almanac)
        self.assertNotIn(expected.sunrise.astimezone(timezone.utc).strftime("%H:%M"), almanac)
        self.assertEqual(self.text(out, "place").strip(), "London · Sunday 29 March")
        _, _, next_sunrise = (int(field) for field in self.text(out, "sun").split())
        self.assertAlmostEqual(next_sunrise, expected.sunrise.timestamp(), delta=1)


class SkyPictureTest(HorizonCase):
    def pixels(self, now: datetime, name: str) -> Image.Image:
        out, _ = self.paint(now, name=name)
        with Image.open(out / "logo.png") as image:
            return image.convert("RGB")

    @staticmethod
    def brightness(image: Image.Image, box: tuple[int, int, int, int]) -> float:
        return ImageStat.Stat(image.crop(box).convert("L")).mean[0]

    def test_night_sky_is_darker_than_noon(self) -> None:
        top = (0, 0, SKY_SIZE[0], round(SKY_SIZE[1] * 0.2))
        midnight = self.brightness(self.pixels(at(7, 0), "night"), top)
        noon = self.brightness(self.pixels(at(7, 12), "noon"), top)
        self.assertLess(midnight, noon)
        self.assertLess(midnight, 40)
        self.assertGreater(noon, 80)

    def test_sun_disc_is_drawn_where_the_sun_is(self) -> None:
        now = at(7, 15)
        altitude, azimuth = sun_position(now, RIYADH)
        x, y = round(view_x(azimuth)), round(view_y(altitude))
        image = self.pixels(now, "sun")
        r, g, b = image.getpixel((x, y))
        self.assertGreater(min(r, g), 235, (x, y, (r, g, b)))
        far = image.getpixel((x + 200, y))
        self.assertLess(sum(far), sum((r, g, b)) - 120)

    def test_no_sun_disc_at_midnight(self) -> None:
        image = self.pixels(at(7, 0), "midnight")
        self.assertLess(self.brightness(image, (0, 0, SKY_SIZE[0], round(SKY_SIZE[1] * HORIZON_Y))), 40)

    def test_ground_is_below_the_horizon_line(self) -> None:
        image = self.pixels(at(7, 12), "ground")
        horizon_row = round(SKY_SIZE[1] * HORIZON_Y)
        sky = self.brightness(image, (0, horizon_row - 90, SKY_SIZE[0], horizon_row - 60))
        sand = image.getpixel((SKY_SIZE[0] // 2, SKY_SIZE[1] - 3))
        self.assertNotEqual(sky, sum(sand) / 3)
        self.assertGreater(sand[0], sand[2], "sand should be warmer than it is blue")

    def test_moon_is_drawn_when_it_is_up(self) -> None:
        # First quarter 2026-11-17 ~ 20:48 UTC; the moon stands in the south at sunset.
        now = at(17, 19)
        with_moon = self.pixels(now, "moon")
        altitude, azimuth = moon_position(now, RIYADH)
        self.assertGreater(altitude, 20)
        x, y = round(view_x(azimuth)), round(view_y(altitude))
        bright = max(sum(with_moon.getpixel((x + dx, y + dy))) for dx in range(-9, 10, 3) for dy in range(-9, 10, 3))
        self.assertGreater(bright, 3 * 170)

    def test_stars_come_out_at_night_only(self) -> None:
        blank = Image.new("RGB", SKY_SIZE, (30, 60, 120))
        for now, expected in ((at(7, 12), 0), (at(7, 17, 15), 0), (at(7, 1), None)):
            with self.subTest(now=now):
                scene = horizon.build_scene(now, RIYADH, RIYADH_TZ)
                frame = blank.copy()
                horizon._paint_stars(frame, horizon.star_field(scene.day), scene, 0.0)
                changed = sum(1 for a, b in zip(frame.tobytes(), blank.tobytes()) if a != b)
                if expected == 0:
                    self.assertEqual(changed, 0)
                else:
                    self.assertGreater(changed, 300)

    def test_the_night_picture_has_bright_points_in_a_dark_sky(self) -> None:
        window = self.pixels(at(7, 1), "stars").crop((0, 0, SKY_SIZE[0], 120)).convert("L").tobytes()
        self.assertGreater(sum(1 for value in window if value > 120), 20)


class DunesTest(HorizonCase):
    @staticmethod
    def silhouette(day: date) -> bytes:
        return b"".join(horizon.ridge_coverage(profile).tobytes() for profile in horizon.dune_profiles(day))

    def test_same_day_same_dunes(self) -> None:
        self.assertEqual(self.silhouette(date(2026, 11, 7)), self.silhouette(date(2026, 11, 7)))

    def test_another_day_other_dunes(self) -> None:
        self.assertNotEqual(self.silhouette(date(2026, 11, 7)), self.silhouette(date(2026, 11, 8)))

    def test_dune_profiles_stay_inside_the_picture_and_are_ordered_back_to_front(self) -> None:
        profiles = horizon.dune_profiles(date(2026, 11, 7))
        self.assertEqual(len(profiles), 3)
        horizon_row = SKY_SIZE[1] * HORIZON_Y
        means = [sum(p) / len(p) for p in profiles]
        self.assertEqual(means, sorted(means))
        for profile in profiles:
            self.assertEqual(len(profile), SKY_SIZE[0])
            self.assertGreater(min(profile), horizon_row - 40)
            self.assertLess(max(profile), SKY_SIZE[1])

    def test_coverage_is_solid_below_the_crest_and_clear_above(self) -> None:
        profile = horizon.dune_profiles(date(2026, 11, 7))[1]
        coverage = horizon.ridge_coverage(profile)
        column = SKY_SIZE[0] // 3
        crest = profile[column]
        self.assertEqual(coverage.getpixel((column, math.floor(crest) - 2)), 0)
        self.assertEqual(coverage.getpixel((column, math.ceil(crest) + 2)), 255)
        self.assertEqual(coverage.getpixel((column, SKY_SIZE[1] - 1)), 255)

    def test_the_land_does_not_depend_on_the_time_of_day(self) -> None:
        def ground(now: datetime, name: str) -> bytes:
            out, _ = self.paint(now, name=name)
            with Image.open(out / "logo.png") as image:
                row = image.convert("L").crop((0, SKY_SIZE[1] - 1, SKY_SIZE[0], SKY_SIZE[1]))
            return bytes(1 if value else 0 for value in row.tobytes())

        self.assertEqual(ground(at(7, 10, 0), "ten"), ground(at(7, 10, 20), "twenty"))


class MoonMaskTest(unittest.TestCase):
    RADIUS = 16

    def lit_share(self, mask: Image.Image) -> float:
        return sum(mask.tobytes()) / 255 / (math.pi * self.RADIUS**2)

    @staticmethod
    def centroid(mask: Image.Image) -> tuple[float, float]:
        total = sum_x = sum_y = 0
        for index, value in enumerate(mask.tobytes()):
            total += value
            sum_x += value * (index % mask.width)
            sum_y += value * (index // mask.width)
        return sum_x / total - mask.width / 2, sum_y / total - mask.height / 2

    def test_lit_area_matches_the_fraction(self) -> None:
        for fraction in (0.15, 0.5, 0.85):
            for bearing in (90.0, -90.0, 30.0):
                with self.subTest(fraction=fraction, bearing=bearing):
                    mask = horizon.moon_lit_mask(fraction, bearing, self.RADIUS)
                    self.assertAlmostEqual(self.lit_share(mask), fraction, delta=0.05)

    def test_lit_side_faces_the_sun(self) -> None:
        right = self.centroid(horizon.moon_lit_mask(0.3, 90.0, self.RADIUS))
        left = self.centroid(horizon.moon_lit_mask(0.3, -90.0, self.RADIUS))
        top = self.centroid(horizon.moon_lit_mask(0.3, 0.0, self.RADIUS))
        bottom = self.centroid(horizon.moon_lit_mask(0.3, 180.0, self.RADIUS))
        self.assertGreater(right[0], 2)
        self.assertLess(left[0], -2)
        self.assertLess(top[1], -2)
        self.assertGreater(bottom[1], 2)

    def test_new_moon_has_no_lit_limb_and_full_moon_is_whole(self) -> None:
        self.assertLess(self.lit_share(horizon.moon_lit_mask(0.0, 90.0, self.RADIUS)), 0.02)
        self.assertGreater(self.lit_share(horizon.moon_lit_mask(1.0, 90.0, self.RADIUS)), 0.97)


class StillBudgetTest(HorizonCase):
    def test_still_paints_within_budget(self) -> None:
        self.paint(at(7, 12), name="warmup")
        for now in (at(7, 12), at(7, 18), at(7, 1)):
            started = time.perf_counter()
            self.paint(now, name=f"timed-{now.hour}")
            elapsed = time.perf_counter() - started
            self.assertLess(elapsed, STILL_BUDGET_S, f"{now}: {elapsed:.3f}s")


THEME_DIR = Path(__file__).resolve().parents[2] / "dotfiles" / "terminal" / "_themes" / "horizon"
BAR_CELLS = 13


class PromptBarTest(HorizonCase):
    """The starship bar (one awk over the `sun` file) agrees with sun_bar_progress."""

    def command(self, live: Path) -> str:
        config = tomllib.loads((THEME_DIR / "starship.toml").read_text(encoding="utf-8"))
        template = config["custom"]["sun"]["command"]
        return template.replace("{{live}}", str(live)).replace("{{outline.rgb}}", "1;2;3")

    def bar(self, live: Path, epoch: int | None) -> str:
        env = {"PATH": "/usr/bin:/bin"} | ({} if epoch is None else {"DCLI_SUN_NOW": str(epoch)})
        done = subprocess.run(["/bin/sh"], input=self.command(live), capture_output=True, text=True, env=env, check=True)
        return re.sub(r"\x1b\[[0-9;]*m", "", done.stdout)

    def test_bar_matches_the_reference_at_day_and_night(self) -> None:
        today = sun_times(date(2026, 11, 7), RIYADH, RIYADH_TZ)
        tomorrow = sun_times(date(2026, 11, 8), RIYADH, RIYADH_TZ)
        yesterday = sun_times(date(2026, 11, 6), RIYADH, RIYADH_TZ)
        cases = ((at(7, 7), "☀"), (at(7, 12), "☀"), (at(7, 16, 59), "☀"), (at(7, 18), "☾"), (at(7, 23), "☾"), (at(7, 4), "☾"))
        for now, glyph in cases:
            with self.subTest(now=now):
                out, _ = self.paint(now, name=f"bar-{now.hour}-{now.minute}")
                _, share = sun_bar_progress(now, today, tomorrow.sunrise, yesterday.sunset)
                text = self.bar(out, int(now.timestamp()))
                self.assertEqual(len(text.rstrip()), BAR_CELLS + 2)
                self.assertEqual(text.index(glyph) - 1, int(share * (BAR_CELLS - 1) + 0.5))

    def test_bar_is_hidden_without_or_with_a_stale_sun_file(self) -> None:
        out, _ = self.paint(at(7, 12), name="stale")
        self.assertEqual(self.bar(out / "nowhere", None), "")
        self.assertEqual(self.bar(out, int(at(9, 12).timestamp())), "")
        (out / "sun").write_text("garbage\n")
        self.assertEqual(self.bar(out, int(at(7, 12).timestamp())), "")


if __name__ == "__main__":
    unittest.main()
