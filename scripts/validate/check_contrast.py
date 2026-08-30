#!/usr/bin/env python3
"""WCAG contrast checker for the design system, run as a ratchet.

Why this exists
----------------
Every colour in the app lives in exactly two files:
`lib/core/design_system/tokens.dart` (`WbColors`, the raw palette) and
`lib/core/design_system/theme.dart` (`WbSemanticColors.light` / `.dark`, the
per-theme roles built from that palette). Feature code never hard-codes a
colour; it only asks `WbTheme.of(context)` for a role. That means every colour
*combination* the app can ever render is a combination of roles from those two
files, wired together in a small number of design-system components
(`WbBadge`, `WbCard`, `WbFilterChip`, buttons, the nav bar, the snackbar, ...)
plus the `ThemeData` construction in `theme.dart` itself.

So instead of grepping every feature screen for colours it does not contain,
this script parses the two colour-definition files to get the *actual, current*
RGBA values (never duplicating a literal here — a colour changed in
`theme.dart` is picked up automatically) and pairs those roles up using a
curated `PAIRS` list below. Each pair cites the component/theme-construction
site where that foreground/background combination really occurs, so this list
tracks real rendering, not hypothetical combinations nobody draws.

Alpha compositing
------------------
Some roles are translucent (`scrim: Color(0x66111827)`, and a few components
apply `.withValues(alpha: ...)` to a role before using it as a fill — e.g. the
muted [WbBadge] tone and the [WbEmptyState] icon roundel). Measuring an alpha
colour against a background as though it were opaque is not a smaller version
of the real bug — it is a different, meaningless number: a low-alpha dark
colour on a dark background can measure as if it were "black on black"
(ratio ~1) even though the actual rendered pixels (colour painted over the
real backdrop) are perfectly legible, or the reverse can hide a real failure.
The fix is the standard "over" compositing operator: flatten the translucent
layer onto the backdrop it is actually drawn over *first*, then measure the
opaque result. See `composite()`.

The ratchet
-----------
Flipping this check on for the first time must not fail the build over
pre-existing contrast issues nobody asked this script to introduce. So the set
of pairs that currently fail is frozen into `contrast_baseline.json` (the
"baseline"). A run only fails when:
  * a pair not in the baseline now fails (a REGRESSION -- something got worse), or
  * a pair IS in the baseline but now passes (a STALE entry -- the debt was
    paid off in the code but nobody removed the paper trail, which quietly
    turns the baseline into a list nobody trims and nobody trusts).
Fixing a real failure therefore requires touching this file (removing the now
-passing entry), which is the point: the baseline must stay an honest mirror
of reality, not a fire-and-forget allowlist.

This script only measures and reports. It never edits theme.dart / tokens.dart.

Usage:
    python scripts/validate/check_contrast.py
    python scripts/validate/check_contrast.py --update-baseline   # maintainers only
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Dict, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOKENS_PATH = os.path.join(ROOT, "lib", "core", "design_system", "tokens.dart")
THEME_PATH = os.path.join(ROOT, "lib", "core", "design_system", "theme.dart")
BASELINE_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "contrast_baseline.json"
)

# WCAG 2.x thresholds. Normal text needs 4.5:1; large text (>=18pt, or >=14pt
# bold) and non-text UI/graphical objects (borders, icons carrying meaning)
# need 3:1 per SC 1.4.3 and 1.4.11.
#
# Simplification, stated up front rather than buried: several text roles below
# are reused across more than one text style (e.g. `brand` labels a chevron
# link at 13px in one place and a competition name at 13px-bold in another),
# and this script measures *role pairs*, not individual TextStyle call sites.
# Rather than thread every TextStyle's exact size/weight through the pair
# table, every "text" pair is held to the stricter 4.5:1 normal-text bar. This
# can only ever be conservative (flag something WCAG's relaxed large-text rule
# would forgive), never the reverse, so it does not hide a real failure.
TEXT_MIN_RATIO = 4.5
NONTEXT_MIN_RATIO = 3.0


# --------------------------------------------------------------------------
# Dart source parsing -- the single source of truth stays theme.dart/tokens.dart
# --------------------------------------------------------------------------


def _parse_wb_colors(src: str) -> Dict[str, int]:
    """Extract every `static const <name> = Color(0xAARRGGBB);` in WbColors."""
    colors: Dict[str, int] = {}
    for m in re.finditer(
        r"static const (\w+) = Color\((0x[0-9A-Fa-f]{8})\);", src
    ):
        colors[m.group(1)] = int(m.group(2), 16)
    if not colors:
        raise RuntimeError(f"no WbColors constants found in {TOKENS_PATH!r}")
    return colors


def _extract_balanced(src: str, open_paren_index: int) -> str:
    """Return the substring between a `(` at `open_paren_index` and its match."""
    depth = 0
    for i in range(open_paren_index, len(src)):
        if src[i] == "(":
            depth += 1
        elif src[i] == ")":
            depth -= 1
            if depth == 0:
                return src[open_paren_index + 1 : i]
    raise RuntimeError("unbalanced parentheses while parsing theme.dart")


def _parse_semantic_block(src: str, wb_colors: Dict[str, int], marker: str) -> Dict[str, int]:
    """Parse one `static const WbSemanticColors <marker> = WbSemanticColors(...)` block
    into role name -> resolved 0xAARRGGBB int, resolving `WbColors.x` references
    against the already-parsed palette."""
    anchor = f"static const WbSemanticColors {marker} = WbSemanticColors"
    idx = src.index(anchor)
    open_paren = src.index("(", idx)
    body = _extract_balanced(src, open_paren)

    roles: Dict[str, int] = {}
    field_re = re.compile(
        r"(\w+):\s*(?:WbColors\.(\w+)|(?:const )?Color\((0x[0-9A-Fa-f]{8})\))"
    )
    for line in body.split("\n"):
        m = field_re.search(line)
        if not m:
            continue
        field_name, colors_ref, literal_hex = m.groups()
        if colors_ref is not None:
            if colors_ref not in wb_colors:
                raise RuntimeError(
                    f"{marker}.{field_name} references unknown WbColors.{colors_ref}"
                )
            roles[field_name] = wb_colors[colors_ref]
        else:
            roles[field_name] = int(literal_hex, 16)
    if not roles:
        raise RuntimeError(f"no fields parsed for WbSemanticColors.{marker}")
    return roles


def _parse_on_accent(src: str, wb_colors: Dict[str, int]) -> Dict[str, int]:
    """`final onAccent = isLight ? WbColors.surface : WbColors.darkCanvas;`
    -- the one themed colour computed inline in `_build` rather than stored on
    `WbSemanticColors`. Used as the foreground on filled buttons / primary
    accents."""
    m = re.search(
        r"final onAccent = isLight \? WbColors\.(\w+) : WbColors\.(\w+);", src
    )
    if not m:
        raise RuntimeError("could not find onAccent computation in theme.dart")
    light_name, dark_name = m.groups()
    return {"light": wb_colors[light_name], "dark": wb_colors[dark_name]}


@dataclass
class Palette:
    """Resolved colours for both themes, straight from the two source files."""

    wb_colors: Dict[str, int]
    roles: Dict[str, Dict[str, int]]  # theme -> role -> 0xAARRGGBB
    on_accent: Dict[str, int]  # theme -> 0xAARRGGBB


def load_palette() -> Palette:
    with open(TOKENS_PATH, "r", encoding="utf-8") as f:
        tokens_src = f.read()
    with open(THEME_PATH, "r", encoding="utf-8") as f:
        theme_src = f.read()

    wb_colors = _parse_wb_colors(tokens_src)
    roles = {
        "light": _parse_semantic_block(theme_src, wb_colors, "light"),
        "dark": _parse_semantic_block(theme_src, wb_colors, "dark"),
    }
    on_accent = _parse_on_accent(theme_src, wb_colors)
    return Palette(wb_colors=wb_colors, roles=roles, on_accent=on_accent)


# --------------------------------------------------------------------------
# Colour maths
# --------------------------------------------------------------------------


def argb_channels(argb: int) -> Tuple[int, int, int, int]:
    a = (argb >> 24) & 0xFF
    r = (argb >> 16) & 0xFF
    g = (argb >> 8) & 0xFF
    b = argb & 0xFF
    return a, r, g, b


def composite(fg_argb: int, bg_argb: int) -> int:
    """Standard "source-over" alpha compositing of a translucent `fg_argb`
    onto an opaque `bg_argb`, returning an opaque 0xFFRRGGBB.

    `bg_argb`'s own alpha is ignored (call sites always resolve a *fully
    opaque* backdrop first, e.g. `canvas`/`surface`, which is what every real
    drawing surface in the app ultimately bottoms out on -- Flutter never
    lets you paint onto a transparent screen)."""
    fa, fr, fg_, fb = argb_channels(fg_argb)
    _, br, bg2, bb = argb_channels(bg_argb)
    alpha = fa / 255.0
    r = round(fr * alpha + br * (1 - alpha))
    g = round(fg_ * alpha + bg2 * (1 - alpha))
    b = round(fb * alpha + bb * (1 - alpha))
    return (0xFF << 24) | (r << 16) | (g << 8) | b


def _srgb_to_linear(c: float) -> float:
    c /= 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def relative_luminance(argb: int) -> float:
    _, r, g, b = argb_channels(argb)
    rl, gl, bl = _srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b)
    return 0.2126 * rl + 0.7152 * gl + 0.0722 * bl


def contrast_ratio(argb1: int, argb2: int) -> float:
    l1, l2 = relative_luminance(argb1), relative_luminance(argb2)
    lighter, darker = max(l1, l2), min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


# --------------------------------------------------------------------------
# Pair table -- every foreground/background combination the app actually
# renders, per the design-system components that build them. Each entry names
# the file(s) where the combination occurs so this list can be audited against
# the code rather than trusted blindly.
# --------------------------------------------------------------------------


@dataclass
class ColorSpec:
    """How to resolve one side of a pair for a given theme."""

    role: str  # a WbSemanticColors field name, e.g. "ink"
    alpha: float = None  # if set, apply this alpha to `role` before compositing
    over: str = None  # role this (possibly-translucent) colour is painted over


@dataclass
class Pair:
    id: str
    fg: ColorSpec
    bg: ColorSpec
    category: str  # "text" | "nontext"
    source: str
    fg_is_on_accent: bool = False  # resolves against Palette.on_accent instead of roles


PAIRS = [
    Pair(
        "ink_on_canvas",
        ColorSpec("ink"),
        ColorSpec("canvas"),
        "text",
        "theme.dart textTheme + scaffoldBackgroundColor; AppBarTheme title; "
        "primitives.dart WbSectionHeader/WbEmptyState title; game_widgets.dart WbDayHeader",
    ),
    Pair(
        "ink_on_surface",
        ColorSpec("ink"),
        ColorSpec("surface"),
        "text",
        "game_widgets.dart WbGameRow/_TeamBlock/_RowTeamLine team names & scores "
        "on a default (non-emphasized) WbCard; NavigationBar selected label",
    ),
    Pair(
        "ink_on_surfaceRaised",
        ColorSpec("ink"),
        ColorSpec("surfaceRaised"),
        "text",
        "game_widgets.dart WbHeroGameCard team names, time, score "
        "on an emphasized WbCard",
    ),
    Pair(
        "inkMuted_on_canvas",
        ColorSpec("inkMuted"),
        ColorSpec("canvas"),
        "text",
        "primitives.dart WbSectionHeader subtitle / WbEmptyState message; "
        "game_widgets.dart WbDayHeader count",
    ),
    Pair(
        "inkMuted_on_surface",
        ColorSpec("inkMuted"),
        ColorSpec("surface"),
        "text",
        "game_widgets.dart WbGameRow venue/time/date text on a default WbCard; "
        "NavigationBar unselected label",
    ),
    Pair(
        "inkMuted_on_surfaceRaised",
        ColorSpec("inkMuted"),
        ColorSpec("surfaceRaised"),
        "text",
        "game_widgets.dart WbHeroGameCard venue line and KST/date labels",
    ),
    Pair(
        "brand_on_canvas",
        ColorSpec("brand"),
        ColorSpec("canvas"),
        "text",
        "primitives.dart WbSectionHeader '전체 보기' action label; "
        "TextButtonThemeData foreground",
    ),
    Pair(
        "brand_on_surfaceRaised",
        ColorSpec("brand"),
        ColorSpec("surfaceRaised"),
        "text",
        "game_widgets.dart WbHeroGameCard competition name",
    ),
    Pair(
        "onAccent_on_brand",
        ColorSpec("__onAccent__"),
        ColorSpec("brand"),
        "text",
        "theme.dart FilledButtonThemeData label on its own backgroundColor",
        fg_is_on_accent=True,
    ),
    Pair(
        "canvas_on_ink",
        ColorSpec("canvas"),
        ColorSpec("ink"),
        "text",
        "theme.dart SnackBarTheme: contentTextStyle colour on backgroundColor",
    ),
    Pair(
        "brand_on_brandSoft",
        ColorSpec("brand"),
        ColorSpec("brandSoft"),
        "text",
        "primitives.dart WbBadge(tone: neutral) label+icon; "
        "theme.dart NavigationBarTheme selected icon on indicatorColor",
    ),
    Pair(
        "action_on_actionSoft",
        ColorSpec("action"),
        ColorSpec("actionSoft"),
        "text",
        "primitives.dart WbBadge(tone: live) label+icon "
        "(game_widgets.dart WbGameStatusBadge for GameStatus.live)",
    ),
    Pair(
        "verified_on_verifiedSoft",
        ColorSpec("verified"),
        ColorSpec("verifiedSoft"),
        "text",
        "primitives.dart WbBadge(tone: positive) label+icon",
    ),
    Pair(
        "highlight_on_highlightSoft",
        ColorSpec("highlight"),
        ColorSpec("highlightSoft"),
        "text",
        "primitives.dart WbBadge(tone: warning|highlight) label+icon "
        "(game_widgets.dart WbWeatherRiskBadge, forfeit/postponed/delayed statuses)",
    ),
    Pair(
        "danger_on_actionSoft",
        ColorSpec("danger"),
        ColorSpec("actionSoft"),
        "text",
        "primitives.dart WbBadge(tone: danger) label+icon -- deliberately reuses "
        "actionSoft rather than a dedicated 'danger soft' fill; not this "
        "script's place to relayout the design system, only to measure it",
    ),
    Pair(
        "surface_on_brand",
        ColorSpec("surface"),
        ColorSpec("brand"),
        "text",
        "primitives.dart WbFilterChip selected state (fg=surface, bg=brand)",
    ),
    Pair(
        "inkMuted_on_dividerAlpha_canvas",
        ColorSpec("inkMuted"),
        ColorSpec("divider", alpha=0.45, over="canvas"),
        "text",
        "primitives.dart WbBadge(tone: muted) label+icon over "
        "`divider.withValues(alpha: 0.45)` -- ALPHA COMPOSITED",
    ),
    Pair(
        "brand_on_brandAlpha12_canvas",
        ColorSpec("brand"),
        ColorSpec("brand", alpha=0.12, over="canvas"),
        "text",
        "primitives.dart WbTeamMark monogram (no team colorHex, falls back to "
        "c.brand) over `accent.withValues(alpha: 0.12)` -- ALPHA COMPOSITED",
    ),
    Pair(
        "divider_on_canvas",
        ColorSpec("divider"),
        ColorSpec("canvas"),
        "nontext",
        "primitives.dart WbInsetDivider / game_widgets.dart list separators drawn "
        "directly on the page background",
    ),
    Pair(
        "divider_on_surface",
        ColorSpec("divider"),
        ColorSpec("surface"),
        "nontext",
        "primitives.dart WbCard default border; WbFilterChip unselected border",
    ),
    Pair(
        "danger_icon_on_dividerAlpha40_canvas",
        ColorSpec("danger"),
        ColorSpec("divider", alpha=0.40, over="canvas"),
        "nontext",
        "primitives.dart WbEmptyState(tone: danger) icon over "
        "`divider.withValues(alpha: 0.4)` roundel -- ALPHA COMPOSITED",
    ),
    Pair(
        "highlight_icon_on_dividerAlpha40_canvas",
        ColorSpec("highlight"),
        ColorSpec("divider", alpha=0.40, over="canvas"),
        "nontext",
        "primitives.dart WbEmptyState(tone: warning) icon roundel -- ALPHA COMPOSITED",
    ),
    Pair(
        "verified_icon_on_dividerAlpha40_canvas",
        ColorSpec("verified"),
        ColorSpec("divider", alpha=0.40, over="canvas"),
        "nontext",
        "primitives.dart WbEmptyState(tone: positive) icon roundel -- ALPHA COMPOSITED",
    ),
    Pair(
        "inkMuted_icon_on_dividerAlpha40_canvas",
        ColorSpec("inkMuted"),
        ColorSpec("divider", alpha=0.40, over="canvas"),
        "nontext",
        "primitives.dart WbEmptyState(default tone) icon roundel -- ALPHA COMPOSITED",
    ),
    Pair(
        "highlight_star_on_surface",
        ColorSpec("highlight"),
        ColorSpec("surface"),
        "nontext",
        "game_widgets.dart _RowTeamLine favourite star icon on a default WbCard",
    ),
    Pair(
        "highlight_star_on_surfaceRaised",
        ColorSpec("highlight"),
        ColorSpec("surfaceRaised"),
        "nontext",
        "game_widgets.dart WbHeroGameCard follow-star icon (favourited state)",
    ),
]


def _resolve(spec: ColorSpec, roles: Dict[str, int]) -> int:
    base = roles[spec.role]
    if spec.alpha is None:
        return base
    a, r, g, b = argb_channels(base)
    translucent = ((round(spec.alpha * 255) & 0xFF) << 24) | (r << 16) | (g << 8) | b
    over_argb = roles[spec.over]
    return composite(translucent, over_argb)


def measure(palette: Palette):
    """Yield (pair, theme, ratio, threshold, passed) for every pair x theme."""
    for theme in ("light", "dark"):
        roles = palette.roles[theme]
        for pair in PAIRS:
            fg_argb = (
                palette.on_accent[theme]
                if pair.fg_is_on_accent
                else _resolve(pair.fg, roles)
            )
            bg_argb = _resolve(pair.bg, roles)
            ratio = contrast_ratio(fg_argb, bg_argb)
            threshold = TEXT_MIN_RATIO if pair.category == "text" else NONTEXT_MIN_RATIO
            yield pair, theme, ratio, threshold, ratio >= threshold


# --------------------------------------------------------------------------
# Baseline ratchet
# --------------------------------------------------------------------------


def load_baseline() -> set:
    if not os.path.exists(BASELINE_PATH):
        return set()
    with open(BASELINE_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return {(entry["pair"], entry["theme"]) for entry in data.get("failures", [])}


def write_baseline(failing: set) -> None:
    data = {
        "_comment": (
            "Frozen contrast failures, as of the day this ratchet went live. "
            "A pair here means: this foreground/background combination is "
            "currently below its WCAG threshold, and check_contrast.py is told "
            "not to fail the build over it. Fix the colours, then DELETE the "
            "entry -- a passing pair left in this file is itself a failure "
            "(see check_contrast.py's --update-baseline / stale-entry check)."
        ),
        "failures": [
            {"pair": pair_id, "theme": theme}
            for pair_id, theme in sorted(failing)
        ],
    }
    with open(BASELINE_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main(argv=None) -> int:
    # Pair sources quote Korean UI strings (e.g. WbSectionHeader's '전체
    # 보기'). Windows consoles default stdout/stderr to the system codepage
    # (cp949/cp1252, not UTF-8), which mangles those into '?'/mojibake rather
    # than erroring -- silently unreadable output being its own small bug in a
    # tool whose entire job is making problems visible. `reconfigure` is
    # Python 3.7+; guarded because a caller piping output through something
    # that already fixed the stream shouldn't crash on a redundant call.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--update-baseline",
        action="store_true",
        help=(
            "Maintainer escape hatch: overwrite contrast_baseline.json with "
            "whatever currently fails, instead of checking it. Never use this "
            "to make a CI failure go away -- use it only right after you've "
            "looked at every newly-frozen entry and decided it's real, "
            "pre-existing debt."
        ),
    )
    args = parser.parse_args(argv)

    palette = load_palette()
    results = list(measure(palette))

    failing_now = {
        (pair.id, theme) for pair, theme, ratio, threshold, passed in results if not passed
    }

    if args.update_baseline:
        write_baseline(failing_now)
        print(f"[contrast] baseline updated: {len(failing_now)} failing pair(s) frozen.")
        return 0

    baseline = load_baseline()
    regressions = sorted(failing_now - baseline)
    stale = sorted(baseline - failing_now)

    print(f"[contrast] measured {len(results)} pair-checks "
          f"({len(PAIRS)} pairs x 2 themes)")
    print(f"[contrast] currently failing: {len(failing_now)} "
          f"(baseline debt: {len(baseline)})")

    worst = sorted(results, key=lambda r: r[2])[:5]
    print("[contrast] worst 5 ratios:")
    for pair, theme, ratio, threshold, passed in worst:
        mark = "FAIL" if not passed else "ok"
        print(f"  {ratio:5.2f}:1 (need {threshold}:1) [{mark}] {pair.id} ({theme})")

    ok = True
    if regressions:
        ok = False
        print("\n[contrast] REGRESSION -- newly failing pair(s) not in baseline:")
        for pair_id, theme in regressions:
            r = next(
                r for r in results if r[0].id == pair_id and r[1] == theme
            )
            print(f"  {pair_id} ({theme}): {r[2]:.2f}:1, needs {r[3]}:1 -- {r[0].source}")

    if stale:
        ok = False
        print("\n[contrast] STALE BASELINE ENTRY -- now passing, remove it from "
              "contrast_baseline.json (or run --update-baseline after reviewing "
              "every entry):")
        for pair_id, theme in stale:
            r = next(
                r for r in results if r[0].id == pair_id and r[1] == theme
            )
            print(f"  {pair_id} ({theme}): {r[2]:.2f}:1 (>= {r[3]}:1 now)")

    if ok:
        print("\n[contrast] OK -- no new failures, no stale baseline entries.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
