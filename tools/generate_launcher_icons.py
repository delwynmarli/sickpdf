"""Generate legacy (pre-Android 12) launcher PNGs for sickPDF.

Pure standard library: no Pillow/ImageMagick required. Rasterizes the same
document mark used by the adaptive icon vector so legacy devices and the
adaptive icon stay visually consistent.

Run from the project root:

    python tools/generate_launcher_icons.py

It overwrites android/app/src/main/res/mipmap-*/ic_launcher.png.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RES = PROJECT_ROOT / "android" / "app" / "src" / "main" / "res"

# Brand palette (must match lib/theme/app_theme.dart and the vector drawables).
CHARCOAL = (0x20, 0x23, 0x21)
TEAL = (0x14, 0x7D, 0x73)
WHITE = (0xFF, 0xFF, 0xFF)
FOLD = (0xC8, 0xCE, 0xC8)

# Density buckets -> icon size in pixels (mdpi=48dp baseline).
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def in_rounded_square(u, v, inset, radius):
    x0 = inset
    y0 = inset
    x1 = 1.0 - inset
    y1 = 1.0 - inset
    cx = min(max(u, x0 + radius), x1 - radius)
    cy = min(max(v, y0 + radius), y1 - radius)
    dx = u - cx
    dy = v - cy
    return (dx * dx + dy * dy) <= radius * radius


def sample(u, v):
    """Color for normalized point (u, v) in [0, 1]; returns (r, g, b, a)."""
    if not in_rounded_square(u, v, 0.06, 0.18):
        return (0, 0, 0, 0)

    # Document sheet.
    x0, y0, x1, y1 = 0.30, 0.24, 0.70, 0.78
    if not (x0 <= u <= x1 and y0 <= v <= y1):
        return (*TEAL, 255)

    fold_start = x1 - 0.16
    # Top-right folded corner triangle.
    if u >= fold_start and v <= y0 + 0.16 and (u - fold_start) >= (v - y0):
        return (*FOLD, 255)

    # Charcoal content lines on white.
    for ly in (0.46, 0.55):
        if 0.35 <= u <= 0.65 and ly <= v <= ly + 0.045:
            return (*CHARCOAL, 255)
    # Teal accent line.
    if 0.35 <= u <= 0.56 and 0.64 <= v <= 0.685:
        return (*TEAL, 255)
    return (*WHITE, 255)


def render(size, ss=4):
    rows = []
    n = ss * ss
    for y in range(size):
        row = bytearray()
        for x in range(size):
            r = g = b = a = 0
            for sy in range(ss):
                for sx in range(ss):
                    u = (x + (sx + 0.5) / ss) / size
                    v = (y + (sy + 0.5) / ss) / size
                    pr, pg, pb, pa = sample(u, v)
                    r += pr
                    g += pg
                    b += pb
                    a += pa
            row += bytes((r // n, g // n, b // n, a // n))
        rows.append(bytes(row))
    return rows


def write_png(path, rows, size):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def main():
    for folder, size in SIZES.items():
        target = RES / folder / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        write_png(target, render(size), size)
        print(f"wrote {target} ({size}x{size})")


if __name__ == "__main__":
    main()
