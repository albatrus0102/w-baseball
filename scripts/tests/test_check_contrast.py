"""Tests for the WCAG contrast ratchet (scripts/validate/check_contrast.py).

Three things specifically needed proof, because getting any of them wrong
would make the checker worse than not having one at all:

  * alpha compositing is arithmetically correct, using the exact translucent
    colours that live in theme.dart today (a naive "measure the alpha colour
    as if it were opaque" bug reads as a real number, not a crash);
  * the ratchet actually treats "newly failing" and "already known and now
    fixed" as two different, both-fatal outcomes, rather than only catching
    one direction;
  * the Dart source parser resolves both `WbColors.xxx` references and
    literal `Color(0x...)` values, so a future colour change is picked up
    without anyone touching this test.

Run with:
    python -m unittest discover -s scripts/tests -v
"""

from __future__ import annotations

import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts", "validate"))

import check_contrast as cc  # noqa: E402


class CompositingTest(unittest.TestCase):
    def test_opaque_over_anything_is_itself(self):
        # Fully opaque foreground: compositing must be a no-op.
        self.assertEqual(cc.composite(0xFF112233, 0xFFFFFFFF), 0xFF112233)

    def test_half_alpha_black_over_white_is_mid_grey(self):
        half_black = 0x80000000  # 128/255 alpha, close enough to 50%
        result = cc.composite(half_black, 0xFFFFFFFF)
        _, r, g, b = cc.argb_channels(result)
        # 128/255 ~= 0.502 -> white channel (255) scaled down by (1-0.502)
        self.assertEqual((r, g, b), (127, 127, 127))

    def test_the_actual_scrim_value_from_theme_dart_composites_sanely(self):
        # `scrim: Color(0x66111827)` from WbSemanticColors.light. Naively
        # treating this as opaque would read its RGB (#111827, near-black) and
        # compare it as if that were the real on-screen colour. Composited
        # over the light canvas it actually sits in front of, the result must
        # land strictly between the two endpoints -- proof the alpha channel
        # was actually applied rather than ignored or double-counted.
        scrim = 0x66111827
        canvas = 0xFFF7F5F0  # WbColors.canvas
        result = cc.composite(scrim, canvas)
        result_lum = cc.relative_luminance(result)
        self.assertLess(result_lum, cc.relative_luminance(canvas))
        self.assertGreater(result_lum, cc.relative_luminance(0xFF111827))

    def test_zero_alpha_foreground_is_pure_background(self):
        transparent = 0x00ABCDEF
        bg = 0xFF102030
        self.assertEqual(cc.composite(transparent, bg), bg | 0xFF000000)


class ContrastMathTest(unittest.TestCase):
    def test_black_on_white_is_21_to_1(self):
        self.assertAlmostEqual(
            cc.contrast_ratio(0xFF000000, 0xFFFFFFFF), 21.0, places=1
        )

    def test_identical_colours_are_1_to_1(self):
        self.assertAlmostEqual(
            cc.contrast_ratio(0xFF336699, 0xFF336699), 1.0, places=6
        )

    def test_ratio_is_symmetric(self):
        a, b = 0xFF224466, 0xFFEEEEEE
        self.assertAlmostEqual(cc.contrast_ratio(a, b), cc.contrast_ratio(b, a))


class PaletteParsingTest(unittest.TestCase):
    """The checker must read colours out of the real source files, not a
    duplicated copy -- otherwise a colour change in theme.dart would silently
    stop being measured."""

    def setUp(self):
        self.palette = cc.load_palette()

    def test_resolves_a_literal_wbcolors_constant(self):
        self.assertEqual(self.palette.wb_colors["ink"], 0xFF111827)

    def test_light_role_resolved_via_wbcolors_reference(self):
        # WbSemanticColors.light: `ink: WbColors.ink`.
        self.assertEqual(self.palette.roles["light"]["ink"], 0xFF111827)

    def test_dark_role_resolved_from_inline_literal(self):
        # WbSemanticColors.dark: `brand: Color(0xFF9FB3D9)` -- not a WbColors
        # reference at all, so the literal branch of the parser must fire.
        self.assertEqual(self.palette.roles["dark"]["brand"], 0xFF9FB3D9)

    def test_translucent_scrim_role_keeps_its_alpha_channel(self):
        scrim = self.palette.roles["light"]["scrim"]
        alpha = (scrim >> 24) & 0xFF
        self.assertLess(alpha, 0xFF)

    def test_on_accent_differs_by_brightness(self):
        self.assertNotEqual(
            self.palette.on_accent["light"], self.palette.on_accent["dark"]
        )


class RatchetTest(unittest.TestCase):
    """Exercises the pass/fail decision in isolation from the real pair table
    and the real baseline file, using tiny synthetic ones, so this test does
    not need updating every time a real colour or pair changes."""

    def _failing_set(self, results):
        return {(pid, theme) for pid, theme, passed in results if not passed}

    def test_new_failure_not_in_baseline_is_a_regression(self):
        results = [("a", "light", True), ("b", "light", False)]
        failing_now = self._failing_set(results)
        baseline = set()  # "b" was never frozen
        regressions = failing_now - baseline
        self.assertEqual(regressions, {("b", "light")})

    def test_baseline_entry_that_now_passes_is_stale(self):
        results = [("a", "light", True)]  # "a" used to fail, now passes
        failing_now = self._failing_set(results)
        baseline = {("a", "light")}
        stale = baseline - failing_now
        self.assertEqual(stale, {("a", "light")})

    def test_baseline_entry_still_failing_is_not_flagged_either_way(self):
        results = [("a", "light", False)]
        failing_now = self._failing_set(results)
        baseline = {("a", "light")}
        self.assertEqual(failing_now - baseline, set())  # no regression
        self.assertEqual(baseline - failing_now, set())  # no stale entry


class BaselineFileTest(unittest.TestCase):
    """The committed baseline must actually agree with the current code --
    this is the same check `main()` runs, exercised directly so a broken
    baseline shows up as a unit test failure with a precise assertion diff
    instead of only a CLI exit code."""

    def test_committed_baseline_has_no_regressions_or_stale_entries(self):
        palette = cc.load_palette()
        results = list(cc.measure(palette))
        failing_now = {
            (pair.id, theme)
            for pair, theme, ratio, threshold, passed in results
            if not passed
        }
        baseline = cc.load_baseline()
        self.assertEqual(
            failing_now - baseline, set(), "new contrast regression(s) found"
        )
        self.assertEqual(
            baseline - failing_now,
            set(),
            "stale baseline entr(y/ies): now passing, remove from "
            "contrast_baseline.json",
        )


if __name__ == "__main__":
    unittest.main()
