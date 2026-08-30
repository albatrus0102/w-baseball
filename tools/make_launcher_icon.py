#!/usr/bin/env python3
"""Generates the launcher icon from the app's own design tokens.

No image library is available here and the icon is simple geometry, so the
raster is drawn directly and encoded as PNG with `zlib`. Regenerating is
therefore reproducible on any machine with a plain Python install.

The mark: a ball on the app's navy, with two coral seams. Drawn from the
palette in `lib/core/design_system/tokens.dart` so the icon and the app cannot
drift apart. Original artwork — no team, league or broadcaster asset is used.

    python tools/make_launcher_icon.py
"""

from __future__ import annotations

import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# WbColors, kept in sync with tokens.dart.
NAVY = (0x14, 0x21, 0x3D)
CANVAS = (0xF7, 0xF5, 0xF0)
CORAL = (0xF0, 0x5D, 0x5E)

# Legacy launcher densities. Adaptive icons (API 26+) use the vector below.
LEGACY = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

SS = 4  # supersampling factor, for edges that do not look chewed


def _seam_distance(x: float, y: float, cx: float, cy: float, r: float) -> float:
    """Distance from a point to a circle's outline."""
    return abs(math.hypot(x - cx, y - cy) - r)


def _sample(x: float, y: float, size: float, full_bleed: bool) -> tuple:
    """Colour of one sample point, in device-independent 0..size space."""
    cx = cy = size / 2
    ball_r = size * (0.30 if full_bleed else 0.34)

    dx, dy = x - cx, y - cy
    dist = math.hypot(dx, dy)

    if dist > ball_r:
        # Outside the ball: background, or nothing for the adaptive foreground.
        return NAVY + (255,) if full_bleed else (0, 0, 0, 0)

    # Two seams, one down each side, bowing gently toward the centre — the
    # shape a baseball actually has.
    #
    # Each seam is the part of a circle that falls inside the ball. Centring
    # that circle *outside* the ball at 1.10r with a radius of 0.66r puts its
    # apex at 0.44r from the middle and its ends at roughly (0.81r, ±0.58r),
    # so the seam runs top-to-bottom near one edge.
    #
    # Two earlier attempts got this wrong in opposite ways: a radius larger
    # than the offset (1.42 / 1.30) swept both arcs through the middle and drew
    # an X, and widening it (1.55 / 1.10) made the arcs meet at the poles and
    # read as a lens. The radius must be *smaller* than the offset.
    offset = ball_r * 1.10
    seam_r = ball_r * 0.66
    width = ball_r * 0.075

    near_seam = min(
        _seam_distance(x, y, cx - offset, cy, seam_r),
        _seam_distance(x, y, cx + offset, cy, seam_r),
    )
    if near_seam <= width:
        return CORAL + (255,)
    return CANVAS + (255,)


def render(size: int, full_bleed: bool) -> bytes:
    """Renders one icon as raw RGBA rows."""
    rows = []
    step = 1.0 / SS
    for py in range(size):
        row = bytearray()
        for px in range(size):
            r = g = b = a = 0
            for sy in range(SS):
                for sx in range(SS):
                    cr, cg, cb, ca = _sample(
                        px + (sx + 0.5) * step,
                        py + (sy + 0.5) * step,
                        size,
                        full_bleed,
                    )
                    r += cr * ca
                    g += cg * ca
                    b += cb * ca
                    a += ca
            n = SS * SS
            if a == 0:
                row += bytes((0, 0, 0, 0))
            else:
                row += bytes((round(r / a), round(g / a), round(b / a), round(a / n)))
        rows.append(bytes(row))
    return b"".join(b"\x00" + r for r in rows)


def write_png(path: str, size: int, raw: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def main() -> None:
    for folder, size in LEGACY.items():
        raw = render(size, full_bleed=True)
        write_png(os.path.join(RES, folder, "ic_launcher.png"), size, raw)
        print(f"{folder}/ic_launcher.png  {size}x{size}")

    # Adaptive foreground: the mark alone, inside the 66/108 safe zone. Android
    # crops adaptive icons to whatever shape the launcher uses, so anything
    # outside that zone can be cut off.
    for folder, size in LEGACY.items():
        adaptive = round(size * 108 / 48)
        raw = render(adaptive, full_bleed=False)
        write_png(
            os.path.join(RES, folder, "ic_launcher_foreground.png"), adaptive, raw
        )
    print("ic_launcher_foreground.png  (adaptive, 108dp)")


if __name__ == "__main__":
    main()
